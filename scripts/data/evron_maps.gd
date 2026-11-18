## Os mapas de Evron em data/evron/ (importados de mapas.zip por tools/import_maps.py). Só lê arquivos.
## A pasta tem .gdignore: o Godot não importa as imagens, elas são lidas em tempo de execução e ficam sem perda.


const DIR := "res://data/evron/"
# shortcut: data/evron/ não entra no export (tem .gdignore); ao distribuir, ler de uma pasta do projeto do usuário.
const HEIGHT_FILE := "height_4096x2048.f32"
const HEIGHT_SIZE := Vector2i(4096, 2048)


## Os mapas foram importados? (sem eles o globo não tem o que mostrar)
static func available() -> bool:
	return FileAccess.file_exists(DIR + HEIGHT_FILE)


## Altitude em metros (FORMAT_RF), calibrada na importação: de -13.500 m a +9.103,4 m, mar em 0 m.
static func load_height() -> Image:
	var bytes := FileAccess.get_file_as_bytes(DIR + HEIGHT_FILE)
	return Image.create_from_data(HEIGHT_SIZE.x, HEIGHT_SIZE.y, false, Image.FORMAT_RF, bytes)


## Uma camada PNG de data/evron/ (por exemplo "Satelite.png"), ou null se o arquivo não existe.
static func load_layer(file: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(DIR + file))

