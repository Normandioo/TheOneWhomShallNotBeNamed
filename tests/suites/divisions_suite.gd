extends "res://tests/test_suite.gd"
## Subdivisões: província e município são um tipo só, em dois níveis, com o nome que o autor der (estado, condado…). O nome próprio vale
## mais que o do país, um mundo antigo não perde nada, a árvore não para em 200, e o cartão cria já com o nome e dentro do lugar certo.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const WorldDb = preload("res://scripts/data/WorldDb.cs")


## A linha aberta edita nome, tipo do nome, população e cor, e filtra pelo nome, sem sair do país.
func _editing(aren: int, state: int, county: int) -> void:
	var hub = main.domains
	var reg = hub.registry
	var sheet = hub.sheet
	var terr = main.territories
	if terr._highlighted != county:
		return fail("a divisão aberta é a destacada no mapa: %d" % terr._highlighted)
	sheet.division_editor.name.text = "Vale Salgado"
	sheet.division_editor.name.text_submitted.emit("Vale Salgado")
	if reg.Name(county) != "Vale Salgado" or sheet.division_rows[county].text != "Vale Salgado":
		return fail("o nome muda na linha: %s" % reg.Name(county))
	sheet.division_editor.name.text = "Vale do Sal"
	sheet.division_editor.name.text_submitted.emit("Vale do Sal")
	sheet.division_editor.total.text = "abc"
	sheet.division_editor.total.text_submitted.emit("abc")
	if not sheet.division_editor.message.visible or reg.Sheet(county, hub.shown_t).population.has_total:
		return fail("população que não é número avisa e não grava")
	sheet.division_editor.total.text = "12.500"
	sheet.division_editor.total.text_submitted.emit("12.500")
	await frames(3)
	if reg.Sheet(county, hub.shown_t).population.total != 12500.0 or sheet.division_editor.total.text != "12.500" or hub.current() != aren:
		return fail("a população da linha: %s" % [reg.Sheet(county, hub.shown_t).population])
	sheet.division_editor.total.text = ""
	sheet.division_editor.total.text_submitted.emit("")
	await frames(3)
	if reg.Sheet(county, hub.shown_t).population.has_total:
		return fail("apagar o número tira o total")
	sheet.entity_color_changed.emit(county, 0x336699, true)
	if reg.EntityColor(county) != 0x336699:
		return fail("a cor da linha")
	sheet.division_named.emit(county, "Baronato")
	await frames(4)
	if reg.DivisionName(county) != "Baronato" or sheet.open_division != county:
		return fail("como se chama, pela linha")
	sheet.division_named.emit(county, "Condado")
	await frames(4)
	sheet.division_search.text = "zzz"
	sheet.division_search.text_changed.emit("zzz")
	await frames(2)
	if sheet.division_rows[state].is_visible_in_tree():
		return fail("o filtro esconde o que não casa")
	sheet.division_search.text = "sal"
	sheet.division_search.text_changed.emit("sal")
	await frames(2)
	if not sheet.division_rows[county].is_visible_in_tree() or not sheet.division_rows[state].is_visible_in_tree():
		return fail("o filtro acha a de dentro e mostra a de cima")
	sheet.division_search.text = ""
	sheet.division_search.text_changed.emit("")
	sheet.toggle_division(state)
	await frames(3)
	if sheet.division_editor.inside == null:
		return fail("uma do 1º nível oferece pintar dentro")
	sheet.division_editor.inside.pressed.emit()
	await frames(3)
	if not terr.drafting or terr._draft_parent != state:
		return fail("pintar dentro abre o rascunho já com a de cima: %d" % terr._draft_parent)
	terr.discard_draft()
	hub.open(aren)
	sheet.show_page("Território")
	await frames(3)
	sheet.open_division = 0
	sheet.toggle_division(county)
	await frames(3)
	sheet.division_editor.paint.pressed.emit()
	await frames(3)
	if not terr.painting_territory or terr.territory_owner != county or hub.current() != aren:
		return fail("pintar a área pela linha, com o país ainda aberto")
	terr.stop_painting()
	await frames(3)
	var empty: int = reg.Create("provincia", "Sem área")
	reg.Link(empty, aren, "provincia_de")
	hub.show_division(empty)
	await frames(3)
	if sheet.open_division != empty or terr._highlighted != aren or not sheet.division_editor.view.disabled:
		return fail("sem área pintada o destaque fica no país: %d" % terr._highlighted)
	reg.Delete(empty)
	sheet.open_division = 0
	sheet.toggle_division(county)
	await frames(3)


