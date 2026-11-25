extends PanelContainer
## O painel de recursos: o catálogo, o recurso escolhido, as ocorrências dele e a escolhida. Os detalhes do recurso ficam recolhidos.
## Só mostra e pede: avisa por sinais; quem grava é o Registry, pelo resource_controller.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal query_changed
signal type_chosen(id: int)
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
signal delete_requested
signal focus_requested
signal cancel_requested                    # Esc enquanto espera um clique
signal closed

const WIDTH := 320

var query: LineEdit
var types: ItemList
var occurrences: ItemList
var new_name: LineEdit
var type_name: LineEdit
var type_color: ColorPickerButton
var type_description: LineEdit
var type_category: LineEdit
var type_unit: LineEdit
var occurrence_name: LineEdit
var occurrence_note: LineEdit
var _point_actions: Array = []  # mover e duplicar: só pontos
var _paint_button: Button
var message: Label
var type_box: VBoxContainer
var occurrence_box: VBoxContainer
var waiting := false  # esperando um clique no globo


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	custom_minimum_size = Vector2(WIDTH, 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := _column(scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var head := _row(box)
	_heading(head, "RECURSOS").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "✕", func() -> void: closed.emit())
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(WIDTH - 40, 0)
	message.modulate = Color(1.0, 0.85, 0.4)
	message.hide()
	box.add_child(message)
	query = _edit(box, "Buscar recurso")
	query.text_changed.connect(func(_t: String) -> void: query_changed.emit())
	types = _list(box, 130, "Catálogo de recursos")
	types.item_selected.connect(func(i: int) -> void: type_chosen.emit(types.get_item_metadata(i)))
	var create := _row(box)
	new_name = _edit(create, "Nome do recurso novo")
	new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_name.text_submitted.connect(func(t: String) -> void: create_requested.emit(t))
	_button(create, "Criar", func() -> void: create_requested.emit(new_name.text))

	type_box = _column(box)
	var title := _row(type_box)
	type_name = _edit(title, "Nome do recurso")
	type_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_color = ColorPickerButton.new()
	type_color.edit_alpha = false
	type_color.custom_minimum_size = Vector2(40, 0)
	type_color.tooltip_text = "Cor no mapa"
	title.add_child(type_color)
	var details_toggle := _button(type_box, "Detalhes (opcionais)", Callable())
	details_toggle.toggle_mode = true
	var details := _column(type_box)
	details.hide()
	details_toggle.toggled.connect(func(open: bool) -> void: details.visible = open)
	type_description = _edit(details, "Descrição")
	type_category = _edit(details, "Categoria (metal, mágico…)")
	type_unit = _edit(details, "Unidade (kg, m³…)")
	var type_actions := _row(type_box)
	_button(type_actions, "Salvar recurso", func() -> void:
		type_saved.emit(type_name.text, type_description.text, type_category.text, type_unit.text, type_color.color))
	_button(type_actions, "Excluir recurso", func() -> void: type_delete_requested.emit())

	_heading(type_box, "Ocorrências")
	var add := _row(type_box)
	_button(add, "Pintar área nova", func() -> void: area_requested.emit())
	_button(add, "Colocar ponto", func() -> void: point_requested.emit())
	occurrences = _list(type_box, 120, "Ocorrências do recurso")
	occurrences.item_selected.connect(func(i: int) -> void: occurrence_chosen.emit(occurrences.get_item_metadata(i)))

	occurrence_box = _column(type_box)
	occurrence_name = _edit(occurrence_box, "Nome da ocorrência (opcional)")
	occurrence_note = _edit(occurrence_box, "Anotação")
	_button(occurrence_box, "Salvar nome e anotação", func() -> void: occurrence_saved.emit(occurrence_name.text, occurrence_note.text))
	var actions := _row(occurrence_box)
	_button(actions, "Ver", func() -> void: focus_requested.emit())
	_paint_button = _button(actions, "Pintar", func() -> void: paint_requested.emit())
	_point_actions = [_button(actions, "Mover", func() -> void: move_requested.emit()),
		_button(actions, "Duplicar", func() -> void: duplicate_requested.emit())]
	_button(actions, "Excluir", func() -> void: delete_requested.emit())
	show_type({})
	show_occurrence({})


## rows: o que Registry.ResourceTypes devolve.
func show_types(rows: Array, selected: int) -> void:
	types.clear()
	for t in rows:
		var i := types.add_item("● %s (%d)" % [t.name, t.count])
		types.set_item_custom_fg_color(i, _color(t.rgb).lightened(0.2))
		types.set_item_metadata(i, int(t.id))
		if int(t.id) == selected:
			types.select(i)


## O recurso escolhido ({} = nenhum).
func show_type(t: Dictionary) -> void:
	type_box.visible = not t.is_empty()
	if t.is_empty():
		return
	type_name.text = t.name
	type_description.text = t.description
	type_category.text = t.category
	type_unit.text = t.unit
	type_color.color = _color(t.rgb)


func show_occurrences(rows: Array, selected: int) -> void:
	occurrences.clear()
	for o in rows:
		var i := occurrences.add_item(describe(o))
		occurrences.set_item_metadata(i, int(o.id))
		if int(o.id) == selected:
			occurrences.select(i)


## A ocorrência escolhida ({} = nenhuma).
func show_occurrence(o: Dictionary) -> void:
	occurrence_box.visible = not o.is_empty()
	if o.is_empty():
		return
	occurrence_name.text = o.name
	occurrence_note.text = o.note
	var point: bool = o.kind == "ponto"
	_paint_button.visible = not point
	for button in _point_actions:
		button.visible = point


func show_message(text: String) -> void:
	message.text = text
	message.visible = text != ""


## o: uma linha de Registry.Occurrences; as áreas trazem area_km2.
static func describe(o: Dictionary) -> String:
	var shape := "ponto"
	if o.kind == "area":
		shape = "área, %d km²" % roundi(o.area_km2) if o.area_km2 > 0.0 else "área ainda sem pintura"
	return "%s · %s" % [o.name if o.name != "" else "nº %d" % o.id, shape]


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
