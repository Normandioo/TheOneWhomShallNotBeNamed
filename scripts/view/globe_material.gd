## O material do globo (globe.gdshader). É o único lugar que escreve nos uniforms: o resto pede por aqui.
## Mantém na memória só a camada que está na tela (cada PNG de 4096x2048 ocupa ~24 MB na RAM e outro tanto na GPU;
## a cor natural, 8192x4096 RGBA com mipmaps, ~170 MB, mais os rios: 128 MB + 32 MB, carregados uma vez).

const GLOBE_SHADER = preload("res://shaders/globe.gdshader")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")

var _satellite_loaded := false
var _satellite_optics: ImageTexture
var _satellite_river_atlas: ImageTexture

var material: ShaderMaterial
var height_texture: ImageTexture  # também usada pelos blocos (TileLayer), para o mesmo relevo
var layer_file := ""  # arquivo da camada carregada ("" = nenhuma)


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = GLOBE_SHADER


func set_height(height: Image) -> void:
	height_texture = ImageTexture.create_from_image(height)
	material.set_shader_parameter("height_map", height_texture)


# = uniform `mode` do globe.gdshader; "tiles" mostra a imagem de base enquanto os blocos (TileLayer) não cobrem
const MODES := {"image": 0, "altitude": 1, "natural": 2, "tiles": 0}


## Mostra a camada `layer` (uma entrada de MapLayers.LAYERS). A altitude calibrada não precisa de imagem.
func show_layer(layer: Dictionary) -> void:
	material.set_shader_parameter("mode", MODES[layer["kind"]])
	material.set_shader_parameter("nearest", layer.get("nearest", false))
	var file: String = layer.get("file", "")
	var experimental := file == "natural_satellite.png"
	material.set_shader_parameter("experimental", experimental)
	if experimental:
		_load_satellite()
	if file == "" or file == layer_file:
		return
	var img := EvronMaps.load_layer(file)
	if img == null:
		push_error("camada não encontrada: " + file)
		return
	if layer["kind"] == "natural":
		img.generate_mipmaps()  # 8K num disco de ~700 px: sem mipmaps a imagem cintila ao girar
		if not experimental:
			_load_rivers()
	var tex := ImageTexture.create_from_image(img)
	material.set_shader_parameter("layer_linear", tex)
	material.set_shader_parameter("layer_nearest", tex)
	layer_file = file


## Os rios com largura em metros (só na cor natural). Sem mipmaps: a média de vetores de lados opostos do rio daria
## zero e pintaria água onde não há; de longe o shader afina a linha pelo tamanho do pixel.
func _load_rivers() -> void:
	if material.get_shader_parameter("rivers_on"):
		return
	var off := EvronMaps.load_rivers()
	var width := EvronMaps.load_layer("rivers_width.png")
	if off == null or width == null:
		push_warning("rios não encontrados em data/evron/: rode python tools/build_rivers.py")
		return
	material.set_shader_parameter("river_offset", ImageTexture.create_from_image(off))
	material.set_shader_parameter("river_width", ImageTexture.create_from_image(width))
	material.set_shader_parameter("rivers_on", true)


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
