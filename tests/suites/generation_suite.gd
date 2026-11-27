extends "res://tests/test_suite.gd"
## Recursos, etapa 2: a geração. Em um mundo sintético (sem cena): as condições valem, a mesma semente repete o resultado, o que é
## do autor nunca muda, o que ele tira não volta e aplicar é um desfazer só. Com a cena: cada modelo contra os mapas reais e a
## prévia pela tela. As linhas "ERROR" das recusas são esperadas.

const CommandStack = preload("res://scripts/edit/command_stack.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")
const Terrain = preload("res://scripts/world/Terrain.cs")
const Territory = preload("res://scripts/world/Territory.cs")
const ResourceController = preload("res://scripts/app/resource_controller.gd")
const GeneratorPanel = preload("res://scripts/ui/generator_panel.gd")
const ResourceProfiles = preload("res://scripts/ui/resource_profiles.gd")
const BlindReview = preload("res://scripts/app/blind_review.gd")
const GoldenSet = preload("res://scripts/app/golden_set.gd")
const GeneratorController = preload("res://scripts/app/generator_controller.gd")

const W := 512
const H := 256
const GRANITE := Color8(190, 100, 220)
const SANDSTONE := Color8(200, 190, 15)

var terrain: Terrain
var maps := {}
var r


func run() -> void:
	# Mundo sintético: terra a leste do meridiano 0 (100 m), mar a oeste (−100 m); granito ao norte, arenito ao sul.
	var height := Image.create(W, H, false, Image.FORMAT_RF)
	var rock := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		for x in W:
			height.set_pixel(x, y, Color(100.0 if x >= W / 2 else -100.0, 0, 0))
			rock.set_pixel(x, y, GRANITE if y < H / 2 else SANDSTONE)
	terrain = Terrain.new()
	terrain.Setup(height)
	maps = {"Bedrock.png": rock}

	var path := out_dir.path_join("generation_suite.db")
	for ext in ["", "-journal", "-wal", "-shm"]:
		DirAccess.remove_absolute(path + ext)
	r = load("res://scripts/world/Registry.cs").new()
	r.OpenAtVersion(path, 18)
	r.Close()
	r.Open(path)
	var ore: int = r.CreateResourceType("Minério").Id
	if r.ResourceRuleOf(ore) != "":
		return fail("um mundo da versão 18 deveria ganhar a geração, sem regra")

	var layer := _new_layer()
	var base := {"rocks": ["intrusiva"], "output": "area", "count": 6, "size_km": 600.0, "seed": 7}
	var first = _plan(ore, base, layer)
	if first.Error != "" or first.Count != 6:
		return fail("deveria sugerir 6 áreas: %s (%d)" % [first.Error, first.Count])
	if _proposals(first) != _proposals(_plan(ore, base, layer)):
		return fail("a mesma semente deveria repetir o resultado")
	var other := base.duplicate()
	other.seed = 8
	if _proposals(first) == _proposals(_plan(ore, other, layer)):
		return fail("outra semente deveria mudar o resultado")
	for i in first.Count:
		var p: Dictionary = first.Proposal(i)
		if p.lat <= 0.0 or p.lon <= 0.0 or p.km2 <= 0.0:
			return fail("sugestão fora da terra com granito (nordeste): %s" % [p])
	if r.Occurrences(0).size() != 0 or layer.AreaKm2(0) != 0.0 or r.ResourceRuleOf(ore) != "":
		return fail("a prévia não pode gravar nada")
	ok("condições valem; mesma semente repete; a prévia não grava")

	if r.CheckResourceRule('{"count": 8.0, "seed": 3.0}') != "" or r.CheckResourceRule('{"count": 8.5}') == "":
		return fail("um inteiro escrito como 8.0 vale; 8.5 não")
	for bad in ["{", '{"count": 0}', '{"surface": "mar", "rocks": ["intrusiva"]}', '{"rocks": ["queijo"]}', '{"elev_min": 10, "elev_max": 0}',
			'{"size_km": 1}']:
		if r.CheckResourceRule(bad) == "" or r.PlanResources(ore, bad, terrain, layer, maps).Error == "":
			return fail("regra inválida aceita: " + bad)
	if r.PlanResources(ore, JSON.stringify(base), terrain, layer, {}).Error == "":
		return fail("sem o mapa de rochas não há prévia")
	ok("regras inválidas e mapa faltando são recusados com motivo")

	# O que é do autor: uma área manual pintada em cima da primeira sugestão e um ponto manual.
	var stack := CommandStack.new()
	var mine = r.AddArea(ore)
	var spot: Dictionary = first.Proposal(0)
	layer.Begin()
	layer.Dab(EvronGeo.dir(spot.lat, spot.lon), 300.0, mine.Id, true, -1)
	layer.End()
	var mine_km2: float = layer.AreaKm2(mine.Id)
	var point = r.AddPoint(ore, -40.0, 100.0)
	var stale = _plan(ore, base, layer)
	r.SetOccurrenceText(point.Id, "meu ponto", "")
	if r.ApplyGeneration(stale, layer).size() != 0:
		return fail("uma prévia de um mundo que mudou deveria ser recusada")
	var before := _state(ore, layer)
	var plan = _plan(ore, base, layer)
	if plan.ProtectedCount != 2 or plan.ReplacedCount != 0 or plan.Count != 5:
		return fail("a sugestão em cima da área manual deveria sair: %d protegidas, %d sugestões" % [plan.ProtectedCount, plan.Count])
	plan.Toggle(1)
	var rejected: Dictionary = plan.Proposal(1)
	var cmds: Array = r.ApplyGeneration(plan, layer)
	if cmds.is_empty():
		return fail("aplicar")
	stack.push("gerar", ResourceController.Batch.new(cmds))
	var made: Array = r.Occurrences(ore).filter(func(o): return o.origin == "gerada")
	if made.size() != 4 or r.SuppressionCount(ore) != 1 or layer.AreaKm2(mine.Id) != mine_km2 or r.ResourceRuleOf(ore) == "":
		return fail("4 geradas, 1 supressão, área manual intacta e regra gravada: %d, %d" % [made.size(), r.SuppressionCount(ore)])
	for o in made:
		if o.fixed or o.state != "narrativo" or layer.AreaKm2(o.id) <= 0.0:
			return fail("gerada: sem fixar, narrativa e pintada: %s" % [o])
	var applied := _state(ore, layer)
	stack.undo()
	if _state(ore, layer) != before or r.SuppressionCount(ore) != 0 or r.ResourceRuleOf(ore) != "":
		return fail("um desfazer deveria voltar a antes da geração")
	stack.redo()
	if _state(ore, layer) != applied:
		return fail("refazer a geração")
	ok("aplicar preserva o que é do autor, suprime o que foi tirado e é um desfazer só; prévia velha é recusada")

	# Regenerar com a mesma regra: o removido não volta e as mesmas sugestões reaparecem no mesmo lugar.
	var again = _plan(ore, base, layer)
	if again.ReplacedCount != 4 or again.Count != 4 or again.SuppressedCount != 1:
		return fail("regenerar: substitui 4, sugere 4 e deixa a removida de fora: %d/%d/%d" % [again.ReplacedCount, again.Count, again.SuppressedCount])
	for i in again.Count:
		if absf(again.Proposal(i).lat - rejected.lat) < 0.5 and absf(again.Proposal(i).lon - rejected.lon) < 0.5:
			return fail("a sugestão removida voltou")
	var centers := _proposals(again)
	# Fixar uma, editar outra (fixa sozinha), excluir uma terceira (supressão).
	var keep: int = made[0].id
	var edited: int = made[1].id
	var gone: int = made[2].id
	r.SetFixed(keep, true)
	r.SetOccurrenceText(edited, "veio do norte", "")
	r.SuppressOccurrence(gone)
	layer.ClearOwner(gone)
	r.DeleteOccurrence(gone)
	var kept_km2: float = layer.AreaKm2(keep)
	var edited_km2: float = layer.AreaKm2(edited)
	var third = _plan(ore, base, layer)
	if third.ReplacedCount != 1 or third.ProtectedCount != 4 or third.Count != 1:
		return fail("fixada, editada e excluída: substitui 1, preserva 4, sugere 1: %d/%d/%d" % [third.ReplacedCount, third.ProtectedCount, third.Count])
	if not centers.has(_proposals(third)[0]):
		return fail("a sugestão que resta deveria ser uma das de antes, no mesmo lugar")
	if r.ApplyGeneration(third, layer).is_empty() or layer.AreaKm2(keep) != kept_km2 or layer.AreaKm2(edited) != edited_km2 or layer.AreaKm2(mine.Id) != mine_km2:
		return fail("regenerar não pode mexer na manual, na fixada nem na editada")
	var ids: Array = r.Occurrences(ore).map(func(o): return o.id)
	for id in [keep, edited, int(mine.Id), int(point.Id)]:
		if not ids.has(id):
			return fail("sumiu uma ocorrência protegida: %d" % id)
	var suppressed_before: int = r.SuppressionCount(ore)
	var freed: Array = r.ClearSuppressions(ore)
	if suppressed_before != 2 or freed.size() != 2 or r.SuppressionCount(ore) != 0 or _plan(ore, base, layer).SuppressedCount != 0:
		return fail("liberar as removidas")
	ok("regenerar: manual, fixada e editada intactas; excluída e tirada não voltam até liberar")

	# Pontos, no mar e em terra, com distância mínima; reabrir conserva a regra.
	var fish: int = r.CreateResourceType("Cardume").Id
	var sea := {"surface": "mar", "elev_min": -200.0, "elev_max": 0.0, "output": "ponto", "count": 10, "size_km": 700.0, "seed": 3}
	var points = _plan(fish, sea, _new_layer())
	if points.Count != 10:
		return fail("10 pontos no mar: %d %s" % [points.Count, points.Error])
	for i in points.Count:
		var a: Dictionary = points.Proposal(i)
		if a.lon >= 0.0:
			return fail("ponto de mar em terra: %s" % [a])
		for k in i:
			var b: Dictionary = points.Proposal(k)
			if EvronGeo.distance_km(EvronGeo.dir(a.lat, a.lon), EvronGeo.dir(b.lat, b.lon)) < 699.0:
				return fail("pontos perto demais")
	if r.ApplyGeneration(points, _new_layer()).is_empty() or r.Occurrences(fish).size() != 10 or r.Occurrences(fish)[0].kind != "ponto":
		return fail("aplicar os pontos")
	var rule: String = r.ResourceRuleOf(fish)
	r.Close()
	r.Open(path)
	if r.ResourceRuleOf(fish) != rule or r.Occurrences(fish).size() != 10:
		return fail("reabrir conserva a regra e as sugestões")
	r.Close()
	ok("pontos no mar com distância mínima; reabrir conserva a regra")
	r.Open(path)
	_test_scores()
	_test_auto()
	_test_cover()
	_test_golden()
	r.Close()
	_test_summary()
	if main != null:
		await _run_scene()


