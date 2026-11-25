extends VBoxContainer
## A parte "Gerar sugestões" do painel de recursos: um modelo para começar, as condições (todas ajustáveis), a prévia e o aplicar.
## Os modelos são só pontos de partida: não criam recurso nem dizem o que existe no mundo.

signal preview_requested(rule: String)
signal apply_requested
signal discard_requested
signal clear_requested  # liberar as sugestões que o autor removeu
signal stability_requested(rule: String)
signal review_requested(rule: String)    # avaliação às cegas
signal review_answered(value: String)    # sim | nao | talvez
signal review_stopped
signal golden_requested(rule: String, final_test: bool)  # comparar a regra com o gabarito do autor

const ResourceProfiles = preload("res://scripts/ui/resource_profiles.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const ROCKS := [["sedimentar_clastica", "Sedimentar (arenito, argilito…)"], ["sedimentar_quimica", "Calcário, sílex e sais"],
	["halita", "Só sal-gema (halita)"], ["intrusiva", "Ígnea profunda (granito, gabro…)"], ["extrusiva", "Ígnea vulcânica (basalto…)"],
	["metamorfica", "Metamórfica (mármore, xisto…)"]]
const CLIMATES := [["A", "Tropical"], ["B", "Árido"], ["C", "Temperado"], ["D", "Continental"], ["E", "Polar"]]
const DEFAULTS := {"surface": "terra", "rocks": [], "climates": [], "elev_min": -13500.0, "elev_max": 9200.0, "slope_max": 90.0,
	"trees_min": 0.0, "soil_min": 0.0, "output": "area", "count": 8, "size_km": 250.0, "seed": 1, "prefer": [], "min_score": 1}
const TEMPLATES := [
	["Minério de montanha", {"rocks": ["intrusiva", "metamorfica"], "elev_min": 600.0, "output": "ponto", "count": 15, "size_km": 150.0}],
	["Jazida em rocha sedimentar", {"rocks": ["sedimentar_clastica"], "output": "ponto", "count": 12, "size_km": 200.0}],
	["Sal em região seca", {"rocks": ["sedimentar_quimica"], "climates": ["B"], "output": "ponto", "count": 10, "size_km": 200.0}],
	["Floresta", {"trees_min": 40.0, "output": "area", "count": 12, "size_km": 300.0}],
	["Solo de cultivo", {"climates": ["A", "C", "D"], "soil_min": 50.0, "slope_max": 2.0, "elev_min": 0.0, "elev_max": 2000.0,
		"output": "area", "count": 12, "size_km": 250.0}],
	["Pesca costeira", {"surface": "mar", "elev_min": -200.0, "elev_max": 0.0, "output": "area", "count": 12, "size_km": 250.0}],
]

