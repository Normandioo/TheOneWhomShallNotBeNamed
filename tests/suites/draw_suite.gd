extends "res://tests/test_suite.gd"
## O desenho de fronteiras à mão (etapa de fronteiras): o modo desenhar pelo hub e pela barra, o clique que marca pontos e cola em vértices
## vizinhos, conclusão e recusas, redesenhar, cancelar, atalhos de teclado e o desenho do contorno e do rascunho no globo.
## As linhas "ERROR" das recusas do C# são esperadas.

const SearchPanel = preload("res://scripts/ui/search_panel.gd")
const SheetPanel = preload("res://scripts/ui/sheet_panel.gd")
const CalendarPanel = preload("res://scripts/ui/calendar_panel.gd")
const PresencePanel = preload("res://scripts/ui/presence_panel.gd")
const DrawPanel = preload("res://scripts/ui/draw_panel.gd")
const PlaceLayer = preload("res://scripts/view/place_layer.gd")
const DomainHub = preload("res://scripts/world/domain_hub.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")

var hub
var reg
var search
var sheet
var presence
var map
var draw_panel
var host: Control


func _click(lat: float, lon: float, snap_km: float = 0.0) -> void:
	hub.draw_click(EvronGeo.dir(lat, lon), snap_km)


func _square(lat: float, lon: float, size: float) -> void:
	for p in [[lat, lon], [lat, lon + size], [lat + size, lon + size], [lat + size, lon]]:
		_click(p[0], p[1])


