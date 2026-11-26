extends Control
## O menu de opções: uma janela no meio, sobre o mapa escurecido, com as seções à esquerda. Cada controle grava na hora no
## UserSettings (quem aplica é o Main). Os pedidos que não são uma opção (ver um tutorial, sair do jogo) saem por sinal.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")

signal tutorial_requested(key: String)  # "basico" ou a chave de uma ferramenta
signal quit_requested

const SIZE := Vector2(940, 720)
## [chave, nome, ícone]
const SECTIONS := [["tela", "Tela", "calendar"], ["controles", "Controles", "navigate"], ["mapa", "Mapa", "area"], ["jogo", "Jogo", "gear"], ["ajuda", "Ajuda", "help"],
	["cadastros", "Cadastros", "file"]]
const CONFIRM_WORD := "APAGAR"
const OPTIONS_NOTE := "Valem para este computador, não para o mundo"
const RECORDS_NOTE := "Atenção: esta seção altera o mundo aberto"
const DANGER := Color("#8c2f2a")
const SHORTCUTS := [["Arrastar", "Girar o globo"], ["Roda do mouse", "Aproximar e afastar"], ["Clique", "Selecionar um país"], ["V", "Navegar"],
	["T", "Pintar território"], ["R", "Esculpir o relevo"], ["O", "Abrir ou fechar os Registros"], ["Ctrl+F", "Buscar"],
	["Ctrl+Z / Ctrl+Y", "Desfazer e refazer"], ["Esc", "Fechar a janela, tirar a seleção, abrir as opções"], ["F1", "Atalhos"]]

var tutorial_groups: Array = []  # [[grupo, [[chave, nome]]]], dado por quem monta os tutoriais
var section_buttons := {}
var pages := {}
var controls := {}       # chave da opção -> o controle dela
var tutorial_buttons := {}  # chave do tutorial -> Button "Ver"
var _settings
var _panel: PanelContainer
var _syncing := false
var _header_note: Label
# Cadastros: o que apagar
var record_checks := {}      # tipo -> CheckBox
var loose_check: CheckBox
var delete_button: Button
var confirm_box: VBoxContainer
var confirm_text: Label
var confirm_edit: LineEdit
var confirm_button: Button
var result_label: Label
var _records                 # records_reset: o que há, os avisos e a exclusão
var _record_grid: GridContainer
var _confirm_card: PanelContainer
var _result_card: PanelContainer
var _backup_path := ""


func _init() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false  # a roda do mouse não aproxima o globo por trás do menu


func setup(settings, groups: Array, records = null) -> void:
	_settings = settings
	tutorial_groups = groups
	_records = records
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.03, 0.04, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.dock_style(SIDE_RIGHT, 0, 0))
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	_panel.add_child(root)
	_build_header(root)
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 0)
	root.add_child(middle)
	var nav := VBoxContainer.new()
	nav.custom_minimum_size.x = 200
	nav.add_theme_constant_override("separation", 6)
	middle.add_child(_pad(nav, 12, 16))
	var group := ButtonGroup.new()
	var stack := MarginContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(_pad(stack, 20, 16))
	stack.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for spec in SECTIONS:
		var key: String = spec[0]
		var b := Button.new()
		b.text = spec[1]
		b.icon = UiIcons.get_icon(spec[2], 20)
		UiKit.tint_icon(b, spec[2])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size.y = 44
		b.pressed.connect(show_section.bind(key))
		nav.add_child(b)
		section_buttons[key] = b
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		stack.add_child(scroll)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 8)
		scroll.add_child(box)
		pages[key] = scroll
		call("_build_" + key, box)
	_build_footer(root)
	resized.connect(_center)
	show_section("tela")


func open(section := "") -> void:
	if _settings == null:
		return
	sync()
	if section != "":
		show_section(section)
	visible = true
	move_to_front()
	_center()


func close() -> void:
	visible = false


func show_section(key: String) -> void:
	if key == "cadastros" and pages.has(key) and not pages[key].visible:
		refresh_records()
	if _header_note != null:
		_header_note.text = RECORDS_NOTE if key == "cadastros" else OPTIONS_NOTE
	for k in pages:
		pages[k].visible = k == key
		section_buttons[k].set_pressed_no_signal(k == key)


