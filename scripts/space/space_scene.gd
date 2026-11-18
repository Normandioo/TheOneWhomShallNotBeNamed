extends Node3D
## O mundo 3D do modo espaço: os corpos, as órbitas e os cinturões de asteroides.
## Não sabe de câmera nem de tempo: recebe o dia, as posições e o ponto que fica no centro da cena (o foco),
## e põe tudo no lugar. Duas etapas por quadro: place() posiciona, fade() ajusta a transparência pelo zoom.
##
## Origem flutuante: o foco da câmera é sempre a origem da cena, e tudo é posicionado em relação a ele (a conta é
## feita em double, ver SolarBodies). Sem isso, a Terra a 1 UA do Sol teria ~20 km de tremor em float32.

const Ephemeris = preload("res://scripts/sim/ephemeris.gd")
const SolarBodies = preload("res://scripts/sim/solar_bodies.gd")
const BeltGenerator = preload("res://scripts/sim/belt_generator.gd")
const SpaceTextures = preload("res://scripts/space/space_textures.gd")
const Physics = preload("res://scripts/sim/mars_physics.gd")
const MarsGeo = preload("res://scripts/data/mars_geo.gd")

const BODY_SHADER = preload("res://shaders/space_body.gdshader")
const ORBIT_SHADER = preload("res://shaders/space_orbit.gdshader")
const BELT_SHADER = preload("res://shaders/space_belt.gdshader")
const ATMOSPHERE_SHADER = preload("res://shaders/space_atmosphere.gdshader")

# O halo de Marte tem a espessura real multiplicada por isto: com 110 km (Marte hoje) a atmosfera real é uma linha
# de 1 pixel, e o jogador precisa ver a diferença quando ela chega a 330 km.
const ATMOSPHERE_EXAGGERATION := 3.0
const ATMOSPHERE_DUST := Color(0.9, 0.55, 0.35)
const ATMOSPHERE_SKY := Color(0.4, 0.65, 1.0)
const ORBIT_POINTS := 256
const MOON_ORBIT_POINTS := 192
const MARS_MOON_ORBIT_COLOR := Color(0.7, 0.6, 0.55, 0.7)
const HUGE_ORBIT_PX := Vector2(200.0, 400.0)  # raio da órbita na tela (pixels): acima disso ela passaria o quadro, e some
const MOON_SIDEREAL_DAYS := 27.321662
const PLANET_REBUILD_DAYS := 7300.0  # a órbita muda devagar: refazer a cada ~20 anos basta
const MOON_REBUILD_DAYS := 3.0       # a órbita da Lua muda mais rápido (o nó dá a volta em 18,6 anos)
const SPIN_MAX_DAYS_PER_SECOND := 0.5  # acima disso a Terra pararia de girar na tela (ela piscaria), então fica parada
const MOON_ORBIT_COLOR := Color(0.75, 0.75, 0.8, 0.7)
const PLANET_ORBIT_ALPHA := 0.6
const BELT_FADE_UNITS := Vector2(75000.0, 300000.0)  # com a câmera mais perto que isso do foco (0,5 a 2 UA), os cinturões somem
const ORBIT_FOCUS_FADE := Vector2(0.03, 0.2)  # zoom / distância do foco à órbita: abaixo disso a linha está longe demais para importar

# count: pontos; size: lado do ponto em pixels (da tela já pixelada).
const BELTS := [
	{"name": "Cinturão principal", "make": "main_belt", "count": 22000, "seed": 11, "color": Color(0.80, 0.72, 0.62), "size": 1.0},
	{"name": "Troianos de Júpiter", "make": "jupiter_trojans", "count": 3000, "seed": 22, "color": Color(0.55, 0.75, 0.6), "size": 1.0},
	{"name": "Cinturão de Kuiper", "make": "kuiper_belt", "count": 14000, "seed": 33, "color": Color(0.5, 0.6, 0.8), "size": 1.0},
]

## O material de Marte do jogo (terreno, mares, gelo, nuvens, modos de mapa): o shader dele é iluminado por uma luz do
## Godot, então a cena tem uma luz apontando do Sol para Marte. Definir antes de add_child.
var mars_material: ShaderMaterial

