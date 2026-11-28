extends PanelContainer
## O Índice, painel acoplado à esquerda (ao lado da coluna de modos): o campo de busca no alto e, embaixo, uma lista (seção) por categoria,
## uma sob a outra e cada uma recolhível: países (com as províncias e municípios sob cada um), religiões, culturas, etnias, raças, idiomas e os
## outros tipos. Com texto na busca, os resultados (com filtro de tipo) ocupam o lugar das listas. No fim, a criação de registros novos.
## Só mostra e pede: avisa por sinal; quem busca e cria é o DomainHub.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")

signal query_changed(text: String, kind: String)
signal batch_tag_requested(ids: Array, tag: String)  # o lote: a mesma etiqueta em vários
signal batch_delete_requested(ids: Array)              # o lote: excluir vários
signal entity_chosen(id: int)
signal create_requested(kind: String, name: String)
signal society_requested(name: String)
signal calendars_requested
signal types_requested
signal rules_requested
signal tutorial_requested  # o botão "?" do cabeçalho
signal summary_changed(text: String)  # "4 países · 31 cadastros", para a barra de cima

const WIDTH := 280
var _summary := ""


func summary() -> String:
	return _summary


const SOCIETY_ID := 100  # item do menu "Novo" que não é um tipo
# As seções de categoria: [chave, ícone, nome, tipos que entram, peso da altura]. Os tipos que não estão aqui (criados pelo usuário) vão em "Outros".
const CATEGORIES := [
	["pais", "politics", "Países", ["pais", "provincia", "municipio"], 4],
	["religiao", "religion", "Religiões", ["religiao"], 1],
	["cultura", "culture", "Culturas", ["cultura"], 1],
	["etnia", "ethnicity", "Etnias", ["etnia"], 1],
	["raca", "race", "Raças", ["raca"], 1],
	["idioma", "language", "Idiomas", ["idioma"], 1],
]

