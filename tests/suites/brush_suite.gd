extends "res://tests/test_suite.gd"
## O pincel na tela, pelo caminho de verdade (eventos de mouse e teclado): pintar uma montanha arrastando o mouse,
## ver o círculo de prévia, Ctrl+Z e Ctrl+Y, e o botão direito ainda girando a câmera. Capturas de antes e depois.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")
const TerrainBrush = preload("res://scripts/edit/terrain_brush.gd")

const CENTER := Vector2(640.0, 360.0)


func run() -> void:
	var cam = main.globe.camera
	for i in MapLayers.LAYERS.size():
		if MapLayers.LAYERS[i]["kind"] == "altitude":
			main.set_layer(i)
	var spot := EvronGeo.dir(-20.0, -100.0)  # planície costeira: a montanha nova aparece bem
	cam.look_at_dir(spot, 1.25)
	await frames(3)
	var target: Vector3 = main.globe.pick(CENTER)
	var h0: float = main.terrain.height_at(target)
	await save("8_antes_do_pincel")

	# Pincel ativo: passar o mouse mostra o círculo.
	main.set_tool(TerrainBrush.Op.RAISE)
	main.brush.roughness = 0.0
	main.brush.radius_km = 250.0
	main.brush.strength = 400.0
	await send(motion(CENTER, Vector2(1, 0)))
	var b: Vector4 = main.brush_preview
	if b.w <= 0.0:
		return fail("com o pincel ativo, o mouse sobre o globo deveria mostrar o círculo")

	# Arrastar com o esquerdo pinta, não gira; vira um comando só.
	var yaw0: float = cam.yaw
	await send(button(MOUSE_BUTTON_LEFT, true, CENTER))
	for i in range(1, 9):
		await send(motion(CENTER + Vector2(i * 6, 0), Vector2(6, 0)))
	await send(button(MOUSE_BUTTON_LEFT, false, CENTER + Vector2(48, 0)))
	var h1: float = main.terrain.height_at(target)
	if h1 < h0 + 300.0:
		return fail("arrastar o pincel de elevar deveria subir o centro (%.0f -> %.0f m)" % [h0, h1])
	if cam.yaw != yaw0:
		return fail("com o pincel, arrastar com o esquerdo não deveria girar a câmera")
	if main.commands.undo_name().begins_with("Elevar") == false:
		return fail("a pincelada deveria aparecer como 'Elevar' para desfazer")
	main._show_brush(Vector3.ZERO)  # sem o círculo por cima, para ver o resultado
	await frames(3)
	await save("8_depois_do_pincel")
	ok("pincel: arrastar elevou o centro de %.0f para %.0f m, sem girar a câmera" % [h0, h1])

	# Ctrl+Z desfaz, Ctrl+Y refaz.
	var ctrl_z := key(KEY_Z)
	ctrl_z.ctrl_pressed = true
	await send(ctrl_z)
	if main.terrain.height_at(target) != h0:
		return fail("Ctrl+Z deveria devolver a altura exata")
	var ctrl_y := key(KEY_Y)
	ctrl_y.ctrl_pressed = true
	await send(ctrl_y)
	if main.terrain.height_at(target) != h1:
		return fail("Ctrl+Y deveria refazer")
	await send(ctrl_z)
	ok("Ctrl+Z desfaz e Ctrl+Y refaz")

	# O botão direito continua girando a câmera.
	await send(button(MOUSE_BUTTON_RIGHT, true, CENTER))
	await send(motion(CENTER + Vector2(60, 0), Vector2(60, 0)))
	await send(button(MOUSE_BUTTON_RIGHT, false, CENTER + Vector2(60, 0)))
	if cam.yaw == yaw0:
		return fail("arrastar com o direito deveria girar a câmera")
	ok("botão direito gira a câmera com o pincel ativo")

	# Voltar a navegar esconde o círculo.
	main.set_tool(-1)
	b = main.brush_preview
	if b.w != 0.0:
		return fail("navegar deveria esconder o círculo do pincel")

	# Montanhas: uma pincelada arrastada cria uma cordilheira com cristas e vales.
	main.set_tool(TerrainBrush.Op.MOUNTAINS)
	main.brush.radius_km = 280.0
	main.brush.strength = 450.0
	main.brush.seed_value = 11
	main.brush.roughness = 0.5
	cam.look_at_dir(spot, 1.3)
	await frames(3)
	await send(button(MOUSE_BUTTON_LEFT, true, CENTER + Vector2(-150, 40)))
	for i in range(1, 16):
		await send(motion(CENTER + Vector2(-150 + i * 20, 40 - i * 6), Vector2(20, -6)))
	await send(button(MOUSE_BUTTON_LEFT, false, CENTER + Vector2(150, -50)))
	main._show_brush(Vector3.ZERO)
	await frames(3)
	await save("8_montanhas")
	main.commands.undo()
	main.set_tool(TerrainBrush.Op.RAISE)
	main.brush.seed_value = -1

	# Quanto custa reenviar a altitude para a GPU (a cada 0,1 s durante a pincelada).
	var t0 := Time.get_ticks_usec()
	main.material.refresh_height(main.height_img)
	await RenderingServer.frame_post_draw
	ok("reenviar a altitude (32 MiB) para a GPU: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	main.set_layer(0)
