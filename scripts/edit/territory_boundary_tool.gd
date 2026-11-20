extends RefCounted
## Desenha uma nova divisão para o país selecionado e a aplica ao soltar o mouse.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const SPACING_PX := 7.0
const MAX_POINTS := 256

var dragging: bool:
	get:
		return _capturing or _handle >= 0

var _map
var _territory
var _registry
var _panel
var _commands
var _owner := 0
var _id := 0
var _paths: Array = []
var _saved := PackedVector3Array()
var _points := PackedVector3Array()
var _capturing := false
var _outside := false
var _handle := -1
var _inserting := false
var _last_screen := Vector2.ZERO
var _tail := Vector3.ZERO
var _altitude_km := 1000.0


func setup(territory, registry, map, panel, commands) -> void:
	_territory = territory
	_registry = registry
	_map = map
	_panel = panel
	_commands = commands
	panel.boundary_selected.connect(select_path)
	panel.boundary_reset_requested.connect(_reset_path)
	commands.changed.connect(_on_history_changed)


func start(owner: int) -> void:
	_owner = owner
	_paths = _territory.BoundariesFor(owner)
	select_path(0)


func stop() -> void:
	if _owner == 0:
		return
	_owner = 0
	_capturing = false
	_handle = -1
	_inserting = false
	if _map != null:
		_map.show_territory_path(PackedVector3Array(), PackedVector3Array(), true, _altitude_km)


func select_path(id: int) -> void:
	_id = id
	_saved = PackedVector3Array()
	for path in _paths:
		if path.id == id:
			_saved = path.points
			break
	_points = _saved.duplicate()
	_capturing = false
	_handle = -1
	_inserting = false
	_refresh_menus()
	_refresh()


func press(dir: Vector3, screen: Vector2, altitude_km: float) -> void:
	if dir == Vector3.ZERO or dragging:
		return
	_altitude_km = altitude_km
	if _id == 0 or _points.is_empty():
		_capturing = true
		_outside = false
		_points.clear()
		_points.append(dir)
		_last_screen = screen
		_tail = dir
		_refresh()
		return
	var pick_angle := maxf(altitude_km * 0.014, 0.15) / EvronGeo.RADIUS_KM
	var distance := pick_angle * 0.55
	for i in _points.size():
		var angle := dir.angle_to(_points[i])
		if angle < distance:
			_handle = i
			distance = angle
	if _handle >= 0 or _points.size() >= MAX_POINTS:
		return
	distance = pick_angle
	for i in _points.size() - 1:
		var closest := Geometry3D.get_closest_point_to_segment(dir, _points[i], _points[i + 1]).normalized()
		var angle := dir.angle_to(closest)
		if angle < distance:
			_handle = i + 1
			_inserting = true
			distance = angle


func drag(dir: Vector3, screen: Vector2) -> void:
	if dir == Vector3.ZERO:
		if _capturing:
			_outside = true
		return
	if _capturing:
		if _outside:
			return
		_tail = dir
		if screen.distance_to(_last_screen) < SPACING_PX or dir.is_equal_approx(_points[-1]):
			return
		if _points.size() == MAX_POINTS:
			# Mantém o traço inteiro ao espaçar mais as amostras de um gesto muito longo.
			var reduced := PackedVector3Array()
			for i in range(0, _points.size() - 1, 2):
				reduced.append(_points[i])
			reduced.append(_points[-1])
			_points = reduced
		_points.append(dir)
		_last_screen = screen
		_refresh()
	elif _handle >= 0 and not dir.is_equal_approx(_points[_handle]):
		var next := _handle if _inserting else _handle + 1
		if (_handle > 0 and dir.is_equal_approx(_points[_handle - 1])) or \
				(next < _points.size() and dir.is_equal_approx(_points[next])):
			return
		if _inserting:
			_points.insert(_handle, dir)
			_inserting = false
		else:
			_points.set(_handle, dir)
		_refresh()


func release() -> void:
	if not dragging:
		return
	if _capturing:
		if not _tail.is_equal_approx(_points[-1]) and _points.size() < MAX_POINTS:
			_points.append(_tail)
		if _points.size() < 2:
			_points.clear()
	_capturing = false
	_handle = -1
	_inserting = false
	if _points.size() >= 2 and _points != _saved:
		_apply_stroke()
	else:
		_refresh()


func cancel() -> void:
	if dragging:
		select_path(_id)


func update_zoom(altitude_km: float) -> void:
	if _owner == 0 or absf(altitude_km - _altitude_km) < _altitude_km * 0.15:
		return
	_altitude_km = altitude_km
	_show_path()


func _apply_stroke() -> void:
	var result: Dictionary = _territory.PlanBoundaryClaim(_owner, _points, _id)
	var plan = result.get("plan")
	if plan == null:
		_points = _saved.duplicate()
		_refresh(result.message)
		return
	var neighbor: String = _registry.Name(plan.SourceOwner)
	if neighbor.is_empty() or _registry.Kind(plan.SourceOwner) != "pais":
		_points = _saved.duplicate()
		_refresh("O território cortado precisa pertencer a um país cadastrado.")
		return
	var edit = _territory.ApplyBoundary(plan)
	if edit == null:
		_points = _saved.duplicate()
		_refresh("O mapa mudou durante o traço. Desenhe novamente.")
		return
	_commands.push("Redesenhar fronteira", edit)
	_refresh("Fronteira com %s atualizada." % neighbor)


func _reset_path() -> void:
	_capturing = false
	_handle = -1
	_inserting = false
	_points.clear()
	_refresh()


func _on_history_changed() -> void:
	if _owner == 0:
		return
	var paths: Array = _territory.BoundariesFor(_owner)
	if paths != _paths:
		_paths = paths
		for path in _paths:
			if path.id == _id:
				select_path(_id)
				return
		select_path(0)


func _refresh_menus() -> void:
	var neighbors := {}
	for path in _paths:
		if not neighbors.has(path.source):
			neighbors[path.source] = _registry.Name(path.source)
	_panel.show_boundary_options(_paths, neighbors, _id)


func _show_path() -> void:
	if _map != null:
		var controls := PackedVector3Array() if dragging else _points
		var draft := _id == 0 or _points != _saved
		_map.show_territory_path(_territory.SmoothBoundary(_points), controls, draft, _altitude_km)


func _refresh(message := "") -> void:
	if message.is_empty():
		if dragging:
			message = "Solte o mouse para aplicar o traço."
		elif _points.size() < 2:
			message = "Trace de uma borda à outra dentro do país vizinho. Ao soltar, seu país ganha o pedaço separado."
		else:
			message = "Arraste a linha ou os pontos para ajustar o traço."
	_panel.show_boundary_state(message)
	_show_path()
