extends "res://tests/test_suite.gd"
## O menu de opções (gravar, aplicar, Esc, atalhos que esperam, sessão lembrada) e os tutoriais (o básico e o de cada ferramenta).

const UserSettings = preload("res://scripts/app/user_settings.gd")


func run() -> void:
	var settings = main.settings
	var options = main.options_panel
	var overlay = main.tutorial_overlay
	var tutorials = main.tutorials
	var hub = main.domains
	var path := out_dir.path_join("opcoes_teste.cfg")
	DirAccess.remove_absolute(path)

	# Gravar e reler; um arquivo mexido à mão não quebra; "Restaurar padrões" não esquece o que o jogo lembra.
	var a = UserSettings.new()
	a.load_from(path)
	if a.value("max_fps") != 60 or a.value("tutorial_asked"):
		return fail("sem arquivo valem os padrões")
	a.set_value("max_fps", 30)
	a.set_value("tutorial_asked", true)
	a.set_value("nao_existe", 1)
	var b = UserSettings.new()
	b.load_from(path)
	if b.value("max_fps") != 30 or not b.value("tutorial_asked") or b.value("nao_existe") != null:
		return fail("gravar e reler: %s %s" % [b.value("max_fps"), b.value("tutorial_asked")])
	b.restore_defaults()
	if b.value("max_fps") != 60 or not b.value("tutorial_asked"):
		return fail("restaurar padrões volta as opções e mantém o que o jogo lembra")
	var bad := ConfigFile.new()
	bad.set_value("evron", "max_fps", "muito")
	bad.set_value("evron", "seen_tools", 5)
	bad.save(path)
	var c = UserSettings.new()
	c.load_from(path)
	if c.value("max_fps") != 60 or c.value("seen_tools") != []:
		return fail("valor de tipo errado no arquivo é ignorado: %s %s" % [c.value("max_fps"), c.value("seen_tools")])
	ok("opções: gravar, reler, restaurar padrões e ignorar arquivo estragado")

	# Esc sem janela e sem seleção abre as opções; Esc de novo fecha. Com o menu aberto os atalhos esperam.
	await frames(3)
	await send(key(KEY_ESCAPE))
	if not options.visible:
		return fail("Esc sem nada aberto abre as opções")
	await send(key(KEY_T))
	await send(key(KEY_R))
	if main._dock["region_card"].visible or main.tool_panel.edit_bar.visible:
		return fail("com as opções abertas, os atalhos não agem no mapa")
	await send(key(KEY_ESCAPE))
	if options.visible:
		return fail("Esc fecha as opções")
	var aren: int = hub.registry.Create("pais", "Aren")
	hub.open(aren)
	await frames(2)
	await send(key(KEY_ESCAPE))  # fecha a janela
	if options.visible or main.windows.window_open():
		return fail("o primeiro Esc só fecha a janela")
	await send(key(KEY_ESCAPE))  # tira a seleção
	if options.visible or hub.current() != 0:
		return fail("o segundo Esc só tira a seleção")
	main._open_config("opcoes")
	if not options.visible:
		return fail("o menu Mundo abre as opções")
	ok("Esc: janela, seleção e então as opções; atalhos esperam; Mundo abre o menu")

	# Cada controle grava e aplica na hora.
	var fps := Engine.max_fps
	var factor: float = tree.root.content_scale_factor
	var pick := func(key_name: String, wanted) -> void:
		var o: OptionButton = options.controls[key_name]
		for i in o.item_count:
			if o.get_item_metadata(i) == wanted:
				o.select(i)
				o.item_selected.emit(i)
	pick.call("max_fps", 30)
	pick.call("autosave_seconds", 300)
	pick.call("ui_scale", 1.15)
	options.controls["orbit_speed"].value = 150
	options.controls["zoom_speed"].value = 50
	await frames(3)
	if Engine.max_fps != 30 or settings.value("autosave_seconds") != 300 or not is_equal_approx(tree.root.content_scale_factor, 1.15) \
			or not is_equal_approx(main.globe.camera.orbit_speed, 1.5) or not is_equal_approx(main.globe.camera.zoom_speed, 0.5):
		return fail("os controles aplicam na hora: fps %d, escala %.2f, giro %.2f" % [Engine.max_fps, tree.root.content_scale_factor, main.globe.camera.orbit_speed])
	var shown: Color = main.hud.theme.get_color("font_color", "TooltipLabel")
	options.controls["tooltips"].button_pressed = false
	if main.hud.theme.get_color("font_color", "TooltipLabel").a != 0.0:
		return fail("dicas desligadas ficam invisíveis")
	options.controls["tooltips"].button_pressed = true
	if main.hud.theme.get_color("font_color", "TooltipLabel") != shown:
		return fail("ligar as dicas devolve o visual delas")
	for section in options.pages:
		options.show_section(section)
		await frames(3)
		var screen := Rect2(Vector2.ZERO, main.hud.size).grow(1.0)
		if not screen.encloses(options._panel.get_global_rect()):
			return fail("a seção %s do menu sai da tela: %s em %s" % [section, options._panel.get_global_rect(), main.hud.size])
	settings.restore_defaults()
	await frames(3)
	if Engine.max_fps != 60 or not is_equal_approx(tree.root.content_scale_factor, 1.0) or not is_equal_approx(main.globe.camera.orbit_speed, 1.0):
		return fail("restaurar padrões aplica de volta")
	Engine.max_fps = fps
	tree.root.content_scale_factor = factor
	options.close()
	ok("opções aplicam na hora (quadros, escala, giro, zoom, salvamento, dicas) e as seções cabem na tela")

	# Com os tutoriais desligados (testes) nada se oferece sozinho.
	main.set_tool(0)
	await frames(3)
	if overlay.visible:
		return fail("nos testes nenhum tutorial se oferece sozinho")
	main.set_tool(-1)
	tutorials.auto = true

	# O básico: pergunta antes; "Sim" mostra os 7 passos com o destaque na tela; depois não pergunta de novo.
	tutorials.offer_basic()
	await frames(3)
	if not overlay.visible or not overlay.asking or not overlay.blocking():
		return fail("o primeiro acesso começa pela pergunta")
	await send(key(KEY_T))
	if main._dock["region_card"].visible:
		return fail("com a pergunta na tela os atalhos esperam")
	overlay.yes_button.pressed.emit()
	await frames(3)
	if overlay.asking or overlay.steps.size() != 7:
		return fail("sim: 7 passos (%d)" % overlay.steps.size())
	if not await _walk("básico", [1, 2, 3, 4, 5]):
		return
	if overlay.visible or not settings.value("tutorial_asked") or tutorials.current != "":
		return fail("concluir fecha e marca o tutorial como perguntado")
	tutorials.offer_basic()
	await frames(2)
	if overlay.visible:
		return fail("não pergunta de novo")
	settings.set_value("tutorial_asked", false)
	tutorials.offer_basic()
	await frames(2)
	overlay.no_button.pressed.emit()
	if overlay.visible or not settings.value("tutorial_asked"):
		return fail("'Não, obrigado' também vale para sempre")
	ok("tutorial básico: pergunta, 7 passos com destaque, e não pergunta de novo")

	# Ferramentas: na primeira vez pergunta sem travar o jogo; fechar a ferramenta tira a pergunta; "nunca" desliga todas.
	main.set_tool(0)
	await frames(4)
	if not overlay.visible or not overlay.asking or overlay.blocking():
		return fail("abrir o relevo oferece o tutorial sem travar a tela")
	main.set_tool(-1)
	await frames(2)
	if overlay.visible or "relevo" in settings.value("seen_tools"):
		return fail("fechar a ferramenta tira a pergunta, e ela volta na próxima vez")
	main.set_tool(0)
	await frames(4)
	overlay.never_button.pressed.emit()
	main.set_tool(-1)
	main.resources.set_open(true)
	await frames(4)
	if overlay.visible or settings.value("offer_tool_tutorials"):
		return fail("'não perguntar mais' vale para todas as ferramentas")
	main.resources.set_open(false)
	settings.set_value("offer_tool_tutorials", true)
	main.resources.set_open(true)
	await frames(4)
	if not overlay.asking:
		return fail("religada a oferta, os recursos perguntam")
	overlay.yes_button.pressed.emit()
	await frames(3)
	if overlay.steps.size() != 7 or not await _walk("recursos", [0, 1, 2, 3, 4, 5, 6]):
		return fail("o tutorial dos recursos tem 7 passos: %d" % overlay.steps.size())
	main.resources.set_open(false)
	main.resources.set_open(true)
	await frames(4)
	if overlay.visible or not "recursos" in settings.value("seen_tools"):
		return fail("já visto: não pergunta de novo")
	main.resources.set_open(false)
	ok("tutoriais de ferramenta: oferta sem travar, 'nunca', e uma vez por ferramenta")

	# Pelo menu, uma ferramenta fechada abre e mostra; pelo "?" do pincel, os 5 passos apontam a barra.
	options.open("ajuda")
	options.tutorial_buttons["povoados"].pressed.emit()
	await frames(5)
	if options.visible or not main._dock["settlements"].visible or overlay.steps.size() != 7:
		return fail("'Ver' dos povoados abre a ferramenta e o tutorial: %d passos" % overlay.steps.size())
	if not await _walk("povoados", [0, 1, 2, 6]):  # as abas do povoado precisam de um povoado: aqui o mundo não tem
		return
	main.production.set_open(false)
	settings.set_value("offer_tool_tutorials", false)
	hub.open(aren)
	main.territories.start_painting(aren)
	await frames(5)
	main._dock["territory"].help_button.pressed.emit()
	await frames(3)
	if overlay.steps.size() != 5 or not await _walk("território", [0, 1, 2, 3, 4]):
		return fail("o '?' do pincel mostra os 5 passos")
	main.territories.stop_painting()
	options.open("ajuda")
	options.tutorial_buttons["relevo"].pressed.emit()
	await frames(5)
	if overlay.steps.size() != 4 or not await _walk("relevo", [0, 1, 2, 3]):
		return fail("o tutorial do relevo tem 4 passos")
	main.set_tool(-1)
	ok("pelo menu e pelo '?': a ferramenta abre e os destaques apontam para ela")

	# Em 1280 × 720 o menu e os cartões do tutorial cabem na tela.
	var before: Vector2i = tree.root.size
	tree.root.size = Vector2i(1280, 720)
	await frames(8)
	options.open("ajuda")
	await frames(4)
	if not Rect2(Vector2.ZERO, main.hud.size).grow(1.0).encloses(options._panel.get_global_rect()):
		return fail("em 1280×720 o menu sai da tela: %s" % options._panel.get_global_rect())
	options.close()
	tutorials.request("basico")
	await frames(4)
	if not await _walk("básico em 1280", [1, 2, 3, 4, 5]):
		return
	tree.root.size = before
	await frames(4)
	ok("1280 × 720: menu e tutorial cabem")

	# A sessão é lembrada: o alto, as sobreposições e o modo de mapa.
	settings.load_from(path)
	DirAccess.remove_absolute(path)
	settings.load_from(path)
	main.top_hud.set_minimized(true)
	main._presence.rivers_check.set_pressed_no_signal(true)
	main._presence.names_check.button_pressed = false
	main.territories.show_level("cultura")
	main._remember_session()
	var kept = UserSettings.new()
	kept.load_from(path)
	if not kept.value("hud_minimized") or kept.value("country_names") or not kept.value("rivers") or kept.value("map_level") != "cultura":
		return fail("a sessão lembrada: %s %s %s %s" % [kept.value("hud_minimized"), kept.value("country_names"), kept.value("rivers"), kept.value("map_level")])
	main.top_hud.set_minimized(false)
	main._presence.names_check.button_pressed = true
	main.territories.show_level("pais")
	main._restore_session()
	await frames(3)
	if not main.top_hud.minimized or main._presence.names_check.button_pressed or main.territories.territory_level != "cultura":
		return fail("restaurar a sessão: alto %s, nomes %s, nível %s" % [main.top_hud.minimized, main._presence.names_check.button_pressed, main.territories.territory_level])
	settings.path = ""
	ok("a sessão é lembrada: alto minimizado, sobreposições e modo de mapa")


## Percorre os passos abertos conferindo que o cartão fica na tela e que os passos de `marked` têm um destaque visível; conclui no fim.
func _walk(name: String, marked: Array) -> bool:
	var overlay = main.tutorial_overlay
	var count: int = overlay.steps.size()
	for i in count:
		await frames(3)
		var screen := Rect2(Vector2.ZERO, main.hud.size).grow(1.0)
		if not screen.encloses(overlay.card.get_global_rect()):
			fail("tutorial %s, passo %d: o cartão sai da tela %s" % [name, i + 1, overlay.card.get_global_rect()])
			return false
		var target: Rect2 = overlay.target_rect()
		if i in marked and not target.has_area():
			fail("tutorial %s, passo %d (%s) sem destaque" % [name, i + 1, overlay.steps[i].title])
			return false
		if target.has_area() and target.size.x < main.hud.size.x * 0.7 and target.intersects(overlay.card.get_global_rect().grow(-8.0)) and target.size.y < main.hud.size.y * 0.5:
			fail("tutorial %s, passo %d: o cartão tapa o destaque %s %s" % [name, i + 1, overlay.card.get_global_rect(), target])
			return false
		overlay.next_button.pressed.emit()
	await frames(2)
	return true
