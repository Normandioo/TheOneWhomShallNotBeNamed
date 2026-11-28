extends PanelContainer
## O painel da Economia, em telas. A LISTA: como vai cada povoado (gente ocupada e o resultado do último mês), criar um, as receitas e os
## totais por país. O NOVO povoado: numa cidade que já existe (a parte da população que trabalha sugere o número) ou num lugar novo do
## mapa. O POVOADO numa página só: a gente, o que faz (um cartão por atividade: − e + pessoas, a alça ⋮⋮ arrasta e muda a ordem, o
## resultado do mês em cor), o estoque e, recolhidos, os detalhes. A NOVA ATIVIDADE: o que dá para fazer aqui e o que falta (com o
## motivo). As RECEITAS: o que entra, o trabalho, o que sai e o que precisa. Só mostra e pede: quem grava é o production_controller.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")

signal settlement_chosen(id: int)
signal back_requested
signal new_requested                                 # abrir a tela do povoado novo (o controlador traz as cidades)
signal city_chosen(place_id: int, workers: int, pct: float)  # dar economia a uma cidade que já existe (pct NaN = número digitado)
signal create_requested(name: String, workers: int)  # lugar novo: o próximo clique no globo põe o povoado (e a cidade)
signal recipes_requested
signal picker_requested                              # a tela da nova atividade
signal totals_requested
signal new_activity_requested                        # de dentro do povoado: criar uma receita nova e voltar para ele
signal recipe_saved(id: int, data: Dictionary)       # id 0 = nova
signal recipe_delete_requested(id: int)
signal good_create_requested(name: String)           # um bem fabricado novo, para ser o produto da receita
signal activity_added(recipe_id: int, workers: int)
signal activity_workers_set(id: int, workers: int)
signal activity_moved(id: int, index: int)           # arrastar (ou as setas na alça) leva a atividade para a posição index
signal activity_removed(id: int)
signal stock_changed(good_id: int, qty: float, note: String)  # qty < 0 tira
signal settlement_saved(name: String, workers: int, reach_km: float)
signal share_set(pct: float)                         # a parte da população que trabalha (NaN = os trabalhadores foram digitados)
signal move_requested
signal focus_requested
signal delete_requested
signal capability_set(name: String, proficiency: int)   # o povoado sabe fazer (0 = tira)
signal cancel_requested
signal closed
signal tutorial_requested  # o botão "?" do cabeçalho

const WIDTH := 340
const KINDS := [["extracao", "Extrair", "tira de um lugar do mapa"], ["fabricacao", "Fabricar", "transforma o que entra"]]
const INPUT_ROWS := 3
const REQUIREMENT_ROWS := 2
const OK_COLOR := Color("#a6dd7a")
const WARN := Color("#f2c46d")
const STOP := Color("#f08a80")
const MENU_FOCUS := 0
const MENU_MOVE := 1
const MENU_DELETE := 2

var title: Label
var back_button: Button
var menu_button: MenuButton      # ⋯ do povoado: ver no mapa, mover, excluir
var message: Label
var list_box: VBoxContainer      # a lista dos povoados
var settlements: VBoxContainer   # um cartão por povoado
var empty_list: Label
var new_button: Button
var recipes_button: Button
var totals_button: Button
var new_box: VBoxContainer       # o povoado novo
var _origin_cards := {}          # "cidade" / "lugar" -> Button
var new_origin := "cidade"
var city_search: LineEdit
var cities_box: VBoxContainer
var city_box: VBoxContainer      # o que só vale numa cidade
var place_new_box: VBoxContainer # o que só vale num lugar novo
var new_name: LineEdit
var new_pct: SpinBox
var new_workers: SpinBox
var place_button: Button         # "Colocar no mapa" (lugar novo)
var city_button: Button          # "Dar economia a …"
var _cities: Array = []
var _city := {}                  # a cidade escolhida
var place_box: VBoxContainer     # o povoado, numa página só
var workers_line: Label
var workers_bar: ProgressBar
var cards: VBoxContainer         # um cartão por atividade
var empty_activities: Label
var create_activity: Button      # "＋ Nova atividade"
var results_box: VBoxContainer   # o resultado de cada atividade no último mês (um rótulo por cartão)
var stock_title: Label
var stock: VBoxContainer
var empty_stock: Label
var stock_good: OptionButton
var stock_qty: LineEdit
var stock_note: LineEdit
var edit_name: LineEdit
var edit_pct: SpinBox
var edit_workers: SpinBox
var edit_reach: SpinBox
var capabilities: ItemList
var capability_name: LineEdit
var capability_level: SpinBox
var picker_box: VBoxContainer    # a nova atividade
var picker_line: Label
var picker_search: LineEdit
var picker_ready: VBoxContainer
var picker_blocked: VBoxContainer
var recipes_box: VBoxContainer   # as receitas
var recipes: ItemList
var recipe_title: Label
var recipe_name: LineEdit
var recipe_kind: OptionButton    # escondido: os dois cartões escolhem
var _kind_cards: Array = []
var recipe_output: OptionButton
var recipe_qty: LineEdit
var recipe_labor: LineEdit
var recipe_inputs: Array = []       # [OptionButton, LineEdit]
var recipe_alternatives: Array = [] # CheckBox por linha de insumo (a primeira não tem)
var recipe_requirements: Array = [] # [OptionButton, LineEdit]
var recipe_capability: LineEdit
var recipe_sentence: Label
var recipe_delete: Button
var new_good: LineEdit              # criar o bem produzido ali mesmo, sem passar pelo painel Recursos
var totals_box: VBoxContainer
var totals: Label
var waiting := false
var _goods: Array = []             # {id, name, unit} para os menus
var _recipes: Array = []
var _recipe_id := 0                # a receita no formulário (0 = nova)
var _capability_names: Array = []
var _place := {}                   # o povoado aberto (uma linha de Settlements)
var _acts: Array = []
var _blocks := {}                  # receita -> motivo ("" = dá)
var _sync := false


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
	back_button = _button(head, "‹", func() -> void: back_requested.emit())
	back_button.tooltip_text = "Voltar"
	var icon := TextureRect.new()
	icon.texture = UiIcons.get_icon("economy", 20)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.modulate = UiKit.ICON_COLOR["economy"]
	head.add_child(icon)
	title = _heading(head, "ECONOMIA")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	menu_button = MenuButton.new()
	menu_button.icon = UiIcons.get_icon("more", 18)
	menu_button.tooltip_text = "Mais: ver no mapa, mover e excluir o povoado"
	menu_button.accessibility_name = "Mais ações do povoado"
	menu_button.flat = false
	menu_button.get_popup().add_item("Ver no mapa", MENU_FOCUS)
	menu_button.get_popup().add_item("Mover para outro ponto", MENU_MOVE)
	menu_button.get_popup().add_separator()
	menu_button.get_popup().add_item("Excluir povoado…", MENU_DELETE)
	menu_button.get_popup().set_item_tooltip(3, "Só um povoado sem histórico de estoque")
	menu_button.get_popup().id_pressed.connect(_on_menu)
	head.add_child(menu_button)
	_button(head, "?", func() -> void: tutorial_requested.emit()).tooltip_text = "Ver como funciona a economia"
	_button(head, "✕", func() -> void: closed.emit())
	message = _note(box, "")
	message.modulate = Color(1.0, 0.85, 0.4)
	message.hide()
	_build_list(box)
	_build_new(box)
	_build_place(box)
	_build_picker(box)
	_build_recipes(box)
	_build_totals(box)
	show_screen("lista")


