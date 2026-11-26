extends RefCounted
## O alto da tela: monta os números e os avisos do cadastro selecionado, leva cada botão de categoria à janela da esquerda e mantém
## só uma janela aberta por vez (a ficha, os Registros, os recursos ou os povoados). Não guarda dado do mundo: lê o que o DomainHub releu.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const UiIcons = preload("res://scripts/ui/ui_icons.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")

signal layout_changed

## categoria do alto -> página da ficha
const PAGE := {"ficha": "Ficha", "governo": "Governo", "povo": "Povo", "populacao": "População", "territorio": "Território", "calendarios": "Calendários"}
const COVERED := ["pais", "provincia", "municipio"]
const WORLD_COLOR := Color("#4f7d8c")
const NAME_LIMIT := 22

var alerts := HBoxContainer.new()  # os avisos do selecionado, sob o bloco do alto à direita (o Main o põe no HUD)
var paint_new := Callable()        # sem seleção, "Território" pinta uma região nova
var _top
var _hub
var _sheet
var _search
var _resources
var _resource_panel
var _production
var _settlement_panel
var _territories
var _summary := ""
var _data := {}  # {sheet, geo} do selecionado; vazio = nenhum
var _switching := false


func setup(top_hud, hub, search, resources, resource_panel, production, settlement_panel, territories) -> void:
	_top = top_hud
	_hub = hub
	_sheet = hub.sheet
	_search = search
	_resources = resources
	_resource_panel = resource_panel
	_production = production
	_settlement_panel = settlement_panel
	_territories = territories
	alerts.add_theme_constant_override("separation", 6)
	alerts.resized.connect(func() -> void: layout_changed.emit())
	_top.category_pressed.connect(press)
	_top.emblem_pressed.connect(func() -> void:
		if _hub.current() != 0:
			_show_page("Ficha"))
	_top.clear_pressed.connect(_hub.deselect)
	_search.summary_changed.connect(func(text: String) -> void:
		_summary = text
		if _data.is_empty():
			_show_world())
	_hub.sheet_loaded.connect(func(sheet: Dictionary, geo: Dictionary) -> void:
		_data = {"sheet": sheet, "geo": geo}
		_show_selection())
	_hub.selection_cleared.connect(func() -> void:
		_data = {}
		_show_world())
	for pair in [["sheet", _sheet], ["search", _search], ["resources", _resource_panel], ["settlements", _settlement_panel]]:
		pair[1].visibility_changed.connect(_on_window.bind(pair[0], pair[1]))
	_sheet.page_changed.connect(func(_page: String) -> void: _mark())
	_show_world()


## Um botão de categoria (ou um número do alto): abre a janela dele; apertar o da janela já aberta a fecha.
func press(key: String) -> void:
	match key:
		"recursos":
			_resources.set_open(not _resource_panel.visible)
		"economia":
			_production.set_open(not _settlement_panel.visible)
		_:
			var page: String = PAGE[key]
			if _hub.current() == 0:
				if key == "territorio" and paint_new.is_valid():
					paint_new.call()
				elif key == "calendarios":
					_search.calendars_requested.emit()
			elif _sheet.visible and _sheet.active_page() == page:
				_sheet.dismiss()
			elif key == "calendarios" and not _sheet.has_page(page):
				_search.calendars_requested.emit()
			else:
				_show_page(page)
	_mark()


## Abre ou fecha os Registros (o botão do alto e a tecla O).
func toggle_registry() -> void:
	_search.visible = not _search.visible


## Há uma janela aberta à esquerda?
func window_open() -> bool:
	return _sheet.visible or _search.visible or _resource_panel.visible or _settlement_panel.visible


func close_window() -> void:
	_sheet.dismiss() if _sheet.visible else null
	_search.visible = false
	_resources.set_open(false)
	_production.set_open(false)


func _show_page(page: String) -> void:
	_sheet.show_page(page)
	if _sheet.current_id() != _hub.current():
		_hub.refresh_sheet()


## Uma janela apareceu: as outras saem.
func _on_window(which: String, panel: Control) -> void:
	if not _switching and panel.visible:
		_switching = true
		if which != "sheet" and _sheet.visible:
			_sheet.dismiss()
		if which != "search":
			_search.visible = false
		if which != "resources" and _resource_panel.visible:
			_resources.set_open(false)
		if which != "settlements" and _settlement_panel.visible:
			_production.set_open(false)
		_switching = false
	_mark()
	layout_changed.emit()


func _mark() -> void:
	var active := ""
	if _resource_panel.visible:
		active = "recursos"
	elif _settlement_panel.visible:
		active = "economia"
	elif _sheet.visible:
		for key in PAGE:
			if PAGE[key] == _sheet.active_page():
				active = key
	_top.set_active(active)


# --- o que o alto mostra --------------------------------------------------------------------------------------------

func _show_world() -> void:
	var stats: Array = []
	if _summary != "":
		stats.append({"icon": "world", "text": _summary, "tip": "O mundo inteiro"})
	stats.append({"icon": "navigate", "text": "Clique num país no mapa", "tip": "Os números e as categorias passam a ser os do país clicado"})
	_top.show_info({"name": "Mundo", "color": WORLD_COLOR, "selected": false, "stats": stats,
		"enabled": {"territorio": true, "recursos": true, "economia": true, "calendarios": true}})
	_set_alerts([])
	_mark()


