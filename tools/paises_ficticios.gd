extends SceneTree
## Põe no banco do usuário os 424 países fictícios do protótipo (data/evron/politico/paises.json, de `python tools/mapa_politico.py paises`):
## nome, nome oficial, cor, capital e o território crescido pelas fronteiras naturais (só na terra sem dono: o que já foi pintado fica).
## Todos levam a etiqueta "fictício". Rodar com o jogo FECHADO (ele guarda o território na memória e gravaria por cima):
##   godot --headless --path . -s tools/paises_ficticios.gd              cria
##   godot --headless --path . -s tools/paises_ficticios.gd -- remover   apaga os países, as capitais e o território deles
##   ... -- banco=<arquivo.db>                                            usa outro banco (por exemplo, uma cópia para testar)

const EvronMaps = preload("res://scripts/data/evron_maps.gd")
const TAG := "fictício"
const DB := "user://evron_world.db"
const JSON_FILE := "res://data/evron/politico/paises.json"
const REACH_KM := 2500.0   # alcance do crescimento: cobre as serras (com 1.500 km as mais altas ficam sem dono)
const NOW := 9223372036854775806  # "o que não tem fim": as presenças sem prazo valem


func _initialize() -> void:
	var path := ProjectSettings.globalize_path(DB)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("banco="):  # outro arquivo (para testar numa cópia)
			path = arg.trim_prefix("banco=")
	var reg = load("res://scripts/world/Registry.cs").new()
	reg.Open(path)
	if not reg.IsOpen():
		push_error("o banco não abriu: " + path)
		quit(1)
		return
	var terrain = load("res://scripts/world/Terrain.cs").new()
	terrain.Setup(EvronMaps.load_height())
	terrain.SetLakes(EvronMaps.load_layer("Waterbodies.png"))
	var territory = load("res://scripts/world/Territory.cs").new()
	territory.Setup(terrain)
	territory.SetRiverFlow(EvronMaps.load_layer("Waterflow.png"))
	reg.LoadTerritory(territory)
	var ok: bool = _remove(reg, territory) if "remover" in OS.get_cmdline_user_args() else _add(reg, territory)
	if ok:
		reg.SaveTerritory(territory)
	reg.Close()
	quit(0 if ok else 1)


func _add(reg, territory) -> bool:
	if not reg.Search("", "pais", TAG, 0, NOW).is_empty():
		push_error("já há países fictícios no banco: rode com '-- remover' antes de criar de novo")
		return false
	var rows = JSON.parse_string(FileAccess.get_file_as_string(JSON_FILE))
	if rows == null:
		push_error("faltou %s: rode python tools/mapa_politico.py paises" % JSON_FILE)
		return false
	var owners := PackedInt32Array()
	var lats := PackedFloat64Array()
	var lons := PackedFloat64Array()
	for r in rows:
		var id: int = reg.Create("pais", r.nome)
		reg.AddName(id, r.oficial, "oficial", 0)
		reg.AddTag(id, TAG)
		reg.SetEntityColor(id, Color(r.cor).to_rgba32() >> 8)
		reg.AddPresence(id, reg.AddPlace(r.capital, "assentamento", r.lat, r.lon, 0.0, TAG), "capital", "media")
		owners.append(id)
		lats.append(r.lat)
		lons.append(r.lon)
	var t0 := Time.get_ticks_msec()
	var edit = territory.Grow(owners, lats, lons, 0, REACH_KM)
	print("%d países fictícios criados; território: %d pixels em %d ms" % [owners.size(), edit.Count if edit != null else 0, Time.get_ticks_msec() - t0])
	return true


func _remove(reg, territory) -> bool:
	var ids := PackedInt32Array()
	var places: Array = []
	var rows: Array = reg.Search("", "pais", TAG, 0, NOW)
	while not rows.is_empty():  # a busca devolve até 200 por vez
		for r in rows:
			for p in reg.PresencesOf(r.id, NOW):
				reg.DeletePresence(p.id)
				if not places.has(p.place_id):
					places.append(p.place_id)
			ids.append(r.id)
			reg.Delete(r.id)
		rows = reg.Search("", "pais", TAG, 0, NOW)
	for p in places:
		var place = reg.Place(p)
		if place != null and place.note == TAG:  # só as capitais criadas aqui
			reg.DeletePlace(p)
	territory.ClearOwners(ids)
	print("%d países fictícios apagados (e %d capitais)" % [ids.size(), places.size()])
	return true
