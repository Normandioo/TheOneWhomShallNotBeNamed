extends RefCounted
## A produção na tela e no tempo. É um módulo do relógio (step_seconds e on_step): na virada de cada mês do calendário, processa o mês
## que terminou (Registry.RunMonth). Também liga o painel dos povoados ao Registry. Quem calcula e grava é o Registry.

const Calendar = preload("res://scripts/world/calendar.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const TerritoryEditor = preload("res://scripts/app/territory_editor.gd")

signal month_processed(end: int)

var hub
var panel
var layer                 # PlaceLayer dos povoados
var terrain
var territories           # as camadas pintadas dos recursos (para achar as áreas ao alcance)
var clock
var navigate := Callable()  # sai do pincel ou da pintura antes de esperar um clique
var focus_map := Callable()
var settlement_id := 0
var _return_to_place := false  # a tela de receitas foi aberta de dentro de um povoado
var _waiting := ""        # "" | "create" | "move"
var _new := {}            # o povoado que o próximo clique cria


func setup(domain_hub, settlement_panel, settlement_layer, world_terrain, territory_editor, world_clock) -> void:
	hub = domain_hub
	panel = settlement_panel
	layer = settlement_layer
	terrain = world_terrain
	territories = territory_editor
	clock = world_clock
	if not hub.usable:
		return
	clock.register(self)
	panel.settlement_chosen.connect(func(id: int) -> void:
		cancel_click()
		_return_to_place = false
		settlement_id = id
		panel.show_screen("povoado")
		refresh())
	panel.back_requested.connect(func() -> void:
		cancel_click()
		if _return_to_place and panel.recipes_box.visible and settlement_id != 0:
			_open_place()
			return
		_return_to_place = false
		settlement_id = 0
		panel.show_screen("lista")
		refresh())
	panel.recipes_requested.connect(func() -> void:
		cancel_click()
		_return_to_place = false
		panel.show_screen("receitas")
		refresh())
	panel.new_activity_requested.connect(func() -> void:
		cancel_click()
		_return_to_place = true
		panel.new_recipe()
		panel.show_screen("receitas")
		panel.show_message("Preencha a receita e salve: você volta para o povoado com ela escolhida.")
		refresh())
	panel.create_requested.connect(func(new_name: String, workers: int) -> void:
		if new_name.strip_edges() == "":
			panel.show_message("Dê um nome ao povoado.")
			return
		_new = {"name": new_name, "workers": workers}
		_wait("create", "Clique no globo onde fica o povoado (Esc cancela)."))
	panel.move_requested.connect(func() -> void: _wait("move", "Clique no novo lugar do povoado (Esc cancela)."))
	panel.cancel_requested.connect(cancel_click)
	panel.recipe_saved.connect(_save_recipe)
	panel.recipe_delete_requested.connect(func(id: int) -> void:
		_do(func(): hub.registry.DeleteRecipe(id), "Esta receita está em uso: tire as atividades que a usam antes."))
	panel.activity_added.connect(func(recipe: int, workers: int) -> void:
		_do(func(): return hub.registry.AddActivity(settlement_id, recipe, workers), _free_text()))
	panel.activity_workers_set.connect(func(id: int, workers: int) -> void:
		_do(func(): hub.registry.SetActivityWorkers(id, workers), _free_text()))
	panel.activity_up.connect(func(id: int) -> void: _do(func(): hub.registry.MoveActivityUp(id), ""))
	panel.activity_removed.connect(func(id: int) -> void: _do(func(): hub.registry.DeleteActivity(id), ""))
	panel.stock_changed.connect(func(good: int, qty: float, note: String) -> void:
		_do(func(): hub.registry.Intervene(settlement_id, good, qty, clock.now, note), "O estoque não tem tudo isso para tirar."))
	panel.settlement_saved.connect(func(n: String, workers: int, reach: float) -> void:
		_do(func(): hub.registry.SetSettlement(settlement_id, n, workers, reach), "O povoado precisa de um nome."))
	panel.focus_requested.connect(func() -> void:
		var s := _settlement()
		if not s.is_empty() and focus_map.is_valid():
			focus_map.call(EvronGeo.dir(s.lat, s.lon), 1.0 + 2.5 * 150.0 / EvronGeo.RADIUS_KM))
	panel.delete_requested.connect(func() -> void:
		if _do(func(): hub.registry.DeleteSettlement(settlement_id), "Este povoado já tem histórico de estoque e não pode ser excluído."):
			settlement_id = 0
			panel.show_screen("lista")
			refresh())
	panel.capability_set.connect(func(cap_name: String, proficiency: int) -> void:
		if cap_name.strip_edges() == "":
			panel.show_message("Diga o que o povoado sabe fazer.")
			return
		var cap = hub.registry.CreateCapability(cap_name)
		if cap != null:
			_do(func(): hub.registry.SetSettlementCapability(settlement_id, int(cap), proficiency), ""))
	panel.closed.connect(func() -> void: set_open(false))


func set_open(open: bool) -> void:
	if not hub.usable or panel.visible == open:
		return
	if open and navigate.is_valid():
		navigate.call()
	if not open:
		cancel_click()
	panel.visible = open
	refresh()


# --- o relógio ---------------------------------------------------------------------------------------------------

func step_seconds() -> int:
	return Calendar.DAY


## Na meia-noite do dia 1 de cada mês, o mês que terminou é processado (uma vez só: o Registry lembra os meses feitos).
func on_step(t: int) -> void:
	if not hub.usable:
		return
	var d := Calendar.from_seconds(t)
	if d.day != 1 or d.hour != 0 or d.minute != 0 or d.second != 0:
		return
	var layers := {}
	for good in hub.registry.ExtractedGoods():
		var map = territories.layer(TerritoryEditor.RESOURCE + str(good)) if territories != null else null
		if map != null:
			layers[good] = map
	var done = hub.registry.RunMonth(Calendar.add_months(t, -1), t, terrain, layers)
	if done != null and done.ran:
		month_processed.emit(t)
		refresh()


# --- tela --------------------------------------------------------------------------------------------------------

func refresh() -> void:
	if hub == null or not hub.usable:
		return
	var rows: Array = hub.registry.Settlements()
	if not rows.any(func(s): return int(s.id) == settlement_id) and settlement_id != 0:
		settlement_id = 0
		panel.show_screen("lista")
	if panel.visible:
		var goods: Array = hub.registry.ResourceTypes("").map(func(t): return {"id": int(t.id), "name": t.name, "unit": t.unit})
		panel.show_catalog(goods, hub.registry.Recipes())
		panel.show_settlements(rows, settlement_id)
		var shown: int = clock.shown()
		if settlement_id != 0 and not panel.recipes_box.visible:
			panel.show_place(_settlement(), hub.registry.Activities(settlement_id), hub.registry.StockAt(settlement_id, shown),
				hub.registry.SettlementCapabilities(settlement_id), Calendar.format(shown, false))
		var countries = territories.layer("pais") if territories != null else null
		if countries != null:
			panel.show_totals(hub.registry.StockByCountry(countries, terrain, shown))
	layer.show_items([] if not panel.visible else rows.map(func(s): return {"place_id": int(s.id), "lat": s.lat, "lon": s.lon,
		"radius_km": 0.0, "color": Color.WHITE if int(s.id) == settlement_id else Color(0.95, 0.85, 0.65), "label": "⌂ " + s.name}))


func cancel_click() -> void:
	if _waiting != "":
		_waiting = ""
		panel.waiting = false
		panel.show_message("")


## Um clique no globo em n. true = era dos povoados.
func click(n: Vector3) -> bool:
	if not hub.usable or not panel.visible or _waiting == "" or n == Vector3.ZERO:
		return false
	var ll := EvronGeo.lat_lon(n)
	var what := _waiting
	cancel_click()
	if what == "create":
		var made = hub.registry.CreateSettlement(_new.name, ll.x, ll.y, _new.workers)
		if made == null:
			panel.show_message("Não deu para criar o povoado (veja o log).")
			return true
		settlement_id = int(made)
		panel.new_name.text = ""
		panel.show_screen("povoado")
	else:
		_do(func(): hub.registry.MoveSettlement(settlement_id, ll.x, ll.y), "")
	refresh()
	return true


func _save_recipe(id: int, data: Dictionary) -> void:
	var inputs := PackedFloat64Array()
	for i in data.inputs:
		if is_nan(float(i.qty)):
			panel.show_message("Informe a quantidade de cada insumo.")
			return
		inputs.append_array([i.good_id, i.qty])
	if is_nan(float(data.output_qty)) or is_nan(float(data.labor_days)):
		panel.show_message("Informe quanto a receita produz e quanto trabalho leva (em pessoas-dia).")
		return
	var requirements := PackedFloat64Array()
	for q in data.get("requirements", []):
		if is_nan(float(q.cycles)) or float(q.cycles) <= 0.0:
			panel.show_message("Diga quantas vezes por mês cada instalação ou ferramenta permite fazer a receita.")
			return
		requirements.append_array([q.good_id, q.cycles])
	var groups := PackedFloat64Array()
	for i in data.inputs:
		if int(i.get("group", 0)) != 0:
			groups.append_array([i.good_id, i.group])
	var why := "Confira a receita: nome, quantidades maiores que zero e um insumo que não seja o próprio bem produzido."
	var before := _fingerprint()
	var saved_id := id
	if id == 0:
		var made = hub.registry.CreateRecipe(data.name, data.kind, data.output_id, data.output_qty, data.labor_days, inputs)
		saved_id = int(made) if made != null else 0
	else:
		hub.registry.UpdateRecipe(id, data.name, data.kind, data.output_id, data.output_qty, data.labor_days, inputs)
	if saved_id == 0:  # o formulário fica como está, para corrigir
		panel.show_message(why)
		return
	if id != 0 and before == _fingerprint() and data.get("capability", "") == "" and requirements.is_empty() and groups.is_empty():
		panel.show_message("")
		refresh()
		return
	var cap := 0
	if String(data.get("capability", "")) != "":
		var made_cap = hub.registry.CreateCapability(data.capability)
		cap = int(made_cap) if made_cap != null else 0
	hub.registry.SetRecipeExtras(saved_id, cap, requirements, groups)
	panel.show_message("")
	if id == 0:
		panel.new_recipe()
	if id == 0 and _return_to_place and settlement_id != 0:
		_open_place()
		panel.choose_recipe(saved_id)
		panel.show_message("Atividade \"%s\" criada. Diga quantas pessoas e clique em Adicionar." % String(data.name).strip_edges())
	else:
		refresh()


## Volta da tela de receitas para o povoado aberto.
func _open_place() -> void:
	_return_to_place = false
	panel.show_message("")
	panel.show_screen("povoado")
	refresh()


## Roda uma gravação do Registry. O C# recusa com exceção, que no GDScript vira só um erro no log: o sucesso é o banco ter mudado.
func _do(action: Callable, refusal: String) -> bool:
	var before := _fingerprint()
	action.call()
	var ok := before != _fingerprint()
	panel.show_message("" if ok or refusal == "" else refusal)
	refresh()
	return ok


func _fingerprint() -> String:
	var rows: Array = [hub.registry.Settlements(), hub.registry.Recipes()]
	if settlement_id != 0:
		rows.append_array([hub.registry.Activities(settlement_id), hub.registry.Stock(settlement_id)])
	return var_to_str(rows)


func _free_text() -> String:
	return "Não há trabalhadores livres para isso: diminua outra atividade ou aumente os trabalhadores na aba Editar."


func _settlement() -> Dictionary:
	for s in hub.registry.Settlements():
		if int(s.id) == settlement_id:
			return s
	return {}


func _wait(what: String, text: String) -> void:
	if navigate.is_valid():
		navigate.call()
	_waiting = what
	panel.waiting = true
	panel.show_message(text)
