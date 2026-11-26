extends RefCounted
## As fichas: liga a busca, a ficha e os calendários ao Registry (cada sinal do painel vira uma chamada ao núcleo, e o que o núcleo
## devolve volta para o painel). Não tem regra de mundo (quem valida e grava é o Registry; quem converte datas é o local_calendar.gd).
## Segue o relógio: Main chama set_time com a data mostrada e tick a cada quadro.
## Os outros controladores (scripts/app/) usam o hub como contexto: o banco, a ficha aberta (current, open, reload, refresh_sheet),
## a data mostrada e o mapa de presenças. O território se registra em territories.
## Quem o cria precisa guardar uma referência (os sinais dos painéis só guardam funções deste objeto).
##
## Quando o C# lança uma exceção, o GDScript recebe null: por isso os resultados que viram id passam por _id() e a ficha
## que não existe mais é fechada, em vez de quebrar a interface.

signal sheet_loaded(sheet: Dictionary, geo: Dictionary)  # a ficha do selecionado foi (re)lida: o alto da tela acompanha
signal selection_cleared                                   # não há mais cadastro selecionado

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Calendar = preload("res://scripts/world/calendar.gd")
const LocalCalendar = preload("res://scripts/world/local_calendar.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")

const REBUILD_MS := 500  # a ficha não é relida mais que 2x por segundo enquanto o relógio anda
const PLACE_CHOICES := 50  # lugares nos menus da ficha; o resto se acha pela busca de lugar
const ALWAYS := -9223372036854775807 - 1
const FOREVER := 9223372036854775807

## Instante em que as fichas são lidas: a data mostrada pelo relógio (set_time). Sem relógio (testes dos painéis sozinhos),
## é "o que não tem fim": tudo o que não tem prazo vale e nenhuma data é escrita.
var shown_t := 9223372036854775806
var has_clock := false
var usable := false        # o banco abriu (uma versão futura ou um caminho inválido o recusam)

var registry
var search
var sheet
var calendars  # o painel de calendários (pode faltar)
var map                    # a camada de lugares do globo (PlaceLayer), ligada por bind_map
var presence_panel         # camadas e escopo do mapa
var focus_map := Callable()  # func(direção, zoom): leva a câmera a um ponto
var fixed_dir := Vector3.ZERO  # o ponto fixado no globo (onde "Criar lugar aqui" cria)
var territories = null     # o editor territorial (TerritoryEditor), se ligado
var _current := 0
var _pending := false      # o tempo andou e a ficha ainda não foi relida
var _last_rebuild_ms := 0
var _sheet_hash := 0       # o que a ficha aberta mostra: só é refeita se isto mudar
var _search_key := 0       # o que a lista de busca mostra
var _outline_selected := 0
var _outline_key := 0      # o que a árvore do Índice mostra
var _map_key := -1         # o que o globo desenha
var _defs := {}            # id do calendário -> definição (as definições não mudam depois de criadas)
var _delete_target := 0    # o que a confirmação de excluir vai apagar (0 = o aberto)


