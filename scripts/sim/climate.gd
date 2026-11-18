extends RefCounted
## Clima estilizado numa grade de 2,5°: vento -> umidade -> nuvens -> chuva -> vegetação.
## Não é um modelo científico: é uma cadeia causal simples que o jogador consegue entender.
## Só chove se a atmosfera e a temperatura permitirem (com o Marte de hoje, o ar é seco demais).
## O ar sobe (esfria, condensa e vira nuvem) de três jeitos: nas montanhas, em sistemas de tempo que passam
## (frentes e ciclones nas latitudes médias) e por convecção (terra quente e úmida). Os dois últimos são o que leva
## nuvem e chuva ao interior do continente, longe da costa e das serras.
## O vento tem uma parte fixa (faixas de latitude) e uma térmica: o ar sopra para onde está mais quente (pressão
## menor). Como o mar esquenta e esfria devagar e a terra depressa, no verão o vento vai do mar para o continente
## (brisa, monção) e no inverno o contrário. É o que leva o vapor do mar para dentro da terra.
## Há dois tipos de nuvem: a de chuva (`cloud`, espessa, esgota o vapor e molha o chão) e a fina (`haze`: cirros,
## estratos e neblina), que não chove, anda com o vento em faixas e aparece onde o ar está úmido e o tempo favorece.
## Só calcula: não sabe de texturas nem de cena (ver ClimateTextures) e quem agenda os passos é o ClimateRunner.

const MarsGeo = preload("res://scripts/data/mars_geo.gd")
const Physics = preload("res://scripts/sim/mars_physics.gd")

const W := 144
const H := 72
const N := W * H
const WIND_CELLS_PER_S := 3.0  # velocidade máxima do vento, em células por segundo de clima
const EVAP := 0.6              # rapidez com que o mar satura o ar
const LAND_EVAP := 0.15        # evaporação do solo molhado
const VEG_EVAP := 0.3          # transpiração: floresta plena devolve umidade ao ar bem mais rápido que solo nu
const RAIN_RATE := 0.5
const RAIN_THRESHOLD := 0.02   # só chove acima desta espessura de nuvem: abaixo, a nuvem fica, anda com o vento e leva a água para o interior
const SOIL_DECAY := 0.02
const TUNDRA_COVER := 0.35      # cobertura máxima no frio (< 0 °C): musgo e líquen, não floresta
const SNOW_GAIN := 20.0         # precipitação abaixo de 0 °C -> neve no chão (mesma escala da umidade do solo)
const MELT_RATE := 0.03        # neve derretida por segundo de clima, com o ar acima de 0 °C
const VEG_K := 400.0           # chuva (umidade/s) -> vegetação alvo
const VEG_RATE := 0.03
const CURRENT_CELLS_PER_S := 0.5  # velocidade das correntes oceânicas, em células por segundo de clima
const SST_RELAX := 0.03           # rapidez com que o mar volta à temperatura da sua latitude
const OCEAN_HEAT_EFFECT := 0.35   # quanto da anomalia do mar passa para o ar
const SEASON_K := 0.25            # °C por W/m² de insolação acima da média anual (Marte de hoje: polos ~±40 °C)
const SEASON_OCEAN := 0.3         # o mar guarda calor: estações mais suaves sobre ele
# Indústria da chuva: cada colônia força condensação ao redor, sem depender do ciclo natural da água.
# É a resposta do jogo para o interior seco de continente: construir onde a natureza não chove sozinha.
const INDUSTRY_RADIUS := 6.0      # alcance de cada colônia, em células (~15°, uns 900 km em Marte)
const INDUSTRY_RATE := 0.4        # força da usina: bem mais rápida que a evaporação natural (EVAP/LAND_EVAP)
# Convecção: em terra quente, o ar já úmido sobe e condensa mesmo sem montanha. Quanto mais úmido (umidade
# relativa perto de 1), mais forte; o ar seco do interior continua seco.
const CONV_MAX := 0.35            # quanto a saturação efetiva cai (fração) no máximo
# Sistemas de tempo: ruído suave que anda com o vento e muda com o tempo, forte nas latitudes médias. Positivo = ar
# subindo (nuvem e chuva), negativo = ar descendo (céu abre).
const EDDY_STRENGTH := 1.5        # km de "subida" por célula no máximo (mesma unidade de `lift`)
const EDDY_WIND := 0.9            # células/s de vento norte-sul dos sistemas de tempo (leva umidade entre latitudes)
const EDDY_PERIOD := 30.0         # segundos de clima para o padrão se renovar
const EDDY_CELLS := 4             # tamanho de um sistema de tempo, em células (~10°)
const EDDY_CW := W / EDDY_CELLS
const EDDY_CH := H / EDDY_CELLS + 1
# Vento térmico: força (em fração do vento fixo, por K de diferença entre células a 2 de distância) e teto.
const THERMAL_WIND_K := 0.1
const THERMAL_WIND_MAX := 0.7
const OCEAN_COOLING := 2.0        # °C: a água (evaporação, calor guardado) esfria o ar em cima dela quando o clima é quente
const LIFT_MAX := 2.0             # a subida por relevo nunca passa disso (km por célula): paredão de cânion não vira faixa de nuvem
const HAZE_MAX := 0.6             # cobertura máxima da nuvem fina (0..1)
# Chuva em episódios: só chove quando o ar está subindo (frente, serra ou pancada). Sem subida, a nuvem fica e passa.
const RAIN_LIFT_GATE := Vector2(0.05, 0.2)  # fração de queda da saturação que abre a chuva (começa em x, plena em y)
# Os sistemas de tempo andam com o vento só um pouco (o padrão se renova a cada EDDY_PERIOD). Andar à velocidade
# cheia, linha a linha, esticava o padrão em tiras horizontais, porque o vento muda com a latitude.
const DRIFT_SCALE := 0.25
const HAZE_RATE := 0.2            # rapidez com que a nuvem fina se forma e se desfaz
# Massas de ar (docs/pesquisa-atmosfera.md): o vento leva a temperatura de onde o ar veio, e ela volta aos poucos ao
# equilíbrio do lugar. No ar fino de hoje o ar esquece na hora (~1 sol); com 1 bar, leva semanas.
const TA_RELAX_THIN := 5.0        # 1/s de clima com o ar de hoje: a temperatura é a do chão de cada lugar
const TA_RELAX_THICK := 0.12      # 1/s com o ar cheio: a massa anda ~15 células antes de perder 2/3 do caráter
const TA_RELAX_SEA := 3.0         # o mar troca calor com o ar mais rápido que a terra
const TA_MAX := 20.0              # °C: maior diferença entre o ar que chegou e o equilíbrio do lugar
const LAPSE := 0.004              # °C por metro, o mesmo de static_t: o ar levado é corrigido pela altitude
const FOEHN_K := 3.0              # °C por km de descida com o ar seco: o lado de baixo da serra fica quente e seco
const CONV_LIFT_K := 0.5          # subida por convergência do vento (células/s por célula): ZCIT e linhas de encontro
const FRONT_K := 0.03             # subida por °C/s de ar de outra massa chegando (frente)
const FRONT_MAX := 0.4
const SEA_CONV_DT := Vector2(4.0, 12.0)  # °C de mar mais quente que o ar: começa e satura a convecção sobre a água
const SEA_ICE_C := -2.0           # mar abaixo disso congela e para de evaporar
const UPWELL_C := 5.0             # °C: a água fria do fundo que sobe onde a corrente se afasta da costa
# Tempestades: a força vem do contraste de temperatura norte-sul (taxa de Eady ~ sen(lat) x dT/dy), não da latitude.
const EDDY_GRAD := Vector2(0.1, 1.8)  # sen(lat) x °C por linha: começa e satura (latitudes médias: ~1 no verão, ~2,5-3 no inverno)
const EDDY_STRETCH := 3           # os sistemas de tempo são 3x mais largos (leste-oeste) que as pancadas: ~30°, como em Marte
# Faixas de vento que andam com a estação: tabelas do vento (já desviado pelo relevo) com o equador térmico deslocado
# de -20° a +20°, de 10 em 10, interpoladas a cada passo. A ZCIT segue o Sol: quase toda a declinação com o ar fino
# (terra sem inércia, como o Marte de hoje), metade com ar grosso e mar.
const BAND_TABLES := 5
const BAND_STEP := 10.0           # graus entre tabelas; a do meio (2) é a sem deslocamento
const BAND_FOLLOW := Vector2(0.9, 0.5)
# Catabático: ar frio e denso escorre encosta abaixo (calotas, platôs, encostas no inverno ou com neve).
const KATABATIC_K := 0.6          # vento (em fração do vento das faixas) por km de descida por célula

