extends PanelContainer
## O painel de recursos, em duas telas. A LISTA: buscar, filtrar por categoria, escolher, criar e gerar todos. O RECURSO, com uma aba
## para cada tarefa: "No mapa" (o que já existe, cada lugar abrindo na própria linha), "Gerar" (generator_panel.gd) e "Editar".
## Só mostra e pede: avisa por sinais; quem grava é o Registry, pelo resource_controller.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")  # só para o separador de milhares
const GeneratorPanel = preload("res://scripts/ui/generator_panel.gd")
const ResourceProfiles = preload("res://scripts/ui/resource_profiles.gd")

signal query_changed
signal type_chosen(id: int)
signal back_requested                      # voltar do recurso para a lista
signal create_requested(name: String, category: String)
signal details_saved(data: Dictionary)     # teor, profundidade, acesso, renovação, política e anos de validade (texto)
signal knowledge_added(entity_id: int, from_year: String, to_year: String, estimate: String, note: String)
signal knowledge_removed(id: int)
signal right_added(entity_id: int, kind: String, from_year: String, to_year: String, note: String)
signal right_removed(id: int)
signal type_saved(name: String, description: String, category: String, unit: String, color: Color)
signal type_delete_requested
signal area_requested                      # área nova: cria a ocorrência e entra na pintura
signal paint_requested                     # continuar pintando a área escolhida
signal point_requested                     # o próximo clique no globo coloca um ponto
signal occurrence_chosen(id: int)
signal occurrence_saved(name: String, note: String)
signal move_requested                      # o próximo clique no globo leva o ponto escolhido para lá
signal duplicate_requested
signal why_requested                       # "Por que aqui?" de uma sugestão aplicada
signal reserve_saved(text: String)         # a quantidade da ocorrência ("" = desconhecida)
signal fixed_toggled(on: bool)             # proteger uma sugestão gerada
signal profile_requested(index: int)       # criar o recurso de um perfil
signal preview_all_requested
signal apply_all_requested
signal discard_all_requested
signal delete_requested
signal focus_requested
signal cancel_requested                    # Esc enquanto espera um clique
signal closed

const WIDTH := 320
const CATEGORIES := [["mineral", "Minerais"], ["vegetal", "Vegetação"], ["animal", "Animal"], ["manufatura", "Manufatura"]]
const UNITS := ["kg", "t", "m³", "L", "ha", "km²", "unidade", "cabeça", "kcal"]
const ACCESS := [["", "Acesso não informado"], ["facil", "Acesso fácil"], ["medio", "Acesso médio"], ["dificil", "Acesso difícil"]]
const POLICIES := [["normal", "A extração gasta a reserva"], ["reposicao", "Reposta pelo autor (magia): não acaba"], ["bloqueada", "Bloqueada: ninguém extrai"]]
const RIGHTS := [["controle", "Controle"], ["acesso", "Acesso"], ["exploracao", "Exploração"]]
const TABS := ["No mapa", "Gerar", "Editar"]
const TAB_MAP := 0
const TAB_SUGGEST := 1
const TAB_EDIT := 2

