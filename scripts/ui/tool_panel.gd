extends PanelContainer
## A barra superior, em toda a largura (48 px): a marca, o menu do mundo e o estado da gravação; os modos (Navegar, Território, Relevo);
## desfazer e refazer; e à direita o resumo do mundo, a busca, a configuração e a ajuda. A placa da data (TimeBar) pende dela, ao centro.
## Os pincéis e os controles do relevo ficam na barra de edição de baixo (edit_bar), que só aparece com uma ferramenta ativa.
## Só mostra e pede: avisa por sinais, e a pilha de comandos diz o que dá para desfazer.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")
const TerrainBrush = preload("res://scripts/edit/terrain_brush.gd")
const SunCrest = preload("res://scripts/ui/sun_crest.gd")

signal tool_selected(op: int)  # -1 = navegar; senão TerrainBrush.Op
signal territory_requested     # o modo Território: pintar o cadastro aberto na ficha
signal radius_changed(km: float)
signal strength_changed(value: float)
signal roughness_changed(value: float)
signal undo_requested
signal redo_requested
signal export_requested
signal import_requested
signal search_requested        # a caixa de busca: abre o Índice na aba Busca
signal config_requested(which: String)  # "tipos", "regras" ou "calendarios"
signal help_requested
signal resources_toggled(open: bool)  # o painel de recursos

const NAVIGATE := -1
const HEIGHT := 48
const BRUSH_ICONS := ["raise", "lower", "level", "smooth", "mountains", "erosion", "valley"]

var radius: HSlider
var strength: HSlider
var roughness: HSlider
var edit_bar: PanelContainer  # embaixo, ao centro: o main a põe no HUD
var _buttons: Array[Button] = []
var _undo: Button
var _redo: Button
var _radius_label: Label
var _strength_label: Label
var _roughness_label: Label
var _terrain_toggle: Button
var _territory_toggle: Button
var _navigate: Button
var resources_toggle: Button
var _saved: Label
var _counts: Label
var _workspace: HBoxContainer
var _territory_active := false


func _init(radius_km: float, strength_m: float, roughness_value := 0.5) -> void:
	add_theme_stylebox_override("panel", UiKit.bar_style(SIDE_BOTTOM))
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, HEIGHT)
	offset_bottom = HEIGHT
	_workspace = HBoxContainer.new()
	_workspace.add_theme_constant_override("separation", 8)
	add_child(_workspace)
	var logo := SunCrest.new()
	logo.custom_minimum_size = Vector2(30, 30)
	logo.color = UiKit.BRASS
	_workspace.add_child(logo)
	var brand := Label.new()
	brand.text = "EVRON"
	brand.add_theme_font_size_override("font_size", 20)
	UiKit.style_heading(brand)
	_workspace.add_child(brand)
	var world := MenuButton.new()  # o mundo como um todo: exportar e importar a pasta .world
	world.text = "Mundo"
	world.icon = UiIcons.get_icon("chevron_down", 14)
	world.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	world.tooltip_text = "Exportar ou importar o mundo (uma pasta .world)"
	world.get_popup().add_item("Exportar mundo…", 0)
	world.get_popup().add_item("Importar mundo…", 1)
	world.get_popup().id_pressed.connect(func(id: int) -> void: (export_requested if id == 0 else import_requested).emit())
	_workspace.add_child(world)
	_saved = Label.new()
	_saved.add_theme_font_size_override("font_size", 13)
	_workspace.add_child(_saved)
	show_saved(true)
	_workspace.add_child(VSeparator.new())
	_navigate = _mode("Navegar", "navigate", "Navegar: girar, aproximar e selecionar · V")
	_navigate.button_pressed = true
	_navigate.pressed.connect(func() -> void: tool_selected.emit(NAVIGATE))
	_territory_toggle = _mode("Território", "territory", "Território: pintar o país, a província ou a área aberta na ficha · T")
	_territory_toggle.toggled.connect(func(open: bool) -> void:
		if open:
			territory_requested.emit()
		else:
			tool_selected.emit(NAVIGATE))
	_terrain_toggle = _mode("Relevo", "relief", "Relevo: esculpir montanhas, vales e erosão · R")
	_terrain_toggle.toggled.connect(func(open: bool) -> void:
		if open:
			tool_selected.emit(0)
		else:
			tool_selected.emit(NAVIGATE))
	_undo = _icon_button("undo", "Desfazer", undo_requested)
	_redo = _icon_button("redo", "Refazer", redo_requested)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace.add_child(spacer)
	_counts = Label.new()
	_counts.add_theme_font_size_override("font_size", 13)
	_counts.add_theme_color_override("font_color", UiKit.MUTED)
	_workspace.add_child(_counts)
	resources_toggle = Button.new()
	resources_toggle.text = "Recursos"
	resources_toggle.toggle_mode = true
	resources_toggle.tooltip_text = "Catálogo de recursos e ocorrências no mapa"
	resources_toggle.toggled.connect(func(open: bool) -> void: resources_toggled.emit(open))
	_workspace.add_child(resources_toggle)
	var search := Button.new()
	search.text = "Buscar…            Ctrl F"
	search.icon = UiIcons.get_icon("search", 16)
	search.alignment = HORIZONTAL_ALIGNMENT_LEFT
	search.custom_minimum_size = Vector2(250, 0)
	search.tooltip_text = "Buscar entidades, lugares e nomes · Ctrl+F"
	search.pressed.connect(func() -> void: search_requested.emit())
	_workspace.add_child(search)
	var config := MenuButton.new()  # tipos, regras e calendários: o que configura o mundo
	config.icon = UiIcons.get_icon("gear", 18)
	config.tooltip_text = "Configuração do mundo: tipos, regras e calendários"
	for item in [["Tipos, campos e vínculos…", "tipos"], ["Regras…", "regras"], ["Calendários…", "calendarios"]]:
		config.get_popup().add_item(item[0])
		config.get_popup().set_item_metadata(config.get_popup().item_count - 1, item[1])
	config.get_popup().index_pressed.connect(func(i: int) -> void: config_requested.emit(config.get_popup().get_item_metadata(i)))
	_workspace.add_child(config)
	var help := Button.new()
	help.icon = UiIcons.get_icon("help", 18)
	help.tooltip_text = "Atalhos e ajuda · F1"
	help.pressed.connect(func() -> void: help_requested.emit())
	_workspace.add_child(help)
	_build_edit_bar(radius_km, strength_m, roughness_value)
	_show_values()
	show_history(false, false, "", "")