func _on_menu(id: int) -> void:
	if id == MENU_FOCUS:
		focus_requested.emit()
	elif id == MENU_MOVE:
		move_requested.emit()
	elif id == MENU_DELETE:
		delete_requested.emit()


# --- a lista -----------------------------------------------------------------------------------------------------

func _build_list(box: VBoxContainer) -> void:
	list_box = _column(box)
	list_box.add_theme_constant_override("separation", 8)
	_note(list_box, "A cada mês do calendário, cada povoado produz com sua gente, seus insumos e os recursos ao alcance.").modulate = Color(1, 1, 1, 0.7)
	new_button = _button(list_box, "＋ Novo povoado", func() -> void: new_requested.emit())
	new_button.add_theme_stylebox_override("normal", UiKit.active_style())
	new_button.custom_minimum_size.y = 40
	_section(list_box, "Povoados · último mês")
	settlements = _column(list_box)
	empty_list = _note(list_box, "Nenhum povoado ainda. Dê economia a uma cidade em ＋ Novo povoado.")
	list_box.add_child(HSeparator.new())
	var foot := _row(list_box)
	recipes_button = _button(foot, "Receitas", func() -> void: recipes_requested.emit())
	recipes_button.icon = UiIcons.get_icon("file", 16)
	recipes_button.tooltip_text = "O que se pode fazer: quanto trabalho, o que entra, o que sai"
	totals_button = _button(foot, "Por país", func() -> void: totals_requested.emit())
	totals_button.icon = UiIcons.get_icon("population", 16)
	totals_button.tooltip_text = "O estoque de cada país: a soma dos povoados dentro dele"
	for b in [recipes_button, totals_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## rows: Settlements, cada uma com "status" ("ok" | "warn" | "stop" | "") e "summary" (o último mês em palavras).
func show_settlements(rows: Array, selected: int) -> void:
	for child in settlements.get_children():
		settlements.remove_child(child)
		child.queue_free()
	for s in rows:
		var card := _button(settlements, "", func() -> void: settlement_chosen.emit(int(s.id)))
		card.set_meta("id", int(s.id))
		card.custom_minimum_size.y = 66
		card.tooltip_text = "Abrir %s" % s.name
		card.accessibility_name = "%s, %d de %d pessoas trabalhando. %s" % [s.name, s.assigned, s.workers, s.get("summary", "")]
		if int(s.id) == selected:
			card.add_theme_stylebox_override("normal", UiKit.active_style())
		var body := VBoxContainer.new()
		body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		body.offset_left = 10
		body.offset_right = -10
		body.offset_top = 6
		body.offset_bottom = -6
		body.add_theme_constant_override("separation", 3)
		card.add_child(body)
		var top := HBoxContainer.new()
		body.add_child(top)
		var house := TextureRect.new()
		house.texture = UiIcons.get_icon("house", 16)
		house.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		house.modulate = UiKit.FOCUS
		top.add_child(house)
		var name_label := Label.new()
		name_label.text = s.name
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_label)
		var people := Label.new()
		people.text = "%d de %d pessoas" % [s.assigned, s.workers]
		people.add_theme_font_size_override("font_size", 12)
		people.modulate.a = 0.7
		top.add_child(people)
		body.add_child(_bar(int(s.assigned), int(s.workers)))
		var line := Label.new()
		line.text = String(s.get("summary", ""))
		line.clip_text = true
		line.add_theme_font_size_override("font_size", 12)
		line.add_theme_color_override("font_color", {"ok": OK_COLOR, "warn": WARN, "stop": STOP}.get(s.get("status", ""), Color(1, 1, 1, 0.6)))
		body.add_child(line)
		for node in [body, top, house, name_label, people, line] + body.get_children():
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_list.visible = rows.is_empty()


