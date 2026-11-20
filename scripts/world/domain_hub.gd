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
const TerritoryBoundaryTool = preload("res://scripts/edit/territory_boundary_tool.gd")
const TerritoryEdit = preload("res://scripts/edit/TerritoryEdit.cs")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")

signal painting_changed(on: bool)      # entrou ou saiu do modo pintar território
signal palette_changed(entries: Array)  # as cores dos países mudaram ([{id, rgb}]): quem desenha atualiza a paleta

const REBUILD_MS := 500  # a ficha não é relida mais que 2x por segundo enquanto o relógio anda
const PLACE_CHOICES := 50  # lugares nos menus da ficha; o resto se acha pela busca de lugar
const SNAP_BAND_KM := 60.0  # "assentar no relevo": a fronteira vai até ~6 pixels do mapa (9,8 km cada) atrás de uma crista ou rio
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
var territory              # a camada territorial mostrada e editada (Territory, C#): o dono de cada pixel
var levels := {}           # nível ("pais", "provincia", "municipio") -> a camada dele: cada nível é independente
var territory_level := "pais"
signal territory_level_shown(level: String, layer)  # a camada mostrada no globo passou a ser outra
var commands               # a pilha de desfazer (a mesma do terreno)
var territory_panel        # a barra do modo pintar território
var import_panel           # a janela de importar PNG
var types_panel            # o designer de tipos, campos e vínculos
var boundary_tool := TerritoryBoundaryTool.new()
var painting_territory := false  # no modo pintar: o botão esquerdo do mouse pinta
var territory_stroking := false  # uma pincelada em andamento
var territory_owner := 0         # o país que está sendo pintado
var territory_mode := "pincel"   # pincel | balde | borracha | fronteira
var territory_radius := 300.0
var territory_land_only := true
var territory_reach := 800.0     # alcance de "crescer" (km de caminho)
var _last_dab := Vector3.ZERO
var _territory_seen := {}        # nível -> a versão vista pela última vez
var _territory_saved := {}       # nível -> a versão gravada no banco
var _territory_changed_ms := 0
var _palette_hash := 0
var _live_colors := {}           # país -> cor em prévia (o seletor está aberto; ainda não foi gravada)
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
	UiKit.set_types(registry.EntityTypes())
	search.refresh_kinds()
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
	sheet.territory_paint_requested.connect(func() -> void: start_painting(_current))
	sheet.territory_boundary_requested.connect(func() -> void: start_painting(_current, "fronteira"))
	sheet.territory_clear_requested.connect(_on_territory_clear)
	sheet.entity_color_changed.connect(_on_color_changed)
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


## Liga a camada política: lê do banco o que estava gravado, ouve a barra de pintar e a pilha de desfazer.
## more: as camadas dos outros níveis ({"provincia": Territory, "municipio": Territory}); sem elas, só países.
func bind_territory(t, stack, panel, more := {}) -> void:
	territory = t
	levels = {"pais": t}
	levels.merge(more)
	commands = stack
	territory_panel = panel
	for level in levels:
		if usable:
			registry.LoadTerritoryLevel(level, levels[level])
		_territory_seen[level] = levels[level].Version
		_territory_saved[level] = levels[level].Version
	boundary_tool.setup(territory, registry, map, panel, commands)
	panel.mode_changed.connect(_set_territory_mode)
	panel.radius_changed.connect(func(km: float) -> void: territory_radius = km)
	panel.land_only_changed.connect(func(on: bool) -> void: territory_land_only = on)
	panel.finish_requested.connect(stop_painting)
	panel.reach_changed.connect(func(km: float) -> void: territory_reach = km)
	panel.grow_requested.connect(territory_grow)
	panel.snap_requested.connect(territory_snap)
	panel.merge_requested.connect(territory_merge)
	panel.import_requested.connect(func() -> void:
		if import_panel != null and painting_territory:
			import_panel.pick_file())
	stack.changed.connect(_on_commands_changed)
	refresh_palette()


