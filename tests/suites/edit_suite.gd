extends "res://tests/test_suite.gd"
## Edição do terreno sem cena: o disco do pincel na esfera (inclusive em 180° e no polo), as quatro operações,
## e o desfazer/refazer devolvendo exatamente as alturas. Mede o tempo de uma marca do pincel.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const CommandStack = preload("res://scripts/edit/command_stack.gd")
const TerrainBrush = preload("res://scripts/edit/terrain_brush.gd")


func run() -> void:
	var terrain := Terrain.new(EvronMaps.load_height())
	var stack := CommandStack.new()
	var brush := TerrainBrush.new(terrain, stack)
	brush.roughness = 0.0  # os testes antigos medem a forma lisa; a rugosidade tem teste próprio

	# Disco: no centro peso ~1, todos os pixels a menos do raio, e área ~ πr² (pixels encolhem com a latitude).
	var here := EvronGeo.dir(30.0, 20.0)
	var d: Array = terrain.disk(here, 200.0)
	var w: PackedFloat32Array = d[1]
	var expected_px := PI * 200.0 * 200.0 / (EvronGeo.KM_PER_DEG * 360.0 / 4096.0) ** 2 / cos(deg_to_rad(30.0))
	if absf(d[0].size() / expected_px - 1.0) > 0.1:
		return fail("disco de 200 km deveria ter ~%d pixels, tem %d" % [expected_px, d[0].size()])
	if w[0] < 0.0 or w.size() == 0:
		return fail("disco vazio")
	# No limite de longitude o disco pega as duas pontas do mapa; no polo, a linha inteira.
	var cols := {}
	for idx in terrain.disk(EvronGeo.dir(0.0, 179.9), 100.0)[0]:
		cols[idx % terrain.size.x] = true
	if not (cols.has(0) and cols.has(terrain.size.x - 1)):
		return fail("disco em 179,9° deveria pegar as colunas das duas pontas")
	var pole_cols := {}
	for idx in terrain.disk(EvronGeo.dir(89.9, 0.0), 100.0)[0]:
		if idx / terrain.size.x == 0:
			pole_cols[idx % terrain.size.x] = true
	if pole_cols.size() != terrain.size.x:
		return fail("disco no polo deveria pegar a primeira linha inteira, pegou %d colunas" % pole_cols.size())
	ok("disco do pincel: área certa, atravessa 180° e cobre o polo")

	# Elevar: o centro sobe a intensidade; a borda quase nada; desfazer volta ao exato; refazer reaplica.
	var h0 := terrain.height_at(here)
	var edge_dir := EvronGeo.dir(30.0 + 190.0 / EvronGeo.KM_PER_DEG, 20.0)
	var edge0 := terrain.height_at(edge_dir)
	brush.op = TerrainBrush.Op.RAISE
	brush.radius_km = 200.0
	brush.strength = 300.0
	var t0 := Time.get_ticks_usec()
	brush.begin(here)
	var dab_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var changed := brush.end()
	var h1 := terrain.height_at(here)
	if absf(h1 - h0 - 300.0) > 15.0:
		return fail("elevar 300 m no centro deveria subir ~300 m: %.1f -> %.1f" % [h0, h1])
	if absf(terrain.height_at(edge_dir) - edge0) > 15.0:
		return fail("a borda do pincel não deveria subir quase nada")
	if not stack.can_undo() or not stack.undo_name().begins_with("Elevar"):
		return fail("a pincelada deveria virar um comando 'Elevar'")
	stack.undo()
	if terrain.height_at(here) != h0:
		return fail("desfazer deveria devolver a altura exata: %.3f != %.3f" % [terrain.height_at(here), h0])
	stack.redo()
	if terrain.height_at(here) != h1:
		return fail("refazer deveria reaplicar a mesma altura")
	stack.undo()
	ok("elevar +300 m no centro, borda intacta, desfazer exato e refazer (%d pontos; uma marca de 200 km: %.1f ms)" % [changed, dab_ms])

	# Arrastar: várias marcas viram um comando só.
	brush.op = TerrainBrush.Op.LOWER
	brush.radius_km = 100.0
	brush.begin(EvronGeo.dir(0.0, 0.0))
	for i in range(1, 11):
		brush.drag(EvronGeo.dir(0.0, i * 0.3))
	brush.end()
	stack.undo()
	if stack.can_undo():
		return fail("uma pincelada arrastada deveria ser um comando só")
	ok("pincelada arrastada = um comando na pilha")

	# Nivelar puxa para a altura do ponto inicial; suavizar diminui a variação.
	var hill := EvronGeo.dir(33.0, -39.0)  # cordilheira
	var spread_before := _spread(terrain, hill, 120.0)
	brush.op = TerrainBrush.Op.FLATTEN
	brush.strength = 500.0
	brush.radius_km = 150.0
	for i in 4:
		brush.begin(hill)
		brush.end()
	var spread_flat := _spread(terrain, hill, 120.0)
	for i in 4:
		stack.undo()
	brush.op = TerrainBrush.Op.SMOOTH
	for i in 4:
		brush.begin(hill)
		brush.end()
	var spread_smooth := _spread(terrain, hill, 120.0)
	if spread_flat > spread_before * 0.5 or spread_smooth >= spread_before:
		return fail("nivelar e suavizar deveriam reduzir a variação: %.0f -> %.0f (nivelar), %.0f (suavizar)" % [
			spread_before, spread_flat, spread_smooth])
	ok("nivelar e suavizar reduzem a variação da cordilheira (desvio %.0f m -> %.0f e %.0f m)" % [spread_before, spread_flat, spread_smooth])
	for i in 4:
		stack.undo()
	brush.roughness = 0.5
	if not _mountains(terrain, stack, brush):
		return
	if not _inland(terrain, stack, brush):
		return
	if not _erosion(terrain, stack, brush):
		return
	if not _roughness(terrain, stack, brush):
		return
	if not _valleys(terrain, stack, brush):
		return
	_cap(terrain, stack, brush)


