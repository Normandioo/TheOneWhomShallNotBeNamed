extends "res://tests/test_suite.gd"
## Costa, lago e bioma (aceite A02), com a cena: os pincéis Terra e Mar mudam a costa e desfazem; lagos e biomas são camadas pintadas
## (o bioma nasce da imagem do Gleba sem interpolar categorias; o lago muda a água do terreno); tudo grava e relê. E o alinhamento
## entre os níveis de zoom: a pirâmide de blocos, a grade de edição (4096 × 2048) e o pixel do mapa caem no mesmo lugar.

const Geo = preload("res://scripts/data/evron_geo.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")
const TerrainBrush = preload("res://scripts/edit/terrain_brush.gd")
const TerritoryEditor = preload("res://scripts/app/territory_editor.gd")


## Um ponto de mar (ou de terra) com o outro a menos de ~100 km: para a costa.
func _near_coast(want_sea: bool) -> Vector3:
	var t = main.terrain
	for lat in range(-40, 41, 3):
		for lon in range(-170, 171, 3):
			var n := Geo.dir(lat, lon)
			var other := Geo.dir(lat, lon + 0.9)
			if (t.HeightAt(n) < -20.0) == want_sea and (t.HeightAt(other) >= 0.0) == want_sea:
				return n
	return Vector3.ZERO


func run() -> void:
	if main == null:
		return fail("esta suíte precisa da cena")
	await _coast()
	await _lakes()
	await _biomes()
	_alignment()


func _coast() -> void:
	var t = main.terrain
	var brush = main.brush
	var sea := _near_coast(true)
	var land := _near_coast(false)
	if sea == Vector3.ZERO or land == Vector3.ZERO:
		return fail("não achei costa nos mapas")
	var before_sea: float = t.HeightAt(sea)
	brush.op = TerrainBrush.Op.LAND
	brush.radius_km = 60.0
	brush.begin(sea)
	brush.end()
	if t.HeightAt(sea) != 5.0:
		return fail("Terra deveria fazer do mar terra baixa (+5 m): %.1f" % t.HeightAt(sea))
	brush.op = TerrainBrush.Op.SEA
	brush.begin(land)
	brush.end()
	if t.HeightAt(land) != -50.0:
		return fail("Mar deveria fazer da terra mar raso (−50 m): %.1f" % t.HeightAt(land))
	main.undo()
	main.undo()
	if t.HeightAt(sea) != before_sea or t.HeightAt(land) < 0.0:
		return fail("desfazer as duas pinceladas devolve a costa")
	main.redo()
	if not main.domains.registry.SaveTerrain(t):
		return fail("gravar o relevo")
	var again = load("res://scripts/world/Terrain.cs").new()
	again.Setup(EvronMaps.load_height())
	if not main.domains.registry.LoadTerrain(again) or again.HeightAt(sea) != 5.0:
		return fail("a costa nova volta ao reler o relevo gravado")
	main.undo()
	ok("costa: Terra e Mar viram o miolo do pincel em terra baixa ou mar raso; desfazem; gravam e voltam")


func _lakes() -> void:
	var t = main.terrain
	var terr = main.territories
	var land := Geo.dir(48.0, 10.0)
	for lat in range(20, 60, 2):  # terra firme, sem lago do Gleba
		land = Geo.dir(lat, 20.0)
		if t.HeightAt(land) > 200.0 and not t.IsLake(t.PixelOf(land)):
			break
	var gleba_lake := -1
	for i in range(0, t.Size.x * t.Size.y, 97):
		if t.IsLake(i) and t.GetH(i) >= 0.0:
			gleba_lake = i
			break
	if gleba_lake < 0:
		return fail("não achei um lago do Gleba")
	terr.start_data("lago", 1)
	if not terr.painting_territory or terr.territory_level != "lago":
		return fail("Pintar lagos abre o pincel na camada dos lagos")
	terr.territory_radius = 30.0
	terr.territory_begin(land)
	terr.territory_end()
	if not t.IsLake(t.PixelOf(land)):
		return fail("o lago pintado vira água no terreno")
	terr.territory_owner = 2  # o seco: tira o lago do Gleba
	terr.territory_begin(t.DirOf(gleba_lake))
	terr.territory_end()
	if t.IsLake(gleba_lake):
		return fail("pintar seco tira o lago do Gleba")
	main.undo()
	if not t.IsLake(gleba_lake):
		return fail("desfazer devolve o lago do Gleba")
	main.redo()
	terr.stop_painting()
	if terr.territory_level != "pais":
		return fail("Terminar volta ao mapa dos países")
	if not terr.save():
		return fail("gravar os lagos")
	var check = load("res://scripts/world/Territory.cs").new()
	check.Setup(t)
	if not main.domains.registry.LoadTerritoryLevel("lago", check) or check.Get(t.PixelOf(land)) != 1 or check.Get(gleba_lake) != 2:
		return fail("as edições dos lagos voltam ao reler")
	ok("lagos: pintar lago e secar o do Gleba mudam a água do terreno; desfazem; gravam e voltam")


