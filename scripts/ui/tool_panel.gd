extends PanelContainer
## Barra de ferramentas, no topo ao centro: navegar ou um pincel de terreno, raio, intensidade, desfazer e refazer.
## Só mostra e pede: avisa por sinais, e a pilha de comandos diz o que dá para desfazer.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const TerrainBrush = preload("res://scripts/edit/terrain_brush.gd")

signal tool_selected(op: int)  # -1 = navegar; senão TerrainBrush.Op
signal radius_changed(km: float)
signal strength_changed(value: float)
signal roughness_changed(value: float)
signal undo_requested
signal redo_requested

const NAVIGATE := -1

var radius: HSlider
var strength: HSlider
var roughness: HSlider
var _buttons: Array[Button] = []
var _undo: Button
var _redo: Button
var _radius_label: Label
var _strength_label: Label
var _roughness_label: Label
var _terrain_deck: VBoxContainer
var _terrain_toggle: Button
var _navigate: Button
var _workspace: HBoxContainer
var _territory_status: Label


func _init(radius_km: float, strength_m: float, roughness_value := 0.5) -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style())
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_left = 12
	offset_right = -12
	offset_top = 12
	var box := VBoxContainer.new()
	add_child(box)
	_workspace = HBoxContainer.new()
	_workspace.add_theme_constant_override("separation", 8)
	box.add_child(_workspace)
	var brand := Label.new()
	brand.text = "Evron"
	brand.add_theme_font_size_override("font_size", 24)
	UiKit.style_heading(brand)
	_workspace.add_child(brand)
	_workspace.add_child(VSeparator.new())
	_navigate = _command(_workspace, "Navegar", "navigate")
	_navigate.toggle_mode = true
	_navigate.button_pressed = true
	_navigate.pressed.connect(func() -> void: tool_selected.emit(NAVIGATE))
	_terrain_toggle = _command(_workspace, "Terreno", "terrain")
	_terrain_toggle.toggle_mode = true
	_terrain_toggle.toggled.connect(func(open: bool) -> void:
		if open:
			tool_selected.emit(0)
		else:
			tool_selected.emit(NAVIGATE))
	_workspace.add_child(VSeparator.new())
	_undo = _add_button(_workspace, "Desfazer", undo_requested)
	_undo.icon = load("res://assets/ui/undo.png")
	_undo.text = ""
	_redo = _add_button(_workspace, "Refazer", redo_requested)
	_redo.icon = load("res://assets/ui/redo.png")
	_redo.text = ""
	_territory_status = Label.new()
	_territory_status.text = "Edição territorial"
	_territory_status.hide()
	_workspace.add_child(_territory_status)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace.add_child(spacer)

	_terrain_deck = VBoxContainer.new()
	_terrain_deck.hide()
	box.add_child(_terrain_deck)
	_terrain_deck.add_child(HSeparator.new())
	var tools := HBoxContainer.new()
	_terrain_deck.add_child(tools)
	var group := ButtonGroup.new()
	var icons := ["raise", "lower", "level", "smooth", "terrain", "erosion", "valley"]
	for item in _brush_items():
		var b := _command(tools, item[1], icons[item[0]])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = item[0] == NAVIGATE
		b.pressed.connect(tool_selected.emit.bind(item[0]))
		b.set_meta("op", item[0])
		_buttons.append(b)

	var sliders := HBoxContainer.new()
	_terrain_deck.add_child(sliders)
	_radius_label = Label.new()
	radius = _add_slider(sliders, _radius_label, 20.0, 1000.0, 10.0, radius_km, radius_changed)
	_strength_label = Label.new()
	strength = _add_slider(sliders, _strength_label, 10.0, 1000.0, 10.0, strength_m, strength_changed)
	_roughness_label = Label.new()
	roughness = _add_slider(sliders, _roughness_label, 0.0, 1.0, 0.05, roughness_value, roughness_changed)
	_show_values()
	show_history(false, false, "", "")


## Marca a ferramenta atual, sem repetir o evento.
func show_tool(op: int) -> void:
	_navigate.set_pressed_no_signal(op == NAVIGATE and not _territory_status.visible)
	_terrain_toggle.set_pressed_no_signal(op != NAVIGATE)
	_terrain_deck.visible = op != NAVIGATE
	offset_bottom = offset_top + get_combined_minimum_size().y
	for b in _buttons:
		b.set_pressed_no_signal(b.get_meta("op") == op)


func show_territory_editing(active: bool) -> void:
	_territory_status.visible = active
	show_tool(NAVIGATE)


func bind_panel(panel: Control, label: String, icon_name: String) -> void:
	var button := _command(_workspace, label, icon_name)
	button.toggle_mode = true
	button.set_pressed_no_signal(panel.visible)
	button.toggled.connect(func(open: bool) -> void: panel.visible = open)
	panel.visibility_changed.connect(func() -> void: button.set_pressed_no_signal(panel.visible))


func _command(row: Container, label: String, icon_name: String) -> Button:
	var button := Button.new()
	button.text = label
	button.tooltip_text = label
	button.icon = load("res://assets/ui/%s.png" % icon_name)
	row.add_child(button)
	return button


func show_history(can_undo: bool, can_redo: bool, undo_name: String, redo_name: String) -> void:
	_undo.disabled = not can_undo
	_redo.disabled = not can_redo
	_undo.tooltip_text = ("Desfazer: " + undo_name + " (Ctrl+Z)") if can_undo else "Nada para desfazer"
	_redo.tooltip_text = ("Refazer: " + redo_name + " (Ctrl+Y)") if can_redo else "Nada para refazer"


func _brush_items() -> Array:
	var items := []
	for op in TerrainBrush.NAMES.size():
		items.append([op, TerrainBrush.NAMES[op]])
	return items


func _show_values() -> void:
	_radius_label.text = "Raio %d km" % roundi(radius.value)
	_strength_label.text = "  Intensidade %d" % roundi(strength.value)
	_roughness_label.text = "  Rugosidade %d%%" % roundi(roughness.value * 100.0)
	roughness.tooltip_text = "Quanto o ruído manda na forma. Elevar/Rebaixar/Nivelar: de liso a irregular. Montanhas: de maciço arredondado a cristas finas."
	strength.tooltip_text = "Elevar/rebaixar: metros por marca no centro. Nivelar/suavizar: força (1000 = máxima)."


func _add_slider(box: Container, label: Label, lo: float, hi: float, step: float, value: float, changed: Signal) -> HSlider:
	box.add_child(label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(104, 0)
	s.value_changed.connect(func(v: float) -> void:
		_show_values()
		changed.emit(v))
	box.add_child(s)
	return s


func _add_button(box: Container, text: String, signal_to: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(signal_to.emit)
	box.add_child(b)
	return b
