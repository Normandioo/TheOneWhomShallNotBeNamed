extends PanelContainer
## Controles do mapa de presenças: de quem (a ficha aberta ou todas as entidades) e quais camadas aparecem no globo. Cada camada tem a
## sua cor: fronteira política, presença cultural, distribuição étnica, área linguística e presença religiosa não se confundem.
## Só mostra e pede: avisa por sinal quando o usuário muda; o DomainHub decide o que desenhar.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal changed
signal tutorial_requested  # o botão "?" ao lado do título
signal political_visibility_changed(on: bool)
signal rivers_highlight_changed(on: bool)
signal legend_visibility_changed(on: bool)
signal area_overlay_changed(level: String)  # "" = nenhuma
signal country_names_changed(on: bool)

var _scope: OptionButton
var _checks := {}  # camada -> CheckBox
var _box: VBoxContainer
var rivers_check: CheckBox
var names_check: CheckBox
var legend_check: CheckBox
var _presence_box: VBoxContainer   # as presenças por lugar (o sistema antigo de marcadores), recolhidas por padrão
var _area_checks := {}  # nível -> CheckBox: a sobreposição de área na tela (uma por vez)


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var fold := Button.new()
	fold.text = "Sobreposições do mapa"
	fold.toggle_mode = true
	var head := HBoxContainer.new()
	box.add_child(head)
	fold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fold)
	var help := Button.new()
	help.text = "?"
	help.custom_minimum_size.x = 30
	help.tooltip_text = "Ver o que cada sobreposição faz"
	help.pressed.connect(func() -> void: tutorial_requested.emit())
	head.add_child(help)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(300, 400)
	scroll.hide()
	box.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_box)
	fold.toggled.connect(func(open: bool) -> void:
		scroll.visible = open
		reset_size())
	fold.button_pressed = true  # abre já com a lista: a coluna de modos só mostra ou esconde o painel todo

	_caption("NO MAPA")
	legend_check = _check("Legenda do mapa", "Mostra ou esconde a legenda no canto da tela.", legend_visibility_changed.emit)
	legend_check.button_pressed = true
	names_check = _check("Nomes dos países", "Escreve o nome de cada país no mapa político.", country_names_changed.emit)
	names_check.button_pressed = true  # ligado por padrão (o Main começa com os nomes ligados)
	rivers_check = _check("Rios em destaque", "Realça a rede de rios em azul por cima de qualquer mapa (de longe, só os grandes).", rivers_highlight_changed.emit)

	_caption("ÁREAS SOBRE O MAPA POLÍTICO")
	var hint := Label.new()
	hint.text = "Uma de cada vez; os países ficam em cinza."
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.6)
	_box.add_child(hint)
	for spec in [["cultura", "Culturas"], ["etnia", "Etnias"], ["raca", "Raças"], ["religiao", "Religiões"], ["idioma", "Idiomas"]]:
		var area_check := _check(spec[1], "Mostra o território pintado, com a cor e o nome, sobre os países em cinza.", func(on: bool) -> void:
			if on:
				for other in _area_checks:
					if other != spec[0]:
						_area_checks[other].set_pressed_no_signal(false)
			area_overlay_changed.emit(spec[0] if on else ""))
		_area_checks[spec[0]] = area_check

	_caption("PRESENÇAS POR LUGAR")
	var presence_toggle := Button.new()
	presence_toggle.text = "▸ Marcadores por lugar"
	presence_toggle.flat = true
	presence_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	presence_toggle.tooltip_text = "Os marcadores por lugar (círculos e áreas ligados a um lugar): o que os mapas de área não mostram."
	_box.add_child(presence_toggle)
	_presence_box = VBoxContainer.new()
	_presence_box.visible = false
	_box.add_child(_presence_box)
	_scope = OptionButton.new()
	_scope.add_item("Só a ficha aberta")
	_scope.add_item("Todas as entidades")
	_scope.item_selected.connect(func(_i: int) -> void: changed.emit())
	_presence_box.add_child(_scope)
	presence_toggle.toggled.connect(func(open: bool) -> void:
		_presence_box.visible = open
		presence_toggle.text = ("▾ " if open else "▸ ") + "Marcadores por lugar"
		reset_size())
	presence_toggle.toggle_mode = true
	refresh_layers()


func _caption(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("#8e907f"))
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	_box.add_child(gap)
	_box.add_child(label)


func _check(text: String, tip: String, on_toggled: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.toggled.connect(on_toggled)
	_box.add_child(c)
	return c


## Acrescenta as camadas que ainda não têm caixa (UiKit.layer_list, vindas do banco): uma camada nova já aparece marcada.
func refresh_layers() -> void:
	for layer in UiKit.layer_list:
		if _checks.has(layer):
			continue
		var c := CheckBox.new()
		c.text = UiKit.layer_label[layer]
		c.button_pressed = true
		c.add_theme_color_override("font_color", UiKit.layer_color[layer])
		c.toggled.connect(func(_on: bool) -> void: changed.emit())
		if layer == "politica":
			c.toggled.connect(political_visibility_changed.emit)
		_presence_box.add_child(c)
		_checks[layer] = c


## As camadas marcadas.
func layers() -> PackedStringArray:
	var out := PackedStringArray()
	for layer in UiKit.layer_list:
		if _checks.has(layer) and _checks[layer].button_pressed:
			out.append(layer)
	return out


## O nível mostrado mudou por outro caminho (a coluna de modos): marca só a caixa dele.
func set_area_level(level: String) -> void:
	for k in _area_checks:
		_area_checks[k].set_pressed_no_signal(k == level)


func set_political_visible(on: bool) -> void:
	_checks["politica"].button_pressed = on


## true = todas as entidades; false = só a da ficha aberta.
func all_entities() -> bool:
	return _scope.selected == 1
