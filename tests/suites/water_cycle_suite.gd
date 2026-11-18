extends "res://tests/test_suite.gd"
## Ciclo da água visto na cena: Marte seco, terraformado e com a atmosfera caindo (ideia do kikuri).

const MarsGeo = preload("res://scripts/data/mars_geo.gd")


func run() -> void:
	await frames(5)
	main.space.look_at_surface(MarsGeo.dir(-20.0, 70.0), 3.0)
	await save("1_marte_seco")

	for p in [["temperature", 0.6], ["h2o", 0.6], ["atmosphere", 0.7]]:
		main.planet.set_control(p[0], p[1])
	main._process(3000.0)  # pula a transição gelo -> líquida (de propósito lenta: ICE_RATE, ~2000 anos)
	await save("2_terraformado")
	var liquid_before: float = main.planet.liquid
	var ice_before: float = main.planet.ice

	# Ideia do kikuri: a atmosfera cai -> a água líquida diminui e o gelo aumenta. Mas devagar: um oceano
	# congelando tem inércia térmica (ICE_RATE), não devia virar gelo de uma hora pra outra.
	main.planet.set_control("atmosphere", 0.25)
	main._process(1.0)
	if absf(main.planet.ice - ice_before) > 0.01:
		return fail("1 segundo não devia congelar quase nada do oceano (ICE_RATE é lento), gelo foi de %.3f pra %.3f" % [ice_before, main.planet.ice])
	main._process(2999.0)
	if not (main.planet.liquid < liquid_before and main.planet.ice > ice_before):
		return fail("atmosfera caiu, mas água/gelo não mudaram: %s/%s -> %s/%s" % [liquid_before, ice_before, main.planet.liquid, main.planet.ice])
	ok("atmosfera caiu -> líquida %.2f -> %.2f, gelo %.2f -> %.2f (devagar: ICE_RATE)" % [liquid_before, main.planet.liquid, ice_before, main.planet.ice])
	await save("3_atmosfera_caiu")

	# A interface mostra o que a simulação decidiu: o slider acompanha o controle, sem ninguém mexer nele.
	if absf(main.control_panel.control_value("atmosphere") - 0.25) > 0.01:
		return fail("o slider de atmosfera deveria mostrar 0,25, mostra %s" % main.control_panel.control_value("atmosphere"))
	ok("o slider acompanha o estado do planeta")
