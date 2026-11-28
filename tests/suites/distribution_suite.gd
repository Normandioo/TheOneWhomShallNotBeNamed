extends "res://tests/test_suite.gd"
## Distribuições pela ficha (aceite A04), sem cena: criar cultura, etnia, idioma e religião; distribuir a população de um país por culturas
## numa cidade e numa região (área com outra fronteira) pelo formulário "＋ Composição"; as recusas de soma; apagar e desfazer; e tudo
## continua lá depois de fechar e reabrir o banco. As linhas "ERROR" das recusas são esperadas.

const SearchPanel = preload("res://scripts/ui/search_panel.gd")
const SheetPanel = preload("res://scripts/ui/sheet_panel.gd")
const DomainHub = preload("res://scripts/app/domain_hub.gd")
const CommandStack = preload("res://scripts/edit/command_stack.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")


func run() -> void:
	var path := out_dir.path_join("distribution_suite.db")
	for ext in ["", "-journal"]:
		DirAccess.remove_absolute(path + ext)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var search := SearchPanel.new()
	var sheet := SheetPanel.new()
	host.add_child(search)
	host.add_child(sheet)
	var hub := DomainHub.new()
	hub.setup(path, search, sheet)
	var stack := CommandStack.new()
	hub.bind_commands(stack)
	var r = hub.registry

	var aren: int = r.Create("cultura", "Cultura aren")
	var vales: int = r.Create("cultura", "Cultura dos vales")
	r.Create("etnia", "Arenos")
	r.Create("idioma", "Arenês")
	r.Create("religiao", "Via do silêncio")
	var pais: int = r.Create("pais", "Reino de Aren")
	var cidade: int = r.AddPlace("Valdória", "assentamento", 10.0, 20.0, 0.0, "")
	var regiao: int = r.AddPlace("Vale de Aren", "regiao", 14.0, 24.0, 300.0, "")
	r.AddPresence(pais, cidade, "capital", "alta")
	r.AddPresence(pais, regiao, "territorio", "media")
	hub.open(pais)
	await frames(1)
	if sheet.composition_form == null:
		return fail("a ficha do país deveria ter o formulário de composição")

	# Pelo formulário: cidade, cultura, exclusivas e completa, duas categorias que somam 100%.
	var form := sheet.composition_form
	var place: OptionButton = _find(form, OptionButton, 0)
	_select_meta(place, cidade)
	var complete: CheckBox = _find(form, CheckBox, 1)
	complete.button_pressed = true
	var rows: VBoxContainer = form.get_child(2)
	var more: Button = _button(form, "＋ categoria")
	more.pressed.emit()
	_fill(rows.get_child(0), aren, 60.0)
	_fill(rows.get_child(1), vales, 40.0)
	form.visible = true
	search.hide()
	sheet.size = Vector2(440, 1040)  # sem a cena, ninguém dá o tamanho da janela
	sheet.show_page("População")
	await frames(3)
	await save("composicao_formulario")
	_button(form, "Criar composição").pressed.emit()
	await frames(1)
	var comps = r.CompositionsOf(pais, hub.shown_t)
	if comps.size() != 1 or comps[0].place != "Valdória" or comps[0].shares.size() != 2 or not comps[0].complete:
		return fail("criar a composição da cidade pelo formulário: %s" % [comps])
	ok("formulário: a composição da cidade, por cultura, exclusiva e completa, gravada na data mostrada")

	# Recusas antes de gravar: a mensagem diz o que corrigir.
	var why := hub.add_distribution(regiao, "cultura", true, true, [aren], [70.0])
	if not why.contains("100%") or r.CompositionsOf(pais, hub.shown_t).size() != 1:
		return fail("exclusiva e completa somando 70% deveria ser recusada: " + why)
	if hub.add_distribution(regiao, "cultura", true, false, [aren, aren], [10.0, 20.0]) == "" or hub.add_distribution(0, "cultura", true, false, [aren], [10.0]) == "":
		return fail("categoria repetida e lugar vazio deveriam ser recusados")
	if hub.add_distribution(regiao, "cultura", true, false, [aren, vales], [80.0, 30.0]) == "":
		return fail("exclusivas passando de 100% deveriam ser recusadas")
	ok("recusas: soma diferente de 100% na exclusiva completa, mais de 100% na exclusiva, categoria repetida, sem lugar")

	# A região tem outra fronteira e outra composição; o idioma não é exclusivo (passa de 100%).
	if hub.add_distribution(regiao, "cultura", true, false, [aren], [70.0]) != "":
		return fail("a composição da região")
	var idioma: int = r.Search("Arenês", "idioma", "", 0, hub.shown_t)[0].id
	if hub.add_distribution(regiao, "idioma", false, false, [idioma], [100.0]) != "":
		return fail("idioma não exclusivo")
	comps = r.CompositionsOf(pais, hub.shown_t)
	var by_place := {}
	for c in comps:
		by_place[String(c.place) + "/" + String(c.dimension)] = c
	if comps.size() != 3 or by_place["Vale de Aren/cultura"].unknown_pct != 30.0 or by_place["Valdória/cultura"].shares[0].pct != 60.0:
		return fail("cidade e região com composições diferentes: %s" % [by_place.keys()])
	hub.open(pais)
	sheet.show_page("População")
	await frames(3)
	await save("composicao_ficha")
	ok("cidade e região (área com outra fronteira) com composições próprias; incompleta mostra o desconhecido")

	# Apagar e desfazer.
	var drop: int = by_place["Vale de Aren/idioma"].id
	sheet.distribution_removed.emit(drop)
	if r.CompositionsOf(pais, hub.shown_t).size() != 2:
		return fail("apagar a composição")
	stack.undo()
	if r.CompositionsOf(pais, hub.shown_t).size() != 3:
		return fail("desfazer o apagar devolve a composição")
	stack.undo()  # desfaz a criação do idioma
	stack.redo()
	if r.CompositionsOf(pais, hub.shown_t).size() != 3:
		return fail("refazer a criação")
	ok("apagar e criar composição desfazem e refazem")

	# Fechar e reabrir.
	hub.close()
	var again = load("res://scripts/world/Registry.cs").new()
	again.Open(path)
	if again.CompositionsOf(pais, hub.shown_t).size() != 3:
		return fail("as composições depois de reabrir")
	again.Close()
	ok("persistência: as composições voltam ao reabrir o mundo")
	host.queue_free()
	await frames(1)


func _find(root: Node, type, index: int) -> Node:
	var found: Array = []
	_collect(root, type, found)
	return found[index] if index < found.size() else null


func _collect(n: Node, type, out: Array) -> void:
	for c in n.get_children():
		if is_instance_of(c, type):
			out.append(c)
		_collect(c, type, out)


func _button(root: Node, text: String) -> Button:
	var all: Array = []
	_collect(root, Button, all)
	for b in all:
		if b.text == text:
			return b
	return null


func _select_meta(o: OptionButton, meta: int) -> void:
	for i in o.item_count:
		if o.get_item_metadata(i) == meta:
			o.select(i)


func _fill(row: Node, category: int, pct: float) -> void:
	_select_meta(row.get_child(0), category)
	row.get_child(1).value = pct
