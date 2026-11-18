extends "res://tests/test_suite.gd"
## A camada política (o dono de cada pixel) no núcleo, sem cena: pincel, só em terra, sobrepor e apagar, a volta na longitude 180° e o polo, balde, desfazer
## e refazer, área real em km², compressão e o banco (camada e cor dos países). Usa um terreno sintético pequeno (256 × 128 pixels, ~200 km cada).
## As linhas "ERROR" das recusas são esperadas.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")

const R := 8282.3
const W := 256
const H := 128


func _terrain() -> Object:
	var img := Image.create(W, H, false, Image.FORMAT_RF)
	for y in H:
		for x in W:
			# um "mar" no meio (lon de -29° a 29°) e terra no resto
			img.set_pixel(x, y, Color(-100.0 if x >= 107 and x < 149 else 100.0, 0, 0, 1))
	var t = load("res://scripts/world/Terrain.cs").new()
	t.Setup(img)
	return t


func _territory(terrain) -> Object:
	var t = load("res://scripts/world/Territory.cs").new()
	t.Setup(terrain)
	return t


func _paint(t, lat: float, lon: float, km: float, owner: int, land_only := false, only_owner := -1) -> Object:
	t.Begin()
	t.Dab(EvronGeo.dir(lat, lon), km, owner, land_only, only_owner)
	return t.End()