func _biomes() -> void:
	var terr = main.territories
	var biomes = terr.layer("bioma")
	var img := EvronMaps.load_layer(TerritoryEditor.BIOME_SOURCE)
	if biomes == null or img == null:
		return fail("a camada dos biomas nasce da imagem do Gleba")
	img.convert(Image.FORMAT_RGB8)
	var colors := {}
	for c in TerritoryEditor.DATA_LEVELS.bioma:
		colors[int(c.rgb)] = int(c.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var w: int = main.terrain.Size.x
	var h: int = main.terrain.Size.y
	for k in 2000:  # cada pixel é exatamente a categoria da cor do Gleba ali (nada interpolado)
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, h - 1)
		var cpx := img.get_pixel(x * img.get_width() / w, y * img.get_height() / h)
		var want: int = colors.get((cpx.r8 << 16) | (cpx.g8 << 8) | cpx.b8, 0)
		if biomes.Get(y * w + x) != want:
			return fail("bioma do pixel %d,%d: %d, a imagem diz %d" % [x, y, biomes.Get(y * w + x), want])
	if main.domains.registry.HasTerritoryLevel("bioma"):
		return fail("o bioma do Gleba não é gravado antes de ser editado")
	var spot := Geo.dir(30.0, 40.0)
	var original: int = biomes.OwnerAt(spot)
	var steppe := 7 if original != 7 else 10
	terr.start_data("bioma", steppe)
	terr.territory_begin(spot)
	terr.territory_end()
	if biomes.OwnerAt(spot) != steppe:
		return fail("pintar o bioma")
	main.undo()
	if biomes.OwnerAt(spot) != original:
		return fail("desfazer o bioma")
	main.redo()
	main.globe.focus(spot, 2.0)
	var deadline := Time.get_ticks_msec() + 8000
	while main.gpu_sync.coast_pending() and Time.get_ticks_msec() < deadline:  # a costa é recalculada numa thread
		await frames(1)
	await frames(20)
	await save("biomas")
	terr.stop_painting()
	if not terr.save() or not main.domains.registry.HasTerritoryLevel("bioma"):
		return fail("gravar os biomas")
	var check = load("res://scripts/world/Territory.cs").new()
	check.Setup(main.terrain)
	if not main.domains.registry.LoadTerritoryLevel("bioma", check) or check.OwnerAt(spot) != steppe:
		return fail("os biomas editados voltam ao reler")
	ok("biomas: nascem iguais ao Gleba pixel a pixel (sem interpolar); pintar desfaz; gravam e voltam")