var template: OptionButton
var advanced_toggle: Button
var tests_toggle: Button
var _into: Control        # onde _spin e _choice põem o que criam
var surface: OptionButton
var output: OptionButton
var summary: Label
var apply_button: Button
var discard_button: Button
var clear_button: Button
var spins := {}    # chave -> SpinBox
var rocks := {}    # classe -> botão de marcar
var climates := {} # grupo -> botão de marcar
var _land_only: Array = []  # controles que só valem em terra
var factors_box: VBoxContainer
var weights: Array = []   # um SpinBox de peso por indício
var _prefer: Array = []   # os indícios da regra na tela
var result: Label         # estabilidade e avaliação
var review_box: VBoxContainer
var review_question: Label
var review_facts: Label


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_into = self

	# O essencial: que lugar, quantos, de que tamanho, ver e aplicar.
	_note(self, "O programa procura lugares nos mapas. Nada muda antes de você aplicar.")
	_note(self, "Que tipo de lugar?")
	template = OptionButton.new()
	template.fit_to_longest_item = false
	template.accessibility_name = "Que tipo de lugar"
	template.add_item("Escolha um modelo…")
	for t in all_templates():
		template.add_item(t[0])
	template.item_selected.connect(func(i: int) -> void:
		if i > 0:
			var rule: Dictionary = all_templates()[i - 1][1].duplicate(true)
			rule["seed"] = int(spins.seed.value)
			load_rule(rule)
			template.select(i))
	add_child(template)
	_spin("count", "Quantos lugares", 1, 200, 1)
	_spin("size_km", "Tamanho (km)", 10, 2000, 10)
	spins.size_km.tooltip_text = "Áreas: raio aproximado de cada mancha. Pontos: distância mínima entre eles."
	var preview := _button(self, "Ver no mapa (prévia)", func() -> void: preview_requested.emit(JSON.stringify(rule())))
	preview.add_theme_stylebox_override("normal", UiKit.active_style())
	summary = _note(self, "")
	var row := HBoxContainer.new()
	add_child(row)
	apply_button = _button(row, "Aplicar", func() -> void: apply_requested.emit())
	discard_button = _button(row, "Descartar", func() -> void: discard_requested.emit())
	clear_button = _button(self, "", func() -> void: clear_requested.emit())

	# Recolhido: as condições da regra.
	advanced_toggle = _section("Ajustes avançados")
	surface = _choice("Onde", ["Em terra", "No mar"])
	surface.item_selected.connect(func(_i: int) -> void: _sync_surface())
	output = _choice("Gerar", ["Áreas pintadas", "Pontos"])
	factors_box = VBoxContainer.new()
	_into.add_child(factors_box)
	_spin("min_score", "Aptidão mínima", 1, 100, 1)
	_land_only.append(_note(_into, "Rochas (nenhuma marcada = qualquer uma)"))
	for pair in ROCKS:
		rocks[pair[0]] = _toggle(_into, pair[1], true)
	_land_only.append(_note(_into, "Climas (nenhum marcado = qualquer um)"))
	var flow := HFlowContainer.new()
	_into.add_child(flow)
	_land_only.append(flow)
	for pair in CLIMATES:
		climates[pair[0]] = _toggle(flow, pair[1], false)
	_spin("elev_min", "Altitude mínima (m)", -13500, 9200, 10)
	_spin("elev_max", "Altitude máxima (m)", -13500, 9200, 10)
	_spin("slope_max", "Declive máximo (graus)", 0.1, 90, 0.1)
	_land_only.append(_spin("trees_min", "Árvores, no mínimo (%)", 0, 100, 1))
	_land_only.append(_spin("soil_min", "Riqueza do solo, no mínimo", 0, 100, 1))
	_note(_into, "A riqueza do solo é uma leitura de baixa confiança.")
	var seed_row: HBoxContainer = _spin("seed", "Semente", 0, 999999, 1)
	seed_row.tooltip_text = "Outro número sorteia outros lugares entre os que servem"
	_button(seed_row, "Sortear", func() -> void: spins.seed.value = randi() % 1000000)

	# Recolhido: os testes da regra.
	_into = self
	tests_toggle = _section("Testar a regra (avançado)")
	var tests := HFlowContainer.new()
	_into.add_child(tests)
	_button(tests, "Testar estabilidade", func() -> void: stability_requested.emit(JSON.stringify(rule())))
	_button(tests, "Avaliar às cegas", func() -> void: review_requested.emit(JSON.stringify(rule())))
	_button(tests, "Comparar com gabarito", func() -> void: golden_requested.emit(JSON.stringify(rule()), false)).tooltip_text = \
		"Testa a regra da tela nos lugares que você já julgou (dois terços deles)"
	_button(tests, "Teste final", func() -> void: golden_requested.emit(JSON.stringify(rule()), true)).tooltip_text = \
		"Usa o terço reservado. Rode só quando terminar de ajustar a regra: depois de olhar, ele deixa de ser uma prova independente"
	review_box = VBoxContainer.new()
	review_box.hide()
	_into.add_child(review_box)
	review_question = _note(review_box, "")
	review_facts = _note(review_box, "")
	var answers := HFlowContainer.new()
	review_box.add_child(answers)
	for pair in [["Faz sentido", "sim"], ["Não faz", "nao"], ["Não sei", "talvez"]]:
		_button(answers, pair[0], func() -> void: review_answered.emit(pair[1]))
	_button(answers, "Encerrar", func() -> void: review_stopped.emit())
	result = _note(_into, "")
	result.hide()
	_into = self

	load_rule({})
	show_preview("")
	show_suppressions(0)


## Uma parte que abre e fecha; o que for criado a seguir (em _into) vai para dentro dela. Devolve o botão.
func _section(label: String) -> Button:
	_into = self
	add_child(HSeparator.new())
	var toggle := _button(self, "▸ " + label, Callable())
	toggle.toggle_mode = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.hide()
	add_child(body)
	toggle.toggled.connect(func(open: bool) -> void:
		body.visible = open
		toggle.text = ("▾ " if open else "▸ ") + label)
	_into = body
	return toggle


## Saindo da aba: a prévia fecha e uma avaliação em andamento é encerrada, guardando as respostas.
func leave() -> void:
	if review_box.visible:
		review_stopped.emit()
	discard_requested.emit()


