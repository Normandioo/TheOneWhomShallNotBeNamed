extends PanelContainer
## Janela dos calendários locais: os cadastrados (com a data de agora em cada um) e o formulário de um calendário novo com a sua
## primeira era. Só mostra e pede: avisa por sinal; quem cria é o DomainHub.
## Um calendário desta etapa conserva os 12 meses e os 365 dias do universal; o autor escolhe nomes, era, numeração e a hora em que o dia vira.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Calendar = preload("res://scripts/world/calendar.gd")

signal create_requested(data: Dictionary)  # name, era_name, era_abbr, year, month, day, first, direction, day_hour, months
signal closed

const WIDTH := 480

var _list: ItemList
var _name: LineEdit
var _era: LineEdit
var _abbr: LineEdit
var _year: SpinBox
var _month: OptionButton
var _day: SpinBox
var _first: SpinBox
var _direction: OptionButton
var _hour: SpinBox
var _months: TextEdit
var _message: Label


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(WIDTH, 0)
	var box := VBoxContainer.new()
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Calendários"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	head.add_child(close)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 96)
	box.add_child(_list)

	box.add_child(HSeparator.new())
	var sub := Label.new()
	sub.text = "Novo calendário (meses e dias como no universal)"
	sub.add_theme_font_size_override("font_size", 15)
	box.add_child(sub)

	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	_name = _line(grid, "Nome", "Calendário de …")
	_era = _line(grid, "Era", "Nome da era")
	_abbr = _line(grid, "Abreviação", "opcional")
	_year = _spin(grid, "Marco da era: ano", -100000, 100000, 1)
	grid.add_child(_label("Marco: mês"))
	_month = OptionButton.new()
	for m in Calendar.MONTH_NAMES:
		_month.add_item(m)
	grid.add_child(_month)
	_day = _spin(grid, "Marco: dia", 1, 31, 1)
	_first = _spin(grid, "Número do ano do marco", -1000000, 1000000, 1)
	grid.add_child(_label("Contagem"))
	_direction = OptionButton.new()
	_direction.add_item("Cresce com o tempo")
	_direction.add_item("Cresce para o passado (antes de)")
	grid.add_child(_direction)
	_hour = _spin(grid, "O dia vira às (h)", 0, 23, 0)

	var months_label := _label("Nomes dos meses")
	box.add_child(months_label)
	_months = TextEdit.new()
	_months.custom_minimum_size = Vector2(0, 90)
	_months.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_months.placeholder_text = "12 nomes, um por linha. Vazio = nomes do calendário universal."
	box.add_child(_months)

	var row := HBoxContainer.new()
	box.add_child(row)
	var create := Button.new()
	create.text = "Criar calendário"
	create.pressed.connect(_on_create)
	row.add_child(create)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_message)


## Abre a janela com os calendários cadastrados (cada um: name, summary).
func open(rows: Array) -> void:
	visible = true
	show_calendars(rows)


func show_calendars(rows: Array) -> void:
	_list.clear()
	for r in rows:
		_list.add_item("%s  —  %s" % [r.name, r.summary])
	if rows.is_empty():
		_list.add_item("Nenhum calendário ainda.", null, false)


func show_message(text: String) -> void:
	_message.text = text


func _on_create() -> void:
	var months := _months.text.strip_edges()
	var lines := months.split("\n", false) if months != "" else PackedStringArray()
	if _name.text.strip_edges() == "" or _era.text.strip_edges() == "":
		show_message("Dê um nome ao calendário e à era.")
	elif lines.size() != 0 and lines.size() != 12:
		show_message("São 12 nomes de mês (vieram %d), ou deixe vazio." % lines.size())
	else:
		create_requested.emit({"name": _name.text.strip_edges(), "era_name": _era.text.strip_edges(), "era_abbr": _abbr.text.strip_edges(),
			"year": int(_year.value), "month": _month.selected + 1, "day": int(_day.value), "first": int(_first.value),
			"direction": "up" if _direction.selected == 0 else "down", "day_hour": int(_hour.value), "months": months})


func clear_form() -> void:
	for l in [_name, _era, _abbr]:
		l.text = ""
	_months.text = ""


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _line(grid: GridContainer, label: String, placeholder: String) -> LineEdit:
	grid.add_child(_label(label))
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(e)
	return e


func _spin(grid: GridContainer, label: String, lo: int, hi: int, value: int) -> SpinBox:
	grid.add_child(_label(label))
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	grid.add_child(s)
	return s
