extends "res://tests/test_suite.gd"
## Dividir e reivindicar território (aceite A03), com a cena: o botão Dividir da ficha entra no pincel de fronteira; uma linha de borda a borda tira
## um lado, que vira um país novo com a identidade copiada; as presenças e quem aponta para o original ficam com ele; a província que fica
## toda do lado que sai passa para o país novo; um desfazer volta tudo (cadastro, vínculos e pintura) e o refazer repete.
## Reivindicação: uma camada própria, pintada por cima do território de outro país sem mudar a fronteira; a ficha diz o que cada um
## reivindica e de quem; gravada e relida; excluir o país leva a reivindicação no mesmo desfazer.

const Geo = preload("res://scripts/data/evron_geo.gd")


func _paint(layer, center: Vector3, radius: float, owner: int) -> void:
	layer.Begin()
	layer.Dab(center, radius, owner, false, -1)
	layer.End()


func _cut(tool) -> String:
	var points := PackedVector3Array()
	for i in 33:  # de uma borda à outra pelo meridiano 0 (o país tem ~8,1° de raio)
		points.append(Geo.dir(8.2 - i * 16.4 / 32.0, 0.0))
	var result: Dictionary = tool._make_plan(points)
	if not result.has("plan"):
		return String(result.get("message", "sem plano"))
	tool._points = points
	tool._plan = result.plan
	tool.apply_preview()
	return ""


func run() -> void:
	if main == null:
		return fail("esta suíte precisa da cena")
	var hub = main.domains
	var r = hub.registry
	var terr = main.territories
	var aren: int = r.Create("pais", "Aren")
	var idioma: int = r.Create("idioma", "Arenês")
	r.Link(aren, idioma, "idioma_oficial")
	r.SetSummary(aren, "um reino")
	var capital: int = r.AddPlace("Valdória", "assentamento", 0.0, -4.0, 0.0, "")
	r.AddPresence(aren, capital, "capital", "alta")
	var leste: int = r.Create("provincia", "Leste")
	var oeste: int = r.Create("provincia", "Oeste")
	r.Link(leste, aren, "provincia_de")
	r.Link(oeste, aren, "provincia_de")
	_paint(main.territory, Geo.dir(0, 0), 900, aren)
	var provinces = terr.layer("provincia")
	_paint(provinces, Geo.dir(0, 4), 250, leste)
	_paint(provinces, Geo.dir(0, -4), 250, oeste)
	terr.refresh_palette()
	var whole: float = main.territory.AreaKm2(aren)
	hub.open(aren)
	await frames(3)

	hub.sheet.territory_split_requested.emit()
	await frames(2)
	if not terr.splitting or terr.territory_mode != "fronteira" or terr.territory_owner != aren:
		return fail("Dividir deve abrir o pincel de fronteira de Aren no modo de dividir")
	var tool = terr.boundary_tool
	tool.land_only = false
	var why := _cut(tool)
	if why != "":
		return fail("o traço de borda a borda deveria virar um plano: " + why)
	var parts: Array = []
	for p in r.Palette("pais"):
		if int(p.id) != aren and main.territory.AreaKm2(int(p.id)) > 0.0:
			parts.append(int(p.id))
	if parts.size() != 1:
		return fail("a divisão deveria criar um país novo com território (%d)" % parts.size())
	var novo: int = parts[0]
	var a: float = main.territory.AreaKm2(aren)
	var b: float = main.territory.AreaKm2(novo)
	if absf(a + b - whole) > whole * 0.001 or a < whole * 0.3 or b < whole * 0.3:
		return fail("as duas partes deveriam somar o todo e ter cada uma uma boa parte: %.0f + %.0f de %.0f" % [a, b, whole])
	var west_owner: int = main.territory.OwnerAt(Geo.dir(0, -4))
	var east_owner: int = main.territory.OwnerAt(Geo.dir(0, 4))
	if west_owner == east_owner or not (west_owner in [aren, novo]) or not (east_owner in [aren, novo]):
		return fail("cada lado da linha deveria ter um dono")
	if r.Summary(novo) != "um reino" or r.Name(novo) != "Aren (parte)":
		return fail("o país novo copia a identidade: %s / %s" % [r.Summary(novo), r.Name(novo)])
	var links_novo = r.Sheet(novo, hub.shown_t).links.filter(func(l): return l.outgoing and l.type == "idioma_oficial")
	if links_novo.size() != 1 or r.PresencesOf(novo, hub.shown_t).size() != 0 or r.PresencesOf(aren, hub.shown_t).size() != 1:
		return fail("o país novo leva o idioma oficial; a capital fica com o original")
	var moved: int = leste if east_owner == novo else oeste
	var stayed: int = oeste if moved == leste else leste
	if int(r.TerritoryParent(moved)) != novo or int(r.TerritoryParent(stayed)) != aren or provinces.AreaKm2(moved) <= 0.0:
		return fail("a província do lado que sai passa para o país novo com a área; a outra fica")
	if not main.commands.undo_name().begins_with("Dividir Aren"):
		return fail("um comando só, com nome: " + main.commands.undo_name())
	ok("dividir: a linha de borda a borda cria o país novo com o lado que sai, a identidade copiada e a província desse lado; a capital fica")

	main.undo()
	await frames(2)
	if r.Kind(novo) != "" or absf(main.territory.AreaKm2(aren) - whole) > 1.0 or int(r.TerritoryParent(moved)) != aren or provinces.AreaKm2(moved) <= 0.0:
		return fail("desfazer volta o país inteiro, apaga o novo e devolve a província")
	main.redo()
	await frames(2)
	if r.Kind(novo) != "pais" or absf(main.territory.AreaKm2(novo) - b) > 1.0 or int(r.TerritoryParent(moved)) != novo:
		return fail("refazer repete a divisão com o mesmo id")
	ok("dividir: um desfazer volta cadastro, vínculos e pintura; refazer repete")

	# Uma linha que não separa nada (só toca a borda) não cria nada.
	main.undo()
	await frames(1)
	var count: int = r.Count("pais")
	var short := PackedVector3Array([Geo.dir(8.2, -1.0), Geo.dir(8.2, 1.0)])
	var result: Dictionary = tool._make_plan(short)
	if result.has("plan"):
		tool._plan = result.plan
		tool.apply_preview()
	if r.Count("pais") != count:
		return fail("um traço que não separa nada não deveria criar país")
	terr.stop_painting()
	if terr.splitting:
		return fail("Terminar sai do modo de dividir")
	ok("dividir: traço que não separa nada não cria cadastro; Terminar sai do modo")
	await _claims()


