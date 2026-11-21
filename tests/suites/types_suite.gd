extends "res://tests/test_suite.gd"
## Designer de tipos (E2; aceite 1 a 3 da especificação): criar um tipo de entidade, um campo personalizado com validação e um vínculo
## personalizado entre dois tipos, tudo como dado, sem mudar código; e que isso sobrevive a fechar e reabrir.
## As linhas "ERROR" das recusas são esperadas.

const UiKit = preload("res://scripts/ui/ui_kit.gd")


## Pela interface (cena): o designer cria tipo, campo com limite e vínculo; o menu "＋ Novo" e a ficha passam a mostrá-los.
func _ui() -> void:
	var hub = main.domains
	var panel = main.types.types_panel
	panel.open_dialog()
	panel._type_name.text = "Fortaleza"
	panel.type_requested.emit(panel._type_name.text)
	var kinds: Array = UiKit.all_kinds()
	if not kinds.has("fortaleza") or hub.search._new_pop.get_item_text(kinds.find("fortaleza")) != "Fortaleza":
		return fail("o tipo criado no designer aparece no menu Novo: " + panel._message.text)
	panel._field_name.text = "Guarnição"
	panel._field_type.select(1)
	panel._min.text = "0"
	panel._max.text = "5000"
	for c in panel._kind_checks.get_children():
		if c is CheckBox:
			c.button_pressed = c.get_meta("code") == "fortaleza"
	await frames(1)
	panel._request_field()
	panel._rel_out.text = "Protege"
	panel._rel_in.text = "Protegida por"
	panel._rel_src.select(panel._codes.find("fortaleza") + 1)
	panel.relation_requested.emit(panel._rel_out.text, panel._rel_in.text, panel._menu_code(panel._rel_src), "")
	hub.search._query.text = "Castelo"
	hub.search._on_new(kinds.find("fortaleza"))
	var id: int = hub.current()
	if id == 0 or hub.registry.Kind(id) != "fortaleza" or hub.sheet._title.text != "Ficha · Fortaleza":
		return fail("criar uma Fortaleza pelo menu abre a ficha do tipo novo: " + hub.sheet._title.text)
	var fields: Array = hub.registry.FieldsFor("fortaleza")
	if fields.size() != 1 or not hub.registry.LinkTypesFor("fortaleza").any(func(t): return t.code == "protege"):
		return fail("campo e vínculo criados pelo designer: %s" % [fields])
	panel._layer_name.text = "Fortificações"
	for c in panel._layer_checks.get_children():
		c.button_pressed = c.get_meta("code") == "fortaleza"
	panel.layer_requested.emit(panel._layer_name.text, 0x996633, panel._checked(panel._layer_checks))
	if not hub.presence_panel._checks.has("fortificacoes") or not hub.presence_panel.layers().has("fortificacoes"):
		return fail("a camada criada no designer aparece marcada em Presenças no mapa: " + panel._message.text)
	ok("designer pela interface: tipo no menu Novo, ficha do tipo novo, campo com limite e vínculo e camada nova em Presenças")