var _bodies := {}          # Id -> MeshInstance3D
var _real := {}            # Id -> Vector3: posição real relativa ao foco (o nó pode estar mais perto, ver place)
var _basis := {}           # Id -> Basis: orientação do corpo (sem a escala de place)
var _materials := {}       # Id -> ShaderMaterial
var _planet_orbits := {}   # Id -> {"node", "material", "built_jd", "a"}
var _moon_orbit := {}
var _mars_moon_orbits := {}  # Id (Fobos, Deimos) -> {"node", "material", "built_jd", "a", "points"}
var _belts: Array = []     # {"node", "material"}
var _orbit_root: Node3D    # centrado no Sol
var _last_jd := 0.0
var _atmosphere_mat: ShaderMaterial
var _sun_light: DirectionalLight3D


func _ready() -> void:
	_orbit_root = Node3D.new()
	add_child(_orbit_root)
	_sun_light = DirectionalLight3D.new()  # só o Marte do mapa usa luz do Godot; os outros corpos têm a própria conta
	_sun_light.light_color = Color(1.0, 0.85, 0.7)
	_sun_light.light_energy = 1.4
	add_child(_sun_light)
	_build_bodies()
	_build_planet_orbits()
	_build_moon_orbit()
	_build_mars_moon_orbits()
	_build_belts()


## Posições na cena (relativas ao foco) dos corpos, na ordem de SolarBodies.Id.
func body_position(id: int) -> Vector3:
	return _real[id]


## Orientação do corpo (eixos leste, polo, meridiano zero); identidade nos que ainda não giram.
func body_basis(id: int) -> Basis:
	return _basis.get(id, Basis.IDENTITY)


## O nó 3D do corpo (as colônias de Marte são filhas do nó dele).
func body_node(id: int) -> MeshInstance3D:
	return _bodies[id]


## Põe tudo no lugar para o dia jd. `positions` = SolarBodies.all_positions(jd); `origin` = foco (UA).
## `spins` = o tempo está devagar o bastante para ver a Terra e Marte girando (ver SPIN_MAX_DAYS_PER_SECOND);
## senão eles ficam parados, porque girando rápido demais piscariam.
## Corpos a mais de `max_range` da câmera (`cam_pos`) ficam a essa distância, na mesma direção e encolhidos
## na mesma proporção: o tamanho na tela não muda, mas o plano de corte da câmera pode ser bem mais curto.
func place(jd: float, positions: Array, origin: PackedFloat64Array, spins: bool, cam_pos: Vector3, max_range: float) -> void:
	_last_jd = jd
	var sun_rel := SolarBodies.relative_scene(positions[SolarBodies.Id.SUN], origin)
	for id in SolarBodies.Id.size():
		var node: MeshInstance3D = _bodies[id]
		var real := SolarBodies.relative_scene(positions[id], origin)
		_real[id] = real
		var to_body := real - cam_pos
		var distance := to_body.length()
		if distance > max_range:
			node.position = cam_pos + to_body / distance * max_range
			node.scale = Vector3.ONE * (max_range / distance)
		else:
			node.position = real
			node.scale = Vector3.ONE
		if id == SolarBodies.Id.MARS and mars_material != null:
			_sun_light.basis = Basis.looking_at(-(sun_rel - real).normalized())  # a luz anda do Sol para Marte
			_atmosphere_mat.set_shader_parameter("sun_dir", (sun_rel - real).normalized())
		elif id != SolarBodies.Id.SUN:
			_materials[id].set_shader_parameter("sun_dir", (sun_rel - real).normalized())
	var earth_node: MeshInstance3D = _bodies[SolarBodies.Id.EARTH]
	var moon_node: MeshInstance3D = _bodies[SolarBodies.Id.MOON]
	# Parado: a Terra mostra Greenwich ao meio-dia, e Marte o mesmo lado (um dia sideral inteiro de cada vez).
	var earth_jd := jd if spins else floorf(jd)
	var mars_days := SolarBodies.MARS_SIDEREAL_DAYS
	var mars_jd := jd if spins else Ephemeris.J2000 + floorf((jd - Ephemeris.J2000) / mars_days) * mars_days
	var mars_node: MeshInstance3D = _bodies[SolarBodies.Id.MARS]
	_basis[SolarBodies.Id.EARTH] = SolarBodies.earth_orientation(earth_jd)
	_basis[SolarBodies.Id.MARS] = SolarBodies.mars_orientation(mars_jd)
	_basis[SolarBodies.Id.MOON] = SolarBodies.moon_orientation(_real[SolarBodies.Id.MOON] - _real[SolarBodies.Id.EARTH])
	earth_node.basis = _basis[SolarBodies.Id.EARTH] * Basis.from_scale(earth_node.scale)
	mars_node.basis = _basis[SolarBodies.Id.MARS] * Basis.from_scale(mars_node.scale)
	moon_node.basis = _basis[SolarBodies.Id.MOON] * Basis.from_scale(moon_node.scale)

	_orbit_root.position = sun_rel
	for entry in _belts:
		entry["node"].position = sun_rel
		entry["material"].set_shader_parameter("days", jd - Ephemeris.J2000)
	_moon_orbit["node"].position = _real[SolarBodies.Id.EARTH]
	for id in _mars_moon_orbits:
		_mars_moon_orbits[id]["node"].position = _real[SolarBodies.Id.MARS]
		if absf(jd - _mars_moon_orbits[id]["built_jd"]) > PLANET_REBUILD_DAYS:
			_rebuild_mars_moon_orbit(id, jd)
	for id in _planet_orbits:
		if absf(jd - _planet_orbits[id]["built_jd"]) > PLANET_REBUILD_DAYS:
			_rebuild_planet_orbit(id, jd)
	if absf(jd - _moon_orbit["built_jd"]) > MOON_REBUILD_DAYS:
		_rebuild_moon_orbit(jd)


