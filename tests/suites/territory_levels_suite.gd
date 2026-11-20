extends "res://tests/test_suite.gd"
## Camadas territoriais independentes (especificação 17, fase 5): países e províncias em camadas separadas, cada uma gravada à parte,
## e os avisos de inconsistência (província fora do país, sem país, lacuna). Terreno sintético de 256 × 128 pixels.
## Se houver o banco real do usuário, uma CÓPIA dele passa pela migração (o original não é tocado).

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const TerritoryEdit = preload("res://scripts/edit/TerritoryEdit.cs")

const W := 256
const H := 128


func _terrain() -> Object:
	var img := Image.create(W, H, false, Image.FORMAT_RF)
	img.fill(Color(100.0, 0, 0, 1))
	var t = load("res://scripts/world/Terrain.cs").new()
	t.Setup(img)
	return t


func _layer(terrain) -> Object:
	var t = load("res://scripts/world/Territory.cs").new()
	t.Setup(terrain)
	return t


func _paint(t, lat: float, lon: float, km: float, owner: int) -> Object:
	t.Begin()
	t.Dab(EvronGeo.dir(lat, lon), km, owner, false, -1)
	return t.End()


func _warning(list: Array, kind: String, id: int) -> Dictionary:
	for w in list:
		if w.kind == kind and int(w.id) == id:
			return w
	return {}