## db_path: arquivo do banco ("user://..." é traduzido) ou ":memory:" nos testes.
func setup(db_path: String, search_panel, sheet_panel, calendar_panel = null) -> void:
	registry = load("res://scripts/world/Registry.cs").new()
	registry.Open(db_path if db_path == ":memory:" else ProjectSettings.globalize_path(db_path))
	usable = registry.IsOpen()
	if not usable:
		push_error("O banco dos cadastros não abriu (%s): veja o log acima. Os painéis de cadastro ficam inativos." % db_path)
		return
	search = search_panel
	sheet = sheet_panel
	calendars = calendar_panel
	UiKit.set_types(registry.EntityTypes())
	UiKit.set_layers(registry.MapLayers())
	search.refresh_kinds()
	search.query_changed.connect(func(_t: String, _k: String) -> void: refresh_search())
	search.entity_chosen.connect(choose)
	search.create_requested.connect(_on_create)
	search.society_requested.connect(_on_society)
	# O que se edita na ficha vai para a entidade da ficha em que foi digitado (o sinal leva o id), mesmo que a ficha já tenha trocado.
	sheet.name_changed.connect(func(id: int, t: String) -> void:
		registry.Correct(id, t)
		refresh_search())
	sheet.summary_changed.connect(func(id: int, t: String) -> void: registry.SetSummary(id, t))
	sheet.field_edited.connect(_on_field)
	sheet.alias_added.connect(func(role: String, n: String) -> void:
		registry.AddName(_current, n, role, 0)
		_reload())
	sheet.tag_added.connect(func(t: String) -> void:
		registry.AddTag(_current, t)
		_reload())
	sheet.tag_removed.connect(func(t: String) -> void:
		registry.RemoveTag(_current, t)
		_reload())
	sheet.link_added.connect(func(type: String, other: int) -> void:
		registry.Link(_current, other, type)
		_reload())
	sheet.link_removed.connect(func(id: int) -> void:
		registry.DeleteLink(id)
		_reload())
	sheet.link_search.connect(_on_link_search)
	sheet.lookup = func(text: String, kind: String) -> Array:
		var found = registry.Search(text, kind, "", 0, shown_t)
		return found if found != null else []
	sheet.hierarchy_set.connect(set_parent)
	sheet.division_named.connect(func(id: int, division_name: String) -> void:
		registry.SetDivisionName(id, division_name)
		_reload())
	sheet.level_named.connect(func(country: int, level: int, level_name: String) -> void:
		registry.SetLevelName(country, level, level_name)
		_reload())
	sheet.open_entity.connect(open)
	sheet.duplicate_requested.connect(func(copy_links: bool) -> void:
		open(_id(registry.Duplicate(_current, copy_links, ""))))
	sheet.delete_requested.connect(func() -> void:
		_delete_target = _current
		sheet.confirm_delete(registry.Name(_current), registry.AffectedLinks(_current)))
	sheet.division_detail = _division_detail
	sheet.division_total_set.connect(_set_division_total)
	sheet.division_delete_requested.connect(func(id: int) -> void:
		_delete_target = id
		sheet.confirm_delete(registry.Name(id), registry.AffectedLinks(id)))
	sheet.division_view_requested.connect(_view_division)
	sheet.division_back_requested.connect(show_division)
	sheet.delete_confirmed.connect(_on_delete)
	sheet.calendar_use_added.connect(func(calendar_id: int, purpose: String) -> void:
		registry.UseCalendar(_current, calendar_id, purpose, 0)
		_reload())
	sheet.calendar_use_removed.connect(func(use_id: int) -> void:
		registry.DeleteCalendarUse(use_id)
		_reload())
	search.calendars_requested.connect(func() -> void:
		if calendars != null:
			calendars.open(_calendar_rows()))
	if calendars != null:
		calendars.create_requested.connect(_on_calendar_create)
	sheet.presence_added.connect(func(place_id: int, role: String) -> void:
		registry.AddPresence(_current, place_id, role, "media")
		_reload())
	sheet.presence_removed.connect(func(id: int) -> void:
		registry.DeletePresence(id)
		_reload())
	sheet.place_created.connect(_on_place_created)
	sheet.place_search.connect(_on_place_search)
	sheet.estimate_added.connect(_on_estimate_added)
	sheet.city_created.connect(func(city_name: String, count: String) -> void:
		var n := parse_number(count)
		if is_nan(n) or n < 0.0:
			sheet.show_geo_message("Informe o número de habitantes (0 ou mais).")
			return
		if fixed_dir == Vector3.ZERO:
			return
		var ll := EvronGeo.lat_lon(fixed_dir)
		var place := _id(registry.AddPlace(city_name, "assentamento", ll.x, ll.y, 0.0, ""))
		if place != 0:
			registry.AddPresence(_current, place, "presenca", "media")
			registry.AddEstimate(_current, place, shown_t, n, n, "alta", "")
		_reload())
	sheet.total_set.connect(func(text: String) -> void:
		var v := parse_number(text)
		if is_nan(v) or v < 0.0:
			sheet.show_geo_message("Informe o número de habitantes (0 ou mais).")
			return
		registry.SetTotal(_current, shown_t, roundf(v))
		_reload())
	sheet.total_removed.connect(func() -> void:
		var p: Dictionary = registry.PopulationOf(_current, shown_t)
		if p.has_total:
			registry.DeleteTotal(_current, int(p.t))
			_reload())
	sheet.estimate_removed.connect(func(id: int) -> void:
		registry.DeleteEstimate(id)
		_reload())
	sheet.place_focus_requested.connect(focus_place)
	refresh_search()


