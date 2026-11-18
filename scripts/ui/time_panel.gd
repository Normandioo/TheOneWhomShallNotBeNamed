extends PanelContainer
## Painel do topo, ao centro: a data, a velocidade do tempo e as opções da simulação.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const GameClock = preload("res://scripts/sim/game_clock.gd")

signal speed_selected(scale: float)
signal auto_terraform_toggled(on: bool)
signal extremes_toggled(on: bool)

var _date: Label
var _speed_buttons: Array[Button] = []


## `speed` é a velocidade inicial.
func _init(speed: float) -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style())
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	position = Vector2(0, 12)
	var box := VBoxContainer.new()
	add_child(box)
	_date = Label.new()
	_date.add_theme_font_size_override("font_size", 20)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_date)

	var speeds := HBoxContainer.new()
	box.add_child(speeds)
	var group := ButtonGroup.new()
	for s in GameClock.SPEEDS:
		var b := Button.new()
		b.text = s[0]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = s[1] == speed
		b.pressed.connect(speed_selected.emit.bind(s[1]))
		speeds.add_child(b)
		_speed_buttons.append(b)

	var options := HBoxContainer.new()
	box.add_child(options)
	_add_check(options, "Terraformação automática", false, auto_terraform_toggled)
	var extremes := _add_check(options, "Permitir extremos", false, extremes_toggled)
	extremes.tooltip_text = "Temperatura até +60 °C e pressão até 5 bar"


## A data do jogo, a partir do dia juliano.
func show_date(jd: float) -> void:
	var t := Time.get_datetime_dict_from_unix_time(int(roundf((jd - 2440587.5) * 86400.0)))
	_date.text = "%04d-%02d-%02d" % [t["year"], t["month"], t["day"]]


## Marca o botão da velocidade atual, sem repetir o evento.
func show_speed(scale: float) -> void:
	for k in _speed_buttons.size():
		_speed_buttons[k].set_pressed_no_signal(GameClock.SPEEDS[k][1] == scale)


func _add_check(box: Container, text: String, pressed: bool, changed: Signal) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = pressed
	c.toggled.connect(changed.emit)
	box.add_child(c)
	return c