func run() -> void:
	var terrain = _terrain()
	var t = _territory(terrain)
	if t.Size != Vector2i(W, H) or t.OwnerAt(EvronGeo.dir(10, 100)) != 0:
		return fail("a camada começa sem dono, na grade do terreno")

	# Uma marca de pincel: a área do disco (2πR²(1−cos(r/R))) com a precisão dos pixels; o centro é do dono e longe não.
	var edit = _paint(t, 0, 80, 1500, 5)
	var esperado: float = 2.0 * PI * R * R * (1.0 - cos(1500.0 / R))
	if edit == null or absf(t.AreaKm2(5) / esperado - 1.0) > 0.1 or t.OwnerAt(EvronGeo.dir(0, 80)) != 5 or t.OwnerAt(EvronGeo.dir(40, -100)) != 0:
		return fail("o disco de 1500 km: %.0f km² (esperado ~%.0f)" % [t.AreaKm2(5), esperado])
	var area := float(t.AreaKm2(5))
	var v0: int = t.Version
	edit.Undo()
	if t.AreaKm2(5) != 0.0 or t.Version == v0 or t.OwnerAt(EvronGeo.dir(0, 80)) != 0:
		return fail("desfazer tira o território")
	edit.Redo()
	if absf(t.AreaKm2(5) - area) > 1e-6 or edit.Bytes != edit.Count * 8:
		return fail("refazer devolve o mesmo território (8 bytes por pixel)")
	ok("pincel: área do disco (%.0f km², esperado %.0f), centro e fora, desfazer e refazer" % [area, esperado])

	# Só em terra: a costa do país segue a costa do mapa (o "mar" do meio fica sem dono).
	var t2 = _territory(terrain)
	_paint(t2, 0, 0, 6000, 7, true)
	if t2.OwnerAt(EvronGeo.dir(0, 0)) != 0 or t2.OwnerAt(EvronGeo.dir(0, 35)) != 7 or t2.OwnerAt(EvronGeo.dir(0, -35)) != 7:
		return fail("só em terra: o mar do meio fica sem dono e a terra dos lados é do país")
	_paint(t2, 0, 0, 6000, 8, false)
	if t2.OwnerAt(EvronGeo.dir(0, 0)) != 8:
		return fail("sem 'só em terra' o pincel pinta o mar também")
	ok("só em terra: o mar fica sem dono; sem a opção, pinta tudo")

	# Conquista (sobrepor) e a borracha de um país que não apaga o vizinho.
	var t3 = _territory(terrain)
	_paint(t3, 0, 80, 1500, 5)
	_paint(t3, 0, 100, 1500, 6)    # o país 6 avança sobre o 5
	if t3.OwnerAt(EvronGeo.dir(0, 80)) != 5 or t3.OwnerAt(EvronGeo.dir(0, 100)) != 6 or t3.OwnerAt(EvronGeo.dir(0, 90)) != 6:
		return fail("o pincel sobrepõe o que já era de outro país (cada pixel tem um dono só)")
	_paint(t3, 0, 90, 4000, 0, false, 5)   # a borracha do país 5 passa por cima dos dois
	if t3.OwnerAt(EvronGeo.dir(0, 80)) != 0 or t3.OwnerAt(EvronGeo.dir(0, 100)) != 6 or t3.AreaKm2(5) >= area:
		return fail("a borracha de um país só apaga o dele")
	ok("conquista (sobrepõe) e borracha por dono (não apaga o vizinho)")

	# A volta na longitude 180° e o polo.
	var t4 = _territory(terrain)
	_paint(t4, 0, 179, 1000, 9)
	_paint(t4, 89, 0, 800, 10)
	if t4.OwnerAt(EvronGeo.dir(0, -179)) != 9 or t4.OwnerAt(EvronGeo.dir(0, 180)) != 9 or t4.OwnerAt(EvronGeo.dir(89, 180)) != 10 or t4.OwnerAt(EvronGeo.dir(89, -90)) != 10:
		return fail("o pincel atravessa 180° e cobre o polo")
	var perto_polo := float(t4.AreaKm2(10))
	var esp_polo: float = 2.0 * PI * R * R * (1.0 - cos(800.0 / R))
	if absf(perto_polo / esp_polo - 1.0) > 0.25:
		return fail("a área perto do polo pesa pela largura real dos pixels: %.0f km² (esperado ~%.0f)" % [perto_polo, esp_polo])
	ok("atravessa 180°, cobre o polo e a área perto do polo é a real (~%.0f km²)" % perto_polo)

	# O balde: preenche só o que está dentro de uma linha fechada (feita com o pincel).
	var t5 = _territory(terrain)
	for i in 36:
		var a := TAU * i / 36.0
		_paint(t5, 60.0 * sin(a) * 0.0 + 20.0 * cos(a), 80.0 + 20.0 * sin(a) / cos(deg_to_rad(20.0)), 260, 3)   # um anel de ~20° de raio, de países "3"
	var preenchido = t5.Fill(EvronGeo.dir(0, 80), 4, true)
	if preenchido == null or t5.OwnerAt(EvronGeo.dir(0, 80)) != 4 or t5.OwnerAt(EvronGeo.dir(0, 140)) != 0 or t5.OwnerAt(EvronGeo.dir(70, 80)) != 0:
		return fail("o balde preenche dentro do anel e não vaza para fora")
	var interior := float(t5.AreaKm2(4))
	if interior < 3.0e6 or interior > 2.0 * PI * R * R * (1.0 - cos(deg_to_rad(21.0))) * 1.05:
		return fail("a área preenchida cabe no anel de 20°: %.0f km²" % interior)
	if t5.Fill(EvronGeo.dir(0, 80), 4, true) != null or t5.Fill(EvronGeo.dir(0, 0), 4, true) != null:
		return fail("balde no mesmo dono, ou no mar com 'só em terra', não faz nada")
	preenchido.Undo()
	if t5.OwnerAt(EvronGeo.dir(0, 80)) != 0:
		return fail("desfazer o balde")
	ok("balde: preenche só dentro do anel (%.0f km²), não vaza, e desfaz" % interior)

	# Apagar todo o território de um dono.
	var limpa = t3.ClearOwner(6)
	if limpa == null or t3.AreaKm2(6) != 0.0 or t3.ClearOwner(6) != null:
		return fail("ClearOwner apaga o território do dono (e é nulo se não há nada)")
	limpa.Undo()
	if t3.AreaKm2(6) <= 0.0:
		return fail("desfazer o apagar")
	ok("apagar todo o território de um país (e desfazer)")

	# Dono fora de 0..65535 é recusado sem mudar nada.
	var antes := float(t3.AreaKm2(6))
	t3.Begin()
	t3.Dab(EvronGeo.dir(0, 100), 500, 70000, false, -1)
	if t3.End() != null or t3.AreaKm2(6) != antes:
		return fail("dono 70000 deveria ser recusado")
	ok("dono fora de 0..65535 recusado")

	# Compressão: a camada quase vazia cabe em poucos KB e volta igual.
	var bytes: PackedByteArray = t3.Pack()
	var copia = _territory(terrain)
	if not copia.Unpack(bytes, W, H) or absf(copia.AreaKm2(6) - t3.AreaKm2(6)) > 1e-6 or copia.OwnerAt(EvronGeo.dir(0, 100)) != 6 or bytes.size() > W * H * 2 / 4:
		return fail("Pack/Unpack: %d bytes de %d" % [bytes.size(), W * H * 2])
	var outra = load("res://scripts/world/Terrain.cs").new()
	var img2 := Image.create(64, 32, false, Image.FORMAT_RF)
	outra.Setup(img2)
	var pequena = _territory(outra)
	if pequena.Unpack(bytes, W, H):
		return fail("uma camada de outra grade não é aplicada")
	ok("Pack/Unpack: %d bytes de %d (%.1f%%) e volta igual; outra grade é recusada" % [bytes.size(), W * H * 2, 100.0 * bytes.size() / (W * H * 2)])

	# No banco: a camada, a cor de cada país e a paleta.
	var path := out_dir.path_join("territory_suite.db")
	for ext in ["", "-journal"]:
		DirAccess.remove_absolute(path + ext)
	var reg = load("res://scripts/world/Registry.cs").new()
	reg.Open(path)
	var vazia = _territory(terrain)
	if reg.LoadTerritory(vazia):
		return fail("sem camada gravada, LoadTerritory devolve false")
	reg.SaveTerritory(t3)
	var lida = _territory(terrain)
	if not reg.LoadTerritory(lida) or lida.OwnerAt(EvronGeo.dir(0, 100)) != 6 or absf(lida.AreaKm2(5) - t3.AreaKm2(5)) > 1e-6:
		return fail("a camada gravada volta igual")
	reg.SaveTerritory(t)   # gravar de novo substitui
	var lida2 = _territory(terrain)
	reg.LoadTerritory(lida2)
	if lida2.OwnerAt(EvronGeo.dir(0, 100)) != 0 or lida2.OwnerAt(EvronGeo.dir(0, 80)) != 5:
		return fail("gravar de novo substitui a camada")
	var a: int = reg.Create("pais", "Aren")
	var b: int = reg.Create("pais", "Dravia")
	var povo: int = reg.Create("etnia", "Povo")
	var todas := {}
	var ids: Array = []
	for i in 20:
		ids.append(int(reg.Create("pais", "País %d" % i)))
	for id in ids + [a, b]:
		todas[int(reg.EntityColor(id))] = true
	if todas.size() != 22:
		return fail("as cores automáticas dos países são todas diferentes (%d de 22)" % todas.size())
	reg.SetEntityColor(a, 0x336699)
	if reg.EntityColor(a) != 0x336699 or reg.EntityColor(b) == 0x336699:
		return fail("escolher a cor de um país")
	reg.SetEntityColor(a, -5)   # recusado
	reg.SetEntityColor(a, 0x1000000)
	if reg.EntityColor(a) != 0x336699:
		return fail("cor inválida é recusada sem mudar")
	var pal: Array = reg.CountryPalette()
	if pal.size() != 22 or pal.any(func(p): return p.id == povo) or pal.filter(func(p): return p.id == a)[0].rgb != 0x336699:
		return fail("a paleta tem só os países, com a cor de cada um: %d" % pal.size())
	reg.Close()
	reg.Open(path)
	var lida3 = _territory(terrain)
	if not reg.LoadTerritory(lida3) or reg.EntityColor(a) != 0x336699:
		return fail("reabrir conserva a camada e as cores")
	reg.Close()
	ok("banco: camada gravada e relida (e substituída), cor automática distinta por país, cor escolhida, paleta só de países")
