extends PanelContainer
## Controles do mapa de presenças: de quem (a ficha aberta ou todas as entidades) e quais camadas aparecem no globo. Cada camada tem a
## sua cor: fronteira política, presença cultural, distribuição étnica, área linguística e presença religiosa não se confundem.
## Só mostra e pede: avisa por sinal quando o usuário muda; o DomainHub decide o que desenhar.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal changed
signal political_visibility_changed(on: bool)

var _scope: OptionButton
var _checks := {}  # camada -> CheckBox
var _box: VBoxContainer


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style())
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	position = Vector2(12, -128)  # acima da barra de tempo
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Presenças no mapa"
	title.add_theme_font_size_override("font_size", 15)
	box.add_child(title)
	_scope = OptionButton.new()
	_scope.add_item("Só a ficha aberta")
	_scope.add_item("Todas as entidades")
	_scope.item_selected.connect(func(_i: int) -> void: changed.emit())
	box.add_child(_scope)
	_box = box
	refresh_layers()


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
		_box.add_child(c)
		_checks[layer] = c


## As camadas marcadas.
func layers() -> PackedStringArray:
	var out := PackedStringArray()
	for layer in UiKit.layer_list:
		if _checks.has(layer) and _checks[layer].button_pressed:
			out.append(layer)
	return out


func set_political_visible(on: bool) -> void:
	_checks["politica"].button_pressed = on


## true = todas as entidades; false = só a da ficha aberta.
func all_entities() -> bool:
	return _scope.selected == 1
