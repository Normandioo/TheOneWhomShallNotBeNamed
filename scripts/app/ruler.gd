extends RefCounted
## A régua (botão "Medir" da barra de baixo): cada clique no globo (ou no mapa plano) acrescenta um ponto; a distância é a soma dos
## trechos pela superfície da esfera (círculo máximo, EvronGeo.distance_km), então atravessa a longitude 180° e os polos como o pincel.
## Backspace tira o último ponto; Esc encerra. A linha é desenhada numa camada de lugares própria.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")

var active := false
var points := PackedVector3Array()
var _layer         # PlaceLayer da régua
var _altitude: Callable  # a altura da câmera em km (a espessura da linha acompanha)


func _init(layer, altitude_km: Callable) -> void:
	_layer = layer
	_altitude = altitude_km


func start() -> void:
	active = true
	points.clear()
	redraw()


func stop() -> void:
	active = false
	points.clear()
	redraw()


func add(n: Vector3) -> void:
	if active and n != Vector3.ZERO:
		points.append(n)
		redraw()


func remove_last() -> void:
	if not points.is_empty():
		points.remove_at(points.size() - 1)
		redraw()


## Soma dos trechos, em km.
func total_km() -> float:
	var km := 0.0
	for i in range(1, points.size()):
		km += EvronGeo.distance_km(points[i - 1], points[i])
	return km


## O que a tela mostra: a distância e como continuar.
func text() -> String:
	if points.size() < 2:
		return "Régua: clique no mapa para marcar os pontos (Esc encerra)."
	var km := total_km()
	var value := ("%.1f" % km).replace(".", ",") if km < 100.0 else _thousands(roundi(km))
	return "Régua: %s km em %d trecho%s\n(clique para continuar · Backspace tira o último · Esc encerra)" % [value, points.size() - 1, "" if points.size() == 2 else "s"]


func redraw() -> void:
	_layer.show_territory_path(points, points, true, float(_altitude.call()) if _altitude.is_valid() else 1000.0)


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
