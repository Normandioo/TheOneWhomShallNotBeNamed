## Peças comuns da interface: o estilo dos painéis.


static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.88)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	return sb
