extends Control
## O que os tutoriais põem na tela: a pergunta "quer ver como funciona?" e os passos. Nos passos o jogo continua valendo: só o cartão
## recebe o mouse, a parte falada ganha um contorno, e cada passo propõe algo para experimentar (marcado como feito quando acontece).
## O cartão pode ser arrastado pelo título. Só mostra e pede: avisa por sinal; quem decide os passos é o tutorial_controller.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

signal accepted
signal declined          # "Não" na pergunta ou "Pular" no meio
signal never_requested   # "não perguntar mais"
signal finished          # chegou ao fim

const CARD_WIDTH := 460.0
const NARROW_WIDTH := 380.0  # dentro das janelas pequenas (Tipos)
const GAP := 14.0
const MARK := Color("#f2c46d")
const DONE := Color("#8fce9c")
const DIM := Color(0.015, 0.03, 0.04, 0.66)

## Passo: {title, text, try, watch: Callable, rect: Callable() -> Rect2, show: Callable()}.
## try: o que experimentar; watch: um estado do jogo (mudou = feito); rect: o destaque (inválido = passo sem destaque);
## show: deixa a parte falada na tela (abre o menu e rola até ela).
var steps: Array = []
var step := 0
var asking := false
var modal := false       # só a pergunta do primeiro acesso segura a tela
var done := false        # o "Experimente" do passo atual já aconteceu
var card: PanelContainer
var title_label: Label
var count_label: Label
var text_label: Label
var try_label: Label
var tip_label: Label
var yes_button: Button
var no_button: Button
var never_button: Button
var back_button: Button
var next_button: Button
var skip_button: Button
var again_button: Button
var _ask_row: HBoxContainer
var _step_row: HBoxContainer
var _missing_row: HBoxContainer
var _head: HBoxContainer
var _baseline: Variant
var _dragged := false
var _dragging := false
var _ever_shown := false  # o destaque deste passo já apareceu: sumir depois é o usuário que fechou


func _init() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_force_pass_scroll_events = false
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel_style())
	card.custom_minimum_size.x = CARD_WIDTH
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	card.add_child(box)
	_head = HBoxContainer.new()
	_head.mouse_filter = Control.MOUSE_FILTER_STOP
	_head.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_head.gui_input.connect(_drag)
	box.add_child(_head)
	title_label = Label.new()
	UiKit.style_heading(title_label)
	title_label.add_theme_font_size_override("font_size", 19)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_head.add_child(title_label)
	count_label = Label.new()
	count_label.add_theme_font_size_override("font_size", 13)
	count_label.add_theme_color_override("font_color", UiKit.MUTED)
	_head.add_child(count_label)
	text_label = _text(box, 15, UiKit.PAPER)
	try_label = _text(box, 15, MARK)
	tip_label = _text(box, 13, UiKit.MUTED)
	_missing_row = HBoxContainer.new()
	_missing_row.add_theme_constant_override("separation", 8)
	box.add_child(_missing_row)
	var gone := Label.new()
	gone.text = "Essa parte não está na tela agora."
	gone.add_theme_font_size_override("font_size", 13)
	gone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_missing_row.add_child(gone)
	again_button = _button(_missing_row, "Mostrar de novo", func() -> void: _reveal())
	_ask_row = HBoxContainer.new()
	_ask_row.add_theme_constant_override("separation", 10)
	box.add_child(_ask_row)
	no_button = _button(_ask_row, "Agora não", func() -> void:
		close()
		declined.emit())
	no_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes_button = _button(_ask_row, "Sim, mostrar", func() -> void: accepted.emit())
	yes_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes_button.add_theme_stylebox_override("normal", UiKit.active_style())
	never_button = _button(box, "Não perguntar mais em nenhum menu", func() -> void:
		close()
		never_requested.emit())
	never_button.flat = true
	never_button.add_theme_font_size_override("font_size", 13)
	_step_row = HBoxContainer.new()
	_step_row.add_theme_constant_override("separation", 8)
	box.add_child(_step_row)
	skip_button = _button(_step_row, "Pular", func() -> void:
		close()
		declined.emit())
	skip_button.flat = true
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_row.add_child(spacer)
	back_button = _button(_step_row, "Voltar", func() -> void: show_step(step - 1))
	next_button = _button(_step_row, "Próximo", _next)
	next_button.add_theme_stylebox_override("normal", UiKit.active_style())
	card.minimum_size_changed.connect(func() -> void: _place.call_deferred())
	resized.connect(_place)


