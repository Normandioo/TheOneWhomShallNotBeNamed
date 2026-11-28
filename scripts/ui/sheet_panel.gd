extends PanelContainer
## A ficha de um cadastro, à esquerda da busca: identidade, resumo, etiquetas, nomes, o conteúdo do tipo (gerado das definições
## de campo, com os campos vazios recolhidos em "Adicionar informação") e as relações. Só mostra e pede: avisa por sinal quando
## o usuário edita; o DomainHub grava no Registry e devolve o que for preciso mostrar.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")  # só para o separador de milhares
const SunCrest = preload("res://scripts/ui/sun_crest.gd")

signal name_changed(entity_id: int, text: String)  # correção de grafia do nome atual (não é mudança histórica)
signal summary_changed(entity_id: int, text: String)
signal field_edited(entity_id: int, code: String, state: String, value: String)  # state: known | unknown | na; known + "" = limpar
signal alias_added(role: String, name: String)
signal tag_added(tag: String)
signal tag_removed(tag: String)
signal link_added(type: String, other_id: int)
signal link_removed(link_id: int)
signal link_search(text: String, dst_kind: String)
signal open_entity(id: int)
signal paint_kind_requested(kind: String, parent_id: int)  # "pintar no mapa": uma região nova deste tipo (parent_id: dentro de quem; 0 = livre)
signal hierarchy_set(child_id: int, parent_id: int)  # ligar um município a uma província, ou uma província a um país (parent_id 0 = tirar do de cima)
signal duplicate_requested(copy_links: bool)
signal delete_requested
signal delete_confirmed
signal closed
signal tutorial_requested  # o botão "?" do cabeçalho: o tutorial da página aberta
signal calendar_use_added(calendar_id: int, purpose: String)
signal calendar_use_removed(use_id: int)
signal place_focus_requested(place_id: int)
signal place_edited(place_id: int, name: String, kind: String, radius_km: float)  # o mesmo lugar muda em todas as fichas que o usam
signal place_move_requested(place_id: int)  # o próximo clique no globo leva o lugar (e a área dele) para lá

signal territory_paint_requested                              # entrar no modo pintar território para este país
signal territory_boundary_requested                           # entrar direto no pincel de fronteira do país selecionado
signal territory_clear_requested                              # apagar todo o território deste país (desfaz com Ctrl+Z)
signal territory_claim_requested                              # pintar o que este país reivindica (camada própria, sobre os outros)
signal territory_split_requested                              # dividir o território em dois pelo traço (o lado que sai vira um cadastro novo)
signal entity_color_changed(entity_id: int, rgb: int, final: bool)  # final = o usuário fechou o seletor (grava); senão, prévia na paleta
signal place_search(text: String)  # buscar lugares para os menus (o hub responde com show_place_candidates)
signal presence_added(place_id: int, role: String)
signal presence_removed(presence_id: int)
signal place_created(name: String, kind: String, radius_km: float, role: String)  # no ponto fixado no mapa
signal estimate_added(place_id: int, low: String, high: String, level: String, certainty: String)
signal estimate_removed(estimate_id: int)
## Uma composição nova da população desta ficha num lugar (cidade ou região), na data mostrada: categorias (ids) e percentuais.
signal distribution_added(place_id: int, dimension: String, exclusive: bool, complete: bool, categories: Array, pcts: Array)
signal distribution_removed(distribution_id: int)
signal total_set(text: String)
signal total_removed
signal division_named(id: int, name: String)                  # como esta divisão se chama
signal level_named(country: int, level: int, name: String)    # como o país chama o 1º ou o 2º nível
# A lista de subdivisões edita cada uma sem sair do país (nome, tipo do nome e cor usam os sinais de sempre, com o id dela).
signal division_focused(id: int)                              # a divisão aberta na lista, à vista (0 = nenhuma): o mapa a destaca
signal division_paint_requested(id: int, mode: String)
signal division_total_set(id: int, text: String)              # "" tira o total
signal division_delete_requested(id: int)
signal division_view_requested(id: int)                       # leva o mapa até ela
signal division_back_requested(id: int)                       # da ficha completa, de volta à lista do país
signal city_created(name: String, count: String)  # uma cidade nova no ponto fixado, já com habitantes

const EntityPicker = preload("res://scripts/ui/entity_picker.gd")
const DivisionNamePicker = preload("res://scripts/ui/division_name_picker.gd")
const WIDTH := 420
const CATEGORY_COLORS := {"cultura": Color("#7fb8a8"), "etnia": Color("#e0907f"), "raca": Color("#b5c070"), "religiao": Color("#dfb868"), "idioma": Color("#8fa9e0")}
const PRESENCE_TYPES := ["cultura_presente", "etnia_presente", "raca_presente", "religiao_presente", "idioma_falado"]
const CATEGORIES := [["cultura", "Culturas", "cultura_presente"], ["etnia", "Etnias", "etnia_presente"], ["raca", "Raças", "raca_presente"],
	["religiao", "Religiões", "religiao_presente"], ["idioma", "Idiomas", "idioma_falado"]]
const PARENT_OF := {"provincia": "pais", "municipio": "provincia"}  # a hierarquia política: o cadastro de cima de cada nível
const CHILD_OF := {"pais": ["provincia", "municipio"], "provincia": ["municipio"]}
const FOREVER := 9223372036854775807
const STATES := ["known", "unknown", "na"]
const STATE_LABELS := ["Valor", "Desconhecido", "Não se aplica"]
const PURPOSES := {"civil": "Civil", "ritual": "Ritual", "tradicional": "Tradicional", "administrativo": "Administrativo", "outro": "Outro"}
const ROLES := [
	["alternativo", "Nome alternativo"], ["historico", "Nome histórico"], ["autodenominacao", "Autodenominação"],
	["exonimo", "Exônimo"], ["oficial", "Nome oficial"], ["popular", "Nome popular"], ["gentilico", "Gentílico"],
	["etnonimo", "Etnônimo"], ["denominacao_coletiva", "Denominação coletiva"],
]

var _title: Label
var _banner: PanelContainer
var _crest: Control
var _name_label: Label
var _subtitle: Label
var _division_row: HBoxContainer  # "Como se chama:" no alto da ficha de uma subdivisão
var division_picker: Control
var level_pickers: Array = []     # na ficha do país: como se chamam o 1º e o 2º nível
var division_detail := Callable()  # (id) -> {name, label, area_km2, color, ok, has_total, total}, ligado pelo DomainHub
var open_division := 0             # a linha aberta na lista de subdivisões
var division_rows := {}            # id -> o botão do nome na lista
var division_editor := {}          # os controles da linha aberta
var back_button: Button            # "‹ Voltar a <país>", na ficha completa de uma subdivisão
var level_toggle: Button
var division_search: LineEdit
var _queued_division := 0
var _focused_division := 0
var _level_names_open := false
var _division_filter := ""
var _division_groups: Array = []   # [{box, name, kids: [{box, name}], expanded}] para o filtro
var _actions: HFlowContainer     # Pintar território e a subdivisão, logo abaixo do cabeçalho (só para quem tem território)
var _actions_wrap: Control
var _boundary_brush: Button
var _scroll: ScrollContainer
var _body: VBoxContainer
var _page: VBoxContainer
var _tab_bar: HBoxContainer
var _pages := {}
var _tab_buttons := {}
var _tab_scroll := {}
var _active_tab := ""
var wanted_page := "Ficha"   # a categoria escolhida no alto: a janela continua nela ao trocar de cadastro
var keep_closed := false     # o usuário fechou a janela: reler a ficha (o relógio andou) não a reabre
var _has_actions := false
var _has_boundary := false
var _confirm: ConfirmationDialog
var _sheet := {}
var _fields := {}          # código -> {row, state, editor, type, last_state, last_value}
var _add_menu: OptionButton
var _types: Array = []     # tipos de vínculo que esta ficha pode criar
var _division_open := {}     # província -> aberta na lista de divisões
signal page_changed(page: String)  # a página (categoria) mostrada passou a ser outra
var _category_open := {}     # categoria vazia -> expandida (para ligar a primeira)
var lookup: Callable        # (texto, tipo) -> [{id, kind, name}]: a busca dos seletores de cadastro (quem liga é o DomainHub)
var _link_type: OptionButton
var _link_query: LineEdit
var _link_candidates: OptionButton
var _calendars := {}       # o que o hub mandou: universal, uses, choices
var _geo := {}             # lugares e datas para as seções de mapa e população (do hub)
var _fixed_label: Label
var _create_place_btn: Button
var _geo_message: Label
var _territory_msg: Label
var _place_pickers: Array = []  # os menus de lugar da ficha (a busca de um atualiza todos)
var composition_form: VBoxContainer = null  # o formulário "＋ Composição" (os testes o preenchem)
var _universal_label: Label
var _date_labels := {}     # id do uso -> Label com a data local


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.dock_style(SIDE_RIGHT, 0, 0))
	custom_minimum_size = Vector2(WIDTH, 0)  # a janela da esquerda: o Main a põe abaixo do alto da tela
	clip_contents = true
	var root := VBoxContainer.new()
	add_child(root)
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", UiKit.banner_style(Color("#6e86d8")))
	root.add_child(_banner)
	var banner_row := HBoxContainer.new()
	banner_row.add_theme_constant_override("separation", 12)
	_banner.add_child(banner_row)
	_crest = SunCrest.new()
	_crest.visible = false  # o emblema do selecionado fica no alto da tela
	banner_row.add_child(_crest)
	var banner_text := VBoxContainer.new()
	banner_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_row.add_child(banner_text)
	var head := HBoxContainer.new()
	banner_text.add_child(head)
	_title = Label.new()
	_title.clip_text = true  # o painel tem largura fixa: o título recorta em vez de alargá-lo
	UiKit.style_heading(_title)
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color("#f4ebd3"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 24)
	UiKit.style_heading(_name_label)
	_name_label.add_theme_color_override("font_color", Color("#f4ebd3"))
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.visible = false  # o nome vai no subtítulo (e no emblema, no alto da tela): o cabeçalho fica baixo
	banner_text.add_child(_name_label)
	_subtitle = Label.new()
	_subtitle.add_theme_color_override("font_color", Color("#e6d3c8"))
	_subtitle.clip_text = true
	banner_text.add_child(_subtitle)
	_division_row = HBoxContainer.new()
	_division_row.hide()
	banner_text.add_child(_division_row)
	_boundary_brush = Button.new()
	_boundary_brush.text = "Pincel de fronteira"
	_boundary_brush.visible = false
	_boundary_brush.pressed.connect(func() -> void: territory_boundary_requested.emit())
	_boundary_brush.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	banner_text.add_child(_boundary_brush)  # sob o nome: na linha do título faltava espaço nos 420 px
	var help := Button.new()
	help.text = "?"
	help.custom_minimum_size.x = 30
	help.tooltip_text = "Ver o que cada botão desta página faz"
	help.pressed.connect(func() -> void: tutorial_requested.emit())
	head.add_child(help)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.tooltip_text = "Fechar a janela (o selecionado continua)"
	close.pressed.connect(func() -> void:
		dismiss()
		closed.emit())
	head.add_child(close)
	_actions = HFlowContainer.new()  # quebra a linha: país tem três botões (pintar, ＋ Província, ＋ Município) e não cabem nos 420 px lado a lado
	_actions.add_theme_constant_override("h_separation", 6)
	_actions.add_theme_constant_override("v_separation", 6)
	_actions_wrap = _margin(_actions, 14, 12, 4)
	_actions_wrap.hide()
	root.add_child(_actions_wrap)
	_tab_bar = HBoxContainer.new()  # escondida: quem troca de página são os botões de categoria do alto
	var tabs := _margin(_tab_bar, 6, 8, 0)
	tabs.visible = false
	root.add_child(tabs)
	root.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_margin(_scroll, 14, 0, 12, true))
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Excluir cadastro"
	_confirm.confirmed.connect(func() -> void: delete_confirmed.emit())
	add_child(_confirm)


