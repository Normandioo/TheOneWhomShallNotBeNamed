extends "res://tests/test_suite.gd"
## O globo na tela: camadas e legenda, a entrada do mouse pelo caminho de verdade, o clique que acerta lat/lon
## e a leitura do cursor. Salva capturas das camadas principais.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")

const CENTER := Vector2(640.0, 360.0)


func run() -> void:
	var cam = main.globe.camera
	cam.look_at_dir(EvronGeo.dir(20.0, 0.0), 3.0)
	await save("1_satelite")

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
	var text: String = main.layer_panel._cursor.text
	if not text.contains("Lat 20,") or not text.contains("Altitude"):
		return fail("o cursor no centro deveria mostrar lat 20° e a altitude: %s" % text)
	await send(motion(Vector2(5, 5), Vector2(1, 0)))
	if main.layer_panel._cursor.text != "Fora do planeta.":
		return fail("o canto da tela está fora do planeta: %s" % main.layer_panel._cursor.text)
	ok("cursor: lat/lon e altitude sob o mouse")

	# De perto: a câmera chega a poucos km do chão sem atravessar o planeta.
	main.set_layer(0)
	cam.look_at_dir(EvronGeo.dir(10.0, 30.0), 1.01)
	await save("3_perto")
	if main.globe.camera_altitude_km() > 100.0:
		return fail("a 1,01 raio a câmera deveria estar a ~83 km do chão")
	ok("vista de perto a %.0f km do chão" % main.globe.camera_altitude_km())


func _layer_index(menu: String) -> int:
	for i in MapLayers.LAYERS.size():
		if MapLayers.LAYERS[i]["menu"] == menu:
			return i
	return -1