## Põe nos controles o que está nas opções.
func sync() -> void:
	_syncing = true
	for key in controls:
		var c = controls[key]
		var v = _settings.value(key)
		if c is CheckBox:
			c.button_pressed = v
		elif c is HSlider:
			c.value = float(v) * 100.0
		elif c is OptionButton:
			for i in c.item_count:
				if c.get_item_metadata(i) == v:
					c.select(i)
	_syncing = false


func _center() -> void:
	if _panel == null:
		return
	var wanted := Vector2(minf(SIZE.x, size.x - 24.0), minf(SIZE.y, size.y - 24.0))
	_panel.size = wanted
	_panel.position = ((size - wanted) / 2.0).floor()


func _input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _build_header(root: VBoxContainer) -> void:
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", UiKit.banner_style(Color("#c98a82")))
	root.add_child(banner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	banner.add_child(row)
	var title := Label.new()
	title.text = "Opções"
	UiKit.style_heading(title)
	title.add_theme_color_override("font_color", UiKit.PAPER)
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var note := Label.new()
	_header_note = note
	note.text = OPTIONS_NOTE
	note.add_theme_font_size_override("font_size", 13)
	note.modulate = Color(1, 1, 1, 0.75)
	row.add_child(note)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.tooltip_text = "Fechar as opções (Esc)"
	x.pressed.connect(close)
	row.add_child(x)


func _build_footer(root: VBoxContainer) -> void:
	root.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	root.add_child(_pad(row, 16, 10))
	var restore := Button.new()
	restore.text = "Restaurar padrões"
	restore.pressed.connect(func() -> void:
		_settings.restore_defaults()
		sync())
	row.add_child(restore)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var quit := Button.new()
	quit.text = "Sair do jogo"
	quit.tooltip_text = "Salva o mundo e fecha o Evron"
	quit.pressed.connect(func() -> void: quit_requested.emit())
	row.add_child(quit)
	var back := Button.new()
	back.text = "Voltar ao mapa"
	back.add_theme_stylebox_override("normal", UiKit.active_style())
	back.pressed.connect(close)
	row.add_child(back)


# --- seções -----------------------------------------------------------------------------------------------------------

func _build_tela(box: VBoxContainer) -> void:
	_choice(box, "window_mode", "Modo da janela", "", [["Maximizada", "maximizada"], ["Tela cheia", "cheia"], ["Janela", "janela"]])
	_choice(box, "ui_scale", "Tamanho da interface", "Botões e textos maiores ou menores", [["90%", 0.9], ["100%", 1.0], ["115%", 1.15], ["130%", 1.3]])
	_choice(box, "max_fps", "Limite de quadros por segundo", "Menos quadros esquentam menos o computador", [["30", 30], ["60", 60], ["120", 120], ["Sem limite", 0]])
	_check(box, "vsync", "Sincronização vertical (VSync)", "")


func _build_controles(box: VBoxContainer) -> void:
	_slider(box, "orbit_speed", "Velocidade de giro do globo")
	_slider(box, "zoom_speed", "Velocidade do zoom")
	_heading(box, "Atalhos")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 3)
	for pair in SHORTCUTS:
		var key := Label.new()
		key.text = pair[0]
		key.add_theme_color_override("font_color", Color("#f2c46d"))
		grid.add_child(key)
		var what := Label.new()
		what.text = pair[1]
		grid.add_child(what)
	_card(box).add_child(grid)


func _build_mapa(box: VBoxContainer) -> void:
	_check(box, "remember_overlays", "Lembrar as sobreposições", "Legenda, nomes dos países, rios e área ligada voltam como você deixou")
	_check(box, "remember_map", "Abrir no último modo de mapa usado", "")


func _build_jogo(box: VBoxContainer) -> void:
	_choice(box, "autosave_seconds", "Salvar automaticamente", "", [["A cada 30 segundos", 30], ["A cada 1 minuto", 60], ["A cada 5 minutos", 300]])
	_check(box, "remember_hud", "Lembrar o alto da tela minimizado", "")
	_check(box, "tooltips", "Dicas ao passar o mouse", "")


func _build_ajuda(box: VBoxContainer) -> void:
	_check(box, "offer_tool_tutorials", "Oferecer o tutorial na primeira vez que abrir cada menu", "Durante o tutorial o jogo continua valendo: dá para experimentar")
	for group in tutorial_groups:
		_heading(box, group[0])
		for t in group[1]:
			_tutorial_row(box, t[0], t[1], "")


