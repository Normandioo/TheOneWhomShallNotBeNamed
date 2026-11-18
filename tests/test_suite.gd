extends RefCounted
## Base das suítes do autoteste. Cada suíte herda desta, sobrescreve run() e chama fail() quando algo falha
## (o `return fail(...)` para a suíte; o executor para tudo na primeira falha).

var tree: SceneTree
var main: Node  # a cena principal; null nas suítes que não precisam dela
var out_dir := ""
var failed := false


func setup(scene_tree: SceneTree, main_node: Node, out: String) -> void:
	tree = scene_tree
	main = main_node
	out_dir = out


func run() -> void:
	pass


func fail(msg: String) -> void:
	push_error(msg)
	failed = true


func ok(msg: String) -> void:
	print("OK: ", msg)


func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


## Salva uma captura da janela inteira em out_dir/<name>.png.
func save(name: String) -> void:
	await frames(5)
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	tree.root.get_texture().get_image().save_png(path)
	print("captura: ", path)


## Envia um evento de entrada pelo caminho de verdade (janela -> Main) e espera um quadro.
func send(e: InputEvent) -> void:
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await frames(1)


func button(index: MouseButton, pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	return e


## Um giro da roda do mouse no centro da janela.
func wheel(index: MouseButton) -> InputEventMouseButton:
	return button(index, true, Vector2(640.0, 360.0))


func motion(pos: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = relative
	return e


func key(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	return e