var _query: LineEdit
var _filter: OptionButton
var _new_pop: PopupMenu
var _list: ItemList
var _batch: HFlowContainer  # a barra do lote: aparece com dois ou mais marcados
var _batch_label: Label
var _ids: Array[int] = []
var _sections: VBoxContainer   # as listas, uma sob a outra
var _results: VBoxContainer    # o filtro e a lista da busca (no lugar das seções enquanto há texto)
var _pages: Array = []         # uma por categoria: {key, name, kinds, tree, header, section, count, open}
var _item_page := {}           # id do cadastro -> índice da seção onde ele aparece
var _tree_items := {}          # id do cadastro -> TreeItem
var _tree_silent := false      # selecionar por código não abre a ficha de novo
var _last_selected := 0


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.dock_style(SIDE_RIGHT))
	custom_minimum_size = Vector2(WIDTH, 0)  # o Main põe no lugar (ao lado da coluna) e na altura toda
	var box := VBoxContainer.new()
	add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Registros"
	UiKit.style_heading(title)
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var help := Button.new()
	help.text = "?"
	help.custom_minimum_size.x = 30
	help.tooltip_text = "Ver o que cada botão dos Registros faz"
	help.pressed.connect(func() -> void: tutorial_requested.emit())
	head.add_child(help)
	var fold := Button.new()
	fold.icon = UiIcons.get_icon("close", 16)
	fold.flat = true
	fold.tooltip_text = "Fechar os Registros · O"
	fold.pressed.connect(func() -> void: hide())
	head.add_child(fold)
	_query = LineEdit.new()
	_query.placeholder_text = "Buscar por nome"
	_query.clear_button_enabled = true
	_query.tooltip_text = "Acha também pelos nomes alternativos e históricos, sem diferenciar acentos."
	_query.text_changed.connect(func(_t: String) -> void:
		_show_mode()
		_emit_query())
	box.add_child(_query)

	_results = VBoxContainer.new()
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.hide()
	box.add_child(_results)
	_filter = OptionButton.new()
	_filter.item_selected.connect(func(_i: int) -> void: _emit_query())
	_results.add_child(_filter)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 170)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void: entity_chosen.emit.call_deferred(_ids[i]))
	_list.select_mode = ItemList.SELECT_MULTI  # Ctrl ou Shift marcam vários: a barra do lote aparece embaixo
	_list.multi_selected.connect(func(_i: int, _on: bool) -> void: _show_batch())
	_results.add_child(_list)
	_batch = HFlowContainer.new()
	_batch.add_theme_constant_override("h_separation", 6)
	_batch.hide()
	_results.add_child(_batch)
	_batch_label = Label.new()
	_batch.add_child(_batch_label)
	var tag := LineEdit.new()
	tag.placeholder_text = "etiqueta"
	tag.custom_minimum_size.x = 100
	_batch.add_child(tag)
	var tag_go := Button.new()
	tag_go.text = "Etiquetar"
	tag_go.tooltip_text = "Põe a etiqueta em todos os marcados (um desfazer só)"
	tag_go.pressed.connect(func() -> void:
		if tag.text.strip_edges() != "":
			batch_tag_requested.emit(marked(), tag.text.strip_edges()))
	_batch.add_child(tag_go)
	var drop := Button.new()
	drop.text = "Excluir marcados"
	drop.tooltip_text = "Exclui todos os marcados, com o território e os vínculos de cada um (um desfazer só)"
	drop.pressed.connect(func() -> void: batch_delete_requested.emit(marked()))
	_batch.add_child(drop)

	_sections = VBoxContainer.new()  # cada seção divide a altura: a dos países pesa mais; as vazias ficam só com o título
	_sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", 4)
	box.add_child(_sections)
	for cat in CATEGORIES:
		_add_page(cat[0], cat[1], cat[2], cat[3], cat[4])
	_add_page("outros", "more", "Outros tipos", [], 1)
	var footer := HBoxContainer.new()
	box.add_child(footer)
	for spec in [["＋ País", "Cria um país com o texto da busca como nome (pode ser provisório)", UiKit.all_kinds().find("pais")], ["＋ Sociedade", "País, cultura e etnia de uma vez", SOCIETY_ID]]:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[1]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_new.bind(spec[2]))
		footer.add_child(b)
	var new_menu := MenuButton.new()  # os outros tipos de cadastro
	new_menu.text = "＋ Outro"
	_new_pop = new_menu.get_popup()
	_new_pop.id_pressed.connect(_on_new)
	new_menu.tooltip_text = "Cria um cadastro de outro tipo, com o texto da busca como nome."
	footer.add_child(new_menu)
	refresh_kinds()


## Refaz os menus de tipo (depois de criar um tipo novo). O filtro escolhido fica, se o tipo ainda existir.
func refresh_kinds() -> void:
	var keep := kind_filter() if _filter.item_count > 0 else ""
	var kinds := UiKit.all_kinds()
	_new_pop.clear()
	for i in kinds.size():
		if kinds[i] != "municipio":  # uma subdivisão nova começa no 1º nível; o 2º é uma dentro de outra
			_new_pop.add_item(UiKit.short_label(kinds[i]), i)
	_new_pop.add_separator()
	_new_pop.add_item("Sociedade (país + cultura + etnia)", SOCIETY_ID)
	_filter.clear()
	_filter.add_item("Todos os tipos")
	for k in kinds:
		_filter.add_item(UiKit.kind_label(k))
	_filter.select(kinds.find(keep) + 1)


## Os ids marcados na lista (Ctrl ou Shift + clique).
func marked() -> Array:
	return Array(_list.get_selected_items()).map(func(i: int) -> int: return _ids[i])


func _show_batch() -> void:
	var n := _list.get_selected_items().size()
	_batch.visible = n > 1
	_batch_label.text = "%d marcados:" % n


## Mostra os resultados (cada um: id, kind, name, match). Não repete o evento de seleção.
func show_results(items: Array, selected_id: int = 0) -> void:
	_list.clear()
	_ids.clear()
	_batch.hide()
	for it in items:
		var text: String = "%s  ·  %s" % [it.name, UiKit.entry_label(String(it.kind), String(it.get("label", "")))]
		if it.match != "":
			text += "  (%s)" % it.match
		_list.add_item(text)
		_ids.append(int(it.id))
		if int(it.id) == selected_id:
			_list.select(_ids.size() - 1, false)


