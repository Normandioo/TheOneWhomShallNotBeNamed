## O material do globo (globe.gdshader). É o único lugar que escreve nos uniforms: o resto pede por aqui.
## Mantém na memória só a camada que está na tela (cada PNG de 4096x2048 ocupa ~24 MB na RAM e outro tanto na GPU).

const GLOBE_SHADER = preload("res://shaders/globe.gdshader")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")

var material: ShaderMaterial
var river_texture: ImageTexture
var political_texture: ImageTexture          # os donos de cada pixel (RG8)
var political_palette_texture: ImageTexture  # 256×256: a cor de cada país por id
var height_texture: ImageTexture  # também usada pelos blocos (TileLayer), para o mesmo relevo
var coast_texture: ImageTexture   # mapa político: distância à costa e lagos (Terrain.CoastImage)
var layer_file := ""  # arquivo da camada carregada ("" = nenhuma)


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = GLOBE_SHADER


func set_rivers(rivers: Image) -> void:
	river_texture = ImageTexture.create_from_image(rivers)
	material.set_shader_parameter("river_map", river_texture)


## Reenvia os rios editados para a GPU (4 MiB).
func refresh_rivers(rivers: Image) -> void:
	river_texture.update(rivers)


## A camada política (donos por pixel, RG8): vai para o parâmetro global que o globo e os blocos leem.
func set_political(owners: Image) -> void:
	political_texture = ImageTexture.create_from_image(owners)
	RenderingServer.global_shader_parameter_set("political_map", political_texture)


## Reenvia os donos editados para a GPU (a imagem inteira, 16 MiB).
func refresh_political(owners: Image) -> void:
	political_texture.update(owners)


## A paleta: entries = [{id, rgb}] (Registry.CountryPalette). Ids sem entrada ficam sem cor (alfa 0).
func set_political_palette(entries: Array) -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for e in entries:
		var id := int(e.id)
		var rgb := int(e.rgb)
		if id > 0 and id <= 65535:
			img.set_pixel(id & 255, id >> 8, Color8((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255, 255))
	if political_palette_texture == null:
		political_palette_texture = ImageTexture.create_from_image(img)
		RenderingServer.global_shader_parameter_set("political_palette", political_palette_texture)
	else:
		political_palette_texture.update(img)


## A costa do mapa político (RGH: km até a costa, lago). Cria a textura na primeira vez; depois só a atualiza.
func set_coast(coast: Image) -> void:
	if coast_texture == null:
		coast_texture = ImageTexture.create_from_image(coast)
		material.set_shader_parameter("coast_map", coast_texture)
	else:
		coast_texture.update(coast)


func show_political(on: bool) -> void:
	RenderingServer.global_shader_parameter_set("political_on", 1.0 if on else 0.0)


## Peso de julho (0 = só janeiro, 1 = só julho) da temperatura sazonal; vem de SeasonalTemperature.july_weight.
func set_season(july_weight: float) -> void:
	material.set_shader_parameter("season_july", july_weight)


## Carrega os dois mapas de °C e a escala magma na primeira vez que a camada sazonal aparece (2 × 32 MiB).
func _load_season() -> bool:
	if _season_loaded:
		return true
	var maps := EvronMaps.load_temperature()
	if maps.is_empty():
		return false
	material.set_shader_parameter("temp_jan", ImageTexture.create_from_image(maps["jan"]))
	material.set_shader_parameter("temp_jul", ImageTexture.create_from_image(maps["jul"]))
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(MapLayers.NINE)
	g.colors = PackedColorArray(MapLayers.MAGMA)
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	ramp.width = 256
	material.set_shader_parameter("temp_ramp", ramp)
	_season_loaded = true
	return true


func set_height(height: Image) -> void:
	height_texture = ImageTexture.create_from_image(height)
	material.set_shader_parameter("height_map", height_texture)


## Reenvia a altitude editada para a GPU (a imagem inteira: 32 MiB). Os blocos usam a mesma textura.
## shortcut: sem atualização parcial de textura no Godot; se ficar lento, dividir a altitude em blocos editáveis.
func refresh_height(height: Image) -> void:
	height_texture.update(height)


# = uniform `mode` do globe.gdshader; "tiles" mostra a imagem de base enquanto os blocos (TileLayer) não cobrem
const MODES := {"image": 0, "altitude": 1, "natural": 2, "tiles": 0, "season": 3, "political": 4}
const MapLayers = preload("res://scripts/ui/map_layers.gd")

var _season_loaded := false
var _satellite_loaded := false
var _satellite_optics: ImageTexture
var _satellite_river_atlas: ImageTexture


## Mostra a camada `layer` (uma entrada de MapLayers.LAYERS). A altitude calibrada não precisa de imagem.
func show_layer(layer: Dictionary) -> void:
	material.set_shader_parameter("mode", MODES[layer["kind"]])
	material.set_shader_parameter("nearest", layer.get("nearest", false))
	if layer["kind"] == "season" and not _load_season():
		push_error("temperatura sazonal: rode python tools/import_maps.py (faltam os mapas em °C)")
	var file: String = layer.get("file", "")
	if layer.has("fallback") and not FileAccess.file_exists(EvronMaps.DIR + file):
		file = layer["fallback"]
	if file == "" or file == layer_file:
		return
	var img := EvronMaps.load_layer(file)
	if img == null:
		push_error("camada não encontrada: " + file)
		return
	img.generate_mipmaps()  # de longe a camada não cintila (o shader escolhe o nível sem costura em 180°)
	var tex := ImageTexture.create_from_image(img)
	material.set_shader_parameter("layer_linear", tex)
	material.set_shader_parameter("layer_nearest", tex)
	layer_file = file
	if layer["kind"] == "natural" and file == layer["file"]:
		_load_satellite()


func _load_satellite() -> void:
	if _satellite_loaded:
		return
	_satellite_loaded = true
	if FileAccess.file_exists(EvronMaps.DIR + "natural_water.png"):
		var optics := EvronMaps.load_layer("natural_water.png")
		if optics != null:
			_satellite_optics = ImageTexture.create_from_image(optics)
			RenderingServer.global_shader_parameter_set("satellite_optics", _satellite_optics)
			RenderingServer.global_shader_parameter_set("satellite_optics_on", 1.0)
	var rivers := EvronMaps.load_satellite_rivers()
	if rivers != null:
		_satellite_river_atlas = ImageTexture.create_from_image(rivers)
		RenderingServer.global_shader_parameter_set("satellite_river_atlas", _satellite_river_atlas)
		RenderingServer.global_shader_parameter_set("satellite_rivers_on", 1.0)