func settlement_rows() -> Array:
	return settlements.get_children()


func _bar(value: int, total: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = maxi(total, 1)
	bar.value = clampi(value, 0, maxi(total, 1))
	bar.custom_minimum_size.y = 6
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiKit.BRASS
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = UiKit.BAR
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar


# --- o povoado novo ----------------------------------------------------------------------------------------------

func _build_new(box: VBoxContainer) -> void:
	new_box = _column(box)
	new_box.add_theme_constant_override("separation", 8)
	_note(new_box, "Um povoado é a economia de uma cidade: quem trabalha nela, o que faz e o que guarda.").modulate = Color(1, 1, 1, 0.7)
	_section(new_box, "Onde fica?")
	_origin_cards["cidade"] = _choice_card(new_box, "population", "Numa cidade que já existe",
		"Usa o lugar e o nome dela. A cidade continua na ficha do país, com a população.", func() -> void: _pick_origin("cidade"))
	_origin_cards["lugar"] = _choice_card(new_box, "place", "Num lugar novo do mapa",
		"Clique no globo. O lugar vira uma cidade nova, já com economia.", func() -> void: _pick_origin("lugar"))
	city_box = _column(new_box)
	city_search = _edit(city_box, "Buscar cidade")
	city_search.right_icon = UiIcons.get_icon("search", 16)
	city_search.text_changed.connect(func(_t: String) -> void: _show_cities())
	cities_box = _column(city_box)
	cities_box.add_theme_constant_override("separation", 2)
	place_new_box = _column(new_box)
	new_name = _edit(place_new_box, "Nome da cidade nova")
	_section(new_box, "Quem trabalha")
	var share := _row(new_box)
	new_pct = _spin(share, 0, 100, 1, "Parte da população que trabalha, em %")
	new_pct.suffix = "%"
	new_pct.value = 25
	new_pct.tooltip_text = "Você escolhe quanto da população trabalha. Mudar um campo atualiza o outro."
	var of := _label(share, "")
	of.add_theme_font_size_override("font_size", 13)
	new_workers = _spin(share, 0, 100000000, 1, "Trabalhadores")
	_label(share, "pessoas")
	new_pct.value_changed.connect(func(_v: float) -> void: _sync_new_workers(true))
	new_workers.value_changed.connect(func(_v: float) -> void: _sync_new_workers(false))
	new_pct.set_meta("of", of)
	city_button = _button(new_box, "Dar economia à cidade", func() -> void:
		if _city.is_empty():
			show_message("Escolha a cidade na lista.")
			return
		city_chosen.emit(int(_city.place_id), int(new_workers.value), new_pct.value if _has_population() else NAN))
	place_button = _button(new_box, "Colocar no mapa", func() -> void: create_requested.emit(new_name.text, int(new_workers.value)))
	for b in [city_button, place_button]:
		b.add_theme_stylebox_override("normal", UiKit.active_style())
		b.custom_minimum_size.y = 40
	_pick_origin("cidade")


func _pick_origin(origin: String) -> void:
	new_origin = origin
	for key in _origin_cards:
		_origin_cards[key].set_pressed_no_signal(key == origin)
	city_box.visible = origin == "cidade"
	city_button.visible = origin == "cidade"
	place_new_box.visible = origin == "lugar"
	place_button.visible = origin == "lugar"
	_sync_new_workers(true)


## As cidades para escolher: {place_id, name, country, population, settlement_id} (Registry.Cities).
func show_cities(rows: Array) -> void:
	_cities = rows
	if not _city.is_empty() and not rows.any(func(c): return int(c.place_id) == int(_city.place_id) and int(c.settlement_id) == 0):
		_city = {}
	_show_cities()


func _show_cities() -> void:
	for child in cities_box.get_children():
		cities_box.remove_child(child)
		child.queue_free()
	var wanted := city_search.text.strip_edges().to_lower()
	var shown := 0
	for c in _cities:
		if wanted != "" and not String(c.name).to_lower().contains(wanted):
			continue
		shown += 1
		var free := int(c.settlement_id) == 0
		var parts: Array[String] = []
		if c.country != "":
			parts.append(c.country)
		if not is_nan(float(c.population)):
			parts.append("%s hab." % _number(c.population))
		var b := _button(cities_box, "%s%s%s" % [c.name, "  ·  " + " · ".join(parts) if not parts.is_empty() else "", "" if free else "  ·  já tem economia"],
			func() -> void:
				_city = c
				_show_cities()
				_sync_new_workers(true))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.icon = UiIcons.get_icon("house", 16)
		b.disabled = not free
		b.set_meta("place_id", int(c.place_id))
		if not _city.is_empty() and int(c.place_id) == int(_city.place_id):
			b.add_theme_stylebox_override("normal", UiKit.active_style())
	if shown == 0:
		_note(cities_box, "Nenhuma cidade ainda. Crie uma na ficha do país (População) ou escolha Num lugar novo do mapa." if _cities.is_empty()
			else "Nenhuma cidade com esse nome.")
	city_button.text = "Dar economia a %s" % _city.name if not _city.is_empty() else "Dar economia à cidade"


func _has_population() -> bool:
	return new_origin == "cidade" and not _city.is_empty() and not is_nan(float(_city.population))


## % e pessoas andam juntos quando a cidade tem população; from_pct: quem mudou foi a porcentagem.
func _sync_new_workers(from_pct: bool) -> void:
	if _sync:
		return
	_sync = true
	var of: Label = new_pct.get_meta("of")
	var known := _has_population()
	new_pct.editable = known
	of.text = "de %s hab. =" % _number(_city.population) if known else "(sem população: digite as pessoas)"
	if known:
		var pop := float(_city.population)
		if from_pct:
			new_workers.value = roundi(pop * new_pct.value / 100.0)
		elif pop > 0.0:
			new_pct.value = clampf(new_workers.value * 100.0 / pop, 0.0, 100.0)
	_sync = false


## Um cartão de escolha: ícone, título e uma linha explicando.
func _choice_card(parent: Control, icon_name: String, heading: String, about: String, on_press: Callable) -> Button:
	var card := _button(parent, "", on_press)
	card.toggle_mode = true
	card.custom_minimum_size.y = 74
	card.tooltip_text = about
	card.accessibility_name = "%s: %s" % [heading, about]
	card.add_theme_stylebox_override("pressed", UiKit.active_style())
	var body := VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 10
	body.offset_right = -10
	body.offset_top = 6
	body.add_theme_constant_override("separation", 0)
	card.add_child(body)
	var top := HBoxContainer.new()
	body.add_child(top)
	var icon := TextureRect.new()
	icon.texture = UiIcons.get_icon(icon_name, 18)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	top.add_child(icon)
	var name_label := Label.new()
	name_label.text = heading
	top.add_child(name_label)
	var line := Label.new()
	line.text = about
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", 12)
	line.modulate.a = 0.7
	body.add_child(line)
	for node in [body, top, icon, name_label, line]:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


# --- o povoado ---------------------------------------------------------------------------------------------------

func _build_place(box: VBoxContainer) -> void:
	place_box = _column(box)
	place_box.add_theme_constant_override("separation", 8)
	workers_line = _label(place_box, "")
	workers_bar = _bar(0, 1)
	place_box.add_child(workers_bar)

	_section(place_box, "O que faz")
	_note(place_box, "As de cima ficam primeiro com a gente e os insumos: arraste pela alça ⋮⋮ (ou use as setas nela). O que é feito num mês só pode ser usado no seguinte.").modulate = Color(1, 1, 1, 0.65)
	empty_activities = _note(place_box, "Nenhuma atividade ainda.")
	cards = _column(place_box)
	cards.add_theme_constant_override("separation", 6)
	results_box = cards  # cada cartão traz o resultado do mês (os testes leem por aqui)
	create_activity = _button(place_box, "＋ Nova atividade", func() -> void: picker_requested.emit())
	create_activity.tooltip_text = "As receitas que dá para fazer aqui, e o que falta nas outras"

	_section(place_box, "Estoque")
	stock_title = _label(place_box, "")
	stock_title.add_theme_font_size_override("font_size", 12)
	stock_title.modulate.a = 0.7
	empty_stock = _note(place_box, "O estoque está vazio.")
	stock = _column(place_box)
	stock.add_theme_constant_override("separation", 0)
	var move := _fold(place_box, "± Pôr ou tirar do estoque")
	_note(move, "Fica no histórico do povoado. Para corrigir, faça o contrário.").modulate = Color(1, 1, 1, 0.7)
	stock_good = OptionButton.new()
	stock_good.fit_to_longest_item = false
	stock_good.accessibility_name = "Bem"
	move.add_child(stock_good)
	stock_qty = _edit(move, "Quantidade")
	stock_note = _edit(move, "Motivo (opcional)")
	var moves := _row(move)
	_button(moves, "Pôr no estoque", func() -> void: _stock(1.0))
	_button(moves, "Tirar do estoque", func() -> void: _stock(-1.0))

	var edit := _fold(place_box, "Detalhes: nome, gente, alcance, saber")
	_label(edit, "Nome (é o da cidade)")
	edit_name = _edit(edit, "Nome do povoado")
	var share := _row(edit)
	edit_pct = _spin(share, 0, 100, 1, "Parte da população que trabalha, em %")
	edit_pct.suffix = "%"
	var of := _label(share, "")
	of.add_theme_font_size_override("font_size", 13)
	edit_pct.set_meta("of", of)
	edit_workers = _spin(share, 0, 100000000, 1, "Trabalhadores")
	_label(share, "pessoas")
	edit_pct.value_changed.connect(func(_v: float) -> void: _sync_edit_workers(true))
	edit_workers.value_changed.connect(func(_v: float) -> void: _sync_edit_workers(false))
	var r := _row(edit)
	_label(r, "Alcance (km)").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_reach = _spin(r, 0, 1000, 1, "Alcance em km")
	edit_reach.tooltip_text = "Até onde o povoado vai buscar um recurso para extrair"
	_button(edit, "Salvar", func() -> void:
		settlement_saved.emit(edit_name.text, int(edit_workers.value), edit_reach.value)
		share_set.emit(edit_pct.value if _place_population() else NAN))
	edit.add_child(HSeparator.new())
	_label(edit, "Sabe fazer")
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


func _place_population() -> bool:
	return not _place.is_empty() and not is_nan(float(_place.get("population", NAN)))


func _sync_edit_workers(from_pct: bool) -> void:
	if _sync:
		return
	_sync = true
	var of: Label = edit_pct.get_meta("of")
	var known := _place_population()
	edit_pct.editable = known
	of.text = "de %s hab. =" % _number(_place.population) if known else "(a cidade não tem população)"
	if known:
		var pop := float(_place.population)
		if from_pct:
			edit_workers.value = roundi(pop * edit_pct.value / 100.0)
		elif pop > 0.0:
			edit_pct.value = clampf(edit_workers.value * 100.0 / pop, 0.0, 100.0)
	_sync = false


## O povoado aberto: s = uma linha de Settlements; acts = Activities; items = o estoque na data; caps = SettlementCapabilities.
func show_place(s: Dictionary, acts: Array, items: Array, caps: Array = [], date := "") -> void:
	var fresh := _place.is_empty() or int(_place.id) != int(s.id)
	_place = s
	_acts = acts
	title.text = String(s.name).to_upper()
	stock_title.text = "em " + date if date != "" else ""
	var free: int = int(s.workers) - int(s.assigned)
	workers_line.text = "%d pessoas · %d trabalhando · %d livres" % [s.workers, s.assigned, maxi(free, 0)]
	if free < 0:
		workers_line.text += "\nHá %d pessoas a mais nas atividades: as de baixo ficam sem gente." % -free
	workers_bar.max_value = maxi(int(s.workers), 1)
	workers_bar.value = clampi(int(s.assigned), 0, maxi(int(s.workers), 1))
	if fresh:
		_sync = true
		edit_name.text = s.name
		edit_workers.value = s.workers
		edit_reach.value = s.reach_km
		edit_pct.value = 0.0 if is_nan(float(s.get("work_pct", NAN))) else float(s.work_pct)
		_sync = false
		_sync_edit_workers(false)
	capabilities.clear()
	_capability_names.clear()
	for c in caps:
		capabilities.add_item("%s · prática %d%%" % [c.name, c.proficiency])
		_capability_names.append(String(c.name))
	for child in cards.get_children():
		cards.remove_child(child)
		child.queue_free()
	for i in acts.size():
		_activity_card(acts[i], i)
	empty_activities.visible = acts.is_empty()
	for child in stock.get_children():
		stock.remove_child(child)
		child.queue_free()
	for item in items:
		var line := _label(stock, "%s: %s%s" % [item.name, _number(item.qty), " " + item.unit if item.unit != "" else ""])
		line.add_theme_font_size_override("font_size", 14)
	empty_stock.visible = items.is_empty()


## Um cartão de atividade: a alça (arrastar ou setas), o nome, − pessoas +, a receita e o resultado do último mês, em cor.
func _activity_card(a: Dictionary, index: int) -> void:
	var card := ActivityCard.new()
	card.panel = self
	card.activity = int(a.id)
	card.index = index
	card.add_theme_stylebox_override("panel", UiKit.card_style())
	cards.add_child(card)
	var body := _column(card)
	body.add_theme_constant_override("separation", 2)
	var top := _row(body)
	var handle := Handle.new()
	handle.panel = self
	handle.activity = int(a.id)
	handle.index = index
	handle.text = "⋮⋮"
	handle.flat = true
	handle.tooltip_text = "Arraste para mudar a ordem (ou use as setas para cima e para baixo)"
	handle.accessibility_name = "Ordem de %s: posição %d. Setas mudam." % [a.recipe, index + 1]
	top.add_child(handle)
	var name_label := Label.new()
	name_label.text = a.recipe
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var minus := _button(top, "−", func() -> void: activity_workers_set.emit(int(a.id), maxi(int(a.workers) - 1, 0)))
	minus.accessibility_name = "Menos pessoas em %s" % a.recipe
	var count := LineEdit.new()
	count.text = str(a.workers)
	count.custom_minimum_size.x = 52
	count.alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.accessibility_name = "Pessoas em %s" % a.recipe
	count.text_submitted.connect(func(t: String) -> void:
		var n := _parse(t)
		if not is_nan(n):
			activity_workers_set.emit(int(a.id), maxi(roundi(n), 0)))
	top.add_child(count)
	var plus := _button(top, "+", func() -> void: activity_workers_set.emit(int(a.id), int(a.workers) + 1))
	plus.accessibility_name = "Mais pessoas em %s" % a.recipe
	var remove := _button(top, "✕", func() -> void: activity_removed.emit(int(a.id)))
	remove.flat = true
	remove.tooltip_text = "Tirar esta atividade"
	var recipe := Label.new()
	recipe.text = String(a.text)
	recipe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recipe.custom_minimum_size.x = WIDTH - 60
	recipe.add_theme_font_size_override("font_size", 12)
	recipe.modulate.a = 0.65
	body.add_child(recipe)
	var last := Label.new()
	var note := String(a.last)
	last.text = ("%s: %s" % [a.recipe, note]) if note != "" else "%s: ainda não houve mês processado" % a.recipe
	last.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	last.custom_minimum_size.x = WIDTH - 60
	last.add_theme_font_size_override("font_size", 12)
	last.add_theme_color_override("font_color", _note_color(note))
	body.add_child(last)


## A cor do resultado do mês: parou = vermelho, limitado = amarelo, produziu = verde.
static func _note_color(note: String) -> Color:
	if note.begins_with("parou"):
		return STOP
	if note.contains("limitado") or note.contains("(só ") or note.begins_with("só "):
		return WARN
	if note.begins_with("+"):
		return OK_COLOR
	return Color(1, 1, 1, 0.6)


## A alça do cartão: arrastar leva a atividade a outro lugar; as setas sobem e descem uma posição.
class Handle extends Button:
	var panel
	var activity := 0
	var index := 0

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = "⋮⋮ mover"
		set_drag_preview(preview)
		return {"activity": activity}

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_UP, KEY_DOWN]:
			panel.activity_moved.emit(activity, maxi(index + (-1 if e.keycode == KEY_UP else 1), 0))
			accept_event()


