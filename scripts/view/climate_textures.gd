## Texturas do clima para os shaders. A simulação (Climate) não sabe nada de GPU: este é o único lugar que
## empacota as grades dela em imagens.
##
## climate_map (RGBAF): R nuvem, G chuva, B vegetação, A umidade do ar.
## wind_map    (RGBAF): R,G vento e B,A corrente oceânica (leste, norte), em células por segundo.
## weather_map (RGBAF): R chuva de agora (a de `climate_map` é a recente), G neve no chão, B frente (+ quente, - fria).
## temp_map    (RGBAF): R temperatura do ar (°C), G anomalia de temperatura do mar (°C), B nuvem fina (que não chove),
##                      A massa de ar (°C acima ou abaixo do equilíbrio do lugar).

const Climate = preload("res://scripts/sim/climate.gd")

var climate_map: ImageTexture
var wind_map: ImageTexture
var temp_map: ImageTexture
var weather_map: ImageTexture


func _init(c: Climate) -> void:
	climate_map = ImageTexture.create_from_image(_climate_image(c))
	wind_map = ImageTexture.create_from_image(_wind_image(c))
	temp_map = ImageTexture.create_from_image(_temp_image(c))
	weather_map = ImageTexture.create_from_image(_weather_image(c))


func update(c: Climate) -> void:
	climate_map.update(_climate_image(c))
	wind_map.update(_wind_image(c))
	temp_map.update(_temp_image(c))
	weather_map.update(_weather_image(c))


static func _climate_image(c: Climate) -> Image:
	var d := PackedFloat32Array()
	d.resize(Climate.N * 4)
	for i in Climate.N:
		d[i * 4] = c.cloud[i]
		d[i * 4 + 1] = c.rain[i]
		d[i * 4 + 2] = c.veg[i]
		d[i * 4 + 3] = c.q[i]
	return Image.create_from_data(Climate.W, Climate.H, false, Image.FORMAT_RGBAF, d.to_byte_array())


static func _wind_image(c: Climate) -> Image:
	var d := PackedFloat32Array()
	d.resize(Climate.N * 4)
	for i in Climate.N:
		d[i * 4] = c.wind_u[i]
		d[i * 4 + 1] = c.wind_v[i]
		d[i * 4 + 2] = c.cur_u[i]
		d[i * 4 + 3] = c.cur_v[i]
	return Image.create_from_data(Climate.W, Climate.H, false, Image.FORMAT_RGBAF, d.to_byte_array())


static func _temp_image(c: Climate) -> Image:
	var d := PackedFloat32Array()
	d.resize(Climate.N * 4)
	for i in Climate.N:
		d[i * 4] = c.temp_c[i]
		d[i * 4 + 1] = c.oa[i]
		d[i * 4 + 2] = c.haze[i]
		d[i * 4 + 3] = c.ta[i]
	return Image.create_from_data(Climate.W, Climate.H, false, Image.FORMAT_RGBAF, d.to_byte_array())


static func _weather_image(c: Climate) -> Image:
	var d := PackedFloat32Array()
	d.resize(Climate.N * 4)
	for i in Climate.N:
		d[i * 4] = c.raining[i]
		d[i * 4 + 1] = c.snow[i]
		d[i * 4 + 2] = c.front[i]
	return Image.create_from_data(Climate.W, Climate.H, false, Image.FORMAT_RGBAF, d.to_byte_array())
