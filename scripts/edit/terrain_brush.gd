## O pincel de terreno: uma pincelada (apertar, arrastar, soltar) vira UM comando na pilha de desfazer.
## Durante a pincelada guarda a altura original de cada pixel na primeira vez que o mexe; ao soltar, empurra o
## comando com o "antes" e o "depois" só desses pixels.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const CommandStack = preload("res://scripts/edit/command_stack.gd")

enum Op { RAISE, LOWER, FLATTEN, SMOOTH }
const NAMES := ["Elevar", "Rebaixar", "Nivelar", "Suavizar"]
const SPACING := 0.25  # nova marca do pincel a cada 1/4 do raio percorrido

var op := Op.RAISE
var radius_km := 150.0
var strength := 100.0  # metros por marca no centro (elevar/rebaixar); nivelar e suavizar usam strength/500 por marca
var active := false

var _terrain: Terrain
var _stack: CommandStack
var _before := {}       # índice do pixel -> altura antes da pincelada
var _target := 0.0      # nivelar: a altura do ponto onde a pincelada começou
var _last := Vector3.ZERO


func _init(terrain: Terrain, stack: CommandStack) -> void:
	_terrain = terrain
	_stack = stack


func begin(n: Vector3) -> void:
	active = true
	_before = {}
	_target = _terrain.height_at(n)
	_dab(n)


## Continua a pincelada em n, se andou o bastante desde a última marca.
func drag(n: Vector3) -> void:
	if active and _angle(n, _last) * EvronGeo.RADIUS_KM >= radius_km * SPACING:
		_dab(n)


## Termina a pincelada e a registra como comando. Retorna quantos pixels mudaram.
func end() -> int:
	active = false
	if _before.is_empty():
		return 0
	var before := _before
	var after := {}
	for idx in before:
		after[idx] = _terrain.get_h(idx)
	var t := _terrain
	_stack.push("%s terreno (%d pontos)" % [NAMES[op], before.size()], t.write.bind(before), t.write.bind(after))
	_before = {}
	return before.size()


func _dab(n: Vector3) -> void:
	_last = n
	var d: Array = _terrain.disk(n, radius_km)
	var idx: PackedInt32Array = d[0]
	var w: PackedFloat32Array = d[1]
	var k := clampf(strength / 500.0, 0.02, 1.0)
	var means := PackedFloat32Array()
	if op == Op.SMOOTH:  # médias lidas antes de mexer, senão o resultado depende da ordem dos pixels
		means.resize(idx.size())
		for i in idx.size():
			means[i] = _terrain.neighbor_mean(idx[i])
	for i in idx.size():
		var p := idx[i]
		var h := _terrain.get_h(p)
		if not _before.has(p):
			_before[p] = h
		match op:
			Op.RAISE:
				h += strength * w[i]
			Op.LOWER:
				h -= strength * w[i]
			Op.FLATTEN:
				h += (_target - h) * w[i] * k
			Op.SMOOTH:
				h += (means[i] - h) * w[i] * k
		_terrain.set_h(p, h)


static func _angle(a: Vector3, b: Vector3) -> float:
	return atan2(a.cross(b).length(), a.dot(b))