var title: Label
var back_button: Button
var message: Label
var list_box: VBoxContainer      # a tela da lista
var suggest_button: Button
var add_row: Control              # "Pintar área nova" e "Colocar ponto"
signal tutorial_requested         # o botão "?" do cabeçalho
var query: LineEdit
var types: VBoxContainer         # uma linha (botão) por recurso
var filter_buttons: Array[Button] = []
var category_filter := "*"       # "*" = todas as categorias
var empty_list: Label
var new_toggle: Button
var new_box: VBoxContainer
var new_name: LineEdit
var all_summary: Label
var all_actions: HBoxContainer    # Descartar e Aplicar da prévia de todos, presos embaixo
var all_apply_button: Button
var all_previewing := false
var browse_box: VBoxContainer     # a lista em si; some durante a prévia de todos
var all_box: VBoxContainer        # a prévia de todos
var _all_stats: HBoxContainer
var _all_rows: VBoxContainer
var _all_warning: Label
var _all_changes: VBoxContainer
var delete_type_button: Button
var _delete_note: Label
var type_box: VBoxContainer      # a tela de um recurso
var tab_buttons: Array[Button] = []
var pages: Array[VBoxContainer] = []
var tab := TAB_MAP
var occurrences: VBoxContainer   # uma linha (botão) por lugar; a escolhida abre logo abaixo dela
var occurrence_filter: LineEdit
var empty_occurrences: Label
var occurrence_box: VBoxContainer
var _detail: PanelContainer      # o cartão que leva occurrence_box para baixo da linha escolhida
var more_toggle: Button          # "Mais opções": o que se usa pouco
var _reserve_unit: Label
var _dot: ColorRect              # a cor do recurso, no cabeçalho
var _footer_slot: PanelContainer # Descartar e Aplicar, fora da rolagem
var _types_rows: Array = []      # o que veio de show_types, para refiltrar
var _selected_type := 0
var occurrence_name: LineEdit
var occurrence_note: LineEdit
var text_toggle: Button
var _point_actions: Array = []   # mover e duplicar: só pontos
var _paint_button: Button
var why_button: Button
var reserve_edit: LineEdit
var reserve_line: Label
var fixed_check: CheckButton
var generator: GeneratorPanel
var type_name: LineEdit
var type_color: ColorPickerButton
var type_description: LineEdit
var type_category: OptionButton
var type_unit: OptionButton
var unit_other: LineEdit
var new_category: OptionButton
var shares_line: Label
var details := {}                # controles dos detalhes da ocorrência
var knowledge_list: ItemList
var knowledge_ui := {}
var rights_list: ItemList
var rights_ui := {}
var lookup := Callable()         # func(texto) -> [{id, name, kind}]: a busca de cadastros (o controlador liga)
var _knowledge_ids: Array = []
var _right_ids: Array = []
var waiting := false             # esperando um clique no globo
var _names := {}                 # id -> o nome mostrado na lista
var _type := 0                   # o recurso na tela (para voltar à primeira aba quando troca)


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	custom_minimum_size = Vector2(WIDTH, 0)
	var shell := _column(self)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(scroll)
	_footer_slot = PanelContainer.new()
	_footer_slot.add_theme_stylebox_override("panel", UiKit.card_style())
	_footer_slot.hide()
	shell.add_child(_footer_slot)
	var box := _column(scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)

	var head := _row(box)
	back_button = _button(head, "‹", func() -> void: back_requested.emit())
	back_button.tooltip_text = "Voltar para a lista de recursos"
	_dot = _square(head)
	title = _heading(head, "RECURSOS")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	_button(head, "?", func() -> void: tutorial_requested.emit()).tooltip_text = "Ver como funcionam os recursos"
	_button(head, "✕", func() -> void: closed.emit())
	message = _note(box, "")
	message.modulate = Color(1.0, 0.85, 0.4)
	message.hide()

	_build_list(box)
	_build_type(box)
	var footers := _column(_footer_slot)
	footers.add_child(generator.footer)
	footers.add_child(all_actions)
	generator.mode_changed.connect(_sync_footer)
	show_type({})
	show_occurrence({})
	show_all("")