var hgt := PackedFloat32Array()     # altitude em metros
var static_t := PackedFloat32Array() # °C relativos à média global (latitude + altitude)
var wu := PackedFloat32Array()      # direção do vento (leste), já desviada pelo relevo
var wv := PackedFloat32Array()      # direção do vento (norte)
var lift := PackedFloat32Array()    # quanto o ar sobe montanha (km por célula)
var weight := PackedFloat32Array()  # cos(lat): peso de área
var q := PackedFloat32Array()       # umidade do ar
var cloud := PackedFloat32Array()
var rain := PackedFloat32Array()    # chuva média recente
var soil := PackedFloat32Array()
var veg := PackedFloat32Array()     # 0..1
var wind_u := PackedFloat32Array()  # vento final (células/s), para desenhar
var wind_v := PackedFloat32Array()
var lat_t := PackedFloat32Array()   # °C relativos à média global só pela latitude
var bu := PackedFloat32Array()      # vento base (sem relevo), para as correntes
var bv := PackedFloat32Array()
var cur_u := PackedFloat32Array()   # corrente oceânica (células/s); 0 em terra
var cur_v := PackedFloat32Array()
var sst := PackedFloat32Array()     # temperatura da superfície do mar (relativa à média global)
var oa := PackedFloat32Array()      # anomalia do mar: sst - o esperado para a latitude (+ = corrente quente)
var temp_c := PackedFloat32Array()  # temperatura final do ar (°C), para o mapa
var season_t := 0.0                 # fração do ano marciano (0 = Ls 0°); quem dá é o calendário do jogo (main.gd)
var season_amp := 1.0               # 0..1: força das estações; 0 = só a média do ano (tempo rápido demais pra ver)
var ls := 0.0                       # longitude solar atual (graus)
var season := PackedFloat32Array()  # anomalia sazonal de temperatura por linha (°C)
var _q_mean := PackedFloat32Array() # insolação média anual por linha (W/m²)
var industry := PackedFloat32Array() # 0..1: força da usina de chuva perto de cada colônia; 0 sem colônia
var mean_veg := 0.0                 # vegetação média em terra firme
var mean_rain := 0.0
var mean_cloud := 0.0
var snow := PackedFloat32Array()    # 0..1: neve no chão; chove abaixo de 0 °C, derrete acima
var raining := PackedFloat32Array() # chuva de agora (neste passo), ao contrário de `rain`, que é a média recente
var haze := PackedFloat32Array()    # nuvem fina que não chove, 0..1
var mean_haze := 0.0
var ta := PackedFloat32Array()      # °C: ar que chegou menos o equilíbrio do lugar (+ = massa quente, - = fria)
var front := PackedFloat32Array()   # subida por frente: + = frente quente (ar quente chegando), - = frente fria
var sink := PackedFloat32Array()    # quanto o ar desce a serra (km por célula), para o foehn
var upwell := PackedFloat32Array()  # 0..1: ressurgência (a corrente se afasta da costa); 0 em terra
var _storm_k := PackedFloat32Array() # tempestades preferem as baixadas (corredores de Acidalia, Utopia, Arcadia)
var _ta2 := PackedFloat32Array()
var _theta := PackedFloat32Array()  # temperatura do ar levada ao nível zero (°C), do passo anterior
var _theta2 := PackedFloat32Array()
var _pu := PackedFloat32Array()     # vento do passo anterior, para a convergência
var _pv := PackedFloat32Array()
var _air_ready := false             # o primeiro passo não tem ar anterior para levar
var itcz_lat := 0.0                 # graus: equador térmico, onde os alísios se encontram (anda com a estação)
var _tab_wu := PackedFloat32Array() # BAND_TABLES grades de N seguidas: vento e subida/descida do relevo por deslocamento
var _tab_wv := PackedFloat32Array()
var _tab_lift := PackedFloat32Array()
var _tab_sink := PackedFloat32Array()
var _tab_a := BAND_TABLES / 2       # tabela de baixo e fração até a próxima, para o deslocamento atual
var _tab_f := 0.0
var _down_u := PackedFloat32Array() # encosta abaixo (km de descida por célula, leste e norte), para o catabático
var _down_v := PackedFloat32Array()

