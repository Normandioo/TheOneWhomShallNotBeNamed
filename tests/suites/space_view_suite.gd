extends "res://tests/test_suite.gd"
## A vista do espaço na cena: a câmera livre (girar, zoom da superfície da Terra ao sistema solar),
## órbitas e cinturões que aparecem pelo zoom, foco em Marte, na Terra e na Lua, e a entrada enviada como o jogo recebe.

const Ephemeris = preload("res://scripts/sim/ephemeris.gd")
const SolarBodies = preload("res://scripts/sim/solar_bodies.gd")
const SpaceView = preload("res://scripts/space/space_view.gd")
const SpaceCamera = preload("res://scripts/space/space_camera.gd")

const Id = SolarBodies.Id


func run() -> void:
	var space = main.space
	main.clock.set_speed(0.0)  # as capturas assumem o tempo parado
	await frames(3)
	if not (space is SpaceView) or space.camera.focus_id != Id.MARS:
		return fail("o jogo deveria abrir na vista do espaço, com Marte em foco")
	if absf(space.jd - Ephemeris.jd_from_year(main.clock.year)) > 1e-6:
		return fail("a vista do espaço deveria usar a data do jogo")
	if space.scene.body_position(Id.MARS) != Vector3.ZERO:
		return fail("com foco em Marte ele deveria estar na origem da cena")
	await save("29_marte_padrao")

	# A barra de foco: o botão "Terra" leva a câmera para a Terra.
	var earth_button: Button = null
	for b in space.hud.find_children("*", "Button", true, false):
		if b.text == "Terra":
			earth_button = b
	if earth_button == null:
		return fail("a barra de foco deveria ter o botão 'Terra'")
	earth_button.pressed.emit()
	if space.camera.focus_id != Id.EARTH:
		return fail("o botão 'Terra' deveria focar a Terra")

	# A Terra de perto: a origem flutuante põe a Terra exatamente na origem, e a Lua a ~384 mil km.
	await look(space, Id.EARTH, 3.5)
	var moon_dist: float = space.scene.body_position(Id.MOON).length()
	if space.scene.body_position(Id.EARTH) != Vector3.ZERO or moon_dist < 356.0 or moon_dist > 407.0:
		return fail("com foco na Terra ela deveria estar na origem e a Lua a 356-407 unidades: Terra %s, Lua a %.1f" % [space.scene.body_position(Id.EARTH), moon_dist])
	if space.scene.belt_alpha() > 0.01:
		return fail("de perto da Terra os cinturões não deveriam aparecer: %.2f" % space.scene.belt_alpha())
	await save("21_espaco_terra")
	# O relevo da Terra e da Lua vem de mapas de altitude (NASA), lidos pelo shader dos corpos.
	for id in [Id.EARTH, Id.MOON]:
		var m: ShaderMaterial = space.scene._materials[id]
		if m.get_shader_parameter("use_height") != true or m.get_shader_parameter("height_tex") == null:
			return fail("a Terra e a Lua deveriam ter o mapa de altitude (relevo)")
	ok("Terra e Lua com mapa de altitude (relevo)")

	# A Terra e a órbita da Lua.
	await look(space, Id.EARTH, 200.0)
	if space.scene.moon_orbit_alpha() < 0.95:
		return fail("a 200 raios da Terra a órbita da Lua deveria aparecer: alpha %.2f" % space.scene.moon_orbit_alpha())
	await save("22_espaco_terra_e_orbita_da_lua")

	# De pertinho da superfície (a ~380 km): a câmera chega perto e o chão não some atrás do plano de corte.
	await look(space, Id.EARTH, 1.06)
	await save("26_espaco_terra_superficie")
	await look(space, Id.MOON, 1.06)
	await save("27_espaco_lua_superficie")

	# A atmosfera de Marte: o halo engrossa com o controle de atmosfera, e o medidor mostra o topo em km.
	main.planet.set_control("atmosphere", 0.0)
	var thin: float = space.scene.atmosphere_thickness()
	main.planet.set_control("atmosphere", 0.9)
	var thick: float = space.scene.atmosphere_thickness()
	if thick < 2.0 * thin:
		return fail("a espessura do halo deveria crescer bem com a atmosfera: %.3f -> %.3f" % [thin, thick])
	main._process(0.0)
	var gauge_text := ""
	for l in main.gauge.find_children("*", "Label", true, false):
		if l.text.begins_with("Atmosfera até"):
			gauge_text = l.text
	if gauge_text == "":
		return fail("o medidor deveria mostrar o topo da atmosfera")
	await look(space, Id.MARS, 2.2)
	await save("30_marte_atmosfera_alta")
	main.planet.set_control("atmosphere", 0.0)
	await save("31_marte_atmosfera_fina")
	ok("atmosfera de Marte: halo %.2f -> %.2f unidades; medidor: %s" % [thin, thick, gauge_text.strip_edges()])

	# Marte tem o mesmo visual do jogo (material do mapa), não uma bola lisa.
	await look(space, Id.MARS, 3.5)
	if not space.scene.has_surface(Id.MARS):
		return fail("Marte deveria usar o material do jogo")
	await save("28_espaco_marte")

	# As luas de Marte: com Marte a ~15 raios as órbitas aparecem; no zoom padrão (3,5) a órbita de Fobos passaria
	# do quadro e some; e dá para focar em Fobos.
	await look(space, Id.MARS, 15.0)
	if space.scene.mars_moon_orbit_alpha(Id.PHOBOS) < 0.9 or space.scene.mars_moon_orbit_alpha(Id.DEIMOS) < 0.8:
		return fail("a 15 raios de Marte as órbitas de Fobos e Deimos deveriam aparecer: %.2f e %.2f" % [
			space.scene.mars_moon_orbit_alpha(Id.PHOBOS), space.scene.mars_moon_orbit_alpha(Id.DEIMOS)])
	await save("32_marte_e_suas_luas")
	await look(space, Id.MARS, 3.5)
	if space.scene.mars_moon_orbit_alpha(Id.PHOBOS) > 0.1:
		return fail("no zoom padrão a órbita de Fobos não deveria cruzar a tela: %.2f" % space.scene.mars_moon_orbit_alpha(Id.PHOBOS))
	await look(space, Id.PHOBOS, 3.5)
	if space.scene.body_position(Id.PHOBOS) != Vector3.ZERO:
		return fail("com foco em Fobos ele deveria estar na origem")
	await save("33_fobos")
	ok("Fobos e Deimos orbitam Marte e dá para focar neles")

	# A Lua de perto.
	await look(space, Id.MOON, 3.5)
	if space.scene.body_position(Id.MOON) != Vector3.ZERO:
		return fail("com foco na Lua ela deveria estar na origem")
	await save("23_espaco_lua")

	# O sistema solar interno, com o cinturão principal.
	await look(space, Id.SUN, 0.0, 4.5 * SolarBodies.UNIT_PER_AU)
	space.camera.pitch = 0.9
	await frames(2)
	if space.scene.belt_alpha() < 0.95 or space.scene.moon_orbit_alpha() > 0.05 or space.scene.planet_orbit_alpha(Id.EARTH) < 0.95:
		return fail("a 4,5 UA deveria mostrar órbitas dos planetas e cinturões, sem a órbita da Lua: Terra %.2f, cinturão %.2f, Lua %.2f" % [
			space.scene.planet_orbit_alpha(Id.EARTH), space.scene.belt_alpha(), space.scene.moon_orbit_alpha()])
	await save("24_espaco_sistema_interno")

	# Tudo: a visão geral até Netuno e o cinturão de Kuiper.
	space.camera.overview(space._positions)
	space.camera.snap()
	await frames(2)
	if space.scene.planet_orbit_alpha(Id.NEPTUNE) < 0.95:
		return fail("na visão geral a órbita de Netuno deveria aparecer")
	await save("25_espaco_sistema_inteiro")

	if not await _zoom_with_real_input(space):
		return
	if not await _click_to_focus(space):
		return
	if not await _time_moves(space):
		return

	# Custo por quadro: as posições, as órbitas e os marcadores têm que caber folgado no quadro (16 ms).
	space.camera.overview(space._positions)
	space.camera.snap()
	var t0 := Time.get_ticks_usec()
	for i in 60:
		space.update(0.016)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 60.0
	if ms > 6.0:
		return fail("a lógica do modo espaço deveria custar bem menos de um quadro, custou %.1f ms" % ms)
	print("modo espaço: %.2f ms de lógica por quadro" % ms)

	ok("vista do espaço: Marte em foco, Terra e Lua com zoom, órbitas e cinturões pelo zoom")


