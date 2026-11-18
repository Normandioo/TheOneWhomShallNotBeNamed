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
	if tiles.max_drawn_level() > 2:
		return fail("de longe não deveria passar do nível 2, está no %d" % tiles.max_drawn_level())
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


## Espera os blocos pedidos chegarem (até 5 s): o quadro seguinte já não pede nada novo.
func _settle() -> void:
	var tiles = main.globe.tiles
	for i in 300:
		await frames(1)
		if tiles._loading.is_empty() and tiles._ready_images.is_empty():
			await frames(2)
			if tiles._loading.is_empty():
				return