## Liga o designer de tipos (E2).
func bind_types(panel) -> void:
	types_panel = panel
	if not usable:
		return
	search.types_requested.connect(panel.open_dialog)
	panel.show_types(registry.EntityTypes())
	panel.type_requested.connect(func(label: String) -> void:
		if label.strip_edges() == "":
			panel.show_message("Dê um nome ao tipo.")
			return
		_types_done(registry.CreateEntityType(label), "Tipo \"%s\" criado: já aparece em \"＋ Novo\"." % label.strip_edges(),
			"Não deu para criar o tipo (já existe um com esse nome?)."))
	panel.field_requested.connect(_on_field_requested)
	panel.relation_requested.connect(func(out_label: String, in_label: String, src: String, dst: String) -> void:
		if out_label.strip_edges() == "" or in_label.strip_edges() == "":
			panel.show_message("Escreva o nome do vínculo nas duas pontas.")
			return
		_types_done(registry.CreateRelationType(out_label, in_label, src, dst), "Vínculo \"%s\" criado: aparece na ficha em Vínculos." % out_label.strip_edges(),
			"Não deu para criar o vínculo."))


func _on_field_requested(label: String, type: String, unit: String, options: String, min_value: float, max_value: float, kinds: PackedStringArray) -> void:
	if label.strip_edges() == "" or kinds.is_empty():
		types_panel.show_message("Dê um nome ao campo e marque ao menos um tipo.")
		return
	if not is_nan(min_value) and not is_nan(max_value) and min_value > max_value:
		types_panel.show_message("O mínimo é maior que o máximo.")
		return
	var code = registry.AddField(label, type, unit, options, kinds)
	if code != null and type == "number" and (not is_nan(min_value) or not is_nan(max_value)):
		registry.SetFieldLimits(code, min_value, max_value)
	_types_done(code, "Campo \"%s\" criado." % label.strip_edges(), "Não deu para criar o campo (escolha precisa de 2 opções).")


func _types_done(result, ok_text: String, fail_text: String) -> void:
	if result == null:
		types_panel.show_message(fail_text)
		return
	types_panel.show_message(ok_text)
	types_panel.clear_inputs()
	UiKit.set_types(registry.EntityTypes())
	search.refresh_kinds()
	types_panel.show_types(registry.EntityTypes())
	if _current != 0:
		_sheet_hash = 0
		_reload()


## Liga a janela de importar PNG.
func bind_import(panel) -> void:
	import_panel = panel
	panel.file_chosen.connect(_on_import_file)
	panel.apply_requested.connect(_on_import_apply)
	panel.focus_requested.connect(func(lat: float, lon: float) -> void:
		if focus_map.is_valid():
			focus_map.call(EvronGeo.dir(lat, lon), 1.6))


