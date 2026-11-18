extends Node
## A vista 3D: o globo de Evron numa SubViewport, a câmera e a conversão de tela para ponto da superfície.
## Avisa por sinais o ponto sob o mouse (`surface_hovered`) e o ponto clicado (`surface_clicked`), como direções
## no referencial do planeta (lat/lon de EvronGeo). Fora do globo, a direção é Vector3.ZERO.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const GlobeCamera = preload("res://scripts/view/globe_camera.gd")
const TileLayer = preload("res://scripts/view/tile_layer.gd")

signal surface_hovered(direction: Vector3)
signal surface_clicked(direction: Vector3)

const UNIT_KM := 1000.0  # 1 unidade da cena = 1000 km
const RADIUS := EvronGeo.RADIUS_KM / UNIT_KM
# Com blocos na tela, o globo de baixo desce ~10 km: as cordas dos blocos grandes afundam e ele apareceria por cima.
# Ele continua lá para tapar qualquer fresta entre blocos de níveis diferentes (com a mesma imagem em 4K).
const UNDER_TILES_SCALE := 0.9988

var camera: GlobeCamera
var tiles: TileLayer
var _globe: MeshInstance3D
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

	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 256
	sphere.rings = 128
	_globe = MeshInstance3D.new()
	_globe.mesh = sphere
	_globe.material_override = _material
	viewport.add_child(_globe)
	tiles = TileLayer.new()
	viewport.add_child(tiles)

	camera = GlobeCamera.new()
	camera.radius = RADIUS
	viewport.add_child(camera)
	camera.clicked.connect(func(pos: Vector2) -> void: surface_clicked.emit(pick(pos)))
	camera.look_at_dir(EvronGeo.dir(20.0, 0.0), 3.0)


func update(delta: float) -> void:
	camera.advance(delta)
	tiles.update(camera.cam)


## Mostra a pirâmide de blocos `tile_set` por cima do globo ("" = nenhuma).
func set_tiles(tile_set: String, height_tex: Texture2D, river_tex: Texture2D) -> void:
	if tile_set == tiles.name_id:
		return
	var on := tile_set != "" and tiles.open(tile_set, RADIUS, height_tex, river_tex)
	if not on:
		tiles.close()
	_globe.scale = Vector3.ONE * (UNDER_TILES_SCALE if on else 1.0)


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
	var b := origin.dot(dir)
	var disc := b * b - (origin.length_squared() - RADIUS * RADIUS)
	if disc < 0.0 or -b - sqrt(disc) <= 0.0:
		return Vector3.ZERO
	return (origin + dir * (-b - sqrt(disc))).normalized()