## O cartão recebe a atividade arrastada: ela vai para a posição dele.
class ActivityCard extends PanelContainer:
	var panel
	var activity := 0
	var index := 0

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("activity") and int(data.activity) != activity

	func _drop_data(_at: Vector2, data: Variant) -> void:
		panel.activity_moved.emit(int(data.activity), index)


## Os cartões de atividade, na ordem.
func activity_cards() -> Array:
	return cards.get_children()


# --- a nova atividade --------------------------------------------------------------------------------------------

func _build_picker(box: VBoxContainer) -> void:
	picker_box = _column(box)
	picker_box.add_theme_constant_override("separation", 8)
	picker_line = _label(picker_box, "")
	picker_line.add_theme_font_size_override("font_size", 13)
	picker_line.modulate.a = 0.7
	picker_search = _edit(picker_box, "Buscar receita ou bem")
	picker_search.right_icon = UiIcons.get_icon("search", 16)
	picker_search.text_changed.connect(func(_t: String) -> void: _show_picker())
	_section(picker_box, "Dá para fazer aqui")
	picker_ready = _column(picker_box)
	_section(picker_box, "Falta algo")
	picker_blocked = _column(picker_box)
	var make := _button(picker_box, "＋ Criar receita nova", func() -> void: new_activity_requested.emit())
	make.tooltip_text = "O que se produz, com quanto trabalho e o que entra. Você volta para cá depois de salvar."