func _build_list(box: VBoxContainer) -> void:
	list_box = _column(box)
	browse_box = _column(list_box)
	query = _edit(browse_box, "Buscar recurso")
	query.text_changed.connect(func(_t: String) -> void: query_changed.emit())
	var chips := HFlowContainer.new()
	browse_box.add_child(chips)
	var group := ButtonGroup.new()
	for entry in [["*", "Todos"]] + CATEGORIES:
		var chip := _button(chips, entry[1], func() -> void:
			category_filter = entry[0]
			_build_types())
		chip.toggle_mode = true
		chip.button_group = group
		chip.add_theme_font_size_override("font_size", 13)
		chip.add_theme_stylebox_override("pressed", UiKit.active_style())
		filter_buttons.append(chip)
	filter_buttons[0].set_pressed_no_signal(true)
	empty_list = _note(browse_box, "")
	types = _column(browse_box)

	new_toggle = _button(browse_box, "＋ Novo recurso", Callable())
	new_toggle.toggle_mode = true
	new_toggle.add_theme_stylebox_override("normal", UiKit.active_style())
	new_toggle.custom_minimum_size.y = 36
	new_box = _column(browse_box)
	new_box.hide()
	new_toggle.toggled.connect(func(open: bool) -> void: new_box.visible = open)
	var create := _row(new_box)
	new_name = _edit(create, "Nome do recurso novo")
	new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_name.text_submitted.connect(func(t: String) -> void: create_requested.emit(t, _category_code(new_category)))
	_button(create, "Criar", func() -> void: create_requested.emit(new_name.text, _category_code(new_category)))
	new_category = _category_menu(new_box)
	_note(new_box, "Ou comece de um modelo pronto:")
	var ready := HFlowContainer.new()
	new_box.add_child(ready)
	for i in ResourceProfiles.PROFILES.size():
		_button(ready, ResourceProfiles.PROFILES[i].name, func() -> void: profile_requested.emit(i)).tooltip_text = ResourceProfiles.PROFILES[i].about

	suggest_button = _button(browse_box, "Gerar todos de uma vez", func() -> void: preview_all_requested.emit())
	suggest_button.tooltip_text = \
		"Mostra no mapa uma prévia dos recursos que já têm critérios de geração. Nada muda antes de aplicar."
	all_summary = _note(list_box, "")

	all_box = _column(list_box)
	all_box.add_theme_constant_override("separation", 10)
	all_box.hide()
	_heading(all_box, "Prévia de todos")
	_all_stats = _row(all_box)
	_all_rows = _column(all_box)
	_all_rows.add_theme_constant_override("separation", 4)
	_all_warning = _note(all_box, "")
	_all_warning.add_theme_color_override("font_color", Color("#f2c46d"))
	var changes := PanelContainer.new()
	changes.add_theme_stylebox_override("panel", UiKit.card_style())
	all_box.add_child(changes)
	_all_changes = _column(changes)
	_note(all_box, "Clique num lugar do mapa para saber por que ele está ali (e tirá-lo, se quiser). Cada recurso tem a sua cor.").modulate = Color(1, 1, 1, 0.7)

	all_actions = HBoxContainer.new()
	var drop := _button(all_actions, "Descartar", func() -> void: discard_all_requested.emit())
	all_apply_button = _button(all_actions, "Aplicar", func() -> void: apply_all_requested.emit())
	all_apply_button.add_theme_stylebox_override("normal", UiKit.active_style())
	for pair in [[drop, 1.0], [all_apply_button, 2.0]]:
		pair[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pair[0].size_flags_stretch_ratio = pair[1]
		pair[0].custom_minimum_size.y = 40


func _build_type(box: VBoxContainer) -> void:
	type_box = _column(box)
	var bar := _row(type_box)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := _button(bar, TABS[i], func() -> void: show_tab(i))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_buttons.append(b)
		pages.append(null)
	type_box.add_child(HSeparator.new())
	for i in TABS.size():
		pages[i] = _column(type_box)

	var map_page := pages[TAB_MAP]
	var add := _row(map_page)
	add_row = add
	_button(add, "Pintar área nova", func() -> void: area_requested.emit()).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(add, "Colocar ponto", func() -> void: point_requested.emit()).tooltip_text = "Para um local pequeno, como uma mina"
	empty_occurrences = _note(map_page, "Ainda não está no mapa. Pinte uma área, coloque um ponto ou use a aba Gerar.")
	occurrence_filter = _edit(map_page, "filtrar")
	occurrence_filter.text_changed.connect(func(_t: String) -> void: _filter_occurrences())
	occurrences = _column(map_page)
	occurrences.add_theme_constant_override("separation", 3)

	# As ações só aparecem para o item escolhido, logo abaixo da linha dele.
	_detail = PanelContainer.new()
	_detail.add_theme_stylebox_override("panel", UiKit.card_style())
	occurrences.add_child(_detail)
	occurrence_box = _column(_detail)
	var reserve_row := _row(occurrence_box)
	var amount_label := Label.new()
	amount_label.text = "Quantidade"
	reserve_row.add_child(amount_label)
	reserve_edit = _edit(reserve_row, "não informada")
	reserve_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reserve_edit.tooltip_text = "Quanto há neste lugar, na unidade do recurso. Sem quantidade, os povoados não extraem dele."
	_reserve_unit = Label.new()
	reserve_row.add_child(_reserve_unit)
	_button(reserve_row, "Salvar", func() -> void: reserve_saved.emit(reserve_edit.text))
	reserve_line = _note(occurrence_box, "")
	var actions := HFlowContainer.new()
	occurrence_box.add_child(actions)
	_button(actions, "Ver no mapa", func() -> void: focus_requested.emit())
	_paint_button = _button(actions, "Pintar", func() -> void: paint_requested.emit())
	_point_actions = [_button(actions, "Mover", func() -> void: move_requested.emit()),
		_button(actions, "Duplicar", func() -> void: duplicate_requested.emit())]
	_button(actions, "Excluir", func() -> void: delete_requested.emit())
	fixed_check = CheckButton.new()
	fixed_check.text = "Proteger: gerar de novo não mexe neste"
	fixed_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fixed_check.add_theme_font_size_override("font_size", 13)
	fixed_check.toggled.connect(func(on: bool) -> void: fixed_toggled.emit(on))
	occurrence_box.add_child(fixed_check)
	var links := _row(occurrence_box)
	why_button = _button(links, "Por que aqui?", func() -> void: why_requested.emit())
	why_button.flat = true
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	links.add_child(gap)
	more_toggle = _button(links, "Mais opções ▸", Callable())
	more_toggle.toggle_mode = true
	more_toggle.flat = true
	more_toggle.tooltip_text = "Nome e anotação, teor e datas, quem conhece, direitos e a divisão por país"
	var more := _column(occurrence_box)
	more.hide()
	more_toggle.toggled.connect(func(open: bool) -> void:
		more.visible = open
		more_toggle.text = "Mais opções ▾" if open else "Mais opções ▸")
	shares_line = _note(more, "")
	_build_details(more)
	_build_people(more)
	text_toggle = _button(more, "▸ Nome e anotação", Callable())
	text_toggle.toggle_mode = true
	text_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var texts := _column(more)
	texts.hide()
	text_toggle.toggled.connect(func(open: bool) -> void:
		texts.visible = open
		text_toggle.text = ("▾ " if open else "▸ ") + "Nome e anotação")
	occurrence_name = _edit(texts, "Nome (opcional)")
	occurrence_note = _edit(texts, "Anotação")
	_button(texts, "Salvar nome e anotação", func() -> void: occurrence_saved.emit(occurrence_name.text, occurrence_note.text))

	generator = GeneratorPanel.new()
	pages[TAB_SUGGEST].add_child(generator)

	_build_edit(pages[TAB_EDIT])


## A aba Editar: quem é o recurso, como ele é classificado, salvar; e, separado, excluir.
func _build_edit(page: VBoxContainer) -> void:
	page.add_theme_constant_override("separation", 8)
	_section_title(page, "Identificação")
	type_name = LineEdit.new()
	_field(page, "Nome", type_name)
	type_color = ColorPickerButton.new()
	type_color.edit_alpha = false
	type_color.custom_minimum_size = Vector2(0, 30)
	_field(page, "Cor no mapa", type_color)
	type_description = LineEdit.new()
	type_description.placeholder_text = "opcional"
	_field(page, "Descrição", type_description)

	_section_title(page, "Classificação")
	type_category = _category_menu(page)
	_field(page, "Categoria", type_category)
	type_unit = OptionButton.new()
	type_unit.add_item("Sem unidade")
	for u in UNITS:
		type_unit.add_item(u)
	type_unit.add_item("Outra…")
	_field(page, "Unidade", type_unit)
	unit_other = LineEdit.new()
	unit_other.placeholder_text = "qual unidade"
	unit_other.accessibility_name = "Qual unidade"
	page.add_child(unit_other)
	type_unit.item_selected.connect(func(i: int) -> void: unit_other.visible = i == type_unit.item_count - 1)
	_note(page, "Receitas, estoques e quantidades usam só esta unidade.").modulate = Color(1, 1, 1, 0.7)

	var save := _button(page, "Salvar alterações", func() -> void:
		type_saved.emit(type_name.text, type_description.text, _category_code(type_category), _unit_text(), type_color.color))
	save.add_theme_stylebox_override("normal", UiKit.active_style())
	save.custom_minimum_size.y = 40

	page.add_child(HSeparator.new())
	delete_type_button = _button(page, "Excluir recurso", func() -> void: type_delete_requested.emit())
	_delete_note = _note(page, "")
	_delete_note.modulate = Color(1, 1, 1, 0.7)


func _section_title(parent: Control, text: String) -> void:
	_heading(parent, text).add_theme_font_size_override("font_size", 15)


## Uma linha do formulário: o nome do campo à esquerda e o controle ocupando o resto.
func _field(parent: Control, label: String, control: Control) -> void:
	var row := _row(parent)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 100
	row.add_child(l)
	if control.get_parent() != null:
		control.get_parent().remove_child(control)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.accessibility_name = label
	row.add_child(control)


## Troca de aba. Sair de "Sugerir" fecha a prévia (e encerra uma avaliação, guardando as respostas).
func show_tab(index: int) -> void:
	var leaving := tab == TAB_SUGGEST and index != TAB_SUGGEST
	tab = index
	for i in pages.size():
		pages[i].visible = i == index
		tab_buttons[i].set_pressed_no_signal(i == index)
	if leaving:
		generator.leave()
	_sync_footer()


func _sync_footer() -> void:
	var one := generator.previewing and type_box.visible and tab == TAB_SUGGEST
	var all := all_previewing and list_box.visible
	generator.footer.visible = one
	all_actions.visible = all
	_footer_slot.visible = one or all


## rows: o que Registry.ResourceTypes devolve.
func show_types(rows: Array, selected: int) -> void:
	_types_rows = rows
	_selected_type = selected
	_build_types()


## Uma linha por recurso, na ordem das categorias; o filtro de cima mostra uma só.
func _build_types() -> void:
	for child in types.get_children():
		types.remove_child(child)
		child.queue_free()
	var groups := CATEGORIES.duplicate()
	groups.append(["", "Sem categoria"])
	for g in groups:
		if category_filter != "*" and category_filter != g[0]:
			continue
		for t in _types_rows:
			if (t.category == g[0]) if g[0] != "" else not CATEGORIES.any(func(c): return c[0] == t.category):
				_type_row(t, g[1])
	var none := types.get_child_count() == 0
	empty_list.visible = none and (query.text == "" or category_filter != "*")
	empty_list.text = "Nenhum recurso nesta categoria." if not _types_rows.is_empty() else "Nenhum recurso ainda. Comece em ＋ Novo recurso."


func _type_row(t: Dictionary, category: String) -> void:
	var row := _button(types, "", func() -> void: type_chosen.emit(int(t.id)))
	row.set_meta("id", int(t.id))
	row.set_meta("category", category)
	row.custom_minimum_size.y = 40
	row.tooltip_text = "Abrir %s (%d no mapa)" % [t.name, t.count]
	row.accessibility_name = "%s, %s, %d no mapa" % [t.name, category, t.count]
	if int(t.id) == _selected_type:
		row.add_theme_stylebox_override("normal", UiKit.active_style())
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 10
	line.offset_right = -10
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)
	_square(line).color = _color(t.rgb)
	for pair in [[String(t.name), 15, 1.0, true], [category, 12, 0.65, false],
			["%d no mapa" % t.count if int(t.count) > 0 else "fora do mapa", 12, 0.65, false], ["›", 16, 1.0, false]]:
		var l := Label.new()
		l.text = pair[0]
		l.add_theme_font_size_override("font_size", pair[1])
		l.modulate.a = pair[2]
		if pair[3]:
			l.clip_text = true
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
	for node in [line] + line.get_children():
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE


func type_rows() -> Array:
	return types.get_children()


func _square(parent: Control) -> ColorRect:
	var square := ColorRect.new()
	square.custom_minimum_size = Vector2(14, 14)
	square.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(square)
	return square


## O recurso aberto ({} = a tela da lista).
func show_type(t: Dictionary) -> void:
	var open := not t.is_empty()
	type_box.visible = open
	list_box.visible = not open
	back_button.visible = open
	_dot.visible = open
	if open:
		_dot.color = _color(t.rgb)
		tab_buttons[TAB_MAP].text = "%s · %d" % [TABS[TAB_MAP], int(t.get("count", 0))]
		_reserve_unit.text = String(t.unit)
	_sync_footer.call_deferred()
	title.text = String(t.name).to_upper() if open else "RECURSOS"
	if not open:
		_type = 0
		return
	if int(t.id) != _type:
		_type = int(t.id)
		new_toggle.button_pressed = false
		more_toggle.button_pressed = false
		text_toggle.button_pressed = false
		occurrence_filter.text = ""
		show_tab(TAB_MAP)
	var uses := int(t.get("count", 0))
	delete_type_button.disabled = uses > 0  # o Registry recusa excluir um recurso que está no mapa
	_delete_note.text = ("Está em %d %s no mapa. Exclua-%s antes." % [uses, "lugar" if uses == 1 else "lugares", "o" if uses == 1 else "os"]) if uses > 0 \
		else "Dá para desfazer com Ctrl+Z."
	type_name.text = t.name
	type_description.text = t.description
	type_category.select(1 + CATEGORIES.map(func(c): return c[0]).find(t.category))
	var known := UNITS.find(t.unit)
	type_unit.select(0 if t.unit == "" else (1 + known if known >= 0 else type_unit.item_count - 1))
	unit_other.text = t.unit if known < 0 else ""
	unit_other.visible = type_unit.selected == type_unit.item_count - 1
	type_color.color = _color(t.rgb)


