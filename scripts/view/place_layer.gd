extends Node3D
## As presenças dos cadastros desenhadas sobre o globo: um disco translúcido com aro para cada área aproximada, um contorno (fronteira desenhada à mão)
## com preenchimento e aro seguindo os arcos entre os pontos, e um rótulo de tamanho fixo
## na tela para cada lugar (com a função e as entidades que estão nele). Cada camada tem a sua cor: fronteira política, presença cultural,
## distribuição étnica, área linguística, presença religiosa e habitat de raça não se confundem. Só desenha o que recebe; quem decide o que
## mostrar (camadas, entidade, data) é o DomainHub.
##
## O globo é estático na cena (a câmera é que gira), então um ponto do planeta é só `direção × raio`.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const HEIGHT := 1.0015       # fração do raio: ~12 km acima do globo, sobre o relevo e sem flutuar
const SEGMENTS := 72         # lados de cada anel
const MAX_RING_STEP := 0.02  # rad (~165 km): o preenchimento é em anéis para acompanhar a curvatura
const MAX_LABEL_LINES := 4

var radius := 1.0            # raio do globo na cena (GlobeView.RADIUS)
var item_count := 0          # presenças desenhadas
var area_count := 0          # discos e contornos
var polygon_count := 0       # só os contornos
var draft_count := 0         # pontos do contorno que está sendo desenhado
var label_count := 0         # lugares rotulados

var _mesh_node: MeshInstance3D
var _labels: Array[Label3D] = []
var _material: StandardMaterial3D
var _draft_node: MeshInstance3D
var _draft_labels: Array[Label3D] = []


func _init() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_node = MeshInstance3D.new()
	_mesh_node.material_override = _material
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_node)
	_draft_node = MeshInstance3D.new()
	_draft_node.material_override = _material
	_draft_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_draft_node)


## Redesenha tudo. items: o que Registry.MapItems devolve (place_id, place, lat, lon, radius_km, layer, role, entity).
## Esconde os nomes do outro lado do planeta (eles não têm teste de profundidade).
func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _labels.is_empty():
		return
	var eye := cam.global_position.normalized()
	for l in _labels:
		l.visible = l.global_position.normalized().dot(eye) > 0.2


func show_items(items: Array) -> void:
	for l in _labels:
		l.queue_free()
	_labels.clear()
	item_count = items.size()
	area_count = 0
	polygon_count = 0
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var by_place := {}  # place_id -> itens (um rótulo por lugar)
	var rings := {}     # place_id -> discos já desenhados nele
	for it in items:
		if not by_place.has(it.place_id):
			by_place[it.place_id] = []
		by_place[it.place_id].append(it)
		if it.has("vertices") and it.vertices.size() >= 6:  # contorno desenhado à mão (vence o raio)
			area_count += 1
			polygon_count += 1
			_add_polygon(verts, colors, it)
		elif it.radius_km > 0.0:
			area_count += 1
			var inset: int = rings.get(it.place_id, 0)  # entidades no mesmo lugar: cada aro um pouco mais para dentro, para não esconder o de baixo
			rings[it.place_id] = inset + 1
			_add_disc(verts, colors, it, inset)
	_mesh_node.mesh = _build_mesh(verts, colors)
	for place_id in by_place:
		_add_label(by_place[place_id])
	label_count = _labels.size()


func _build_mesh(verts: PackedVector3Array, colors: PackedColorArray) -> ArrayMesh:
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## O contorno: preenchimento translúcido (triangulado no plano gnomônico em torno do centro, onde os arcos de círculo máximo são retas, e subdividido
## para acompanhar a curvatura) e um aro que segue cada arco entre os pontos.
func _add_polygon(verts: PackedVector3Array, colors: PackedColorArray, it: Dictionary) -> void:
	var flat: PackedFloat64Array = it.vertices
	var dirs: Array[Vector3] = []
	for i in flat.size() / 2:
		dirs.append(EvronGeo.dir(flat[2 * i], flat[2 * i + 1]))
	var color: Color = UiKit.layer_color.get(it.layer, Color.WHITE)
	var tri := _triangulate(dirs, EvronGeo.dir(it.lat, it.lon))
	for k in range(0, tri.size(), 3):
		_fill_triangle(verts, colors, dirs[tri[k]], dirs[tri[k + 1]], dirs[tri[k + 2]], Color(color, 0.16), 0)
	var extent := sqrt(maxf(it.area_km2, 1.0) / PI) / EvronGeo.RADIUS_KM  # raio equivalente em rad
	_ribbon(verts, colors, dirs, clampf(extent * 0.03, 0.0004, 0.008), Color(color, 0.9), true)


