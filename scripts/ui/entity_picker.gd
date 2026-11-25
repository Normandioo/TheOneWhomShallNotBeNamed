extends VBoxContainer
## Escolher um cadastro digitando: um campo de busca com a lista de resultados logo embaixo (sem menu suspenso). Clicar num resultado escolhe.
## Quem usa dá `lookup` (texto, tipo -> [{id, kind, name}]); o seletor só mostra e avisa por `picked` (adiado: quem reage costuma refazer a ficha).

signal picked(id: int)

const ROWS := 5

var lookup: Callable
var kind := ""        # só cadastros deste tipo ("" = qualquer)
var exclude: Array = []  # ids que não aparecem (o próprio cadastro, os que já estão ligados)

var _edit: LineEdit
var _list: ItemList
var _ids: Array = []
var _names: Array = []
var picked_name := ""  # o nome do último escolhido (já preenchido quando `picked` chega)


func _init(placeholder := "buscar pelo nome", search_kind := "", lookup_fn := Callable(), excluded := []) -> void:
	kind = search_kind
	lookup = lookup_fn
	exclude = excluded
	add_theme_constant_override("separation", 2)
	_edit = LineEdit.new()
	_edit.placeholder_text = placeholder
	_edit.clear_button_enabled = true
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.text_changed.connect(func(_t: String) -> void: _refresh())
	_edit.focus_entered.connect(_refresh)
	_edit.focus_exited.connect(func() -> void:
		if _edit.text == "":
			_hide_list.call_deferred())
	add_child(_edit)
	_list = ItemList.new()
	_list.visible = false
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _ids.size():
			var id: int = _ids[i]
			picked_name = _names[i]
			_edit.text = ""
			_hide_list()
			picked.emit.call_deferred(id))
	add_child(_list)


func _refresh() -> void:
	if not lookup.is_valid():
		return
	_list.clear()
	_ids.clear()
	_names.clear()
	for it in lookup.call(_edit.text, kind):
		if int(it.id) in exclude:
			continue
		_list.add_item(String(it.name) if kind != "" else "%s · %s" % [it.name, it.kind])
		_ids.append(int(it.id))
		_names.append(String(it.name))
		if _ids.size() >= 30:
			break
	_list.visible = not _ids.is_empty()
	_list.custom_minimum_size.y = minf(_ids.size(), ROWS) * 26.0 + 6.0


func _hide_list() -> void:
	if is_instance_valid(_list):
		_list.visible = false
