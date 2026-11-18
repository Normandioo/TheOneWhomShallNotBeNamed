extends RefCounted
## DEMONSTRATIVO: um evento e uma camada de teste que só existem para exercitar o contrato dos módulos do relógio.
## Não é clima nem história de Evron: o evento é um marco de teste e o valor da camada é uma onda anual inventada.
## Quando houver módulos de verdade (temperatura sazonal), este arquivo e seus usos em main.gd saem.

const Calendar = preload("res://scripts/world/calendar.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")

const EVENT_ID := "demo_evento"
const EVENT_NAME := "Evento de teste (demonstrativo)"
const EVENT_AFTER_DAYS := 10
const NAME := "Camada de teste (demonstrativa)"
const STATE := "demonstrativo"  # condição do dado: estático, estimado, simulado, editado ou demonstrativo

var steps := 0  # quantas vezes o relógio chamou o passo diário: prova de que o módulo recebe o tempo


func attach(clock) -> void:
	clock.register(self)
	clock.schedule(EVENT_ID, clock.now + EVENT_AFTER_DAYS * Calendar.DAY, EVENT_NAME)  # recusado se já existe (salvamento)


func step_seconds() -> int:
	return Calendar.DAY


func on_step(_t: int) -> void:
	steps += 1


## O valor da camada na direção n e no instante t: {state, value, unit, source, date} ou, sem base, só {state, date}.
## Função pura do instante: não há histórico guardado, então antes do início do cenário técnico diz "indisponível".
static func value_at(n: Vector3, t: int) -> Dictionary:
	var date := Calendar.format(t, false)
	if t < Calendar.to_seconds(Calendar.TECHNICAL_START_YEAR, 1, 1):
		return {"state": "indisponível", "date": date}
	var season := sin(TAU * float(Calendar.day_of_year(t) - 1) / Calendar.YEAR_DAYS)
	return {"state": STATE, "value": 10.0 * season * sin(deg_to_rad(EvronGeo.lat_lon(n).x)), "unit": "u",
		"source": "onda anual inventada para teste", "date": date}
