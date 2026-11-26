extends PanelContainer
## O cartão da região nova, em dois momentos. ANTES de pintar sem cadastro selecionado: só "O que você vai pintar?", para o mapa já
## mostrar aquele tipo de coisa. DEPOIS do desenho: o nome e, numa subdivisão, como ela se chama e dentro de quê fica (o país ou uma
## subdivisão direta dele), sugerido pelo lugar onde se pintou; o tipo ainda dá para trocar. Só mostra e pede: quem cria é o TerritoryEditor.
## "provincia" e "municipio" são os dois níveis da subdivisão: o nível vem de onde ela fica.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const EntityPicker = preload("res://scripts/ui/entity_picker.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")  # só para o separador de milhares

signal create_requested(kind: String, region_name: String, parent_id: int, division_name: String)
signal kind_chosen(kind: String)   # a escolha de antes de pintar
signal kind_changed(kind: String)  # o tipo foi trocado depois do desenho: o mapa acompanha
signal more_requested
signal discard_requested

const KINDS := ["pais", "provincia", "cultura", "etnia", "raca", "religiao", "idioma"]
const SUBDIVISIONS := ["provincia", "municipio"]
const CHIPS := 6  # quantos nomes de divisão aparecem como botão, além de "Outro…"
const WIDTH := 460
const NEW_TITLE := {"pais": "Novo país", "provincia": "Nova subdivisão", "municipio": "Nova subdivisão", "cultura": "Nova cultura", "etnia": "Nova etnia",
	"raca": "Nova raça", "religiao": "Nova religião", "idioma": "Novo idioma"}

var choosing := false  # perguntando o tipo, antes de pintar
var _title: Label
var _kind_caption: Label
var _chip_row: HFlowContainer
var _change: Button
var _form: VBoxContainer
var _more: Button
var _discard: Button

var lookup: Callable   # (texto, tipo) -> [{id, kind, name, label}], ligado pelo Main
var naming: Callable   # (id do de cima, nível) -> {inherited, suggestions}, ligado pelo Main

var _kind := "pais"
var _parent := {}      # {id, name, kind, share}: dentro de quê a subdivisão fica ({} = nada)
var _division_name := ""   # o nome escolhido para o tipo da divisão ("" = o que o país já usa)
var _typing := false       # "Outro…" aberto
var other_name: LineEdit
var name_chips := {}       # nome -> botão
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
	_title = Label.new()
	UiKit.style_heading(_title)
	_title.add_theme_font_size_override("font_size", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_area = Label.new()
	_area.modulate = Color(1, 1, 1, 0.7)
	head.add_child(_area)
	_change = Button.new()
	_change.text = "Trocar tipo"
	_change.flat = true
	_change.add_theme_font_size_override("font_size", 12)
	_change.pressed.connect(func() -> void:
		_chip_row.visible = not _chip_row.visible
		reset_size())
	head.add_child(_change)
	_kind_caption = _caption("O mapa passa a mostrar o tipo escolhido.")
	box.add_child(_kind_caption)
	var chips := HFlowContainer.new()
	_chip_row = chips
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	box.add_child(chips)
	var group := ButtonGroup.new()
	for k in KINDS:
		var b := Button.new()
		b.text = UiKit.short_label(k)
		b.toggle_mode = true
		b.button_group = group
		var tint: String = {"pais": "politics", "provincia": "government", "municipio": "organization", "cultura": "culture", "etnia": "ethnicity",
			"raca": "race", "religiao": "religion", "idioma": "language"}[k]
		b.icon = UiIcons.get_icon(tint, 16)
		UiKit.tint_icon(b, tint)
		b.pressed.connect(func() -> void:
			if choosing:
				kind_chosen.emit(k)
			else:
				_set_kind(k)
				_chip_row.visible = false
				reset_size()
				kind_changed.emit(k))
		chips.add_child(b)
		_chips[k] = b
	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 8)
	box.add_child(_form)
	_form.add_child(_caption("Nome"))
	_name = LineEdit.new()
	_name.placeholder_text = "sem nome"
	_form.add_child(_name)
	_parents = VBoxContainer.new()
	_form.add_child(_parents)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_create = Button.new()
	_create.add_theme_stylebox_override("normal", UiKit.active_style())
	_create.pressed.connect(func() -> void:
		var parent := int(_parent.get("id", 0)) if _kind in SUBDIVISIONS else 0
		create_requested.emit(_kind, _name.text.strip_edges(), parent, chosen_division_name() if _kind in SUBDIVISIONS else ""))
	buttons.add_child(_create)
	_more = Button.new()
	_more.text = "Pintar mais"
	_more.pressed.connect(func() -> void: more_requested.emit())
	buttons.add_child(_more)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_discard = Button.new()
	_discard.flat = true
	_discard.pressed.connect(func() -> void:
		if choosing:
			hide()
		discard_requested.emit())
	buttons.add_child(_discard)


## Antes de pintar: só a pergunta do tipo.
func show_choice() -> void:
	choosing = true
	_title.text = "O que você vai pintar?"
	_area.text = ""
	for k in _chips:
		_chips[k].set_pressed_no_signal(false)
	_chip_row.visible = true
	_kind_caption.visible = true
	_change.visible = false
	_form.visible = false
	_create.visible = false
	_more.visible = false
	_discard.text = "Cancelar"
	visible = true
	reset_size()
	reset_size.call_deferred()  # a altura dos tipos só se sabe depois de a linha deles ter largura


