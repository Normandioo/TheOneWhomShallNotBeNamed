extends PanelContainer
## O painel dos povoados, em três telas. A LISTA (escolher, criar, abrir as receitas), o POVOADO com as abas "Atividades", "Estoque" e
## "Editar", e as RECEITAS (o que se faz com quanto trabalho e quais insumos). Só mostra e pede: quem grava é o production_controller.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal settlement_chosen(id: int)
signal back_requested
signal create_requested(name: String, workers: int)  # o próximo clique no globo põe o povoado
signal recipes_requested
signal new_activity_requested                        # de dentro do povoado: criar uma receita nova e voltar para ele
signal recipe_saved(id: int, data: Dictionary)       # id 0 = nova
signal recipe_delete_requested(id: int)
signal activity_added(recipe_id: int, workers: int)
signal activity_workers_set(id: int, workers: int)
signal activity_up(id: int)
signal activity_removed(id: int)
signal stock_changed(good_id: int, qty: float, note: String)  # qty < 0 tira
signal settlement_saved(name: String, workers: int, reach_km: float)
signal move_requested
signal focus_requested
signal delete_requested
signal capability_set(name: String, proficiency: int)   # o povoado sabe fazer (0 = tira)
signal cancel_requested
signal closed

const WIDTH := 340
const TABS := ["Atividades", "Estoque", "Editar"]
const KINDS := [["extracao", "Extrair de uma ocorrência"], ["fabricacao", "Fabricar com insumos"]]
const INPUT_ROWS := 3
const REQUIREMENT_ROWS := 2

