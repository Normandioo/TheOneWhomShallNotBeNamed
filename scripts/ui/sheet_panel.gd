extends PanelContainer
## A ficha de um cadastro, à esquerda da busca: identidade, resumo, etiquetas, nomes, o conteúdo do tipo (gerado das definições
## de campo, com os campos vazios recolhidos em "Adicionar informação") e as relações. Só mostra e pede: avisa por sinal quando
## o usuário edita; o DomainHub grava no Registry e devolve o que for preciso mostrar.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal name_changed(text: String)           # correção de grafia do nome atual (não é mudança histórica)
signal summary_changed(text: String)
signal field_edited(code: String, state: String, value: String)  # state: known | unknown | na; known + "" = limpar
signal alias_added(role: String, name: String)
signal tag_added(tag: String)
signal tag_removed(tag: String)
signal link_added(type: String, other_id: int)
signal link_removed(link_id: int)
signal link_search(text: String, dst_kind: String)
signal open_entity(id: int)
signal duplicate_requested(copy_links: bool)
signal delete_requested
signal delete_confirmed
signal closed

const WIDTH := 440
const FOREVER := 9223372036854775807
const STATES := ["known", "unknown", "na"]
const STATE_LABELS := ["Valor", "Desconhecido", "Não se aplica"]
const ROLES := [
	["alternativo", "Nome alternativo"], ["historico", "Nome histórico"], ["autodenominacao", "Autodenominação"],
	["exonimo", "Exônimo"], ["oficial", "Nome oficial"], ["popular", "Nome popular"], ["gentilico", "Gentílico"],
	["etnonimo", "Etnônimo"], ["denominacao_coletiva", "Denominação coletiva"],
]

var _title: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _confirm: ConfirmationDialog
var _sheet := {}
var _fields := {}          # código -> {row, state, editor, type, last_state, last_value}
var _add_menu: OptionButton
var _types: Array = []     # tipos de vínculo que esta ficha pode criar
var _link_type: OptionButton
var _link_query: LineEdit
var _link_candidates: OptionButton


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -(WIDTH + 320 + 24)  # à esquerda do painel de busca
	offset_right = -(320 + 24)
	offset_top = 80      # abaixo da barra de ferramentas (topo, no centro)
	offset_bottom = -128  # acima da barra de tempo (embaixo, à esquerda)
	var root := VBoxContainer.new()
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	head.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Excluir cadastro"
	_confirm.confirmed.connect(func() -> void: delete_confirmed.emit())
	add_child(_confirm)


func current_id() -> int:
	return int(_sheet.get("id", 0))


## Mostra a ficha (o Dictionary de Registry.Sheet) e os tipos de vínculo que ela pode criar (Registry.LinkTypesFor).
func show_sheet(sheet: Dictionary, link_types: Array) -> void:
	var keep := _scroll.scroll_vertical if int(sheet.id) == current_id() else 0
	_sheet = sheet
	_types = link_types
	visible = true
	_title.text = "Ficha · " + UiKit.kind_label(sheet.kind)
	if _body != null:
		_scroll.remove_child(_body)
		_body.queue_free()
	_fields.clear()
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_build_identity()
	_build_names()
	_build_content()
	_build_links()
	_build_footer()
	_scroll.set_deferred("scroll_vertical", keep)


func hide_sheet() -> void:
	visible = false
	_sheet = {}


## O que ficou gravado num campo depois de uma edição (corrige o que o usuário digitou se foi recusado ou normalizado).
func update_field(code: String, state: String, value: String) -> void:
	if not _fields.has(code):
		return
	var f: Dictionary = _fields[code]
	f.last_state = state
	f.last_value = value
	f.state.select(maxi(STATES.find(state), 0))
	_write_editor(f, value)
	f.editor.visible = state == "known" or state == "unfilled"


## Candidatos para o vínculo que está sendo criado (cada um: id, kind, name).
func show_link_candidates(items: Array) -> void:
	if _link_candidates == null:
		return
	_link_candidates.clear()
	for it in items:
		if int(it.id) == current_id():
			continue
		_link_candidates.add_item("%s · %s" % [it.name, UiKit.kind_label(it.kind)])
		_link_candidates.set_item_metadata(_link_candidates.item_count - 1, int(it.id))


func confirm_delete(name: String, links: int) -> void:
	_confirm.dialog_text = "Excluir \"%s\"?\n%s\nIsto é correção de um cadastro criado por engano, e não pode ser desfeito." % [
		name, "Nenhum vínculo será apagado." if links == 0 else "%d vínculo(s) com outros cadastros serão apagados." % links]
	_confirm.popup_centered()


# --- seções -------------------------------------------------------------------------------------------------------

