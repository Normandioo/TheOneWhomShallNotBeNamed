extends "res://tests/test_suite.gd"
## Edição do terreno sem cena: o disco do pincel na esfera (inclusive em 180° e no polo), as quatro operações,
## e o desfazer/refazer devolvendo exatamente as alturas. Mede o tempo de uma marca do pincel.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")
const Terrain = preload("res://scripts/world/Terrain.cs")
const CommandStack = preload("res://scripts/edit/command_stack.gd")
const TerrainBrush = preload("res://scripts/edit/terrain_brush.gd")


func run() -> void:
	var terrain := Terrain.new()
	terrain.Setup(EvronMaps.load_height())
	var stack := CommandStack.new()
	var brush := TerrainBrush.new(terrain, stack)
	brush.roughness = 0.0  # os testes antigos medem a forma lisa; a rugosidade tem teste próprio

	# Disco: no centro peso ~1, todos os pixels a menos do raio, e área ~ πr² (pixels encolhem com a latitude).
	var here := EvronGeo.dir(30.0, 20.0)
	var d: Array = terrain.Disk(here, 200.0)
	var w: PackedFloat32Array = d[1]
	var expected_px := PI * 200.0 * 200.0 / (EvronGeo.KM_PER_DEG * 360.0 / 4096.0) ** 2 / cos(deg_to_rad(30.0))
	if absf(d[0].size() / expected_px - 1.0) > 0.1:
		return fail("disco de 200 km deveria ter ~%d pixels, tem %d" % [expected_px, d[0].size()])
	if w[0] < 0.0 or w.size() == 0:
		return fail("disco vazio")
	# No limite de longitude o disco pega as duas pontas do mapa; no polo, a linha inteira.
	var cols := {}
	for idx in terrain.Disk(EvronGeo.dir(0.0, 179.9), 100.0)[0]:
		cols[idx % terrain.Size.x] = true
	if not (cols.has(0) and cols.has(terrain.Size.x - 1)):
		return fail("disco em 179,9° deveria pegar as colunas das duas pontas")
	var pole_cols := {}
	for idx in terrain.Disk(EvronGeo.dir(89.9, 0.0), 100.0)[0]:
		if idx / terrain.Size.x == 0:
			pole_cols[idx % terrain.Size.x] = true
	if pole_cols.size() != terrain.Size.x:
		return fail("disco no polo deveria pegar a primeira linha inteira, pegou %d colunas" % pole_cols.size())
	ok("disco do pincel: área certa, atravessa 180° e cobre o polo")

	# Elevar: o centro sobe a intensidade; a borda quase nada; desfazer volta ao exato; refazer reaplica.
	var h0 := terrain.HeightAt(here)
	var edge_dir := EvronGeo.dir(30.0 + 190.0 / EvronGeo.KM_PER_DEG, 20.0)
	var edge0 := terrain.HeightAt(edge_dir)
	brush.op = TerrainBrush.Op.RAISE
	brush.radius_km = 200.0
	brush.strength = 300.0
	var t0 := Time.get_ticks_usec()
	brush.begin(here)
	var dab_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var changed := brush.end()
	var h1 := terrain.HeightAt(here)
	if absf(h1 - h0 - 300.0) > 15.0:
		return fail("elevar 300 m no centro deveria subir ~300 m: %.1f -> %.1f" % [h0, h1])
	if absf(terrain.HeightAt(edge_dir) - edge0) > 15.0:
		return fail("a borda do pincel não deveria subir quase nada")
	if not stack.can_undo() or not stack.undo_name().begins_with("Elevar"):
		return fail("a pincelada deveria virar um comando 'Elevar'")
	stack.undo()
	if terrain.HeightAt(here) != h0:
		return fail("desfazer deveria devolver a altura exata: %.3f != %.3f" % [terrain.HeightAt(here), h0])
	stack.redo()
	if terrain.HeightAt(here) != h1:
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
	if not _cap(terrain, stack, brush):
		return
	if not _coast(terrain, stack, brush):
		return
	_long_river(terrain, stack, brush)


