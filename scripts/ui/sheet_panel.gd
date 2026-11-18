extends PanelContainer
## A ficha de um cadastro, à esquerda da busca: identidade, resumo, etiquetas, nomes, o conteúdo do tipo (gerado das definições
## de campo, com os campos vazios recolhidos em "Adicionar informação") e as relações. Só mostra e pede: avisa por sinal quando
## o usuário edita; o DomainHub grava no Registry e devolve o que for preciso mostrar.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")  # só para o separador de milhares

signal name_changed(entity_id: int, text: String)  # correção de grafia do nome atual (não é mudança histórica)
signal summary_changed(entity_id: int, text: String)
signal field_edited(entity_id: int, code: String, state: String, value: String)  # state: known | unknown | na; known + "" = limpar
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
signal calendar_use_added(calendar_id: int, purpose: String)
signal calendar_use_removed(use_id: int)
signal place_focus_requested(place_id: int)
signal border_draw_requested(name: String, role: String)   # desenhar uma fronteira nova no globo
signal border_redraw_requested(place_id: int, role: String)  # refazer o contorno de um lugar que já é contorno
signal place_search(text: String)  # buscar lugares para os menus (o hub responde com show_place_candidates)
signal presence_added(place_id: int, role: String)
signal presence_removed(presence_id: int)
signal place_created(name: String, kind: String, radius_km: float, role: String)  # no ponto fixado no mapa
signal estimate_added(place_id: int, low: String, high: String, level: String, certainty: String)
signal estimate_removed(estimate_id: int)

const WIDTH := 440
const FOREVER := 9223372036854775807
const STATES := ["known", "unknown", "na"]
const STATE_LABELS := ["Valor", "Desconhecido", "Não se aplica"]
const PURPOSES := {"civil": "Civil", "ritual": "Ritual", "tradicional": "Tradicional", "administrativo": "Administrativo", "outro": "Outro"}
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
var _calendars := {}       # o que o hub mandou: universal, uses, choices
var _geo := {}             # lugares e datas para as seções de mapa e população (do hub)
var _fixed_label: Label
var _create_place_btn: Button
var _geo_message: Label
var _border_msg: Label
var _place_pickers: Array = []  # os menus de lugar da ficha (a busca de um atualiza todos)
var _universal_label: Label
var _date_labels := {}     # id do uso -> Label com a data local


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
func show_sheet(sheet: Dictionary, link_types: Array, calendars := {}, geo := {}) -> void:
	var keep := _scroll.scroll_vertical if int(sheet.id) == current_id() else 0
	_sheet = sheet
	_types = link_types
	_calendars = calendars
	_geo = geo
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
	_build_places()
	_build_population()
	_build_calendars()
	_build_footer()
	_scroll.set_deferred("scroll_vertical", keep)


## Atualiza só as datas (universal e locais) quando o relógio anda, sem refazer a ficha. texts: id do uso -> texto.
func show_calendar_dates(universal: String, texts: Dictionary) -> void:
	if _universal_label != null:
		_universal_label.text = "Data universal: " + universal
	for use_id in texts:
		if _date_labels.has(use_id):
			_date_labels[use_id].text = texts[use_id]


## O ponto fixado no mapa mudou: o texto e se dá para criar um lugar nele. Não refaz a ficha.
func show_fixed_point(text: String, enabled: bool) -> void:
	if _fixed_label != null:
		_fixed_label.text = text
		_create_place_btn.disabled = not enabled


func show_border_message(text: String) -> void:
	if _border_msg != null:
		_border_msg.text = text


func show_geo_message(text: String) -> void:
	if _geo_message != null:
		_geo_message.text = text


## O usuário está digitando na ficha ou com um menu aberto? Quem refaz a ficha (o hub) espera, para não tirar o foco nem fechar o menu.
func is_editing() -> bool:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f == null or not is_ancestor_of(f):
		return false
	if f is OptionButton or f is MenuButton:
		return f.get_popup().visible  # refazer a ficha destruiria o menu aberto
	return f is LineEdit or f is TextEdit


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
	var eid := int(_sheet.id)  # a entidade desta ficha: capturado agora, porque o foco pode sair quando outra ficha já abriu
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
			name_changed.emit(eid, t)
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
			summary_changed.emit(eid, summary.text))
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
	var eid := int(_sheet.id)  # ver _build_identity
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
			field_edited.emit(eid, f.code, st, v)
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


