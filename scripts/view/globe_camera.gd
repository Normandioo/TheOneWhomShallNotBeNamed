extends Node3D
## Câmera que gira em volta do globo e dá zoom em escala logarítmica, da órbita até perto do chão.
## Arrastar (esquerdo ou direito) = girar · roda = zoom · clique parado (esquerdo) = `clicked`. Com um pincel ativo
## o Main fica com o botão esquerdo e só o direito gira. A entrada vem de handle_input (o SubViewport não
## recebe mouse). A luz vai junto com a câmera: o lado que se olha está sempre iluminado, como num mapa.

## O usuário clicou (sem arrastar) na posição da janela.
signal clicked(screen_pos: Vector2)

const MIN_FACTOR := 1.002   # mais perto que isso não: ~17 km acima da superfície
const MAX_FACTOR := 12.0    # o planeta inteiro com folga
const WHEEL_FACTOR := 1.3
const SMOOTH := 7.0         # 1/s: rapidez com que a distância alcança o alvo
const ORBIT_SENSITIVITY := 0.005  # rad por pixel arrastado, a 3 raios; mais devagar quando perto
const FOV := 40.0

var orbit_speed := 1.0  # opções do jogador: 1 = o padrão
var zoom_speed := 1.0

var cam: Camera3D
var radius := 1.0            # raio do globo na cena
var yaw := 0.0
var pitch := 0.3
var dist := 3.0
var target_dist := 3.0

var _dragging := false
var _drag_moved := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = FOV
	add_child(cam)
	cam.make_current()
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(0.35, 0.45, 0.0)  # um pouco de lado e de cima: o relevo aparece
	cam.add_child(light)


## Olha para a direção n do globo (referencial do planeta) a `zoom` raios do centro.
func look_at_dir(n: Vector3, zoom: float) -> void:
	yaw = atan2(n.x, n.z)
	pitch = asin(clampf(n.y, -1.0, 1.0))
	target_dist = clampf(radius * zoom, radius * MIN_FACTOR, radius * MAX_FACTOR)
	snap()


## Termina o zoom na hora (sem animação): usado ao abrir e nos testes.
func snap() -> void:
	dist = target_dist
	advance(0.0)


func advance(delta: float) -> void:
	target_dist = clampf(target_dist, radius * MIN_FACTOR, radius * MAX_FACTOR)
	dist = exp(lerpf(log(dist), log(target_dist), 1.0 - exp(-SMOOTH * delta)))
	rotation = Vector3(-pitch, yaw, 0.0)
	cam.position = Vector3(0.0, 0.0, dist)
	var surface := maxf(dist - radius, radius * 0.0005)
	cam.near = surface * 0.05
	cam.far = dist + radius * 1.5


func handle_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			# O zoom age na altura acima do chão, não na distância ao centro: perto da superfície ainda aproxima.
			target_dist = radius + (target_dist - radius) / pow(WHEEL_FACTOR, zoom_speed)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			target_dist = radius + (target_dist - radius) * pow(WHEEL_FACTOR, zoom_speed)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
			if mb.pressed:
				_drag_moved = 0.0
			elif _drag_moved < 4.0 and mb.button_index == MOUSE_BUTTON_LEFT:
				clicked.emit(mb.position)
	elif e is InputEventMouseMotion and _dragging:
		var mm := e as InputEventMouseMotion
		_drag_moved += mm.relative.length()
		var k := ORBIT_SENSITIVITY * orbit_speed * clampf((dist - radius) / (2.0 * radius), 0.002, 1.0)
		yaw = wrapf(yaw - mm.relative.x * k, -PI, PI)
		pitch = clampf(pitch + mm.relative.y * k, -1.5, 1.5)
