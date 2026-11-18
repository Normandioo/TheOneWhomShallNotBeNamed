extends PanelContainer
## A barra do modo "desenhar fronteira": quantos pontos já foram marcados, o que fazer em seguida e os botões Desfazer ponto, Concluir e Cancelar.
## Só mostra e pede: avisa por sinal; quem desenha e grava é o DomainHub. Atalhos enquanto a barra aparece: Esc cancela, Enter conclui, Backspace desfaz o último ponto.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal undo_requested
signal finish_requested
signal cancel_requested

const MIN_POINTS := 3

var _title: Label
var _status: Label
var _undo: Button
var _finish: Button


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	position = Vector2(-12, -150)  # acima da legenda
	custom_minimum_size = Vector2(300, 0)
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.modulate = Color(1.0, 0.92, 0.35)
	box.add_child(_title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(280, 0)
	box.add_child(_status)
	var row := HBoxContainer.new()
	box.add_child(row)
	_undo = Button.new()
	_undo.text = "Desfazer ponto"
	_undo.pressed.connect(func() -> void: undo_requested.emit())
	row.add_child(_undo)
	_finish = Button.new()
	_finish.text = "Concluir"
	_finish.pressed.connect(func() -> void: finish_requested.emit())
	row.add_child(_finish)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.pressed.connect(func() -> void: cancel_requested.emit())
	row.add_child(cancel)


## Mostra a barra com o estado do desenho: título, pontos marcados e a mensagem (dica ou erro).
func show_state(title: String, points: int, message: String) -> void:
	visible = true
	_title.text = title
	_status.text = "%d ponto(s) marcado(s). %s" % [points, message]
	_undo.disabled = points == 0
	_finish.disabled = points < MIN_POINTS


func hide_panel() -> void:
	visible = false


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	match e.keycode:
		KEY_ESCAPE:
			cancel_requested.emit()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if not _finish.disabled:
				finish_requested.emit()
				get_viewport().set_input_as_handled()
		KEY_BACKSPACE:
			if not _undo.disabled:
				undo_requested.emit()
				get_viewport().set_input_as_handled()
