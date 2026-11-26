## O material do globo (globe.gdshader). É o único lugar que escreve nos uniforms: o resto pede por aqui.
## Mantém na memória apenas as texturas da camada ativa. Os mosaicos fornecem o detalhe de perto.

const GLOBE_SHADER = preload("res://shaders/globe.gdshader")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")

var _satellite_loaded := false
var _wall_textures: Array = []  # o índice e os trechos das linhas na GPU (precisam continuar vivos)
var _satellite_optics: ImageTexture
var _satellite_river_atlas: ImageTexture
const EMPTY_MAP_TEXTURE = preload("res://shaders/political_default.tres")

var material: ShaderMaterial
var river_texture: ImageTexture
var area_texture: ImageTexture               # a área (cultura, etnia...) por cima do mapa político: donos por pixel (RG8)
var area_palette_texture: ImageTexture       # 256×256: a cor de cada área por id
var political_texture: ImageTexture          # os donos de cada pixel (RG8)
var political_palette_texture: ImageTexture  # 256×256: a cor de cada país por id
var political_top_texture: ImageTexture      # 256×256 RG8: o país de cada id (a província aponta para o país)
var height_texture: ImageTexture  # também usada pelos blocos (TileLayer), para o mesmo relevo
var coast_texture: ImageTexture   # mapa político: distância à costa e lagos (Terrain.CoastImage)
var _river_highlight := false  # a sobreposição "Rios em destaque" está ligada (usa o atlas de rios do satélite)
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


## A camada de área (cultura, etnia, raça, religião, idioma) mostrada sobre os países.
func set_area(owners: Image) -> void:
	if area_texture == null:
		area_texture = ImageTexture.create_from_image(owners)
		RenderingServer.global_shader_parameter_set("area_map", area_texture)
	else:
		area_texture.update(owners)


