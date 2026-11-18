## As colônias em Marte e quem é dono de cada região. Põe os modelos na esfera de Marte da cena do espaço e
## escolhe o que aparece pelo zoom: marcador de longe, modelos de perto.

const MarsGeo = preload("res://scripts/data/mars_geo.gd")
const ColonyModel = preload("res://scripts/view/colony_model.gd")

enum Owner { NEUTRAL, PLAYER, RIVAL }

const OWNER_COLORS := [Vector3(0.35, 0.3, 0.28), Vector3(0.2, 0.55, 1.0), Vector3(1.0, 0.3, 0.2)]
const LOD_DIST := 2.5  # câmera mais perto que isso (em raios de Marte): aparecem os modelos das colônias

var region_owner: Array[int] = []  # Owner de cada região de MarsGeo.REGIONS

var _planet: Node3D
var _radius := 1.0
var _colonies: Array[Dictionary] = []  # {models, marker, dir}


## `planet` é o nó da esfera de Marte; `radius` o raio dela na cena. O referencial do nó é o do corpo (MarsGeo).
func setup(planet: Node3D, radius: float) -> void:
	_planet = planet
	_radius = radius
	for r in MarsGeo.REGIONS:
		region_owner.append(Owner.NEUTRAL)
	region_owner[MarsGeo.RIVAL_REGION] = Owner.RIVAL


func is_rival(region: int) -> bool:
	return region_owner[region] == Owner.RIVAL


## Cor do dono de cada região, na ordem de MarsGeo.REGIONS (vai para o shader do mapa político).
func owner_colors() -> PackedVector3Array:
	var cols := PackedVector3Array()
	for o in region_owner:
		cols.append(OWNER_COLORS[o])
	return cols


## Direção de cada colônia fundada.
func directions() -> Array[Vector3]:
	var dirs: Array[Vector3] = []
	for c in _colonies:
		dirs.append(c["dir"])
	return dirs


## Funda uma colônia na direção n: a região passa a ser do jogador.
func found(n: Vector3) -> void:
	region_owner[MarsGeo.nearest_region(n)] = Owner.PLAYER
	# Eixo Y local aponta para fora do planeta; tudo é feito para um planeta de raio 1 e escalado pelo raio.
	var root := Node3D.new()
	_planet.add_child(root)
	var x := n.cross(Vector3.UP if absf(n.y) < 0.99 else Vector3.RIGHT).normalized()
	root.transform = Transform3D(Basis(x, n, x.cross(n)).scaled(Vector3.ONE * _radius), n * _radius)
	var models := ColonyModel.build()
	models.scale = Vector3.ONE * 0.5  # pequenos como peças de mapa de grand strategy
	root.add_child(models)
	var marker := ColonyModel.build_marker(root)
	_colonies.append({"models": models, "marker": marker, "dir": n})


## Mostra o que cabe no zoom atual: `dist` é a distância da câmera ao centro de Marte, em raios dele.
func apply_distance(dist: float) -> void:
	var near := dist < LOD_DIST
	for c in _colonies:
		c["models"].visible = near
		c["marker"].visible = not near


## Há colônia mostrando os modelos (de perto) ou só o marcador (de longe)? Para os testes.
func showing_models() -> bool:
	return not _colonies.is_empty() and _colonies[0]["models"].visible
