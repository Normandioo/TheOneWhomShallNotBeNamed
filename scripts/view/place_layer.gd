extends Node3D
## As presenças dos cadastros desenhadas sobre o globo: um disco translúcido com aro para cada área aproximada, e um rótulo de tamanho fixo
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
var area_count := 0          # discos
var label_count := 0         # lugares rotulados

var _mesh_node: MeshInstance3D
var _labels: Array[Label3D] = []
var _material: StandardMaterial3D


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


## Redesenha tudo. items: o que Registry.MapItems devolve (place_id, place, lat, lon, radius_km, layer, role, entity).
func show_items(items: Array) -> void:
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
	if verts.is_empty():
		_mesh_node.mesh = null
	else:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_mesh_node.mesh = mesh
	for place_id in by_place:
		_add_label(by_place[place_id])
	label_count = _labels.size()


func _add_disc(verts: PackedVector3Array, colors: PackedColorArray, it: Dictionary, inset: int) -> void:
	var c := EvronGeo.dir(it.lat, it.lon)
	var a: float = it.radius_km / EvronGeo.RADIUS_KM
	var any := Vector3.UP if absf(c.y) < 0.99 else Vector3.RIGHT
	var u := c.cross(any).normalized()
	var v := c.cross(u)
	var color: Color = UiKit.LAYER_COLOR.get(it.layer, Color.WHITE)
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
	label.modulate = UiKit.LAYER_COLOR.get(first.layer, Color.WHITE).lightened(0.25)
	label.no_depth_test = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.position = EvronGeo.dir(first.lat, first.lon) * radius * (HEIGHT + 0.0008)
	add_child(label)
	_labels.append(label)
