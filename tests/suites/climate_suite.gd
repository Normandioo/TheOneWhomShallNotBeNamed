extends "res://tests/test_suite.gd"
## O clima na cena: Marte seco, ciclo vento -> vapor -> nuvem -> chuva -> vegetação, estações, correntes
## e as capturas dos modos de mapa.

const MarsGeo = preload("res://scripts/data/mars_geo.gd")
const Climate = preload("res://scripts/sim/climate.gd")
const MapLegends = preload("res://scripts/ui/map_legends.gd")


func run() -> void:
	var c: Climate = main.climate
	var planet = main.planet
	# Marte de hoje: o ar é fino demais, não pode haver nuvem, chuva nem vegetação.
	planet.set_control("temperature", 0.0)
	planet.set_control("atmosphere", 0.0)
	main._process(120.0)
	main.advance_climate(300.0, 1.0)
	# Inclui a colônia fundada antes: a usina de chuva também não pode fazer chover no Marte de hoje.
	if max_of(c.industry) <= 0.0:
		return fail("o teste do Marte seco deveria ter uma colônia (usina de chuva) ativa")
	if c.mean_rain > 1e-4 or c.mean_cloud > 1e-3 or c.mean_haze > 1e-3 or c.mean_veg > 1e-3:
		return fail("Marte seco não deveria ter clima: chuva %s nuvem %s nuvem fina %s veg %s" % [c.mean_rain, c.mean_cloud, c.mean_haze, c.mean_veg])
	ok("Marte de hoje sem nuvem, chuva ou vegetação")

	# Planeta quente e com ar: o ciclo vento -> vapor -> nuvem -> chuva -> vegetação tem que aparecer.
	for p in [["temperature", 0.9], ["atmosphere", 0.8], ["h2o", 0.6]]:
		planet.set_control(p[0], p[1])
	main._process(3000.0)  # gelo derrete devagar (ICE_RATE): avança o bastante pro oceano encher antes do clima
	var t0 := Time.get_ticks_usec()
	main.advance_climate(1500.0, 1.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 1500.0
	print("clima: %.1f ms por passo | nuvem média %.4f (máx %.3f) | chuva média %.5f (máx %.4f) | umidade máx %.3f | vegetação média %.3f (máx %.2f)" % [
		ms, c.mean_cloud, max_of(c.cloud), c.mean_rain, max_of(c.rain), max_of(c.q), c.mean_veg, max_of(c.veg)])
	if c.mean_cloud <= 0.0 or c.mean_rain <= 0.0 or c.mean_veg <= 0.0:
		return fail("planeta quente deveria ter nuvem, chuva e vegetação")
	# Chuva orográfica: em terra, o lado em que o ar sobe a montanha deve chover mais que o plano.
	var up_rain := 0.0
	var up_n := 0
	var flat_rain := 0.0
	var flat_n := 0
	for i in Climate.N:
		if c.hgt[i] < planet.sea_level:
			continue
		if c.lift[i] > 0.3:
			up_rain += c.rain[i]
			up_n += 1
		elif c.lift[i] == 0.0:
			flat_rain += c.rain[i]
			flat_n += 1
	print("chuva em terra: encosta %.5f (%d células) | sem subida %.5f (%d células)" % [up_rain / maxi(up_n, 1), up_n, flat_rain / maxi(flat_n, 1), flat_n])
	ok("ciclo de clima completo")

	# Nuvem no interior: longe do mar (7+ células, ~17°) não pode ser deserto de nuvem só porque o vapor se esgota
	# na costa e nas serras. Convecção e sistemas de tempo levam nuvem ao meio do continente.
	var inland := _cloud_cover(c, planet.sea_level, 7, 99)
	var coast := _cloud_cover(c, planet.sea_level, 1, 2)
	print("cobertura de nuvem (>0,01): interior %.2f, costa %.2f" % [inland, coast])
	if inland < 0.12 or inland < coast * 0.2:
		return fail("o interior do continente deveria ter nuvem (antes: 7%% do interior contra 41%% da costa): interior %.2f, costa %.2f" % [inland, coast])
	ok("nuvens chegam ao interior do continente (cobertura %.0f%% no interior, %.0f%% na costa)" % [inland * 100.0, coast * 100.0])

	# Chuva em episódios, não sem parar: em cada instante só parte da terra chove, e a mesma célula alterna entre
	# chover e não chover (antes de reequilibrar, 5x mais chuva e quase tudo chovendo o tempo todo).
	if c.mean_rain > 0.01:
		return fail("a chuva média deveria ser de poucos milésimos (era 0,0037 no começo; 0,018 era demais): %.4f" % c.mean_rain)
	var episodes := _rain_episodes(c, planet.sea_level)
	if episodes.x > 0.5 or episodes.y < 0.4:
		return fail("a chuva deveria vir em episódios: %.0f%% da terra chove por instante (máx 50%%), %.0f%% das células que choveram alternam (mín 40%%)" % [
			episodes.x * 100.0, episodes.y * 100.0])
	ok("chuva em episódios: %.0f%% da terra chove por instante, %.0f%% das células que choveram alternam" % [episodes.x * 100.0, episodes.y * 100.0])
	if c.max_row_shear() > 3.5:
		return fail("o padrão dos sistemas de tempo deveria ter pouco cisalhamento entre linhas (senão vira faixas): %.1f células" % c.max_row_shear())

	# Nem toda nuvem chove: há nuvem fina em lugares sem nuvem de chuva, e ela cobre só parte do planeta.
	var thin_only := 0
	var any_haze := 0
	var land_cells := 0
	for k in Climate.N:
		if c.hgt[k] < planet.sea_level:
			continue
		land_cells += 1
		if c.haze[k] > 0.1:
			any_haze += 1
			if c.cloud[k] < 0.01:
				thin_only += 1
	var thin_share := float(thin_only) / land_cells
	var haze_share := float(any_haze) / land_cells
	if thin_share < 0.05 or haze_share > 0.85 or c.mean_haze <= 0.0:
		return fail("deveria haver nuvem fina sem chuva em parte da terra (sem cobrir tudo): fina sem chuva %.2f, fina %.2f" % [thin_share, haze_share])
	ok("nuvem que não chove: fina em %.0f%% da terra, %.0f%% só dela (sem nuvem de chuva)" % [haze_share * 100.0, thin_share * 100.0])
	if max_of(c.lift) > Climate.LIFT_MAX + 1e-6:
		return fail("a subida por relevo deveria ter teto de %s: %s" % [Climate.LIFT_MAX, max_of(c.lift)])

	# A vegetação média chegou ao planeta pelo sinal do passo do clima.
	if absf(planet.vegetation - c.mean_veg) > 1e-6:
		return fail("a vegetação média do clima deveria chegar ao planeta: %s vs %s" % [planet.vegetation, c.mean_veg])

	# Floresta recicla água: a mesma diferença para a saturação, vegetação plena devolve mais que solo seco.
	if Climate.land_evap_rate(1.0, 0.0, 1.0) <= Climate.land_evap_rate(1.0, 0.0, 0.0):
		return fail("vegetação deveria reciclar água para o ar mesmo com solo seco")
	ok("vegetação recicla água para o ar (transpiração)")

	# Estações: no verão do norte, o polo norte fica mais quente que a média e o sul mais frio.
	c.season_t = 0.29  # Ls ~90°
	c.season_amp = 1.0
	main.advance_climate(10.0, 1.0)
	if not (c.season[0] > 5.0 and c.season[c.H - 1] < -5.0):
		return fail("verão do norte (Ls %d°): polo norte %+.1f °C, polo sul %+.1f °C" % [c.ls, c.season[0], c.season[c.H - 1]])
	ok("estações (Ls %d°): polo norte %+.1f °C, polo sul %+.1f °C" % [c.ls, c.season[0], c.season[c.H - 1]])

	# Tundra: no frio (< -12 °C) em terra firme só cresce vegetação baixa (musgo e líquen), nunca floresta.
	var tundra := 0
	var tundra_sum := 0.0
	for k in c.N:
		if c.hgt[k] >= planet.sea_level and c.temp_c[k] < -12.0:
			tundra_sum += c.veg[k]
			if c.veg[k] > 0.01:
				tundra += 1
	var tundra_mean := tundra_sum / maxi(tundra, 1)
	if tundra == 0 or tundra_mean > Climate.TUNDRA_COVER:
		return fail("no frio deveria haver tundra, com vegetação média abaixo de %.2f: %d células, média %.2f" % [Climate.TUNDRA_COVER, tundra, tundra_mean])
	ok("tundra: %d células frias com vegetação baixa (média %.2f)" % [tundra, tundra_mean])

	# Neve: só se acumula onde está frio; chuva "de agora" é só parte do que choveu há pouco.
	var snowy := 0
	var snow_temp := 0.0
	var recent := 0
	var now := 0
	for k in c.N:
		if c.hgt[k] < planet.sea_level:
			continue
		if c.snow[k] > 0.02:
			snowy += 1
			snow_temp += c.temp_c[k]
		if c.rain[k] > 0.002:
			recent += 1
		if c.raining[k] > 0.002:
			now += 1
	print("neve: %d células (temperatura média %.1f °C) | chuva recente %d, chovendo agora %d" % [snowy, snow_temp / maxi(snowy, 1), recent, now])
	if snowy == 0 or snow_temp / snowy > 3.0:
		return fail("deveria haver neve em terra fria: %d células, %.1f °C" % [snowy, snow_temp / maxi(snowy, 1)])
	if recent == 0 or now >= recent:
		return fail("chovendo agora (%d células) deveria ser só uma parte da chuva recente (%d)" % [now, recent])
	ok("neve em %d células frias; chovendo agora em %d das %d com chuva recente" % [snowy, now, recent])

	if not _monsoon(c, planet.sea_level):
		return
	if not _currents():
		return
	if not _air_masses():
		return

	main.space.look_from_sun(3.0)  # o lado iluminado, para ver as nuvens
	await save("8_clima_nuvens")
	main.set_map_mode(3)
	await save("9_umidade_chuva")
	main.set_map_mode(4)
	await save("10_vento")
	main.set_map_mode(1)
	await save("10b_temperatura")
	main.space.look_at_surface(MarsGeo.dir(35.0, 60.0), 3.0)
	main.set_map_mode(5)
	await save("10c_correntes")
	main.space.look_at_surface(MarsGeo.dir(35.0, 60.0), 1.5)
	await save("10d_correntes_plano")
	# Mapa de altitude: o shader e a legenda têm o mesmo número de modos, e Olympus Mons cai na última faixa.
	if MapLegends.MODES.size() != 8 or MapLegends.MODES[6]["title"] != "Altitude" or MapLegends.MODES[7]["menu"] != "Mapa: massas de ar":
		return fail("os modos 6 e 7 do mapa deveriam ser a altitude e as massas de ar")
	main.set_map_mode(6)
	main.space.look_at_surface(MarsGeo.dir(10.0, -120.0), 3.0)  # Tharsis: Olympus Mons e os vulcões
	await save("10e_altitude")
	main.set_map_mode(7)
	main.space.look_from_sun(3.0)  # o lado iluminado
	await save("10f_massas_de_ar")
	main.set_map_mode(4)
	main.space.look_at_surface(MarsGeo.dir(10.0, -60.0), 1.5)
	await save("11_vento_plano")
	main.set_map_mode(0)
	main.space.look_at_surface(MarsGeo.dir(10.0, -60.0), 1.5)
	await save("12_plano_clima")

	_chunked_equals_whole()


## Observa a chuva (média recente) em 30 instantes: devolve Vector2(fração média da terra chovendo por instante,
## fração das células que já choveram e alternam entre chover e não chover).
func _rain_episodes(c: Climate, sea: float) -> Vector2:
	var counts := PackedInt32Array()
	counts.resize(Climate.N)
	var land := 0
	for k in Climate.N:
		if c.hgt[k] >= sea:
			land += 1
	var rainy := 0.0
	for snapshot in 30:
		main.advance_climate(8.0, 1.0)
		var n := 0
		for k in Climate.N:
			if c.hgt[k] >= sea and c.rain[k] > 0.002:
				n += 1
				counts[k] += 1
		rainy += float(n) / land / 30.0
	var ever := 0
	var alternate := 0
	for k in Climate.N:
		if counts[k] > 0:
			ever += 1
			if counts[k] > 2 and counts[k] < 28:
				alternate += 1
	return Vector2(rainy, float(alternate) / maxi(ever, 1))


## Fração das células de terra, entre d_min e d_max células de distância do mar, com nuvem acima de 0,01.
func _cloud_cover(c: Climate, sea: float, d_min: int, d_max: int) -> float:
	var total := 0
	var cloudy := 0
	for j in range(6, c.H - 6):  # sem os polos, onde o gelo e a noite polar distorcem
		for i in c.W:
			if c.hgt[j * c.W + i] < sea:
				continue
			var d := _distance_to_sea(c, sea, i, j)
			if d < d_min or d > d_max:
				continue
			total += 1
			if c.cloud[j * c.W + i] > 0.01:
				cloudy += 1
	return float(cloudy) / maxi(total, 1)


## Distância (em células, máx 9) da célula (i, j) ao mar mais próximo; 99 se não há mar por perto.
func _distance_to_sea(c: Climate, sea: float, i: int, j: int) -> int:
	for r in range(1, 10):
		for dj in range(-r, r + 1):
			var jj := j + dj
			if jj < 0 or jj >= c.H:
				continue
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) == r and c.hgt[jj * c.W + posmod(i + di, c.W)] < sea:
					return r
	return 99