func show_occurrences(rows: Array, selected: int) -> void:
	for row in occurrence_rows():
		occurrences.remove_child(row)
		row.queue_free()
	_names.clear()
	var counts := {"area": 0, "ponto": 0}  # "Área 1, Área 2…" na ordem de criação: o número interno não diz nada ao autor
	var at := 0
	var open_at := -1
	for o in rows:
		counts[o.kind] += 1
		var id := int(o.id)
		_names[id] = o.name if o.name != "" else "%s %d" % ["Área" if o.kind == "area" else "Ponto", counts[o.kind]]
		var chosen := id == selected
		var row := Button.new()
		row.text = ("▾  " if chosen else "▸  ") + describe(o, _names[id])
		row.tooltip_text = describe(o, _names[id])
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.add_theme_font_size_override("font_size", 14)
		row.set_meta("id", id)
		if chosen:
			row.add_theme_stylebox_override("normal", UiKit.active_style())
		row.pressed.connect(func() -> void: occurrence_chosen.emit(0 if chosen else id))
		occurrences.add_child(row)
		occurrences.move_child(row, at)
		at += 1
		if chosen:
			open_at = at
	# O cartão só muda de lugar (não sai da árvore), para não perder o foco de quem está digitando nele.
	occurrences.move_child(_detail, open_at if open_at >= 0 else occurrences.get_child_count() - 1)
	occurrence_filter.visible = rows.size() > 8
	if not occurrence_filter.visible:
		occurrence_filter.text = ""
	_filter_occurrences()
	occurrences.visible = not rows.is_empty()
	empty_occurrences.visible = rows.is_empty()


