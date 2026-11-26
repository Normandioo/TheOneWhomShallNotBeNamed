extends PanelContainer
## O painel de recursos, em duas telas. A LISTA: buscar, escolher, criar e sugerir para todos. O RECURSO, com uma aba para cada
## tarefa: "No mapa" (o que já existe e como acrescentar), "Sugerir" (generator_panel.gd) e "Editar" (o cadastro).
## Só mostra e pede: avisa por sinais; quem grava é o Registry, pelo resource_controller.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")  # só para o separador de milhares
const GeneratorPanel = preload("res://scripts/ui/generator_panel.gd")
const ResourceProfiles = preload("res://scripts/ui/resource_profiles.gd")

signal query_changed
signal type_chosen(id: int)
signal back_requested                      # voltar do recurso para a lista
signal create_requested(name: String)
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
const TABS := ["No mapa", "Sugerir", "Editar"]
const TAB_MAP := 0
const TAB_SUGGEST := 1
const TAB_EDIT := 2

var title: Label
var back_button: Button
var message: Label
var list_box: VBoxContainer      # a tela da lista
var query: LineEdit
var types: ItemList
var empty_list: Label
var new_toggle: Button
var new_box: VBoxContainer
var new_name: LineEdit
var all_summary: Label
var all_actions: HBoxContainer
var type_box: VBoxContainer      # a tela de um recurso
var tab_buttons: Array[Button] = []
var pages: Array[VBoxContainer] = []
var tab := TAB_MAP
var occurrences: ItemList
var empty_occurrences: Label
var occurrence_box: VBoxContainer
var occurrence_title: Label
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
var type_category: LineEdit
var type_unit: LineEdit
var waiting := false             # esperando um clique no globo
var _names := {}                 # id -> o nome mostrado na lista
var _type := 0                   # o recurso na tela (para voltar à primeira aba quando troca)


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	custom_minimum_size = Vector2(WIDTH, 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := _column(scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)

	var head := _row(box)
	back_button = _button(head, "‹ Voltar", func() -> void: back_requested.emit())
	back_button.tooltip_text = "Voltar para a lista de recursos"
	title = _heading(head, "RECURSOS")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	_button(head, "✕", func() -> void: closed.emit())
	message = _note(box, "")
	message.modulate = Color(1.0, 0.85, 0.4)
	message.hide()

	_build_list(box)
	_build_type(box)
	show_type({})
	show_occurrence({})
	show_all("")


func _build_list(box: VBoxContainer) -> void:
	list_box = _column(box)
	query = _edit(list_box, "Buscar recurso")
	query.text_changed.connect(func(_t: String) -> void: query_changed.emit())
	types = _list(list_box, 300, "Recursos: clique para abrir")
	types.item_selected.connect(func(i: int) -> void: type_chosen.emit(types.get_item_metadata(i)))
	empty_list = _note(list_box, "Nenhum recurso ainda. Comece em \"+ Novo recurso\".")

	new_toggle = _button(list_box, "+ Novo recurso", Callable())
	new_toggle.toggle_mode = true
	new_box = _column(list_box)
	new_box.hide()
	new_toggle.toggled.connect(func(open: bool) -> void: new_box.visible = open)
	var create := _row(new_box)
	new_name = _edit(create, "Nome do recurso novo")
	new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_name.text_submitted.connect(func(t: String) -> void: create_requested.emit(t))
	_button(create, "Criar", func() -> void: create_requested.emit(new_name.text))
	_note(new_box, "Ou comece de um modelo pronto:")
	var ready := HFlowContainer.new()
	new_box.add_child(ready)
	for i in ResourceProfiles.PROFILES.size():
		_button(ready, ResourceProfiles.PROFILES[i].name, func() -> void: profile_requested.emit(i)).tooltip_text = ResourceProfiles.PROFILES[i].about

	list_box.add_child(HSeparator.new())
	_button(list_box, "Sugerir para todos", func() -> void: preview_all_requested.emit()).tooltip_text = \
		"Mostra no mapa uma prévia dos recursos que já têm regra de sugestão. Nada muda antes de aplicar."
	all_summary = _note(list_box, "")
	all_actions = _row(list_box)
	_button(all_actions, "Aplicar todos", func() -> void: apply_all_requested.emit())
	_button(all_actions, "Descartar", func() -> void: discard_all_requested.emit())


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
	_button(add, "Pintar área nova", func() -> void: area_requested.emit()).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(add, "Colocar ponto", func() -> void: point_requested.emit()).tooltip_text = "Para um local pequeno, como uma mina"
	empty_occurrences = _note(map_page, "Este recurso ainda não está no mapa. Pinte uma área, coloque um ponto ou use a aba Sugerir.")
	occurrences = _list(map_page, 200, "Onde este recurso está: clique para ver as ações")
	occurrences.item_selected.connect(func(i: int) -> void: occurrence_chosen.emit(occurrences.get_item_metadata(i)))

	# As ações só aparecem para o item escolhido.
	occurrence_box = _column(map_page)
	occurrence_title = _heading(occurrence_box, "")
	occurrence_title.clip_text = true
	var actions := HFlowContainer.new()
	occurrence_box.add_child(actions)
	_button(actions, "Ver no mapa", func() -> void: focus_requested.emit())
	_paint_button = _button(actions, "Pintar", func() -> void: paint_requested.emit())
	_point_actions = [_button(actions, "Mover", func() -> void: move_requested.emit()),
		_button(actions, "Duplicar", func() -> void: duplicate_requested.emit())]
	why_button = _button(actions, "Por que aqui?", func() -> void: why_requested.emit())
	_button(actions, "Excluir", func() -> void: delete_requested.emit())
	fixed_check = CheckButton.new()
	fixed_check.text = "Proteger de novas sugestões"
	fixed_check.tooltip_text = "Ligado, uma nova sugestão não troca nem apaga este item"
	fixed_check.toggled.connect(func(on: bool) -> void: fixed_toggled.emit(on))
	occurrence_box.add_child(fixed_check)
	var reserve_row := _row(occurrence_box)
	reserve_edit = _edit(reserve_row, "Quantidade (vazio = desconhecida)")
	reserve_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reserve_edit.tooltip_text = "Quanto há nesta ocorrência, na unidade do recurso. Sem quantidade, os povoados não extraem dela."
	_button(reserve_row, "Salvar", func() -> void: reserve_saved.emit(reserve_edit.text))
	reserve_line = _note(occurrence_box, "")
	text_toggle = _button(occurrence_box, "Nome e anotação", Callable())
	text_toggle.toggle_mode = true
	var texts := _column(occurrence_box)
	texts.hide()
	text_toggle.toggled.connect(func(open: bool) -> void: texts.visible = open)
	occurrence_name = _edit(texts, "Nome (opcional)")
	occurrence_note = _edit(texts, "Anotação")
	_button(texts, "Salvar nome e anotação", func() -> void: occurrence_saved.emit(occurrence_name.text, occurrence_note.text))

	generator = GeneratorPanel.new()
	pages[TAB_SUGGEST].add_child(generator)

	var edit_page := pages[TAB_EDIT]
	_note(edit_page, "Nome e cor no mapa")
	var named := _row(edit_page)
	type_name = _edit(named, "Nome do recurso")
	type_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_color = ColorPickerButton.new()
	type_color.edit_alpha = false
	type_color.custom_minimum_size = Vector2(40, 0)
	type_color.tooltip_text = "Cor no mapa"
	named.add_child(type_color)
	_note(edit_page, "Opcionais")
	type_description = _edit(edit_page, "Descrição")
	type_category = _edit(edit_page, "Categoria (metal, mágico…)")
	type_unit = _edit(edit_page, "Unidade (kg, m³…)")
	_button(edit_page, "Salvar", func() -> void:
		type_saved.emit(type_name.text, type_description.text, type_category.text, type_unit.text, type_color.color))
	edit_page.add_child(HSeparator.new())
	_button(edit_page, "Excluir recurso", func() -> void: type_delete_requested.emit()).tooltip_text = \
		"Só funciona quando o recurso não está em lugar nenhum do mapa"


## Troca de aba. Sair de "Sugerir" fecha a prévia (e encerra uma avaliação, guardando as respostas).
func show_tab(index: int) -> void:
	var leaving := tab == TAB_SUGGEST and index != TAB_SUGGEST
	tab = index
	for i in pages.size():
		pages[i].visible = i == index
		tab_buttons[i].set_pressed_no_signal(i == index)
	if leaving:
		generator.leave()


## rows: o que Registry.ResourceTypes devolve.
func show_types(rows: Array, selected: int) -> void:
	types.clear()
	for t in rows:
		var i := types.add_item("● %s  (%d)" % [t.name, t.count])
		types.set_item_custom_fg_color(i, _color(t.rgb).lightened(0.2))
		types.set_item_metadata(i, int(t.id))
		types.set_item_tooltip(i, "Abrir %s (%d no mapa)" % [t.name, t.count])
		if int(t.id) == selected:
			types.select(i)
	types.visible = not rows.is_empty()
	empty_list.visible = rows.is_empty() and query.text == ""


## O recurso aberto ({} = a tela da lista).
func show_type(t: Dictionary) -> void:
	var open := not t.is_empty()
	type_box.visible = open
	list_box.visible = not open
	back_button.visible = open
	title.text = String(t.name).to_upper() if open else "RECURSOS"
	if not open:
		_type = 0
		types.deselect_all()  # senão clicar de novo no mesmo recurso não o reabre
		return
	if int(t.id) != _type:
		_type = int(t.id)
		new_toggle.button_pressed = false
		text_toggle.button_pressed = false
		show_tab(TAB_MAP)
	type_name.text = t.name
	type_description.text = t.description
	type_category.text = t.category
	type_unit.text = t.unit
	type_color.color = _color(t.rgb)


func show_occurrences(rows: Array, selected: int) -> void:
	occurrences.clear()
	_names.clear()
	var counts := {"area": 0, "ponto": 0}  # "Área 1, Área 2…" na ordem de criação: o número interno não diz nada ao autor
	for o in rows:
		counts[o.kind] += 1
		_names[int(o.id)] = o.name if o.name != "" else "%s %d" % ["Área" if o.kind == "area" else "Ponto", counts[o.kind]]
		var i := occurrences.add_item(describe(o, _names[int(o.id)]))
		occurrences.set_item_tooltip(i, describe(o, _names[int(o.id)]))
		occurrences.set_item_metadata(i, int(o.id))
		if int(o.id) == selected:
			occurrences.select(i)
	occurrences.visible = not rows.is_empty()
	empty_occurrences.visible = rows.is_empty()


## O item escolhido no mapa ({} = nenhum).
func show_occurrence(o: Dictionary) -> void:
	occurrence_box.visible = not o.is_empty()
	if o.is_empty():
		return
	occurrence_title.text = _names.get(int(o.id), o.name)
	occurrence_name.text = o.name
	occurrence_note.text = o.note
	why_button.visible = o.origin == "gerada"
	fixed_check.visible = o.origin == "gerada"
	fixed_check.set_pressed_no_signal(o.fixed)
	var reserve: Dictionary = o.get("reserve_info", {})
	reserve_edit.text = "" if reserve.is_empty() or is_nan(reserve.reserve) else _plain(reserve.reserve)
	reserve_line.text = "Quantidade desconhecida: os povoados não extraem daqui." if reserve.is_empty() or is_nan(reserve.reserve) else \
		"Restam %s de %s (%s já extraídos)." % [_plain(reserve.left), _plain(reserve.reserve), _plain(reserve.extracted)]
	var point: bool = o.kind == "ponto"
	_paint_button.visible = not point
	for button in _point_actions:
		button.visible = point


## A prévia de todos os recursos ("" = não há).
func show_all(text: String, can_apply := false) -> void:
	all_summary.text = text
	all_summary.visible = text != ""
	all_actions.visible = can_apply


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