## Montanhas: mais rugoso que Elevar, mesma semente = mesmo relevo, e desfazer exato.
func _mountains(terrain: Terrain, stack: CommandStack, brush: TerrainBrush) -> bool:
	var spot := EvronGeo.dir(-20.0, -100.0)
	brush.radius_km = 300.0
	brush.strength = 150.0
	brush.seed_value = 7
	var before := _rough(terrain, spot, 250.0)
	var h0 := terrain.HeightAt(spot)
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
	var peak := terrain.HeightAt(spot)
	var snapshot := terrain.GetH(terrain.Disk(spot, 250.0)[0][100])
	stack.undo()
	brush.begin(spot)  # mesma semente: o relevo tem de sair igual
	brush.end()
	if terrain.GetH(terrain.Disk(spot, 250.0)[0][100]) != snapshot:
		fail("a mesma semente deveria dar o mesmo relevo")
		return false
	stack.undo()
	if terrain.HeightAt(spot) != h0:
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
			for i in terrain.Disk(n, 350.0)[0]:
				if terrain.GetH(i) < 150.0:
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
	var idx: PackedInt32Array = terrain.Disk(spot, 300.0)[0]
	var before := {}
	for i in idx:
		before[i] = terrain.GetH(i)
	brush.begin(spot)
	brush.end()
	var lower := 0
	var water := 0
	for i in idx:
		if terrain.GetH(i) < before[i] - 0.001:
			lower += 1
		if terrain.GetH(i) < 0.0:
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
	var big: PackedInt32Array = terrain.Disk(hill, 500.0)[0]
	var mass0 := 0.0
	for i in big:
		mass0 += terrain.GetH(i)
	var slope0 := _rough(terrain, hill, 150.0)
	var peak0 := 0.0
	for i in terrain.Disk(hill, 150.0)[0]:
		peak0 = maxf(peak0, terrain.GetH(i))
	brush.op = TerrainBrush.Op.ERODE
	brush.radius_km = 150.0
	brush.strength = 800.0
	for i in 6:
		brush.begin(hill)
		brush.end()
	var mass1 := 0.0
	for i in big:
		mass1 += terrain.GetH(i)
	var slope1 := _rough(terrain, hill, 150.0)
	var peak1 := 0.0
	for i in terrain.Disk(hill, 150.0)[0]:
		peak1 = maxf(peak1, terrain.GetH(i))
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
		for i in terrain.Disk(spot, 250.0)[0]:
			total += terrain.GetH(i)
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


## Vales: entalham mais onde passa mais água, depositam sedimento nas partes planas, criam rios só em terra, nunca criam
## água e desfazer é exato (alturas e rios).
func _valleys(terrain: Terrain, stack: CommandStack, brush: TerrainBrush) -> bool:
	var hill := EvronGeo.dir(33.0, -39.0)  # cordilheira
	var idx: PackedInt32Array = terrain.Disk(hill, 250.0)[0]
	var before := {}
	for i in idx:
		before[i] = terrain.GetH(i)
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
	var removed := 0.0
	var deposited := 0.0
	for i in idx:
		var cut: float = before[i] - terrain.GetH(i)
		if cut > 0.0:
			removed += cut
		else:
			deposited -= cut
		if before[i] > 1.0 and terrain.GetH(i) < 1.0:
			water += 1
		var a: float = flow.get(i, 1.0)
		if a >= 6.0:
			cut_high += cut
			n_high += 1
		elif a <= 1.0:
			cut_low += cut
			n_low += 1
	var river_px := 0
	var river_on_water := 0
	for i in idx:
		if terrain.GetRiver(i) > 0.0:
			river_px += 1
			if terrain.GetH(i) <= 1.0:
				river_on_water += 1
	stack.undo()
	var river_left := 0
	for i in idx:
		if terrain.GetH(i) != before[i]:
			fail("desfazer os vales deveria devolver a altura exata")
			return false
		if terrain.GetRiver(i) > 0.0:
			river_left += 1
	if river_left > 0:
		fail("desfazer os vales deveria apagar os rios: sobraram %d pixels" % river_left)
		return false
	if water > 0 or river_on_water > 0:
		fail("vales criaram %d pixels de água e %d de rio sobre água" % [water, river_on_water])
		return false
	if river_px < 5:
		fail("vales deveriam criar rios onde a água se junta: só %d pixels" % river_px)
		return false
	if removed < 100.0 or deposited < removed * 0.05 or deposited > removed * 0.85:
		fail("vales deveriam depositar entre 5%% e 85%% do que entalham (o resto fica como vale): removido %.0f m, depositado %.0f m" % [removed, deposited])
		return false
	var mean_high := cut_high / maxi(n_high, 1)
	var mean_low := cut_low / maxi(n_low, 1)
	if mean_high < 8.0 or mean_high < mean_low * 3.0 + 5.0:
		fail("os canais deveriam ficar >= 8 m mais fundos e bem mais que os espigões: %.1f m vs %.1f m" % [mean_high, mean_low])
		return false
	ok("vales: canais -%.1f m (espigões %.1f m), %.0f m removidos e %.0f m depositados (%.0f%%), %d pixels de rio, sem água, desfazer exato" % [
		mean_high, mean_low, removed, deposited, 100.0 * deposited / removed, river_px])
	return true


