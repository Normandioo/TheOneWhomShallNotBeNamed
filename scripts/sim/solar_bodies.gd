## Os corpos do sistema solar que o jogo mostra: nome, tamanho, cor, e onde estão em cada dia.
## Posições absolutas são PackedFloat64Array [x, y, z] em UA, eclíptica J2000, centradas no Sol (ver Ephemeris).
## Para desenhar, usa-se sempre a posição RELATIVA a um ponto (o foco da câmera), calculada em double antes de
## virar Vector3: assim a Terra, a 1 UA do Sol, ainda tem precisão de metros quando a câmera está a 10 km dela.
##
## Convenção da cena: 1 unidade = 1000 km, e os eixos do Godot (Y para cima) são x, z, -y da eclíptica.

const Ephemeris = preload("res://scripts/sim/ephemeris.gd")

enum Id { SUN, MERCURY, VENUS, EARTH, MARS, JUPITER, SATURN, URANUS, NEPTUNE, MOON, PHOBOS, DEIMOS }

const UNIT_KM := 1000.0
const UNIT_PER_AU := Ephemeris.AU_KM / UNIT_KM

## Na ordem de Id. "texture" e "height" (altitude em tons de cinza, de height_min a height_min + height_range metros) só existem para a Terra e a Lua; Marte usa o material do globo do mapa (ver SpaceScene.mars_material); os outros são esferas de uma cor.
const BODIES := [
	{"name": "Sol", "radius_km": 696340.0, "color": Color(1.0, 0.86, 0.45)},
	{"name": "Mercúrio", "radius_km": 2439.7, "color": Color(0.62, 0.57, 0.52)},
	{"name": "Vênus", "radius_km": 6051.8, "color": Color(0.91, 0.80, 0.55)},
	{"name": "Terra", "radius_km": 6371.0, "color": Color(0.25, 0.45, 0.8), "texture": "res://data/space/earth_2048.jpg",
		"atmosphere": 1.0, "height": "res://data/space/earth_height_5400.jpg", "height_min": 0.0, "height_range": 8848.0, "relief": 30.0},  # relief: a Terra tem inclinações suaves na grade e precisa de mais exagero que a Lua (12)
	{"name": "Marte", "radius_km": 3389.5, "color": Color(0.80, 0.42, 0.26)},
	{"name": "Júpiter", "radius_km": 69911.0, "color": Color(0.82, 0.67, 0.52)},
	{"name": "Saturno", "radius_km": 58232.0, "color": Color(0.87, 0.77, 0.56)},
	{"name": "Urano", "radius_km": 25362.0, "color": Color(0.62, 0.86, 0.90)},
	{"name": "Netuno", "radius_km": 24622.0, "color": Color(0.30, 0.42, 0.92)},
	{"name": "Lua", "radius_km": 1737.4, "color": Color(0.66, 0.65, 0.63), "texture": "res://data/space/moon_1k.jpg",
		"height": "res://data/space/moon_height_8bit.jpg", "height_min": -9100.0, "height_range": 19900.0, "relief": 12.0},
	{"name": "Fobos", "radius_km": 11.1, "color": Color(0.52, 0.47, 0.43)},   # na verdade um batata de 27x22x18 km: esfera por ora
	{"name": "Deimos", "radius_km": 6.2, "color": Color(0.62, 0.57, 0.50)},
]

## Luas de Marte: órbitas keplerianas no plano do equador do planeta. Semieixo, excentricidade, inclinação sobre o
## equador e período são reais; a fase em J2000 (m0) e o argumento do periélio são ilustrativos, e a precessão do
## plano (Fobos dá uma volta em ~2 anos) não está no modelo.
const MARS_MOONS := {
	Id.PHOBOS: {"a_km": 9376.0, "e": 0.0151, "inc": 1.093, "period": 0.31891023, "m0": 100.0, "peri": 150.0},
	Id.DEIMOS: {"a_km": 23463.2, "e": 0.00033, "inc": 0.93, "period": 1.2624407, "m0": 215.0, "peri": 60.0},
}


## O corpo em volta do qual `id` orbita (a Terra para a Lua, Marte para Fobos e Deimos), ou -1.
static func parent_of(id: int) -> int:
	if id == Id.MOON:
		return Id.EARTH
	return Id.MARS if MARS_MOONS.has(id) else -1


static func body_name(id: int) -> String:
	return BODIES[id]["name"]


## Raio do corpo em unidades da cena.
static func radius_units(id: int) -> float:
	return BODIES[id]["radius_km"] / UNIT_KM


## Posições de todos os corpos no dia jd, indexadas por Id. A Terra é o centro dela (não o baricentro Terra-Lua).
static func all_positions(jd: float) -> Array:
	var out: Array = []
	out.resize(Id.size())
	out[Id.SUN] = PackedFloat64Array([0.0, 0.0, 0.0])
	for id in range(Id.MERCURY, Id.NEPTUNE + 1):
		out[id] = Ephemeris.planet_position(id - 1, jd)  # a tabela dos planetas começa em Mercúrio
	var moon_au := Ephemeris.moon_position_km(jd)
	var emb: PackedFloat64Array = out[Id.EARTH]
	var earth := PackedFloat64Array()
	var moon := PackedFloat64Array()
	for k in 3:
		var rel := moon_au[k] / Ephemeris.AU_KM
		earth.append(emb[k] - Ephemeris.MOON_MASS_FRACTION * rel)
		moon.append(emb[k] + (1.0 - Ephemeris.MOON_MASS_FRACTION) * rel)
	out[Id.EARTH] = earth
	out[Id.MOON] = moon
	for id in MARS_MOONS:
		var off := mars_moon_offset(id, jd)  # unidades da cena; volta para a eclíptica em UA
		var mars: PackedFloat64Array = out[Id.MARS]
		out[id] = PackedFloat64Array([mars[0] + off.x * UNIT_KM / Ephemeris.AU_KM, mars[1] - off.z * UNIT_KM / Ephemeris.AU_KM,
			mars[2] + off.y * UNIT_KM / Ephemeris.AU_KM])
	return out


