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



const BRASS := Color("#ba9c60")
const PAPER := Color("#f2e9d4")
const FRAME := Color("#706347")


static func _surface(fill: Color, border: Color, horizontal: int, vertical: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = horizontal
	sb.content_margin_right = horizontal
	sb.content_margin_top = vertical
	sb.content_margin_bottom = vertical
	return sb


static func panel_style() -> StyleBoxFlat:
	var panel := _surface(Color("#142328f5"), FRAME, 12, 10)
	panel.border_width_top = 2
	panel.shadow_color = Color(0, 0, 0, 0.38)
	panel.shadow_size = 5
	panel.shadow_offset = Vector2(0, 2)
	return panel


static func style_heading(label: Label) -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Georgia", "Liberation Serif", "DejaVu Serif"])
	label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", BRASS)


static func map_theme() -> Theme:
	var theme := ThemeDB.get_default_theme().duplicate() as Theme
	theme.default_font_size = 14
	var normal := _surface(Color("#25383e"), FRAME, 7, 4)
	var hover := _surface(Color("#345059"), BRASS, 7, 4)
	var pressed := _surface(Color("#55462e"), BRASS, 7, 4)
	var disabled := _surface(Color("#18272c"), Color("#3f4843"), 7, 4)
	var focus := _surface(Color.TRANSPARENT, Color("#f0cf82"), 7, 4)
	focus.draw_center = false
	for kind in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", kind, normal)
		theme.set_stylebox("hover", kind, hover)
		theme.set_stylebox("pressed", kind, pressed)
		theme.set_stylebox("hover_pressed", kind, pressed)
		theme.set_stylebox("disabled", kind, disabled)
		theme.set_stylebox("focus", kind, focus)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(state, kind, PAPER)
		theme.set_color("font_disabled_color", kind, Color("#a0a59a"))
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "PopupMenu", PAPER)
	theme.set_stylebox("panel", "PopupMenu", panel_style())
	theme.set_stylebox("hover", "PopupMenu", hover)
	for kind in ["LineEdit", "TextEdit", "ItemList"]:
		theme.set_stylebox("normal" if kind != "ItemList" else "panel", kind,
			_surface(Color("#101c20"), FRAME, 8, 5))
		theme.set_color("font_color", kind, PAPER)
	theme.set_stylebox("selected", "ItemList", pressed)
	theme.set_stylebox("selected_focus", "ItemList", pressed)
	return theme