func occurrence_rows() -> Array:
	return occurrences.get_children().filter(func(c): return c != _detail)


func _filter_occurrences() -> void:
	var wanted := occurrence_filter.text.strip_edges().to_lower()
	for row in occurrence_rows():
		row.visible = wanted == "" or row.tooltip_text.to_lower().contains(wanted)


## O item escolhido no mapa ({} = nenhum).
func show_occurrence(o: Dictionary) -> void:
	occurrence_box.visible = not o.is_empty()
	_detail.visible = not o.is_empty()
	if o.is_empty():
		return
	occurrence_name.text = o.name
	occurrence_note.text = o.note
	why_button.visible = o.origin == "gerada"
	fixed_check.visible = o.origin == "gerada"
	fixed_check.set_pressed_no_signal(o.fixed)
	var reserve: Dictionary = o.get("reserve_info", {})
	reserve_edit.text = "" if reserve.is_empty() or is_nan(reserve.reserve) else _plain(reserve.reserve)
	reserve_line.visible = not reserve.is_empty() and not is_nan(reserve.reserve) and reserve.extracted > 0.0
	if reserve_line.visible:
		reserve_line.text = "Restam %s de %s (%s já extraídos)." % [_plain(reserve.left), _plain(reserve.reserve), _plain(reserve.extracted)]
	_show_extra(o)
	var point: bool = o.kind == "ponto"
	_paint_button.visible = not point
	for button in _point_actions:
		button.visible = point


func _build_details(parent: Control) -> void:
	var body := _fold(parent, "Teor, acesso e datas")
	details.grade = _labeled(body, "Teor (%)")
	details.depth = _labeled(body, "Profundidade (m)")
	details.access = _options(body, ACCESS)
	details.renewal = _labeled(body, "Renova por ano")
	details.renewal.tooltip_text = "Quanto volta por ano depois de extraído (floresta, pesca). Nunca passa da quantidade dada."
	details.policy = _options(body, POLICIES)
	details.from = _labeled(body, "Existe desde o ano")
	details.to = _labeled(body, "Deixa de existir no ano")
	_note(body, "Anos vazios = sempre. Isto muda o mundo numa data; mover a área no mapa é só correção.").modulate = Color(1, 1, 1, 0.7)
	_button(body, "Salvar detalhes", func() -> void:
		details_saved.emit({"grade": details.grade.text, "depth": details.depth.text, "access": ACCESS[details.access.selected][0],
			"renewal": details.renewal.text, "policy": POLICIES[details.policy.selected][0], "from": details.from.text, "to": details.to.text}))


## "Quem conhece" e "Direitos": uma lista e o formulário de um novo, cada um.
func _build_people(parent: Control) -> void:
	var known := _fold(parent, "Quem conhece")
	_note(known, "Um país, cultura ou outro cadastro sabe desta ocorrência, com a estimativa dele (pode errar).").modulate = Color(1, 1, 1, 0.7)
	knowledge_list = _list(known, 80, "Quem conhece")
	knowledge_ui = _picker(known)
	knowledge_ui.estimate = _labeled(known, "Estimativa dele")
	var krow := _row(known)
	_button(krow, "Adicionar", func() -> void:
		if knowledge_ui.who.selected >= 0:
			knowledge_added.emit(int(knowledge_ui.who.get_item_metadata(knowledge_ui.who.selected)), knowledge_ui.from.text, knowledge_ui.to.text,
				knowledge_ui.estimate.text, ""))
	_button(krow, "Tirar o escolhido", func() -> void:
		var i := knowledge_list.get_selected_items()
		if not i.is_empty():
			knowledge_removed.emit(_knowledge_ids[i[0]]))
	var rights := _fold(parent, "Direitos")
	_note(rights, "Controle, acesso e exploração são direitos diferentes: controlar não dá a exploração.").modulate = Color(1, 1, 1, 0.7)
	rights_list = _list(rights, 80, "Direitos")
	rights_ui = _picker(rights)
	rights_ui.kind = _options(rights, RIGHTS)
	var rrow := _row(rights)
	_button(rrow, "Adicionar", func() -> void:
		if rights_ui.who.selected >= 0:
			right_added.emit(int(rights_ui.who.get_item_metadata(rights_ui.who.selected)), RIGHTS[rights_ui.kind.selected][0],
				rights_ui.from.text, rights_ui.to.text, ""))
	_button(rrow, "Tirar o escolhido", func() -> void:
		var i := rights_list.get_selected_items()
		if not i.is_empty():
			right_removed.emit(_right_ids[i[0]]))


