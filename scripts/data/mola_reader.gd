## Relevo real de Marte: MOLA (NASA PDS), altitude em metros. Só lê arquivos; não sabe nada do jogo.
##
## Fonte: 4 px/grau (~15 km), convertido por tools/convert_mola.py em float16 (.rh).

const MarsGeo = preload("res://scripts/data/mars_geo.gd")

# shortcut: arquivo .rh cru não entra no export do Godot sozinho; incluir "data/*" no filtro de export ao publicar.
const HEIGHT_PATH := "res://data/mars_height_1440x720.rh"
const HEIGHT_SIZE := Vector2i(1440, 720)


## Relevo global (FORMAT_RH, metros) de HEIGHT_SIZE pixels.
static func load_global_height() -> Image:
	var bytes := FileAccess.get_file_as_bytes(HEIGHT_PATH)
	return Image.create_from_data(HEIGHT_SIZE.x, HEIGHT_SIZE.y, false, Image.FORMAT_RH, bytes)


## Altitude em metros no ponto n, lida do mesmo mapa que o shader usa.
static func height_at(img: Image, n: Vector3) -> float:
	var ll := MarsGeo.lat_lon(n)
	var x := clampi(int((ll.y / 360.0 + 0.5) * img.get_width()), 0, img.get_width() - 1)
	var y := clampi(int((0.5 - ll.x / 180.0) * img.get_height()), 0, img.get_height() - 1)
	return img.get_pixel(x, y).r
