extends "res://tests/test_suite.gd"
## A simulação sem cena: estado do planeta, curva do nível do mar, calendário e terraformação automática.
## Roda sem nenhum nó, o que só é possível porque a simulação não depende da interface.

const MolaReader = preload("res://scripts/data/mola_reader.gd")
const Climate = preload("res://scripts/sim/climate.gd")
const Hypsometry = preload("res://scripts/sim/hypsometry.gd")
const PlanetState = preload("res://scripts/sim/planet_state.gd")
const AutoTerraformer = preload("res://scripts/sim/auto_terraformer.gd")
const GameClock = preload("res://scripts/sim/game_clock.gd")


func run() -> void:
	var img := MolaReader.load_global_height()
	var climate := Climate.new()
	climate.setup(img)
	var hyps := Hypsometry.new()
	hyps.setup(climate.hgt, climate.weight)

	# Enchimento do relevo: valores de referência calculados do mapa de 1440x720 (grade do clima é mais grossa).
	for ref in [[34.0, -4638.0], [156.0, -3653.0], [500.0, -2377.0]]:
		var lvl: float = hyps.sea_level_for(ref[0])
		if absf(lvl - ref[1]) > 250.0:
			return fail("%d m de água deveriam dar mar em ~%d m, deu %d" % [ref[0], ref[1], lvl])
	ok("nível do mar pelo relevo real (34 m de água -> %d m)" % hyps.sea_level_for(34.0))

	_planet_state(hyps)
	if failed:
		return
	_clock()
	if failed:
		return
	_auto_terraformer(hyps)


func _planet_state(hyps: Hypsometry) -> void:
	var planet := PlanetState.new(hyps)
	var events := {"controls": 0, "limits": 0, "sea": 0}  # dicionário: a lambda altera o original
	planet.control_changed.connect(func(_p: String, _v: float) -> void: events["controls"] += 1)
	planet.limits_changed.connect(func() -> void: events["limits"] += 1)
	planet.sea_level_changed.connect(func(_l: float) -> void: events["sea"] += 1)

	# Os controles param em 1, e em EXTREME_MAX com "Permitir extremos"; cada mudança avisa.
	planet.set_control("temperature", 1.5)
	if planet.temperature != 1.0 or events["controls"] != 1:
		return fail("sem extremos a temperatura deveria parar em 1 e avisar uma vez: %s, %d avisos" % [planet.temperature, events["controls"]])
	planet.set_extremes(true)
	planet.set_control("temperature", 9.0)
	if planet.temperature != PlanetState.EXTREME_MAX["temperature"] or events["limits"] != 1:
		return fail("com extremos a temperatura deveria parar em %s, está em %s" % [PlanetState.EXTREME_MAX["temperature"], planet.temperature])
	planet.set_extremes(false)
	if planet.temperature > 1.0 or events["limits"] != 2:
		return fail("desligar os extremos deveria devolver a temperatura a 1 e avisar o novo limite")
	ok("estado do planeta: controles cortados no limite e avisando por sinal")

	# Conservação: a água total sempre se divide entre líquida, gelo e vapor; o mar sobe quando o gelo derrete.
	for p in [["temperature", 0.9], ["atmosphere", 0.8], ["h2o", 0.6]]:
		planet.set_control(p[0], p[1])
	for i in 20:
		planet.step(100.0)  # 2000 anos: o gelo derrete inteiro (ICE_RATE)
		if absf(planet.liquid + planet.ice + planet.vapor - planet.h2o) > 1e-5:
			return fail("a água não se conservou: %s líquida + %s gelo + %s vapor != %s" % [planet.liquid, planet.ice, planet.vapor, planet.h2o])
	if planet.sea_level <= PlanetState.SEA_DRY or events["sea"] == 0:
		return fail("com o gelo derretido o mar deveria ter subido e avisado (nível %s)" % planet.sea_level)
	ok("ciclo da água conserva a massa e o nível do mar sobe com o degelo (%d m)" % roundi(planet.sea_level))

	# Vegetação escurece a superfície.
	planet.vegetation = 1.0
	planet.step(0.0)
	if absf(planet.veg_warming_c - PlanetState.VEG_ALBEDO_K) > 0.01:
		return fail("vegetação plena deveria esquentar %.1f °C por albedo, deu %.1f" % [PlanetState.VEG_ALBEDO_K, planet.veg_warming_c])
	ok("vegetação plena esquenta +%.1f °C por albedo" % planet.veg_warming_c)


func _clock() -> void:
	var clock := GameClock.new()
	var speeds := []
	clock.speed_changed.connect(func(s: float) -> void: speeds.append(s))
	clock.set_speed(0.0)
	var y0 := clock.year
	if clock.tick(5.0) != 0.0 or clock.year != y0:
		return fail("em pausa o calendário não deveria avançar")
	clock.set_speed(10.0)
	if absf(clock.tick(1.0) - 10.0) > 1e-9 or absf(clock.year - (y0 + 10.0)) > 1e-9:
		return fail("1 s a 10x deveria dar 10 anos")
	if clock.seasons_on:
		return fail("a 10x as estações deveriam virar a média do ano")
	clock.set_speed(0.0)
	if clock.tick(1.0) != 0.0 or clock.seasons_on:
		return fail("em pausa as estações ficam como estavam")
	clock.set_speed(0.1)
	clock.tick(0.0)
	var t0 := clock.season_t
	clock.tick(1.0 / 0.1 * GameClock.MARS_YEAR * 0.25)  # um quarto de ano marciano
	if not clock.seasons_on or absf(fposmod(clock.season_t - t0, 1.0) - 0.25) > 0.01:
		return fail("a 0.1x as estações deveriam andar com o calendário")
	clock.toggle_pause()
	clock.toggle_pause()
	if clock.time_scale != 1.0 or speeds.size() != 6:
		return fail("pausar e retomar deveria voltar a 1x e avisar cada mudança de velocidade: %s %s" % [clock.time_scale, speeds])
	ok("calendário: pausa, aceleração e estações")


## O bug que este teste pega: a terraformação automática andava ~0,004 por ano, e quando o valor passava por um
## slider de passo 0,01 cada quadro (6e-5 a 1x) arredondava para zero e ela nunca saía do lugar. Só o teste, com
## passos de 1 s, funcionava. Agora o valor vive no PlanetState e o slider só mostra.
func _auto_terraformer(hyps: Hypsometry) -> void:
	var planet := PlanetState.new(hyps)
	var auto := AutoTerraformer.new()
	for i in 600:
		auto.step(planet, 1.0 / 60.0)  # desligada: nada muda
	if planet.temperature != 0.0:
		return fail("desligada, a terraformação automática não deveria mexer em nada")
	auto.enabled = true
	for i in 600:
		auto.step(planet, 1.0 / 60.0)  # 10 s a 1x, quadro a quadro
	if absf(planet.temperature - AutoTerraformer.RATE * 10.0) > 0.001:
		return fail("10 anos a 60 quadros por segundo deveriam subir %.3f, subiu %.4f" % [AutoTerraformer.RATE * 10.0, planet.temperature])
	for i in 1000:
		auto.step(planet, 1.0)
	for p in AutoTerraformer.TARGETS:
		if absf(planet.get_control(p) - AutoTerraformer.TARGETS[p]) > 1e-6:
			return fail("%s deveria ter chegado em %s, está em %s" % [p, AutoTerraformer.TARGETS[p], planet.get_control(p)])
	ok("terraformação automática anda em passos pequenos (quadro a quadro) e para nos alvos")
