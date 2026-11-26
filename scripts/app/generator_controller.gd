extends RefCounted
## Gerar sugestões: pede a prévia ao Registry (de um recurso ou de todos os que têm regra), mostra no mapa, deixa tirar sugestões
## com um clique e aplica tudo num comando só. Nada muda no mundo antes de Aplicar. Quem decide o que é substituído é o Registry
## (só geradas não fixadas). Também roda o teste de estabilidade; a avaliação às cegas é de blind_review.gd.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")
const ResourceProfiles = preload("res://scripts/ui/resource_profiles.gd")
const BlindReview = preload("res://scripts/app/blind_review.gd")
const GoldenSet = preload("res://scripts/app/golden_set.gd")
const ResourcePlanScript = preload("res://scripts/world/ResourcePlan.cs")
const STABILITY_NEAR_KM := 500.0

var resources            # o resource_controller: o recurso escolhido, a camada dele, a pilha e a tela
var panel                # GeneratorPanel
var card = null          # o cartão "Por que aqui?" (why_card.gd), se ligado
var _explained := {}     # a sugestão da prévia no cartão: {entry, index}
var terrain
var review := BlindReview.new()
var plans: Array = []    # a prévia na tela: [{type, name, rgb, plan}]
var load_map := Callable(EvronMaps, "load_layer")  # os testes trocam por mapas sintéticos
var _all := false        # a prévia é de todos os recursos
var _loaded_type := -1

## A prévia de um recurso só (null se não há, ou se é a de todos).
var plan:
	get:
		return plans[0].plan if plans.size() == 1 and not _all else null


func setup(resource_controller, generator_panel, world_terrain) -> void:
	resources = resource_controller
	panel = generator_panel
	terrain = world_terrain
	resources.generator = self
	review.setup(self, panel)
	panel.preview_requested.connect(preview)
	panel.apply_requested.connect(apply)
	panel.discard_requested.connect(discard)
	panel.clear_requested.connect(clear_suppressions)
	panel.stability_requested.connect(stability)
	panel.golden_requested.connect(func(rule: String, final_test: bool) -> void:
		var text := compare(resources.type_id, rule, final_test)
		panel.show_review_result(text if text != "" else "Ainda não há gabarito deste recurso: faça uma avaliação às cegas."))
	resources.panel.profile_requested.connect(add_profile)
	resources.panel.preview_all_requested.connect(preview_all)
	resources.panel.apply_all_requested.connect(apply)
	resources.panel.discard_all_requested.connect(discard)
	resources.panel.why_requested.connect(func() -> void: explain_occurrence(resources.occurrence_id))
	resources.panel.occurrence_chosen.connect(func(_id: int) -> void: hide_why())
	resources.commands.changed.connect(discard)  # desfazer, pintar ou editar muda o mundo: a prévia deixa de valer
	resources.territories.territory_level_shown.connect(func(_level: String, _layer) -> void: discard())
	resources.territories.painting_changed.connect(func(on: bool) -> void:
		if on:
			close())


func active() -> bool:
	return not plans.is_empty()


## Fecha a prévia e a avaliação (o painel fechou, ou a pintura começou).
func close() -> void:
	hide_why()
	discard()
	review.cancel()


## Ao escolher outro recurso, o formulário passa a mostrar a regra gravada nele.
func show_type(type_id: int) -> void:
	if type_id != _loaded_type:
		review.cancel()
	if type_id == 0:
		_loaded_type = -1
		return
	for t in resources.hub.registry.ResourceTypes(""):
		if int(t.id) == type_id:
			panel.set_category(String(t.category))
	if type_id != _loaded_type:
		_loaded_type = type_id
		var saved: String = resources.hub.registry.ResourceRuleOf(type_id)
		panel.load_rule(JSON.parse_string(saved) if saved != "" else {})
		panel.show_review_result("")
	panel.show_suppressions(resources.hub.registry.SuppressionCount(type_id))
	if plan == null and resources.hub.registry.GenerationStale(type_id, terrain):
		panel.show_preview("O relevo mudou depois da última sugestão aplicada: ela pode estar desatualizada. Peça a prévia de novo para refazê-la (o que é seu continua).")