## Com os mapas reais: cada modelo acha lugares; a prévia pela tela, o clique que tira, aplicar e desfazer.
func _run_scene() -> void:
	await frames(5)
	var res = main.resources
	var gen = main.generator
	var reg = main.domains.registry
	var editor = main.territories
	res.set_open(true)
	# Números curtos da prévia e o que as etiquetas dizem de um modelo.
	var short: Array = [200.0, 812400.0, 28009711.0, 15098515221.51].map(func(v): return GeneratorPanel.short_number(v))
	if short != ["200", "812 mil", "28 mi", "15,1 bi"]:
		return fail("números curtos: %s" % [short])
	var soil: Dictionary = GeneratorPanel.TEMPLATES.filter(func(t): return t[0] == "Solo de cultivo")[0][1]
	var chips: Array = Array(GeneratorPanel.describe_rule(res.panel.generator.complete(soil)))
	if chips != ["solo fértil", "quase plano", "até 2.000 m", "clima tropical, temperado ou continental", "2 indícios dão nota"]:
		return fail("etiquetas do Solo de cultivo: %s" % [chips])
	for t in GeneratorPanel.all_templates():
		res.create_type(t[0])
		res.panel.generator.load_rule(t[1])
		var start := Time.get_ticks_msec()
		gen.preview(JSON.stringify(res.panel.generator.rule()))
		if gen.plan == null or gen.plan.Count < mini(5, int(t[1].get("count", 5))):
			return fail("modelo '%s' nos mapas reais: %s (%s)" % [t[0], gen.plan.Count if gen.plan != null else -1, res.panel.generator.summary.text])
		print("modelo %s: %d sugestões, %d km², %d ms" % [t[0], gen.plan.Count, roundi(gen.plan.AcceptedKm2()), Time.get_ticks_msec() - start])
		gen.discard()
	ok("cada modelo acha lugares nos mapas reais")

	res.create_type("Madeira de teste")
	var wood: int = res.type_id
	var forest: Dictionary = GeneratorPanel.TEMPLATES.filter(func(t): return t[0] == "Floresta")[0][1]
	res.panel.generator.load_rule(forest)
	if not res.panel.generator.covers() or res.panel.generator.some_box.visible:
		return fail("o modelo Floresta cobre, sem pedir quantidade nem tamanho")
	res.panel.generator.load_rule({})
	if res.panel.generator.covers() or not res.panel.generator.some_box.visible:
		return fail("sem categoria a tela volta às manchas")
	res.panel.generator.set_category("vegetal")
	if not res.panel.generator.covers():
		return fail("vegetação cobre quando a regra não diz")
	res.panel.generator.load_rule(forest)
	gen.preview(JSON.stringify(res.panel.generator.rule()))
	await frames(3)
	if not gen.plan.Cover:
		return fail("a prévia da Floresta deveria ser cobertura")
	var total: int = gen.plan.Count
	if not editor.previewing or not res.panel.generator.apply_button.visible or reg.Occurrences(wood).size() != 0:
		return fail("a prévia deveria estar na tela sem gravar")
	res.panel.show_tab(res.panel.TAB_SUGGEST)
	gen.preview(JSON.stringify(res.panel.generator.rule()))
	await frames(3)
	if res.panel.generator.form.visible or not res.panel.generator.apply_button.is_visible_in_tree() \
			or res.panel.generator.apply_button.text != "Aplicar %d lugares" % total:
		return fail("na prévia os passos saem e Aplicar fica embaixo: " + res.panel.generator.apply_button.text)
	var first: Dictionary = gen.plan.Proposal(0)
	main.globe.focus(EvronGeo.dir(first.lat, first.lon), 2.4)
	var hit := Vector3.ZERO  # o centro de uma mancha pertence a ela
	hit = EvronGeo.dir(first.lat, first.lon)
	main.select(hit)
	if gen.plan == null or gen.plan.AcceptedCount() != total or not gen.card.visible:
		return fail("o clique deveria explicar a sugestão sem tirá-la")
	if not gen.card.body.text.contains("pelo menos 40% de árvores") or not gen.card.body.text.contains("O que os mapas dizem"):
		return fail("a explicação de um modelo simples: " + gen.card.body.text)
	gen.card.toggle_button.pressed.emit()
	if gen.plan.AcceptedCount() != total - 1 or gen.card.toggle_button.text != "Devolver à prévia":
		return fail("o botão do cartão deveria tirar a sugestão")
	if res.panel.generator.apply_button.text != "Aplicar %d lugares" % (total - 1):
		return fail("o botão acompanha o que foi tirado: " + res.panel.generator.apply_button.text)
	res.panel.generator.visible = true
	await frames(8)
	await save("geracao_previa")
	res.panel.generator.apply_button.pressed.emit()
	await frames(2)
	if res.panel.tab != res.panel.TAB_MAP or not res.panel.message.text.begins_with("Aplicado") or res.panel._footer_slot.visible:
		return fail("aplicar mostra a lista do que entrou: aba %d, '%s'" % [res.panel.tab, res.panel.message.text])
	if editor.previewing or reg.Occurrences(wood).size() != total - 1 or reg.SuppressionCount(wood) != 1:
		return fail("aplicar: %d ocorrências, %d supressões (%s)" % [reg.Occurrences(wood).size(), reg.SuppressionCount(wood), res.panel.generator.summary.text])
	var area: int = int(reg.Occurrences(wood)[0].id)
	res.occurrence_id = area
	res.paint()
	if not editor.painting_territory or not reg.Occurrences(wood)[0].fixed:
		return fail("pintar uma sugestão deveria fixá-la")
	editor.stop_painting()
	res.delete_occurrence()
	if reg.SuppressionCount(wood) != 2:
		return fail("excluir uma sugestão deveria suprimi-la")
	main.undo()
	if reg.SuppressionCount(wood) != 1 or reg.OccurrenceType(area) != wood:
		return fail("um desfazer devolve a ocorrência e tira a supressão")
	gen.preview(JSON.stringify(res.panel.generator.rule()))
	main.undo()
	if gen.plan != null or editor.previewing:
		return fail("desfazer com a prévia aberta deveria descartá-la")
	gen.preview(JSON.stringify(res.panel.generator.rule()))
	res.set_open(false)
	if gen.plan != null or editor.previewing:
		return fail("fechar o painel deveria descartar a prévia")
	while main.commands.can_undo():
		main.undo()
	if reg.ResourceTypes("").size() != 0:
		return fail("desfazer tudo pela pilha do programa")
	ok("cena: prévia, tirar pelo clique, aplicar, fixar ao pintar, suprimir ao excluir e descartar")
	await _run_profiles()


