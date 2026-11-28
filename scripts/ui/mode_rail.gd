extends PanelContainer
## O painel dos modos de mapa, embaixo à direita: o nome do modo atual e o botão das sobreposições; MUNDO (política, subdivisões, religião,
## cultura, etnia, raça, idioma e biomas, que são camadas pintadas sobre o mapa político) e PLANETA (um botão por grupo de camadas:
## satélite, relevo, clima, ecologia…). Os de grupo abrem as variantes; o modo atual fica marcado.
## Só mostra e pede: avisa por sinal (o Main escolhe a camada e o nível).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")

signal layer_selected(index: int)
signal level_selected(level: String)  # "pais", "religiao"...: o mapa político nesse nível
signal overlays_toggled(open: bool)
signal tutorial_requested  # o botão "?" do cabeçalho

const WIDTH := 540
const ICON := 20
# Nível territorial (mundo): [nível, ícone, dica, sigla embaixo do ícone]
const WORLD := [["pais", "politics", "Política: países", "Pol"], ["subdivisoes", "organization", "Política: subdivisões do país aberto (cada uma na sua cor, os outros países em cinza)", "Sub"], ["religiao", "religion", "Religião", "Rel"], ["cultura", "culture", "Cultura", "Cul"],
	["etnia", "ethnicity", "Etnia", "Etn"], ["raca", "race", "Raça", "Raç"], ["idioma", "language", "Idioma", "Idi"],
	["bioma", "ecology", "Biomas (a camada editável: todos os biomas; pinte pela barra do Relevo)", "Bio"],
	["recursos", "resources", "Recursos: todos juntos, cada um na sua cor (a legenda liga e desliga; o clique abre o recurso)", "Rec"]]
const LEVEL_NAME := {"pais": "político", "subdivisoes": "subdivisões", "religiao": "religiões", "cultura": "culturas", "etnia": "etnias", "raca": "raças", "idioma": "idiomas", "bioma": "biomas", "recursos": "recursos"}
# Grupo de camadas (planeta): [grupo em MapLayers, ícone]
const PLANET := [["Relevo", "relief"], ["Clima", "climate"], ["Ecologia", "ecology"], ["Solos", "soils"], ["Hidrologia", "hydrology"],
	["Geologia", "geology"], ["Organização", "organization"]]
const SATELLITE_GROUP := "Visão geral"

var _level_buttons := {}  # nível -> Button
var _group_buttons := {}  # grupo -> MenuButton
var _items := {}          # grupo -> {id do item no popup: índice em MapLayers.LAYERS}
var _overlays: Button
var _layer := 0
var _level := "pais"
var _subs := false
var _title: Label


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", UiKit.metal_style(Color("#1b262a"), 8, 6))
	resized.connect(func() -> void: size = get_combined_minimum_size())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = Label.new()
	UiKit.style_heading(_title)
	_title.add_theme_font_size_override("font_size", 14)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	_overlays = Button.new()
	_overlays.text = "Sobreposições"
	_overlays.icon = UiIcons.get_icon("overlays", 14)
	UiKit.tint_icon(_overlays, "overlays")
	_overlays.add_theme_font_size_override("font_size", 12)
	_overlays.tooltip_text = "Sobreposições: nomes, rios, áreas e presenças desenhados por cima do mapa"
	_overlays.toggle_mode = true
	_overlays.toggled.connect(func(open: bool) -> void: overlays_toggled.emit(open))
	head.add_child(_overlays)
	var help := Button.new()
	help.text = "?"
	help.custom_minimum_size.x = 26
	help.add_theme_font_size_override("font_size", 12)
	help.tooltip_text = "Ver o que cada modo de mapa mostra"
	help.pressed.connect(func() -> void: tutorial_requested.emit())
	head.add_child(help)
	var world := HBoxContainer.new()
	world.add_theme_constant_override("separation", 3)
	box.add_child(world)
	for spec in WORLD:
		var b := _button(spec[1], spec[2], spec[3])
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: level_selected.emit(spec[0]))
		world.add_child(b)
		_level_buttons[spec[0]] = b
	var planet := HBoxContainer.new()
	planet.add_theme_constant_override("separation", 3)
	box.add_child(planet)
	_caption(planet, "Planeta")
	_group(planet, SATELLITE_GROUP, "satellite", "Satélite e visão geral")
	for spec in PLANET:
		_group(planet, spec[0], spec[1], spec[0])


