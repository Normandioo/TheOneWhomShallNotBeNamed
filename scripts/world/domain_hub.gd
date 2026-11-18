extends RefCounted
## Liga os painéis de cadastro ao Registry: cada sinal do painel vira uma chamada ao núcleo, e o que o núcleo devolve volta
## para o painel. Não tem regra de mundo (quem valida e grava é o Registry; quem converte datas é o local_calendar.gd) e não
## conhece o globo. Segue o relógio: Main chama set_time com a data mostrada e tick a cada quadro.
## Quem o cria precisa guardar uma referência (os sinais dos painéis só guardam funções deste objeto).
##
## Quando o C# lança uma exceção, o GDScript recebe null: por isso os resultados que viram id passam por _id() e a ficha
## que não existe mais é fechada, em vez de quebrar a interface.

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
var draw_panel             # a barra do modo desenhar fronteira
var drawing := false       # no modo desenhar: o clique no globo marca um ponto do contorno
var _draw_pts: Array[Vector2] = []  # (lat, lon) de cada ponto marcado, na ordem
var _draw_entity := 0      # de quem é a fronteira
var _draw_name := ""
var _draw_role := "territorio"
var _draw_place := 0       # != 0: refazendo o contorno desse lugar
var _draw_message := ""
var _map_items: Array = [] # o que o globo desenha agora (de onde vêm os vértices que atraem o clique)
var _current := 0
var _pending := false      # o tempo andou e a ficha ainda não foi relida
var _last_rebuild_ms := 0
var _sheet_hash := 0       # o que a ficha aberta mostra: só é refeita se isto mudar
var _search_key := 0       # o que a lista de busca mostra
var _map_key := -1         # o que o globo desenha
var _defs := {}            # id do calendário -> definição (as definições não mudam depois de criadas)


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
	search.query_changed.connect(func(_t: String, _k: String) -> void: refresh_search())
	search.entity_chosen.connect(open)
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
	sheet.open_entity.connect(open)
	sheet.duplicate_requested.connect(func(copy_links: bool) -> void:
		open(_id(registry.Duplicate(_current, copy_links, ""))))
	sheet.delete_requested.connect(func() -> void:
		sheet.confirm_delete(registry.Name(_current), registry.AffectedLinks(_current)))
	sheet.delete_confirmed.connect(_on_delete)
	sheet.closed.connect(func() -> void: _current = 0)
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
	sheet.estimate_removed.connect(func(id: int) -> void:
		registry.DeleteEstimate(id)
		_reload())
	sheet.place_focus_requested.connect(focus_place)
	sheet.border_draw_requested.connect(func(n: String, role: String) -> void: start_border(n, role, 0))
	sheet.border_redraw_requested.connect(func(place_id: int, role: String) -> void: start_border("", role, place_id))
	refresh_search()


## Liga o mapa: a camada de lugares do globo, o painel de camadas e como levar a câmera a um ponto.
func bind_map(place_layer, panel, focus: Callable) -> void:
	map = place_layer
	presence_panel = panel
	focus_map = focus
	panel.changed.connect(refresh_map)
	refresh_map()


## Liga a barra do modo desenhar.
func bind_draw(panel) -> void:
	draw_panel = panel
	panel.undo_requested.connect(draw_undo)
	panel.finish_requested.connect(draw_finish)
	panel.cancel_requested.connect(draw_cancel)


func close() -> void:
	if registry != null:
		registry.Close()


func current() -> int:
	return _current


func open(id: int) -> void:
	if id == 0 or not usable:
		return
	if drawing:  # abrir outra ficha no meio do desenho o perderia: termina ou cancela antes
		_draw_message = "Conclua ou cancele o desenho antes de abrir outro cadastro."
		_refresh_draw()
		return
	_current = id
	_reload()


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


## Clique no mapa: as presenças visíveis (mesmas camadas e escopo do desenho) que cobrem o ponto, dentro do raio do lugar ou da tolerância
## (km). Uma só entidade abre a ficha dela (se já é a aberta, a ficha fica como está: refazê-la apagaria o que se digita nela); várias aparecem
## na lista de busca para escolher. Devolve quantas entidades foram achadas.
func pick(dir: Vector3, tolerance_km: float) -> int:
	if not usable or drawing or map == null or dir == Vector3.ZERO or (not presence_panel.all_entities() and _current == 0):
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
	_map_items = items
	var key: int = items.hash()
	if key != _map_key:
		_map_key = key
		map.show_items(items)


# --- desenhar fronteira ----------------------------------------------------------------------------------------------