## O conteúdo recuado nas laterais (o painel é acoplado e o cabeçalho vai de ponta a ponta).
func _margin(child: Control, side: int, top: int, bottom: int, fill := false) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", side)
	m.add_theme_constant_override("margin_right", side)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL if fill else Control.SIZE_SHRINK_BEGIN
	m.add_child(child)
	return m


func current_id() -> int:
	return int(_sheet.get("id", 0))


## Mostra a ficha (o Dictionary de Registry.Sheet) e os tipos de vínculo que ela pode criar (Registry.LinkTypesFor).
func show_sheet(sheet: Dictionary, link_types: Array, calendars := {}, geo := {}) -> void:
	if _queued_division != 0:
		open_division = _queued_division
		_queued_division = 0
	elif int(sheet.id) != current_id():
		open_division = 0
		_division_filter = ""
	var keep := wanted_page
	if int(sheet.id) == current_id() and _active_tab != "":
		keep = _active_tab
		_tab_scroll[keep] = _scroll.scroll_vertical
	else:
		_tab_scroll.clear()
	_sheet = sheet
	var covered: bool = String(sheet.kind) in ["pais", "provincia", "municipio"]  # nestes, a presença de povo e cultura vai na seção Povo e cultura
	_types = link_types.filter(func(t: Dictionary) -> bool: return not String(t.code) in ["provincia_de", "municipio_de"] and not (covered and String(t.code) in PRESENCE_TYPES))  # estes vão nas seções Hierarquia e Povo e cultura
	_calendars = calendars
	_geo = geo
	visible = not keep_closed
	_has_boundary = geo.get("territory", {}).get("ok", false)
	_show_banner(sheet, geo.get("territory", {}))
	if _body != null:
		_scroll.remove_child(_body)
		_body.queue_free()
	for button in _tab_bar.get_children():
		_tab_bar.remove_child(button)
		button.queue_free()
	_tab_buttons.clear()
	_pages.clear()
	_active_tab = ""
	_fields.clear()
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_add_tab("Ficha")
	_build_identity()
	_build_names()
	_build_content()
	_build_footer()
	_add_tab("Governo")  # nos cadastros sem território político, esta página é a das relações
	if covered:
		_build_hierarchy()
	_build_links()
	if covered:
		_add_tab("Povo")
		_build_composition()
	if not _geo.is_empty():
		_add_tab("Território")
	_build_territory()
	division_rows.clear()
	division_editor = {}
	level_pickers.clear()
	if covered and not _geo.is_empty() and CHILD_OF.has(String(_sheet.kind)):
		_build_divisions(int(_sheet.id), String(_sheet.kind))
	_build_places()
	if not _geo.is_empty():
		_add_tab("População")
	_build_population()
	if not _calendars.is_empty():
		_add_tab("Calendários")
	_build_calendars()
	_select_tab(keep if _pages.has(keep) else "Ficha")
	_sync_focus()


## O cabeçalho: o brasão e o fundo na cor do cadastro (a do território, se tiver), o nome e "tipo · área".
func _show_banner(sheet: Dictionary, territory: Dictionary) -> void:
	var rgb := Color("#6e86d8")
	if territory.has("color"):
		var c := int(territory.color)
		rgb = Color8((c >> 16) & 255, (c >> 8) & 255, c & 255)
	_crest.color = rgb
	_banner.add_theme_stylebox_override("panel", UiKit.banner_style(rgb))
	_name_label.text = String(sheet.name)
	var area := float(territory.get("area_km2", 0.0))
	_subtitle.text = String(sheet.name) + ("  ·  ≈ %s km²" % LayerPanel._thousands(roundi(area)) if area > 0.0 else "")
	for child in _division_row.get_children():
		_division_row.remove_child(child)
		child.queue_free()
	division_picker = null
	var label := String(sheet.get("label", ""))
	_division_row.visible = label != ""
	back_button = null
	var country: Dictionary = _geo.get("chain", {}).get("country", {})
	if label != "":
		var caption := Label.new()
		caption.text = "Como se chama:"
		caption.add_theme_color_override("font_color", Color("#e6d3c8"))
		_division_row.add_child(caption)
		var me := int(sheet.id)
		division_picker = DivisionNamePicker.new(label, _geo.get("suggestions", []), "Como se chama esta divisão")
		division_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		division_picker.chosen.connect(func(n: String) -> void: division_named.emit(me, n))
		_division_row.add_child(division_picker)
		if not country.is_empty():
			back_button = Button.new()
			back_button.text = "‹ %s" % country.name
			back_button.tooltip_text = "Voltar para a lista de subdivisões de %s" % country.name
			back_button.clip_text = true
			back_button.custom_minimum_size.x = 96
			back_button.pressed.connect(func() -> void: division_back_requested.emit(me))
			_division_row.add_child(back_button)
			_division_row.move_child(back_button, 0)
			caption.hide()  # com o botão de voltar, o menu fala por si na linha estreita


func _add_tab(label: String) -> void:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.clip_text = true  # cinco abas cabem nos 420 px do painel
	button.add_theme_font_size_override("font_size", 11)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		wanted_page = label
		_select_tab(label))
	_tab_bar.add_child(button)
	_tab_buttons[label] = button
	_page = VBoxContainer.new()
	_body.add_child(_page)
	_pages[label] = _page


func _select_tab(label: String) -> void:
	if label == _active_tab:
		_tab_buttons[label].set_pressed_no_signal(true)
		return
	if not _active_tab.is_empty():
		_tab_scroll[_active_tab] = _scroll.scroll_vertical
	_active_tab = label
	for key in _pages:
		_pages[key].visible = key == label
		_tab_buttons[key].set_pressed_no_signal(key == label)
	_title.text = "%s · %s" % [page_title(label), UiKit.entry_label(String(_sheet.get("kind", "")), String(_sheet.get("label", "")))]
	_actions_wrap.visible = _has_actions and label in ["Governo", "Território"]
	_boundary_brush.visible = _has_boundary and label == "Território"
	_scroll.set_deferred("scroll_vertical", _tab_scroll.get(label, 0))
	page_changed.emit(label)
	_sync_focus()


## O nome da página como o cabeçalho a mostra: nos cadastros sem hierarquia, "Governo" é a página das relações.
func page_title(label: String) -> String:
	return "Relações" if label == "Governo" and not String(_sheet.get("kind", "")) in ["pais", "provincia", "municipio"] else label


func active_page() -> String:
	return _active_tab


func has_page(label: String) -> bool:
	return _pages.has(label)


## Abre a janela na página pedida (ela continua nessa categoria ao trocar de cadastro).
func show_page(label: String) -> void:
	wanted_page = label
	keep_closed = false
	if _sheet.is_empty():
		return
	visible = true
	if _pages.has(label):
		_select_tab(label)


## Fecha a janela sem tirar a seleção: ela só volta quando pedida.
func dismiss() -> void:
	keep_closed = true
	visible = false
	_sync_focus()


## Atualiza só as datas (universal e locais) quando o relógio anda, sem refazer a ficha. texts: id do uso -> texto.
func show_calendar_dates(universal: String, texts: Dictionary) -> void:
	if _universal_label != null:
		_universal_label.text = "Data universal: " + universal
	for use_id in texts:
		if _date_labels.has(use_id):
			_date_labels[use_id].text = texts[use_id]


## O ponto fixado no mapa mudou: o texto e se dá para criar um lugar nele. Não refaz a ficha.
func show_fixed_point(text: String, enabled: bool) -> void:
	if _fixed_label != null:
		_fixed_label.text = text
		_create_place_btn.disabled = not enabled


func show_territory_message(text: String) -> void:
	if _territory_msg != null:
		_territory_msg.text = text
		_territory_msg.visible = text != ""


