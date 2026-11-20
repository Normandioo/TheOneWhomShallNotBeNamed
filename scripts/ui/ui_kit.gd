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



static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.88)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	return sb