var title: Label
var back_button: Button
var message: Label
var list_box: VBoxContainer
var place_button: Button
var recipes_button: Button
signal tutorial_requested  # o botão "?" do cabeçalho
var settlements: ItemList
var empty_list: Label
var new_name: LineEdit
var new_workers: SpinBox
var place_box: VBoxContainer       # a tela de um povoado
var tab_buttons: Array[Button] = []
var pages: Array[VBoxContainer] = []
var tab := 0
var workers_line: Label
var activities: ItemList
var results_box: VBoxContainer      # o que cada atividade fez no último mês, em linhas inteiras
var empty_activities: Label
var activity_recipe: OptionButton
var activity_workers: SpinBox
var create_activity: Button
var selected_box: VBoxContainer
var selected_workers: SpinBox
var stock: ItemList
var stock_title: Label
var capabilities: ItemList
var capability_name: LineEdit
var capability_level: SpinBox
var totals: Label
var recipe_capability: LineEdit
var recipe_requirements: Array = []  # [OptionButton, LineEdit]
var recipe_alternatives: Array = []  # CheckBox por linha de insumo (a primeira não tem)
var _capability_names: Array = []
var empty_stock: Label
var stock_good: OptionButton
var stock_qty: LineEdit
var stock_note: LineEdit
var edit_name: LineEdit
var edit_workers: SpinBox
var edit_reach: SpinBox
var recipes_box: VBoxContainer      # a tela das receitas
var recipes: ItemList
var recipe_name: LineEdit
var recipe_kind: OptionButton
var recipe_output: OptionButton
var recipe_qty: LineEdit
var recipe_labor: LineEdit
var recipe_inputs: Array = []       # [OptionButton, LineEdit]
var recipe_title: Label
var recipe_delete: Button
var waiting := false
var _goods: Array = []             # {id, name, unit} para os menus
var _recipes: Array = []
var _recipe_id := 0                # a receita no formulário (0 = nova)
var _activity_ids: Array = []
var _place := 0


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	custom_minimum_size = Vector2(WIDTH, 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := _column(scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	var head := _row(box)
	back_button = _button(head, "‹ Voltar", func() -> void: back_requested.emit())
	title = _heading(head, "POVOADOS")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	_button(head, "?", func() -> void: tutorial_requested.emit()).tooltip_text = "Ver como funcionam os povoados"
	_button(head, "✕", func() -> void: closed.emit())
	message = _note(box, "")
	message.modulate = Color(1.0, 0.85, 0.4)
	message.hide()
	_build_list(box)
	_build_place(box)
	_build_recipes(box)
	show_screen("lista")


func _build_list(box: VBoxContainer) -> void:
	list_box = _column(box)
	_note(list_box, "Cada mês do calendário, os povoados produzem o que dá com os trabalhadores, os insumos e os recursos ao alcance.")
	settlements = _list(list_box, 260, "Povoados: clique para abrir")
	settlements.item_selected.connect(func(i: int) -> void: settlement_chosen.emit(settlements.get_item_metadata(i)))
	empty_list = _note(list_box, "Nenhum povoado ainda.")
	_heading(list_box, "Novo povoado")
	new_name = _edit(list_box, "Nome do povoado")
	var row := _row(list_box)
	_label(row, "Trabalhadores").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_workers = _spin(row, 0, 1000000, 1, "Trabalhadores")
	place_button = _button(list_box, "Colocar no mapa", func() -> void: create_requested.emit(new_name.text, int(new_workers.value)))
	list_box.add_child(HSeparator.new())
	recipes_button = _button(list_box, "Receitas…", func() -> void: recipes_requested.emit())
	recipes_button.tooltip_text = "O que se pode fazer: quanto trabalho, quais insumos, o que sai"
	var fold := _button(list_box, "▸ Totais por país", Callable())
	fold.toggle_mode = true
	fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	totals = _note(list_box, "")
	totals.hide()
	fold.toggled.connect(func(open: bool) -> void:
		totals.visible = open
		fold.text = ("▾ " if open else "▸ ") + "Totais por país")


func _build_place(box: VBoxContainer) -> void:
	place_box = _column(box)
	var bar := _row(place_box)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := _button(bar, TABS[i], func() -> void: show_tab(i))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_buttons.append(b)
		pages.append(_column(place_box))
	place_box.move_child(place_box.get_child(place_box.get_child_count() - TABS.size()), 1)  # as páginas logo abaixo da barra

	var work := pages[0]
	workers_line = _note(work, "")
	_note(work, "O que é feito num mês só pode ser usado no mês seguinte. As atividades de cima ficam primeiro com os trabalhadores e os insumos.").modulate = Color(1, 1, 1, 0.7)
	empty_activities = _note(work, "Nenhuma atividade. Escolha uma receita abaixo.")
	activities = _list(work, 130, "Atividades: clique para mudar")
	activities.item_selected.connect(func(i: int) -> void: _select_activity(i))
	results_box = _column(work)
	selected_box = _column(work)
	var sel := _row(selected_box)
	_label(sel, "Pessoas").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_workers = _spin(sel, 0, 1000000, 1, "Pessoas nesta atividade")
	var sel_actions := _row(selected_box)
	_button(sel_actions, "Aplicar", func() -> void: activity_workers_set.emit(_activity(), int(selected_workers.value)))
	_button(sel_actions, "Subir", func() -> void: activity_up.emit(_activity()))
	_button(sel_actions, "Tirar", func() -> void: activity_removed.emit(_activity()))
	_heading(work, "Nova atividade")
	activity_recipe = OptionButton.new()
	activity_recipe.fit_to_longest_item = false
	activity_recipe.accessibility_name = "Receita"
	work.add_child(activity_recipe)
	var add := _row(work)
	_label(add, "Pessoas").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	activity_workers = _spin(add, 0, 1000000, 1, "Pessoas na nova atividade")
	_button(add, "Adicionar", func() -> void:
		if activity_recipe.selected >= 0 and not _recipes.is_empty():
			activity_added.emit(int(_recipes[activity_recipe.selected].id), int(activity_workers.value)))
	create_activity = _button(work, "＋ Criar uma atividade diferente…", func() -> void: new_activity_requested.emit())
	create_activity.tooltip_text = "A lista acima mostra as receitas que já existem. Aqui você cria outra: o que se produz, com quanto trabalho e quais insumos."

	var store := pages[1]
	stock_title = _heading(store, "")
	empty_stock = _note(store, "O estoque está vazio.")
	stock = _list(store, 170, "Estoque")
	_heading(store, "Pôr ou tirar")
	_note(store, "Fica no histórico do povoado. Para corrigir, faça o contrário.").modulate = Color(1, 1, 1, 0.7)
	stock_good = OptionButton.new()
	stock_good.fit_to_longest_item = false
	stock_good.accessibility_name = "Bem"
	store.add_child(stock_good)
	stock_qty = _edit(store, "Quantidade")
	stock_note = _edit(store, "Motivo (opcional)")
	var move := _row(store)
	_button(move, "Pôr no estoque", func() -> void: _stock(1.0))
	_button(move, "Tirar do estoque", func() -> void: _stock(-1.0))

	var edit := pages[2]
	_label(edit, "Nome")
	edit_name = _edit(edit, "Nome do povoado")
	var w := _row(edit)
	_label(w, "Trabalhadores").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_workers = _spin(w, 0, 1000000, 1, "Trabalhadores")
	var r := _row(edit)
	_label(r, "Alcance (km)").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_reach = _spin(r, 0, 1000, 1, "Alcance em km")
	edit_reach.tooltip_text = "Até onde o povoado vai buscar um recurso para extrair"
	_button(edit, "Salvar", func() -> void: settlement_saved.emit(edit_name.text, int(edit_workers.value), edit_reach.value))
	edit.add_child(HSeparator.new())
	_heading(edit, "Sabe fazer")
	_note(edit, "Uma receita pode exigir que o povoado saiba algo. A prática (1 a 100%) multiplica o que o trabalho rende.").modulate = Color(1, 1, 1, 0.7)
	capabilities = _list(edit, 90, "O que o povoado sabe fazer")
	capability_name = _edit(edit, "O quê (ex.: Fundir bronze)")
	var lv := _row(edit)
	_label(lv, "Prática (%)").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	capability_level = _spin(lv, 1, 100, 1, "Prática em %")
	capability_level.value = 100
	var cap_actions := _row(edit)
	_button(cap_actions, "Adicionar ou mudar", func() -> void: capability_set.emit(capability_name.text, int(capability_level.value)))
	_button(cap_actions, "Tirar o escolhido", func() -> void:
		var i := capabilities.get_selected_items()
		if not i.is_empty():
			capability_set.emit(_capability_names[i[0]], 0))
	var actions := _row(edit)
	_button(actions, "Ver no mapa", func() -> void: focus_requested.emit())
	_button(actions, "Mover", func() -> void: move_requested.emit())
	edit.add_child(HSeparator.new())
	_button(edit, "Excluir povoado", func() -> void: delete_requested.emit()).tooltip_text = "Só para um povoado sem histórico de estoque"


func _build_recipes(box: VBoxContainer) -> void:
	recipes_box = _column(box)
	_note(recipes_box, "Uma receita diz quanto trabalho e quais insumos fazem quanto de um bem. Os bens são os do painel Recursos.")
	recipes = _list(recipes_box, 170, "Receitas: clique para editar")
	recipes.max_text_lines = 2
	recipes.item_selected.connect(func(i: int) -> void: _load_recipe(_recipes[i]))
	recipe_title = _heading(recipes_box, "Nova receita")
	_button(recipes_box, "Limpar (nova receita)", func() -> void: _load_recipe({}))
	recipe_name = _edit(recipes_box, "Nome (ex.: Extrair sal)")
	recipe_kind = OptionButton.new()
	for k in KINDS:
		recipe_kind.add_item(k[1])
	recipe_kind.accessibility_name = "Tipo de receita"
	recipes_box.add_child(recipe_kind)
	_label(recipes_box, "Produz")
	var out := _row(recipes_box)
	recipe_qty = _edit(out, "Quanto")
	recipe_qty.custom_minimum_size.x = 90
	recipe_output = OptionButton.new()
	recipe_output.fit_to_longest_item = false
	recipe_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_output.accessibility_name = "Bem produzido"
	out.add_child(recipe_output)
	recipe_labor = _edit(recipes_box, "Trabalho por vez (pessoas-dia)")
	recipe_labor.tooltip_text = "Pessoas-dia: 10 = uma pessoa por 10 dias, ou 10 pessoas por um dia"
	_label(recipes_box, "Insumos (gastos; opcionais)")
	for i in INPUT_ROWS:
		if i > 0:
			var alt := CheckBox.new()
			alt.text = "ou este no lugar do de cima"
			alt.tooltip_text = "Marcado, este insumo substitui o de cima: usa-se o de cima e, se faltar, este"
			recipes_box.add_child(alt)
			recipe_alternatives.append(alt)
		var row := _row(recipes_box)
		var qty := _edit(row, "Quanto")
		qty.custom_minimum_size.x = 90
		var good := OptionButton.new()
		good.fit_to_longest_item = false
		good.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		good.accessibility_name = "Insumo %d" % (i + 1)
		row.add_child(good)
		recipe_inputs.append([good, qty])
	_label(recipes_box, "Instalações e ferramentas (não são gastas)")
	for i in REQUIREMENT_ROWS:
		var row := _row(recipes_box)
		var cycles := _edit(row, "Vezes por mês, cada")
		cycles.custom_minimum_size.x = 90
		cycles.tooltip_text = "Quantas vezes por mês uma unidade (um forno, uma ferramenta) permite fazer a receita"
		var good := OptionButton.new()
		good.fit_to_longest_item = false
		good.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		good.accessibility_name = "Instalação ou ferramenta %d" % (i + 1)
		row.add_child(good)
		recipe_requirements.append([good, cycles])
	recipe_capability = _edit(recipes_box, "Exige saber (opcional, ex.: Fundir bronze)")
	var actions := _row(recipes_box)
	_button(actions, "Salvar receita", _save_recipe)
	recipe_delete = _button(actions, "Excluir", func() -> void: recipe_delete_requested.emit(_recipe_id))
	recipe_delete.hide()  # o formulário começa em "Nova receita" (os menus de bens ainda estão vazios)
	recipe_kind.select(1)


## "lista", "povoado" ou "receitas".
func show_screen(screen: String) -> void:
	list_box.visible = screen == "lista"
	place_box.visible = screen == "povoado"
	recipes_box.visible = screen == "receitas"
	back_button.visible = screen != "lista"
	if screen == "lista":
		title.text = "POVOADOS"
		settlements.deselect_all()
		_place = 0
	elif screen == "receitas":
		title.text = "RECEITAS"


func show_tab(index: int) -> void:
	tab = index
	for i in pages.size():
		pages[i].visible = i == index
		tab_buttons[i].set_pressed_no_signal(i == index)


func show_settlements(rows: Array, selected: int) -> void:
	settlements.clear()
	for s in rows:
		var i := settlements.add_item("⌂ %s  · %d trabalhadores" % [s.name, s.workers])
		settlements.set_item_metadata(i, int(s.id))
		if int(s.id) == selected:
			settlements.select(i)
	settlements.visible = not rows.is_empty()
	empty_list.visible = rows.is_empty()


## Os bens (tipos de recurso) e as receitas, para os menus.
func show_catalog(goods: Array, recipe_rows: Array) -> void:
	_goods = goods
	_recipes = recipe_rows
	var keep := _recipe_id
	var chosen_output := recipe_output.selected
	for menu in [stock_good, recipe_output]:
		_fill(menu, goods.map(func(g): return _good_label(g)), false)
	for pair in recipe_inputs + recipe_requirements:
		_fill(pair[0], goods.map(func(g): return _good_label(g)), true)
	_fill(activity_recipe, recipe_rows.map(func(r): return String(r.name)), false)
	recipes.clear()
	for r in recipe_rows:
		var i := recipes.add_item("%s%s\n   %s" % [r.name, "" if r.ok else "  ⚠", r.text])
		recipes.set_item_tooltip(i, r.text)
	var current := recipe_rows.filter(func(r): return int(r.id) == keep)
	if not current.is_empty():
		_load_recipe(current[0])
	elif keep != 0:
		new_recipe()
	else:  # uma receita nova pela metade: o que foi digitado fica, mesmo se o mês virar
		recipe_output.select(mini(chosen_output, recipe_output.item_count - 1))


## Os totais de estoque por país (Registry.StockByCountry), em texto.
func show_totals(rows: Array) -> void:
	var lines: Array[String] = []
	for r in rows:
		lines.append("%s · %s: %s%s" % [r.country, r.name, _number(r.qty), " " + r.unit if r.unit != "" else ""])
	totals.text = "Nenhum estoque ainda." if lines.is_empty() else "\n".join(lines) + "\n(É uma soma dos povoados: não é um estoque à parte.)"


## O povoado aberto: s = uma linha de Settlements; acts = Activities; items = o estoque na data; caps = SettlementCapabilities.
func show_place(s: Dictionary, acts: Array, items: Array, caps: Array = [], date := "") -> void:
	stock_title.text = "Estoque em " + date if date != "" else "Estoque"
	capabilities.clear()
	_capability_names.clear()
	for c in caps:
		capabilities.add_item("%s · prática %d%%" % [c.name, c.proficiency])
		_capability_names.append(String(c.name))
	if int(s.id) != _place:
		_place = int(s.id)
		show_tab(0)
		edit_name.text = s.name
		edit_workers.value = s.workers
		edit_reach.value = s.reach_km
	title.text = String(s.name).to_upper()
	var free: int = int(s.workers) - int(s.assigned)
	workers_line.text = "Trabalhadores: %d · %d em atividades · %d livres" % [s.workers, s.assigned, maxi(free, 0)]
	if free < 0:
		workers_line.text += "\nHá %d pessoas a mais nas atividades: as de baixo ficam sem gente." % -free
	var keep := _activity()
	activities.clear()
	_activity_ids.clear()
	for child in results_box.get_children():
		results_box.remove_child(child)
		child.queue_free()
	if not acts.is_empty():
		_heading(results_box, "Último mês")
	for a in acts:
		var i := activities.add_item("%s · %d pessoas" % [a.recipe, a.workers])
		activities.set_item_tooltip(i, String(a.text))
		_note(results_box, "%s: %s" % [a.recipe, a.last if a.last != "" else "ainda não houve mês processado"])
		_activity_ids.append(int(a.id))
		if int(a.id) == keep:
			activities.select(i)
	activities.visible = not acts.is_empty()
	empty_activities.visible = acts.is_empty()
	selected_box.visible = not activities.get_selected_items().is_empty()
	stock.clear()
	for item in items:
		stock.add_item("%s: %s%s" % [item.name, _number(item.qty), " " + item.unit if item.unit != "" else ""])
	stock.visible = not items.is_empty()
	empty_stock.visible = items.is_empty()


func show_message(text: String) -> void:
	message.text = text
	message.visible = text != ""


func _select_activity(i: int) -> void:
	selected_box.visible = true
	selected_workers.value = int(activities.get_item_text(i).get_slice(" · ", 1).get_slice(" ", 0))


func _activity() -> int:
	var i := activities.get_selected_items()
	return _activity_ids[i[0]] if not i.is_empty() and i[0] < _activity_ids.size() else 0


func _stock(sign: float) -> void:
	var qty := _parse(stock_qty.text)
	if is_nan(qty) or qty <= 0.0:
		show_message("Informe uma quantidade maior que zero.")
		return
	if stock_good.selected < 0:
		show_message("Crie um bem no painel Recursos antes.")
		return
	stock_changed.emit(int(_goods[stock_good.selected].id), sign * qty, stock_note.text)


## O formulário de receita em branco.
func new_recipe() -> void:
	_load_recipe({})


## Deixa a receita escolhida no menu de "Nova atividade".
func choose_recipe(id: int) -> void:
	for i in _recipes.size():
		if int(_recipes[i].id) == id:
			activity_recipe.select(i)


func _load_recipe(r: Dictionary) -> void:
	_recipe_id = int(r.get("id", 0))
	recipe_title.text = "Editar receita" if _recipe_id != 0 else "Nova receita"
	recipe_delete.visible = _recipe_id != 0
	recipe_name.text = r.get("name", "")
	recipe_kind.select(maxi(KINDS.map(func(k): return k[0]).find(r.get("kind", "fabricacao")), 0))
	recipe_output.select(_goods.map(func(g): return int(g.id)).find(int(r.get("output_id", -1))))
	recipe_qty.text = _number(r.output_qty) if r.has("output_qty") else ""
	recipe_labor.text = _number(r.labor_days) if r.has("labor_days") else ""
	var ins: Array = r.get("inputs", [])
	var ids := _goods.map(func(g): return int(g.id))
	for i in INPUT_ROWS:
		var good: OptionButton = recipe_inputs[i][0]
		var qty: LineEdit = recipe_inputs[i][1]
		good.select(0 if i >= ins.size() else 1 + ids.find(int(ins[i].good_id)))
		qty.text = "" if i >= ins.size() else _number(ins[i].qty)
		if i > 0:
			recipe_alternatives[i - 1].button_pressed = i < ins.size() and int(ins[i].group) != 0 and int(ins[i].group) == int(ins[i - 1].group)
	var reqs: Array = r.get("requirements", [])
	for i in REQUIREMENT_ROWS:
		recipe_requirements[i][0].select(0 if i >= reqs.size() else 1 + ids.find(int(reqs[i].good_id)))
		recipe_requirements[i][1].text = "" if i >= reqs.size() else _number(reqs[i].cycles)
	recipe_capability.text = r.get("capability", "")


func _save_recipe() -> void:
	if recipe_output.selected < 0:
		show_message("Crie os bens no painel Recursos antes." if _goods.is_empty() else "Escolha o bem que a receita produz.")
		return
	var inputs: Array = []
	var group := 0
	for i in INPUT_ROWS:
		var pair: Array = recipe_inputs[i]
		if pair[0].selected <= 0:
			continue
		var alt: bool = i > 0 and recipe_alternatives[i - 1].button_pressed and not inputs.is_empty()
		if alt and int(inputs[-1].group) == 0:
			group += 1
			inputs[-1].group = group
		inputs.append({"good_id": int(_goods[pair[0].selected - 1].id), "qty": _parse(pair[1].text), "group": group if alt else 0})
	var requirements: Array = []
	for pair in recipe_requirements:
		if pair[0].selected > 0:
			requirements.append({"good_id": int(_goods[pair[0].selected - 1].id), "cycles": _parse(pair[1].text)})
	recipe_saved.emit(_recipe_id, {"name": recipe_name.text, "kind": KINDS[recipe_kind.selected][0], "output_id": int(_goods[recipe_output.selected].id),
		"output_qty": _parse(recipe_qty.text), "labor_days": _parse(recipe_labor.text), "inputs": inputs, "requirements": requirements,
		"capability": recipe_capability.text.strip_edges()})


static func _good_label(g: Dictionary) -> String:
	return "%s%s" % [g.name, " (%s)" % g.unit if g.unit != "" else ""]


func _fill(menu: OptionButton, labels: Array, with_none: bool) -> void:
	var keep := menu.selected
	menu.clear()
	if with_none:
		menu.add_item("—")
	for l in labels:
		menu.add_item(l)
	menu.select(mini(keep, menu.item_count - 1) if keep >= 0 else (0 if menu.item_count > 0 else -1))


## Números como a ficha: "1.200" é 1200 e "1,5" é 1,5.
static func _parse(text: String) -> float:
	var t := text.strip_edges()
	if t == "":
		return NAN
	if "," in t:
		t = t.replace(".", "").replace(",", ".")
	elif RegEx.create_from_string("^\\d{1,3}(\\.\\d{3})+$").search(t) != null:
		t = t.replace(".", "")
	return float(t) if t.is_valid_float() else NAN


static func _number(v: float) -> String:
	var whole := roundi(v)
	if absf(v - whole) < 0.005:
		var s := str(absi(whole))
		var out := ""
		while s.length() > 3:
			out = "." + s.right(3) + out
			s = s.left(s.length() - 3)
		return ("-" if whole < 0 else "") + s + out
	return ("%.2f" % v).replace(".", ",")


func _unhandled_key_input(e: InputEvent) -> void:
	if visible and waiting and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		cancel_requested.emit()
		get_viewport().set_input_as_handled()


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


func _label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l


func _note(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 40, 0)
	l.add_theme_font_size_override("font_size", 13)
	parent.add_child(l)
	return l


func _edit(parent: Control, hint: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.tooltip_text = hint
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(e)
	return e


func _spin(parent: Control, low: float, high: float, step: float, label: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = low
	s.max_value = high
	s.step = step
	s.accessibility_name = label
	parent.add_child(s)
	return s


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
