extends Control
## Marcadores e nomes dos corpos, desenhados por cima do 3D, em resolução cheia (o 3D é pixelado, o texto não).
## Corpos pequenos demais para aparecer viram um ponto; os grandes ganham só o nome. Também responde "qual corpo
## está sob o clique?".

const SolarBodies = preload("res://scripts/sim/solar_bodies.gd")

const FONT_SIZE := 14
const DOT_RADIUS := 3.0
const SMALL_PX := 4.0         # corpo com raio menor que isso na tela vira um ponto
const PICK_PX := 14.0         # distância máxima do clique ao corpo, além do raio dele
const MOON_HIDE_PX := 24.0    # a Lua some quando está colada na Terra na tela
const LABEL_COLOR := Color(0.9, 0.9, 0.95, 0.9)

var focus_id := SolarBodies.Id.EARTH
var _screen := {}  # Id -> {"pos": Vector2, "radius": float}


## Calcula onde cada corpo cai na tela. `positions` = Id -> Vector3 (cena); `shrink` = fator de pixelização do 3D.
func update_frame(cam: Camera3D, px_scale: float, shrink: int, positions: Dictionary) -> void:
	_screen.clear()
	for id in positions:
		var p: Vector3 = positions[id]
		if cam.is_position_behind(p):
			continue
		var dist := maxf(cam.global_position.distance_to(p), 1e-6)
		_screen[id] = {"pos": cam.unproject_position(p) * float(shrink),
			"radius": SolarBodies.radius_units(id) / dist * px_scale * shrink}
	queue_redraw()


## O corpo mais perto do ponto da tela, ou -1.
func pick(screen_pos: Vector2) -> int:
	var best := -1
	var best_d := PICK_PX
	for id in _screen:
		if not _visible(id):
			continue
		var d: float = _screen[id]["pos"].distance_to(screen_pos) - maxf(_screen[id]["radius"], 0.0)
		if d < best_d:
			best_d = d
			best = id
	return best


func _visible(id: int) -> bool:
	var parent := SolarBodies.parent_of(id)  # a lua some quando está colada no corpo em volta do qual orbita
	if parent >= 0 and _screen.has(parent):
		return _screen[id]["pos"].distance_to(_screen[parent]["pos"]) > MOON_HIDE_PX
	return true


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var drawn: Array[Rect2] = []  # nomes já escritos: um nome que sobrepõe outro (planetas juntos) não é escrito
	for id in _draw_order():
		var pos: Vector2 = _screen[id]["pos"]
		var radius: float = _screen[id]["radius"]
		if pos.x < -50.0 or pos.y < -50.0 or pos.x > size.x + 50.0 or pos.y > size.y + 50.0:
			continue
		var color: Color = SolarBodies.BODIES[id]["color"]
		var offset := radius + 8.0
		if radius < SMALL_PX:
			draw_circle(pos, DOT_RADIUS + 1.0, Color(0.0, 0.0, 0.0, 0.8))
			draw_circle(pos, DOT_RADIUS, color)
			offset = DOT_RADIUS + 6.0
		if id == focus_id:
			draw_arc(pos, maxf(radius, DOT_RADIUS) + 5.0, 0.0, TAU, 32, Color(1, 1, 1, 0.6), 1.0)
			offset += 5.0
		var text := SolarBodies.body_name(id)
		var box := Rect2(pos + Vector2(offset, -FONT_SIZE * 0.6), font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE))
		var overlaps := false
		for other in drawn:
			if other.grow(2.0).intersects(box):
				overlaps = true
				break
		if overlaps:
			continue
		drawn.append(box)
		draw_string(font, pos + Vector2(offset + 1.0, 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0, 0, 0, 0.8))
		draw_string(font, pos + Vector2(offset, 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LABEL_COLOR)


## Quem escreve o nome primeiro vence a disputa por espaço: o foco, a Terra, depois o Sol e os planetas, e a Lua por último.
func _draw_order() -> Array:
	var order: Array = []
	for id in _screen:
		if _visible(id):
			order.append(id)
	order.sort_custom(func(a: int, b: int) -> bool: return _priority(a) < _priority(b))
	return order


func _priority(id: int) -> int:
	if id == focus_id:
		return -2
	if id == SolarBodies.Id.EARTH:
		return -1
	return 100 + id if id >= SolarBodies.Id.MOON else id
