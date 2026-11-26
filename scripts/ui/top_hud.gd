extends HBoxContainer
## O alto à esquerda: o emblema do selecionado, os números dele e os botões de categoria, cada um abrindo a janela única da esquerda.
## Dá para minimizar: sobra uma faixa fina com o brasão, o nome e o botão de expandir.
## Só mostra e pede: avisa por sinais; quem decide os números e abre as janelas é o hud_controller.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")
const SunCrest = preload("res://scripts/ui/sun_crest.gd")

signal category_pressed(key: String)
signal emblem_pressed
signal clear_pressed

## [chave, nome, ícone, dica]
const CATEGORIES := [
	["ficha", "Ficha", "file", "Nome, resumo, etiquetas e informações"],
	["governo", "Governo", "government", "Hierarquia e vínculos"],
	["povo", "Povo", "people", "Culturas, etnias, religiões, idiomas e raças"],
	["populacao", "População", "population", "Total e cidades"],
	["territorio", "Território", "border", "Território, subdivisões e lugares · T pinta direto"],
	["recursos", "Recursos", "resources", "Catálogo de recursos e ocorrências no mapa"],
	["economia", "Economia", "economy", "Povoados: trabalhadores, atividades, estoques e receitas"],
	["calendarios", "Calendários", "calendar", "Calendários em uso"],
]
const WIDE := 90.0
const NARROW := 50.0

var minimized := false
var category_buttons := {}  # chave -> Button
var _column: VBoxContainer
var _mini: PanelContainer
var _mini_crest: Control
var _mini_name: Button
var _mini_clear: Button
var _fold: Button
var _expand: Button
var stat_buttons: Array[Button] = []
var _crest: Control
var _emblem: Button
var _name: Label
var _clear: Button
var _stats: HBoxContainer
var _stats_clip: Control
var _compact := false


func _init() -> void:
	add_theme_constant_override("separation", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_emblem = Button.new()
	_emblem.custom_minimum_size = Vector2(150, 108)
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_emblem.add_theme_stylebox_override("normal", UiKit.metal_style(Color("#1b262a")))
	_emblem.add_theme_stylebox_override("hover", UiKit.metal_style(Color("#24343a")))
	_emblem.add_theme_stylebox_override("pressed", UiKit.metal_style(Color("#24343a")))
	_emblem.add_theme_stylebox_override("disabled", UiKit.metal_style(Color("#1b262a")))
	_emblem.pressed.connect(func() -> void: emblem_pressed.emit())
	add_child(_emblem)
	var inner := VBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem.add_child(inner)
	_crest = SunCrest.new()
	_crest.custom_minimum_size = Vector2(60, 60)
	_crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_crest.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(_crest)
	_name = Label.new()
	UiKit.style_heading(_name)
	_name.add_theme_color_override("font_color", UiKit.PAPER)
	_name.add_theme_font_size_override("font_size", 15)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inner.add_child(_name)
	_clear = Button.new()
	_clear.text = "✕"
	_clear.flat = true
	_clear.tooltip_text = "Tirar a seleção (Esc)"
	_clear.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_clear.offset_left = -26
	_clear.offset_right = -2
	_clear.offset_top = 2
	_clear.offset_bottom = 26
	_clear.pressed.connect(func() -> void: clear_pressed.emit())
	_emblem.add_child(_clear)

	var column := VBoxContainer.new()
	_column = column
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UiKit.metal_style(Color("#1b262a"), 6, 5))
	strip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(strip)
	_stats_clip = Control.new()  # os números que não cabem são cortados, não empurram o resto da tela
	_stats_clip.clip_contents = true
	_stats_clip.custom_minimum_size = Vector2(0, 32)
	strip.add_child(_stats_clip)
	_stats = HBoxContainer.new()
	_stats.add_theme_constant_override("separation", 6)
	_stats_clip.add_child(_stats)

	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiKit.metal_style(Color("#223036"), 5, 4))
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	bar.add_child(row)
	for spec in CATEGORIES:
		var b := Button.new()
		b.text = spec[1]
		b.icon = UiIcons.get_icon(spec[2], 24)
		UiKit.tint_icon(b, spec[2])
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(WIDE, 58)
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = "%s: %s" % [spec[1], spec[3]]
		var key: String = spec[0]
		b.pressed.connect(func() -> void: category_pressed.emit(key))
		row.add_child(b)
		category_buttons[key] = b
	_fold = _chevron("chevron_up", "Minimizar o alto da tela")
	_fold.custom_minimum_size = Vector2(28, 58)
	_fold.pressed.connect(set_minimized.bind(true))
	row.add_child(_fold)
	_build_mini()