## Vai para o corpo `id` a `zoom` raios (ou a `units` unidades, se informado) sem animação.
func look(space: Node, id: int, zoom: float, units := -1.0) -> void:
	space.camera.focus_on(id, space._positions, zoom if units < 0.0 else 1.0)
	if units > 0.0:
		space.camera.target_dist = units
	space.camera.snap()
	await frames(2)


func _zoom_with_real_input(space: Node) -> bool:
	await look(space, Id.EARTH, 3.5)
	for i in 120:
		Input.parse_input_event(wheel(MOUSE_BUTTON_WHEEL_UP))
	Input.flush_buffered_events()
	await frames(2)
	var min_dist: float = SolarBodies.radius_units(Id.EARTH) * SpaceCamera.MIN_FACTOR
	if absf(space.camera.target_dist - min_dist) > 1e-6:
		fail("a roda para cima deveria parar a 3%% do raio acima da superfície (%.2f unidades), parou em %.4f" % [min_dist, space.camera.target_dist])
		return false
	for i in 200:
		Input.parse_input_event(wheel(MOUSE_BUTTON_WHEEL_DOWN))
	Input.flush_buffered_events()
	await frames(2)
	if absf(space.camera.target_dist - SpaceCamera.MAX_DIST) > 1.0:
		fail("a roda para baixo deveria chegar a 500 UA, parou em %.3e unidades" % space.camera.target_dist)
		return false
	space.camera.snap()
	await frames(2)
	if space.scene.planet_orbit_alpha(Id.NEPTUNE) < 0.2 and space.scene.planet_orbit_alpha(Id.MERCURY) > 0.95:
		fail("a 500 UA o sistema solar inteiro deveria ser pequeno, mas as órbitas externas somem antes das internas")
		return false
	# Arrastar com o botão esquerdo gira em volta do foco.
	var yaw0: float = space.camera.yaw
	await send(button(MOUSE_BUTTON_LEFT, true, Vector2(640.0, 360.0)))
	await send(motion(Vector2(700.0, 380.0), Vector2(60.0, 20.0)))
	await send(button(MOUSE_BUTTON_LEFT, false, Vector2(700.0, 380.0)))
	if space.camera.yaw == yaw0:
		fail("arrastar deveria girar a câmera em volta do corpo")
		return false
	ok("zoom da superfície (%.1f mil km) a 500 UA pela roda do mouse, e arrastar gira a câmera" % (min_dist))
	return true