## Transparência das órbitas e dos cinturões pelo zoom. `px_scale` = pixels da tela por unidade a 1 unidade de
## distância (altura da tela / (2·tan(fov/2))), `focus_dist` = distância da câmera ao foco, em unidades.
func fade(cam_pos: Vector3, px_scale: float, focus_id: int, focus_dist: float) -> void:
	for id in _planet_orbits:
		var entry: Dictionary = _planet_orbits[id]
		var alpha := _orbit_alpha(entry, _orbit_root.position, cam_pos, px_scale, focus_dist)
		if id == focus_id:  # a linha que passa pelo corpo em foco atrapalharia de perto
			alpha *= smoothstep(1.5, 8.0, focus_dist / SolarBodies.radius_units(id))
		entry["material"].set_shader_parameter("alpha", alpha)
	var moon_alpha := _orbit_alpha(_moon_orbit, _moon_orbit["node"].position, cam_pos, px_scale, focus_dist)
	if focus_id == SolarBodies.Id.MOON:
		moon_alpha *= smoothstep(1.5, 8.0, focus_dist / SolarBodies.radius_units(focus_id))
	_moon_orbit["material"].set_shader_parameter("alpha", moon_alpha)
	for id in _mars_moon_orbits:
		var entry: Dictionary = _mars_moon_orbits[id]
		var center: Vector3 = entry["node"].position
		var apparent_px: float = entry["a"] / maxf(cam_pos.distance_to(center), 1e-6) * px_scale
		var alpha := _orbit_alpha(entry, center, cam_pos, px_scale, focus_dist) * (1.0 - smoothstep(HUGE_ORBIT_PX.x, HUGE_ORBIT_PX.y, apparent_px))
		if id == focus_id:
			alpha *= smoothstep(1.5, 8.0, focus_dist / SolarBodies.radius_units(id))
		entry["material"].set_shader_parameter("alpha", alpha)
	var belt_alpha := smoothstep(BELT_FADE_UNITS.x, BELT_FADE_UNITS.y, focus_dist)
	for entry in _belts:
		entry["material"].set_shader_parameter("alpha", belt_alpha)


## Transparência atual (0..1) da órbita da Lua, de uma órbita de planeta e dos cinturões (para os testes).
func moon_orbit_alpha() -> float:
	return _moon_orbit["material"].get_shader_parameter("alpha")


func mars_moon_orbit_alpha(id: int) -> float:
	return _mars_moon_orbits[id]["material"].get_shader_parameter("alpha")


func planet_orbit_alpha(id: int) -> float:
	return _planet_orbits[id]["material"].get_shader_parameter("alpha")


## A atmosfera de Marte (controle 0..1 do jogo): a espessura e a cor do halo seguem a altura do topo.
func set_atmosphere(atm: float) -> void:
	var radius := SolarBodies.radius_units(SolarBodies.Id.MARS)
	var top_km := Physics.atmosphere_top_km(atm)
	var sky := clampf(atm, 0.0, 1.0)
	_atmosphere_mat.set_shader_parameter("planet_radius", radius)
	_atmosphere_mat.set_shader_parameter("top", radius * top_km * ATMOSPHERE_EXAGGERATION / MarsGeo.RADIUS_KM)
	_atmosphere_mat.set_shader_parameter("tint", ATMOSPHERE_DUST.lerp(ATMOSPHERE_SKY, sky))
	_atmosphere_mat.set_shader_parameter("strength", 0.3 + 0.6 * sky)


