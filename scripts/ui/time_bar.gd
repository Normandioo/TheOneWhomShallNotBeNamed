extends VBoxContainer
## Barra de tempo, no bloco do alto à direita (a janela do calendário abre embaixo dela): data e hora mostradas, pausa, velocidade e avanços; e a janela do calendário
## (consultar uma data, avançar até uma data, marcos). Só mostra e pede: avisa por sinais, o relógio decide.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Calendar = preload("res://scripts/world/calendar.gd")

signal play_toggled
signal speed_selected(seconds_per_real_second: int)
signal advance_seconds(seconds: int)
signal advance_months(n: int)
signal advance_to(t: int)
signal view_date(t: int)
signal back_to_present

const SPEEDS := [["1 minuto do mundo/s", Calendar.MINUTE], ["1 hora/s", Calendar.HOUR], ["1 dia/s", Calendar.DAY]]
# Hora, dia e semana são durações fixas; o mês conserva o dia do mês (31 jan + 1 mês = 28 fev); o ano são 365 dias.
const ADVANCES := [["+1 hora", "s", Calendar.HOUR, "Duração fixa de 1 hora."],
	["+1 dia", "s", Calendar.DAY, "Duração fixa de 24 horas."],
	["+7 dias", "s", 7 * Calendar.DAY, "Duração fixa de 7 dias."],
	["+1 mês", "m", 1, "Mês do calendário: conserva o dia e a hora; se o dia não existe no destino, usa o último (31 jan → 28 fev)."],
	["+1 ano", "m", 12, "365 dias (não há anos bissextos)."]]

var _date: Label
var _state: Label
var _message: Label
var _present: Label  # só em consulta: onde está o presente preservado
var _play: Button
var _speed: OptionButton
var _advance_buttons: Array[Button] = []
var _window: PanelContainer
var _fields := {}  # year, day, hour, minute: SpinBox; month: OptionButton
var _markers: Label
var _go_buttons: Array[Button] = []  # "Avançar até": só vale fora da consulta
var _shown := 0  # a data na tela, com que a janela do calendário abre preenchida


func _init() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(bar)
	_build_window()  # depois da linha do tempo: abre embaixo dela
	var box := VBoxContainer.new()
	bar.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	box.add_child(top)
	_play = _button(top, "", func() -> void: play_toggled.emit())  # só o ícone; a dica diz Continuar/Pausar
	_play.icon = preload("res://assets/ui/play.png")
	_play.tooltip_text = "Continuar"
	_play.custom_minimum_size = Vector2(42, 40)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiKit.inset_style())
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(plate)
	var when := VBoxContainer.new()
	when.add_theme_constant_override("separation", 0)
	plate.add_child(when)
	_date = Label.new()
	UiKit.style_heading(_date)
	_date.add_theme_font_size_override("font_size", 15)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	when.add_child(_date)
	_state = Label.new()
	_state.add_theme_font_size_override("font_size", 12)
	_state.add_theme_color_override("font_color", Color("#9fb0a8"))
	_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	when.add_child(_state)
	_speed = OptionButton.new()
	for s in SPEEDS:
		_speed.add_item(s[0])
	_speed.item_selected.connect(func(i: int) -> void: speed_selected.emit(SPEEDS[i][1]))
	_speed.fit_to_longest_item = false  # o bloco fica estreito; a lista aberta mostra os nomes inteiros
	_speed.custom_minimum_size = Vector2(84, 0)
	_speed.tooltip_text = "Velocidade do tempo"
	top.add_child(_speed)
	var calendar_button := _button(top, "", _toggle_window)
	calendar_button.icon = preload("res://assets/ui/clock.png")
	calendar_button.tooltip_text = "Calendário: consultar uma data, avançar até ela e ver os marcos"

	var advance := Button.new()
	advance.text = "Avançar…"
	top.add_child(advance)
	var adv := HBoxContainer.new()
	advance.toggled.connect(func(open: bool) -> void: adv.visible = open)
	advance.toggle_mode = true
	adv.hide()
	box.add_child(adv)
	for a in ADVANCES:
		var b := _button(adv, a[0], _on_advance.bind(a[1], a[2]))
		b.tooltip_text = a[3]
		_advance_buttons.append(b)
	_present = Label.new()
	_present.modulate = Color(0.6, 0.85, 1.0)
	_present.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_present)
	_message = Label.new()
	_message.modulate = Color(1, 0.8, 0.5)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # um aviso comprido não alarga o bloco
	_message.hide()
	box.add_child(_message)