## Brisa e monção: no verão do norte a terra esquenta mais que o mar e o vento térmico sopra do mar para a terra
## (nas costas do norte); no mesmo instante é inverno no sul, e o sopro se inverte (da terra para o mar).
func _monsoon(c: Climate, sea: float) -> bool:
	c.season_t = 0.29  # Ls ~90°: verão no norte
	c.season_amp = 1.0
	main.advance_climate(40.0, 1.0)
	var gain: float = c.WIND_CELLS_PER_S * (0.3 + 0.7 * main.planet.atmosphere)
	var north := 0.0
	var north_n := 0
	var south := 0.0
	var south_n := 0
	for j in range(4, c.H - 4):
		var lat := 90.0 - (j + 0.5) * 180.0 / c.H
		if absf(lat) < 20.0 or absf(lat) > 60.0:
			continue
		for i in c.W:
			var k: int = j * c.W + i
			if c.hgt[k] < sea:
				continue
			# direção (leste, norte) para o mar mais próximo, nas 5x5 células em volta
			var to_sea := Vector2.ZERO
			for dj in range(-2, 3):
				for di in range(-2, 3):
					if c.hgt[(j + dj) * c.W + posmod(i + di, c.W)] < sea:
						to_sea += Vector2(di, -dj)
			if to_sea == Vector2.ZERO:
				continue
			var eddy_v: float = c._eddy_noise(i + 7, posmod(j + 5, c.H)) * c._eddy_amp[j] * c.EDDY_WIND  # o vento dos sistemas de tempo não conta
			var thermal := Vector2(c.wind_u[k] / gain - c.wu[k], c.wind_v[k] / gain - c.wv[k] - eddy_v)
			# nem o catabático (ar frio descendo a encosta); a neve já é a deste passo, então a conta é aproximada
			thermal -= Vector2(c._down_u[k], c._down_v[k]) * c.KATABATIC_K * maxf(smoothstep(0.0, -15.0, c.season[j]), c.snow[k])
			var onshore := -thermal.dot(to_sea.normalized())
			if lat > 0.0:
				north += onshore
				north_n += 1
			else:
				south += onshore
				south_n += 1
	var north_mean := north / maxi(north_n, 1)
	var south_mean := south / maxi(south_n, 1)
	print("vento térmico em direção à terra (costas, 20-60°): verão do norte %+.3f, inverno do sul %+.3f" % [north_mean, south_mean])
	if north_mean < 0.02 or south_mean > -0.02:
		fail("monção: no verão do norte o vento deveria soprar do mar para a terra (%+.3f) e no inverno do sul o contrário (%+.3f)" % [north_mean, south_mean])
		return false
	ok("brisa e monção: vento do mar para a terra no verão (%+.2f), da terra para o mar no inverno (%+.2f)" % [north_mean, south_mean])
	return true