## Rio contínuo: uma pincelada longa de Vales dá um rio conectado e comprido (não trechos de um disco só).
func _long_river(terrain: Terrain, stack: CommandStack, brush: TerrainBrush) -> bool:
	var start := EvronGeo.dir(33.0, -45.0)  # cordilheira
	brush.op = TerrainBrush.Op.VALLEYS
	brush.radius_km = 200.0
	brush.strength = 300.0
	brush.begin(start)
	for i in range(1, 25):  # 25 marcas, ~1.250 km de traço
		brush.drag(EvronGeo.dir(33.0, -45.0 + i * 0.35))
	brush.end()
	# Maior componente conectada (8 vizinhos) dos pixels de rio, perto do traço.
	var pts := {}
	var width: int = terrain.Size.x
	for i in terrain.Disk(EvronGeo.dir(33.0, -41.0), 900.0)[0]:
		if terrain.GetRiver(i) > 0.0:
			pts[i] = true
	var seen := {}
	var best := 0
	var best_span := 0
	var best_rows := 0
	for p in pts:
		if seen.has(p):
			continue
		var stack_px := [p]
		seen[p] = true
		var size := 0
		var xmin := 1 << 30
		var xmax := -(1 << 30)
		var ymin := 1 << 30
		var ymax := -(1 << 30)
		while not stack_px.is_empty():
			var c: int = stack_px.pop_back()
			size += 1
			xmin = mini(xmin, c % width)
			xmax = maxi(xmax, c % width)
			ymin = mini(ymin, c / width)
			ymax = maxi(ymax, c / width)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var q: int = (c / width + dy) * width + posmod(c % width + dx, width)
					if pts.has(q) and not seen.has(q):
						seen[q] = true
						stack_px.append(q)
		if size > best:
			best = size
			best_span = xmax - xmin
			best_rows = ymax - ymin
	stack.undo()
	var left := 0
	for i in terrain.Disk(EvronGeo.dir(33.0, -41.0), 900.0)[0]:
		if terrain.GetRiver(i) > 0.0:
			left += 1
	if left > 0:
		fail("desfazer deveria apagar o rio inteiro: sobraram %d pixels" % left)
		return false
	if best < 25:
		fail("a pincelada longa deveria dar um rio conectado de >= 25 pixels, o maior tem %d" % best)
		return false
	ok("rio contínuo: maior trecho conectado de %d pixels (~%.0f km de extensão), desfeito por inteiro" % [best, maxi(best_span, best_rows) * 12.7])
	return true



## Vales numa costa: o sedimento que desce o rio não transforma mar em terra (antes do conserto, 218 pixels viravam ilha
## com estas pinceladas).
func _coast(terrain: Terrain, stack: CommandStack, brush: TerrainBrush) -> bool:
	var region: PackedInt32Array = terrain.Disk(EvronGeo.dir(-52.0, -63.0), 700.0)[0]
	var sea := []
	for i in region:
		if terrain.GetH(i) < 0.0:
			sea.append(i)
	brush.op = TerrainBrush.Op.VALLEYS
	brush.strength = 1000.0
	brush.radius_km = 400.0
	for s in 6:
		brush.begin(EvronGeo.dir(-51.0, -66.0 + s))
		for k in range(1, 10):
			brush.drag(EvronGeo.dir(-51.0 - k * 0.2, -66.0 + s + k * 0.4))
		brush.end()
	var made := 0
	for i in sea:
		if terrain.GetH(i) >= 0.0:
			made += 1
	for s in 6:
		stack.undo()
	if sea.size() < 1000:
		fail("a região do teste deveria ter mar (tem %d pixels)" % sea.size())
		return false
	if made > 0:
		fail("vales na costa transformaram %d pixels de mar em terra" % made)
		return false
	ok("vales na costa: %d pixels de mar na região, nenhum virou terra" % sea.size())
	return true

## Montanhas têm teto por pincelada: sem platôs altos e largos.
func _cap(terrain: Terrain, stack: CommandStack, brush: TerrainBrush) -> bool:
	var spot := EvronGeo.dir(-50.0, -60.0)
	brush.op = TerrainBrush.Op.MOUNTAINS
	brush.radius_km = 250.0
	brush.strength = 300.0
	brush.roughness = 0.0
	brush.seed_value = 9
	var idx: PackedInt32Array = terrain.Disk(spot, 250.0)[0]
	var before := {}
	for i in idx:
		before[i] = terrain.GetH(i)
	brush.begin(spot)
	for i in 12:  # muitas marcas no mesmo lugar: sem teto, o platô subiria sem parar
		brush._dab(spot)
	brush.end()
	var rise := 0.0
	for i in idx:
		rise = maxf(rise, terrain.GetH(i) - before[i])
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
	var idx: PackedInt32Array = terrain.Disk(n, km)[0]
	for i in idx:
		s += absf(terrain.GetH(i) - terrain.GetH(i + 1))
	return s / idx.size()


## Desvio padrão das alturas num disco.
func _spread(terrain: Terrain, n: Vector3, km: float) -> float:
	var s := 0.0
	var s2 := 0.0
	var idx: PackedInt32Array = terrain.Disk(n, km)[0]
	for i in idx:
		var h := terrain.GetH(i)
		s += h
		s2 += h * h
	var m := s / idx.size()
	return sqrt(maxf(s2 / idx.size() - m * m, 0.0))