## info: {area_km2, kind (o escolhido antes de pintar, ou o sugerido), country: {id, name, share} ou {}, province: {...} ou {}}; a
## província é a subdivisão direta em que a área está quase toda: se há uma, a nova fica dentro dela.
func show_draft(info: Dictionary) -> void:
	choosing = false
	_chip_row.visible = false
	_kind_caption.visible = false
	_change.visible = true
	_form.visible = true
	_create.visible = true
	_more.visible = true
	_discard.text = "Descartar"
	_area.text = "≈ %s km²" % LayerPanel._thousands(roundi(float(info.area_km2)))
	var inside: Dictionary = info.get("province", {})
	var country: Dictionary = info.get("country", {})
	_parent = {}
	if not inside.is_empty():
		_parent = inside.merged({"kind": "provincia"})
	elif not country.is_empty():
		_parent = country.merged({"kind": "pais"})
	_name.text = ""
	_division_name = ""
	_typing = false
	visible = true
	_set_kind(String(info.get("kind", "pais")))
	_name.grab_focus()


func _set_kind(kind: String) -> void:
	_kind = kind
	if kind in SUBDIVISIONS:  # o nível vem de onde ela fica: dentro de uma subdivisão é o 2º
		_kind = "municipio" if String(_parent.get("kind", "")) == "provincia" else "provincia"
	for k in _chips:
		_chips[k].set_pressed_no_signal(k == kind or (k == "provincia" and kind == "municipio"))
	_title.text = NEW_TITLE.get(_kind, "Nova região")
	_refresh_parents()
	_refresh_create()
	reset_size()


## Como a subdivisão vai se chamar: o escolhido, ou o que o país já usa naquele nível.
func chosen_division_name() -> String:
	return _division_name if _division_name != "" else String(_naming().get("inherited", ""))


func _naming() -> Dictionary:
	if not naming.is_valid() or not _kind in SUBDIVISIONS:
		return {}
	return naming.call(int(_parent.get("id", 0)), 2 if _kind == "municipio" else 1)


func _refresh_create() -> void:
	var what := UiKit.short_label(_kind)
	if _kind in SUBDIVISIONS and chosen_division_name() != "":
		what = chosen_division_name()
	_create.text = "Criar %s" % what.to_lower()


func _refresh_parents() -> void:
	for c in _parents.get_children():
		_parents.remove_child(c)
		c.queue_free()
	name_chips.clear()
	other_name = null
	if not _kind in SUBDIVISIONS:
		return
	_name_choice()
	_parents.add_child(_caption("Fica dentro de"))
	_parent_row()


func _name_choice() -> void:
	var info := _naming()
	if info.is_empty():
		return
	_parents.add_child(_caption("Como se chama esse tipo de divisão?"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_parents.add_child(flow)
	var current := chosen_division_name()
	var names: Array = Array(info.suggestions).slice(0, CHIPS)
	if not current in names:
		names.push_front(current)
	for n in names + ["Outro…"]:
		var b := Button.new()
		b.text = String(n)
		b.toggle_mode = true
		b.set_pressed_no_signal((n == "Outro…") if _typing else n == current)
		var value := String(n)
		b.pressed.connect(func() -> void:
			_typing = value == "Outro…"
			_division_name = "" if _typing else value
			_refresh_parents.call_deferred()
			_refresh_create())
		flow.add_child(b)
		name_chips[value] = b
	if _typing:
		other_name = LineEdit.new()
		other_name.placeholder_text = "escreva o nome: Marca, Distrito…"
		other_name.max_length = 40
		other_name.text = _division_name
		other_name.text_changed.connect(func(t: String) -> void:
			_division_name = t.strip_edges()
			_refresh_create())
		_parents.add_child(other_name)


## Escolhe dentro de quê a subdivisão fica ({} = nada); o nível (e o mapa) acompanham.
func set_parent_choice(parent: Dictionary) -> void:
	var before := _kind
	_parent = parent
	_set_kind("provincia")
	if _kind != before:
		kind_changed.emit(_kind)


func _parent_row() -> void:
	var row := HBoxContainer.new()
	_parents.add_child(row)
	var value := Label.new()
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if _parent.is_empty():
		value.text = "nada (sem país)"
		value.modulate = Color(1, 1, 1, 0.6)
	else:
		var share := float(_parent.get("share", 0.0))
		var what := "País" if _parent.kind == "pais" else String(_parent.get("label", "subdivisão"))
		value.text = "%s · %s%s" % [_parent.name, what, " · cobre %d%% da área" % roundi(share * 100.0) if share > 0.0 and share < 1.0 else ""]
	row.add_child(value)
	if not _parent.is_empty():
		var clear := Button.new()
		clear.text = "✕"
		clear.flat = true
		clear.tooltip_text = "Tirar"
		clear.pressed.connect(func() -> void: set_parent_choice.call_deferred({}))
		row.add_child(clear)
	var picker := EntityPicker.new("trocar: digite o nome do país ou da subdivisão", "", _parent_lookup, [])
	picker.picked.connect(func(id: int) -> void:
		set_parent_choice(picker.picked_item.merged({"share": 1.0}, true)))
	_parents.add_child(picker)
	var note := _caption("O próprio país ou uma subdivisão direta dele. A pintura fica cortada nas bordas do escolhido.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = WIDTH - 40
	_parents.add_child(note)


## Só países e subdivisões do 1º nível podem ter uma subdivisão dentro.
func _parent_lookup(text: String, _kind_filter: String) -> Array:
	var found: Array = lookup.call(text, "") if lookup.is_valid() else []
	return found.filter(func(it) -> bool: return String(it.kind) in ["pais", "provincia"])


func _unhandled_key_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		if choosing:
			hide()
		discard_requested.emit()
		get_viewport().set_input_as_handled()


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(1, 1, 1, 0.65)
	return l