## Liga o mapa: a camada de lugares do globo, o painel de camadas e como levar a câmera a um ponto.
func bind_map(place_layer, panel, focus: Callable) -> void:
	map = place_layer
	presence_panel = panel
	focus_map = focus
	panel.refresh_layers()
	panel.changed.connect(refresh_map)
	refresh_map()



func close() -> void:
	if registry != null and usable:
		if territories != null:
			territories.flush()
		registry.Close()
		usable = false  # fechar duas vezes (trocar de mundo e depois sair da cena) não grava num banco fechado


func current() -> int:
	return _current


## Relê a ficha aberta agora (depois de uma mudança que ela mostra).
func reload() -> void:
	_reload()


## Relê a ficha aberta mesmo que pareça igual (uma regra, uma cor ou um tipo mudou o que ela mostra).
func refresh_sheet() -> void:
	if _current != 0:
		_sheet_hash = 0
		_reload()


## Tira a seleção: fecha a janela e limpa o destaque do mapa.
func deselect() -> void:
	if _current == 0:
		return
	_current = 0
	_sheet_hash = 0
	sheet.hide_sheet()
	selection_cleared.emit()
	refresh_search()
	refresh_map()
	if territories != null:
		territories.refresh_selection()


## Muitos cadastros mudaram de uma vez (Opções → Cadastros): esquece o que estava guardado e relê a lista e o mapa.
func forget_cached() -> void:
	_composition_cache.clear()
	_defs.clear()
	_sheet_hash = 0
	_search_key = 0
	_outline_key = 0
	refresh_search()
	redraw_map()


## Redesenha as presenças do mapa mesmo que pareçam iguais (as camadas mudaram).
func redraw_map() -> void:
	_map_key = 0
	refresh_map()


func is_painting() -> bool:
	return territories != null and territories.painting_territory


func open(id: int) -> void:
	if id == 0 or not usable:
		return
	if territories != null:
		territories.on_open(id)
	_current = id
	sheet.keep_closed = false  # abrir um cadastro mostra a janela, mesmo que ela tenha sido fechada
	_reload()


## Escolher um cadastro numa lista ou no mapa: uma subdivisão abre dentro da lista do país dela; o resto abre a própria ficha.
func choose(id: int) -> void:
	if id != 0 and usable and String(registry.Kind(id)) in ["provincia", "municipio"]:
		show_division(id)
	else:
		open(id)


## Abre o país da subdivisão, na página Território, com a linha dela aberta. Sem país, abre a ficha dela.
func show_division(id: int) -> void:
	var country: int = registry.CountryOf(id)
	if country == 0:
		open(id)
		return
	sheet.queue_division(id)
	open(country)
	sheet.show_page("Território")


## O que a linha aberta mostra de uma subdivisão.
func _division_detail(id: int) -> Dictionary:
	var s = registry.Sheet(id, shown_t)
	if s == null:
		return {}
	var info: Dictionary = territories.sheet_info(s) if territories != null else {}
	return {"name": s.name, "label": s.label, "area_km2": float(info.get("area_km2", 0.0)), "color": int(info.get("color", registry.EntityColor(id))),
		"ok": bool(info.get("ok", false)), "has_total": s.population.has_total, "total": s.population.total if s.population.has_total else 0.0}


func _set_division_total(id: int, text: String) -> void:
	if text == "":
		var p: Dictionary = registry.PopulationOf(id, shown_t)
		if p.has_total:
			registry.DeleteTotal(id, int(p.t))
	else:
		var v := parse_number(text)
		if is_nan(v) or v < 0.0:
			sheet.show_division_message("Informe o número de habitantes (0 ou mais).")
			return
		registry.SetTotal(id, shown_t, roundf(v))
	_reload()


