extends "res://tests/test_suite.gd"
## As posições do sistema solar contra fatos conhecidos (datas de eventos reais): se um número da tabela estiver
## errado, um destes falha. Não precisa da cena.

const Ephemeris = preload("res://scripts/sim/ephemeris.gd")
const SolarBodies = preload("res://scripts/sim/solar_bodies.gd")
const BeltGenerator = preload("res://scripts/sim/belt_generator.gd")


func run() -> void:
	_kepler()
	if failed:
		return
	_planets()
	if failed:
		return
	_moon()
	if failed:
		return
	_earth_orientation()
	if failed:
		return
	_mars_orientation()
	if failed:
		return
	_mars_moons()
	if failed:
		return
	_belts()


func _kepler() -> void:
	if Ephemeris.jd_from_year(2000.0) != Ephemeris.J2000:
		return fail("o ano 2000,0 deveria ser J2000")
	for e in [0.0, 0.0934, 0.2056, 0.6, 0.9]:
		for m in [-3.0, -1.0, 0.0, 0.5, 2.0, 3.1]:
			var ea := Ephemeris.solve_kepler(m, e)
			if absf(ea - e * sin(ea) - m) > 1e-10:
				return fail("Kepler errado para e=%s M=%s" % [e, m])
	ok("equação de Kepler")


func _planets() -> void:
	# A Terra em J2000: 0,9833 UA do Sol (a Terra passa pelo periélio dois dias depois), longitude ~100,4°.
	var earth := Ephemeris.planet_position(2, Ephemeris.J2000)
	var r := Vector3(earth[0], earth[1], earth[2]).length()
	var lon := rad_to_deg(atan2(earth[1], earth[0]))
	if absf(r - 0.98333) > 0.001 or absf(lon - 100.4) > 0.5:
		return fail("a Terra em J2000 deveria estar a 0,9833 UA e longitude 100,4°, está a %.4f UA e %.2f°" % [r, lon])

	# Períodos: a terceira lei de Kepler, T² = a³, contra a taxa da longitude média da tabela.
	for i in 8:
		var a: float = Ephemeris.PLANETS[i][0]
		var days := Ephemeris.planet_period_days(i)
		if absf(days / (365.25636 * pow(a, 1.5)) - 1.0) > 0.003:
			return fail("planeta %d: período %.1f dias não bate com a 3ª lei de Kepler (%.1f)" % [i, days, 365.25636 * pow(a, 1.5)])

	# Oposição de Marte em 2020: o mais perto que ele chegou da Terra foi 0,4146 UA, em 6 de outubro.
	var best := 99.0
	var best_jd := 0.0
	var jd := 2459126.5
	while jd < 2459132.5:
		var d := _distance(Ephemeris.planet_position(2, jd), Ephemeris.planet_position(3, jd))
		if d < best:
			best = d
			best_jd = jd
		jd += 0.1
	if absf(best - 0.4146) > 0.008 or absf(best_jd - 2459128.5) > 2.0:
		return fail("Marte deveria chegar a 0,4146 UA da Terra por volta de 6/out/2020 (JD 2459128,5): %.4f UA em JD %.1f" % [best, best_jd])

	# Grande conjunção de Júpiter e Saturno em 21/12/2020: vistos DA TERRA, ficaram a 0,1° um do outro.
	var earth_now := Ephemeris.planet_position(2, 2459204.5)
	var j := Ephemeris.planet_position(4, 2459204.5)
	var s := Ephemeris.planet_position(5, 2459204.5)
	var lon_j := rad_to_deg(atan2(j[1] - earth_now[1], j[0] - earth_now[0]))
	var lon_s := rad_to_deg(atan2(s[1] - earth_now[1], s[0] - earth_now[0]))
	var dl := absf(wrapf(lon_j - lon_s, -180.0, 180.0))
	if dl > 0.7 or absf(fposmod(lon_j, 360.0) - 300.3) > 1.0:
		return fail("Júpiter e Saturno deveriam estar juntos em ~300,3° em 21/12/2020, vistos da Terra: Júpiter %.2f°, Saturno %.2f°" % [lon_j, lon_s])
	ok("planetas: Terra em J2000, 3ª lei de Kepler, oposição de Marte (%.4f UA) e conjunção Júpiter-Saturno (%.2f°)" % [best, dl])


