extends "res://tests/test_suite.gd"
## Todos os tutoriais: cada passo de cada menu abre o menu, acha o botão de que fala (o contorno) e deixa o cartão fora do caminho.
## E o jogo continua valendo com o tutorial aberto: cliques de mouse de verdade chegam aos botões e ao globo.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const Controller = preload("res://scripts/app/tutorial_controller.gd")

var overlay
var tutorials


func run() -> void:
	overlay = main.tutorial_overlay
	tutorials = main.tutorials
	var hub = main.domains
	var reg = hub.registry
	await frames(5)

	# Um mundo com o que os menus precisam: um país pintado, com província, cidade, cultura, povoado e recurso.
	var aren: int = reg.Create("pais", "Aren")
	var province: int = reg.Create("provincia", "Alta Aren")
	reg.Link(province, aren, "provincia_de")
	var faith: int = reg.Create("religiao", "Via do Sol")
	var city: int = reg.AddPlace("Porto", "assentamento", 2.0, 2.0, 0.0, "")
	reg.AddPresence(aren, city, "capital", "media")
	main.territory.Begin()
	main.territory.Dab(EvronGeo.dir(0, 0), 900.0, aren, false, -1)
	main.territory.End()
	var cultures = main.territories.layer("cultura")
	var culture: int = reg.Create("cultura", "Tecelões")
	cultures.Begin()
	cultures.Dab(EvronGeo.dir(0, 0), 600.0, culture, false, -1)
	cultures.End()
	reg.CreateResourceType("Cobre")
	reg.CreateSettlement("Vila", 1.0, 1.0, 20)
	main.resources.refresh()
	main.globe.focus(EvronGeo.dir(0, 0), 2.4)
	await frames(10)

	# Cada tutorial, passo a passo.
	var total := 0
	var keys: Array = []
	for group in Controller.GROUPS:
		for t in group[1]:
			keys.append(t[0])
	for key in keys:
		_close_all()
		await frames(3)
		hub.open(aren)
		await frames(3)
		main.windows.close_window()
		if key == "territorio":
			hub.open(aren)
		await frames(3)
		tutorials.request(key)
		await frames(6)
		if tutorials.current != key or overlay.steps.is_empty() or overlay.asking:
			return fail("'%s' não abriu (atual '%s', pergunta %s, texto %s)" % [key, tutorials.current, overlay.asking, overlay.text_label.text])
		var count: int = overlay.steps.size()
		for i in count:
			overlay.show_step(i)
			await frames(5)
			var problem := _check(key, i)
			if problem != "":
				await save("tutorial_%s_%d" % [key, i + 1])
				return fail(problem)
		total += count
		overlay.next_button.pressed.emit()
		await frames(3)
		if overlay.visible or tutorials.current != "" or overlay.get_parent() != main.hud:
			return fail("'%s': concluir fecha e devolve o cartão à tela" % key)
	ok("%d tutoriais, %d passos: cada um abre o menu, acha o botão de que fala e deixa o cartão fora do caminho" % [keys.size(), total])

	# Com o tutorial aberto o jogo continua valendo: o clique de mouse chega ao botão, e o passo marca como feito.
	_close_all()
	hub.open(aren)
	await frames(4)
	tutorials.request("alto")
	await frames(6)
	overlay.show_step(3)  # minimizar
	await frames(6)
	if overlay.done or overlay.blocking():
		return fail("o passo começa por fazer, sem segurar a tela")
	await _click(main.top_hud._fold)
	await frames(4)
	if not main.top_hud.minimized or not overlay.visible or not overlay.done or not overlay.try_label.text.begins_with("✓ Feito"):
		return fail("o clique minimiza com o tutorial aberto, e o passo marca feito: minimizado %s, feito %s" % [main.top_hud.minimized, overlay.done])
	await _click(main.top_hud._expand)
	await frames(4)
	tutorials.request("mapas")
	await frames(6)
	overlay.show_step(3)  # os mapas do povo
	await frames(5)
	await _click(main.mode_rail._level_buttons["cultura"])
	await frames(5)
	if main.territories.territory_level != "cultura" or not overlay.done or not overlay.visible:
		return fail("o clique no modo de mapa vale durante o tutorial: %s" % main.territories.territory_level)
	main.territories.show_level("pais")
	ok("durante o tutorial os cliques chegam aos botões, e o passo marca ✓ Feito")

	# Pintar de verdade com o tutorial do pincel aberto (o mouse passa pelo cartão e chega ao globo); Ctrl+Z desfaz.
	_close_all()
	hub.open(aren)
	await frames(4)
	main.territories.start_painting(aren)
	await frames(4)
	tutorials.request("territorio")
	await frames(6)
	main.territories._set_territory_mode("borracha")  # no meio do país a borracha sempre tem o que apagar
	main.territories.territory_panel.set_mode("borracha")
	main.globe.focus(EvronGeo.dir(0, 0), 2.4)
	await frames(20)
	var version: int = main.territory.Version
	var spot: Vector2 = main.globe.camera.cam.unproject_position(EvronGeo.dir(0, 0) * main.globe.RADIUS)
	if overlay.card.get_global_rect().has_point(spot):
		return fail("o cartão não deveria cobrir o meio do mapa: %s" % overlay.card.get_global_rect())
	await send(motion(spot, Vector2(1, 0)))
	await send(button(MOUSE_BUTTON_LEFT, true, spot))
	await send(button(MOUSE_BUTTON_LEFT, false, spot))
	await frames(4)
	if main.territory.Version == version or not overlay.visible or not overlay.done:
		return fail("pintar com o tutorial aberto: versão %d -> %d, feito %s" % [version, main.territory.Version, overlay.done])
	main.undo()
	main.territories.stop_painting()
	overlay.close()
	tutorials.current = ""
	ok("dá para pintar no globo com o tutorial do pincel aberto")

	# Fechar a parte falada não derruba o tutorial: o cartão oferece mostrar de novo. Esc vai para o jogo.
	_close_all()
	hub.open(aren)
	await frames(4)
	tutorials.request("ficha")
	await frames(8)
	await send(key(KEY_ESCAPE))
	await frames(5)
	if hub.sheet.visible or not overlay.visible or not overlay._missing_row.visible:
		return fail("Esc fecha a ficha, o tutorial continua e oferece mostrar de novo: ficha %s, tutorial %s, aviso %s" % [hub.sheet.visible, overlay.visible, overlay._missing_row.visible])
	overlay.again_button.pressed.emit()
	await frames(6)
	if not hub.sheet.visible or overlay._missing_row.visible or not overlay.target_rect().has_area():
		return fail("'Mostrar de novo' reabre a ficha e o destaque volta")
	# O cartão arrastado fica onde foi deixado.
	var before: Vector2 = overlay.card.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	overlay._drag(press)
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(180, 90)
	overlay._drag(move)
	press.pressed = false
	overlay._drag(press)
	await frames(5)
	if overlay.card.position.distance_to(before) < 100.0:
		return fail("arrastar o cartão pelo título deve deixá-lo no lugar novo: %s -> %s" % [before, overlay.card.position])
	overlay.close()
	tutorials.current = ""
	ok("fechar o que se está vendo não derruba o tutorial; o cartão arrasta e 'Mostrar de novo' reabre")

	# Sem nada selecionado, o tutorial de um menu da ficha diz o que falta e começa quando a ficha abrir.
	_close_all()
	hub.deselect()
	await frames(3)
	tutorials.request("povo")
	await frames(3)
	if not overlay.asking or overlay.yes_button.visible or not overlay.text_label.text.contains("Clique num país"):
		return fail("sem seleção, o aviso do que falta: %s" % overlay.text_label.text)
	hub.open(aren)
	await frames(2)
	main.windows.press("povo")
	await frames(8)
	if overlay.asking or tutorials.current != "povo" or overlay.steps.is_empty():
		return fail("aberta a página, o tutorial começa sozinho: atual '%s'" % tutorials.current)
	overlay.close()
	tutorials.current = ""
	# Dentro de uma janela o contorno cai em cima do que fala, e não deslocado.
	tutorials.request("tipos")
	await frames(10)
	var row: Rect2 = main._dock["types"]._type_name.get_parent().get_global_rect()
	var drawn: Rect2 = overlay.target_rect()
	drawn.position += overlay.global_position  # onde ele aparece na janela
	if not drawn.grow(1.0).encloses(row) or not row.grow(8.0).encloses(drawn):  # envolve a linha, com pouca folga
		return fail("o contorno em Tipos está deslocado: %s, a linha é %s (o cartão começa em %s)" % [drawn, row, overlay.global_position])
	overlay.close()
	tutorials.current = ""
	tutorials._move_to("")
	main._dock["types"]._dialog.hide()
	await frames(4)
	# Fechar a janela do Mundo no meio do tutorial devolve o cartão à tela.
	tutorials.request("tipos")
	await frames(8)
	if overlay.get_parent() != main._dock["types"]._dialog:
		return fail("o tutorial de Tipos fica dentro da janela")
	main._dock["types"]._dialog.hide()
	await frames(4)
	if overlay.visible or overlay.get_parent() != main.hud or tutorials.current != "":
		return fail("fechar a janela encerra o tutorial e devolve o cartão")
	ok("sem seleção o tutorial espera a ficha; fechar a janela do Mundo devolve o cartão")

	# Na primeira vez que cada menu abre, a pergunta; trocar de página troca a pergunta; uma vez respondida, não volta.
	tutorials.auto = true
	_close_all()
	main.settings.set_value("seen_tools", [])
	hub.deselect()
	hub.sheet.wanted_page = "Ficha"  # a ficha reabre na última categoria usada
	await frames(3)
	hub.open(aren)
	await frames(5)
	if not overlay.asking or tutorials.current != "ficha" or overlay.blocking():
		return fail("abrir a ficha pela primeira vez oferece o tutorial dela: atual '%s'" % tutorials.current)
	main.windows.press("povo")
	await frames(5)
	if not overlay.asking or tutorials.current != "povo":
		return fail("trocar de página troca a pergunta: atual '%s'" % tutorials.current)
	overlay.no_button.pressed.emit()
	main.windows.press("governo")
	await frames(5)
	main.windows.press("povo")
	await frames(5)
	if tutorials.current == "povo":
		return fail("respondido, o menu Povo não pergunta de novo")
	overlay.close()
	tutorials.current = ""
	main.windows.toggle_registry()
	await frames(5)
	if tutorials.current != "registros":
		return fail("os Registros também oferecem: atual '%s'" % tutorials.current)
	overlay.never_button.pressed.emit()
	main.windows.press("ficha")
	await frames(5)
	if overlay.visible or main.settings.value("offer_tool_tutorials"):
		return fail("'não perguntar mais' vale para todos os menus")
	tutorials.auto = false
	ok("cada menu oferece o tutorial na primeira vez, e 'não perguntar mais' vale para todos")