## A regra como está na tela, no formato de ResourceRule (C#).
func rule() -> Dictionary:
	var sea := surface.selected == 1
	var out := {"version": 1, "surface": "mar" if sea else "terra", "output": "ponto" if output.selected == 1 else "area",
		"rocks": [] if sea else rocks.keys().filter(func(k): return rocks[k].button_pressed),
		"climates": [] if sea else climates.keys().filter(func(k): return climates[k].button_pressed),
		"elev_min": spins.elev_min.value, "elev_max": spins.elev_max.value, "slope_max": spins.slope_max.value,
		"trees_min": 0.0 if sea else spins.trees_min.value, "soil_min": 0.0 if sea else spins.soil_min.value,
		"count": int(spins.count.value), "size_km": spins.size_km.value, "seed": int(spins.seed.value)}
	var prefer: Array = [] if sea else _prefer.duplicate(true)
	for i in prefer.size():
		prefer[i]["weight"] = int(weights[i].value)
	out["prefer"] = prefer
	out["min_score"] = int(spins.min_score.value) if not prefer.is_empty() else 1
	return out


## Os modelos do menu: os perfis de recurso (com indícios) e os modelos simples.
static func all_templates() -> Array:
	var out: Array = ResourceProfiles.PROFILES.map(func(p): return ["Perfil: " + p.name, p.rule])
	out.append_array(TEMPLATES)
	return out


## Uma regra de perfil ou modelo com todos os campos.
func complete(partial: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate(true)
	out.merge(partial.duplicate(true), true)
	out["version"] = 1
	return out


## A pergunta e os fatos do lugar em avaliação; pergunta "" = sem avaliação em andamento.
func show_review(question: String, facts: String) -> void:
	review_box.visible = question != ""
	review_question.text = question
	if question != "":
		tests_toggle.button_pressed = true
	review_facts.text = facts
	if question != "":
		show_review_result("")


func show_review_result(text: String) -> void:
	result.text = text
	result.visible = text != ""
	if text != "":
		tests_toggle.button_pressed = true


func _show_factors() -> void:
	for child in factors_box.get_children():
		factors_box.remove_child(child)
		child.queue_free()
	weights.clear()
	spins.min_score.get_parent().visible = not _prefer.is_empty()
	if _prefer.is_empty():
		return
	_note(factors_box, "Indícios (o peso soma na aptidão, até 100)")
	for f in _prefer:
		var row := HBoxContainer.new()
		factors_box.add_child(row)
		var l := Label.new()
		l.text = String(f.name)
		l.tooltip_text = l.text
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var s := SpinBox.new()
		s.min_value = 1
		s.max_value = 100
		s.value = f.weight
		s.accessibility_name = "Peso: " + String(f.name)
		row.add_child(s)
		weights.append(s)


## Preenche o formulário; o que a regra não diz volta ao padrão.
func load_rule(saved: Dictionary) -> void:
	var r := DEFAULTS.duplicate()
	r.merge(saved, true)
	surface.select(1 if r.surface == "mar" else 0)
	output.select(1 if r.output == "ponto" else 0)
	for k in rocks:
		rocks[k].button_pressed = k in r.rocks
	for k in climates:
		climates[k].button_pressed = k in r.climates
	for k in spins:
		spins[k].value = r[k]
	_prefer = r.prefer.duplicate(true)
	if template.item_count > 0:
		template.select(0)
		template.set_item_text(0, "Escolha um modelo…" if saved.is_empty() else "Regra atual deste recurso")
	_show_factors()
	_sync_surface()


## "" = não há prévia na tela.
func show_preview(text: String, can_apply := false) -> void:
	summary.text = text
	summary.visible = text != ""
	apply_button.visible = can_apply
	discard_button.visible = can_apply


func show_suppressions(count: int) -> void:
	clear_button.visible = count > 0
	clear_button.text = "Liberar sugestões removidas (%d)" % count


func _sync_surface() -> void:
	for control in _land_only + rocks.values():
		control.visible = surface.selected == 0
	factors_box.visible = surface.selected == 0


func _note(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(270, 0)
	l.add_theme_font_size_override("font_size", 13)
	parent.add_child(l)
	return l


func _toggle(parent: Control, text: String, full_row: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.clip_text = full_row
	b.tooltip_text = text
	if full_row:
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Marcado: destaque e um sinal no texto (não depende só da cor).
	b.toggled.connect(func(on: bool) -> void: b.text = ("✓ " if on else "") + text)
	parent.add_child(b)
	return b


func _choice(label: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	_into.add_child(row)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var option := OptionButton.new()
	option.accessibility_name = label
	for item in items:
		option.add_item(item)
	row.add_child(option)
	return option


func _spin(key: String, label: String, low: float, high: float, step: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	_into.add_child(row)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.tooltip_text = label
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = low
	s.max_value = high
	s.step = step
	s.accessibility_name = label
	row.add_child(s)
	spins[key] = s
	return row


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	if on_press.is_valid():
		b.pressed.connect(on_press)
	parent.add_child(b)
	return b
