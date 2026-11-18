## Geografia de Evron: o planeta (esfera) e as conversões entre latitude/longitude, direção e pixel do mapa.
## Ângulos em graus, longitude leste positiva, de -180 a 180.
## Convenção usada em todo o projeto (e nos shaders): dir = (cos(lat)·sin(lon), sin(lat), cos(lat)·cos(lon)).
## Mapas equiretangulares: u = lon/360 + 0.5 (coluna 0 = -180°), v = 0.5 - lat/180 (linha 0 = polo norte).

const RADIUS_KM := 6371.0  # a Terra (definido pelo autor em 18/11/2026; antes 8.282,3 km); esfera perfeita
const KM_PER_DEG := RADIUS_KM * PI / 180.0  # ≈ 111,2 km


static func dir(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))


## Retorna Vector2(lat, lon) em graus.
static func lat_lon(n: Vector3) -> Vector2:
	return Vector2(rad_to_deg(asin(clampf(n.y, -1.0, 1.0))), rad_to_deg(atan2(n.x, n.z)))


## Pixel do mapa equiretangular `size` que contém a direção n.
static func pixel(n: Vector3, size: Vector2i) -> Vector2i:
	var ll := lat_lon(n)
	return Vector2i(
		posmod(int(floorf((ll.y / 360.0 + 0.5) * size.x)), size.x),
		clampi(int(floorf((0.5 - ll.x / 180.0) * size.y)), 0, size.y - 1))


## Distância pela superfície (círculo máximo) entre duas direções, em km.
## atan2 em vez de acos: o Vector3 é float32, e acos perto de 1 erra quilômetros em distâncias curtas.
static func distance_km(a: Vector3, b: Vector3) -> float:
	return RADIUS_KM * atan2(a.cross(b).length(), a.dot(b))