## A faixa do alto minimizado.
func _build_mini() -> void:
	_mini = PanelContainer.new()
	_mini.add_theme_stylebox_override("panel", UiKit.metal_style(Color("#1b262a"), 6, 4))
	_mini.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_mini.visible = false
	add_child(_mini)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_mini.add_child(row)
	_mini_crest = SunCrest.new()
	_mini_crest.custom_minimum_size = Vector2(30, 30)
	row.add_child(_mini_crest)
	_mini_name = Button.new()
	_mini_name.flat = true
	_mini_name.add_theme_font_override("font", UiKit.heading_font())
	_mini_name.add_theme_font_size_override("font_size", 15)
	_mini_name.pressed.connect(func() -> void: emblem_pressed.emit())
	row.add_child(_mini_name)
	_mini_clear = Button.new()
	_mini_clear.text = "✕"
	_mini_clear.flat = true
	_mini_clear.tooltip_text = "Tirar a seleção (Esc)"
	_mini_clear.pressed.connect(func() -> void: clear_pressed.emit())
	row.add_child(_mini_clear)
	_expand = _chevron("chevron_down", "Expandir o alto da tela")
	_expand.custom_minimum_size = Vector2(36, 30)
	_expand.pressed.connect(set_minimized.bind(false))
	row.add_child(_expand)


func _chevron(icon_name: String, tip: String) -> Button:
	var b := Button.new()
	b.icon = UiIcons.get_icon(icon_name, 16)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = tip
	return b


## Recolhe os números e as categorias (ou os traz de volta). A janela aberta continua; os avisos também.
func set_minimized(on: bool) -> void:
	if on == minimized:
		return
	minimized = on
	_emblem.visible = not on
	_column.visible = not on
	_mini.visible = on
	reset_size.call_deferred()


## Em janela estreita os botões ficam só com o ícone (a dica diz o nome).
func set_compact(compact: bool) -> void:
	if compact == _compact:
		return
	_compact = compact
	for spec in CATEGORIES:
		var b: Button = category_buttons[spec[0]]
		b.text = "" if compact else spec[1]
		b.custom_minimum_size.x = NARROW if compact else WIDE
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER if compact else VERTICAL_ALIGNMENT_TOP
	_emblem.custom_minimum_size.x = 108.0 if compact else 150.0


## info: {name, color: Color, selected: bool, stats: [{icon, text, tip, key, warn}], enabled: {chave: bool}, labels: {chave: nome}}
func show_info(info: Dictionary) -> void:
	_crest.color = info.color
	_name.text = String(info.name).to_upper()
	_mini_crest.color = info.color
	_mini_name.text = _name.text
	_mini_name.disabled = not info.selected
	_mini_name.tooltip_text = "Abrir a ficha de %s" % info.name if info.selected else "Clique num país no mapa para selecionar"
	_mini_clear.visible = info.selected
	_emblem.disabled = not info.selected
	_emblem.tooltip_text = "Abrir a ficha de %s" % info.name if info.selected else "Clique num país no mapa para selecionar"
	_clear.visible = info.selected
	for b in stat_buttons:
		_stats.remove_child(b)
		b.queue_free()
	stat_buttons.clear()
	for s in info.stats:
		var chip := Button.new()
		chip.text = s.text
		chip.icon = UiIcons.get_icon(s.icon, 16)
		UiKit.tint_icon(chip, s.icon)
		chip.tooltip_text = s.tip
		chip.add_theme_stylebox_override("normal", UiKit.inset_style())
		chip.add_theme_stylebox_override("hover", UiKit.inset_style(true))
		chip.add_theme_stylebox_override("pressed", UiKit.inset_style(true))
		chip.add_theme_color_override("font_color", Color("#f2c46d") if s.get("warn", false) else UiKit.PAPER)
		var key: String = s.get("key", "")
		if key != "":
			chip.pressed.connect(func() -> void: category_pressed.emit(key))
		_stats.add_child(chip)
		stat_buttons.append(chip)
	for spec in CATEGORIES:
		var b: Button = category_buttons[spec[0]]
		b.disabled = not info.enabled.get(spec[0], false)
		var label: String = info.get("labels", {}).get(spec[0], spec[1])
		b.text = "" if _compact else label


## A faixa dos números ocupa a largura pedida (a dos botões de categoria, no máximo o espaço livre).
func fit_stats(limit: float) -> void:
	var wanted := minf(_stats.get_combined_minimum_size().x, maxf(limit, 0.0))
	_stats.size = _stats.get_combined_minimum_size()
	if not is_equal_approx(_stats_clip.custom_minimum_size.x, wanted):
		_stats_clip.custom_minimum_size.x = wanted


## Marca a categoria da janela aberta ("" = nenhuma), sem repetir o evento.
func set_active(key: String) -> void:
	for k in category_buttons:
		category_buttons[k].set_pressed_no_signal(k == key)
