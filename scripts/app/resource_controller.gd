extends RefCounted
## Recursos na tela: liga o painel ao Registry. A área de uma ocorrência é pintada como os países (TerritoryEditor), numa camada por
## recurso, e o mapa mostra a do recurso escolhido; os pontos têm uma camada de rótulos. Toda gravação vira um comando na pilha de
## desfazer; a pilha avisa quando muda (inclusive ao desfazer) e o painel e o globo são relidos. Main roteia o clique no globo (click).

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const ResourcePanel = preload("res://scripts/ui/resource_panel.gd")
const TerritoryEditor = preload("res://scripts/app/territory_editor.gd")
const Calendar = preload("res://scripts/world/calendar.gd")


const Batch = preload("res://scripts/edit/command_stack.gd").Batch  # vários comandos que são um só para o autor
const ResourcePlanScript = preload("res://scripts/world/ResourcePlan.cs")
const TerritoryScript = preload("res://scripts/world/Territory.cs")

signal rec_changed(on: bool)    # o modo de mapa Rec ligou ou desligou (a barra de modos e a legenda acompanham)
signal rec_drawn                # o Rec foi redesenhado: a legenda relê rec_entries e rec_hidden

var rec := false                # o modo de mapa Rec: todos os recursos juntos, cada um na sua cor
var rec_hidden := {}            # tipo -> true: desligado na legenda do Rec
var rec_entries: Array = []     # o que a legenda mostra: [{id, name, rgb, category, count}]
var _rec_layers: Array = []     # [tipo, camada] das áreas desenhadas no Rec, na ordem das cores
var _drawing_rec := false
var hub
var panel: ResourcePanel
var layer                       # PlaceLayer dos pontos e dos nomes das áreas
var commands                    # CommandStack
var territories: TerritoryEditor
var generator                   # o generator_controller (prévia e aplicar), se ligado
var navigate := Callable()      # sai do pincel ou da pintura antes de esperar um clique
var focus_map := Callable()     # func(direção, zoom)
var clock                       # WorldClock: o estoque de um bem fabricado é o da data na tela
var type_id := 0
var occurrence_id := 0
var _waiting := ""              # "" | "place" | "move": o que o próximo clique no globo faz
var _back_level := "pais"       # o mapa que volta quando o recurso sai da tela
var _centers_key := ""
var _centers := {}              # área -> [direção, km², raio equivalente]
var _key := 0