## Pintando uma divisão nova: não passa da fronteira de quem a contém nem por cima das irmãs, por nenhuma ferramenta.
func _borders() -> void:
	var hub = main.domains
	var reg = hub.registry
	var terr = main.territories
	var countries = main.territory
	var kept: Dictionary = {}
	var land: int = reg.Create("pais", "Borda")
	var other: int = reg.Create("pais", "Vizinho")
	for pair in [[land, 120.0], [other, 140.0]]:
		countries.Begin()
		countries.Dab(EvronGeo.dir(0, pair[1]), 1300.0, pair[0], false, -1)
		countries.End()
	var old: int = reg.Create("provincia", "Antiga")
	reg.Link(old, land, "provincia_de")
	var provinces = terr.layer("provincia")
	provinces.Begin()
	provinces.Dab(EvronGeo.dir(0, 116), 500.0, old, false, -1)
	provinces.End()
	terr.refresh_palette()
	kept[old] = provinces.AreaKm2(old)

	var only := func(map, allowed: int) -> bool:
		return terr.draft.OverlapKm2(map, terr.DRAFT).keys().all(func(o): return int(o) == allowed)
	var stroke := func(lon: float, radius: float) -> void:
		terr.territory_radius = radius
		terr.territory_land_only = false
		terr.territory_begin(EvronGeo.dir(0, lon))
		terr.territory_drag(EvronGeo.dir(0, lon + 25.0))  # arrasta até dentro do vizinho
		terr.territory_end()

	# Pedida pela ficha do país.
	hub.open(land)
	await frames(2)
	hub.sheet.paint_kind_requested.emit("provincia", land)
	await frames(2)
	stroke.call(122.0, 900.0)
	if terr.draft.AreaKm2(terr.DRAFT) <= 0.0 or not only.call(countries, land) or not only.call(provinces, 0):
		return fail("o pincel fica no país e fora da irmã: país %s, divisões %s" % [terr.draft.OverlapKm2(countries, terr.DRAFT), terr.draft.OverlapKm2(provinces, terr.DRAFT)])
	await save("subdivisao_limite")
	terr._set_territory_mode("balde")
	terr.territory_begin(EvronGeo.dir(5.0, 124.0))
	var free: float = countries.AreaKm2(land) - provinces.AreaKm2(old)
	if not only.call(countries, land) or not only.call(provinces, 0) or terr.draft.AreaKm2(terr.DRAFT) > free + 1.0:
		return fail("o balde enche só o que sobra do país: %.0f de %.0f" % [terr.draft.AreaKm2(terr.DRAFT), free])
	# Pincel de fronteira: um contorno grande, passando pelo vizinho e em volta da irmã, só fica com o que é livre no país.
	terr.draft.ClearOwner(terr.DRAFT)
	var loop := PackedVector3Array()
	for corner in [[-14.0, 104.0], [-14.0, 128.0], [-14.0, 150.0], [14.0, 150.0], [14.0, 128.0], [14.0, 104.0]]:
		loop.append(EvronGeo.dir(corner[0], corner[1]))
	var traced: Dictionary = terr.draft.PlanLoopClaim(terr.DRAFT, loop, 0, false)
	if not traced.has("plan") or terr.draft.ApplyBoundary(traced.plan) == null:
		return fail("o contorno deveria dar uma área: %s" % [traced])
	if terr.draft.AreaKm2(terr.DRAFT) <= 0.0 or not only.call(countries, land) or not only.call(provinces, 0):
		return fail("o contorno fica no país e fora da irmã: país %s, divisões %s" % [terr.draft.OverlapKm2(countries, terr.DRAFT), terr.draft.OverlapKm2(provinces, terr.DRAFT)])
	terr.discard_draft()
	await frames(2)

	# Pelo botão de baixo: o primeiro traço decide o país.
	hub.deselect()
	terr.start_draft("provincia")
	stroke.call(124.0, 900.0)
	if terr._draft_parent != land or not only.call(countries, land) or not only.call(provinces, 0):
		return fail("sem pedido, o primeiro traço escolhe o país e fica nele: %d" % terr._draft_parent)
	terr.territory_begin(EvronGeo.dir(0, 142))  # outro traço, já no vizinho: não pinta lá
	terr.territory_end()
	if not only.call(countries, land):
		return fail("depois do primeiro traço o país não muda")
	terr.discard_draft()
	await frames(2)

	# Começando sobre uma divisão: a nova fica dentro dela.
	terr.start_draft("provincia")
	stroke.call(116.0, 900.0)
	if terr._draft_parent != old or terr._draft_hint != "municipio" or not only.call(provinces, old):
		return fail("começando sobre uma divisão, fica dentro dela: %s %s" % [terr._draft_parent, terr.draft.OverlapKm2(provinces, terr.DRAFT)])
	terr.stop_painting()
	await frames(3)
	var card = main._dock["region_card"]
	card._create.pressed.emit()
	await frames(5)
	var inner: int = hub.sheet.open_division
	if reg.Kind(inner) != "municipio" or reg.TerritoryParent(inner) != old or absf(provinces.AreaKm2(old) - kept[old]) > 1.0:
		return fail("criada dentro, sem mexer na de cima: %s %.0f/%.0f" % [reg.Kind(inner), provinces.AreaKm2(old), kept[old]])
	for id in [inner, old, land, other]:
		terr.layer(String(reg.Kind(id))).ClearOwner(id)
		reg.Delete(id)
	hub.deselect()
	terr.refresh_palette()
	ok("pintando uma divisão nova: pincel, balde e contorno não passam da fronteira nem por cima das irmãs")


