extends HBoxContainer
## Como uma divisão se chama: as sugestões num menu e "Outro…" para escrever. Só avisa por `chosen` (adiado: quem reage refaz a ficha).

signal chosen(name: String)

const OTHER := "Outro…"

var menu: OptionButton
var edit: LineEdit
var _current := ""


func _init(current: String, suggestions: Array, label: String) -> void:
	_current = current
	menu = OptionButton.new()
	menu.accessibility_name = label
	menu.fit_to_longest_item = false
	menu.custom_minimum_size.x = 150
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var names: Array = Array(suggestions)
	if not current in names:
		names.append(current)
	for n in names:
		menu.add_item(String(n))
	menu.add_item(OTHER)
	menu.select(names.find(current))
	add_child(menu)
	edit = LineEdit.new()
	edit.placeholder_text = "escreva o nome"
	edit.accessibility_name = label + " (escrito)"
	edit.max_length = 40
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.hide()
	add_child(edit)
	menu.item_selected.connect(func(i: int) -> void:
		if menu.get_item_text(i) == OTHER:
			menu.hide()
			edit.show()
			edit.grab_focus()
		else:
			_choose(menu.get_item_text(i)))
	edit.text_submitted.connect(func(text: String) -> void: _choose(text))
	edit.focus_exited.connect(func() -> void:
		if edit.text.strip_edges() != "":
			_choose(edit.text))


func _choose(text: String) -> void:
	var value := text.strip_edges()
	if value == "" or value == _current:
		return
	_current = value
	chosen.emit.call_deferred(value)