func _caption(box: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = 56
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("#9fb0a8"))
	box.add_child(label)


func _button(icon_name: String, tip: String, caption := "") -> Button:
	var b := Button.new()
	_style(b, icon_name, caption)
	b.tooltip_text = tip
	return b


## Ícone no alto e, se houver, a sigla pequena embaixo (os modos de mundo trazem a sigla, para o mapa se ler sem passar o mouse).
func _style(b: Button, icon_name: String, caption: String) -> void:
	b.icon = UiIcons.get_icon(icon_name, ICON)
	UiKit.tint_icon(b, icon_name)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.flat = true
	if caption.is_empty():
		b.custom_minimum_size = Vector2(40, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return
	b.text = caption
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_font_size_override("font_size", 11)
	b.custom_minimum_size = Vector2(52, 48)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Um botão de grupo de camadas: o clique abre a lista das variantes.
func _group(box: Container, group: String, icon_name: String, tip: String, caption := "") -> void:
	var b := MenuButton.new()
	_style(b, icon_name, caption)
	b.tooltip_text = "%s: escolher a variante" % tip
	b.get_popup().id_pressed.connect(_on_item.bind(group))
	_group_buttons[group] = b
	_items[group] = {}
	box.add_child(b)
	for i in MapLayers.LAYERS.size():
		if MapLayers.LAYERS[i]["group"] == group:
			var popup := b.get_popup()
			var id := popup.item_count
			popup.add_item(MapLayers.LAYERS[i]["menu"], id)
			_items[group][id] = i


func _on_item(id: int, group: String) -> void:
	layer_selected.emit(_items[group][id])


## Marca o modo da camada atual, sem repetir o evento.
func show_layer(index: int) -> void:
	_layer = index
	_refresh()


## Marca o nível mostrado, sem repetir o evento. subdivisions: o mapa político está no modo por subdivisões.
func show_level(level: String, subdivisions := false) -> void:
	_level = level
	_subs = subdivisions
	_refresh()


func _refresh() -> void:
	var data: Dictionary = MapLayers.LAYERS[_layer]
	var rec := _level == "recursos"  # o Rec vai por cima de qualquer mapa: o botão dele vale mais que o do mapa de baixo
	var political: bool = data["kind"] == "political" or rec
	_title.text = "Mapa: %s" % data["menu"]
	if political:
		var level := "subdivisoes" if _subs else _level
		_title.text = "Mapa: %s" % LEVEL_NAME.get(level, "recursos" if level.begins_with("recurso") else "político")
	for level in _level_buttons:
		_mark(_level_buttons[level], political and (level == "subdivisoes" if _subs else level == _level))  # o botão plano não desenha o "pressed": o destaque vai no "normal"
	for group in _group_buttons:
		var b: MenuButton = _group_buttons[group]
		var active: bool = not political and data["group"] == group
		_mark(b, active)
		var popup := b.get_popup()
		for id in _items[group]:
			var name: String = MapLayers.LAYERS[_items[group][id]]["menu"]
			popup.set_item_text(id, ("● " if _items[group][id] == _layer else "    ") + name)  # a variante atual leva o marcador


func _mark(b: Button, active: bool) -> void:
	b.flat = not active  # o botão plano não desenha o fundo "normal", onde fica o destaque
	if active:
		b.add_theme_stylebox_override("normal", UiKit.active_style())
		b.add_theme_stylebox_override("hover", UiKit.active_style())
	else:
		b.remove_theme_stylebox_override("normal")
		b.remove_theme_stylebox_override("hover")
