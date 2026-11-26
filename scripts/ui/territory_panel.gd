extends PanelContainer
## A barra do modo "pintar território", embaixo ao centro, numa linha: o país, a ferramenta (pincel, balde, borracha, conta-gotas ou fronteira), o raio e "só em terra"
## e as ações do território (unir, importar PNG, crescer, assentar), só com ícone, e Concluir. A área pintada fica no tooltip do nome do país.
## Só mostra e pede: avisa por sinal; quem pinta é o DomainHub. Esc termina. Ctrl+Z e Ctrl+Y desfazem e refazem (a pilha é a mesma do terreno).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")  # só para o separador de milhares

signal mode_changed(mode: String)   # pincel | balde | borracha
signal radius_changed(km: float)
signal land_only_changed(on: bool)
signal protect_changed(on: bool)   # "Não invadir": poupar o território dos outros
signal finish_requested
signal tutorial_requested   # o botão "?" da barra
signal reach_changed(km: float)  # o alcance do crescimento: sem controle na barra, vale o padrão de 800 km
signal grow_requested(all: bool)  # crescer pela terra sem dono: só este país (false) ou todos (true)
signal snap_requested             # assentar as fronteiras deste país na crista ou no rio mais perto
signal boundary_selected(id: int)
signal boundary_reset_requested
signal boundary_apply_requested    # confirmar a prévia da divisão
signal boundary_discard_requested  # descartar a prévia
signal boundary_side_requested     # ver o outro lado do corte
signal merge_requested(from_id: int)  # unir: o território inteiro de outro cadastro passa para este
signal import_requested  # importar um PNG para a camada do nível que está sendo pintado
signal fidelity_changed(index: int)  # modo de fidelidade do traço (TerritoryBoundaryTool.FIDELITY)
signal snap_rivers_changed(on: bool)

const ICONS := {"pincel": "territory", "balde": "bucket", "borracha": "eraser", "conta-gotas": "eyedropper", "fronteira": "border"}
const MODES := [["pincel", "Pincel"], ["balde", "Balde"], ["borracha", "Borracha"], ["conta-gotas", "Conta-gotas"], ["fronteira", "Fronteira"]]
const TIPS := {
	"pincel": "Arraste no globo para pintar. Pintar sobre outro país toma o território dele.",
	"balde": "Clique dentro de uma área cercada por pintura para preencher tudo de uma vez.",
	"borracha": "Arraste para apagar só o território deste país (o dos vizinhos fica).",
	"conta-gotas": "Clique num território do mesmo nível para passar a pintar com ele.",
}

var radius_km := 300.0
var land_only := true
var protect_check: CheckBox
var mode := "pincel"

