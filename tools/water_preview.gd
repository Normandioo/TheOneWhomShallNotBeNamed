extends SceneTree
## godot --path . -s tools/water_preview.gd -- <pasta da prévia>

const Geo = preload("res://scripts/data/evron_geo.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")

var _region := Vector4.ZERO
var _texture: ImageTexture
var _enabled := true


func _initialize() -> void:
	_open.call_deferred()


func _open() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		_fail("Informe a pasta gerada por build_water_preview.py.")
		return
	var folder := args[0]
	var info = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("water.json")))
	if not info is Dictionary:
		_fail("Manifesto da prévia ausente ou inválido.")
		return
	var size := Vector2i(int(info.size[0]), int(info.size[1]))
	var data := FileAccess.get_file_as_bytes(folder.path_join("water.rgbaf"))
	if size.x <= 0 or size.y <= 0 or data.size() != size.x * size.y * 16:
		_fail("Dimensões ou textura da prévia inválidas.")
		return
	_texture = ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBAF, data))
	var u := (float(info.center[0]) + 0.0) / 4096.0
	var v := (float(info.center[1]) + 0.0) / 2048.0
	_region = Vector4(u, v, float(info.source_size[0]) / 4096.0, float(info.source_size[1]) / 2048.0)

	var main = load("res://scenes/main.tscn").instantiate()
	main.domains_db = ":memory:"
	main.save_path = ""
	main.options_path = ""
	root.add_child(main)
	current_scene = main
	for index in MapLayers.LAYERS.size():
		if MapLayers.LAYERS[index]["menu"] == "Satélite experimental":
			main.set_layer(index)
			break
	main._show_political(false)
	main.globe.camera.look_at_dir(Geo.dir(90.0 - v * 180.0, u * 360.0 - 180.0), 1.14)
	RenderingServer.global_shader_parameter_set("satellite_water_preview", _texture)
	root.window_input.connect(_on_input)
	_apply()
	await RenderingServer.frame_post_draw
	print("EVRON_WATER_PREVIEW_READY")


func _on_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_enabled = not _enabled
		_apply()


func _apply() -> void:
	RenderingServer.global_shader_parameter_set("satellite_water_region", _region if _enabled else Vector4.ZERO)
	root.title = "Evron (DEBUG) | Água %s | F8 para comparar" % ("experimental" if _enabled else "original")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
