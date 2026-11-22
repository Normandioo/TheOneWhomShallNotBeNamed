extends "res://tests/test_suite.gd"
## O globo na tela: camadas e legenda, a entrada do mouse pelo caminho de verdade, o clique que acerta lat/lon
## e a leitura do cursor. Salva capturas das camadas principais.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")

var CENTER := Vector2.ZERO  # o centro da janela (a de referência é 1920 × 1080): definido em run()


func run() -> void:
	CENTER = tree.root.get_visible_rect().size * 0.5
	var cam = main.globe.camera
	cam.look_at_dir(EvronGeo.dir(20.0, 0.0), 3.0)
	await save("1_satelite")
	cam.look_at_dir(EvronGeo.dir(-24.0, -118.0), 1.35)  # rio grande atravessando um deserto
	await save("1_satelite_rio")

	# Cor natural (natural.png, 8K com mipmaps): longe, média distância e perto (detalhe procedural do shader).
	for i in MapLayers.LAYERS.size():
		if MapLayers.LAYERS[i]["kind"] == "natural":
			main.set_layer(i)
	var tex: Texture2D = main.material.material.get_shader_parameter("layer_linear")
	var base_width := 4096 if main.globe.tiles.name_id == "natural" else 8192
	if main.material.layer_file != "natural.png" or tex.get_width() != base_width or not tex.get_image().has_mipmaps():
		return fail("a cor natural deveria estar em %d px com mipmaps: %s %d" % [base_width, main.material.layer_file, tex.get_width()])
	cam.look_at_dir(EvronGeo.dir(20.0, 0.0), 3.0)
	await save("1_natural")
	cam.look_at_dir(EvronGeo.dir(-24.0, -118.0), 1.35)
	await save("1_natural_rio")
	cam.look_at_dir(EvronGeo.dir(80.0, 0.0), 2.2)  # gelo marinho: borda irregular, não um círculo
	await save("1_natural_polo")
	cam.look_at_dir(EvronGeo.dir(-12.5, -123.5), 1.04)  # cordilheira de ~8 km
	await save("1_natural_perto")
	cam.look_at_dir(EvronGeo.dir(-12.5, -123.5), 1.004)
	await save("1_natural_rente")
	if not main.material.material.get_shader_parameter("rivers_on"):
		return fail("os rios (tools/build_rivers.py) deveriam estar carregados na cor natural")
	cam.look_at_dir(EvronGeo.dir(-26.17, -117.22), 1.03)  # o rio grande do deserto: ~2,8 km de largura
	await save("1_natural_rio_perto")
	cam.look_at_dir(EvronGeo.dir(-26.17, -117.22), 1.003)
	await save("1_natural_rio_rente")
	ok("cor natural em 8K com mipmaps, rios com largura em metros")

	# Trocar de camada muda o material e a legenda.
	for want in ["Altitude (calibrada)", "Temperatura — janeiro", "Biomas"]:
		var i := _layer_index(want)
		main.set_layer(i)
		if main.legend._title.text != MapLayers.LAYERS[i]["title"]:
			return fail("a legenda deveria mostrar %s" % MapLayers.LAYERS[i]["title"])
		await save("2_" + want.get_slice(" ", 0).to_lower())
	if main.material.layer_file != "BiomasGleba.png":
		return fail("o material deveria estar com BiomasGleba.png, está com %s" % main.material.layer_file)
	ok("camadas: altitude, temperatura e biomas, com legenda")

	# As opções das sobreposições: a legenda liga e desliga; "Rios em destaque" liga o global do shader e solta os rios ao desligar.
	var panel = main.domains.presence_panel
	panel.legend_check.button_pressed = false
	if main.legend.visible:
		return fail("com a opção desligada a legenda deveria sumir")
	panel.legend_check.button_pressed = true
	if not main.legend.visible:
		return fail("com a opção ligada a legenda deveria voltar")
	if FileAccess.file_exists(EvronMaps.directory() + "rivers_indexed.rgbaf"):
		panel.rivers_check.button_pressed = true
		if not main.material._river_highlight or main.material._satellite_river_atlas == null:
			return fail("Rios em destaque deveria carregar os rios")
		panel.rivers_check.button_pressed = false
		if main.material._river_highlight or main.material._satellite_river_atlas != null:
			return fail("desligar Rios em destaque deveria soltar os rios")
	ok("sobreposições: legenda do mapa e rios em destaque ligam e desligam")

	# Roda do mouse aproxima e afasta; arrastar gira sem fixar ponto.
	var d0: float = cam.target_dist
	await send(wheel(MOUSE_BUTTON_WHEEL_UP))
	if cam.target_dist >= d0:
		return fail("a roda para cima deveria aproximar")
	await send(wheel(MOUSE_BUTTON_WHEEL_DOWN))
	main.select(Vector3.ZERO)
	var yaw0: float = cam.yaw
	await send(button(MOUSE_BUTTON_LEFT, true, CENTER))
	await send(motion(CENTER + Vector2(60, 0), Vector2(60, 0)))
	await send(button(MOUSE_BUTTON_LEFT, false, CENTER + Vector2(60, 0)))
	if cam.yaw == yaw0 or main.selected_dir != Vector3.ZERO:
		return fail("arrastar deveria girar a câmera sem fixar um ponto")
	ok("mouse: roda aproxima e afasta, arrastar gira")

	# O clique no centro cai no ponto que a câmera olha, inclusive perto do limite de longitude e do polo.
	for ref in [[20.0, 0.0], [-35.0, 179.5], [70.0, -120.0]]:
		cam.look_at_dir(EvronGeo.dir(ref[0], ref[1]), 2.0)
		await frames(2)
		await send(button(MOUSE_BUTTON_LEFT, true, CENTER))
		await send(button(MOUSE_BUTTON_LEFT, false, CENTER))
		var ll := EvronGeo.lat_lon(main.selected_dir)
		if absf(ll.x - ref[0]) > 0.3 or absf(wrapf(ll.y - ref[1], -180.0, 180.0)) > 0.3:
			return fail("clique no centro olhando %s deveria dar o mesmo ponto, deu %s" % [ref, ll])
	ok("o clique acerta lat/lon (inclusive em 179,5° e a 70°N)")

	# Cursor: passar o mouse mostra lat/lon e altitude; fora do planeta avisa.
	cam.look_at_dir(EvronGeo.dir(20.0, 0.0), 3.0)
	await frames(2)
	await send(motion(CENTER, Vector2(1, 0)))
	var text: String = main.status_bar._cursor.text
	if not text.contains("Lat 20,") or not text.contains("Altitude"):
		return fail("o cursor no centro deveria mostrar lat 20° e a altitude: %s" % text)
	await send(motion(Vector2(tree.root.size.x - 8.0, 60.0), Vector2(1, 0)))  # fora do planeta e dos painéis (a barra de cima ocupa o canto de cima)
	if main.status_bar._cursor.text != "Fora do planeta.":
		return fail("o canto da tela está fora do planeta: %s" % main.status_bar._cursor.text)
	ok("cursor: lat/lon e altitude sob o mouse")

	# De perto: a câmera chega a poucos km do chão sem atravessar o planeta.
	main.set_layer(0)
	cam.look_at_dir(EvronGeo.dir(10.0, 30.0), 1.01)
	await save("3_perto")
	if main.globe.camera_altitude_km() > 100.0:
		return fail("a 1,01 raio a câmera deveria estar a ~64 km do chão")
	ok("vista de perto a %.0f km do chão" % main.globe.camera_altitude_km())


func _layer_index(menu: String) -> int:
	for i in MapLayers.LAYERS.size():
		if MapLayers.LAYERS[i]["menu"] == menu:
			return i
	return -1
