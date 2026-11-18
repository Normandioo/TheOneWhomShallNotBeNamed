extends Node3D
## A câmera livre do modo espaço: gira em volta de um foco (um corpo) e dá zoom sem limite prático,
## da superfície da Terra até 500 UA, em escala logarítmica (cada volta da roda multiplica a distância).
## O foco fica sempre na origem da cena (origem flutuante, ver SpaceScene): quem se move são os outros corpos.
## Arrastar = girar · roda = zoom · clique = escolher um corpo (avisa por `clicked`). A entrada vem de handle_input.

const SolarBodies = preload("res://scripts/sim/solar_bodies.gd")

## O jogador clicou (sem arrastar) na posição da janela.
signal clicked(screen_pos: Vector2)

const MIN_FACTOR := 1.03  # a câmera nunca chega mais perto que 3% do raio acima da superfície
const MAX_DIST := 500.0 * SolarBodies.UNIT_PER_AU
const WHEEL_FACTOR := 1.3
const SMOOTH := 7.0         # 1/s: rapidez com que a distância alcança o alvo
const FOCUS_SECONDS := 1.4  # tempo para a câmera viajar de um foco ao outro
const ORBIT_SENSITIVITY := 0.005  # rad por pixel arrastado
const FOV := 40.0
const FOCUS_ZOOM := 3.5     # distância ao focar em um corpo, em raios dele
const MAX_DEPTH_RATIO := 2e6  # far / near máximo

var cam: Camera3D
var focus_id := SolarBodies.Id.EARTH
var yaw := 0.6
var pitch := 0.35
var dist := 5.0 * 6.371     # unidades (1000 km)
var target_dist := 5.0 * 6.371
var pixel_shrink := 2       # a janela é desenhada numa resolução menor (visual pixelado)

var _from := PackedFloat64Array([0.0, 0.0, 0.0])  # onde o foco estava ao começar a viagem (UA)
var _blend := 1.0           # 0..1: progresso da viagem entre _from e o corpo em foco
var _dragging := false
var _drag_moved := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = FOV
	add_child(cam)
	cam.make_current()


## Pixels da janela por unidade a 1 unidade de distância; serve para saber quanto um objeto ocupa na tela.
func pixel_scale() -> float:
	return cam.get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(FOV) / 2.0))


## Até onde os corpos aparecem no tamanho e na posição reais; além disso a cena os aproxima e encolhe.
func body_range() -> float:
	return cam.far * 0.5


func min_dist() -> float:
	return SolarBodies.radius_units(focus_id) * MIN_FACTOR


## Onde está o foco agora (UA): o corpo em foco, ou o ponto da viagem até ele.
func focus_position(positions: Array) -> PackedFloat64Array:
	var to: PackedFloat64Array = positions[focus_id]
	if _blend >= 1.0:
		return to
	var s := _blend * _blend * (3.0 - 2.0 * _blend)
	return PackedFloat64Array([lerpf(_from[0], to[0], s), lerpf(_from[1], to[1], s), lerpf(_from[2], to[2], s)])


## Passa a olhar para o corpo `id`, a `zoom` raios de distância (o padrão enquadra o corpo inteiro).
func focus_on(id: int, positions: Array, zoom := FOCUS_ZOOM) -> void:
	_from = focus_position(positions)
	_blend = 0.0
	focus_id = id
	target_dist = clampf(SolarBodies.radius_units(id) * zoom, min_dist(), MAX_DIST)


## Visão geral: o Sol no centro e o sistema solar inteiro (até os cinturões de Kuiper) na tela.
func overview(positions: Array) -> void:
	_from = focus_position(positions)
	_blend = 0.0
	focus_id = SolarBodies.Id.SUN
	target_dist = 130.0 * SolarBodies.UNIT_PER_AU
	pitch = 0.7


## Termina a viagem e o zoom na hora (sem animação): usado ao abrir e nos testes.
func snap() -> void:
	_blend = 1.0
	dist = clampf(target_dist, min_dist(), MAX_DIST)
	advance(0.0)


## Avança a viagem e a suavização do zoom e posiciona a câmera.
func advance(delta: float) -> void:
	_blend = minf(_blend + delta / FOCUS_SECONDS, 1.0)
	target_dist = clampf(target_dist, min_dist(), MAX_DIST)
	# O zoom anda no logaritmo: a mesma sensação a 7 mil km e a 7 bilhões de km.
	dist = exp(lerpf(log(dist), log(target_dist), 1.0 - exp(-SMOOTH * delta)))
	dist = clampf(dist, min_dist(), MAX_DIST)
	rotation = Vector3(-pitch, yaw, 0.0)
	cam.position = Vector3(0.0, 0.0, dist)
	# Planos de corte pela distância: perto, enxerga o chão a poucos km; longe, alcança Netuno e o cinturão de Kuiper.
	# Corpos além da metade do far (o Sol visto da Terra, por exemplo) são aproximados e encolhidos pela cena
	# (SpaceScene.place): parecem iguais, e a razão far/near fica pequena (o Godot reclama acima de ~1e7).
	var surface := maxf(dist - SolarBodies.radius_units(focus_id), 0.01)
	cam.far = dist * 10.0 + 3000.0
	cam.near = maxf(maxf(0.001, minf(surface * 0.05, dist * 0.002)), cam.far / MAX_DEPTH_RATIO)


## Quem recebe a entrada é o SpaceView (fora do SubViewport, que não recebe mouse); ele repassa para cá.
func handle_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			target_dist = maxf(min_dist(), target_dist / WHEEL_FACTOR)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			target_dist = minf(MAX_DIST, target_dist * WHEEL_FACTOR)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_drag_moved = 0.0
			elif _drag_moved < 4.0:
				clicked.emit(mb.position)
	elif e is InputEventMouseMotion and _dragging:
		var mm := e as InputEventMouseMotion
		_drag_moved += mm.relative.length()
		yaw = wrapf(yaw - mm.relative.x * ORBIT_SENSITIVITY, -PI, PI)
		pitch = clampf(pitch + mm.relative.y * ORBIT_SENSITIVITY, -1.5, 1.5)
