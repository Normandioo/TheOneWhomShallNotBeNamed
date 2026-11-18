## Geografia de Marte: conversões entre latitude/longitude e direção, e as regiões nomeadas.
## Ângulos em graus, longitude leste positiva.
## Convenção usada em todo o projeto (e nos shaders): dir = (cos(lat)·sin(lon), sin(lat), cos(lat)·cos(lon)).

const RADIUS_KM := 3389.5
const KM_PER_DEG := RADIUS_KM * PI / 180.0

# Coordenadas aproximadas das regiões reais.
const REGIONS := [
	{"name": "Tharsis", "lat": 0.0, "lon": -112.0},
	{"name": "Valles Marineris", "lat": -13.0, "lon": -65.0},
	{"name": "Acidalia Planitia", "lat": 47.0, "lon": -25.0},
	{"name": "Arabia Terra", "lat": 20.0, "lon": 5.0},
	{"name": "Hellas Planitia", "lat": -42.0, "lon": 70.0},
	{"name": "Utopia Planitia", "lat": 47.0, "lon": 118.0},
	{"name": "Elysium", "lat": 25.0, "lon": 147.0},
	{"name": "Arcadia Planitia", "lat": 47.0, "lon": -176.0},
	{"name": "Argyre Planitia", "lat": -50.0, "lon": -43.0},
	{"name": "Terra Cimmeria", "lat": -35.0, "lon": 145.0},
	{"name": "Noachis Terra", "lat": -45.0, "lon": -5.0},
]

const RIVAL_REGION := 6  # Elysium: colônia rival fixa, só para testar o modo político


static func dir(lat_deg: float, lon_deg: float) -> Vector3:
	return dir_rad(deg_to_rad(lat_deg), deg_to_rad(lon_deg))


static func dir_rad(lat: float, lon: float) -> Vector3:
	return Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))


## Retorna Vector2(lat, lon) em graus.
static func lat_lon(n: Vector3) -> Vector2:
	return Vector2(rad_to_deg(asin(clampf(n.y, -1.0, 1.0))), rad_to_deg(atan2(n.x, n.z)))


## Direção do centro de cada região, na ordem de REGIONS (o shader recebe esta lista).
static func region_dirs() -> PackedVector3Array:
	var dirs := PackedVector3Array()
	for r in REGIONS:
		dirs.append(dir(r["lat"], r["lon"]))
	return dirs


## Índice da região mais próxima da direção n.
static func nearest_region(n: Vector3) -> int:
	var best := 0
	var best_dot := -2.0
	for i in REGIONS.size():
		var r: Dictionary = REGIONS[i]
		var d := n.dot(dir(r["lat"], r["lon"]))
		if d > best_dot:
			best_dot = d
			best = i
	return best