## Uma seção: o título (clique para recolher ou abrir) e a lista embaixo.
func _add_page(key: String, icon_name: String, page_name: String, kinds: Array, weight: int) -> void:
	var section := VBoxContainer.new()
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.size_flags_stretch_ratio = weight
	section.add_theme_constant_override("separation", 2)
	_sections.add_child(section)
	var header := Button.new()
	header.toggle_mode = true
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.icon = UiIcons.get_icon(icon_name, 16)
	UiKit.tint_icon(header, icon_name)
	header.add_theme_color_override("font_color", UiKit.BRASS)
	header.add_theme_color_override("font_pressed_color", UiKit.BRASS)
	header.add_theme_color_override("font_hover_color", UiKit.FOCUS)
	header.add_theme_font_override("font", UiKit.heading_font())
	section.add_child(header)
	var tree := Tree.new()
	tree.name = page_name
	tree.hide_root = true
	tree.custom_minimum_size = Vector2(0, 70)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_selected.connect(func() -> void:
		var it := tree.get_selected()
		if _tree_silent or it == null or it.get_metadata(0) == null:
			return
		_tree_silent = true  # só uma lista guarda a seleção
		for other in _pages:
			if other.tree != tree:
				other.tree.deselect_all()
		_tree_silent = false
		entity_chosen.emit.call_deferred(int(it.get_metadata(0))))  # a lista é refeita ao abrir a ficha: dentro do clique, apagaria o item em uso (queda no Linux)
	section.add_child(tree)
	var index := _pages.size()
	_pages.append({"key": key, "name": page_name, "kinds": kinds, "tree": tree, "header": header, "section": section, "count": 0,
		"open": true, "weight": weight})
	header.button_pressed = true
	header.toggled.connect(func(open: bool) -> void:
		_pages[index].open = open
		_pages[index].user = true  # a partir daqui o usuário decide
		_refresh_section(index))


## O título e a altura da seção: aberta, divide o espaço; recolhida, fica só o título.
func _refresh_section(i: int) -> void:
	var page: Dictionary = _pages[i]
	var open: bool = page.open
	page.tree.visible = open
	page.section.size_flags_vertical = Control.SIZE_EXPAND_FILL if open else Control.SIZE_SHRINK_BEGIN
	page.header.set_pressed_no_signal(open)
	page.header.text = "%s %s (%d)" % ["▾" if open else "▸", page.name, page.count]


## Com texto na busca, os resultados ocupam o lugar das listas.
func _show_mode() -> void:
	var searching := not _query.text.is_empty()
	_results.visible = searching
	_sections.visible = not searching


## Os tipos que cada seção mostra: os fixos da categoria; em "Outros", todos os que não estão em nenhuma categoria.
func _kinds_of(page: Dictionary) -> Array:
	if page.key != "outros":
		return page.kinds
	var taken := []
	for cat in CATEGORIES:
		taken.append_array(cat[3])
	return UiKit.all_kinds().filter(func(k: String) -> bool: return not k in taken)


