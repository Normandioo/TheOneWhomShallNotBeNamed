extends PanelContainer
## Painel da esquerda: controles de terraformação, o que a simulação resultou, modo de mapa e a região escolhida.
## Só mostra e pede: os valores vivem no PlanetState, e este painel avisa por sinais quando o jogador mexe.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const MapLegends = preload("res://scripts/ui/map_legends.gd")

## O jogador moveu um slider.
signal control_changed(param: String, value: float)
signal map_mode_selected(mode: int)
signal found_requested

const CONTROLS := [["Temperatura", "temperature"], ["Atmosfera", "atmosphere"], ["Água total (H₂O)", "h2o"]]

var _sliders := {}  # param -> HSlider
var _liquid_bar: ProgressBar
var _ice_bar: ProgressBar
var _vapor_bar: ProgressBar
var _veg_bar: ProgressBar
var _info: Label
var _found_btn: Button


func _init() -> void:
	position = Vector2(12, 12)
	custom_minimum_size = Vector2(260, 0)
	add_theme_stylebox_override("panel", UiKit.panel_style())
	var box := VBoxContainer.new()
	add_child(box)

	for c in CONTROLS:
		var label := Label.new()
		label.text = c[0]
		box.add_child(label)
		var slider := HSlider.new()
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value_changed.connect(_on_slider.bind(c[1]))
		_sliders[c[1]] = slider
		box.add_child(slider)

	# Resultado da simulação: só leitura.
	_liquid_bar = UiKit.add_bar(box, "Água líquida")
	_ice_bar = UiKit.add_bar(box, "Gelo")
	_vapor_bar = UiKit.add_bar(box, "Vapor")
	_veg_bar = UiKit.add_bar(box, "Vegetação")

	box.add_child(HSeparator.new())
	var modes := OptionButton.new()
	for m in MapLegends.MODES:
		modes.add_item(m["menu"])
	modes.item_selected.connect(map_mode_selected.emit)
	box.add_child(modes)

	box.add_child(HSeparator.new())
	_info = Label.new()
	_info.text = "Clique no planeta para selecionar uma região."
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_info)
	_found_btn = _add_button(box, "Fundar colônia aqui", found_requested.emit)


## Põe o slider no valor do planeta, sem repetir o evento.
func set_control_value(param: String, value: float) -> void:
	_sliders[param].set_value_no_signal(value)


func set_control_max(param: String, max_value: float) -> void:
	_sliders[param].max_value = max_value


func control_value(param: String) -> float:
	return _sliders[param].value


func control_max(param: String) -> float:
	return _sliders[param].max_value


func show_water(liquid: float, ice: float, vapor: float, vegetation: float) -> void:
	_liquid_bar.value = liquid
	_ice_bar.value = ice
	_vapor_bar.value = vapor
	_veg_bar.value = vegetation


## Texto da região escolhida e quais ações ela permite.
func show_selection(text: String, can_found: bool) -> void:
	_info.text = text
	_found_btn.disabled = not can_found


func _on_slider(value: float, param: String) -> void:
	control_changed.emit(param, value)


func _add_button(box: Container, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = true
	b.pressed.connect(on_pressed)
	box.add_child(b)
	return b
