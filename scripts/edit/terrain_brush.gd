## O pincel de terreno: uma pincelada (apertar, arrastar, soltar) vira UM comando na pilha de desfazer.
## Durante a pincelada guarda a altura original de cada pixel na primeira vez que o mexe; ao soltar, empurra o
## comando com o "antes" e o "depois" só desses pixels.
##
## Modos (ver o estudo "Pincéis Procedurais de Terreno" no cofre):
##  - Elevar/Rebaixar: forma de colina com ondulação (fbm) em vez de um cone liso; `roughness` mistura o cone e o ruído.
##  - Nivelar: puxa para a altura do ponto inicial, com textura fraca de ruído.
##  - Suavizar: média ponderada; a intensidade decide quanto.
##  - Montanhas: ruído de cristas. SÓ SOMA relevo (nunca baixa o terreno): vale = sem mudança, então o continente
##    não ganha água. Rugosidade alta = cristas finas e altas; baixa = maciços arredondados.
##  - Erosão: erosão térmica. Move material das encostas íngremes (acima do ângulo de repouso) para as vizinhas mais
##    baixas: arredonda picos, entulha vales, conserva a massa.
##  - Vales: erosão hidráulica simplificada. Cada pixel escoa para o vizinho mais baixo; o fluxo acumulado rio abaixo
##    entalha o terreno (potência de corrente: quanto mais água e mais declive, mais fundo). Cria vales em árvore.
##    Nunca baixa a terra abaixo de 1 m (não cria mar) nem abaixo do vizinho para onde escoa (não cria poço).

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const CommandStack = preload("res://scripts/edit/command_stack.gd")
const TerrainNoise = preload("res://scripts/edit/terrain_noise.gd")

enum Op { RAISE, LOWER, FLATTEN, SMOOTH, MOUNTAINS, ERODE, VALLEYS }
const NAMES := ["Elevar", "Rebaixar", "Nivelar", "Suavizar", "Montanhas", "Erosão", "Vales"]
const MOUNTAIN_CAP := 1.5  # montanhas: uma pincelada sobe no máximo intensidade × ganho × 1,5 em cada pixel (sem platôs)
const INCISION := 0.02     # vales: fração do desnível entalhada por passada, por raiz da área de captação
const RIVER_SHARE := 0.04   # vales: o pixel vira rio se recebe a água de 4% do disco (mínimo RIVER_MIN pixels)
const RIVER_MIN := 12.0
const SPACING := 0.25      # nova marca do pincel a cada 1/4 do raio percorrido
const MOUNTAIN_GAIN := 6.0 # a intensidade (até 1000) vale ×6 em montanhas: picos de milhares de metros
const TALUS_M := 150.0     # erosão: desnível entre pixels vizinhos (12,7 km) que ainda se sustenta

var op := Op.RAISE
var radius_km := 150.0
var strength := 100.0  # metros por marca no centro (elevar/rebaixar); nivelar/suavizar/erosão: strength/500 por marca
var roughness := 0.5   # 0..1: quanto o ruído manda na forma
var active := false
var seed_value := -1   # -1 = sorteia uma semente nova a cada pincelada (um número fixo repete o mesmo relevo)

var _noise := TerrainNoise.new()
var _terrain: Terrain
var _stack: CommandStack
var _before := {}       # índice do pixel -> altura antes da pincelada
var _before_r := {}     # índice do pixel -> rio antes da pincelada
var _target := 0.0      # nivelar: a altura do ponto onde a pincelada começou
var _last := Vector3.ZERO
var last_flow := {}     # vales: pixel -> área de captação da última marca (para os testes e para estudar)


func _init(terrain: Terrain, stack: CommandStack) -> void:
	_terrain = terrain
	_stack = stack


func begin(n: Vector3) -> void:
	active = true
	_before = {}
	_before_r = {}
	_target = _terrain.height_at(n)
	_noise.set_seed(seed_value if seed_value >= 0 else randi())
	_dab(n)


## Continua a pincelada em n, se andou o bastante desde a última marca.
func drag(n: Vector3) -> void:
	if active and _angle(n, _last) * EvronGeo.RADIUS_KM >= radius_km * SPACING:
		_dab(n)


