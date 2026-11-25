extends PanelContainer
## O cartão "Por que aqui?": explica em palavras simples por que o programa escolheu um lugar. Não diz que a escolha está certa.
## Só mostra e pede: na prévia, o botão tira ou devolve a sugestão.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const ResourceProfiles = preload("res://scripts/ui/resource_profiles.gd")

signal toggle_requested  # tirar da prévia, ou devolver
signal closed

const WIDTH := 460
const NOTE := "Isto explica por que o programa escolheu o lugar. Não prova que o recurso existe ali: a decisão é sua."

var title: Label
var body: Label
var toggle_button: Button


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	title = Label.new()
	UiKit.style_heading(title)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(WIDTH, 400)
	box.add_child(scroll)
	body = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(WIDTH - 20, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var row := HBoxContainer.new()
	box.add_child(row)
	toggle_button = Button.new()
	toggle_button.pressed.connect(func() -> void: toggle_requested.emit())
	row.add_child(toggle_button)
	var close := Button.new()
	close.text = "Fechar"
	close.pressed.connect(func() -> void:
		hide()
		closed.emit())
	row.add_child(close)


## why: o que ResourcePlan.Explain ou Registry.ExplainOccurrence devolvem. facts: o que os mapas dizem do lugar.
## toggle_text "" = não há o que tirar (uma sugestão já aplicada).
func show_why(heading: String, why: Dictionary, facts: String, toggle_text := "") -> void:
	title.text = heading
	body.text = text_of(why, facts)
	toggle_button.visible = toggle_text != ""
	toggle_button.text = toggle_text
	visible = true


static func text_of(why: Dictionary, facts: String) -> String:
	var lines: Array[String] = []
	if why.scored:
		lines.append("Somou %d pontos (precisa de %d). Não é chance de haver o recurso." % [why.score, why.min_score])
		if why.score < why.min_score:
			lines.append("Hoje este lugar NÃO entraria: a regra ou o relevo mudou.")
		var found := PackedStringArray(why.factors.filter(func(f): return f.ok).map(func(f): return String(f.name)))
		if not found.is_empty():  # a conclusão antes dos detalhes, sem precisar rolar
			lines.append("%s: %s." % ["Entrou por" if why.score >= why.min_score else "Só tem", "; ".join(found)])
		lines.append("")
		for f in why.factors:
			var mark := "✓" if f.ok else "✗"
			var points := "+%d" % f.weight if f.ok else "+0 (valeria %d)" % f.weight
			var plain: String = ResourceProfiles.PLAIN.get(f.name, "")
			lines.append("%s %s: %s%s" % [mark, f.name, points, "\n     " + plain if plain != "" else ""])
	if not why.conditions.is_empty():
		lines.append("")
		lines.append("A regra também exige: " + "; ".join(PackedStringArray(why.conditions)) + ".")
		if not why.scored:
			lines.append("Este lugar foi sorteado entre os que atendem a essas condições.")
	if facts != "":
		lines.append("")
		lines.append("O que os mapas dizem deste ponto:")
		lines.append(facts)
	lines.append("")
	lines.append(NOTE)
	return "\n".join(lines).strip_edges()
