## Ruídos para os pincéis procedurais. Todos são funções da posição 3D na esfera (em km): sem emenda na longitude 180°,
## sem estiramento nos polos, e a mesma posição dá o mesmo valor para uma mesma semente.
## - fbm: ondulação suave e natural (colinas); 0..1, média ~0,5.
## - ridge: cristas finas de montanha (ridged multifractal + deslocamento de domínio); 0..1, cristas altas perto de 1.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")

const RIDGE_BASE_KM := 320.0
const RIDGE_OCTAVES := 6
const WARP_KM := 120.0   # deslocamento que faz as cristas serpentearem em vez de seguirem a grade do ruído
const HILL_BASE_KM := 100.0

var _ridge := FastNoiseLite.new()
var _fbm := FastNoiseLite.new()


func set_seed(seed_value: int) -> void:
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = RIDGE_OCTAVES
	_ridge.fractal_gain = 0.55
	_ridge.frequency = 1.0 / RIDGE_BASE_KM
	_ridge.domain_warp_enabled = true
	_ridge.domain_warp_amplitude = WARP_KM
	_ridge.domain_warp_frequency = 1.0 / (RIDGE_BASE_KM * 1.5)
	_ridge.seed = seed_value
	_fbm.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_fbm.fractal_type = FastNoiseLite.FRACTAL_FBM
	_fbm.fractal_octaves = 4
	_fbm.fractal_gain = 0.6
	_fbm.frequency = 1.0 / HILL_BASE_KM
	_fbm.seed = seed_value + 1013


## Ondulação 0..1 (média ~0,5) em n.
func fbm(n: Vector3) -> float:
	var p := n * EvronGeo.RADIUS_KM
	return clampf(_fbm.get_noise_3d(p.x, p.y, p.z) * 0.8 + 0.5, 0.0, 1.0)


## Crista 0..1 em n. O ruído medido vai de -0,67 a 0,92 (mediana 0,3): normalizado para essa faixa.
func ridge(n: Vector3) -> float:
	var p := n * EvronGeo.RADIUS_KM
	return clampf((_ridge.get_noise_3d(p.x, p.y, p.z) + 0.2) / 0.9, 0.0, 1.0)
