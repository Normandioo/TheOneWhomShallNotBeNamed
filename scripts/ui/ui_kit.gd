## Peças comuns da interface: o estilo dos painéis, barras e formatação de números.


static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.06, 0.85)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	return sb


## Título e barra de progresso 0..1 (só leitura) no fim de `box`.
static func add_bar(box: Container, title: String) -> ProgressBar:
	var label := Label.new()
	label.text = title
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.001
	box.add_child(bar)
	return bar


## Pressão em mbar: uma casa decimal abaixo de 10, inteiro acima.
static func format_mbar(p: float) -> String:
	return "%.1f" % p if p < 10.0 else str(roundi(p))