## Correntes: só no mar, nunca apontando para dentro da terra, e levando calor de um lugar a outro.
func _currents() -> bool:
	var c: Climate = main.climate
	var sea: float = main.planet.sea_level
	var cur_n := 0
	var max_an := 0.0
	for j in c.H:
		for i in c.W:
			var k: int = j * c.W + i
			var cu: float = c.cur_u[k]
			var cv: float = c.cur_v[k]
			max_an = maxf(max_an, absf(c.oa[k]))
			if c.hgt[k] >= sea:
				if cu != 0.0 or cv != 0.0:
					fail("há corrente em terra na célula %d,%d" % [i, j])
					return false
				continue
			if cu != 0.0 or cv != 0.0:
				cur_n += 1
			if cu != 0.0 and c.hgt[j * c.W + (i + (1 if cu > 0.0 else c.W - 1)) % c.W] >= sea:
				fail("corrente em %d,%d aponta para a terra (leste/oeste)" % [i, j])
				return false
			if cv != 0.0:
				var jn: int = j - 1 if cv > 0.0 else j + 1
				if jn < 0 or jn >= c.H or c.hgt[jn * c.W + i] >= sea:
					fail("corrente em %d,%d aponta para a terra (norte/sul)" % [i, j])
					return false
	print("correntes: %d células de mar com corrente | maior anomalia de temperatura do mar %.1f °C" % [cur_n, max_an])
	if cur_n == 0 or max_an < 2.0:
		fail("deveria haver correntes carregando calor")
		return false
	ok("correntes oceânicas")
	return true


