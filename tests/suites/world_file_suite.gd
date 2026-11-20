extends "res://tests/test_suite.gd"
## O mundo como pasta portátil (Evron.world): exportar, conferir, recusar uma pasta alterada e importar em outro lugar (aceite 12).
## Também a ferramenta de unir territórios. As linhas "ERROR" de recusas são esperadas.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")


func run() -> void:
	var base := out_dir.path_join("world_file_suite")
	var world := base.path_join("Teste.world")
	var src := base.path_join("origem.db")
	var dst := base.path_join("destino.db")
	var clock := base.path_join("relogio.json")
	DirAccess.make_dir_recursive_absolute(world)
	for f in [src, dst, dst + ".antes-importacao", clock, world.path_join("world.sqlite"), world.path_join("manifest.json"), world.path_join("clock.json")]:
		DirAccess.remove_absolute(f)
	var f := FileAccess.open(clock, FileAccess.WRITE)
	f.store_string("{\"t\": 42}")
	f.close()

	var terrain = load("res://scripts/world/Terrain.cs").new()
	terrain.Setup(Image.create(256, 128, false, Image.FORMAT_RF))
	var layer = load("res://scripts/world/Territory.cs").new()
	layer.Setup(terrain)
	var reg = load("res://scripts/world/Registry.cs").new()
	reg.Open(src)
	var a: int = reg.Create("pais", "Aren")
	var b: int = reg.Create("pais", "Dravia")
	layer.Begin()
	layer.Dab(EvronGeo.dir(0, 0), 1500, a, false, -1)
	layer.End()
	layer.Begin()
	layer.Dab(EvronGeo.dir(0, 40), 900, b, false, -1)
	layer.End()

	# Unir: o território de Dravia passa para Aren; desfazer volta.
	var before_b: int = layer.Pixels(b)
	var merged = layer.ReplaceOwner(b, a)
	if merged == null or layer.Pixels(b) != 0 or layer.Pixels(a) == 0:
		return fail("unir passa todo o território de um para o outro")
	merged.Undo()
	if layer.Pixels(b) != before_b:
		return fail("desfazer a união volta o território")
	ok("unir territórios e desfazer")

	reg.SaveTerritory(layer)
	var why: String = reg.ExportWorld(world, clock)
	if why != "" or not FileAccess.file_exists(world.path_join("manifest.json")) or FileAccess.file_exists(world.path_join("world.sqlite.tmp")):
		return fail("exportar cria a pasta com banco, relógio e manifesto: " + why)
	reg.Close()
	if reg.CheckWorld(world) != "":
		return fail("a pasta exportada confere: " + reg.CheckWorld(world))
	ok("exportar: world.sqlite, clock.json e manifest.json com hashes")

	# Uma pasta alterada é recusada antes de mexer em qualquer coisa.
	var g := FileAccess.open(world.path_join("clock.json"), FileAccess.WRITE)
	g.store_string("{\"t\": 99}")
	g.close()
	if reg.CheckWorld(world) == "" or reg.ImportWorld(world, dst, "") == "" or FileAccess.file_exists(dst):
		return fail("clock.json alterado: a pasta é recusada e nada é importado")
	var h := FileAccess.open(world.path_join("clock.json"), FileAccess.WRITE)
	h.store_string("{\"t\": 42}")
	h.close()
	if reg.CheckWorld(base) == "":
		return fail("pasta sem manifesto é recusada")
	ok("pasta alterada ou sem manifesto é recusada sem importar nada")

	# Importar em outro lugar: o banco anterior fica guardado, o mundo volta igual.
	var other = load("res://scripts/world/Registry.cs").new()
	other.Open(dst)
	other.Create("pais", "Mundo que será trocado")
	other.Close()
	var dst_clock := base.path_join("relogio_destino.json")
	DirAccess.remove_absolute(dst_clock)
	if other.ImportWorld(world, dst, dst_clock) != "" or not FileAccess.file_exists(dst + ".antes-importacao"):
		return fail("importar troca o banco e guarda o anterior")
	if FileAccess.get_file_as_string(dst_clock) != "{\"t\": 42}":
		return fail("importar traz o relógio")
	other.Open(dst)
	var back = load("res://scripts/world/Territory.cs").new()
	back.Setup(terrain)
	if other.Name(a) != "Aren" or not other.LoadTerritory(back) or back.Pack() != layer.Pack():
		return fail("o mundo importado tem os cadastros e o território")
	other.Close()
	ok("importar: cadastros, território e relógio iguais; o mundo anterior fica como .antes-importacao")
