extends PanelContainer
## A barra do modo "pintar território": de que país, a ferramenta (pincel, balde ou borracha), o raio, "só em terra", as fronteiras naturais
## (crescer pela terra sem dono, assentar no relevo), a área já pintada e Terminar.
## Só mostra e pede: avisa por sinal; quem pinta é o DomainHub. Esc termina. Ctrl+Z e Ctrl+Y desfazem e refazem (a pilha é a mesma do terreno).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")  # só para o separador de milhares

signal mode_changed(mode: String)   # pincel | balde | borracha
signal radius_changed(km: float)
signal land_only_changed(on: bool)
signal finish_requested
signal reach_changed(km: float)
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

const MODES := [["pincel", "Pincel"], ["balde", "Balde"], ["borracha", "Borracha"], ["conta-gotas", "Conta-gotas"], ["fronteira", "Fronteira"]]
const TIPS := {
	"pincel": "Arraste no globo para pintar. Pintar sobre outro país toma o território dele.",
	"balde": "Clique dentro de uma área cercada por pintura para preencher tudo de uma vez.",
	"borracha": "Arraste para apagar só o território deste país (o dos vizinhos fica).",
	"conta-gotas": "Clique num território do mesmo nível para passar a pintar com ele.",
}

var radius_km := 300.0
var land_only := true
var mode := "pincel"
var reach_km := 800.0

var _title: Label
var _tip: Label
var _area: Label
var _radius_label: Label
var _reach_label: Label
var _message: Label
var _buttons: Dictionary = {}
var _brush_controls: VBoxContainer
var _boundary_controls: VBoxContainer
var _paths: OptionButton
var _boundary_status: Label
var _reset_boundary: Button
var _preview_row: HBoxContainer
var _merge_menu: OptionButton
var _merge_ids: Array = []
var _side_button: Button


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiKit.panel_style())
	custom_minimum_size = Vector2(300, 0)
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.add_theme_font_size_override("font_size", 16)
	_title.modulate = Color(1.0, 0.92, 0.35)
	box.add_child(_title)
	var tools := HBoxContainer.new()
	box.add_child(tools)
	var group := ButtonGroup.new()
	for m in MODES:
		var b := Button.new()
		b.text = m[1]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = m[0] == mode
		b.pressed.connect(func() -> void:
			set_mode(m[0])
			mode_changed.emit(mode))
		tools.add_child(b)
		_buttons[m[0]] = b
	_brush_controls = VBoxContainer.new()
	box.add_child(_brush_controls)
	var row := HBoxContainer.new()
	_brush_controls.add_child(row)
	_radius_label = Label.new()
	row.add_child(_radius_label)
	var slider := HSlider.new()
	slider.min_value = 20.0
	slider.max_value = 2500.0
	slider.step = 10.0
	slider.value = radius_km
	slider.custom_minimum_size = Vector2(160, 0)
	slider.value_changed.connect(func(v: float) -> void:
		radius_km = v
		_show_radius()
		radius_changed.emit(v))
	row.add_child(slider)
	var land := CheckBox.new()
	land.text = "Só em terra"
	land.tooltip_text = "Pinta só onde a altitude é de terra: a costa do país segue a costa do mapa."
	land.button_pressed = land_only
	land.toggled.connect(func(on: bool) -> void:
		land_only = on
		land_only_changed.emit(on))
	_brush_controls.add_child(land)
	_tip = Label.new()
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tip.custom_minimum_size = Vector2(280, 0)
	_tip.modulate = Color(1, 1, 1, 0.75)
	_tip.text = TIPS[mode]
	_brush_controls.add_child(_tip)
	_area = Label.new()
	_brush_controls.add_child(_area)
	var merge_row := HBoxContainer.new()
	_merge_menu = OptionButton.new()
	_merge_menu.fit_to_longest_item = false
	_merge_menu.custom_minimum_size = Vector2(170, 0)
	merge_row.add_child(_merge_menu)
	var merge := Button.new()
	merge.text = "Unir a este"
	merge.tooltip_text = "Todo o território do cadastro escolhido passa para este (Ctrl+Z desfaz)."
	merge.pressed.connect(func() -> void:
		if _merge_menu.selected >= 0 and _merge_menu.selected < _merge_ids.size():
			merge_requested.emit(_merge_ids[_merge_menu.selected]))
	merge_row.add_child(merge)
	_brush_controls.add_child(merge_row)
	var import_png := Button.new()
	import_png.text = "Importar PNG…"
	import_png.tooltip_text = "Lê um mapa em PNG (equiretangular): cada mancha de cor vira uma região que você liga a um cadastro deste nível."
	import_png.pressed.connect(func() -> void: import_requested.emit())
	_brush_controls.add_child(import_png)
	_natural(_brush_controls)
	_build_boundary_controls(box)
	var done := Button.new()
	done.text = "Terminar"
	done.pressed.connect(func() -> void: finish_requested.emit())
	box.add_child(done)
	_show_radius()
	_update_controls()


