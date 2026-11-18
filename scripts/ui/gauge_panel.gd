extends PanelContainer
## Marcador do clima do planeta, no canto superior direito: temperatura, pressão e estação.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Physics = preload("res://scripts/sim/mars_physics.gd")

var _temperature: Label
var _pressure: Label
var _atmosphere_top: Label
var _season: Label


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style())
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	position = Vector2(-12, 12)
	var box := VBoxContainer.new()
	add_child(box)
	_temperature = Label.new()
	_pressure = Label.new()
	_atmosphere_top = Label.new()
	_season = Label.new()
	for l in [_temperature, _pressure, _atmosphere_top, _season]:
		box.add_child(l)


## `greenhouse_c` e `veg_warming_c` são as parcelas do aquecimento que já estão em `temp_c`.
func show_climate(temp_c: float, greenhouse_c: float, veg_warming_c: float, atmosphere: float) -> void:
	_temperature.text = "Temperatura  %+d °C" % roundi(temp_c)
	if greenhouse_c > 0.5:
		_temperature.text += "  (estufa +%d)" % roundi(greenhouse_c)
	if veg_warming_c > 0.5:
		_temperature.text += "  (vegetação +%d)" % roundi(veg_warming_c)
	_pressure.text = "Pressão  %s mbar" % UiKit.format_mbar(Physics.pressure_mbar(atmosphere))
	_atmosphere_top.text = "Atmosfera até  %d km" % roundi(Physics.atmosphere_top_km(atmosphere))


## `seasons_on` false = o tempo está rápido demais e o clima usa só a média do ano.
func show_season(ls: float, seasons_on: bool) -> void:
	if seasons_on:
		_season.text = "%s (Ls %d°)" % [Physics.season_name(ls), roundi(ls)]
	else:
		_season.text = "Estações: média do ano (use 0.1x)"