## Montanhas: mais rugoso que Elevar, mesma semente = mesmo relevo, e desfazer exato.
func _mountains(terrain: Terrain, stack: CommandStack, brush: TerrainBrush) -> bool:
	var spot := EvronGeo.dir(-20.0, -100.0)
	brush.radius_km = 300.0
	brush.strength = 150.0
	brush.seed_value = 7
	var before := _rough(terrain, spot, 250.0)
	var h0 := terrain.height_at(spot)
	brush.op = TerrainBrush.Op.RAISE
	brush.roughness = 0.0  # o Elevar liso é a referência
	brush.strength = 900.0
	brush.begin(spot)
	brush.end()
	brush.roughness = 0.5
	brush.strength = 150.0
	var smooth_rough := _rough(terrain, spot, 250.0)
	stack.undo()
	brush.op = TerrainBrush.Op.MOUNTAINS
	brush.begin(spot)
	brush.end()
	var rough := _rough(terrain, spot, 250.0)
	var peak := terrain.height_at(spot)
	var snapshot := terrain.get_h(terrain.disk(spot, 250.0)[0][100])
	stack.undo()
	brush.begin(spot)  # mesma semente: o relevo tem de sair igual
	brush.end()
	if terrain.get_h(terrain.disk(spot, 250.0)[0][100]) != snapshot:
		fail("a mesma semente deveria dar o mesmo relevo")
		return false
	stack.undo()
	if terrain.height_at(spot) != h0:
		fail("desfazer as montanhas deveria devolver a altura exata")
		return false
	if rough < smooth_rough * 1.1 or rough < before * 2.0:
		fail("montanhas deveriam ser bem mais rugosas que elevar: %.0f m vs %.0f m (antes: %.0f m)" % [rough, smooth_rough, before])
		return false
	ok("montanhas: rugosidade %.0f m (elevar: %.0f m, terreno original: %.0f m), mesma semente = mesmo relevo, desfazer exato" % [rough, smooth_rough, before])
	return true


## Montanhas no meio do continente não criam água: nenhum pixel fica abaixo do que era, e a terra continua terra.
func _inland(terrain: Terrain, stack: CommandStack, brush: TerrainBrush) -> bool:
	var spot := Vector3.ZERO
	for lat in range(-50, 60, 5):
		for lon in range(-170, 170, 10):
			var n := EvronGeo.dir(lat, lon)
			var ok_spot := true
			for i in terrain.disk(n, 350.0)[0]:
				if terrain.get_h(i) < 150.0:
					ok_spot = false
					break
			if ok_spot:
				spot = n
				break
		if spot != Vector3.ZERO:
			break
	if spot == Vector3.ZERO:
		fail("não achei um ponto no interior do continente para o teste")
		return false
	brush.op = TerrainBrush.Op.MOUNTAINS
	brush.radius_km = 300.0
	brush.strength = 600.0
	brush.seed_value = 3
	var idx: PackedInt32Array = terrain.disk(spot, 300.0)[0]
	var before := {}
	for i in idx:
		before[i] = terrain.get_h(i)
	brush.begin(spot)
	brush.end()
	var lower := 0
	var water := 0
	for i in idx:
		if terrain.get_h(i) < before[i] - 0.001:
			lower += 1
		if terrain.get_h(i) < 0.0:
			water += 1
	stack.undo()
	if lower > 0 or water > 0:
		fail("montanhas no interior baixaram %d pixels e criaram %d de água" % [lower, water])
		return false
	ok("montanhas no interior do continente (%.1f°, %.1f°): nenhum pixel baixou e nenhum virou água" % [EvronGeo.lat_lon(spot).x, EvronGeo.lat_lon(spot).y])
	return true


