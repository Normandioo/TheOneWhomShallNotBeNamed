extends RefCounted
## Recursos na tela: liga o painel ao Registry. A área de uma ocorrência é pintada como os países (TerritoryEditor), numa camada por
## recurso, e o mapa mostra a do recurso escolhido; os pontos têm uma camada de rótulos. Toda gravação vira um comando na pilha de
## desfazer; a pilha avisa quando muda (inclusive ao desfazer) e o painel e o globo são relidos. Main roteia o clique no globo (click).

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const ResourcePanel = preload("res://scripts/ui/resource_panel.gd")
const TerritoryEditor = preload("res://scripts/app/territory_editor.gd")


## Dois comandos que são um só para o autor (apagar a pintura e o registro de uma área).
class Both:
	var first: Object
	var second: Object
	var Bytes: int

	func _init(a: Object, b: Object) -> void:
		first = a
		second = b
		Bytes = a.Bytes + b.Bytes

	func Undo() -> void:
		second.Undo()
		first.Undo()

	func Redo() -> void:
		first.Redo()
		second.Redo()


var hub
var panel: ResourcePanel
var layer                       # PlaceLayer dos pontos e dos nomes das áreas
var commands                    # CommandStack
var territories: TerritoryEditor
var navigate := Callable()      # sai do pincel ou da pintura antes de esperar um clique
var focus_map := Callable()     # func(direção, zoom)
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
	territories.resource_owner_picked.connect(func(id: int) -> void:
		occurrence_id = id
		refresh())
	panel.query_changed.connect(refresh)
	panel.type_chosen.connect(func(id: int) -> void:
		_leave_painting()
		cancel_click()
		type_id = id
		occurrence_id = 0
		_show_map()
		refresh())
	panel.occurrence_chosen.connect(func(id: int) -> void:
		_leave_painting()
		cancel_click()
		occurrence_id = id
		refresh())
	panel.create_requested.connect(create_type)
	panel.type_saved.connect(func(n: String, description: String, category: String, unit: String, color: Color) -> void:
		_apply("editar recurso", hub.registry.SetResourceType(type_id, n, description, category, unit, color.to_rgba32() >> 8),
			"O recurso precisa de um nome."))
	panel.type_delete_requested.connect(func() -> void:
		_leave_painting()
		_apply("excluir recurso", hub.registry.DeleteResourceType(type_id), "Exclua antes as ocorrências deste recurso.")
		_show_map())
	panel.area_requested.connect(new_area)
	panel.paint_requested.connect(paint)
	panel.point_requested.connect(func() -> void: _wait("place", "Clique no globo para colocar o ponto (Esc cancela)."))
	panel.move_requested.connect(func() -> void: _wait("move", "Clique no novo lugar do ponto (Esc cancela)."))
	panel.cancel_requested.connect(cancel_click)
	panel.occurrence_saved.connect(func(n: String, note: String) -> void:
		_apply("editar ocorrência", hub.registry.SetOccurrenceText(occurrence_id, n, note)))
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
		_leave_painting()
		cancel_click()
	panel.visible = open
	_show_map()
	refresh()


func create_type(type_name: String) -> void:
	_leave_painting()
	var cmd = hub.registry.CreateResourceType(type_name)
	if cmd != null:
		type_id = cmd.Id
		occurrence_id = 0
		panel.new_name.text = ""
		panel.query.text = ""
	_apply("criar recurso", cmd, "Dê um nome ao recurso.")
	_show_map()


## Uma área nova do recurso escolhido, já no modo pintar.
func new_area() -> void:
	if type_id == 0:
		return
	_leave_painting()
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
	_show_map()
	territories.start_resource(_level(), occurrence_id)


## Excluir leva junto a pintura da área, num comando só.
func delete_occurrence() -> void:
	var o := _occurrence()
	if o.is_empty():
		return
	_leave_painting()
	cancel_click()
	var painted = null
	if o.kind == "area":
		var map = territories.layer(_level())
		painted = map.ClearOwner(occurrence_id) if map != null else null
	var removed = hub.registry.DeleteOccurrence(occurrence_id)
	if removed != null and painted != null:
		removed = Both.new(painted, removed)
	elif removed == null and painted != null:
		painted.Undo()
	_apply("excluir ocorrência", removed)


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
func click(n: Vector3, tolerance_km: float) -> bool:
	if not hub.usable or not panel.visible or type_id == 0 or n == Vector3.ZERO:
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
	elif territories.territory_level == _level():
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
		panel.show_types(hub.registry.ResourceTypes(panel.query.text), type_id)
		panel.show_type(current)
		panel.show_occurrences(mine, occurrence_id)
		panel.show_occurrence(_occurrence())
		shown = mine
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
		var color := ResourcePanel._color(o.rgb)
		items.append({"place_id": o.id, "lat": at.x, "lon": at.y, "radius_km": 0.0,
			"color": Color.WHITE if int(o.id) == occurrence_id else color, "label": ("◆ " if o.kind == "ponto" else "") + title})
	var key: int = items.hash()
	if key != _key:
		_key = key
		layer.show_items(items)


## Põe em cada área o tamanho pintado e acha os centros (a varredura do mapa só se repete quando a camada muda).
func _measure(mine: Array) -> void:
	_centers = _centers if _centers_key != "" else {}
	var has_area := mine.any(func(o): return o.kind == "area")
	var map = territories.layer(_level()) if has_area else null
	if map == null:
		_centers = {}
		_centers_key = ""
	else:
		var key := "%s:%d" % [_level(), map.Version]
		if key != _centers_key and not territories.territory_stroking:
			_centers_key = key
			_centers = map.Centroids()
	for o in mine:
		o["area_km2"] = map.AreaKm2(int(o.id)) if map != null and o.kind == "area" else 0.0


## O mapa mostra a camada do recurso escolhido enquanto o painel está aberto; depois volta ao que estava.
func _show_map() -> void:
	var current: String = territories.territory_level
	if territories.painting_territory or territories.drafting:
		return
	if panel.visible and type_id != 0:
		if not TerritoryEditor.is_resource(current):
			_back_level = current
		territories.show_level(_level())
	elif TerritoryEditor.is_resource(current):
		territories.show_level(_back_level)


## Sai da pintura de uma área (a de um país, em andamento, não é assunto dos recursos).
func _leave_painting() -> void:
	if territories.painting_territory and TerritoryEditor.is_resource(territories.territory_level):
		territories.stop_painting()


func _level() -> String:
	return TerritoryEditor.RESOURCE + str(type_id)


func _occurrence() -> Dictionary:
	if occurrence_id != 0 and type_id != 0:
		for o in hub.registry.Occurrences(type_id):
			if int(o.id) == occurrence_id:
				return o
	return {}


func _wait(what: String, text: String) -> void:
	if type_id == 0:
		return
	if navigate.is_valid():
		navigate.call()
	_show_map()
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
