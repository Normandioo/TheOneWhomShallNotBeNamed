extends "res://tests/test_suite.gd"
## A entrada do jogador, enviada como o jogo recebe de verdade (Input.parse_input_event): o evento tem que
## atravessar a janela até o Main e chegar à câmera e à simulação. Chamar os métodos direto não pegaria um
## evento que se perde no caminho (já aconteceu: o contêiner do 3D ignora o mouse e engolia a roda).

const MarsGeo = preload("res://scripts/data/mars_geo.gd")


func run() -> void:
	var space = main.space
	main.clock.set_speed(0.0)
	space.look_at_surface(MarsGeo.dir(0.0, 0.0), 3.0)

	# Roda do mouse: aproxima e afasta.
	var d0: float = space.camera.target_dist
	await send(wheel(MOUSE_BUTTON_WHEEL_UP))
	if space.camera.target_dist >= d0:
		return fail("a roda do mouse para cima deveria aproximar a câmera: %s -> %s" % [d0, space.camera.target_dist])
	var d_near: float = space.camera.target_dist
	await send(wheel(MOUSE_BUTTON_WHEEL_DOWN))
	if space.camera.target_dist <= d_near:
		return fail("a roda do mouse para baixo deveria afastar a câmera: %s -> %s" % [d_near, space.camera.target_dist])

	# Arrastar: gira a câmera em volta de Marte, e soltar depois de arrastar não conta como clique.
	space.look_at_surface(MarsGeo.dir(0.0, 0.0), 3.0)
	main.selected_dir = Vector3.ZERO
	var yaw0: float = space.camera.yaw
	await send(button(MOUSE_BUTTON_LEFT, true, Vector2(640.0, 360.0)))
	await send(motion(Vector2(700.0, 360.0), Vector2(60.0, 0.0)))
	await send(button(MOUSE_BUTTON_LEFT, false, Vector2(700.0, 360.0)))
	if space.camera.yaw == yaw0:
		return fail("arrastar deveria girar a câmera")
	if main.selected_dir != Vector3.ZERO:
		return fail("soltar o botão depois de arrastar não deveria selecionar uma região")

	# Clique parado: seleciona o ponto de Marte sob o mouse.
	space.look_at_surface(MarsGeo.dir(0.0, 0.0), 3.0)
	await send(button(MOUSE_BUTTON_LEFT, true, Vector2(640.0, 360.0)))
	await send(button(MOUSE_BUTTON_LEFT, false, Vector2(640.0, 360.0)))
	if main.selected_dir == Vector3.ZERO:
		return fail("um clique parado em Marte deveria selecionar o ponto")
	ok("mouse: roda aproxima, arrastar gira sem selecionar, clique seleciona")

	# Espaço pausa e retoma.
	main.clock.set_speed(1.0)
	await send(key(KEY_SPACE))
	if main.clock.time_scale != 0.0:
		return fail("espaço deveria pausar")
	await send(key(KEY_SPACE))
	if main.clock.time_scale != 1.0:
		return fail("espaço de novo deveria retomar a 1x")
	ok("espaço pausa e retoma")

	# Slider: o jogador mexe, e a simulação recebe (os sliders são os HSlider do painel).
	var sliders: Array[Node] = main.control_panel.find_children("*", "HSlider", true, false)
	if sliders.size() != 3:
		return fail("o painel deveria ter 3 sliders, tem %d" % sliders.size())
	sliders[0].value = 0.5
	if absf(main.planet.temperature - 0.5) > 1e-6:
		return fail("mexer no slider de temperatura deveria mudar o planeta: %s" % main.planet.temperature)
	main.planet.set_control("temperature", 0.0)
	if sliders[0].value != 0.0:
		return fail("o slider deveria voltar a 0 quando o planeta mudar por código")
	ok("slider -> planeta e planeta -> slider")
