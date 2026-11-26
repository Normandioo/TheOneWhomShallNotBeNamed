extends "res://tests/test_suite.gd"
## Opções → Cadastros: apagar categorias ou tudo, com cópia antes; nada sem confirmação nem sem cópia; e o banco continua íntegro.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const WorldDb = preload("res://scripts/data/WorldDb.cs")
const Calendar = preload("res://scripts/world/calendar.gd")


func run() -> void:
	var hub = main.domains
	var reg = hub.registry
	var options = main.options_panel
	var terr = main.territories
	main.backup_dir = out_dir.path_join("copias_%d" % Time.get_ticks_usec())
	await frames(3)

	var aren: int = reg.Create("pais", "Aren")
	var dravia: int = reg.Create("pais", "Dravia")
	var province: int = reg.Create("provincia", "Alta Aren")
	reg.Link(province, aren, "provincia_de")
	var town: int = reg.Create("municipio", "Vila")
	reg.Link(town, province, "municipio_de")
	var culture: int = reg.Create("cultura", "Tecelões")
	var faith: int = reg.Create("religiao", "Via do Sol")
	var port: int = reg.AddPlace("Porto", "assentamento", 2.0, 2.0, 0.0, "")
	reg.AddPresence(aren, port, "capital", "media")
	var empty_place: int = reg.AddPlace("Ruína solta", "regiao", 10.0, 10.0, 0.0, "")
	reg.SetTotal(aren, hub.shown_t, 5000.0)
	reg.AddEstimate(aren, port, hub.shown_t, 100.0, 100.0, "alta", "")
	reg.AddTag(aren, "antigo")
	# Um recurso com quem o conhece e quem tem direito: era o que fazia excluir um cadastro falhar.
	var salt = reg.CreateResourceType("Sal")
	var point: int = reg.AddPoint(salt.Id, 1.0, 1.0).Id
	reg.AddKnowledge(point, dravia, 0, 9223372036854775807, 10.0, "")
	reg.AddRight(point, dravia, "controle", 0, 9223372036854775807, "")
	reg.CreateSettlement("Povoado", 1.0, 1.0, 20)
	if reg.Delete(dravia) == null or reg.Search("Dravia", "pais", "", 0, hub.shown_t).size() != 0:
		return fail("excluir um cadastro que conhece um recurso e tem direito sobre ele deve funcionar")
	ok("excluir um cadastro com conhecimento e direito sobre um recurso funciona (antes o banco recusava)")

	var paint := func(layer, owner: int, lon: float) -> void:
		layer.Begin()
		layer.Dab(EvronGeo.dir(0, lon), 500.0, owner, false, -1)
		layer.End()
	paint.call(main.territory, aren, 0.0)
	paint.call(terr.layer("provincia"), province, 0.0)
	paint.call(terr.layer("cultura"), culture, 30.0)
	terr.refresh_palette()
	terr.flush()
	hub.open(aren)
	await frames(3)

	# A seção: contagens, nada marcado, e nada acontece sem a palavra de confirmação.
	options.open("cadastros")
	await frames(4)
	if options._header_note.text != options.RECORDS_NOTE:
		return fail("na seção Cadastros o topo avisa que o mundo muda: %s" % options._header_note.text)
	options.show_section("tela")
	if options._header_note.text != options.OPTIONS_NOTE:
		return fail("nas outras seções o topo volta ao normal: %s" % options._header_note.text)
	options.show_section("cadastros")
	await frames(2)
	if options.record_checks["pais"].text != "Países (1)" or options.record_checks["provincia"].text != "Subdivisões de 1º nível (1)" or not options.record_checks["raca"].disabled:
		return fail("as contagens: %s / %s" % [options.record_checks["pais"].text, options.record_checks["provincia"].text])
	if not options.delete_button.disabled or options.confirm_box.is_visible_in_tree():
		return fail("nada marcado: o botão de apagar fica desligado")
	options.record_checks["pais"].button_pressed = true
	options.delete_button.pressed.emit()
	await frames(3)
	var text: String = options.confirm_text.text
	if not options.confirm_box.is_visible_in_tree() or not text.contains("Países: 1") or not text.contains("subdivisões de 1º nível continuam no mundo, sem país") or not options.confirm_button.disabled:
		return fail("a confirmação diz o que sai e o que fica: %s" % text)
	options.confirm_edit.text = "apagar"
	options.confirm_edit.text_changed.emit("apagar")
	options.confirm_button.pressed.emit()
	if reg.Count("pais") != 1 or not options.confirm_button.disabled:
		return fail("sem a palavra exata nada é apagado")
	options.record_checks["religiao"].button_pressed = true
	if options.confirm_box.is_visible_in_tree():
		return fail("mudar o que está marcado pede nova confirmação")
	ok("seção Cadastros: contagens, avisos, e só apaga com a palavra APAGAR depois de ver o que sai")

	# Sem conseguir guardar a cópia, nada é apagado.
	var blocked := out_dir.path_join("nao_e_pasta.txt")
	FileAccess.open(blocked, FileAccess.WRITE).store_string("x")
	var good_dir: String = main.backup_dir
	main.backup_dir = blocked.path_join("copias")
	var refused: Dictionary = main.records.run(["pais"], false)
	if refused.ok or reg.Count("pais") != 1 or main.territory.AreaKm2(aren) <= 0.0 or not refused.message.begins_with("Nada foi apagado"):
		return fail("sem cópia nada é apagado: %s" % refused.message)
	main.backup_dir = good_dir
	ok("se a cópia falha, nada é apagado")

	# Só as províncias, pela tela.
	options._mark_all(false)
	options.record_checks["provincia"].button_pressed = true
	_confirm(options)
	await frames(5)
	if reg.Count("provincia") != 0 or reg.Count("pais") != 1 or reg.Count("municipio") != 1 or terr.layer("provincia").AreaKm2(province) > 0.0 or main.territory.AreaKm2(aren) <= 0.0:
		return fail("só as províncias: %d províncias, %d países, área do país %.0f" % [reg.Count("provincia"), reg.Count("pais"), main.territory.AreaKm2(aren)])
	if not options.result_label.is_visible_in_tree() or not options.result_label.text.begins_with("1 cadastro apagado"):
		return fail("o resultado: %s" % options.result_label.text)
	var copy: String = options._backup_path
	if reg.CheckWorld(copy) != "":
		return fail("a cópia deve ser um mundo importável: %s" % reg.CheckWorld(copy))
	if _count(copy, "select count(*) from entity where kind = 'provincia'") != 1:
		return fail("a cópia guarda o que foi apagado")
	ok("apagar só uma categoria: sai o cadastro e o território dele, o resto fica, e a cópia guarda o de antes")

	# Tudo, com os lugares soltos.
	hub.open(aren)
	await frames(3)
	options.open("cadastros")
	options.refresh_records()
	options._mark_all(true)
	_confirm(options)
	await frames(8)
	for kind in ["pais", "provincia", "municipio", "cultura", "etnia", "raca", "religiao", "idioma"]:
		if reg.Count(kind) != 0:
			return fail("tudo marcado: sobrou %d de %s" % [reg.Count(kind), kind])
	if hub.current() != 0 or main.windows.window_open() or main.top_hud._name.text != "MUNDO":
		return fail("depois de apagar não há seleção nem ficha: %s" % main.top_hud._name.text)
	if reg.Places("").size() != 0 or main.territory.AreaKm2(aren) > 0.0 or terr.layer("cultura").AreaKm2(culture) > 0.0:
		return fail("lugares soltos e territórios saem: %d lugares" % reg.Places("").size())
	if reg.ResourceTypes("").size() != 1 or reg.Settlements().size() != 1:
		return fail("recursos e povoados continuam")
	if not main._dock["search"]._summary.begins_with("0 países · 0 cadastros"):
		return fail("o alto e os Registros se atualizam: %s" % main._dock["search"]._summary)
	main.undo()  # o desfazer não traz de volta o território de quem não existe mais
	await frames(2)
	if main.territory.AreaKm2(aren) > 0.0:
		return fail("o Ctrl+Z não pode devolver território a um cadastro apagado")
	var check := out_dir.path_join("integridade_%d.world" % Time.get_ticks_usec())
	if reg.ExportWorld(check, "") != "" or _count(check, "select count(*) from pragma_foreign_key_check") != 0:
		return fail("o banco precisa continuar íntegro")
	var after: int = reg.Create("pais", "Novo")
	if after == 0 or main.territory.AreaKm2(after) > 0.0:
		return fail("dá para criar de novo, sem herdar território: %d" % after)
	ok("apagar tudo: nenhum cadastro, território ou lugar solto sobra; recursos e povoados ficam; o banco continua íntegro")

	# A seção cabe em 1280 × 720, com a confirmação aberta.
	var before: Vector2i = tree.root.size
	tree.root.size = Vector2i(1280, 720)
	await frames(8)
	options.open("cadastros")
	options.refresh_records()
	options._mark_all(true)
	options.delete_button.pressed.emit()
	await frames(8)
	if not Rect2(Vector2.ZERO, main.hud.size).grow(1.0).encloses(options._panel.get_global_rect()):
		return fail("em 1280×720 o menu sai da tela: %s" % options._panel.get_global_rect())
	var view: Rect2 = options.pages["cadastros"].get_global_rect()
	if not view.grow(2.0).encloses(options.confirm_button.get_global_rect()):
		return fail("o botão de confirmar fica à vista: %s em %s" % [options.confirm_button.get_global_rect(), view])
	tree.root.size = before
	options.close()
	ok("1280 × 720: a confirmação cabe e o botão fica à vista")


func _confirm(options) -> void:
	options.delete_button.pressed.emit()
	options.confirm_edit.text = "APAGAR"
	options.confirm_edit.text_changed.emit("APAGAR")
	options.confirm_button.pressed.emit()


## Uma contagem no banco de uma cópia exportada.
func _count(world_dir: String, sql: String) -> int:
	var db = WorldDb.new()
	db.Open(world_dir.path_join("world.sqlite"))
	var n: int = db.QueryLong(sql)
	db.Close()
	return n