func _build_places() -> void:
	_place_pickers.clear()
	_border_msg = null
	_fixed_label = null
	_create_place_btn = null
	if _geo.is_empty():
		return
	var box := _section("Presença no mapa")
	if _sheet.presences.is_empty():
		box.add_child(_note("Em nenhum lugar ainda."))
	for p in _sheet.presences:
		var row := HBoxContainer.new()
		box.add_child(row)
		var is_border: bool = p.vertices.size() >= 6
		var what := "ponto"
		if is_border:
			what = "contorno de %d pontos · ≈ %s km²" % [p.vertices.size() / 2, LayerPanel._thousands(roundi(p.area_km2))]
		elif p.radius_km > 0.0:
			what = "área de %s km" % LayerPanel._thousands(roundi(p.radius_km))
		var label := Label.new()
		label.text = "%s · %s (%s)" % [UiKit.role_label(p.role), p.place, what]
		label.tooltip_text = "%s · certeza %s" % [UiKit.LAYER_LABEL.get(p.layer, p.layer), UiKit.CERTAINTY_LABEL.get(p.certainty, p.certainty)]
		label.modulate = UiKit.LAYER_COLOR.get(p.layer, Color.WHITE).lightened(0.3)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var focus := Button.new()
		focus.text = "Ver"
		focus.flat = true
		focus.tooltip_text = "Centralizar o mapa neste lugar"
		focus.pressed.connect(func() -> void: place_focus_requested.emit(int(p.place_id)))
		row.add_child(focus)
		if is_border:
			var redraw := Button.new()
			redraw.text = "Redesenhar"
			redraw.flat = true
			redraw.tooltip_text = "Marcar o contorno de novo no globo (troca o contorno deste lugar)"
			redraw.pressed.connect(func() -> void: border_redraw_requested.emit(int(p.place_id), p.role))
			row.add_child(redraw)
		var del := Button.new()
		del.text = "✕"
		del.flat = true
		del.tooltip_text = "Apagar esta presença (criada por engano)"
		del.pressed.connect(func() -> void: presence_removed.emit(int(p.id)))
		row.add_child(del)
	var role_keys: Array = UiKit.ROLE_LABEL.keys()
	box.add_child(_note("Vincular a um lugar que já existe:"))
	var place := _place_picker(box)
	var existing := HBoxContainer.new()
	box.add_child(existing)
	var role_a := _option(role_keys, func(k): return UiKit.ROLE_LABEL[k])
	existing.add_child(role_a)
	var link := Button.new()
	link.text = "Vincular"
	link.pressed.connect(func() -> void:
		if place.item_count > 0 and place.selected >= 0:
			presence_added.emit(int(place.get_item_metadata(place.selected)), role_keys[role_a.selected]))
	existing.add_child(link)
	box.add_child(_note("Ou crie um lugar no ponto fixado no mapa (clique no globo):"))
	_fixed_label = _note(_geo.fixed_text)
	box.add_child(_fixed_label)
	var new_row := HBoxContainer.new()
	box.add_child(new_row)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "nome do lugar"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_child(name_edit)
	var radius := SpinBox.new()
	radius.min_value = 0
	radius.max_value = 8000
	radius.step = 10
	radius.suffix = "km"
	radius.tooltip_text = "Raio da área aproximada; 0 = um ponto"
	new_row.add_child(radius)
	var new_row2 := HBoxContainer.new()
	box.add_child(new_row2)
	var kind_keys: Array = UiKit.PLACE_KIND_LABEL.keys()
	var kind := _option(kind_keys, func(k): return UiKit.PLACE_KIND_LABEL[k])
	new_row2.add_child(kind)
	var role := _option(role_keys, func(k): return UiKit.ROLE_LABEL[k])
	new_row2.add_child(role)
	_create_place_btn = Button.new()
	_create_place_btn.text = "Criar lugar aqui"
	_create_place_btn.disabled = not _geo.has_fixed
	_create_place_btn.pressed.connect(func() -> void:
		if name_edit.text.strip_edges() != "":
			place_created.emit(name_edit.text.strip_edges(), kind_keys[kind.selected], radius.value, role_keys[role.selected]))
	new_row2.add_child(_create_place_btn)
	box.add_child(_note("Ou desenhe uma fronteira à mão no globo (clicando ponto a ponto):"))
	var draw_row := HBoxContainer.new()
	box.add_child(draw_row)
	var border_name := LineEdit.new()
	border_name.placeholder_text = "nome da região"
	border_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	draw_row.add_child(border_name)
	var border_role := _option(role_keys, func(k): return UiKit.ROLE_LABEL[k])
	border_role.select(role_keys.find("territorio"))
	draw_row.add_child(border_role)
	var draw_btn := Button.new()
	draw_btn.text = "Desenhar no mapa"
	draw_btn.pressed.connect(func() -> void: border_draw_requested.emit(border_name.text.strip_edges(), role_keys[border_role.selected]))
	draw_row.add_child(draw_btn)
	_border_msg = _note("")
	box.add_child(_border_msg)


