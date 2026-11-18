extends "res://tests/test_suite.gd"
## O núcleo de edição sobre um terreno SINTÉTICO (não precisa de data/evron/): roda num clone limpo e no CI.
## Disco do pincel em 180° e no polo, desfazer/refazer exato, pincelada = um comando, histórico limitado por memória,
## erosão conserva a massa, e Vales numa costa não transformam mar em terra nem terra em mar.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const Terrain = preload("res://scripts/world/Terrain.cs")
const CommandStack = preload("res://scripts/edit/command_stack.gd")
const TerrainBrush = preload("res://scripts/edit/terrain_brush.gd")

const W := 512  # 1 pixel ≈ 100 km no equador


## Um comando falso, só com o tamanho (para testar o limite do histórico).
class FakeCommand:
	var Bytes := 0

	func _init(b: int) -> void:
		Bytes = b

	func Undo() -> void:
		pass

	func Redo() -> void:
		pass


func run() -> void:
	var terrain := Terrain.new()
	terrain.Setup(_synthetic())
	var stack := CommandStack.new()
	var brush := TerrainBrush.new(terrain, stack)
	brush.seed_value = 1

	# Disco: atravessa a longitude 180° e cobre a linha do polo.
	var cols := {}
	for idx in terrain.Disk(EvronGeo.dir(0.0, 179.9), 600.0)[0]:
		cols[idx % W] = true
	if not (cols.has(0) and cols.has(W - 1)):
		return fail("disco em 179,9° deveria pegar as colunas das duas pontas")
	var top := {}
	for idx in terrain.Disk(EvronGeo.dir(89.9, 0.0), 600.0)[0]:
		if idx / W == 0:
			top[idx % W] = true
	if top.size() != W:
		return fail("disco no polo deveria pegar a primeira linha inteira, pegou %d colunas" % top.size())
	ok("núcleo: disco atravessa 180° e cobre o polo")

	# Elevar: desfazer e refazer devolvem as alturas exatas; arrastar vira um comando só.
	var here := EvronGeo.dir(10.0, 20.0)
	var h0: float = terrain.HeightAt(here)
	brush.op = TerrainBrush.Op.RAISE
	brush.radius_km = 1500.0
	brush.strength = 300.0
	brush.begin(here)
	for i in range(1, 6):
		brush.drag(EvronGeo.dir(10.0, 20.0 + i * 5.0))
	brush.end()
	var h1: float = terrain.HeightAt(here)
	if h1 <= h0:
		return fail("elevar deveria subir o centro: %.1f -> %.1f" % [h0, h1])
	stack.undo()
	if stack.can_undo() or terrain.HeightAt(here) != h0:
		return fail("uma pincelada arrastada deveria ser um comando só, e desfazer, exato")
	stack.redo()
	if terrain.HeightAt(here) != h1:
		return fail("refazer deveria reaplicar a mesma altura")
	stack.undo()
	ok("núcleo: elevar, desfazer e refazer exatos; pincelada arrastada = um comando")

	# Histórico limitado por memória: os mais antigos saem, o último fica sempre.
	var hist := CommandStack.new()
	var big := CommandStack.LIMIT_BYTES / 3
	for i in 5:
		hist.push("c%d" % i, FakeCommand.new(big))
	if hist.bytes() > CommandStack.LIMIT_BYTES or hist.undo_name() != "c4":
		return fail("o histórico deveria caber em %d bytes (tem %d)" % [CommandStack.LIMIT_BYTES, hist.bytes()])
	var huge := CommandStack.new()
	huge.push("enorme", FakeCommand.new(CommandStack.LIMIT_BYTES * 2))
	if not huge.can_undo():
		return fail("um comando maior que o limite ainda deveria poder ser desfeito")
	ok("núcleo: histórico limitado a %d MiB, o último comando fica sempre" % (CommandStack.LIMIT_BYTES / 1048576))

	# Erosão conserva a massa.
	var peak := EvronGeo.dir(0.0, -60.0)
	var region: PackedInt32Array = terrain.Disk(peak, 3000.0)[0]
	var mass0 := _sum(terrain, region)
	brush.op = TerrainBrush.Op.ERODE
	brush.strength = 900.0
	brush.radius_km = 2000.0
	brush.begin(peak)
	brush.end()
	var mass1 := _sum(terrain, region)
	stack.undo()
	if absf(mass1 - mass0) > 1.0:
		return fail("erosão deveria conservar a massa: %.3f -> %.3f" % [mass0, mass1])
	if absf(_sum(terrain, region) - mass0) > 0.0:
		return fail("desfazer a erosão deveria devolver as alturas exatas")
	ok("núcleo: erosão conserva a massa (%.3f m somados)" % (mass1 - mass0))

	# Vales na costa da montanha: terra continua terra e mar continua mar.
	region = terrain.Disk(peak, 4500.0)[0]  # a costa e a plataforma inteiras
	var land := {}
	for i in region:
		land[i] = terrain.GetH(i) >= 0.0
	brush.op = TerrainBrush.Op.VALLEYS
	brush.strength = 1000.0
	brush.radius_km = 2500.0
	for s in 4:
		brush.begin(EvronGeo.dir(0.0, -70.0 + s * 6.0))
		brush.drag(EvronGeo.dir(-8.0, -64.0 + s * 6.0))
		brush.end()
	var flipped := 0
	for i in region:
		if (terrain.GetH(i) >= 0.0) != land[i]:
			flipped += 1
	for i in 4:
		stack.undo()
	if flipped > 0:
		return fail("vales na costa trocaram %d pixels entre terra e mar" % flipped)
	ok("núcleo: vales na costa não trocam terra e mar")


## Uma montanha cônica de 6 km no equador em -60° (costa a 3000 km do pico), com uma plataforma rasa (-5 m) de 500 km
## que depois desce até -2 km: é onde o sedimento dos Vales se acumula e, sem o piso do mar, viraria ilha.
func _synthetic() -> Image:
	var img := Image.create(W, W / 2, false, Image.FORMAT_RF)
	var center := EvronGeo.dir(0.0, -60.0)
	for y in W / 2:
		for x in W:
			var n := EvronGeo.dir(90.0 - (y + 0.5) * 180.0 / (W / 2), ((x + 0.5) / W - 0.5) * 360.0)
			var d := EvronGeo.distance_km(n, center)
			var h := lerpf(6000.0, 20.0, d / 3000.0) if d < 3000.0 else lerpf(-5.0, -2000.0, clampf((d - 3500.0) / 1000.0, 0.0, 1.0))
			h += 15.0 * sin(x * 0.7) * cos(y * 0.9)
			img.set_pixel(x, y, Color(h, 0.0, 0.0))
	return img


func _sum(terrain: Terrain, idx: PackedInt32Array) -> float:
	var s := 0.0
	for i in idx:
		s += terrain.GetH(i)
	return s