func show_geo_message(text: String) -> void:
	if _geo_message != null:
		_geo_message.text = text


## O usuário está digitando na ficha ou com um menu aberto? Quem refaz a ficha (o hub) espera, para não tirar o foco nem fechar o menu.
func is_editing() -> bool:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f == null or not is_ancestor_of(f):
		return false
	if f is OptionButton or f is MenuButton:
		return f.get_popup().visible  # refazer a ficha destruiria o menu aberto
	return f is LineEdit or f is TextEdit


func hide_sheet() -> void:
	visible = false
	keep_closed = false
	_sheet = {}
	open_division = 0
	_sync_focus()


## A próxima ficha mostrada abre com esta subdivisão aberta na lista.
func queue_division(id: int) -> void:
	_queued_division = id


## O mapa só destaca a divisão enquanto a linha dela está à vista.
func _sync_focus() -> void:
	var now := open_division if visible and _active_tab == "Território" else 0
	if now != _focused_division:
		_focused_division = now
		division_focused.emit(now)


## O que ficou gravado num campo depois de uma edição (corrige o que o usuário digitou se foi recusado ou normalizado).
func update_field(code: String, state: String, value: String) -> void:
	if not _fields.has(code):
		return
	var f: Dictionary = _fields[code]
	f.last_state = state
	f.last_value = value
	f.state.select(maxi(STATES.find(state), 0))
	_write_editor(f, value)
	f.editor.visible = state == "known" or state == "unfilled"


## Candidatos para o vínculo que está sendo criado (cada um: id, kind, name).
func show_link_candidates(items: Array) -> void:
	if _link_candidates == null:
		return
	_link_candidates.clear()
	for it in items:
		if int(it.id) == current_id():
			continue
		_link_candidates.add_item("%s · %s" % [it.name, UiKit.entry_label(String(it.kind), String(it.get("label", "")))])
		_link_candidates.set_item_metadata(_link_candidates.item_count - 1, int(it.id))


func confirm_delete(name: String, links: int) -> void:
	_confirm.dialog_text = "Excluir \"%s\"?\n%s\nIsto é correção de um cadastro criado por engano, e não pode ser desfeito." % [
		name, "Nenhum vínculo será apagado." if links == 0 else "%d vínculo(s) com outros cadastros serão apagados." % links]
	_confirm.popup_centered()


# --- seções -------------------------------------------------------------------------------------------------------

func _build_identity() -> void:
	var id_box := _card("Identidade")
	var name_edit := LineEdit.new()
	var eid := int(_sheet.id)  # a entidade desta ficha: capturado agora, porque o foco pode sair quando outra ficha já abriu
	name_edit.text = _sheet.name
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.tooltip_text = "Corrige a grafia do nome. Uma mudança de nome no mundo (com data) é outro registro."
	var last: Array = [name_edit.text]
	var commit := func() -> void:
		var t := name_edit.text.strip_edges()
		if t == "":
			name_edit.text = last[0]  # o nome nunca fica vazio
		elif t != last[0]:
			last[0] = t
			name_changed.emit(eid, t)
	name_edit.text_submitted.connect(func(_t: String) -> void: commit.call())
	name_edit.focus_exited.connect(commit)
	id_box.add_child(name_edit)

	var summary_label := Label.new()
	summary_label.text = "Resumo"
	summary_label.modulate = Color(1, 1, 1, 0.7)
	id_box.add_child(summary_label)
	var summary := TextEdit.new()
	summary.text = _sheet.summary
	summary.custom_minimum_size = Vector2(0, 64)
	summary.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	summary.placeholder_text = "Opcional. Pode ficar vazio."
	var last_summary: Array = [summary.text]
	summary.focus_exited.connect(func() -> void:
		if summary.text != last_summary[0]:
			last_summary[0] = summary.text
			summary_changed.emit(eid, summary.text))
	id_box.add_child(summary)

	var tags := HFlowContainer.new()
	id_box.add_child(tags)
	for t in _sheet.tags:
		var b := Button.new()
		b.text = "%s ✕" % t
		b.flat = true
		b.tooltip_text = "Remover a etiqueta"
		b.pressed.connect(func() -> void: tag_removed.emit(t))
		tags.add_child(b)
	var new_tag := LineEdit.new()
	new_tag.placeholder_text = "＋ etiqueta"
	new_tag.custom_minimum_size = Vector2(110, 0)
	new_tag.text_submitted.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			tag_added.emit(t.strip_edges()))
	tags.add_child(new_tag)


func _build_names() -> void:
	var box := _section("Nomes")
	for n in _sheet.names:
		var text := ""
		if n.role == "principal":
			if n.to == FOREVER:
				continue  # o nome atual está no alto da ficha
			text = "Nome anterior: " + n.name
		else:
			text = "%s: %s" % [_role_label(n.role), n.name]
			if n.lang != "":
				text += "  (%s)" % n.lang
		box.add_child(_note(text))
	var row := HBoxContainer.new()
	box.add_child(row)
	var role := OptionButton.new()
	for r in ROLES:
		role.add_item(r[1])
	row.add_child(role)
	var edit := LineEdit.new()
	edit.placeholder_text = "novo nome"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var add := func() -> void:
		if edit.text.strip_edges() != "":
			alias_added.emit(ROLES[role.selected][0], edit.text.strip_edges())
	edit.text_submitted.connect(func(_t: String) -> void: add.call())
	var btn := Button.new()
	btn.text = "＋"
	btn.pressed.connect(add)
	row.add_child(btn)


func _build_content() -> void:
	var box := _section("Conteúdo")
	_add_menu = OptionButton.new()
	_add_menu.add_item("＋ Adicionar informação…")
	box.add_child(_add_menu)
	var hidden: Array = []
	for f in _sheet.fields:
		var entry := _make_field(f)
		box.add_child(entry.row)
		if f.state == "unfilled":
			entry.row.visible = false
			hidden.append(f)
	for f in hidden:
		_add_menu.add_item(f.label)
		_add_menu.set_item_metadata(_add_menu.item_count - 1, f.code)
	_add_menu.visible = hidden.size() > 0
	_add_menu.item_selected.connect(func(i: int) -> void:
		if i == 0:
			return
		var code: String = _add_menu.get_item_metadata(i)
		_fields[code].row.visible = true
		_add_menu.remove_item(i)
		_add_menu.select(0)
		_add_menu.visible = _add_menu.item_count > 1)


func _make_field(f: Dictionary) -> Dictionary:
	var eid := int(_sheet.id)  # ver _build_identity
	var row := VBoxContainer.new()
	var head := HBoxContainer.new()
	row.add_child(head)
	var label := Label.new()
	label.text = f.label + (" (%s)" % f.unit if f.unit != "" else "")
	label.tooltip_text = f.hint
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(label)
	var state := OptionButton.new()
	for s in STATE_LABELS:
		state.add_item(s)
	state.select(maxi(STATES.find(f.state), 0))
	head.add_child(state)

	var editor  # LineEdit, TextEdit ou OptionButton, conforme o tipo do campo
	match f.type:
		"number":
			editor = LineEdit.new()
			editor.placeholder_text = f.unit if f.unit != "" else "número"
		"choice":
			editor = OptionButton.new()
			editor.add_item("—")
			for o in f.options.split("\n", false):
				editor.add_item(o.strip_edges())
		"bool":
			editor = OptionButton.new()
			for o in ["—", "Sim", "Não"]:
				editor.add_item(o)
		_:
			editor = TextEdit.new()
			editor.custom_minimum_size = Vector2(0, 72)
			editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			editor.tooltip_text = f.hint
			editor.placeholder_text = f.hint
	row.add_child(editor)
	if f.has("computed"):  # regra automática ou valor fixado, na data mostrada
		var c: Dictionary = f.computed
		var shown := Label.new()
		shown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var number := UiKit.number_text(c.value)
		match String(c.status):
			"fixado":
				shown.text = "🔒 %s fixado na data mostrada%s" % [number, " (" + c.note + ")" if c.note != "" else ""]
			"erro":
				shown.text = "⚠ a regra \"%s\" não calculou: %s" % [c.rule, c.note]
			_:
				shown.text = "= %s pela regra \"%s\" na data mostrada" % [number, c.rule]
		shown.modulate = Color(0.55, 0.85, 1.0)
		row.add_child(shown)
	var entry := {"row": row, "state": state, "editor": editor, "type": f.type, "last_state": f.state, "last_value": f.value}
	_fields[f.code] = entry
	_write_editor(entry, f.value)
	editor.visible = f.state == "known" or f.state == "unfilled"

	var commit := func() -> void:
		var st: String = STATES[state.selected]
		var v := _read_editor(entry) if st == "known" else ""
		if st != entry.last_state or v != entry.last_value:
			entry.last_state = st
			entry.last_value = v
			field_edited.emit(eid, f.code, st, v)
	state.item_selected.connect(func(_i: int) -> void:
		editor.visible = state.selected == 0
		commit.call())
	if editor is OptionButton:
		editor.item_selected.connect(func(_i: int) -> void: commit.call())
	else:
		editor.focus_exited.connect(commit)
		if editor is LineEdit:
			editor.text_submitted.connect(func(_t: String) -> void: commit.call())
	return entry


func _read_editor(entry: Dictionary) -> String:
	var e = entry.editor
	if e is OptionButton:
		if entry.type == "bool":
			return ["", "true", "false"][e.selected]
		return "" if e.selected <= 0 else e.get_item_text(e.selected)
	return e.text.strip_edges()


func _write_editor(entry: Dictionary, value: String) -> void:
	var e = entry.editor
	if e is OptionButton:
		if entry.type == "bool":
			e.select(["", "true", "false"].find(value) if value != "" else 0)
		else:
			e.select(0)
			for i in e.item_count:
				if e.get_item_text(i) == value and value != "":
					e.select(i)
	else:
		e.text = value


