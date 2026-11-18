## Posições reais dos planetas e da Lua. Fórmulas puras, sem estado, sem cena.
## Tudo em doubles (GDScript usa 64 bits em float; Vector3 só tem 32, então posições absolutas são
## PackedFloat64Array [x, y, z]) no referencial eclíptico J2000: x = equinócio de março, z = polo norte da eclíptica.
##
## Planetas: elementos keplerianos médios do JPL ("Keplerian Elements for Approximate Positions of the Major
## Planets", E. M. Standish, tabela 1, válida de 1800 a 2050; fora disso o erro cresce devagar, mas segue plausível).
## Lua: série truncada de Meeus, "Astronomical Algorithms" (2ª ed.), cap. 47.

const AU_KM := 149597870.7
const J2000 := 2451545.0  # 2000-01-01 12:00 TT
const DAYS_PER_CENTURY := 36525.0
const OBLIQUITY_DEG := 23.4392911  # inclinação do equador sobre a eclíptica em J2000
const MOON_MASS_FRACTION := 0.0121505  # massa da Lua / (Terra + Lua): a Terra orbita o baricentro por esta fração da distância

## Linhas: Mercúrio, Vênus, Terra-Lua (baricentro), Marte, Júpiter, Saturno, Urano, Netuno.
## Colunas: a (UA), e, I (°), L (°), longitude do periélio (°), longitude do nó (°), e as taxas por século das mesmas seis.
const PLANETS := [
	[0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593,
		0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081],
	[0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255,
		0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418],
	[1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0,
		0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0],
	[1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891,
		0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343],
	[5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909,
		-0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106],
	[9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448,
		-0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794],
	[19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503,
		-0.00196176, -0.00004397, -0.00242939, 428.48202785, 0.40805281, 0.04240589],
	[30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574,
		0.00026291, 0.00005105, 0.00035372, 218.45945325, -0.32241464, -0.00508664],
]

# Lua, tabela 47.A de Meeus: D, M, M', F, soma da longitude (1e-6 °), soma da distância (1e-3 km).
const MOON_LON_DIST := [
	[0, 0, 1, 0, 6288774, -20905355], [2, 0, -1, 0, 1274027, -3699111], [2, 0, 0, 0, 658314, -2955968],
	[0, 0, 2, 0, 213618, -569925], [0, 1, 0, 0, -185116, 48888], [0, 0, 0, 2, -114332, -3149],
	[2, 0, -2, 0, 58793, 246158], [2, -1, -1, 0, 57066, -152138], [2, 0, 1, 0, 53322, -170733],
	[2, -1, 0, 0, 45758, -204586], [0, 1, -1, 0, -40923, -129620], [1, 0, 0, 0, -34720, 108743],
	[0, 1, 1, 0, -30383, 104755], [2, 0, 0, -2, 15327, 10321], [0, 0, 1, 2, -12528, 0],
	[0, 0, 1, -2, 10980, 79661], [4, 0, -1, 0, 10675, -34782], [0, 0, 3, 0, 10034, -23210],
	[4, 0, -2, 0, 8548, -21636], [2, 1, -1, 0, -7888, 24208], [2, 1, 0, 0, -6766, 30824],
	[1, 0, -1, 0, -5163, -8379], [1, 1, 0, 0, 4987, -16675], [2, -1, 1, 0, 4036, -12831],
	[2, 0, 2, 0, 3994, -10445], [4, 0, 0, 0, 3861, -11650], [2, 0, -3, 0, 3665, 14403],
	[0, 1, -2, 0, -2689, -7003],
]
# Tabela 47.B: D, M, M', F, soma da latitude (1e-6 °).
const MOON_LAT := [
	[0, 0, 0, 1, 5128122], [0, 0, 1, 1, 280602], [0, 0, 1, -1, 277693], [2, 0, 0, -1, 173237],
	[2, 0, -1, 1, 55413], [2, 0, -1, -1, 46271], [2, 0, 0, 1, 32573], [0, 0, 2, 1, 17198],
	[2, 0, 1, -1, 9266], [0, 0, 2, -1, 8822], [2, -1, 0, -1, 8216], [2, 0, -2, -1, 4324],
	[2, 0, 1, 1, 4200], [2, 1, 0, -1, -3359], [2, -1, -1, 1, 2463], [2, -1, 0, 1, 2211],
	[2, -1, -1, -1, 2065], [0, 1, -1, -1, -1870], [4, 0, -1, -1, 1828], [0, 1, 0, 1, -1794],
]


## Dia juliano de um ano decimal do calendário (ano 2070,0 = 1 de janeiro de 2070 ao meio-dia, aproximadamente).
static func jd_from_year(year: float) -> float:
	return J2000 + (year - 2000.0) * 365.25


static func centuries(jd: float) -> float:
	return (jd - J2000) / DAYS_PER_CENTURY


## Resolve a equação de Kepler M = E - e·sin(E) (radianos).
static func solve_kepler(mean_anomaly: float, e: float) -> float:
	var m := wrapf(mean_anomaly, -PI, PI)
	var ea := m + e * sin(m)
	for i in 10:
		var d := (ea - e * sin(ea) - m) / (1.0 - e * cos(ea))
		ea -= d
		if absf(d) < 1e-13:
			break
	return ea


