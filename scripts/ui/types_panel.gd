extends Node
## Designer de tipos (E2): criar tipos de entidade, campos personalizados (com validação) e tipos de vínculo, sem mudar código.
## Só mostra e pede: quem cria é o DomainHub (Registry).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const FIELD_TYPES := [["text", "Texto"], ["number", "Número"], ["choice", "Escolha (lista)"], ["bool", "Sim/não"]]

signal type_requested(label: String)
signal field_requested(label: String, type: String, unit: String, options: String, min_value: float, max_value: float, kinds: PackedStringArray)
signal layer_requested(label: String, rgb: int, kinds: PackedStringArray)
signal relation_requested(out_label: String, in_label: String, src_kind: String, dst_kind: String)

var _dialog: AcceptDialog
var _message: Label
var _type_name: LineEdit
var _field_name: LineEdit
var _field_type: OptionButton
var _unit: LineEdit
var _options: TextEdit
var _min: LineEdit
var _max: LineEdit
var _number_row: HBoxContainer
var _kind_checks: VBoxContainer
var _rel_out: LineEdit
var _rel_in: LineEdit
var _rel_src: OptionButton
var _rel_dst: OptionButton
var _layer_name: LineEdit
var _layer_color: ColorPickerButton
var _layer_checks: VBoxContainer
var _codes: Array = []  # códigos dos tipos, na ordem dos menus


func _ready() -> void:
	_dialog = UiKit.themed(AcceptDialog.new())
	_dialog.title = "Tipos, campos e vínculos"
	_dialog.ok_button_text = "Fechar"
	_dialog.min_size = Vector2i(520, 560)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dialog.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.modulate = Color(1.0, 0.85, 0.4)
	box.add_child(_message)

	_title(box, "Novo tipo de entidade")
	var row := HBoxContainer.new()
	box.add_child(row)
	_type_name = _line(row, "Nome do tipo (ex.: Fortaleza)")
	_button(row, "Criar tipo", func() -> void: type_requested.emit(_type_name.text))

	_title(box, "Novo campo")
	var f1 := HBoxContainer.new()
	box.add_child(f1)
	_field_name = _line(f1, "Nome do campo (ex.: Guarnição)")
	_field_type = OptionButton.new()
	for t in FIELD_TYPES:
		_field_type.add_item(t[1])
	_field_type.item_selected.connect(func(_i: int) -> void: _show_field_extras())
	f1.add_child(_field_type)
	_number_row = HBoxContainer.new()
	box.add_child(_number_row)
	_unit = _line(_number_row, "Unidade (opcional)")
	_min = _line(_number_row, "Mínimo")
	_max = _line(_number_row, "Máximo")
	_options = TextEdit.new()
	_options.placeholder_text = "Uma opção por linha (ao menos 2)"
	_options.custom_minimum_size = Vector2(0, 70)
	box.add_child(_options)
	var applies := Label.new()
	applies.text = "Vale para os tipos:"
	box.add_child(applies)
	_kind_checks = VBoxContainer.new()
	box.add_child(_kind_checks)
	_button(box, "Adicionar campo", _request_field)

	_title(box, "Novo tipo de vínculo")
	var r1 := HBoxContainer.new()
	box.add_child(r1)
	_rel_out = _line(r1, "Na origem (ex.: Protege)")
	_rel_in = _line(r1, "No destino (ex.: Protegida por)")
	var r2 := HBoxContainer.new()
	box.add_child(r2)
	_rel_src = OptionButton.new()
	_rel_dst = OptionButton.new()
	for pair in [["De:", _rel_src], ["Para:", _rel_dst]]:
		var l := Label.new()
		l.text = pair[0]
		r2.add_child(l)
		r2.add_child(pair[1])
	_button(box, "Criar vínculo", func() -> void:
		relation_requested.emit(_rel_out.text, _rel_in.text, _menu_code(_rel_src), _menu_code(_rel_dst)))
	_title(box, "Nova camada do mapa")
	var l1 := HBoxContainer.new()
	box.add_child(l1)
	_layer_name = _line(l1, "Nome da camada (ex.: Fortificações)")
	_layer_color = ColorPickerButton.new()
	_layer_color.edit_alpha = false
	_layer_color.color = Color(0.85, 0.85, 0.85)
	_layer_color.custom_minimum_size = Vector2(60, 0)
	l1.add_child(_layer_color)
	var shows := Label.new()
	shows.text = "Mostra os tipos (cada tipo fica numa camada só):"
	box.add_child(shows)
	_layer_checks = VBoxContainer.new()
	box.add_child(_layer_checks)
	_button(box, "Criar camada", func() -> void:
		var c := _layer_color.color
		layer_requested.emit(_layer_name.text, (roundi(c.r * 255) << 16) | (roundi(c.g * 255) << 8) | roundi(c.b * 255), _checked(_layer_checks)))
	add_child(_dialog)
	_show_field_extras()


func open_dialog() -> void:
	_message.text = ""
	_dialog.popup_centered()


## Os tipos que existem ({code, label}): refaz os menus e as caixas de "vale para".
func show_types(types: Array) -> void:
	_codes.clear()
	for holder in [_kind_checks, _layer_checks]:
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
	for m in [_rel_src, _rel_dst]:
		m.clear()
		m.add_item("Qualquer tipo")
	for t in types:
		_codes.append(String(t.code))
		var check := CheckBox.new()
		check.text = String(t.label)
		check.set_meta("code", String(t.code))
		_kind_checks.add_child(check)
		var lcheck := CheckBox.new()
		lcheck.text = String(t.label)
		lcheck.set_meta("code", String(t.code))
		_layer_checks.add_child(lcheck)
		for m in [_rel_src, _rel_dst]:
			m.add_item(String(t.label))


func show_message(text: String) -> void:
	_message.text = text


func clear_inputs() -> void:
	for e in [_type_name, _field_name, _unit, _min, _max, _rel_out, _rel_in, _layer_name]:
		e.text = ""
	_options.text = ""


func _checked(holder: VBoxContainer) -> PackedStringArray:
	var kinds := PackedStringArray()
	for c in holder.get_children():
		if c is CheckBox and c.button_pressed:
			kinds.append(c.get_meta("code"))
	return kinds


func _request_field() -> void:
	var kinds := _checked(_kind_checks)
	var type: String = FIELD_TYPES[_field_type.selected][0]
	field_requested.emit(_field_name.text, type, _unit.text, _options.text, _number(_min.text), _number(_max.text), kinds)


func _show_field_extras() -> void:
	var type: String = FIELD_TYPES[_field_type.selected][0]
	_number_row.visible = type == "number"
	_options.visible = type == "choice"


func _menu_code(menu: OptionButton) -> String:
	return "" if menu.selected <= 0 else _codes[menu.selected - 1]


static func _number(text: String) -> float:
	text = text.strip_edges().replace(",", ".")
	return text.to_float() if text.is_valid_float() else NAN


func _title(box: VBoxContainer, text: String) -> void:
	box.add_child(HSeparator.new())
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	box.add_child(l)


func _line(parent: Control, hint: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(110, 0)
	parent.add_child(e)
	return e


func _button(parent: Control, text: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	parent.add_child(b)
