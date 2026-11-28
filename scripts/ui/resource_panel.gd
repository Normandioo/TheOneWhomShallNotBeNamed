extends PanelContainer
## O painel de recursos, em duas telas. A LISTA: buscar, escolher e criar, com os recursos em dois grupos (da natureza, no mapa; fabricados,
## nos povoados); gerar todos fica no menu ⋯. O RECURSO, numa página só: "Pôr no mapa" (pintar, marcar ponto, gerar sozinho) e os lugares,
## cada um abrindo na própria linha. Gerar (generator_panel.gd) e Editar são subtelas, com ‹ de volta. As antigas abas continuam como
## páginas (show_tab), sem a barra. Só mostra e pede: avisa por sinais; quem grava é o Registry, pelo resource_controller.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")
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
const NATURE := ["mineral", "vegetal", "animal"]
const CATEGORY_ICON := {"mineral": "resources", "vegetal": "ecology", "animal": "animal", "manufatura": "hammer"}
const NEW_UNITS := ["kg", "t", "unidade"]  # os atalhos do recurso novo; "outra…" abre o campo
const WARN := Color("#f2c46d")
const TABS := ["No mapa", "Gerar", "Editar"]
const TAB_MAP := 0
const TAB_SUGGEST := 1
const TAB_EDIT := 2
const MENU_ALL := 0      # itens do menu ⋯
const MENU_AUTHOR := 1
const MENU_EDIT := 2
const MENU_DELETE := 3

var title: Label
var back_button: Button
var message: Label
var list_box: VBoxContainer      # a tela da lista
var add_row: Control              # "Pôr no mapa": pintar área, marcar ponto, gerar sozinho
signal tutorial_requested         # o botão "?" do cabeçalho
var query: LineEdit
var types: VBoxContainer         # os dois grupos, uma linha (botão) por recurso
var empty_list: Label
var menu_button: MenuButton      # ⋯: gerar todos, ferramentas do autor, editar e excluir
var subtitle: Label              # "Mineral · em t · 3 lugares no mapa"
var new_origin := "natureza"     # o recurso novo: "natureza" ou "fabricado"
var new_kind := "mineral"        # e, se da natureza, de que tipo
var new_unit := ""
var _origin_cards := {}          # "natureza"/"fabricado" -> Button
var _kind_chips := {}            # categoria -> Button
var _unit_chips := {}            # unidade (ou "outra") -> Button
var new_unit_other: LineEdit
var new_profile: CheckBox        # "Usar o modelo X" quando o nome bate com um modelo pronto
var _profile_index := -1
var new_toggle: Button
var new_box: VBoxContainer
var new_name: LineEdit
var new_create: Button
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
var made_note: Label             # bem fabricado: em vez do mapa, quem o produz e quem o tem
var _made := false               # o recurso na tela é Manufatura sem lugar no mapa: a aba do mapa vira "Produção"
var occurrence_box: VBoxContainer
var _detail: PanelContainer      # o cartão que leva occurrence_box para baixo da linha escolhida
var more_toggle: Button          # "Mais opções": o que se usa pouco
var _reserve_unit: Label
var _dot: TextureRect            # o ícone da categoria, na cor do recurso, no cabeçalho
var _tabs_bar: HBoxContainer     # a barra das antigas abas: escondida (as páginas viraram subtelas)
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
	# Numa subtela (Gerar, Editar), ‹ volta para o recurso; no recurso, para a lista.
	back_button = _button(head, "‹", func() -> void:
		if type_box.visible and tab != TAB_MAP:
			show_tab(TAB_MAP)
		else:
			back_requested.emit())
	back_button.tooltip_text = "Voltar"
	_dot = TextureRect.new()
	_dot.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_dot.custom_minimum_size = Vector2(24, 24)
	head.add_child(_dot)
	title = _heading(head, "RECURSOS")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	menu_button = MenuButton.new()
	menu_button.icon = UiIcons.get_icon("more", 18)
	menu_button.tooltip_text = "Mais: gerar todos de uma vez, ferramentas do autor, editar e excluir"
	menu_button.accessibility_name = "Mais ações"
	menu_button.flat = false
	head.add_child(menu_button)
	menu_button.about_to_popup.connect(_fill_menu)
	menu_button.get_popup().id_pressed.connect(_on_menu)
	_button(head, "?", func() -> void: tutorial_requested.emit()).tooltip_text = "Ver como funcionam os recursos"
	_button(head, "✕", func() -> void: closed.emit())
	subtitle = _note(box, "")
	subtitle.modulate = Color(1, 1, 1, 0.7)
	subtitle.hide()
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
	query.right_icon = UiIcons.get_icon("search", 16)
	query.text_changed.connect(func(_t: String) -> void: query_changed.emit())

	new_toggle = _button(browse_box, "＋ Novo recurso", Callable())
	new_toggle.toggle_mode = true
	new_toggle.add_theme_stylebox_override("normal", UiKit.active_style())
	new_toggle.custom_minimum_size.y = 40
	new_box = _column(browse_box)
	new_box.add_theme_constant_override("separation", 8)
	new_box.hide()
	new_toggle.toggled.connect(func(open: bool) -> void: new_box.visible = open)
	_build_new(new_box)

	empty_list = _note(browse_box, "")
	types = _column(browse_box)
	types.add_theme_constant_override("separation", 2)
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


