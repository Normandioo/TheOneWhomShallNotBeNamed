extends "res://tests/test_suite.gd"
## Os painéis de busca e de ficha ligados ao Registry pelo DomainHub, sem a cena principal (não precisa dos mapas):
## criar, preencher campos (com os estados), nomes, etiquetas, vínculos, duplicar, excluir e sociedade, pelos próprios widgets.
## As linhas "ERROR" das recusas são esperadas.

const SearchPanel = preload("res://scripts/ui/search_panel.gd")
const SheetPanel = preload("res://scripts/ui/sheet_panel.gd")
const CalendarPanel = preload("res://scripts/ui/calendar_panel.gd")
const Calendar = preload("res://scripts/world/calendar.gd")
const DomainHub = preload("res://scripts/world/domain_hub.gd")

var hub: DomainHub
var search: SearchPanel
var sheet: SheetPanel
var host: Control


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
	var name_edit: LineEdit = sheet._body.get_child(0)
	name_edit.text = "Reino de Arên"
	name_edit.text_submitted.emit("Reino de Arên")
	if reg.Name(pais) != "Reino de Arên" or not search._list.get_item_text(search._ids.find(pais)).begins_with("Reino de Arên"):
		return fail("a correção do nome deveria chegar ao registro e à busca")
	name_edit.text = "   "
	name_edit.text_submitted.emit("   ")
	if name_edit.text != "Reino de Arên" or reg.Name(pais) != "Reino de Arên":
		return fail("nome vazio não pode ser aceito")
	ok("corrigir o nome atualiza o registro e a busca; nome vazio é desfeito")

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
	if main == null:
		hub.close()
		host.queue_free()
