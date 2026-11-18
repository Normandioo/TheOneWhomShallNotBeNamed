## O material de Marte (globe.gdshader): terreno, mares, gelo, nuvens e os modos de mapa. É o único lugar que
## escreve nos uniforms: o resto do jogo pede por aqui.

const GLOBE_SHADER = preload("res://shaders/globe.gdshader")
const ClimateTextures = preload("res://scripts/view/climate_textures.gd")
const Climate = preload("res://scripts/sim/climate.gd")

var globe: ShaderMaterial   # o material da esfera de Marte, compartilhado com a vista do espaço

var _textures: ClimateTextures
var _season_strength := 1.0  # força das estações desenhada nas calotas; segue a da simulação suavemente


func _init() -> void:
	globe = ShaderMaterial.new()
	globe.shader = GLOBE_SHADER


## Relevo global, o centro das regiões e as texturas iniciais do clima.
func setup(height_img: Image, region_dirs: PackedVector3Array, climate: Climate) -> void:
	set_param("height_map", ImageTexture.create_from_image(height_img))
	set_param("region_dirs", region_dirs)
	_textures = ClimateTextures.new(climate)
	set_param("climate_map", _textures.climate_map)
	set_param("wind_map", _textures.wind_map)
	set_param("temp_map", _textures.temp_map)
	set_param("weather_map", _textures.weather_map)


## Aplica um parâmetro ao material.
func set_param(param: String, value: Variant) -> void:
	globe.set_shader_parameter(param, value)


func set_map_mode(mode: int) -> void:
	set_param("map_mode", mode)


func set_region_colors(colors: PackedVector3Array) -> void:
	set_param("region_colors", colors)


func show_water(sea_level: float, ice: float) -> void:
	set_param("sea_level", sea_level)
	set_param("ice", ice)


func upload_climate(climate: Climate) -> void:
	_textures.update(climate)


## Calotas: crescem no inverno de cada polo; o máximo vem ~45° de Ls depois do solstício de inverno.
## `strength` (0..1) é a força das estações na simulação; a calota não pula ao trocar de velocidade.
func show_seasons(ls: float, strength: float, delta: float) -> void:
	_season_strength = move_toward(_season_strength, strength, delta)
	set_param("cap_season", -sin(deg_to_rad(ls - 45.0)) * _season_strength)
