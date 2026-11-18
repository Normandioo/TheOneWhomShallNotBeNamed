extends PanelContainer
## Barra de foco da vista do espaço, embaixo ao centro, em duas linhas: o Sol e os planetas; depois as luas e o botão
## para ver o sistema inteiro.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const SolarBodies = preload("res://scripts/sim/solar_bodies.gd")

signal focus_requested(id: int)
signal overview_requested


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style())
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	position = Vector2(0, -12)
	var rows := VBoxContainer.new()
	add_child(rows)
	var planets := HBoxContainer.new()
	var moons := HBoxContainer.new()
	rows.add_child(planets)
	rows.add_child(moons)
	for id in SolarBodies.Id.size():
		var b := Button.new()
		b.text = SolarBodies.body_name(id)
		b.pressed.connect(focus_requested.emit.bind(id))
		(planets if id < SolarBodies.Id.MOON else moons).add_child(b)
	var overview := Button.new()
	overview.text = "Visão geral"
	overview.pressed.connect(overview_requested.emit)
	moons.add_child(overview)
