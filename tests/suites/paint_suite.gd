extends "res://tests/test_suite.gd"
## O pincel de território pela interface: a seção Território da ficha, a barra do modo pintar (pincel, balde, borracha, raio, "só em terra"), as pinceladas e o
## desfazer, a cor do país e a paleta, o que é gravado no banco, o clique que seleciona o dono e a exclusão do país. Terreno sintético pequeno (256 × 128).
## As linhas "ERROR" das recusas do C# são esperadas.

const SearchPanel = preload("res://scripts/ui/search_panel.gd")
const SheetPanel = preload("res://scripts/ui/sheet_panel.gd")
const CalendarPanel = preload("res://scripts/ui/calendar_panel.gd")
const PresencePanel = preload("res://scripts/ui/presence_panel.gd")
const DrawPanel = preload("res://scripts/ui/draw_panel.gd")
const TerritoryPanel = preload("res://scripts/ui/territory_panel.gd")
const PlaceLayer = preload("res://scripts/view/place_layer.gd")
const DomainHub = preload("res://scripts/app/domain_hub.gd")
const PlaceDrawing = preload("res://scripts/app/place_drawing.gd")
const TerritoryEditor = preload("res://scripts/app/territory_editor.gd")
const CommandStack = preload("res://scripts/edit/command_stack.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")

const W := 256
const H := 128

var hub
var terr  # o TerritoryEditor ligado ao hub
var drawer  # o PlaceDrawing
var reg
var sheet
var search
var presence
var map
var tpanel
var dpanel
var stack
var terrain
var territory
var host: Control
var palettes: Array = []
var painting_events: Array = []


func _make_terrain() -> Object:
	var img := Image.create(W, H, false, Image.FORMAT_RF)
	for y in H:
		for x in W:
			img.set_pixel(x, y, Color(-100.0 if x >= 107 and x < 149 else 100.0, 0, 0, 1))  # mar no meio, terra nos lados
	var t = load("res://scripts/world/Terrain.cs").new()
	t.Setup(img)
	return t


func _build(db_path: String) -> void:
	host = Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	search = SearchPanel.new()
	sheet = SheetPanel.new()
	presence = PresencePanel.new()
	map = PlaceLayer.new()
	map.radius = 6.371
	dpanel = DrawPanel.new()
	tpanel = TerritoryPanel.new()
	var cal := CalendarPanel.new()
	for n in [search, sheet, cal, presence, map, dpanel, tpanel]:
		host.add_child(n)
	terrain = _make_terrain()
	territory = load("res://scripts/world/Territory.cs").new()
	territory.Setup(terrain)
	stack = CommandStack.new()
	hub = DomainHub.new()
	hub.setup(db_path, search, sheet, cal)
	hub.bind_map(map, presence, func(_d: Vector3, _z: float) -> void: pass)
	drawer = PlaceDrawing.new()
	drawer.setup(hub, dpanel)
	terr = TerritoryEditor.new()
	terr.palette_changed.connect(func(entries: Array) -> void: palettes.append(entries))
	terr.painting_changed.connect(func(on: bool) -> void: painting_events.append(on))
	terr.setup(hub, territory, stack, tpanel)
	reg = hub.registry
	await frames(2)


func _close() -> void:
	hub.focus_map = Callable()
	for sig in [terr.palette_changed, terr.painting_changed]:  # os callbacks capturam esta suíte: soltar para não deixar um ciclo
		for c in sig.get_connections():
			sig.disconnect(c.callable)
	hub.close()
	host.queue_free()
	await frames(2)


func _button(text: String) -> Button:
	return _find_button(sheet, text)  # as ações de território ficam na barra abaixo do cabeçalho, fora do corpo das abas


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for c in node.get_children():
		var f := _find_button(c, text)
		if f != null:
			return f
	return null


func _texts(node: Node, out: Array) -> Array:
	if node is Label:
		out.append(node.text)
	for c in node.get_children():
		_texts(c, out)
	return out