var _eddy_a := PackedFloat32Array()  # ruído dos sistemas de tempo, grade grossa, no instante atual
var _eddy_b := PackedFloat32Array()  # ...e no próximo, para a mistura no tempo
var _eddy_amp := PackedFloat32Array()  # força por linha: fraca nos trópicos, forte nas latitudes médias
var _row_u := PackedFloat32Array()   # vento base médio de cada linha, para os sistemas de tempo andarem com ele
var _drift_a := PackedFloat32Array()  # quanto o padrão já andou em cada linha (células): o do instante atual...
var _drift_b := PackedFloat32Array()  # ...e o do próximo, que já "chegou" (a diferença entre linhas fica limitada)
var _eddy_t := 0.0
var _eddy_idx := -1
var _eddy_f := 0.0

var _q2 := PackedFloat32Array()
var _cloud2 := PackedFloat32Array()
var _haze2 := PackedFloat32Array()
var _thermal := PackedFloat32Array()  # anomalia térmica da superfície (°C): terra x mar, estação, mar esfriando o ar
var _sst2 := PackedFloat32Array()
var _oa2 := PackedFloat32Array()
var _cur_sea := INF  # nível do mar com que as correntes foram calculadas


func setup(height_img: Image) -> void:
	for a in [hgt, static_t, wu, wv, lift, weight, q, cloud, haze, rain, snow, raining, soil, veg, wind_u, wind_v, _q2, _cloud2, _haze2, _thermal,
			lat_t, bu, bv, cur_u, cur_v, sst, oa, temp_c, _sst2, _oa2, industry, ta, front, sink, upwell, _storm_k, _ta2,
			_theta, _theta2, _pu, _pv, _down_u, _down_v]:
		a.resize(N)
	for a in [_tab_wu, _tab_wv, _tab_lift, _tab_sink]:
		a.resize(N * BAND_TABLES)
	var iw := height_img.get_width()
	var ih := height_img.get_height()
	for j in H:
		for i in W:
			hgt[j * W + i] = height_img.get_pixel(int((i + 0.5) * iw / W), int((j + 0.5) * ih / H)).r
	# O relevo que levanta o ar é suavizado (~5 células): na grade de 2,5° um cânion vira um degrau de vários km entre
	# duas células vizinhas e gerava uma faixa reta de nuvem ao longo da parede inteira.
	var hs := _smooth_heights(_smooth_heights(hgt))
	for k in BAND_TABLES:
		_build_bands(k, hs)
	var mid := (BAND_TABLES / 2) * N
	for j in H:
		var lat := _row_lat(j)
		for i in W:
			var idx := j * W + i
			wu[idx] = _tab_wu[mid + idx]
			wv[idx] = _tab_wv[mid + idx]
			lift[idx] = _tab_lift[mid + idx]
			sink[idx] = _tab_sink[mid + idx]
			var down := -Vector2((hs[j * W + (i + 1) % W] - hs[j * W + (i + W - 1) % W]) * 0.5,
				(hs[maxi(j - 1, 0) * W + i] - hs[mini(j + 1, H - 1) * W + i]) * 0.5) / 1000.0
			down = down.limit_length(1.0)
			_down_u[idx] = down.x
			_down_v[idx] = down.y
			_storm_k[idx] = lerpf(0.6, 1.2, smoothstep(2000.0, -4000.0, hgt[idx]))
			lat_t[idx] = 35.0 * (cos(2.0 * lat) - 1.0 / 3.0)
			sst[idx] = lat_t[idx]
			static_t[idx] = lat_t[idx] - 0.004 * maxf(hgt[idx], 0.0)
			weight[idx] = cos(lat)
	soil.fill(0.0)
	for a in [_eddy_a, _eddy_b]:
		a.resize(EDDY_CW * EDDY_CH)
	for a in [_eddy_amp, _row_u, _drift_a, _drift_b]:
		a.resize(H)
	for j in H:
		_eddy_amp[j] = smoothstep(8.0, 35.0, absf(90.0 - (j + 0.5) * 180.0 / H))
		_row_u[j] = bu[j * W]
	season.resize(H)
	season.fill(0.0)
	_q_mean.resize(H)
	_q_mean.fill(0.0)
	for k in 96:  # média em tempo: amostras iguais de t, não de Ls
		var o := Physics.orbit(k / 96.0)
		for j in H:
			_q_mean[j] += Physics.daily_insolation(_row_lat(j), o.x, o.y) / 96.0