## Adicionar os quatro perfis, gerar todos juntos, aplicar e desfazer num passo; estabilidade e avaliação às cegas pela tela.
func _run_profiles() -> void:
	var res = main.resources
	var gen = main.generator
	var reg = main.domains.registry
	res.set_open(true)
	res.panel.back_requested.emit()
	res.panel.preview_all_requested.emit()
	if gen.active() or not res.panel.all_summary.text.contains("Nenhum recurso tem critérios de geração"):
		return fail("sem regra não há o que gerar")
	for i in ResourceProfiles.PROFILES.size():
		res.panel.profile_requested.emit(i)
	res.panel.profile_requested.emit(0)
	if reg.ResourceTypes("").size() != 4 or not res.panel.message.text.contains("Já existe"):
		return fail("quatro perfis, sem duplicar: %s" % [reg.ResourceTypes("")])
	res.panel.back_requested.emit()
	await frames(2)
	if not res.panel.list_box.visible or res.panel.type_box.visible:
		return fail("voltar mostra a lista")
	await save("menu_lista")
	var start := Time.get_ticks_msec()
	res.panel.preview_all_requested.emit()
	var elapsed := Time.get_ticks_msec() - start
	if gen.plans.size() != 4 or not res.panel.all_actions.visible or reg.Occurrences(0).size() != 0:
		return fail("prévia conjunta dos quatro sem gravar: %d (%s)" % [gen.plans.size(), res.panel.all_summary.text])
	var total := 0
	for entry in gen.plans:
		total += entry.plan.Count
	print("gerar todos: %d sugestões em %d ms" % [total, elapsed])
	if res.panel.browse_box.visible or not res.panel.all_apply_button.is_visible_in_tree() \
			or res.panel.all_apply_button.text != "Aplicar %d lugares" % total:
		return fail("a prévia de todos toma o lugar da lista, com Aplicar embaixo: " + res.panel.all_apply_button.text)
	if not main.territories.previewing or gen.plans.any(func(e): return not e.plan.IsArea or e.plan.AcceptedKm2() <= 0.0):
		return fail("os perfis geram áreas, e a prévia conjunta as pinta")
	var spot: Dictionary = gen.plans[0].plan.Proposal(0)
	main.select(EvronGeo.dir(spot.lat, spot.lon))
	if not gen.card.visible or not gen.card.body.text.contains("pontos (precisa de") or not gen.card.body.text.contains("✓ "):
		return fail("o cartão deveria mostrar a soma e os sinais: " + gen.card.body.text)
	await frames(8)
	await save("por_que_aqui")
	var shown_text: String = gen.card.body.text
	gen.card.toggle_button.pressed.emit()
	var accepted := 0
	for entry in gen.plans:
		accepted += entry.plan.AcceptedCount()
	if accepted != total - 1:
		return fail("o clique deveria tirar uma sugestão da prévia conjunta")
	main.globe.focus(EvronGeo.dir(spot.lat, spot.lon), 3.0)
	await frames(5)
	await save("geracao_todos")
	if res.panel.all_apply_button.text != "Aplicar %d lugares" % (total - 1):
		return fail("o botão de todos acompanha o que foi tirado: " + res.panel.all_apply_button.text)
	res.panel.all_apply_button.pressed.emit()
	if not res.panel.browse_box.visible or res.panel.all_actions.visible or not res.panel.all_summary.text.begins_with("Aplicado"):
		return fail("aplicar todos volta à lista com o aviso: " + res.panel.all_summary.text)
	if reg.Occurrences(0).size() != total - 1:
		return fail("aplicar todos: %d de %d (%s)" % [reg.Occurrences(0).size(), total - 1, res.panel.all_summary.text])
	main.undo()
	if reg.Occurrences(0).size() != 0 or reg.ResourceTypes("").size() != 4:
		return fail("um desfazer tira a geração dos quatro")
	main.redo()
	if reg.Occurrences(0).size() != total - 1:
		return fail("refazer a geração dos quatro")
	for t in reg.ResourceTypes(""):
		var painted = main.territories.layer("recurso:%d" % int(t.id))
		for o in reg.Occurrences(int(t.id)):
			if o.kind != "area" or painted.AreaKm2(int(o.id)) <= 0.0:
				return fail("depois de aplicar, cada sugestão é um território pintado: %s %s" % [t.name, o])
	ok("cena: perfis, gerar todos, tirar pelo clique, aplicar e desfazer num passo")
	if gen.card.visible:
		return fail("aplicar deveria fechar o cartão")
	var applied: Dictionary = reg.Occurrences(0)[0]
	res.panel.type_chosen.emit(int(applied.type_id))
	res.panel.occurrence_chosen.emit(int(applied.id))
	if not res.panel.why_button.visible:
		return fail("uma sugestão aplicada tem o botão Por que aqui?")
	res.panel.why_button.pressed.emit()
	if not gen.card.visible or gen.card.toggle_button.visible or not gen.card.body.text.contains("pontos (precisa de"):
		return fail("a explicação de uma sugestão aplicada: " + gen.card.body.text)
	var note: String = applied.note  # "Aptidão N: indícios." tem de bater com o cartão
	var points := note.get_slice(":", 0).get_slice(" ", 1)
	if not gen.card.body.text.begins_with("Somou %s pontos" % points):
		return fail("o cartão e a anotação deveriam concordar: %s / %s" % [note, gen.card.body.text])
	print(shown_text)

	var salt: int = int(reg.ResourceTypes("Sal")[0].id)
	res.panel.type_chosen.emit(salt)
	await frames(2)
	if res.panel.tab != res.panel.TAB_MAP or res.panel.list_box.visible or res.panel.title.text != "SAL" or res.panel.generator.is_visible_in_tree():
		return fail("abrir um recurso mostra a aba No mapa")
	res.panel.occurrence_chosen.emit(int(reg.Occurrences(salt)[0].id))
	await frames(5)
	await save("menu_no_mapa")
	res.panel.show_tab(res.panel.TAB_EDIT)
	await frames(3)
	if not res.panel.delete_type_button.disabled:
		return fail("um recurso que está no mapa não oferece a exclusão")
	await save("menu_editar")
	res.panel.show_tab(res.panel.TAB_SUGGEST)
	await frames(3)
	if res.panel.generator.advanced_toggle.button_pressed or res.panel.generator.rocks.values()[0].is_visible_in_tree():
		return fail("os ajustes avançados começam fechados")
	await save("menu_sugerir")
	gen.preview(JSON.stringify(res.panel.generator.rule()))
	res.panel.show_tab(res.panel.TAB_MAP)
	if gen.active() or main.territories.previewing:
		return fail("sair da aba Sugerir fecha a prévia")
	res.panel.show_tab(res.panel.TAB_SUGGEST)
	var rule: String = JSON.stringify(res.panel.generator.rule())
	if JSON.parse_string(rule).prefer.size() != 4 or JSON.parse_string(rule).min_score != 60:
		return fail("o formulário deveria mostrar os indícios do perfil: " + rule)
	start = Time.get_ticks_msec()
	res.panel.generator.stability_requested.emit(rule)
	print("estabilidade em %d ms: %s" % [Time.get_ticks_msec() - start, res.panel.generator.result.text])
	if not res.panel.generator.result.text.contains("num sorteio"):
		return fail("o resultado da estabilidade: " + res.panel.generator.result.text)
	for t in ResourceProfiles.PROFILES:
		var s: Dictionary = reg.RuleStability(JSON.stringify(res.panel.generator.complete(t.rule)), gen.terrain,
			gen.maps_for(Array(reg.RuleMaps(JSON.stringify(res.panel.generator.complete(t.rule))))), 500.0)
		print("perfil %s: área igual %d%%, outra semente %d%%, sorteio %d%%" % [t.name, roundi(100 * s.area_overlap),
			roundi(100 * s.seed_agreement), roundi(100 * s.random_agreement)])

	var review = gen.review
	review.save_path = out_dir.path_join("avaliacao-%d.csv" % Time.get_ticks_usec())
	var count_before: int = reg.Occurrences(0).size()
	res.panel.generator.review_requested.emit(rule)
	if not review.active() or review.items.size() < 20 or review.items.filter(func(i): return i.rule).size() * 2 != review.items.size():
		return fail("a avaliação mistura metade da regra e metade de sorteio: %d" % review.items.size())
	if res.panel.generator.review_question.text.contains("regra") or not res.panel.generator.review_facts.text.contains("Altitude"):
		return fail("a pergunta não pode revelar a origem: " + res.panel.generator.review_question.text)
	if gen.card.visible:
		return fail("a avaliação às cegas não pode mostrar o cartão")
	if main.globe.resources.label_count != 1 or editor_is_resource():
		return fail("na avaliação só o lugar julgado aparece: %d nomes" % main.globe.resources.label_count)
	await frames(5)
	await save("avaliacao_cegas")
	var answered: int = review.items.size()
	var truth: Array = review.items.map(func(i): return i.rule)
	start = Time.get_ticks_msec()
	for i in answered:
		res.panel.generator.review_answered.emit("sim" if truth[i] else "nao")
	var per_answer: int = (Time.get_ticks_msec() - start) / answered
	print("avaliação: %d ms por resposta" % per_answer)
	if per_answer > 700:
		return fail("cada resposta da avaliação está lenta demais: %d ms" % per_answer)
	if review.active() or not res.panel.generator.result.text.contains("ganhou do sorteio") or reg.Occurrences(0).size() != count_before:
		return fail("o fim da avaliação mostra o resultado sem mudar o mundo: " + res.panel.generator.result.text)
	var lines := FileAccess.get_file_as_string(review.save_path).strip_edges().split("\n")
	if lines.size() != answered + 1:
		return fail("o arquivo guarda uma linha por resposta: %d de %d" % [lines.size() - 1, answered])
	# A avaliação virou gabarito: o botão compara a regra da tela, e toda prévia já vem testada.
	res.panel.generator.golden_requested.emit(rule, false)
	var same: String = res.panel.generator.result.text
	if not same.begins_with("Gabarito:") or not same.contains("mesma regra"):
		return fail("a regra avaliada contra o próprio gabarito: " + same)
	var strict: Dictionary = JSON.parse_string(rule)
	strict.min_score = 100
	res.panel.generator.golden_requested.emit(JSON.stringify(strict), false)
	if not res.panel.generator.result.text.contains("em relação à regra avaliada"):
		return fail("uma regra mudada é comparada com a avaliada: " + res.panel.generator.result.text)
	print(res.panel.generator.result.text)
	res.panel.generator.golden_requested.emit(rule, true)
	if not res.panel.generator.result.text.begins_with("Teste final"):
		return fail("o teste final usa a parte reservada: " + res.panel.generator.result.text)
	gen.preview(rule)
	if gen.plan == null or not res.panel.generator.result.text.begins_with("Gabarito:"):
		return fail("a prévia deveria vir com o gabarito: " + res.panel.generator.result.text)
	gen.discard()
	res.set_open(false)
	while main.commands.can_undo():
		main.undo()
	if reg.ResourceTypes("").size() != 0:
		return fail("desfazer tudo")
	ok("cena: estabilidade e avaliação às cegas, sem mudar o mundo")


