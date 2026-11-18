## Peças comuns da interface: o estilo dos painéis e os nomes dos tipos de cadastro.

const KINDS := ["cultura", "pais", "raca", "etnia", "idioma", "religiao"]
const KIND_LABEL := {"cultura": "Cultura", "pais": "País", "raca": "Raça", "etnia": "Etnia", "idioma": "Idioma", "religiao": "Religião"}


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


static func kind_label(kind: String) -> String:
	return KIND_LABEL.get(kind, kind)



static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.88)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	return sb