# --- cadastros ---------------------------------------------------------------------------------------------------------

func _build_cadastros(box: VBoxContainer) -> void:
	_heading(box, "Apagar cadastros")
	var note := Label.new()
	note.text = "Marque o que apagar. Antes de apagar qualquer coisa, o jogo guarda uma cópia do mundo."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 8)
	box.add_child(quick)
	for spec in [["Marcar tudo", true], ["Desmarcar tudo", false]]:
		var b := Button.new()
		b.text = spec[0]
		var on: bool = spec[1]
		b.pressed.connect(func() -> void: _mark_all(on))
		quick.add_child(b)
	_record_grid = GridContainer.new()
	_record_grid.columns = 2
	_record_grid.add_theme_constant_override("h_separation", 24)
	_card(box).add_child(_record_grid)
	loose_check = CheckBox.new()
	loose_check.toggled.connect(func(_on: bool) -> void: _selection_changed())
	_card(box).add_child(loose_check)
	delete_button = Button.new()
	delete_button.text = "Apagar os marcados…"
	delete_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	delete_button.custom_minimum_size.y = 36
	delete_button.pressed.connect(_ask_confirmation)
	box.add_child(delete_button)

	_confirm_card = _card(box)
	confirm_box = VBoxContainer.new()
	confirm_box.add_theme_constant_override("separation", 8)
	_confirm_card.add_child(confirm_box)
	confirm_text = Label.new()
	confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_box.add_child(confirm_text)
	confirm_edit = LineEdit.new()
	confirm_edit.placeholder_text = "digite %s para confirmar" % CONFIRM_WORD
	confirm_edit.text_changed.connect(func(t: String) -> void: confirm_button.disabled = t.strip_edges() != CONFIRM_WORD)
	confirm_box.add_child(confirm_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	confirm_box.add_child(row)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.pressed.connect(func() -> void: _confirm_card.hide())
	row.add_child(cancel)
	confirm_button = Button.new()
	confirm_button.text = "Apagar definitivamente"
	var danger := UiKit.active_style()
	danger.bg_color = DANGER
	confirm_button.add_theme_stylebox_override("normal", danger)
	confirm_button.pressed.connect(_delete_marked)
	row.add_child(confirm_button)

	_result_card = _card(box)
	var result_box := VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 8)
	_result_card.add_child(result_box)
	result_label = Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY  # o caminho da cópia é comprido
	result_box.add_child(result_label)
	var folder := Button.new()
	folder.text = "Abrir a pasta das cópias"
	folder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	folder.pressed.connect(func() -> void:
		if _backup_path != "":
			OS.shell_open(_backup_path.get_base_dir()))
	result_box.add_child(folder)
	_confirm_card.hide()
	_result_card.hide()


## Relê as contagens (ao abrir a seção e depois de apagar); nada fica marcado.
func refresh_records() -> void:
	if _records == null or _record_grid == null:
		return
	for c in _record_grid.get_children():
		_record_grid.remove_child(c)
		c.queue_free()
	record_checks.clear()
	for category in _records.categories():
		var check := CheckBox.new()
		check.text = "%s (%d)" % [category.label, category.count]
		check.disabled = category.count == 0
		check.custom_minimum_size.x = 260
		check.set_meta("label", category.label)
		check.set_meta("count", category.count)
		check.toggled.connect(func(_on: bool) -> void: _selection_changed())
		_record_grid.add_child(check)
		record_checks[category.kind] = check
	loose_check.set_pressed_no_signal(false)
	loose_check.text = "Lugares soltos, sem ligação com nenhum cadastro (hoje: %d, mais os que ficarem soltos)" % _records.loose_places()
	_confirm_card.hide()
	_result_card.hide()
	_selection_changed()


## Os tipos marcados.
func marked_kinds() -> Array:
	return record_checks.keys().filter(func(k): return record_checks[k].button_pressed)


func _mark_all(on: bool) -> void:
	for check in record_checks.values():
		check.set_pressed_no_signal(on and not check.disabled)
	loose_check.set_pressed_no_signal(on)
	_selection_changed()


