extends PanelContainer
## A barra de estado, embaixo em toda a largura: a leitura do cursor (lat/lon, altitude, camada) e a altura da câmera.
## Só mostra: quem decide o texto é o Main.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")  # só para o separador de milhares

const HEIGHT := 30  # os painéis de baixo sobem esta altura

var _cursor: Label
var _camera: Label
var _row: HBoxContainer


func _init() -> void:
	var bar := UiKit.panel_style()
	bar.set_corner_radius_all(0)
	bar.border_width_top = 1
	bar.content_margin_top = 3
	bar.content_margin_bottom = 3
	add_theme_stylebox_override("panel", bar)
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	_row = row
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	_cursor = Label.new()
	_cursor.text = "Passe o mouse sobre o planeta."
	_cursor.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_cursor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cursor.add_theme_font_size_override("font_size", 13)
	row.add_child(_cursor)
	_camera = Label.new()
	_camera.add_theme_font_size_override("font_size", 13)
	_camera.modulate = Color(1, 1, 1, 0.6)
	row.add_child(_camera)


## Encaixa no começo da barra o que o mundo informa sempre (salvo e contagem).
func add_leading(node: Control) -> void:
	_row.add_child(node)
	_row.move_child(node, 0)


## O texto do Main vem em várias linhas; aqui fica numa só.
func show_cursor(text: String) -> void:
	var line := text.replace("\n", "  ·  ")
	if line != _cursor.text:
		_cursor.text = line


func show_camera_altitude(km: float) -> void:
	_camera.text = "Câmera a %s km do chão" % LayerPanel._thousands(roundi(km))
