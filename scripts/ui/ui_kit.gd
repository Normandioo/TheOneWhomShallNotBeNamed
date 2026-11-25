## Peças comuns da interface: o estilo dos painéis e os nomes dos tipos de cadastro.

const KINDS := ["cultura", "pais", "raca", "etnia", "idioma", "religiao", "provincia", "municipio"]  # novos tipos no fim: o menu "Novo" usa o índice
const KIND_LABEL := {"cultura": "Cultura", "pais": "País", "provincia": "Província", "municipio": "Município", "raca": "Raça", "etnia": "Etnia", "idioma": "Idioma", "religiao": "Religião"}


## As camadas do mapa de presenças (uma por tipo de entidade): chave -> cor e nome.
const LAYERS := ["politica", "cultural", "etnica", "linguistica", "religiosa", "racial"]
const LAYER_COLOR := {
	"politica": Color(0.95, 0.45, 0.30), "cultural": Color(0.95, 0.80, 0.30), "etnica": Color(0.45, 0.85, 0.50),
	"linguistica": Color(0.40, 0.80, 0.95), "religiosa": Color(0.75, 0.55, 0.95), "racial": Color(0.95, 0.50, 0.75),
}
const LAYER_LABEL := {
	"politica": "Fronteira política", "cultural": "Presença cultural", "etnica": "Distribuição étnica",
	"linguistica": "Área linguística", "religiosa": "Presença religiosa", "racial": "Habitat de raça",
}
const ROLE_LABEL := {
	"capital": "Capital", "sede": "Sede", "origem": "Origem", "presenca": "Presença", "centro_cultural": "Centro cultural",
	"lugar_sagrado": "Lugar sagrado", "territorio": "Território", "reivindicacao": "Reivindicação", "outro": "Outro",
}
const PLACE_KIND_LABEL := {"assentamento": "Assentamento", "regiao": "Região", "local_sagrado": "Local sagrado", "natural": "Natural", "outro": "Outro"}
const CERTAINTY_LABEL := {"alta": "alta", "media": "média", "baixa": "baixa", "desconhecida": "desconhecida"}


static func role_label(role: String) -> String:
	return ROLE_LABEL.get(role, role)


## Os tipos criados pelo usuário (Registry.EntityTypes, os que não são de fábrica): o DomainHub os põe aqui ao abrir e ao criar.
static var custom_kinds: Array = []
static var custom_labels := {}


static func set_types(types: Array) -> void:
	custom_kinds = []
	custom_labels = {}
	for t in types:
		if not t.builtin:
			custom_kinds.append(String(t.code))
			custom_labels[String(t.code)] = String(t.label)


## As camadas do mapa de presenças vindas do banco (Registry.MapLayers): as de fábrica e as criadas pelo usuário. Começam com as de fábrica.
static var layer_list: Array = LAYERS.duplicate()
static var layer_color: Dictionary = LAYER_COLOR.duplicate()
static var layer_label: Dictionary = LAYER_LABEL.duplicate()