## Indícios: a aptidão é a soma dos pesos, o mínimo corta, o motivo é gravado, e a regra sem indícios dá o resultado de antes.
func _test_scores() -> void:
	var type: int = r.CreateResourceType("Estanho de teste").Id
	var north := {"name": "Granito", "rocks": ["granito"], "weight": 70}
	var south := {"name": "Arenito", "rocks": ["arenito"], "weight": 30}
	var land := {"name": "Terra qualquer rocha", "rocks": ["granito", "arenito"], "weight": 20}
	var rule := {"output": "ponto", "count": 12, "size_km": 500.0, "seed": 5, "prefer": [north, south, land], "min_score": 60}
	var plan = _plan(type, rule, _new_layer())
	if plan.Error != "" or plan.Count != 12 or not plan.Scored:
		return fail("regra com indícios: %s (%d)" % [plan.Error, plan.Count])
	for i in plan.Count:
		var p: Dictionary = plan.Proposal(i)
		if p.score != 90 or p.why != "Granito; Terra qualquer rocha" or p.lat <= 0.0:
			return fail("com mínimo 60 só o granito (90) passa: %s" % [p])
	rule.min_score = 1
	var mixed = _plan(type, rule, _new_layer())
	var good := 0
	for i in mixed.Count:
		good += 1 if mixed.Proposal(i).score == 90 else 0
	if good <= mixed.Count - good:
		return fail("aptidão alta deveria concorrer mais: %d de %d" % [good, mixed.Count])
	var plain := {"output": "ponto", "count": 8, "size_km": 500.0, "seed": 5}
	var flat := plain.duplicate()
	flat["prefer"] = [{"name": "Tudo", "weight": 100}]
	if _proposals(_plan(type, plain, _new_layer())) != _proposals(_plan(type, flat, _new_layer())):
		return fail("um indício que vale em todo lugar com peso 100 deveria dar o mesmo que nenhum")
	rule.min_score = 60
	if r.ApplyGeneration(_plan(type, rule, _new_layer()), _new_layer()).is_empty():
		return fail("aplicar a regra com indícios")
	if r.Occurrences(type)[0].note != "Aptidão 90: Granito; Terra qualquer rocha." or r.Occurrences(type)[0].fixed:
		return fail("o motivo vai para a anotação sem fixar: %s" % [r.Occurrences(type)[0]])
	for bad in [{"prefer": [{"name": "", "weight": 5}]}, {"prefer": [{"name": "x", "weight": 0}]}, {"prefer": [{"name": "x", "volcanoes": ["lua"]}]},
			{"prefer": [north], "min_score": 101}, {"surface": "mar", "prefer": [north]}]:
		if r.CheckResourceRule(JSON.stringify(bad)) == "":
			return fail("indício inválido aceito: %s" % [bad])
	ok("aptidão: soma dos pesos, mínimo, motivo na anotação e indícios inválidos recusados")

	var s: Dictionary = r.RuleStability(JSON.stringify(rule), terrain, maps, 500.0)
	if s.area_overlap < 0.0 or s.area_overlap > 1.0 or s.seed_agreement < 0.0 or s.seed_agreement > 1.0 or s.count != 12:
		return fail("estabilidade fora da faixa: %s" % [s])
	var cliff := {"prefer": [north], "min_score": 70}  # com o peso 10% menor nada passa: o teste tem de acusar
	if r.RuleStability(JSON.stringify(cliff), terrain, maps, 500.0).area_overlap != 0.0:
		return fail("uma regra no limite do mínimo deveria sair como frágil")
	if r.RuleStability(JSON.stringify(plain), terrain, maps, 500.0).area_overlap != 1.0:
		return fail("sem limites nem pesos, ±10% não muda nada")
	if r.RandomSites("mar", 1, 30, terrain).size() != 30 or r.RandomSites("mar", 1, 30, terrain).any(func(p): return p.lon >= 0.0):
		return fail("os sorteios do mar ficam no mar")
	if not r.PlaceFacts(terrain, maps, 40.0, 90.0).contains("Rocha: Granito"):
		return fail("os fatos do lugar: %s" % r.PlaceFacts(terrain, maps, 40.0, 90.0))
	ok("estabilidade acusa regra frágil; sorteios na superfície certa; fatos do lugar")