func _build_identity() -> void:
	var name_edit := LineEdit.new()
	name_edit.text = _sheet.name
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.tooltip_text = "Corrige a grafia do nome. Uma mudança de nome no mundo (com data) é outro registro."
	var last: Array = [name_edit.text]
	var commit := func() -> void:
		var t := name_edit.text.strip_edges()
		if t == "":
			name_edit.text = last[0]  # o nome nunca fica vazio
		elif t != last[0]:
			last[0] = t
			name_changed.emit(t)
	name_edit.text_submitted.connect(func(_t: String) -> void: commit.call())
	name_edit.focus_exited.connect(commit)
	_body.add_child(name_edit)

	_label("Resumo")
	var summary := TextEdit.new()
	summary.text = _sheet.summary
	summary.custom_minimum_size = Vector2(0, 64)
	summary.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	summary.placeholder_text = "Opcional. Pode ficar vazio."
	var last_summary: Array = [summary.text]
	summary.focus_exited.connect(func() -> void:
		if summary.text != last_summary[0]:
			last_summary[0] = summary.text
			summary_changed.emit(summary.text))
	_body.add_child(summary)

	var tags := HFlowContainer.new()
	_body.add_child(tags)
	for t in _sheet.tags:
		var b := Button.new()
		b.text = "%s ✕" % t
		b.flat = true
		b.tooltip_text = "Remover a etiqueta"
		b.pressed.connect(func() -> void: tag_removed.emit(t))
		tags.add_child(b)
	var new_tag := LineEdit.new()
	new_tag.placeholder_text = "＋ etiqueta"
	new_tag.custom_minimum_size = Vector2(110, 0)
	new_tag.text_submitted.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			tag_added.emit(t.strip_edges()))
	tags.add_child(new_tag)


func _build_names() -> void:
	var box := _section("Nomes")
	for n in _sheet.names:
		var text := ""
		if n.role == "principal":
			if n.to == FOREVER:
				continue  # o nome atual está no alto da ficha
			text = "Nome anterior: " + n.name
		else:
			text = "%s: %s" % [_role_label(n.role), n.name]
			if n.lang != "":
				text += "  (%s)" % n.lang
		box.add_child(_note(text))
	var row := HBoxContainer.new()
	box.add_child(row)
	var role := OptionButton.new()
	for r in ROLES:
		role.add_item(r[1])
	row.add_child(role)
	var edit := LineEdit.new()
	edit.placeholder_text = "novo nome"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var add := func() -> void:
		if edit.text.strip_edges() != "":
			alias_added.emit(ROLES[role.selected][0], edit.text.strip_edges())
	edit.text_submitted.connect(func(_t: String) -> void: add.call())
	var btn := Button.new()
	btn.text = "＋"
	btn.pressed.connect(add)
	row.add_child(btn)


func _build_content() -> void:
	var box := _section("Conteúdo")
	_add_menu = OptionButton.new()
	_add_menu.add_item("＋ Adicionar informação…")
	box.add_child(_add_menu)
	var hidden: Array = []
	for f in _sheet.fields:
		var entry := _make_field(f)
		box.add_child(entry.row)
		if f.state == "unfilled":
			entry.row.visible = false
			hidden.append(f)
	for f in hidden:
		_add_menu.add_item(f.label)
		_add_menu.set_item_metadata(_add_menu.item_count - 1, f.code)
	_add_menu.visible = hidden.size() > 0
	_add_menu.item_selected.connect(func(i: int) -> void:
		if i == 0:
			return
		var code: String = _add_menu.get_item_metadata(i)
		_fields[code].row.visible = true
		_add_menu.remove_item(i)
		_add_menu.select(0)
		_add_menu.visible = _add_menu.item_count > 1)