func _build_population() -> void:
	_geo_message = null
	if _geo.is_empty():
		return
	var box := _section("População")
	for e in _sheet.estimates:
		var row := HBoxContainer.new()
		box.add_child(row)
		var when: String = _geo.dates_e.get(int(e.id), "")
		var what := "nível %s (sem número)" % e.level if e.level != "" else _range(float(e.low), float(e.high))
		var label := Label.new()
		label.text = "%s · %s %s%s" % [e.place, what, e.basis, "  ·  " + when if when != "" else ""]
		label.tooltip_text = "Certeza %s%s" % [UiKit.CERTAINTY_LABEL.get(e.certainty, e.certainty), " · fonte: " + e.source if e.source != "" else ""]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var del := Button.new()
		del.text = "✕"
		del.flat = true
		del.tooltip_text = "Apagar esta estimativa (criada por engano)"
		del.pressed.connect(func() -> void: estimate_removed.emit(int(e.id)))
		row.add_child(del)
	for c in _sheet.compositions:
		var when2: String = _geo.dates_d.get(int(c.id), "")
		var head := "%s em %s%s (%s, %s)" % [UiKit.kind_label(c.dimension), c.place, "  ·  " + when2 if when2 != "" else "",
			"categorias exclusivas" if c.exclusive else "podem se sobrepor", "lista completa" if c.complete else "lista incompleta"]
		box.add_child(_note(head))
		for s in c.shares:
			var line := "     %s: %s%%" % [s.name, _pct(s.pct)]
			if s.has("low"):
				line += "  ≈ " + _range(s.low, s.high) + " pessoas"
			box.add_child(_note(line))
		if c.unknown_pct > 0.0:
			box.add_child(_note("     desconhecido: %s%%" % _pct(c.unknown_pct)))
		if c.denominator.is_empty():
			box.add_child(_note("     (sem população de referência: só percentuais)"))
	if _sheet.estimates.is_empty() and _sheet.compositions.is_empty():
		box.add_child(_note("Nenhuma estimativa ainda."))
	if _geo.places.is_empty():
		box.add_child(_note("Crie ou vincule um lugar acima para registrar uma estimativa."))
		return
	var place := _place_picker(box)
	var add := HBoxContainer.new()
	box.add_child(add)
	var low := LineEdit.new()
	low.placeholder_text = "de"
	low.custom_minimum_size = Vector2(70, 0)
	add.add_child(low)
	var high := LineEdit.new()
	high.placeholder_text = "até"
	high.custom_minimum_size = Vector2(70, 0)
	add.add_child(high)
	var add2 := HBoxContainer.new()
	box.add_child(add2)
	var level := OptionButton.new()
	level.add_item("com número")
	for lv in ["só nível: baixa", "só nível: média", "só nível: alta"]:
		level.add_item(lv)
	add2.add_child(level)
	var cert_keys: Array = UiKit.CERTAINTY_LABEL.keys()
	var certainty := _option(cert_keys, func(k): return "certeza " + UiKit.CERTAINTY_LABEL[k])
	certainty.select(1)
	add2.add_child(certainty)
	var go := Button.new()
	go.text = "Registrar"
	go.tooltip_text = "Vale para a data mostrada pelo relógio"
	go.pressed.connect(func() -> void:
		if place.item_count == 0 or place.selected < 0:
			return
		estimate_added.emit(int(place.get_item_metadata(place.selected)), low.text.strip_edges(), high.text.strip_edges(),
			["", "baixa", "media", "alta"][level.selected], cert_keys[certainty.selected]))
	add2.add_child(go)
	_geo_message = _note("")
	box.add_child(_geo_message)


