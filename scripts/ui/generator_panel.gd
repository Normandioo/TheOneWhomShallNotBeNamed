extends VBoxContainer
## A aba "Gerar" do painel de recursos, em três passos (onde procurar, como preencher, quanto há), e a prévia com o que entra e o que sai.
## Os critérios do modelo ficam recolhidos e aparecem resumidos em etiquetas. Os botões Descartar e Aplicar vão em `footer`, que o
## painel prende embaixo, fora da rolagem. Os modelos são só pontos de partida: não criam recurso nem dizem o que existe no mundo.

signal preview_requested(rule: String)
signal apply_requested
signal discard_requested
signal clear_requested  # liberar as sugestões que o autor removeu
signal stability_requested(rule: String)
signal review_requested(rule: String)    # avaliação às cegas
signal review_answered(value: String)    # sim | nao | talvez
signal review_stopped
signal golden_requested(rule: String, final_test: bool)  # comparar a regra com o gabarito do autor
signal mode_changed      # entrou ou saiu da prévia

const ResourceProfiles = preload("res://scripts/ui/resource_profiles.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")  # só para o separador de milhares
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const ROCKS := [["sedimentar_clastica", "Sedimentar (arenito, argilito…)"], ["sedimentar_quimica", "Calcário, sílex e sais"],
	["halita", "Só sal-gema (halita)"], ["intrusiva", "Ígnea profunda (granito, gabro…)"], ["extrusiva", "Ígnea vulcânica (basalto…)"],
	["metamorfica", "Metamórfica (mármore, xisto…)"]]
const CLIMATES := [["A", "Tropical"], ["B", "Árido"], ["C", "Temperado"], ["D", "Continental"], ["E", "Polar"]]
const DEFAULTS := {"surface": "terra", "rocks": [], "climates": [], "elev_min": -13500.0, "elev_max": 9200.0, "slope_max": 90.0,
	"trees_min": 0.0, "soil_min": 0.0, "output": "area", "count": 8, "size_km": 250.0, "seed": 1, "prefer": [], "min_score": 1, "auto": true, "density": 1000.0,
	"spread": ""}
const COVER_CATEGORIES := ["vegetal", "animal"]  # o mesmo que Registry.CoversArea decide quando a regra não diz
## Modelos sem recurso específico (os recursos com fontes estão em resource_profiles.gd). Saíram "Minério de montanha", "Jazida em rocha
## sedimentar" e "Sal em região seca": genéricos demais (o segundo cobria quase metade da terra; o terceiro contava sílex como sal).
const TEMPLATES := [
	["Floresta", {"trees_min": 40.0, "output": "area", "spread": "cobertura"}],
	["Solo de cultivo", {"climates": ["A", "C", "D"], "soil_min": 40.0, "slope_max": 2.0, "elev_min": 0.0, "elev_max": 2000.0,
		"output": "area", "count": 12, "size_km": 250.0, "min_score": 40, "prefer": [
			{"name": "Planície perto de rio grande", "water": ["rio", "lago"], "water_km": 30.0, "slope_max": 1.0, "weight": 60},
			{"name": "Clima temperado", "climates": ["C"], "weight": 40}]}],
	["Pesca costeira", {"surface": "mar", "elev_min": -200.0, "elev_max": 0.0, "output": "area", "count": 12, "size_km": 250.0}],
]