## A paleta das áreas: entries = [{id, rgb}].
func set_area_palette(entries: Array) -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for e in entries:
		var id := int(e.id)
		var rgb := int(e.rgb)
		if id > 0 and id <= 65535:
			img.set_pixel(id & 255, id >> 8, Color8((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255, 255))
	if area_palette_texture == null:
		area_palette_texture = ImageTexture.create_from_image(img)
		RenderingServer.global_shader_parameter_set("area_palette", area_palette_texture)
	else:
		area_palette_texture.update(img)


## gray: o mapa de baixo são os países (ficam cinzas).
func show_area(on: bool, gray := false) -> void:
	RenderingServer.global_shader_parameter_set("area_on", 1.0 if on else 0.0)
	RenderingServer.global_shader_parameter_set("area_gray", 1.0 if gray else 0.0)


## Reenvia os donos editados para a GPU (a imagem inteira, 16 MiB).
func refresh_political(owners: Image) -> void:
	political_texture.update(owners)


## A paleta: entries = [{id, rgb, top}] (top: o país de uma província; sem top = o próprio id). Ids sem entrada ficam sem cor (alfa 0).
func set_political_palette(entries: Array) -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var tops := Image.create(256, 256, false, Image.FORMAT_RG8)
	for e in entries:
		var id := int(e.id)
		var rgb := int(e.rgb)
		var top := int(e.get("top", id))
		if id > 0 and id <= 65535:
			img.set_pixel(id & 255, id >> 8, Color8((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255, 255))
			tops.set_pixel(id & 255, id >> 8, Color8(top & 255, (top >> 8) & 255, 0, 255))
	if political_palette_texture == null:
		political_palette_texture = ImageTexture.create_from_image(img)
		political_top_texture = ImageTexture.create_from_image(tops)
		RenderingServer.global_shader_parameter_set("political_palette", political_palette_texture)
		RenderingServer.global_shader_parameter_set("political_top", political_top_texture)
	else:
		political_palette_texture.update(img)
		political_top_texture.update(tops)


## As linhas do pincel de fronteira (Territory.Walls): a borda do mapa sai em cima delas.
func set_walls(walls: Dictionary) -> void:
	if int(walls.get("count", 0)) == 0:
		RenderingServer.global_shader_parameter_set("wall_on", 0.0)
		return
	_wall_textures = [ImageTexture.create_from_image(walls.index), ImageTexture.create_from_image(walls.segments)]
	RenderingServer.global_shader_parameter_set("wall_index", _wall_textures[0])
	RenderingServer.global_shader_parameter_set("wall_segments", _wall_textures[1])
	RenderingServer.global_shader_parameter_set("wall_on", 1.0)


## O país (ou o topo) selecionado na ficha fica destacado no mapa; 0 = nenhum.
func set_political_selected(id: int) -> void:
	RenderingServer.global_shader_parameter_set("political_selected", id)


## A costa do mapa político (RGH: km até a costa, lago). Cria a textura na primeira vez; depois só a atualiza.
func set_coast(coast: Image) -> void:
	if coast_texture == null:
		coast_texture = ImageTexture.create_from_image(coast)
		RenderingServer.global_shader_parameter_set("coast_map", coast_texture)  # global: o globo, os blocos e a camada política leem a mesma costa
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


## Mostra a camada `layer` (uma entrada de MapLayers.LAYERS). A altitude calibrada não precisa de imagem.
func show_layer(layer: Dictionary) -> void:
	material.set_shader_parameter("mode", MODES[layer["kind"]])
	material.set_shader_parameter("nearest", layer.get("nearest", false))
	if layer["kind"] == "season" and not _load_season():
		push_error("temperatura sazonal: rode python tools/import_maps.py (faltam os mapas em °C)")
	var file: String = layer.get("file", "")
	if layer.has("fallback") and not FileAccess.file_exists(EvronMaps.directory() + file):
		file = layer["fallback"]
	var experimental := file == "natural_satellite.png"
	material.set_shader_parameter("experimental", experimental)
	if not experimental and _satellite_loaded:
		_unload_satellite()
	if layer["kind"] != "natural" or experimental:
		if material.get_shader_parameter("rivers_on"):
			material.set_shader_parameter("rivers_on", false)
			material.set_shader_parameter("river_offset", null)
			material.set_shader_parameter("river_width", null)
	if file == "":
		material.set_shader_parameter("layer_linear", null)
		material.set_shader_parameter("layer_nearest", null)
		layer_file = ""
		return
	if file == layer_file:
		return
	var img := EvronMaps.load_layer(file)
	if img == null:
		push_error("camada não encontrada: " + file)
		return
	if layer["kind"] == "natural":
		var pyramid: String = layer.get("tiles", "")
		if img.get_width() > 4096 and pyramid != "" and FileAccess.file_exists(
				EvronMaps.directory() + "tiles/" + pyramid + "/manifest.json"):
			img.resize(4096, 2048, Image.INTERPOLATE_BILINEAR)
		if experimental:
			_load_satellite()
		else:
			_load_rivers()
	img.generate_mipmaps()  # de longe a camada não cintila (o shader escolhe o nível sem costura em 180°)
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


## "Rios em destaque": liga ou desliga a sobreposição de rios em todas as camadas. Usa os mesmos trechos de rio do satélite experimental (o atlas de
## tools/build_indexed_rivers.py, uns 80 MB), carregados ao ligar e soltos ao desligar se o satélite experimental não estiver na tela.
## Devolve false se o arquivo não existe.
func set_river_highlight(on: bool) -> bool:
	_river_highlight = on
	if on:
		if _satellite_river_atlas == null:
			var rivers := EvronMaps.load_satellite_rivers()
			if rivers == null:
				_river_highlight = false
				push_warning("rios não encontrados em data/evron/: rode python tools/build_indexed_rivers.py")
				return false
			_satellite_river_atlas = ImageTexture.create_from_image(rivers)
		RenderingServer.global_shader_parameter_set("satellite_river_atlas", _satellite_river_atlas)
		RenderingServer.global_shader_parameter_set("river_hl_on", 1.0)
		return true
	RenderingServer.global_shader_parameter_set("river_hl_on", 0.0)
	if not _satellite_loaded:
		RenderingServer.global_shader_parameter_set("satellite_river_atlas", EMPTY_MAP_TEXTURE)
		_satellite_river_atlas = null
	return true


func _load_satellite() -> void:
	if _satellite_loaded:
		return
	_satellite_loaded = true
	if FileAccess.file_exists(EvronMaps.directory() + "natural_water.png"):
		var optics := EvronMaps.load_layer("natural_water.png")
		if optics != null:
			_satellite_optics = ImageTexture.create_from_image(optics)
			RenderingServer.global_shader_parameter_set("satellite_optics", _satellite_optics)
			RenderingServer.global_shader_parameter_set("satellite_optics_on", 1.0)
	if _satellite_river_atlas == null:
		var rivers := EvronMaps.load_satellite_rivers()
		if rivers != null:
			_satellite_river_atlas = ImageTexture.create_from_image(rivers)
	if _satellite_river_atlas != null:
		RenderingServer.global_shader_parameter_set("satellite_river_atlas", _satellite_river_atlas)
		RenderingServer.global_shader_parameter_set("satellite_rivers_on", 1.0)


func _unload_satellite() -> void:
	RenderingServer.global_shader_parameter_set("satellite_optics_on", 0.0)
	RenderingServer.global_shader_parameter_set("satellite_rivers_on", 0.0)
	RenderingServer.global_shader_parameter_set("satellite_optics", EMPTY_MAP_TEXTURE)
	if not _river_highlight:  # com os rios em destaque ligados o atlas continua: é o mesmo
		RenderingServer.global_shader_parameter_set("satellite_river_atlas", EMPTY_MAP_TEXTURE)
		_satellite_river_atlas = null
	_satellite_optics = null
	_satellite_river_atlas = null
	_satellite_loaded = false
