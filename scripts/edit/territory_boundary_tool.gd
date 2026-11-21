extends RefCounted
## Desenha uma nova divisão para o selecionado, ou um CONTORNO FECHADO (terminar perto de onde começou) que toma a terra sem dono de
## dentro: o mundo começa vazio. Ao soltar o mouse mostra a PRÉVIA (o mapa como ficaria, a área e de quem sai);
## só muda a camada quando o usuário confirma. Se mais de um lado do corte encosta no selecionado, ele escolhe qual.

signal preview_changed(image)  # Image = mostrar o mapa como ficaria; null = voltar ao mapa de verdade

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const SPACING_PX := 7.0
## Modos de fidelidade do traço: [nome, espaçamento das amostras (px de tela), passadas de estabilização]. A estabilização é uma média
## móvel nos pontos de controle (as pontas ficam): o caminho gravado já é o estabilizado, então reabrir e remodelar dá o mesmo resultado.
const FIDELITY := [["Alta fidelidade", 3.0, 0], ["Equilibrado", SPACING_PX, 0], ["Suavizado", 14.0, 3]]
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
var _plan = null  # o plano da prévia (mostrada quando o mouse para durante o traço)
var _moved_ms := 0
var _preview_points := PackedVector3Array()
var _last_side := {}  # o último corte aplicado com mais de um lado possível (para "Outro lado")
const PAUSE_MS := 350  # parado com o botão apertado por isto = mostra a prévia
var below: Array = []   # as camadas de cima que a tela mostra por baixo (a prévia é composta sobre elas)
var land_only := true   # o contorno fechado toma só terra
var _first_screen := Vector2.ZERO
const CLOSE_PX := 30.0  # terminar a menos disto (px de tela) do começo fecha o contorno
var _spacing := SPACING_PX
var _stabilize := 0


func setup(territory, registry, map, panel, commands) -> void:
	_territory = territory
	_registry = registry
	_map = map
	_panel = panel
	_commands = commands
	panel.boundary_selected.connect(select_path)
	panel.boundary_reset_requested.connect(_reset_path)
	panel.boundary_apply_requested.connect(apply_preview)
	panel.boundary_discard_requested.connect(func() -> void: select_path(_id))
	panel.boundary_side_requested.connect(next_side)
	panel.fidelity_changed.connect(set_fidelity)
	commands.changed.connect(_on_history_changed)


func set_fidelity(index: int) -> void:
	_spacing = FIDELITY[index][1]
	_stabilize = FIDELITY[index][2]


## Passa a editar outra camada (outro nível territorial).
func use_territory(territory) -> void:
	stop()
	_territory = territory


func start(owner: int) -> void:
	_owner = owner
	_paths = _territory.BoundariesFor(owner)
	select_path(0)


func stop() -> void:
	if _owner == 0:
		return
	_drop_preview()
	_owner = 0
	_capturing = false
	_handle = -1
	_inserting = false
	if _map != null:
		_map.show_territory_path(PackedVector3Array(), PackedVector3Array(), true, _altitude_km)


func select_path(id: int) -> void:
	_drop_preview()
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
	_drop_preview()
	_last_side = {}
	_preview_points = PackedVector3Array()
	_moved_ms = Time.get_ticks_msec()
	_altitude_km = altitude_km
	if _id == 0 or _points.is_empty():
		_capturing = true
		_outside = false
		_points.clear()
		_points.append(dir)
		_last_screen = screen
		_first_screen = screen
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
	_moved_ms = Time.get_ticks_msec()
	if dir == Vector3.ZERO:
		if _capturing:
			_outside = true
		return
	if _capturing:
		if _outside:
			return
		_tail = dir
		if screen.distance_to(_last_screen) < _spacing or dir.is_equal_approx(_points[-1]):
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
		_points = stabilized(_points, _stabilize)
	_capturing = false
	_handle = -1
	_inserting = false
	if _points.size() >= 2 and _points != _saved:
		# Solta = aplica. Reaproveita a prévia se ela é deste mesmo traço e o mapa não mudou; senão planeja agora.
		if _plan == null or _preview_points != _points or _plan.Version != _territory.Version:
			var result := _make_plan(_points)
			if not result.has("plan"):
				_drop_preview()
				_points = _saved.duplicate()
				_refresh(String(result.message))
				return
			_plan = result.plan
		apply_preview()
	else:
		_drop_preview()
		_refresh()


func cancel() -> void:
	if dragging:
		select_path(_id)


func update_zoom(altitude_km: float) -> void:
	if _owner == 0 or absf(altitude_km - _altitude_km) < _altitude_km * 0.15:
		return
	_altitude_km = altitude_km
	_show_path()


## O traço é um contorno fechado? Um caminho já aplicado continua o que era (o contorno é guardado fechado: último ponto = primeiro);
## um novo, se terminou perto de onde começou.
func _is_loop() -> bool:
	for path in _paths:
		if path.id == _id and _id != 0:
			var pts: PackedVector3Array = path.points
			return int(path.source) == 0 and pts.size() >= 3 and pts[0].is_equal_approx(pts[-1])
	return _points.size() >= 3 and _last_screen.distance_to(_first_screen) <= CLOSE_PX


## O plano para estes pontos: {plan} ou {message}. Contorno fechado (terra livre de dentro) ou linha (corte de vizinho ou bolsão de terra livre).
func _make_plan(points: PackedVector3Array) -> Dictionary:
	var loop := _is_loop()
	var result: Dictionary = _territory.PlanLoopClaim(_owner, points, _id, land_only) if loop else _territory.PlanBoundaryClaimOn(_owner, points, _id, land_only)
	var plan = result.get("plan")
	if plan != null and plan.SourceOwner != 0 and (_registry.Name(plan.SourceOwner).is_empty() or _registry.Kind(plan.SourceOwner) != _registry.Kind(_owner)):
		return {"message": "O território cortado precisa pertencer a um cadastro do mesmo nível (país com país, província com província)."}
	return result