## Para pontos ao acaso (inclusive perto de 180° e dos polos): o pixel de cada nível da pirâmide (pelos limites que o globo usa para montar
## o bloco) é o pixel do mapa naquela resolução, o do nível de cima é o do de baixo dividido por 2, e o do nível 2 (4096 px) é o da grade
## de edição (Terrain.PixelOf). Depois, nos dados: o bloco do nível 3 é a média do nível 4 sem deslocamento (a diferença é mínima
## em 0 px e cresce com 1 px de deslocamento).
func _alignment() -> void:
	var bounds := func(z: int, y: int, x: int) -> Vector4:
		var dlon := 360.0 / float(2 << z)
		var dlat := 180.0 / float(1 << z)
		return Vector4(-180.0 + x * dlon, 90.0 - (y + 1) * dlat, -180.0 + (x + 1) * dlon, 90.0 - y * dlat)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 3000:
		var lat: float = rng.randf_range(-89.99, 89.99) if k > 20 else [89.99, -89.99, 0.0, 45.0][k % 4]
		var lon: float = rng.randf_range(-179.999, 179.999) if k > 20 else [179.999, -179.999][k % 2]
		var n := Geo.dir(lat, lon)
		var ll := Geo.lat_lon(n)
		var previous := Vector2i(-1, -1)
		for z in 5:
			var tx := clampi(int(floorf((ll.y + 180.0) / (360.0 / float(2 << z)))), 0, (2 << z) - 1)
			var ty := clampi(int(floorf((90.0 - ll.x) / (180.0 / float(1 << z)))), 0, (1 << z) - 1)
			var b: Vector4 = bounds.call(z, ty, tx)
			if ll.y < b.x - 1e-9 or ll.y > b.z + 1e-9 or ll.x < b.y - 1e-9 or ll.x > b.w + 1e-9:
				return fail("o ponto %s não cai no bloco %d/%d/%d" % [ll, z, ty, tx])
			var u := (ll.y - b.x) / (b.z - b.x)
			var v := (b.w - ll.x) / (b.w - b.y)
			var global := Vector2i(tx * 512 + mini(int(floorf(u * 512.0)), 511), ty * 512 + mini(int(floorf(v * 512.0)), 511))
			var size := Vector2i(1024 << z, 512 << z)
			var direct := Geo.pixel(n, size)
			if global != direct and absi(global.x - direct.x) % (size.x - 1) > 1:  # a fronteira de pixel pode cair de um lado em float
				return fail("nível %d: pixel do bloco %s, do mapa %s (lat %.4f lon %.4f)" % [z, global, direct, ll.x, ll.y])
			if previous.x >= 0 and (absi(global.x / 2 - previous.x) > 1 or absi(global.y / 2 - previous.y) > 1):
				return fail("nível %d não é o de cima dividido por 2: %s × %s" % [z, global, previous])
			previous = global
			if z == 2:
				var edit_px: int = main.terrain.PixelOf(n)
				if absi(edit_px % 4096 - global.x) > 1 or absi(edit_px / 4096 - global.y) > 1:
					return fail("a grade de edição (%d) e o bloco do nível 2 (%s) não coincidem" % [edit_px, global])
	# Nos dados: o bloco 3/2/5 contra a média 2×2 dos quatro filhos no nível 4, com 0 e com 1 px de deslocamento.
	var dir := EvronMaps.directory() + "tiles/relevo/"
	var parent := Image.load_from_file(ProjectSettings.globalize_path(dir + "3/2_5.jpg"))
	if parent == null:
		return fail("sem os blocos do relevo para conferir os dados")
	var child := Image.create(1024, 1024, false, Image.FORMAT_RGB8)
	for j in 2:
		for i in 2:
			var c := Image.load_from_file(ProjectSettings.globalize_path(dir + "4/%d_%d.jpg" % [4 + j, 10 + i]))
			c.convert(Image.FORMAT_RGB8)
			child.blit_rect(c, Rect2i(0, 0, 512, 512), Vector2i(i * 512, j * 512))
	parent.convert(Image.FORMAT_RGB8)
	var diffs: Array = []
	for shift in [0, 1, 2]:
		var total := 0.0
		for y in range(8, 504, 6):
			for x in range(8, 504, 6):
				var m := Color(0, 0, 0)
				for dy in 2:
					for dx in 2:
						m += child.get_pixel(2 * x + dx + shift, 2 * y + dy) / 4.0
				var p := parent.get_pixel(x, y)
				total += absf(p.r - m.r) + absf(p.g - m.g) + absf(p.b - m.b)
		diffs.append(total)
	if not (diffs[0] < diffs[1] and diffs[1] < diffs[2]):
		return fail("nos dados, o nível 4 deveria casar com o 3 sem deslocamento: %s" % [diffs])
	ok("zoom: 3.000 pontos (com 180° e polos) caem no mesmo pixel em todos os níveis e na grade de edição; nos dados, o nível 4 casa com o 3 sem deslocamento (diferença %d < %d < %d)" % [diffs[0], diffs[1], diffs[2]])
