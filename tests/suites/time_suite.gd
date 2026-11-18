extends "res://tests/test_suite.gd"
## O tempo na cena: pausa, aceleração, terraformação automática com o slider acompanhando e estações.

const MarsGeo = preload("res://scripts/data/mars_geo.gd")
const AutoTerraformer = preload("res://scripts/sim/auto_terraformer.gd")
const GameClock = preload("res://scripts/sim/game_clock.gd")
const Ephemeris = preload("res://scripts/sim/ephemeris.gd")


func run() -> void:
	var planet = main.planet
	var clock: GameClock = main.clock
	# Pausa: nada avança.
	planet.set_control("temperature", 0.0)
	planet.set_control("atmosphere", 0.0)
	planet.set_control("h2o", 0.3)
	clock.set_speed(0.0)
	main._process(1.0)  # a água total caiu: a água líquida se limita a ela uma vez
	var y0 := clock.year
	var liquid0: float = planet.liquid
	main._process(5.0)
	if clock.year != y0 or planet.liquid != liquid0:
		return fail("em pausa o tempo não deveria avançar")

	# 10x com terraformação automática: 25 s reais = 250 anos, e os controles chegam nos alvos.
	clock.set_speed(10.0)
	main.auto_terraformer.enabled = true
	for i in 25:
		main._process(1.0)
	if absf(clock.year - (y0 + 250.0)) > 0.01:
		return fail("25 s a 10x deveriam dar 250 anos, deu %s" % (clock.year - y0))
	for p in AutoTerraformer.TARGETS:
		if absf(planet.get_control(p) - AutoTerraformer.TARGETS[p]) > 0.001:
			return fail("%s deveria ter chegado em %s, está em %s" % [p, AutoTerraformer.TARGETS[p], planet.get_control(p)])
		if absf(main.control_panel.control_value(p) - planet.get_control(p)) > 0.01:
			return fail("o slider de %s não acompanhou" % p)
	ok("tempo acelerado, ano %d, terraformação automática chegou nos alvos" % int(clock.year))

	# O mesmo, mas como no jogo de verdade: quadro a quadro, a 1x. O valor não pode travar em zero.
	main.auto_terraformer.enabled = false
	planet.set_control("temperature", 0.0)
	clock.set_speed(1.0)
	main.auto_terraformer.enabled = true
	for i in 300:
		main._process(1.0 / 60.0)
	if planet.temperature < AutoTerraformer.RATE * 4.0:
		return fail("a terraformação automática deveria andar a 60 quadros por segundo: 5 anos subiram só %.5f" % planet.temperature)
	main.auto_terraformer.enabled = false
	ok("terraformação automática anda quadro a quadro a 1x (temperatura %.3f depois de 5 anos)" % planet.temperature)

	# Estações seguem o calendário: rápido demais, só a média do ano; em 0.1x, um ano marciano = 1,88 ano.
	clock.set_speed(10.0)
	main._process(1.0)
	if main.climate.season_amp != 0.0:
		return fail("a 10x as estações deveriam virar a média do ano")
	clock.set_speed(0.1)
	main._process(1.0)
	var t0: float = main.climate.season_t
	main._process(1.0 / 0.1 * GameClock.MARS_YEAR * 0.25)  # um quarto de ano marciano
	var dt := fposmod(main.climate.season_t - t0, 1.0)
	if main.climate.season_amp != 1.0 or absf(dt - 0.25) > 0.01:
		return fail("em 0.1x as estações deveriam andar com o calendário: amp %s, avançou %.3f do ano" % [main.climate.season_amp, dt])
	clock.set_speed(10.0)
	ok("estações seguem o calendário (só aparecem até 0.3x)")

	# A vista do espaço usa a data do jogo, e Marte gira de verdade (ver space_physics_suite): aqui só a data.
	main._process(0.0)
	var jd_clock := Ephemeris.jd_from_year(clock.year)
	if absf(main.space.jd - jd_clock) > 1e-6:
		return fail("a vista do espaço deveria usar a data do jogo: %.4f vs %.4f" % [main.space.jd, jd_clock])
	ok("a vista do espaço usa a data do jogo")

	main.space.look_at_surface(MarsGeo.dir(10.0, -60.0), 3.0)
	main.set_map_mode(0)
	await save("13_tempo_terraformado")