func run() -> void:
	var path := out_dir.path_join("territory_levels_suite.db")
	for ext in ["", "-journal"]:
		DirAccess.remove_absolute(path + ext)
	var reg = load("res://scripts/world/Registry.cs").new()
	reg.Open(path)
	var a: int = reg.Create("pais", "Aren")
	var b: int = reg.Create("pais", "Dravia")
	var p1: int = reg.Create("provincia", "Alta Aren")
	var p2: int = reg.Create("provincia", "Baixa Aren")
	var p3: int = reg.Create("provincia", "Sem dono")
	if p1 == 0 or reg.Kind(p1) != "provincia":
		return fail("o cadastro aceita o tipo província")
	reg.Link(p1, a, "provincia_de")
	reg.Link(p2, a, "provincia_de")
	if not reg.LinkTypesFor("provincia").any(func(t): return t.code == "provincia_de"):
		return fail("o vínculo 'província de' aparece para províncias")
	ok("tipo província e vínculo 'província de' (província -> país)")

	var terrain = _terrain()
	var countries = _layer(terrain)
	var provinces = _layer(terrain)
	_paint(countries, 0, 60, 2500, a)  # lon ~37 a ~83
	_paint(countries, 0, 130, 1500, b)  # lon ~116 a ~144
	var countries_before: PackedByteArray = countries.Pack()

	# Critérios 1 e 2: pintar uma província não mexe nos países (e vice-versa).
	var e1 = _paint(provinces, 0, 55, 700, p1)
	_paint(provinces, 0, 75, 500, p2)
	if countries.Pack() != countries_before:
		return fail("pintar província mudou a camada dos países")
	var provinces_before: PackedByteArray = provinces.Pack()
	var e2 = _paint(countries, 0, 60, 300, b)
	if provinces.Pack() != provinces_before:
		return fail("editar país mudou a camada das províncias")
	e2.Undo()
	if countries.Pack() != countries_before or provinces.Pack() != provinces_before:
		return fail("desfazer a edição do país volta só os países")
	e1.Undo()
	if countries.Pack() != countries_before or provinces.AreaKm2(p1) != 0.0:
		return fail("desfazer a província volta só as províncias")
	e1.Redo()
	ok("camadas independentes: pintar e desfazer em uma não muda a outra (critérios 1, 2 e 4)")

	# Avisos.
	var clean: Array = reg.TerritoryWarnings(countries, provinces)
	if not _warning(clean, "fora", p1).is_empty() or not _warning(clean, "fora", p2).is_empty():
		return fail("província dentro do país não gera aviso de 'fora': %s" % [clean])
	var gap := _warning(clean, "lacuna", a)
	if gap.is_empty() or gap.area_km2 <= 0.0 or not _warning(clean, "lacuna", b).is_empty():
		return fail("terra de Aren sem província é lacuna; Dravia não tem províncias, então não: %s" % [clean])
	_paint(provinces, 0, 95, 600, p2)  # Baixa Aren sai de Aren (até ~lon 100)
	_paint(provinces, 40, -100, 400, p3)
	var w: Array = reg.TerritoryWarnings(countries, provinces)
	var out := _warning(w, "fora", p2)
	if out.is_empty() or int(out.country) != a or out.area_km2 <= 0.0:
		return fail("província que sai do país gera aviso 'fora': %s" % [w])
	if _warning(w, "sem_pais", p3).is_empty():
		return fail("província pintada sem país ligado gera aviso 'sem_pais': %s" % [w])
	if not _warning(w, "fora", p1).is_empty():
		return fail("Alta Aren continua dentro: %s" % [w])
	ok("avisos: fora do país (%.0f km²), sem país, lacuna (%.0f km²)" % [out.area_km2, gap.area_km2])

	# Critério 7: gravar e reabrir conserva as duas camadas, cada uma no seu nível.
	reg.SaveTerritoryLevel("pais", countries)
	reg.SaveTerritoryLevel("provincia", provinces)
	reg.Close()
	reg.Open(path)
	var c2 = _layer(terrain)
	var p2l = _layer(terrain)
	if not reg.LoadTerritoryLevel("pais", c2) or not reg.LoadTerritoryLevel("provincia", p2l):
		return fail("as duas camadas são relidas")
	if c2.Pack() != countries.Pack() or p2l.Pack() != provinces.Pack():
		return fail("reabrir conserva cada camada")
	var c3 = _layer(terrain)
	if not reg.LoadTerritory(c3) or c3.Pack() != countries.Pack():
		return fail("LoadTerritory continua lendo a camada dos países")
	var pal: Array = reg.Palette("provincia")
	if pal.size() != 3 or pal.any(func(x): return int(x.id) == a):
		return fail("a paleta das províncias tem só províncias: %s" % [pal])
	# Terceiro nível: município dentro de uma província, com os mesmos avisos em relação ao nível de cima.
	var m1: int = reg.Create("municipio", "Porto Alto")
	reg.Link(m1, p1, "municipio_de")
	var towns = _layer(terrain)
	_paint(towns, 0, 55, 300, m1)
	var mw: Array = reg.LevelWarnings("municipio", provinces, towns)
	if not _warning(mw, "fora", m1).is_empty() or _warning(mw, "lacuna", p1).is_empty():
		return fail("município dentro da província: sem 'fora', e o resto da província é lacuna: %s" % [mw])
	_paint(towns, 0, 90, 300, m1)  # fora de Alta Aren
	if _warning(reg.LevelWarnings("municipio", provinces, towns), "fora", m1).is_empty():
		return fail("município que sai da província gera aviso 'fora'")
	reg.SaveTerritoryLevel("municipio", towns)
	reg.Close()
	reg.Open(path)
	var t2 = _layer(terrain)
	if not reg.LoadTerritoryLevel("municipio", t2) or t2.Pack() != towns.Pack() or not reg.LoadTerritoryLevel("pais", c2):
		return fail("a camada dos municípios é gravada à parte e as outras ficam")
	reg.Close()
	ok("gravar e reabrir conserva cada camada; paleta por nível; municípios com avisos em relação à província (critério 7)")

	# Tiles: numa grade de 1024 × 512 (2 × 1 tiles de 512), só o tile mexido é regravado; reabrir monta a camada igual.
	var wide_img := Image.create(1024, 512, false, Image.FORMAT_RF)
	var wide = load("res://scripts/world/Terrain.cs").new()
	wide.Setup(wide_img)
	var tiled = _layer(wide)
	reg.Open(path)
	_paint(tiled, 0, -90, 800, a)  # só no tile da esquerda
	if tiled.TilesX != 2 or tiled.DirtyTileCount() != 1:
		return fail("pintar à esquerda marca só o tile da esquerda: %d" % tiled.DirtyTileCount())
	var first: int = reg.SaveTerritoryLevel("pais", tiled)
	if first <= 0 or tiled.DirtyTileCount() != 0:
		return fail("a primeira gravação escreve a camada e limpa as marcas")
	_paint(tiled, 0, 90, 800, b)  # só no da direita
	if tiled.DirtyTileCount() != 1:
		return fail("pintar à direita marca um tile")
	reg.SaveTerritoryLevel("pais", tiled)
	var back = _layer(wide)
	if not reg.LoadTerritoryLevel("pais", back) or back.Pack() != tiled.Pack():
		return fail("a camada relida dos tiles é igual")
	tiled.ClearOwner(b)  # o tile da direita fica vazio: some do banco
	reg.SaveTerritoryLevel("pais", tiled)
	var back2 = _layer(wide)
	reg.LoadTerritoryLevel("pais", back2)
	if back2.Pack() != tiled.Pack() or back2.Pixels(b) != 0:
		return fail("apagar um tile inteiro o tira do banco")
	var other = _layer(wide)  # outra camada (não veio do banco): gravar substitui tudo
	_paint(other, 30, 90, 500, b)
	reg.SaveTerritoryLevel("pais", other)
	var back3 = _layer(wide)
	reg.LoadTerritoryLevel("pais", back3)
	if back3.Pack() != other.Pack() or back3.Pixels(a) != 0:
		return fail("gravar uma camada de fora substitui a anterior (sem sobra de tiles velhos)")
	reg.Close()
	ok("tiles: só o tile mexido é regravado, tile vazio sai do banco, gravar outra camada substitui")

	# Importar PNG: manchas separadas da mesma cor são regiões separadas; transparente é fundo; manchas mínimas ficam de fora.
	var png := Image.create(W, H, false, Image.FORMAT_RGBA8)
	png.fill(Color(0, 0, 0, 0))
	png.fill_rect(Rect2i(10, 50, 10, 10), Color8(255, 0, 0))   # vermelho 1 (100 px)
	png.fill_rect(Rect2i(200, 50, 8, 8), Color8(255, 0, 0))    # vermelho 2 (64 px), longe do 1
	png.fill_rect(Rect2i(100, 20, 20, 10), Color8(0, 0, 255))  # azul (200 px)
	png.set_pixel(50, 100, Color8(255, 0, 0))                  # ruído (1 px)
	var target = _layer(terrain)
	var regions: Array = target.AnalyzeImage(png, 4)
	if regions.size() != 3 or int(regions[0].pixels) != 200 or int(regions[1].rgb) != 0xFF0000 or int(regions[2].rgb) != 0xFF0000:
		return fail("o PNG vira 3 regiões (as maiores primeiro, os dois vermelhos separados, sem o ruído): %s" % [regions])
	var red1: int = regions[1].index
	var blue: int = regions[0].index
	var imported = target.ApplyImport(PackedInt32Array([red1, blue]), PackedInt32Array([a, b]))
	var red2_dir: Vector3 = terrain.DirOf(54 * W + 204)
	if imported == null or target.OwnerAt(terrain.DirOf(55 * W + 15)) != a or target.OwnerAt(terrain.DirOf(25 * W + 110)) != b 			or target.OwnerAt(red2_dir) != 0 or target.Pixels(a) != 100:
		return fail("aplicar liga só as regiões escolhidas (o segundo vermelho, ignorado, fica sem dono)")
	imported.Undo()
	if target.Pixels(a) != 0 or target.Pixels(b) != 0:
		return fail("desfazer a importação volta tudo")
	ok("importar PNG: 3 regiões (mesma cor separada), mapeamento explícito, ruído ignorado, desfazer")

	# Fidelidade do traço: a estabilização não mexe nas pontas e puxa os pontos do meio para os vizinhos.
	var Tool = load("res://scripts/edit/territory_boundary_tool.gd")
	var zig := PackedVector3Array([EvronGeo.dir(0, 0), EvronGeo.dir(2, 1), EvronGeo.dir(-2, 2), EvronGeo.dir(2, 3), EvronGeo.dir(0, 4)])
	var calm: PackedVector3Array = Tool.stabilized(zig, 3)
	if calm[0] != zig[0] or calm[4] != zig[4] or absf(EvronGeo.lat_lon(calm[2]).x) >= 1.0 or Tool.stabilized(zig, 0) != zig:
		return fail("estabilização do traço suavizado")
	ok("fidelidade: suavizado estabiliza o meio do traço e mantém as pontas; alta fidelidade não mexe")

	# Um banco gravado antes desta versão (camada na tabela antiga) migra sem perder a camada dos países.
	var real := OS.get_user_data_dir().path_join("evron_world.db")
	if not FileAccess.file_exists(real):
		ok("sem banco do usuário para testar a migração (pulado)")
		return
	var copy := out_dir.path_join("territory_levels_real.db")
	for ext in ["", "-journal"]:
		DirAccess.remove_absolute(copy + ext)
	DirAccess.copy_absolute(real, copy)
	var old = load("res://scripts/world/Registry.cs").new()
	old.Open(copy)
	if not old.IsOpen():
		return fail("a cópia do banco do usuário abre e migra")
	var img := Image.create(4096, 2048, false, Image.FORMAT_RF)  # a grade real; o relevo não importa para ler os donos
	var real_terrain = load("res://scripts/world/Terrain.cs").new()
	real_terrain.Setup(img)
	var real_layer = _layer(real_terrain)
	var had: bool = old.LoadTerritoryLevel("pais", real_layer)
	if had:  # a camada antiga (inteira numa linha) é regravada em tiles e volta igual
		old.SaveTerritoryLevel("pais", real_layer)
		var again = _layer(real_terrain)
		if not old.LoadTerritoryLevel("pais", again) or again.Pack() != real_layer.Pack():
			return fail("a camada do banco do usuário passa para tiles sem mudar")
	var prov: int = old.Create("provincia", "Teste de migração")
	if prov == 0 or old.Kind(prov) != "provincia":
		return fail("o banco migrado aceita províncias")
	old.Close()
	ok("cópia do banco do usuário migrou (%s) e aceita províncias" % ("camada de países preservada" if had else "sem camada"))
