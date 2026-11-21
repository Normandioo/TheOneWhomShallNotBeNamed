extends "res://tests/test_suite.gd"
## Regras (E3; aceite 6 a 8): uma regra com condição e cálculo, executada em datas diferentes do mundo, e um valor fixado pelo autor que
## a regra respeita. Também a validação da definição e as versões. As linhas "ERROR" das recusas são esperadas.

const Rules = preload("res://scripts/world/rules.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")


## Pela janela de regras (cena): montar a regra ligando nós, conferir que falta de ligação é avisada, salvar, reabrir em nós (ida e volta
## igual), executar na data mostrada, fixar; e o modo automático, que faz a ficha mostrar o valor.
func _ui() -> void:
	var hub = main.domains
	var reg = hub.registry
	var fort: String = reg.CreateEntityType("Fortaleza")
	var city: String = reg.CreateEntityType("Cidade")
	var garrison: String = reg.AddField("Guarnição", "number", "", "", PackedStringArray([fort]))
	var power: String = reg.AddField("Poder", "number", "", "", PackedStringArray([fort]))
	var guards: String = reg.CreateRelationType("Protege", "Protegida por", fort, city)
	var castle: int = reg.Create(fort, "Castelo Negro")
	reg.SetField(castle, garrison, "known", "100")
	for i in 2:
		reg.Link(castle, reg.Create(city, "Vila %d" % i), guards)
	hub.search.rules_requested.emit()
	var panel = main.rules.rules_panel
	panel._kind.select(panel._kinds.find(fort))
	panel._kind.item_selected.emit(panel._kinds.find(fort))
	panel._name.text = "Poder das fortalezas"
	panel._target.select(panel._targets.find(power))
	var g: GraphEdit = panel._graph
	# Se vínculos > 0 então guarnição × vínculos senão guarnição ÷ 2
	var when = panel.add_node("if")
	var count = panel.add_node("links")
	var zero = panel.add_node("const")
	var times = panel.add_node("math")
	var by = panel.add_node("math")
	var gar1 = panel.add_node("field")
	var gar2 = panel.add_node("field")
	var count2 = panel.add_node("links")
	var two = panel.add_node("const")
	times.get_node("Head").select(2)
	by.get_node("Head").select(3)
	two.get_node("Head").value = 2
	gar1.get_node("Head").select(panel._fields.map(func(f): return f.code).find(garrison))
	gar2.get_node("Head").select(panel._fields.map(func(f): return f.code).find(garrison))
	for n in [count, count2]:
		n.get_node("Head").select(panel._links.map(func(l): return l.code).find(guards))
	for c in [[count, when, 0], [zero, when, 1], [times, when, 2], [gar1, times, 0], [count2, times, 1], [gar2, by, 0], [two, by, 1]]:
		panel._on_connect(c[0].name, 0, c[1].name, c[2])
	panel._on_connect(when.name, 0, panel._result.name, 0)
	panel._save()
	if not panel._message.text.contains("senão") or panel._rule_ids.size() != 0:
		return fail("faltando ligar o \"senão\", nada é salvo e o aviso diz qual: " + panel._message.text)
	panel._on_connect(by.name, 0, when.name, 3)
	var built = panel.graph_rule()
	var expected := Rules.rule(fort, power, Rules.when(Rules.links(guards), "gt", Rules.number(0),
		Rules.calc(Rules.field(garrison), "mul", Rules.links(guards)), Rules.calc(Rules.field(garrison), "div", Rules.number(2))))
	if JSON.parse_string(JSON.stringify(built)) != JSON.parse_string(JSON.stringify(expected)):
		return fail("os nós ligados viram a definição esperada: %s" % [built])
	panel._save()
	if panel._rule_ids.size() != 1:
		return fail("a regra montada em nós é salva: " + panel._message.text)
	panel.open_rule(panel._rule_ids[0], panel._rule_names[0], panel._rule_defs[0])
	if JSON.parse_string(JSON.stringify(panel.graph_rule())) != JSON.parse_string(JSON.stringify(expected)):
		return fail("abrir a regra redesenha os mesmos nós (ida e volta igual)")
	panel._save()
	if hub.registry.Rules()[0].version != 2:
		return fail("salvar a regra aberta grava uma versão nova dela")
	ok("editor de nós: ligar, aviso de entrada solta, salvar, reabrir em nós igual e versão nova")

	panel._list.select(0)
	panel.run_requested.emit(panel._rule_ids[0])
	if panel._result_rows.size() != 1 or panel._result_rows[0].value != 200.0:
		return fail("executar na data mostrada dá 200: %s" % [panel._result_rows])
	hub.open(castle)
	panel.mode_requested.emit(panel._rule_ids[0], "toggle")  # manual -> automático
	if reg.Rules()[0].mode != "automatico" or not _sheet_text(hub).contains("= 200 pela regra"):
		return fail("no modo automático a ficha mostra o valor calculado na data mostrada: " + _sheet_text(hub).replace("
", " / "))
	panel._results.select(0)
	panel.pin_requested.emit(castle, panel._last_field, 999.0, "decisão do autor")
	if not _sheet_text(hub).contains("🔒 999 fixado") or not _sheet_text(hub).contains("calcularia 200"):
		return fail("depois de fixar, a ficha mostra 999 fixado e o que a regra daria: " + _sheet_text(hub).replace("
", " / "))
	panel.run_requested.emit(panel._rule_ids[0])
	if panel._result_rows[0].status != "fixado" or panel._result_rows[0].value != 999.0:
		return fail("a execução respeita o fixado: %s" % [panel._result_rows])
	# Os nós novos no editor: distância até a Vila 0, ida e volta igual.
	panel._new_rule()
	var dist = panel.add_node("distance")
	var village: int = panel._entities.filter(func(e): return e.name.begins_with("Vila 0"))[0].id
	dist.get_node("Head").select(panel._entities.map(func(e): return e.id).find(village))
	panel._on_connect(dist.name, 0, panel._result.name, 0)
	var dist_rule = panel.graph_rule()
	panel.open_rule(0, "Distância", JSON.parse_string(JSON.stringify(dist_rule)))
	if dist_rule == null or dist_rule.expr.op != "distance" or int(dist_rule.expr.to) != village 			or JSON.parse_string(JSON.stringify(panel.graph_rule())) != JSON.parse_string(JSON.stringify(dist_rule)):
		return fail("o nó de distância vira a definição e volta igual: %s" % [dist_rule])
	ok("modo automático na ficha (= 200), fixação mostrada na ficha e respeitada na execução (999)")


func _sheet_text(hub) -> String:
	var out := ""
	var stack: Array = [hub.sheet]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			out += n.text + "
"
		stack.append_array(n.get_children())
	return out


func run() -> void:
	if main != null:
		await _ui()
		return
	var path := out_dir.path_join("rules_suite.db")
	for ext in ["", "-journal"]:
		DirAccess.remove_absolute(path + ext)
	var reg = load("res://scripts/world/Registry.cs").new()
	reg.Open(path)
	var fort: String = reg.CreateEntityType("Fortaleza")
	var city: String = reg.CreateEntityType("Cidade")
	var garrison: String = reg.AddField("Guarnição", "number", "soldados", "", PackedStringArray([fort]))
	var power: String = reg.AddField("Poder", "number", "", "", PackedStringArray([fort]))
	var name_field: String = reg.AddField("Lema", "text", "", "", PackedStringArray([fort]))
	var guards: String = reg.CreateRelationType("Protege", "Protegida por", fort, city)
	var castle: int = reg.Create(fort, "Castelo Negro")
	var tower: int = reg.Create(fort, "Torre Branca")
	var empty: int = reg.Create(fort, "Forte Vazio")  # sem guarnição: a regra dá erro só para ele
	reg.SetField(castle, garrison, "known", "100")
	reg.SetField(tower, garrison, "known", "40")
	for i in 2:
		reg.LinkDuring(castle, reg.Create(city, "Vila %d" % i), guards, 1000, 9223372036854775807)

	# 6. Regra com condição e cálculo: Poder = se protege alguma cidade, guarnição × cidades protegidas; senão, guarnição ÷ 2.
	var links := Rules.links(guards)
	var rule := Rules.rule(fort, power, Rules.when(links, "gt", Rules.number(0),
		Rules.calc(Rules.field(garrison), "mul", links), Rules.calc(Rules.field(garrison), "div", Rules.number(2))))
	var bad := [
		Rules.rule(fort, name_field, Rules.number(1)),                                   # alvo de texto
		Rules.rule(fort, power, Rules.links("nao_existe")),                              # vínculo inexistente
		Rules.rule(fort, power, {"op": "exec", "code": "OS.shell_open('x')"}),           # nó desconhecido: nunca código
		Rules.rule(fort, power, Rules.calc(Rules.number(1), "add", {})),                 # nó faltando
	]
	for b in bad:
		if reg.ValidateRule(JSON.stringify(b)) == "":
			return fail("definição inválida deveria ser recusada: %s" % [b])
	if reg.ValidateRule(JSON.stringify(rule)) != "":
		return fail("a regra válida passa: " + reg.ValidateRule(JSON.stringify(rule)))
	var id: int = reg.SaveRule(0, "Poder das fortalezas", JSON.stringify(rule))
	ok("regra com condição e cálculo validada (alvo de texto, vínculo inexistente, nó desconhecido e nó faltando recusados)")

	# 7. Executar em datas históricas: antes dos vínculos o castelo vale 100 ÷ 2; depois, 100 × 2.
	var before: Dictionary = reg.RunRule(id, 500)
	var after: Dictionary = reg.RunRule(id, 2000)
	var v_before := _value(before, castle)
	var v_after := _value(after, castle)
	if v_before.value != 50.0 or v_after.value != 200.0 or _value(after, tower).value != 20.0:
		return fail("Poder em t=500 é 50 e em t=2000 é 200 (Torre: 20): %s / %s" % [v_before, v_after])
	if _value(after, empty).status != "erro" or not String(_value(after, empty).note).contains("Guarnição"):
		return fail("a entidade sem guarnição dá erro só para ela: %s" % [_value(after, empty)])
	ok("execução em datas do mundo: 50 antes dos vínculos, 200 depois; erro isolado na entidade sem dado")

	# 8. Fixação autoral: de t=1500 em diante o Poder do castelo é 999, e a regra respeita (e avisa que calcularia outro valor).
	reg.PinField(castle, power, 999, 1500, 9223372036854775807, "decisão do autor")
	var pinned := _value(reg.RunRule(id, 2000), castle)
	var unpinned := _value(reg.RunRule(id, 1200), castle)
	if pinned.status != "fixado" or pinned.value != 999.0 or pinned.computed != 200.0 or not String(pinned.note).contains("200"):
		return fail("o valor fixado prevalece e a divergência é sinalizada: %s" % [pinned])
	if unpinned.status != "calculado" or unpinned.value != 200.0:
		return fail("antes do período fixado vale o cálculo: %s" % [unpinned])
	ok("fixação autoral: a regra respeita 999 a partir de t=1500 e registra que calcularia 200")

	# Entradas novas: população (a estimativa mais recente até t), área (território pintado ou o maior lugar) e distância entre lugares.
	var keep: int = reg.AddPlace("Castelo", "assentamento", 0, 0, 50, "")
	var spire: int = reg.AddPlace("Torre", "assentamento", 0, 10, 20, "")
	reg.AddPresence(castle, keep, "capital", "alta")
	reg.AddPresence(tower, spire, "sede", "alta")
	reg.AddEstimate(castle, keep, 100, 900, 1100, "media", "")
	reg.AddEstimate(castle, keep, 3000, 2000, 2000, "media", "")
	var people: String = reg.AddField("Gente", "number", "", "", PackedStringArray([fort]))
	var reach: String = reg.AddField("Alcance", "number", "", "", PackedStringArray([fort]))
	var far: String = reg.AddField("Longe da torre", "number", "", "", PackedStringArray([fort]))
	var r_people: int = reg.SaveRule(0, "Gente", JSON.stringify(Rules.rule(fort, people, Rules.population())))
	var r_area: int = reg.SaveRule(0, "Alcance", JSON.stringify(Rules.rule(fort, reach, Rules.area())))
	var r_far: int = reg.SaveRule(0, "Longe", JSON.stringify(Rules.rule(fort, far, Rules.distance(tower))))
	if r_people == 0 or r_area == 0 or r_far == 0 or reg.ValidateRule(JSON.stringify(Rules.rule(fort, far, Rules.distance(999999)))) == "":
		return fail("as regras novas valem; distância até entidade inexistente é recusada")
	if _value(reg.RunRule(r_people, 2000), castle).value != 1000.0 or _value(reg.RunRule(r_people, 3500), castle).value != 2000.0 			or _value(reg.RunRule(r_people, 50), castle).status != "erro":
		return fail("população: 1000 em t=2000, 2000 em t=3500, erro antes da primeira estimativa")
	var disc := 2 * PI * 6371.0 * 6371.0 * (1 - cos(50.0 / 6371.0))
	var area_value: float = _value(reg.RunRule(r_area, 2000), castle).value
	if absf(area_value - disc) > 1.0:
		return fail("área sem território pintado = a do lugar (%.0f km²): %.0f" % [disc, area_value])
	var d: float = _value(reg.RunRule(r_far, 2000), castle).value
	if absf(d - 6371.0 * PI / 18.0) > 1.0 or _value(reg.RunRule(r_far, 2000), empty).status != "erro":
		return fail("distância entre a capital do castelo e a sede da torre ≈ 1.112 km; sem lugar dá erro: %.1f" % d)
	# Área pintada: um país com território na camada entregue ao Registry.
	var terrain = load("res://scripts/world/Terrain.cs").new()
	terrain.Setup(Image.create(256, 128, false, Image.FORMAT_RF))
	var layer = load("res://scripts/world/Territory.cs").new()
	layer.Setup(terrain)
	var land: int = reg.Create("pais", "Aren")
	layer.Begin()
	layer.Dab(EvronGeo.dir(0, 0), 1500, land, false, -1)
	layer.End()
	reg.UseTerritory("pais", layer)
	var size_field: String = reg.AddField("Tamanho", "number", "km²", "", PackedStringArray(["pais"]))
	var r_size: int = reg.SaveRule(0, "Tamanho", JSON.stringify(Rules.rule("pais", size_field, Rules.area())))
	if absf(_value(reg.RunRule(r_size, 0), land).value - layer.AreaKm2(land)) > 1e-6:
		return fail("área de um país = o território pintado")
	ok("população na data (1000, depois 2000), área do lugar e do território pintado, distância entre capitais (1.112 km)")

	# Versões e modos: uma nova versão é a que roda; desativada não roda; reabrir conserva.
	rule.expr = Rules.number(7)
	reg.SaveRule(id, "Poder das fortalezas", JSON.stringify(rule))
	var v2: Dictionary = reg.RunRule(id, 2000)
	if v2.version != 2 or _value(v2, tower).value != 7.0:
		return fail("a versão nova é a executada")
	reg.SetRuleMode(id, "desativado")
	if reg.RunRule(id, 2000) != null:
		return fail("regra desativada não executa")
	reg.Close()
	reg.Open(path)
	var rules: Array = reg.Rules()
	if rules.size() != 5 or rules[0].version != 2 or rules[0].mode != "desativado":
		return fail("reabrir conserva regras, versões e modo")
	reg.Close()
	ok("versões (a nova é a que roda), modo desativado e reabrir")


func _value(run: Dictionary, entity: int) -> Dictionary:
	for r in run.results:
		if int(r.entity_id) == entity:
			return r
	return {}