## Termina a pincelada e a registra como comando. Retorna quantos pixels mudaram.
func end() -> int:
	active = false
	if _before.is_empty() and _before_r.is_empty():
		return 0
	var before := _before
	var before_r := _before_r
	var after := {}
	var after_r := {}
	for idx in before:
		after[idx] = _terrain.get_h(idx)
	for idx in before_r:
		after_r[idx] = _terrain.get_river(idx)
	var t := _terrain
	_stack.push("%s terreno (%d pontos)" % [NAMES[op], before.size()], t.apply.bind(before, before_r), t.apply.bind(after, after_r))
	_before = {}
	_before_r = {}
	return before.size()


func _dab(n: Vector3) -> void:
	_last = n
	var d: Array = _terrain.disk(n, radius_km)
	var idx: PackedInt32Array = d[0]
	var w: PackedFloat32Array = d[1]
	if op == Op.ERODE:
		_erode(idx, w)
		return
	if op == Op.VALLEYS:
		_valleys(idx, w)
		return
	var k := clampf(strength / 500.0, 0.02, 1.0)
	var means := PackedFloat32Array()
	if op == Op.SMOOTH:  # médias lidas antes de mexer, senão o resultado depende da ordem dos pixels
		means.resize(idx.size())
		for i in idx.size():
			means[i] = _terrain.neighbor_mean(idx[i])
	var ridge_power := lerpf(1.4, 3.0, roughness)  # montanhas: maciço arredondado -> cristas finas
	for i in idx.size():
		var p := idx[i]
		var h := _terrain.get_h(p)
		_remember(p, h)
		match op:
			Op.RAISE:
				h += strength * w[i] * _hill_shape(p)
			Op.LOWER:
				h -= strength * w[i] * _hill_shape(p)
			Op.FLATTEN:
				var goal := _target + (_noise.fbm(_terrain.dir_of(p)) - 0.5) * roughness * 300.0
				h += (goal - h) * w[i] * k
			Op.SMOOTH:
				h += (means[i] - h) * w[i] * k
			Op.MOUNTAINS:
				# max(0, ...): vale não escava. A crista sobe de 0 a 1,5; abaixo de ~0,15 o terreno fica como está.
				var crest := maxf(pow(_noise.ridge(_terrain.dir_of(p)), ridge_power) * 1.5 - 0.15, 0.0)
				var cap: float = _before[p] + strength * MOUNTAIN_GAIN * MOUNTAIN_CAP
				h = minf(h + strength * MOUNTAIN_GAIN * w[i] * crest, maxf(cap, h))
		_terrain.set_h(p, h)


## Forma da marca de elevar/rebaixar: 1 (cone liso) misturado com ondulação (média 1, desvio ~1,2) pela rugosidade.
func _hill_shape(p: int) -> float:
	if roughness <= 0.0:
		return 1.0
	return maxf(lerpf(1.0, 1.0 + (_noise.fbm(_terrain.dir_of(p)) - 0.5) * 5.0, roughness), 0.0)


## Erosão térmica: cada pixel acima de TALUS_M em relação a um vizinho mais baixo (entre os 8) manda parte do excesso
## para ele. As mudanças são calculadas sobre as alturas de antes e aplicadas juntas: não depende da ordem.
func _erode(idx: PackedInt32Array, w: PackedFloat32Array) -> void:
	for pass_i in 3:  # 3 passadas por marca: o material escorre mais de um pixel
		_erode_pass(idx, w)


func _erode_pass(idx: PackedInt32Array, w: PackedFloat32Array) -> void:
	var k := clampf(strength / 500.0, 0.02, 1.0)
	var delta := {}
	var width := _terrain.size.x
	for i in idx.size():
		var p := idx[i]
		var x := p % width
		var y := p / width
		var h := _terrain.get_h(p)
		for dy in [-1, 0, 1]:
			var yy: int = y + dy
			if yy < 0 or yy >= _terrain.size.y:
				continue
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var q := yy * width + posmod(x + dx, width)
				var drop := h - _terrain.get_h(q)
				if drop > TALUS_M:
					var moved := (drop - TALUS_M) * 0.125 * k * w[i]  # 8 vizinhos: 1/8 cada, no máximo
					delta[p] = delta.get(p, 0.0) - moved
					delta[q] = delta.get(q, 0.0) + moved
	for p in delta:
		var h := _terrain.get_h(p)
		_remember(p, h)
		_terrain.set_h(p, h + delta[p])