## Entra no modo desenhar para a ficha aberta: o clique no globo passa a marcar os pontos do contorno (draw_click). place_id != 0 refaz o
## contorno desse lugar; senão, ao concluir, cria o lugar com o nome dado e liga a entidade a ele com a função (role).
func start_border(place_name: String, role: String, place_id: int = 0) -> void:
	if not usable or drawing or _current == 0:
		return
	if place_id == 0 and place_name.strip_edges() == "":
		sheet.show_border_message("Dê um nome à região antes de desenhar.")
		return
	drawing = true
	_draw_entity = _current
	_draw_name = place_name.strip_edges()
	_draw_role = role
	_draw_place = place_id
	_draw_pts.clear()
	_draw_message = "Clique no globo para marcar cada ponto; arraste para girar. Perto do vértice de outra fronteira o ponto cola nele."
	_refresh_draw()


## Um clique no globo no modo desenhar: marca um ponto. Se cai a menos de snap_km de um vértice de um contorno desenhado (o que está no mapa),
## cola nesse vértice, para que duas fronteiras vizinhas dividam a borda sem fresta.
func draw_click(dir: Vector3, snap_km: float) -> void:
	if not drawing or dir == Vector3.ZERO:
		return
	var ll := EvronGeo.lat_lon(dir)
	var pt := Vector2(ll.x, ll.y)
	var glued := false
	var best := snap_km
	for it in _map_items:
		var vs: PackedFloat64Array = it.vertices
		for i in vs.size() / 2:
			var d := EvronGeo.distance_km(dir, EvronGeo.dir(vs[2 * i], vs[2 * i + 1]))
			if d <= best:
				best = d
				pt = Vector2(vs[2 * i], vs[2 * i + 1])
				glued = true
	if not _draw_pts.is_empty() and _draw_pts[_draw_pts.size() - 1].is_equal_approx(pt):
		_draw_message = "Esse ponto já está marcado."
	else:
		_draw_pts.append(pt)
		_draw_message = "Ponto colado ao vértice de outra fronteira." if glued else "Continue marcando; com 3 pontos já dá para concluir."
	_refresh_draw()


func draw_undo() -> void:
	if drawing and not _draw_pts.is_empty():
		_draw_pts.pop_back()
		_draw_message = "Último ponto desfeito."
		_refresh_draw()


func draw_cancel() -> void:
	if drawing:
		_end_draw()


## Conclui: cria o lugar com o contorno e liga a entidade (ou troca o contorno do lugar que estava sendo refeito). Um contorno que não vale
## (cruza ele mesmo, grande demais, sem área) não é gravado e o desenho continua, para desfazer pontos.
func draw_finish() -> void:
	if not drawing:
		return
	if _draw_pts.size() < 3:
		_draw_message = "Marque ao menos 3 pontos."
		_refresh_draw()
		return
	var flat := PackedFloat64Array()
	for p in _draw_pts:
		flat.append_array([p.x, p.y])
	var done := false
	if _draw_place != 0:
		done = registry.SetPlaceVertices(_draw_place, flat) != null
	else:
		var pid := _id(registry.AddPolygonPlace(_draw_name, "regiao", flat, ""))
		if pid != 0:
			done = registry.AddPresence(_draw_entity, pid, _draw_role, "media") != null
	if not done:
		_draw_message = "Esse contorno não vale: ele cruza ele mesmo, é grande demais ou não tem área. Desfaça pontos ou cancele."
		_refresh_draw()
		return
	var entity := _draw_entity
	_end_draw()
	open(entity)


func _end_draw() -> void:
	drawing = false
	_draw_pts.clear()
	_draw_place = 0
	if map != null:
		map.show_draft([])
	if draw_panel != null:
		draw_panel.hide_panel()


func _refresh_draw() -> void:
	var dirs: Array = []
	for p in _draw_pts:
		dirs.append(EvronGeo.dir(p.x, p.y))
	if map != null:
		map.show_draft(dirs)
	if draw_panel != null:
		draw_panel.show_state("Desenhando fronteira: %s" % (_draw_name if _draw_name != "" else "novo contorno"), _draw_pts.size(), _draw_message)


## A cada quadro: se o tempo andou (e faz ao menos REBUILD_MS desde a última leitura), relê a ficha só se algo dela mudou, e nunca com o usuário
## digitando ou com um menu aberto. A busca e o mapa só se redesenham se o resultado mudou.
func tick() -> void:
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
	registry.Delete(_current)
	_current = 0
	_sheet_hash = 0
	sheet.hide_sheet()
	refresh_search()
	refresh_map()


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
	else:
		_sheet_hash = s.hash()
		sheet.show_sheet(s, registry.LinkTypesFor(s.kind), _calendar_info(s), _geo_info(s))
	refresh_search()
	refresh_map()


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
	return {"places": c.items, "places_more": c.more, "fixed_text": _fixed_text(), "has_fixed": fixed_dir != Vector3.ZERO, "dates_e": dates_e, "dates_d": dates_d}


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
