## O material do globo (globe.gdshader). É o único lugar que escreve nos uniforms: o resto pede por aqui.
## Mantém na memória só a camada que está na tela (cada PNG de 4096x2048 ocupa ~24 MB na RAM e outro tanto na GPU).

const GLOBE_SHADER = preload("res://shaders/globe.gdshader")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")

var material: ShaderMaterial
var river_texture: ImageTexture
var height_texture: ImageTexture  # também usada pelos blocos (TileLayer), para o mesmo relevo
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
const MODES := {"image": 0, "altitude": 1, "natural": 2, "tiles": 0, "season": 3}
const MapLayers = preload("res://scripts/ui/map_layers.gd")

var _season_loaded := false


## Mostra a camada `layer` (uma entrada de MapLayers.LAYERS). A altitude calibrada não precisa de imagem.
func show_layer(layer: Dictionary) -> void:
	material.set_shader_parameter("mode", MODES[layer["kind"]])
	material.set_shader_parameter("nearest", layer.get("nearest", false))
	if layer["kind"] == "season" and not _load_season():
		push_error("temperatura sazonal: rode python tools/import_maps.py (faltam os mapas em °C)")
	var file: String = layer.get("file", "")
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