## O gabarito: a última resposta vale, "não sei" sai, um terço fica reservado e a regra é medida contra o julgamento.
func _test_golden() -> void:
	var file_path := out_dir.path_join("gabarito-%d.csv" % Time.get_ticks_usec())
	var granite := JSON.stringify({"rocks": ["granito"]})
	var anywhere := JSON.stringify({})
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_csv_line(PackedStringArray(["data", "recurso", "regra", "lat", "lon", "origem", "resposta"]))
	var add := func(resource: String, rule: String, lat: float, lon: float, answer: String) -> void:
		file.store_csv_line(PackedStringArray(["agora", resource, rule, "%.3f" % lat, "%.3f" % lon, "regra", answer]))
	for i in 30:  # o autor aprova o norte (granito) e rejeita o sul (arenito), ambos em terra
		add.call("Estanho", granite, 20.0 + i, 40.0 + i, "sim")
		add.call("Estanho", granite, -20.0 - i, 40.0 + i, "nao")
	add.call("Estanho", granite, 20.0, 40.0, "nao")      # mudou de ideia sobre o primeiro aprovado
	add.call("Estanho", granite, -21.0, 41.0, "talvez")  # e ficou em dúvida sobre um rejeitado
	add.call("Cobre", anywhere, 1.0, 1.0, "sim")
	file.close()

	var golden: Dictionary = GoldenSet.load_set(file_path, "estanho")
	var reserved: Array = golden.places.filter(func(p): return p.reserved)
	var open: Array = golden.places.filter(func(p): return not p.reserved)
	if golden.places.size() != 59 or golden.rule != granite or reserved.is_empty() or open.size() <= reserved.size():
		return fail("59 lugares, parte reservada menor que a aberta: %d (%d/%d)" % [golden.places.size(), open.size(), reserved.size()])
	if var_to_str(GoldenSet.load_set(file_path, "estanho")) != var_to_str(golden):
		return fail("a parte reservada tem de ser sempre a mesma")
	if GoldenSet.load_set(file_path, "Ferro").rule != "" or GoldenSet.load_set(file_path + ".nao-existe", "Estanho").rule != "":
		return fail("sem respostas não há gabarito")

	var measure := func(rule: String) -> Dictionary:
		var flat := PackedFloat64Array()
		for p in open:
			flat.append_array([p.lat, p.lon])
		return GoldenSet.measure(open, r.ScorePlaces(rule, terrain, maps, flat))
	var good: Dictionary = measure.call(granite)
	var all: Dictionary = measure.call(anywhere)
	# O lugar de que o autor mudou de ideia fica no granito: a regra o aceita, e isso conta como um erro (se ele estiver na parte aberta).
	if good.yes != good.yes_total or good.no < good.no_total - 1 or absf(all.agreement - 0.5) > 0.001:
		return fail("a regra certa concorda quase em tudo; aceitar tudo vale 50%%: %s / %s" % [good, all])
	if not GoldenSet.report(good, all, false, false).contains("Melhorou") or not GoldenSet.report(all, good, false, false).contains("Piorou"):
		return fail("o relatório diz se melhorou ou piorou")
	if not GoldenSet.report(good, good, true, true).begins_with("Teste final") or not GoldenSet.report(good, good, true, false).contains("mesma regra"):
		return fail("relatório da mesma regra e do teste final")
	if not GoldenSet.report(GoldenSet.measure(open.slice(0, 3), PackedInt32Array([1, 1, 1])), all, false, false).contains("poucas respostas"):
		return fail("com poucas respostas não compara")
	ok("gabarito: última resposta vale, terço reservado estável, aceitar tudo vale 50% e melhora ou piora")