## A pergunta. blocking: escurece e segura a tela (a do primeiro acesso); sem isso, só o cartão.
func ask(title: String, text: String, note: String, blocking_screen: bool, offer_never: bool, no_text := "Agora não") -> void:
	asking = true
	modal = blocking_screen
	steps = []
	title_label.text = title
	count_label.text = ""
	text_label.text = text
	try_label.visible = false
	tip_label.text = note
	tip_label.visible = note != ""
	no_button.text = no_text
	yes_button.visible = true
	never_button.visible = offer_never
	_missing_row.visible = false
	_ask_row.visible = true
	_step_row.visible = false
	_open()


## Um aviso sem pergunta (o que falta para o tutorial começar), com um botão para desistir.
func notice(title: String, text: String) -> void:
	ask(title, text, "", false, false, "Cancelar")
	yes_button.visible = false


func run(list: Array) -> void:
	if list.is_empty():
		return
	asking = false
	modal = false  # o jogo continua: dá para experimentar enquanto o tutorial está aberto
	steps = list
	step = 0  # antes de abrir: o passo de um tutorial mais comprido não pode sobrar
	never_button.visible = false
	_ask_row.visible = false
	_step_row.visible = true
	_open()
	show_step(0)


func show_step(index: int) -> void:
	step = clampi(index, 0, steps.size() - 1)
	var s: Dictionary = steps[step]
	title_label.text = s.title
	count_label.text = "Passo %d de %d" % [step + 1, steps.size()]
	text_label.text = s.text
	tip_label.text = s.get("tip", "")
	tip_label.visible = tip_label.text != ""
	done = false
	_dragged = false
	_ever_shown = false
	_missing_row.visible = false
	var watch: Callable = s.get("watch", Callable())
	_baseline = watch.call() if watch.is_valid() else null
	_show_try()
	back_button.visible = step > 0
	next_button.text = "Concluir" if step == steps.size() - 1 else "Próximo"
	_reveal()
	card.reset_size()
	_place()


func close() -> void:
	visible = false
	asking = false
	modal = false
	_dragging = false
	steps = []


## Está tomando a tela (o teclado e o mouse são do tutorial)? Só a pergunta do primeiro acesso.
func blocking() -> bool:
	return visible and modal


## Muda a largura do cartão (as janelas pequenas pedem um mais estreito).
func set_card_width(width: float) -> void:
	card.custom_minimum_size.x = width
	for l in [text_label, try_label, tip_label]:
		l.custom_minimum_size.x = width - 40.0
	card.reset_size()


## A parte da tela em destaque agora (vazia = nenhuma).
func target_rect() -> Rect2:
	if asking or steps.is_empty():
		return Rect2()
	var rect: Callable = steps[step].get("rect", Callable())
	if not rect.is_valid():
		return Rect2()
	var r: Rect2 = rect.call()
	r.position -= global_position  # dentro de uma janela o cartão não começa no canto dela
	return r.grow(3.0).intersection(Rect2(Vector2.ZERO, size)) if r.has_area() else Rect2()


func _reveal() -> void:
	if steps.is_empty():
		return
	var show_it: Callable = steps[step].get("show", Callable())
	if show_it.is_valid():
		show_it.call()
	_dragged = false


func _show_try() -> void:
	var what: String = steps[step].get("try", "")
	try_label.visible = what != ""
	try_label.text = "✓ Feito! " + what if done else "Experimente: " + what
	try_label.add_theme_color_override("font_color", DONE if done else MARK)