func run() -> void:
	if main != null:
		await _ui()
		return
	var path := out_dir.path_join("types_suite.db")
	for ext in ["", "-journal"]:
		DirAccess.remove_absolute(path + ext)
	var reg = load("res://scripts/world/Registry.cs").new()
	reg.Open(path)

	# 1. Tipo novo.
	var fort: String = reg.CreateEntityType("Fortaleza")
	var city: String = reg.CreateEntityType("Cidade")
	if fort != "fortaleza" or city != "cidade" or reg.CreateEntityType("fortaleza") != null:
		return fail("criar tipos (código pelo nome; nome repetido recusado): %s %s" % [fort, city])
	var guard: String = reg.CreateEntityType("Forte São José!")
	if guard != "forte_sao_jose":
		return fail("o código tira acentos e símbolos: " + guard)
	var types: Array = reg.EntityTypes()
	if types.size() != 11 or not types[0].builtin or types[-1].code != "forte_sao_jose" or types[-1].builtin:
		return fail("a lista de tipos tem os 8 de fábrica e depois os criados: %s" % [types])
	var castle: int = reg.Create(fort, "Castelo Negro")
	var town: int = reg.Create(city, "Vila Alta")
	if castle == 0 or reg.Kind(castle) != "fortaleza" or reg.Create("inexistente", "X") != null:
		return fail("entidades do tipo novo são criadas; tipo inexistente é recusado")
	ok("tipos criados pela interface: código estável, nome repetido recusado, entidades do tipo novo")

	# 2. Campo com validação.
	var garrison: String = reg.AddField("Guarnição", "number", "soldados", "", PackedStringArray([fort]))
	reg.SetFieldLimits(garrison, 0, 5000)
	reg.SetField(castle, garrison, "known", "1200")
	reg.SetField(castle, garrison, "known", "9000")  # acima do máximo: recusado
	reg.SetField(castle, garrison, "known", "-3")    # abaixo do mínimo: recusado
	if reg.GetField(castle, garrison).value != "1200":
		return fail("o campo guarda 1200 e recusa valores fora de 0 a 5000: %s" % [reg.GetField(castle, garrison)])
	reg.SetField(town, garrison, "known", "10")  # o campo não se aplica a Cidade
	if reg.GetField(town, garrison).state != "unfilled":
		return fail("o campo só vale para o tipo escolhido")
	var fields: Array = reg.FieldsFor(fort)
	if fields.size() != 1 or not String(fields[0].hint).contains("5000"):
		return fail("a ficha do tipo novo mostra o campo e o limite: %s" % [fields])
	ok("campo personalizado com mínimo e máximo, só no tipo escolhido")

	# 3. Vínculo personalizado entre dois tipos.
	var guards: String = reg.CreateRelationType("Protege", "Protegida por", fort, city)
	if guards != "protege" or reg.CreateRelationType("X", "Y", "nada", "") != null:
		return fail("criar vínculo (tipo inexistente recusado): " + guards)
	if not reg.LinkTypesFor(fort).any(func(t): return t.code == "protege"):
		return fail("o vínculo aparece para o tipo de origem")
	reg.Link(castle, town, guards)
	var sheet: Dictionary = reg.Sheet(castle, 0)
	if sheet == null or not str(sheet).contains("Vila Alta"):
		return fail("a ficha da fortaleza mostra o vínculo com a cidade")
	ok("vínculo personalizado entre os dois tipos novos")

	# 4 e 5. Uma geometria desenhada ligada à fortaleza, e uma camada nova do mapa para ver as fortalezas.
	var builtin_layers: Array = reg.MapLayers()
	if builtin_layers.size() != 6 or not builtin_layers[0].kinds.has("pais") or not builtin_layers[0].kinds.has("provincia"):
		return fail("as 6 camadas de fábrica vêm com os seus tipos: %s" % [builtin_layers])
	var walls: int = reg.AddPolygonPlace("Muralhas", "regiao", PackedFloat64Array([10, 10, 10, 14, 13, 14, 13, 10]), "")
	reg.AddPresence(castle, walls, "territorio", "alta")
	var all_layers := PackedStringArray(["politica", "cultural", "etnica", "linguistica", "religiosa", "racial"])
	if reg.MapItems(all_layers, castle, 0).size() != 0:
		return fail("antes de ter camada, a fortaleza não aparece em nenhuma camada de fábrica")
	var forts: String = reg.CreateMapLayer("Fortificações", 0x996633, PackedStringArray([fort, guard]))
	var items: Array = reg.MapItems(PackedStringArray([forts]), 0, 0)
	if forts != "fortificacoes" or items.size() != 1 or items[0].entity_id != castle or items[0].layer != forts or items[0].vertices.size() != 8:
		return fail("a camada nova mostra o contorno desenhado da fortaleza: %s" % [items])
	if reg.MapItems(all_layers, castle, 0).size() != 0 or reg.CreateMapLayer("fortificações", 0, PackedStringArray([fort])) != null:
		return fail("a fortaleza só está na camada nova; nome repetido é recusado")
	if reg.EntitiesAt(11.5, 12, 1, PackedStringArray([forts]), 0, 0).size() != 1:
		return fail("clicar dentro do contorno acha a fortaleza pela camada nova")
	ok("geometria desenhada ligada à fortaleza e camada nova do mapa que a mostra (aceite 4 e 5)")

	reg.Close()
	reg.Open(path)
	if reg.MapItems(PackedStringArray(["fortificacoes"]), 0, 0).size() != 1:
		return fail("a camada nova sobrevive a reabrir")
	if reg.Kind(castle) != "fortaleza" or reg.GetField(castle, garrison).value != "1200" or reg.EntityTypes().size() != 11:
		return fail("fechar e reabrir conserva tipos, campos e valores")
	reg.Close()
	ok("fechar e reabrir conserva tudo")
