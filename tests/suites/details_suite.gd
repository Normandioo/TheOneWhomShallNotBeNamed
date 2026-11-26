extends "res://tests/test_suite.gd"
## O que faltava das etapas 0 a 3 do plano de recursos (migração 21), sem cena: cópia antes de migrar; detalhes, validade e política
## das ocorrências; quem conhece e direitos; divisão entre países; capacidades, instalações, insumos alternativos e renovação na
## produção; estoque numa data e por país; aviso de relevo mudado. As linhas "ERROR" das recusas são esperadas.

const Calendar = preload("res://scripts/world/calendar.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const Terrain = preload("res://scripts/world/Terrain.cs")
const Territory = preload("res://scripts/world/Territory.cs")
const ALWAYS := -9223372036854775807 - 1
const FOREVER := 9223372036854775807

var r
var terrain: Terrain


func run() -> void:
	var height := Image.create(512, 256, false, Image.FORMAT_RF)
	height.fill(Color(100.0, 0, 0))
	terrain = Terrain.new()
	terrain.Setup(height)
	var path := out_dir.path_join("details_suite.db")
	for f in [path, path + ".antes-v20", path + "-journal"]:
		DirAccess.remove_absolute(f)
	r = load("res://scripts/world/Registry.cs").new()
	r.OpenAtVersion(path, 20)
	r.Close()
	r.Open(path)
	if not FileAccess.file_exists(path + ".antes-v20"):
		return fail("antes de migrar um mundo existente, uma cópia dele fica ao lado")
	ok("cópia do mundo antes de migrar (.antes-v20)")

	# Catálogo: as categorias e a dimensão das unidades.
	var sal := _good("Sal", "t", "mineral")
	var lenha := _good("Lenha", "kg", "vegetal")
	var carvao := _good("Carvão", "kg", "manufatura")
	var forno := _good("Forno", "unidade", "manufatura")
	if r.ResourceTypes("Sal")[0].category != "mineral" or r.DimensionOf("t") != "massa" or r.DimensionOf("pitada") != "outra" or r.Units().size() != 9:
		return fail("categorias e unidades")
	ok("categorias do catálogo e dimensão de cada unidade")

	# Detalhes da ocorrência: aceitos, recusados, desfeitos; a validade no tempo vale para a produção.
	var point: int = r.AddPoint(sal, 0.0, 10.0).Id
	r.SetOccurrenceReserve(point, 1000.0)
	var edit = r.SetOccurrenceDetails(point, 40.0, 120.0, "dificil", NAN, "normal", ALWAYS, FOREVER)
	var d: Dictionary = r.OccurrenceDetails(point)
	if d.grade != 40.0 or d.depth_m != 120.0 or d.access != "dificil" or not is_nan(d.renewal) or d.valid_from != ALWAYS:
		return fail("detalhes gravados: %s" % [d])
	for bad in [r.SetOccurrenceDetails(point, 140.0, NAN, "", NAN, "normal", ALWAYS, FOREVER), r.SetOccurrenceDetails(point, NAN, NAN, "longe", NAN, "normal", ALWAYS, FOREVER),
			r.SetOccurrenceDetails(point, NAN, NAN, "", NAN, "magia", ALWAYS, FOREVER), r.SetOccurrenceDetails(point, NAN, NAN, "", NAN, "normal", 10, 5)]:
		if bad != null:
			return fail("detalhe inválido aceito")
	edit.Undo()
	if not is_nan(r.OccurrenceDetails(point).grade):
		return fail("desfazer os detalhes")
	edit.Redo()
	ok("detalhes da ocorrência: teor, profundidade e acesso, com recusas e desfazer")

	# Quem conhece e direitos: por cadastro e período; a estimativa dele pode divergir da real.
	var reino: int = r.Create("pais", "Reino")
	var povo: int = r.Create("etnia", "Povo")
	var y5: int = Calendar.to_seconds(5, 1, 1)
	var k: int = r.AddKnowledge(point, reino, y5, FOREVER, 300.0, "")
	r.AddKnowledge(point, povo, ALWAYS, FOREVER, NAN, "")
	r.AddRight(point, reino, "controle", y5, FOREVER, "")
	r.AddRight(point, povo, "exploracao", ALWAYS, FOREVER, "concessão")
	if r.AddRight(point, reino, "posse", y5, FOREVER, "") != null or r.AddKnowledge(point, 999, ALWAYS, FOREVER, NAN, "") != null:
		return fail("direito ou cadastro inválido aceito")
	if r.Knowledge(point).size() != 2 or r.Knowledge(point)[1].estimate != 300.0 or r.Rights(point).size() != 2:
		return fail("conhecimento e direitos: %s / %s" % [r.Knowledge(point), r.Rights(point)])
	if Array(r.KnownBy(reino, Calendar.to_seconds(1, 1, 1))) != [] or Array(r.KnownBy(reino, y5)) != [point]:
		return fail("o reino só conhece a partir do ano 5")
	r.DeleteKnowledge(k)
	if r.Knowledge(point).size() != 1:
		return fail("tirar um conhecimento")
	ok("quem conhece (com estimativa própria e período) e direitos de controle, acesso e exploração")

	# Uma área dividida entre dois países: uma ocorrência só; a parte de cada um é proporcional à área.
	var area: int = r.AddArea(sal).Id
	r.SetOccurrenceReserve(area, 900.0)
	var layer := Territory.new()
	layer.Setup(terrain)
	layer.Begin()
	layer.Dab(EvronGeo.dir(30.0, 60.0), 600.0, area, false, -1)
	layer.End()
	var countries := Territory.new()
	countries.Setup(terrain)
	var vizinho: int = r.Create("pais", "Vizinho")
	countries.Begin()
	countries.Dab(EvronGeo.dir(30.0, 55.0), 600.0, reino, false, -1)
	countries.Dab(EvronGeo.dir(30.0, 65.0), 600.0, vizinho, false, -1)
	countries.End()
	var shares: Array = r.OccurrenceShares(area, layer, countries)
	var total := 0.0
	for s in shares:
		total += s.reserve
	if shares.size() < 2 or absf(total - 900.0) > 1e-6:
		return fail("a divisão entre países soma a reserva toda: %s" % [shares])
	ok("área sobre dois países: %d partes, a reserva não se duplica" % shares.size())

	# Produção: capacidade, prática, instalação, insumos alternativos, política e validade.
	var vila: int = r.CreateSettlement("Vila", 0.0, 10.1, 100)
	var carvoaria: int = r.CreateRecipe("Fazer carvão", "fabricacao", carvao, 1.0, 10.0, PackedFloat64Array([lenha, 4.0, sal, 8.0]))
	var queimar: int = r.CreateCapability("Queimar carvão")
	if r.CreateCapability("queimar CARVÃO") != queimar:
		return fail("o mesmo nome de capacidade devolve a que existe")
	r.SetRecipeExtras(carvoaria, queimar, PackedFloat64Array([forno, 5.0]), PackedFloat64Array([lenha, 1, sal, 1]))
	var rec: Dictionary = r.Recipes()[0]
	if rec.capability != "Queimar carvão" or rec.requirements.size() != 1 or rec.inputs[1].group != 1 or not rec.text.contains(" ou "):
		return fail("a receita com capacidade, requisito e alternativa: %s" % [rec])
	r.AddActivity(vila, carvoaria, 30)
	var jan: int = Calendar.to_seconds(1, 1, 1)
	var feb: int = Calendar.to_seconds(1, 2, 1)
	r.Intervene(vila, lenha, 40.0, jan, "")
	r.Intervene(vila, sal, 400.0, jan, "")
	r.RunMonth(jan, feb, terrain, {})
	if not r.Activities(vila)[0].last.begins_with("parou: ninguém em Vila sabe Queimar carvão"):
		return fail("sem a capacidade, parou: %s" % r.Activities(vila)[0].last)
	r.SetSettlementCapability(vila, queimar, 50)
	var mar: int = Calendar.to_seconds(1, 3, 1)
	r.RunMonth(feb, mar, terrain, {})
	if not r.Activities(vila)[0].last.begins_with("parou: falta Forno"):
		return fail("sem o forno, parou: %s" % r.Activities(vila)[0].last)
	r.Intervene(vila, forno, 2.0, feb, "")
	var apr: int = Calendar.to_seconds(1, 4, 1)
	r.RunMonth(mar, apr, terrain, {})
	# 2 fornos × 5 = 10 vezes (o trabalho daria 30 × 31 ÷ 10 × 50% = 46,5); lenha 40 ÷ 4 = 10 vezes: gasta a lenha toda, sal nenhum.
	if not _near(_stock(vila, carvao), 10.0) or _stock(vila, lenha) != 0.0 or not _near(_stock(vila, sal), 400.0) or not _near(_stock(vila, forno), 2.0):
		return fail("instalação limita, a lenha vem antes do sal e o forno não é gasto: %s" % [r.Stock(vila)])
	r.Intervene(vila, forno, 8.0, apr, "")
	var may: int = Calendar.to_seconds(1, 5, 1)
	r.RunMonth(apr, may, terrain, {})
	# Sem lenha, o sal (a alternativa) cobre: 30 × 30 ÷ 10 × 50% = 45 vezes × 8 = 360 de sal.
	if not _near(_stock(vila, carvao), 55.0) or not _near(_stock(vila, sal), 40.0):
		return fail("a alternativa cobre o que faltou: %s" % [r.Stock(vila)])
	ok("capacidade e prática, instalação que não é gasta e insumo alternativo")

	# Reserva: renovação, reposta pelo autor, bloqueada e validade no tempo.
	var extrair: int = r.CreateRecipe("Extrair sal", "extracao", sal, 10.0, 30.0, PackedFloat64Array())
	var mina: int = r.CreateSettlement("Mina", 0.0, 9.9, 30)
	r.AddActivity(mina, extrair, 30)
	r.SetOccurrenceDetails(point, NAN, NAN, "", 120.0, "normal", ALWAYS, FOREVER)  # renova 120 por ano
	var jun: int = Calendar.to_seconds(1, 6, 1)
	r.RunMonth(may, jun, terrain, {})  # tira 310
	var jul: int = Calendar.to_seconds(1, 7, 1)
	r.RunMonth(jun, jul, terrain, {})  # renova 120 × 30 ÷ 365 antes, depois tira 300
	var res: Dictionary = r.OccurrenceReserve(point)
	if not _near(res.regrown, 120.0 * 30.0 / 365.0) or not _near(res.left, 1000.0 - res.extracted + res.regrown):
		return fail("renovação: %s" % [res])
	r.SetOccurrenceDetails(point, NAN, NAN, "", NAN, "reposicao", ALWAYS, FOREVER)
	if r.OccurrenceReserve(point).left != 1000.0:
		return fail("reposta pelo autor: a reserva não acaba")
	r.SetOccurrenceDetails(point, NAN, NAN, "", NAN, "bloqueada", ALWAYS, FOREVER)
	var aug: int = Calendar.to_seconds(1, 8, 1)
	r.RunMonth(jul, aug, terrain, {})
	if not r.Activities(mina)[0].last.contains("bloqueada pelo autor"):
		return fail("bloqueada: %s" % r.Activities(mina)[0].last)
	r.SetOccurrenceDetails(point, NAN, NAN, "", NAN, "normal", Calendar.to_seconds(2, 1, 1), FOREVER)  # só passa a existir no ano 2
	var sep: int = Calendar.to_seconds(1, 9, 1)
	r.RunMonth(aug, sep, terrain, {})
	if not r.Activities(mina)[0].last.begins_with("parou: nenhuma ocorrência de Sal"):
		return fail("antes de existir, não há o que extrair: %s" % r.Activities(mina)[0].last)
	ok("renovação, reserva reposta pelo autor, bloqueada e ocorrência que só existe a partir de uma data")

	# Estoque numa data passada e somado por país (uma consulta, não outro estoque).
	if not _near(_stock_at(vila, carvao, Calendar.to_seconds(1, 4, 15)), 10.0) or _stock_at(vila, carvao, jan) != 0.0:
		return fail("estoque numa data: abril tinha 10 de carvão; janeiro, nada")
	var by_country: Array = r.StockByCountry(countries, terrain, FOREVER)
	if by_country.is_empty() or by_country.any(func(x): return x.country_id != 0):
		return fail("os povoados ficam fora dos países pintados: %s" % [by_country])
	countries.Begin()
	countries.Dab(EvronGeo.dir(0.0, 10.0), 300.0, reino, false, -1)
	countries.End()
	by_country = r.StockByCountry(countries, terrain, FOREVER)
	var carvao_reino := by_country.filter(func(x): return x.country == "Reino" and x.name == "Carvão")
	var sal_reino := by_country.filter(func(x): return x.country == "Reino" and x.name == "Sal")
	if carvao_reino.size() != 1 or not _near(carvao_reino[0].qty, _stock(vila, carvao) + _stock(mina, carvao)) 			or not _near(sal_reino[0].qty, _stock(vila, sal) + _stock(mina, sal)):
		return fail("os estoques da Vila contam para o Reino: %s" % [by_country])
	ok("estoque numa data e somado por país")

	# Relevo mudado depois de uma geração.
	var rule := JSON.stringify({"output": "ponto", "count": 3, "size_km": 500.0, "seed": 2})
	var plan = r.PlanResources(lenha, rule, terrain, Territory.new() if false else layer, {})
	r.ApplyGeneration(plan, layer)
	if r.GenerationStale(lenha, terrain):
		return fail("logo depois de gerar, não está desatualizada")
	terrain.SetH(1000, 4000.0)
	if not r.GenerationStale(lenha, terrain):
		return fail("o relevo mudou: a geração fica desatualizada")
	r.Close()
	ok("aviso de relevo mudado depois da geração")


func _good(good_name: String, unit: String, category: String) -> int:
	var id: int = r.CreateResourceType(good_name).Id
	r.SetResourceType(id, good_name, "", category, unit, 0x808080)
	return id


func _stock(settlement: int, good: int) -> float:
	return _stock_at(settlement, good, FOREVER)


func _stock_at(settlement: int, good: int, t: int) -> float:
	for item in r.StockAt(settlement, t):
		if int(item.good_id) == good:
			return item.qty
	return 0.0


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 1e-6 * maxf(1.0, absf(b))
