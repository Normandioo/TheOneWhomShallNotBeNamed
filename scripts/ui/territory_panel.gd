extends PanelContainer
## A barra do modo "pintar território": de que país, a ferramenta (pincel, balde ou borracha), o raio, "só em terra", a área já pintada e Terminar.
## Só mostra e pede: avisa por sinal; quem pinta é o DomainHub. Esc termina. Ctrl+Z e Ctrl+Y desfazem e refazem (a pilha é a mesma do terreno).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")  # só para o separador de milhares

signal mode_changed(mode: String)   # pincel | balde | borracha
signal radius_changed(km: float)
signal land_only_changed(on: bool)
signal finish_requested

const MODES := [["pincel", "Pincel"], ["balde", "Balde"], ["borracha", "Borracha"]]
const TIPS := {
	"pincel": "Arraste no globo para pintar. Pintar sobre outro país toma o território dele.",
	"balde": "Clique dentro de uma área cercada por pintura para preencher tudo de uma vez.",
	"borracha": "Arraste para apagar só o território deste país (o dos vizinhos fica).",
}

var radius_km := 300.0
var land_only := true
var mode := "pincel"

var _title: Label
var _tip: Label
var _area: Label
var _radius_label: Label
var _buttons: Dictionary = {}


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	position = Vector2(-12, -150)  # acima da legenda
	custom_minimum_size = Vector2(300, 0)
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.modulate = Color(1.0, 0.92, 0.35)
	box.add_child(_title)
	var tools := HBoxContainer.new()
	box.add_child(tools)
	var group := ButtonGroup.new()
	for m in MODES:
		var b := Button.new()
		b.text = m[1]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = m[0] == mode
		b.pressed.connect(func() -> void:
			mode = m[0]
			_tip.text = TIPS[mode]
			mode_changed.emit(mode))
		tools.add_child(b)
		_buttons[m[0]] = b
	var row := HBoxContainer.new()
	box.add_child(row)
	_radius_label = Label.new()
	row.add_child(_radius_label)
	var slider := HSlider.new()
	slider.min_value = 20.0
	slider.max_value = 2500.0
	slider.step = 10.0
	slider.value = radius_km
	slider.custom_minimum_size = Vector2(160, 0)
	slider.value_changed.connect(func(v: float) -> void:
		radius_km = v
		_show_radius()
		radius_changed.emit(v))
	row.add_child(slider)
	var land := CheckBox.new()
	land.text = "Só em terra"
	land.tooltip_text = "Pinta só onde a altitude é de terra: a costa do país segue a costa do mapa."
	land.button_pressed = land_only
	land.toggled.connect(func(on: bool) -> void:
		land_only = on
		land_only_changed.emit(on))
	box.add_child(land)
	_tip = Label.new()
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tip.custom_minimum_size = Vector2(280, 0)
	_tip.modulate = Color(1, 1, 1, 0.75)
	_tip.text = TIPS[mode]
	box.add_child(_tip)
	_area = Label.new()
	box.add_child(_area)
	var done := Button.new()
	done.text = "Terminar"
	done.pressed.connect(func() -> void: finish_requested.emit())
	box.add_child(done)
	_show_radius()


## Abre a barra para o país, com a área que ele já tem.
func show_state(country_name: String, area_km2: float) -> void:
	visible = true
	_title.text = "Pintando território: %s" % country_name
	set_area(area_km2)


func set_area(area_km2: float) -> void:
	_area.text = "Território: ≈ %s km²" % LayerPanel._thousands(roundi(area_km2)) if area_km2 > 0.0 else "Ainda sem território."


func hide_panel() -> void:
	visible = false


func _show_radius() -> void:
	_radius_label.text = "Raio %d km  " % roundi(radius_km)


func _unhandled_key_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		finish_requested.emit()
		get_viewport().set_input_as_handled()
