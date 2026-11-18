extends RefCounted
## Liga os painéis de cadastro ao Registry: cada sinal do painel vira uma chamada ao núcleo, e o que o núcleo devolve volta
## para o painel. Não tem regra de mundo (quem valida e grava é o Registry; quem converte datas é o local_calendar.gd) e não
## conhece o globo. Segue o relógio: Main chama set_time com a data mostrada e tick a cada quadro.
## Quem o cria precisa guardar uma referência (os sinais dos painéis só guardam funções deste objeto).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Calendar = preload("res://scripts/world/calendar.gd")
const LocalCalendar = preload("res://scripts/world/local_calendar.gd")

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
	refresh_search()


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


## A cada quadro: se o tempo andou, relê a ficha e a busca, mas só quando o usuário não está digitando.
func tick() -> void:
	if _pending and Time.get_ticks_msec() - _last_rebuild_ms >= REBUILD_MS and not sheet.is_editing():
		if _current != 0:
			_reload()
		else:
			_pending = false
			refresh_search()


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
	sheet.show_sheet(s, registry.LinkTypesFor(s.kind), _calendar_info(s))
	refresh_search()


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