## O recurso novo: nome, de onde vem (natureza: mineral, vegetal, animal; ou fabricado), unidade e, se o nome bate com um modelo pronto,
## a oferta de usá-lo.
func _build_new(box: VBoxContainer) -> void:
	new_name = _edit(box, "Nome do recurso novo")
	new_name.text_submitted.connect(func(_t: String) -> void: _create())
	new_name.text_changed.connect(func(_t: String) -> void: _sync_new())
	_section_title(box, "De onde ele vem?")
	_origin_cards["natureza"] = _choice_card(box, "mountains", "Da natureza",
		"Está no mundo: mina, floresta, rebanho. Vai para o mapa e os povoados extraem dele.", func() -> void: _pick_origin("natureza"))
	var kinds := HFlowContainer.new()
	box.add_child(kinds)
	for c in CATEGORIES:
		if c[0] in NATURE:
			var chip := _button(kinds, c[1], func() -> void:
				new_kind = c[0]
				_sync_new())
			chip.icon = UiIcons.get_icon(CATEGORY_ICON[c[0]], 16)
			_kind_chips[c[0]] = chip
	_origin_cards["fabricado"] = _choice_card(box, "hammer", "Fabricado",
		"Feito nos povoados por uma receita, como espada ou pão. Não vai para o mapa.", func() -> void: _pick_origin("fabricado"))
	_section_title(box, "Unidade")
	var units := HFlowContainer.new()
	box.add_child(units)
	for u in NEW_UNITS + ["outra"]:
		_unit_chips[u] = _button(units, "outra…" if u == "outra" else u, func() -> void:
			new_unit = "" if new_unit == u else u
			_sync_new())
	new_unit_other = _edit(box, "Qual unidade")
	new_profile = CheckBox.new()
	new_profile.button_pressed = true
	new_profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(new_profile)
	new_create = _button(box, "Criar", _create)
	new_create.add_theme_stylebox_override("normal", UiKit.active_style())
	new_create.custom_minimum_size.y = 40
	_note(box, "Modelos prontos (já sabem onde procurar no mapa):").modulate = Color(1, 1, 1, 0.7)
	var ready := HFlowContainer.new()
	box.add_child(ready)
	for i in ResourceProfiles.PROFILES.size():
		_button(ready, ResourceProfiles.PROFILES[i].name, func() -> void: profile_requested.emit(i)).tooltip_text = ResourceProfiles.PROFILES[i].about
	_sync_new()


## Um cartão de escolha: ícone, título e uma linha explicando.
func _choice_card(parent: Control, icon_name: String, heading: String, about: String, on_press: Callable) -> Button:
	var card := _button(parent, "", on_press)
	card.toggle_mode = true
	card.custom_minimum_size.y = 62
	card.tooltip_text = about
	card.accessibility_name = "%s: %s" % [heading, about]
	var body := VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 10
	body.offset_right = -10
	body.offset_top = 6
	body.add_theme_constant_override("separation", 0)
	card.add_child(body)
	var top := HBoxContainer.new()
	body.add_child(top)
	var icon := TextureRect.new()
	icon.texture = UiIcons.get_icon(icon_name, 18)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	top.add_child(icon)
	var name_label := Label.new()
	name_label.text = heading
	top.add_child(name_label)
	var line := Label.new()
	line.text = about
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", 12)
	line.modulate.a = 0.7
	body.add_child(line)
	for node in [body, top, icon, name_label, line]:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _pick_origin(origin: String) -> void:
	new_origin = origin
	_sync_new()