## "Não invadir" nos países: um país novo (ou um que já existe) passado por cima do vizinho encosta nele sem tomar nada; desligado, toma.
func _neighbors() -> void:
	var hub = main.domains
	var reg = hub.registry
	var terr = main.territories
	var countries = main.territory
	var neighbor: int = reg.Create("pais", "Antigo")
	countries.Begin()
	countries.Dab(EvronGeo.dir(0, 120.0), 900.0, neighbor, false, -1)
	countries.End()
	terr.refresh_palette()
	var before: float = countries.AreaKm2(neighbor)
	var stroke := func() -> void:  # do lado de fora até o meio do vizinho
		terr.territory_radius = 700.0
		terr.territory_land_only = false
		terr.territory_begin(EvronGeo.dir(0, 138.0))
		terr.territory_drag(EvronGeo.dir(0, 120.0))
		terr.territory_end()

	hub.deselect()
	terr.start_draft("pais")
	if not terr.territory_panel.protect_check.button_pressed:
		return fail("Não invadir começa ligado")
	stroke.call()
	if not terr.draft.OverlapKm2(countries, terr.DRAFT).keys().all(func(o): return int(o) == 0) or terr.draft.AreaKm2(terr.DRAFT) <= 0.0:
		return fail("o rascunho de um país não passa por cima do vizinho: %s" % [terr.draft.OverlapKm2(countries, terr.DRAFT)])
	terr.draft_create("pais", "Novo", 0)
	await frames(4)
	var made: int = hub.current()
	if absf(countries.AreaKm2(neighbor) - before) > 1.0 or countries.AreaKm2(made) <= 0.0:
		return fail("criar não tira nada do vizinho: %.0f -> %.0f" % [before, countries.AreaKm2(neighbor)])

	# Um país que já existe, pelo pincel e pelo balde.
	terr.start_painting(made)
	stroke.call()
	terr._set_territory_mode("balde")
	terr.territory_begin(EvronGeo.dir(0, 118.0))
	if absf(countries.AreaKm2(neighbor) - before) > 1.0:
		return fail("repintando um país, o vizinho continua inteiro: %.0f -> %.0f" % [before, countries.AreaKm2(neighbor)])
	if not terr.territory_panel._message.text.contains("Antigo"):
		return fail("a barra diz de quem é: " + terr.territory_panel._message.text)
	# Desligado, conquista como antes.
	terr.territory_panel.protect_check.button_pressed = false
	terr._set_territory_mode("pincel")
	stroke.call()
	if countries.AreaKm2(neighbor) >= before - 1.0:
		return fail("desligado, o pincel toma do vizinho")
	terr.stop_painting()
	# Fora da pintura a camada não fica protegida.
	countries.Begin()
	countries.Dab(EvronGeo.dir(0, 120.0), 200.0, made, false, -1)
	countries.End()
	if countries.OwnerAt(EvronGeo.dir(0, 120.0)) != made:
		return fail("a proteção sai quando a pintura termina")
	terr.territory_panel.protect_check.button_pressed = true
	for id in [made, neighbor]:
		countries.ClearOwner(id)
		reg.Delete(id)
	hub.deselect()
	terr.refresh_palette()
	ok("Não invadir: país novo e existente encostam no vizinho sem tomar; desligado, conquista")


