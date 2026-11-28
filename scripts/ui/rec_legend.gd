extends PanelContainer
## A legenda do modo de mapa Rec, acima dos modos de mapa: um recurso por linha (ícone da categoria na cor dele e quantos lugares tem),
## com a caixa que o mostra ou esconde, e Todos/Nenhum. Só mostra e pede: quem desenha é o resource_controller.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")
const ResourcePanel = preload("res://scripts/ui/resource_panel.gd")

signal shown_changed(id: int, shown: bool)

const WIDTH := 240

var rows: VBoxContainer
var checks := {}  # tipo -> CheckBox
var _key := ""


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", UiKit.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var title := Label.new()
	title.text = "RECURSOS NO MAPA"
	UiKit.style_heading(title)
	title.add_theme_font_size_override("font_size", 13)
	box.add_child(title)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	box.add_child(rows)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	for pair in [["Todos", true], ["Nenhum", false]]:
		var b := Button.new()
		b.text = pair[0]
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func() -> void:
			for id in checks.keys():
				if checks.has(id) and checks[id].button_pressed != pair[1]:
					checks[id].button_pressed = pair[1])
		actions.add_child(b)
	var note := Label.new()
	note.text = "Clique num lugar do mapa para abrir o recurso. Os fabricados ficam nos povoados."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = WIDTH - 24
	note.add_theme_font_size_override("font_size", 12)
	note.modulate.a = 0.7
	box.add_child(note)


## entries: as linhas de Registry.ResourceTypes que estão no mapa; hidden: tipo -> true.
func show_entries(entries: Array, hidden: Dictionary) -> void:
	var key := var_to_str(entries.map(func(t): return [t.id, t.name, t.count, t.rgb, t.category]))
	if key == _key:  # as mesmas linhas: só as caixas (refazer as linhas no meio de um clique perderia o botão clicado)
		for id in checks:
			checks[id].set_pressed_no_signal(not hidden.has(id))
		return
	_key = key
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	checks.clear()
	for t in entries:
		var id := int(t.id)
		var check := CheckBox.new()
		check.button_pressed = not hidden.has(id)
		check.text = "%s · %d" % [t.name, t.count]
		check.tooltip_text = "Mostrar %s no mapa" % t.name
		check.icon = UiIcons.get_icon(ResourcePanel.CATEGORY_ICON.get(t.category, "resources"), 16)
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
			check.add_theme_color_override(state, ResourcePanel._color(int(t.rgb)))
		check.clip_text = true
		check.toggled.connect(func(on: bool) -> void: shown_changed.emit(id, on))
		rows.add_child(check)
		checks[id] = check
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "Nenhum recurso no mapa ainda."
		empty.add_theme_font_size_override("font_size", 13)
		rows.add_child(empty)
