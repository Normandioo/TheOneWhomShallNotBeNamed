extends "res://tests/test_suite.gd"
## O alto da tela e a janela única: categorias, seleção que sobrevive ao fechar a janela, uma janela por vez, números e avisos.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")


func run() -> void:
	var hub = main.domains
	var reg = hub.registry
	var sheet = hub.sheet
	var windows = main.windows
	var top = main.top_hud
	await frames(3)
	if windows.window_open() or not top.category_buttons["ficha"].disabled or top.category_buttons["recursos"].disabled:
		return fail("sem seleção o mapa abre livre, com as categorias do cadastro desligadas e as do mundo ligadas")
	ok("sem seleção: nenhuma janela, e só as categorias do mundo ligadas")

	var aren: int = reg.Create("pais", "Aren")
	var province: int = reg.Create("provincia", "Alta Aren")
	reg.Link(province, aren, "provincia_de")
	hub.open(aren)
	await frames(2)
	if not sheet.visible or top._name.text != "AREN" or top.category_buttons["povo"].disabled:
		return fail("abrir um país mostra a janela e o põe no emblema: %s" % top._name.text)
	var texts: Array = top.stat_buttons.map(func(b): return b.text)
	if not texts.has("sem total") or not texts.has("1 divisão"):
		return fail("os números do alto: %s" % [texts])
	var tips: Array = windows.alerts.get_children().map(func(b): return b.tooltip_text)
	if not tips.has("1 divisão sem território") or not tips.has("Sem população total") or not tips.has("Sem território pintado"):
		return fail("os avisos do país: %s" % [tips])
	ok("o alto mostra o país, os números e os avisos")

	top.category_buttons["populacao"].pressed.emit()
	if not sheet.visible or sheet.active_page() != "População" or not top.category_buttons["populacao"].button_pressed:
		return fail("o botão População abre a página dela e fica marcado")
	sheet.total_set.emit("5000")
	await frames(2)
	if not top.stat_buttons.any(func(b): return b.text == "5.000") or windows.alerts.get_children().any(func(b): return b.tooltip_text == "Sem população total"):
		return fail("definir o total atualiza o número do alto e tira o aviso")
	top.category_buttons["populacao"].pressed.emit()
	if sheet.visible or hub.current() != aren or top._name.text != "AREN":
		return fail("apertar de novo fecha a janela e o país continua selecionado")
	hub.set_time(hub.shown_t + 86400)  # o relógio andou: a ficha é relida sem reabrir a janela
	hub.refresh_sheet()
	if sheet.visible:
		return fail("reler a ficha não pode reabrir a janela fechada")
	ok("a categoria abre e fecha a janela; fechada, a seleção continua e o relógio não a reabre")

	top.category_buttons["povo"].pressed.emit()
	hub.open(province)
	if not sheet.visible or sheet.active_page() != "Povo":
		return fail("a categoria escolhida continua ao trocar de cadastro: %s" % sheet.active_page())
	var search = main._dock["search"]
	var resources = main._dock["resources"]
	top.category_buttons["recursos"].pressed.emit()
	if not resources.visible or sheet.visible or search.visible:
		return fail("Recursos toma o lugar da ficha")
	windows.toggle_registry()
	if not search.visible or resources.visible or sheet.visible:
		return fail("os Registros tomam o lugar dos recursos")
	top.category_buttons["economia"].pressed.emit()
	if not main._dock["settlements"].visible or search.visible:
		return fail("a Economia toma o lugar dos Registros")
	top.category_buttons["ficha"].pressed.emit()
	if not sheet.visible or main._dock["settlements"].visible or sheet.active_page() != "Ficha":
		return fail("a Ficha toma o lugar da Economia")
	ok("uma janela por vez")

	windows.close_window()
	hub.deselect()
	await frames(2)
	if windows.window_open() or hub.current() != 0 or top._name.text != "MUNDO" or windows.alerts.get_child_count() != 0:
		return fail("tirar a seleção volta ao mundo")
	var faith: int = reg.Create("religiao", "Via do Sol")
	hub.open(faith)
	if not top.category_buttons["povo"].disabled or top.category_buttons["governo"].text != "Relações":
		return fail("numa religião não há Povo, e Governo vira Relações")
	ok("tirar a seleção; cadastros sem hierarquia têm Relações")

	# Minimizar o alto: sobra uma faixa fina, a janela sobe para o espaço livre; a escolha vale ao trocar de cadastro.
	hub.open(aren)
	await frames(4)
	var full_height: float = top.size.y
	var window_y: float = sheet.position.y
	top._fold.pressed.emit()
	await frames(6)
	if not top.minimized or top.category_buttons["ficha"].is_visible_in_tree() or top.size.y > 50.0 or sheet.position.y >= window_y - 40.0 or not sheet.visible:
		return fail("minimizado: faixa fina (%d px) e a janela sobe (%d -> %d)" % [top.size.y, window_y, sheet.position.y])
	hub.open(faith)
	await frames(4)
	if not top.minimized or top._mini_name.text != "VIA DO SOL":
		return fail("trocar de cadastro mantém o alto minimizado e atualiza o nome: %s" % top._mini_name.text)
	top._expand.pressed.emit()
	await frames(6)
	if top.minimized or not top.category_buttons["ficha"].is_visible_in_tree() or absf(top.size.y - full_height) > 1.0 or absf(sheet.position.y - window_y) > 1.0:
		return fail("expandir volta ao que era: %d de %d px" % [top.size.y, full_height])
	ok("o alto minimiza e expande, e a janela acompanha")

	# Pintar sem nada selecionado: primeiro o tipo; o mapa passa a mostrar esse tipo; o nome vem depois do desenho.
	hub.deselect()
	var terr = main.territories
	var card = main._dock["region_card"]
	var tapestry: int = reg.Create("cultura", "Tapeceiros")
	main.set_layer(0)  # começa no satélite: pintar leva ao mapa político do tipo
	main._start_territory()
	await frames(4)
	if not card.visible or not card.choosing or terr.drafting or terr.painting_territory or card._form.visible:
		return fail("sem seleção, antes de pintar vem só a pergunta do tipo")
	card._chips["cultura"].pressed.emit()
	await frames(4)
	if card.visible or not terr.drafting or terr.shown_kind() != "cultura" or MapLayers.LAYERS[main.layer]["kind"] != "political":
		return fail("escolhido o tipo, o pincel começa no mapa dele: %s, camada %d" % [terr.shown_kind(), main.layer])
	if terr._composed().size() != 2 or terr._composed()[1] != terr.layer("cultura") or main.mode_rail._level != "cultura":
		return fail("o mapa do rascunho de cultura mostra as culturas, e o painel de modos marca Cultura")
	terr.territory_radius = 400.0
	terr.territory_begin(EvronGeo.dir(10, 10))
	terr.territory_end()
	terr.stop_painting()
	await frames(4)
	if not card.visible or card.choosing or card._kind != "cultura" or card._title.text != "Nova cultura" or card._chip_row.visible:
		return fail("depois do desenho o cartão pede o nome, já com o tipo escolhido: %s" % card._title.text)
	card._change.pressed.emit()
	card._chips["religiao"].pressed.emit()
	if terr.shown_kind() != "religiao" or card._title.text != "Nova religião" or terr._composed()[1] != terr.layer("religiao"):
		return fail("trocar o tipo no cartão troca o mapa junto")
	card.discard_requested.emit()
	if terr.drafting or card.visible or reg.Count("religiao") != 1:
		return fail("descartar não cria nada")
	main._start_territory()
	card._discard.pressed.emit()  # Cancelar, na pergunta
	if card.visible or terr.drafting:
		return fail("cancelar a pergunta não começa pintura")
	ok("pintar sem seleção: o tipo vem antes, o mapa mostra esse tipo, o nome vem depois; dá para trocar e cancelar")

	# Pintando uma província, cada província aparece na própria cor (e não na do país); ao terminar, volta.
	var pal: Array = []
	var keep := func(entries: Array) -> void: pal.assign(entries)
	terr.palette_changed.connect(keep)
	var rgb_of := func(id: int) -> int:
		for e in pal:
			if int(e.id) == id:
				return int(e.rgb)
		return -1
	hub.open(province)
	terr.start_painting(province)
	if rgb_of.call(province) != int(reg.EntityColor(province)) or rgb_of.call(aren) == int(reg.EntityColor(aren)):
		return fail("pintando uma província, ela fica na própria cor e o país em cinza")
	terr.stop_painting()
	if rgb_of.call(province) != int(reg.EntityColor(aren)):
		return fail("terminada a pintura, a província volta à cor do país")
	terr.start_draft("provincia")
	if rgb_of.call(province) != int(reg.EntityColor(province)):
		return fail("no rascunho de província as que existem aparecem na própria cor")
	terr.discard_draft()
	terr.palette_changed.disconnect(keep)
	ok("pintando província, as divisões se distinguem")

	# Em 1280 × 720 nada do alto, dos modos ou da barra de ferramentas sai da tela nem se sobrepõe.
	var before: Vector2i = tree.root.size
	tree.root.size = Vector2i(1280, 720)
	hub.open(aren)
	await frames(10)
	var screen := Rect2(Vector2.ZERO, main.hud.size)
	var pieces := {"alto": main.top_hud, "tempo": main.tool_panel.world_block, "modos": main.mode_rail, "ferramentas": main.tool_panel, "janela": sheet}
	for name in pieces:
		if not screen.grow(1.0).encloses(pieces[name].get_global_rect()):
			return fail("em 1280×720 %s sai da tela: %s" % [name, pieces[name].get_global_rect()])
	for pair in [["alto", "tempo"], ["janela", "modos"], ["janela", "alto"], ["ferramentas", "modos"], ["ferramentas", "janela"]]:
		if pieces[pair[0]].get_global_rect().intersects(pieces[pair[1]].get_global_rect()):
			return fail("em 1280×720 %s e %s se sobrepõem" % pair)
	main.territories.start_painting(aren)
	await frames(6)
	if not screen.grow(1.0).encloses(main.territories.territory_panel.get_global_rect()) or main.tool_panel.visible:
		return fail("a barra de pintar cabe na tela e toma o lugar das ferramentas: %s" % main.territories.territory_panel.get_global_rect())
	main.territories.stop_painting()
	tree.root.size = before
	ok("1280 × 720: o alto, a janela, os modos e as barras cabem sem se sobrepor")