func run() -> void:
	_old_world()
	if failed:
		return
	_names()
	if failed:
		return
	await _screen()
	if failed:
		return
	await _borders()
	if failed:
		return
	await _neighbors()


## Um mundo de antes desta mudança abre, guarda o que tinha e chama as divisões de Província e Município.
func _old_world() -> void:
	var path := out_dir.path_join("divisoes_%d.db" % Time.get_ticks_usec())
	var r = load("res://scripts/world/Registry.cs").new()
	r.Open(path)
	r.Close()
	var db = WorldDb.new()
	db.Open(path)
	var latest: int = db.SchemaVersion()
	db.Close()
	var old := out_dir.path_join("divisoes_antigo_%d.db" % Time.get_ticks_usec())
	r.OpenAtVersion(old, latest - 1)
	var country: int = r.Create("pais", "Aren")
	var province: int = r.Create("provincia", "Alta Aren")
	var town: int = r.Create("municipio", "Vila")
	r.Link(province, country, "provincia_de")
	r.Link(town, province, "municipio_de")
	r.Close()
	r.Open(old)
	if r.DivisionName(province) != "Província" or r.DivisionName(town) != "Município" or r.TerritoryParent(town) != province or r.CountryOf(town) != country:
		return fail("o mundo antigo deveria abrir com os nomes de sempre: %s / %s" % [r.DivisionName(province), r.DivisionName(town)])
	r.Close()
	ok("um mundo de antes abre sem perder nada: Província e Município")


func _names() -> void:
	var r = load("res://scripts/world/Registry.cs").new()
	r.Open(":memory:")
	var aren: int = r.Create("pais", "Aren")
	var dravia: int = r.Create("pais", "Dravia")
	var first: int = r.Create("provincia", "Alta Aren")
	r.Link(first, aren, "provincia_de")
	r.NameNewDivision(first, "Estado")
	if r.LevelName(aren, 1) != "Estado" or r.DivisionName(first) != "Estado" or r.LevelName(dravia, 1) != "Província":
		return fail("a primeira do nível dá o nome ao nível do país, e só dele")
	var second: int = r.Create("provincia", "Marca do Norte")
	r.Link(second, aren, "provincia_de")
	r.NameNewDivision(second, "Ducado")
	var inside: int = r.Create("municipio", "Vale")
	r.Link(inside, first, "municipio_de")
	r.NameNewDivision(inside, "Condado")
	if r.DivisionName(second) != "Ducado" or r.LevelName(aren, 1) != "Estado" or r.LevelName(aren, 2) != "Condado":
		return fail("a segunda diferente fica com nome próprio: %s, %s" % [r.DivisionName(second), r.LevelName(aren, 2)])
	r.SetLevelName(aren, 1, "Região")
	if r.DivisionName(first) != "Região" or r.DivisionName(second) != "Ducado":
		return fail("trocar o nível muda as que seguem o país e deixa a diferente: %s, %s" % [r.DivisionName(first), r.DivisionName(second)])
	var rows: Dictionary = {}
	for row in r.Outline(0):
		rows[int(row.id)] = row
	if rows[second].differs != true or rows[first].differs or rows[inside].label != "Condado" or int(rows[inside].parent) != first or rows[aren].label != "":
		return fail("a árvore traz o nome, o de cima e quem é diferente: %s" % [rows])
	r.SetDivisionName(second, "Região")
	r.SetLevelName(aren, 1, "Estado")
	if r.DivisionName(second) != "Estado":
		return fail("dar o nome do nível faz voltar a seguir o país")
	if r.DivisionName(aren) != "" or not "Condado" in Array(r.DivisionSuggestions()):
		return fail("país não tem nome de divisão; as sugestões trazem os nomes usados")
	var copy: int = r.Duplicate(first, true, "Cópia")
	if r.DivisionName(copy) != "Estado" or r.Sheet(first, 0).label != "Estado":
		return fail("a ficha e a cópia trazem o nome")
	r.SetDivisionName(second, "Ducado")
	if r.Delete(second) == null or r.Delete(aren) == null:
		return fail("excluir quem tem nome guardado não pode esbarrar no banco")
	if r.DivisionName(first) != "Província":
		return fail("sem o país, volta o nome padrão: %s" % r.DivisionName(first))
	for i in 230:
		var made: int = r.Create("provincia", "P%03d" % i)
		r.Link(made, dravia, "provincia_de")
	var all: Array = r.Outline(0).filter(func(x): return int(x.parent) == dravia)
	if all.size() != 230 or r.Search("", "provincia", "", 0, 0).size() != 200:
		return fail("a árvore traz todas (%d); a busca continua em 200" % all.size())
	if r.DeleteKinds(PackedStringArray(["pais", "provincia", "municipio"]), false) == null:
		return fail("apagar categorias com nomes guardados")
	r.Close()
	ok("nomes por país e por divisão, árvore sem limite, e excluir, copiar e apagar categorias sem sobra")