var template: OptionButton
var amount_mode: OptionButton   # "Quantos couberem" (automático) ou "Eu escolho…"
var cover_card: Button
var some_card: Button
var some_box: VBoxContainer     # o que só vale em "Alguns lugares"
var form: VBoxContainer         # os três passos; some na prévia
var preview_box: VBoxContainer
var footer: HBoxContainer       # Descartar e Aplicar, presos embaixo pelo painel
var previewing := false
var unit := ""                  # a unidade do recurso aberto
var _spread := ""               # "" = pela categoria | manchas | cobertura
var _count_row: Control
var _chips: HFlowContainer
var _example: Label
var _unit_label: Label
var _preview_line: Label
var _preview_stats: HBoxContainer
var _preview_warning: Label
var _preview_changes: VBoxContainer
var _preview_hint: Label
var _tests_box: VBoxContainer
var advanced_toggle: Button
var tests_toggle: Button
var _into: Control        # onde _spin e _choice põem o que criam
var surface: OptionButton
var output: OptionButton
var category := ""  # a do recurso aberto: decide o jeito de se espalhar quando a regra não diz
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
	form = _box(self, 10)

	_title(form, "1 · Onde procurar")
	template = OptionButton.new()
	template.fit_to_longest_item = false
	template.accessibility_name = "Modelo de lugar"
	template.add_item("Escolha um modelo…")
	for t in all_templates():
		template.add_item(t[0])
	template.item_selected.connect(func(i: int) -> void:
		if i > 0:
			var rule: Dictionary = all_templates()[i - 1][1].duplicate(true)
			rule["seed"] = int(spins.seed.value)
			if not rule.has("auto"):  # os modelos também começam no automático
				rule.merge({"auto": true, "density": DEFAULTS.density})
			load_rule(rule)
			template.select(i))
	form.add_child(template)
	_chips = HFlowContainer.new()
	form.add_child(_chips)

	# Recolhido: as condições da regra, logo abaixo das etiquetas que as resumem.
	advanced_toggle = _fold(form, "Mudar critérios")
	surface = _choice("Onde", ["Em terra", "No mar"])
	surface.item_selected.connect(func(_i: int) -> void: _sync_surface())
	output = _choice("Gerar", ["Áreas pintadas", "Pontos"])
	output.item_selected.connect(func(_i: int) -> void: _sync_auto())
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

	_title(form, "2 · Como preencher")
	var cards := HBoxContainer.new()
	form.add_child(cards)
	var group := ButtonGroup.new()
	cover_card = _card(cards, group, "cobertura")
	cover_card.tooltip_text = "Pinta tudo o que serve, seguindo o contorno do mapa: um lugar por trecho contínuo. Trechos com menos de 5.000 km² ficam de fora (no máximo 200, os maiores)."
	some_card = _card(cards, group, "manchas")
	some_card.tooltip_text = "Manchas separadas (ou pontos) entre os lugares que servem"
	some_box = _box(form, 6)
	_into = some_box
	amount_mode = _choice("Quantos", ["Quantos couberem", "Eu escolho…"])
	amount_mode.tooltip_text = "Quantos couberem: o programa põe todos os que cabem, até 200"
	amount_mode.item_selected.connect(func(_i: int) -> void: _sync_auto())
	_count_row = _spin("count", "Quantos lugares", 1, 200, 1)
	_spin("size_km", "Tamanho de cada um (km)", 10, 2000, 10)
	spins.size_km.tooltip_text = "Áreas: raio de cada mancha (em Quantos couberem, o máximo). Pontos: distância mínima entre eles."

	_title(form, "3 · Quanto há (opcional)")
	var amount := HBoxContainer.new()
	form.add_child(amount)
	var density := SpinBox.new()
	density.min_value = 0
	density.max_value = 1000000000
	density.step = 1
	density.accessibility_name = "Quantidade em cada km²"
	density.tooltip_text = "Multiplicada pela nota do lugar. 0 = sem quantidade. É uma escolha sua: não foi calibrada."
	amount.add_child(density)
	spins["density"] = density
	_unit_label = Label.new()
	_unit_label.clip_text = true
	_unit_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_unit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount.add_child(_unit_label)
	_example = _note(form, "")
	_example.modulate = Color(1, 1, 1, 0.7)

	summary = _note(form, "")
	var preview := _button(form, "Mostrar no mapa", func() -> void: preview_requested.emit(JSON.stringify(rule())))
	preview.add_theme_stylebox_override("normal", UiKit.active_style())
	preview.custom_minimum_size.y = 40
	var safe := _note(form, "Nada muda antes de você aplicar.")
	safe.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	safe.modulate = Color(1, 1, 1, 0.7)
	clear_button = _button(form, "", func() -> void: clear_requested.emit())

	_build_preview()

	# Os testes da regra: aparecem com os critérios abertos; o resultado aparece também junto da prévia.
	_tests_box = _box(self, 4)
	tests_toggle = _fold(_tests_box, "Testar a regra (avançado)")
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
	advanced_toggle.toggled.connect(func(_open: bool) -> void: _sync_tests())

	# As etiquetas e o exemplo acompanham qualquer mudança.
	for spin in spins.values():
		spin.value_changed.connect(func(_v: float) -> void: _refresh_texts())
	for button in rocks.values() + climates.values():
		button.toggled.connect(func(_on: bool) -> void: _refresh_texts())

	load_rule({})
	show_preview("")
	show_suppressions(0)


