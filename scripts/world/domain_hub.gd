extends RefCounted
## Liga os painéis de cadastro ao Registry: cada sinal do painel vira uma chamada ao núcleo, e o que o núcleo devolve volta
## para o painel. Não tem regra de mundo (quem valida e grava é o Registry; quem converte datas é o local_calendar.gd) e não
## conhece o globo. Segue o relógio: Main chama set_time com a data mostrada e tick a cada quadro.
## Quem o cria precisa guardar uma referência (os sinais dos painéis só guardam funções deste objeto).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Calendar = preload("res://scripts/world/calendar.gd")
const LocalCalendar = preload("res://scripts/world/local_calendar.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")

const REBUILD_MS := 500  # a ficha não é refeita mais que 2x por segundo enquanto o relógio anda
const ALWAYS := -9223372036854775807 - 1
const FOREVER := 9223372036854775807

## Instante em que as fichas são lidas: a data mostrada pelo relógio (set_time). Sem relógio (testes dos painéis sozinhos),
## é "o que não tem fim": tudo o que não tem prazo vale e nenhuma data é escrita.
var shown_t := 9223372036854775806
var has_clock := false

var registry
var search
var sheet
var calendars  # o painel de calendários (pode faltar)
var map                    # a camada de lugares do globo (PlaceLayer), ligada por bind_map
var presence_panel         # camadas e escopo do mapa
var focus_map := Callable()  # func(direção, zoom): leva a câmera a um ponto
var fixed_dir := Vector3.ZERO  # o ponto fixado no globo (onde "Criar lugar aqui" cria)
var _current := 0
var _pending := false      # o tempo andou e a ficha ainda não foi relida
var _last_rebuild_ms := 0
var _defs := {}            # id do calendário -> definição (as definições não mudam depois de criadas)


## db_path: arquivo do banco ("user://..." é traduzido) ou ":memory:" nos testes.
func setup(db_path: String, search_panel, sheet_panel, calendar_panel = null) -> void:
	registry = load("res://scripts/world/Registry.cs").new()
	registry.Open(db_path if db_path == ":memory:" else ProjectSettings.globalize_path(db_path))
	search = search_panel
	sheet = sheet_panel
	calendars = calendar_panel
	search.query_changed.connect(func(_t: String, _k: String) -> void: refresh_search())
	search.entity_chosen.connect(open)
	search.create_requested.connect(_on_create)
	search.society_requested.connect(_on_society)
	sheet.name_changed.connect(func(t: String) -> void:
		registry.Correct(_current, t)
		refresh_search())
	sheet.summary_changed.connect(func(t: String) -> void: registry.SetSummary(_current, t))
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
		open(registry.Duplicate(_current, copy_links, "")))
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
	sheet.estimate_added.connect(_on_estimate_added)
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
	panel.changed.connect(refresh_map)
	refresh_map()


func close() -> void:
	registry.Close()


func current() -> int:
	return _current


func open(id: int) -> void:
	_current = id
	_reload()


func refresh_search() -> void:
	search.show_results(registry.Search(search.query(), search.kind_filter(), "", 0, shown_t), _current)


## O relógio do mundo mostra a data t (presente ou consulta). Atualiza na hora as datas escritas na ficha; a ficha em si
## (nomes, vínculos e usos válidos em t) é relida em seguida, por tick(), sem passar de REBUILD_MS.
func set_time(t: int) -> void:
	if has_clock and t == shown_t:
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
	sheet.show_fixed_point(_fixed_text(), dir != Vector3.ZERO)


## Clique no mapa: as presenças visíveis (mesmas camadas e escopo do desenho) que cobrem o ponto, dentro do raio do lugar ou da tolerância
## (km). Uma só entidade abre a ficha dela; várias aparecem na lista de busca para escolher. Devolve quantas entidades foram achadas.
func pick(dir: Vector3, tolerance_km: float) -> int:
	if map == null or dir == Vector3.ZERO or (not presence_panel.all_entities() and _current == 0):
		return 0
	var ll := EvronGeo.lat_lon(dir)
	var only := 0 if presence_panel.all_entities() else _current
	var found := {}  # entidade -> o primeiro resultado (o mais específico)
	for h in registry.EntitiesAt(ll.x, ll.y, tolerance_km, presence_panel.layers(), only, shown_t):
		if not found.has(int(h.entity_id)):
			found[int(h.entity_id)] = h
	if found.size() == 1:
		open(found.keys()[0])
	elif found.size() > 1:
		var rows: Array = []
		for id in found:
			var h: Dictionary = found[id]
			rows.append({"id": id, "kind": h.kind, "name": h.entity, "match": "%s · %s" % [h.place, UiKit.role_label(h.role)]})
		search.show_results(rows, _current)
	return found.size()


## Leva a câmera ao lugar, a uma distância proporcional ao tamanho da área.
func focus_place(place_id: int) -> void:
	if not focus_map.is_valid():
		return
	var p: Dictionary = registry.Place(place_id)
	focus_map.call(EvronGeo.dir(p.lat, p.lon), 1.0 + 2.5 * maxf(p.radius_km, 150.0) / EvronGeo.RADIUS_KM)