func setup(domain_hub, resource_panel, place_layer, command_stack, territory_editor) -> void:
	hub = domain_hub
	panel = resource_panel
	layer = place_layer
	commands = command_stack
	territories = territory_editor
	if not hub.usable:
		return
	commands.changed.connect(refresh)
	# Outro mapa na tela (outro nível, ou a prévia de uma geração) encerra o Rec.
	territories.territory_level_shown.connect(func(_level: String, _layer) -> void:
		if rec:
			set_rec(false))
	territories.preview_image.connect(func(img) -> void:
		if rec and not _drawing_rec and img != null:
			rec = false
			rec_changed.emit(false))
	territories.resource_owner_picked.connect(func(id: int) -> void:
		occurrence_id = id
		_fix_edited()
		refresh())
	panel.fixed_toggled.connect(func(on: bool) -> void:
		_apply("fixar ocorrência" if on else "liberar ocorrência", hub.registry.SetFixed(occurrence_id, on)))
	panel.query_changed.connect(refresh)
	panel.type_chosen.connect(func(id: int) -> void:
		leave_painting()
		cancel_click()
		type_id = id
		occurrence_id = 0
		show_map()
		refresh())
	panel.occurrence_chosen.connect(func(id: int) -> void:
		leave_painting()
		cancel_click()
		occurrence_id = id
		refresh())
	panel.create_requested.connect(create_type)
	panel.lookup = func(text: String) -> Array:
		var found = hub.registry.Search(text, "", "", 0, hub.shown_t)
		return found if found != null else []
	panel.details_saved.connect(_save_details)
	panel.knowledge_added.connect(func(entity: int, from_year: String, to_year: String, estimate: String, note: String) -> void:
		var period := _period(from_year, to_year)
		var value: float = hub.parse_number(estimate) if estimate.strip_edges() != "" else NAN
		if period.is_empty() or (estimate.strip_edges() != "" and (is_nan(value) or value < 0.0)):
			panel.show_message("Confira os anos (o primeiro antes do segundo) e a estimativa (um número, zero ou mais).")
			return
		hub.registry.AddKnowledge(occurrence_id, entity, period.from, period.to, value, note)
		refresh())
	panel.knowledge_removed.connect(func(id: int) -> void:
		hub.registry.DeleteKnowledge(id)
		refresh())
	panel.right_added.connect(func(entity: int, kind: String, from_year: String, to_year: String, note: String) -> void:
		var period := _period(from_year, to_year)
		if period.is_empty():
			panel.show_message("Confira os anos: o primeiro tem de vir antes do segundo.")
			return
		hub.registry.AddRight(occurrence_id, entity, kind, period.from, period.to, note)
		refresh())
	panel.right_removed.connect(func(id: int) -> void:
		hub.registry.DeleteRight(id)
		refresh())
	panel.back_requested.connect(func() -> void:
		leave_painting()
		cancel_click()
		if generator != null:
			generator.close()
		type_id = 0
		occurrence_id = 0
		show_map()
		refresh())
	panel.type_saved.connect(func(n: String, description: String, category: String, unit: String, color: Color) -> void:
		_apply("editar recurso", hub.registry.SetResourceType(type_id, n, description, category, unit, color.to_rgba32() >> 8),
			"O recurso precisa de um nome."))
	panel.type_delete_requested.connect(func() -> void:
		leave_painting()
		_apply("excluir recurso", hub.registry.DeleteResourceType(type_id), "Exclua antes as ocorrências deste recurso.")
		show_map())
	panel.area_requested.connect(new_area)
	panel.paint_requested.connect(paint)
	panel.point_requested.connect(func() -> void: _wait("place", "Clique no globo para colocar o ponto (Esc cancela)."))
	panel.move_requested.connect(func() -> void: _wait("move", "Clique no novo lugar do ponto (Esc cancela)."))
	panel.cancel_requested.connect(cancel_click)
	panel.occurrence_saved.connect(func(n: String, note: String) -> void:
		_apply("editar ocorrência", hub.registry.SetOccurrenceText(occurrence_id, n, note)))
	panel.reserve_saved.connect(func(text: String) -> void:
		var value: float = hub.parse_number(text) if text.strip_edges() != "" else NAN
		if text.strip_edges() != "" and (is_nan(value) or value < 0.0):
			panel.show_message("A quantidade é um número, zero ou mais (vazio = desconhecida).")
			return
		_apply("definir quantidade", hub.registry.SetOccurrenceReserve(occurrence_id, value)))
	panel.duplicate_requested.connect(func() -> void:
		var cmd = hub.registry.DuplicatePoint(occurrence_id)
		if cmd != null:
			occurrence_id = cmd.Id
		_apply("duplicar ponto", cmd))
	panel.delete_requested.connect(delete_occurrence)
	panel.focus_requested.connect(focus)
	panel.closed.connect(func() -> void: set_open(false))


func set_open(open: bool) -> void:
	if not hub.usable or panel.visible == open:
		return
	if open and navigate.is_valid():
		navigate.call()
	if not open:
		leave_painting()
		cancel_click()
		if generator != null:
			generator.close()
	panel.visible = open
	show_map()
	refresh()


func create_type(type_name: String, category := "") -> void:
	leave_painting()
	var made := create_good(type_name, category, panel.chosen_unit())
	if made == 0:
		_apply("criar recurso", null, "Dê um nome ao recurso.")
		return
	type_id = made
	occurrence_id = 0
	panel.new_name.text = ""
	panel.query.text = ""
	panel.new_toggle.button_pressed = false
	show_map()
	refresh()  # o push dentro de create_good redesenhou antes de o recurso novo virar o escolhido