## Automático: cabem mais manchas, cada uma do tamanho do lugar, e cada uma traz a quantidade (área × densidade × aptidão).
func _test_auto() -> void:
	var type: int = r.CreateResourceType("Granito automático").Id
	var manual := {"rocks": ["granito"], "output": "area", "count": 6, "size_km": 600.0, "seed": 7}
	var auto := manual.duplicate()
	auto.merge({"auto": true, "density": 10.0})
	var few = _plan(type, manual, _new_layer())
	var many = _plan(type, auto, _new_layer())
	if many.Error != "" or many.Count <= few.Count or many.AcceptedKm2() <= few.AcceptedKm2():
		return fail("o automático deveria pôr mais manchas e cobrir mais: %d/%d" % [many.Count, few.Count])
	for i in many.Count:
		var p: Dictionary = many.Proposal(i)
		if p.km2 < 500.0 or absf(p.reserve - p.km2 * 10.0) > 1e-6 * p.km2:
			return fail("mancha pequena demais ou quantidade errada: %s" % [p])
	if _plan(type, manual, _new_layer()).Proposal(0).reserve != 0.0:
		return fail("sem densidade, sem quantidade")
	var layer := _new_layer()
	r.ApplyGeneration(many, layer)
	var first: Dictionary = r.Occurrences(type)[0]
	if absf(r.OccurrenceReserve(int(first.id)).reserve - layer.AreaKm2(int(first.id)) * 10.0) > 1.0:
		return fail("aplicar grava a quantidade de cada mancha: %s" % [r.OccurrenceReserve(int(first.id))])
	ok("automático: %d manchas (manual: %d), cada uma do tamanho do lugar e com quantidade" % [many.Count, few.Count])