## Redesenha as presenças no globo: as camadas marcadas, da ficha aberta ou de todas as entidades, na data mostrada.
func refresh_map() -> void:
	if map == null:
		return
	var all: bool = presence_panel.all_entities()
	if not all and _current == 0:
		map.show_items([])
		return
	map.show_items(registry.MapItems(presence_panel.layers(), 0 if all else _current, shown_t))


## A cada quadro: se o tempo andou, relê a ficha e a busca, mas só quando o usuário não está digitando.
func tick() -> void:
	if _pending and Time.get_ticks_msec() - _last_rebuild_ms >= REBUILD_MS and not sheet.is_editing():
		if _current != 0:
			_reload()
		else:
			_pending = false
			refresh_search()
			refresh_map()


# --- tratadores ---------------------------------------------------------------------------------------------------

func _on_create(kind: String, name: String) -> void:
	var text := name.strip_edges()
	open(registry.Create(kind, text if text != "" else "Sem nome (%s)" % UiKit.kind_label(kind)))


func _on_society(name: String) -> void:
	var text := name.strip_edges()
	var ids: Array = registry.CreateSociety(text if text != "" else "Sem nome", PackedStringArray(["pais", "cultura", "etnia"]))
	open(ids[0])  # a ficha do país; as outras abrem pelas relações


func _on_field(code: String, state: String, value: String) -> void:
	registry.SetField(_current, code, state, value)
	var now: Dictionary = registry.GetField(_current, code)
	sheet.update_field(code, now.state, now.value)  # mostra o que ficou (corrige o que foi recusado)


func _on_link_search(text: String, dst_kind: String) -> void:
	sheet.show_link_candidates(registry.Search(text, dst_kind, "", 0, shown_t))


func _on_delete() -> void:
	registry.Delete(_current)
	_current = 0
	sheet.hide_sheet()
	refresh_search()
	refresh_map()


## Cria um lugar no ponto fixado no globo e já o liga à ficha aberta.
func _on_place_created(place_name: String, kind: String, radius_km: float, role: String) -> void:
	if fixed_dir == Vector3.ZERO:
		return
	var ll := EvronGeo.lat_lon(fixed_dir)
	var id: int = registry.AddPlace(place_name, kind, ll.x, ll.y, radius_km, "")
	if id != 0:
		registry.AddPresence(_current, id, role, "media")
	_reload()


## Estimativa na data mostrada: com nível (sem número) ou com faixa "de ... até ..." (só o "de" = valor exato; vírgula decimal aceita).
func _on_estimate_added(place_id: int, low: String, high: String, level: String, certainty: String) -> void:
	if level != "":
		registry.AddEstimateLevel(_current, place_id, shown_t, level, certainty, "")
		_reload()
		return
	var lo := low.replace(",", ".")
	var hi := (high if high != "" else low).replace(",", ".")
	if not lo.is_valid_float() or not hi.is_valid_float():
		sheet.show_geo_message("Informe um número (de ... até ...) ou escolha só um nível.")
	elif float(lo) < 0.0 or float(hi) < float(lo):
		sheet.show_geo_message("A faixa precisa ser de 0 para cima, e o \"até\" não pode ser menor que o \"de\".")
	else:
		registry.AddEstimate(_current, place_id, shown_t, float(lo), float(hi), certainty, "")
		_reload()


## data: o que o CalendarPanel manda (name, era_name, era_abbr, year, month, day, first, direction, day_hour, months).
## O calendário e a primeira era valem para sempre; o marco é a meia-noite LOCAL da data escolhida (a hora em que o dia vira).
func _on_calendar_create(data: Dictionary) -> void:
	var marker := Calendar.to_seconds(data.year, data.month, data.day)
	if marker == Calendar.INVALID:
		calendars.show_message("Essa data do marco não existe (o mês escolhido não tem esse dia).")
		return
	marker += int(data.day_hour) * Calendar.HOUR
	var id: int = registry.AddCalendar(data.name, "", data.months, int(data.day_hour) * Calendar.HOUR, "exata", "")
	if id == 0:
		calendars.show_message("Não consegui criar o calendário (veja o log).")
		return
	var era: int = registry.AddEra(data.era_name, data.era_abbr, marker, data.direction, data.first)
	registry.AttachEra(id, era, ALWAYS, FOREVER, 0)
	calendars.clear_form()
	calendars.show_message("Calendário criado.")
	calendars.show_calendars(_calendar_rows())
	if _current != 0:
		_reload()  # a ficha aberta passa a oferecer o calendário novo


## Relê a ficha atual e refaz a lista de busca.
func _reload() -> void:
	_pending = false
	_last_rebuild_ms = Time.get_ticks_msec()
	var s: Dictionary = registry.Sheet(_current, shown_t)
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
	var places: Array = []
	for p in registry.Places(""):
		places.append({"id": p.id, "name": p.name})
	var dates_e := {}
	for e in s.estimates:
		dates_e[int(e.id)] = Calendar.format(int(e.t), false) if has_clock else ""
	var dates_d := {}
	for c in s.compositions:
		dates_d[int(c.id)] = Calendar.format(int(c.t), false) if has_clock else ""
	return {"places": places, "fixed_text": _fixed_text(), "has_fixed": fixed_dir != Vector3.ZERO, "dates_e": dates_e, "dates_d": dates_d}


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
