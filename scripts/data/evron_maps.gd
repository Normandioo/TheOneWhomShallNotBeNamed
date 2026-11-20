## Os mapas de Evron em data/evron/ (importados de mapas.zip por tools/import_maps.py). Só lê arquivos.
## A pasta tem .gdignore: o Godot não importa as imagens, elas são lidas em tempo de execução e ficam sem perda.


const DIR := "res://data/evron/"
# shortcut: data/evron/ não entra no export (tem .gdignore); ao distribuir, ler de uma pasta do projeto do usuário.
const HEIGHT_FILE := "height_4096x2048.f32"
const HEIGHT_SIZE := Vector2i(4096, 2048)
# Temperatura média de janeiro e julho em °C (tools/build_temperature.py): mesma grade da altitude, NaN = sem dado,
# -20,0 = "-20 °C ou menos" (a escala do Gleba satura ali).
const TEMPERATURE_FILES := {"jan": "temperature_jan_4096x2048.f32", "jul": "temperature_jul_4096x2048.f32"}


## Os mapas foram importados? (sem eles o globo não tem o que mostrar)
static func available() -> bool:
	return FileAccess.file_exists(DIR + HEIGHT_FILE)


## Altitude em metros (FORMAT_RF), calibrada na importação: de -13.500 m a +9.103,4 m, mar em 0 m.
static func load_height() -> Image:
	var bytes := FileAccess.get_file_as_bytes(DIR + HEIGHT_FILE)
	return Image.create_from_data(HEIGHT_SIZE.x, HEIGHT_SIZE.y, false, Image.FORMAT_RF, bytes)


## Índice espacial e trechos dos rios em texels RGBA float32 (tools/build_rivers.py).
static func load_satellite_rivers() -> Image:
	var file := FileAccess.open(DIR + "rivers_indexed.rgbaf", FileAccess.READ)
	if file == null:
		return null
	var magic := file.get_32()
	var rows := file.get_32()
	const WIDTH := 1024
	if magic != 0x32525645 or rows < 512 or rows > 8192 or file.get_length() != 8 + WIDTH * rows * 16:
		push_warning("Índice dos rios inválido. Gere os dados com tools/build_rivers.py.")
		return null
	return Image.create_from_data(WIDTH, rows, false, Image.FORMAT_RGBAF, file.get_buffer(WIDTH * rows * 16))


## Os dois mapas de temperatura (FORMAT_RF, °C) ou {} se não foram gerados (rode tools/import_maps.py).
static func load_temperature() -> Dictionary:
	var out := {}
	for key in TEMPERATURE_FILES:
		if not FileAccess.file_exists(DIR + TEMPERATURE_FILES[key]):
			return {}
		var bytes := FileAccess.get_file_as_bytes(DIR + TEMPERATURE_FILES[key])
		out[key] = Image.create_from_data(HEIGHT_SIZE.x, HEIGHT_SIZE.y, false, Image.FORMAT_RF, bytes)
	return out


## Uma camada PNG de data/evron/ (por exemplo "Satelite.png"), ou null se o arquivo não existe.
static func load_layer(file: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(DIR + file))

