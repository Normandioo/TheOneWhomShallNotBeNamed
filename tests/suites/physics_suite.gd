extends "res://tests/test_suite.gd"
## Conversões, relevo real e as fórmulas físicas. Não precisa da cena.

const MarsGeo = preload("res://scripts/data/mars_geo.gd")
const MolaReader = preload("res://scripts/data/mola_reader.gd")
const Physics = preload("res://scripts/sim/mars_physics.gd")


func run() -> void:
	for p in [[0.0, 0.0], [45.0, 120.0], [-42.0, 70.0], [10.0, -170.0]]:
		var ll: Vector2 = MarsGeo.lat_lon(MarsGeo.dir(p[0], p[1]))
		if absf(ll.x - p[0]) > 0.01 or absf(ll.y - p[1]) > 0.01:
			return fail("lat/lon ida e volta falhou em %s -> %s" % [p, ll])
	if MarsGeo.nearest_region(MarsGeo.dir(-42.0, 70.0)) != 4:
		return fail("Hellas deveria ser a região 4")
	var img := MolaReader.load_global_height()
	if MolaReader.height_at(img, MarsGeo.dir(18.65, -133.8)) < 18000.0:
		return fail("Olympus Mons deveria passar de 18 km no relevo carregado")
	if Physics.liquid_fraction(0.6, 0.0) != 0.0 or Physics.liquid_fraction(0.6, 0.7) <= Physics.liquid_fraction(0.6, 0.3):
		return fail("menos atmosfera deveria significar menos água líquida")
	if absf(Physics.pressure_mbar(0.0) - 6.0) > 0.01 or absf(Physics.pressure_mbar(1.0) - 1000.0) > 0.5:
		return fail("pressão deveria ir de 6 a 1000 mbar")
	if Physics.temperature_c(0.0) != -63.0 or Physics.temperature_c(1.0) != 15.0:
		return fail("temperatura deveria ir de -63 a +15 °C")
	# Pressão local: Hellas (-8 km) ~2x o nível zero hoje; Olympus (+21 km) bem abaixo.
	var p_hellas := Physics.pressure_mbar(Physics.local_atmosphere(0.0, -8000.0))
	var p_olympus := Physics.pressure_mbar(Physics.local_atmosphere(1.0, 21000.0))
	if absf(p_hellas - 12.4) > 1.0 or absf(p_olympus - 390.0) > 40.0:
		return fail("pressão local errada: Hellas hoje %.1f mbar (esperado ~12), Olympus a 1 bar %.0f (esperado ~390)" % [p_hellas, p_olympus])
	if absf(Physics.water_gel(0.3) - 34.0) > 2.0:
		return fail("h2o 0,3 deveria ser ~34 m de água global, é %.1f" % Physics.water_gel(0.3))
	if absf(Physics.boiling_c(1013.25) - 100.0) > 0.5 or absf(Physics.boiling_c(5000.0) - 152.0) > 3.0:
		return fail("ponto de ebulição errado: %.1f °C a 1 atm, %.1f °C a 5 bar" % [Physics.boiling_c(1013.25), Physics.boiling_c(5000.0)])
	# Estações com Kepler: primavera 194 sols, verão 178, outono 142, inverno 154 (ano de 668,6 sols).
	for ref in [[194.0 / 668.6, 90.0], [372.0 / 668.6, 180.0], [514.0 / 668.6, 270.0]]:
		var ls: float = Physics.orbit(ref[0]).x
		if absf(ls - ref[1]) > 3.0:
			return fail("fração do ano %.3f deveria ser Ls ~%d°, deu %.1f" % [ref[0], ref[1], ls])
	if absf(Physics.daily_insolation(0.0, 0.0, 586.2) - 586.2 / PI) > 0.5:
		return fail("insolação no equador no equinócio deveria ser S/π")
	var lat_p := deg_to_rad(85.0)
	var q_south := Physics.daily_insolation(-lat_p, 270.0, Physics.orbit(514.0 / 668.6).y)
	var q_north := Physics.daily_insolation(lat_p, 90.0, Physics.orbit(194.0 / 668.6).y)
	if q_south <= q_north * 1.2:
		return fail("verão do sul (periélio) deveria ter bem mais sol que o do norte: %.0f vs %.0f W/m²" % [q_south, q_north])
	# Altura da atmosfera: cresce com a pressão, e em Marte (gravidade menor) é bem maior que na Terra à mesma pressão.
	var top_now := Physics.atmosphere_top_km(0.0)
	var top_earthlike := Physics.atmosphere_top_km(1.0)
	var top_earth := Physics.EARTH_SCALE_HEIGHT_KM * log(Physics.PRESSURE_MAX_MBAR / Physics.ATMOSPHERE_EDGE_MBAR)
	if absf(top_now - 110.0) > 15.0 or absf(top_earthlike - 330.0) > 40.0 or top_earthlike < 2.0 * top_earth:
		return fail("topo da atmosfera: Marte hoje deveria dar ~110 km (deu %.0f), com ar tipo Terra ~330 km (deu %.0f), mais que o dobro do da Terra à mesma pressão (%.0f)" % [top_now, top_earthlike, top_earth])
	var last := 0.0
	for k in 14:
		var top := Physics.atmosphere_top_km(k / 10.0)
		if top <= last:
			return fail("o topo da atmosfera deveria crescer com o controle de atmosfera")
		last = top
	ok("conversões, regiões, relevo real, fórmulas físicas e leituras (atmosfera: %.0f km hoje, %.0f km com ar tipo Terra)" % [top_now, top_earthlike])