## Massas de ar, frentes, foehn, ressurgência e tempestades pelo contraste (docs/pesquisa-atmosfera.md §9).
## Roda depois de _monsoon: o planeta está quente, com ar grosso e no verão do norte (Ls ~90°).
func _air_masses() -> bool:
	var c: Climate = main.climate
	var sea: float = main.planet.sea_level
	# Memória do ar: com o ar de hoje a temperatura é a do chão de cada lugar; com ar grosso o ar chega diferente.
	var thin := Climate.new()
	thin.setup(main.height_img)
	for k in 10:
		thin.step(1.0, -60.0, 0.0, -9000.0)
	var mem_thin := _mean_abs(thin.ta)
	var mem_thick := _mean_abs(c.ta)
	# Frentes: só numa parte pequena do planeta, e dos dois tipos.
	var warm := 0
	var cold := 0
	for k in Climate.N:
		if c.front[k] > 0.05:
			warm += 1
		elif c.front[k] < -0.05:
			cold += 1
	print("massas de ar: |diferença| média %.2f °C (ar de hoje %.3f) | frentes quentes %d, frias %d células" % [mem_thick, mem_thin, warm, cold])
	if mem_thin > 0.05 or mem_thick < 0.3:
		fail("o ar deveria lembrar de onde veio só com atmosfera grossa: grossa %.2f °C, a de hoje %.3f °C" % [mem_thick, mem_thin])
		return false
	if warm == 0 or cold == 0 or warm + cold > Climate.N * 0.3:
		fail("deveria haver frentes quentes e frias numa parte pequena do planeta: %d quentes, %d frias" % [warm, cold])
		return false
	ok("massas de ar levadas pelo vento (%.1f °C em média) e frentes (%d quentes, %d frias)" % [mem_thick, warm, cold])

	# Foehn: o ar que desce a serra (ao nível zero, comparado à média da linha) é mais quente que o que sobe.
	var lee := 0.0
	var lee_n := 0
	var wind := 0.0
	var wind_n := 0
	for j in c.H:
		var row := 0.0
		for i in c.W:
			row += c._theta[j * c.W + i]
		row /= c.W
		for i in c.W:
			var k: int = j * c.W + i
			if c.hgt[k] < sea:
				continue
			if c.sink[k] > 0.5:
				lee += c._theta[k] - row
				lee_n += 1
			elif c.lift[k] > 0.5:
				wind += c._theta[k] - row
				wind_n += 1
	lee /= maxi(lee_n, 1)
	wind /= maxi(wind_n, 1)
	print("foehn: ar descendo a serra %+.2f °C (%d células), subindo %+.2f °C (%d células), relativo à linha" % [lee, lee_n, wind, wind_n])
	if lee_n == 0 or lee <= wind:
		fail("o lado de baixo da serra deveria ser mais quente que o de cima: descendo %+.2f, subindo %+.2f" % [lee, wind])
		return false
	ok("foehn: sotavento %.1f °C mais quente que barlavento" % (lee - wind))

	# Ressurgência: onde a corrente se afasta da costa sobe água fria do fundo. (Não comparar com o resto do mar da
	# mesma latitude: as correntes, sem giro de volta, deixam a faixa de 45-60°N ~10 °C fria.)
	var up_d := 0.0
	var up_n := 0
	for k in Climate.N:
		if c.hgt[k] < sea and c.upwell[k] > 0.5:
			up_d += c.oa[k]
			up_n += 1
	up_d /= maxi(up_n, 1)
	print("ressurgência: %d células, anomalia do mar %+.2f °C" % [up_n, up_d])
	if up_n == 0 or up_d > -2.0:
		fail("a ressurgência deveria esfriar o mar na costa: %+.2f °C" % up_d)
		return false
	ok("ressurgência esfria o mar em %d células da costa (%.1f °C)" % [up_n, up_d])

	# Tempestades pelo contraste: as latitudes médias do sul (continente, sem o mar para amortecer) têm mais
	# tempestade no inverno (agora, Ls ~90°) que no verão (Ls ~270°).
	var winter := _storms_south(c)
	var itcz_n := _itcz(c)
	var kat := _katabatic(c, sea)
	c.season_t = 0.79
	main.advance_climate(40.0, 1.0)
	var summer := _storms_south(c)
	var itcz_s := _itcz(c)
	# ZCIT: os alísios se encontram no hemisfério de verão (norte em Ls 90°, sul em Ls 270°).
	print("ZCIT (encontro dos alísios): Ls 90° %+.1f° (equador térmico %+.1f°), Ls 270° %+.1f°" % [itcz_n.x, itcz_n.y, itcz_s.x])
	if itcz_n.x < 3.0 or itcz_s.x > -3.0:
		fail("a ZCIT deveria ir para o hemisfério de verão: Ls 90° %+.1f°, Ls 270° %+.1f°" % [itcz_n.x, itcz_s.x])
		return false
	ok("ZCIT anda com a estação: %+.0f° no verão do norte, %+.0f° no verão do sul" % [itcz_n.x, itcz_s.x])
	# Catabático: em encosta, o vento desce mais no frio do inverno (sul em Ls 90°) que no verão (norte).
	print("vento encosta abaixo: inverno %+.3f, verão %+.3f (células/s por célula de encosta)" % [kat.x, kat.y])
	if kat.x <= kat.y + 0.05:
		fail("o ar frio do inverno deveria escorrer encosta abaixo: inverno %+.3f, verão %+.3f" % [kat.x, kat.y])
		return false
	ok("ventos catabáticos no inverno (%+.2f contra %+.2f no verão)" % [kat.x, kat.y])
	print("força das tempestades a 30-60°S: inverno %.2f, verão %.2f" % [winter, summer])
	if winter <= summer * 1.1:
		fail("o inverno deveria ter mais tempestade que o verão: %.2f contra %.2f" % [winter, summer])
		return false
	ok("tempestades mais fortes no inverno (%.2f contra %.2f no verão)" % [winter, summer])
	return true