## Os cartões e as etiquetas do recurso novo mostram o que está escolhido; o modelo aparece só quando o nome bate com um.
func _sync_new() -> void:
	for key in _origin_cards:
		_origin_cards[key].set_pressed_no_signal(key == new_origin)
		_origin_cards[key].add_theme_stylebox_override("pressed", UiKit.active_style())
	for key in _kind_chips:
		_kind_chips[key].visible = new_origin == "natureza"
		_mark(_kind_chips[key], key == new_kind)
	for key in _unit_chips:
		_mark(_unit_chips[key], key == new_unit)
	new_unit_other.visible = new_unit == "outra"
	_profile_index = -1
	var typed := new_name.text.strip_edges()
	for i in ResourceProfiles.PROFILES.size():
		if typed != "" and typed.to_lower() == String(ResourceProfiles.PROFILES[i].name).to_lower():
			_profile_index = i
	new_profile.visible = _profile_index >= 0
	if _profile_index >= 0:
		new_profile.text = "Usar o modelo %s: já vem com os critérios para gerar no mapa" % ResourceProfiles.PROFILES[_profile_index].name


static func _mark(button: Button, on: bool) -> void:
	if on:
		button.add_theme_stylebox_override("normal", UiKit.active_style())
	else:
		button.remove_theme_stylebox_override("normal")


func _create() -> void:
	if _profile_index >= 0 and new_profile.button_pressed:
		profile_requested.emit(_profile_index)
		new_name.text = ""
		_sync_new()
		return
	create_requested.emit(new_name.text, "manufatura" if new_origin == "fabricado" else new_kind)


## A unidade escolhida no recurso novo ("" = nenhuma).
func chosen_unit() -> String:
	return new_unit_other.text.strip_edges() if new_unit == "outra" else new_unit