## Índices dos triângulos do contorno (de 3 em 3), ou vazio se não dá para triangular (o aro continua sendo desenhado).
func _triangulate(dirs: Array[Vector3], c: Vector3) -> PackedInt32Array:
	var east := Vector3.UP.cross(c)
	east = Vector3.RIGHT if east.length() < 1e-6 else east.normalized()
	var north := c.cross(east)
	var poly := PackedVector2Array()
	for p in dirs:
		var k := p.dot(c)
		poly.append(Vector2(p.dot(east) / k, p.dot(north) / k))
	return Geometry2D.triangulate_polygon(poly)


## Um triângulo do preenchimento, dividido em quatro (com os pontos médios sobre a esfera) até os lados ficarem curtos.
func _fill_triangle(verts: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, color: Color, depth: int) -> void:
	if depth < 7 and maxf(maxf(a.angle_to(b), b.angle_to(c)), c.angle_to(a)) > MAX_RING_STEP * 1.5:
		var ab := (a + b).normalized()
		var bc := (b + c).normalized()
		var ca := (c + a).normalized()
		_fill_triangle(verts, colors, a, ab, ca, color, depth + 1)
		_fill_triangle(verts, colors, ab, b, bc, color, depth + 1)
		_fill_triangle(verts, colors, ca, bc, c, color, depth + 1)
		_fill_triangle(verts, colors, ab, bc, ca, color, depth + 1)
		return
	var h := radius * (HEIGHT - 0.0007)
	verts.append_array([a * h, b * h, c * h])
	for _n in 3:
		colors.append(color)


## Faixa de meia-largura angular w (rad) ao longo do caminho que passa pelos pontos, por arcos de círculo máximo (fechada: liga o último ao primeiro).
func _ribbon(verts: PackedVector3Array, colors: PackedColorArray, dirs: Array[Vector3], w: float, color: Color, closed: bool) -> void:
	var path: Array[Vector3] = []
	var edges := dirs.size() if closed else dirs.size() - 1
	for i in edges:
		var a := dirs[i]
		var b := dirs[(i + 1) % dirs.size()]
		var steps := maxi(1, ceili(a.angle_to(b) / MAX_RING_STEP))
		for s in steps:
			path.append(a.slerp(b, float(s) / steps) if a.dot(b) < 0.999999 else a)
	if not closed:
		path.append(dirs[dirs.size() - 1])
	var m := path.size()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in m:
		var p := path[i]
		var prev := path[(i - 1 + m) % m] if closed else path[maxi(i - 1, 0)]
		var next := path[(i + 1) % m] if closed else path[mini(i + 1, m - 1)]
		var tangent := next - prev
		var side := p.cross(tangent)
		side = side.normalized() if side.length() > 1e-9 else Vector3.ZERO
		left.append((p + side * w).normalized() * radius * HEIGHT)
		right.append((p - side * w).normalized() * radius * HEIGHT)
	for i in (m if closed else m - 1):
		var j := (i + 1) % m
		verts.append_array([left[i], right[i], right[j], left[i], right[j], left[j]])
		for _n in 6:
			colors.append(color)


## O contorno que está sendo desenhado: a linha pelos pontos (e, com 3 ou mais, o lado que fecharia, mais fraco) e uma marca em cada ponto.
## dirs: direções dos pontos na ordem em que foram clicados; vazio apaga o rascunho.
func show_draft(dirs: Array) -> void:
	draft_count = dirs.size()
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var typed: Array[Vector3] = []
	for d in dirs:
		typed.append(d)
	if typed.size() >= 2:
		var extent := 0.0
		for p in typed:
			extent = maxf(extent, typed[0].angle_to(p))
		var w := clampf(extent * 0.012, 0.0005, 0.004)
		_ribbon(verts, colors, typed, w, Color(1.0, 0.92, 0.35, 0.95), false)
		if typed.size() >= 3:
			_ribbon(verts, colors, [typed[typed.size() - 1], typed[0]] as Array[Vector3], w * 0.6, Color(1.0, 0.92, 0.35, 0.35), false)
	_draft_node.mesh = _build_mesh(verts, colors)
	_show_draft_marks(PackedVector3Array(typed), Color(1.0, 0.92, 0.35))