## Mostra o estado do relógio (não guarda tempo próprio).
func show_clock(clock) -> void:
	var t: int = clock.shown()
	_shown = t
	_date.text = Calendar.format(t)
	_date.modulate = Color(0.6, 0.85, 1.0) if clock.viewing else Color.WHITE
	if clock.viewing:
		_state.text = "CONSULTA"
	else:
		_state.text = "▶ em execução" if clock.running else "⏸ pausado"
	_present.visible = clock.viewing
	_present.text = "O presente continua em %s" % Calendar.format(clock.now)
	_play.tooltip_text = "Pausar" if clock.running else "Continuar"
	_play.icon = preload("res://assets/ui/pause.png") if clock.running else preload("res://assets/ui/play.png")
	_play.disabled = clock.viewing  # em consulta a reprodução fica parada; "Voltar ao presente" encerra
	for b in _advance_buttons:
		b.disabled = clock.viewing
	for b in _go_buttons:
		b.disabled = clock.viewing
	for i in SPEEDS.size():
		if SPEEDS[i][1] == clock.speed:
			_speed.select(i)
	var lines := PackedStringArray()
	for e in clock.events():
		lines.append("%s  %s  %s" % ["✔" if e["fired"] else "·", Calendar.format(e["at"]), e["name"]])
	_markers.text = "\n".join(lines) if lines.size() > 0 else "Nenhum marco cadastrado."


## Abre ou fecha a janela do calendário. Ao abrir, os campos partem da data mostrada: para voltar, muda-se só o que difere.
func _toggle_window() -> void:
	_window.visible = not _window.visible
	if not _window.visible:
		return
	var d := Calendar.from_seconds(_shown)
	for f in ["year", "day", "hour", "minute"]:
		_fields[f].value = d[f]
	_fields["month"].select(d["month"] - 1)


func show_message(text: String) -> void:
	_message.text = text
	_message.visible = not text.is_empty()
	reset_size.call_deferred()


func _on_advance(kind: String, n: int) -> void:
	show_message("")
	if kind == "s":
		advance_seconds.emit(n)
	else:
		advance_months.emit(n)


func _build_window() -> void:
	_window = PanelContainer.new()
	_window.visible = false
	_window.add_theme_stylebox_override("panel", UiKit.panel_style())
	var box := VBoxContainer.new()
	_window.add_child(box)
	var title := Label.new()
	title.text = "Calendário de Evron (versão %d · 365 dias, sem anos bissextos)" % Calendar.VERSION
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	_fields["day"] = _spin(row, "Dia", 1, 31, 1)
	var month := OptionButton.new()
	for n in Calendar.MONTH_NAMES:
		month.add_item(n)
	row.add_child(month)
	_fields["month"] = month
	_fields["year"] = _spin(row, "Ano", -1000000, 1000000, Calendar.TECHNICAL_START_YEAR)
	_fields["hour"] = _spin(row, "Hora", 0, 23, 0)
	_fields["minute"] = _spin(row, "Min", 0, 59, 0)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	_button(actions, "Consultar data", _emit_date.bind(view_date))
	_go_buttons.append(_button(actions, "Avançar até", _emit_date.bind(advance_to)))
	_button(actions, "Voltar ao presente", func() -> void: back_to_present.emit())
	_markers = Label.new()
	box.add_child(_markers)
	add_child(_window)


func _emit_date(sig: Signal) -> void:
	var t := Calendar.to_seconds(int(_fields["year"].value), _fields["month"].selected + 1, int(_fields["day"].value),
		int(_fields["hour"].value), int(_fields["minute"].value))
	if t == Calendar.INVALID:
		show_message("Data inválida: %s não tem %d dias." % [Calendar.MONTH_NAMES[_fields["month"].selected], int(_fields["day"].value)])
		return
	show_message("")
	sig.emit(t)


func _spin(box: Container, label: String, lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.prefix = label
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.select_all_on_focus = true  # digitar substitui o número; sem isto "2" num campo com "1" virava 12
	box.add_child(s)
	return s


func _button(box: Container, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	box.add_child(b)
	return b