## Vector2(latitude onde o vento norte-sul médio das faixas troca de sinal perto do equador, itcz_lat do clima).
static func _itcz(c: Climate) -> Vector2:
	var prev := 0.0
	for j in c.H:
		var lat := 90.0 - (j + 0.5) * 180.0 / c.H
		var m := 0.0
		for i in c.W:
			m += c.wv[j * c.W + i]
		m /= c.W
		if absf(lat) < 35.0 and prev < 0.0 and m > 0.0:  # ao norte o ar desce para o sul, ao sul sobe para o norte
			return Vector2(lat + 1.25, c.itcz_lat)
		prev = m
	return Vector2(INF, c.itcz_lat)


## Componente média do vento encosta abaixo em terra inclinada: Vector2(inverno: sul a 30-70°, verão: norte a 30-70°).
static func _katabatic(c: Climate, sea: float) -> Vector2:
	var sums := Vector2.ZERO
	var counts := Vector2.ZERO
	for j in c.H:
		var lat := 90.0 - (j + 0.5) * 180.0 / c.H
		if absf(lat) < 30.0 or absf(lat) > 70.0:
			continue
		for i in c.W:
			var k: int = j * c.W + i
			var down := Vector2(c._down_u[k], c._down_v[k])
			if c.hgt[k] < sea or down.length() < 0.3:
				continue
			var along := Vector2(c.wind_u[k], c.wind_v[k]).dot(down.normalized())
			if lat < 0.0:
				sums.x += along
				counts.x += 1
			else:
				sums.y += along
				counts.y += 1
	return Vector2(sums.x / maxf(counts.x, 1.0), sums.y / maxf(counts.y, 1.0))


