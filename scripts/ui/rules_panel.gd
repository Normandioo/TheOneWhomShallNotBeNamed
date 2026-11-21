extends Node
## Janela de regras (E3): montar uma regra com nós ligados (GraphEdit), executá-la na data mostrada pelo relógio e fixar valores que a
## regra deve respeitar. Os nós viram a definição declarativa de RegistryRules.cs ao salvar; abrir uma regra a redesenha em nós.
## Só mostra e pede: quem valida, executa e grava é o DomainHub (Registry).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Rules = preload("res://scripts/world/rules.gd")
const OPS := ["add", "sub", "mul", "div", "min", "max"]
const CMPS := ["gt", "ge", "lt", "le", "eq", "ne"]
const MODES := ["manual", "automatico", "desativado"]
const MODE_LABEL := {"manual": "manual", "automatico": "automática: a ficha mostra o valor", "desativado": "desativada"}
const MAX_DEPTH := 24
const PORT := Color(0.55, 0.85, 1.0)
const NODE_TITLE := {"const": "Número", "field": "Campo", "links": "Vínculos vigentes", "population": "População", "area": "Área (km²)",
	"distance": "Distância (km) até", "math": "Operação", "if": "Se", "result": "Resultado"}
const LEAVES := ["const", "field", "links", "population", "area", "distance"]
# O título de cada tipo de nó: entradas em azul, cálculos em vinho, o resultado em verde.
const NODE_COLOR := {"input": Color("#1b3a48"), "calc": Color("#4a2e30"), "result": Color("#25402f")}
const INPUTS := {"math": ["a", "b"], "if": ["A", "B", "então", "senão"], "result": ["valor"]}

signal kind_selected(kind: String)
signal save_requested(rule_id: int, name: String, definition: String)
signal run_requested(rule_id: int)
signal mode_requested(rule_id: int, mode: String)
signal pin_requested(entity_id: int, code: String, value: float, reason: String)

var _dialog: AcceptDialog
var _message: Label
var _list: ItemList
var _rule_ids: Array = []
var _rule_defs: Array = []
var _rule_names: Array = []
var _name: LineEdit
var _kind: OptionButton
var _kinds: Array = []
var _target: OptionButton
var _targets: Array = []
var _fields: Array = []   # {code, label} dos campos numéricos do tipo
var _links: Array = []    # {code, label} dos vínculos do tipo
var _entities: Array = [] # {id, name} das entidades (destinos da distância)
var _graph: GraphEdit
var _result: GraphNode
var _editing := 0         # a regra aberta no editor (0 = nova)
var _results: ItemList
var _result_rows: Array = []
var _pin_value: SpinBox
var _pin_reason: LineEdit
var _last_field := ""
var _serial := 0


