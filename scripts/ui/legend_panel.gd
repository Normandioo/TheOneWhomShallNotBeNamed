extends PanelContainer
## Legenda da camada atual, no canto inferior esquerdo: o que as cores significam.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

const WIDTH := 260

var _title: Label
var _body: VBoxContainer
var _text: Label
var _stale: Label


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(WIDTH, 150)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_title = Label.new()
	UiKit.style_heading(_title)
	_title.add_theme_font_size_override("font_size", 16)
	box.add_child(_title)
	_body = VBoxContainer.new()
	box.add_child(_body)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_text.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_text)
	_stale = Label.new()
	_stale.text = "Terreno editado: esta camada é do mapa original e não acompanha o relevo novo."
	_stale.autowrap_mode = TextServer.AUTOWRAP_WORD
	_stale.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	_stale.visible = false
	box.add_child(_stale)


## `data` é uma entrada de MapLayers.LAYERS.
func show_layer(data: Dictionary) -> void:
	_title.text = data["title"]
	_text.text = data["text"]
	for c in _body.get_children():
		c.queue_free()
	for item in data.get("items", []):
		_add_swatch(item[0], item[1])
	if data.has("gradient"):
		_add_gradient(data["gradient"][0], data["gradient"][1], data["labels"])


func _add_swatch(color: Color, text: String) -> void:
	var row := HBoxContainer.new()
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(16, 16)
	row.add_child(swatch)
	var label := Label.new()
	label.text = " " + text
	row.add_child(label)
	_body.add_child(row)


func _add_gradient(offsets: Array, colors: Array, labels: Array) -> void:
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array(offsets)
	gr.colors = PackedColorArray(colors)
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	gt.width = WIDTH
	var bar := TextureRect.new()
	bar.texture = gt
	bar.custom_minimum_size = Vector2(WIDTH, 14)
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	_body.add_child(bar)
	var row := HBoxContainer.new()
	var aligns := [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT]
	for k in 3:
		var l := Label.new()
		l.text = labels[k]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = aligns[k]
		row.add_child(l)
	_body.add_child(row)


## Avisa que a camada ficou desatualizada em relação ao terreno editado (a proposta pede marcar os derivados).
func show_stale(on: bool) -> void:
	_stale.visible = on