## Uma tabela do vento das faixas com o equador térmico deslocado de (k - BAND_TABLES/2) * BAND_STEP graus, já
## desviado pelo relevo, com a subida e a descida que ele causa. A tabela do meio também dá o vento base (bu, bv)
## das correntes: o oceano responde devagar, segue a média do ano.
func _build_bands(k: int, hs: PackedFloat32Array) -> void:
	var shift := deg_to_rad((k - BAND_TABLES / 2) * BAND_STEP)
	var o := k * N
	for j in H:
		var lat := _row_lat(j)
		# O equador vai para `shift` e os polos ficam no lugar: um hemisfério encolhe e o outro estica.
		var le := (lat - shift) * (PI / 2.0) / (PI / 2.0 - shift if lat >= shift else PI / 2.0 + shift)
		# Faixas de vento: alísios (leste->oeste) no trópico, ventos de oeste nas latitudes médias.
		var ub := -cos(3.0 * le)
		var vb := -0.35 * sin(6.0 * le)  # vai para o equador nos trópicos e para o polo nas latitudes médias
		for i in W:
			var idx := j * W + i
			var ge := (hs[j * W + (i + 1) % W] - hs[j * W + (i + W - 1) % W]) * 0.5
			var gn := (hs[maxi(j - 1, 0) * W + i] - hs[mini(j + 1, H - 1) * W + i]) * 0.5
			var up := ub * ge + vb * gn  # metros que o ar precisa subir por célula
			var wx := ub
			var wy := vb
			if up > 0.0:
				var s2 := ge * ge + gn * gn
				var block := clampf(up / 1500.0, 0.0, 0.8)  # a montanha desvia parte do vento
				wx -= block * up / s2 * ge
				wy -= block * up / s2 * gn
			if k == BAND_TABLES / 2:
				bu[idx] = ub
				bv[idx] = vb
			_tab_wu[o + idx] = wx
			_tab_wv[o + idx] = wy
			_tab_lift[o + idx] = minf(maxf(up, 0.0) / 1000.0, LIFT_MAX)
			_tab_sink[o + idx] = minf(maxf(-up, 0.0) / 1000.0, LIFT_MAX)