## Escolher um cadastro pelo nome, e o período.
func _picker(parent: Control) -> Dictionary:
	var ui := {}
	ui.search = _edit(parent, "Buscar país, cultura… pelo nome")
	ui.who = OptionButton.new()
	ui.who.fit_to_longest_item = false
	ui.who.accessibility_name = "Quem"
	parent.add_child(ui.who)
	ui.search.text_changed.connect(func(text: String) -> void:
		ui.who.clear()
		if lookup.is_valid() and text.strip_edges() != "":
			for e in lookup.call(text):
				ui.who.add_item("%s (%s)" % [e.name, UiKit.kind_label(e.kind)])
				ui.who.set_item_metadata(ui.who.item_count - 1, int(e.id))
		if ui.who.item_count > 0:
			ui.who.select(0))
	ui.from = _labeled(parent, "Desde o ano (vazio = sempre)")
	ui.to = _labeled(parent, "Até o ano (vazio = sempre)")
	return ui


func _show_extra(o: Dictionary) -> void:
	var d: Dictionary = o.get("details", {})
	if not d.is_empty():
		details.grade.text = "" if is_nan(d.grade) else _plain(d.grade)
		details.depth.text = "" if is_nan(d.depth_m) else _plain(d.depth_m)
		details.access.select(maxi(ACCESS.map(func(x): return x[0]).find(d.access), 0))
		details.renewal.text = "" if is_nan(d.renewal) else _plain(d.renewal)
		details.policy.select(maxi(POLICIES.map(func(x): return x[0]).find(d.policy), 0))
		details.from.text = o.get("from_year", "")
		details.to.text = o.get("to_year", "")
	knowledge_list.clear()
	_knowledge_ids.clear()
	for k in o.get("knowledge", []):
		knowledge_list.add_item("%s · %s%s" % [k.entity, k.period, " · estima %s" % _plain(k.estimate) if not is_nan(k.estimate) else ""])
		_knowledge_ids.append(int(k.id))
	rights_list.clear()
	_right_ids.clear()
	for r in o.get("rights", []):
		rights_list.add_item("%s · %s · %s" % [r.entity, RIGHTS.filter(func(x): return x[0] == r.kind)[0][1], r.period])
		_right_ids.append(int(r.id))
	var shares: Array = o.get("shares", [])
	shares_line.text = "" if shares.is_empty() else "Por país: " + ", ".join(shares.map(func(x): return "%s %d%%" % [x.country, roundi(100 * x.share)]))
	shares_line.visible = shares_line.text != ""


func _fold(parent: Control, label: String) -> VBoxContainer:
	var toggle := _button(parent, "▸ " + label, Callable())
	toggle.toggle_mode = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.clip_text = true  # um título comprido não pode alargar o painel
	toggle.tooltip_text = label
	var body := _column(parent)
	body.hide()
	toggle.toggled.connect(func(open: bool) -> void:
		body.visible = open
		toggle.text = ("▾ " if open else "▸ ") + label)
	return body


func _labeled(parent: Control, label: String) -> LineEdit:
	var row := _row(parent)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var e := LineEdit.new()
	e.custom_minimum_size.x = 100
	e.accessibility_name = label
	row.add_child(e)
	return e


