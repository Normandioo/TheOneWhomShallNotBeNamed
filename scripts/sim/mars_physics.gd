## Física de Marte usada pelo jogo: fórmulas puras, sem estado. Não depende de cena nem de nó.
## Os controles do jogador são frações 0..1 (temperatura, atmosfera, água); aqui estão as unidades reais.

# Temperatura média global: de Marte hoje a "parecido com a Terra".
const TEMP_MIN_C := -63.0
const TEMP_MAX_C := 15.0
const TEMP_SPAN_C := TEMP_MAX_C - TEMP_MIN_C  # usado para converter °C <-> fração do controle

# Pressão atmosférica, em escala logarítmica.
const PRESSURE_MIN_MBAR := 6.0
const PRESSURE_MAX_MBAR := 1000.0

# Altura da atmosfera: o "topo" é onde a pressão cai a ATMOSPHERE_EDGE_MBAR, o mesmo critério que dá ~100 km na
# Terra (linha de Kármán). Marte tem 38% da gravidade da Terra, então o mesmo ar sobe mais antes de rarefazer.
const ATMOSPHERE_EDGE_MBAR := 0.0003
const EARTH_SCALE_HEIGHT_KM := 8.5

# Órbita (NASA Mars Fact Sheet). Ls = longitude solar: 0° = equinócio de primavera do norte.
const ECCENTRICITY := 0.0934
const OBLIQUITY_DEG := 25.19
const LS_PERIHELION := 251.0  # periélio perto do verão do sul: verão do sul curto e quente
const SOLAR_MEAN := 586.2     # W/m² na distância média (1,524 UA)


## Temperatura média global em °C para o controle t (0..1).
static func temperature_c(t: float) -> float:
	return lerpf(TEMP_MIN_C, TEMP_MAX_C, t)


## Pressão atmosférica em mbar para o controle a (0..1).
static func pressure_mbar(a: float) -> float:
	return PRESSURE_MIN_MBAR * pow(PRESSURE_MAX_MBAR / PRESSURE_MIN_MBAR, a)


## Posição na órbita para a fração t (0..1) do ano marciano, com t = 0 em Ls 0°.
## Retorna Vector2(Ls em graus, luz solar no topo da atmosfera em W/m²).
## Resolve a equação de Kepler: perto do periélio Marte anda mais rápido, então as estações têm durações diferentes.
static func orbit(t: float) -> Vector2:
	var e := ECCENTRICITY
	var nu0 := deg_to_rad(-LS_PERIHELION)  # anomalia verdadeira no Ls 0°
	var e0 := 2.0 * atan2(sqrt(1.0 - e) * sin(nu0 * 0.5), sqrt(1.0 + e) * cos(nu0 * 0.5))
	var m := e0 - e * sin(e0) + TAU * t
	var ea := m
	for k in 6:
		ea -= (ea - e * sin(ea) - m) / (1.0 - e * cos(ea))
	var nu := 2.0 * atan2(sqrt(1.0 + e) * sin(ea * 0.5), sqrt(1.0 - e) * cos(ea * 0.5))
	var r := 1.0 - e * cos(ea)  # distância em semieixos maiores
	return Vector2(fposmod(rad_to_deg(nu) + LS_PERIHELION, 360.0), SOLAR_MEAN / (r * r))


## Insolação média do dia (W/m²) na latitude lat (radianos), para Ls (graus) e luz solar flux (W/m²).
static func daily_insolation(lat: float, ls_deg: float, flux: float) -> float:
	var d := asin(sin(deg_to_rad(OBLIQUITY_DEG)) * sin(deg_to_rad(ls_deg)))  # declinação do Sol
	var h0 := acos(clampf(-tan(lat) * tan(d), -1.0, 1.0))  # metade do arco do dia (0 = noite polar)
	return flux / PI * (h0 * sin(lat) * sin(d) + cos(lat) * cos(d) * sin(h0))


## Nome da estação no hemisfério norte para Ls (graus).
static func season_name(ls_deg: float) -> String:
	return ["Primavera", "Verão", "Outono", "Inverno"][int(fposmod(ls_deg, 360.0) / 90.0)] + " no norte"


## Escala de altura (m) da atmosfera de Marte: a pressão cai a 1/e a cada Hs de altitude.
## Vai de ~11 km (CO₂ frio de hoje) a ~22 km (ar tipo Terra a 15 °C); ver docs/pesquisa-marte.md.
static func scale_height_m(atm: float) -> float:
	return lerpf(11000.0, 22000.0, atm)


## Atmosfera local (mesma escala 0..1 de pressure_mbar) na altitude h: o ar rarefaz com exp(-h/Hs).
static func local_atmosphere(atm: float, h: float) -> float:
	return maxf(atm - h / (scale_height_m(atm) * log(PRESSURE_MAX_MBAR / PRESSURE_MIN_MBAR)), 0.0)


## Altura (km) onde a atmosfera "acaba" para o controle atm: Hs · ln(pressão no chão / pressão do limite).
## Marte hoje ~110 km; com ar tipo Terra (1 bar) ~330 km, contra ~130 km na Terra.
static func atmosphere_top_km(atm: float) -> float:
	return scale_height_m(atm) / 1000.0 * log(pressure_mbar(atm) / ATMOSPHERE_EDGE_MBAR)  # passa de 1 com extremos


## Água total do planeta em metros de camada global (GEL) para o controle h2o (0..1).
## h2o 0,3 = ~34 m, a água conhecida hoje; h2o 1 = 500 m, o maior oceano antigo estimado (exige importar água).
static func water_gel(h2o: float) -> float:
	return 500.0 * pow(h2o, 2.23)


## Ponto de ebulição da água (°C) para a pressão p (mbar). Equação de Antoine; boa de ~1 a ~5000 mbar.
static func boiling_c(p_mbar: float) -> float:
	return 1730.63 / (8.07131 - log(p_mbar * 0.750062) / log(10.0)) - 233.426


## Fração da água que ferve e vira vapor: calor perto do ponto de ebulição (pouca pressão ferve mais cedo).
## Gelo não ferve: abaixo de 0 °C a água fica sólida.
static func vapor_fraction(temp_c: float, p_mbar: float) -> float:
	var boil := boiling_c(p_mbar)
	return smoothstep(boil - 20.0, boil, temp_c) * smoothstep(0.0, 5.0, temp_c)


## Fração da água do planeta que pode ficar líquida. Sem pressão (atmosfera) ou sem calor, ela congela.
static func liquid_fraction(temperature: float, atmosphere: float) -> float:
	return smoothstep(0.15, 0.6, atmosphere) * smoothstep(0.2, 0.6, temperature)