func _distance(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return Vector3(a[0] - b[0], a[1] - b[1], a[2] - b[2]).length()


func _moon() -> void:
	# Exemplo 47.a do livro de Meeus (12/04/1992 0h TD): longitude 133,1627°, latitude -3,2291°, distância 368409,7 km.
	var m := Ephemeris.moon_ecliptic_of_date(2448724.5)
	if absf(m.x - 133.162655) > 0.15 or absf(m.y + 3.229126) > 0.1 or absf(m.z - 368409.7) > 300.0:
		return fail("Lua em 12/04/1992: esperado (133.1627°, -3.2291°, 368410 km), deu %s" % m)

	# Lua nova em 6/1/2000 18:14 UT: Lua e Sol na mesma longitude. Lua cheia em 21/1/2000 04:40 UT: opostos.
	var new_elong := _elongation(2451550.2597)
	var full_elong := absf(_elongation(2451564.6944))
	if absf(new_elong) > 2.0 or absf(full_elong - 180.0) > 2.0:
		return fail("fases da Lua em jan/2000: lua nova deveria dar elongação 0° (deu %.2f°) e cheia 180° (deu %.2f°)" % [new_elong, full_elong])
	# O mesmo, em 2070 (o jogo começa lá): a Lua nova de 2070 não é conhecida de cabeça, mas o ciclo se repete a cada
	# 29,53 dias: a elongação tem que andar ~12,19° por dia.
	var jd := Ephemeris.jd_from_year(2070.0)
	var rate := wrapf(_elongation(jd + 1.0) - _elongation(jd), -180.0, 180.0)
	if rate < 10.0 or rate > 15.0:
		return fail("a elongação da Lua deveria andar ~12,2° por dia, andou %.2f°" % rate)

	# Distância: sempre entre o perigeu e o apogeu (356 a 407 mil km), e passa pelos dois extremos em um mês.
	var lo := 1e9
	var hi := 0.0
	for k in 300:
		var d := Ephemeris.moon_ecliptic_of_date(Ephemeris.J2000 + k * 0.1).z
		lo = minf(lo, d)
		hi = maxf(hi, d)
	if lo < 354000.0 or hi > 408000.0 or hi - lo < 30000.0:
		return fail("distância da Lua em um mês deveria ir de ~357 a ~406 mil km, foi de %.0f a %.0f" % [lo, hi])

	# A Terra e a Lua em volta do baricentro: a distância entre elas é a geocêntrica, e o baricentro fica dentro da Terra.
	var pos := SolarBodies.all_positions(2451545.0)
	var earth: PackedFloat64Array = pos[SolarBodies.Id.EARTH]
	var moon: PackedFloat64Array = pos[SolarBodies.Id.MOON]
	var gap_km := _distance(earth, moon) * Ephemeris.AU_KM
	var emb := Ephemeris.planet_position(2, 2451545.0)
	var earth_offset_km := _distance(earth, emb) * Ephemeris.AU_KM
	if absf(gap_km - Ephemeris.moon_ecliptic_of_date(2451545.0).z) > 1.0 or earth_offset_km > 6371.0:
		return fail("Terra-Lua: distância %.0f km, e a Terra deveria ficar a menos de 1 raio do baricentro (%.0f km)" % [gap_km, earth_offset_km])
	ok("Lua: exemplo de Meeus, fases de jan/2000 (%.2f° e %.2f°), distância %.0f-%.0f km" % [new_elong, full_elong, lo, hi])


## Longitude da Lua menos a do Sol, vistas da Terra (graus, -180..180). Ambas na eclíptica J2000.
func _elongation(jd: float) -> float:
	var moon := Ephemeris.moon_position_km(jd)
	var earth := Ephemeris.planet_position(2, jd)
	var moon_lon := rad_to_deg(atan2(moon[1], moon[0]))
	var sun_lon := rad_to_deg(atan2(-earth[1], -earth[0]))
	return wrapf(moon_lon - sun_lon, -180.0, 180.0)


func _earth_orientation() -> void:
	# Em J2000 o Sol está sobre ~23° sul, perto de Greenwich ao meio-dia; seis horas depois, sobre 90° oeste.
	for ref in [[Ephemeris.J2000, 1.1], [Ephemeris.J2000 + 0.25, -90.0 + 1.1], [Ephemeris.J2000 + 0.5, -180.0 + 1.1]]:
		var jd: float = ref[0]
		var pos := SolarBodies.all_positions(jd)
		var sun_dir := SolarBodies.relative_scene(pos[SolarBodies.Id.SUN], pos[SolarBodies.Id.EARTH]).normalized()
		var local := SolarBodies.earth_orientation(jd).transposed() * sun_dir  # o Sol no referencial da Terra
		var lon := rad_to_deg(atan2(local.x, local.z))
		var lat := rad_to_deg(asin(local.y))
		if absf(lat + 23.0) > 0.7 or absf(wrapf(lon - ref[1], -180.0, 180.0)) > 3.0:
			return fail("ponto subsolar em JD %.2f: esperado (-23°, %.1f°), deu (%.2f°, %.2f°)" % [jd, ref[1], lat, lon])
	# Lua: a face voltada para a Terra fica sempre virada para ela.
	var from_earth := Vector3(3.0, 0.2, -2.0)  # a Lua fica a poucos graus da eclíptica, então quase no plano horizontal
	var moon_basis := SolarBodies.moon_orientation(from_earth)
	var to_earth_local := moon_basis.transposed() * (-from_earth).normalized()
	if to_earth_local.z < 0.995 or absf(moon_basis.determinant() - 1.0) > 1e-6:
		return fail("a Lua deveria ter o meridiano zero voltado para a Terra")
	ok("orientação: ponto subsolar da Terra no dia e na hora certos; Lua com a mesma face para a Terra")


## Latitude e longitude do ponto de Marte que está sob o Sol (graus), no referencial do planeta.
func _mars_subsolar(jd: float) -> Vector2:
	var pos := SolarBodies.all_positions(jd)
	var sun_dir := SolarBodies.relative_scene(pos[SolarBodies.Id.SUN], pos[SolarBodies.Id.MARS]).normalized()
	var local := SolarBodies.mars_orientation(jd).transposed() * sun_dir
	return Vector2(rad_to_deg(asin(local.y)), rad_to_deg(atan2(local.x, local.z)))


func _mars_orientation() -> void:
	# A estação de Marte (Ls) vale a longitude heliocêntrica dele menos 85°. No Ls 90° o Sol está a +25° de latitude,
	# nos equinócios (Ls 0° e 180°) no equador e no Ls 270° a -25°: confere o eixo (a inclinação e para onde aponta).
	for ref in [[175.0, 25.2, 1.0], [85.0, 0.0, 2.0], [265.0, 0.0, 2.0], [355.0, -25.2, 1.0]]:
		var best_jd := 0.0
		var best := 999.0
		var jd := 2459000.0
		while jd < 2459700.0:
			var p := Ephemeris.planet_position(3, jd)
			var gap := absf(wrapf(rad_to_deg(atan2(p[1], p[0])) - ref[0], -180.0, 180.0))
			if gap < best:
				best = gap
				best_jd = jd
			jd += 0.25
		var lat := _mars_subsolar(best_jd).x
		if absf(lat - ref[1]) > ref[2]:
			return fail("Marte com longitude heliocêntrica %.0f° (Ls %.0f°): o Sol deveria estar a %.1f° de latitude, está a %.2f°" % [ref[0], ref[0] - 85.0, ref[1], lat])
	# Rotação: um dia solar de Marte (1,02749 dias) devolve o Sol ao mesmo ponto; um quarto dele o move 90° para oeste.
	var start := 2459300.0
	var lon0 := _mars_subsolar(start).y
	var after_sol := _mars_subsolar(start + 1.0274912).y
	var after_quarter := _mars_subsolar(start + 1.0274912 / 4.0).y
	if absf(wrapf(after_sol - lon0, -180.0, 180.0)) > 3.0 or absf(wrapf(after_quarter - lon0 + 90.0, -180.0, 180.0)) > 8.0:
		return fail("a rotação de Marte deveria mover o ponto subsolar -90° em um quarto de dia e 0° em um dia: %.1f° e %.1f°" % [
			wrapf(after_quarter - lon0, -180.0, 180.0), wrapf(after_sol - lon0, -180.0, 180.0)])
	ok("orientação de Marte: eixo (Sol a ±25° nos solstícios, 0° nos equinócios) e rotação de 24h39")


func _mars_moons() -> void:
	var jd := 2459300.0
	for id in SolarBodies.MARS_MOONS:
		var m: Dictionary = SolarBodies.MARS_MOONS[id]
		var a: float = m["a_km"]
		var e: float = m["e"]
		var period: float = m["period"]
		# A distância a Marte fica entre o periápsis e o apoápsis, durante a órbita inteira.
		for k in 24:
			var d := SolarBodies.mars_moon_offset(id, jd + period * k / 24.0).length() * SolarBodies.UNIT_KM
			if d < a * (1.0 - e) - 1.0 or d > a * (1.0 + e) + 1.0:
				return fail("%s a %.0f km de Marte, fora de %.0f-%.0f" % [SolarBodies.body_name(id), d, a * (1.0 - e), a * (1.0 + e)])
		# Depois de um período, volta ao mesmo ponto.
		var back := SolarBodies.mars_moon_offset(id, jd + period).angle_to(SolarBodies.mars_moon_offset(id, jd))
		if rad_to_deg(back) > 0.5:
			return fail("%s deveria voltar ao mesmo ponto depois de um período, ficou %.2f° fora" % [SolarBodies.body_name(id), rad_to_deg(back)])
		# O plano da órbita é o equador de Marte (inclinação de ~1°).
		var normal := SolarBodies.mars_moon_offset(id, jd).cross(SolarBodies.mars_moon_offset(id, jd + period / 4.0))
		var pole := SolarBodies.mars_orientation(jd).y
		var tilt := rad_to_deg(normal.angle_to(pole))
		if tilt > m["inc"] + 1.0:
			return fail("a órbita de %s deveria estar no equador de Marte (inclinação %.2f°), está a %.2f° dele" % [SolarBodies.body_name(id), m["inc"], tilt])
		# A posição absoluta usa o mesmo deslocamento.
		var pos := SolarBodies.all_positions(jd)
		var gap := Vector3(pos[id][0] - pos[SolarBodies.Id.MARS][0], pos[id][1] - pos[SolarBodies.Id.MARS][1], pos[id][2] - pos[SolarBodies.Id.MARS][2]).length() * Ephemeris.AU_KM
		var expected := SolarBodies.mars_moon_offset(id, jd).length() * SolarBodies.UNIT_KM
		if absf(gap - expected) > 0.5:
			return fail("a posição de %s no sistema solar deveria estar a %.1f km de Marte, está a %.1f" % [SolarBodies.body_name(id), expected, gap])
	# Fobos dá ~3 voltas por dia marciano (nasce no oeste), e Deimos uma volta em ~1,2 dia.
	var turns := SolarBodies.MARS_SIDEREAL_DAYS / float(SolarBodies.MARS_MOONS[SolarBodies.Id.PHOBOS]["period"])
	if turns < 3.1 or turns > 3.3:
		return fail("Fobos deveria dar ~3,2 voltas por dia marciano, dá %.2f" % turns)
	ok("luas de Marte: Fobos e Deimos no equador, com período, distância e posição certos (Fobos: %.1f voltas por dia marciano)" % turns)


func _belts() -> void:
	var belt := BeltGenerator.main_belt(22000, 11)
	if belt["orbit"].size() != 22000 or belt["angles"].size() != 22000 or belt["phase"].size() != 22000:
		return fail("o cinturão principal deveria ter 22000 pontos, tem %d" % belt["orbit"].size())
	var near_gap := 0
	var beside := 0
	var lo := 99.0
	var hi := 0.0
	for o in belt["orbit"]:
		lo = minf(lo, o.x)
		hi = maxf(hi, o.x)
		if o.x > 2.485 and o.x < 2.515:
			near_gap += 1
		elif (o.x > 2.40 and o.x < 2.485) or (o.x > 2.515 and o.x < 2.60):
			beside += 1
	if lo < 2.1 or hi > 3.3:
		return fail("o cinturão principal deveria ficar entre 2,1 e 3,3 UA: %.2f a %.2f" % [lo, hi])
	if near_gap > 0 or beside < 500:
		return fail("a lacuna de Kirkwood em 2,50 UA deveria estar vazia e os lados cheios: %d dentro, %d ao lado" % [near_gap, beside])

	var trojans := BeltGenerator.jupiter_trojans(3000, 22)
	var jupiter_long: float = Ephemeris.PLANETS[4][3]
	var off := 0
	for k in 3000:
		var angles: Vector2 = trojans["angles"][k]
		var mean_long := rad_to_deg(angles.x + angles.y + trojans["phase"][k].x)
		var rel := absf(wrapf(mean_long - jupiter_long, -180.0, 180.0))
		if absf(rel - 60.0) > 40.0:
			off += 1
	if off > 15:
		return fail("os troianos deveriam ficar a 60° de Júpiter, %d de 3000 estão fora" % off)

	var kuiper := BeltGenerator.kuiper_belt(18000, 33)
	for o in kuiper["orbit"]:
		if o.x < 38.0 or o.x > 91.0 or o.y > 0.55 or o.x * (1.0 - o.y) < 28.5:
			return fail("órbita fora do cinturão de Kuiper: a=%.1f e=%.2f" % [o.x, o.y])
	ok("cinturões: principal com lacunas de Kirkwood (%d ao lado, 0 dentro), troianos a ±60° de Júpiter, Kuiper entre 38 e 90 UA" % beside)