## "Pertence a" (as subdivisões): a cadeia em uma linha e a linha de cada cima. "Divisões" (país e 1º nível): as de dentro, recolhíveis.
func _build_hierarchy() -> void:
	var kind := String(_sheet.kind)
	if not PARENT_OF.has(kind) and not CHILD_OF.has(kind):
		return
	var me := int(_sheet.id)
	var chain: Dictionary = _geo.get("chain", {"parent": {}, "country": {}})
	var parent: Dictionary = chain.parent
	if PARENT_OF.has(kind):
		var box := _card("Pertence a")
		var trail := HFlowContainer.new()
		trail.add_theme_constant_override("h_separation", 6)
		box.add_child(trail)
		var parts: Array = []
		if not chain.country.is_empty():
			parts.append([String(chain.country.name), int(chain.country.id), false])
		else:
			parts.append(["sem país", 0, true])
		if kind == "municipio" and not parent.is_empty() and String(parent.kind) == "provincia":
			parts.append([String(parent.name), int(parent.id), false])
		parts.append([String(_sheet.name), me, false])
		for i in parts.size():
			if i > 0:
				var arrow := Label.new()
				arrow.text = "›"
				arrow.modulate = Color(1, 1, 1, 0.6)
				trail.add_child(arrow)
			var p: Array = parts[i]
			var b := Button.new()
			b.text = p[0]
			b.flat = true
			b.disabled = p[1] == 0 or p[1] == me
			if p[2]:
				b.modulate = Color(1, 1, 1, 0.55)
			if p[1] != 0 and p[1] != me:
				b.pressed.connect(func() -> void: open_entity.emit(int(p[1])))
			trail.add_child(b)
		var direct_in_country := not parent.is_empty() and String(parent.kind) == "pais"
		_parent_line(box, "País", "pais", me, chain.country, direct_in_country)
		if kind == "municipio":
			var in_province := not parent.is_empty() and String(parent.kind) == "provincia"
			_parent_line(box, "Dentro de", "provincia", me, parent if in_province else {}, in_province)
	# As divisões (o que está dentro deste cadastro) ficam na aba Mapa: ver show_sheet.


## As subdivisões deste cadastro, na página Território. Cada linha abre ali mesmo para editar, sem sair do país: uma de cada vez. As do 2º
## nível aparecem quando a de cima está aberta (ou uma delas). Na ficha do país, a linha dos nomes diz como os dois níveis se chamam nele.
func _build_divisions(me: int, kind: String) -> void:
	var box := _card("Subdivisões")
	_division_groups.clear()
	level_toggle = null
	var tree: Array = _geo.get("division", [])
	var have: Array = [me]
	var total := 0
	for d in tree:
		have.append(int(d.id))
		for c in d.children:
			have.append(int(c.id))
		total += 1 + d.children.size()
	var head := HBoxContainer.new()
	box.add_child(head)
	var count := Label.new()
	count.text = "Nenhuma ainda." if total == 0 else "%d no total" % total
	count.modulate = Color(1, 1, 1, 0.65)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(count)
	var names: Array = _geo.get("level_names", [])
	if kind == "pais" and names.size() == 2:
		level_toggle = Button.new()
		level_toggle.flat = true
		level_toggle.text = "1º %s · 2º %s %s" % [names[0], names[1], "▾" if _level_names_open else "▸"]
		level_toggle.tooltip_text = "Como as subdivisões se chamam neste país"
		level_toggle.add_theme_font_size_override("font_size", 12)
		level_toggle.pressed.connect(func() -> void:
			_level_names_open = not _level_names_open
			_rebuild())
		head.add_child(level_toggle)
		if _level_names_open:
			_build_level_names(box, me)
	if not tree.is_empty():
		division_search = LineEdit.new()
		division_search.placeholder_text = "filtrar pelo nome"
		division_search.text = _division_filter
		division_search.clear_button_enabled = true
		division_search.text_changed.connect(func(t: String) -> void:
			_division_filter = t
			_filter_divisions())
		box.add_child(division_search)
	for d in tree:
		var group := VBoxContainer.new()
		box.add_child(group)
		var kids: Array = d.children
		var expanded: bool = open_division == int(d.id) or kids.any(func(c): return int(c.id) == open_division)
		var entry := {"box": group, "name": String(d.name), "kids": [], "expanded": expanded}
		_division_line(group, d, 0, ("▾" if expanded else "▸") if not kids.is_empty() else "")
		for c in kids:
			var row := _division_line(group, c, 24, "")
			entry.kids.append({"box": row, "name": String(c.name)})
		_division_groups.append(entry)
	_filter_divisions()
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	var paint := Button.new()
	paint.text = "＋ Pintar divisão"
	paint.add_theme_stylebox_override("normal", UiKit.active_style())
	paint.tooltip_text = "Pinta a área de uma subdivisão nova aqui dentro: o cartão pergunta o nome e como ela se chama."
	paint.pressed.connect(func() -> void: paint_kind_requested.emit("provincia" if kind == "pais" else "municipio", me))
	actions.add_child(paint)
	var link := Button.new()
	link.text = "Ligar existente…"
	actions.add_child(link)
	var picker := EntityPicker.new("digite o nome", "" if kind == "pais" else "municipio", _division_lookup(kind), have)
	picker.visible = false
	picker.picked.connect(func(id: int) -> void: hierarchy_set.emit(id, me))
	box.add_child(picker)
	link.pressed.connect(func() -> void: picker.visible = not picker.visible)


## Com texto no filtro, ficam as linhas cujo nome o contém (e a de cima delas).
func _filter_divisions() -> void:
	var text := _division_filter.strip_edges().to_lower()
	for group in _division_groups:
		var any_kid := false
		for kid in group.kids:
			var matches: bool = text != "" and String(kid.name).to_lower().contains(text)
			kid.box.visible = group.expanded if text == "" else matches
			any_kid = any_kid or matches
		group.box.visible = text == "" or any_kid or String(group.name).to_lower().contains(text)