func run() -> void:
	host = Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	search = SearchPanel.new()
	sheet = SheetPanel.new()
	presence = PresencePanel.new()
	map = PlaceLayer.new()
	map.radius = 6.371
	draw_panel = DrawPanel.new()
	var cal := CalendarPanel.new()
	for n in [search, sheet, cal, presence, map, draw_panel]:
		host.add_child(n)
	hub = DomainHub.new()
	hub.setup(":memory:", search, sheet, cal)
	hub.bind_map(map, presence, func(_d: Vector3, _z: float) -> void: pass)
	hub.bind_draw(draw_panel)
	reg = hub.registry
	await frames(2)

	var pais: int = reg.Create("pais", "Reino de Aren")
	var vizinho: int = reg.Create("pais", "Reino vizinho")
	hub.open(pais)

	# Começar exige um nome; entrando no modo, a barra aparece e a ficha/lista/clique não atrapalham.
	sheet.border_draw_requested.emit("  ", "territorio")
	if hub.drawing or not sheet._border_msg.text.begins_with("Dê um nome"):
		return fail("sem nome não deveria começar a desenhar: '%s'" % sheet._border_msg.text)
	sheet.border_draw_requested.emit("Vale de Aren", "territorio")
	if not hub.drawing or not draw_panel.visible or not draw_panel._finish.disabled or not draw_panel._undo.disabled:
		return fail("o modo desenhar deveria abrir a barra com Concluir e Desfazer desligados")
	hub.open(vizinho)
	if hub.current() != pais or not draw_panel._status.text.contains("Conclua ou cancele"):
		return fail("abrir outra ficha no meio do desenho deveria ser ignorado, com aviso")
	if hub.pick(EvronGeo.dir(10.0, 20.0), 100.0) != 0:
		return fail("o clique de seleção não age durante o desenho")
	ok("modo desenhar: exige nome, abre a barra, bloqueia abrir outra ficha e o clique de seleção")

	# Marcar pontos, desfazer, ponto repetido e o rascunho no globo.
	_click(5, 15)
	_click(5, 25)
	if draw_panel._finish.disabled == false or map.draft_count != 2 or map._draft_node.mesh == null:
		return fail("com 2 pontos: o rascunho é uma linha e Concluir segue desligado")
	_click(15, 25)
	if draw_panel._finish.disabled or map.draft_count != 3:
		return fail("com 3 pontos Concluir liga")
	hub.draw_undo()
	if map.draft_count != 2 or not draw_panel._finish.disabled:
		return fail("desfazer tira o último ponto")
	_click(5, 25)  # o mesmo ponto do último: ignorado
	if map.draft_count != 2 or not draw_panel._status.text.contains("já está marcado"):
		return fail("o ponto repetido em seguida deveria ser ignorado")
	_click(15, 25)
	_click(15, 15)
	if map.draft_count != 4 or map._draft_labels.size() != 4:
		return fail("4 pontos e 4 marcas no rascunho")
	ok("pontos, desfazer, ponto repetido ignorado e rascunho no globo (linha e marcas)")

	# Um contorno que se cruza é recusado e o desenho continua para corrigir.
	var lugares: int = reg.Places("").size()
	hub.draw_undo()
	hub.draw_undo()
	_click(15, 15)   # ordem trocada: (5,15) (5,25) (15,15) (15,25) forma uma gravata
	_click(15, 25)
	hub.draw_finish()
	if not hub.drawing or reg.Places("").size() != lugares or not draw_panel._status.text.contains("Esse contorno não vale"):
		return fail("a gravata deveria ser recusada sem gravar e sem sair do modo (lugares %d -> %d)" % [lugares, reg.Places("").size()])
	hub.draw_undo()
	hub.draw_undo()
	_click(15, 25)
	_click(15, 15)
	hub.draw_finish()
	if hub.drawing or draw_panel.visible or map.draft_count != 0:
		return fail("concluir sai do modo, esconde a barra e apaga o rascunho")
	var pres: Array = reg.PresencesOf(pais, hub.shown_t)
	if pres.size() != 1 or pres[0].place != "Vale de Aren" or pres[0].role != "territorio" or pres[0].vertices.size() != 8 or pres[0].radius_km != 0.0:
		return fail("a fronteira deveria virar lugar + presença de território: %s" % [pres])
	if hub.current() != pais or map.polygon_count != 1:
		return fail("a ficha do país reabre e o mapa desenha o contorno (contornos=%d)" % map.polygon_count)
	var linhas := []
	_texts(sheet._body, linhas)
	if not "\n".join(linhas).contains("contorno de 4 pontos"):
		return fail("a ficha deveria dizer 'contorno de 4 pontos': %s" % ["\n".join(linhas)])
	ok("a gravata é recusada (e o desenho continua); corrigida, vira lugar + território, a ficha e o mapa mostram o contorno")

	# Fronteira vizinha: o clique perto de um vértice existente cola nele (borda compartilhada sem fresta).
	presence._scope.select(1)  # todas as entidades: o contorno do primeiro país está no mapa
	presence._scope.item_selected.emit(1)
	hub.open(vizinho)
	sheet.border_draw_requested.emit("Reino vizinho (território)", "territorio")
	_click(15.02, 25.02, 20.0)   # a ~3 km do vértice (15, 25)
	if hub._draw_pts[0] != Vector2(15, 25) or not draw_panel._status.text.contains("colado"):
		return fail("o primeiro ponto deveria colar no vértice (15, 25): %s" % [hub._draw_pts])
	_click(5.02, 24.98, 20.0)
	_click(5, 35, 20.0)          # longe de qualquer vértice: fica onde foi clicado
	_click(15, 35, 20.0)
	if hub._draw_pts[1] != Vector2(5, 25) or hub._draw_pts[2] != Vector2(5, 35):
		return fail("o segundo ponto cola em (5, 25) e o terceiro fica onde foi: %s" % [hub._draw_pts])
	hub.draw_finish()
	var v2: PackedFloat64Array = reg.PresencesOf(vizinho, hub.shown_t)[0].vertices
	var v1: PackedFloat64Array = reg.PresencesOf(pais, hub.shown_t)[0].vertices
	if v2[0] != 15.0 or v2[1] != 25.0 or v2[2] != 5.0 or v2[3] != 25.0 or v1.size() != 8:
		return fail("as bordas compartilhadas deveriam ser exatamente iguais: %s" % [v2])
	var no_meio: Array = reg.EntitiesAt(10.0, 25.0, 0.0, PackedStringArray(["politica"]), 0, hub.shown_t)
	var a_leste: Array = reg.EntitiesAt(10.0, 30.0, 0.0, PackedStringArray(["politica"]), 0, hub.shown_t)
	if a_leste.size() != 1 or a_leste[0].entity_id != vizinho or reg.EntitiesAt(10.0, 20.0, 0.0, PackedStringArray(["politica"]), 0, hub.shown_t)[0].entity_id != pais:
		return fail("cada ponto deveria estar em um país só: leste=%d" % a_leste.size())
	print("MEDIDA     na borda compartilhada (10, 25): %d país(es) achado(s) com tolerância 0 (borda exata)" % no_meio.size())
	ok("fronteira vizinha: cola nos vértices existentes (borda compartilhada exata) e cada lado é de um país")

	# Redesenhar o contorno de um lugar que já existe.
	hub.open(pais)
	var vale_id: int = pres[0].place_id
	sheet.border_redraw_requested.emit(vale_id, "territorio")
	if not hub.drawing or hub._draw_place != vale_id:
		return fail("redesenhar deveria entrar no modo para esse lugar")
	_click(0, 0)
	_click(0, 10)
	hub.draw_finish()
	if not hub.drawing or not draw_panel._status.text.contains("ao menos 3"):
		return fail("com 2 pontos concluir pede ao menos 3")
	_click(10, 5)
	hub.draw_finish()
	var novo: PackedFloat64Array = reg.PlaceVertices(vale_id)
	if hub.drawing or novo.size() != 6 or novo[0] != 0.0 or reg.Place(vale_id).vertex_count != 3 or reg.Places("Vale de Aren").size() != 1:
		return fail("o contorno do mesmo lugar deveria ser trocado (sem criar outro lugar): %s" % [novo])
	ok("redesenhar troca o contorno do mesmo lugar; com 2 pontos pede 3")

	# Cancelar não grava nada; os atalhos da barra.
	var antes: int = reg.Places("").size()
	sheet.border_draw_requested.emit("Não vai existir", "reivindicacao")
	_square(30, 30, 5)
	hub.draw_cancel()
	if hub.drawing or draw_panel.visible or map.draft_count != 0 or reg.Places("").size() != antes:
		return fail("cancelar apaga o rascunho e não grava")
	sheet.border_draw_requested.emit("Pelos atalhos", "reivindicacao")
	_click(30, 30)
	_click(30, 35)
	var bs := InputEventKey.new()
	bs.keycode = KEY_BACKSPACE
	bs.pressed = true
	draw_panel._unhandled_key_input(bs)
	if hub._draw_pts.size() != 1:
		return fail("Backspace desfaz o último ponto")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	draw_panel._unhandled_key_input(enter)   # só 1 ponto: Concluir está desligado, então Enter não faz nada
	if not hub.drawing:
		return fail("Enter não conclui com menos de 3 pontos")
	_click(35, 35)
	_click(35, 30)
	draw_panel._unhandled_key_input(enter)
	if hub.drawing or reg.Places("Pelos atalhos").size() != 1:
		return fail("Enter conclui quando dá")
	sheet.border_draw_requested.emit("Esc cancela", "reivindicacao")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	draw_panel._unhandled_key_input(esc)
	if hub.drawing:
		return fail("Esc cancela")
	ok("cancelar não grava; Backspace desfaz, Enter conclui (com 3+) e Esc cancela")

	# O desenho no globo: contorno côncavo triangula; um contorno estragado (que não passou pela validação) não derruba o desenho.
	var dirs: Array[Vector3] = []
	for p in [[0, 0], [0, 10], [5, 10], [5, 5], [10, 5], [10, 0]]:   # um L
		dirs.append(EvronGeo.dir(p[0], p[1]))
	var tri: PackedInt32Array = map._triangulate(dirs, EvronGeo.dir(4.0, 4.0))
	if tri.size() != 12:
		return fail("um L de 6 vértices dá 4 triângulos (12 índices): %d" % tri.size())
	var gravata: Array[Vector3] = []
	for p in [[5, 15], [15, 25], [15, 15], [5, 25]]:
		gravata.append(EvronGeo.dir(p[0], p[1]))
	map.show_items([{"place_id": 99, "place": "Estragado", "lat": 10.0, "lon": 20.0, "radius_km": 0.0, "layer": "politica", "role": "territorio", "entity": "x",
		"vertices": PackedFloat64Array([5, 15, 15, 25, 15, 15, 5, 25]), "area_km2": 1000.0}])
	var arrays: Array = map._mesh_node.mesh.surface_get_arrays(0)
	if map.polygon_count != 1 or arrays[Mesh.ARRAY_VERTEX].size() < 12:
		return fail("mesmo sem triangulação o aro do contorno é desenhado (vértices=%d)" % arrays[Mesh.ARRAY_VERTEX].size())
	hub.refresh_map()
	var itens: Array = reg.MapItems(PackedStringArray(["politica"]), pais, hub.shown_t)
	map.show_items(itens)
	var n_total: int = map._mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var dirs_item: Array[Vector3] = []
	var vs: PackedFloat64Array = itens[0].vertices
	for i in vs.size() / 2:
		dirs_item.append(EvronGeo.dir(vs[2 * i], vs[2 * i + 1]))
	var so_aro_v := PackedVector3Array()
	map._ribbon(so_aro_v, PackedColorArray(), dirs_item, 0.001, Color.WHITE, true)
	if n_total <= so_aro_v.size() or n_total < 100:
		return fail("o contorno deveria ter preenchimento além do aro (total %d, só o aro %d)" % [n_total, so_aro_v.size()])
	map.show_draft([])
	if map._draft_node.mesh != null or map.draft_count != 0 or not map._draft_labels.is_empty():
		return fail("rascunho vazio apaga a linha e as marcas")
	ok("o contorno côncavo triangula; um contorno estragado não derruba o desenho (só o aro); rascunho vazio apaga")

	# Com a cena: o clique de verdade (Main.select) marca os pontos no modo desenhar, sem fixar ponto nem selecionar.
	if main != null:
		var h = main.domains  # o banco do Main é outro: cria a entidade nele
		h.open(int(h.registry.Create("pais", "País do Main")))
		var fixo_antes: Vector3 = main.selected_dir
		h.start_border("Pelo Main", "territorio", 0)
		main.select(EvronGeo.dir(1.0, 1.0))
		main.select(EvronGeo.dir(1.0, 3.0))
		if h._draw_pts.size() != 2 or main.selected_dir != fixo_antes:
			return fail("Main.select no modo desenhar marca pontos e não fixa o ponto (pontos=%d)" % h._draw_pts.size())
		h.draw_cancel()
		main.select(EvronGeo.dir(1.0, 1.0))
		if main.selected_dir == fixo_antes and fixo_antes != EvronGeo.dir(1.0, 1.0):
			return fail("fora do modo desenhar o clique volta a fixar o ponto")
		ok("com a cena: Main.select marca pontos no modo desenhar e volta a fixar o ponto depois")

		if DisplayServer.get_name() != "headless":  # a captura: dois países vizinhos, uma etnia em L, um desenho em andamento
			var r2 = h.registry
			var a: int = r2.Create("pais", "Aren")
			var b: int = r2.Create("pais", "Dravia")
			var e: int = r2.Create("etnia", "Povo do L")
			r2.AddPresence(a, r2.AddPolygonPlace("Território de Aren", "regiao", PackedFloat64Array([4, 14, 7, 20, 12, 24, 14, 18, 12, 13, 8, 12]), ""), "territorio", "alta")
			r2.AddPresence(b, r2.AddPolygonPlace("Território de Dravia", "regiao", PackedFloat64Array([12, 24, 7, 20, 4, 24, 5, 30, 11, 31]), ""), "territorio", "alta")
			r2.AddPresence(e, r2.AddPolygonPlace("Vale em L", "regiao", PackedFloat64Array([8, 14, 8, 22, 10, 22, 10, 17, 13, 17, 13, 14]), ""), "presenca", "media")
			h.presence_panel._scope.select(1)
			h.presence_panel._scope.item_selected.emit(1)
			h.open(a)
			h.start_border("Nova fronteira", "reivindicacao", 0)
			for p in [[15, 28], [17, 33], [13, 36], [9, 34]]:
				h.draw_click(EvronGeo.dir(p[0], p[1]), 0.0)
			main.globe.focus(EvronGeo.dir(10.0, 24.0), 1.55)
			host.visible = false  # os painéis soltos deste teste não entram na foto do Main
			sheet.visible = false
			h.sheet.hide_sheet()
			await save("fronteiras_mapa")
			h.draw_cancel()

	hub.focus_map = Callable()
	hub.close()
	host.queue_free()


func _texts(node: Node, out: Array) -> void:
	if node is Label:
		out.append(node.text)
	for c in node.get_children():
		_texts(c, out)
