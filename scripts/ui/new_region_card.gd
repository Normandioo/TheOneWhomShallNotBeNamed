extends PanelContainer
## O cartão "Nova região": depois de pintar uma área sem cadastro selecionado, pergunta o que é (tipo), o nome e a quem pertence (país e, para município,
## província opcional). O tipo e o "pertence a" já vêm sugeridos pelo lugar onde se pintou. Só mostra e pede: quem cria é o TerritoryEditor.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const EntityPicker = preload("res://scripts/ui/entity_picker.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")  # só para o separador de milhares

signal create_requested(kind: String, region_name: String, parent_id: int)
signal more_requested
signal discard_requested

const KINDS := ["pais", "provincia", "municipio", "cultura", "etnia", "raca", "religiao", "idioma"]
const WIDTH := 460

var lookup: Callable   # (texto, tipo) -> [{id, kind, name}], ligado pelo Main

var _kind := "pais"
var _country := {}     # {id, name, share}: o país de cima escolhido ("" = nenhum)
var _province := {}
var _area: Label
var _chips: Dictionary = {}
var _name: LineEdit
var _parents: VBoxContainer
var _create: Button


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	custom_minimum_size.x = WIDTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Nova região"
	UiKit.style_heading(title)
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_area = Label.new()
	_area.modulate = Color(1, 1, 1, 0.7)
	head.add_child(_area)
	box.add_child(_caption("O que é?"))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	box.add_child(chips)
	var group := ButtonGroup.new()
	for k in KINDS:
		var b := Button.new()
		b.text = UiKit.kind_label(k)
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(func() -> void: _set_kind(k))
		chips.add_child(b)
		_chips[k] = b
	box.add_child(_caption("Nome"))
	_name = LineEdit.new()
	_name.placeholder_text = "sem nome"
	box.add_child(_name)
	_parents = VBoxContainer.new()
	box.add_child(_parents)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_create = Button.new()
	_create.add_theme_stylebox_override("normal", UiKit.active_style())
	_create.pressed.connect(func() -> void:
		var parent := 0
		if _kind == "municipio" and not _province.is_empty():
			parent = int(_province.id)
		elif _kind in ["provincia", "municipio"] and not _country.is_empty():
			parent = int(_country.id)
		create_requested.emit(_kind, _name.text.strip_edges(), parent))
	buttons.add_child(_create)
	var more := Button.new()
	more.text = "Pintar mais"
	more.pressed.connect(func() -> void: more_requested.emit())
	buttons.add_child(more)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var discard := Button.new()
	discard.text = "Descartar"
	discard.flat = true
	discard.pressed.connect(func() -> void: discard_requested.emit())
	buttons.add_child(discard)


## info: {area_km2, kind (o tipo sugerido), country: {id, name, share} ou {}, province: {...} ou {}}
func show_draft(info: Dictionary) -> void:
	_area.text = "≈ %s km²" % LayerPanel._thousands(roundi(float(info.area_km2)))
	_country = info.get("country", {})
	_province = info.get("province", {})
	_name.text = ""
	visible = true
	_set_kind(String(info.get("kind", "pais")))
	_name.grab_focus()


func _set_kind(kind: String) -> void:
	_kind = kind
	for k in _chips:
		_chips[k].set_pressed_no_signal(k == kind)
	_create.text = "Criar %s" % UiKit.kind_label(kind).to_lower()
	_refresh_parents()
	reset_size()


func _refresh_parents() -> void:
	for c in _parents.get_children():
		_parents.remove_child(c)
		c.queue_free()
	if not _kind in ["provincia", "municipio"]:
		return
	_parents.add_child(_caption("Pertence a"))
	_parent_row("País", "pais", _country, _pick_country, _clear_country)
	if _kind == "municipio":
		_parent_row("Província (opcional)", "provincia", _province, _pick_province, _clear_province)


func _pick_country(id: int, parent_name: String) -> void:
	_country = {"id": id, "name": parent_name, "share": 1.0}
	_province = {}  # trocar o país solta a província escolhida antes
	_refresh_parents()


func _clear_country() -> void:
	_country = {}
	_province = {}
	_refresh_parents()


func _pick_province(id: int, parent_name: String) -> void:
	_province = {"id": id, "name": parent_name, "share": 1.0}
	_refresh_parents()


func _clear_province() -> void:
	_province = {}
	_refresh_parents()


func _parent_row(label_text: String, parent_kind: String, current: Dictionary, on_pick: Callable, on_clear: Callable) -> void:
	var row := HBoxContainer.new()
	_parents.add_child(row)
	var label := Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size.x = 150
	row.add_child(label)
	var value := Label.new()
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if current.is_empty():
		value.text = "nenhum"
		value.modulate = Color(1, 1, 1, 0.6)
	else:
		var share := float(current.get("share", 0.0))
		value.text = "%s%s" % [current.name, " · cobre %d%% da área" % roundi(share * 100.0) if share > 0.0 and share < 1.0 else ""]
	row.add_child(value)
	if not current.is_empty():
		var clear := Button.new()
		clear.text = "✕"
		clear.flat = true
		clear.tooltip_text = "Tirar"
		clear.pressed.connect(on_clear)
		row.add_child(clear)
	var picker := EntityPicker.new("trocar: digite o nome", parent_kind, lookup, [])
	picker.picked.connect(func(id: int) -> void: on_pick.call(id, picker.picked_name))
	_parents.add_child(picker)


func _unhandled_key_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		discard_requested.emit()
		get_viewport().set_input_as_handled()


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(1, 1, 1, 0.65)
	return l
