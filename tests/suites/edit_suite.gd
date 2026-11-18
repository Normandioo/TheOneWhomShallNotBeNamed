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
