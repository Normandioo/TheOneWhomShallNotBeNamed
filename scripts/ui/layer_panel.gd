extends PanelContainer
## Painel da esquerda: a escolha da camada e a leitura do ponto sob o cursor (e do ponto clicado).
## Só mostra e pede: avisa por sinal quando o usuário escolhe outra camada.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")

signal layer_selected(index: int)
signal political_visibility_changed(on: bool)

var layers: OptionButton
var _countries: CheckBox
var _cursor: Label
var _selection: Label
var _camera: Label
var _item_layer := {}  # índice do item no menu -> índice em MapLayers.LAYERS (os grupos ocupam itens)


func _init() -> void:
	position = Vector2(12, 12)
	custom_minimum_size = Vector2(260, 0)
	add_theme_stylebox_override("panel", UiKit.panel_style())
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Evron"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	layers = OptionButton.new()
	var group := ""
	for i in MapLayers.LAYERS.size():
		var l: Dictionary = MapLayers.LAYERS[i]
		if l["group"] != group:
			group = l["group"]
			layers.add_separator(group)
		_item_layer[layers.item_count] = i
		layers.add_item(l["menu"])
	layers.item_selected.connect(func(item: int) -> void: layer_selected.emit(_item_layer[item]))
	box.add_child(layers)
	_countries = CheckBox.new()
	_countries.text = "Mostrar países"
	_countries.button_pressed = true
	_countries.toggled.connect(political_visibility_changed.emit)
	box.add_child(_countries)

	box.add_child(HSeparator.new())
	_cursor = _add_label(box, "Passe o mouse sobre o planeta.")
	box.add_child(HSeparator.new())
	_selection = _add_label(box, "Clique para fixar um ponto.")
	_camera = _add_label(box, "")
	_camera.modulate = Color(1, 1, 1, 0.6)


## Marca a camada no menu, sem repetir o evento.
func show_layer(index: int) -> void:
	for item in _item_layer:
		if _item_layer[item] == index:
			layers.select(item)


func show_political(on: bool) -> void:
	_countries.set_pressed_no_signal(on)


func show_cursor(text: String) -> void:
	_cursor.text = text


func show_selection(text: String) -> void:
	_selection.text = text


func show_camera_altitude(km: float) -> void:
	_camera.text = "Câmera a %s km do chão" % _thousands(roundi(km))


static func _thousands(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if v < 0 else "") + s + out


func _add_label(box: Container, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(l)
	return l
