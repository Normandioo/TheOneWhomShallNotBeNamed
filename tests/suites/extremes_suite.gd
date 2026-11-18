extends "res://tests/test_suite.gd"
## Temperatura e pressão extremas: fervura pelo ponto de ebulição real, efeito estufa descontrolado e albedo da vegetação.

const Physics = preload("res://scripts/sim/mars_physics.gd")
const PlanetState = preload("res://scripts/sim/planet_state.gd")


func run() -> void:
	var planet: PlanetState = main.planet
	# Sem a opção, os controles param em 1; com ela, chegam a +60 °C e 5 bar.
	planet.set_control("temperature", 1.5)
	if planet.temperature > 1.0:
		return fail("sem 'Permitir extremos' a temperatura não deveria passar de 1")
	planet.set_extremes(true)
	if main.control_panel.control_max("temperature") != PlanetState.EXTREME_MAX["temperature"]:
		return fail("o slider de temperatura deveria passar a aceitar o máximo dos extremos")
	planet.set_control("h2o", 0.6)
	# 5 bar primeiro, antes de qualquer vapor: +60 °C não ferve a 5 bar (ferve só a ~152 °C), nem gera estufa.
	planet.set_control("temperature", PlanetState.EXTREME_MAX["temperature"])
	planet.set_control("atmosphere", PlanetState.EXTREME_MAX["atmosphere"])
	main._process(3000.0)  # gelo derrete devagar (ICE_RATE): avança o bastante pra deixar de ser o gargalo aqui
	if planet.vapor > 0.01 or planet.liquid < 0.5 or planet.greenhouse_c > 1.0:
		return fail("+60 °C a 5 bar não deveria ferver nem esquentar mais: vapor %.2f, líquida %.2f, estufa %.1f" % [planet.vapor, planet.liquid, planet.greenhouse_c])
	var t60 := roundi(Physics.temperature_c(planet.temperature))

	# Agora a pressão cai para 100 mbar: ferve, e o vapor começa a aquecer o ar de volta (efeito estufa).
	planet.set_control("atmosphere", log(100.0 / 6.0) / log(1000.0 / 6.0))  # 100 mbar: água ferve a ~46 °C
	main._process(60.0)
	if planet.vapor < 0.5 or planet.liquid > 0.05:
		return fail("+60 °C a 100 mbar deveria ferver o mar: vapor %.2f, líquida %.2f" % [planet.vapor, planet.liquid])
	main.advance_climate(60.0, 1.0)
	await save("13_extremo_quente")
	if planet.greenhouse_c < 20.0:
		return fail("vapor no ar deveria descontrolar o efeito estufa, aqueceu só %.1f °C" % planet.greenhouse_c)
	var gh1 := planet.greenhouse_c
	ok("extremos: %+d °C ferve o mar a 100 mbar | estufa descontrolado: +%.0f °C | vegetação média %.3f" % [t60, gh1, main.climate.mean_veg])

	# Descontrolado é descontrolado: voltar a 5 bar não desfaz o aquecimento sozinho, só a falta de água.
	planet.set_control("atmosphere", PlanetState.EXTREME_MAX["atmosphere"])
	main._process(1.0)
	if planet.greenhouse_c < gh1 - 5.0:
		return fail("o efeito estufa não deveria desaparecer só por voltar a pressão: caiu de %.1f para %.1f" % [gh1, planet.greenhouse_c])

	# Sem água, não há vapor para segurar calor: o efeito estufa se desfaz sozinho.
	planet.set_control("h2o", 0.0)
	main._process(120.0)
	if planet.greenhouse_c > 2.0:
		return fail("sem água o efeito estufa deveria sumir, ficou em %.1f °C" % planet.greenhouse_c)
	ok("sem água o efeito estufa descontrolado se desfaz sozinho (estufa %.1f -> %.1f °C)" % [gh1, planet.greenhouse_c])

	planet.set_extremes(false)
	if planet.temperature > 1.0 or planet.atmosphere > 1.0:
		return fail("desligar os extremos deveria devolver os controles a 1")
	if main.control_panel.control_max("temperature") != 1.0:
		return fail("desligar os extremos deveria devolver o limite do slider a 1")

	# Vegetação escurece a superfície: floresta plena deveria esquentar o planeta um pouco, sem virar estufa.
	planet.vegetation = 0.0
	planet.set_control("h2o", 0.3)
	planet.set_control("temperature", 0.0)
	planet.set_control("atmosphere", 0.3)
	main._process(1.0)
	var cold := Physics.temperature_c(planet.temperature)
	planet.vegetation = 1.0
	main._process(1.0)
	if absf(planet.veg_warming_c - PlanetState.VEG_ALBEDO_K) > 0.01:
		return fail("vegetação plena deveria esquentar %.1f °C por albedo, deu %.1f" % [PlanetState.VEG_ALBEDO_K, planet.veg_warming_c])
	planet.vegetation = 0.0
	ok("vegetação plena esquenta +%.1f °C por albedo (sem vegetação: %+d °C)" % [PlanetState.VEG_ALBEDO_K, roundi(cold)])
