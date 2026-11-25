extends SceneTree
## Preenche o mundo do usuário: províncias para todos os países (os que já têm província ficam como estão) e cobre a terra com religiões,
## culturas, etnias, raças e idiomas (só onde a camada ainda não tem dono: o que já foi pintado fica). Os nomes são inventados, com semente fixa.
## Rodar com o jogo FECHADO (ele guarda o território na memória e gravaria por cima):
##   godot --headless --path . -s tools/mundo_completo.gd
##   ... -- banco=<arquivo.db>    usa outro banco (por exemplo, uma cópia para testar)

const EvronMaps = preload("res://scripts/data/evron_maps.gd")
const DB := "user://evron_world.db"
const KM2_PER_PROVINCE := 60000.0  # uma província a cada ~60 mil km² (raiz do que sobra: 3 a 16 por país)
const AREAS := {"religiao": 16, "cultura": 45, "etnia": 70, "raca": 8, "idioma": 55}
const SYL_A := ["ka", "ra", "mo", "ven", "al", "tor", "sa", "el", "dun", "mir", "or", "han", "ti", "bel", "zar", "lu", "gra", "nor", "ys", "quo", "fen", "dra", "ul", "mar", "tev", "ash", "ire", "kos", "pel", "vor"]
const SYL_B := ["a", "o", "e", "i", "an", "or", "en", "ia", "ul", "ar", "is", "um", "el", "on"]
const END := ["", "ia", "land", "mark", "heim", "ora", "esh", "uan", "ire", "os", "ar", "ia", "ov", "ado"]

var _rng := RandomNumberGenerator.new()
var _used := {}


func _initialize() -> void:
	var path := ProjectSettings.globalize_path(DB)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("banco="):
			path = arg.trim_prefix("banco=")
	_rng.seed = 20261123
	var reg = load("res://scripts/world/Registry.cs").new()
	reg.Open(path)
	if not reg.IsOpen():
		push_error("o banco não abriu: " + path)
		quit(1)
		return
	var terrain = load("res://scripts/world/Terrain.cs").new()
	terrain.Setup(EvronMaps.load_height())
	terrain.SetLakes(EvronMaps.load_layer("Waterbodies.png"))
	var layers := {}
	for level in ["pais", "provincia"] + AREAS.keys():
		var t = load("res://scripts/world/Territory.cs").new()
		t.Setup(terrain)
		reg.LoadTerritoryLevel(level, t)
		layers[level] = t
	for id in reg.Palette("pais"):
		_used[String(reg.Name(int(id.id)))] = true
	var t0 := Time.get_ticks_msec()
	var provinces := _provinces(reg, layers)
	var made := {}
	for level in AREAS:
		made[level] = _area(reg, layers[level], level, int(AREAS[level]))
	var save := {"provincia": layers["provincia"]}
	for level in AREAS:
		save[level] = layers[level]
	var ok: bool = reg.SaveTerritoryLevels(save)
	print("%d províncias; áreas: %s; gravado=%s; %d ms" % [provinces, made, ok, Time.get_ticks_msec() - t0])
	reg.Close()
	quit(0 if ok else 1)


## Cria as províncias dos países que ainda não têm nenhuma. Devolve quantas criou.
func _provinces(reg, layers: Dictionary) -> int:
	var has := {}
	for p in reg.Palette("provincia"):
		if layers["provincia"].AreaKm2(int(p.id)) > 0.0:
			has[int(reg.TerritoryParent(int(p.id)))] = true
	var created := 0
	for c in reg.Palette("pais"):
		var id := int(c.id)
		var area: float = layers["pais"].AreaKm2(id)
		if has.has(id) or area <= 0.0:
			continue
		var n := clampi(roundi(sqrt(area / KM2_PER_PROVINCE) * 1.4), 3, 16)
		var ids := PackedInt32Array()
		for i in n:
			var made = reg.Create("provincia", _name(""))
			reg.Link(int(made), id, "provincia_de")
			ids.append(int(made))
		layers["provincia"].Partition(layers["pais"], id, ids, id)
		created += n
	return created


func _area(reg, layer, level: String, count: int) -> int:
	var ids := PackedInt32Array()
	for i in count:
		ids.append(int(reg.Create(level, _name(level))))
	layer.FillLand(ids, hash(level))
	return count


func _name(level: String) -> String:
	for _i in 50:
		var stem: String = SYL_A[_rng.randi() % SYL_A.size()] + SYL_B[_rng.randi() % SYL_B.size()]
		if _rng.randf() < 0.55:
			stem += SYL_A[_rng.randi() % SYL_A.size()]
		stem = stem.capitalize() + END[_rng.randi() % END.size()]
		var text := stem
		match level:
			"religiao": text = ["Culto de %s", "Fé %s", "Via de %s"][_rng.randi() % 3] % stem
			"etnia": text = "Povo " + stem
			"raca": text = "Linhagem " + stem
			"idioma": text = "Língua " + stem
			"cultura": text = "Cultura " + stem
			"": text = stem
		if not _used.has(text):
			_used[text] = true
			return text
	return "Sem nome %d" % _used.size()