func _stroke(lat: float, lon: float, steps: int = 6, dlon: float = 3.0) -> void:
	terr.territory_begin(EvronGeo.dir(lat, lon))
	for i in range(1, steps):
		terr.territory_drag(EvronGeo.dir(lat, lon + dlon * i))
	terr.territory_end()


func run() -> void:
	var path := out_dir.path_join("paint_suite.db")
	for ext in ["", "-journal"]:
		DirAccess.remove_absolute(path + ext)
	await _build(path)

	var aren: int = reg.Create("pais", "Aren")
	var dravia: int = reg.Create("pais", "Dravia")
	var povo: int = reg.Create("etnia", "Povo")
	hub.open(aren)
	if palettes.is_empty() or palettes.back().map(func(e): return e.id).has(povo) or palettes.back().size() < 2:
		return fail("a paleta deveria ter só os países: %s" % [palettes.back() if not palettes.is_empty() else []])
	var botao := _button("Pintar território")
	if botao == null or botao.disabled or _button("Apagar território") == null or not _button("Apagar território").disabled:
		return fail("a ficha do país tem 'Pintar território' e 'Apagar território' (desligado sem território)")
	hub.open(povo)
	if _button("Pintar território") != null:
		return fail("só país tem território")
	hub.open(aren)
	ok("a ficha do país tem a seção Território (pintar; apagar desligado sem área); outros tipos não; a paleta só tem países")

	# Entrar no modo, pintar uma pincelada, desfazer e refazer pela mesma pilha do terreno.
	botao.pressed.emit()
	if not terr.painting_territory or not tpanel.visible or terr.territory_owner != aren or not tpanel._title.text.contains("Aren") or painting_events != [true]:
		return fail("pintar território abre a barra para o país")
	tpanel.radius_changed.emit(1500.0)
	_stroke(0, 70)
	var area: float = territory.AreaKm2(aren)
	if area < 1.0e7 or not stack.can_undo() or not stack.undo_name().begins_with("Pintar território") or not tpanel._area.text.contains("km²"):
		return fail("uma pincelada de 1500 km arrastada vira UM comando e a área aparece (%.0f km²; desfazer='%s')" % [area, stack.undo_name()])
	stack.undo()
	if territory.AreaKm2(aren) != 0.0 or not tpanel._area.text.contains("Ainda sem território"):
		return fail("desfazer tira a pincelada e a barra atualiza a área (área=%s, barra='%s', pilha=%s, redo=%s)" % [territory.AreaKm2(aren), tpanel._area.text, stack._undo.map(func(c): return c.name), stack._redo.map(func(c): return c.name)])
	stack.redo()
	if absf(territory.AreaKm2(aren) - area) > 1e-6:
		return fail("refazer devolve a mesma pincelada")
	ok("modo pintar: raio 1500 km, pincelada arrastada = 1 comando (%.0f km²), desfazer e refazer com a barra atualizando" % area)

	# Só em terra liga/desliga pela barra; o balde preenche uma área cercada; a borracha só apaga o país da barra.
	if territory.OwnerAt(EvronGeo.dir(0, 0)) != 0:
		return fail("o mar do meio não deveria ter dono (só em terra ligado)")
	tpanel.land_only_changed.emit(false)
	_stroke(0, -20, 2, 3.0)   # agora pinta o mar também
	if territory.OwnerAt(EvronGeo.dir(0, -20)) != aren:
		return fail("com 'só em terra' desligado o pincel pinta o mar")
	tpanel.land_only_changed.emit(true)
	stop_all()
	terr.start_painting(dravia)
	tpanel.radius_changed.emit(1000.0)
	tpanel.mode_changed.emit("pincel")
	_stroke(5, 80, 3, 3.0)   # Dravia toma uma faixa do território de Aren
	var de_dravia: float = territory.AreaKm2(dravia)
	if de_dravia <= 0.0 or territory.OwnerAt(EvronGeo.dir(5, 80)) != dravia or territory.AreaKm2(aren) >= area + 1.0e7:
		return fail("pintar sobre outro país toma o território dele")
	tpanel.mode_changed.emit("borracha")
	_stroke(0, 80, 6, 3.0)   # a borracha de Dravia passa por cima de Aren e de Dravia
	var aren_depois: float = territory.AreaKm2(aren)
	if territory.AreaKm2(dravia) >= de_dravia or aren_depois <= 0.0:
		return fail("a borracha apaga só o território de quem está na barra (Dravia), e o de Aren fica")
	terr.stop_painting()
	ok("só em terra pela barra; conquista (pintar sobre outro país) e borracha só do país da barra")

	# O balde dentro de um anel feito com o pincel.
	terr.start_painting(dravia)
	tpanel.mode_changed.emit("pincel")
	tpanel.radius_changed.emit(300.0)
	for i in 36:
		var a := TAU * i / 36.0
		terr.territory_begin(EvronGeo.dir(35.0 * 0.5 * sin(a) + 35.0, 150.0 + 18.0 * cos(a)))
		terr.territory_end()
	tpanel.mode_changed.emit("balde")
	var antes := float(territory.AreaKm2(dravia))
	terr.territory_begin(EvronGeo.dir(35.0, 150.0))
	if territory.AreaKm2(dravia) <= antes * 1.3 or territory.OwnerAt(EvronGeo.dir(35.0, 150.0)) != dravia or territory.OwnerAt(EvronGeo.dir(70.0, 150.0)) != 0:
		return fail("o balde preenche dentro do anel (%.0f -> %.0f km²) e não vaza" % [antes, territory.AreaKm2(dravia)])
	stack.undo()
	if territory.OwnerAt(EvronGeo.dir(35.0, 150.0)) != 0:
		return fail("o balde desfaz como um comando")
	terr.stop_painting()
	ok("o balde preenche o interior do anel e desfaz como um comando")

	# Fronteiras naturais pela barra: crescer a partir da capital do cadastro, crescer todos, assentar; tudo é comando.
	var sem_terra: int = reg.Create("pais", "Sem Terra")
	terr.start_painting(sem_terra)
	tpanel.grow_requested.emit(false)
	if territory.AreaKm2(sem_terra) != 0.0 or not tpanel._message.visible:
		return fail("sem território nem capital não há de onde crescer, e a barra avisa")
	reg.AddPresence(sem_terra, reg.AddPlace("Porto Capital", "assentamento", -40.0, 150.0, 0.0, ""), "capital", "media")
	tpanel.reach_changed.emit(1500.0)
	tpanel.grow_requested.emit(false)
	var cresceu := float(territory.AreaKm2(sem_terra))
	if cresceu <= 0.0 or territory.OwnerAt(EvronGeo.dir(-40.0, 150.0)) != sem_terra or territory.OwnerAt(EvronGeo.dir(-40.0, 10.0)) != 0 \
			or not stack.undo_name().begins_with("Crescer território") or tpanel._message.visible or not tpanel._area.text.contains("km²"):
		return fail("crescer a partir da capital (%.0f km², pilha '%s', dono no pixel da capital %d, capitais %s, t %d)" % [cresceu, stack.undo_name(), territory.OwnerAt(EvronGeo.dir(-40.0, 150.0)), reg.MapItems(PackedStringArray(["politica"]), 0, hub.shown_t).map(func(i): return [i.entity, i.role]), hub.shown_t])
	tpanel.snap_requested.emit()
	if not tpanel._message.visible or not stack.undo_name().begins_with("Crescer território"):
		return fail("assentar sem vizinho avisa e não cria comando")
	var de_dravia_antes := float(territory.AreaKm2(dravia))
	tpanel.grow_requested.emit(true)
	if not stack.undo_name().begins_with("Crescer todos") or territory.AreaKm2(dravia) <= de_dravia_antes:
		return fail("crescer todos: Dravia também cresce (%.0f -> %.0f)" % [de_dravia_antes, territory.AreaKm2(dravia)])
	stack.undo()
	stack.undo()
	if territory.AreaKm2(sem_terra) != 0.0 or absf(territory.AreaKm2(dravia) - de_dravia_antes) > 1e-6:
		return fail("desfazer os dois crescimentos")
	terr.stop_painting()
	ok("fronteiras naturais pela barra: sem origem avisa; cresce da capital (%.0f km²) sem pintar o mar; assentar sem vizinho avisa; crescer todos; desfaz" % cresceu)

	# Esc termina; a ficha mostra a área.
	terr.start_painting(aren)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	tpanel._unhandled_key_input(esc)
	if terr.painting_territory or tpanel.visible or painting_events.back() != false:
		return fail("Esc termina o modo pintar")
	hub.open(aren)
	if not "\n".join(_texts(sheet._body, [])).contains("km² pintados"):
		return fail("a ficha mostra a área pintada")
	if _button("Apagar território").disabled:
		return fail("com território, 'Apagar território' liga")
	_button("Apagar território").pressed.emit()
	if territory.AreaKm2(aren) != 0.0 or not stack.undo_name().begins_with("Apagar território"):
		return fail("apagar o território do país é um comando")
	stack.undo()
	if territory.AreaKm2(aren) <= 0.0:
		return fail("desfazer o apagar")
	ok("Esc termina; a ficha mostra a área; 'Apagar território' é um comando que desfaz")

	# Não pinta durante o desenho de fronteira por contorno; só país pinta.
	drawer.start_border("Região", "territorio", 0)
	terr.start_painting(aren)
	if terr.painting_territory:
		return fail("não se pinta território durante o desenho de contorno")
	drawer.draw_cancel()
	terr.start_painting(povo)
	if terr.painting_territory:
		return fail("uma etnia não pinta território")
	ok("não pinta durante o desenho de contorno nem para uma etnia")

	# A cor do país: a prévia vai para a paleta, só o "final" grava no banco.
	hub.open(aren)
	var n_pal := palettes.size()
	sheet.entity_color_changed.emit(aren, 0x112233, false)
	var ultima: Array = palettes.back()
	var minha: Dictionary = ultima.filter(func(e): return e.id == aren)[0]
	if palettes.size() != n_pal + 1 or minha.rgb != 0x112233 or reg.EntityColor(aren) == 0x112233:
		return fail("a prévia da cor entra na paleta sem gravar no banco")
	sheet.entity_color_changed.emit(aren, 0x112233, true)
	if reg.EntityColor(aren) != 0x112233:
		return fail("o final grava a cor")
	ok("cor do país: a prévia atualiza a paleta, o final grava no banco")

	# O clique seleciona o dono do pixel (camada política ligada); sem a camada, não.
	presence._scope.select(1)
	presence._scope.item_selected.emit(1)
	hub.open(dravia)
	var n_achados: int = hub.pick(EvronGeo.dir(0, 70), 0.0)
	if n_achados != 1 or hub.current() != aren:
		return fail("o clique no território de Aren abre Aren (achados=%d, ficha=%d)" % [n_achados, hub.current()])
	presence._checks["politica"].button_pressed = false
	if hub.pick(EvronGeo.dir(0, 70), 0.0) != 0:
		return fail("sem a camada política o clique não acha o território")
	presence._checks["politica"].button_pressed = true
	ok("o clique no território abre o país dono do pixel; sem a camada, não")

	# Gravar: com atraso (~1,5 s) e ao fechar; reabrir lê a camada e a cor.
	if territory.Version == terr._territory_saved["pais"]:
		return fail("há edições ainda não gravadas")
	hub.tick()
	if territory.Version == terr._territory_saved["pais"]:
		return fail("a camada não deveria ser gravada logo depois da edição")
	terr._territory_changed_ms -= 2000
	hub.tick()
	if territory.Version != terr._territory_saved["pais"]:
		return fail("passado o atraso o tick grava a camada")
	var area_aren := float(territory.AreaKm2(aren))
	await _close()
	await _build(path)   # um mundo novo, lendo o mesmo arquivo
	if absf(territory.AreaKm2(aren) - area_aren) > 1e-6 or reg.EntityColor(aren) != 0x112233:
		return fail("reabrir conserva o território (%.0f) e a cor" % territory.AreaKm2(aren))
	ok("a camada é gravada ~1,5 s depois da edição e ao fechar; reabrir lê o território e a cor")

	# Excluir o país apaga o território dele e o tira da paleta.
	hub.open(aren)
	sheet.delete_confirmed.emit()
	if territory.AreaKm2(aren) != 0.0 or territory.OwnerAt(EvronGeo.dir(0, 70)) != 0 or palettes.back().any(func(e): return e.id == aren):
		return fail("excluir o país tira o território e a cor da paleta")
	ok("excluir o país apaga o território dele e o tira da paleta")

	# Com a cena: o shader desenha as cores e a borda do território do Main.
	if main != null:
		var h = main.domains
		var r2 = h.registry
		var a: int = r2.Create("pais", "Terra do Norte")
		var b: int = r2.Create("pais", "Reino do Sul")
		var c: int = r2.Create("pais", "Ilhas")
		h.open(a)
		for p in [[a, 22, 14, 6], [a, 22, 20, 6], [b, 22, 36, 6], [b, 22, 42, 6], [c, 34, 28, 3]]:  # dois países que se tocam e uma ilha à parte
			main.territories.start_painting(p[0])
			main.territories.territory_radius = 800.0 if p[0] != c else 450.0
			main.territories.territory_land_only = false
			main.territories.territory_begin(EvronGeo.dir(p[1], p[2]))
			main.territories.territory_drag(EvronGeo.dir(p[1], p[2] + p[3]))
			main.territories.territory_end()
			main.territories.stop_painting()
		await frames(3)
		if main.territory.Dirty:
			return fail("o Main deveria levar a camada política à GPU")
		if DisplayServer.get_name() != "headless":
			host.visible = false
			h.sheet.hide_sheet()
			main.globe.focus(EvronGeo.dir(24.0, 28.0), 1.6)
			await save("territorio_mapa")
			if not await _check_visibility():
				return
		ok("com a cena: o Main leva a camada à GPU e desenha os países")

		# Com os mapas reais: as capitais do protótipo (tools/mapa_politico.py, vista "oeste") crescem juntas pelas serras e rios do Gleba.
		var caps := [[18.1, -112.0], [19.6, -107.5], [28.3, -112.0], [38.7, -107.0], [16.7, -116.1], [20.1, -96.7], [26.9, -129.0],
			[41.9, -129.1], [24.6, -100.2], [43.5, -116.1], [28.9, -105.2], [38.2, -119.8], [18.6, -126.8]]
		var first := 0
		for i in caps.size():
			var id: int = r2.Create("pais", "País %d" % (i + 1))
			r2.AddPresence(id, r2.AddPlace("Capital %d" % (i + 1), "assentamento", caps[i][0], caps[i][1], 0.0, ""), "capital", "media")
			first = id if first == 0 else first
		main.territories.start_painting(first)
		main.territories.territory_reach = 1500.0
		var t0 := Time.get_ticks_msec()
		main.territories.territory_grow(true)
		var ms := Time.get_ticks_msec() - t0
		main.territories.stop_painting()
		var vazios := 0
		for i in caps.size():
			vazios += 1 if main.territory.AreaKm2(first + i) <= 0.0 else 0
		if not main.commands.undo_name().begins_with("Crescer todos") or vazios > 0 or ms > 20000:
			return fail("crescer todos nos mapas reais: %d países sem terra, %d ms, pilha '%s'" % [vazios, ms, main.commands.undo_name()])
		await frames(3)
		if DisplayServer.get_name() != "headless":
			h.sheet.hide_sheet()  # stop_painting reabriu a ficha
			main.globe.focus(EvronGeo.dir(30.6, -111.6), 1.9)
			await save("fronteiras_naturais")
		ok("com os mapas reais: %d capitais crescem juntas em %d ms (todos ganham terra)" % [caps.size(), ms])

		# O mapa político (modo 4): a costa é calculada quando a camada aparece; capturas de longe e de perto.
		var camada_antes: int = main.layer
		for i in MapLayers.LAYERS.size():
			if MapLayers.LAYERS[i]["kind"] == "political":
				main.set_layer(i)
		await frames(2)
		for _i in 100:  # a costa é calculada numa thread (~1 s)
			if not main.gpu_sync.coast_pending():
				break
			await frames(2)
		if main.gpu_sync.coast_pending() or main.material.coast_texture == null:
			return fail("com o mapa político na tela, a costa é calculada")
		var t1 := Time.get_ticks_msec()
		main.terrain.CoastImage()
		var costa_ms := Time.get_ticks_msec() - t1
		if costa_ms > 2000:
			return fail("a costa do mapa de 4K deveria sair em menos de 2 s (recalculada a cada edição de terreno): %d ms" % costa_ms)
		if DisplayServer.get_name() != "headless":
			main.globe.focus(EvronGeo.dir(30.6, -111.6), 1.9)
			await save("mapa_politico")
			main.globe.focus(EvronGeo.dir(24.0, -108.0), 1.25)
			await save("mapa_politico_perto")
		main.set_layer(camada_antes)
		main.commands.undo()  # o crescimento ("Crescer todos") também fez crescer os países pintados acima: as suítes seguintes partem do mapa de antes
		ok("mapa político: a costa do mapa de 4K sai em %d ms e a camada desenha os países" % costa_ms)

	await _close()