static func set_layers(layers: Array) -> void:
	layer_list = []
	for l in layers:
		var code := String(l.code)
		layer_list.append(code)
		layer_label[code] = String(l.label)
		if not LAYER_COLOR.has(code):
			var rgb := int(l.rgb)
			layer_color[code] = Color8((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255)


## Todos os tipos de entidade: os de fábrica e depois os criados.
static func all_kinds() -> Array:
	return KINDS + custom_kinds


## Um número para mostrar: inteiro sem casas, senão com até 2 casas; NaN = "—".
static func number_text(v: float) -> String:
	if is_nan(v):
		return "—"
	return str(int(v)) if v == floorf(v) and absf(v) < 1e15 else str(snappedf(v, 0.01))


static func kind_label(kind: String) -> String:
	return KIND_LABEL.get(kind, custom_labels.get(kind, kind))



# O nome BRASS ficou do primeiro tema: a cor de destaque agora é o rosa-terracota do desenho "Telas" (painéis seguem verde-petróleo).
const BRASS := Color("#c98a82")
const PAPER := Color("#f2e9d4")
const FRAME := Color("#8e5650")
const FOCUS := Color("#ebb5ab")
const ACTIVE := Color("#6b3b3a")
const PANEL := Color("#142328")
const BAR := Color("#0f1c20")
const LINE := Color("#2e4247")
const MUTED := Color("#b9b29f")

const UiIcons = preload("res://scripts/ui/ui_icons.gd")
const FONT_TEXT := preload("res://assets/fonts/SourceSans3.ttf")
const FONT_HEADING := preload("res://assets/fonts/Cinzel.ttf")


static func _surface(fill: Color, border: Color, horizontal: int, vertical: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = horizontal
	sb.content_margin_right = horizontal
	sb.content_margin_top = vertical
	sb.content_margin_bottom = vertical
	return sb


## Um painel solto (janelas, menus): borda de destaque e a linha mais forte em cima.
## O cartão de uma seção da ficha (Pertence a, Divisões, Povo e cultura): um bloco um pouco mais claro que o painel, com borda, para as seções se distinguirem.
static func card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#1b2f35")
	s.border_color = Color("#34505a")
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


static func panel_style() -> StyleBoxFlat:
	var panel := _surface(Color("#142328f5"), FRAME, 12, 10)
	panel.border_width_top = 2
	panel.shadow_color = Color(0, 0, 0, 0.38)
	panel.shadow_size = 5
	panel.shadow_offset = Vector2(0, 2)
	return panel


## Um painel acoplado à borda da janela (o Índice, a ficha, a coluna de modos): reto, só com a divisória do lado de dentro.
## side: SIDE_LEFT ou SIDE_RIGHT = o lado em que a divisória aparece.
static func dock_style(side: int, horizontal := 12, vertical := 10) -> StyleBoxFlat:
	var dock := _surface(PANEL, LINE, horizontal, vertical)
	dock.set_border_width_all(0)
	dock.set_border_width(side as Side, 1)
	dock.set_corner_radius_all(0)
	return dock


## As barras de cima e de baixo, em toda a largura: divisória só do lado de dentro (em cima: embaixo; embaixo: em cima).
static func bar_style(side: int, color := FRAME) -> StyleBoxFlat:
	var bar := _surface(BAR, color, 14, 6)
	bar.set_border_width_all(0)
	bar.set_border_width(side as Side, 1)
	bar.set_corner_radius_all(0)
	return bar


## A placa da data, pendurada no topo ao centro: sem borda em cima, cantos de baixo arredondados.
static func plate_style() -> StyleBoxFlat:
	var plate := _surface(Color("#1b3038f5"), FRAME, 14, 8)
	plate.border_width_top = 0
	plate.corner_radius_top_left = 0
	plate.corner_radius_top_right = 0
	plate.corner_radius_bottom_left = 10
	plate.corner_radius_bottom_right = 10
	plate.shadow_color = Color(0, 0, 0, 0.45)
	plate.shadow_size = 6
	return plate


## O cabeçalho da ficha: a cor do cadastro bem escurecida, com a linha de destaque embaixo.
static func banner_style(base: Color) -> StyleBoxFlat:
	var banner := _surface(base.darkened(0.7), FRAME, 12, 10)
	banner.border_width_bottom = 2
	banner.set_corner_radius_all(0)
	return banner


## O botão ligado (modo ativo): fundo e borda de destaque.
static func active_style() -> StyleBoxFlat:
	return _surface(ACTIVE, BRASS, 8, 4)


## Uma aba (TabContainer): plana, estreita, com a linha de destaque embaixo na escolhida. Estreita para caber oito ícones nos 280 px do Índice.
static func tab_style(selected: bool, hovered := false) -> StyleBoxFlat:
	var tab := _surface(Color("#1b2e34") if hovered else Color.TRANSPARENT, BRASS if selected else Color.TRANSPARENT, 5, 4)
	tab.set_border_width_all(0)
	tab.border_width_bottom = 2
	tab.set_corner_radius_all(0)
	return tab


## A fonte dos títulos (Cinzel, variável) no peso pedido.
static func heading_font(weight := 600) -> Font:
	var font := FontVariation.new()
	font.base_font = FONT_HEADING
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): weight}
	return font


static func style_heading(label: Label) -> void:
	label.add_theme_font_override("font", heading_font())
	label.add_theme_color_override("font_color", BRASS)


static var _shared: Theme


## O tema do jogo, uma vez só. As janelas (AcceptDialog, FileDialog…) ficam sob nós comuns, que cortam a herança do tema: cada uma pede este.
static func shared_theme() -> Theme:
	if _shared == null:
		_shared = map_theme()
	return _shared


## Dá o tema do jogo a uma janela e a devolve.
static func themed(window: Window) -> Window:
	window.theme = shared_theme()
	return window


## O título de um nó do editor de regras, na cor do tipo dele (entrada, cálculo ou resultado).
static func node_title_style(color: Color, selected := false) -> StyleBoxFlat:
	var title := _surface(color, BRASS if selected else LINE, 8, 4)
	title.set_corner_radius_all(0)
	title.corner_radius_top_left = 4
	title.corner_radius_top_right = 4
	return title