## Cria o recurso de um perfil, já com a regra, num desfazer só. Um recurso com o mesmo nome não é alterado.
func add_profile(index: int) -> void:
	var profile: Dictionary = ResourceProfiles.PROFILES[index]
	for t in resources.hub.registry.ResourceTypes(""):
		if t.name.to_lower() == profile.name.to_lower():
			resources.panel.show_message("Já existe um recurso chamado %s; ele não foi alterado." % t.name)
			return
	close()
	resources.leave_painting()
	var created = resources.hub.registry.CreateResourceType(profile.name)
	if created == null:
		return
	var ruled = resources.hub.registry.SetResourceRule(created.Id, JSON.stringify(panel.complete(profile.rule)))
	if ruled == null:
		created.Undo()
		resources.panel.show_message("A regra do perfil não foi aceita (veja o log).")
		return
	var t: Dictionary = resources.hub.registry.ResourceTypes("").filter(func(x): return int(x.id) == int(created.Id))[0]
	var labeled = resources.hub.registry.SetResourceType(created.Id, profile.name, "", profile.get("category", ""), profile.get("unit", ""), int(t.rgb))
	resources.type_id = created.Id
	resources.occurrence_id = 0
	_loaded_type = -1
	resources.push_batch("adicionar perfil %s" % profile.name, [created, ruled] + ([labeled] if labeled != null else []))
	resources.show_map()
	resources.panel.show_tab(resources.panel.TAB_SUGGEST)  # um modelo pronto já abre onde se pede a prévia


## Os mapas pedidos, em RGB8; {} (com aviso) se falta algum.
func maps_for(files: Array, cache := {}) -> Dictionary:
	var out := {}
	for file in files:
		if not cache.has(file):
			var image = load_map.call(file)
			if image == null:
				panel.show_preview("Falta o mapa %s em data/evron (rode tools/import_maps.py)." % file)
				return {}
			image.convert(Image.FORMAT_RGB8)
			cache[file] = image
		out[file] = cache[file]
	return out


## A regra testada nos lugares que o autor julgou, ao lado da regra que ele avaliou. "" = não há gabarito deste recurso.
func compare(type_id: int, rule: String, final_test := false) -> String:
	var resource_name := ""
	for t in resources.hub.registry.ResourceTypes(""):
		if int(t.id) == type_id:
			resource_name = t.name
	var golden: Dictionary = GoldenSet.load_set(review.save_path, resource_name)
	if golden.rule == "":
		return ""
	var places: Array = golden.places.filter(func(p): return p.reserved == final_test)
	var why: String = resources.hub.registry.CheckResourceRule(rule)
	if why != "":
		return "A regra não vale: %s." % why
	var flat := PackedFloat64Array()
	for p in places:
		flat.append_array([p.lat, p.lon])
	var cache := {}
	var results: Array = []
	for text in [rule, golden.rule]:
		var needed: Array = Array(resources.hub.registry.RuleMaps(text))
		var maps := maps_for(needed, cache)
		if maps.size() != needed.size():
			return "Falta um mapa para comparar."
		var scores = resources.hub.registry.ScorePlaces(text, terrain, maps, flat)
		if scores == null:
			return "Não deu para comparar (veja o log)."
		results.append(GoldenSet.measure(places, scores))
	return GoldenSet.report(results[0], results[1], _same_rule(rule, golden.rule), final_test)


## As duas regras escolhem os mesmos lugares? Quantidade, tamanho, semente e saída não mudam o que é apto.
func _same_rule(a: String, b: String) -> bool:
	var parts: Array = []
	for text in [a, b]:
		var r: Dictionary = panel.complete(JSON.parse_string(text))
		for key in ["output", "count", "size_km", "seed", "spread"]:
			r.erase(key)
		parts.append(JSON.stringify(JSON.parse_string(JSON.stringify(r)), "", true))
	return parts[0] == parts[1]