## Espessura visível do halo de Marte, em unidades do objeto (para os testes).
func atmosphere_thickness() -> float:
	return _atmosphere_mat.get_shader_parameter("top")


## O corpo tem textura ou relevo (e não é só uma esfera de uma cor)?
func has_surface(id: int) -> bool:
	return id == SolarBodies.Id.MARS and mars_material != null or _materials[id].get_shader_parameter("use_tex") == true


func belt_alpha() -> float:
	return _belts[0]["material"].get_shader_parameter("alpha")


## Transparência de uma órbita: some quando é pequena demais na tela, e quando está tão longe do foco, comparado
## ao zoom, que seria só uma linha solta cruzando a tela (as órbitas de Marte e Júpiter vistas de perto da Terra).
func _orbit_alpha(entry: Dictionary, center: Vector3, cam_pos: Vector3, px_scale: float, focus_dist: float) -> float:
	var apparent: float = entry["a"] / maxf(cam_pos.distance_to(center), 1.0) * px_scale
	var nearest := INF
	for p in entry["points"]:
		nearest = minf(nearest, (p + center).length_squared())
	return smoothstep(2.0, 9.0, apparent) * smoothstep(ORBIT_FOCUS_FADE.x, ORBIT_FOCUS_FADE.y, focus_dist / maxf(sqrt(nearest), 1.0))


func _build_bodies() -> void:
	for id in SolarBodies.Id.size():
		var def: Dictionary = SolarBodies.BODIES[id]
		var radius := SolarBodies.radius_units(id)
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 96 if radius > 0.5 else 24  # as luas minúsculas de Marte não precisam de tanta malha
		mesh.rings = 48 if radius > 0.5 else 12
		var mat := ShaderMaterial.new()
		mat.shader = BODY_SHADER
		mat.set_shader_parameter("base_color", def["color"])
		mat.set_shader_parameter("emissive", id == SolarBodies.Id.SUN)
		mat.set_shader_parameter("atmosphere", def.get("atmosphere", 0.0))
		if def.has("texture"):
			var tex := SpaceTextures.load_texture(def["texture"])
			if tex != null:
				mat.set_shader_parameter("albedo_tex", tex)
				mat.set_shader_parameter("use_tex", true)
		if def.has("height"):
			var height := SpaceTextures.load_texture(def["height"])
			if height != null:
				mat.set_shader_parameter("height_tex", height)
				mat.set_shader_parameter("use_height", true)
				mat.set_shader_parameter("height_min", def["height_min"])
				mat.set_shader_parameter("height_range", def["height_range"])
				mat.set_shader_parameter("relief", def["relief"])
				mat.set_shader_parameter("body_radius_m", float(def["radius_km"]) * 1000.0)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = mars_material if id == SolarBodies.Id.MARS and mars_material != null else mat
		node.name = def["name"]
		add_child(node)
		_bodies[id] = node
		_materials[id] = mat
		if id == SolarBodies.Id.MARS:
			_build_atmosphere(node, radius)


## A casca do halo, filha de Marte (herda posição, escala e rotação). Maior que o planeta o bastante para o halo
## do ar mais alto possível (com "Permitir extremos").
func _build_atmosphere(mars: MeshInstance3D, radius: float) -> void:
	var shell := SphereMesh.new()
	shell.radius = radius * 1.5
	shell.height = radius * 3.0
	shell.radial_segments = 64
	shell.rings = 32
	_atmosphere_mat = ShaderMaterial.new()
	_atmosphere_mat.shader = ATMOSPHERE_SHADER
	var node := MeshInstance3D.new()
	node.mesh = shell
	node.material_override = _atmosphere_mat
	node.name = "Atmosfera de Marte"
	mars.add_child(node)
	set_atmosphere(0.0)


func _line_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ORBIT_SHADER
	mat.set_shader_parameter("line_color", color)
	mat.set_shader_parameter("alpha", 0.0)
	return mat


func _build_planet_orbits() -> void:
	for id in range(SolarBodies.Id.MERCURY, SolarBodies.Id.NEPTUNE + 1):
		var color: Color = SolarBodies.BODIES[id]["color"]
		color.a = PLANET_ORBIT_ALPHA
		var node := MeshInstance3D.new()
		node.mesh = ArrayMesh.new()
		node.material_override = _line_material(color)
		node.name = "Órbita " + SolarBodies.body_name(id)
		_orbit_root.add_child(node)
		_planet_orbits[id] = {"node": node, "material": node.material_override, "built_jd": 0.0,
			"a": Ephemeris.PLANETS[id - 1][0] * SolarBodies.UNIT_PER_AU, "points": PackedVector3Array()}
		_rebuild_planet_orbit(id, Ephemeris.J2000)


