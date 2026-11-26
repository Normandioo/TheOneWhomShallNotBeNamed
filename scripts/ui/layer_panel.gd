extends PanelContainer
## O ponto fixado por clique: o cartão fica escondido, só guarda o texto. Guarda também, escondidos, o menu do nível e a caixa
## "Mostrar território": o nível vem da coluna de modos e a visibilidade, das sobreposições.
## (A escolha da camada de mapa é a coluna ModeRail; o cursor e a câmera, a StatusBar; exportar e importar, o menu Mundo.)
## Só mostra e pede: avisa por sinal.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal political_visibility_changed(on: bool)
signal level_selected(level: String)  # "pais", "provincia" ou "municipio": qual camada territorial o globo mostra

var _countries: CheckBox
var _level: OptionButton
const LEVELS := ["pais", "provincia", "municipio", "religiao", "cultura", "etnia", "raca", "idioma"]
const LEVEL_MENU := ["Países", "Subdivisões (1º nível)", "Subdivisões (2º nível)", "Religiões", "Culturas", "Etnias", "Raças", "Idiomas"]
var _selection: Label


func _init() -> void:
	custom_minimum_size = Vector2(350, 0)
	add_theme_stylebox_override("panel", UiKit.panel_style())
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Ponto fixado"
	UiKit.style_heading(title)
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)

	_countries = CheckBox.new()
	_countries.text = "Mostrar território"
	_countries.button_pressed = true
	_countries.toggled.connect(political_visibility_changed.emit)
	_level = OptionButton.new()
	for item in LEVEL_MENU:
		_level.add_item(item)
	_level.tooltip_text = "Cada nível é uma camada separada: pintar províncias não muda os países."
	_level.item_selected.connect(func(i: int) -> void: level_selected.emit(LEVELS[i]))
	var level_row := HBoxContainer.new()
	level_row.add_child(_countries)
	level_row.add_child(_level)
	level_row.hide()
	box.add_child(level_row)

	_selection = _add_label(box, "Clique para fixar um ponto.")
	visible = false


## Marca o nível mostrado, sem repetir o evento.
func show_level(level: String) -> void:
	_level.select(LEVELS.find(level))


func show_political(on: bool) -> void:
	_countries.set_pressed_no_signal(on)


func show_selection(text: String) -> void:
	_selection.text = text  # o cartão fica escondido (a leitura do cursor está na barra de estado); o texto segue guardado para os testes
	reset_size.call_deferred()


static func _thousands(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if v < 0 else "") + s + out


func _add_label(box: Container, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(l)
	return l