## A prévia de uma regra para um recurso, sem mostrar; null (com aviso) se não deu.
func make_plan(type_id: int, rule: String, cache := {}):
	var layer = resources.territories.layer(resources.TerritoryEditor.RESOURCE + str(type_id))
	if layer == null:
		return null
	var needed: Array = Array(resources.hub.registry.RuleMaps(rule))
	var maps := maps_for(needed, cache)
	if maps.size() != needed.size():
		return null
	var made = resources.hub.registry.PlanResources(type_id, rule, terrain, layer, maps)
	if made == null or made.Error != "":
		panel.show_preview("Não deu para gerar: %s." % (made.Error if made != null else "veja o log"))
		return null
	return made


func preview(rule: String) -> void:
	if resources.type_id == 0:
		return
	_prepare()
	resources.show_map()
	var made = make_plan(resources.type_id, rule)
	if made == null:
		return
	plans = [_entry(resources.type_id, made)]
	_all = false
	_show()
	panel.show_review_result(compare(resources.type_id, rule))  # com gabarito, toda prévia já vem testada


## A prévia de todos os recursos que têm regra gravada, juntos.
func preview_all() -> void:
	_prepare()
	var cache := {}
	var found: Array = []
	var failed: Array[String] = []
	for t in resources.hub.registry.ResourceTypes(""):
		var rule: String = resources.hub.registry.ResourceRuleOf(int(t.id))
		if rule == "":
			continue
		var made = make_plan(int(t.id), rule, cache)
		if made == null:
			failed.append(t.name)
		else:
			found.append(_entry(int(t.id), made))
	if not failed.is_empty():
		resources.panel.show_all("Não deu para gerar: %s. Nada foi mudado." % ", ".join(failed))
		return
	if found.is_empty():
		resources.panel.show_all("Nenhum recurso tem regra de sugestão ainda. Crie um por um modelo pronto, ou aplique uma sugestão num recurso.")
		return
	plans = found
	_all = true
	_show()


func discard() -> void:
	hide_why()
	if plans.is_empty():
		return
	plans = []
	_all = false
	panel.show_preview("")
	resources.panel.show_all("")
	resources.territories.end_preview()
	resources.refresh()


## Aplica a prévia inteira num desfazer só. Ou entra tudo, ou nada.
func apply() -> void:
	if plans.is_empty():
		return
	var current := plans.duplicate()
	var all := _all
	discard()
	var steps: Array = []
	for entry in current:
		var layer = resources.territories.layer(resources.TerritoryEditor.RESOURCE + str(entry.type))
		var cmds: Array = resources.hub.registry.ApplyGeneration(entry.plan, layer)
		if cmds.is_empty():
			for i in range(steps.size() - 1, -1, -1):
				steps[i].Undo()
			_say(all, "O mundo mudou desde a prévia. Peça a prévia de novo.")
			return
		steps.append_array(cmds)
	resources.push_batch("gerar todos os recursos" if all else "gerar sugestões", steps)
	_say(all, "Aplicado. Ctrl+Z desfaz a geração inteira.")


func clear_suppressions() -> void:
	if resources.type_id == 0:
		return
	var cmds: Array = resources.hub.registry.ClearSuppressions(resources.type_id)
	if not cmds.is_empty():
		resources.push_batch("liberar sugestões removidas", cmds)


## shortcut: roda no quadro principal (alguns segundos nos mapas reais); levar para uma thread se incomodar.
func stability(rule: String) -> void:
	var why: String = resources.hub.registry.CheckResourceRule(rule)
	if why != "":
		panel.show_review_result("A regra não vale: %s." % why)
		return
	var needed: Array = Array(resources.hub.registry.RuleMaps(rule))
	var maps := maps_for(needed)
	if maps.size() != needed.size():
		return
	var s: Dictionary = resources.hub.registry.RuleStability(rule, terrain, maps, STABILITY_NEAR_KM)
	s["cover"] = resources.hub.registry.CoversArea(resources.type_id, rule)
	panel.show_review_result(stability_text(s))