## Cria o tipo já na categoria e na unidade, num desfazer só, sem mexer na tela (a receita também cria bens por aqui). 0 = recusado.
func create_good(type_name: String, category := "manufatura", unit := "") -> int:
	var cmd = hub.registry.CreateResourceType(type_name)
	if cmd == null:
		return 0
	var steps: Array = [cmd]
	if category != "" or unit != "":
		var t: Dictionary = hub.registry.ResourceTypes("").filter(func(x): return int(x.id) == cmd.Id)[0]
		var categorized = hub.registry.SetResourceType(cmd.Id, t.name, "", category, unit, int(t.rgb))
		if categorized != null:
			steps.append(categorized)
	push_batch("criar recurso", steps)
	return cmd.Id


## Uma área nova do recurso escolhido, já no modo pintar.
func new_area() -> void:
	if type_id == 0:
		return
	leave_painting()
	cancel_click()
	var cmd = hub.registry.AddArea(type_id)
	if cmd != null:
		occurrence_id = cmd.Id
	_apply("criar área de recurso", cmd)
	if cmd != null:
		paint()


## Pinta (ou continua pintando) a área escolhida.
func paint() -> void:
	var o := _occurrence()
	if o.is_empty() or o.kind != "area":
		return
	cancel_click()
	if navigate.is_valid():
		navigate.call()
	show_map()
	_fix_edited()
	territories.start_resource(level(), occurrence_id)


## Excluir leva junto a pintura da área, num comando só.
func delete_occurrence() -> void:
	var o := _occurrence()
	if o.is_empty():
		return
	leave_painting()
	cancel_click()
	var painted = null
	if o.kind == "area":
		var map = territories.layer(level())
		painted = map.ClearOwner(occurrence_id) if map != null else null
	var suppressed = hub.registry.SuppressOccurrence(occurrence_id) if o.origin == "gerada" else null  # não volta na próxima geração
	var removed = hub.registry.DeleteOccurrence(occurrence_id)
	if removed == null:
		if suppressed != null:
			suppressed.Undo()
		if painted != null:
			painted.Undo()
		_apply("excluir ocorrência", null)
		return
	var steps: Array = []
	if suppressed != null:
		steps.append(suppressed)
	if painted != null:
		steps.append(painted)
	steps.append(removed)
	push_batch("excluir ocorrência", steps)


func focus() -> void:
	var o := _occurrence()
	if o.is_empty() or not focus_map.is_valid():
		return
	if o.kind == "ponto":
		focus_map.call(EvronGeo.dir(o.lat, o.lon), 1.0 + 2.5 * 150.0 / EvronGeo.RADIUS_KM)
	elif _centers.has(occurrence_id):
		var c: Array = _centers[occurrence_id]
		focus_map.call(c[0], 1.0 + 2.5 * maxf(sqrt(c[1] / PI), 150.0) / EvronGeo.RADIUS_KM)
	else:
		panel.show_message("Essa área ainda não foi pintada.")


func cancel_click() -> void:
	if _waiting != "":
		_waiting = ""
		panel.waiting = false
		panel.show_message("")


## Um clique no globo em n. true = era dos recursos (colocar, mover ou escolher o que está na tela).
## Liga ou desliga o modo de mapa Rec. Ligado, a camada política mostra as áreas de todos os recursos visíveis (uma cor por recurso) e
## os pontos deles aparecem no globo; um clique num deles abre o recurso no painel.
func set_rec(on: bool) -> void:
	if hub == null or not hub.usable or rec == on:
		return
	rec = on
	if on:
		_draw_rec()
	else:
		_rec_layers = []
		territories.end_preview()
	rec_changed.emit(on)
	refresh()


## Mostra ou esconde um recurso no Rec (a legenda).
func set_rec_visible(id: int, shown: bool) -> void:
	if shown:
		rec_hidden.erase(id)
	else:
		rec_hidden[id] = true
	if rec:
		_draw_rec()
		refresh()