## Um menu de lugar com busca por nome: mostra os primeiros lugares e, ao digitar, o hub devolve os que casam (show_place_candidates).
func _place_picker(box: VBoxContainer) -> OptionButton:
	var row := HBoxContainer.new()
	box.add_child(row)
	var query := LineEdit.new()
	query.placeholder_text = "buscar lugar"
	query.custom_minimum_size = Vector2(110, 0)
	query.text_changed.connect(func(t: String) -> void: place_search.emit(t))
	row.add_child(query)
	var pick := OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pick)
	_fill_places(pick, _geo.places, _geo.get("places_more", false))
	_place_pickers.append(pick)
	return pick


func _fill_places(pick: OptionButton, items: Array, more: bool) -> void:
	pick.clear()
	for pl in items:
		pick.add_item(pl.name)
		pick.set_item_metadata(pick.item_count - 1, int(pl.id))
	if more:  # há mais do que cabe: o aviso não é escolhível
		pick.add_item("… há mais: refine a busca")
		pick.set_item_disabled(pick.item_count - 1, true)
	if pick.item_count > 0:
		pick.select(0)


## O resultado de uma busca de lugar (cada um: id, name) nos menus de lugar da ficha; more = havia mais do que cabe.
func show_place_candidates(items: Array, more: bool) -> void:
	for pick in _place_pickers:
		if is_instance_valid(pick):
			_fill_places(pick, items, more)


func _option(keys: Array, label_of: Callable) -> OptionButton:
	var o := OptionButton.new()
	for k in keys:
		o.add_item(label_of.call(k))
	return o


func _range(low: float, high: float) -> String:
	return LayerPanel._thousands(roundi(low)) if is_equal_approx(low, high) else "%s–%s" % [LayerPanel._thousands(roundi(low)), LayerPanel._thousands(roundi(high))]


func _pct(v: float) -> String:
	return ("%.1f" % v).rstrip("0").rstrip(".").replace(".", ",")


func _build_calendars() -> void:
	_universal_label = null
	_date_labels.clear()
	if _calendars.is_empty():
		return
	var box := _section("Calendários")
	_universal_label = _note("Data universal: " + _calendars.universal)
	box.add_child(_universal_label)
	if _calendars.uses.is_empty():
		box.add_child(_note("Nenhum calendário em uso."))
	for u in _calendars.uses:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = "%s · %s" % [PURPOSES.get(u.purpose, u.purpose), u.name]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_text = "Prioridade de exibição: %d" % u.priority
		row.add_child(label)
		var del := Button.new()
		del.text = "✕"
		del.flat = true
		del.tooltip_text = "Apagar este uso (criado por engano)"
		del.pressed.connect(func() -> void: calendar_use_removed.emit(int(u.use_id)))
		row.add_child(del)
		var date := Label.new()
		date.text = u.text
		date.autowrap_mode = TextServer.AUTOWRAP_WORD
		_date_labels[int(u.use_id)] = date
		box.add_child(date)
	if _calendars.choices.is_empty():
		box.add_child(_note("Nenhum calendário cadastrado: crie um em Calendários… (painel de busca)."))
		return
	var add := HBoxContainer.new()
	box.add_child(add)
	var cal := OptionButton.new()
	cal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in _calendars.choices:
		cal.add_item(c.name)
		cal.set_item_metadata(cal.item_count - 1, int(c.id))
	add.add_child(cal)
	var purpose := OptionButton.new()
	for p in PURPOSES:
		purpose.add_item(PURPOSES[p])
		purpose.set_item_metadata(purpose.item_count - 1, p)
	add.add_child(purpose)
	var go := Button.new()
	go.text = "Usar"
	go.pressed.connect(func() -> void: calendar_use_added.emit(int(cal.get_item_metadata(cal.selected)), purpose.get_item_metadata(purpose.selected)))
	add.add_child(go)


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
