extends Node3D
## As presenças dos cadastros desenhadas sobre o globo: um disco translúcido com aro para cada área aproximada e um rótulo de tamanho fixo
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
const LABEL_PIXEL := 0.00045  # tamanho do nome de perto
const FAR_SCALE := 0.65      # de longe o nome encolhe até esta fração
const NEAR_KM := 1500.0      # altitude da câmera: daqui para baixo, tamanho cheio
const FAR_KM := 9000.0       # daqui para cima, o menor
const CELL := 12.0           # pixels da grade que diz onde já há nome

static var flat := false    # mapa plano (GlobeView.set_flat): os pontos vão para o plano z = 0, em (lon · raio, lat · raio)
var radius := 1.0            # raio do globo na cena (GlobeView.RADIUS)
var _items: Array = []       # o último show_items (para redesenhar ao trocar globo e plano)
var item_count := 0          # presenças desenhadas
var area_count := 0          # discos
var label_count := 0         # lugares rotulados

var _mesh_node: MeshInstance3D
var _labels: Array[Label3D] = []
var _laid_out: Array = []    # a vista da última arrumação dos nomes
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


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _labels.is_empty():
		return
	var view := get_viewport().get_visible_rect().size
	if _laid_out != [cam.global_transform, view]:
		_laid_out = [cam.global_transform, view]
		_lay_out(cam, view)


## Esconde os nomes do outro lado do planeta (eles não têm teste de profundidade), encolhe todos de longe e, onde um cobriria outro,
## deixa só o símbolo; símbolo que cairia em cima de um nome some. A ordem dos itens decide quem fica com o texto; aproximando, os
## outros voltam.
func _lay_out(cam: Camera3D, view: Vector2) -> void:
	var eye := cam.global_position.normalized()
	var altitude := (cam.global_position.z / radius if flat else cam.global_position.length() / radius - 1.0) * EvronGeo.RADIUS_KM
	var far := clampf(inverse_lerp(NEAR_KM, FAR_KM, altitude), 0.0, 1.0)
	var pixel := LABEL_PIXEL * snappedf(lerpf(1.0, FAR_SCALE, far), 0.05)  # em degraus: o zoom não refaz os textos a cada quadro
	var screen := pixel * view.y / (2.0 * tan(deg_to_rad(cam.fov) / 2.0))  # pixels da tela por pixel da fonte
	var used := {}
	var loose := {}  # os que ficaram só com o símbolo: onde cada um está na tela
	for l in _labels:
		l.visible = flat or l.global_position.normalized().dot(eye) > 0.2
		if not l.visible:
			continue
		l.pixel_size = pixel
		var size: Vector2 = l.get_meta("size") * screen
		var full: String = l.get_meta("text")
		var at := cam.unproject_position(l.global_position)
		var fits := _take(used, Rect2(at - Vector2(0, size.y / 2.0), size))
		l.text = full if fits else (full[0] if full.length() > 1 and full[1] == " " else "•")
		if not fits:
			loose[l] = at
	for l in loose:
		l.visible = not used.has(Vector2i((loose[l] / CELL).floor()))


## Marca as células da tela que o retângulo cobre; false (sem marcar) se alguma já tem nome.
func _take(used: Dictionary, rect: Rect2) -> bool:
	var cells: Array[Vector2i] = []
	for x in range(floori(rect.position.x / CELL), ceili(rect.end.x / CELL)):
		for y in range(floori(rect.position.y / CELL), ceili(rect.end.y / CELL)):
			if used.has(Vector2i(x, y)):
				return false
			cells.append(Vector2i(x, y))
	for c in cells:
		used[c] = true
	return true


## O ponto da cena da direção n a `height` raios do centro: no globo, n × raio × height; no plano, o ponto (lon, lat) com a
## folga (height − 1) acima dele.
static func at(n: Vector3, r: float, height: float) -> Vector3:
	if not flat:
		return n.normalized() * r * height
	var ll := EvronGeo.lat_lon(n.normalized())
	return Vector3(deg_to_rad(ll.y) * r, deg_to_rad(ll.x) * r, (height - 1.0) * r)


## Redesenha o que estava na tela (depois de trocar globo e plano).
func redraw() -> void:
	show_items(_items)


## Redesenha tudo. items: o que Registry.MapItems devolve (place_id, place, lat, lon, radius_km, layer, role, entity).
func show_items(items: Array) -> void:
	_items = items
	_laid_out = []
	for l in _labels:
		l.queue_free()
	_labels.clear()
	item_count = items.size()
	area_count = 0
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var by_place := {}  # place_id -> itens (um rótulo por lugar)
	var rings := {}     # place_id -> discos já desenhados nele
	for it in items:
		if not by_place.has(it.place_id):
			by_place[it.place_id] = []
		by_place[it.place_id].append(it)
		if it.radius_km > 0.0:
			area_count += 1
			var inset: int = rings.get(it.place_id, 0)  # entidades no mesmo lugar: cada aro um pouco mais para dentro, para não esconder o de baixo
			rings[it.place_id] = inset + 1
			_add_disc(verts, colors, it, inset)
	_mesh_node.mesh = _build_mesh(verts, colors)
	for place_id in by_place:
		_add_label(by_place[place_id])
	label_count = _labels.size()


## A cor do item: a própria (ocorrências de recurso) ou a da camada de presença.
func _color_of(it: Dictionary) -> Color:
	return it["color"] if it.has("color") else UiKit.layer_color.get(it.layer, Color.WHITE)


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
		left.append(at(p + side * w, radius, HEIGHT))
		right.append(at(p - side * w, radius, HEIGHT))
	for i in (m if closed else m - 1):
		var j := (i + 1) % m
		verts.append_array([left[i], right[i], right[j], left[i], right[j], left[j]])
		for _n in 6:
			colors.append(color)


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
	# Um traço longo tem milhares de pontos: marca só alguns (todos continuam podendo ser arrastados).
	var every := maxi(1, ceili(points.size() / 120.0))
	for i in points.size():
		if i % every != 0 and i != points.size() - 1:
			continue
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
		mark.position = at(points[i], radius, HEIGHT + 0.0012)
		add_child(mark)
		_draft_labels.append(mark)


func _add_disc(verts: PackedVector3Array, colors: PackedColorArray, it: Dictionary, inset: int) -> void:
	var c := EvronGeo.dir(it.lat, it.lon)
	var a: float = it.radius_km / EvronGeo.RADIUS_KM
	var any := Vector3.UP if absf(c.y) < 0.99 else Vector3.RIGHT
	var u := c.cross(any).normalized()
	var v := c.cross(u)
	var color := _color_of(it)
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
		pts.append(at(cos(a) * c + sin(a) * (cos(b) * u + sin(b) * v), radius, height))
	return pts


func _add_label(group: Array) -> void:
	var first: Dictionary = group[0]
	if first.has("label"):  # um rótulo pronto (ocorrência de recurso)
		_place_label(first, first.label)
		return
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
	_place_label(first, "\n".join(lines))


func _place_label(first: Dictionary, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = LABEL_PIXEL
	label.font_size = 32
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.modulate = _color_of(first).lightened(0.25)
	label.no_depth_test = true  # com teste de profundidade o relevo cortava o nome ao girar o globo; o lado de trás é escondido em _process
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.position = at(EvronGeo.dir(first.lat, first.lon), radius, HEIGHT + 0.0008)
	label.set_meta("text", text)
	label.set_meta("size", ThemeDB.fallback_font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size))
	add_child(label)
	_labels.append(label)
