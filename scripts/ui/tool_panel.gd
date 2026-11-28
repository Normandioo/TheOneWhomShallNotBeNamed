extends PanelContainer
## As ferramentas e os comandos do mundo. Este painel é a barra de baixo ao centro (Navegar, Território, Relevo, desfazer e refazer);
## ele monta também o bloco do alto à direita (world_block: o tempo, a busca, os Registros e o menu Mundo), o par "salvo / contagem" que
## vai para a barra de estado (status_items) e a barra dos pincéis de relevo (edit_bar), que só aparece com a ferramenta ativa.
## Só mostra e pede: avisa por sinais, e a pilha de comandos diz o que dá para desfazer.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")
const TerritoryEditor = preload("res://scripts/app/territory_editor.gd")
const TerrainBrush = preload("res://scripts/edit/terrain_brush.gd")

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
signal relief_tutorial_requested  # o botão "?" da barra de relevo
signal data_paint_requested(level: String, category: int)  # pintar lagos ou biomas (TerritoryEditor.DATA_LEVELS)
signal registry_requested      # o botão Registros: abre ou fecha a árvore de todos os cadastros
signal resources_toggled(open: bool)  # o painel de recursos
signal settlements_toggled(open: bool)  # o painel dos povoados (produção)

const NAVIGATE := -1
const BLOCK_WIDTH := 500
const BRUSH_ICONS := ["raise", "lower", "level", "smooth", "mountains", "erosion", "valley", "geology", "hydrology"]

var radius: HSlider
var strength: HSlider
var roughness: HSlider
var edit_bar: PanelContainer  # embaixo, ao centro: o main a põe no HUD
var world_block: PanelContainer  # no alto à direita: o main o põe no HUD
var status_items: HBoxContainer  # "salvo" e a contagem: o main põe na barra de estado
var time_slot: VBoxContainer     # onde a barra de tempo é encaixada, no alto do world_block
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
var settlements_toggle: Button
var _saved: Label
var _counts: Label
var _workspace: HBoxContainer
var _territory_active := false


func _init(radius_km: float, strength_m: float, roughness_value := 0.5) -> void:
	add_theme_stylebox_override("panel", UiKit.metal_style(Color("#1b262a"), 6, 5))
	resized.connect(func() -> void: size = get_combined_minimum_size())
	_workspace = HBoxContainer.new()
	_workspace.add_theme_constant_override("separation", 4)
	add_child(_workspace)
	_navigate = _mode("Navegar", "navigate", "Navegar: girar, aproximar e selecionar · V")
	_navigate.button_pressed = true
	_navigate.pressed.connect(func() -> void: tool_selected.emit(NAVIGATE))
	_territory_toggle = _mode("Território", "territory", "Território: pintar o país, a subdivisão ou a área selecionada · T")
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
	_workspace.add_child(VSeparator.new())
	_undo = _icon_button("undo", "Desfazer", undo_requested)
	_redo = _icon_button("redo", "Refazer", redo_requested)
	# Os painéis de recursos e de povoados são abertos pelas categorias do alto; estes botões escondidos guardam o estado deles.
	resources_toggle = _hidden_toggle(resources_toggled)
	settlements_toggle = _hidden_toggle(settlements_toggled)
	_build_world_block()
	_build_status()
	_build_edit_bar(radius_km, strength_m, roughness_value)
	_show_values()
	show_history(false, false, "", "")


func _hidden_toggle(signal_to: Signal) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.visible = false
	b.toggled.connect(func(open: bool) -> void: signal_to.emit(open))
	add_child(b)
	return b


