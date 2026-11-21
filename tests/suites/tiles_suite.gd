extends "res://tests/test_suite.gd"
## O relevo de 16K em blocos: de longe só os níveis grossos, de perto o nível mais detalhado; o cache fica no limite
## num sobrevoo; mede a memória de vídeo, a memória do processo e o tempo até o detalhe chegar.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")
const TileLayer = preload("res://scripts/view/tile_layer.gd")


func run() -> void:
	var cam = main.globe.camera
	var tiles = main.globe.tiles
	for i in MapLayers.LAYERS.size():
		if MapLayers.LAYERS[i].get("tiles", "") == "relevo":
			main.set_layer(i)
	if tiles.name_id != "relevo" or tiles.loaded_count() < 2:
		return fail("a camada de 16K deveria abrir a pirâmide com o nível 0 carregado")

	# De longe: o planeta inteiro cabe na tela com os níveis grossos.
	cam.look_at_dir(EvronGeo.dir(20.0, 0.0), 3.0)
	await _settle()
	# O nível desce quando 1 texel passa de DETAIL pixels na tela: na janela de referência (1080p) o planeta inteiro chega ao nível 3;
	# numa janela de 720p, ao 2.
	var far_limit := 3 if tree.root.get_visible_rect().size.y > 720.0 else 2
	if tiles.max_drawn_level() > far_limit:
		return fail("de longe não deveria passar do nível %d, está no %d" % [far_limit, tiles.max_drawn_level()])
	await save("6_blocos_longe")
	ok("de longe: nível %d, %d blocos na tela" % [tiles.max_drawn_level(), tiles.drawn.size()])

	# De perto: chega ao nível mais detalhado (4 = 16K) em pouco tempo.
	var t0 := Time.get_ticks_msec()
	var mountains := EvronGeo.dir(33.0, -39.0)  # cordilheira: onde a diferença de resolução aparece
	cam.look_at_dir(mountains, 1.03)
	await _settle()
	var ms := Time.get_ticks_msec() - t0
	if tiles.max_drawn_level() != tiles.levels - 1:
		return fail("a 1,03 raio deveria chegar ao nível %d, ficou no %d" % [tiles.levels - 1, tiles.max_drawn_level()])
	await save("7_blocos_perto")
	var layer: int = main.layer
	main.set_layer(layer + 1)  # "Elevação (cores do Gleba)": a mesma paleta em 4K, para comparar
	await save("7_mesmo_ponto_em_4k")
	main.set_layer(layer)
	await _settle()
	ok("de perto: nível %d em %d ms (%d blocos na tela, %d na memória)" % [tiles.max_drawn_level(), ms, tiles.drawn.size(), tiles.loaded_count()])

	# Sobrevoo: o cache não passa do limite, e cada parada chega ao detalhe.
	for p in [[35.0, 70.0], [10.0, 110.0], [-20.0, 150.0], [-45.0, -170.0], [5.0, -120.0], [60.0, -60.0], [80.0, 0.0]]:
		cam.look_at_dir(EvronGeo.dir(p[0], p[1]), 1.03)
		await _settle()
		if tiles.loaded_count() > TileLayer.MAX_CACHE:
			return fail("cache passou do limite: %d blocos" % tiles.loaded_count())
	ok("sobrevoo por 7 pontos: %d blocos na memória (limite %d), ~%.0f MiB de vídeo" % [
		tiles.loaded_count(), TileLayer.MAX_CACHE, tiles.gpu_mib()])
	print("memória do processo: %.0f MiB · texturas (Godot): %.0f MiB" % [
		OS.get_static_memory_usage() / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])

	# Voltar para uma camada comum fecha a pirâmide e solta a memória.
	main.set_layer(0)
	if tiles.loaded_count() != 0:
		return fail("trocar de camada deveria soltar os blocos")
	ok("trocar de camada solta os blocos")

	if FileAccess.file_exists(TileLayer.ROOT + "natural_satellite/manifest.json"):
		await _satellite()


