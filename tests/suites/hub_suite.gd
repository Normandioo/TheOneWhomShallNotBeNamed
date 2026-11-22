extends "res://tests/test_suite.gd"
## Os painéis de busca e de ficha ligados ao Registry pelo DomainHub, sem a cena principal (não precisa dos mapas):
## criar, preencher campos (com os estados), nomes, etiquetas, vínculos, duplicar, excluir e sociedade, pelos próprios widgets.
## As linhas "ERROR" das recusas são esperadas.

const SearchPanel = preload("res://scripts/ui/search_panel.gd")
const SheetPanel = preload("res://scripts/ui/sheet_panel.gd")
const CalendarPanel = preload("res://scripts/ui/calendar_panel.gd")
const Calendar = preload("res://scripts/world/calendar.gd")
const PresencePanel = preload("res://scripts/ui/presence_panel.gd")
const PlaceLayer = preload("res://scripts/view/place_layer.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const DomainHub = preload("res://scripts/app/domain_hub.gd")

var hub: DomainHub
var search: SearchPanel
var sheet: SheetPanel
var host: Control
var focused: Array = []  # chamadas de "centralizar o mapa" (sem globo, nos testes sem cena)


func _create(kind_index: int, name: String) -> int:
	search._query.text = name
	search._on_new(kind_index)
	return sheet.current_id()


func run() -> void:
	if main != null:  # com a cena: usa o hub do Main (o banco dele é ":memory:" nos testes)
		hub = main.domains
		search = hub.search
		sheet = hub.sheet
	else:
		host = Control.new()
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tree.root.add_child(host)
		search = SearchPanel.new()
		sheet = SheetPanel.new()
		host.add_child(search)
		host.add_child(sheet)
		var cal_panel := CalendarPanel.new()
		host.add_child(cal_panel)
		hub = DomainHub.new()
		hub.setup(":memory:", search, sheet, cal_panel)
		var presence := PresencePanel.new()
		var layer := PlaceLayer.new()
		layer.radius = 6.371
		host.add_child(presence)
		host.add_child(layer)
		hub.bind_map(layer, presence, func(dir: Vector3, zoom: float) -> void: focused.append([dir, zoom]))
	await frames(2)
	var reg = hub.registry

	# Criar pelo menu "Novo": o texto da busca vira o nome, e a ficha abre; sem texto, nome provisório.
	var pais := _create(1, "Reino de Aren")
	if pais == 0 or not sheet.visible or reg.Name(pais) != "Reino de Aren" or reg.Kind(pais) != "pais":
		return fail("criar país pelo painel")
	search._query.text = ""
	var sem_nome := _create(2, "")
	if reg.Name(sem_nome) != "Sem nome (Raça)":
		return fail("nome provisório: %s" % reg.Name(sem_nome))
	hub.open(pais)
	if search._list.item_count != 2 or search._ids.size() != 2:
		return fail("a lista de busca deveria ter 2 cadastros: %d" % search._list.item_count)
	ok("criar pelo painel: texto da busca vira o nome; sem texto, nome provisório; a lista acompanha")

	# Trocar de ficha só move a seleção do Índice: a árvore não é refeita (item é o mesmo objeto).
	var antes: TreeItem = search._tree_items[pais]
	hub.open(sem_nome)
	hub.open(pais)
	if search._tree_items[pais] != antes or search._tree_items[pais].get_tree().get_selected() != antes:
		return fail("trocar de ficha refez a árvore do Índice ou perdeu a seleção")
	ok("trocar de ficha move a seleção do Índice sem refazer a árvore")

	# Campos vazios ficam recolhidos; "Adicionar informação" revela um; digitar grava.
	var f: Dictionary = sheet._fields["pais.governo"]
	if f.row.visible or sheet._add_menu.item_count != 12 or not sheet._add_menu.visible:
		return fail("os 11 campos vazios deveriam estar recolhidos no menu (itens=%d)" % sheet._add_menu.item_count)
	var idx := -1
	for i in sheet._add_menu.item_count:
		if sheet._add_menu.get_item_metadata(i) == "pais.governo":
			idx = i
	sheet._add_menu.select(idx)
	sheet._add_menu.item_selected.emit(idx)
	if not f.row.visible or sheet._add_menu.item_count != 11:
		return fail("'Adicionar informação' deveria revelar o campo e tirá-lo do menu")
	f.editor.text = "Monarquia eletiva"
	f.editor.focus_exited.emit()
	if reg.GetField(pais, "pais.governo").value != "Monarquia eletiva":
		return fail("o texto digitado não foi gravado")
	f.state.select(1)  # Desconhecido
	f.state.item_selected.emit(1)
	if reg.GetField(pais, "pais.governo").state != "unknown" or f.editor.visible:
		return fail("'Desconhecido' deveria gravar o estado e esconder o editor")
	f.state.select(2)  # Não se aplica
	f.state.item_selected.emit(2)
	f.state.select(0)  # volta a Valor: o editor reaparece, vazio (o valor antigo foi trocado pelo estado)
	f.state.item_selected.emit(0)
	if reg.GetField(pais, "pais.governo").state != "unfilled" or not f.editor.visible:
		return fail("voltar a 'Valor' com o editor vazio deveria virar 'não preenchido': %s" % [reg.GetField(pais, "pais.governo")])
	ok("campos recolhidos, 'Adicionar informação', valor, desconhecido, não se aplica e retorno")

	# Número personalizado: vírgula decimal aceita, zero é valor, lixo é recusado e o editor volta ao que está gravado.
	var code: String = reg.AddField("Área", "number", "km²", "", PackedStringArray(["pais"]))
	hub.open(pais)
	var n: Dictionary = sheet._fields[code]
	n.row.visible = true
	n.editor.text = "1234,5"
	n.editor.text_submitted.emit("1234,5")
	if float(reg.GetField(pais, code).value) != 1234.5 or n.editor.text != "1234.5":
		return fail("número com vírgula: gravado=%s, editor=%s" % [reg.GetField(pais, code), n.editor.text])
	n.editor.text = "0"
	n.editor.text_submitted.emit("0")
	if reg.GetField(pais, code).state != "known" or float(reg.GetField(pais, code).value) != 0.0:
		return fail("zero deveria ser um valor conhecido")
	n.editor.text = "muito"
	n.editor.text_submitted.emit("muito")
	if n.editor.text != "0":
		return fail("um texto inválido deveria voltar ao valor gravado, mas o editor mostra '%s'" % n.editor.text)
	ok("número: vírgula decimal, zero é valor, texto inválido volta ao gravado")

	# Escolha e sim/não pelos OptionButton.
	var cod_esc: String = reg.AddField("Regime", "choice", "", "aberto\nfechado", PackedStringArray(["pais"]))
	hub.open(pais)
	var c: Dictionary = sheet._fields[cod_esc]
	c.editor.select(2)
	c.editor.item_selected.emit(2)
	if reg.GetField(pais, cod_esc).value != "fechado":
		return fail("escolha 'fechado' não gravou")
	ok("campo de escolha")

	# Nome: a correção chega ao registro e à busca; nome vazio é desfeito.
	hub.open(pais)
	var name_edit: LineEdit = sheet._pages["Geral"].get_child(0)
	name_edit.text = "Reino de Arên"
	name_edit.text_submitted.emit("Reino de Arên")
	if reg.Name(pais) != "Reino de Arên" or not search._list.get_item_text(search._ids.find(pais)).begins_with("Reino de Arên"):
		return fail("a correção do nome deveria chegar ao registro e à busca")
	name_edit.text = "   "
	name_edit.text_submitted.emit("   ")
	if name_edit.text != "Reino de Arên" or reg.Name(pais) != "Reino de Arên":
		return fail("nome vazio não pode ser aceito")
	ok("corrigir o nome atualiza o registro e a busca; nome vazio é desfeito")
	sheet._tab_buttons["Mapa"].pressed.emit()
	hub.open(pais)
	if sheet._active_tab != "Mapa" or not sheet._pages["Mapa"].visible or sheet._pages["Geral"].visible:
		return fail("atualizar a mesma ficha deve preservar a aba e mostrar só o conteúdo dela")
	sheet._tab_buttons["Geral"].pressed.emit()
	ok("abas separam o conteúdo e a ficha mantém a aba ativa ao atualizar")

	# Nomes alternativos e etiquetas.
	sheet.alias_added.emit("gentilico", "arenês")
	sheet.tag_added.emit("reino")
	sheet.tag_added.emit("antigo")
	sheet.tag_removed.emit("antigo")
	var s: Dictionary = reg.Sheet(pais, hub.shown_t)
	if reg.NamesWithRole(pais, "gentilico") != PackedStringArray(["arenês"]) or s.tags != PackedStringArray(["reino"]):
		return fail("nome alternativo ou etiquetas: %s" % [s.tags])
	ok("nome alternativo (gentílico) e etiquetas")

	# Vínculos: criar o idioma, achá-lo pelo painel de vínculo, vincular, abrir pela relação, apagar o vínculo.
	var idioma := _create(4, "Arenês antigo")
	hub.open(pais)
	if sheet._link_type == null or sheet._link_type.item_count < 5:
		return fail("o país deveria poder criar vários tipos de vínculo")
	for i in sheet._link_type.item_count:
		if sheet._types[i].code == "idioma_oficial":
			sheet._link_type.select(i)
			sheet._link_type.item_selected.emit(i)
	sheet._link_query.text = "arenês"
	sheet._link_query.text_changed.emit("arenês")
	if sheet._link_candidates.item_count != 1 or int(sheet._link_candidates.get_item_metadata(0)) != idioma:
		return fail("o candidato deveria ser só o idioma (filtrado pelo tipo do vínculo): %d itens" % sheet._link_candidates.item_count)
	sheet._link_candidates.select(0)
	sheet.link_added.emit("idioma_oficial", idioma)
	if reg.Linked(pais, "idioma_oficial", hub.shown_t, false) != [idioma]:
		return fail("vincular pela ficha")
	sheet.open_entity.emit(idioma)
	if sheet.current_id() != idioma or reg.Sheet(idioma, hub.shown_t).links.size() != 1:
		return fail("abrir o idioma pela relação")
	var link_id: int = reg.Sheet(idioma, hub.shown_t).links[0].id
	sheet.link_removed.emit(link_id)
	if reg.Sheet(idioma, hub.shown_t).links.size() != 0:
		return fail("apagar o vínculo")
	ok("vínculo pela ficha: candidatos filtrados pelo tipo, vincular, abrir pela relação, apagar")

	# Duplicar e excluir (com o aviso dos vínculos).
	hub.open(pais)
	sheet.link_added.emit("idioma_oficial", idioma)
	sheet.duplicate_requested.emit(true)
	var copia: int = sheet.current_id()
	if copia == pais or reg.Name(copia) != "Cópia de Reino de Arên" or reg.Sheet(copia, hub.shown_t).links.size() != 1:
		return fail("duplicar com vínculos")
	sheet.delete_requested.emit()
	if not sheet._confirm.dialog_text.contains("1 vínculo") or reg.Count("pais") != 2:
		return fail("o aviso de exclusão deveria citar 1 vínculo: %s" % sheet._confirm.dialog_text)
	sheet._confirm.hide()
	sheet.delete_confirmed.emit()
	if reg.Count("pais") != 1 or sheet.visible or hub.current() != 0:
		return fail("excluir a cópia")
	if reg.Sheet(pais, hub.shown_t).links.size() != 1:
		return fail("excluir a cópia não pode mexer nos vínculos da original")
	ok("duplicar (com vínculos), aviso e exclusão")

	# Sociedade e a busca por tipo e por nome.
	search._query.text = "Dravos"
	search._on_new(SearchPanel.SOCIETY_ID)
	if reg.Kind(sheet.current_id()) != "pais" or sheet._sheet.links.size() != 2:
		return fail("a sociedade deveria abrir o país com 2 relações")
	search._query.text = "dravos"
	search._query.text_changed.emit("dravos")
	if search._list.item_count != 3:
		return fail("a busca por 'dravos' deveria achar país, cultura e etnia: %d" % search._list.item_count)
	search._filter.select(2)  # País
	search._filter.item_selected.emit(2)
	if search._list.item_count != 1 or search.kind_filter() != "pais":
		return fail("filtro de tipo na busca")
	ok("sociedade (país+cultura+etnia) e busca com filtro de tipo")

	# Calendários: criar pelo painel, usar na ficha, e a data local acompanha a data mostrada.
	var cp = hub.calendars
	search.calendars_requested.emit()
	if not cp.visible or cp._list.item_count != 1:
		return fail("o painel de calendários deveria abrir, ainda sem calendários")
	cp._name.text = "Calendário de Aren"
	cp._era.text = "Era de Aren"
	cp._abbr.text = "EA"
	cp._year.value = 100
	cp._month.select(2)  # março
	cp._day.value = 15
	cp._first.value = 1
	cp._hour.value = 6
	cp._months.text = "Gelo
Neve
Brota
Chuva
Flor
Sol
Calor
Seca
Colheita
Névoa
Geada
Longa noite"
	cp._on_create()
	var cals: Array = reg.Calendars()
	if cals.size() != 1 or cp._message.text != "Calendário criado." or cp._list.item_count != 1:
		return fail("criar calendário pelo painel: %s / %s" % [cals, cp._message.text])
	var cal_id: int = cals[0].id
	var marco := Calendar.to_seconds(100, 3, 15) + 6 * Calendar.HOUR  # a meia-noite local (o dia vira às 6h)
	var def: Dictionary = reg.CalendarDef(cal_id)
	if def.eras[0].start != marco or def.day_offset != 6 * Calendar.HOUR or def.month_names[2] != "Brota":
		return fail("a definição criada: %s" % [def])
	cp._months.text = "Gelo
Neve"  # só 2 nomes
	cp._on_create()
	cp._name.text = "Outro"
	cp._on_create()
	cp._month.select(1)  # fevereiro
	cp._day.value = 30
	cp._months.text = ""
	cp._on_create()
	if reg.Calendars().size() != 1:
		return fail("um calendário inválido foi criado pelo painel (%d)" % reg.Calendars().size())
	ok("painel de calendários: cria com era, virada às 6h e nomes de mês; recusa 2 nomes de mês e 30 de fevereiro")

	hub.open(pais)
	if sheet._calendars.choices.size() != 1 or sheet._calendars.uses.size() != 0:
		return fail("a ficha deveria oferecer o calendário novo")
	sheet.calendar_use_added.emit(cal_id, "civil")
	var uso: Dictionary = reg.CalendarsOf(pais, hub.shown_t)[0]
	if uso.calendar_id != cal_id or uso.purpose != "civil" or not sheet._date_labels.has(int(uso.use_id)):
		return fail("usar o calendário pela ficha")
	hub.set_time(marco)
	var local_text: String = sheet._date_labels[int(uso.use_id)].text
	if local_text != "15 de Brota de 1 EA · 00:00" or sheet._universal_label.text != "Data universal: 15 de março de 100 · 06:00":
		return fail("data universal e local lado a lado: '%s' | '%s'" % [sheet._universal_label.text, local_text])
	hub.set_time(marco + 3 * Calendar.YEAR - 1)  # 1 s antes de completar 3 anos do marco: 14 de Brota (23:59) do ano 4 EA
	if not sheet._date_labels[int(uso.use_id)].text.begins_with("14 de Brota de 4 EA"):
		return fail("a data local deveria andar com o relógio: %s" % sheet._date_labels[int(uso.use_id)].text)
	if not hub._pending:
		return fail("mudar o tempo deveria marcar a ficha para ser relida")
	hub._last_rebuild_ms -= 1000
	hub.tick()
	if hub._pending:
		return fail("o tick deveria reler a ficha depois do intervalo")
	ok("ficha: usar um calendário, data universal e local lado a lado, segue o relógio e a ficha é relida pelo tick")

	var gen: int = reg.UseCalendar(pais, cal_id, "ritual", 0)
	hub.open(pais)
	sheet.calendar_use_removed.emit(gen)
	if reg.CalendarsOf(pais, hub.shown_t).size() != 1:
		return fail("apagar um uso pela ficha")
	if main != null:  # com a cena: o hub segue o relógio de verdade
		var t_consulta: int = Calendar.to_seconds(50, 6, 1)
		main.clock.enter_view(t_consulta)
		if hub.shown_t != t_consulta:
			return fail("o hub deveria mostrar a data de consulta do relógio: %d" % hub.shown_t)
		main.clock.exit_view()
		if hub.shown_t != main.clock.now:
			return fail("ao voltar ao presente o hub deveria mostrar o presente")
		ok("o hub segue o relógio do mundo (consulta e presente)")

	await _map_and_population(pais)
	if failed:
		return

	if DisplayServer.get_name() != "headless":
		search._filter.select(0)
		search._query.text = ""
		search._query.text_changed.emit("")
		cp.visible = false
		hub.open(pais)
		await frames(2)
		sheet._scroll.scroll_vertical = 100000
		await save("fichas_dominios")
		search.calendars_requested.emit()
		await save("calendarios_dominios")
		cp.visible = false
		if main != null:  # o mapa com as presenças de todas as entidades e a ficha do país
			hub.presence_panel._scope.select(1)
			hub.presence_panel._scope.item_selected.emit(1)
			main.globe.focus(EvronGeo.dir(12.0, 21.0), 1.5)
			sheet.hide_sheet()
			await save("mapa_presencas")
	if main == null:
		hub.focus_map = Callable()  # o callback captura esta suíte: soltar para não deixar um ciclo
		hub.close()
		host.queue_free()


func _texts(node: Node, out: Array) -> Array:
	if node is Label:
		out.append(node.text)
	for c in node.get_children():
		_texts(c, out)
	return out


## Lugares, camadas, clique e população pelos próprios widgets e sinais da ficha.
func _map_and_population(pais: int) -> void:
	var reg = hub.registry
	var map = hub.map
	var pp = hub.presence_panel
	hub.open(pais)
	if map.item_count != 0:
		return fail("sem presenças, o mapa deveria estar vazio")

	# Criar lugares no ponto fixado: sem ponto o botão fica desligado; ponto e área.
	hub.set_fixed_point(Vector3.ZERO)  # com a cena, suítes anteriores já fixaram pontos
	if not sheet._create_place_btn.disabled:
		return fail("sem ponto fixado não dá para criar lugar")
	hub.set_fixed_point(EvronGeo.dir(10.0, 20.0))
	if sheet._create_place_btn.disabled or not sheet._fixed_label.text.begins_with("Ponto fixado: lat 10,00° N"):
		return fail("com ponto fixado o botão liga e o texto mostra a coordenada: %s" % sheet._fixed_label.text)
	sheet.place_created.emit("Valdória", "assentamento", 0.0, "capital")
	hub.set_fixed_point(EvronGeo.dir(12.0, 21.0))
	sheet.place_created.emit("Vale de Aren", "regiao", 600.0, "territorio")
	var pres: Array = reg.PresencesOf(pais, hub.shown_t)
	if pres.size() != 2 or absf(pres[0].lat - 10.0) > 0.01 and absf(pres[1].lat - 10.0) > 0.01:
		return fail("as duas presenças deveriam existir: %s" % [pres])
	if map.item_count != 2 or map.area_count != 1 or map.label_count != 2 or map._mesh_node.mesh == null:
		return fail("o mapa deveria desenhar 2 lugares, 1 disco e 2 rótulos: %d/%d/%d" % [map.item_count, map.area_count, map.label_count])
	ok("mapa: lugar criado no ponto fixado (ponto e área), desenhado com disco e rótulos")

	# Camadas e escopo do painel.
	pp._checks["politica"].button_pressed = false
	if map.item_count != 0:
		return fail("desligar a camada política tira as presenças do país do mapa")
	pp._checks["politica"].button_pressed = true
	var vale_id: int = pres.filter(func(p): return p.place == "Vale de Aren")[0].place_id
	var etnia: int = _create(3, "Arenos")
	sheet.presence_added.emit(vale_id, "origem")  # o MESMO lugar, outra entidade
	if reg.Places("Vale").size() != 1 or map.item_count != 1:
		return fail("a etnia usa o lugar existente e a ficha dela mostra só a presença dela")
	pp._scope.select(1)
	pp._scope.item_selected.emit(1)
	if map.item_count != 3 or map.label_count != 2 or map.area_count != 2:
		return fail("todas as entidades: 3 presenças em 2 lugares (2 discos): %d/%d/%d" % [map.item_count, map.label_count, map.area_count])
	ok("camadas e escopo: desligar a camada esconde; o mesmo lugar serve a duas fichas; 'todas as entidades' mostra as 3 presenças em 2 rótulos")

	# O clique: o que se vê se seleciona.
	var antes := hub.current()
	var n := hub.pick(EvronGeo.dir(12.5, 21.5), 0.0)
	if n != 2 or hub.current() != antes or search._list.item_count != 2 or not search._list.get_item_text(0).contains("Vale de Aren"):
		return fail("o clique no vale acha 2 entidades e mostra a lista sem trocar a ficha: n=%d" % n)
	pp._checks["politica"].button_pressed = false
	n = hub.pick(EvronGeo.dir(12.5, 21.5), 0.0)
	if n != 1 or hub.current() != etnia:
		return fail("com só a camada étnica o clique abre a etnia: n=%d, ficha=%d" % [n, hub.current()])
	pp._checks["politica"].button_pressed = true
	if hub.pick(EvronGeo.dir(-40.0, -100.0), 40.0) != 0:
		return fail("clicar em nada não acha nada")
	hub.open(pais)  # um farol isolado (fora de qualquer disco) para isolar a tolerância do ponto
	hub.set_fixed_point(EvronGeo.dir(-30.0, 100.0))
	sheet.place_created.emit("Farol", "assentamento", 0.0, "outro")
	hub.open(etnia)
	if hub.pick(EvronGeo.dir(-30.0, 100.2), 40.0) != 1 or hub.current() != pais:
		return fail("com tolerância, o clique perto do farol (~19 km) abre o país (ficha=%d)" % hub.current())
	if hub.pick(EvronGeo.dir(-30.0, 100.2), 0.0) != 0:
		return fail("sem tolerância, um ponto não pega um clique a ~19 km")
	ok("clique no mapa: duas entidades listam, uma abre a ficha, camada filtra, tolerância no ponto")

	# Centralizar o mapa no lugar da presença.
	if main == null:
		sheet.place_focus_requested.emit(vale_id)
		if focused.size() != 1 or not focused[0][0].is_equal_approx(EvronGeo.dir(12.0, 21.0)) or focused[0][1] <= 1.0:
			return fail("'Ver' deveria centralizar o mapa no vale: %s" % [focused])
	else:
		sheet.place_focus_requested.emit(vale_id)
		await frames(1)
	ok("'Ver' centraliza o mapa no lugar")

	# População pela ficha: faixa, nível e entradas inválidas.
	hub.open(pais)
	var valdoria_id: int = reg.PresencesOf(pais, hub.shown_t).filter(func(p): return p.place == "Valdória")[0].place_id
	sheet.estimate_added.emit(vale_id, "1200", "1500", "", "media")
	sheet.estimate_added.emit(valdoria_id, "", "", "alta", "baixa")
	var ests: Array = reg.EstimatesOf(pais, hub.shown_t)
	var do_vale: Dictionary = ests.filter(func(e): return e.place == "Vale de Aren")[0]
	var da_cidade: Dictionary = ests.filter(func(e): return e.place == "Valdória")[0]
	if ests.size() != 2 or do_vale.low != 1200.0 or do_vale.high != 1500.0 or da_cidade.level != "alta" or str(da_cidade.low) != "":
		return fail("estimativas pela ficha: %s" % [ests])
	sheet.estimate_added.emit(vale_id, "abc", "", "", "media")
	if not sheet._geo_message.text.begins_with("Informe um número") or reg.EstimatesOf(pais, hub.shown_t).size() != 2:
		return fail("número inválido deveria avisar e não gravar")
	sheet.estimate_added.emit(vale_id, "500", "100", "", "media")
	if not sheet._geo_message.text.contains("não pode ser menor") or reg.EstimatesOf(pais, hub.shown_t).size() != 2:
		return fail("faixa invertida deveria avisar e não gravar")
	ok("população pela ficha: faixa, só nível, número inválido e faixa invertida avisam sem gravar")

	# A composição aparece na ficha (percentuais, faixa derivada, desconhecido) e o texto não promete o que não sabe.
	var rel1: int = reg.Create("religiao", "Via do silêncio")
	var rel2: int = reg.Create("religiao", "Culto das águas")
	var den: int = do_vale.id
	reg.AddDistribution(pais, vale_id, hub.shown_t, "religiao", den, true, false, "media", "", PackedInt64Array([rel1, rel2]), PackedFloat64Array([60.0, 30.0]))
	hub.open(pais)
	var linhas := _texts(sheet._body, [])
	var tudo := "\n".join(linhas)
	if not tudo.contains("Via do silêncio: 60%  ≈ 720–900 pessoas") or not tudo.contains("desconhecido: 10%") or not tudo.contains("lista incompleta"):
		return fail("a composição na ficha:\n%s" % tudo)
	if not tudo.contains("1.200–1.500 habitantes") or not tudo.contains("nível alta (sem número) habitantes"):
		return fail("as estimativas na ficha (faixa com milhar, nível sem número):\n%s" % tudo)
	ok("a ficha mostra a composição (60% ≈ 720–900 pessoas, 10% desconhecido, lista incompleta) e estimativas sem inventar número")

	if main != null:  # com a cena: o clique de verdade no Main fixa o ponto e consulta o mapa
		main.select(EvronGeo.dir(10.0, 20.0))
		if not hub.fixed_dir.is_equal_approx(EvronGeo.dir(10.0, 20.0)):
			return fail("Main.select deveria fixar o ponto nos cadastros")
		ok("Main.select fixa o ponto para os cadastros e consulta o mapa")