func _view_division(id: int) -> void:
	var layer = territories.layer(String(registry.Kind(id))) if territories != null else null
	if layer == null or not focus_map.is_valid():
		return
	var centers: Dictionary = layer.Centroids()
	if centers.has(id):
		var radius := sqrt(float(centers[id][1]) / PI)
		focus_map.call(centers[id][0], 1.0 + 5.0 * maxf(radius, 150.0) / EvronGeo.RADIUS_KM)  # com folga: a janela cobre a esquerda


## Liga uma província a um país ou um município a uma província (parent = 0 tira do de cima). Cada cadastro tem um só de cima: o vínculo anterior sai.
## O território que já foi pintado não muda.
func set_parent(child: int, parent: int) -> void:
	var kind := String(registry.Kind(child))
	if not kind in ["provincia", "municipio"]:
		return
	if parent > 0:
		var parent_kind := String(registry.Kind(parent))
		if not parent_kind in (["pais"] if kind == "provincia" else ["pais", "provincia"]):  # o município pode ficar direto no país: a província é opcional
			return
	var code := kind + "_de"
	var s = registry.Sheet(child, shown_t)
	if s != null:
		for l in s.links:
			if l.outgoing and l.type == code:
				registry.DeleteLink(int(l.id))
	if parent > 0:
		registry.Link(child, parent, code)
	if territories != null:
		territories.refresh_palette()  # a cor da província segue a do país
	_reload()


const PRESENCE := {"cultura": "cultura_presente", "etnia": "etnia_presente", "raca": "raca_presente", "religiao": "religiao_presente", "idioma": "idioma_falado"}
var _composition_cache := {}   # "id:versões" -> {categoria: [{id, name, share}]}


## O "pelo mapa" da aba Composição: para país, província ou município com território, quanto da área dele cada cultura, etnia, raça, religião e idioma
## pintados cobrem (cada categoria é uma camada). Guardado por versão das camadas: a ficha é refeita a cada edição e a conta varre o mapa.
func _map_composition(s: Dictionary) -> Dictionary:
	var out := {}
	if territories == null or not String(s.kind) in ["pais", "provincia", "municipio"]:
		return out
	var base = territories.layer(String(s.kind))
	if base == null or int(s.id) > 65535 or base.AreaKm2(int(s.id)) <= 0.0:
		return out
	var key := "%d:%d" % [int(s.id), base.Version]
	var layers := {}
	for category in PRESENCE:
		var layer = territories.layer(category)
		if layer != null:
			layers[category] = layer
			key += ":%d" % layer.Version
	if _composition_cache.has(key):
		return _composition_cache[key]
	var area: float = base.AreaKm2(int(s.id))
	for category in layers:
		var over: Dictionary = base.OverlapKm2(layers[category], int(s.id))
		var rows: Array = []
		for o in over:
			var share: float = float(over[o]) / area
			if int(o) != 0 and share >= 0.01:
				rows.append({"id": int(o), "name": registry.Name(int(o)), "share": share})
		rows.sort_custom(func(a, b) -> bool: return a.share > b.share)
		out[category] = rows
	if _composition_cache.size() > 64:
		_composition_cache.clear()
	_composition_cache[key] = out
	return out


## A cadeia de cima de um cadastro: {"parent": {id, name, kind}, "country": {id, name}} (vazios quando não há). O país de um município que está numa província é o da província.
func _chain_of(id: int) -> Dictionary:
	var out := {"parent": {}, "country": {}}
	var parent: int = registry.TerritoryParent(id)
	if parent == 0:
		return out
	out.parent = {"id": parent, "name": registry.Name(parent), "kind": registry.Kind(parent)}
	var top: int = parent if String(registry.Kind(parent)) == "pais" else int(registry.TerritoryParent(parent))
	if top != 0 and String(registry.Kind(top)) == "pais":
		out.country = {"id": top, "name": registry.Name(top)}
	return out


## A lista de busca só é refeita se o resultado mudou (refazer a lista a cada relógio perderia a seleção e a rolagem).
func refresh_search() -> void:
	if not usable:
		return
	var results = registry.Search(search.query(), search.kind_filter(), "", 0, shown_t)
	if results == null:
		return
	var key: int = [results, _current].hash()
	if key != _search_key:
		_search_key = key
		search.show_results(results, _current)
	_refresh_hierarchy()


