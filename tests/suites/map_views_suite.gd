extends "res://tests/test_suite.gd"
## Marte na vista do espaço: colônias (marcador de longe, modelos de perto), mapa político e o clique que escolhe
## um ponto da superfície.

const MarsGeo = preload("res://scripts/data/mars_geo.gd")
const ColonyLayer = preload("res://scripts/view/colony_layer.gd")


func run() -> void:
	var here := MarsGeo.dir(-20.0, 60.0)
	main.planet.set_control("atmosphere", 0.7)
	main._process(3000.0)
	main.select(here)
	main.found_colony()
	main.set_map_mode(2)
	main.space.look_at_surface(here, 3.0)
	await save("4_politico")

	# A colônia: de longe só o marcador, de perto os modelos.
	main.set_map_mode(0)
	main.space.look_at_surface(here, 6.0)
	await frames(2)
	if main.colonies.showing_models():
		return fail("a 6 raios de Marte a colônia deveria ser só o marcador")
	main.space.look_at_surface(here, 1.6)
	await frames(2)
	if not main.colonies.showing_models():
		return fail("a 1,6 raio de Marte a colônia deveria mostrar os modelos")
	await save("5_colonia_perto")

	# A colônia fundada vira região do jogador, e o rival continua sem poder receber outra.
	if main.colonies.directions().size() != 1 or main.colonies.region_owner[MarsGeo.nearest_region(here)] != ColonyLayer.Owner.PLAYER:
		return fail("a colônia deveria ter sido fundada e a região ser do jogador")
	if not main.colonies.is_rival(MarsGeo.RIVAL_REGION):
		return fail("Elysium deveria ser do rival")
	ok("colônia fundada, marcador de longe e modelos de perto")

	# O clique no centro da tela, com Marte grande, cai no ponto que a câmera olha: a conta passa pela orientação
	# de Marte (eixo e rotação), então um erro de eixo ou de meridiano aparece aqui.
	for ref in [[-20.0, 60.0], [35.0, -110.0], [0.0, 0.0]]:
		main.space.look_at_surface(MarsGeo.dir(ref[0], ref[1]), 3.0)
		await frames(2)
		main.select(Vector3.UP)
		await send(button(MOUSE_BUTTON_LEFT, true, Vector2(640.0, 360.0)))
		await send(button(MOUSE_BUTTON_LEFT, false, Vector2(640.0, 360.0)))
		var ll: Vector2 = MarsGeo.lat_lon(main.selected_dir)
		if absf(ll.x - ref[0]) > 1.5 or absf(wrapf(ll.y - ref[1], -180.0, 180.0)) > 1.5:
			return fail("clique no centro, olhando (%s, %s), deveria dar o mesmo ponto, deu %s" % [ref[0], ref[1], ll])
	ok("o clique na superfície de Marte acerta lat/lon (câmera olhando de 3 pontos diferentes)")

	main.planet.set_control("atmosphere", 0.0)
	main.planet.set_control("temperature", 0.0)
	main._process(60.0)
	main.space.look_at_surface(MarsGeo.dir(15.0, -125.0), 1.5)
	await save("7_tharsis_perto")
