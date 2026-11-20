## Os mapas de Evron em data/evron/ (importados de mapas.zip por tools/import_maps.py). Só lê arquivos.
## A pasta tem .gdignore: o Godot não importa as imagens, elas são lidas em tempo de execução e ficam sem perda.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")

const DIR := "res://data/evron/"
# shortcut: data/evron/ não entra no export (tem .gdignore); ao distribuir, ler de uma pasta do projeto do usuário.
const HEIGHT_FILE := "height_4096x2048.f32"
const HEIGHT_SIZE := Vector2i(4096, 2048)
const RIVERS_FILE := "rivers_8192x4096.rgh"  # tools/build_rivers.py
const RIVERS_SIZE := Vector2i(8192, 4096)


## Os mapas foram importados? (sem eles o globo não tem o que mostrar)
static func available() -> bool:
	return FileAccess.file_exists(DIR + HEIGHT_FILE)


## Altitude em metros (FORMAT_RF), calibrada na importação: de -13.500 m a +9.103,4 m, mar em 0 m.
static func load_height() -> Image:
	var bytes := FileAccess.get_file_as_bytes(DIR + HEIGHT_FILE)
	return Image.create_from_data(HEIGHT_SIZE.x, HEIGHT_SIZE.y, false, Image.FORMAT_RF, bytes)


## Rios (tools/build_rivers.py): vetor em km (leste, norte) até a linha central do rio mais próximo (FORMAT_RGH),
## ou null se o arquivo não existe. A largura de cada rio está em rivers_width.png (load_layer).
static func load_rivers() -> Image:
	if not FileAccess.file_exists(DIR + RIVERS_FILE):
		return null
	var bytes := FileAccess.get_file_as_bytes(DIR + RIVERS_FILE)
	return Image.create_from_data(RIVERS_SIZE.x, RIVERS_SIZE.y, false, Image.FORMAT_RGH, bytes)


## Uma camada PNG de data/evron/ (por exemplo "Satelite.png"), ou null se o arquivo não existe.
static func load_layer(file: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(DIR + file))


## Altitude em metros na direção n, lida do mesmo mapa que o shader usa.
static func height_at(img: Image, n: Vector3) -> float:
	var p := EvronGeo.pixel(n, img.get_size())
	return img.get_pixel(p.x, p.y).r


## Índice espacial e trechos dos rios em texels RGBA float32 (tools/build_indexed_rivers.py).
static func load_satellite_rivers() -> Image:
	var file := FileAccess.open(DIR + "rivers_indexed.rgbaf", FileAccess.READ)
	if file == null:
		return null
	var magic := file.get_32()
	var rows := file.get_32()
	const WIDTH := 1024
	if magic != 0x32525645 or rows < 512 or rows > 8192 or file.get_length() != 8 + WIDTH * rows * 16:
		push_warning("Índice dos rios inválido. Gere os dados com tools/build_indexed_rivers.py.")
		return null
	return Image.create_from_data(WIDTH, rows, false, Image.FORMAT_RGBAF, file.get_buffer(WIDTH * rows * 16))