func _build_world_block() -> void:
	world_block = PanelContainer.new()
	world_block.add_theme_stylebox_override("panel", UiKit.metal_style(Color("#1b262a"), 8, 6))
	world_block.custom_minimum_size = Vector2(BLOCK_WIDTH, 0)
	world_block.resized.connect(func() -> void: world_block.size = world_block.get_combined_minimum_size())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	world_block.add_child(box)
	time_slot = VBoxContainer.new()
	box.add_child(time_slot)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var search := Button.new()
	search.text = "Buscar…    Ctrl F"
	search.icon = UiIcons.get_icon("search", 16)
	search.alignment = HORIZONTAL_ALIGNMENT_LEFT
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.clip_text = true
	search.tooltip_text = "Buscar entidades, lugares e nomes · Ctrl+F"
	search.pressed.connect(func() -> void: search_requested.emit())
	row.add_child(search)
	var registry := Button.new()
	registry.text = "Registros"
	registry.tooltip_text = "Todos os cadastros do mundo, por tipo · O"
	registry.pressed.connect(func() -> void: registry_requested.emit())
	row.add_child(registry)
	var world := MenuButton.new()  # o mundo como um todo: o que o configura, exportar e importar
	world.text = "Mundo"
	world.flat = false
	world.icon = UiIcons.get_icon("chevron_down", 14)
	world.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	world.tooltip_text = "Opções, tipos, regras, calendários, exportar e importar o mundo"
	var popup := world.get_popup()
	for item in [["Opções…", "opcoes"], ["Tipos, campos e vínculos…", "tipos"], ["Regras…", "regras"], ["Calendários…", "calendarios"], ["Exportar mundo…", "exportar"], ["Importar mundo…", "importar"]]:
		if item[1] == "exportar":
			popup.add_separator()
		popup.add_item(item[0])
		popup.set_item_metadata(popup.item_count - 1, item[1])
	popup.index_pressed.connect(func(i: int) -> void:
		var key: String = popup.get_item_metadata(i)
		if key == "exportar":
			export_requested.emit()
		elif key == "importar":
			import_requested.emit()
		else:
			config_requested.emit(key))
	row.add_child(world)
	var help := Button.new()
	help.icon = UiIcons.get_icon("help", 18)
	help.tooltip_text = "Ajuda e tutoriais de cada menu (F1: atalhos)"
	help.pressed.connect(func() -> void: help_requested.emit())
	row.add_child(help)


func _build_status() -> void:
	status_items = HBoxContainer.new()
	status_items.add_theme_constant_override("separation", 16)
	_saved = Label.new()
	_saved.add_theme_font_size_override("font_size", 13)
	status_items.add_child(_saved)
	_counts = Label.new()
	_counts.add_theme_font_size_override("font_size", 13)
	_counts.add_theme_color_override("font_color", UiKit.MUTED)
	status_items.add_child(_counts)
	show_saved(true)


## Um modo da barra: botão de alternância com ícone e nome.
func _mode(label: String, icon_name: String, tip: String) -> Button:
	var b := Button.new()
	b.text = label
	b.icon = UiIcons.get_icon(icon_name, 16)
	UiKit.tint_icon(b, icon_name)
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
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "RELEVO"
	UiKit.style_heading(title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var help := Button.new()
	help.text = "?"
	help.custom_minimum_size = Vector2(28, 24)
	help.tooltip_text = "Ver como funciona o relevo"
	help.pressed.connect(func() -> void: relief_tutorial_requested.emit())
	head.add_child(help)
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
	var data := VBoxContainer.new()  # lagos e biomas: dados pintados (não mudam a altitude), com o pincel do território
	row.add_child(data)
	for level in ["lago", "bioma"]:
		var line := HBoxContainer.new()
		data.add_child(line)
		var pick := OptionButton.new()
		pick.fit_to_longest_item = false
		pick.custom_minimum_size.x = 150
		pick.tooltip_text = "A categoria a pintar"
		for c in TerritoryEditor.DATA_LEVELS[level]:
			pick.add_item(c.name, int(c.id))
		line.add_child(pick)
		var go := Button.new()
		go.text = "Pintar lagos" if level == "lago" else "Pintar biomas"
		go.icon = UiIcons.get_icon("hydrology" if level == "lago" else "ecology", 18)
		go.tooltip_text = "Abre o pincel do território na camada dos %s (Terminar ou Esc volta)" % ("lagos" if level == "lago" else "biomas")
		go.pressed.connect(func() -> void: data_paint_requested.emit(level, pick.get_selected_id()))
		line.add_child(go)
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