## A árvore dos Registros: todos os cadastros, sem o limite da busca; cada divisão sob o cadastro de nível acima (parent).
func _hierarchy_rows() -> Array:
	var rows = registry.Outline(shown_t)
	return rows if rows != null else []


## As divisões de um país ou de uma subdivisão, para a ficha: [{id, name, kind, label, differs, children: [...]}] (as do 1º nível com as
## de dentro; as do 2º nível ligadas direto ao país, sem filhos).
func _division_of(id: int, kind: String) -> Array:
	if not kind in ["pais", "provincia"]:
		return []
	var children := {}  # parent -> as divisões dele, na ordem de nome
	for r in _hierarchy_rows():
		if int(r.parent) != 0:
			children.get_or_add(int(r.parent), []).append(r)
	var out: Array = []
	for level in ["provincia", "municipio"]:
		for r in children.get(id, []):
			if r.kind == level:
				var item: Dictionary = r.duplicate()
				item["color"] = int(registry.EntityColor(int(r.id)))
				var inside: Array = children.get(int(r.id), []) if level == "provincia" else []
				item["children"] = inside.map(func(c): return c.merged({"color": int(registry.EntityColor(int(c.id)))}))
				out.append(item)
	return out


func _refresh_hierarchy() -> void:
	var rows := _hierarchy_rows()
	var key: int = rows.hash()  # sem o país aberto: trocar de ficha só move a seleção, a árvore não é refeita
	if key != _outline_key:
		_outline_key = key
		search.show_hierarchy(rows, _current)
	elif _current != _outline_selected:
		search.select_in_hierarchy(_current)
	_outline_selected = _current


## O relógio do mundo mostra a data t (presente ou consulta). Atualiza na hora as datas escritas na ficha; a ficha em si
## (nomes, vínculos e usos válidos em t) é relida por tick() só se algo dela mudou.
func set_time(t: int) -> void:
	if not usable or (has_clock and t == shown_t):
		return
	has_clock = true
	shown_t = t
	_pending = true
	if _current != 0 and sheet.visible:
		var texts := {}
		for u in registry.CalendarsOf(_current, shown_t):
			texts[int(u.use_id)] = _local_text(int(u.calendar_id))
		sheet.show_calendar_dates(_universal_text(), texts)


## O ponto fixado no globo mudou (ZERO = nenhum): a ficha aberta passa a poder criar um lugar nele.
func set_fixed_point(dir: Vector3) -> void:
	fixed_dir = dir
	if usable:
		sheet.show_fixed_point(_fixed_text(), dir != Vector3.ZERO)


## O clique na camada política seleciona o dono do pixel. Onde ela não tem um dono visível, consulta as presenças do mapa.
func pick(dir: Vector3, tolerance_km: float) -> int:
	if not usable or is_painting() or map == null or dir == Vector3.ZERO:
		return 0
	if territories != null and "politica" in presence_panel.layers():
		var owner: int = territories.owner_at(dir)
		if owner != 0:
			var division: int = territories.division_at(dir, owner)
			if division != 0:
				if sheet.open_division != division or not sheet.visible:
					show_division(division)
			elif owner != _current or not sheet.visible:
				open(owner)
			return 1
	if not presence_panel.all_entities() and _current == 0:
		return 0
	var ll := EvronGeo.lat_lon(dir)
	var only := 0 if presence_panel.all_entities() else _current
	var hits = registry.EntitiesAt(ll.x, ll.y, tolerance_km, presence_panel.layers(), only, shown_t)
	var found := {}  # entidade -> o primeiro resultado (o mais específico)
	for h in (hits if hits != null else []):
		if not found.has(int(h.entity_id)):
			found[int(h.entity_id)] = h
	if found.size() == 1:
		var only_id: int = found.keys()[0]
		if only_id != _current:
			open(only_id)
	elif found.size() > 1:
		var rows: Array = []
		for id in found:
			var h: Dictionary = found[id]
			rows.append({"id": id, "kind": h.kind, "name": h.entity, "match": "%s · %s" % [h.place, UiKit.role_label(h.role)]})
		search.show()  # os vários resultados do clique precisam aparecer para o usuário escolher
		search.show_results(rows, _current)
		_search_key = 0  # a lista agora não é a da busca: a próxima atualização a refaz
	return found.size()


