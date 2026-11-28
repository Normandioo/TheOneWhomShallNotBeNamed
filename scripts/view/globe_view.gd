extends Node
## A vista 3D: o globo de Evron numa SubViewport, a câmera e a conversão de tela para ponto da superfície.
## Avisa por sinais o ponto sob o mouse (`surface_hovered`) e o ponto clicado (`surface_clicked`), como direções
## no referencial do planeta (lat/lon de EvronGeo). Fora do globo, a direção é Vector3.ZERO.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const GlobeCamera = preload("res://scripts/view/globe_camera.gd")
const TileLayer = preload("res://scripts/view/tile_layer.gd")
const PlaceLayer = preload("res://scripts/view/place_layer.gd")

signal surface_hovered(direction: Vector3)
signal surface_clicked(direction: Vector3)

const UNIT_KM := 1000.0  # 1 unidade da cena = 1000 km
const RADIUS := EvronGeo.RADIUS_KM / UNIT_KM
# Com blocos na tela, o globo de baixo desce ~10 km: as cordas dos blocos grandes afundam e ele apareceria por cima.
# Ele continua lá para tapar qualquer fresta entre blocos de níveis diferentes (com a mesma imagem em 4K).
const UNDER_TILES_SCALE := 0.9988

var camera: GlobeCamera
var tiles: TileLayer
var places: PlaceLayer  # as presenças dos cadastros (discos e rótulos) sobre o globo
var resources: PlaceLayer  # as ocorrências de recursos, numa camada própria
var settlements: PlaceLayer  # os povoados da produção
var ruler: PlaceLayer  # a linha da régua
var _globe: MeshInstance3D
var flat := false  # mapa plano (set_flat)
var _material: ShaderMaterial


## Chamar antes de add_child.
func setup(material: ShaderMaterial) -> void:
	_material = material


func _ready() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	container.add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR  # o lado de trás não fica preto
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.35
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	_globe = MeshInstance3D.new()
	_globe.mesh = _latlon_sphere(256, 128)
	_globe.material_override = _material
	viewport.add_child(_globe)
	tiles = TileLayer.new()
	viewport.add_child(tiles)
	places = PlaceLayer.new()
	places.radius = RADIUS
	viewport.add_child(places)
	resources = PlaceLayer.new()
	resources.radius = RADIUS
	viewport.add_child(resources)
	settlements = PlaceLayer.new()
	settlements.radius = RADIUS
	viewport.add_child(settlements)
	ruler = PlaceLayer.new()
	ruler.radius = RADIUS
	viewport.add_child(ruler)

	camera = GlobeCamera.new()
	camera.radius = RADIUS
	viewport.add_child(camera)
	camera.clicked.connect(func(pos: Vector2) -> void: surface_clicked.emit(pick(pos)))
	camera.look_at_dir(EvronGeo.dir(20.0, 0.0), 3.0)


func update(delta: float) -> void:
	camera.advance(delta)
	if not flat:
		tiles.update(camera.cam)


## A esfera como grade de lat/lon (costura em 180°, UV equiretangular): o shader a desdobra no mapa plano sem triângulo atravessando o mapa.
static func _latlon_sphere(cols: int, rows: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in rows + 1:
		for i in cols + 1:
			var uv := Vector2(float(i) / cols, float(j) / rows)
			var n := EvronGeo.dir(90.0 - uv.y * 180.0, uv.x * 360.0 - 180.0)
			verts.append(n * RADIUS)
			normals.append(n)
			uvs.append(uv)
	for j in rows:
		for i in cols:
			var a := j * (cols + 1) + i
			idx.append_array([a, a + 1, a + cols + 1, a + 1, a + cols + 2, a + cols + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-PI, -PI, -PI) * RADIUS, Vector3(TAU, TAU, TAU) * RADIUS)  # cobre também o plano desdobrado
	return mesh


## Globo ou mapa plano (equiretangular). As mesmas camadas, entidades e coordenadas: só a geometria e a câmera mudam. Os blocos de
## alta resolução ficam só no globo (shortcut: o plano usa o mapa de 4K; levar a pirâmide ao plano se fizer falta de perto).
func set_flat(on: bool) -> void:
	if on == flat:
		return
	flat = on
	_material.set_shader_parameter("flat_map", 1.0 if on else 0.0)
	tiles.visible = not on
	PlaceLayer.flat = on
	for layer in [places, resources, settlements]:
		layer.redraw()
	camera.flat = on
	camera.snap()


## O ponto da cena de uma direção do planeta, a `height` raios do centro (no plano, `height` vira uma pequena folga acima dele).
static func world_of(n: Vector3, height := 1.0) -> Vector3:
	return PlaceLayer.at(n, RADIUS, height)


## Mostra a pirâmide de blocos `tile_set` por cima do globo ("" = nenhuma).
func set_tiles(tile_set: String, height_tex: Texture2D, river_tex: Texture2D) -> void:
	if tile_set == tiles.name_id:
		return
	var on := tile_set != "" and tiles.open(tile_set, RADIUS, height_tex, river_tex)
	if not on:
		tiles.close()
	_globe.scale = Vector3.ONE * (UNDER_TILES_SCALE if on and not flat else 1.0)


## Leva a câmera para olhar a direção n do globo, a `zoom` raios do centro (3 = o planeta inteiro; perto do chão, ~1,05).
func focus(n: Vector3, zoom: float) -> void:
	camera.look_at_dir(n, zoom)


func handle_input(e: InputEvent) -> void:
	camera.handle_input(e)
	if e is InputEventMouseMotion:
		surface_hovered.emit(pick((e as InputEventMouseMotion).position))


## Altitude da câmera acima da superfície, em km.
func camera_altitude_km() -> float:
	return (camera.dist - RADIUS) * UNIT_KM


## O ponto do globo sob a posição da tela (direção no referencial do planeta), ou Vector3.ZERO fora dele.
func pick(screen_pos: Vector2) -> Vector3:
	var cam := camera.cam
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if flat:  # o plano z = 0: x = lon · raio, y = lat · raio
		if absf(dir.z) < 1e-9:
			return Vector3.ZERO
		var hit := origin + dir * (-origin.z / dir.z)
		var lon := hit.x / RADIUS
		var lat := hit.y / RADIUS
		if absf(lon) > PI or absf(lat) > PI / 2.0:
			return Vector3.ZERO
		return EvronGeo.dir(rad_to_deg(lat), rad_to_deg(lon))
	var b := origin.dot(dir)
	var disc := b * b - (origin.length_squared() - RADIUS * RADIUS)
	if disc < 0.0 or -b - sqrt(disc) <= 0.0:
		return Vector3.ZERO
	return (origin + dir * (-b - sqrt(disc))).normalized()