## blocks: Registry.RecipeBlocks do povoado aberto (receita -> motivo; "" = dá para fazer).
func show_picker(blocks: Dictionary) -> void:
	_blocks = blocks
	var free: int = int(_place.get("workers", 0)) - int(_place.get("assigned", 0))
	picker_line.text = "em %s · %d %s" % [_place.get("name", ""), maxi(free, 0), "pessoa livre" if free == 1 else "pessoas livres"]
	_show_picker()


func _show_picker() -> void:
	for box in [picker_ready, picker_blocked]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	var wanted := picker_search.text.strip_edges().to_lower()
	var free: int = maxi(int(_place.get("workers", 0)) - int(_place.get("assigned", 0)), 0)
	for r in _recipes:
		if wanted != "" and not (String(r.name) + " " + String(r.text)).to_lower().contains(wanted):
			continue
		var why: String = _blocks.get(int(r.id), "")
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiKit.card_style())
		row.set_meta("recipe", int(r.id))
		(picker_ready if why == "" else picker_blocked).add_child(row)
		var line := HBoxContainer.new()
		row.add_child(line)
		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_theme_constant_override("separation", 0)
		line.add_child(texts)
		var name_label := _label(texts, r.name)
		name_label.clip_text = true
		var detail := Label.new()
		detail.text = r.text if why == "" else why
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.custom_minimum_size.x = WIDTH - 110
		detail.add_theme_font_size_override("font_size", 12)
		if why == "":
			detail.modulate.a = 0.65
		else:
			detail.add_theme_color_override("font_color", WARN)
			name_label.modulate.a = 0.75
		texts.add_child(detail)
		if why == "":
			var add := _button(line, "＋", func() -> void: activity_added.emit(int(r.id), free))
			add.add_theme_stylebox_override("normal", UiKit.active_style())
			add.custom_minimum_size = Vector2(36, 36)
			add.tooltip_text = "Pôr %s neste povoado, com as %d pessoas livres (mude depois com − e +)" % [r.name, free]
	if picker_ready.get_child_count() == 0:
		_note(picker_ready, "Nenhuma receita dá para fazer aqui ainda.").modulate = Color(1, 1, 1, 0.7)
	if picker_blocked.get_child_count() == 0:
		_note(picker_blocked, "Nada.").modulate = Color(1, 1, 1, 0.7)