func _draw_rec() -> void:
	var occurrences: Array = hub.registry.Occurrences(0)
	var areas := {}
	for o in occurrences:
		if o.kind == "area":
			areas[int(o.type_id)] = true
	rec_entries = []
	_rec_layers = []
	var layers: Array[TerritoryScript] = []
	var colors: Array = []
	var plan = ResourcePlanScript.new()  # os métodos dele são estáticos, mas o GDScript os chama por uma instância
	for t in hub.registry.ResourceTypes(""):
		if int(t.count) == 0:
			continue  # fora do mapa (os fabricados ficam nos povoados)
		rec_entries.append(t)
		if rec_hidden.has(int(t.id)) or not areas.has(int(t.id)):
			continue
		# shortcut: cada camada aberta fica na memória (ver TerritoryEditor.layer); com muitos recursos em área, pesa.
		var area_layer = territories.layer(TerritoryEditor.RESOURCE + str(t.id))
		if area_layer == null:
			continue
		var owner: int = plan.LayerOwner(layers.size())
		layers.append(area_layer)
		_rec_layers.append([int(t.id), area_layer])
		colors.append({"id": owner, "rgb": int(t.rgb), "top": owner})
	_drawing_rec = true
	territories.show_preview(plan.LayersImage(territories.territory.Size, layers), colors)
	_drawing_rec = false
	rec_drawn.emit()


## O clique no Rec: um ponto perto ou a área sob o clique abre o recurso (e o lugar) no painel. true = era de um recurso.
func _rec_click(n: Vector3, tolerance_km: float) -> bool:
	var ll := EvronGeo.lat_lon(n)
	var picked_type := 0
	var picked := 0
	for t in rec_entries:
		if rec_hidden.has(int(t.id)):
			continue
		var hits: PackedInt64Array = hub.registry.PointsAt(int(t.id), ll.x, ll.y, tolerance_km)
		if not hits.is_empty():
			picked_type = int(t.id)
			picked = hits[0]
			break
	if picked == 0:
		for pair in _rec_layers:
			var owner: int = pair[1].OwnerAt(n)
			if owner != 0:
				picked_type = pair[0]
				picked = owner
	if picked == 0:
		return false
	set_rec(false)
	set_open(true)
	type_id = picked_type
	occurrence_id = picked
	show_map()
	refresh()
	return true


func click(n: Vector3, tolerance_km: float) -> bool:
	if rec and hub.usable and n != Vector3.ZERO and (not panel.visible or type_id == 0):
		return _rec_click(n, tolerance_km)
	if not hub.usable or not panel.visible or n == Vector3.ZERO:
		return false
	if generator != null and generator.active():
		generator.click(n, tolerance_km)
		return true  # na prévia o clique é só das sugestões
	if type_id == 0:
		return false
	var ll := EvronGeo.lat_lon(n)
	if _waiting == "place":
		cancel_click()
		var cmd = hub.registry.AddPoint(type_id, ll.x, ll.y)
		if cmd != null:
			occurrence_id = cmd.Id
		_apply("colocar ponto", cmd)
		return true
	if _waiting == "move":
		cancel_click()
		_apply("mover ponto", hub.registry.MovePoint(occurrence_id, ll.x, ll.y))
		return true
	var hits: PackedInt64Array = hub.registry.PointsAt(type_id, ll.x, ll.y, tolerance_km)
	var picked := 0
	if not hits.is_empty():
		# Cliques repetidos no mesmo lugar passam por todos os pontos que se sobrepõem.
		picked = hits[(hits.find(occurrence_id) + 1) % hits.size()]
	elif territories.territory_level == level():
		var owner: int = territories.territory.OwnerAt(n)
		if owner != 0 and hub.registry.OccurrenceType(owner) == type_id:
			picked = owner
	if picked == 0:
		return false
	occurrence_id = picked
	refresh()
	return true


