extends "res://tests/test_suite.gd"
## O resto da E2, com a cena: o mapa plano (as mesmas camadas, cadastros e coordenadas do globo: um ponto projetado e clicado volta ao
## mesmo lat/lon nos dois modos, inclusive perto de 180° e dos polos; o clique abre o mesmo país), a régua (distância pela esfera, que
## atravessa 180°) e as operações em lote da busca (etiquetar e excluir vários, num desfazer só).

const Geo = preload("res://scripts/data/evron_geo.gd")


func _paint(layer, center: Vector3, radius: float, owner: int) -> void:
	layer.Begin()
	layer.Dab(center, radius, owner, false, -1)
	layer.End()


## Projeta o ponto da cena da direção n na tela e clica (pick) ali: a direção que volta, em graus de erro.
func _round_trip(n: Vector3) -> float:
	var globe = main.globe
	var screen: Vector2 = globe.camera.cam.unproject_position(globe.world_of(n))
	var back: Vector3 = globe.pick(screen)
	return 999.0 if back == Vector3.ZERO else rad_to_deg(back.angle_to(n))


func run() -> void:
	if main == null:
		return fail("esta suíte precisa da cena")
	await _flat()
	await _ruler()
	await _batch()


func _flat() -> void:
	var globe = main.globe
	var hub = main.domains
	var aren: int = hub.registry.Create("pais", "Aren")
	_paint(main.territory, Geo.dir(10, 20), 900, aren)
	main.territories.refresh_palette()
	var cidade: int = hub.registry.AddPlace("Valdória", "assentamento", 10.0, 20.0, 0.0, "")
	hub.registry.AddPresence(aren, cidade, "capital", "alta")
	hub.open(aren)
	for i in MapLayers_political():
		main.set_layer(i)
	main.tool_panel.flat_toggle.button_pressed = true
	await frames(2)
	if not globe.flat:
		return fail("o botão Plano deveria pôr o mapa plano")
	globe.focus(Geo.dir(10, 20), 2.5)
	await frames(30)
	var worst := 0.0
	for p in [[10, 20], [0, 0], [-30, 40], [45, -10], [60, 30]]:
		worst = maxf(worst, _round_trip(Geo.dir(p[0], p[1])))
	if worst > 0.2:
		return fail("no plano, projetar e clicar deveria voltar ao mesmo ponto (erro %.3f°)" % worst)
	var label_at: Vector3 = hub.map._labels[0].position if not hub.map._labels.is_empty() else Vector3.ZERO
	var want: Vector3 = globe.world_of(Geo.dir(10, 20), 1.0)
	if label_at == Vector3.ZERO or Vector2(label_at.x, label_at.y).distance_to(Vector2(want.x, want.y)) > 0.01:
		return fail("o nome da capital deveria ir para o plano, no mesmo lat/lon: %s × %s" % [label_at, want])
	var center: Vector2 = globe.camera.cam.unproject_position(globe.world_of(Geo.dir(10, 20)))
	hub.deselect()
	main.select(globe.pick(center))
	if hub.current() != aren:
		return fail("clicar no plano deveria abrir o mesmo país (aberto: %d)" % hub.current())
	await save("mapa_plano")
	# Perto de 180° e dos polos (a câmera vai até lá).
	for p in [[0, 179.5], [0, -179.5], [80, 100], [-80, -60]]:
		globe.focus(Geo.dir(p[0], p[1]), 1.5)
		await frames(3)
		worst = maxf(worst, _round_trip(Geo.dir(p[0], p[1])))
	if worst > 0.2:
		return fail("no plano, perto de 180° e dos polos o clique deveria voltar ao mesmo ponto (erro %.3f°)" % worst)
	main.tool_panel.flat_toggle.button_pressed = false
	await frames(2)
	globe.focus(Geo.dir(10, 20), 2.5)
	await frames(5)
	if globe.flat or _round_trip(Geo.dir(10, 20)) > 0.2:
		return fail("de volta ao globo, o clique vale de novo na esfera")
	ok("mapa plano: as mesmas camadas e cadastros; o clique volta ao mesmo lat/lon (também em 180° e perto dos polos) e abre o mesmo país")


func MapLayers_political() -> Array:
	var MapLayers = load("res://scripts/ui/map_layers.gd")
	for i in MapLayers.LAYERS.size():
		if MapLayers.LAYERS[i]["kind"] == "political":
			return [i]
	return []


func _ruler() -> void:
	var r = main.ruler
	var opened: int = main.domains.current()
	main.tool_panel.ruler_toggle.button_pressed = true
	if not r.active:
		return fail("o botão Medir liga a régua")
	main.select(Geo.dir(0, 179))
	main.select(Geo.dir(0, -179))
	var across: float = r.total_km()
	var want := Geo.distance_km(Geo.dir(0, 179), Geo.dir(0, -179))
	if absf(across - want) > 0.01 or across > 300.0:
		return fail("a régua atravessa 180° pela esfera: %.1f km (devia ser %.1f)" % [across, want])
	main.select(Geo.dir(10, -179))
	if r.points.size() != 3 or not r.text().contains("2 trechos"):
		return fail("três cliques, dois trechos: " + r.text())
	r.remove_last()
	if r.points.size() != 2:
		return fail("Backspace tira o último ponto")
	if main.domains.current() != opened:
		return fail("com a régua, o clique não seleciona cadastros")
	main.tool_panel.ruler_toggle.button_pressed = false
	if r.active or not r.points.is_empty():
		return fail("desligar a régua apaga a medida")
	ok("régua: %.0f km de um lado ao outro de 180° (pela esfera, não pelo mapa); trechos, Backspace e desligar" % across)


func _batch() -> void:
	var hub = main.domains
	var r = hub.registry
	var ids: Array = []
	for name in ["Lote A", "Lote B", "Lote C"]:
		var id: int = r.Create("pais", name)
		ids.append(id)
		_paint(main.territory, Geo.dir(-40, -100 + 15 * ids.size()), 300, id)
	hub.batch_tag(ids, "costa sul")
	for id in ids:
		if not "costa sul" in Array(r.Sheet(id, hub.shown_t).tags):
			return fail("etiquetar em lote")
	main.undo()
	for id in ids:
		if "costa sul" in Array(r.Sheet(id, hub.shown_t).tags):
			return fail("um desfazer tira a etiqueta de todos")
	var area: float = main.territory.AreaKm2(ids[1])
	hub.batch_delete(ids)
	for id in ids:
		if r.Kind(id) != "" or main.territory.AreaKm2(id) > 0.0:
			return fail("excluir em lote apaga os cadastros e o território de cada um")
	main.undo()
	if r.Kind(ids[2]) != "pais" or absf(main.territory.AreaKm2(ids[1]) - area) > 1.0:
		return fail("um desfazer devolve todos, com o território")
	# Pela lista da busca: marcar dois com Ctrl mostra a barra do lote.
	var search = hub.search
	search._query.text = "Lote"
	search._emit_query()
	await frames(2)
	search._list.select(0, false)
	search._list.select(1, false)
	search._show_batch()
	if not search._batch.visible or search.marked().size() != 2:
		return fail("dois marcados na busca mostram a barra do lote")
	ok("lote: etiquetar e excluir vários (com o território) num desfazer só; a busca marca vários com Ctrl")