## Leva a câmera ao lugar, a uma distância proporcional ao tamanho da área.
func focus_place(place_id: int) -> void:
	if not usable or not focus_map.is_valid():
		return
	var p = registry.Place(place_id)
	if p != null:
		focus_map.call(EvronGeo.dir(p.lat, p.lon), 1.0 + 2.5 * maxf(p.radius_km, 150.0) / EvronGeo.RADIUS_KM)


## Redesenha as presenças no globo se mudaram: as camadas marcadas (nenhuma marcada = nada), da ficha aberta ou de todas, na data mostrada.
func refresh_map() -> void:
	if not usable or map == null:
		return
	var all: bool = presence_panel.all_entities()
	var items = [] if not all and _current == 0 else registry.MapItems(presence_panel.layers(), 0 if all else _current, shown_t)
	if items == null:
		return
	var key: int = items.hash()
	if key != _map_key:
		_map_key = key
		map.show_items(items)



## A cada quadro: se o tempo andou (e faz ao menos REBUILD_MS desde a última leitura), relê a ficha só se algo dela mudou, e nunca com o usuário
## digitando ou com um menu aberto. A busca e o mapa só se redesenham se o resultado mudou.
func tick() -> void:
	if territories != null:
		territories.save_if_due()
	if not usable or not _pending or Time.get_ticks_msec() - _last_rebuild_ms < REBUILD_MS or sheet.is_editing():
		return
	_pending = false
	_last_rebuild_ms = Time.get_ticks_msec()
	if _current != 0:
		var s = registry.Sheet(_current, shown_t)
		if s != null and s.hash() != _sheet_hash:
			_reload()
			return
	refresh_search()
	refresh_map()


## Aceita o formato que a ficha mostra (pt-BR): "1.200" e "1.200,5" têm ponto de milhar; "1,5" e "1.5" são decimais. NAN se não for número.
static func parse_number(text: String) -> float:
	var t := text.strip_edges()
	if t == "":
		return NAN
	if "," in t:
		t = t.replace(".", "").replace(",", ".")
	elif RegEx.create_from_string("^\\d{1,3}(\\.\\d{3})+$").search(t) != null:
		t = t.replace(".", "")
	return float(t) if t.is_valid_float() else NAN


# --- tratadores ---------------------------------------------------------------------------------------------------

## O C# devolve null quando lança exceção; isto vira 0 ("não deu").
static func _id(v) -> int:
	return 0 if v == null else int(v)


func _on_create(kind: String, name: String) -> void:
	var text := name.strip_edges()
	open(_id(registry.Create(kind, text if text != "" else "Sem nome (%s)" % UiKit.kind_label(kind))))


func _on_society(name: String) -> void:
	var text := name.strip_edges()
	var ids = registry.CreateSociety(text if text != "" else "Sem nome", PackedStringArray(["pais", "cultura", "etnia"]))
	if ids != null and not ids.is_empty():
		open(ids[0])  # a ficha do país; as outras abrem pelas relações


## id: a entidade da ficha em que o usuário digitou (pode já não ser a aberta, se a ficha trocou enquanto o campo tinha o foco).
func _on_field(id: int, code: String, state: String, value: String) -> void:
	registry.SetField(id, code, state, value)
	if id == _current:
		var now = registry.GetField(id, code)
		if now != null:
			sheet.update_field(code, now.state, now.value)  # mostra o que ficou (corrige o que foi recusado)


func _on_link_search(text: String, dst_kind: String) -> void:
	sheet.show_link_candidates(registry.Search(text, dst_kind, "", 0, shown_t))


func _on_delete() -> void:
	var deleted := _delete_target if _delete_target != 0 else _current
	_delete_target = 0
	var deleted_layer = territories.before_delete(deleted) if territories != null else null
	if registry.Delete(deleted) == null:
		return
	if territories != null:
		territories.after_delete(deleted, deleted_layer)
	if deleted != _current:  # excluída pela lista do país: o país continua aberto
		sheet.open_division = 0
		_reload()
		return
	_current = 0
	_sheet_hash = 0
	sheet.hide_sheet()
	selection_cleared.emit()
	refresh_search()
	refresh_map()
	if territories != null:
		territories.refresh_palette()