## Cobertura: um trecho contínuo por sugestão, sem raio nem sorteio; vegetação e animal cobrem quando a regra não diz.
func _test_cover() -> void:
	var rock := Image.create(W, H, false, Image.FORMAT_RGB8)
	rock.fill(SANDSTONE)
	rock.fill_rect(Rect2i(300, 60, 90, 50), GRANITE)   # o trecho grande
	rock.fill_rect(Rect2i(430, 140, 30, 20), GRANITE)  # o menor
	rock.set_pixel(350, 12, GRANITE)                   # um pixel perto do polo: menos de 5.000 km²
	var before: Dictionary = maps
	maps = {"Bedrock.png": rock}
	var made = r.CreateResourceType("Mata")
	var type: int = made.Id
	var rule := {"rocks": ["intrusiva"], "output": "area", "count": 3, "size_km": 100.0, "seed": 1, "density": 10.0}
	var json := JSON.stringify(rule)
	if r.CoversArea(type, json) or _plan(type, rule, _new_layer()).Cover:
		return fail("sem categoria, o normal são manchas")
	r.SetResourceType(type, "Mata", "", "animal", "", 0x00ff00)
	if not r.CoversArea(type, json):
		return fail("animal cobre quando a regra não diz")
	r.SetResourceType(type, "Mata", "", "vegetal", "", 0x00ff00)
	var layer := _new_layer()
	var plan = _plan(type, rule, layer)
	if plan.Error != "" or not plan.Cover or plan.Count != 2:
		return fail("cobertura: dois trechos, o pontinho fica de fora (%s, %d)" % [plan.Error, plan.Count])
	var big: Dictionary = plan.Proposal(0)
	var small: Dictionary = plan.Proposal(1)
	if big.km2 <= small.km2 or small.km2 < 5000.0 or absf(big.reserve - big.km2 * 10.0) > 1e-6 * big.km2:
		return fail("o maior primeiro, com a quantidade do trecho inteiro: %s %s" % [big, small])
	var other := rule.duplicate()
	other.merge({"seed": 99, "size_km": 2000.0, "count": 1}, true)
	if _proposals(plan) != _proposals(_plan(type, other, layer)) or _plan(type, other, layer).AcceptedKm2() != plan.AcceptedKm2():
		return fail("semente, raio e quantidade não mudam a cobertura")
	var patchy := rule.duplicate()
	patchy.spread = "manchas"
	var points := rule.duplicate()
	points.output = "ponto"
	if _plan(type, patchy, layer).Cover or _plan(type, patchy, layer).AcceptedKm2() >= plan.AcceptedKm2() or _plan(type, points, layer).Cover:
		return fail("pedir manchas ou pontos vale mais que a categoria")
	if r.CheckResourceRule('{"spread": "tudo"}') == "":
		return fail("jeito desconhecido de se espalhar é recusado")
	plan.Toggle(1)
	if r.ApplyGeneration(plan, layer).is_empty() or r.Occurrences(type).size() != 1 or absf(layer.AreaKm2(int(r.Occurrences(type)[0].id)) - big.km2) > 1.0:
		return fail("aplicar pinta o trecho inteiro: %s" % [r.Occurrences(type)])
	if r.ResourceRuleOf(type).contains('"spread":"cobertura"'):
		return fail("a regra do recurso continua valendo pela categoria: " + r.ResourceRuleOf(type))
	var again = _plan(type, rule, layer)
	if again.Count != 1 or again.SuppressedCount != 1 or again.ReplacedCount != 1 or _proposals(again)[0] != _proposals(plan)[0]:
		return fail("o trecho tirado não volta e o outro se repete: %d, %d fora" % [again.Count, again.SuppressedCount])
	r.SetResourceType(type, "Mata", "", "mineral", "", 0x00ff00)
	if _plan(type, rule, _new_layer()).Cover:
		return fail("mineral continua em manchas")
	maps = before
	ok("cobertura: segue o contorno, ignora semente e raio, vale para vegetação e animal, e tirar um trecho não derruba o outro")