## Relê o catálogo (o que desfazer também muda) e redesenha o globo se os pontos ou os nomes das áreas mudaram.
func refresh() -> void:
	if hub == null or not hub.usable:
		return
	var shown: Array = []
	if panel.visible:
		var current := {}
		for t in hub.registry.ResourceTypes(""):
			if int(t.id) == type_id:
				current = t
		if current.is_empty():
			type_id = 0
		var mine: Array = hub.registry.Occurrences(type_id) if type_id != 0 else []
		if mine.filter(func(o): return int(o.id) == occurrence_id).is_empty():
			occurrence_id = 0
		_measure(mine)
		var rows: Array = hub.registry.ResourceTypes(panel.query.text)
		var recipes := {}  # bem -> quantas receitas o fazem: o estado de um fabricado na lista (só a lista mostra)
		for r in hub.registry.Recipes() if type_id == 0 else []:
			recipes[int(r.output_id)] = recipes.get(int(r.output_id), 0) + 1
		for t in rows:
			t["recipes"] = recipes.get(int(t.id), 0)
		panel.show_types(rows, type_id)
		panel.show_type(current)
		panel.show_occurrences(mine, occurrence_id)
		panel.show_occurrence(_occurrence())
		if panel._made:
			var t: int = clock.shown() if clock != null else 9223372036854775807
			panel.show_made(hub.registry.Recipes().filter(func(r): return int(r.output_id) == type_id).map(func(r): return String(r.name)),
				hub.registry.GoodMakers(type_id, t), current.unit)
		shown = mine
		if generator != null:
			generator.show_type(type_id)
			if generator.active():  # na prévia, as geradas que vão sair somem
				shown = mine.filter(func(o): return o.origin != "gerada" or o.fixed)
	var rec_view: bool = rec and (not panel.visible or type_id == 0)
	var units := {}
	if rec_view:
		_draw_rec()  # desfazer e refazer também mudam as áreas
		shown = hub.registry.Occurrences(0).filter(func(o): return o.kind == "ponto" and not rec_hidden.has(int(o.type_id)))
		for t in rec_entries:
			units[int(t.id)] = String(t.unit)
	if TerritoryEditor.is_resource(territories.territory_level):
		# Desfazer a criação da área que está sendo pintada encerra a pintura.
		if territories.painting_territory and hub.registry.OccurrenceType(territories.territory_owner) == 0:
			territories.stop_painting()
		territories.refresh_palette()
	var items: Array = []
	for o in shown:
		var at: Vector2
		if o.kind == "ponto":
			at = Vector2(o.lat, o.lon)
		elif _centers.has(int(o.id)):
			at = EvronGeo.lat_lon(_centers[int(o.id)][0])
		else:
			continue
		var title: String = o.type if o.name == "" else "%s · %s" % [o.name, o.type]
		if rec_view:  # no Rec, a quantidade vai junto do nome (sem ela, ninguém extrai)
			var reserve := float(o.get("reserve", NAN))
			title += " · " + ("sem quantidade" if is_nan(reserve) else ResourcePanel._plain(reserve) + (" " + units.get(int(o.type_id), "") if units.get(int(o.type_id), "") != "" else ""))
		var color := ResourcePanel._color(o.rgb)
		items.append({"place_id": o.id, "lat": at.x, "lon": at.y, "radius_km": 0.0,
			"color": Color.WHITE if int(o.id) == occurrence_id else color, "label": ("◆ " if o.kind == "ponto" else "") + title})
	if panel.visible and generator != null:
		if generator.review.active():
			items = []  # na avaliação às cegas, o que já existe revelaria quais lugares vêm da regra
		items.append_array(generator.labels())
	var key: int = items.hash()
	if key != _key:
		_key = key
		layer.show_items(items)


## Põe em cada área o tamanho pintado e acha os centros (a varredura do mapa só se repete quando a camada muda).
func _measure(mine: Array) -> void:
	_centers = _centers if _centers_key != "" else {}
	var has_area := mine.any(func(o): return o.kind == "area")
	var map = territories.layer(level()) if has_area else null
	if map == null:
		_centers = {}
		_centers_key = ""
	else:
		var key := "%s:%d" % [level(), map.Version]
		if key != _centers_key and not territories.territory_stroking:
			_centers_key = key
			_centers = map.Centroids()
	for o in mine:
		o["area_km2"] = map.AreaKm2(int(o.id)) if map != null and o.kind == "area" else 0.0


## O mapa mostra a camada do recurso escolhido enquanto o painel está aberto; depois volta ao que estava.
func show_map() -> void:
	var current: String = territories.territory_level
	if territories.painting_territory or territories.drafting:
		return
	if panel.visible and type_id != 0:
		if not TerritoryEditor.is_resource(current):
			_back_level = current
		territories.show_level(level())
	elif TerritoryEditor.is_resource(current):
		territories.show_level(_back_level)