func _screen() -> void:
	var hub = main.domains
	var reg = hub.registry
	var terr = main.territories
	var card = main._dock["region_card"]
	await frames(3)
	var aren: int = reg.Create("pais", "Aren")
	main.territory.Begin()
	main.territory.Dab(EvronGeo.dir(0, 10), 1500.0, aren, false, -1)
	main.territory.End()
	terr.refresh_palette()

	var paint := func(radius: float) -> void:  # pelo caminho do mouse, que decide o lugar no primeiro traço
		terr.territory_radius = radius
		terr.territory_land_only = false
		terr.territory_begin(EvronGeo.dir(0, 10))
		terr.territory_end()
		terr.stop_painting()

	card.show_choice()
	if card._chips.has("municipio") or card._chips["provincia"].text != "Subdivisão":
		return fail("antes de pintar há um botão só para subdivisão")
	card.hide()
	terr.start_draft("provincia")
	paint.call(700.0)
	await frames(4)
	if not card.visible or card._title.text != "Nova subdivisão" or card._parent.get("id", 0) != aren or not card.name_chips.has("Estado") or card._create.text != "Criar província":
		return fail("o cartão da subdivisão: %s / %s / %s" % [card._title.text, card._parent, card._create.text])
	card.name_chips["Estado"].pressed.emit()
	await frames(2)
	if card._create.text != "Criar estado":
		return fail("o botão acompanha o nome escolhido: " + card._create.text)
	card._name.text = "Alta Aren"
	await save("subdivisao_cartao")
	card._create.pressed.emit()
	await frames(6)
	var sheet = hub.sheet
	var state: int = sheet.open_division
	if hub.current() != aren or sheet.active_page() != "Território" or not sheet.division_rows.has(state):
		return fail("criada, ela aparece aberta na lista do país: %s %s %s" % [hub.current(), sheet.active_page(), state])
	if reg.Kind(state) != "provincia" or reg.DivisionName(state) != "Estado" or reg.LevelName(aren, 1) != "Estado" or reg.TerritoryParent(state) != aren:
		return fail("criar pelo cartão faz um Estado de Aren: %s %s" % [reg.Kind(state), reg.DivisionName(state)])

	terr.start_draft("provincia")
	paint.call(200.0)  # bem dentro do estado: fica dentro dele
	await frames(4)
	if card._parent.get("id", 0) != state or card._kind != "municipio" or card._create.text != "Criar município":
		return fail("pintada dentro de um estado, a nova fica dentro dele: %s %s %s" % [card._parent, card._kind, card._create.text])
	card.name_chips["Condado"].pressed.emit()
	card._name.text = "Vale do Sal"
	await frames(2)
	card._create.pressed.emit()
	await frames(6)
	var county: int = sheet.open_division
	if reg.Kind(county) != "municipio" or reg.TerritoryParent(county) != state or reg.DivisionName(county) != "Condado":
		return fail("o segundo nível: %s %s" % [reg.Kind(county), reg.DivisionName(county)])
	if hub.current() != aren or sheet.division_editor.get("id", 0) != county or not sheet.division_rows[state].is_visible_in_tree():
		return fail("a de dentro abre na lista, com a de cima à vista")
	await save("subdivisao_lista")
	await _editing(aren, state, county)
	if failed:
		return
	sheet.division_editor.full.pressed.emit()
	await frames(4)
	if hub.current() != county or sheet.division_picker == null or sheet._title.text.find("Condado") < 0 or sheet.back_button == null:
		return fail("a ficha completa mostra como ela se chama e o botão de voltar: " + sheet._title.text)
	var shown: String = main._dock["search"]._tree_items[county].get_text(0)
	if shown != "Vale do Sal · Condado":
		return fail("os Registros mostram o nome do tipo: " + shown)
	sheet.show_page("Governo")
	await frames(3)
	await save("subdivisao_ficha")
	sheet.back_button.pressed.emit()
	await frames(4)
	if hub.current() != aren or sheet.open_division != county or sheet.active_page() != "Território":
		return fail("voltar leva à lista do país com a linha aberta")

	# Pelos Registros e pelo mapa: o país com a linha aberta.
	hub.deselect()
	await frames(2)
	main._dock["search"].entity_chosen.emit(state)
	await frames(4)
	if hub.current() != aren or sheet.open_division != state:
		return fail("escolher nos Registros abre o país com a linha: %s %s" % [hub.current(), sheet.open_division])
	sheet.toggle_division(state)
	await frames(3)
	if sheet.open_division != 0 or terr._highlighted != aren:
		return fail("fechar a linha devolve o destaque ao país")
	terr.set_subdivisions_view(true)
	await frames(3)
	hub.pick(EvronGeo.dir(0, 10), 0.0)
	await frames(4)
	if hub.current() != aren or sheet.open_division != county or terr._highlighted != county:
		return fail("o clique na vista de subdivisões abre a linha da mais funda e a destaca: %s %s %s" % [hub.current(), sheet.open_division, terr._highlighted])
	await save("subdivisao_mapa")
	terr.set_subdivisions_view(false)
	sheet.show_page("Povo")
	await frames(3)
	if terr._highlighted != aren:
		return fail("fora da lista o destaque volta ao país")

	hub.open(aren)
	await frames(4)
	sheet.show_page("Território")
	await frames(3)
	sheet.level_toggle.pressed.emit()
	await frames(3)
	if sheet.level_pickers.size() != 2:
		return fail("a ficha do país diz como os dois níveis se chamam")
	var menu: OptionButton = sheet.level_pickers[0].menu
	for i in menu.item_count:
		if menu.get_item_text(i) == "Ducado":
			menu.select(i)
			menu.item_selected.emit(i)
	await frames(6)
	if reg.DivisionName(state) != "Ducado" or sheet.level_pickers[0].menu.get_item_text(sheet.level_pickers[0].menu.selected) != "Ducado":
		return fail("trocar na ficha do país muda as divisões dele: " + reg.DivisionName(state))
	await save("subdivisao_pais")
	# Excluir pela lista: some a divisão, o país continua aberto.
	sheet.open_division = 0
	sheet.toggle_division(county)
	await frames(3)
	sheet.division_editor.remove.pressed.emit()
	sheet.delete_confirmed.emit()
	await frames(4)
	if hub.current() != aren or sheet.open_division != 0 or reg.Count("municipio") != 0 or terr.layer("municipio").AreaKm2(county) > 0.0:
		return fail("excluir pela lista mantém o país aberto e tira a área")
	var area = terr.layer("municipio")
	main.undo()  # o mesmo desfazer devolve o cadastro e a pintura
	await frames(3)
	if reg.Kind(county) != "municipio" or area.AreaKm2(county) <= 0.0 or hub.current() != aren:
		return fail("desfazer a exclusão devolve a subdivisão com a área pintada")
	main.redo()
	await frames(3)
	if reg.Count("municipio") != 0 or area.AreaKm2(county) > 0.0:
		return fail("refazer a exclusão tira de novo")
	ok("tela: um botão só, o cartão dá o nome e o lugar, o 2º nível vem de onde se pintou, e a ficha troca os nomes")
