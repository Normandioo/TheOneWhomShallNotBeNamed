## Terraformação automática (demonstração): os controles sobem sozinhos até os alvos, ~0,4% por ano de jogo.
## Mexe no planeta só pelo set_control(), como o jogador faria.

const PlanetState = preload("res://scripts/sim/planet_state.gd")

const TARGETS := {"temperature": 0.9, "atmosphere": 0.8, "h2o": 0.6}
const RATE := 0.004  # fração do controle por ano de jogo

var enabled := false


func step(planet: PlanetState, years: float) -> void:
	if not enabled:
		return
	for p in TARGETS:
		var current := planet.get_control(p)
		if current < TARGETS[p]:
			planet.set_control(p, minf(TARGETS[p], current + RATE * years))