func show_territory_path(curve: PackedVector3Array, controls: PackedVector3Array, draft: bool, altitude_km: float) -> void:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var color := Color(1.0, 0.73, 0.22) if draft else Color(0.28, 1.0, 0.78)
	if curve.size() >= 2:
		var dirs: Array[Vector3] = []
		dirs.assign(Array(curve))
		var width := clampf(altitude_km / EvronGeo.RADIUS_KM * 0.003, 0.000005, 0.003)
		_ribbon(verts, colors, dirs, width, color, false)
	_draft_node.mesh = _build_mesh(verts, colors)
	_show_draft_marks(controls, color)


func _show_draft_marks(points: PackedVector3Array, color: Color) -> void:
	for label in _draft_labels:
		label.queue_free()
	_draft_labels.clear()
	for i in points.size():
		var mark := Label3D.new()
		mark.text = "◉" if i == 0 else "●"
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.fixed_size = true
		mark.pixel_size = 0.0005
		mark.font_size = 36
		mark.outline_size = 8
		mark.outline_modulate = Color(0, 0, 0, 0.9)
		mark.modulate = color
		mark.no_depth_test = false
		mark.position = points[i] * radius * (HEIGHT + 0.0012)
		add_child(mark)
		_draft_labels.append(mark)


func _add_disc(verts: PackedVector3Array, colors: PackedColorArray, it: Dictionary, inset: int) -> void:
	var c := EvronGeo.dir(it.lat, it.lon)
	var a: float = it.radius_km / EvronGeo.RADIUS_KM
	var any := Vector3.UP if absf(c.y) < 0.99 else Vector3.RIGHT
	var u := c.cross(any).normalized()
	var v := c.cross(u)
	var color: Color = UiKit.layer_color.get(it.layer, Color.WHITE)
	var steps := clampi(ceili(a / MAX_RING_STEP), 1, 24)
	for k in range(1, steps + 1):  # preenchimento translúcido, de dentro para fora
		_band(verts, colors, c, u, v, a * (k - 1) / steps, a * k / steps, HEIGHT - 0.0007, Color(color, 0.16))
	var width := clampf(a * 0.06, 0.0006, 0.02)  # o aro: ~6% do raio do disco, nem fino demais de longe nem grosso de perto
	var edge := a - inset * width * 1.4
	if edge > width:
		_band(verts, colors, c, u, v, edge - width, edge, HEIGHT, Color(color, 0.9))


## Triângulos entre o anel de raio angular a0 e o de a1 em volta de c (a0 = 0 é o centro).
func _band(verts: PackedVector3Array, colors: PackedColorArray, c: Vector3, u: Vector3, v: Vector3, a0: float, a1: float, height: float, color: Color) -> void:
	var inner := _ring(c, u, v, a0, height)
	var outer := _ring(c, u, v, a1, height)
	for i in SEGMENTS:
		var j := (i + 1) % SEGMENTS
		verts.append_array([inner[i], outer[i], outer[j], inner[i], outer[j], inner[j]])
		for _n in 6:
			colors.append(color)


func _ring(c: Vector3, u: Vector3, v: Vector3, a: float, height: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in SEGMENTS:
		var b := TAU * i / SEGMENTS
		pts.append((cos(a) * c + sin(a) * (cos(b) * u + sin(b) * v)).normalized() * radius * height)
	return pts


func _add_label(group: Array) -> void:
	var first: Dictionary = group[0]
	var glyph := "● "
	for it in group:
		if it.role == "capital":
			glyph = "★ "
		elif glyph == "● " and it.role in ["sede", "lugar_sagrado"]:
			glyph = "◆ "
	var lines: Array[String] = [glyph + first.place]
	for it in group:
		if lines.size() > MAX_LABEL_LINES:
			lines.append("…")
			break
		lines.append("   %s · %s" % [it.entity, UiKit.role_label(it.role)])
	var label := Label3D.new()
	label.text = "\n".join(lines)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.00045
	label.font_size = 32
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.modulate = UiKit.layer_color.get(first.layer, Color.WHITE).lightened(0.25)
	label.no_depth_test = true  # com teste de profundidade o relevo cortava o nome ao girar o globo; o lado de trás é escondido em _process
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.position = EvronGeo.dir(first.lat, first.lon) * radius * (HEIGHT + 0.0008)
	add_child(label)
	_labels.append(label)