func _close_all() -> void:
	overlay.close()
	tutorials.current = ""
	tutorials._pending = ""
	tutorials._move_to("")
	if main.territories.drafting:
		main.territories.discard_draft()
	if main.territories.painting_territory:
		main.territories.stop_painting()
	main._dock["region_card"].hide()
	main.set_tool(-1)
	main.windows.close_window()
	main.options_panel.close()
	main._dock["calendar"].visible = false
	main.mode_rail._overlays.button_pressed = false
	for key in ["types", "rules"]:
		main._dock[key]._dialog.hide()


## O passo está certo? O cartão dentro da tela (ou da janela), o destaque encontrado e o cartão sem tapar o botão pequeno.
func _check(key: String, index: int) -> String:
	var s: Dictionary = overlay.steps[index]
	var host := Rect2(Vector2.ZERO, overlay.size).grow(1.0)
	var card: Rect2 = Rect2(overlay.card.position, overlay.card.size)
	if not host.encloses(card):
		return "%s, passo %d (%s): o cartão sai da área %s em %s" % [key, index + 1, s.title, card, overlay.size]
	if not s.has("rect"):
		return ""
	var target: Rect2 = overlay.target_rect()
	if not target.has_area():
		return "%s, passo %d (%s): o contorno não achou a parte falada" % [key, index + 1, s.title]
	var small: bool = target.size.x * target.size.y < overlay.size.x * overlay.size.y * 0.1
	if small and target.intersects(card.grow(-6.0)) and not key in ["tipos", "regras"]:
		return "%s, passo %d (%s): o cartão tapa o destaque %s %s" % [key, index + 1, s.title, card, target]
	return ""


func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	await send(motion(at, Vector2(1, 0)))
	await send(button(MOUSE_BUTTON_LEFT, true, at))
	await send(button(MOUSE_BUTTON_LEFT, false, at))
