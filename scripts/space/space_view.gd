extends Node
## A vista do jogo: o sistema solar em 3D, com Marte (o planeta do jogo) em foco. Gire a câmera em volta de um
## corpo e dê zoom da superfície até o sistema solar inteiro: órbitas dos planetas e da Lua, cinturões de asteroides.
## Usa o relógio do jogo (a data é a do jogo) e o material de Marte do jogo (mares, gelo, nuvens, modos de mapa).
## Clicar na superfície de Marte escolhe um ponto (`surface_clicked`); clicar em outro corpo foca nele.

const Ephemeris = preload("res://scripts/sim/ephemeris.gd")
const GameClock = preload("res://scripts/sim/game_clock.gd")
const SolarBodies = preload("res://scripts/sim/solar_bodies.gd")
const SpaceScene = preload("res://scripts/space/space_scene.gd")
const SpaceCamera = preload("res://scripts/space/space_camera.gd")
const SpaceOverlay = preload("res://scripts/space/space_overlay.gd")
const SpaceHud = preload("res://scripts/space/space_hud.gd")

## O jogador clicou na superfície de Marte: direção do ponto, no referencial de Marte (lat/lon de MarsGeo).
signal surface_clicked(direction: Vector3)

const PIXEL_SHRINK := 2
const MARS_PICK_PX := 30.0  # Marte com raio maior que isso na tela: o clique escolhe um ponto da superfície
const Id = SolarBodies.Id

var jd := Ephemeris.J2000

var scene: SpaceScene
var camera: SpaceCamera
var overlay: SpaceOverlay
var hud: SpaceHud
var _clock: GameClock
var _positions: Array = []
var _mars_material: ShaderMaterial
var _spins := true  # devagar o bastante para ver os planetas girando (ver SpaceScene.place)


## Chamar antes de add_child: o relógio do jogo e o material de Marte.
func setup(clock: GameClock, mars_material: ShaderMaterial) -> void:
	_clock = clock
	_mars_material = mars_material


func _ready() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = PIXEL_SHRINK  # fixo em 2x: ruído fino (nuvem) vira bagunça em fatores maiores
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	container.add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR  # o lado escuro de Marte
	env.ambient_light_color = Color(0.45, 0.3, 0.35)
	env.ambient_light_energy = 0.35
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	scene = SpaceScene.new()
	scene.mars_material = _mars_material
	viewport.add_child(scene)
	camera = SpaceCamera.new()
	viewport.add_child(camera)

	overlay = SpaceOverlay.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	hud = SpaceHud.new()
	add_child(hud)
	hud.focus_requested.connect(func(id: int) -> void: camera.focus_on(id, _positions))
	hud.overview_requested.connect(func() -> void: camera.overview(_positions))
	camera.clicked.connect(_on_click)

	jd = Ephemeris.jd_from_year(_clock.year)
	_positions = SolarBodies.all_positions(jd)
	camera.focus_id = Id.MARS
	camera.target_dist = SolarBodies.radius_units(Id.MARS) * SpaceCamera.FOCUS_ZOOM
	var sun_dir := SolarBodies.relative_scene(_positions[Id.SUN], _positions[Id.MARS]).normalized()
	camera.yaw = atan2(sun_dir.x, sun_dir.z) + 0.8  # um pouco ao lado do Sol: Marte aparece meio iluminado
	camera.snap()
	update(0.0)


## Um quadro: a data do jogo -> posições -> foco -> câmera -> cena -> marcadores.
func update(delta: float) -> void:
	jd = Ephemeris.jd_from_year(_clock.year)
	_positions = SolarBodies.all_positions(jd)
	camera.advance(delta)
	var origin := camera.focus_position(_positions)
	var days_per_second := _clock.time_scale * GameClock.YEARS_PER_SECOND * 365.25
	if days_per_second != 0.0:  # em pausa fica como estava: pausar não faz Marte e a Terra girarem de repente
		_spins = absf(days_per_second) <= SpaceScene.SPIN_MAX_DAYS_PER_SECOND
	scene.place(jd, _positions, origin, _spins, camera.cam.global_position, camera.body_range())
	var px_scale := camera.pixel_scale()
	scene.fade(camera.cam.global_position, px_scale, camera.focus_id, camera.dist)
	var points := {}
	for id in Id.size():
		points[id] = scene.body_position(id)
	overlay.focus_id = camera.focus_id
	overlay.update_frame(camera.cam, px_scale, PIXEL_SHRINK, points)


## A atmosfera de Marte (controle 0..1): engrossa o halo em volta do planeta.
func set_atmosphere(atm: float) -> void:
	scene.set_atmosphere(atm)


## Quem recebe a entrada é o Main (fora do SubViewport, que não recebe mouse); ele repassa para cá.
func handle_input(e: InputEvent) -> void:
	camera.handle_input(e)


## Distância da câmera ao centro do corpo, em raios dele.
func distance_in_radii(id: int) -> float:
	return camera.cam.global_position.distance_to(scene.body_position(id)) / SolarBodies.radius_units(id)


## Põe a câmera sobre o ponto n da superfície de Marte (direção no referencial do planeta), a `zoom` raios.
func look_at_surface(n: Vector3, zoom := 3.0) -> void:
	camera.focus_on(Id.MARS, _positions, zoom)
	var world := scene.body_basis(Id.MARS) * n  # a orientação que está na tela
	camera.yaw = atan2(world.x, world.z)
	camera.pitch = asin(clampf(world.y, -1.0, 1.0))
	camera.snap()


## Põe a câmera do lado iluminado de Marte (um pouco ao lado do Sol), a `zoom` raios.
func look_from_sun(zoom := 3.0) -> void:
	camera.focus_on(Id.MARS, _positions, zoom)
	var sun := SolarBodies.relative_scene(_positions[Id.SUN], _positions[Id.MARS]).normalized()
	camera.yaw = atan2(sun.x, sun.z) + 0.5
	camera.pitch = asin(clampf(sun.y, -1.0, 1.0))
	camera.snap()


func _on_click(screen_pos: Vector2) -> void:
	var hit := _pick_mars_surface(screen_pos)
	if hit != Vector3.ZERO:
		surface_clicked.emit(hit)
		return
	var id := overlay.pick(screen_pos)
	if id >= 0:
		camera.focus_on(id, _positions)


## O ponto de Marte sob a posição da tela (direção no referencial do planeta), ou Vector3.ZERO se Marte está
## pequeno demais na tela ou o raio não o toca.
func _pick_mars_surface(screen_pos: Vector2) -> Vector3:
	var center := scene.body_position(Id.MARS)
	var radius := SolarBodies.radius_units(Id.MARS)
	var cam := camera.cam
	var apparent := radius / maxf(cam.global_position.distance_to(center), 1e-6) * camera.pixel_scale() * PIXEL_SHRINK
	if apparent < MARS_PICK_PX:
		return Vector3.ZERO
	var p := screen_pos / float(PIXEL_SHRINK)
	var origin := cam.project_ray_origin(p) - center
	var dir := cam.project_ray_normal(p)
	var b := origin.dot(dir)
	var disc := b * b - (origin.length_squared() - radius * radius)
	if disc < 0.0 or -b - sqrt(disc) <= 0.0:
		return Vector3.ZERO
	var point := origin + dir * (-b - sqrt(disc))
	return scene.body_basis(Id.MARS).transposed() * point.normalized()
