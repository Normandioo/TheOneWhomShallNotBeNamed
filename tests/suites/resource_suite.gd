extends "res://tests/test_suite.gd"
## Recursos, etapa 1, sem cena: catálogo, ocorrências em qualquer lugar, desfazer/refazer pela pilha comum e o aceite do plano
## (criar um recurso novo, pintar a ocorrência e reabrir o mundo). As linhas "ERROR" das recusas são esperadas.

const CommandStack = preload("res://scripts/edit/command_stack.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const Calendar = preload("res://scripts/world/calendar.gd")
const Terrain = preload("res://scripts/world/Terrain.cs")
const Territory = preload("res://scripts/world/Territory.cs")


## Dois nomes no mesmo ponto: um fica por extenso e o outro vira só o símbolo; afastados, os dois aparecem; de longe a letra encolhe.
func _test_crowded_labels() -> String:
	var layer = main.globe.resources
	var camera = main.globe.camera
	var item := func(id: int, lon: float) -> Dictionary:
		return {"place_id": id, "lat": 0.0, "lon": lon, "radius_km": 0.0, "color": Color.WHITE, "label": "◇ sugestão %d" % -id}
	camera.look_at_dir(preload("res://scripts/data/evron_geo.gd").dir(0.0, 100.0), 1.2)
	camera.snap()
	layer.show_items([item.call(-1, 100.0), item.call(-2, 100.0)])
	await frames(3)
	if layer._labels[0].text != "◇ sugestão 1" or layer._labels[1].text != "◇":
		return "no mesmo ponto: %s / %s" % [layer._labels[0].text, layer._labels[1].text]
	var near_pixel: float = layer._labels[0].pixel_size
	layer.show_items([item.call(-1, 100.0), item.call(-2, 108.0)])
	await frames(3)
	if layer._labels[1].text != "◇ sugestão 2":
		return "afastados, os dois por extenso: %s" % layer._labels[1].text
	camera.look_at_dir(preload("res://scripts/data/evron_geo.gd").dir(0.0, 100.0), 3.0)
	camera.snap()
	await frames(3)
	if layer._labels[0].pixel_size >= near_pixel:
		return "de longe a letra encolhe"
	layer.show_items([])
	return ""


func run() -> void:
	var crowded: String = await _test_crowded_labels()
	if crowded != "":
		return fail(crowded)
	ok("nomes apertados viram só o símbolo, e de longe a letra encolhe")
	var path := out_dir.path_join("resource_suite.db")
	for ext in ["", "-journal", "-wal", "-shm"]:
		DirAccess.remove_absolute(path + ext)

	# Um mundo da versão 16 (antes dos recursos) ganha o catálogo. A região desenhada por pontos sai, com o vínculo e os números dela;
	# o país e o lugar comum ficam. O ponto de um mundo da versão 17 continua ponto.
	var r = load("res://scripts/world/Registry.cs").new()
	r.OpenAtVersion(path, 16)
	var pais: int = r.Create("pais", "País antigo")
	var porto: int = r.AddPlace("Porto", "assentamento", 1.0, 2.0, 0.0, "")
	r.AddPresence(pais, porto, "capital", "alta")
	r.Close()
	var raw = load("res://scripts/data/WorldDb.cs").new()
	raw.Open(path)
	raw.Execute("insert into place(id, name, kind, lat, lon, radius_km) values (900, 'teste', 'regiao', 5, 5, 0)")
	for i in 3:
		raw.Execute("insert into place_vertex(place_id, seq, lat, lon) values (900, %d, %d, %d)" % [i, i * i, i])
	raw.Close()
	r.OpenAtVersion(path, 16)
	r.AddPresence(pais, 900, "territorio", "media")
	var estimate: int = r.AddEstimate(pais, 900, 0, 10.0, 10.0, "alta", "")
	if estimate == 0 or r.PresencesOf(pais, 0).size() != 2:
		return fail("preparação do mundo antigo")
	r.Close()
	r.OpenAtVersion(path, 17)
	r.Close()
	raw.Open(path)
	raw.Execute("insert into resource_type(id, name, rgb) values (50, 'Antigo', 255)")
	raw.Execute("insert into resource_occurrence(id, type_id, lat, lon) values (7, 50, 3, 4)")
	raw.Close()
	r.Open(path)
	if not r.IsOpen() or r.Name(pais) != "País antigo" or r.Places("teste").size() != 0 or r.Places("Porto").size() != 1:
		return fail("a migração deveria tirar só a região desenhada")
	if r.PresencesOf(pais, 0).size() != 1 or r.EstimatesOf(pais, 0).size() != 0:
		return fail("o vínculo e os números da região desenhada deveriam sair: %s" % [r.PresencesOf(pais, 0)])
	var old: Dictionary = r.Occurrences(50)[0]
	if old.id != 7 or old.kind != "ponto" or old.lat != 3.0:
		return fail("o ponto antigo deveria continuar: %s" % [old])
	r.DeleteOccurrence(7)
	r.DeleteResourceType(50)
	ok("migração: a região desenhada sai com vínculo e números; país, lugar e ponto ficam")

	var stack := CommandStack.new()
	var made = r.CreateResourceType("  Éter azul  ")
	stack.push("criar recurso", made)
	var eter: int = made.Id
	var t: Dictionary = r.ResourceTypes("eter")[0]  # a busca ignora acentos
	if t.name != "Éter azul" or t.unit != "" or t.count != 0:
		return fail("recurso só com nome: %s" % [t])
	if r.CreateResourceType("   ") != null:
		return fail("nome vazio deveria ser recusado")
	ok("recurso novo só com o nome; busca sem acentos")

	# Pontos no polo e no meio do mar; áreas com identidade própria. Nada ambiental recusa.
	var point = r.AddPoint(eter, -89.9, 179.99)
	stack.push("ponto", point)
	var area = r.AddArea(eter)
	stack.push("área", area)
	var rows: Array = r.Occurrences(eter)
	if rows.size() != 2 or rows[0].kind != "ponto" or rows[1].kind != "area" or rows[0].origin != "manual" or rows[1].state != "narrativo":
		return fail("ponto e área: %s" % [rows])
	if Array(r.PointsAt(eter, -89.9, 179.99, 5.0)) != [point.Id] or r.PointsAt(eter, 0.0, 0.0, 5.0).size() != 0:
		return fail("achar o ponto")
	var level := "recurso:%d" % eter
	if r.Palette(level).size() != 1 or r.Palette(level)[0].id != area.Id or r.OccurrenceType(area.Id) != eter:
		return fail("a paleta do recurso são as áreas dele: %s" % [r.Palette(level)])
	for bad in [r.AddPoint(eter, 91.0, 0.0), r.AddPoint(eter, NAN, 0.0), r.AddPoint(999, 0.0, 0.0), r.AddArea(999),
			r.MovePoint(area.Id, 0.0, 0.0), r.DuplicatePoint(area.Id), r.DuplicatePoint(999), r.DeleteOccurrence(999), r.DeleteResourceType(eter)]:
		if bad != null:
			return fail("uma operação inválida foi aceita")
	if r.Occurrences(0).size() != 2 or r.ResourceTypes("").size() != 1:
		return fail("as recusas não podem gravar nada")
	ok("pontos e áreas em qualquer lugar; recusas não gravam; recurso em uso não é excluído")

	var states: Array = [_state(r)]
	for step in [func(): return r.MovePoint(point.Id, -30.0, 40.0), func(): return r.DuplicatePoint(point.Id),
			func(): return r.SetOccurrenceText(area.Id, "Veio norte", "achado pelo autor"),
			func(): return r.SetResourceType(eter, "Éter", "brilha", "mágico", "frasco", 0x112233), func(): return r.DeleteOccurrence(point.Id)]:
		var cmd = step.call()
		if cmd == null:
			return fail("um passo válido foi recusado (estado %d)" % states.size())
		stack.push("passo", cmd)
		states.append(_state(r))
	for i in range(states.size() - 2, -1, -1):
		stack.undo()
		if _state(r) != states[i]:
			return fail("desfazer até o estado %d: %s ≠ %s" % [i, _state(r), states[i]])
	for i in range(1, states.size()):
		stack.redo()
		if _state(r) != states[i]:
			return fail("refazer até o estado %d: %s ≠ %s" % [i, _state(r), states[i]])
	var final_state := _state(r)
	while stack.can_undo():
		stack.undo()
	if r.ResourceTypes("").size() != 0 or r.Occurrences(0).size() != 0:
		return fail("desfazer tudo deveria esvaziar o catálogo")
	while stack.can_redo():
		stack.redo()
	if _state(r) != final_state:
		return fail("refazer tudo deveria voltar ao fim com os mesmos ids")
	var last = r.AddArea(eter)
	r.DeleteOccurrence(last.Id)
	if r.AddArea(eter).Id <= last.Id:
		return fail("o id de uma ocorrência excluída foi reusado")
	ok("mover, duplicar, editar e excluir: desfazer e refazer exatos; id excluído não volta")

	# Aceite: pintar na camada do recurso, reabrir e exportar o mundo conserva o recurso e a pintura.
	var terrain := Terrain.new()
	var height := Image.create(512, 256, false, Image.FORMAT_RF)
	height.fill(Color(100.0, 0, 0))
	terrain.Setup(height)
	var painted := Territory.new()
	painted.Setup(terrain)
	painted.Begin()
	painted.Dab(EvronGeo.dir(10.0, 20.0), 800.0, area.Id, true, -1)
	painted.End()
	var km2: float = painted.AreaKm2(area.Id)
	var wrote = r.SaveTerritoryLevel(level, painted)
	var refused = r.SaveTerritoryLevel("recurso:abc", painted)  # a recusa do C# chega como null ou 0
	if km2 <= 0.0 or wrote == null or wrote <= 0 or (refused != null and refused != 0):
		return fail("a camada do recurso deveria gravar (e um nível inventado, não)")
	final_state = _state(r)
	r.Close()
	var dir := out_dir.path_join("recursos-%d.world" % Time.get_ticks_usec())
	r.Open(path)
	if r.ExportWorld(dir, "") != "":
		return fail("exportar o mundo")
	for source in [path, dir.path_join("world.sqlite")]:
		r.Close()
		r.Open(source)
		var back := Territory.new()
		back.Setup(terrain)
		if _state(r) != final_state or not r.LoadTerritoryLevel(level, back) or back.AreaKm2(area.Id) != km2:
			return fail("reabrir %s mudou os recursos ou a pintura" % source)
	r.Close()
	ok("aceite: criar, pintar, reabrir e exportar o mundo")
	if main != null:
		await _run_scene()


## Com a cena: o botão abre o painel; a área é pintada pelo mesmo caminho dos países; o mapa mostra o recurso escolhido.
func _run_scene() -> void:
	await frames(5)
	var res = main.resources
	var panel = res.panel
	var reg = main.domains.registry
	var layer = main.globe.resources
	var editor = main.territories
	main.tool_panel.resources_toggle.button_pressed = true
	await frames(2)
	if not panel.visible or panel.type_box.visible or editor.territory_level != "pais":
		return fail("o botão deveria abrir o painel sem recurso escolhido")
	panel.create_requested.emit("", "")
	if panel.message.text == "" or reg.ResourceTypes("").size() != 0:
		return fail("nome vazio deveria avisar e não criar")
	panel.create_requested.emit("Ferro estelar", "mineral")
	var ferro: int = res.type_id
	if panel.delete_type_button.disabled:
		return fail("um recurso fora do mapa pode ser excluído")
	if not panel.type_box.visible or editor.territory_level != "recurso:%d" % ferro:
		return fail("o recurso criado deveria ficar escolhido, com o mapa dele")
	panel.area_requested.emit()
	var area: int = res.occurrence_id
	if not editor.painting_territory or editor.territory_owner != area or editor.territory_panel._actions.visible:
		return fail("a área nova deveria entrar no modo pintar, sem as ações de país")
	editor.territory_land_only = false
	editor.territory_radius = 700.0
	editor.territory_begin(EvronGeo.dir(5.0, 20.0))
	editor.territory_end()
	await frames(3)
	var painted: float = editor.territory.AreaKm2(area)
	if painted <= 0.0 or layer.label_count != 1 or not panel.occurrence_rows()[0].text.contains("km²"):
		return fail("a pintura deveria aparecer no painel e no nome sobre o globo")
	# O lugar escolhido abre na própria linha; clicar nela de novo fecha.
	var first_row: Button = panel.occurrence_rows()[0]
	if not panel.occurrence_box.is_visible_in_tree() or not first_row.text.begins_with("▾") or panel._detail.get_index() != first_row.get_index() + 1:
		return fail("a área escolhida deveria estar aberta logo abaixo da linha dela")
	if panel.occurrence_box.find_children("*", "Button", true, false).any(func(b): return b.text == "Salvar detalhes" and b.is_visible_in_tree()):
		return fail("os detalhes começam guardados em Mais opções")
	main.undo()
	if editor.territory.AreaKm2(area) != 0.0:
		return fail("Ctrl+Z desfaz a pincelada")
	main.redo()
	main.globe.focus(EvronGeo.dir(5.0, 25.0), 2.6)
	await save("recursos_painel")
	editor.stop_painting()
	panel.point_requested.emit()
	main.select(EvronGeo.dir(-20.0, 40.0))
	if reg.Occurrences(ferro).size() != 2 or layer.label_count != 2:
		return fail("o clique deveria colocar um ponto")
	main.select(EvronGeo.dir(5.0, 20.0))
	if res.occurrence_id != area:
		return fail("o clique na área pintada deveria escolhê-la")

	# Outro recurso, no mesmo lugar: camadas separadas.
	panel.create_requested.emit("Solo fértil", "vegetal")
	var solo: int = res.type_id
	panel.area_requested.emit()
	var other: int = res.occurrence_id
	editor.territory_begin(EvronGeo.dir(5.0, 20.0))
	editor.territory_end()
	if editor.layer("recurso:%d" % solo).AreaKm2(other) <= 0.0 or editor.layer("recurso:%d" % ferro).AreaKm2(area) != painted:
		return fail("recursos diferentes se sobrepõem sem apagar um ao outro")
	panel.back_requested.emit()
	await frames(2)
	var categories := func() -> Array: return panel.type_rows().map(func(row): return row.get_meta("category"))
	if categories.call() != ["Minerais", "Vegetação"]:
		return fail("a lista segue a ordem das categorias: %s" % [categories.call()])
	var heads: Array = panel.types.get_children().filter(func(c): return c.has_meta("header"))
	if heads.size() != 1 or not panel.type_rows()[0].accessibility_name.contains("2 lugares"):
		return fail("os dois da natureza ficam num grupo só e dizem quantos lugares têm: %s" % panel.type_rows()[0].accessibility_name)
	# O recurso novo pelo formulário: fabricado, em unidades; e o modelo pronto aparece quando o nome bate.
	panel.new_toggle.button_pressed = true
	panel.new_name.text = "cobre"
	panel.new_name.text_changed.emit("cobre")
	if not panel.new_profile.visible:
		return fail("o nome de um modelo pronto oferece o modelo")
	panel.new_name.text = "Lâmina de teste"
	panel.new_name.text_changed.emit("Lâmina de teste")
	panel._origin_cards["fabricado"].pressed.emit()
	panel._unit_chips["unidade"].pressed.emit()
	panel.new_create.pressed.emit()
	var blade: Array = Array(reg.ResourceTypes("Lâmina de teste"))
	if blade.size() != 1 or blade[0].category != "manufatura" or blade[0].unit != "unidade" or not panel._made or panel.new_box.visible:
		return fail("criar pelo formulário: fabricado, em unidades, e abre o recurso: %s" % [blade])
	main.undo()
	panel.back_requested.emit()
	await save("recursos_categorias")
	panel.type_chosen.emit(ferro)
	panel.occurrence_chosen.emit(area)
	for row in panel.occurrence_rows():
		if row.text.begins_with("▾"):
			row.pressed.emit()
	if res.occurrence_id != 0 or panel.occurrence_box.visible:
		return fail("clicar de novo na linha aberta a fecha")
	panel.occurrence_chosen.emit(area)
	panel.details.grade.text = "35"
	panel.details.access.select(2)
	panel.details_saved.emit({"grade": "35", "depth": "", "access": "medio", "renewal": "", "policy": "normal", "from": "3", "to": ""})
	var detail: Dictionary = reg.OccurrenceDetails(area)
	if detail.grade != 35.0 or detail.access != "medio" or detail.valid_from != Calendar.to_seconds(3, 1, 1):
		return fail("os detalhes salvos pela tela: %s" % [detail])
	main.undo()
	if not is_nan(reg.OccurrenceDetails(area).grade):
		return fail("Ctrl+Z desfaz os detalhes")
	var reino: int = reg.Create("pais", "Reino de teste")
	panel.knowledge_ui.search.text = "Reino de"
	panel.knowledge_ui.search.text_changed.emit("Reino de")
	panel.knowledge_added.emit(int(panel.knowledge_ui.who.get_item_metadata(0)), "", "", "120", "")
	panel.right_added.emit(reino, "exploracao", "2", "", "")
	if reg.Knowledge(area).size() != 1 or reg.Rights(area).size() != 1 or panel.knowledge_list.item_count != 1 or panel.rights_list.item_count != 1:
		return fail("quem conhece e direitos pela tela")
	reg.DeleteKnowledge(int(reg.Knowledge(area)[0].id))
	reg.DeleteRight(int(reg.Rights(area)[0].id))
	panel.type_chosen.emit(ferro)
	if editor.painting_territory or editor.territory_level != "recurso:%d" % ferro:
		return fail("escolher outro recurso encerra a pintura e troca o mapa")
	ok("cena: pintar, desfazer, ponto, escolher pelo clique e sobreposição entre recursos")

	# Excluir a área leva a pintura junto, num comando só.
	panel.occurrence_chosen.emit(area)
	panel.delete_requested.emit()
	if reg.OccurrenceType(area) != 0 or editor.territory.AreaKm2(area) != 0.0:
		return fail("excluir a área apaga o registro e a pintura")
	main.undo()
	if reg.OccurrenceType(area) != ferro or editor.territory.AreaKm2(area) != painted:
		return fail("um Ctrl+Z devolve o registro e a pintura")

	# Trocar de mapa no meio da pintura a encerra; fechar o painel volta ao mapa de antes.
	panel.occurrence_chosen.emit(area)
	panel.paint_requested.emit()
	editor.show_level("cultura")
	if editor.painting_territory:
		return fail("trocar de mapa deveria encerrar a pintura")
	editor.show_level("recurso:%d" % ferro)
	main.tool_panel.resources_toggle.button_pressed = false
	if panel.visible or layer.item_count != 0 or editor.is_resource(editor.territory_level):
		return fail("fechado, o painel devolve o mapa e some com os nomes (%s)" % editor.territory_level)

	# Rec: todos os recursos juntos, com os pontos; a legenda esconde um; o clique abre o recurso; outro modo encerra.
	main.mode_rail.level_selected.emit("recursos")
	await frames(2)
	if not res.rec or not main.rec_legend.visible or main.rec_legend.checks.size() != 2 or layer.item_count != 1:
		return fail("o Rec mostra os dois recursos na legenda e o ponto no globo (%d itens)" % layer.item_count)
	main.globe.focus(EvronGeo.dir(5.0, 25.0), 2.6)
	await save("recursos_rec")
	main.rec_legend.checks[solo].button_pressed = false
	if not res.rec_hidden.has(solo) or res._rec_layers.size() != 1:
		return fail("desligar na legenda tira o recurso do mapa")
	main.select(EvronGeo.dir(5.0, 20.0))
	if res.rec or not panel.visible or res.type_id != ferro or res.occurrence_id != area:
		return fail("o clique numa área do Rec abre o recurso e o lugar (%d, %d)" % [res.type_id, res.occurrence_id])
	main.tool_panel.resources_toggle.button_pressed = false
	main.mode_rail.level_selected.emit("recursos")
	main.mode_rail.level_selected.emit("pais")
	if res.rec or main.rec_legend.visible or editor.previewing:
		return fail("outro modo de mapa encerra o Rec")
	res.rec_hidden.clear()

	while main.commands.can_undo():
		main.undo()
	if reg.ResourceTypes("").size() != 0:
		return fail("desfazer tudo pela pilha do programa")
	if not editor.flush():
		return fail("as camadas de recurso deveriam gravar")
	ok("cena: excluir com um desfazer, trocar de mapa, fechar o painel e gravar")


## Tudo o que o catálogo e as ocorrências mostram.
func _state(r) -> String:
	return var_to_str([r.ResourceTypes(""), r.Occurrences(0)])