## Uma linha da lista: a seta, a cor, o nome (abre e fecha o editor ali) e o nome do tipo.
func _division_line(parent: VBoxContainer, d: Dictionary, indent: int, arrow_text: String) -> Control:
	var id := int(d.id)
	var is_open := open_division == id
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", indent)
	parent.add_child(margin)
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05) if is_open else Color(0, 0, 0, 0)
	style.border_color = Color("#f2c46d") if is_open else Color(1, 1, 1, 0.14)
	style.set_border_width_all(1)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 8 if is_open else 2
	card.add_theme_stylebox_override("panel", style)
	margin.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 7)
	card.add_child(inner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 30
	inner.add_child(row)
	var arrow := Label.new()
	arrow.text = arrow_text
	arrow.custom_minimum_size.x = 12
	arrow.add_theme_color_override("font_color", Color("#f2c46d"))
	row.add_child(arrow)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(13, 13)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.color = _rgb(int(d.get("color", 0)))
	row.add_child(swatch)
	var name_button := Button.new()
	name_button.text = String(d.name)
	name_button.flat = true
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.clip_text = true
	name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_button.tooltip_text = "Fechar" if is_open else "Ver e editar aqui"
	name_button.pressed.connect(func() -> void: toggle_division(id))
	row.add_child(name_button)
	division_rows[id] = name_button
	var text := String(d.label)
	if indent == 0 and String(d.kind) == "municipio" and String(_sheet.kind) == "pais":
		text += " · direto no país"
	var pill := _pill(text, Color("#e0b45c") if d.differs else Color("#8fa9e0"))
	if d.differs:
		pill.tooltip_text = "Chamada diferente das outras deste nível"
		pill.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(pill)
	if is_open:
		_division_edit(inner, d, name_button, swatch)
	return margin


## Abre a linha (ou fecha, se já é a aberta).
func toggle_division(id: int) -> void:
	open_division = 0 if open_division == id else id
	_rebuild()


func _rebuild() -> void:
	show_sheet(_sheet, _types, _calendars, _geo)


## O editor de uma subdivisão, dentro da linha dela.
func _division_edit(box: VBoxContainer, d: Dictionary, name_button: Button, swatch: ColorRect) -> void:
	var id := int(d.id)
	var info: Dictionary = division_detail.call(id) if division_detail.is_valid() else {}
	if info.is_empty():
		return
	var name_edit := LineEdit.new()
	name_edit.text = String(info.name)
	name_edit.tooltip_text = "Corrige a grafia do nome"
	var last_name: Array = [name_edit.text]
	var commit_name := func() -> void:
		var t := name_edit.text.strip_edges()
		if t != "" and t != last_name[0]:
			last_name[0] = t
			name_button.text = t
			name_changed.emit(id, t)
	name_edit.focus_exited.connect(commit_name)
	name_edit.text_submitted.connect(func(_t: String) -> void: commit_name.call())
	_edit_row(box, "Nome", name_edit)
	var called := DivisionNamePicker.new(String(info.label), _geo.get("suggestions", []), "Como se chama esta divisão")
	called.chosen.connect(func(n: String) -> void: division_named.emit(id, n))
	_edit_row(box, "Como se chama", called)
	var total := LineEdit.new()
	total.placeholder_text = "sem total"
	total.text = LayerPanel._thousands(roundi(info.total)) if info.has_total else ""
	total.tooltip_text = "Habitantes na data mostrada. Apagar o número tira o total."
	var last_total: Array = [total.text]
	var commit_total := func() -> void:
		var t := total.text.strip_edges()
		if t != last_total[0]:
			last_total[0] = t
			division_total_set.emit(id, t)
	total.focus_exited.connect(commit_total)
	total.text_submitted.connect(func(_t: String) -> void: commit_total.call())
	_edit_row(box, "População", total)
	var area_row := HBoxContainer.new()
	var area := Label.new()
	area.text = "%s km²" % LayerPanel._thousands(roundi(info.area_km2)) if info.area_km2 > 0.0 else "Sem território"
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area_row.add_child(area)
	var color := ColorPickerButton.new()
	color.edit_alpha = false
	color.custom_minimum_size = Vector2(46, 26)
	color.tooltip_text = "Cor no mapa"
	color.color = _rgb(int(info.color))
	var rgb_of := func(c: Color) -> int:
		return (roundi(c.r * 255.0) << 16) | (roundi(c.g * 255.0) << 8) | roundi(c.b * 255.0)
	color.color_changed.connect(func(c: Color) -> void:
		swatch.color = c
		entity_color_changed.emit(id, rgb_of.call(c), false))
	color.popup_closed.connect(func() -> void: entity_color_changed.emit(id, rgb_of.call(color.color), true))
	area_row.add_child(color)
	_edit_row(box, "Área e cor", area_row)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	var paint := _grid_button(grid, "Pintar área", "Abre o pincel no globo, só dentro de quem está acima", func() -> void: division_paint_requested.emit(id, "pincel"))
	paint.add_theme_stylebox_override("normal", UiKit.active_style())
	paint.disabled = not info.ok
	var boundary := _grid_button(grid, "Pincel de fronteira", "Desenha o limite dela à mão", func() -> void: division_paint_requested.emit(id, "fronteira"))
	boundary.disabled = not info.ok or info.area_km2 <= 0.0
	var inside: Button = null
	if String(d.kind) == "provincia":
		inside = _grid_button(grid, "＋ Pintar dentro", "Uma subdivisão nova dentro desta", func() -> void: paint_kind_requested.emit("municipio", id))
		inside.disabled = not info.ok or info.area_km2 <= 0.0
	var view := _grid_button(grid, "Ver no mapa", "Leva o mapa até ela", func() -> void: division_view_requested.emit(id))
	view.disabled = info.area_km2 <= 0.0
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	var full := Button.new()
	full.text = "Ficha completa ›"
	full.flat = true
	full.tooltip_text = "Povo, lugares, outros nomes, calendários e o resto"
	full.pressed.connect(func() -> void: open_entity.emit(id))
	bottom.add_child(full)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	var remove := Button.new()
	remove.text = "Excluir divisão…"
	remove.pressed.connect(func() -> void: division_delete_requested.emit(id))
	bottom.add_child(remove)
	var message := _note("")
	message.visible = false
	box.add_child(message)
	division_editor = {"id": id, "name": name_edit, "called": called, "total": total, "color": color, "paint": paint, "boundary": boundary,
		"inside": inside, "view": view, "full": full, "remove": remove, "message": message}


## Um aviso na linha aberta (um número de habitantes que não vale, por exemplo).
func show_division_message(text: String) -> void:
	var label: Label = division_editor.get("message")
	if label != null:
		label.text = text
		label.visible = text != ""


func _edit_row(box: VBoxContainer, text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 116
	label.modulate = Color(1, 1, 1, 0.7)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _grid_button(grid: GridContainer, text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	grid.add_child(b)
	return b


static func _rgb(c: int) -> Color:
	return Color8((c >> 16) & 255, (c >> 8) & 255, c & 255)


func _build_level_names(box: VBoxContainer, country: int) -> void:
	var names: Array = _geo.get("level_names", [])
	box.add_child(_note("Trocar muda todas as que não têm um nome próprio."))
	for i in 2:
		var picker := DivisionNamePicker.new(String(names[i]), _geo.get("suggestions", []), "Nome do %dº nível" % (i + 1))
		var level := i + 1
		picker.chosen.connect(func(n: String) -> void: level_named.emit(country, level, n))
		_edit_row(box, ["1º nível", "2º nível"][i], picker)
		level_pickers.append(picker)


## A busca do "Ligar existente…" de um país: só províncias e municípios.
func _division_lookup(kind: String) -> Callable:
	if kind != "pais":
		return lookup
	return func(text: String, _kind: String) -> Array:
		var found: Array = lookup.call(text, "") if lookup.is_valid() else []
		return found.filter(func(it) -> bool: return String(it.kind) in ["provincia", "municipio"])


## Uma linha "País: Drikhor ✕" com o campo para trocar. `shown` é o cadastro mostrado (vazio = nenhum); `removable` diz se o ✕ tira o vínculo daqui.
func _parent_line(box: VBoxContainer, label_text: String, parent_kind: String, me: int, shown: Dictionary, removable: bool) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size.x = 84
	row.add_child(label)
	if shown.is_empty():
		var none := Label.new()
		none.text = "nenhum" if parent_kind == "pais" else "direto no país"
		none.modulate = Color(1, 1, 1, 0.6)
		row.add_child(none)
	else:
		var open := Button.new()
		open.text = String(shown.name)
		open.flat = true
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.pressed.connect(func() -> void: open_entity.emit(int(shown.id)))
		row.add_child(open)
		if removable:
			var del := Button.new()
			del.text = "✕"
			del.flat = true
			del.tooltip_text = "Tirar de %s (o território pintado continua)" % shown.name
			del.pressed.connect(func() -> void: hierarchy_set.emit(me, 0))
			row.add_child(del)
	var article := "a subdivisão" if parent_kind == "provincia" else "o país"
	var picker := EntityPicker.new(("trocar %s: digite o nome" if not shown.is_empty() else "escolher %s: digite o nome") % article, parent_kind, lookup, [me])
	picker.picked.connect(func(id: int) -> void: hierarchy_set.emit(me, id))
	box.add_child(picker)


## "Povo e cultura": para país, província e município, cada categoria com algo lista o que está presente e a origem do número: "pelo mapa" (a fração da área
## coberta pela camada pintada) ou "à mão" (um vínculo feito pela ficha, sem porcentagem). As vazias ficam numa linha de títulos recolhidos no fim.
func _build_composition() -> void:
	if not String(_sheet.kind) in ["pais", "provincia", "municipio"]:
		return
	var me := int(_sheet.id)
	var from_map: Dictionary = _geo.get("composition", {})
	var box := _card("Povo e cultura")
	var empty: Array = []
	for cat in CATEGORIES:
		var shown := {}
		var rows: Array = []
		for r in from_map.get(cat[0], []):
			shown[int(r.id)] = true
			rows.append([String(r.name), float(r.share), "pelo mapa", int(r.id), 0])
		var have: Array = [me]
		for l in _sheet.links:
			if l.outgoing and l.type == cat[2]:
				have.append(int(l.other_id))
				if not shown.has(int(l.other_id)):
					rows.append([String(l.other_name), -1.0, "à mão", int(l.other_id), int(l.id)])
		var expanded: bool = _category_open.get(String(cat[0]), false)
		if rows.is_empty() and not expanded:
			empty.append([cat, have])
			continue
		var caption := Button.new()
		caption.text = "● %s%s" % [("▾ " if rows.is_empty() else ""), String(cat[1]).to_upper()]
		caption.flat = true
		caption.alignment = HORIZONTAL_ALIGNMENT_LEFT
		caption.add_theme_font_size_override("font_size", 13)
		caption.add_theme_color_override("font_color", CATEGORY_COLORS[cat[0]])
		caption.add_theme_color_override("font_disabled_color", CATEGORY_COLORS[cat[0]])
		caption.disabled = not rows.is_empty()
		caption.pressed.connect(func() -> void:
			_category_open[String(cat[0])] = false
			show_sheet(_sheet, _types, _calendars, _geo))
		box.add_child(caption)
		for r in rows:
			_composition_row(box, r[0], r[1], r[2], r[3], r[4], CATEGORY_COLORS[cat[0]])
			_rule(box)
		_category_actions(box, cat, have, me)
	if not empty.is_empty():
		var line := HFlowContainer.new()
		line.add_theme_constant_override("h_separation", 6)
		box.add_child(line)
		for e in empty:
			var cat: Array = e[0]
			var fold := Button.new()
			fold.text = "%s (0) ▸" % cat[1]
			fold.flat = true
			fold.add_theme_font_size_override("font_size", 13)
			fold.modulate = Color(1, 1, 1, 0.7)
			fold.pressed.connect(func() -> void:
				_category_open[String(cat[0])] = true
				show_sheet(_sheet, _types, _calendars, _geo))
			line.add_child(fold)


## As duas formas de ligar numa categoria, em texto pequeno: escolher na lista (abre o campo de busca) e pintar no mapa (abre o rascunho já deste tipo).
func _category_actions(box: VBoxContainer, cat: Array, have: Array, me: int) -> void:
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	var pick := Button.new()
	pick.text = "＋ Escolher na lista"
	pick.tooltip_text = "Liga um cadastro que já existe: abre um campo de busca."
	actions.add_child(pick)
	var paint := Button.new()
	paint.text = "Pintar no mapa"
	paint.tooltip_text = "Pinta a área onde isto predomina; a porcentagem sai da sobreposição com este território."
	paint.pressed.connect(func() -> void: paint_kind_requested.emit(String(cat[0]), 0))
	actions.add_child(paint)
	var picker := EntityPicker.new("digite o nome", cat[0], lookup, have)
	picker.visible = false
	picker.picked.connect(func(id: int) -> void: link_added.emit(String(cat[2]), id))
	box.add_child(picker)
	pick.pressed.connect(func() -> void: picker.visible = not picker.visible)


func _composition_row(box: VBoxContainer, entry_name: String, share: float, origin: String, entry_id: int, link_id: int, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size.y = 32
	box.add_child(row)
	var open := Button.new()
	open.text = entry_name
	open.flat = true
	open.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.clip_text = true
	open.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	open.add_theme_font_size_override("font_size", 16)
	open.tooltip_text = entry_name
	open.pressed.connect(func() -> void: open_entity.emit(entry_id))
	row.add_child(open)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = maxf(share, 0.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(64, 10)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.35)
	track.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var pct := Label.new()
	pct.text = "%d%%" % roundi(share * 100.0) if share >= 0.0 else "—"
	pct.add_theme_font_size_override("font_size", 16)
	pct.custom_minimum_size.x = 44
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	row.add_child(_pill(origin, Color("#7fb8a8") if origin == "pelo mapa" else Color("#dfb868")))
	if link_id != 0:
		var del := Button.new()
		del.text = "✕"
		del.flat = true
		del.tooltip_text = "Tirar este vínculo"
		del.pressed.connect(func() -> void: link_removed.emit(link_id))
		row.add_child(del)


func _build_links() -> void:
	var covered := String(_sheet.kind) in ["pais", "provincia", "municipio"]
	var others: Array = _sheet.links.filter(func(l: Dictionary) -> bool: return not String(l.type) in ["provincia_de", "municipio_de"] and not (covered and l.outgoing and String(l.type) in PRESENCE_TYPES))  # estes estão em Hierarquia e Povo e cultura
	var collapsed := covered and others.is_empty()  # nada a mostrar: o bloco de ligar fica atrás de um clique (os controles existem, só escondidos)
	var toggle: Button = null
	if collapsed:
		toggle = Button.new()
		toggle.text = "Outras relações ▸"
		toggle.flat = true
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_page.add_child(toggle)
	var box := _card("Outras relações") if covered else _section("Relações")
	if collapsed:
		var hidden: Array = [box.get_parent().get_parent() if box.get_parent() is PanelContainer else box]  # o cartão (com a margem) inteiro
		for n in hidden:
			n.visible = false
		toggle.pressed.connect(func() -> void:
			var on: bool = not hidden[0].visible
			for n in hidden:
				n.visible = on
			toggle.text = "Outras relações ▾" if on else "Outras relações ▸")
	elif others.is_empty():
		box.add_child(_note("Nenhuma relação ainda."))
	for l in others:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = l.label + ":"
		row.add_child(label)
		var open := Button.new()
		open.text = "%s · %s" % [l.other_name, UiKit.entry_label(String(l.other_kind), String(l.get("other_label", "")))]
		open.flat = true
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.pressed.connect(func() -> void: open_entity.emit(int(l.other_id)))
		row.add_child(open)
		var del := Button.new()
		del.text = "✕"
		del.flat = true
		del.tooltip_text = "Apagar este vínculo (criado por engano)"
		del.pressed.connect(func() -> void: link_removed.emit(int(l.id)))
		row.add_child(del)
	if _types.is_empty():
		return
	var add := HBoxContainer.new()
	box.add_child(add)
	_link_type = OptionButton.new()
	for t in _types:
		_link_type.add_item(t.label)
	add.add_child(_link_type)
	_link_query = LineEdit.new()
	_link_query.placeholder_text = "buscar o outro cadastro"
	_link_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.add_child(_link_query)
	var add2 := HBoxContainer.new()
	box.add_child(add2)
	_link_candidates = OptionButton.new()
	_link_candidates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_link_candidates.fit_to_longest_item = false
	add2.add_child(_link_candidates)
	var go := Button.new()
	go.text = "Vincular"
	go.pressed.connect(func() -> void:
		if _link_candidates.item_count > 0 and _link_candidates.selected >= 0:
			link_added.emit(_types[_link_type.selected].code, int(_link_candidates.get_item_metadata(_link_candidates.selected))))
	add2.add_child(go)
	var search := func() -> void:
		link_search.emit(_link_query.text, _types[_link_type.selected].dst_kind)
	_link_query.text_changed.connect(func(_t: String) -> void: search.call())
	_link_type.item_selected.connect(func(_i: int) -> void: search.call())
	search.call()


## Só para países e províncias: a camada do nível (o território pintado, a cor, pintar e apagar).
func _build_territory() -> void:
	_territory_msg = null
	for b in _actions.get_children():
		_actions.remove_child(b)
		b.queue_free()
	_actions_wrap.hide()
	_has_actions = false
	if not _geo.has("territory"):
		return
	var info: Dictionary = _geo.territory
	var eid := int(_sheet.id)
	var box := _section("Território" if _sheet.kind in ["pais", "provincia", "municipio"] else "Área no mapa")
	var row := HBoxContainer.new()  # uma linha: a área, a cor e apagar
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var area := Label.new()
	area.text = "%s km²" % LayerPanel._thousands(roundi(info.area_km2)) if info.area_km2 > 0.0 else "Sem território"
	area.add_theme_font_size_override("font_size", 18)
	area.modulate = Color(1, 1, 1, 1.0 if info.area_km2 > 0.0 else 0.6)
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(area)
	var picker := ColorPickerButton.new()
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(46, 30)
	picker.tooltip_text = "Cor no mapa"
	picker.color = Color8((info.color >> 16) & 255, (info.color >> 8) & 255, info.color & 255)
	var rgb_of := func(c: Color) -> int:
		return (roundi(c.r * 255.0) << 16) | (roundi(c.g * 255.0) << 8) | roundi(c.b * 255.0)
	picker.color_changed.connect(func(c: Color) -> void: entity_color_changed.emit(eid, rgb_of.call(c), false))
	picker.popup_closed.connect(func() -> void: entity_color_changed.emit(eid, rgb_of.call(picker.color), true))
	row.add_child(picker)
	var paint := Button.new()  # a ação principal vai para a barra de ações, abaixo do cabeçalho
	paint.text = "Pintar território"
	paint.icon = UiIcons.get_icon("territory", 16)
	paint.disabled = not info.ok
	paint.tooltip_text = "Pinta no globo com o pincel; pintar sobre outro do mesmo nível toma o território dele" if info.ok else "Este cadastro tem um id acima de 65535: a camada política não comporta"
	paint.pressed.connect(func() -> void: territory_paint_requested.emit())
	paint.add_theme_stylebox_override("normal", UiKit.active_style())
	paint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_child(paint)
	_has_actions = true
	var clear := Button.new()
	clear.text = "Apagar"
	clear.disabled = info.area_km2 <= 0.0
	clear.tooltip_text = "Apaga todo o território pintado deste cadastro (Ctrl+Z desfaz)"
	clear.pressed.connect(func() -> void: territory_clear_requested.emit())
	row.add_child(clear)
	if String(_sheet.kind) in ["pais", "provincia", "municipio"]:
		var split := Button.new()
		split.text = "Dividir"
		split.disabled = info.area_km2 <= 0.0 or not info.ok
		split.tooltip_text = "Divide o território em dois por uma linha: o lado que sai vira um cadastro novo, com as subdivisões dele (Ctrl+Z desfaz)"
		split.pressed.connect(func() -> void: territory_split_requested.emit())
		row.add_child(split)
	if info.has("claims"):
		var claim := Button.new()
		claim.text = "Pintar reivindicação"
		claim.disabled = not info.ok
		claim.tooltip_text = "Pinta o que este país reivindica, inclusive sobre outro país: a fronteira não muda (Ctrl+Z desfaz)"
		claim.pressed.connect(func() -> void: territory_claim_requested.emit())
		_actions.add_child(claim)
		for c in info.claims.claims:
			box.add_child(_note("Reivindica %s km² de %s" % [LayerPanel._thousands(roundi(c.km2)), c.name]))
		for c in info.claims.claimed_by:
			box.add_child(_note("%s reivindica %s km² daqui" % [c.name, LayerPanel._thousands(roundi(c.km2))]))
	_territory_msg = _note("")
	_territory_msg.visible = false
	box.add_child(_territory_msg)


func _build_places() -> void:
	_place_pickers.clear()
	_fixed_label = null
	_create_place_btn = null
	if _geo.is_empty():
		return
	var box := _section("Lugares")
	if _sheet.presences.is_empty():
		var none := Label.new()
		none.text = "Em nenhum lugar ainda"
		none.modulate = Color(1, 1, 1, 0.55)
		box.add_child(none)
	for p in _sheet.presences:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size.y = 32
		box.add_child(row)
		var what := "ponto"
		if p.radius_km > 0.0:
			what = "área de %s km" % LayerPanel._thousands(roundi(p.radius_km))
		var color: Color = UiKit.layer_color.get(p.layer, Color.WHITE)
		var open := Button.new()
		open.text = String(p.place)
		open.flat = true
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.clip_text = true
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.add_theme_font_size_override("font_size", 16)
		open.add_theme_color_override("font_color", color.lightened(0.3))
		open.tooltip_text = "Centralizar o mapa neste lugar · %s · %s · certeza %s" % [what, UiKit.layer_label.get(p.layer, p.layer), UiKit.CERTAINTY_LABEL.get(p.certainty, p.certainty)]
		open.pressed.connect(func() -> void: place_focus_requested.emit(int(p.place_id)))
		row.add_child(open)
		if what != "ponto":
			var detail := Label.new()
			detail.text = what
			detail.add_theme_font_size_override("font_size", 12)
			detail.modulate = Color(1, 1, 1, 0.6)
			row.add_child(detail)
		row.add_child(_pill(UiKit.role_label(p.role), color))
		var edit_button := Button.new()
		edit_button.text = "✎"
		edit_button.flat = true
		edit_button.toggle_mode = true
		edit_button.tooltip_text = "Editar o lugar: nome, tipo, raio e posição (vale em todas as fichas que o usam)"
		row.add_child(edit_button)
		var del := Button.new()
		del.text = "✕"
		del.flat = true
		del.tooltip_text = "Apagar esta presença (criada por engano)"
		del.pressed.connect(func() -> void: presence_removed.emit(int(p.id)))
		row.add_child(del)
		var editor := _place_editor(p)
		editor.visible = false
		box.add_child(editor)
		edit_button.toggled.connect(func(on: bool) -> void: editor.visible = on)
		_rule(box)
	var role_keys: Array = UiKit.ROLE_LABEL.keys()

	# Dois jeitos de pôr um lugar, um formulário de cada vez.
	var choices := HFlowContainer.new()
	choices.add_theme_constant_override("h_separation", 8)
	choices.add_theme_constant_override("v_separation", 6)
	box.add_child(choices)
	var forms: Array = []
	var group := ButtonGroup.new()
	group.allow_unpress = true
	var add_form := func(title: String, tip: String) -> VBoxContainer:
		var button := Button.new()
		button.text = title
		button.tooltip_text = tip
		button.toggle_mode = true
		button.button_group = group
		choices.add_child(button)
		var form := VBoxContainer.new()
		form.visible = false
		form.add_theme_constant_override("separation", 6)
		box.add_child(form)
		forms.append(form)
		button.toggled.connect(func(on: bool) -> void: form.visible = on)
		return form

	# 1. Ligar a um lugar que já existe.
	var existing: VBoxContainer = add_form.call("＋ Existente", "Liga um lugar que já existe no mundo.")
	var place := _place_picker(existing)
	var existing_row := HBoxContainer.new()
	existing_row.add_theme_constant_override("separation", 8)
	existing.add_child(existing_row)
	var role_a := _option(role_keys, func(k): return UiKit.ROLE_LABEL[k])
	role_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	existing_row.add_child(role_a)
	var link := Button.new()
	link.text = "Vincular"
	link.pressed.connect(func() -> void:
		if place.item_count > 0 and place.selected >= 0:
			presence_added.emit(int(place.get_item_metadata(place.selected)), role_keys[role_a.selected]))
	existing_row.add_child(link)

	# 2. Criar um lugar no ponto fixado no globo.
	var created: VBoxContainer = add_form.call("＋ No ponto fixado", "Cria um lugar onde você clicou no globo.")
	_fixed_label = Label.new()
	_fixed_label.text = _geo.fixed_text
	_fixed_label.add_theme_font_size_override("font_size", 13)
	_fixed_label.modulate = Color(1, 1, 1, 0.7)
	created.add_child(_fixed_label)
	var new_row := HBoxContainer.new()
	new_row.add_theme_constant_override("separation", 8)
	created.add_child(new_row)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "nome do lugar"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_child(name_edit)
	var radius := SpinBox.new()
	radius.min_value = 0
	radius.max_value = 8000
	radius.step = 10
	radius.suffix = "km"
	radius.tooltip_text = "Raio da área aproximada; 0 = um ponto"
	new_row.add_child(radius)
	var new_row2 := HFlowContainer.new()
	created.add_child(new_row2)
	var kind_keys: Array = UiKit.PLACE_KIND_LABEL.keys()
	var kind := _option(kind_keys, func(k): return UiKit.PLACE_KIND_LABEL[k])
	new_row2.add_child(kind)
	var role := _option(role_keys, func(k): return UiKit.ROLE_LABEL[k])
	new_row2.add_child(role)
	_create_place_btn = Button.new()
	_create_place_btn.text = "Criar lugar aqui"
	_create_place_btn.disabled = not _geo.has_fixed
	_create_place_btn.pressed.connect(func() -> void:
		if name_edit.text.strip_edges() != "":
			place_created.emit(name_edit.text.strip_edges(), kind_keys[kind.selected], radius.value, role_keys[role.selected]))
	new_row2.add_child(_create_place_btn)


## Editar um lugar: nome, tipo e raio (Salvar) e a posição (Mover no globo: o próximo clique). Tudo desfaz com Ctrl+Z.
func _place_editor(p: Dictionary) -> HFlowContainer:
	var form := HFlowContainer.new()
	form.add_theme_constant_override("h_separation", 8)
	form.add_theme_constant_override("v_separation", 6)
	var name_edit := LineEdit.new()
	name_edit.text = String(p.place)
	name_edit.custom_minimum_size.x = 160
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(name_edit)
	var kind_keys: Array = UiKit.PLACE_KIND_LABEL.keys()
	var kind := _option(kind_keys, func(k): return UiKit.PLACE_KIND_LABEL[k])
	kind.selected = maxi(0, kind_keys.find(String(p.place_kind)))
	form.add_child(kind)
	var radius := SpinBox.new()
	radius.min_value = 0
	radius.max_value = 8000
	radius.step = 10
	radius.suffix = "km"
	radius.value = float(p.radius_km)
	radius.tooltip_text = "Raio da área aproximada; 0 = um ponto"
	form.add_child(radius)
	var save := Button.new()
	save.text = "Salvar"
	save.pressed.connect(func() -> void:
		place_edited.emit(int(p.place_id), name_edit.text.strip_edges(), kind_keys[kind.selected], radius.value))
	form.add_child(save)
	var move := Button.new()
	move.text = "Mover no globo"
	move.tooltip_text = "O próximo clique no globo leva o lugar (e a área em volta dele) para lá. Esc cancela."
	move.pressed.connect(func() -> void: place_move_requested.emit(int(p.place_id)))
	form.add_child(move)
	return form


func _build_population() -> void:
	_geo_message = null
	if _geo.is_empty():
		return
	var box := _section("População")
	var pop: Dictionary = _sheet.population
	var fmt := func(v: float) -> String: return LayerPanel._thousands(roundi(v))
	var total_row := HBoxContainer.new()
	total_row.add_theme_constant_override("separation", 8)
	box.add_child(total_row)
	var total_label := Label.new()
	total_label.text = "Total: %s" % fmt.call(pop.total) if pop.has_total else "Sem população total"
	total_label.add_theme_font_size_override("font_size", 18)
	total_label.modulate = Color(1, 1, 1, 1.0 if pop.has_total else 0.6)
	total_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_row.add_child(total_label)
	if pop.has_total:
		var del_total := Button.new()
		del_total.text = "✕"
		del_total.flat = true
		del_total.tooltip_text = "Apagar a população total"
		del_total.pressed.connect(func() -> void: total_removed.emit())
		total_row.add_child(del_total)
	var set_row := HBoxContainer.new()
	set_row.add_theme_constant_override("separation", 8)
	box.add_child(set_row)
	var total_edit := LineEdit.new()
	total_edit.placeholder_text = "número exato de habitantes"
	total_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_row.add_child(total_edit)
	var set_total := Button.new()
	set_total.text = "Definir"
	set_total.tooltip_text = "Vale para a data mostrada pelo relógio"
	set_total.pressed.connect(func() -> void: total_set.emit(total_edit.text.strip_edges()))
	set_row.add_child(set_total)
	if pop.has_total or not pop.cities.is_empty():
		_rule(box)
		var head := Label.new()
		head.text = "Por cidade"
		head.modulate = Color(1, 1, 1, 0.7)
		box.add_child(head)
	for e in pop.cities:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var name_label := Label.new()
		name_label.text = String(e.place)
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var num := Label.new()
		num.text = fmt.call(e.low)
		row.add_child(num)
		var del := Button.new()
		del.text = "✕"
		del.flat = true
		del.tooltip_text = "Tirar esta cidade da distribuição"
		del.pressed.connect(func() -> void: estimate_removed.emit(int(e.id)))
		row.add_child(del)
	if pop.has_total and pop.outside >= 0.0:
		box.add_child(_note("Fora das cidades: %s" % fmt.call(pop.outside)))
	elif pop.has_total:
		var over := _note("As cidades passam do total em %s" % fmt.call(-pop.outside))
		over.modulate = Color(1.0, 0.6, 0.5)
		box.add_child(over)
	for c in _sheet.compositions:
		var when2: String = _geo.dates_d.get(int(c.id), "")
		var head := "%s em %s%s (%s, %s)" % [UiKit.kind_label(c.dimension), c.place, "  ·  " + when2 if when2 != "" else "",
			"categorias exclusivas" if c.exclusive else "podem se sobrepor", "lista completa" if c.complete else "lista incompleta"]
		var head_row := HBoxContainer.new()
		box.add_child(head_row)
		var head_label := _note(head)
		head_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head_row.add_child(head_label)
		var drop := Button.new()
		drop.text = "✕"
		drop.flat = true
		drop.tooltip_text = "Apagar esta composição (desfaz com Ctrl+Z)"
		drop.pressed.connect(func() -> void: distribution_removed.emit(int(c.id)))
		head_row.add_child(drop)
		for s in c.shares:
			var line := "     %s: %s%%" % [s.name, _pct(s.pct)]
			if s.has("low"):
				line += "  ≈ " + _range(s.low, s.high) + " pessoas"
			box.add_child(_note(line))
		if c.unknown_pct > 0.0:
			box.add_child(_note("     desconhecido: %s%%" % _pct(c.unknown_pct)))
		if c.denominator.is_empty():
			box.add_child(_note("     (sem população de referência: só percentuais)"))
	_rule(box)
	# Só as cidades desta ficha (assentamentos ligados a ela); sem nenhuma, ou para outra, "Nova cidade" no ponto fixado no globo.
	var cities: Array = _geo.get("cities", [])
	var place := OptionButton.new()
	place.fit_to_longest_item = false
	place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place.clip_text = true
	for c in cities:
		place.add_item(c.name)
		place.set_item_metadata(place.item_count - 1, int(c.id))
	place.add_item("＋ Nova cidade…")
	place.set_item_metadata(place.item_count - 1, -1)
	place.select(0)
	box.add_child(place)
	var fresh := VBoxContainer.new()
	fresh.visible = place.get_item_metadata(place.selected) == -1
	box.add_child(fresh)
	var new_name := LineEdit.new()
	new_name.placeholder_text = "nome da cidade nova"
	fresh.add_child(new_name)
	var where := _note(_geo.fixed_text if _geo.has_fixed else "Clique no globo para fixar onde fica a cidade.")
	fresh.add_child(where)
	place.item_selected.connect(func(i: int) -> void: fresh.visible = place.get_item_metadata(i) == -1)
	var add := HBoxContainer.new()
	add.add_theme_constant_override("separation", 8)
	box.add_child(add)
	var count := LineEdit.new()
	count.placeholder_text = "habitantes da cidade"
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.add_child(count)
	var go := Button.new()
	go.text = "Adicionar cidade"
	go.tooltip_text = "Vale para a data mostrada pelo relógio"
	go.pressed.connect(func() -> void:
		var n := count.text.strip_edges()
		var pid: int = place.get_item_metadata(place.selected)
		if pid != -1:
			estimate_added.emit(pid, n, n, "", "alta")
		elif new_name.text.strip_edges() == "":
			_geo_message.text = "Dê um nome à cidade nova."
		elif not _geo.has_fixed:
			_geo_message.text = "Clique no globo para fixar onde fica a cidade."
		else:
			city_created.emit(new_name.text.strip_edges(), n))
	add.add_child(go)
	_geo_message = _note("")
	box.add_child(_geo_message)
	_composition_form(box)


## "＋ Composição": em que lugar (cidade ou região), por qual dimensão, se as categorias são exclusivas e se a lista é completa, e as
## categorias com o percentual de cada uma. Vale para a data mostrada; o hub confere as somas e grava.
func _composition_form(box: VBoxContainer) -> void:
	var toggle := Button.new()
	toggle.text = "＋ Composição"
	toggle.toggle_mode = true
	toggle.tooltip_text = "Quanto da população desta ficha, num lugar, é de cada raça, etnia, cultura, religião ou idioma"
	box.add_child(toggle)
	var form := VBoxContainer.new()
	form.visible = false
	form.add_theme_constant_override("separation", 6)
	box.add_child(form)
	composition_form = form
	toggle.toggled.connect(func(on: bool) -> void: form.visible = on)
	var place := _place_picker(form)
	var dims: Array = ["cultura", "etnia", "raca", "religiao", "idioma"]
	var dim := _option(dims, func(k): return UiKit.kind_label(k))
	var flags := HFlowContainer.new()
	flags.add_theme_constant_override("h_separation", 10)
	form.add_child(flags)
	flags.add_child(dim)
	var exclusive := CheckBox.new()
	exclusive.text = "Exclusivas"
	exclusive.button_pressed = true
	exclusive.tooltip_text = "Cada pessoa está em uma só categoria (desligado: falantes de vários idiomas contam em cada um)"
	flags.add_child(exclusive)
	var complete := CheckBox.new()
	complete.text = "Lista completa"
	complete.tooltip_text = "A lista traz todas as categorias; exclusiva e completa precisa somar 100%"
	flags.add_child(complete)
	var rows := VBoxContainer.new()
	form.add_child(rows)
	var add_row := func() -> void:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		rows.add_child(row)
		var who := OptionButton.new()
		who.fit_to_longest_item = false
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.clip_text = true
		var found: Array = lookup.call("", dims[dim.selected]) if lookup.is_valid() else []
		for e in found:
			who.add_item(String(e.name))
			who.set_item_metadata(who.item_count - 1, int(e.id))
		row.add_child(who)
		var pct := SpinBox.new()
		pct.min_value = 0
		pct.max_value = 100
		pct.step = 0.1
		pct.suffix = "%"
		row.add_child(pct)
		var remove := Button.new()
		remove.text = "✕"
		remove.flat = true
		remove.pressed.connect(row.queue_free)
		row.add_child(remove)
	dim.item_selected.connect(func(_i: int) -> void:
		for r in rows.get_children():
			r.queue_free()
		add_row.call())
	add_row.call()
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	form.add_child(actions)
	var more := Button.new()
	more.text = "＋ categoria"
	more.pressed.connect(add_row)
	actions.add_child(more)
	var go := Button.new()
	go.text = "Criar composição"
	go.tooltip_text = "Vale para a data mostrada pelo relógio"
	go.pressed.connect(func() -> void:
		var ids: Array = []
		var pcts: Array = []
		for r in rows.get_children():
			if r.is_queued_for_deletion():
				continue
			var who: OptionButton = r.get_child(0)
			if who.selected >= 0:
				ids.append(int(who.get_item_metadata(who.selected)))
				pcts.append(float(r.get_child(1).value))
		var pid: int = place.get_item_metadata(place.selected) if place.selected >= 0 else 0
		distribution_added.emit(pid, dims[dim.selected], exclusive.button_pressed, complete.button_pressed, ids, pcts))
	actions.add_child(go)


## Um menu de lugar com busca por nome: mostra os primeiros lugares e, ao digitar, o hub devolve os que casam (show_place_candidates).
func _place_picker(box: VBoxContainer) -> OptionButton:
	var row := HBoxContainer.new()
	box.add_child(row)
	var query := LineEdit.new()
	query.placeholder_text = "buscar lugar"
	query.custom_minimum_size = Vector2(110, 0)
	query.text_changed.connect(func(t: String) -> void: place_search.emit(t))
	row.add_child(query)
	var pick := OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.fit_to_longest_item = false  # o nome mais comprido não alarga o painel (largura fixa)
	pick.custom_minimum_size.x = 90
	row.add_child(pick)
	_fill_places(pick, _geo.places, _geo.get("places_more", false))
	_place_pickers.append(pick)
	return pick


func _fill_places(pick: OptionButton, items: Array, more: bool) -> void:
	pick.clear()
	for pl in items:
		pick.add_item(pl.name)
		pick.set_item_metadata(pick.item_count - 1, int(pl.id))
	if more:  # há mais do que cabe: o aviso não é escolhível
		pick.add_item("… há mais: refine a busca")
		pick.set_item_disabled(pick.item_count - 1, true)
	if pick.item_count > 0:
		pick.select(0)


## O resultado de uma busca de lugar (cada um: id, name) nos menus de lugar da ficha; more = havia mais do que cabe.
func show_place_candidates(items: Array, more: bool) -> void:
	for pick in _place_pickers:
		if is_instance_valid(pick):
			_fill_places(pick, items, more)


func _option(keys: Array, label_of: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.fit_to_longest_item = false  # a largura é a do item escolhido, não a do mais comprido
	for k in keys:
		o.add_item(label_of.call(k))
	return o


func _range(low: float, high: float) -> String:
	return LayerPanel._thousands(roundi(low)) if is_equal_approx(low, high) else "%s–%s" % [LayerPanel._thousands(roundi(low)), LayerPanel._thousands(roundi(high))]


func _pct(v: float) -> String:
	return ("%.1f" % v).rstrip("0").rstrip(".").replace(".", ",")


func _build_calendars() -> void:
	_universal_label = null
	_date_labels.clear()
	if _calendars.is_empty():
		return
	var box := _section("Calendários")
	_universal_label = _note("Data universal: " + _calendars.universal)
	box.add_child(_universal_label)
	if _calendars.uses.is_empty():
		box.add_child(_note("Nenhum calendário em uso."))
	for u in _calendars.uses:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = "%s · %s" % [PURPOSES.get(u.purpose, u.purpose), u.name]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_text = "Prioridade de exibição: %d" % u.priority
		row.add_child(label)
		var del := Button.new()
		del.text = "✕"
		del.flat = true
		del.tooltip_text = "Apagar este uso (criado por engano)"
		del.pressed.connect(func() -> void: calendar_use_removed.emit(int(u.use_id)))
		row.add_child(del)
		var date := Label.new()
		date.text = u.text
		date.autowrap_mode = TextServer.AUTOWRAP_WORD
		_date_labels[int(u.use_id)] = date
		box.add_child(date)
	if _calendars.choices.is_empty():
		box.add_child(_note("Nenhum calendário cadastrado: crie um em Mundo ▾ → Calendários…"))
		return
	var add := HBoxContainer.new()
	box.add_child(add)
	var cal := OptionButton.new()
	cal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in _calendars.choices:
		cal.add_item(c.name)
		cal.set_item_metadata(cal.item_count - 1, int(c.id))
	add.add_child(cal)
	var purpose := OptionButton.new()
	for p in PURPOSES:
		purpose.add_item(PURPOSES[p])
		purpose.set_item_metadata(purpose.item_count - 1, p)
	add.add_child(purpose)
	var go := Button.new()
	go.text = "Usar"
	go.pressed.connect(func() -> void: calendar_use_added.emit(int(cal.get_item_metadata(cal.selected)), purpose.get_item_metadata(purpose.selected)))
	add.add_child(go)


func _build_footer() -> void:
	var footer := _card("Ações")
	var row := HBoxContainer.new()
	footer.add_child(row)
	var with_links := CheckBox.new()
	with_links.text = "com vínculos"
	row.add_child(with_links)
	var dup := Button.new()
	dup.text = "Duplicar"
	dup.pressed.connect(func() -> void: duplicate_requested.emit(with_links.button_pressed))
	row.add_child(dup)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var del := Button.new()
	del.text = "Excluir…"
	del.pressed.connect(func() -> void: delete_requested.emit())
	row.add_child(del)


# --- peças -----------------------------------------------------------------------------------------------------------

## Uma seção em cartão: um bloco com borda, o título em Cinzel e o conteúdo logo abaixo (devolve onde pôr o conteúdo).
func _card(title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.card_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()  # um respiro entre os cartões
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_child(card)
	_page.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 19)
	UiKit.style_heading(l)
	box.add_child(l)
	return box


## Um filete fino entre linhas de uma lista.
func _rule(box: VBoxContainer) -> void:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.08)
	line.custom_minimum_size = Vector2(0, 1)
	box.add_child(line)


## Uma etiqueta arredondada (a origem do número, o resumo de uma divisão).
func _pill(text: String, color: Color) -> PanelContainer:
	var pill := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.16)
	style.border_color = Color(color.r, color.g, color.b, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color.lightened(0.25))
	pill.add_child(label)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return pill


func _section(title: String) -> VBoxContainer:
	return _card(title)


func _label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)
	_page.add_child(l)


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.modulate = Color(1, 1, 1, 0.8)
	return l


func _role_label(role: String) -> String:
	for r in ROLES:
		if r[0] == role:
			return r[1]
	return role
