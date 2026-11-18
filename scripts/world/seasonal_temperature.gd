extends RefCounted
## Temperatura sazonal ESTIMADA: o ciclo anual entre os mapas de janeiro e de julho do Gleba, em °C, sem tempo meteorológico.
## É uma função pura da data (sem estado nem histórico): repete-se todo ano e não é tendência climática de longo prazo.
## As âncoras são uma convenção do modelo: janeiro vale em 15 jan 12:00 e julho em 15 jul 12:00 (181 dias entre elas e 184 de
## julho até janeiro seguinte); T(t) = (1 − s)·Tjan + s·Tjul, com s o peso de julho. A conversão de cor em °C é feita antes
## (tools/build_temperature.py); aqui só se interpola valores, nunca cores.

const Calendar = preload("res://scripts/world/calendar.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")

const VERSION := 1  # versão do modelo: vai para o salvamento (WorldClock.models)
const NAME := "Temperatura sazonal"
const STATE := "estimado"
const UNIT := "°C"
const UNCERTAINTY := "±0,5 °C na calibração de Köppen; resolução de 0,24 °C; a interpolação é uma estimativa, não uma medição"
const SOURCE := "Temperatura Janeiro/Julho do Gleba, interpolação linear (âncoras em 15 jan e 15 jul, 12h)"
const FLOOR_C := -20.0  # o valor -20,0 do mapa significa "−20 °C ou menos": a escala do Gleba satura ali

var _jan: Image
var _jul: Image


func _init(maps: Dictionary) -> void:
	_jan = maps["jan"]
	_jul = maps["jul"]


## Peso de julho (0..1) no instante t: 0 em 15 jan 12h, 1 em 15 jul 12h, contínuo na virada do ano.
static func july_weight(t: int) -> float:
	var jan := Calendar.to_seconds(0, 1, 15, 12)
	var jul := Calendar.to_seconds(0, 7, 15, 12)
	var x := posmod(t, Calendar.YEAR)
	if x >= jan and x < jul:
		return float(x - jan) / float(jul - jan)
	var since_jul := x - jul if x >= jul else x + Calendar.YEAR - jul  # de julho até janeiro do ano seguinte
	return 1.0 - float(since_jul) / float(jan + Calendar.YEAR - jul)


## {state, value, unit, saturated, source, uncertainty, date} em n no instante t; sem dado devolve só
## {state: "indisponível", date}. saturated = o resultado depende de uma referência cortada em −20 °C (o real é menor ou igual).
func value_at(n: Vector3, t: int) -> Dictionary:
	var date := Calendar.format(t, false)
	var p := EvronGeo.pixel(n, _jan.get_size())
	var a := _jan.get_pixel(p.x, p.y).r
	var b := _jul.get_pixel(p.x, p.y).r
	if is_nan(a) or is_nan(b):
		return {"state": "indisponível", "date": date}
	var v := lerpf(a, b, july_weight(t))
	return {"state": STATE, "value": v, "unit": UNIT, "saturated": a <= FLOOR_C or b <= FLOOR_C,
		"source": SOURCE, "uncertainty": UNCERTAINTY, "date": date}