func _ready() -> void:
	_dialog = UiKit.themed(AcceptDialog.new())
	_dialog.title = "Regras"
	_dialog.ok_button_text = "Fechar"
	_dialog.min_size = Vector2i(1180, 700)
	var box := VBoxContainer.new()
	_dialog.add_child(box)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(600, 0)
	_message.modulate = Color(1.0, 0.85, 0.4)
	box.add_child(_message)
	var columns := HBoxContainer.new()  # a lista à esquerda, o editor de nós no centro, o resultado e as fixações à direita
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)

	# Esquerda: as regras e o que se faz com a escolhida.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(270, 0)
	columns.add_child(left)
	left.add_child(_heading("Regras"))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.max_text_lines = 3
	_list.auto_height = false
	left.add_child(_list)
	var new_rule := _button(left, "＋ Nova regra", func() -> void: _new_rule())
	new_rule.add_theme_stylebox_override("normal", UiKit.active_style())
	_button(left, "Abrir no editor", func() -> void:
		var i := _list.get_selected_items()
		if not i.is_empty():
			open_rule(_rule_ids[i[0]], _rule_names[i[0]], _rule_defs[i[0]]))
	_button(left, "Executar na data mostrada", func() -> void:
		if _selected_rule() != 0:
			run_requested.emit(_selected_rule()))
	_button(left, "Trocar modo", func() -> void:
		if _selected_rule() != 0:
			mode_requested.emit(_selected_rule(), "toggle"))
	var hint := _label(left, "Uma regra calcula um campo a partir de outros campos, vínculos, população ou área. Valores fixados por você nunca são substituídos.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(250, 0)  # sem largura mínima, o texto com quebra pede altura de uma palavra por linha
	hint.modulate = Color(1, 1, 1, 0.6)

	# Centro: o nome, o que a regra calcula, os nós e Salvar.
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(center)
	var r1 := HBoxContainer.new()
	center.add_child(r1)
	_name = LineEdit.new()
	_name.placeholder_text = "Nome da regra"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(_name)
	_kind = OptionButton.new()
	_kind.item_selected.connect(func(i: int) -> void:
		_clear_graph()
		kind_selected.emit(_kinds[i]))
	r1.add_child(_kind)
	_label(r1, "calcula")
	_target = OptionButton.new()
	r1.add_child(_target)
	var palette := GridContainer.new()  # grade fixa: uma fileira que quebra pediria altura demais à janela
	palette.columns = 4
	center.add_child(palette)
	for k in LEAVES + ["math", "if"]:
		_button(palette, "＋ " + NODE_TITLE[k], func() -> void: add_node(k)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph = GraphEdit.new()
	_graph.custom_minimum_size = Vector2(0, 330)
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.right_disconnects = true
	_graph.connection_request.connect(_on_connect)
	_graph.disconnection_request.connect(func(from: StringName, fp: int, to: StringName, tp: int) -> void: _graph.disconnect_node(from, fp, to, tp))
	_graph.delete_nodes_request.connect(_on_delete)
	center.add_child(_graph)
	var tip := _label(center, "Ligue as saídas (direita) às entradas (esquerda); Delete apaga o nó.")
	tip.modulate = Color(1, 1, 1, 0.6)
	_button(center, "Salvar regra", _save)

	# Direita: o resultado da última execução e a fixação de um valor.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	columns.add_child(right)
	right.add_child(_heading("Resultado da execução"))
	_results = ItemList.new()
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_results)
	right.add_child(_heading("Fixar um valor"))
	_pin_value = SpinBox.new()
	_pin_value.min_value = -1e12
	_pin_value.max_value = 1e12
	_pin_value.step = 0.01
	right.add_child(_pin_value)
	_pin_reason = LineEdit.new()
	_pin_reason.placeholder_text = "Motivo da fixação"
	right.add_child(_pin_reason)
	_button(right, "Fixar a partir da data mostrada", func() -> void:
		var i := _results.get_selected_items()
		if i.is_empty() or _last_field == "":
			show_message("Escolha uma entidade no resultado.")
			return
		pin_requested.emit(int(_result_rows[i[0]].entity_id), _last_field, _pin_value.value, _pin_reason.text))
	add_child(_dialog)
	_clear_graph()


## O título de uma coluna: Cinzel em destaque.
func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	UiKit.style_heading(l)
	l.add_theme_font_size_override("font_size", 17)
	return l


func open_dialog() -> void:
	_message.text = ""
	_dialog.popup_centered()


func show_message(text: String) -> void:
	_message.text = text


## Os tipos que têm campo numérico (os únicos que uma regra pode calcular).
func show_kinds(kinds: Array) -> void:
	var keep: String = _kinds[_kind.selected] if _kind.selected >= 0 and _kind.selected < _kinds.size() else ""
	_kinds = kinds
	_kind.clear()
	for k in kinds:
		_kind.add_item(UiKit.kind_label(k))
	if kinds.has(keep):
		_kind.select(kinds.find(keep))
	elif not kinds.is_empty():
		_clear_graph()
		kind_selected.emit(kinds[0])


## Os campos numéricos e os vínculos do tipo escolhido, e as entidades que a distância pode ter como destino.
func show_inputs(fields: Array, link_types: Array, entities: Array = []) -> void:
	_entities = entities.map(func(e): return {"id": int(e.id), "name": "%s · %s" % [e.name, UiKit.kind_label(e.kind)]})
	_fields = fields.map(func(f): return {"code": String(f.code), "label": String(f.label)})
	_links = link_types.map(func(l): return {"code": String(l.code), "label": String(l.label)})
	_targets = _fields.map(func(f): return f.code)
	_target.clear()
	for f in _fields:
		_target.add_item(f.label)


## As regras gravadas: {id, name, mode, version, definition, text (a regra legível)}.
func show_rules(rules: Array) -> void:
	var keep := _selected_rule()
	_list.clear()
	_rule_ids.clear()
	_rule_defs.clear()
	_rule_names.clear()
	for r in rules:
		_list.add_item("%s (v%d, %s): %s" % [r.name, r.version, MODE_LABEL.get(r.mode, r.mode), r.text])
		_rule_ids.append(int(r.id))
		_rule_defs.append(JSON.parse_string(r.definition))
		_rule_names.append(String(r.name))
		if int(r.id) == keep:
			_list.select(_list.item_count - 1)


## O resultado de uma execução: {when (a data escrita), version, results: [{entity_id, name, value, status, note}]}.
func show_run(run: Dictionary, rule_id: int) -> void:
	_results.clear()
	_result_rows = run.results
	var i := _rule_ids.find(rule_id)
	_last_field = String(_rule_defs[i].field) if i >= 0 else ""
	for r in run.results:
		var value: String = UiKit.number_text(r.value)
		var tag: String = {"calculado": "", "fixado": "  🔒 fixado", "erro": "  ⚠ erro"}.get(r.status, "")
		_results.add_item("%s: %s%s%s" % [r.name, value, tag, "  (" + r.note + ")" if r.note != "" else ""])
	show_message("Executada em %s (versão %d)." % [run.when, run.version])


## Redesenha uma regra gravada em nós, para editar (salvar grava uma versão nova dela).
func open_rule(rule_id: int, rule_name: String, def: Dictionary) -> void:
	if not _kinds.has(String(def.kind)):
		show_message("O tipo dessa regra não tem mais campo numérico.")
		return
	_kind.select(_kinds.find(String(def.kind)))
	_clear_graph()
	kind_selected.emit(String(def.kind))
	_target.select(_targets.find(String(def.field)))
	_name.text = rule_name
	_editing = rule_id
	var top := _build(def.expr, Vector2(_result.position_offset.x - 240, 40), 0)
	_graph.connect_node(top.name, 0, _result.name, 0)
	show_message("Editando \"%s\": salvar grava uma versão nova." % rule_name)


# --- nós ---------------------------------------------------------------------------------------------------------------

## Acrescenta um nó (kind: const | field | links | math | if | result) e o devolve.
func add_node(kind: String, at := Vector2.ZERO) -> GraphNode:
	var n := GraphNode.new()
	_serial += 1
	n.name = "%s_%d" % [kind, _serial]
	n.title = NODE_TITLE[kind]
	n.set_meta("kind", kind)
	var tone: Color = NODE_COLOR["result"] if kind == "result" else (NODE_COLOR["calc"] if kind in ["math", "if"] else NODE_COLOR["input"])
	n.add_theme_stylebox_override("titlebar", UiKit.node_title_style(tone))
	n.add_theme_stylebox_override("titlebar_selected", UiKit.node_title_style(tone, true))
	n.position_offset = at if at != Vector2.ZERO else _graph.scroll_offset / _graph.zoom + Vector2(40 + (_serial % 5) * 30, 40 + (_serial % 5) * 30)
	var head: Control
	match kind:
		"const":
			var spin := SpinBox.new()
			spin.min_value = -1e12
			spin.max_value = 1e12
			spin.step = 0.01
			head = spin
		"field", "links":
			var menu := OptionButton.new()
			for c in (_fields if kind == "field" else _links):
				menu.add_item(c.label)
			head = menu
		"distance":
			var menu := OptionButton.new()
			menu.fit_to_longest_item = false
			menu.custom_minimum_size = Vector2(160, 0)
			for e in _entities:
				menu.add_item(e.name)
			head = menu
		"population", "area":
			var l := Label.new()
			l.text = "da entidade, na data"
			head = l
		"math", "if":
			var menu := OptionButton.new()
			for o in (OPS if kind == "math" else CMPS):
				menu.add_item(Rules.MATH[o] if kind == "math" else Rules.COMPARE[o])
			head = menu
		_:
			var l := Label.new()
			l.text = "→ campo calculado"
			head = l
	head.name = "Head"
	n.add_child(head)
	if kind == "result":
		n.set_slot(0, true, 0, PORT, false, 0, PORT)  # só entrada
	else:
		n.set_slot(0, false, 0, PORT, true, 0, PORT)  # a saída fica no cabeçalho
		for label in INPUTS.get(kind, []):
			var l := Label.new()
			l.text = label
			n.add_child(l)
			n.set_slot(n.get_child_count() - 1, true, 0, PORT, false, 0, PORT)
	_graph.add_child(n)
	return n


func _clear_graph() -> void:
	_editing = 0
	if _graph == null:
		return
	_graph.clear_connections()
	for c in _graph.get_children():
		if c is GraphNode:
			_graph.remove_child(c)
			c.queue_free()
	_result = add_node("result", Vector2(560, 120))


## A regra aberta foi gravada com esse id: salvar de novo grava uma versão nova dela.
func saved(rule_id: int) -> void:
	_editing = rule_id


func _new_rule() -> void:
	_clear_graph()
	_name.text = ""
	show_message("Nova regra.")


## Uma entrada recebe uma ligação só: ligar de novo troca a anterior.
func _on_connect(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	if from == to:
		return
	for c in _graph.get_connection_list():
		if c.to_node == to and c.to_port == to_port:
			_graph.disconnect_node(c.from_node, c.from_port, c.to_node, c.to_port)
	_graph.connect_node(from, from_port, to, to_port)


func _on_delete(names: Array) -> void:
	for node_name in names:
		var n := _graph.get_node_or_null(NodePath(node_name))
		if n == null or n == _result:
			continue
		for c in _graph.get_connection_list():
			if c.from_node == node_name or c.to_node == node_name:
				_graph.disconnect_node(c.from_node, c.from_port, c.to_node, c.to_port)
		_graph.remove_child(n)
		n.queue_free()


## A definição a partir dos nós ligados ao Resultado; null (e a mensagem) se falta ligação ou há ciclo.
func graph_rule() -> Variant:
	if _target.selected < 0:
		show_message("Esse tipo não tem campo numérico para calcular (crie um em Tipos…).")
		return null
	var into := {}  # "nó:porta" -> nó ligado nela
	for c in _graph.get_connection_list():
		into["%s:%d" % [c.to_node, c.to_port]] = String(c.from_node)
	var expr = _node_json(String(_result.name), 0, into, 0)
	if expr == null:
		return null
	return Rules.rule(_kinds[_kind.selected], _targets[_target.selected], expr)


func _node_json(host_name: String, port: int, into: Dictionary, depth: int) -> Variant:
	var host := _graph.get_node(NodePath(host_name)) as GraphNode
	var from: String = into.get("%s:%d" % [host_name, port], "")
	if from == "":
		show_message("Falta ligar a entrada \"%s\" do nó %s." % [INPUTS[host.get_meta("kind")][port], host.title])
		return null
	if depth > MAX_DEPTH:
		show_message("Os nós formam um ciclo (ou passam de %d níveis)." % MAX_DEPTH)
		return null
	var n := _graph.get_node(NodePath(from)) as GraphNode
	var head = n.get_node("Head")
	var ins := []
	for i in INPUTS.get(n.get_meta("kind"), []).size():
		var sub = _node_json(from, i, into, depth + 1)
		if sub == null:
			return null
		ins.append(sub)
	match String(n.get_meta("kind")):
		"const":
			return Rules.number(head.value)
		"field":
			if head.selected < 0:
				show_message("O nó Campo não tem campo escolhido.")
				return null
			return Rules.field(_fields[head.selected].code)
		"links":
			if head.selected < 0:
				show_message("Esse tipo não tem vínculos para contar.")
				return null
			return Rules.links(_links[head.selected].code)
		"population":
			return Rules.population()
		"area":
			return Rules.area()
		"distance":
			if head.selected < 0:
				show_message("Escolha a entidade de destino da distância.")
				return null
			return Rules.distance(_entities[head.selected].id)
		"math":
			return Rules.calc(ins[0], OPS[head.selected], ins[1])
		_:
			return Rules.when(ins[0], CMPS[head.selected], ins[1], ins[2], ins[3])


## Cria os nós de uma definição, da direita para a esquerda; devolve o nó da raiz.
func _build(node: Dictionary, at: Vector2, depth: int) -> GraphNode:
	var op := String(node.op)
	var kind: String = op if op in LEAVES + ["if"] else "math"
	var n := add_node(kind, at)
	var head = n.get_node("Head")
	match kind:
		"const":
			head.value = float(node.value)
		"field":
			head.select(_fields.map(func(f): return f.code).find(String(node.code)))
		"links":
			head.select(_links.map(func(l): return l.code).find(String(node.type)))
		"distance":
			head.select(_entities.map(func(e): return e.id).find(int(node.to)))
		"math":
			head.select(OPS.find(op))
		"if":
			head.select(CMPS.find(String(node.cond.op)))
	var subs: Array = []
	if kind == "math":
		subs = [node.a, node.b]
	elif kind == "if":
		subs = [node.cond.a, node.cond.b, node.then, node["else"]]
	var y := at.y
	for i in subs.size():
		var child := _build(subs[i], Vector2(at.x - 240, y), depth + 1)
		_graph.connect_node(child.name, 0, n.name, i)
		y += 110.0 * _leaves(subs[i])
	return n


static func _leaves(node: Dictionary) -> int:
	if String(node.op) in LEAVES:
		return 1
	match String(node.op):
		"if":
			return _leaves(node.cond.a) + _leaves(node.cond.b) + _leaves(node.then) + _leaves(node["else"])
		_:
			return _leaves(node.a) + _leaves(node.b)


func _selected_rule() -> int:
	var i := _list.get_selected_items()
	return 0 if i.is_empty() else _rule_ids[i[0]]


func _save() -> void:
	var def = graph_rule()
	if def != null:
		save_requested.emit(_editing, _name.text, JSON.stringify(def))


func _label(row: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	row.add_child(l)
	return l


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b
