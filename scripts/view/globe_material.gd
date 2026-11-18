## O material do globo (globe.gdshader). É o único lugar que escreve nos uniforms: o resto pede por aqui.
## Mantém na memória só a camada que está na tela (cada PNG de 4096x2048 ocupa ~24 MB na RAM e outro tanto na GPU).

const GLOBE_SHADER = preload("res://shaders/globe.gdshader")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")

var material: ShaderMaterial
var height_texture: ImageTexture  # também usada pelos blocos (TileLayer), para o mesmo relevo
var layer_file := ""  # arquivo da camada carregada ("" = nenhuma)


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = GLOBE_SHADER


func set_height(height: Image) -> void:
	height_texture = ImageTexture.create_from_image(height)
	material.set_shader_parameter("height_map", height_texture)


## Reenvia a altitude editada para a GPU (a imagem inteira: 32 MiB). Os blocos usam a mesma textura.
## shortcut: sem atualização parcial de textura no Godot; se ficar lento, dividir a altitude em blocos editáveis.
func refresh_height(height: Image) -> void:
	height_texture.update(height)


# = uniform `mode` do globe.gdshader; "tiles" mostra a imagem de base enquanto os blocos (TileLayer) não cobrem
const MODES := {"image": 0, "altitude": 1, "natural": 2, "tiles": 0}


## Mostra a camada `layer` (uma entrada de MapLayers.LAYERS). A altitude calibrada não precisa de imagem.
func show_layer(layer: Dictionary) -> void:
	material.set_shader_parameter("mode", MODES[layer["kind"]])
	material.set_shader_parameter("nearest", layer.get("nearest", false))
	var file: String = layer.get("file", "")
	if file == "" or file == layer_file:
		return
	var img := EvronMaps.load_layer(file)
	if img == null:
		push_error("camada não encontrada: " + file)
		return
	var tex := ImageTexture.create_from_image(img)
	material.set_shader_parameter("layer_linear", tex)
	material.set_shader_parameter("layer_nearest", tex)
	layer_file = file