var _title: Label
var _area: Label  # a área já pintada: não aparece, fica no tooltip do nome do país
var _radius_label: Label
var _message: Label
var _buttons: Dictionary = {}
var _brush_controls: HBoxContainer
var _boundary_controls: HBoxContainer
var _paths: OptionButton
var _boundary_status: Label
var _reset_boundary: Button
var _preview_row: HBoxContainer
var _merge_button: MenuButton
var help_button: Button
var done_button: Button
var _merge_menu: PopupMenu  # a lista de cadastros do botão de unir
var _merge_ids: Array = []
var _actions: HBoxContainer  # unir, importar e fronteiras naturais: só para cadastros
var _side_button: Button


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	# Uma linha só: o país, as ferramentas (só o ícone; o nome e a dica ficam no tooltip), o raio e "só em terra", "Mais" e Concluir.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	_title = Label.new()
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.custom_minimum_size.x = 140  # "Nova província" inteiro
	_title.add_theme_font_size_override("font_size", 15)
	UiKit.style_heading(_title)
	_title.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_title)
	_area = Label.new()
	_area.visible = false
	row.add_child(_area)
	var group := ButtonGroup.new()
	for m in MODES:
		var b := Button.new()
		b.icon = UiIcons.get_icon(ICONS[m[0]], 20)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(38, 34)
		b.tooltip_text = "%s: %s" % [m[1], TIPS.get(m[0], "Desenha uma fronteira à mão, aberta ou como contorno fechado.")]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = m[0] == mode
		b.pressed.connect(func() -> void:
			set_mode(m[0])
			mode_changed.emit(mode))
		row.add_child(b)
		_buttons[m[0]] = b
	_brush_controls = HBoxContainer.new()  # só nas ferramentas de pintar (a fronteira não tem raio)
	_brush_controls.add_theme_constant_override("separation", 8)
	row.add_child(_brush_controls)
	_brush_controls.add_child(VSeparator.new())
	_radius_label = Label.new()
	_brush_controls.add_child(_radius_label)
	var slider := HSlider.new()
	slider.min_value = 20.0
	slider.max_value = 2500.0
	slider.step = 10.0
	slider.value = radius_km
	slider.custom_minimum_size = Vector2(110, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		radius_km = v
		_show_radius()
		radius_changed.emit(v))
	_brush_controls.add_child(slider)
	var land := CheckBox.new()
	land.text = "Só em terra"
	land.tooltip_text = "Pinta só onde a altitude é de terra: a costa do país segue a costa do mapa."
	land.button_pressed = land_only
	land.toggled.connect(func(on: bool) -> void:
		land_only = on
		land_only_changed.emit(on))
	_brush_controls.add_child(land)
	protect_check = CheckBox.new()
	protect_check.text = "Não invadir"
	protect_check.tooltip_text = "A pintura para na fronteira dos outros: dá para passar o pincel por cima que ela encosta sem tomar nada. Desligue para conquistar território."
	protect_check.button_pressed = true
	protect_check.toggled.connect(func(on: bool) -> void: protect_changed.emit(on))
	row.add_child(protect_check)
	_boundary_controls = HBoxContainer.new()  # só na ferramenta Fronteira: a fronteira, o traço e o "Outro lado"
	_boundary_controls.add_theme_constant_override("separation", 6)
	row.add_child(_boundary_controls)
	_build_boundary_controls(_boundary_controls)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(VSeparator.new())
	# As ações do território, só com ícone (o nome e a dica ficam no tooltip): unir, importar PNG e as fronteiras naturais.
	_merge_button = MenuButton.new()
	_merge_button.icon = UiIcons.get_icon("merge", 20)
	_merge_button.custom_minimum_size = Vector2(38, 34)
	_merge_button.tooltip_text = "Unir a este: escolha o cadastro cujo território inteiro passa para este (Ctrl+Z desfaz)."
	_merge_menu = _merge_button.get_popup()
	_merge_menu.id_pressed.connect(func(i: int) -> void:
		if i >= 0 and i < _merge_ids.size():
			merge_requested.emit(_merge_ids[i]))
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 6)
	row.add_child(_actions)
	_actions.add_child(_merge_button)
	for spec in [["upload", "Importar PNG: cada mancha de cor de um mapa equiretangular vira uma região que você liga a um cadastro deste nível.", import_requested, null],
			["grow", "Crescer este país: ocupa a terra sem dono em volta do território e da capital, até onde os vizinhos chegariam antes (800 km de caminho).", grow_requested, false],
			["grow_all", "Crescer todos: todos os países com território ou capital crescem juntos pela terra sem dono; as divisas caem em serras, rios grandes e estreitos.", grow_requested, true],
			["snap", "Assentar fronteiras no relevo: leva as fronteiras deste país com os vizinhos para a crista ou o rio grande mais perto (até ~60 km). Não muda a costa.", snap_requested, null]]:
		var ab := Button.new()
		ab.icon = UiIcons.get_icon(spec[0], 20)
		ab.custom_minimum_size = Vector2(38, 34)
		ab.tooltip_text = spec[1]
		var sig: Signal = spec[2]
		var arg = spec[3]
		ab.pressed.connect(func() -> void:
			if arg == null:
				sig.emit()
			else:
				sig.emit(arg))
		_actions.add_child(ab)
	row.add_child(VSeparator.new())
	help_button = Button.new()
	help_button.text = "?"
	help_button.custom_minimum_size = Vector2(34, 34)
	help_button.tooltip_text = "Ver como funciona o pincel de território"
	help_button.pressed.connect(func() -> void: tutorial_requested.emit())
	row.add_child(help_button)
	var done := Button.new()
	done_button = done
	done.icon = UiIcons.get_icon("check", 20)
	done.custom_minimum_size = Vector2(38, 34)
	done.tooltip_text = "Concluir: sai do modo Território (Esc)"
	done.pressed.connect(func() -> void: finish_requested.emit())
	row.add_child(done)

	_message = Label.new()  # o retorno das ações (crescer, unir, importar, avisos)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD
	_message.custom_minimum_size = Vector2(300, 0)
	_message.modulate = Color(1.0, 0.85, 0.55)
	_message.visible = false
	box.add_child(_message)
	_boundary_status = Label.new()
	_boundary_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_boundary_status.visible = false  # o texto fica guardado (os testes o leem), mas não aparece: a barra não explica, o tooltip sim
	box.add_child(_boundary_status)
	_show_radius()
	_update_controls()


func _ready() -> void:
	get_viewport().size_changed.connect(_position_panel)
	minimum_size_changed.connect(_position_panel)