func _options(parent: Control, items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.fit_to_longest_item = false
	for it in items:
		o.add_item(it[1])
	parent.add_child(o)
	return o


func _category_menu(parent: Control) -> OptionButton:
	var o := OptionButton.new()
	o.accessibility_name = "Categoria"
	o.add_item("Sem categoria")
	for c in CATEGORIES:
		o.add_item(c[1])
	parent.add_child(o)
	return o


static func _category_code(menu: OptionButton) -> String:
	return "" if menu.selected <= 0 else CATEGORIES[menu.selected - 1][0]


func _unit_text() -> String:
	if type_unit.selected <= 0:
		return ""
	if type_unit.selected == type_unit.item_count - 1:
		return unit_other.text.strip_edges()
	return UNITS[type_unit.selected - 1]


## Um aviso da geração de todos ("" = nenhum); fora da prévia.
func show_all(text: String) -> void:
	all_summary.text = text
	all_summary.visible = text != ""
	_set_all_preview(false)


## A prévia de todos. entries: [{name, rgb, unit, count, total, area, km2, reserve, replaced, protected, suppressed}]
func show_all_plan(entries: Array) -> void:
	var total := {"count": 0, "km2": 0.0, "replaced": 0, "protected": 0, "suppressed": 0}
	var full: Array[String] = []
	GeneratorPanel.clear_box(_all_rows)
	for e in entries:
		for key in total:
			total[key] += e[key]
		if int(e.total) >= 200:
			full.append(String(e.name))
		_all_row(e)
	GeneratorPanel.clear_box(_all_stats)
	generator.stat_card(_all_stats, str(entries.size()), "recurso" if entries.size() == 1 else "recursos")
	generator.stat_card(_all_stats, GeneratorPanel.short_number(total.count), "lugar" if total.count == 1 else "lugares")
	if total.km2 > 0.0:
		generator.stat_card(_all_stats, GeneratorPanel.short_number(total.km2), "km²")
	_all_warning.text = "Chegaram ao máximo de 200: %s." % ", ".join(full)
	_all_warning.visible = not full.is_empty()
	generator.fill_changes(_all_changes, total)
	all_apply_button.text = "Aplicar %d %s" % [total.count, "lugar" if total.count == 1 else "lugares"]
	all_summary.text = "%d lugares na prévia" % total.count  # fica escondido: é o que os testes mostram quando falham
	all_summary.hide()
	_set_all_preview(true)


## Um recurso na prévia de todos: a cor, o nome e quantos entram; embaixo, a quantidade e o que sai.
func _all_row(e: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.card_style())
	_all_rows.add_child(card)
	var body := _column(card)
	body.add_theme_constant_override("separation", 0)
	var line := _row(body)
	_square(line).color = _color(e.rgb)
	var name_label := Label.new()
	name_label.text = e.name
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var amount := Label.new()
	amount.text = "%d %s" % [e.count, "lugar" if int(e.count) == 1 else "lugares"]
	line.add_child(amount)
	var extra: Array[String] = []
	if float(e.reserve) > 0.0:
		var unit: String = e.unit
		extra.append("%s %s" % [GeneratorPanel.short_number(e.reserve), unit + "s" if unit in ["unidade", "cabeça"] else unit])
	if int(e.replaced) > 0:
		extra.append("saem %d antigos" % e.replaced)
	if not extra.is_empty():
		var small := Label.new()
		small.text = " · ".join(extra)
		small.clip_text = true
		small.tooltip_text = small.text
		small.mouse_filter = Control.MOUSE_FILTER_PASS
		small.add_theme_font_size_override("font_size", 12)
		small.modulate.a = 0.65
		body.add_child(small)


func _set_all_preview(on: bool) -> void:
	all_previewing = on
	browse_box.visible = not on
	all_box.visible = on
	_sync_footer()


func show_message(text: String) -> void:
	message.text = text
	message.visible = text != ""


## o: uma linha de Registry.Occurrences (as áreas trazem area_km2); label: o nome mostrado.
static func describe(o: Dictionary, label: String) -> String:
	var parts: Array[String] = [label]
	if o.kind == "area":
		parts.append("%s km²" % _thousands(roundi(o.area_km2)) if o.area_km2 > 0.0 else "sem pintura")
	if o.origin == "gerada":
		parts.append("protegida" if o.fixed else "sugerida")
	return " · ".join(parts)


static func _plain(v: float) -> String:
	return _thousands(roundi(v)) if absf(v - roundi(v)) < 0.005 else ("%.2f" % v).replace(".", ",")


static func _thousands(v: int) -> String:
	return LayerPanel._thousands(v)


func _unhandled_key_input(e: InputEvent) -> void:
	if visible and waiting and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		cancel_requested.emit()
		get_viewport().set_input_as_handled()


static func _color(rgb: int) -> Color:
	return Color8((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255)


func _column(parent: Control) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 6)
	parent.add_child(b)
	return b


func _row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	parent.add_child(r)
	return r


func _heading(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	UiKit.style_heading(l)
	parent.add_child(l)
	return l


func _note(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 40, 0)
	l.add_theme_font_size_override("font_size", 13)
	parent.add_child(l)
	return l


func _edit(parent: Control, hint: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.tooltip_text = hint
	parent.add_child(e)
	return e


func _list(parent: Control, height: int, label: String) -> ItemList:
	var l := ItemList.new()
	l.custom_minimum_size = Vector2(0, height)
	l.accessibility_name = label
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	if on_press.is_valid():
		b.pressed.connect(on_press)
	parent.add_child(b)
	return b