func _selection_changed() -> void:
	delete_button.disabled = marked_kinds().is_empty() and not loose_check.button_pressed
	_confirm_card.hide()  # mudou o que está marcado: confirmar de novo


func _ask_confirmation() -> void:
	var lines: Array = []
	var total := 0
	for kind in marked_kinds():
		var check: CheckBox = record_checks[kind]
		lines.append("• %s: %d" % [check.get_meta("label"), check.get_meta("count")])
		total += int(check.get_meta("count"))
	if loose_check.button_pressed:
		lines.append("• Lugares soltos")
	var text := "Vai apagar:
%s" % "
".join(lines)
	if total > 0:
		text += "

São %d cadastros, com os nomes, os territórios pintados, os vínculos, as presenças e a população deles." % total
	for w in _records.warnings(marked_kinds()):
		text += "
" + w
	text += "

Antes, o jogo guarda uma cópia do mundo. O Ctrl+Z não desfaz esta ação."
	confirm_text.text = text
	confirm_edit.text = ""
	confirm_button.disabled = true
	_result_card.hide()
	_confirm_card.show()
	_scroll_to(confirm_button)  # o botão fica à vista, com o texto logo acima


func _delete_marked() -> void:
	if confirm_edit.text.strip_edges() != CONFIRM_WORD:
		return
	var result: Dictionary = _records.run(marked_kinds(), loose_check.button_pressed)
	if result.ok:
		refresh_records()
	_confirm_card.hide()
	_backup_path = result.backup
	result_label.text = result.message
	_result_card.show()
	_scroll_to(_result_card)


## Rola até o controle, depois de o texto com quebra de linha ganhar a altura dele (leva dois quadros).
func _scroll_to(control: Control) -> void:
	for _i in 2:
		await get_tree().process_frame
	if control.is_visible_in_tree():
		pages["cadastros"].ensure_control_visible(control)


# --- peças ------------------------------------------------------------------------------------------------------------

func _pad(child: Control, horizontal: int, vertical: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		m.add_theme_constant_override(side, horizontal)
	for side in ["margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, vertical)
	m.add_child(child)
	return m


func _card(box: VBoxContainer) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.inset_style())
	box.add_child(card)
	return card


func _heading(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	UiKit.style_heading(l)
	l.add_theme_font_size_override("font_size", 16)
	box.add_child(l)


## Uma linha: o nome (e a explicação embaixo) à esquerda, o controle à direita.
func _row(box: VBoxContainer, title: String, note: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size.y = 40
	_card(box).add_child(row)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(texts)
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(name_label)
	if note != "":
		var small := Label.new()
		small.text = note
		small.add_theme_font_size_override("font_size", 13)
		small.add_theme_color_override("font_color", UiKit.MUTED)
		small.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(small)
	return row


func _check(box: VBoxContainer, key: String, title: String, note: String) -> void:
	var c := CheckBox.new()
	c.tooltip_text = title
	c.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			_settings.set_value(key, on))
	_row(box, title, note).add_child(c)
	controls[key] = c


## items: [[texto, valor]]
func _choice(box: VBoxContainer, key: String, title: String, note: String, items: Array) -> void:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(230, 36)
	o.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	o.tooltip_text = title
	for item in items:
		o.add_item(item[0])
		o.set_item_metadata(o.item_count - 1, item[1])
	o.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			_settings.set_value(key, o.get_item_metadata(i)))
	_row(box, title, note).add_child(o)
	controls[key] = o


func _slider(box: VBoxContainer, key: String, title: String) -> void:
	var s := HSlider.new()
	s.min_value = 25
	s.max_value = 200
	s.step = 5
	s.custom_minimum_size = Vector2(280, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.tooltip_text = title
	var shown := Label.new()
	shown.custom_minimum_size.x = 52
	shown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void:
		shown.text = "%d%%" % roundi(v)
		if not _syncing:
			_settings.set_value(key, v / 100.0))
	var row := _row(box, title, "")
	row.add_child(s)
	row.add_child(shown)
	controls[key] = s


func _tutorial_row(box: VBoxContainer, key: String, title: String, note: String) -> void:
	var b := Button.new()
	b.text = "Ver"
	b.custom_minimum_size = Vector2(90, 34)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		close()
		tutorial_requested.emit(key))
	_row(box, title, note).add_child(b)
	tutorial_buttons[key] = b