func _claims() -> void:
	var hub = main.domains
	var r = hub.registry
	var terr = main.territories
	var dravia: int = r.Create("pais", "Dravia")
	var merid: int = r.Create("pais", "Merídia")
	_paint(main.territory, Geo.dir(-30, 60), 600, dravia)
	_paint(main.territory, Geo.dir(-30, 72), 500, merid)
	terr.refresh_palette()
	var meridia_area: float = main.territory.AreaKm2(merid)
	hub.open(dravia)
	await frames(2)
	hub.sheet.territory_claim_requested.emit()
	await frames(2)
	if not terr.painting_territory or terr.territory_level != "reivindicacao" or terr.territory_owner != dravia:
		return fail("Pintar reivindicação deve pintar a camada das reivindicações por Dravia")
	terr.set_territory_protect(false)
	terr.territory_begin(Geo.dir(-30, 72))
	terr.territory_drag(Geo.dir(-30, 73))
	terr.territory_end()
	var claims = terr.layer("reivindicacao")
	if claims.OwnerAt(Geo.dir(-30, 72)) != dravia or main.territory.OwnerAt(Geo.dir(-30, 72)) != merid or main.territory.AreaKm2(merid) != meridia_area:
		return fail("a reivindicação cobre Merídia sem tirar nada da soberania dela")
	terr.stop_painting()
	await frames(2)
	if terr.territory_level != "pais" or terr.overlay_level != "reivindicacao" or not terr.area_hatched() or terr.area_gray():
		return fail("terminada a reivindicação, o mapa volta aos países com ela em listras (sem cinza)")
	main.globe.focus(Geo.dir(-30, 66), 1.5)
	await frames(30)
	await save("reivindicacao")
	var info: Dictionary = terr.claims_of(dravia)
	var over_meridia := 0.0
	for c in info.claims:
		if int(c.id) == merid:
			over_meridia = float(c.km2)
	var by: Array = terr.claims_of(merid).claimed_by
	if over_meridia <= 0.0 or by.size() != 1 or int(by[0].id) != dravia:
		return fail("a ficha diz quanto Dravia reivindica de Merídia, e a de Merídia diz quem a reivindica: %s / %s" % [info, by])
	hub.open(merid)
	await frames(2)
	if not hub.sheet._geo.territory.has("claims"):
		return fail("a ficha do país traz as reivindicações")
	ok("reivindicação: camada própria por cima de outro país, soberania intacta, listras no mapa e a ficha dos dois lados")

	# Gravada e relida (o banco aceita o nível novo).
	if not terr.save():
		return fail("gravar a camada das reivindicações")
	var again = Territory_new()
	again.Setup(main.terrain)
	if not r.LoadTerritoryLevel("reivindicacao", again) or again.OwnerAt(Geo.dir(-30, 72)) != dravia:
		return fail("a reivindicação gravada deveria voltar ao reler")
	ok("reivindicação: gravada no banco e relida")

	# Excluir Dravia leva a reivindicação; o desfazer devolve as duas coisas.
	hub._delete_target = dravia
	hub._on_delete()
	if claims.OwnerAt(Geo.dir(-30, 72)) != 0 or r.Kind(dravia) != "":
		return fail("excluir o país apaga a reivindicação dele")
	main.undo()
	await frames(2)
	if claims.OwnerAt(Geo.dir(-30, 72)) != dravia or main.territory.OwnerAt(Geo.dir(-30, 60)) != dravia:
		return fail("desfazer a exclusão devolve território e reivindicação")
	ok("reivindicação: sai com o país excluído e volta com o desfazer")


func Territory_new():
	return load("res://scripts/world/Territory.cs").new()
