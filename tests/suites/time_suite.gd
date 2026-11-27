extends "res://tests/test_suite.gd"
## A barra de tempo na cena de verdade: abre pausada, os botões movem o presente, a câmera e o mouse não,
## a consulta aparece e o ponto fixado mostra a data exibida.

const Calendar = preload("res://scripts/world/calendar.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")


func run() -> void:
	var clock = main.clock
	var bar = main.time_bar
	var t0: int = clock.now
	if clock.running or t0 != Calendar.to_seconds(1, 1, 1):
		return fail("deveria abrir pausado no cenário técnico (1º de janeiro do ano 1)")
	main.globe.camera.look_at_dir(EvronGeo.dir(10.0, 40.0), 2.0)
	await frames(30)
	if clock.now != t0:
		return fail("girar a câmera e rodar quadros pausado não deveria mover o calendário")
	if not bar._date.text.begins_with("1 de janeiro de 1") or not bar._state.text.contains("pausado"):
		return fail("a barra deveria mostrar a data e 'pausado': %s | %s" % [bar._date.text, bar._state.text])

	_press(bar, "+1 dia")
	_press(bar, "+7 dias")
	_press(bar, "+1 mês")
	var want := Calendar.add_months(t0 + 8 * Calendar.DAY, 1)
	if clock.now != want:
		return fail("+1 dia, +7 dias e +1 mês deveriam levar a %s, está em %s" % [Calendar.format(want), Calendar.format(clock.now)])
	if not bar._markers.text.contains("✔"):
		return fail("o marco demonstrativo (10 dias) deveria constar como ocorrido")
	main.select(EvronGeo.dir(30.0, 20.0))
	var at_now: String = main.layer_panel._selection.text
	if not at_now.contains("Camada de teste (demonstrativa)") or not at_now.contains(Calendar.format(clock.now, false)):
		return fail("o ponto fixado deveria mostrar a camada de teste na data exibida: " + at_now)

	# Consulta: muda o que se vê, não o presente; os avanços ficam desativados; voltar ao presente retorna pausado.
	clock.enter_view(Calendar.to_seconds(-110, 6, 1))
	await frames(2)
	if clock.now != want or not bar._state.text.contains("CONSULTA") or not bar._advance_buttons[0].disabled:
		return fail("em consulta a barra deveria avisar e desativar os avanços")
	var at_past: String = main.layer_panel._selection.text
	if at_past == at_now or not at_past.contains("indisponível"):
		return fail("em consulta, o ponto fixado deveria mostrar a data consultada e 'indisponível': " + at_past)
	clock.exit_view()
	await frames(2)
	if clock.viewing or clock.running or clock.now != want or bar._advance_buttons[0].disabled:
		return fail("voltar ao presente: pausado, presente intacto, avanços de volta")

	# Reproduzir: o botão retoma, o tempo corre, pausar para. Data inválida na janela não chega ao relógio.
	var before: int = clock.now
	_press(bar, "Continuar")
	await frames(10)
	if not clock.running or clock.now <= before:
		return fail("'Continuar' deveria pôr o tempo para correr")
	_press(bar, "Pausar")
	var stopped: int = clock.now
	await frames(10)
	if clock.running or clock.now != stopped:
		return fail("'Pausar' deveria parar o tempo")
	bar._fields["day"].value = 30
	bar._fields["month"].select(1)  # 30 de fevereiro
	bar._emit_date(bar.advance_to)
	if clock.now != stopped or not bar._message.text.contains("inválida"):
		return fail("30 de fevereiro deveria ser recusado na janela com um aviso")
	# Camada sazonal: o shader recebe o peso de julho da data exibida e o ponto fixado declara estimativa e incerteza.
	var season := _layer_index("Temperatura — sazonal (estimada)")
	main.set_layer(season)
	var mat: ShaderMaterial = main.material.material
	if mat.get_shader_parameter("mode") != 3 or main.legend._title.text != "Temperatura sazonal (estimada)":
		return fail("a camada sazonal deveria usar o modo 3 e a legenda própria")
	clock.enter_view(Calendar.to_seconds(3, 1, 15, 12))
	await save("4_temperatura_janeiro")
	if mat.get_shader_parameter("season_july") != 0.0:
		return fail("em 15 de janeiro o peso de julho deveria ser 0")
	clock.enter_view(Calendar.to_seconds(3, 7, 15, 12))
	await save("4_temperatura_julho")
	if mat.get_shader_parameter("season_july") != 1.0:
		return fail("em 15 de julho o peso de julho deveria ser 1")
	main.select(EvronGeo.dir(45.0, 10.0))
	var text: String = main.layer_panel._selection.text
	for piece in ["Temperatura:", "estimado", "Origem:", "Incerteza:", "15 de julho de 3"]:
		if not text.contains(piece):
			return fail("o ponto fixado deveria conter '%s': %s" % [piece, text])
	clock.exit_view()
	main.set_layer(0)
	bar._window.visible = true
	await save("3_barra_de_tempo")
	await _go_back_by_hand(clock, bar)
	ok("barra de tempo: abre pausada, avanços, consulta, retomar e pausar")