## Erosão: conserva a massa e suaviza as encostas; várias passadas arredondam a cordilheira.
func _erosion(terrain: Terrain, stack: CommandStack, brush: TerrainBrush) -> bool:
	var hill := EvronGeo.dir(33.0, -39.0)  # cordilheira
	var big: PackedInt32Array = terrain.disk(hill, 500.0)[0]
	var mass0 := 0.0
	for i in big:
		mass0 += terrain.get_h(i)
	var slope0 := _rough(terrain, hill, 150.0)
	var peak0 := 0.0
	for i in terrain.disk(hill, 150.0)[0]:
		peak0 = maxf(peak0, terrain.get_h(i))
	brush.op = TerrainBrush.Op.ERODE
	brush.radius_km = 150.0
	brush.strength = 800.0
	for i in 6:
		brush.begin(hill)
		brush.end()
	var mass1 := 0.0
	for i in big:
		mass1 += terrain.get_h(i)
	var slope1 := _rough(terrain, hill, 150.0)
	var peak1 := 0.0
	for i in terrain.disk(hill, 150.0)[0]:
		peak1 = maxf(peak1, terrain.get_h(i))
	for i in 6:
		stack.undo()
	if absf(mass1 - mass0) > 1.0:
		fail("a erosão deveria conservar a massa: mudou %.2f m somados" % (mass1 - mass0))
		return false
	if slope1 >= slope0 or peak1 >= peak0:
		fail("a erosão deveria suavizar as encostas e baixar o pico: rugosidade %.0f -> %.0f m, pico %.0f -> %.0f m" % [slope0, slope1, peak0, peak1])
		return false
	ok("erosão: massa conservada (%.3f m somados), rugosidade %.0f -> %.0f m, pico %.0f -> %.0f m" % [mass1 - mass0, slope0, slope1, peak0, peak1])
	return true


## A rugosidade dá forma irregular ao Elevar, e em Montanhas troca maciço arredondado por cristas finas.
func _roughness(terrain: Terrain, stack: CommandStack, brush: TerrainBrush) -> bool:
	var spot := EvronGeo.dir(-20.0, -100.0)
	brush.seed_value = 5
	brush.radius_km = 250.0
	brush.op = TerrainBrush.Op.RAISE
	brush.strength = 400.0
	var shapes := []
	for r in [0.0, 1.0]:
		brush.roughness = r
		brush.begin(spot)
		brush.end()
		shapes.append(_rough(terrain, spot, 200.0))
		stack.undo()
	brush.op = TerrainBrush.Op.MOUNTAINS
	brush.strength = 300.0
	var crest := []
	for r in [0.0, 1.0]:
		brush.roughness = r
		brush.begin(spot)
		brush.end()
		var total := 0.0
		for i in terrain.disk(spot, 250.0)[0]:
			total += terrain.get_h(i)
		crest.append(total)
		stack.undo()
	brush.roughness = 0.5
	if shapes[1] < shapes[0] * 1.3:
		fail("rugosidade 100%% deveria deixar o Elevar bem mais irregular: %.0f m vs %.0f m" % [shapes[1], shapes[0]])
		return false
	if crest[1] >= crest[0] * 0.9:
		fail("em Montanhas, rugosidade alta (cristas finas) deveria levantar menos volume que a baixa (maciço): %.0f vs %.0f" % [crest[1], crest[0]])
		return false
	ok("rugosidade: Elevar %.0f -> %.0f m de irregularidade; Montanhas, volume levantado %.0f -> %.0f (maciço -> cristas finas)" % [shapes[0], shapes[1], crest[0], crest[1]])
	return true


