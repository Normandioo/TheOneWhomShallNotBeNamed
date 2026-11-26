extends RefCounted
## As opções do jogador e o que o jogo lembra entre sessões. Valem para o computador, não para o mundo: ficam num arquivo à parte do
## banco. Com o caminho vazio (testes) nada é lido nem gravado.

signal changed(key: String)

## O que o menu Opções mostra e "Restaurar padrões" devolve.
const OPTIONS := {
	"window_mode": "maximizada", "ui_scale": 1.0, "max_fps": 60, "vsync": true,
	"orbit_speed": 1.0, "zoom_speed": 1.0,
	"remember_overlays": true, "remember_map": true,
	"autosave_seconds": 30, "remember_hud": true, "tooltips": true,
	"offer_tool_tutorials": true,
}
## O que o jogo lembra por conta própria ("Restaurar padrões" não mexe).
const MEMORY := {
	"tutorial_asked": false, "seen_tools": [],
	"hud_minimized": false, "legend": true, "country_names": true, "rivers": false, "area_overlay": "",
	"map_layer": 0, "map_level": "pais", "map_subdivisions": false,
}

var path := ""
var _values := {}


func load_from(file_path: String) -> void:
	path = file_path
	_values = {}
	if path == "":
		return
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return  # primeira vez (ou arquivo estragado): os padrões
	for key in config.get_section_keys("evron") if config.has_section("evron") else []:
		var value = config.get_value("evron", key)
		if _default(key) != null and _same_kind(value, _default(key)):  # um valor de outro tipo (arquivo editado à mão) é ignorado
			_values[key] = value


func value(key: String):
	return _values.get(key, _default(key))


func set_value(key: String, v) -> void:
	if _default(key) == null or value(key) == v:
		return
	_values[key] = v
	_save()
	changed.emit(key)


func restore_defaults() -> void:
	for key in OPTIONS:
		set_value(key, OPTIONS[key])


func _default(key: String):
	return OPTIONS.get(key, MEMORY.get(key))


static func _same_kind(a, b) -> bool:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	return typeof(a) == typeof(b) or (typeof(a) in numbers and typeof(b) in numbers)


func _save() -> void:
	if path == "":
		return
	var config := ConfigFile.new()
	for key in _values:
		config.set_value("evron", key, _values[key])
	var error := config.save(path)
	if error != OK:
		push_warning("Não consegui gravar as opções em %s (erro %d)" % [path, error])