## Cria um lugar no ponto fixado no globo e já o liga à ficha aberta.
func _on_place_created(place_name: String, kind: String, radius_km: float, role: String) -> void:
	if fixed_dir == Vector3.ZERO:
		return
	var ll := EvronGeo.lat_lon(fixed_dir)
	var id := _id(registry.AddPlace(place_name, kind, ll.x, ll.y, radius_km, ""))
	if id != 0:
		registry.AddPresence(_current, id, role, "media")
	_reload()


## Estimativa na data mostrada: com nível (sem número) ou com faixa "de ... até ..." (só o "de" = valor exato). Os números seguem o formato da ficha.
func _on_estimate_added(place_id: int, low: String, high: String, level: String, certainty: String) -> void:
	if level != "":
		registry.AddEstimateLevel(_current, place_id, shown_t, level, certainty, "")
		_reload()
		return
	var lo := parse_number(low)
	var hi := parse_number(high) if high != "" else lo
	if is_nan(lo) or is_nan(hi):
		sheet.show_geo_message("Informe um número (de ... até ...) ou escolha só um nível.")
	elif lo < 0.0 or hi < lo:
		sheet.show_geo_message("A faixa precisa ser de 0 para cima, e o \"até\" não pode ser menor que o \"de\".")
	else:
		registry.AddEstimate(_current, place_id, shown_t, lo, hi, certainty, "")
		_reload()


## data: o que o CalendarPanel manda (name, era_name, era_abbr, year, month, day, first, direction, day_hour, months).
## O calendário e a primeira era valem para sempre; o marco é a meia-noite LOCAL da data escolhida (a hora em que o dia vira).
## É uma operação só no Registry: se a era for inválida, o calendário também não fica.
func _on_calendar_create(data: Dictionary) -> void:
	var marker := Calendar.to_seconds(data.year, data.month, data.day)
	if marker == Calendar.INVALID:
		calendars.show_message("Essa data do marco não existe (o mês escolhido não tem esse dia).")
		return
	marker += int(data.day_hour) * Calendar.HOUR
	var id := _id(registry.CreateCalendar(data.name, "", data.months, int(data.day_hour) * Calendar.HOUR, "exata", "",
		data.era_name, data.era_abbr, marker, data.direction, data.first))
	if id == 0:
		calendars.show_message("Não consegui criar o calendário (veja o log).")
		return
	calendars.clear_form()
	calendars.show_message("Calendário criado.")
	calendars.show_calendars(_calendar_rows())
	if _current != 0:
		_reload()  # a ficha aberta passa a oferecer o calendário novo


## Os lugares dos menus da ficha para o texto buscado: os da própria ficha primeiro (só sem texto), até PLACE_CHOICES; `more` avisa que há mais.
func _on_place_search(text: String) -> void:
	var c := _place_choices(text)
	sheet.show_place_candidates(c.items, c.more)


func _place_choices(text: String) -> Dictionary:
	var found = registry.Places(text)
	if found == null:
		return {"items": [], "more": false}
	var ordered: Array = []
	if text == "" and _current != 0:
		for p in registry.PresencesOf(_current, shown_t):
			ordered.append({"id": int(p.place_id), "name": p.place})
	for p in found:
		ordered.append({"id": int(p.id), "name": p.name})
	var items: Array = []
	var seen := {}
	for it in ordered:
		if not seen.has(it.id):
			seen[it.id] = true
			items.append(it)
	return {"items": items.slice(0, PLACE_CHOICES), "more": items.size() > PLACE_CHOICES or found.size() >= 200}


## Relê a ficha atual e refaz a lista de busca. Uma ficha que não existe mais (apagada por outro caminho) é fechada.
func _reload() -> void:
	_pending = false
	_last_rebuild_ms = Time.get_ticks_msec()
	var s = registry.Sheet(_current, shown_t)
	if s == null:
		_current = 0
		_sheet_hash = 0
		sheet.hide_sheet()
		selection_cleared.emit()
	else:
		_sheet_hash = s.hash()
		var geo := _geo_info(s)
		sheet.show_sheet(s, registry.LinkTypesFor(s.kind), _calendar_info(s), geo)
		sheet_loaded.emit(s, geo)
	refresh_search()
	refresh_map()
	if territories != null:
		territories.on_sheet_reloaded()