func _ready() -> void:
	get_viewport().size_changed.connect(_position_panel)
	minimum_size_changed.connect(_position_panel)


func _build_boundary_controls(box: VBoxContainer) -> void:
	_boundary_controls = VBoxContainer.new()
	box.add_child(_boundary_controls)
	_paths = OptionButton.new()
	_paths.fit_to_longest_item = false
	_paths.item_selected.connect(func(index: int) -> void: boundary_selected.emit(_paths.get_item_id(index)))
	_boundary_controls.add_child(_paths)
	var fidelity := OptionButton.new()
	for f in preload("res://scripts/edit/territory_boundary_tool.gd").FIDELITY:
		fidelity.add_item("Traço: " + f[0])
	fidelity.select(1)
	fidelity.tooltip_text = "Alta fidelidade segue cada tremida da mão; Suavizado amostra menos e estabiliza o traço."
	fidelity.item_selected.connect(fidelity_changed.emit)
	_boundary_controls.add_child(fidelity)
	_boundary_status = Label.new()
	_boundary_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_boundary_status.custom_minimum_size.x = 270
	_boundary_controls.add_child(_boundary_status)
	_reset_boundary = Button.new()
	_reset_boundary.text = "Redesenhar"
	_reset_boundary.pressed.connect(func() -> void: boundary_reset_requested.emit())
	_boundary_controls.add_child(_reset_boundary)
	_preview_row = HBoxContainer.new()
	_preview_row.visible = false
	_boundary_controls.add_child(_preview_row)
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
	if _brush_controls.visible:
		_tip.text = TIPS[mode]
	_position_panel.call_deferred()


func _position_panel() -> void:
	if not is_inside_tree() or not visible:
		return
	size = get_combined_minimum_size()
	var room := get_viewport_rect().size - size - Vector2(12, 12)
	position = Vector2(maxf(0.0, room.x), maxf(0.0, room.y - 138.0))


## Abre a barra para o país, com a área que ele já tem.
func show_state(country_name: String, area_km2: float) -> void:
	visible = true
	_title.text = "Território de %s" % country_name
	set_message("")
	set_area(area_km2)
	_position_panel.call_deferred()


func set_area(area_km2: float) -> void:
	_area.text = "Território: ≈ %s km²" % LayerPanel._thousands(roundi(area_km2)) if area_km2 > 0.0 else "Ainda sem território."


## Uma frase de retorno das fronteiras naturais ("" apaga).
func set_message(text: String) -> void:
	_message.text = text
	_message.visible = text != ""


## Os outros cadastros do nível que podem ser unidos a este: [{id, name}].
func show_merge_choices(entities: Array) -> void:
	_merge_menu.clear()
	_merge_ids.clear()
	for e in entities:
		_merge_menu.add_item(String(e.name))
		_merge_ids.append(int(e.id))
	_merge_menu.disabled = entities.is_empty()


func hide_panel() -> void:
	visible = false


## Fronteiras naturais (docs/mapa-politico.md, etapa 1): o alcance e os três botões.
func _natural(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "Fronteiras naturais"
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	_reach_label = Label.new()
	row.add_child(_reach_label)
	var slider := HSlider.new()
	slider.min_value = 100.0
	slider.max_value = 4000.0
	slider.step = 50.0
	slider.value = reach_km
	slider.custom_minimum_size = Vector2(150, 0)
	slider.tooltip_text = "Até onde cada país cresce, em km \"de caminho\": serra e mar contam mais que planície."
	slider.value_changed.connect(func(v: float) -> void:
		reach_km = v
		_show_reach()
		reach_changed.emit(v))
	row.add_child(slider)
	var grow := HBoxContainer.new()
	box.add_child(grow)
	for spec in [["Crescer este país", false, "Ocupa a terra sem dono em volta do território e da capital, até onde os vizinhos chegariam antes. Não toma terra de ninguém."],
			["Crescer todos", true, "Todos os países com território ou capital crescem juntos pela terra sem dono. As divisas caem em serras, rios grandes e estreitos."]]:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[2]
		b.pressed.connect(func() -> void: grow_requested.emit(spec[1]))
		grow.add_child(b)
	var snap := Button.new()
	snap.text = "Assentar fronteiras no relevo"
	snap.tooltip_text = "Leva as fronteiras deste país com os vizinhos para a crista ou o rio grande mais perto (até ~60 km). Não muda a costa."
	snap.pressed.connect(func() -> void: snap_requested.emit())
	box.add_child(snap)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD
	_message.custom_minimum_size = Vector2(280, 0)
	_message.modulate = Color(1.0, 0.85, 0.55)
	_message.visible = false
	box.add_child(_message)
	_show_reach()


func _show_reach() -> void:
	_reach_label.text = "Alcance %d km  " % roundi(reach_km)


func _show_radius() -> void:
	_radius_label.text = "Raio %d km  " % roundi(radius_km)


func _unhandled_key_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		finish_requested.emit()
		get_viewport().set_input_as_handled()