## As linhas da nova atividade: [prontas, com falta].
func picker_rows() -> Array:
	return [picker_ready.get_children().filter(func(c): return c is PanelContainer),
		picker_blocked.get_children().filter(func(c): return c is PanelContainer)]


# --- as receitas -------------------------------------------------------------------------------------------------

func _build_recipes(box: VBoxContainer) -> void:
	recipes_box = _column(box)
	recipes_box.add_theme_constant_override("separation", 8)
	_note(recipes_box, "Uma receita diz o que entra, quanto trabalho leva e o que sai. Um bem fabricado se cria aqui mesmo e não precisa de lugar no mapa.").modulate = Color(1, 1, 1, 0.7)
	recipes = _list(recipes_box, 150, "Receitas: clique para editar")
	recipes.max_text_lines = 2
	recipes.item_selected.connect(func(i: int) -> void: _load_recipe(_recipes[i]))
	recipe_title = _heading(recipes_box, "Nova receita")
	_button(recipes_box, "Limpar (nova receita)", func() -> void: _load_recipe({}))
	recipe_name = _edit(recipes_box, "Nome (ex.: Forjar espada)")
	recipe_kind = OptionButton.new()
	for k in KINDS:
		recipe_kind.add_item(k[1])
	recipe_kind.hide()
	recipes_box.add_child(recipe_kind)
	var kinds := HBoxContainer.new()
	recipes_box.add_child(kinds)
	for i in KINDS.size():
		var card := _choice_card(kinds, "generate" if i == 0 else "hammer", KINDS[i][1], KINDS[i][2], func() -> void:
			recipe_kind.select(i)
			_sync_kind())
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_kind_cards.append(card)

	_section(recipes_box, "Entra (é gasto; opcional)")
	for i in INPUT_ROWS:
		if i > 0:
			var alt := CheckBox.new()
			alt.text = "ou este no lugar do de cima"
			alt.tooltip_text = "Marcado, este insumo substitui o de cima: usa-se o de cima e, se faltar, este"
			alt.toggled.connect(func(_on: bool) -> void: _sync_sentence())
			recipes_box.add_child(alt)
			recipe_alternatives.append(alt)
		var row := _row(recipes_box)
		var qty := _edit(row, "Quanto")
		qty.custom_minimum_size.x = 80
		qty.size_flags_horizontal = Control.SIZE_FILL
		var good := _good_menu(row, "Insumo %d" % (i + 1))
		recipe_inputs.append([good, qty])
	_section(recipes_box, "Trabalho")
	var labor := _row(recipes_box)
	recipe_labor = _edit(labor, "10")
	recipe_labor.custom_minimum_size.x = 80
	recipe_labor.size_flags_horizontal = Control.SIZE_FILL
	recipe_labor.accessibility_name = "Trabalho por vez, em pessoas-dia"
	_label(labor, "pessoas-dia por vez")
	_note(recipes_box, "10 = uma pessoa por 10 dias, ou 10 pessoas por um dia.").modulate = Color(1, 1, 1, 0.65)
	_section(recipes_box, "Sai")
	var out := _row(recipes_box)
	recipe_qty = _edit(out, "Quanto")
	recipe_qty.custom_minimum_size.x = 80
	recipe_qty.size_flags_horizontal = Control.SIZE_FILL
	recipe_output = _good_menu(out, "Bem produzido")
	var fresh := _row(recipes_box)
	new_good = _edit(fresh, "ou um bem fabricado novo (ex.: Espada)")
	new_good.text_submitted.connect(func(t: String) -> void: good_create_requested.emit(t))
	_button(fresh, "Criar bem", func() -> void: good_create_requested.emit(new_good.text)).tooltip_text = \
		"Entra nos Recursos como Manufatura, sem lugar no mapa: ele é feito nos povoados"
	_section(recipes_box, "Precisa (opcional; não é gasto)")
	for i in REQUIREMENT_ROWS:
		var row := _row(recipes_box)
		var cycles := _edit(row, "Vezes/mês")
		cycles.custom_minimum_size.x = 80
		cycles.size_flags_horizontal = Control.SIZE_FILL
		cycles.tooltip_text = "Quantas vezes por mês uma unidade (um forno, uma ferramenta) permite fazer a receita"
		var good := _good_menu(row, "Instalação ou ferramenta %d" % (i + 1))
		recipe_requirements.append([good, cycles])
	recipe_capability = _edit(recipes_box, "Saber fazer (ex.: Fundir bronze)")
	recipe_sentence = _note(recipes_box, "")
	recipe_sentence.add_theme_color_override("font_color", UiKit.PAPER)
	for e in [recipe_name, recipe_qty, recipe_labor, recipe_capability] + recipe_inputs.map(func(p): return p[1]) + recipe_requirements.map(func(p): return p[1]):
		e.text_changed.connect(func(_t: String) -> void: _sync_sentence())
	var actions := _row(recipes_box)
	var save := _button(actions, "Salvar receita", _save_recipe)
	save.add_theme_stylebox_override("normal", UiKit.active_style())
	save.custom_minimum_size.y = 40
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_delete = _button(actions, "Excluir", func() -> void: recipe_delete_requested.emit(_recipe_id))
	recipe_delete.hide()  # o formulário começa em "Nova receita"
	recipe_kind.select(1)
	_sync_kind()