# --- calendários --------------------------------------------------------------------------------------------------

## O que a seção de calendários da ficha mostra: a data universal, cada uso com a data local e os calendários que dá para escolher.
func _calendar_info(s: Dictionary) -> Dictionary:
	var uses: Array = []
	for u in s.calendars:
		uses.append({"use_id": u.use_id, "name": u.name, "purpose": u.purpose, "priority": u.priority, "text": _local_text(int(u.calendar_id))})
	var choices: Array = []
	for c in registry.Calendars():
		choices.append({"id": c.id, "name": c.name})
	return {"universal": _universal_text(), "uses": uses, "choices": choices}


## O que as seções de mapa e população da ficha mostram além da própria ficha: os lugares que dá para escolher, o ponto fixado e as datas escritas.
func _geo_info(s: Dictionary) -> Dictionary:
	var c := _place_choices("")
	var dates_e := {}
	for e in s.estimates:
		dates_e[int(e.id)] = Calendar.format(int(e.t), false) if has_clock else ""
	var dates_d := {}
	for comp in s.compositions:
		dates_d[int(comp.id)] = Calendar.format(int(comp.t), false) if has_clock else ""
	var cities: Array = []
	var seen := {}
	for p in s.presences:
		if not seen.has(int(p.place_id)) and registry.Place(int(p.place_id)).kind == "assentamento":
			seen[int(p.place_id)] = true
			cities.append({"id": int(p.place_id), "name": p.place})
	for e in s.estimates:
		if not seen.has(int(e.place_id)):
			seen[int(e.place_id)] = true
			cities.append({"id": int(e.place_id), "name": e.place})
	var geo := {"cities": cities, "places": c.items, "places_more": c.more, "fixed_text": _fixed_text(), "has_fixed": fixed_dir != Vector3.ZERO, "dates_e": dates_e, "dates_d": dates_d,
			"chain": _chain_of(int(s.id)), "composition": _map_composition(s), "division": _division_of(int(s.id), String(s.kind)),
			"level_names": [registry.LevelName(int(s.id), 1), registry.LevelName(int(s.id), 2)] if s.kind == "pais" else [],
			"suggestions": Array(registry.DivisionSuggestions())}
	var territory_info: Dictionary = territories.sheet_info(s) if territories != null else {}
	if not territory_info.is_empty():
		geo["territory"] = territory_info
	return geo


func _fixed_text() -> String:
	if fixed_dir == Vector3.ZERO:
		return "Nenhum ponto fixado. Clique no globo."
	var ll := EvronGeo.lat_lon(fixed_dir)
	return ("Ponto fixado: lat %.2f° %s · lon %.2f° %s" % [absf(ll.x), "N" if ll.x >= 0.0 else "S", absf(ll.y), "L" if ll.y >= 0.0 else "O"]).replace(".", ",")


func _universal_text() -> String:
	return Calendar.format(shown_t) if has_clock else "sem relógio"


## A data local de shown_t no calendário (ou o motivo de não haver). Aproximada leva o aviso.
func _local_text(calendar_id: int) -> String:
	if not has_clock:
		return "sem relógio"
	var def := _def(calendar_id)
	var l := LocalCalendar.to_local(def, shown_t)
	var text := LocalCalendar.format(l)
	return text + " (aproximada)" if l.status == LocalCalendar.OK and l.reliability == "aproximada" else text


func _def(calendar_id: int) -> Dictionary:
	if not _defs.has(calendar_id):
		_defs[calendar_id] = registry.CalendarDef(calendar_id)
	return _defs[calendar_id]


func _calendar_rows() -> Array:
	var rows: Array = []
	for c in registry.Calendars():
		var def := _def(int(c.id))
		var era: String = def.eras[0].name if def.eras.size() > 0 else "sem era"
		var hoje := _local_text(int(c.id))
		rows.append({"name": c.name, "summary": "%s · hoje: %s" % [era, hoje]})
	return rows