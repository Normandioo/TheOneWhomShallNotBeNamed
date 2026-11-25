extends "res://tests/test_suite.gd"
## Na cena: "Nova província" pela ficha do país (cria, liga e já pinta só dentro do país), a tela do modo província com os países por
## baixo, e pintar a área de uma religião na camada dela. Roda com a cena (argumento "scene").

const EvronGeo = preload("res://scripts/data/evron_geo.gd")


var c_lat := 0.0
var c_lon := 0.0


## Onde há mais terra (o mapa real é quase todo mar nos pontos fixos): os países do teste ficam ali.
func _land_center() -> void:
	var best := -1
	for lat in range(-40, 41, 10):
		for lon in range(-180, 180, 10):
			var n := 0
			for dy in range(-12, 13, 4):
				for dx in range(-24, 25, 4):
					if main.terrain.HeightAt(EvronGeo.dir(lat + dy, lon + dx)) >= 0.0:
						n += 1
			if n > best:
				best = n
				c_lat = lat
				c_lon = lon


func _d(lat: float, lon: float) -> Vector3:
	return EvronGeo.dir(c_lat + lat, c_lon + lon)


func run() -> void:
	_land_center()
	var hub = main.domains
	var terr = main.territories
	var reg = hub.registry
	var aren: int = reg.Create("pais", "Aren")
	var dravia: int = reg.Create("pais", "Dravia")
	for pair in [[aren, 20.0], [dravia, 60.0]]:
		main.territory.Begin()
		main.territory.Dab(_d(0, pair[1] - 40.0), 1500, pair[0], true, -1)
		main.territory.End()
	hub.open(aren)
	await frames(2)
	hub.sheet.subdivision_requested.emit()
	var prov: int = hub.current()
	if reg.Kind(prov) != "provincia" or reg.TerritoryParent(prov) != aren or not terr.painting_territory or terr.territory_level != "provincia":
		return fail("Nova província cria, liga ao país e abre o pincel no nível província")
	var shown: PackedByteArray = terr.political_image().get_data()
	var aren_px: int = main.terrain.PixelOf(_d(0, -20))
	if shown.decode_u16(aren_px * 2) != aren:
		return fail("no modo província o mapa ainda mostra os países (antes ficava vazio)")
	terr.territory_radius = 4000.0
	terr.territory_land_only = false  # o mapa real tem mar nesses pontos
	terr.territory_begin(_d(0, 0))
	terr.territory_end()
	var provinces = terr.layer("provincia")
	if provinces.OwnerAt(_d(0, -20)) != prov or provinces.OwnerAt(_d(0, 20)) != 0:
		return fail("a província pinta só dentro de Aren (Dravia fica de fora): %d %d %d" % [provinces.OwnerAt(_d(0, -20)), provinces.OwnerAt(_d(0, 20)), provinces.Pixels(prov)])
	shown = terr.political_image().get_data()
	if shown.decode_u16(aren_px * 2) != prov or shown.decode_u16(main.terrain.PixelOf(_d(0, 20)) * 2) != dravia:
		return fail("a tela mostra a província por cima e Dravia por baixo")
	terr.stop_painting()
	hub.open(aren)
	hub.sheet.subdivision_requested.emit()
	var prov2: int = hub.current()
	terr.territory_radius = 700.0
	terr.territory_begin(_d(3, -14))
	terr.territory_end()
	terr.stop_painting()
	if terr.layer("provincia").OwnerAt(_d(3, -14)) != prov2:
		return fail("uma segunda província dentro de Aren")
	# Estilo Europa Universalis: a província tem a cor do país (a paleta aponta a província para o país).
	var second = _id_of(hub, "provincia", prov)
	if terr.selection_changed.get_connections().is_empty() or terr._selected_top != aren:
		return fail("com a província aberta, o país dela fica selecionado no mapa: %d" % terr._selected_top)
	hub.open(aren)
	if terr._selected_top != aren:
		return fail("abrir o país o seleciona")
	# Modo por subdivisões: as províncias do país aberto ficam em cores próprias e os outros países, cinzas.
	var pal: Array = []
	terr.palette_changed.connect(func(entries: Array) -> void: pal.assign(entries))
	terr.set_subdivisions_view(true)
	var rgb_of := func(id: int) -> int:
		for e in pal:
			if int(e.id) == id:
				return int(e.rgb)
		return -1
	var gray_rgb: int = rgb_of.call(dravia)
	if pal.is_empty() or (gray_rgb >> 16) != ((gray_rgb >> 8) & 255) or rgb_of.call(prov) != int(reg.EntityColor(prov)):
		return fail("subdivisões: outro país cinza (%x) e a província na própria cor (%x)" % [gray_rgb, rgb_of.call(prov)])
	terr.set_subdivisions_view(false)
	if rgb_of.call(prov) != int(reg.EntityColor(aren)):
		return fail("sem o modo, a província volta à cor do país")
	if DisplayServer.get_name() != "headless":
		await _shots(hub, terr, aren)
	ok("Nova província: criada e ligada pela ficha, pinta só dentro do país, e o mapa mostra os países por baixo")

	# O caso relatado: país novo, contorno fechado em terra vazia com o pincel de fronteira. Parar o mouse mostra a prévia sem mudar
	# nada; soltar aplica; Terminar mantém (antes a prévia era descartada e o país ficava sem território).
	var fresh: int = reg.Create("pais", "Teste vazio")
	hub.open(fresh)
	terr.start_painting(fresh, "fronteira")
	var tool = terr.boundary_tool
	tool.land_only = false
	var ring := [[_d(8, 40), Vector2(0, 0)], [_d(8, 52), Vector2(120, 0)], [_d(-8, 52), Vector2(120, 120)], [_d(-8, 40), Vector2(0, 120)], [_d(7, 40.5), Vector2(4, 4)]]
	tool.press(ring[0][0], ring[0][1], 3000.0)
	for k in range(1, ring.size()):
		tool.drag(ring[k][0], ring[k][1])
	tool._moved_ms -= 1000  # o mouse parou
	tool.tick()
	if not tool.has_preview() or main.territory.AreaKm2(fresh) != 0.0:
		return fail("parar o mouse mostra a prévia e ainda não muda o mapa: " + terr.territory_panel._boundary_status.text)
	tool.release()
	if tool.has_preview() or main.territory.OwnerAt(_d(0, 46)) != fresh:
		return fail("soltar o mouse aplica o contorno")
	terr.territory_panel.finish_requested.emit()  # o botão Terminar
	if main.territory.OwnerAt(_d(0, 46)) != fresh or main.territory.AreaKm2(fresh) <= 0.0:
		return fail("Terminar com a prévia na tela confirma o contorno: o país fica com o território")
	main.undo()
	if main.territory.AreaKm2(fresh) != 0.0:
		return fail("Ctrl+Z desfaz o contorno confirmado pelo Terminar")
	main.redo()
	# Linha aberta em terra livre: sai da borda do país e volta a ela; o bolsão entre a linha e o território passa para o país.
	hub.open(fresh)
	terr.start_painting(fresh, "fronteira")
	tool.land_only = false
	var before_km2: float = main.territory.AreaKm2(fresh)
	var bulge := [[_d(-6, 47), Vector2(0, 0)], [_d(-6, 58), Vector2(80, 0)], [_d(6, 58), Vector2(80, 90)], [_d(6, 47), Vector2(0, 90)]]
	tool.press(bulge[0][0], bulge[0][1], 3000.0)
	for k in range(1, bulge.size()):
		tool.drag(bulge[k][0], bulge[k][1])
	tool.release()
	var deadline := Time.get_ticks_msec() + 10000
	while tool.applying and Time.get_ticks_msec() < deadline:
		await frames(1)
	if main.territory.OwnerAt(_d(0, 55)) != fresh or main.territory.AreaKm2(fresh) <= before_km2:
		return fail("a linha aberta pela terra livre amplia o país: " + terr.territory_panel._boundary_status.text)
	if main.territory.OwnerAt(_d(0, 62)) == fresh:
		return fail("só o bolsão entre a linha e o país, não o resto do mundo")
	# Terminar e trocar de ferramenta logo depois de soltar, com o plano ainda sendo calculado em segundo plano: o traço não se perde.
	for finish in ["terminar", "trocar_ferramenta"]:
		var lat_sign := 1.0 if finish == "terminar" else -1.0
		var area_before: float = main.territory.AreaKm2(fresh)
		terr.start_painting(fresh, "fronteira")
		tool.land_only = false
		var arm := [[_d(7.0 * lat_sign, 43), Vector2(0, 0)], [_d(14.0 * lat_sign, 43), Vector2(0, 80)],
				[_d(14.0 * lat_sign, 49), Vector2(80, 80)], [_d(7.0 * lat_sign, 49), Vector2(80, 0)]]
		tool.press(arm[0][0], arm[0][1], 3000.0)
		for k in range(1, arm.size()):
			tool.drag(arm[k][0], arm[k][1])
		tool.release()
		if not tool.applying:
			return fail("depois de soltar uma linha aberta o plano é calculado em segundo plano (%s)" % finish)
		if finish == "terminar":
			terr.stop_painting()
		else:
			terr._set_territory_mode("pincel")
			terr.stop_painting()
		if main.territory.AreaKm2(fresh) <= area_before or main.territory.OwnerAt(_d(11.0 * lat_sign, 46)) != fresh:
			return fail("%s durante o cálculo aplica o traço em vez de descartá-lo" % finish)
		main.undo()
		if main.territory.AreaKm2(fresh) != area_before:
			return fail("Ctrl+Z desfaz o traço aplicado por %s" % finish)
		main.redo()
	ok("Terminar e trocar de ferramenta durante o cálculo em segundo plano aplicam o traço (e Ctrl+Z desfaz)")
	terr.start_painting(fresh)
	terr.stop_painting()
	ok("país novo: contorno fechado em terra vazia (prévia ao parar o mouse, aplica ao soltar, Terminar mantém); linha aberta amplia por terra livre")

	var faith: int = reg.Create("religiao", "Fé do Sol")
	hub.open(faith)
	terr.start_painting(faith)
	if terr.territory_level != "religiao" or not terr.painting_territory:
		return fail("pintar uma religião abre a camada de religiões")
	terr.territory_begin(_d(5, -10))
	terr.territory_end()
	if terr.layer("religiao").OwnerAt(_d(5, -10)) != faith or main.territory.OwnerAt(_d(5, -10)) == faith:
		return fail("a religião fica na camada dela, sem mexer nos países")
	if not main.layer_panel._level.get_item_text(main.layer_panel.LEVELS.find("religiao")).begins_with("Religi"):
		return fail("o menu de camadas tem Religiões")
	terr.stop_painting()
	ok("área de religião pintada na camada própria; o menu de camadas tem Religiões, Culturas, Etnias, Raças e Idiomas")


func _id_of(_hub, _kind: String, id: int) -> int:
	return id


## Capturas para conferir o visual: o país selecionado com as províncias, no mapa político e na camada de satélite, e sem seleção.
func _shots(hub, terr, aren: int) -> void:
	var MapLayers = load("res://scripts/ui/map_layers.gd")
	var political := -1
	for i in MapLayers.LAYERS.size():
		if MapLayers.LAYERS[i]["menu"] == "Mapa político":
			political = i
	main.globe.focus(_d(0, -10), 1.9)
	hub.sheet.hide()
	main.hud.visible = false
	main.set_layer(political)
	await frames(30)
	await save("eu_mapa_politico_selecionado")
	main.set_layer(0)
	await frames(30)
	await save("eu_satelite_selecionado")
	hub._current = 0
	terr.refresh_selection()
	main.set_layer(political)
	await frames(30)
	await save("eu_mapa_politico_sem_selecao")
	main.hud.visible = true
