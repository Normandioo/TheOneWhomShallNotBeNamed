extends PanelContainer
## Controles do mapa de presenças: de quem (a ficha aberta ou todas as entidades) e quais camadas aparecem no globo. Cada camada tem a
## sua cor: fronteira política, presença cultural, distribuição étnica, área linguística e presença religiosa não se confundem.
## Só mostra e pede: avisa por sinal quando o usuário muda; o DomainHub decide o que desenhar.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal changed

var _scope: OptionButton
var _checks := {}  # camada -> CheckBox


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
	for layer in UiKit.LAYERS:
		var c := CheckBox.new()
		c.text = UiKit.LAYER_LABEL[layer]
		c.button_pressed = true
		c.add_theme_color_override("font_color", UiKit.LAYER_COLOR[layer])
		c.toggled.connect(func(_on: bool) -> void: changed.emit())
		box.add_child(c)
		_checks[layer] = c


## As camadas marcadas.
func layers() -> PackedStringArray:
	var out := PackedStringArray()
	for layer in UiKit.LAYERS:
		if _checks[layer].button_pressed:
			out.append(layer)
	return out


## true = todas as entidades; false = só a da ficha aberta.
func all_entities() -> bool:
	return _scope.selected == 1