## Elementos do planeta `i` (0 = Mercúrio ... 7 = Netuno) no dia jd: [a, e, I, nó, argumento do periélio, M], ângulos em radianos.
static func planet_elements(i: int, jd: float) -> PackedFloat64Array:
	var row: Array = PLANETS[i]
	var t := centuries(jd)
	var a: float = row[0] + row[6] * t
	var e: float = row[1] + row[7] * t
	var inc: float = row[2] + row[8] * t
	var mean_long: float = row[3] + row[9] * t
	var peri: float = row[4] + row[10] * t
	var node: float = row[5] + row[11] * t
	return PackedFloat64Array([a, e, deg_to_rad(inc), deg_to_rad(node), deg_to_rad(peri - node), deg_to_rad(mean_long - peri)])


## Posição na órbita (plano orbital, perifoco em x) para a anomalia excêntrica ea, depois girada para a eclíptica.
static func position_from_elements(el: PackedFloat64Array, ea: float) -> PackedFloat64Array:
	var a := el[0]
	var e := el[1]
	var xv := a * (cos(ea) - e)
	var yv := a * sqrt(1.0 - e * e) * sin(ea)
	var cw := cos(el[4])
	var sw := sin(el[4])
	var cn := cos(el[3])
	var sn := sin(el[3])
	var ci := cos(el[2])
	var si := sin(el[2])
	return PackedFloat64Array([
		(cw * cn - sw * sn * ci) * xv + (-sw * cn - cw * sn * ci) * yv,
		(cw * sn + sw * cn * ci) * xv + (-sw * sn + cw * cn * ci) * yv,
		(sw * si) * xv + (cw * si) * yv])


## Posição heliocêntrica (UA) do planeta `i` no dia jd. Para a Terra (i = 2) é o baricentro Terra-Lua.
static func planet_position(i: int, jd: float) -> PackedFloat64Array:
	var el := planet_elements(i, jd)
	return position_from_elements(el, solve_kepler(el[5], el[1]))


## Pontos (UA) de uma volta completa da órbita do planeta `i`, com os elementos do dia jd. Matriz plana x, y, z, x, y, z...
## Fecha a volta: o último ponto repete o primeiro.
static func orbit_samples(i: int, jd: float, count: int) -> PackedFloat64Array:
	var el := planet_elements(i, jd)
	var out := PackedFloat64Array()
	for k in count + 1:
		out.append_array(position_from_elements(el, TAU * k / count))
	return out


## Período orbital do planeta `i` em dias, pela taxa da longitude média.
static func planet_period_days(i: int) -> float:
	return DAYS_PER_CENTURY * 360.0 / PLANETS[i][9]


## Lua geocêntrica em Vector3(longitude °, latitude °, distância km), eclíptica e equinócio MÉDIOS DA DATA (Meeus 47).
static func moon_ecliptic_of_date(jd: float) -> Vector3:
	var t := centuries(jd)
	var t2 := t * t
	var lp := 218.3164477 + 481267.88123421 * t - 0.0015786 * t2
	var d := deg_to_rad(297.8501921 + 445267.1114034 * t - 0.0018819 * t2)
	var m := deg_to_rad(357.5291092 + 35999.0502909 * t - 0.0001536 * t2)
	var mp := deg_to_rad(134.9633964 + 477198.8675055 * t + 0.0087414 * t2)
	var f := deg_to_rad(93.2720950 + 483202.0175233 * t - 0.0036539 * t2)
	var ecc := 1.0 - 0.002516 * t - 0.0000074 * t2  # excentricidade da órbita da Terra: corrige os termos com M
	var sum_l := 0.0
	var sum_r := 0.0
	for term in MOON_LON_DIST:
		var arg: float = term[0] * d + term[1] * m + term[2] * mp + term[3] * f
		var k := pow(ecc, absi(term[1]))
		sum_l += term[4] * k * sin(arg)
		sum_r += term[5] * k * cos(arg)
	var sum_b := 0.0
	for term in MOON_LAT:
		var arg: float = term[0] * d + term[1] * m + term[2] * mp + term[3] * f
		sum_b += term[4] * pow(ecc, absi(term[1])) * sin(arg)
	var a1 := deg_to_rad(119.75 + 131.849 * t)
	var a2 := deg_to_rad(53.09 + 479264.290 * t)
	var a3 := deg_to_rad(313.45 + 481266.484 * t)
	var lpr := deg_to_rad(lp)
	sum_l += 3958.0 * sin(a1) + 1962.0 * sin(lpr - f) + 318.0 * sin(a2)
	sum_b += -2235.0 * sin(lpr) + 382.0 * sin(a3) + 175.0 * sin(a1 - f) + 175.0 * sin(a1 + f) \
		+ 127.0 * sin(lpr - mp) - 115.0 * sin(lpr + mp)
	return Vector3(fposmod(lp + sum_l / 1e6, 360.0), sum_b / 1e6, 385000.56 + sum_r / 1000.0)


## Precessão geral em longitude desde J2000 (graus): converte "equinócio da data" em "equinócio J2000".
static func precession_deg(jd: float) -> float:
	var t := centuries(jd)
	return (5028.796195 * t + 1.1054348 * t * t) / 3600.0


## Posição da Lua em relação à Terra (km), no mesmo referencial dos planetas (eclíptica J2000).
static func moon_position_km(jd: float) -> PackedFloat64Array:
	var s := moon_ecliptic_of_date(jd)
	var lon := deg_to_rad(s.x - precession_deg(jd))
	var lat := deg_to_rad(s.y)
	return PackedFloat64Array([s.z * cos(lat) * cos(lon), s.z * cos(lat) * sin(lon), s.z * sin(lat)])