static func map_theme() -> Theme:
	var theme := ThemeDB.get_default_theme().duplicate() as Theme
	theme.default_font = FONT_TEXT
	theme.default_font_size = 14
	var normal := _surface(Color("#25383e"), Color("#3a5057"), 8, 4)
	var hover := _surface(Color("#345059"), Color("#4a6a73"), 8, 4)
	var pressed := active_style()
	var disabled := _surface(Color("#18272c"), Color("#24363b"), 8, 4)
	var focus := _surface(Color.TRANSPARENT, FOCUS, 8, 4)
	focus.draw_center = false
	for kind in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", kind, normal)
		theme.set_stylebox("hover", kind, hover)
		theme.set_stylebox("pressed", kind, pressed)
		theme.set_stylebox("hover_pressed", kind, pressed)
		theme.set_stylebox("disabled", kind, disabled)
		theme.set_stylebox("focus", kind, focus)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			theme.set_color(state, kind, PAPER)
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
			theme.set_color(state, kind, PAPER)
		theme.set_color("font_disabled_color", kind, Color("#7f8a84"))
		theme.set_color("icon_disabled_color", kind, Color("#7f8a84"))
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "PopupMenu", PAPER)
	theme.set_stylebox("panel", "PopupMenu", panel_style())
	theme.set_stylebox("hover", "PopupMenu", hover)
	for kind in ["LineEdit", "TextEdit", "ItemList", "Tree"]:
		theme.set_stylebox("normal" if kind != "ItemList" and kind != "Tree" else "panel", kind,
			_surface(Color("#0e191d"), LINE, 8, 5))
		theme.set_color("font_color", kind, PAPER)
	theme.set_stylebox("selected", "ItemList", pressed)
	theme.set_stylebox("selected_focus", "ItemList", pressed)
	# Janelas (as avançadas: Regras, Tipos, calendários, diálogos): painel escuro, borda de destaque e título em Cinzel.
	var frame := _surface(PANEL, FRAME, 0, 0)
	frame.set_border_width_all(2)
	frame.border_width_top = 0
	frame.set_corner_radius_all(0)
	frame.expand_margin_top = 34
	for state in ["embedded_border", "embedded_unfocused_border"]:
		theme.set_stylebox(state, "Window", frame)
	theme.set_constant("title_height", "Window", 34)
	theme.set_color("title_color", "Window", BRASS)
	theme.set_font("title_font", "Window", heading_font())
	theme.set_font_size("title_font_size", "Window", 16)
	theme.set_icon("close", "Window", UiIcons.get_icon("close", 16))
	theme.set_icon("close_pressed", "Window", UiIcons.get_icon("close", 16))
	theme.set_constant("close_h_offset", "Window", 14)
	theme.set_constant("close_v_offset", "Window", 24)
	var body := _surface(PANEL, PANEL, 14, 12)
	body.set_border_width_all(0)
	body.set_corner_radius_all(0)
	theme.set_stylebox("panel", "AcceptDialog", body)
	theme.set_stylebox("panel", "PanelContainer", _surface(PANEL, LINE, 8, 6))
	theme.set_stylebox("panel", "Panel", _surface(PANEL, LINE, 0, 0))
	# Editor de nós: quadro quadriculado escuro; cada nó um cartão com o título colorido.
	var board := _surface(Color("#0e191d"), LINE, 0, 0)
	theme.set_stylebox("panel", "GraphEdit", board)
	theme.set_color("grid_major", "GraphEdit", Color(1, 1, 1, 0.06))
	theme.set_color("grid_minor", "GraphEdit", Color(1, 1, 1, 0.025))
	theme.set_color("selection_fill", "GraphEdit", Color(0.79, 0.54, 0.51, 0.12))
	theme.set_color("selection_stroke", "GraphEdit", BRASS)
	var card := _surface(PANEL, Color("#3a5057"), 8, 6)
	card.set_corner_radius_all(0)
	card.corner_radius_bottom_left = 4
	card.corner_radius_bottom_right = 4
	var card_selected := card.duplicate() as StyleBoxFlat
	card_selected.border_color = BRASS
	theme.set_stylebox("panel", "GraphNode", card)
	theme.set_stylebox("panel_selected", "GraphNode", card_selected)
	theme.set_stylebox("titlebar", "GraphNode", node_title_style(Color("#1b3a48")))
	theme.set_stylebox("titlebar_selected", "GraphNode", node_title_style(Color("#1b3a48"), true))
	theme.set_color("title_color", "GraphNode", PAPER)
	theme.set_font("title_font", "GraphNode", heading_font(600))
	theme.set_font_size("title_font_size", "GraphNode", 13)
	theme.set_stylebox("tab_selected", "TabContainer", tab_style(true))
	theme.set_stylebox("tab_unselected", "TabContainer", tab_style(false))
	theme.set_stylebox("tab_hovered", "TabContainer", tab_style(false, true))
	theme.set_stylebox("tab_focus", "TabContainer", tab_style(true))
	theme.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	theme.set_constant("h_separation", "TabContainer", 2)
	theme.set_stylebox("selected", "Tree", _surface(Color("#3a2224"), FRAME, 4, 2))
	theme.set_stylebox("selected_focus", "Tree", _surface(Color("#3a2224"), FRAME, 4, 2))
	return theme