## Os cortes (60% e o dobro do sorteio) são escolhas de projeto, só para chamar atenção.
static func stability_text(s: Dictionary) -> String:
	var overlap := roundi(100 * float(s.area_overlap))
	var seeds := roundi(100 * float(s.seed_agreement))
	var chance := roundi(100 * float(s.random_agreement))
	var verdict := "A regra aguenta pequenas mudanças." if overlap >= 60 else "Regra frágil: uma mudança de 10% altera muito os lugares aptos."
	if s.get("cover", false):  # sem sorteio: não há semente para comparar
		return "Lugares aptos com limites e pesos em ±10%%: ao menos %d%% iguais. %s\nNa cobertura não há sorteio: a mesma regra pinta sempre os mesmos lugares." % [overlap, verdict]
	var places := "As regiões se repetem mais que num sorteio." if seeds >= 2 * chance else "Com outra semente, as regiões se repetem pouco mais que num sorteio."
	return "Lugares aptos com limites e pesos em ±10%%: ao menos %d%% iguais. %s\nOutra semente: %d%% das sugestões têm uma a até %d km (num sorteio: %d%%). %s" % [
		overlap, verdict, seeds, roundi(STABILITY_NEAR_KM), chance, places]


## Um clique no globo durante a prévia tira ou devolve a sugestão sob ele. false = não havia sugestão ali.
func click(n: Vector3, tolerance_km: float) -> bool:
	var best := tolerance_km
	var found = null
	var at := -1
	for entry in plans:
		var made = entry.plan
		if made.IsArea:
			var inside: int = made.IndexAtPixel(terrain.PixelOf(n))
			if inside >= 0:
				found = made
				at = inside
				break
		for i in made.Count:
			var p: Dictionary = made.Proposal(i)
			var km: float = EvronGeo.distance_km(n, EvronGeo.dir(p.lat, p.lon))
			if km <= best:
				best = km
				found = made
				at = i
	if found == null:
		return false
	for entry in plans:
		if entry.plan == found:
			_explained = {"entry": entry, "index": at}
	_show_why()
	return true


## O botão do cartão: tira a sugestão explicada da prévia, ou a devolve.
func toggle_explained() -> void:
	if _explained.is_empty() or not active():
		return
	var kept := _explained.duplicate()
	kept.entry.plan.Toggle(kept.index)
	_show()
	_explained = kept
	_show_why()


## "Por que aqui?" de uma sugestão já aplicada: a regra que a gerou, no lugar em que ela foi sugerida.
func explain_occurrence(occurrence_id: int) -> void:
	if card == null or review.active():
		return
	var registry = resources.hub.registry
	var needed: Array = Array(registry.ExplanationMaps(occurrence_id))
	var cache := {}
	var maps := maps_for(needed, cache)
	if maps.size() != needed.size():
		return
	var why = registry.ExplainOccurrence(occurrence_id, terrain, maps)
	if why == null or why.is_empty():
		resources.panel.show_message("Esta ocorrência não veio da geração: não há o que explicar.")
		return
	_explained = {}
	card.show_why("Por que aqui? %s" % registry.OccurrenceLabel(occurrence_id), why, _facts(why.lat, why.lon, cache))


func hide_why() -> void:
	_explained = {}
	if card != null:
		card.hide()


func _show_why() -> void:
	if card == null or _explained.is_empty():
		return
	var entry: Dictionary = _explained.entry
	var i: int = _explained.index
	var p: Dictionary = entry.plan.Proposal(i)
	var heading := "Por que aqui? %s, sugestão %d%s" % [entry.name, i + 1, " (fora da prévia)" if p.rejected else ""]
	card.show_why(heading, entry.plan.Explain(i), _facts(p.lat, p.lon, {}), "Devolver à prévia" if p.rejected else "Tirar da prévia")