## Média 3x3 de uma grade de altitudes (a longitude dá a volta).
func _smooth_heights(a: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(N)
	for j in H:
		for i in W:
			var sum := 0.0
			for dj in range(-1, 2):
				var jj := clampi(j + dj, 0, H - 1)
				for di in range(-1, 2):
					sum += a[jj * W + posmod(i + di, W)]
			out[j * W + i] = sum / 9.0
	return out


func _row_lat(j: int) -> float:
	return deg_to_rad(90.0 - (j + 0.5) * 180.0 / H)


## Célula da grade (i, j) sob a direção n (mesma convenção de longitude/latitude do mapa de altitude).
func cell_of(n: Vector3) -> Vector2i:
	var ll := MarsGeo.lat_lon(n)
	var i := int(wrapf((ll.y / 360.0 + 0.5) * W, 0.0, W))
	var j := clampi(int((0.5 - ll.x / 180.0) * H), 0, H - 1)
	return Vector2i(i, j)


## Vegetação (0..1) na célula sob a direção n.
func veg_at(n: Vector3) -> float:
	var c := cell_of(n)
	return veg[c.y * W + c.x]


## Recalcula a grade de indústria a partir das direções das colônias. Cada uma força chuva num raio ao redor,
## mais forte no centro; some com os vizinhos. Chamar de novo sempre que uma colônia for fundada.
func set_industry(colony_dirs: Array) -> void:
	industry.fill(0.0)
	var r := int(INDUSTRY_RADIUS)
	for n in colony_dirs:
		var c := cell_of(n)
		for dj in range(-r, r + 1):
			var j := c.y + dj
			if j < 0 or j >= H:
				continue
			for di in range(-r, r + 1):
				var dist := Vector2(di, dj).length()
				if dist > INDUSTRY_RADIUS:
					continue
				var i := posmod(c.x + di, W)
				var idx := j * W + i
				industry[idx] = maxf(industry[idx], 1.0 - dist / INDUSTRY_RADIUS)


var _dt := 1.0
var _global_c := 0.0
var _atm := 0.0
var _sea := 0.0
var _sum_v := 0.0
var _sum_w := 0.0
var _sum_r := 0.0
var _sum_c := 0.0
var _sum_h := 0.0


## Avança o clima `dt` segundos de uma vez. global_c = temperatura média (°C), atm = 0..1, sea = nível do mar (m).
func step(dt: float, global_c: float, atm: float, sea: float) -> void:
	step_begin(dt, global_c, atm, sea)
	step_rows(0, H)
	step_end()


## Versão em pedaços: step_begin, vários step_rows que cobrem 0..H, e step_end. Evita engasgos num quadro só.
func step_begin(dt: float, global_c: float, atm: float, sea: float) -> void:
	_dt = dt
	_global_c = global_c
	_atm = atm
	_sea = sea
	_sum_v = 0.0
	_sum_w = 0.0
	_sum_r = 0.0
	_sum_c = 0.0
	_sum_h = 0.0
	if absf(sea - _cur_sea) > 40.0:  # o mar subiu ou desceu o bastante para mudar a costa
		_update_currents(sea)
	# Estações: insolação do dia menos a média anual, por latitude. Ar grosso suaviza e atrasa a resposta.
	var o := Physics.orbit(season_t)
	ls = o.x
	var amp := SEASON_K * lerpf(1.0, 0.4, atm) * season_amp
	var lag_k := minf(1.0, dt / lerpf(1.0, 6.0, atm))
	for j in H:
		var target := amp * (Physics.daily_insolation(_row_lat(j), o.x, o.y) - _q_mean[j])
		season[j] += (target - season[j]) * lag_k
	# A ZCIT segue a declinação do Sol, com o mesmo atraso das estações.
	var decl := rad_to_deg(asin(sin(deg_to_rad(Physics.OBLIQUITY_DEG)) * sin(deg_to_rad(ls))))
	itcz_lat += (decl * lerpf(BAND_FOLLOW.x, BAND_FOLLOW.y, atm) * season_amp - itcz_lat) * lag_k
	var x := clampf(itcz_lat / BAND_STEP + BAND_TABLES / 2, 0.0, BAND_TABLES - 1.001)
	_tab_a = int(x)
	_tab_f = x - _tab_a
	_advance_eddies(dt, atm)
	_update_thermal()
	if _air_ready:
		_update_storminess()
	_pu = wind_u.duplicate()
	_pv = wind_v.duplicate()


## Força das tempestades por linha a partir do contraste de temperatura norte-sul do ar (ao nível zero, para a
## dicotomia de altitude não contar): fortes no inverno e onde há gelo ou costa fria, fracas nos trópicos e no verão.
func _update_storminess() -> void:
	var row := PackedFloat32Array()
	row.resize(H)
	for j in H:
		var s := 0.0
		for i in W:
			s += _theta[j * W + i]
		row[j] = s / W
	for j in H:
		var g := (row[maxi(j - 2, 0)] - row[mini(j + 2, H - 1)]) / float(mini(j + 2, H - 1) - maxi(j - 2, 0))
		_eddy_amp[j] = smoothstep(EDDY_GRAD.x, EDDY_GRAD.y, absf(sin(_row_lat(j)) * g))


## A anomalia térmica da superfície que move o vento: a estação (forte em terra, amortecida no mar) menos o
## esfriamento do ar sobre a água. Só o que difere entre terra e mar e entre estações: a diferença de temperatura
## entre latitudes já está nas faixas fixas do vento.
func _update_thermal() -> void:
	var lat_k := lerpf(1.0, 0.7, _atm)
	for j in H:
		var warm := smoothstep(-5.0, 20.0, _global_c + lat_t[j * W] * lat_k)
		for i in W:
			var idx := j * W + i
			_thermal[idx] = season[j] * SEASON_OCEAN - OCEAN_COOLING * warm if hgt[idx] < _sea else season[j]


## Os sistemas de tempo: o padrão anda com o vento de cada latitude e se renova a cada EDDY_PERIOD.
## Ruído de valor em grade grossa, sorteado por uma conta (hash) e não por um gerador de números: o resultado só
## depende do tempo, então o passo inteiro e o passo em pedaços dão o mesmo clima.
func _advance_eddies(dt: float, atm: float) -> void:
	_eddy_t += dt
	var idx := int(floorf(_eddy_t / EDDY_PERIOD))
	if idx != _eddy_idx:
		_eddy_idx = idx
		for k in EDDY_CW * EDDY_CH:
			_eddy_a[k] = _hash(k % EDDY_CW, k / EDDY_CW, idx) * 2.0 - 1.0
			_eddy_b[k] = _hash(k % EDDY_CW, k / EDDY_CW, idx + 1) * 2.0 - 1.0
	_eddy_f = smoothstep(0.0, 1.0, fposmod(_eddy_t, EDDY_PERIOD) / EDDY_PERIOD)
	# O deslocamento de cada padrão é medido desde o começo do período dele (o próximo já vem deslocado pelo tempo
	# que falta), então não acumula: a diferença entre linhas vizinhas nunca passa de poucas células.
	var local := fposmod(_eddy_t, EDDY_PERIOD)
	var gain := WIND_CELLS_PER_S * (0.3 + 0.7 * atm) * DRIFT_SCALE
	for j in H:
		_drift_a[j] = _row_u[j] * gain * local
		_drift_b[j] = _row_u[j] * gain * (local - EDDY_PERIOD)


## Maior diferença de deslocamento do padrão entre duas linhas vizinhas (células). Para os testes.
func max_row_shear() -> float:
	var m := 0.0
	for j in H - 1:
		m = maxf(m, maxf(absf(_drift_a[j + 1] - _drift_a[j]), absf(_drift_b[j + 1] - _drift_b[j])))
	return m


## Ruído 0..1 de uma célula da grade grossa num instante.
static func _hash(x: int, y: int, t: int) -> float:
	var h := x * 374761393 + y * 668265263 + t * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


## Sistema de tempo na célula (i, j), de -1 (ar descendo, céu aberto) a +1 (ar subindo), antes de pesar pela latitude.
## `sx` estica o padrão no sentido leste-oeste (divisor de EDDY_CW, para dar a volta sem emenda).
## Escrito sem chamadas de função internas: roda uma ou duas vezes por célula, a cada passo do clima.
func _eddy_noise(i: int, j: int, sx: int = 1) -> float:
	var cw := EDDY_CW / sx
	var y := minf(j / float(EDDY_CELLS), EDDY_CH - 1.0)
	var y0 := int(y)
	var fy := y - y0
	var ra := y0 * EDDY_CW
	var rb := mini(y0 + 1, EDDY_CH - 1) * EDDY_CW
	var xa := fposmod((i - _drift_a[j]) / (EDDY_CELLS * sx), float(cw))
	var xa0 := int(xa)
	var xa1 := (xa0 + 1) % cw
	var fxa := xa - xa0
	var xb := fposmod((i - _drift_b[j]) / (EDDY_CELLS * sx), float(cw))
	var xb0 := int(xb)
	var xb1 := (xb0 + 1) % cw
	var fxb := xb - xb0
	var a0 := _eddy_a[ra + xa0] + (_eddy_a[ra + xa1] - _eddy_a[ra + xa0]) * fxa
	var a1 := _eddy_a[rb + xa0] + (_eddy_a[rb + xa1] - _eddy_a[rb + xa0]) * fxa
	var b0 := _eddy_b[ra + xb0] + (_eddy_b[ra + xb1] - _eddy_b[ra + xb0]) * fxb
	var b1 := _eddy_b[rb + xb0] + (_eddy_b[rb + xb1] - _eddy_b[rb + xb0]) * fxb
	var ea := a0 + (a1 - a0) * fy
	var eb := b0 + (b1 - b0) * fy
	return ea + (eb - ea) * _eddy_f


## Correntes: o vento girado ~45° (para a direita no norte, para a esquerda no sul), travadas pela costa.
## A componente que bate na terra some e o resto desliza ao longo dela: surgem giros e correntes de borda.
func _update_currents(sea: float) -> void:
	_cur_sea = sea
	for j in H:
		var lat_deg := 90.0 - (j + 0.5) * 180.0 / H
		var ang := deg_to_rad(45.0) * clampf(lat_deg / 15.0, -1.0, 1.0)
		var ca := cos(ang)
		var sa := sin(ang)
		for i in W:
			var idx := j * W + i
			var cu := 0.0
			var cv := 0.0
			if hgt[idx] < sea:
				cu = (bu[idx] * ca + bv[idx] * sa) * CURRENT_CELLS_PER_S
				cv = (-bu[idx] * sa + bv[idx] * ca) * CURRENT_CELLS_PER_S
				if cu != 0.0 and hgt[j * W + (i + (1 if cu > 0.0 else W - 1)) % W] >= sea:
					cu = 0.0
				var jn := j - 1 if cv > 0.0 else j + 1  # norte = linha menor
				if cv != 0.0 and (jn < 0 or jn >= H or hgt[jn * W + i] >= sea):
					cv = 0.0
			# Ressurgência: a corrente se afasta da terra que tem atrás, e a água fria do fundo sobe no lugar.
			var up := 0.0
			if cu != 0.0 and hgt[j * W + (i + (W - 1 if cu > 0.0 else 1)) % W] >= sea:
				up = absf(cu)
			var jb := j + 1 if cv > 0.0 else j - 1
			if cv != 0.0 and jb >= 0 and jb < H and hgt[jb * W + i] >= sea:
				up = maxf(up, absf(cv))
			upwell[idx] = minf(up / CURRENT_CELLS_PER_S, 1.0)
			cur_u[idx] = cu
			cur_v[idx] = cv


## Anomalia de temperatura do mar que chega à terra vizinha (costas de correntes quentes ficam mais quentes).
func _coast_anom(i: int, j: int) -> float:
	return 0.175 * (oa[j * W + (i + 1) % W] + oa[j * W + (i + W - 1) % W]
		+ oa[maxi(j - 1, 0) * W + i] + oa[mini(j + 1, H - 1) * W + i])


## Quanto da diferença para a saturação o solo (úmido) e a vegetação (transpiração) devolvem ao ar, por segundo.
## A floresta recicla água mesmo com o solo seco por cima: puxa pelas raízes, bem mais rápido que o solo sozinho.
static func land_evap_rate(dt: float, soil: float, veg: float) -> float:
	return minf(1.0, minf(1.0, LAND_EVAP * dt) * minf(soil, 1.0) + minf(1.0, VEG_EVAP * dt) * veg)


func step_rows(j0: int, j1: int) -> void:
	var dt := _dt
	var global_c := _global_c
	var sea := _sea
	var gain := WIND_CELLS_PER_S * (0.3 + 0.7 * _atm)
	# Ar mais grosso leva mais calor aos polos: a diferença equador-polo cai de ~70 K (hoje) para ~50 K (1 bar).
	var lat_k := lerpf(1.0, 0.7, _atm)
	var evap_k := minf(1.0, EVAP * dt)
	var rain_k := minf(1.0, RAIN_RATE * dt)
	var avg_k := minf(1.0, dt * 0.3)
	var veg_k := minf(1.0, dt * VEG_RATE)
	var sst_k := minf(1.0, SST_RELAX * dt)
	# Memória do ar: do ar fino (esquece na hora) ao grosso (semanas), em escala log para a transição ser gradual.
	var relax := exp(lerpf(log(TA_RELAX_THIN), log(TA_RELAX_THICK), _atm))
	var keep_land := exp(-relax * dt)
	var keep_sea := exp(-relax * TA_RELAX_SEA * dt)
	var sum_v := 0.0
	var sum_w := 0.0
	var sum_r := 0.0
	var sum_c := 0.0
	var sum_h := 0.0

	var ta0 := _tab_a * N
	var tab_f := _tab_f
	for j in range(j0, j1):
		# Catabático: frio de inverno (a estação nesta latitude) ou chão com neve.
		var winter := smoothstep(0.0, -15.0, season[j])
		for i in W:
			var idx := j * W + i
			# Faixas de vento na posição desta estação (interpoladas entre as tabelas vizinhas).
			var t0 := ta0 + idx
			wu[idx] = lerpf(_tab_wu[t0], _tab_wu[t0 + N], tab_f)
			wv[idx] = lerpf(_tab_wv[t0], _tab_wv[t0 + N], tab_f)
			lift[idx] = lerpf(_tab_lift[t0], _tab_lift[t0 + N], tab_f)
			sink[idx] = lerpf(_tab_sink[t0], _tab_sink[t0 + N], tab_f)
			var kat := 0.0
			if hgt[idx] >= _sea:
				kat = KATABATIC_K * maxf(winter, snow[idx])
			# Vento térmico: para o lado mais quente (diferença entre as células a 2 de distância, para suavizar a costa).
			var ip := (i + 2) % W
			var im := (i + W - 2) % W
			var jn := maxi(j - 2, 0)
			var js := mini(j + 2, H - 1)
			var tw_u := clampf((_thermal[j * W + ip] - _thermal[j * W + im]) * 0.25 * THERMAL_WIND_K, -THERMAL_WIND_MAX, THERMAL_WIND_MAX)
			var tw_v := clampf((_thermal[jn * W + i] - _thermal[js * W + i]) * 0.25 * THERMAL_WIND_K, -THERMAL_WIND_MAX, THERMAL_WIND_MAX)
			var u := (wu[idx] + tw_u + _down_u[idx] * kat) * gain
			var eddy2 := _eddy_noise(i + 7, posmod(j + 5, H))  # outro padrão: nuvem fina e de chuva não coincidem
			var v := (wv[idx] + tw_v + _down_v[idx] * kat + eddy2 * _eddy_amp[j] * EDDY_WIND) * gain  # os sistemas de tempo ondulam o vento
			wind_u[idx] = u
			wind_v[idx] = v
			# O vento leva o vapor e as nuvens (advecção semi-lagrangiana).
			var sx := i - u * dt
			var sy := j + v * dt  # linhas crescem para o sul
			var qq := _sample(q, sx, sy)
			var cc := _sample(cloud, sx, sy)
			var hh := _sample(haze, sx, sy)

			var water := hgt[idx] < sea
			# Pressão local: terras baixas têm mais ar (Hellas ~2x Tharsis), então lá a água e a vida começam antes.
			var atm_loc := Physics.local_atmosphere(_atm, maxf(hgt[idx], sea))
			var lt := lat_t[idx] * lat_k
			var tc := global_c + static_t[idx] - lat_t[idx] + lt + season[j] * (SEASON_OCEAN if water else 1.0) \
				+ OCEAN_HEAT_EFFECT * (oa[idx] if water else _coast_anom(i, j))
			if water:
				tc -= OCEAN_COOLING * smoothstep(-5.0, 20.0, global_c + lt)  # a água esfria o ar em cima dela
			var air_k := smoothstep(0.05, 0.5, atm_loc)
			# Foehn: descendo a serra, o ar que deixou a água do outro lado aquece mais do que esfriou subindo.
			if sink[idx] > 0.0:
				var sat0 := 0.1 * exp(tc * 0.0693) * air_k
				if sat0 > 1e-6:
					tc += sink[idx] * FOEHN_K * (1.0 - minf(qq / sat0, 1.0))
			# Massa de ar: chega a temperatura de onde o ar veio (corrigida pela altitude) e volta aos poucos ao equilíbrio.
			var lapse := LAPSE * maxf(hgt[idx], 0.0)
			var a := 0.0
			if _air_ready:
				a = clampf((_sample(_theta, sx, sy) - lapse - tc) * (keep_sea if water else keep_land), -TA_MAX, TA_MAX)
			tc += a
			_ta2[idx] = a
			_theta2[idx] = tc + lapse
			temp_c[idx] = tc
			var sat := 0.1 * exp(tc * 0.0693) * air_k  # dobra a cada ~10 °C
			# A corrente leva o calor do mar; ele volta aos poucos à temperatura da latitude (mais fria onde há ressurgência).
			var s := _sample(sst, i - cur_u[idx] * dt, j + cur_v[idx] * dt)
			s = lerpf(s, lt - UPWELL_C, upwell[idx])  # atrás da ressurgência é terra: a água que chega vem do fundo, fria
			s += (lt - s) * sst_k
			if not water:
				s = lt
			_sst2[idx] = s
			_oa2[idx] = s - lt
			var t_water := global_c + s + season[j] * SEASON_OCEAN
			if water:
				qq += maxf(sat - qq, 0.0) * evap_k * smoothstep(SEA_ICE_C - 2.0, SEA_ICE_C, t_water)  # mar congelado não evapora
			else:
				# A floresta recicla a própria chuva (como a Amazônia) e espalha umidade vento abaixo.
				qq += maxf(sat - qq, 0.0) * land_evap_rate(dt, soil[idx] * smoothstep(-4.0, 0.0, tc), veg[idx])  # solo congelado não evapora
				# Usina de chuva: a colônia força umidade além do limite natural, chovendo onde o clima sozinho não chegaria.
				# Precisa de ar e de calor acima do congelamento: no Marte de hoje (6 mbar, -60 °C) ela não faz chover.
				qq += industry[idx] * minf(1.0, INDUSTRY_RATE * dt) * smoothstep(0.05, 0.5, atm_loc) * smoothstep(-5.0, 5.0, tc)
			# Subir esfria o ar: ele segura menos vapor e condensa. Sobe por montanha, por sistema de tempo e, em terra
			# quente e úmida, por convecção. Descer (sistema de tempo) aquece e abre o céu.
			var eddy := _eddy_noise(i, j, EDDY_STRETCH) if sat > 1e-6 else 0.0  # ar seco não condensa: nem calcula
			var rising := lift[idx] * 2.5 * smoothstep(0.0, 1.0, eddy) + eddy * _eddy_amp[j] * EDDY_STRENGTH * _storm_k[idx]  # a subida do relevo oscila com o tempo: a chuva da encosta tem pausas
			var convection := 0.0
			if not water and sat > 1e-6:
				# Pancadas: a convecção só acontece em manchas que andam e se renovam, não em toda terra úmida ao mesmo tempo.
				convection = CONV_MAX * smoothstep(-5.0, 20.0, tc) * smoothstep(0.3, 0.8, qq / sat) \
					* smoothstep(0.45, 0.85, 0.5 + 0.5 * eddy2)
			elif water and sat > 1e-6:
				# Efeito-mar: ar frio sobre mar mais quente é aquecido por baixo e sobe (neve de lago, pancadas no mar).
				convection = CONV_MAX * smoothstep(SEA_CONV_DT.x, SEA_CONV_DT.y, t_water - tc) * smoothstep(0.45, 0.85, 0.5 + 0.5 * eddy2)
			# Convergência: onde o vento se junta o ar só tem para onde subir (ZCIT, encontro da monção); onde se
			# separa, desce e abre o céu. Divergência em coordenadas de grade, com o cos(lat) do meridiano.
			var jn1 := maxi(j - 1, 0)
			var js1 := mini(j + 1, H - 1)
			var div := (_pu[j * W + (i + 1) % W] - _pu[j * W + (i + W - 1) % W]) * 0.5 \
				+ (_pv[jn1 * W + i] * weight[jn1 * W + i] - _pv[js1 * W + i] * weight[js1 * W + i]) / (float(js1 - jn1) * weight[idx])
			# Frente: ar de outra massa chegando. Quente (+) sobe devagar numa faixa larga; fria (-) levanta o ar com força.
			var gx := (ta[j * W + (i + 1) % W] - ta[j * W + (i + W - 1) % W]) * 0.5
			var gy := (ta[jn1 * W + i] - ta[js1 * W + i]) / float(js1 - jn1)
			var fr := clampf(-(u * gx + v * gy) * FRONT_K, -FRONT_MAX, FRONT_MAX)
			front[idx] = fr
			var lifting := clampf(rising * 0.5 + convection + clampf(-div * CONV_LIFT_K, -0.3, 0.4)
				+ (fr * 0.6 if fr > 0.0 else -fr), -0.4, 0.8)
			var sat_eff := sat * (1.0 - lifting)
			var excess := maxf(qq - sat_eff, 0.0)
			qq -= excess
			cc += excess
			if qq < sat_eff:
				var ev := minf(cc, (sat_eff - qq) * minf(1.0, 0.3 * dt))
				cc -= ev
				qq += ev
			cc -= cc * minf(1.0, 0.05 * dt)  # nuvem se dissolve sozinha, mesmo sem ar para reabsorvê-la
			# A usina de chuva da colônia força o ar a subir: a chuva dela não pode ficar presa pela regra dos episódios.
			var gate := smoothstep(RAIN_LIFT_GATE.x, RAIN_LIFT_GATE.y, maxf(lifting, industry[idx] * 0.5))
			var r := maxf(cc - RAIN_THRESHOLD, 0.0) * rain_k * gate
			cc -= r
			var liquid := r  # o que chega ao solo como água: chuva, ou o degelo da neve
			if not water:
				if tc < 0.0:
					snow[idx] = minf(snow[idx] + r * SNOW_GAIN, 1.0)  # abaixo de 0 °C a precipitação vira neve
					liquid = 0.0
				elif snow[idx] > 0.0:
					var melt := minf(snow[idx], MELT_RATE * dt * minf(tc * 0.2, 1.0))
					snow[idx] -= melt
					liquid += melt / SNOW_GAIN
			raining[idx] = r / dt if liquid > 0.0 or water else 0.0
			rain[idx] += (liquid / dt - rain[idx]) * avg_k
			_cloud2[idx] = cc
			# Nuvem fina: não chove nem gasta o vapor. Aparece onde o ar está úmido e o sistema de tempo favorece,
			# anda com o vento (vira faixas alongadas) e se desfaz onde o ar seca ou o céu abre.
			var rh := minf(qq / sat, 1.2) if sat > 1e-6 else 0.0
			var haze_target := HAZE_MAX * smoothstep(0.1, 0.5, rh) * smoothstep(0.35, 0.85, 0.5 + 0.5 * eddy2) \
				* smoothstep(0.01, 0.05, sat) * lerpf(0.5, 1.0, _eddy_amp[j])
			haze_target = maxf(haze_target, HAZE_MAX * smoothstep(0.02, 0.15, fr) * smoothstep(0.01, 0.05, sat))  # cirros antes da frente quente
			hh += (haze_target - hh) * minf(1.0, HAZE_RATE * dt)
			_haze2[idx] = hh
			sum_h += hh
			_q2[idx] = qq

			if water:
				veg[idx] = 0.0
				soil[idx] = 0.0
			else:
				soil[idx] = clampf(soil[idx] + liquid * 20.0 - SOIL_DECAY * dt, 0.0, 1.0)
				var warm := smoothstep(-10.0, 10.0, tc)
				var suit := maxf(warm, TUNDRA_COVER * smoothstep(-30.0, -12.0, tc)) * (1.0 - smoothstep(35.0, 50.0, tc)) * smoothstep(0.1, 0.5, atm_loc)
				# Aridez: o que conta é chuva ÷ evaporação potencial, que dobra a cada ~10 °C (relativa a 15 °C).
				# Mesma chuva vira floresta no frio e savana/deserto no calor (como no limite de Köppen).
				var pet := exp((tc - 15.0) * 0.0693)
				var target := clampf(maxf(rain[idx] * VEG_K / pet, snow[idx] * (1.0 - warm)), 0.0, 1.0) * suit  # no frio a neve é a água da tundra
				veg[idx] += (target - veg[idx]) * veg_k
				sum_v += veg[idx] * weight[idx]
				sum_w += weight[idx]
			sum_r += rain[idx]
			sum_c += cc

	_sum_v += sum_v
	_sum_w += sum_w
	_sum_r += sum_r
	_sum_c += sum_c
	_sum_h += sum_h


func step_end() -> void:
	var t := q
	q = _q2
	_q2 = t
	t = cloud
	cloud = _cloud2
	_cloud2 = t
	t = haze
	haze = _haze2
	_haze2 = t
	t = sst
	sst = _sst2
	_sst2 = t
	t = oa
	oa = _oa2
	_oa2 = t
	t = ta
	ta = _ta2
	_ta2 = t
	t = _theta
	_theta = _theta2
	_theta2 = t
	_air_ready = true
	mean_veg = _sum_v / _sum_w if _sum_w > 0.0 else 0.0
	mean_rain = _sum_r / N
	mean_cloud = _sum_c / N
	mean_haze = _sum_h / N


func _sample(a: PackedFloat32Array, x: float, y: float) -> float:
	x = fposmod(x, float(W))
	y = clampf(y, 0.0, H - 1.0)
	var x0 := int(x)
	var y0 := int(y)
	var x1 := (x0 + 1) % W
	var y1 := mini(y0 + 1, H - 1)
	var fx := x - x0
	var fy := y - y0
	return lerpf(lerpf(a[y0 * W + x0], a[y0 * W + x1], fx), lerpf(a[y1 * W + x0], a[y1 * W + x1], fx), fy)
