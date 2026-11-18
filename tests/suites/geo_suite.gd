extends "res://tests/test_suite.gd"
## Geografia e mapas de Evron, sem cena: conversões, distâncias, a altitude calibrada e as camadas.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")


func run() -> void:
	# lat/lon -> direção -> lat/lon, inclusive perto do limite de longitude e dos polos.
	for ll in [Vector2(0, 0), Vector2(45.5, -179.9), Vector2(-89.0, 179.9), Vector2(-12.3, 77.7)]:
		var back := EvronGeo.lat_lon(EvronGeo.dir(ll.x, ll.y))
		if back.distance_to(ll) > 1e-3:
			return fail("ida e volta lat/lon: %s virou %s" % [ll, back])
	# Pixel: coluna 0 = -180°, linha 0 = polo norte; o limite de longitude dá a volta.
	var size := Vector2i(4096, 2048)
	if EvronGeo.pixel(EvronGeo.dir(89.99, -179.99), size) != Vector2i(0, 0):
		return fail("canto (90N, 180O) deveria ser o pixel (0,0): %s" % EvronGeo.pixel(EvronGeo.dir(89.99, -179.99), size))
	if EvronGeo.pixel(EvronGeo.dir(0.0, 179.99), size).x != 4095:
		return fail("lon 179,99° deveria ser a última coluna")
	# Distância: um quarto de volta pelo equador = 2πR/4 ≈ 13.010 km; e cruza o limite de longitude sem pular.
	var quarter := EvronGeo.distance_km(EvronGeo.dir(0, 0), EvronGeo.dir(0, 90))
	if absf(quarter - TAU * EvronGeo.RADIUS_KM / 4.0) > 0.01:
		return fail("um quarto do equador deveria ter %.1f km, deu %.1f" % [TAU * EvronGeo.RADIUS_KM / 4.0, quarter])
	if absf(EvronGeo.distance_km(EvronGeo.dir(0, 179.5), EvronGeo.dir(0, -179.5)) - EvronGeo.KM_PER_DEG) > 0.01:
		return fail("1° atravessando 180° deveria ter %.1f km" % EvronGeo.KM_PER_DEG)
	ok("lat/lon, pixel e distância (raio 8.282,3 km; 1° = %.1f km), inclusive no limite de longitude" % EvronGeo.KM_PER_DEG)

	if not EvronMaps.available():
		return fail("mapas não importados: rode tools/import_maps.py")
	var h := EvronMaps.load_height()
	var mn := INF
	var mx := -INF
	for y in range(0, h.get_height(), 4):
		for x in range(0, h.get_width(), 4):
			var v := h.get_pixel(x, y).r
			mn = minf(mn, v)
			mx = maxf(mx, v)
	if mn > -12000.0 or mx < 8000.0 or mn < -13500.5 or mx > 9103.5:
		return fail("altitude fora da calibração (-13.500 a +9.103 m): %.0f a %.0f" % [mn, mx])
	ok("altitude calibrada carregada: %.0f a %.0f m (amostra 1/16)" % [mn, mx])

	# Todo arquivo citado nas camadas existe.
	for l in MapLayers.LAYERS:
		var file: String = l.get("file", "")
		if file != "" and not FileAccess.file_exists(EvronMaps.DIR + file):
			return fail("camada sem arquivo: " + file)
	ok("%d camadas, todas com arquivo" % MapLayers.LAYERS.size())