func _check_visibility() -> bool:
	var menu: CheckBox = main.layer_panel._countries
	var presence_check: CheckBox = main.domains.presence_panel._checks["politica"]
	var previous_layer: int = main.layer
	main.globe.focus(EvronGeo.dir(22.0, 20.0), 1.18)
	main.set_layer(0)
	menu.button_pressed = true
	var visible := await _map_color()
	menu.button_pressed = false
	var hidden := await _map_color()
	if presence_check.button_pressed or not _color_changed(visible, hidden):
		fail("Mostrar países deve ocultar o raster no globo e desmarcar Fronteira política")
		return false

	if FileAccess.file_exists("res://data/evron/tiles/natural_satellite/manifest.json"):
		var map_layers = load("res://scripts/ui/map_layers.gd").LAYERS
		for i in map_layers.size():
			if map_layers[i].get("tiles", "") == "natural_satellite":
				main.set_layer(i)
				break
		var tiles = main.globe.tiles
		for frame in 180:
			await frames(1)
			if tiles.max_drawn_level() > 0 and tiles._loading.is_empty():
				break
		if menu.button_pressed or presence_check.button_pressed or tiles.max_drawn_level() < 1:
			fail("trocar para o satélite em mosaicos deve preservar a visibilidade desligada")
			return false
		hidden = await _map_color()
		presence_check.button_pressed = true
		visible = await _map_color()
		if not menu.button_pressed or not _color_changed(visible, hidden):
			fail("Fronteira política deve religar Mostrar países e o raster nos mosaicos")
			return false
	else:
		presence_check.button_pressed = true
	main.set_layer(previous_layer)
	ok("visibilidade dos países sincronizada entre os painéis, inclusive ao trocar de camada")
	return true


func _map_color() -> Color:
	await frames(3)
	await RenderingServer.frame_post_draw
	var viewport: Viewport = main.globe.camera.cam.get_viewport()
	var surface := viewport.get_texture().get_image()
	return surface.get_pixelv(surface.get_size() / 2)


func _color_changed(a: Color, b: Color) -> bool:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() > 0.035


func stop_all() -> void:
	terr.stop_painting()