func _good_menu(parent: Control, label: String) -> OptionButton:
	var good := OptionButton.new()
	good.fit_to_longest_item = false
	good.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	good.accessibility_name = label
	good.item_selected.connect(func(_i: int) -> void: _sync_sentence())
	parent.add_child(good)
	return good


func _sync_kind() -> void:
	for i in _kind_cards.size():
		_kind_cards[i].set_pressed_no_signal(i == recipe_kind.selected)
	_sync_sentence()


## A receita em uma frase, enquanto é escrita: "10 pessoas-dia e 2 t de Ferro → 1 Espada; precisa ter Forja".
func _sync_sentence() -> void:
	if recipe_sentence == null:
		return
	var parts: Array[String] = []
	var labor := _parse(recipe_labor.text)
	parts.append("%s pessoas-dia" % (_number(labor) if not is_nan(labor) else "?"))
	for i in INPUT_ROWS:
		var pair: Array = recipe_inputs[i]
		if pair[0].selected > 0:
			var piece := _amount(pair[1].text, _goods[pair[0].selected - 1])
			if i > 0 and recipe_alternatives[i - 1].button_pressed and parts.size() > 1:
				parts[-1] += " ou " + piece
			else:
				parts.append(piece)
	var text := " e ".join(parts) + " → " + (_amount(recipe_qty.text, _goods[recipe_output.selected]) if recipe_output.selected >= 0 else "?")
	if KINDS[recipe_kind.selected][0] == "extracao":
		text += " (tirado de um lugar ao alcance)"
	var needs: Array[String] = []
	for pair in recipe_requirements:
		if pair[0].selected > 0:
			needs.append(String(_goods[pair[0].selected - 1].name))
	if not needs.is_empty():
		text += "; precisa ter " + ", ".join(needs)
	if recipe_capability.text.strip_edges() != "":
		text += "; precisa saber " + recipe_capability.text.strip_edges()
	recipe_sentence.text = text