## O que os mapas dizem do ponto; "" se falta algum mapa (a explicação da regra vale mesmo assim).
func _facts(lat: float, lon: float, cache: Dictionary) -> String:
	var out := {}
	for file in ["Bedrock.png", "Clima.png", "Provincias geologicas.png", "Vulcanismo.png"]:
		if not cache.has(file):
			var image = load_map.call(file)
			if image == null:
				return ""
			image.convert(Image.FORMAT_RGB8)
			cache[file] = image
		out[file] = cache[file]
	return resources.hub.registry.PlaceFacts(terrain, out, lat, lon)


## Os nomes das sugestões (e o ponto em avaliação) sobre o globo.
func labels() -> Array:
	var items: Array = review.labels()
	var id := -1
	for entry in plans:
		for i in entry.plan.Count:
			var p: Dictionary = entry.plan.Proposal(i)
			var text: String = "%s %s %d" % ["✕" if p.rejected else "◇", entry.name if _all else "sugestão", i + 1]
			if entry.plan.Scored:
				text += " · %d" % p.score
			var color: Color = Color(0.6, 0.6, 0.6) if p.rejected else (resources.panel._color(entry.rgb).lightened(0.2) if _all else Color(1.0, 0.92, 0.35))
			items.append({"place_id": id, "lat": p.lat, "lon": p.lon, "radius_km": 0.0, "color": color, "label": text})
			id -= 1
	return items


func _prepare() -> void:
	resources.cancel_click()
	resources.leave_painting()
	close()


func _entry(type_id: int, made) -> Dictionary:
	for t in resources.hub.registry.ResourceTypes(""):
		if int(t.id) == type_id:
			return {"type": type_id, "name": t.name, "rgb": int(t.rgb), "plan": made}
	return {"type": type_id, "name": "", "rgb": 0xffffff, "plan": made}


func _say(all: bool, text: String) -> void:
	if all:
		resources.panel.show_all(text)
	else:
		panel.show_preview(text)


func _show() -> void:
	if _all:
		var lines: Array[String] = []
		for entry in plans:
			var made = entry.plan
			lines.append("%s: %d de %d · substitui %d · preserva %d%s" % [entry.name, made.AcceptedCount(), made.Count, made.ReplacedCount,
				made.ProtectedCount, " · %d removidas fora" % made.SuppressedCount if made.SuppressedCount > 0 else ""])
		lines.append("Clique numa mancha ou num nome para ver por que ela está ali (e tirá-la, se quiser). Cada recurso tem a sua cor.")
		resources.panel.show_all("\n".join(lines), true)
		# As áreas de todos, pintadas juntas, cada recurso na sua cor.
		var made_plans: Array[ResourcePlanScript] = []
		var colors: Array = []
		for entry in plans:
			colors.append_array(entry.plan.PreviewPalette(entry.rgb, made_plans.size()))
			made_plans.append(entry.plan)
		resources.territories.show_preview(ResourcePlanScript.new().CombinedImage(terrain.Size, made_plans), colors)
	else:
		var entry: Dictionary = plans[0]
		var made = entry.plan
		var layer = resources.territories.layer(resources.level())
		resources.territories.show_preview(made.PreviewImage(layer), made.PreviewPalette(entry.rgb, 0))
		var parts: Array[String] = ["%d de %d sugestões" % [made.AcceptedCount(), made.Count]]
		if made.IsArea:
			parts[0] += " · %d km²" % roundi(made.AcceptedKm2())
		if made.AcceptedReserve() > 0.0:
			parts.append("quantidade total %s" % resources.panel._plain(made.AcceptedReserve()))
		parts.append("substitui %d geradas" % made.ReplacedCount)
		parts.append("preserva %d suas" % made.ProtectedCount)
		if made.SuppressedCount > 0:
			parts.append("%d já removidas ficam de fora" % made.SuppressedCount)
		var text := " · ".join(parts) + "."
		if made.Count == 0:
			text += " Nenhum lugar atende às condições."
		else:
			text += " Clique numa sugestão no mapa para ver por que ela está ali (e tirá-la, se quiser)."
		if made.Scored:
			text += " O número é a aptidão (0 a 100); o motivo fica na anotação."
		panel.show_preview(text, true)
	resources.refresh()
