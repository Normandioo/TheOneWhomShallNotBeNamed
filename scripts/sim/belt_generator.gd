## Cinturões de asteroides gerados a partir de distribuições reais, não de um catálogo: cada ponto é uma órbita
## kepleriana (a, e, i, nó, argumento do periélio, anomalia média em J2000) que a GPU resolve a cada quadro.
##
## Principal (entre Marte e Júpiter): 2,1 a 3,3 UA, com as lacunas de Kirkwood, onde a ressonância com Júpiter
## expulsa os asteroides (3:1 em 2,50 UA, 5:2 em 2,82, 7:3 em 2,96 e 2:1 em 3,28).
## Troianos de Júpiter: duas nuvens, 60° à frente (L4) e 60° atrás (L5) de Júpiter, na mesma órbita dele.
## Kuiper (além de Netuno): clássicos em ~44 UA, plutinos na ressonância 3:2 com Netuno (39,4 UA) e disco espalhado.
## Não é cada asteroide de verdade: é a forma estatística de cada cinturão. As posições de cada ponto são aleatórias
## (semente fixa, então sempre saem iguais).

const Ephemeris = preload("res://scripts/sim/ephemeris.gd")

const JUPITER_A := 5.2029  # UA
const NEPTUNE_RESONANCE_32 := 39.45  # UA

# Lacunas de Kirkwood: [semieixo central (UA), meia-largura (UA)].
const KIRKWOOD_GAPS := [[2.065, 0.012], [2.501, 0.02], [2.825, 0.015], [2.958, 0.012], [3.278, 0.02]]


## Cada gerador devolve {"orbit": PackedVector3Array (a, e, i em rad), "angles": PackedVector2Array (nó, argumento do
## periélio em rad), "phase": PackedVector2Array (anomalia média em J2000 em rad, brilho 0..1)}.
static func main_belt(count: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := _empty()
	while out["orbit"].size() < count:
		var a := rng.randfn(2.75, 0.33)
		if a < 2.1 or a > 3.3 or _in_kirkwood_gap(a):
			continue
		var e := minf(absf(rng.randfn(0.0, 0.16)), 0.4)
		if a * (1.0 - e) < 1.7:  # o periélio não passa de Marte: esses seriam asteroides próximos da Terra, outro grupo
			continue
		var inc := minf(absf(rng.randfn(0.0, 10.0)), 35.0)
		_add(out, rng, a, e, inc)
	return out


static func jupiter_trojans(count: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := _empty()
	var jupiter_mean_long: float = Ephemeris.PLANETS[4][3]
	for k in count:
		var side := 60.0 if k % 2 == 0 else -60.0  # L4 à frente, L5 atrás
		var e := minf(absf(rng.randfn(0.0, 0.06)), 0.2)
		var inc := minf(absf(rng.randfn(0.0, 12.0)), 35.0)
		var node := rng.randf() * TAU
		var peri := rng.randf() * TAU
		var mean_long := deg_to_rad(jupiter_mean_long + side + rng.randfn(0.0, 9.0))
		# Todos com o semieixo de Júpiter: o período igual os mantém ao lado dele (sem a libração real, que é lenta).
		_push(out, rng, JUPITER_A, e, deg_to_rad(inc), node, peri, wrapf(mean_long - node - peri, -PI, PI))
	return out


static func kuiper_belt(count: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := _empty()
	for k in count:
		var kind := rng.randf()
		var a: float
		var e: float
		var inc: float
		if kind < 0.55:  # clássicos
			a = clampf(rng.randfn(44.0, 2.2), 38.5, 50.0)
			e = minf(absf(rng.randfn(0.0, 0.07)), 0.2)
			inc = minf(absf(rng.randfn(0.0, 6.0)), 25.0)
		elif kind < 0.85:  # plutinos
			a = NEPTUNE_RESONANCE_32 + rng.randfn(0.0, 0.25)
			e = clampf(rng.randfn(0.22, 0.06), 0.05, 1.0 - 29.0 / a)  # periélio perto de Netuno, como o de Plutão (29,7 UA)
			inc = minf(absf(rng.randfn(0.0, 10.0)), 30.0)
		else:  # disco espalhado
			a = rng.randf_range(50.0, 90.0)
			e = rng.randf_range(0.2, minf(0.5, 1.0 - 32.0 / a))  # o periélio fica além de Netuno (30 UA)
			inc = minf(absf(rng.randfn(0.0, 15.0)), 40.0)
		_add(out, rng, a, e, inc)
	return out


static func _in_kirkwood_gap(a: float) -> bool:
	for gap in KIRKWOOD_GAPS:
		if absf(a - gap[0]) < gap[1]:
			return true
	return false


static func _empty() -> Dictionary:
	return {"orbit": PackedVector3Array(), "angles": PackedVector2Array(), "phase": PackedVector2Array()}


## Ângulos sorteados: nó, periélio e anomalia média em qualquer lugar da órbita.
static func _add(out: Dictionary, rng: RandomNumberGenerator, a: float, e: float, inc_deg: float) -> void:
	_push(out, rng, a, e, deg_to_rad(inc_deg), rng.randf() * TAU, rng.randf() * TAU, rng.randf_range(-PI, PI))


static func _push(out: Dictionary, rng: RandomNumberGenerator, a: float, e: float, inc: float, node: float,
		peri: float, mean_anomaly: float) -> void:
	out["orbit"].append(Vector3(a, e, inc))
	out["angles"].append(Vector2(node, peri))
	out["phase"].append(Vector2(mean_anomaly, rng.randf_range(0.45, 1.0)))