static func position(id: int, jd: float) -> PackedFloat64Array:
	return all_positions(jd)[id]


## Vetor (UA, eclíptica) -> Vector3 da cena, em unidades de 1000 km.
static func to_scene(v: PackedFloat64Array) -> Vector3:
	return Vector3(v[0], v[2], -v[1]) * UNIT_PER_AU


## Posição na cena do ponto `p` (UA) em relação a `origin` (UA): a subtração é feita em double.
static func relative_scene(p: PackedFloat64Array, origin: PackedFloat64Array) -> Vector3:
	return Vector3(p[0] - origin[0], p[2] - origin[2], -(p[1] - origin[1])) * UNIT_PER_AU


## Mesma conversão para um vetor em km (por exemplo, a Lua em relação à Terra).
static func km_to_scene(v: PackedFloat64Array) -> Vector3:
	return Vector3(v[0], v[2], -v[1]) / UNIT_KM


## Orientação da Terra: as colunas são os eixos do corpo (leste, polo norte, meridiano de Greenwich) na cena.
## Gira com o tempo sideral de Greenwich; o eixo tem a inclinação real de 23,4° (por isso há estações).
static func earth_orientation(jd: float) -> Basis:
	var theta := deg_to_rad(fposmod(280.46061837 + 360.98564736629 * (jd - Ephemeris.J2000), 360.0))
	var pm := Vector3(cos(theta), sin(theta), 0.0)
	var pole := Vector3(0.0, 0.0, 1.0)
	return Basis(_equatorial_to_scene(pole.cross(pm)), _equatorial_to_scene(pole), _equatorial_to_scene(pm))


## Orientação da Lua: sempre com a face voltada para a Terra (rotação sincronizada), polo na direção do norte da eclíptica.
## `moon_from_earth` é o vetor da Terra à Lua na cena (qualquer escala).
static func moon_orientation(moon_from_earth: Vector3) -> Basis:
	var pole := Vector3.UP
	var near_side := (-moon_from_earth).normalized()
	var east := pole.cross(near_side).normalized()
	return Basis(east, pole, east.cross(pole))


## Dia sideral de Marte, em dias da Terra: o tempo que o planeta leva para girar 360°.
const MARS_SIDEREAL_DAYS := 360.0 / 350.89198226


## Posição de Fobos ou Deimos em relação a Marte (unidades da cena, eixos do Godot) no dia jd.
static func mars_moon_offset(id: int, jd: float) -> Vector3:
	var m: Dictionary = MARS_MOONS[id]
	var e: float = m["e"]
	var a: float = m["a_km"]
	var mean := deg_to_rad(m["m0"] + 360.0 / m["period"] * (jd - Ephemeris.J2000))
	var ea := Ephemeris.solve_kepler(mean, e)
	var xv := a * (cos(ea) - e)
	var yv := a * sqrt(1.0 - e * e) * sin(ea)
	var w := deg_to_rad(m["peri"])
	var x := xv * cos(w) - yv * sin(w)
	var y := xv * sin(w) + yv * cos(w)
	var equator := mars_orientation(jd, false)  # sem a rotação do planeta: o plano da órbita não gira com ele
	var inc := deg_to_rad(m["inc"])
	# eixos do plano: meridiano zero e depois leste (z × x = polo), então as luas giram no mesmo sentido que Marte
	return (equator.z * x + (equator.x * cos(inc) + equator.y * sin(inc)) * y) / UNIT_KM


## Orientação de Marte (IAU/WGCCRE): polo norte em RA 317,68° e Dec 52,89° (inclinação de 25,2° com a órbita, por
## isso as estações) e o meridiano zero girando 350,892° por dia. As colunas são os eixos do corpo (leste, polo,
## meridiano zero), como na Terra: lat/lon de MarsGeo valem direto no referencial do corpo.
## `spin` falso dá o referencial do equador sem a rotação do planeta (meridiano zero fixo).
static func mars_orientation(jd: float, spin := true) -> Basis:
	var t := Ephemeris.centuries(jd)
	var ra := deg_to_rad(317.68143 - 0.1061 * t)
	var dec := deg_to_rad(52.88650 - 0.0609 * t)
	var w := deg_to_rad(fposmod(176.630 + 350.89198226 * (jd - Ephemeris.J2000), 360.0)) if spin else 0.0
	var q := Basis(Vector3.BACK, ra + PI / 2.0) * Basis(Vector3.RIGHT, PI / 2.0 - dec) * Basis(Vector3.BACK, w)
	return Basis(_equatorial_to_scene(q * Vector3.UP), _equatorial_to_scene(q * Vector3.BACK), _equatorial_to_scene(q * Vector3.RIGHT))


static func _equatorial_to_scene(v: Vector3) -> Vector3:
	var eps := deg_to_rad(Ephemeris.OBLIQUITY_DEG)
	var ecl := Vector3(v.x, v.y * cos(eps) + v.z * sin(eps), -v.y * sin(eps) + v.z * cos(eps))
	return Vector3(ecl.x, ecl.z, -ecl.y)
