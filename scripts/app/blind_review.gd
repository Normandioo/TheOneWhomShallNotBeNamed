extends RefCounted
## Avaliação às cegas: sugestões da regra misturadas com lugares sorteados. O autor julga cada uma sem saber a origem; a regra
## precisa ganhar do sorteio com folga. Nada muda no mundo. O que se mede é se a regra é plausível para o autor, não se há jazida.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const PER_GROUP := 20
const FILE := "user://avaliacoes_gerador.csv"

var generator            # o generator_controller: mapas, terreno, tela
var panel                # GeneratorPanel
var items: Array = []    # {lat, lon, rule: bool, answer: "" | "sim" | "nao" | "talvez"}
var at := 0
var save_path := FILE    # os testes trocam
var _rule := ""
var _name := ""
var _maps := {}


func setup(generator_controller, generator_panel) -> void:
	generator = generator_controller
	panel = generator_panel
	panel.review_requested.connect(start)
	panel.review_answered.connect(answer)
	panel.review_stopped.connect(finish)


func active() -> bool:
	return not items.is_empty()


func start(rule: String) -> void:
	var resources = generator.resources
	if resources.type_id == 0:
		return
	cancel()
	generator.discard()
	generator.hide_why()  # o cartão revelaria de onde vem o lugar
	var parsed: Dictionary = JSON.parse_string(rule)
	parsed.output = "ponto"  # o que se julga é o lugar
	parsed.count = PER_GROUP
	parsed.auto = false  # julga-se toda a área que a regra aceita, não só o núcleo do automático
	var made = generator.make_plan(resources.type_id, JSON.stringify(parsed))
	if made == null:
		return
	if made.Count < 5:
		panel.show_preview("A regra só achou %d lugares: são poucos para avaliar." % made.Count)
		return
	_maps = generator.maps_for(["Bedrock.png", "Clima.png", "Provincias geologicas.png", "Vulcanismo.png"])
	if _maps.is_empty():
		return
	_rule = rule
	for t in resources.hub.registry.ResourceTypes(""):
		if int(t.id) == resources.type_id:
			_name = t.name
	var found: Array = []
	for i in made.Count:
		var p: Dictionary = made.Proposal(i)
		found.append({"lat": p.lat, "lon": p.lon, "rule": true, "answer": ""})
	for p in resources.hub.registry.RandomSites(parsed.get("surface", "terra"), randi(), made.Count, generator.terrain):
		found.append({"lat": p.lat, "lon": p.lon, "rule": false, "answer": ""})
	found.shuffle()
	items = found
	at = 0
	# A pintura do recurso também revelaria: durante a avaliação o mapa mostra os países.
	if resources.TerritoryEditor.is_resource(resources.territories.territory_level):
		resources.territories.show_level("pais")
	_show()


func answer(value: String) -> void:
	if not active():
		return
	items[at].answer = value
	at += 1
	if at >= items.size():
		finish()
	else:
		_show()


## Encerra e mostra o resultado do que foi respondido.
func finish() -> void:
	if not active():
		return
	var text := summary(items)
	var saved := _save()
	cancel()
	panel.show_review_result(text + ("" if saved else "\nNão consegui gravar o arquivo da avaliação."))


func cancel() -> void:
	if not active():
		return
	items = []
	_maps = {}
	panel.show_review("", "")
	if generator.resources.panel.visible:
		generator.resources.show_map()
	generator.resources.refresh()


## O ponto em julgamento, para o globo.
func labels() -> Array:
	if not active():
		return []
	return [{"place_id": -1000, "lat": items[at].lat, "lon": items[at].lon, "radius_km": 0.0, "color": Color(1.0, 0.92, 0.35), "label": "◎ ?"}]


## O resultado em palavras. "Não sei" fica fora da conta. O intervalo é o de 95% da diferença entre as duas proporções
## (Agresti-Caffo): com poucas respostas ele é largo, e é isso que ele deve mostrar.
static func summary(answers: Array) -> String:
	var yes := [0, 0]
	var total := [0, 0]
	for item in answers:
		if item.answer in ["sim", "nao"]:
			var group := 0 if item.rule else 1
			total[group] += 1
			yes[group] += 1 if item.answer == "sim" else 0
	if total[0] < 5 or total[1] < 5:
		return "Poucas respostas para concluir (regra: %d, sorteio: %d; são precisas ao menos 5 de cada)." % [total[0], total[1]]
	var p0: float = (yes[0] + 1.0) / (total[0] + 2.0)
	var p1: float = (yes[1] + 1.0) / (total[1] + 2.0)
	var margin: float = 1.96 * sqrt(p0 * (1 - p0) / (total[0] + 2) + p1 * (1 - p1) / (total[1] + 2))
	var low := roundi(100 * (p0 - p1 - margin))
	var high := roundi(100 * (p0 - p1 + margin))
	var verdict := "A regra ganhou do sorteio com folga." if low > 0 else (
		"O sorteio se saiu melhor que a regra: revise a regra." if high < 0 else "Não dá para afirmar que a regra é melhor que o sorteio.")
	return "Faz sentido: regra %d de %d, sorteio %d de %d.\nDiferença provável (95%%): de %d a %d pontos percentuais.\n%s" % [
		yes[0], total[0], yes[1], total[1], low, high, verdict]


func _show() -> void:
	var item: Dictionary = items[at]
	var resources = generator.resources
	var facts: String = resources.hub.registry.PlaceFacts(generator.terrain, _maps, item.lat, item.lon)
	if resources.focus_map.is_valid():
		resources.focus_map.call(EvronGeo.dir(item.lat, item.lon), 1.5)
	panel.show_review("Lugar %d de %d: faz sentido haver %s aqui?" % [at + 1, items.size(), _name], facts)
	resources.refresh()


## Acrescenta ao arquivo uma linha por resposta, com a regra que foi avaliada.
func _save() -> bool:
	var fresh := not FileAccess.file_exists(save_path)
	var file := FileAccess.open(save_path, FileAccess.WRITE_READ if fresh else FileAccess.READ_WRITE)
	if file == null:
		return false
	if fresh:
		file.store_csv_line(PackedStringArray(["data", "recurso", "regra", "lat", "lon", "origem", "resposta"]))
	file.seek_end()
	var now := Time.get_datetime_string_from_system()
	for item in items:
		if item.answer != "":
			file.store_csv_line(PackedStringArray([now, _name, _rule, "%.3f" % item.lat, "%.3f" % item.lon,
				"regra" if item.rule else "sorteio", item.answer]))
	return true