## Vales: entalham mais onde passa mais água, nunca criam água nem poços, e desfazer é exato.
func _valleys(terrain: Terrain, stack: CommandStack, brush: TerrainBrush) -> bool:
	var hill := EvronGeo.dir(33.0, -39.0)  # cordilheira
	var idx: PackedInt32Array = terrain.disk(hill, 250.0)[0]
	var before := {}
	for i in idx:
		before[i] = terrain.get_h(i)
	brush.op = TerrainBrush.Op.VALLEYS
	brush.radius_km = 250.0
	brush.strength = 300.0
	brush.begin(hill)
	var flow: Dictionary = brush.last_flow.duplicate()
	brush.end()
	var cut_high := 0.0
	var n_high := 0
	var cut_low := 0.0
	var n_low := 0
	var water := 0
	var total := 0.0
	for i in idx:
		var cut: float = before[i] - terrain.get_h(i)
		total += cut
		if before[i] > 1.0 and terrain.get_h(i) < 1.0:
			water += 1
		if cut < -0.001:
			fail("vales não deveriam levantar terreno: pixel %d subiu %.1f m" % [i, -cut])
			return false
		var a: float = flow.get(i, 1.0)
		if a >= 6.0:
			cut_high += cut
			n_high += 1
		elif a <= 1.0:
			cut_low += cut
			n_low += 1
	stack.undo()
	for i in idx:
		if terrain.get_h(i) != before[i]:
			fail("desfazer os vales deveria devolver a altura exata")
			return false
	if water > 0:
		fail("vales criaram %d pixels de água" % water)
		return false
	if total < 100.0 or n_high == 0 or n_low == 0:
		fail("vales deveriam remover terreno: total %.0f m, %d pixels de canal, %d de espigão" % [total, n_high, n_low])
		return false
	var mean_high := cut_high / n_high
	var mean_low := cut_low / n_low
	if mean_high < mean_low * 3.0:
		fail("o entalhe deveria ser bem maior nos canais (muita água) que nos espigões: %.1f m vs %.1f m" % [mean_high, mean_low])
		return false
	ok("vales: canais entalhados %.1f m em média contra %.1f m nos espigões (%.0fx), nenhum pixel virou água, desfazer exato" % [mean_high, mean_low, mean_high / maxf(mean_low, 0.01)])
	return true


## Montanhas têm teto por pincelada: sem platôs altos e largos.
func _cap(terrain: Terrain, stack: CommandStack, brush: TerrainBrush) -> bool:
	var spot := EvronGeo.dir(-50.0, -60.0)
	brush.op = TerrainBrush.Op.MOUNTAINS
	brush.radius_km = 250.0
	brush.strength = 300.0
	brush.roughness = 0.0
	brush.seed_value = 9
	var idx: PackedInt32Array = terrain.disk(spot, 250.0)[0]
	var before := {}
	for i in idx:
		before[i] = terrain.get_h(i)
	brush.begin(spot)
	for i in 12:  # muitas marcas no mesmo lugar: sem teto, o platô subiria sem parar
		brush._dab(spot)
	brush.end()
	var rise := 0.0
	for i in idx:
		rise = maxf(rise, terrain.get_h(i) - before[i])
	stack.undo()
	var cap: float = brush.strength * TerrainBrush.MOUNTAIN_GAIN * TerrainBrush.MOUNTAIN_CAP
	brush.roughness = 0.5
	if rise > cap + 1.0:
		fail("o ganho de uma pincelada passou do teto: %.0f m (teto %.0f m)" % [rise, cap])
		return false
	ok("montanhas: 13 marcas no mesmo ponto sobem no máximo %.0f m (teto %.0f m)" % [rise, cap])
	return true


## Rugosidade: diferença média de altura entre pixels vizinhos num disco.
func _rough(terrain: Terrain, n: Vector3, km: float) -> float:
	var s := 0.0
	var idx: PackedInt32Array = terrain.disk(n, km)[0]
	for i in idx:
		s += absf(terrain.get_h(i) - terrain.get_h(i + 1))
	return s / idx.size()


## Desvio padrão das alturas num disco.
func _spread(terrain: Terrain, n: Vector3, km: float) -> float:
	var s := 0.0
	var s2 := 0.0
	var idx: PackedInt32Array = terrain.disk(n, km)[0]
	for i in idx:
		var h := terrain.get_h(i)
		s += h
		s2 += h * h
	var m := s / idx.size()
	return sqrt(maxf(s2 / idx.size() - m * m, 0.0))