func _build_type(box: VBoxContainer) -> void:
	type_box = _column(box)
	var bar := _row(type_box)
	_tabs_bar = bar
	bar.hide()  # sem abas: Gerar e Editar abrem pelos botões e pelo ⋯, e ‹ volta
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := _button(bar, TABS[i], func() -> void: show_tab(i))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_buttons.append(b)
		pages.append(null)
	for i in TABS.size():
		pages[i] = _column(type_box)

	var map_page := pages[TAB_MAP]
	var put := _column(map_page)
	add_row = put
	_section_title(put, "Pôr no mapa")
	var add := GridContainer.new()
	add.columns = 3
	add.add_theme_constant_override("h_separation", 6)
	put.add_child(add)
	for spec in [["patch", "Pintar área", "Uma área pintada, como uma floresta ou um campo de minério", func() -> void: area_requested.emit()],
			["place", "Marcar ponto", "Um lugar pequeno, como uma mina", func() -> void: point_requested.emit()],
			["generate", "Gerar sozinho", "Procura nos mapas do planeta os lugares que servem", func() -> void: show_tab(TAB_SUGGEST)]]:
		var b := _button(add, spec[1], spec[3])
		b.icon = UiIcons.get_icon(spec[0], 22)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.expand_icon = false
		b.custom_minimum_size = Vector2(0, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = spec[2]
	_section_title(map_page, "Onde está")
	empty_occurrences = _note(map_page, "Ainda não está no mapa. Escolha um dos três caminhos acima.")
	made_note = _note(map_page, "")
	made_note.hide()
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
	more_toggle = _button(links, "▸ Detalhes avançados", Callable())
	more_toggle.toggle_mode = true
	more_toggle.flat = true
	more_toggle.tooltip_text = "Nome e anotação, teor e datas, quem conhece, direitos e a divisão por país"
	var more := _column(occurrence_box)
	more.hide()
	more_toggle.toggled.connect(func(open: bool) -> void:
		more.visible = open
		more_toggle.text = ("▾ " if open else "▸ ") + "Detalhes avançados")
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


## O ⋯ muda com a tela: na lista, gerar todos; no recurso, editar e excluir. As ferramentas do autor (os testes da geração) valem nas duas.
func _fill_menu() -> void:
	var popup := menu_button.get_popup()
	popup.clear()
	if list_box.visible:
		popup.add_item("Gerar no mapa todos os que têm modelo…", MENU_ALL)
		popup.set_item_tooltip(popup.item_count - 1, "Mostra uma prévia no mapa. Nada muda antes de aplicar.")
	else:
		popup.add_item("Editar nome, cor, categoria e unidade", MENU_EDIT)
	popup.add_check_item("Ferramentas do autor (testes da geração)", MENU_AUTHOR)
	popup.set_item_checked(popup.item_count - 1, generator.author_tools)
	if not list_box.visible:
		popup.add_separator()
		popup.add_item("Excluir recurso…", MENU_DELETE)
		popup.set_item_disabled(popup.item_count - 1, delete_type_button.disabled)


func _on_menu(id: int) -> void:
	match id:
		MENU_ALL:
			preview_all_requested.emit()
		MENU_AUTHOR:
			generator.set_author_tools(not generator.author_tools)
		MENU_EDIT:
			show_tab(TAB_EDIT)
		MENU_DELETE:
			show_tab(TAB_EDIT)  # o botão Excluir fica no fim da tela de edição, com o aviso do que acontece


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


## Dois grupos: da natureza (mineral, vegetal, animal e os sem categoria, que vão para o mapa) e fabricados (feitos nos povoados).
## Dentro de cada um, na ordem das categorias.
func _build_types() -> void:
	for child in types.get_children():
		types.remove_child(child)
		child.queue_free()
	var groups := [["Da natureza", "ficam no mapa", "mountains", NATURE + [""]], ["Fabricados", "feitos nos povoados", "house", ["manufatura"]]]
	for g in groups:
		var mine: Array = _types_rows.filter(func(t): return _category_of(t) in g[3])
		if mine.is_empty():
			continue
		var head := _row(types)
		head.set_meta("header", true)
		var icon := TextureRect.new()
		icon.texture = UiIcons.get_icon(g[2], 16)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.modulate = UiKit.BRASS
		head.add_child(icon)
		var name_label := _heading(head, String(g[0]).to_upper())
		name_label.add_theme_font_size_override("font_size", 13)
		var hint := Label.new()
		hint.text = g[1]
		hint.add_theme_font_size_override("font_size", 12)
		hint.modulate.a = 0.65
		head.add_child(hint)
		for c in g[3]:
			for t in mine:
				if _category_of(t) == c:
					_type_row(t)
	empty_list.visible = _types_rows.is_empty() and query.text == ""
	empty_list.text = "Nenhum recurso ainda. Comece em ＋ Novo recurso."


## A categoria conhecida do recurso ("" = sem categoria).
static func _category_of(t: Dictionary) -> String:
	return t.category if CATEGORY_ICON.has(t.category) else ""


static func _category_label(code: String) -> String:
	for c in CATEGORIES:
		if c[0] == code:
			return c[1]
	return "Sem categoria"


## Uma linha: o ícone da categoria na cor do recurso, o nome com a categoria embaixo e, à direita, como ele está (amarelo = falta algo).
func _type_row(t: Dictionary) -> void:
	var category := _category_label(_category_of(t))
	var made: bool = t.category == "manufatura" and int(t.count) == 0
	var state: String
	if made:
		var recipes := int(t.get("recipes", 0))
		state = "sem receita" if recipes == 0 else "%d %s" % [recipes, "receita" if recipes == 1 else "receitas"]
	else:
		state = "fora do mapa" if int(t.count) == 0 else "%d %s" % [t.count, "lugar" if int(t.count) == 1 else "lugares"]
	var missing := state in ["sem receita", "fora do mapa"]
	var row := _button(types, "", func() -> void: type_chosen.emit(int(t.id)))
	row.set_meta("id", int(t.id))
	row.set_meta("category", category)
	row.custom_minimum_size.y = 44
	row.tooltip_text = "Abrir %s (%s)" % [t.name, state]
	row.accessibility_name = "%s, %s, %s" % [t.name, category, state]
	if int(t.id) == _selected_type:
		row.add_theme_stylebox_override("normal", UiKit.active_style())
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8
	line.offset_right = -10
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)
	var icon := TextureRect.new()
	icon.texture = UiIcons.get_icon(CATEGORY_ICON.get(_category_of(t), "resources"), 20)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.modulate = _color(t.rgb)
	line.add_child(icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(names)
	for pair in [[String(t.name), 15, 1.0], [category, 11, 0.6]]:
		var l := Label.new()
		l.text = pair[0]
		l.clip_text = true
		l.add_theme_font_size_override("font_size", pair[1])
		l.modulate.a = pair[2]
		names.add_child(l)
	var meta := Label.new()
	meta.text = state
	meta.add_theme_font_size_override("font_size", 12)
	if missing:
		meta.add_theme_color_override("font_color", WARN)
	else:
		meta.modulate.a = 0.65
	line.add_child(meta)
	for node in [line, icon, names, meta] + names.get_children():
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE


## As linhas dos recursos (sem os títulos dos grupos).
func type_rows() -> Array:
	return types.get_children().filter(func(c): return not c.has_meta("header"))


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
	# Um bem fabricado não nasce no mapa: o lugar dele são os povoados. Com algo já no mapa, o mapa continua.
	_made = open and t.category == "manufatura" and int(t.get("count", 0)) == 0
	tab_buttons[TAB_SUGGEST].visible = not _made
	add_row.visible = not _made
	made_note.visible = _made
	subtitle.visible = open
	if open:
		_dot.texture = UiIcons.get_icon(CATEGORY_ICON.get(_category_of(t), "resources"), 20)
		_dot.modulate = _color(t.rgb)
		tab_buttons[TAB_MAP].text = "Produção" if _made else "%s · %d" % [TABS[TAB_MAP], int(t.get("count", 0))]
		_reserve_unit.text = String(t.unit)
		var count := int(t.get("count", 0))
		subtitle.text = " · ".join([_category_label(_category_of(t)) if not _made else "Fabricado"] +
			([] if t.unit == "" else ["em %s" % t.unit]) +
			["não vai para o mapa" if _made else ("fora do mapa" if count == 0 else "%d %s no mapa" % [count, "lugar" if count == 1 else "lugares"])])
		if _made and tab == TAB_SUGGEST:
			show_tab(TAB_MAP)
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
		row.text = ("▾  " if chosen else "▸  ") + describe(o, _names[id], _reserve_unit.text)
		row.tooltip_text = describe(o, _names[id], _reserve_unit.text)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.add_theme_font_size_override("font_size", 14)
		row.icon = UiIcons.get_icon("patch" if o.kind == "area" else "place", 16)
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			row.add_theme_color_override(state, _color(o.rgb))
		if is_nan(float(o.get("reserve", NAN))):
			row.add_theme_color_override("font_color", WARN)  # sem quantidade: os povoados não extraem daqui
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
	empty_occurrences.visible = rows.is_empty() and not _made


## A aba "Produção" de um bem fabricado: recipes = os nomes das receitas que o fazem; makers = Registry.GoodMakers.
func show_made(recipes: Array, makers: Array, unit: String) -> void:
	var lines: Array[String] = ["Bem fabricado: não precisa estar no mapa. Ele é feito nos povoados, por uma receita de fabricação."]
	lines.append("Nenhuma receita faz este bem ainda: crie uma no painel Povoados, em Receitas." if recipes.is_empty()
		else "Receitas que fazem: " + ", ".join(recipes))
	for m in makers:
		lines.append("⌂ %s: %s%s em estoque%s" % [m.name, _plain(m.qty), " " + unit if unit != "" else "",
			", %d pessoas fazendo" % m.workers if int(m.workers) > 0 else ""])
	if not recipes.is_empty() and makers.is_empty():
		lines.append("Nenhum povoado faz nem tem este bem ainda: ponha a receita numa atividade.")
	made_note.text = "\n".join(lines)


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


## o: uma linha de Registry.Occurrences (as áreas trazem area_km2); label: o nome mostrado; unit: a do recurso. A quantidade aparece sempre.
static func describe(o: Dictionary, label: String, unit := "") -> String:
	var parts: Array[String] = [label]
	if o.kind == "area":
		parts.append("%s km²" % _thousands(roundi(o.area_km2)) if o.area_km2 > 0.0 else "sem pintura")
	var reserve := float(o.get("reserve", NAN))
	parts.append("⚠ sem quantidade" if is_nan(reserve) else _plain(reserve) + (" " + unit if unit != "" else ""))
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
