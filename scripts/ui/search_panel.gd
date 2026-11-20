extends PanelContainer
## Painel da direita: busca nos cadastros (por nome, com filtro de tipo) e a criação de registros novos.
## Só mostra e pede: avisa por sinal; quem busca e cria é o DomainHub.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal query_changed(text: String, kind: String)
signal entity_chosen(id: int)
signal create_requested(kind: String, name: String)
signal society_requested(name: String)
signal calendars_requested
signal types_requested
signal rules_requested

const WIDTH := 320
const SOCIETY_ID := 100  # item do menu "Novo" que não é um tipo

var _query: LineEdit
var _filter: OptionButton
var _new_pop: PopupMenu
var _list: ItemList
var _ids: Array[int] = []


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style())
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	position = Vector2(-12, 12)
	custom_minimum_size = Vector2(WIDTH, 0)
	var box := VBoxContainer.new()
	add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Cadastros"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var new_menu := MenuButton.new()
	new_menu.text = "＋ Novo"
	_new_pop = new_menu.get_popup()
	_new_pop.id_pressed.connect(_on_new)
	new_menu.tooltip_text = "Cria com o texto da busca como nome (pode ser provisório)."
	head.add_child(new_menu)
	var cal_btn := Button.new()
	cal_btn.text = "Calendários…"
	cal_btn.tooltip_text = "Criar e ver calendários locais"
	cal_btn.pressed.connect(func() -> void: calendars_requested.emit())
	head.add_child(cal_btn)
	var types_btn := Button.new()
	types_btn.text = "Tipos…"
	types_btn.tooltip_text = "Criar tipos de entidade, campos e vínculos"
	types_btn.pressed.connect(func() -> void: types_requested.emit())
	head.add_child(types_btn)
	var rules_btn := Button.new()
	rules_btn.text = "Regras…"
	rules_btn.tooltip_text = "Regras que calculam campos, executadas numa data do mundo"
	rules_btn.pressed.connect(func() -> void: rules_requested.emit())
	head.add_child(rules_btn)

	_query = LineEdit.new()
	_query.placeholder_text = "Buscar por nome"
	_query.clear_button_enabled = true
	_query.tooltip_text = "Acha também pelos nomes alternativos e históricos, sem diferenciar acentos."
	_query.text_changed.connect(func(_t: String) -> void: _emit_query())
	box.add_child(_query)

	_filter = OptionButton.new()
	_filter.item_selected.connect(func(_i: int) -> void: _emit_query())
	box.add_child(_filter)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 170)
	_list.item_selected.connect(func(i: int) -> void: entity_chosen.emit(_ids[i]))
	box.add_child(_list)
	refresh_kinds()


## Refaz os menus de tipo (depois de criar um tipo novo). O filtro escolhido fica, se o tipo ainda existir.
func refresh_kinds() -> void:
	var keep := kind_filter() if _filter.item_count > 0 else ""
	var kinds := UiKit.all_kinds()
	_new_pop.clear()
	for i in kinds.size():
		_new_pop.add_item(UiKit.kind_label(kinds[i]), i)
	_new_pop.add_separator()
	_new_pop.add_item("Sociedade (país + cultura + etnia)", SOCIETY_ID)
	_filter.clear()
	_filter.add_item("Todos os tipos")
	for k in kinds:
		_filter.add_item(UiKit.kind_label(k))
	_filter.select(kinds.find(keep) + 1)


## Mostra os resultados (cada um: id, kind, name, match). Não repete o evento de seleção.
func show_results(items: Array, selected_id: int = 0) -> void:
	_list.clear()
	_ids.clear()
	for it in items:
		var text: String = "%s  ·  %s" % [it.name, UiKit.kind_label(it.kind)]
		if it.match != "":
			text += "  (%s)" % it.match
		_list.add_item(text)
		_ids.append(int(it.id))
		if int(it.id) == selected_id:
			_list.select(_ids.size() - 1, false)


func query() -> String:
	return _query.text


func kind_filter() -> String:
	return "" if _filter.selected <= 0 else UiKit.all_kinds()[_filter.selected - 1]


func _emit_query() -> void:
	query_changed.emit(_query.text, kind_filter())


func _on_new(id: int) -> void:
	if id == SOCIETY_ID:
		society_requested.emit(_query.text)
	else:
		create_requested.emit(UiKit.all_kinds()[id], _query.text)