func _show_selection() -> void:
	var sheet: Dictionary = _data.sheet
	var geo: Dictionary = _data.geo
	var kind := String(sheet.kind)
	var covered := kind in COVERED
	var info: Dictionary = geo.get("territory", {})
	var color := Color("#6e86d8")
	if info.has("color"):
		var c := int(info.color)
		color = Color8((c >> 16) & 255, (c >> 8) & 255, c & 255)
	var enabled := {"ficha": true, "governo": true, "povo": covered, "populacao": true, "territorio": true,
		"recursos": true, "economia": true, "calendarios": true}
	_top.show_info({"name": String(sheet.name), "color": color, "selected": true, "enabled": enabled,
		"labels": {} if covered else {"governo": "Relações"}, "stats": _stats(sheet, geo, covered)})
	_set_alerts(_warnings(sheet, geo, covered))
	_mark()


func _stats(sheet: Dictionary, geo: Dictionary, covered: bool) -> Array:
	var out: Array = []
	var kind := String(sheet.kind)
	var area := float(geo.get("territory", {}).get("area_km2", 0.0))
	if covered:
		var pop: Dictionary = sheet.population
		out.append({"icon": "population", "key": "populacao", "tip": "População total na data mostrada", "warn": not pop.has_total,
			"text": _thousands(pop.total) if pop.has_total else "sem total"})
	else:
		out.append({"icon": "file", "key": "ficha", "tip": "Tipo do cadastro", "text": UiKit.entry_label(kind, String(sheet.get("label", "")))})
	if geo.has("territory"):
		out.append({"icon": "area", "key": "territorio", "tip": "Área do território: %s km²" % _thousands(area), "text": _area_text(area)})
	if not covered:
		return out
	if kind != "municipio":
		var count: int = geo.get("division", []).size()
		out.append({"icon": "government", "key": "territorio", "tip": "Subdivisões logo abaixo",
			"text": "%d %s" % [count, "divisão" if count == 1 else "divisões"]})
	var cities: int = geo.get("cities", []).size()
	out.append({"icon": "organization", "key": "populacao", "tip": "Cidades", "text": "%d cidade%s" % [cities, "" if cities == 1 else "s"]})
	var composition: Dictionary = geo.get("composition", {})
	for spec in [["cultura", "culture", "Maior cultura"], ["religiao", "religion", "Maior religião"], ["idioma", "language", "Idioma mais presente"]]:
		var rows: Array = composition.get(spec[0], [])
		if not rows.is_empty():
			var share := "%d%%" % roundi(float(rows[0].share) * 100.0)
			out.append({"icon": spec[1], "key": "povo", "tip": "%s (pela área no mapa): %s, %s" % [spec[2], rows[0].name, share],
				"text": "%s %s" % [_short(String(rows[0].name)), share]})
	return out


## O que falta no selecionado: [{text, key, count}].
func _warnings(sheet: Dictionary, geo: Dictionary, covered: bool) -> Array:
	var out: Array = []
	if not covered:
		return out
	if geo.has("territory") and float(geo.territory.get("area_km2", 0.0)) <= 0.0:
		out.append({"key": "territorio", "count": 0, "text": "Sem território pintado"})
	var provinces = _territories.layer("provincia") if _territories != null else null
	if String(sheet.kind) == "pais" and provinces != null:
		var empty: int = geo.get("division", []).filter(func(d): return String(d.kind) == "provincia" and int(d.id) <= 65535 and provinces.AreaKm2(int(d.id)) <= 0.0).size()
		if empty > 0:
			out.append({"key": "territorio", "count": empty, "text": "%d %s sem território" % [empty, "divisão" if empty == 1 else "divisões"]})
	var pop: Dictionary = sheet.population
	if not pop.has_total:
		out.append({"key": "populacao", "count": 0, "text": "Sem população total"})
	elif pop.outside < 0.0:
		out.append({"key": "populacao", "count": 0, "text": "As cidades passam do total em %s" % _thousands(-pop.outside)})
	return out


func _set_alerts(list: Array) -> void:
	for c in alerts.get_children():
		alerts.remove_child(c)
		c.queue_free()
	for a in list:
		var b := Button.new()
		b.icon = UiIcons.get_icon("warning", 20)
		b.text = str(a.count) if a.count > 0 else ""
		b.custom_minimum_size = Vector2(44, 40)
		b.tooltip_text = a.text
		b.add_theme_stylebox_override("normal", UiKit.metal_style(Color("#3a2c22"), 8, 4))
		b.add_theme_color_override("icon_normal_color", Color("#f2c46d"))
		b.add_theme_color_override("icon_hover_color", Color("#ffd98a"))
		var key: String = a.key
		b.pressed.connect(func() -> void: _show_page(PAGE[key]))
		alerts.add_child(b)
	alerts.reset_size.call_deferred()


static func _thousands(v: float) -> String:
	return LayerPanel._thousands(roundi(v))


static func _area_text(km2: float) -> String:
	if km2 <= 0.0:
		return "sem território"
	if km2 >= 1e6:
		return ("%.2f mi km²" % (km2 / 1e6)).replace(".", ",")
	return "%s km²" % _thousands(km2)


static func _short(text: String) -> String:
	return text if text.length() <= NAME_LIMIT else text.left(NAME_LIMIT - 1) + "…"
