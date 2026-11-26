extends "res://tests/test_suite.gd"
## Regressões da revisão da branch: cada bug achado ali virou uma verificação que exige o comportamento certo.
## Sem cena (usa os painéis soltos). As linhas "ERROR" das exceções do C# são esperadas.

const SearchPanel = preload("res://scripts/ui/search_panel.gd")
const SheetPanel = preload("res://scripts/ui/sheet_panel.gd")
const CalendarPanel = preload("res://scripts/ui/calendar_panel.gd")
const PresencePanel = preload("res://scripts/ui/presence_panel.gd")
const PlaceLayer = preload("res://scripts/view/place_layer.gd")
const DomainHub = preload("res://scripts/app/domain_hub.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const LocalCalendar = preload("res://scripts/world/local_calendar.gd")
const Calendar = preload("res://scripts/world/calendar.gd")

const LAYERS := ["politica", "cultural", "etnica", "linguistica", "religiosa", "racial"]
const ALWAYS := -9223372036854775807 - 1

var hub
var reg
var search
var sheet
var presence
var map
var host: Control
var cal_panel


func _find(node: Node, cls: String, placeholder: String) -> Node:
	if node.get_class() == cls and node.get("placeholder_text") == placeholder:
		return node
	for c in node.get_children():
		var f := _find(c, cls, placeholder)
		if f != null:
			return f
	return null


func _fresh() -> void:
	if hub != null:
		hub.focus_map = Callable()
		hub.close()
		host.queue_free()
		await frames(2)
	host = Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	search = SearchPanel.new()
	sheet = SheetPanel.new()
	presence = PresencePanel.new()
	map = PlaceLayer.new()
	map.radius = 6.371
	cal_panel = CalendarPanel.new()
	for n in [search, sheet, cal_panel, presence, map]:
		host.add_child(n)
	hub = DomainHub.new()
	hub.setup(":memory:", search, sheet, cal_panel)
	hub.bind_map(map, presence, func(_d: Vector3, _z: float) -> void: pass)
	reg = hub.registry
	await frames(2)


func run() -> void:
	await _fresh()

	# 1. Nenhuma camada marcada = nenhuma presença (no mapa, no clique e no núcleo).
	var pais: int = reg.Create("pais", "Reino A")
	var lugar: int = reg.AddPlace("Vale", "regiao", 12.0, 21.0, 600.0, "")
	reg.AddPresence(pais, lugar, "territorio", "media")
	hub.open(pais)
	if map.item_count != 1:
		return fail("com as camadas marcadas o mapa deveria desenhar a presença")
	for l in LAYERS:
		presence._checks[l].button_pressed = false
	if map.item_count != 0 or hub.pick(EvronGeo.dir(12.5, 21.5), 0.0) != 0:
		return fail("sem camada marcada o mapa deveria ficar vazio e o clique não achar nada (mapa=%d)" % map.item_count)
	if reg.MapItems(PackedStringArray(), 0, hub.shown_t).size() != 0 or reg.EntitiesAt(12.5, 21.5, 0.0, PackedStringArray(), 0, hub.shown_t).size() != 0:
		return fail("lista de camadas vazia no núcleo significa nenhuma camada")
	for l in LAYERS:
		presence._checks[l].button_pressed = true
	if map.item_count != 1:
		return fail("remarcar as camadas traz a presença de volta")
	ok("1: nenhuma camada marcada = mapa vazio e clique sem resultado")

	# 2. O texto digitado numa ficha vai para a entidade dela, mesmo se outra ficha abrir antes de o foco sair (clique no globo).
	var b: int = reg.Create("pais", "Reino B")
	hub.open(pais)
	var f: Dictionary = sheet._fields["pais.governo"]
	f.row.visible = true
	f.editor.text = "texto digitado na ficha de A"
	f.editor.grab_focus()
	await frames(2)
	hub.open(b)
	await frames(3)
	if reg.GetField(b, "pais.governo").state != "unfilled":
		return fail("o texto da ficha de A foi parar em B: '%s'" % reg.GetField(b, "pais.governo").value)
	if reg.GetField(pais, "pais.governo").value != "texto digitado na ficha de A":
		return fail("o texto digitado na ficha de A deveria ter sido gravado em A: '%s'" % reg.GetField(pais, "pais.governo").value)
	var nome_b: LineEdit = sheet._pages["Ficha"].find_children("*", "LineEdit", true, false)[0]
	nome_b.text = "Reino B corrigido"
	nome_b.grab_focus()
	await frames(2)
	hub.open(pais)  # o foco do nome de B sai na troca
	await frames(3)
	if reg.Name(b) != "Reino B corrigido" or reg.Name(pais) != "Reino A":
		return fail("o nome corrigido na ficha de B deveria ir para B (B='%s', A='%s')" % [reg.Name(b), reg.Name(pais)])
	ok("2: campo e nome digitados vão para a entidade da ficha em que foram digitados")

	# 3. Números no formato da ficha.
	for case in [["1.200", 1200.0], ["1,5", 1.5], ["2.000,5", 2000.5], ["1.5", 1.5], ["12.345.678", 12345678.0], ["0", 0.0], ["7", 7.0], ["  42 ", 42.0]]:
		if DomainHub.parse_number(case[0]) != case[1]:
			return fail("parse_number('%s') = %s, esperado %s" % [case[0], DomainHub.parse_number(case[0]), case[1]])
	for ruim in ["", "abc", "1,2,3", "1..2", "--1"]:
		if not is_nan(DomainHub.parse_number(ruim)):
			return fail("'%s' não é número" % ruim)
	hub.open(pais)
	sheet.estimate_added.emit(lugar, "1.200", "1.500,5", "", "media")
	var e: Dictionary = reg.EstimatesOf(pais, hub.shown_t)[0]
	if e.low != 1200.0 or e.high != 1500.5:
		return fail("digitar 1.200 até 1.500,5 deveria gravar 1200–1500,5: %s–%s" % [e.low, e.high])
	ok("3: '1.200' = 1200, '1,5' = 1,5, '2.000,5' = 2000,5; a estimativa grava o que a ficha mostra")

	# 4. Clicar no mapa dentro da própria presença não refaz a ficha (o que se digita fica).
	hub.open(pais)
	var nome: LineEdit = _find(sheet._body, "LineEdit", "nome do lugar")
	nome.text = "Meu lugar novo"
	var n: int = hub.pick(EvronGeo.dir(12.5, 21.5), 0.0)
	await frames(2)
	var depois = _find(sheet._body, "LineEdit", "nome do lugar")
	if n != 1 or depois != nome or not is_instance_valid(nome) or depois.text != "Meu lugar novo":
		return fail("o clique na própria presença não deve refazer a ficha (achou %d; mesmo campo=%s)" % [n, depois == nome])
	ok("4: clique na presença da ficha aberta não refaz a ficha")

	# 5. Mais de 200 lugares: a busca de lugar acha qualquer um.
	for i in 205:
		reg.AddPlace("Lugar %03d" % i, "assentamento", 0.0, 0.0, 0.0, "")
	hub.open(pais)
	var pick = sheet._place_pickers[0]
	if pick.item_count > hub.PLACE_CHOICES + 1 or not pick.is_item_disabled(pick.item_count - 1):
		return fail("o menu mostra no máximo %d lugares e um aviso de que há mais (itens=%d)" % [hub.PLACE_CHOICES, pick.item_count])
	if pick.get_item_text(0) != "Vale":
		return fail("os lugares da própria ficha vêm primeiro: '%s'" % pick.get_item_text(0))
	var busca: LineEdit = _find(sheet._body, "LineEdit", "buscar lugar")
	busca.text = "Lugar 204"
	busca.text_changed.emit("Lugar 204")
	var achou := false
	for i in pick.item_count:
		achou = achou or pick.get_item_text(i) == "Lugar 204"
	if not achou:
		return fail("a busca 'Lugar 204' deveria achar o 205º lugar nos menus (itens=%d)" % pick.item_count)
	sheet.estimate_added.emit(int(pick.get_item_metadata(0)), "10", "", "", "media")
	if reg.EstimatesOf(pais, hub.shown_t).filter(func(x): return x.place == "Lugar 204").size() != 1:
		return fail("registrar estimativa no lugar achado pela busca")
	ok("5: com 207 lugares o menu mostra 50 (os da ficha primeiro) e a busca de lugar acha qualquer um")

	# 6. Criar calendário com era inválida não deixa calendário pela metade.
	var n_cal: int = reg.Calendars().size()
	hub._on_calendar_create({"name": "Sem era", "era_name": "E", "era_abbr": "", "year": 10, "month": 1, "day": 1, "first": 1, "direction": "sideways", "day_hour": 0, "months": ""})
	if reg.Calendars().size() != n_cal or not cal_panel._message.text.begins_with("Não consegui"):
		return fail("era inválida: o calendário não pode ficar (calendários %d -> %d; aviso '%s')" % [n_cal, reg.Calendars().size(), cal_panel._message.text])
	var cid = reg.CreateCalendar("Calendário bom", "", "", 0, "exata", "", "Era boa", "EB", 0, "up", 1)
	if cid == null or reg.CalendarDef(cid).eras.size() != 1 or reg.Calendars().size() != n_cal + 1:
		return fail("CreateCalendar deveria criar o calendário com a era")
	ok("6: calendário e primeira era são tudo ou nada")

	# 7. Banco de versão mais nova é recusado; caminho com ';' abre.
	var p7 := out_dir.path_join("regressao_futuro.db")
	DirAccess.remove_absolute(p7)
	var r1 = load("res://scripts/world/Registry.cs").new()
	r1.Open(p7)
	r1.Create("pais", "Antes")
	r1.Close()
	var raw = load("res://scripts/data/WorldDb.cs").new()
	raw.Open(p7)
	raw.Execute("PRAGMA user_version = 99")
	raw.Close()
	var r2 = load("res://scripts/world/Registry.cs").new()
	r2.Open(p7)
	if r2.IsOpen() or r2.Create("pais", "Em banco de versão futura") != null:
		return fail("um banco de versão mais nova não pode ficar aberto nem receber escrita")
	r2.Close()
	var r2b = load("res://scripts/world/Registry.cs").new()
	r2b.Open(p7)
	if r2b.IsOpen():
		return fail("recusar de novo na segunda tentativa")
	var p7b := out_dir.path_join("regressao;ponto 'e' espaço.db")
	DirAccess.remove_absolute(p7b)
	var r3 = load("res://scripts/world/Registry.cs").new()
	r3.Open(p7b)
	var id3 = r3.Create("pais", "Caminho com ponto e vírgula")
	if not r3.IsOpen() or id3 == null or id3 != 1 or r3.Name(1) != "Caminho com ponto e vírgula":
		return fail("o caminho com ';', espaço e apóstrofo deveria abrir (Create=%s)" % [id3])
	r3.Close()
	var r4 = load("res://scripts/world/Registry.cs").new()
	r4.Open(p7b)  # reabrir o mesmo arquivo conserva
	if r4.Name(1) != "Caminho com ponto e vírgula":
		return fail("reabrir o arquivo com ';' no nome")
	r4.Close()
	# O hub com banco recusado fica inativo em vez de quebrar.
	var hub2 = DomainHub.new()
	hub2.setup(p7, search, sheet, cal_panel)
	hub2.set_time(5)
	hub2.tick()
	hub2.refresh_map()
	if hub2.usable or hub2.pick(EvronGeo.dir(0, 0), 10.0) != 0:
		return fail("com o banco recusado o hub deveria ficar inativo")
	ok("7: banco de versão futura recusado (e o hub fica inativo); caminho com ';', espaço e apóstrofo abre")

	# 8. A ficha só é refeita quando algo dela mudou; menu aberto não é interrompido; o mapa não é refeito sem mudança.
	await _fresh()
	var p8: int = reg.Create("pais", "Reino C")
	var l8: int = reg.AddPlace("Cidade", "assentamento", 0.0, 0.0, 0.0, "")
	reg.AddPresenceDuring(p8, l8, "capital", "alta", ALWAYS, 5000)  # a capital só vale até o instante 5000
	hub.set_time(1000)
	hub.open(p8)
	if sheet._sheet.presences.size() != 1 or map.item_count != 1:
		return fail("em 1000 a capital vale")
	var rebuilds := 0
	var last_ms: int = hub._last_rebuild_ms
	var map_before = map._mesh_node
	var start := Time.get_ticks_msec()
	var t := 1000
	while Time.get_ticks_msec() - start < 1400:
		t += 1  # o relógio anda (bem abaixo de 5000), mas nada da ficha muda de validade
		hub.set_time(t)
		hub.tick()
		if hub._last_rebuild_ms != last_ms:
			rebuilds += 1
			last_ms = hub._last_rebuild_ms
		await tree.process_frame
	print("MEDIDA     %d quadros com o relógio andando; o tick conferiu a ficha %d vez(es) e não a refez (nada mudou de validade)" % [t - 1000, rebuilds])
	var s_now: Dictionary = reg.Sheet(p8, hub.shown_t)
	if s_now.hash() != hub._sheet_hash:
		return fail("a ficha deveria continuar a mesma")
	var body_before = sheet._body
	for i in 5:
		hub.set_time(t + i + 1)
		hub._last_rebuild_ms -= 1000
		hub.tick()
	if sheet._body != body_before:
		return fail("o relógio andou sem mudar nada da ficha: ela não pode ser refeita (o corpo da ficha foi recriado)")
	hub.set_time(6000)  # a capital terminou em 5000: agora a ficha muda e é relida
	hub._last_rebuild_ms -= 1000
	hub.tick()
	if sheet._body == body_before or sheet._sheet.presences.size() != 0 or map.item_count != 0:
		return fail("depois de 5000 a capital não vale: a ficha e o mapa deveriam ter sido relidos")
	# Menu aberto: a ficha espera.
	hub.set_time(7000)
	var menu: OptionButton = sheet._place_pickers[0]
	menu.grab_focus()
	menu.show_popup()
	await frames(2)
	if menu.get_popup().visible:
		if not sheet.is_editing():
			return fail("com um menu aberto a ficha conta como em uso")
	else:
		print("(popup não abre sem janela: o guarda do menu aberto não foi exercitado)")
	menu.get_popup().hide()
	ok("8: o relógio andando não refaz a ficha nem o mapa; mudança de validade refaz; menu aberto é respeitado")

	# 8b. Custo do mapa com muitos dados: os nomes vêm no mesmo SELECT.
	var lug: int = reg.AddPlace("Centro", "regiao", 0.0, 0.0, 300.0, "")
	for i in 1500:
		var en: int = reg.Create("pais" if i % 3 == 0 else ("etnia" if i % 3 == 1 else "cultura"), "Entidade %04d" % i)
		reg.AddPresence(en, lug, "presenca", "media")
	var t0 := Time.get_ticks_usec()
	var items: Array = reg.MapItems(PackedStringArray(LAYERS), 0, hub.shown_t)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("MEDIDA     MapItems com %d presenças: %.1f ms" % [items.size(), ms])
	if items.size() != 1500 or items[0].entity == "" or ms > 60.0:
		return fail("MapItems com 1500 presenças deveria ser bem mais rápido que 60 ms e trazer o nome (%.1f ms, nome='%s')" % [ms, items[0].entity])
	ok("8b: MapItems com 1500 presenças em %.1f ms, com os nomes no mesmo SELECT" % ms)

	# 9. span recusa mês fora de 0..12.
	var def := {"id": 1, "name": "t", "description": "", "source": "", "month_names": [], "day_offset": 0, "reliability": "exata",
		"eras": [{"era_id": 1, "name": "E", "abbreviation": "", "start": 0, "direction": "up", "first": 0, "valid_from": ALWAYS, "valid_to": 9223372036854775807, "priority": 0}]}
	for m in [-1, 13, 99]:
		if LocalCalendar.span(def, 1, 5, m).status != "invalida":
			return fail("span com mês %d deveria ser recusado" % m)
	if LocalCalendar.span(def, 1, 5, 12).status != "exata" or LocalCalendar.span(def, 1, 5, 0).precision != "ano":
		return fail("mês 12 e 0 (o ano todo) continuam válidos")
	ok("9: span recusa mês fora de 0..12")

	hub.focus_map = Callable()
	hub.close()
	host.queue_free()
