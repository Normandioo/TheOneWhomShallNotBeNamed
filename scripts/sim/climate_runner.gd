## Agenda o passo do clima: um passo a cada STEP_INTERVAL segundos reais, calculado em pedaços de ROWS_PER_FRAME
## linhas por quadro para não engasgar (~3 ms cada). Não decide o que o clima faz, só quando e quanto.

const Climate = preload("res://scripts/sim/climate.gd")

## Um passo completo do clima terminou; as texturas e a vegetação média podem ser lidas.
signal step_finished

const STEP_INTERVAL := 0.25         # segundos reais entre passos do clima
const SIM_SECONDS_PER_SECOND := 4.0  # segundos de clima por segundo real, a 1x
const ROWS_PER_FRAME := 6           # linhas da grade calculadas por quadro
const DT_MAX := 8.0                 # passo máximo (s de clima); acima disso a advecção perde precisão

var _climate: Climate
var _acc := 0.0
var _next_row := -1  # próxima linha do passo em andamento; -1 = nenhum


func _init(climate: Climate) -> void:
	_climate = climate


## Chamar a cada quadro. Parado (time_scale 0) o clima não anda.
func tick(delta: float, time_scale: float, temp_c: float, atmosphere: float, sea_level: float) -> void:
	if _next_row < 0 and time_scale > 0.0:
		_acc += delta
		if _acc >= STEP_INTERVAL:
			_acc = 0.0
			_next_row = 0
			_climate.step_begin(minf(STEP_INTERVAL * SIM_SECONDS_PER_SECOND * time_scale, DT_MAX), temp_c, atmosphere, sea_level)
	if _next_row >= 0:
		_climate.step_rows(_next_row, mini(_next_row + ROWS_PER_FRAME, Climate.H))
		_next_row += ROWS_PER_FRAME
		if _next_row >= Climate.H:
			_next_row = -1
			_climate.step_end()
			step_finished.emit()


## Roda `total` segundos de clima de uma vez, em passos de `dt` (para testes e para pular o tempo).
func advance(total: float, dt: float, temp_c: float, atmosphere: float, sea_level: float) -> void:
	var steps := maxi(1, roundi(total / dt))
	for i in steps:
		_climate.step(total / steps, temp_c, atmosphere, sea_level)
	step_finished.emit()
