extends PanelContainer
## A coluna dos modos de mapa, à esquerda, só com ícones (a dica diz o nome): MUNDO (política, religião, cultura, etnia, raça e idioma, que
## são níveis do território sobre o mapa político, e o satélite) e PLANETA (um botão por grupo de camadas: relevo, clima, ecologia…).
## Os de grupo abrem as variantes; o modo atual fica marcado. No fim, o botão das sobreposições.
## Só mostra e pede: avisa por sinal (o Main escolhe a camada e o nível).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")

signal layer_selected(index: int)
signal level_selected(level: String)  # "pais", "religiao"...: o mapa político nesse nível
signal overlays_toggled(open: bool)

const WIDTH := 52
const ICON := 20
# Nível territorial (mundo): [nível, ícone, dica, sigla embaixo do ícone]
const WORLD := [["pais", "politics", "Política: países", "Pol"], ["subdivisoes", "organization", "Política: subdivisões do país aberto (províncias na cor própria, os outros países em cinza)", "Sub"], ["religiao", "religion", "Religião", "Rel"], ["cultura", "culture", "Cultura", "Cul"],
	["etnia", "ethnicity", "Etnia", "Etn"], ["raca", "race", "Raça", "Raç"], ["idioma", "language", "Idioma", "Idi"]]
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


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", UiKit.dock_style(SIDE_RIGHT, 6, 8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_caption(box, "MUNDO")
	for spec in WORLD:
		var b := _button(spec[1], spec[2], spec[3])
		b.toggle_mode = true
		b.pressed.connect(func() -> void: level_selected.emit(spec[0]))
		box.add_child(b)
		_level_buttons[spec[0]] = b
	_group(box, SATELLITE_GROUP, "satellite", "Satélite e visão geral", "Sat")
	box.add_child(HSeparator.new())
	_caption(box, "PLANETA")
	for spec in PLANET:
		_group(box, spec[0], spec[1], spec[0])
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_overlays = _button("overlays", "Sobreposições: fronteiras e presenças desenhadas por cima do mapa")
	_overlays.toggle_mode = true
	_overlays.toggled.connect(func(open: bool) -> void:
		_mark(_overlays, open)  # o botão plano não mostra o estado ligado: o destaque vai no "normal"
		overlays_toggled.emit(open))
	box.add_child(_overlays)


func _caption(box: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("#8e907f"))
	box.add_child(label)


func _button(icon_name: String, tip: String, caption := "") -> Button:
	var b := Button.new()
	_style(b, icon_name, caption)
	b.tooltip_text = tip
	return b


## Ícone no alto e, se houver, a sigla pequena embaixo (os modos de mundo trazem a sigla, para o mapa se ler sem passar o mouse).
func _style(b: Button, icon_name: String, caption: String) -> void:
	b.icon = UiIcons.get_icon(icon_name, ICON)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.flat = true
	if caption.is_empty():
		b.custom_minimum_size = Vector2(40, 38)
		return
	b.text = caption
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_font_size_override("font_size", 10)
	b.custom_minimum_size = Vector2(40, 48)


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
	var political: bool = data["kind"] == "political"
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
