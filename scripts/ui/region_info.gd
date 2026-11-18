## Texto sobre o ponto escolhido no mapa: região, coordenadas, altitude, pressão local e se é mar ou terra.

const MarsGeo = preload("res://scripts/data/mars_geo.gd")
const MolaReader = preload("res://scripts/data/mola_reader.gd")
const Physics = preload("res://scripts/sim/mars_physics.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")


## Retorna {"text": String, "region": int, "ocean": bool}.
static func describe(dir: Vector3, height_img: Image, sea_level: float, atmosphere: float) -> Dictionary:
	var ll := MarsGeo.lat_lon(dir)
	var region := MarsGeo.nearest_region(dir)
	var h := MolaReader.height_at(height_img, dir)
	var ocean := h < sea_level
	var p := Physics.pressure_mbar(Physics.local_atmosphere(atmosphere, maxf(h, sea_level)))
	var text := "%s\nLat %.1f°  Lon %.1f°\nAltitude: %d m\nPressão local: %s mbar\n%s" % [
		MarsGeo.REGIONS[region]["name"], ll.x, ll.y, roundi(h), UiKit.format_mbar(p), "Oceano" if ocean else "Terra firme"]
	return {"text": text, "region": region, "ocean": ocean}
