## Calendário e velocidade do jogo. Converte segundos reais em anos de jogo.

## A velocidade mudou (por botão, tecla ou código).
signal speed_changed(scale: float)

const START_YEAR := 2070.0
const YEARS_PER_SECOND := 1.0  # anos de jogo por segundo real, a 1x
# As duas primeiras são para olhar o sistema solar (a Terra e Marte girando): 1 hora e 1 dia do jogo por segundo.
const SPEEDS := [["Pausa", 0.0], ["1 h/s", 1.0 / 8766.0], ["1 dia/s", 1.0 / 365.25], ["0.1x", 0.1], ["1x", 1.0], ["3x", 3.0],
	["10x", 10.0], ["30x", 30.0]]
const MARS_YEAR := 1.8808  # anos da Terra (os do calendário) por ano marciano
# Acima disto o ano marciano passa rápido demais para o clima acompanhar (a calota piscaria):
# as estações somem e fica só a média do ano. Em 0.1x um ano marciano leva ~19 s reais.
const SEASON_MAX_SCALE := 0.3

var year := START_YEAR
var time_scale := 1.0
var season_t := 0.0     # fração do ano marciano (0 = Ls 0°)
var seasons_on := true  # false = o clima usa só a média do ano (tempo rápido demais)


func set_speed(scale: float) -> void:
	time_scale = scale
	speed_changed.emit(scale)


func toggle_pause() -> void:
	set_speed(0.0 if time_scale > 0.0 else 1.0)


## Avança o calendário por `delta` segundos reais e devolve quantos anos de jogo passaram.
func tick(delta: float) -> float:
	var years := delta * time_scale * YEARS_PER_SECOND
	year += years
	season_t = fposmod((year - START_YEAR) / MARS_YEAR, 1.0)
	if time_scale > 0.0:  # em pausa fica como estava
		seasons_on = time_scale <= SEASON_MAX_SCALE
	return years