## Um modo da barra: botão de alternância com ícone e nome.
func _mode(label: String, icon_name: String, tip: String) -> Button:
	var b := Button.new()
	b.text = label
	b.icon = UiIcons.get_icon(icon_name, 16)
	b.tooltip_text = tip
	b.toggle_mode = true
	_workspace.add_child(b)
	return b


func _icon_button(icon_name: String, tip: String, signal_to: Signal) -> Button:
	var b := Button.new()
	b.icon = UiIcons.get_icon(icon_name, 18)
	b.tooltip_text = tip
	b.flat = true
	b.pressed.connect(signal_to.emit)
	_workspace.add_child(b)
	return b


## A barra de edição do relevo: os sete pincéis (ícone e nome) e os três controles, embaixo ao centro.
func _build_edit_bar(radius_km: float, strength_m: float, roughness_value: float) -> void:
	edit_bar = PanelContainer.new()
	edit_bar.add_theme_stylebox_override("panel", UiKit.panel_style())
	edit_bar.visible = false
	edit_bar.resized.connect(func() -> void: edit_bar.size = edit_bar.get_combined_minimum_size())  # o Main a põe no lugar (_layout)
	var box := VBoxContainer.new()
	edit_bar.add_child(box)
	var title := Label.new()
	title.text = "RELEVO"
	UiKit.style_heading(title)
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var group := ButtonGroup.new()
	for item in _brush_items():
		var b := Button.new()
		b.text = item[1]
		b.tooltip_text = "%s · %d" % [item[1], item[0] + 1]
		b.icon = UiIcons.get_icon(BRUSH_ICONS[item[0]], 20)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = item[0] == NAVIGATE
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.custom_minimum_size = Vector2(78, 54)
		b.pressed.connect(tool_selected.emit.bind(item[0]))
		b.set_meta("op", item[0])
		row.add_child(b)
		_buttons.append(b)
	row.add_child(VSeparator.new())
	var sliders := VBoxContainer.new()
	row.add_child(sliders)
	for spec in [["radius", 20.0, 1000.0, 10.0, radius_km, radius_changed], ["strength", 10.0, 1000.0, 10.0, strength_m, strength_changed],
			["roughness", 0.0, 1.0, 0.05, roughness_value, roughness_changed]]:
		var line := HBoxContainer.new()
		sliders.add_child(line)
		var label := Label.new()
		label.custom_minimum_size = Vector2(150, 0)
		set("_%s_label" % spec[0], label)
		set(spec[0], _add_slider(line, label, spec[1], spec[2], spec[3], spec[4], spec[5]))


## Marca a ferramenta atual, sem repetir o evento.
func show_tool(op: int) -> void:
	_navigate.set_pressed_no_signal(op == NAVIGATE and not _territory_active)
	_territory_toggle.set_pressed_no_signal(_territory_active)
	_terrain_toggle.set_pressed_no_signal(op != NAVIGATE)
	edit_bar.visible = op != NAVIGATE
	for b in _buttons:
		b.set_pressed_no_signal(b.get_meta("op") == op)


func show_territory_editing(active: bool) -> void:
	_territory_active = active
	show_tool(NAVIGATE)


## "Salvo" ou "Alterações pendentes" (o Main avisa depois de gravar e quando algo muda).
func show_saved(saved: bool) -> void:
	_saved.text = "● Salvo" if saved else "● Alterações pendentes"
	_saved.add_theme_color_override("font_color", Color("#7fb37a") if saved else Color("#e3a33b"))


## O resumo do mundo ("4 países · 31 cadastros").
func show_counts(text: String) -> void:
	_counts.text = text


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
	_strength_label.text = "Intensidade %d" % roundi(strength.value)
	_roughness_label.text = "Rugosidade %d%%" % roundi(roughness.value * 100.0)
	roughness.tooltip_text = "Quanto o ruído manda na forma. Elevar/Rebaixar/Nivelar: de liso a irregular. Montanhas: de maciço arredondado a cristas finas."
	strength.tooltip_text = "Elevar/rebaixar: metros por marca no centro. Nivelar/suavizar: força (1000 = máxima)."


func _add_slider(box: Container, label: Label, lo: float, hi: float, step: float, value: float, changed: Signal) -> HSlider:
	box.add_child(label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(130, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void:
		_show_values()
		changed.emit(v))
	box.add_child(s)
	return s
