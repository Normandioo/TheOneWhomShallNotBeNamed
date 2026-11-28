extends "res://tests/test_suite.gd"
## Produção, etapa 3 (primeira cadeia). Sem cena: as contas de um mês, o mês que não se repete, a reserva que acaba e é dividida
## entre povoados, a ordem das atividades, o alcance e o histórico. Com a cena: o calendário processa o mês e a tela dos povoados.
## As linhas "ERROR" das recusas são esperadas.

const Calendar = preload("res://scripts/world/calendar.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const Terrain = preload("res://scripts/world/Terrain.cs")
const Territory = preload("res://scripts/world/Territory.cs")

var r
var terrain: Terrain


func run() -> void:
	var height := Image.create(512, 256, false, Image.FORMAT_RF)
	height.fill(Color(100.0, 0, 0))
	terrain = Terrain.new()
	terrain.Setup(height)
	var path := out_dir.path_join("production_suite.db")
	for ext in ["", "-journal", "-wal", "-shm"]:
		DirAccess.remove_absolute(path + ext)
	r = load("res://scripts/world/Registry.cs").new()
	r.OpenAtVersion(path, 19)
	r.Close()
	var raw = load("res://scripts/data/WorldDb.cs").new()  # um mundo antigo, escrito como o programa antigo escrevia
	raw.Open(path)
	raw.Execute("insert into resource_type(id, name, rgb) values (1, 'Antigo', 255)")
	raw.Execute("insert into resource_occurrence(id, type_id, kind, lat, lon) values (1, 1, 'ponto', 1, 1)")
	raw.Close()
	var old_point := 1
	r.Open(path)
	if not is_nan(r.OccurrenceReserve(old_point).reserve) or r.Settlements().size() != 0:
		return fail("um mundo da versão 19 abre sem povoados e com a quantidade desconhecida")
	ok("migração: mundo antigo sem povoados; quantidade das ocorrências desconhecida")

	var sal := _good("Sal", "kg")
	var lenha := _good("Lenha", "kg")
	var carvao := _good("Carvão", "kg")
	var point: int = r.AddPoint(sal, 0.0, 10.0).Id
	r.SetOccurrenceReserve(point, 1000.0)
	var vila: int = r.CreateSettlement("Vila do Sal", 0.0, 10.1, 40)  # ~11 km do sal
	var extrair: int = r.CreateRecipe("Extrair sal", "extracao", sal, 10.0, 30.0, PackedFloat64Array())
	var fazer: int = r.CreateRecipe("Fazer carvão", "fabricacao", carvao, 1.0, 10.0, PackedFloat64Array([lenha, 4.0]))
	for bad in [r.CreateRecipe("", "fabricacao", carvao, 1.0, 1.0, PackedFloat64Array()), r.CreateRecipe("x", "magia", carvao, 1.0, 1.0, PackedFloat64Array()),
			r.CreateRecipe("x", "fabricacao", carvao, 0.0, 1.0, PackedFloat64Array()), r.CreateRecipe("x", "fabricacao", carvao, 1.0, 1.0, PackedFloat64Array([carvao, 1.0])),
			r.CreateRecipe("x", "fabricacao", 999, 1.0, 1.0, PackedFloat64Array())]:
		if bad != null:
			return fail("receita inválida aceita")
	r.AddActivity(vila, extrair, 20)
	r.AddActivity(vila, fazer, 20)
	if r.AddActivity(vila, extrair, 1) != null or r.Activities(vila).size() != 2:
		return fail("um trabalhador não fica em duas atividades: 40 de 40 já postos")
	var start: int = Calendar.to_seconds(1, 1, 1)
	r.Intervene(vila, lenha, 100.0, start, "doação")
	r.Intervene(vila, lenha, -500.0, start, "")
	if _stock(vila, lenha) != 100.0:
		return fail("tirar mais do que há é recusado")
	ok("receitas, atividades e intervenções conferidas; trabalhador não é posto duas vezes")

	# Janeiro (31 dias): sal = 20 pessoas × 31 dias ÷ 30 pessoas-dia × 10 kg; carvão = só 100 ÷ 4 = 25 (faltou lenha).
	var feb: int = Calendar.to_seconds(1, 2, 1)
	if not r.RunMonth(start, feb, terrain, {}).ran:
		return fail("janeiro deveria rodar")
	if not _near(_stock(vila, sal), 20.0 * 31.0 / 30.0 * 10.0) or not _near(_stock(vila, carvao), 25.0) or _stock(vila, lenha) != 0.0:
		return fail("janeiro: %s" % [r.Stock(vila)])
	var notes: Array = r.Activities(vila).map(func(a): return a.last)
	if not notes[0].begins_with("+206,67 kg de Sal") or not notes[1].contains("limitado: faltou Lenha"):
		return fail("as notas do mês: %s" % [notes])
	var before: String = var_to_str(r.Stock(vila))
	if r.RunMonth(start, feb, terrain, {}).ran or var_to_str(r.Stock(vila)) != before:
		return fail("o mesmo mês não pode rodar duas vezes")
	ok("janeiro: produção, insumo que limita e mês que não se repete")
	var makers: Array = r.GoodMakers(carvao, feb)
	if makers.size() != 1 or int(makers[0].settlement_id) != vila or int(makers[0].workers) != 20 or not _near(makers[0].qty, 25.0) \
			or r.GoodMakers(carvao, start - 1).size() != 1 or not _near(r.GoodMakers(carvao, start - 1)[0].qty, 0.0):
		return fail("quem faz o carvão: %s" % [makers])
	ok("bem fabricado: os povoados que o fazem e o saldo na data")

	var mar: int = Calendar.to_seconds(1, 3, 1)
	r.RunMonth(feb, mar, terrain, {})
	if not _near(_stock(vila, sal), 10.0 * 20.0 * (31.0 + 28.0) / 30.0) or not r.Activities(vila)[1].last.begins_with("parou: faltou Lenha"):
		return fail("fevereiro (28 dias) e o carvão parado: %s" % [r.Activities(vila)])
	var reserve: Dictionary = r.OccurrenceReserve(point)
	if not _near(reserve.left, 1000.0 - _stock(vila, sal)) or not _near(reserve.extracted, _stock(vila, sal)):
		return fail("a reserva desconta o extraído: %s" % [reserve])
	ok("fevereiro: duração real do mês; a reserva desconta o que saiu")

	# Dois povoados na mesma ocorrência, com pouca reserva: cada um leva a parte proporcional ao que pediu.
	var vizinha: int = r.CreateSettlement("Vila Vizinha", 0.0, 9.9, 30)
	r.AddActivity(vizinha, extrair, 30)
	r.SetOccurrenceReserve(point, _stock(vila, sal) + 200.0)  # sobram 200
	var apr: int = Calendar.to_seconds(1, 4, 1)
	var sal_before := _stock(vila, sal)
	r.RunMonth(mar, apr, terrain, {})
	var got_vila := _stock(vila, sal) - sal_before
	var got_vizinha := _stock(vizinha, sal)
	if not _near(got_vila + got_vizinha, 200.0) or not _near(got_vila / got_vizinha, 20.0 / 30.0) or r.OccurrenceReserve(point).left > 1e-6:
		return fail("divisão proporcional: vila %.2f, vizinha %.2f" % [got_vila, got_vizinha])
	if not r.Activities(vizinha)[0].last.contains("dividida com outro povoado"):
		return fail("a nota diz que a reserva foi dividida")
	var may: int = Calendar.to_seconds(1, 5, 1)
	r.RunMonth(apr, may, terrain, {})
	if not r.Activities(vizinha)[0].last.begins_with("parou: a reserva de Sal ao alcance acabou"):
		return fail("reserva acabada: %s" % [r.Activities(vizinha)])
	ok("reserva dividida pela proporção pedida, sem favorecer a ordem; reserva acabada para a extração")

	# Ordem das atividades: com menos trabalhadores que o posto, a de cima fica com eles. Subir muda isso.
	var aldeia: int = r.CreateSettlement("Aldeia", 20.0, -40.0, 30)
	var mato: int = r.AddPoint(lenha, 20.0, -40.2).Id
	r.SetOccurrenceReserve(mato, 100000.0)
	var coletar: int = r.CreateRecipe("Coletar lenha", "extracao", lenha, 5.0, 1.0, PackedFloat64Array())
	var first: int = r.AddActivity(aldeia, coletar, 20)
	var second: int = r.AddActivity(aldeia, coletar, 10)
	r.SetSettlement(aldeia, "Aldeia", 20, 50.0)  # agora são só 20
	var jun: int = Calendar.to_seconds(1, 6, 1)
	r.RunMonth(may, jun, terrain, {})
	var acts: Array = r.Activities(aldeia)
	if not acts[1].last.begins_with("parou: sem trabalhadores livres") or not acts[0].last.begins_with("+"):
		return fail("a de cima fica com os trabalhadores: %s" % [acts])
	r.MoveActivityUp(second)
	r.RunMonth(jun, Calendar.to_seconds(1, 7, 1), terrain, {})
	acts = r.Activities(aldeia)
	if int(acts[0].id) != second or not acts[1].last.contains("só 10 de 20 pessoas"):
		return fail("subir a atividade a põe na frente: %s" % [acts])
	ok("ordem das atividades decide quem fica com os trabalhadores")

	# Alcance: nenhuma ocorrência perto; ocorrência sem quantidade; área pintada ao alcance.
	var longe: int = r.CreateSettlement("Longe", -50.0, 120.0, 10)
	r.AddActivity(longe, extrair, 10)
	var sem: int = r.CreateSettlement("Sem número", 40.0, -100.0, 10)
	r.AddPoint(sal, 40.0, -100.1)
	r.AddActivity(sem, extrair, 10)
	var area: int = r.AddArea(lenha).Id
	var layer := Territory.new()
	layer.Setup(terrain)
	layer.Begin()
	layer.Dab(EvronGeo.dir(30.0, 60.0), 300.0, area, false, -1)
	layer.End()
	r.SetOccurrenceReserve(area, 500.0)
	var borda: int = r.CreateSettlement("Borda da mata", 30.0, 64.0, 10)
	r.AddActivity(borda, coletar, 10)
	if Array(r.ExtractedGoods()).has(lenha) == false:
		return fail("os bens extraídos incluem a lenha")
	var jul: int = Calendar.to_seconds(1, 7, 1)
	var aug: int = Calendar.to_seconds(1, 8, 1)
	r.SetSettlement(borda, "Borda da mata", 10, 10.0)
	r.RunMonth(jul, aug, terrain, {lenha: layer})
	if not r.Activities(longe)[0].last.begins_with("parou: nenhuma ocorrência de Sal a até 50 km"):
		return fail("sem ocorrência perto: %s" % [r.Activities(longe)])
	if not r.Activities(sem)[0].last.contains("não tem quantidade definida"):
		return fail("ocorrência sem quantidade: %s" % [r.Activities(sem)])
	if not r.Activities(borda)[0].last.begins_with("parou: nenhuma ocorrência"):
		return fail("área fora do alcance de 10 km: %s" % [r.Activities(borda)])
	r.SetSettlement(borda, "Borda da mata", 10, 300.0)
	r.RunMonth(aug, Calendar.to_seconds(1, 9, 1), terrain, {lenha: layer})
	if not r.Activities(borda)[0].last.begins_with("+") or not _near(r.OccurrenceReserve(area).extracted, _stock(borda, lenha)):
		return fail("área pintada ao alcance: %s" % [r.Activities(borda)])
	ok("alcance: sem ocorrência, sem quantidade, área fora e dentro do alcance")

	# Histórico: o estoque é a soma das movimentações e nunca fica negativo; o que tem história não some.
	for s in r.Settlements():
		for item in r.Stock(int(s.id)):
			if item.qty < -1e-9:
				return fail("estoque negativo: %s %s" % [s.name, item])
	r.DeleteSettlement(vila)
	r.DeleteRecipe(extrair)
	r.DeleteResourceType(carvao)
	if r.Settlements().size() != 6 or r.Recipes().size() != 3 or r.ResourceTypes("Carvão").size() != 1:
		return fail("o que tem história ou está em uso não pode ser excluído")
	var nada: int = r.CreateSettlement("Engano", 0.0, 0.0, 0)
	r.DeleteSettlement(nada)
	var final_state := _state()
	r.Close()
	r.Open(path)
	if _state() != final_state or not r.MonthDone(feb):
		return fail("reabrir conserva estoques, atividades e os meses feitos")
	r.Close()
	ok("histórico conservado; exclusões só sem uso; reabrir guarda tudo")
	if main != null:
		await _run_scene()


## Com a cena: o calendário processa o mês uma vez só, e a tela dos povoados cria, mostra o resultado e muda o estoque.
func _run_scene() -> void:
	await frames(5)
	var prod = main.production
	var panel = prod.panel
	var reg = main.domains.registry
	var sal: int = reg.CreateResourceType("Sal").Id
	reg.SetResourceType(sal, "Sal", "", "", "kg", 0xffffff)
	var point: int = reg.AddPoint(sal, 0.0, 10.0).Id
	reg.SetOccurrenceReserve(point, 5000.0)
	main.tool_panel.settlements_toggle.button_pressed = true
	await frames(2)
	if not panel.visible or not panel.list_box.visible or main.resources.panel.visible:
		return fail("o botão abre a lista dos povoados")
	panel.recipes_requested.emit()
	panel.recipe_saved.emit(0, {"name": "Extrair sal", "kind": "extracao", "output_id": sal, "output_qty": 10.0, "labor_days": 30.0, "inputs": []})
	if reg.Recipes().size() != 1:
		return fail("a tela de receitas cria a receita: " + panel.message.text)
	panel.back_requested.emit()
	panel.new_name.text = "Vila do Sal"
	panel.new_workers.value = 40
	panel.create_requested.emit(panel.new_name.text, 40)
	main.select(EvronGeo.dir(0.0, 10.1))
	if reg.Settlements().size() != 1 or not panel.place_box.visible or main.globe.settlements.label_count != 1:
		return fail("o clique no globo põe o povoado e abre a tela dele")
	panel.activity_added.emit(int(reg.Recipes()[0].id), 50)
	if not panel.message.text.begins_with("Não há trabalhadores livres"):
		return fail("mais pessoas que o povoado tem: aviso")
	panel.activity_added.emit(int(reg.Recipes()[0].id), 30)
	var village: int = prod.settlement_id
	# Uma atividade diferente, sem sair do povoado: o botão abre a receita em branco, e salvar volta com ela escolhida.
	panel.create_activity.pressed.emit()
	if not panel.recipes_box.visible or panel.title.text != "RECEITAS" or panel.recipe_name.text != "" or panel.recipe_output.selected != -1:
		return fail("o botão abre uma receita em branco: %s" % panel.title.text)
	panel.recipe_name.text = "Secar sal"
	prod.refresh()  # como na virada do mês: o que foi digitado fica
	panel._save_recipe()
	if panel.recipe_name.text != "Secar sal" or panel.recipe_output.selected != -1 or not panel.message.text.begins_with("Escolha o bem que a receita produz"):
		return fail("sem o bem escolhido o formulário fica como está: %s" % panel.message.text)
	panel.recipe_output.select(0)
	panel._save_recipe()
	if panel.recipe_name.text != "Secar sal":
		return fail("uma receita recusada não pode apagar o formulário")
	panel.back_requested.emit()
	if not panel.place_box.visible or prod.settlement_id != village:
		return fail("voltar das receitas, vindo do povoado, volta para ele")
	panel.create_activity.pressed.emit()
	panel.recipe_saved.emit(0, {"name": "Secar sal", "kind": "fabricacao", "output_id": sal, "output_qty": 1.0, "labor_days": 2.0, "inputs": []})
	if not panel.place_box.visible or prod.settlement_id != village or panel.activity_recipe.get_item_text(panel.activity_recipe.selected) != "Secar sal" \
			or not panel.message.text.contains("criada"):
		return fail("salvar volta ao povoado com a atividade escolhida: " + panel.message.text)
	for x in reg.Recipes():
		if x.name == "Secar sal":
			reg.DeleteRecipe(int(x.id))  # o resto da suíte conta com uma receita só
	prod.refresh()
	main.clock.now = Calendar.to_seconds(1, 1, 15)
	main.clock.advance_months(1)  # passa por 1º de fevereiro: janeiro é processado
	if not _near(_stock_of(reg, village, sal), 30.0 * 31.0 / 30.0 * 10.0) or not panel.results_box.get_child(1).text.contains("+310 kg de Sal"):
		return fail("o calendário processa janeiro e a tela mostra: %s" % panel.results_box.get_child(1).text)
	main.clock.now = Calendar.to_seconds(1, 1, 20)  # como se o relógio salvo fosse mais velho que o banco
	main.clock.advance_months(1)
	if not _near(_stock_of(reg, village, sal), 310.0):
		return fail("voltar o relógio e passar pelo mesmo mês não produz de novo")
	panel.show_tab(1)
	panel.stock_qty.text = "10,5"
	panel.stock_good.select(0)
	panel._stock(-1.0)
	if not _near(_stock_of(reg, village, sal), 299.5):
		return fail("tirar do estoque pela tela: %s" % panel.message.text)
	panel.show_tab(0)
	main.globe.focus(EvronGeo.dir(0.0, 10.0), 1.6)
	await save("povoado_atividades")
	panel.show_tab(2)
	panel.capability_name.text = "Fundir bronze"
	panel.capability_level.value = 70
	panel.capability_set.emit("Fundir bronze", 70)
	if reg.SettlementCapabilities(village).size() != 1 or panel.capabilities.item_count != 1:
		return fail("o povoado aprende uma capacidade pela tela")
	panel.recipes_requested.emit()
	panel.recipe_saved.emit(0, {"name": "Bronze", "kind": "fabricacao", "output_id": sal, "output_qty": 1.0, "labor_days": 5.0,
		"inputs": [], "requirements": [], "capability": "Fundir bronze"})
	var bronze: Array = Array(reg.Recipes()).filter(func(x): return x.name == "Bronze")
	if bronze.size() != 1 or bronze[0].capability != "Fundir bronze":
		return fail("a receita exige a capacidade pela tela: %s" % [bronze])
	if panel.stock_title.text.begins_with("Estoque em") == false:
		return fail("o estoque diz a data")
	# Um bem fabricado nasce na receita, como Manufatura, e no painel Recursos aparece pelos povoados, não pelo mapa.
	panel.good_create_requested.emit("Espada")
	var espada: Array = Array(reg.ResourceTypes("Espada"))
	if espada.size() != 1 or espada[0].category != "manufatura" or int(panel._goods[panel.recipe_output.selected].id) != int(espada[0].id):
		return fail("criar o bem na receita o deixa escolhido: %s" % panel.message.text)
	panel.back_requested.emit()
	main.tool_panel.resources_toggle.button_pressed = true
	if panel.visible or not main.resources.panel.visible:
		return fail("um painel lateral por vez")
	var res_panel = main.resources.panel
	res_panel.type_chosen.emit(int(espada[0].id))
	if not res_panel._made or res_panel.add_row.visible or res_panel.tab_buttons[1].visible or not res_panel.made_note.text.contains("Nenhuma receita"):
		return fail("Manufatura sem lugar no mapa mostra a produção: %s" % res_panel.made_note.text)
	res_panel.type_chosen.emit(sal)
	if res_panel._made or not res_panel.add_row.visible or not res_panel.tab_buttons[1].visible:
		return fail("um recurso natural continua no mapa")
	main.commands.undo()
	if reg.ResourceTypes("Espada").size() != 0:
		return fail("Ctrl+Z desfaz o bem criado na receita")
	main.resources.set_open(false)
	ok("cena: o calendário processa o mês uma vez; criar, receita, atividade e estoque pela tela")


func _good(good_name: String, unit: String) -> int:
	var id: int = r.CreateResourceType(good_name).Id
	r.SetResourceType(id, good_name, "", "", unit, 0x808080)
	return id


func _stock(settlement: int, good: int) -> float:
	return _stock_of(r, settlement, good)


func _stock_of(reg, settlement: int, good: int) -> float:
	for item in reg.Stock(settlement):
		if int(item.good_id) == good:
			return item.qty
	return 0.0


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 1e-6 * maxf(1.0, absf(b))


func _state() -> String:
	var rows: Array = [r.Settlements(), r.Recipes()]
	for s in r.Settlements():
		rows.append_array([r.Activities(int(s.id)), r.Stock(int(s.id))])
	return var_to_str(rows)
