## Estado do planeta e o ciclo da água. É a fonte da verdade: a interface só mostra estes valores e pede mudanças
## por set_control(). Não conhece cena, câmera nem interface, então roda e testa sem nenhum nó.
##
## O jogador controla temperatura, atmosfera e água total (frações 0..1). Água líquida, gelo, vapor, efeito estufa
## e nível do mar são resultado da simulação. O tempo vem em "anos de jogo" (ver GameClock).

const Physics = preload("res://scripts/sim/mars_physics.gd")
const Hypsometry = preload("res://scripts/sim/hypsometry.gd")

## Um controle mudou (por código ou pelo jogador).
signal control_changed(param: String, value: float)
## O limite máximo dos controles mudou ("Permitir extremos").
signal limits_changed
## O nível do mar mudou, em metros.
signal sea_level_changed(level: float)

const CONTROLS: Array[String] = ["temperature", "atmosphere", "h2o"]
const SEA_DRY := -8300.0   # nível do mar (m) sem água líquida: abaixo do fundo de Hellas
# Máximo dos controles com "Permitir extremos": +60 °C = (60 + 63) / 78; 5000 mbar = ln(5000/6) / ln(1000/6).
const EXTREME_MAX := {"temperature": 1.5769, "atmosphere": 1.3146}

# Efeito estufa descontrolado: vapor d'água quente segura mais calor, o que evapora mais água (Clausius-Clapeyron).
# GREENHOUSE_K = aquecimento (°C) se toda a água do planeta virasse vapor; escala real do runaway de Vênus.
const GREENHOUSE_K := 90.0
const GREENHOUSE_RATE := 0.015  # mais lento que a fervura (WATER_RATE): o estufa se acumula aos poucos
const VEG_ALBEDO_K := 4.0       # aquecimento (°C) se o planeta inteiro virasse floresta: ela é mais escura que deserto/gelo
const WATER_RATE := 0.15   # fervura/condensação (líquida <-> vapor): ~7 anos de jogo, bem mais rápida que o gelo (ICE_RATE)
# Congelar/derreter um oceano ou calota tem inércia térmica enorme: na Terra, uma era do gelo cheia leva
# milhares de anos pra avançar ou recuar. Aqui, dá pra trocar tudo em ~2000 anos de jogo.
const ICE_RATE := 1.0 / 2000.0

# Controles do jogador (0..1).
var temperature := 0.0
var atmosphere := 0.0
var h2o := 0.3  # Marte real já tem gelo nas calotas

# Resultado da simulação (a água total se divide entre líquida, gelo e vapor).
var liquid := 0.0
var ice := 0.3
var vapor := 0.0  # água que ferveu e ficou no ar (calor extremo com pouca pressão)
var greenhouse_c := 0.0   # aquecimento extra (°C) do vapor d'água na atmosfera: feedback do efeito estufa
var veg_warming_c := 0.0  # aquecimento extra (°C) por vegetação escurecer a superfície (albedo)
var sea_level := SEA_DRY

## Vegetação média em terra firme (0..1), entregue pelo clima. Entra na conta do albedo.
var vegetation := 0.0
var extremes := false

var _hypsometry: Hypsometry


func _init(hypsometry: Hypsometry) -> void:
	_hypsometry = hypsometry


func get_control(param: String) -> float:
	assert(param in CONTROLS, "controle desconhecido: " + param)
	return get(param)


## Maior valor permitido do controle (1, ou mais com "Permitir extremos").
func control_max(param: String) -> float:
	return EXTREME_MAX.get(param, 1.0) if extremes else 1.0


## Muda um controle, cortado em 0..máximo, e avisa quem estiver ouvindo.
func set_control(param: String, value: float) -> void:
	assert(param in CONTROLS, "controle desconhecido: " + param)
	value = clampf(value, 0.0, control_max(param))
	set(param, value)
	control_changed.emit(param, value)


## Libera os controles além do "parecido com a Terra". Desligar devolve os valores ao limite normal.
func set_extremes(on: bool) -> void:
	extremes = on
	for p in EXTREME_MAX:
		if get_control(p) > control_max(p):
			set_control(p, control_max(p))
	limits_changed.emit()


## Temperatura média (°C) já com o efeito estufa e o albedo da vegetação.
func effective_temp_c() -> float:
	return Physics.temperature_c(temperature) + greenhouse_c + veg_warming_c


## O mesmo, como fração do controle de temperatura (para a fração de água líquida).
func effective_temperature() -> float:
	return temperature + (greenhouse_c + veg_warming_c) / Physics.TEMP_SPAN_C


## Avança o ciclo da água por `years` anos de jogo.
## A água muda de estado aos poucos: sem atmosfera ou sem calor, os mares congelam e viram gelo.
## Com muito calor e pouca pressão, a água ferve e fica no ar como vapor.
func step(years: float) -> void:
	# Efeito estufa: o vapor de água de ontem aquece o ar de hoje, o que evapora mais água amanhã.
	# Um planeta quente e úmido pode "descontrolar" (como Vênus) até secar; sem água, o ciclo trava sozinho.
	# Vegetação escurece a superfície (menos reflexo que deserto ou gelo): mais um pouco de calor, sem ser estufa.
	veg_warming_c = vegetation * VEG_ALBEDO_K
	var eff_t := effective_temperature()
	var vap_f := Physics.vapor_fraction(effective_temp_c(), Physics.pressure_mbar(atmosphere))
	vapor = move_toward(minf(vapor, h2o), h2o * vap_f, years * WATER_RATE)
	var gh_target := GREENHOUSE_K * (vapor / h2o if h2o > 0.0 else 0.0) * smoothstep(0.05, 0.3, atmosphere)
	greenhouse_c = move_toward(greenhouse_c, gh_target, years * GREENHOUSE_RATE * GREENHOUSE_K)
	# Gelo derrete ou congela devagar (inércia térmica); a água líquida só reflete o que sobra do vapor e do gelo.
	var ice_target := (h2o - vapor) * (1.0 - Physics.liquid_fraction(eff_t, atmosphere))
	ice = move_toward(minf(ice, h2o - vapor), ice_target, years * ICE_RATE)
	liquid = maxf(h2o - vapor - ice, 0.0)
	# A água líquida enche o relevo real de baixo para cima (Hellas e o norte primeiro).
	var gel := Physics.water_gel(h2o) * liquid / h2o if h2o > 0.0 else 0.0
	var new_sea := _hypsometry.sea_level_for(gel) if gel > 0.0 else SEA_DRY
	if new_sea != sea_level:
		sea_level = new_sea
		sea_level_changed.emit(sea_level)