func _build_preview() -> void:
	preview_box = _box(self, 10)
	var line := HBoxContainer.new()
	preview_box.add_child(line)
	_preview_line = Label.new()
	_preview_line.clip_text = true
	_preview_line.mouse_filter = Control.MOUSE_FILTER_PASS
	_preview_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_line.add_theme_font_size_override("font_size", 13)
	line.add_child(_preview_line)
	_button(line, "mudar", func() -> void: discard_requested.emit()).flat = true
	_title(preview_box, "Prévia no mapa")
	_preview_stats = HBoxContainer.new()
	preview_box.add_child(_preview_stats)
	_preview_warning = _note(preview_box, "")
	_preview_warning.add_theme_color_override("font_color", Color("#f2c46d"))
	var changes := PanelContainer.new()
	changes.add_theme_stylebox_override("panel", UiKit.card_style())
	preview_box.add_child(changes)
	_preview_changes = _box(changes, 4)
	_preview_hint = _note(preview_box, "")
	_preview_hint.modulate = Color(1, 1, 1, 0.7)

	footer = HBoxContainer.new()
	discard_button = _button(footer, "Descartar", func() -> void: discard_requested.emit())
	apply_button = _button(footer, "Aplicar", func() -> void: apply_requested.emit())
	apply_button.add_theme_stylebox_override("normal", UiKit.active_style())
	for pair in [[discard_button, 1.0], [apply_button, 2.0]]:
		pair[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pair[0].size_flags_stretch_ratio = pair[1]
		pair[0].custom_minimum_size.y = 40


## Uma parte que abre e fecha dentro de parent; o que for criado a seguir (em _into) vai para dentro dela. Devolve o botão.
func _fold(parent: Control, label: String) -> Button:
	var toggle := _button(parent, "▸ " + label, Callable())
	toggle.toggle_mode = true
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var body := _box(parent, 4)
	body.hide()
	toggle.toggled.connect(func(open: bool) -> void:
		body.visible = open
		toggle.text = ("▾ " if open else "▸ ") + label)
	_into = body
	return toggle


func _box(parent: Control, gap: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", gap)
	parent.add_child(b)
	return b


func _title(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	UiKit.style_heading(l)
	l.add_theme_font_size_override("font_size", 15)
	parent.add_child(l)


## Uma das duas opções de "Como preencher". Escolhida: fundo, borda e a bolinha cheia (não depende só da cor).
func _card(parent: Control, group: ButtonGroup, value: String) -> Button:
	var b := _button(parent, "", Callable())
	b.toggle_mode = true
	b.button_group = group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 56
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_stylebox_override("pressed", UiKit.active_style())
	b.pressed.connect(func() -> void:
		_spread = value
		_sync_auto())
	return b


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
		"count": int(spins.count.value), "size_km": spins.size_km.value, "seed": int(spins.seed.value),
		"auto": amount_mode.selected == 0, "density": spins.density.value, "spread": _spread}
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
	_sync_tests()


func show_review_result(text: String) -> void:
	result.text = text
	result.visible = text != ""
	if text != "":
		tests_toggle.button_pressed = true
	_sync_tests()


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
	if not saved.is_empty() and not saved.has("auto"):
		r.auto = false
		r.density = 0.0
	r.merge(saved, true)
	surface.select(1 if r.surface == "mar" else 0)
	output.select(1 if r.output == "ponto" else 0)
	_spread = String(r.spread)
	for k in rocks:
		rocks[k].button_pressed = k in r.rocks
	for k in climates:
		climates[k].button_pressed = k in r.climates
	for k in spins:
		spins[k].value = r[k]
	amount_mode.select(0 if bool(r.auto) else 1)
	_prefer = r.prefer.duplicate(true)
	if template.item_count > 0:
		template.select(0)
		template.set_item_text(0, "Escolha um modelo…" if saved.is_empty() else "Critérios deste recurso")
	_show_factors()
	_sync_surface()
	_sync_auto()


## Um aviso na tela dos passos ("" = nenhum); fora da prévia.
func show_preview(text: String) -> void:
	summary.text = text
	summary.visible = text != ""
	_set_previewing(false)


## A prévia. info: {count, total, area, km2, reserve, replaced, protected, suppressed, scored}
func show_plan(info: Dictionary) -> void:
	var chosen := template.get_item_text(template.selected) if template.selected > 0 else "Critérios deste recurso"
	var parts: Array[String] = [chosen, "tudo que serve" if covers() else "alguns lugares"]
	if spins.density.value > 0.0:
		parts.append("%s por km²" % short_number(spins.density.value))
	_preview_line.text = " · ".join(parts)
	_preview_line.tooltip_text = _preview_line.text
	clear_box(_preview_stats)
	stat_card(_preview_stats, short_number(info.count), "lugar" if int(info.count) == 1 else "lugares")
	if info.area:
		stat_card(_preview_stats, short_number(info.km2), "km²")
	if float(info.reserve) > 0.0:
		stat_card(_preview_stats, short_number(info.reserve), plural_unit() if unit != "" else "quantidade")
	var warning := ""
	if int(info.total) == 0:
		warning = "Nenhum lugar atende aos critérios."
	elif int(info.count) < int(info.total):
		warning = "Você tirou %d da prévia." % (int(info.total) - int(info.count))
	elif int(info.total) >= 200:
		warning = "200 é o máximo. Ficaram os maiores." if covers() else "200 é o máximo de uma geração."
	_preview_warning.text = warning
	_preview_warning.visible = warning != ""
	fill_changes(_preview_changes, info)
	_preview_hint.text = "Clique num lugar do mapa para saber por que ele está ali (e tirá-lo, se quiser).%s" % (
		" O número é a nota, de 0 a 100." if info.scored else "")
	_preview_hint.visible = int(info.total) > 0
	apply_button.text = "Aplicar %d %s" % [info.count, "lugar" if int(info.count) == 1 else "lugares"]
	summary.text = "%d de %d na prévia" % [info.count, info.total]  # fica escondido: é o que os testes mostram quando falham
	summary.hide()
	_set_previewing(true)


func _set_previewing(on: bool) -> void:
	previewing = on
	form.visible = not on
	preview_box.visible = on
	apply_button.visible = on
	discard_button.visible = on
	_sync_tests()
	mode_changed.emit()


func _sync_tests() -> void:
	_tests_box.visible = (advanced_toggle.button_pressed and not previewing) or result.visible or review_box.visible


## "Se você aplicar": o que entra, o que sai e o que fica. info: {count, replaced, protected, suppressed}
func fill_changes(box: Control, info: Dictionary) -> void:
	clear_box(box)
	_note(box, "Se você aplicar")
	_note(box, "＋ entram %d" % info.count)
	if int(info.replaced) > 0:
		_note(box, "－ saem %d gerados antes" % info.replaced)
	var kept := _note(box, "O que você fez à mão ou protegeu não muda%s." % (" (%d)" % info.protected if int(info.protected) > 0 else ""))
	kept.add_theme_color_override("font_color", Color("#a9d6a0"))
	if int(info.suppressed) > 0:
		_note(box, "%d que você já tinha removido ficam de fora." % info.suppressed)


## Um número grande da prévia, com o que ele conta embaixo.
func stat_card(parent: Control, value: String, label: String) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.card_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var box := _box(card, 0)
	for pair in [[value, 19], [label, 12]]:
		var l := Label.new()
		l.text = pair[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.tooltip_text = pair[0]
		l.add_theme_font_size_override("font_size", pair[1])
		box.add_child(l)


static func clear_box(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


## 28009711 -> "28 mi"; 15098515221 -> "15,1 bi".
static func short_number(v: float) -> String:
	for step in [[1e9, 1e9, "bi"], [1e6, 1e6, "mi"], [1e4, 1e3, "mil"]]:
		if v >= step[0]:
			var x: float = v / step[1]
			var text := str(roundi(x)) if x >= 100.0 else ("%.1f" % x).trim_suffix(".0").replace(".", ",")
			return "%s %s" % [text, step[2]]
	return LayerPanel._thousands(roundi(v))


func plural_unit() -> String:
	return unit + "s" if unit in ["unidade", "cabeça"] else unit


func set_unit(value: String) -> void:
	unit = value
	_refresh_texts()


## As etiquetas do que os critérios procuram, e o exemplo da quantidade.
func _refresh_texts() -> void:
	if _example == null or result == null:
		return
	clear_box(_chips)
	for text in describe_rule(rule()):
		var chip := Label.new()
		chip.text = text
		if text.contains("indício"):
			chip.mouse_filter = Control.MOUSE_FILTER_PASS
			chip.tooltip_text = "\n".join(_prefer.map(func(f): return "%s (+%d)" % [f.name, f.weight]))
		chip.add_theme_font_size_override("font_size", 13)
		chip.add_theme_color_override("font_color", Color("#b8cdf2"))
		var style := StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT
		style.border_color = Color("#5d7fb0")
		style.set_border_width_all(1)
		style.set_corner_radius_all(9)
		style.content_margin_left = 8
		style.content_margin_right = 8
		chip.add_theme_stylebox_override("normal", style)
		_chips.add_child(chip)
	var per: float = spins.density.value
	_unit_label.text = "%s em cada km²" % plural_unit() if unit != "" else "em cada km²"
	_unit_label.tooltip_text = _unit_label.text
	if per <= 0.0:
		_example.text = "Sem quantidade: os povoados não extraem destes lugares."
	elif output.selected == 1:
		_example.text = "Um ponto com nota 100 teria %s." % short_number(per * 100.0)  # um ponto vale 100 km² (ResourceGenerator.PointKm2)
	else:
		_example.text = "Um lugar de 10.000 km² com nota 100 teria %s." % short_number(per * 10000.0)


## O que a regra procura, em poucas palavras.
static func describe_rule(r: Dictionary) -> Array[String]:
	var sea: bool = r.surface == "mar"
	var out: Array[String] = []
	if sea:
		out.append("no mar")
	if float(r.trees_min) > 0.0:
		out.append("%d%% de árvores ou mais" % roundi(r.trees_min))
	if float(r.soil_min) > 0.0:
		out.append("solo fértil")
	var slope: float = r.slope_max
	if slope < 90.0:
		out.append("quase plano" if slope <= 2.0 else "declive até %s°" % ("%.1f" % slope).trim_suffix(".0").replace(".", ","))
	var low := roundi(r.elev_min)
	var high := roundi(r.elev_max)
	if sea:
		if low > -13500:
			out.append("até %s m de fundo" % LayerPanel._thousands(-low))
	else:
		var floor_set := low > -13500 and low != 0
		if high < 9200 and floor_set:
			out.append("de %s a %s m" % [LayerPanel._thousands(low), LayerPanel._thousands(high)])
		elif high < 9200:
			out.append("até %s m" % LayerPanel._thousands(high))
		elif floor_set:
			out.append("acima de %s m" % LayerPanel._thousands(low))
	var climate_names: Array = CLIMATES.filter(func(c): return c[0] in r.climates).map(func(c): return String(c[1]).to_lower())
	if not climate_names.is_empty():
		var tail: String = climate_names.pop_back()
		out.append("clima " + (tail if climate_names.is_empty() else ", ".join(climate_names) + " ou " + tail))
	if r.rocks.size() == 1:
		out.append(String(ROCKS.filter(func(x): return x[0] == r.rocks[0])[0][1]).get_slice(" (", 0).to_lower())
	elif r.rocks.size() > 1:
		out.append("%d tipos de rocha" % r.rocks.size())
	if not r.prefer.is_empty():
		out.append("%d %s" % [r.prefer.size(), "indício dá nota" if r.prefer.size() == 1 else "indícios dão nota"])
	if out.is_empty() or (sea and out.size() == 1):
		out.append("qualquer lugar do mar" if sea else "qualquer lugar em terra")
	return out


## O recurso aberto mudou, ou a categoria dele.
func set_category(value: String) -> void:
	category = value
	_sync_auto()


## A tela vai gerar cobertura? Só em áreas.
func covers() -> bool:
	return output.selected == 0 and (_spread == "cobertura" or (_spread == "" and category in COVER_CATEGORIES))


## Na cobertura não há quantos, tamanho nem sorteio.
func _sync_auto() -> void:
	var cover := covers()
	cover_card.disabled = output.selected == 1  # pontos não cobrem
	for pair in [[cover_card, cover, "Tudo que serve\n     segue o mapa"], [some_card, not cover, "Alguns lugares\n     separados"]]:
		pair[0].set_pressed_no_signal(pair[1])
		pair[0].text = ("●  " if pair[1] else "○  ") + pair[2]
	some_box.visible = not cover
	_count_row.visible = amount_mode.selected == 1
	spins.seed.get_parent().visible = not cover
	_refresh_texts()


func show_suppressions(count: int) -> void:
	clear_button.visible = count > 0
	clear_button.text = "Liberar sugestões removidas (%d)" % count


func _sync_surface() -> void:
	for control in _land_only + rocks.values():
		control.visible = surface.selected == 0
	factors_box.visible = surface.selected == 0
	_refresh_texts()


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
