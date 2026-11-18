## Peças comuns da interface: o estilo dos painéis e os nomes dos tipos de cadastro.

const KINDS := ["cultura", "pais", "raca", "etnia", "idioma", "religiao"]
const KIND_LABEL := {"cultura": "Cultura", "pais": "País", "raca": "Raça", "etnia": "Etnia", "idioma": "Idioma", "religiao": "Religião"}


static func kind_label(kind: String) -> String:
	return KIND_LABEL.get(kind, kind)



static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.88)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	return sb