## O PNG escolhido: separa as regiões e abre o mapeamento com as entidades do nível pintado.
func _on_import_file(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		territory_panel.set_message("Não consegui ler a imagem.")
		return
	var regions = territory.AnalyzeImage(img, 4)
	if regions == null or regions.is_empty():
		territory_panel.set_message("Nenhuma região colorida (opaca) na imagem.")
		return
	var entities: Array = []
	for p in registry.Palette(territory_level):
		entities.append({"id": int(p.id), "name": registry.Name(int(p.id)), "rgb": int(_live_colors.get(int(p.id), p.rgb))})
	import_panel.show_regions(regions, entities, UiKit.kind_label(territory_level))


func _on_import_apply(indices: PackedInt32Array, owners: PackedInt32Array) -> void:
	if indices.is_empty() or not painting_territory:
		return
	territory_end()
	var edit = territory.ApplyImport(indices, owners)
	if edit == null:
		territory_panel.set_message("A importação não mudou nada.")
		return
	commands.push("Importar PNG (%d pontos)" % edit.Count, edit)
	territory_panel.set_area(territory.AreaKm2(territory_owner))
	territory_panel.set_message("")
	_show_warnings()


## Liga a barra do modo desenhar.
func bind_draw(panel) -> void:
	draw_panel = panel
	panel.undo_requested.connect(draw_undo)
	panel.finish_requested.connect(draw_finish)
	panel.cancel_requested.connect(draw_cancel)


func close() -> void:
	if registry != null and usable:
		territory_end()
		_save_territory()
		registry.Close()
		usable = false  # fechar duas vezes (trocar de mundo e depois sair da cena) não grava num banco fechado


## Grava agora o que ainda espera a gravação adiada (antes de exportar o mundo).
func save_now() -> void:
	territory_end()
	_save_territory()


func current() -> int:
	return _current


func open(id: int) -> void:
	if id == 0 or not usable:
		return
	if drawing:  # abrir outra ficha no meio do desenho o perderia: termina ou cancela antes
		_draw_message = "Conclua ou cancele o desenho antes de abrir outro cadastro."
		_refresh_draw()
		return
	if painting_territory and territory_mode == "fronteira" and id != territory_owner:
		stop_painting()
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


## O clique na camada política seleciona o dono do pixel. Onde ela não tem um dono visível, consulta as presenças do mapa.
func pick(dir: Vector3, tolerance_km: float) -> int:
	if not usable or drawing or painting_territory or map == null or dir == Vector3.ZERO:
		return 0
	if territory != null and "politica" in presence_panel.layers():
		var owner: int = territory.OwnerAt(dir)
		if owner != 0 and registry.Kind(owner) == territory_level:
			if owner != _current or not sheet.visible:
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


# --- pintar território -----------------------------------------------------------------------------------------------

## Entra no modo pintar território para o país: o botão esquerdo do mouse no globo passa a pintar (Main roteia), com pincel, balde ou borracha.
func start_painting(id: int, mode := "pincel") -> void:
	if not usable or territory == null or drawing or painting_territory or id == 0:
		return
	if not levels.has(registry.Kind(id)) or id > 65535:
		sheet.show_territory_message("Só país e província têm território (e com id até 65535).")
		return
	show_level(registry.Kind(id))
	territory_owner = id
	painting_territory = true
	territory_stroking = false
	territory_mode = mode
	territory_panel.set_mode(mode)
	territory_panel.show_state(registry.Name(id), territory.AreaKm2(id))
	_refresh_merge_choices()
	_show_warnings()
	if territory_mode == "fronteira":
		sheet.hide()
		boundary_tool.start(territory_owner)
	painting_changed.emit(true)


func _refresh_merge_choices() -> void:
	var others: Array = []
	for p in registry.Palette(territory_level):
		if int(p.id) != territory_owner and territory.AreaKm2(int(p.id)) > 0.0:
			others.append({"id": int(p.id), "name": registry.Name(int(p.id))})
	territory_panel.show_merge_choices(others)


## Unir: o território inteiro de outro cadastro do mesmo nível passa para o que está sendo pintado.
func territory_merge(from_id: int) -> void:
	if not painting_territory or registry.Kind(from_id) != territory_level:
		return
	territory_end()
	var edit = territory.ReplaceOwner(from_id, territory_owner)
	if edit == null:
		territory_panel.set_message("%s não tem território para unir." % registry.Name(from_id))
		return
	commands.push("Unir %s a %s (%d pontos)" % [registry.Name(from_id), registry.Name(territory_owner), edit.Count], edit)
	territory_panel.set_area(territory.AreaKm2(territory_owner))
	territory_panel.set_message("")
	_refresh_merge_choices()
	_show_warnings()


## Conta-gotas: o território clicado (do mesmo nível) passa a ser o pintado; a ferramenta volta ao pincel.
func _pick_owner(n: Vector3) -> void:
	var owner: int = territory.OwnerAt(n)
	if owner == 0 or registry.Kind(owner) != territory_level:
		territory_panel.set_message("Sem território deste nível aí.")
		return
	territory_owner = owner
	territory_panel.show_state(registry.Name(owner), territory.AreaKm2(owner))
	_refresh_merge_choices()
	_set_territory_mode("pincel")
	territory_panel.set_mode("pincel")
	if owner != _current:
		_current = owner
		_reload()


## Mostra e edita a camada de um nível. As outras ficam como estão (e continuam gravadas).
func show_level(level: String) -> void:
	if not levels.has(level) or level == territory_level:
		return
	territory_end()
	territory_level = level
	territory = levels[level]
	boundary_tool.use_territory(territory)
	_palette_hash = 0
	refresh_palette()
	territory_level_shown.emit(level, territory)


## Os avisos de inconsistência com o nível de cima, na barra de pintar (só ao pintar província ou município: varre a camada inteira).
func _show_warnings() -> void:
	var order := ["pais", "provincia", "municipio"]
	var i := order.find(territory_level)
	if not painting_territory or i < 1 or not levels.has(order[i - 1]):
		return
	var upper: String = order[i - 1]
	var lines: Array = []
	for w in registry.LevelWarnings(territory_level, levels[upper], territory):
		var km := LayerPanel._thousands(roundi(w.area_km2))
		match String(w.kind):
			"fora": lines.append("⚠ %s: %s km² fora de %s" % [registry.Name(int(w.id)), km, registry.Name(int(w.country))])
			"sem_pais": lines.append("⚠ %s não está ligado a um(a) %s (vínculo \"%s de\")" % [registry.Name(int(w.id)),
				UiKit.kind_label(upper).to_lower(), UiKit.kind_label(territory_level)])
			"lacuna": lines.append("⚠ %s: %s km² sem %s" % [registry.Name(int(w.id)), km, UiKit.kind_label(territory_level).to_lower()])
	territory_panel.set_message("\n".join(lines.slice(0, 6)) + ("\n…" if lines.size() > 6 else ""))


func stop_painting() -> void:
	if not painting_territory:
		return
	if territory_stroking:
		territory_end()
	boundary_tool.stop()
	painting_territory = false
	territory_panel.hide_panel()
	painting_changed.emit(false)
	if _current != 0:
		_reload()  # a área da ficha


func _set_territory_mode(mode: String) -> void:
	if mode == territory_mode:
		return
	territory_end()
	territory_mode = mode
	if mode == "fronteira":
		sheet.hide()
		boundary_tool.start(territory_owner)
	else:
		boundary_tool.stop()
	painting_changed.emit(true)


## O botão esquerdo apertou no globo em n. Pincel e borracha começam uma pincelada; o balde preenche na hora.
func territory_begin(n: Vector3) -> void:
	if not painting_territory or territory_mode == "fronteira" or n == Vector3.ZERO:
		return
	if territory_mode == "conta-gotas":
		_pick_owner(n)
		return
	if territory_mode == "balde":
		var edit = territory.Fill(n, territory_owner, territory_land_only)
		if edit != null:
			commands.push("Balde (%d pontos)" % edit.Count, edit)
			territory_panel.set_area(territory.AreaKm2(territory_owner))
		return
	territory.Begin()
	territory_stroking = true
	_dab(n)


## O mouse andou com o botão apertado: nova marca a cada 1/4 do raio percorrido.
func territory_drag(n: Vector3) -> void:
	if territory_stroking and n != Vector3.ZERO and EvronGeo.distance_km(n, _last_dab) >= territory_radius * 0.25:
		_dab(n)


## O botão soltou: a pincelada vira UM comando na pilha de desfazer.
func territory_end() -> void:
	if not territory_stroking:
		return
	territory_stroking = false
	var edit = territory.End()
	if edit != null:
		commands.push("%s território (%d pontos)" % ["Apagar" if territory_mode == "borracha" else "Pintar", edit.Count], edit)
		territory_panel.set_area(territory.AreaKm2(territory_owner))


func _dab(n: Vector3) -> void:
	_last_dab = n
	if territory_mode == "borracha":
		territory.Dab(n, territory_radius, 0, false, territory_owner)  # a borracha de um país só apaga o dele
	else:
		territory.Dab(n, territory_radius, territory_owner, territory_land_only, -1)


## Fronteiras naturais: os países crescem pela terra sem dono a partir do território e da capital (a presença "capital" vigente na data
## mostrada). all = todos crescem; senão só o país pintado ganha terra, parando onde os vizinhos chegariam antes.
func territory_grow(all: bool) -> void:
	if not painting_territory:
		return
	var owners := PackedInt32Array()
	var lats := PackedFloat64Array()
	var lons := PackedFloat64Array()
	for it in registry.MapItems(PackedStringArray(["politica"]), 0, shown_t):
		if it.role == "capital" and it.kind == "pais" and int(it.entity_id) <= 65535:
			owners.append(int(it.entity_id))
			lats.append(it.lat)
			lons.append(it.lon)
	var edit = territory.Grow(owners, lats, lons, 0 if all else territory_owner, territory_reach)
	_natural_done(edit, "Crescer todos os países" if all else "Crescer território",
		"Nada para crescer: o país precisa de território pintado ou de uma capital, e de terra sem dono ao alcance.")


## Assenta as fronteiras do país pintado com os vizinhos na crista ou no rio grande mais perto.
func territory_snap() -> void:
	if painting_territory:
		_natural_done(territory.Snap(territory_owner, SNAP_BAND_KM), "Assentar fronteiras",
			"Nada mudou: o país não faz fronteira com outro, ou ela já está no relevo.")


func _natural_done(edit, name: String, nothing: String) -> void:
	if edit == null:
		territory_panel.set_message(nothing)
		return
	commands.push("%s (%d pontos)" % [name, edit.Count], edit)
	territory_panel.set_area(territory.AreaKm2(territory_owner))
	territory_panel.set_message("")


func _on_territory_clear() -> void:
	if _current == 0 or not levels.has(registry.Kind(_current)):
		return
	var edit = levels[registry.Kind(_current)].ClearOwner(_current)
	if edit != null:
		commands.push("Apagar território (%d pontos)" % edit.Count, edit)
	_reload()


func _on_commands_changed() -> void:
	if painting_territory and not territory_stroking:
		territory_panel.set_area(territory.AreaKm2(territory_owner))  # desfazer e refazer mudam a área
		_refresh_merge_choices()
		_show_warnings()


## A cor de um país: a prévia (seletor aberto) só vai para a paleta; ao fechar o seletor ela é gravada.
func _on_color_changed(id: int, rgb: int, final: bool) -> void:
	if not usable:
		return
	if final:
		registry.SetEntityColor(id, rgb)
		_live_colors.erase(id)
	else:
		_live_colors[id] = rgb
	refresh_palette()


## Manda a paleta do nível mostrado (id e cor) a quem desenha, se mudou.
func refresh_palette() -> void:
	if not usable:
		return
	var entries: Array = []
	for p in registry.Palette(territory_level):
		entries.append({"id": int(p.id), "rgb": int(_live_colors.get(int(p.id), p.rgb))})
	var key: int = entries.hash()
	if key != _palette_hash:
		_palette_hash = key
		palette_changed.emit(entries)


## A camada política é gravada no banco ~1,5 s depois da última edição (e ao fechar), nunca no meio de uma pincelada.
func _save_territory_if_due() -> void:
	if not usable:
		return
	var dirty := false
	for level in levels:
		if levels[level].Version != _territory_seen[level]:
			_territory_seen[level] = levels[level].Version
			_territory_changed_ms = Time.get_ticks_msec()
		dirty = dirty or levels[level].Version != _territory_saved[level]
	if dirty and not territory_stroking and Time.get_ticks_msec() - _territory_changed_ms >= 1500:
		_save_territory()


func _save_territory() -> void:
	if not usable:
		return
	for level in levels:
		if levels[level].Version != _territory_saved[level] and registry.SaveTerritoryLevel(level, levels[level]) != null:
			_territory_saved[level] = levels[level].Version
		else:
			_territory_changed_ms = Time.get_ticks_msec()


# --- desenhar fronteira ----------------------------------------------------------------------------------------------

## Entra no modo desenhar para a ficha aberta: o clique no globo passa a marcar os pontos do contorno (draw_click). place_id != 0 refaz o
## contorno desse lugar; senão, ao concluir, cria o lugar com o nome dado e liga a entidade a ele com a função (role).
func start_border(place_name: String, role: String, place_id: int = 0) -> void:
	if not usable or drawing or _current == 0:
		return
	if place_id == 0 and place_name.strip_edges() == "":
		sheet.show_border_message("Dê um nome à região antes de desenhar.")
		return
	stop_painting()
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
	_save_territory_if_due()
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
	var deleted := _current
	var layer = levels.get(registry.Kind(deleted)) if deleted <= 65535 else null
	var has_territory: bool = layer != null
	if has_territory:
		territory_end()
		if painting_territory and territory_owner == deleted:
			stop_painting()
	if registry.Delete(deleted) == null:
		return
	if has_territory:
		layer.ClearOwner(deleted)
		layer.ForgetOwnerBoundaries(deleted)
		commands.discard_matching(func(cmd: Object) -> bool:
			return cmd.get_script() == TerritoryEdit and cmd.TouchesOwner(deleted))
	_current = 0
	_sheet_hash = 0
	sheet.hide_sheet()
	refresh_search()
	refresh_map()
	refresh_palette()


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
		if painting_territory and territory_mode == "fronteira":
			sheet.hide()
	refresh_search()
	refresh_map()
	refresh_palette()


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
	var geo := {"places": c.items, "places_more": c.more, "fixed_text": _fixed_text(), "has_fixed": fixed_dir != Vector3.ZERO, "dates_e": dates_e, "dates_d": dates_d}
	if levels.has(s.kind):
		geo["territory"] = {"area_km2": levels[s.kind].AreaKm2(int(s.id)), "color": int(_live_colors.get(int(s.id), registry.EntityColor(int(s.id)))), "ok": int(s.id) <= 65535}
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