## Mostra as listas, uma por seção. rows: [{id, kind, name, parent, label}]; parent = o cadastro de nível acima (0 = nenhum).
## Em Países, cada subdivisão fica sob o de cima, com o nome do tipo dela; as que ficaram sem o de cima (o país apagado, por exemplo)
## vão num grupo "Sem lugar definido" no alto, à vista. O que estava aberto continua aberto. Não repete o evento de seleção.
func show_hierarchy(rows: Array, selected_id: int = 0) -> void:
	_tree_silent = true
	var open := {}  # os cadastros que estavam abertos (expandidos) antes de refazer
	for id in _tree_items:
		if not _tree_items[id].collapsed:
			open[id] = true
	_tree_items.clear()
	_item_page.clear()
	for i in _pages.size():
		var page: Dictionary = _pages[i]
		var tree: Tree = page.tree
		tree.clear()
		var root := tree.create_item()
		var kinds := _kinds_of(page)
		var mine := rows.filter(func(r: Dictionary) -> bool: return r.kind in kinds)
		page.count = mine.filter(func(r: Dictionary) -> bool: return r.kind == kinds[0]).size() if not kinds.is_empty() else 0
		var orphans: TreeItem = null
		var groups := {}  # em "Outros": um grupo por tipo
		for kind in kinds:
			for r in mine:
				if r.kind != kind:
					continue
				var parent: TreeItem = _tree_items.get(int(r.parent)) if int(r.parent) != 0 else null
				if parent == null and kind in ["provincia", "municipio"]:
					if orphans == null:
						orphans = _group(tree, root, "Sem lugar definido", true)
					parent = orphans
				elif parent == null and page.key == "outros":
					if not groups.has(kind):
						groups[kind] = _group(tree, root, UiKit.kind_label(kind), false)
					parent = groups[kind]
				var item := tree.create_item(parent if parent != null else root)
				var label := String(r.get("label", ""))
				item.set_text(0, String(r.name) if label == "" else "%s · %s" % [r.name, label])
				item.set_metadata(0, int(r.id))
				_tree_items[int(r.id)] = item
				_item_page[int(r.id)] = i
		for kind in groups:
			groups[kind].set_text(0, "%s (%d)" % [UiKit.kind_label(kind), mine.filter(func(r: Dictionary) -> bool: return r.kind == kind).size()])
		if orphans != null:
			orphans.set_text(0, "Sem lugar definido (%d)" % orphans.get_child_count())
		page.section.visible = not (page.key == "outros" and mine.is_empty())
		if not page.get("user", false):  # sem escolha do usuário: aberta se tem cadastros, recolhida se está vazia
			page.open = page.count > 0
		_refresh_section(i)
	for id in _tree_items:  # tudo recolhido, menos o que o usuário tinha aberto
		var item: TreeItem = _tree_items[id]
		if item.get_child_count() > 0:
			item.collapsed = not open.has(id)
	select_in_hierarchy(selected_id)
	_tree_silent = false
	var countries := rows.filter(func(r: Dictionary) -> bool: return r.kind == "pais").size()
	_summary = "%d países · %d cadastros" % [countries, rows.size()]
	summary_changed.emit(_summary)


## Marca o cadastro escolhido na árvore, sem refazê-la: abre os de cima e a seção dele e rola até ele. Não repete o evento de seleção.
func select_in_hierarchy(selected_id: int) -> void:
	var was := _tree_silent
	_tree_silent = true
	if _tree_items.has(selected_id):
		var chosen: TreeItem = _tree_items[selected_id]
		var up := chosen.get_parent()
		while up != null:  # abre os de cima, para o escolhido aparecer
			up.collapsed = false
			up = up.get_parent()
		chosen.select(0)
		var page: Dictionary = _pages[_item_page[selected_id]]
		if not page.open:  # abriu pelo mapa ou pela busca: abre a seção dele
			page.open = true
			_refresh_section(_item_page[selected_id])
		page.tree.scroll_to_item(chosen)
	_last_selected = selected_id
	_tree_silent = was


## Um grupo (título) numa árvore: não se escolhe, só agrupa.
func _group(tree: Tree, root: TreeItem, text: String, expanded: bool) -> TreeItem:
	var g := tree.create_item(root)
	g.set_text(0, text)
	g.set_selectable(0, false)
	g.set_custom_color(0, UiKit.BRASS)
	g.collapsed = not expanded
	return g


## Ctrl+F: abre o Índice e põe o cursor no campo de busca.
func focus_query() -> void:
	show()
	_query.grab_focus()
	_query.select_all()


func query() -> String:
	return _query.text


func kind_filter() -> String:
	return "" if _filter.selected <= 0 else UiKit.all_kinds()[_filter.selected - 1]


func _emit_query() -> void:
	query_changed.emit(_query.text, kind_filter())


func _on_new(id: int) -> void:
	if id == SOCIETY_ID:
		society_requested.emit(_query.text)
	else:
		create_requested.emit(UiKit.all_kinds()[id], _query.text)