func _build_boundary_controls(row: HBoxContainer) -> void:
	row.add_child(VSeparator.new())
	_paths = OptionButton.new()
	_paths.fit_to_longest_item = false
	_paths.custom_minimum_size.x = 150
	_paths.item_selected.connect(func(index: int) -> void: boundary_selected.emit(_paths.get_item_id(index)))
	row.add_child(_paths)
	var fidelity := OptionButton.new()
	for f in preload("res://scripts/edit/territory_boundary_tool.gd").FIDELITY:
		fidelity.add_item("Traço: " + f[0])
	fidelity.select(1)
	fidelity.fit_to_longest_item = false
	fidelity.tooltip_text = "Alta fidelidade segue cada tremida da mão; Suavizado amostra menos e estabiliza o traço."
	fidelity.item_selected.connect(fidelity_changed.emit)
	row.add_child(fidelity)
	var snap := CheckBox.new()
	snap.text = "Grudar no rio"
	snap.tooltip_text = "O traço desenhado perto de um rio segue o leito dele, com as curvas. São os rios do satélite e de \"Rios em destaque\" (Sobreposições)."
	snap.toggled.connect(snap_rivers_changed.emit)
	row.add_child(snap)
	_reset_boundary = Button.new()
	_reset_boundary.text = "Redesenhar"
	_reset_boundary.pressed.connect(func() -> void: boundary_reset_requested.emit())
	row.add_child(_reset_boundary)
	_preview_row = HBoxContainer.new()
	_preview_row.visible = false
	row.add_child(_preview_row)
	for spec in [["Aplicar", boundary_apply_requested], ["Outro lado", boundary_side_requested], ["Descartar", boundary_discard_requested]]:
		var b := Button.new()
		b.text = spec[0]
		var sig: Signal = spec[1]
		b.pressed.connect(func() -> void: sig.emit())
		_preview_row.add_child(b)
		if spec[0] == "Outro lado":
			_side_button = b


func show_boundary_options(paths: Array, neighbors: Dictionary, path_id: int) -> void:
	_paths.clear()
	_paths.add_item("Nova fronteira", 0)
	for path in paths:
		_paths.add_item("Fronteira %d · %s" % [path.id, neighbors.get(path.source, "País %d" % path.source)], path.id)
	_paths.select(_paths.get_item_index(path_id))
	_paths.visible = not paths.is_empty()
	_reset_boundary.visible = path_id != 0


func show_boundary_state(message: String) -> void:
	_boundary_status.text = message


## O traço se aplica ao soltar o mouse: da fila de botões só resta "Outro lado", depois de um corte em que mais de um lado encostava.
func show_boundary_preview(_on: bool, sides: bool) -> void:
	_preview_row.visible = sides
	for b in _preview_row.get_children():
		b.visible = b == _side_button
	_position_panel.call_deferred()


func set_mode(next_mode: String) -> void:
	mode = next_mode
	_buttons[mode].set_pressed_no_signal(true)
	_update_controls()


func _update_controls() -> void:
	_boundary_controls.visible = mode == "fronteira"
	_brush_controls.visible = mode != "fronteira"
	_position_panel.call_deferred()


func _position_panel() -> void:
	if not is_inside_tree() or not visible:
		return
	size = get_combined_minimum_size()  # quem põe no lugar é o Main (_layout): embaixo, no meio do espaço livre


## Abre a barra para o país, com a área que ele já tem.
func show_state(country_name: String, area_km2: float) -> void:
	visible = true
	_title.text = country_name
	set_message("")
	set_area(area_km2)
	_position_panel.call_deferred()


func set_area(area_km2: float) -> void:
	_area.text = "Território: ≈ %s km²" % LayerPanel._thousands(roundi(area_km2)) if area_km2 > 0.0 else "Ainda sem território."
	_title.tooltip_text = _area.text


## Uma frase de retorno das fronteiras naturais ("" apaga).
func set_message(text: String) -> void:
	_message.text = text
	_message.visible = text != ""


## Os outros cadastros do nível que podem ser unidos a este: [{id, name}].
func show_merge_choices(entities: Array) -> void:
	_merge_menu.clear()
	_merge_ids.clear()
	for e in entities:
		_merge_menu.add_item(String(e.name), _merge_ids.size())
		_merge_ids.append(int(e.id))
	_merge_button.disabled = entities.is_empty()


func set_territory_actions(on: bool) -> void:
	_actions.visible = on


func hide_panel() -> void:
	visible = false


func _show_radius() -> void:
	_radius_label.text = "Raio %d km  " % roundi(radius_km)


func _unhandled_key_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		finish_requested.emit()
		get_viewport().set_input_as_handled()