## Erosão hidráulica, em 4 passadas por marca:
##  1) cada pixel do disco escoa para o vizinho mais baixo (D8);
##  2) a área de captação soma de cima para baixo;
##  3) cada pixel que escoa é entalhado em proporção a raiz(área − 1) × desnível (espigão não entalha, canal sim);
##  4) o sedimento entalhado desce o rio e deposita onde o terreno achata (planícies aluviais); um poço retém 60% e o
##     resto é levado embora (suspenso, rumo ao mar ou lago). Terra continua terra (piso de 1 m).
## No fim, os pixels com água suficiente (tronco principal com captação ≥ RIVER_SHARE do disco) viram rio na camada de rios.
func _valleys(idx: PackedInt32Array, w: PackedFloat32Array) -> void:
	var gain := clampf(strength / 100.0, 0.1, 10.0)
	var width := _terrain.size.x
	var area := {}
	var recv_last := {}
	for pass_i in 4:
		var recv := {}
		var drop := {}
		var order: Array = []
		for i in idx.size():
			var p := idx[i]
			var x := p % width
			var y := p / width
			var h := _terrain.get_h(p)
			var best := -1
			var best_drop := 0.0
			for dy in [-1, 0, 1]:
				var yy: int = y + dy
				if yy < 0 or yy >= _terrain.size.y:
					continue
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var q := yy * width + posmod(x + dx, width)
					var dd := (h - _terrain.get_h(q)) / (1.414 if dx != 0 and dy != 0 else 1.0)
					if dd > best_drop:
						best_drop = dd
						best = q
			if best >= 0:
				recv[p] = best
				drop[p] = best_drop
			order.append([h, i])
		order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])  # do mais alto ao mais baixo
		area = {}
		for it in order:
			var p := idx[it[1]]
			var a: float = area.get(p, 0.0) + 1.0
			area[p] = a
			if recv.has(p):
				area[recv[p]] = area.get(recv[p], 0.0) + a
		last_flow = area
		recv_last = recv
		# Entalhe e sedimento, do alto para baixo, sobre as alturas de antes da passada.
		var delta := {}
		var sediment := {}
		for it in order:
			var i: int = it[1]
			var p := idx[i]
			var h := _terrain.get_h(p)
			var cut := 0.0
			if recv.has(p):
				var d: float = drop[p]
				cut = minf(INCISION * gain * sqrt(maxf(area[p] - 1.0, 0.0)) * d * w[i], d * 0.5)
				cut = minf(cut, maxf(h - minf(h, 1.0), 0.0))  # terra continua terra
			var load: float = sediment.get(p, 0.0) + cut
			var flat := 0.6 if not recv.has(p) else clampf(1.0 - drop[p] / 60.0, 0.0, 1.0) * 0.6
			var deposit := load * flat
			delta[p] = deposit - cut
			if recv.has(p):
				sediment[recv[p]] = sediment.get(recv[p], 0.0) + load - deposit
		for p in delta:
			if absf(delta[p]) > 1e-6:
				var h := _terrain.get_h(p)
				_remember(p, h)
				_terrain.set_h(p, h + delta[p])
	# Rios: tronco principal onde passa água de sobra. Só conta o afluente de maior captação em cada confluência
	# (senão vários afluentes quase iguais viram uma mancha larga), e só em terra.
	var threshold := maxf(RIVER_SHARE * idx.size(), RIVER_MIN)
	var biggest_in := {}
	for p in recv_last:
		biggest_in[recv_last[p]] = maxf(biggest_in.get(recv_last[p], 0.0), area.get(p, 1.0))
	for i in idx.size():
		var p := idx[i]
		var a: float = area.get(p, 1.0)
		var main_stem: bool = not recv_last.has(p) or area.get(p, 1.0) >= biggest_in.get(recv_last[p], 0.0)
		if a >= threshold and main_stem and w[i] > 0.15 and _terrain.get_h(p) > 1.0:
			if not _before_r.has(p):
				_before_r[p] = _terrain.get_river(p)
			_terrain.set_river(p, maxf(_terrain.get_river(p), minf(0.4 + sqrt(a) * 0.03, 1.0)))


func _remember(p: int, h: float) -> void:
	if not _before.has(p):
		_before[p] = h


static func _angle(a: Vector3, b: Vector3) -> float:
	return atan2(a.cross(b).length(), a.dot(b))
