extends "res://tests/test_suite.gd"
## A usina de chuva: cada colônia força chuva ao redor, mesmo no interior seco de um continente.

const MarsGeo = preload("res://scripts/data/mars_geo.gd")


func run() -> void:
	var c = main.climate
	for p in [["temperature", 0.9], ["atmosphere", 0.8], ["h2o", 0.6]]:
		main.planet.set_control(p[0], p[1])
	main._process(3000.0)  # gelo derrete devagar (ICE_RATE): avança o bastante pro oceano encher antes do clima
	main.advance_climate(1500.0, 1.0)

	# Acha uma célula de terra, plana (sem montanha), seca e de clima ameno: o interior do continente,
	# não o polo (lá nem usina de chuva esquenta o bastante pra vegetação pegar).
	var idx := -1
	for jj in range(int(c.H * 0.35), int(c.H * 0.65)):
		for ii in c.W:
			var k: int = jj * int(c.W) + ii
			if c.hgt[k] >= main.planet.sea_level and c.lift[k] == 0.0 and c.rain[k] < 1e-5:
				idx = k
				break
		if idx >= 0:
			break
	if idx < 0:
		return fail("não achei uma célula seca de interior pra testar a usina de chuva")
	var j: int = idx / int(c.W)
	var i: int = idx % int(c.W)
	var lat: float = (0.5 - (j + 0.5) / float(c.H)) * 180.0
	var lon: float = ((i + 0.5) / float(c.W) - 0.5) * 360.0

	# Fundar uma colônia ali (sem passar pela UI) liga a usina de chuva: deveria chover e crescer vegetação.
	c.set_industry([MarsGeo.dir(lat, lon)])
	if c.industry[idx] <= 0.0:
		return fail("a usina não alcançou a célula escolhida")
	main.advance_climate(1500.0, 1.0)
	if c.rain[idx] <= 0.0 or c.veg[idx] <= 0.0:
		return fail("a usina de chuva deveria fazer chover e crescer vegetação numa célula seca do interior")
	ok("usina de chuva molha e esverdeia o interior seco (chuva %.5f, vegetação %.3f)" % [c.rain[idx], c.veg[idx]])

	# A vegetação nessa célula pode ser lida pela direção (é o que o modo explorar usa).
	if absf(c.veg_at(MarsGeo.dir(lat, lon)) - c.veg[idx]) > 1e-6:
		return fail("veg_at deveria ler a vegetação da célula sob a direção")

	# Sem colônia nenhuma, a usina desliga: a grade de indústria volta a zero em toda parte.
	c.set_industry([])
	if c.industry[idx] != 0.0:
		return fail("sem colônias a usina deveria desligar em toda a grade")
	ok("sem colônias a usina de chuva desliga")