## Sai da pintura de uma área (a de um país, em andamento, não é assunto dos recursos).
func leave_painting() -> void:
	if territories.painting_territory and TerritoryEditor.is_resource(territories.territory_level):
		territories.stop_painting()


func level() -> String:
	return TerritoryEditor.RESOURCE + str(type_id)


func _save_details(d: Dictionary) -> void:
	var numbers := {}
	for key in ["grade", "depth", "renewal"]:
		numbers[key] = hub.parse_number(d[key]) if String(d[key]).strip_edges() != "" else NAN
		if String(d[key]).strip_edges() != "" and (is_nan(numbers[key]) or numbers[key] < 0.0):
			panel.show_message("Teor, profundidade e renovação são números, zero ou mais (vazio = não informado).")
			return
	var period := _period(d.from, d.to)
	if period.is_empty():
		panel.show_message("Confira os anos: o primeiro tem de vir antes do segundo.")
		return
	_apply("detalhes da ocorrência", hub.registry.SetOccurrenceDetails(occurrence_id, numbers.grade, numbers.depth, d.access, numbers.renewal,
		d.policy, period.from, period.to), "O teor vai de 0 a 100%.")


## Anos de texto -> {from, to} em segundos (vazio = sempre); {} se não vale.
func _period(from_year: String, to_year: String) -> Dictionary:
	var out := {"from": hub.ALWAYS, "to": hub.FOREVER}
	for pair in [["from", from_year], ["to", to_year]]:
		var text := String(pair[1]).strip_edges()
		if text == "":
			continue
		if not text.is_valid_int():
			return {}
		out[pair[0]] = Calendar.to_seconds(int(text), 1, 1)
	return out if out.from < out.to else {}


static func _year_text(t: int) -> String:
	if t == -9223372036854775807 - 1 or t == 9223372036854775807:
		return ""
	return str(Calendar.from_seconds(t).year)


func _with_period(row: Dictionary) -> Dictionary:
	var from := _year_text(row.from)
	var to := _year_text(row.to)
	row["period"] = "sempre" if from == "" and to == "" else ("desde o ano %s" % from if to == "" else ("até o ano %s" % to if from == "" else "anos %s a %s" % [from, to]))
	return row


## Comandos já aplicados que valem um desfazer só.
func push_batch(action: String, steps: Array) -> void:
	panel.show_message("")
	commands.push(action, Batch.new(steps))


## Pintar uma sugestão gerada a torna decisão do autor: fica fixada.
func _fix_edited() -> void:
	var o := _occurrence()
	if not o.is_empty() and o.origin == "gerada" and not o.fixed:
		_apply("fixar sugestão editada", hub.registry.SetFixed(occurrence_id, true))


func _occurrence() -> Dictionary:
	if occurrence_id != 0 and type_id != 0:
		for o in hub.registry.Occurrences(type_id):
			if int(o.id) == occurrence_id:
				o["reserve_info"] = hub.registry.OccurrenceReserve(occurrence_id)
				o["details"] = hub.registry.OccurrenceDetails(occurrence_id)
				o["from_year"] = _year_text(o.details.valid_from)
				o["to_year"] = _year_text(o.details.valid_to)
				o["knowledge"] = Array(hub.registry.Knowledge(occurrence_id)).map(func(k): return _with_period(k))
				o["rights"] = Array(hub.registry.Rights(occurrence_id)).map(func(r): return _with_period(r))
				var countries = territories.layer("pais")
				var map = territories.layer(level()) if o.kind == "area" else null
				o["shares"] = hub.registry.OccurrenceShares(occurrence_id, map, countries) if map != null and countries != null else []
				return o
	return {}


func _wait(what: String, text: String) -> void:
	if type_id == 0:
		return
	if navigate.is_valid():
		navigate.call()
	show_map()
	_waiting = what
	panel.waiting = true
	panel.show_message(text)


## cmd == null: o C# recusou (o motivo vai para o log); a tela volta ao que está gravado.
func _apply(action: String, cmd, refusal := "Não deu para fazer isso (veja o log).") -> void:
	if cmd == null:
		panel.show_message(refusal)
		refresh()
		return
	panel.show_message("")
	commands.push(action, cmd)  # push avisa changed, que chama refresh