func _next() -> void:
	if step >= steps.size() - 1:
		close()
		finished.emit()
	else:
		show_step(step + 1)


func _open() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if modal else Control.MOUSE_FILTER_IGNORE
	_dragged = false
	visible = true
	if is_inside_tree():
		move_to_front()
	card.reset_size()
	_place()


## O cartão fica ao lado do destaque, onde couber (abaixo, acima, à direita, à esquerda); passo sem destaque, no canto direito, para o
## mapa ficar livre. Depois de arrastado, fica onde o usuário o deixou.
func _place() -> void:
	if not visible:
		return
	card.size = card.get_combined_minimum_size()
	var c := card.size
	var limit := (size - c - Vector2(8, 8)).max(Vector2(8, 8))
	if _dragged:
		card.position = card.position.clamp(Vector2(8, 8), limit).floor()
		queue_redraw()
		return
	var r := target_rect()
	var at := (size - c) / 2.0
	if asking:
		if not modal:
			at = Vector2((size.x - c.x) / 2.0, size.y - c.y - minf(120.0, size.y * 0.06 + 20.0))  # embaixo, sem tapar a barra
	elif r.has_area():
		var x := clampf(r.get_center().x - c.x / 2.0, 8.0, limit.x)
		var y := clampf(r.get_center().y - c.y / 2.0, 8.0, limit.y)
		if r.end.x + GAP + c.x <= size.x - 8.0 and r.size.y > size.y * 0.45:
			at = Vector2(r.end.x + GAP, y)  # uma janela alta: o cartão vai para o lado dela
		elif r.end.y + GAP + c.y <= size.y - 8.0:
			at = Vector2(x, r.end.y + GAP)
		elif r.position.y - GAP - c.y >= 8.0:
			at = Vector2(x, r.position.y - GAP - c.y)
		elif r.end.x + GAP + c.x <= size.x - 8.0:
			at = Vector2(r.end.x + GAP, y)
		elif r.position.x - GAP - c.x >= 8.0:
			at = Vector2(r.position.x - GAP - c.x, y)
		else:
			at = Vector2(limit.x, limit.y)
	else:
		at = Vector2(limit.x - 8.0, clampf(size.y * 0.2, 8.0, limit.y))
	card.position = at.clamp(Vector2(8, 8), limit).floor()
	queue_redraw()


func _drag(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_dragging = e.pressed
	elif e is InputEventMouseMotion and _dragging:
		_dragged = true
		card.position += e.relative
		_place()


func _process(_delta: float) -> void:
	if not visible or asking or steps.is_empty():
		return
	var s: Dictionary = steps[step]
	var watch: Callable = s.get("watch", Callable())
	if not done and watch.is_valid() and watch.call() != _baseline:
		done = true
		_show_try()
	var has_target: bool = s.get("rect", Callable()).is_valid()
	var shown := target_rect().has_area()
	_ever_shown = _ever_shown or shown
	var missing := has_target and not shown and _ever_shown
	if missing != _missing_row.visible:
		_missing_row.visible = missing
		card.reset_size()
	if not _dragging:
		_place()  # o destaque acompanha o que muda embaixo (a ficha refeita, a janela redimensionada)


func _draw() -> void:
	if modal:
		draw_rect(Rect2(Vector2.ZERO, size), DIM)
		return
	var r := target_rect()
	if r.has_area():  # sem escurecer: o que está em volta continua sendo usado
		draw_rect(r.grow(3.0), Color(MARK, 0.28), false, 7.0)
		draw_rect(r, MARK, false, 3.0)


func _input(e: InputEvent) -> void:
	if blocking() and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		close()
		declined.emit()
		get_viewport().set_input_as_handled()


func _text(box: VBoxContainer, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = CARD_WIDTH - 40.0
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


func _button(box: Container, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 36
	b.focus_mode = Control.FOCUS_NONE  # o foco continua no que o usuário está experimentando
	b.pressed.connect(on_press)
	box.add_child(b)
	return b
