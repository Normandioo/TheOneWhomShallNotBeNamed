extends "res://tests/test_suite.gd"
## Galeria dos pincéis na tela: cada modo pinta o mesmo traço sobre o mesmo pedaço do interior do continente, e uma
## captura mostra o resultado. Serve para olhar (e para ver que montanhas no interior não criam água).

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")
const TerrainBrush = preload("res://scripts/edit/terrain_brush.gd")

const CENTER := Vector2(640.0, 360.0)


func run() -> void:
	var cam = main.globe.camera
	for i in MapLayers.LAYERS.size():
		if MapLayers.LAYERS[i]["kind"] == "altitude":
			main.set_layer(i)
	var spot := EvronGeo.dir(-50.0, -60.0)  # interior do continente (achado pelo teste de edição)
	cam.look_at_dir(spot, 1.3)
	await frames(3)
	await save("9_galeria_0_original")
	var modes := [
		["1_montanhas_maciço", TerrainBrush.Op.MOUNTAINS, 450.0, 0.0],
		["2_montanhas_cristas", TerrainBrush.Op.MOUNTAINS, 450.0, 1.0],
		["3_elevar_liso", TerrainBrush.Op.RAISE, 700.0, 0.0],
		["4_elevar_rugoso", TerrainBrush.Op.RAISE, 700.0, 1.0],
	]
	for m in modes:
		await _stroke(m[1], m[2], m[3], 300.0)
		await save("9_galeria_" + m[0])
		main.commands.undo()
	# Erosão: primeiro faz uma cordilheira, depois erode por cima.
	await _stroke(TerrainBrush.Op.MOUNTAINS, 600.0, 1.0, 300.0)
	await save("9_galeria_5_antes_da_erosao")
	for i in 4:
		await _stroke(TerrainBrush.Op.ERODE, 900.0, 0.5, 300.0)
	await save("9_galeria_6_depois_da_erosao")
	for i in 5:
		main.commands.undo()
	# Vales: o mesmo maciço de cristas, entalhado pela água.
	await _stroke(TerrainBrush.Op.MOUNTAINS, 600.0, 1.0, 300.0)
	for i in 4:
		await _stroke(TerrainBrush.Op.VALLEYS, 300.0, 0.5, 300.0)
	await save("9_galeria_7_vales")
	for i in 5:
		main.commands.undo()
	ok("galeria de pincéis salva")


## Uma pincelada arrastada da esquerda para a direita, com semente fixa.
func _stroke(op: int, strength: float, roughness: float, radius: float) -> void:
	main.set_tool(op)
	main.brush.strength = strength
	main.brush.roughness = roughness
	main.brush.radius_km = radius
	main.brush.seed_value = 21
	await send(button(MOUSE_BUTTON_LEFT, true, CENTER + Vector2(-170, 30)))
	for i in range(1, 18):
		await send(motion(CENTER + Vector2(-170 + i * 20, 30 - i * 3), Vector2(20, -3)))
	await send(button(MOUSE_BUTTON_LEFT, false, CENTER + Vector2(170, -20)))
	main._show_brush(Vector3.ZERO)
	await frames(3)