static func _storms_south(c: Climate) -> float:
	var s := 0.0
	for j in c.H:
		var lat := 90.0 - (j + 0.5) * 180.0 / c.H
		if lat <= -30.0 and lat >= -60.0:
			s += c._eddy_amp[j]
	return s


static func _mean_abs(a: PackedFloat32Array) -> float:
	var s := 0.0
	for x in a:
		s += absf(x)
	return s / a.size()


## O passo em pedaços (o que o jogo roda a cada quadro) tem que dar o mesmo resultado que o passo inteiro.
func _chunked_equals_whole() -> void:
	var a := Climate.new()
	var b := Climate.new()
	a.setup(main.height_img)
	b.setup(main.height_img)
	for k in 20:
		a.step(1.0, 10.0, 0.8, 500.0)
		b.step_begin(1.0, 10.0, 0.8, 500.0)
		for j0 in range(0, a.H, 12):
			b.step_rows(j0, mini(j0 + 12, a.H))
		b.step_end()
	if a.cloud != b.cloud or a.haze != b.haze or a.veg != b.veg or a.q != b.q or a.sst != b.sst or a.temp_c != b.temp_c or a.ta != b.ta \
			or a.front != b.front:
		return fail("passo em pedaços difere do passo inteiro")
	ok("passo em pedaços = passo inteiro")