## Voltar a uma data como o usuário: abrir a janela (vem na data mostrada), clicar no campo e digitar, sem selecionar nada antes.
func _go_back_by_hand(clock, bar) -> void:
	clock.advance_to(Calendar.to_seconds(14, 3, 9))
	main.production.settlement_id = main.domains.registry.CreateSettlement("Vila do teste", 10.0, 40.0, 10)
	main.production.panel.visible = true
	main.production.panel.show_screen("povoado")
	main.production.refresh()
	bar._window.visible = false
	bar.find_children("*", "Button", true, false).filter(func(b): return b.tooltip_text.begins_with("Calendário"))[0].pressed.emit()
	await frames(5)
	var d := Calendar.from_seconds(clock.now)
	if [int(bar._fields["day"].value), bar._fields["month"].selected + 1, int(bar._fields["year"].value)] != [d["day"], d["month"], d["year"]]:
		return fail("a janela do calendário deveria abrir na data mostrada")
	var year: LineEdit = bar._fields["year"].get_line_edit()
	await _click(year)
	await send(_typed("2"))
	await _click(_button_named(bar, "Consultar data"))
	await frames(5)
	if not clock.viewing or Calendar.from_seconds(clock.shown())["year"] != 2:
		return fail("digitar 2 no ano e consultar deveria mostrar o ano 2, mostrou " + Calendar.format(clock.shown()))
	await save("3_data_passada")
	if main.production.panel.stock_title.text != "Estoque em " + Calendar.format(clock.shown(), false):
		return fail("o painel de povoados deveria seguir a data consultada: " + main.production.panel.stock_title.text)
	clock.exit_view()
	if main.production.panel.stock_title.text != "Estoque em " + Calendar.format(clock.now, false):
		return fail("ao voltar ao presente, o painel de povoados deveria voltar à data atual")
	main.production.panel.visible = false


func _click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await send(motion(p, Vector2.ZERO))
	await send(button(MOUSE_BUTTON_LEFT, true, p))
	await send(button(MOUSE_BUTTON_LEFT, false, p))
	await frames(2)


func _typed(ch: String) -> InputEventKey:
	var e := key(OS.find_keycode_from_string(ch))
	e.unicode = ch.unicode_at(0)
	return e


func _button_named(bar: Node, text: String) -> Button:
	for b in bar.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func _layer_index(menu: String) -> int:
	for i in MapLayers.LAYERS.size():
		if MapLayers.LAYERS[i]["menu"] == menu:
			return i
	fail("camada não encontrada: " + menu)
	return 0


func _press(bar: Node, text: String) -> void:
	for b in bar.find_children("*", "Button", true, false):
		if (b.text == text or b.tooltip_text == text) and not b.disabled:  # o play é só ícone: a dica diz Continuar/Pausar
			b.pressed.emit()
			return
	fail("botão não encontrado ou desativado: " + text)