func _make_field(f: Dictionary) -> Dictionary:
	var row := VBoxContainer.new()
	var head := HBoxContainer.new()
	row.add_child(head)
	var label := Label.new()
	label.text = f.label + (" (%s)" % f.unit if f.unit != "" else "")
	label.tooltip_text = f.hint
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(label)
	var state := OptionButton.new()
	for s in STATE_LABELS:
		state.add_item(s)
	state.select(maxi(STATES.find(f.state), 0))
	head.add_child(state)

	var editor  # LineEdit, TextEdit ou OptionButton, conforme o tipo do campo
	match f.type:
		"number":
			editor = LineEdit.new()
			editor.placeholder_text = f.unit if f.unit != "" else "número"
		"choice":
			editor = OptionButton.new()
			editor.add_item("—")
			for o in f.options.split("\n", false):
				editor.add_item(o.strip_edges())
		"bool":
			editor = OptionButton.new()
			for o in ["—", "Sim", "Não"]:
				editor.add_item(o)
		_:
			editor = TextEdit.new()
			editor.custom_minimum_size = Vector2(0, 72)
			editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			editor.tooltip_text = f.hint
			editor.placeholder_text = f.hint
	row.add_child(editor)
	var entry := {"row": row, "state": state, "editor": editor, "type": f.type, "last_state": f.state, "last_value": f.value}
	_fields[f.code] = entry
	_write_editor(entry, f.value)
	editor.visible = f.state == "known" or f.state == "unfilled"

	var commit := func() -> void:
		var st: String = STATES[state.selected]
		var v := _read_editor(entry) if st == "known" else ""
		if st != entry.last_state or v != entry.last_value:
			entry.last_state = st
			entry.last_value = v
			field_edited.emit(f.code, st, v)
	state.item_selected.connect(func(_i: int) -> void:
		editor.visible = state.selected == 0
		commit.call())
	if editor is OptionButton:
		editor.item_selected.connect(func(_i: int) -> void: commit.call())
	else:
		editor.focus_exited.connect(commit)
		if editor is LineEdit:
			editor.text_submitted.connect(func(_t: String) -> void: commit.call())
	return entry


func _read_editor(entry: Dictionary) -> String:
	var e = entry.editor
	if e is OptionButton:
		if entry.type == "bool":
			return ["", "true", "false"][e.selected]
		return "" if e.selected <= 0 else e.get_item_text(e.selected)
	return e.text.strip_edges()


func _write_editor(entry: Dictionary, value: String) -> void:
	var e = entry.editor
	if e is OptionButton:
		if entry.type == "bool":
			e.select(["", "true", "false"].find(value) if value != "" else 0)
		else:
			e.select(0)
			for i in e.item_count:
				if e.get_item_text(i) == value and value != "":
					e.select(i)
	else:
		e.text = value


func _build_links() -> void:
	var box := _section("Relações")
	if _sheet.links.is_empty():
		box.add_child(_note("Nenhuma relação ainda."))
	for l in _sheet.links:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = l.label + ":"
		row.add_child(label)
		var open := Button.new()
		open.text = "%s · %s" % [l.other_name, UiKit.kind_label(l.other_kind)]
		open.flat = true
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.pressed.connect(func() -> void: open_entity.emit(int(l.other_id)))
		row.add_child(open)
		var del := Button.new()
		del.text = "✕"
		del.flat = true
		del.tooltip_text = "Apagar este vínculo (criado por engano)"
		del.pressed.connect(func() -> void: link_removed.emit(int(l.id)))
		row.add_child(del)
	if _types.is_empty():
		return
	var add := HBoxContainer.new()
	box.add_child(add)
	_link_type = OptionButton.new()
	for t in _types:
		_link_type.add_item(t.label)
	add.add_child(_link_type)
	_link_query = LineEdit.new()
	_link_query.placeholder_text = "buscar o outro cadastro"
	_link_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.add_child(_link_query)
	var add2 := HBoxContainer.new()
	box.add_child(add2)
	_link_candidates = OptionButton.new()
	_link_candidates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_link_candidates.fit_to_longest_item = false
	add2.add_child(_link_candidates)
	var go := Button.new()
	go.text = "Vincular"
	go.pressed.connect(func() -> void:
		if _link_candidates.item_count > 0 and _link_candidates.selected >= 0:
			link_added.emit(_types[_link_type.selected].code, int(_link_candidates.get_item_metadata(_link_candidates.selected))))
	add2.add_child(go)
	var search := func() -> void:
		link_search.emit(_link_query.text, _types[_link_type.selected].dst_kind)
	_link_query.text_changed.connect(func(_t: String) -> void: search.call())
	_link_type.item_selected.connect(func(_i: int) -> void: search.call())
	search.call()


func _build_footer() -> void:
	_body.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	_body.add_child(row)
	var with_links := CheckBox.new()
	with_links.text = "com vínculos"
	row.add_child(with_links)
	var dup := Button.new()
	dup.text = "Duplicar"
	dup.pressed.connect(func() -> void: duplicate_requested.emit(with_links.button_pressed))
	row.add_child(dup)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var del := Button.new()
	del.text = "Excluir…"
	del.pressed.connect(func() -> void: delete_requested.emit())
	row.add_child(del)


# --- peças -----------------------------------------------------------------------------------------------------------

func _section(title: String) -> VBoxContainer:
	_body.add_child(HSeparator.new())
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 16)
	_body.add_child(l)
	var box := VBoxContainer.new()
	_body.add_child(box)
	return box


func _label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)
	_body.add_child(l)


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.modulate = Color(1, 1, 1, 0.8)
	return l


func _role_label(role: String) -> String:
	for r in ROLES:
		if r[0] == role:
			return r[1]
	return role