func _rebuild_planet_orbit(id: int, jd: float) -> void:
	var raw := Ephemeris.orbit_samples(id - 1, jd, ORBIT_POINTS)
	var points := PackedVector3Array()
	for k in raw.size() / 3:
		points.append(SolarBodies.to_scene(PackedFloat64Array([raw[3 * k], raw[3 * k + 1], raw[3 * k + 2]])))
	_set_line(_planet_orbits[id]["node"], points)
	_planet_orbits[id]["points"] = points
	_planet_orbits[id]["built_jd"] = jd


func _build_moon_orbit() -> void:
	var node := MeshInstance3D.new()
	node.mesh = ArrayMesh.new()
	node.material_override = _line_material(MOON_ORBIT_COLOR)
	node.name = "Órbita da Lua"
	add_child(node)
	_moon_orbit = {"node": node, "material": node.material_override, "built_jd": 0.0,
		"a": 384.4, "points": PackedVector3Array()}  # semieixo maior médio, em unidades (1000 km)
	_rebuild_moon_orbit(Ephemeris.J2000)


## A órbita da Lua em volta da Terra: a trajetória real de uma volta (27,3 dias) a partir de jd.
func _rebuild_moon_orbit(jd: float) -> void:
	var points := PackedVector3Array()
	for k in MOON_ORBIT_POINTS + 1:
		points.append(SolarBodies.km_to_scene(Ephemeris.moon_position_km(jd + MOON_SIDEREAL_DAYS * k / MOON_ORBIT_POINTS)))
	_set_line(_moon_orbit["node"], points)
	_moon_orbit["points"] = points
	_moon_orbit["built_jd"] = jd


## As órbitas de Fobos e Deimos em volta de Marte (no lugar de Marte).
func _build_mars_moon_orbits() -> void:
	for id in SolarBodies.MARS_MOONS:
		var node := MeshInstance3D.new()
		node.mesh = ArrayMesh.new()
		node.material_override = _line_material(MARS_MOON_ORBIT_COLOR)
		node.name = "Órbita de " + SolarBodies.body_name(id)
		add_child(node)
		_mars_moon_orbits[id] = {"node": node, "material": node.material_override, "built_jd": 0.0,
			"a": SolarBodies.MARS_MOONS[id]["a_km"] / SolarBodies.UNIT_KM, "points": PackedVector3Array()}
		_rebuild_mars_moon_orbit(id, Ephemeris.J2000)


func _rebuild_mars_moon_orbit(id: int, jd: float) -> void:
	var period: float = SolarBodies.MARS_MOONS[id]["period"]
	var steps := ORBIT_POINTS / 2
	var points := PackedVector3Array()
	for k in steps + 1:
		points.append(SolarBodies.mars_moon_offset(id, jd + period * k / steps))
	_set_line(_mars_moon_orbits[id]["node"], points)
	_mars_moon_orbits[id]["points"] = points
	_mars_moon_orbits[id]["built_jd"] = jd


func _set_line(node: MeshInstance3D, points: PackedVector3Array) -> void:
	var mesh: ArrayMesh = node.mesh
	mesh.clear_surfaces()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)


func _build_belts() -> void:
	for spec in BELTS:
		var data := _generate_belt(spec)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data["orbit"]
		arrays[Mesh.ARRAY_TEX_UV] = data["angles"]
		arrays[Mesh.ARRAY_TEX_UV2] = data["phase"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
		mesh.custom_aabb = AABB(Vector3.ONE * -1e8, Vector3.ONE * 2e8)  # os pontos se movem no shader
		var mat := ShaderMaterial.new()
		mat.shader = BELT_SHADER
		mat.set_shader_parameter("point_color", spec["color"])
		mat.set_shader_parameter("point_size", spec["size"])
		mat.set_shader_parameter("alpha", 0.0)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = mat
		node.name = spec["name"]
		add_child(node)
		_belts.append({"node": node, "material": mat})


func _generate_belt(spec: Dictionary) -> Dictionary:
	match spec["make"]:
		"main_belt":
			return BeltGenerator.main_belt(spec["count"], spec["seed"])
		"jupiter_trojans":
			return BeltGenerator.jupiter_trojans(spec["count"], spec["seed"])
		"kuiper_belt":
			return BeltGenerator.kuiper_belt(spec["count"], spec["seed"])
	push_error("cinturão desconhecido: " + str(spec["make"]))
	return {}