func _amount(qty_text: String, g: Dictionary) -> String:
	var q := _parse(qty_text)
	return "%s%s %s" % [_number(q) if not is_nan(q) else "?", " " + g.unit if g.unit != "" else "", g.name]


# --- os totais ---------------------------------------------------------------------------------------------------

func _build_totals(box: VBoxContainer) -> void:
	totals_box = _column(box)
	_note(totals_box, "É a soma dos povoados que ficam dentro de cada país pintado, na data do relógio. Não é um estoque à parte.").modulate = Color(1, 1, 1, 0.7)
	totals = _note(totals_box, "")


## Os totais de estoque por país (Registry.StockByCountry), um país por bloco.
func show_totals(rows: Array) -> void:
	var by := {}
	var order: Array = []
	for r in rows:
		var key := String(r.country) if String(r.country) != "" else "Fora de país"
		if not by.has(key):
			by[key] = []
			order.append(key)
		by[key].append("   %s: %s%s" % [r.name, _number(r.qty), " " + r.unit if r.unit != "" else ""])
	var lines: Array[String] = []
	for key in order:
		lines.append(key)
		lines.append_array(by[key])
	totals.text = "Nenhum estoque ainda." if lines.is_empty() else "\n".join(lines)


# --- telas -------------------------------------------------------------------------------------------------------

## "lista", "novo", "povoado", "atividade", "receitas" ou "totais".
func show_screen(screen: String) -> void:
	list_box.visible = screen == "lista"
	new_box.visible = screen == "novo"
	place_box.visible = screen == "povoado"
	picker_box.visible = screen == "atividade"
	recipes_box.visible = screen == "receitas"
	totals_box.visible = screen == "totais"
	back_button.visible = screen != "lista"
	menu_button.visible = screen == "povoado"
	match screen:
		"lista":
			title.text = "ECONOMIA"
			_place = {}
		"novo":
			title.text = "NOVO POVOADO"
			_city = {}
			city_search.text = ""
			new_name.text = ""
			_pick_origin("cidade")
		"atividade":
			title.text = "NOVA ATIVIDADE"
			picker_search.text = ""
		"receitas":
			title.text = "RECEITAS"
		"totais":
			title.text = "POR PAÍS"


func current_screen() -> String:
	for pair in [[list_box, "lista"], [new_box, "novo"], [place_box, "povoado"], [picker_box, "atividade"], [recipes_box, "receitas"], [totals_box, "totais"]]:
		if pair[0].visible:
			return pair[1]
	return ""


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
	_sync_sentence()


func show_message(text: String) -> void:
	message.text = text
	message.visible = text != ""


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


## Deixa o bem escolhido como produto da receita (depois de show_catalog).
func choose_output(id: int) -> void:
	recipe_output.select(_goods.map(func(g): return int(g.id)).find(id))
	_sync_sentence()


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
	_sync_kind()


func _save_recipe() -> void:
	if recipe_output.selected < 0:
		show_message("Escolha o bem que a receita produz, ou crie um bem fabricado novo logo abaixo.")
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


func _section(parent: Control, text: String) -> Label:
	var l := _heading(parent, text.to_upper())
	l.add_theme_font_size_override("font_size", 13)
	return l


## Uma parte que abre e fecha; devolve o corpo.
func _fold(parent: Control, label: String) -> VBoxContainer:
	var toggle := _button(parent, "▸ " + label, Callable())
	toggle.toggle_mode = true
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.clip_text = true
	toggle.tooltip_text = label
	var body := _column(parent)
	body.hide()
	toggle.toggled.connect(func(open: bool) -> void:
		body.visible = open
		toggle.text = ("▾ " if open else "▸ ") + label)
	return body


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