## Clicar na Lua (num zoom em que ela aparece) foca nela.
func _click_to_focus(space: Node) -> bool:
	await look(space, Id.EARTH, 200.0)
	var shrink := float(SpaceView.PIXEL_SHRINK)
	# Gira até a Lua cair num lugar livre da tela (os painéis da interface engoliriam o clique).
	var free := Rect2(320.0, 170.0, 620.0, 430.0)
	var pos := Vector2.ZERO
	for k in 24:
		space.camera.yaw = k * 0.26
		space.camera.snap()
		await frames(2)
		pos = space.camera.cam.unproject_position(space.scene.body_position(Id.MOON)) * shrink
		if free.has_point(pos):
			break
	if not free.has_point(pos):
		fail("não achei um ângulo em que a Lua caia numa parte livre da tela: %s" % pos)
		return false
	await send(button(MOUSE_BUTTON_LEFT, true, pos))
	await send(button(MOUSE_BUTTON_LEFT, false, pos))
	if space.camera.focus_id != Id.MOON:
		fail("clicar na Lua deveria focar nela, o foco ficou em %s" % SolarBodies.body_name(space.camera.focus_id))
		return false
	ok("clique em um corpo move o foco para ele")
	return true


## O tempo anda: a Lua anda em volta da Terra, e a distância continua entre o perigeu e o apogeu.
func _time_moves(space: Node) -> bool:
	await look(space, Id.EARTH, 200.0)
	var before: Vector3 = space.scene.body_position(Id.MOON)
	main.clock.set_speed(1.0)
	main._process(10.0 / 365.25)  # 10 dias do jogo
	main.clock.set_speed(0.0)
	await frames(1)
	var after: Vector3 = space.scene.body_position(Id.MOON)
	var d := after.length()
	if before.distance_to(after) < 100.0 or d < 354.0 or d > 408.0:
		fail("em 10 dias a Lua deveria andar mais de 100 mil km em volta da Terra, ficando a 356-407 mil km: andou %.0f, a %.0f" % [before.distance_to(after), d])
		return false
	ok("o tempo anda: a Lua deu %.0f° em 10 dias" % rad_to_deg(before.angle_to(after)))
	return true