func _satellite() -> void:
	var cam = main.globe.camera
	var tiles = main.globe.tiles
	for i in MapLayers.LAYERS.size():
		if MapLayers.LAYERS[i].get("tiles", "") == "natural_satellite":
			main.set_layer(i)
			break
	if main.material.layer_file != "natural_satellite.png" or tiles.name_id != "natural_satellite" or tiles.levels != 4:
		return fail("satélite experimental deveria abrir a composição 8K com sua pirâmide PNG")
	if main.material._satellite_optics == null or main.material._satellite_river_atlas == null:
		return fail("satélite deveria carregar a máscara de águas e os trechos dos rios")
	if tiles._load_image("0/0/0").get_size() != Vector2i(516, 516):
		return fail("satélite deveria carregar mosaicos com margem de costura")
	main.material.show_political(false)
	var hud := main.get_node("Hud") as Control
	hud.hide()
	cam.look_at_dir(EvronGeo.dir(18, -28), 3.45)
	await _settle()
	await save("satelite-exp-orbita")
	cam.look_at_dir(EvronGeo.dir(-26, -114), 1.13)
	await _settle()
	if tiles.max_drawn_level() != tiles.levels - 1:
		return fail("a aproximação deveria ativar o nível mais detalhado do satélite")
	await save("satelite-exp-costa")
	if not await _check_river_center():
		return
	if not await _check_river_repairs():
		return
	# A rotação de irmãos no cache causava flashes neste enquadramento polar.
	cam.look_at_dir(EvronGeo.dir(84.0, 179.7), 1.45)
	await _settle()
	var polar_tiles: Array[String] = tiles.drawn.duplicate()
	for frame in 12:
		await frames(1)
		if tiles.drawn != polar_tiles or not tiles._loading.is_empty() or tiles.loaded_count() > TileLayer.MAX_CACHE:
			return fail("os blocos perto do polo devem estabilizar sem exceder o cache")
	cam.look_at_dir(EvronGeo.dir(73, 179.5), 1.46)
	await _settle()
	await save("satelite-exp-polar")
	hud.show()
	main.material.show_political(true)
	main.set_layer(0)
	if tiles.name_id != "" or tiles.loaded_count() != 0:
		return fail("trocar de camada deveria soltar os blocos do satélite")
	if main.material._satellite_optics != null or main.material._satellite_river_atlas != null:
		return fail("a camada inativa não deve manter o atlas de rios nem a máscara de águas")
	ok("satélite 8K: água, rios, aproximação por blocos PNG e retorno ao mapa base")


func _check_river_center() -> bool:
	var cam = main.globe.camera
	cam.look_at_dir(EvronGeo.dir(-28.08580756, -114.67028260), 1.012)
	await _settle()
	if await _river_contrast(cam.cam.get_viewport()) < 0.03:
		fail("o eixo reconstruído do curso principal precisa aparecer no satélite")
		return false
	await save("satelite-curso-principal")
	# No mapa de rios, este afluente tem fluxo inferior ao corte de 0,60 usado antes.
	cam.look_at_dir(EvronGeo.dir(-23.203125, -112.2802734375), 1.0022)
	await _settle()
	if await _river_contrast(cam.cam.get_viewport()) < 0.03:
		fail("o afluente de baixo fluxo indicado no mapa de rios precisa aparecer de perto")
		return false
	await save("satelite-afluente-mapeado")
	ok("o satélite mostra o curso principal e o afluente recuperado do mapa de rios")
	return true


func _river_contrast(viewport: Viewport) -> float:
	var with_river := await _center_color(viewport)
	RenderingServer.global_shader_parameter_set("satellite_rivers_on", 0.0)
	var without_river := await _center_color(viewport)
	RenderingServer.global_shader_parameter_set("satellite_rivers_on", 1.0)
	var delta := Vector3(with_river.r - without_river.r, with_river.g - without_river.g, with_river.b - without_river.b)
	return delta.length()


func _check_river_repairs() -> bool:
	var cam = main.globe.camera
	cam.look_at_dir(EvronGeo.dir(21.52, 100.79), 1.037)
	await _settle()
	await save("satelite-ligacao-restaurada")
	# A primeira falha é a da captura do usuário. A última exigiu ligar uma lacuna dos dados de origem.
	var repaired := [Vector2(21.505507, 100.796194), Vector2(5.612512, -111.079113), Vector2(-6.063766, 108.500977)]
	for place: Vector2 in repaired:
		cam.look_at_dir(EvronGeo.dir(place.x, place.y), 1.012)
		await _settle()
		if await _river_contrast(cam.cam.get_viewport()) < 0.03:
			fail("o curso deveria ser contínuo no ponto reparado: %s" % place)
			return false
	ok("três trechos antes interrompidos aparecem no satélite")
	return true


func _center_color(viewport: Viewport) -> Color:
	await frames(3)
	await RenderingServer.frame_post_draw
	var surface := viewport.get_texture().get_image()
	return surface.get_pixelv(surface.get_size() / 2)


## Espera os blocos pedidos chegarem (até 5 s): o quadro seguinte já não pede nada novo.
func _settle() -> void:
	var tiles = main.globe.tiles
	for i in 300:
		await frames(1)
		if tiles._loading.is_empty() and tiles._ready_images.is_empty():
			await frames(2)
			if tiles._loading.is_empty():
				return