func _test_summary() -> void:
	var make := func(rule_yes: int, random_yes: int, n: int) -> String:
		var answers: Array = []
		for i in n:
			answers.append({"rule": true, "answer": "sim" if i < rule_yes else "nao"})
			answers.append({"rule": false, "answer": "sim" if i < random_yes else "nao"})
		answers.append({"rule": true, "answer": "talvez"})
		return BlindReview.summary(answers)
	if not make.call(18, 4, 20).contains("ganhou do sorteio com folga") or not make.call(18, 4, 20).contains("regra 18 de 20, sorteio 4 de 20"):
		return fail("diferença grande: %s" % make.call(18, 4, 20))
	if not make.call(11, 9, 20).contains("Não dá para afirmar") or not make.call(3, 18, 20).contains("revise a regra"):
		return fail("diferença pequena ou negativa")
	if not make.call(4, 0, 4).contains("Poucas respostas"):
		return fail("poucas respostas não concluem")
	ok("resumo da avaliação: folga, sem conclusão, sorteio melhor e poucas respostas")


func editor_is_resource() -> bool:
	return main.territories.is_resource(main.territories.territory_level)


func _new_layer() -> Territory:
	var t := Territory.new()
	t.Setup(terrain)
	return t


func _plan(type: int, rule: Dictionary, layer: Territory):
	return r.PlanResources(type, JSON.stringify(rule), terrain, layer, maps)


func _proposals(plan) -> Array:
	var out: Array = []
	for i in plan.Count:
		var p: Dictionary = plan.Proposal(i)
		out.append("%.4f %.4f" % [p.lat, p.lon])
	return out


## As ocorrências e o tamanho pintado de cada uma.
func _state(type: int, layer: Territory) -> String:
	return var_to_str(r.Occurrences(type).map(func(o): return [o, layer.AreaKm2(int(o.id))]))