## Os pontos do traço como estão agora (com a ponta sob o mouse e a estabilização do modo suavizado).
func _current_points() -> PackedVector3Array:
	var pts := _points.duplicate()
	if _capturing:
		if not pts.is_empty() and not _tail.is_equal_approx(pts[-1]) and pts.size() < MAX_POINTS:
			pts.append(_tail)
		pts = stabilized(pts, _stabilize)
	return pts


## A cada quadro (Main): com o botão apertado e o mouse parado por PAUSE_MS, mostra a prévia do traço como está.
func tick() -> void:
	if not dragging or Time.get_ticks_msec() - _moved_ms < PAUSE_MS:
		return
	var pts := _current_points()
	if pts.size() < 2 or pts == _preview_points or pts == _saved:
		return
	_preview_points = pts
	var result := _make_plan(pts)
	if result.has("plan"):
		_plan = result.plan
		_show_preview()
	else:
		_drop_preview()
		_panel.show_boundary_state(String(result.message))


## Mostra no mapa o lado escolhido e diz o que vai acontecer.
func _show_preview() -> void:
	preview_changed.emit(_territory.PreviewImageOver(_plan, below))
	var source: String = _registry.Name(_plan.SourceOwner) if _plan.SourceOwner != 0 else "terra sem dono"
	var text := "Prévia: ≈ %s km² de %s passam para %s. Solte o mouse para aplicar." % [
		_thousands(roundi(_territory.PlanAreaKm2(_plan))), source, _registry.Name(_plan.TargetOwner)]
	if _plan.ChoiceCount > 1:
		text += " Mais de um lado encosta: depois de soltar, \"Outro lado\" troca."
	_panel.show_boundary_state(text)
	_show_path()


## Depois de aplicar um corte em que mais de um lado encosta: desfaz e aplica o outro lado (só se nada mudou desde então).
func next_side() -> void:
	if _last_side.is_empty() or dragging or _territory.Version != _last_side.version:
		return
	var side: Dictionary = _last_side
	_last_side = {}
	_commands.undo()
	var keep := _id
	_id = side.id
	var result := _make_plan(side.points)
	_id = keep
	if not result.has("plan"):
		_refresh(String(result.get("message", "")))
		return
	result.plan.Choose((side.choice + 1) % side.count)
	_plan = result.plan
	apply_preview()


## Aplica o plano: a camada muda (um comando na pilha de desfazer).
func apply_preview() -> void:
	if _plan == null:
		return
	var plan = _plan
	var neighbor: String = _registry.Name(plan.SourceOwner) if plan.SourceOwner != 0 else "a terra sem dono"
	var applied_id := _id
	var points := _points.duplicate()
	_drop_preview()
	var edit = _territory.ApplyBoundary(plan)
	if edit == null:
		_points = _saved.duplicate()
		_refresh("O mapa mudou durante o traço. Desenhe novamente.")
		return
	_commands.push("Redesenhar fronteira", edit)
	_last_side = {}
	if plan.ChoiceCount > 1:
		_last_side = {"points": points, "id": applied_id, "choice": plan.Choice, "count": plan.ChoiceCount, "version": _territory.Version}
	_panel.show_boundary_preview(false, plan.ChoiceCount > 1)
	_refresh("Fronteira com %s atualizada.%s" % [neighbor, " Mais de um lado encostava: \"Outro lado\" troca." if plan.ChoiceCount > 1 else ""])


## Há uma prévia na tela (traço em andamento)?
func has_preview() -> bool:
	return _plan != null


func _drop_preview() -> void:
	if _plan == null:
		return
	_plan = null
	preview_changed.emit(null)


## Média móvel (vizinho, ponto, vizinho, pesos 1-2-1) na esfera, `passes` vezes; as pontas não se movem.
static func stabilized(points: PackedVector3Array, passes: int) -> PackedVector3Array:
	var out := points
	for _p in passes:
		var next := out.duplicate()
		for i in range(1, out.size() - 1):
			next[i] = (out[i - 1] + 2.0 * out[i] + out[i + 1]).normalized()
		out = next
	return out


static func _thousands(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _reset_path() -> void:
	_capturing = false
	_handle = -1
	_inserting = false
	_points.clear()
	_refresh()


func _on_history_changed() -> void:
	if _owner == 0:
		return
	if _plan != null and _plan.Version != _territory.Version:
		select_path(_id)  # desfazer/refazer depois da prévia: ela não vale mais
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
			neighbors[path.source] = _registry.Name(path.source) if int(path.source) != 0 else "contorno em terra livre"
	_panel.show_boundary_options(_paths, neighbors, _id)


func _show_path() -> void:
	if _map != null:
		var controls := PackedVector3Array() if dragging else _points
		var draft := _id == 0 or _points != _saved
		var curve := _points.duplicate()
		if not dragging and curve.size() >= 3 and _is_loop() and not curve[-1].is_equal_approx(curve[0]):
			curve.append(curve[0])  # o contorno fechado aparece fechado
		_map.show_territory_path(_territory.SmoothBoundary(curve), controls, draft, _altitude_km)


func _refresh(message := "") -> void:
	if message.is_empty():
		if dragging:
			message = "Pare o mouse para ver a prévia; solte para aplicar."
		elif _points.size() < 2:
			message = "Saia da borda do território e volte a ela (por um vizinho ou por terra livre), ou desenhe um contorno fechado em terra livre. Pare o mouse para ver a prévia; solte para aplicar."
		else:
			message = "Arraste a linha ou os pontos para ajustar o traço."
	_panel.show_boundary_state(message)
	_show_path()
