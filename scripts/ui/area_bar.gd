extends PanelContainer
## A barra que aparece com um mapa de área na tela (cultura, etnia, raça, religião ou idioma): o botão de criar uma nova e a dica de clicar numa para editar o território dela.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal new_requested(kind: String)

var _kind := ""
var _title: Label
var _new: Button


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = Label.new()
	UiKit.style_heading(_title)
	box.add_child(_title)
	_new = Button.new()
	_new.add_theme_stylebox_override("normal", UiKit.active_style())
	_new.pressed.connect(func() -> void: new_requested.emit(_kind))
	box.add_child(_new)
	var hint := Label.new()
	hint.text = "Clique numa área do mapa para abrir a ficha e editar o território dela."
	hint.modulate = Color(1, 1, 1, 0.65)
	box.add_child(hint)


## kind: "" esconde a barra.
func show_kind(kind: String) -> void:
	_kind = kind
	visible = kind != ""
	if kind == "":
		return
	var label := UiKit.kind_label(kind)
	_title.text = label + "s"
	_new.text = "＋ Nova %s" % label.to_lower() if kind in ["cultura", "etnia", "raca", "religiao"] else "＋ Novo %s" % label.to_lower()
