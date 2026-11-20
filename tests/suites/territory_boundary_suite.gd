extends "res://tests/test_suite.gd"

const Geo = preload("res://scripts/data/evron_geo.gd")
const Terrain = preload("res://scripts/world/Terrain.cs")
const Territory = preload("res://scripts/world/Territory.cs")
const Registry = preload("res://scripts/world/Registry.cs")
const WorldDb = preload("res://scripts/data/WorldDb.cs")
const CommandStack = preload("res://scripts/edit/command_stack.gd")


func _paint(layer, center: Vector3, radius: float, owner: int) -> Object:
	layer.Begin()
	layer.Dab(center, radius, owner, false, -1)
	return layer.End()


func _at(terrain: Terrain, x: int, y: int) -> Vector3:
	return terrain.DirOf(y * terrain.Size.x + x)


func _rectangle(layer: Territory, terrain: Terrain, rect: Rect2i, owner: int) -> void:
	layer.Begin()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			layer.Dab(_at(terrain, x, y), 15.0, owner, false, -1)
	layer.End()


func _line(terrain: Terrain, x: int) -> PackedVector3Array:
	return PackedVector3Array([_at(terrain, x, 54), _at(terrain, x, 78), _at(terrain, x, 104)])


func run() -> void:
	if main != null:
		await _editor()
		return
	var terrain := Terrain.new()
	terrain.Setup(Image.create(256, 128, false, Image.FORMAT_RF))
	var layer := Territory.new()
	layer.Setup(terrain)
	# Vermelho à esquerda, amarelo acima e azul entre os dois, como no exemplo de edição.
	_rectangle(layer, terrain, Rect2i(80, 38, 20, 65), 2)
	_rectangle(layer, terrain, Rect2i(100, 38, 60, 18), 3)
	_rectangle(layer, terrain, Rect2i(100, 56, 60, 47), 1)
	var island := _at(terrain, 130, 22)
	_paint(layer, island, 400, 1)
	var west := _at(terrain, 110, 80)
	var middle := _at(terrain, 138, 80)
	var east := _at(terrain, 152, 80)
	var north := _at(terrain, 121, 50)
	var original := layer.Pack()
	var short_line := PackedVector3Array([_at(terrain, 125, 60), _at(terrain, 125, 80)])
	if layer.PlanBoundaryClaim(2, short_line, 0).has("plan") or layer.PlanBoundaryClaim(4, _line(terrain, 125), 0).has("plan"):
		return fail("a linha incompleta e uma divisão sem contato com o país selecionado devem ser recusadas")
	var controls := _line(terrain, 145)
	var curve := layer.SmoothBoundary(controls)
	if curve.size() <= controls.size() or curve[0] != controls[0] or curve[-1] != controls[-1]:
		return fail("a suavização deve manter as pontas e os controles originais")
	var plan = layer.PlanBoundaryClaim(2, controls, 0).get("plan")
	if plan == null or plan.SourceOwner != 1 or layer.Pack() != original:
		return fail("o país cortado deve ser identificado pelo traço, sem alterar a camada durante o cálculo")
	var stack := CommandStack.new()
	var split = layer.ApplyBoundary(plan)
	if split == null or split.Count <= 0:
		return fail("um traço válido deve produzir um único comando")
	stack.push("Redesenhar fronteira", split)
	var id: int = plan.PathId
	if layer.OwnerAt(west) != 2 or layer.OwnerAt(middle) != 2 or layer.OwnerAt(east) != 1 or layer.OwnerAt(island) != 1 or layer.OwnerAt(north) != 3:
		return fail("o país selecionado deve ganhar o lado adjacente mesmo quando maior, sem mudar o amarelo ou a ilha")
	if layer.BoundariesFor(2)[0].points != controls or not layer.BoundariesFor(1).is_empty():
		return fail("o traço aplicado precisa continuar editável pelo país que ganhou o pedaço")
	stack.undo()
	if layer.Pack() != original or not layer.BoundariesFor(2).is_empty():
		return fail("desfazer restaura os pixels e o caminho juntos")
	stack.redo()
	if layer.OwnerAt(west) != 2 or layer.BoundariesFor(2)[0].id != id:
		return fail("refazer restaura a divisão e o caminho")
	ok("divisão automática transfere só o lado do país selecionado, preserva o vizinho e entra no histórico")

	var shifted := _line(terrain, 126)
	var adjusted = layer.PlanBoundaryClaim(2, shifted, id).get("plan")
	if adjusted == null:
		return fail("um traçado aplicado deve continuar editável")
	var repaint = _paint(layer, middle, 180, 3)
	if repaint == null or layer.ApplyBoundary(adjusted) != null or layer.PlanBoundaryClaim(2, shifted, id).has("plan"):
		return fail("um traço recalculado não pode sobrescrever pintura posterior")
	repaint.Undo()
	adjusted = layer.PlanBoundaryClaim(2, shifted, id).get("plan")
	stack.push("Remodelar", layer.ApplyBoundary(adjusted))
	if layer.OwnerAt(middle) != 1 or layer.OwnerAt(west) != 2 or layer.BoundariesFor(2)[0].points != shifted:
		return fail("remodelar devolve a faixa liberada ao vizinho")
	stack.undo()
	if layer.OwnerAt(middle) != 2 or layer.BoundariesFor(2)[0].points != controls:
		return fail("desfazer remodelagem devolve a extensão anterior e seus pontos")
	stack.redo()
	ok("remodelagem preserva o lado já conquistado e recusa sobrepor pintura posterior")

	var db_path := OS.get_user_data_dir().path_join("evron-fronteiras-%d.sqlite" % OS.get_process_id())
	var registry := Registry.new()
	var reopened := Territory.new()
	reopened.Setup(terrain)
	registry.Open(db_path)
	registry.SaveTerritory(layer)
	registry.Close()
	registry.Open(db_path)
	if not registry.LoadTerritory(reopened) or reopened.Pack() != layer.Pack() or reopened.BoundariesFor(2) != layer.BoundariesFor(2):
		return fail("reabrir deve carregar raster e fronteiras do mesmo salvamento")
	if not reopened.PlanBoundaryClaim(2, controls, id).has("plan"):
		return fail("um caminho reaberto deve continuar editável pelo país que recebeu a área")
	registry.Close()
	# Um mundo de verdade da versão 6 (só as 6 primeiras migrações: a camada numa linha só, sem fronteiras), depois aberto pela versão atual.
	DirAccess.remove_absolute(db_path)
	registry.OpenAtVersion(db_path, 6)
	registry.Close()
	var db := WorldDb.new()
	db.Open(db_path)
	db.Execute("insert into territory(id, w, h, data) values (1, %d, %d, X'%s')" % [terrain.Size.x, terrain.Size.y, layer.Pack().hex_encode()])
	db.Close()
	registry.Open(db_path)
	if not registry.LoadTerritory(reopened) or reopened.Pack() != layer.Pack() or not reopened.BoundariesFor(2).is_empty():
		return fail("mundos anteriores devem manter os IDs ao ganhar a coluna de fronteiras")
	registry.Close()
	DirAccess.remove_absolute(db_path)
	ok("salvamento conjunto e leitura dos mundos anteriores")

	stack.undo()
	stack.undo()
	_rectangle(layer, terrain, Rect2i(160, 56, 5, 47), 2)
	var two_contacts = layer.PlanBoundaryClaim(2, controls, 0).get("plan")
	var packed: PackedByteArray = layer.Pack()
	if two_contacts == null or two_contacts.ChoiceCount != 2 or two_contacts.Choice != 0:
		return fail("quando ambos os lados tocam o país escolhido, o plano oferece os dois lados")
	var small_km2: float = layer.PlanAreaKm2(two_contacts)
	var preview: Image = layer.PreviewImage(two_contacts)
	var east_px: int = terrain.PixelOf(east)
	if layer.Pack() != packed or preview.get_data().decode_u16(east_px * 2) != 2:
		return fail("a prévia mostra o lado escolhido sem mudar a camada")
	two_contacts.Choose(1)
	if layer.PlanAreaKm2(two_contacts) <= small_km2 or layer.PreviewImage(two_contacts).get_data().decode_u16(east_px * 2) == 2:
		return fail("escolher o outro lado troca o pedaço da prévia")
	two_contacts.Choose(0)
	if layer.ApplyBoundary(two_contacts) == null or layer.OwnerAt(east) != 2 or layer.OwnerAt(west) != 1:
		return fail("aplicar o lado escolhido muda só o menor pedaço")
	ok("quando os dois lados encostam: prévia sem mudar a camada, escolha explícita do lado (menor por padrão)")

	var seam := Territory.new()
	seam.Setup(terrain)
	_paint(seam, Geo.dir(0, 179), 2100, 1)
	_paint(seam, Geo.dir(14, 179), 800, 2)
	var crossing := PackedVector3Array([Geo.dir(0, 159), Geo.dir(0, 179), Geo.dir(0, -159)])
	var seam_plan = seam.PlanBoundaryClaim(2, crossing, 0).get("plan")
	if seam_plan == null or seam.ApplyBoundary(seam_plan) == null or seam.OwnerAt(Geo.dir(6, -176)) != 2 or seam.OwnerAt(Geo.dir(-6, -176)) != 1:
		return fail("o traço atravessando 180° deve dividir e transferir o lado correto")
	ok("divisão atravessa o antimeridiano")


func _screen(lat: float, lon: float) -> Vector2:
	return main.globe.camera.cam.unproject_position(Geo.dir(lat, lon) * main.globe.RADIUS)


func _click(pos: Vector2) -> void:
	await send(button(MOUSE_BUTTON_LEFT, true, pos))
	await send(button(MOUSE_BUTTON_LEFT, false, pos))


func _draw_cut(lon: float) -> void:
	var previous := _screen(14, lon)
	await send(button(MOUSE_BUTTON_LEFT, true, previous))
	for lat in range(12, -15, -2):
		var next := _screen(lat, lon + 0.6 * sin(float(lat) * 0.5))
		await send(motion(next, next - previous))
		previous = next
	if DisplayServer.get_name() != "headless" and lon == 4.0:
		await save("evron-fronteira-traco")
	await send(button(MOUSE_BUTTON_LEFT, false, previous))


func _editor() -> void:
	var hub = main.domains
	var selected: int = hub.registry.Create("pais", "Aren")
	var neighbor: int = hub.registry.Create("pais", "Dravia")
	var third: int = hub.registry.Create("pais", "Merídia")
	# Raios em km para o raio de 6.371 km (os mesmos graus que 1.600, 900 e 850 km tinham com 8.282 km).
	_paint(main.territory, Geo.dir(0, 4), 1230, neighbor)
	_paint(main.territory, Geo.dir(-1, -10), 690, selected)
	_paint(main.territory, Geo.dir(15, 4), 650, third)
	hub.refresh_palette()
	main.globe.focus(Geo.dir(0, 0), 2.6)
	await frames(40)
	await _click(_screen(-1, -10))
	if hub.current() != selected or not hub.sheet._boundary_brush.is_visible_in_tree():
		return fail("clicar no país deve selecioná-lo e revelar o pincel de fronteira na ficha")
	await _click(hub.sheet._boundary_brush.get_global_rect().get_center())
	var panel = hub.territory_panel
	if hub.territory_mode != "fronteira" or hub.territory_owner != selected or hub.sheet.visible:
		return fail("o pincel deve ativar o país clicado e liberar o mapa para desenhar")
	if not tree.root.get_visible_rect().encloses(panel.get_global_rect()):
		return fail("a barra de fronteiras deve caber na janela")
	if DisplayServer.get_name() != "headless":
		await save("evron-fronteira-antes")
	await _draw_cut(4.0)
	if main.territory.OwnerAt(Geo.dir(0, -1)) == selected or not panel._preview_row.visible:
		return fail("soltar o traço mostra a prévia e ainda não muda a camada: " + panel._boundary_status.text)
	panel.boundary_apply_requested.emit()
	if main.territory.OwnerAt(Geo.dir(0, -1)) != selected or main.territory.OwnerAt(Geo.dir(0, 10)) != neighbor or main.territory.OwnerAt(Geo.dir(13, 4)) != third:
		return fail("soltar o traço deve tomar só a faixa ao lado do país selecionado: " + panel._boundary_status.text)
	if main.territory.BoundariesFor(selected).size() != 1 or panel._paths.get_selected_id() != 0:
		return fail("o traço deve ficar disponível para editar e o pincel pronto para um novo gesto")
	if DisplayServer.get_name() != "headless":
		await save("evron-fronteira-depois")
	await _draw_cut(8.0)
	panel.boundary_apply_requested.emit()
	if main.territory.OwnerAt(Geo.dir(0, 6)) != selected or main.territory.OwnerAt(Geo.dir(13, 8)) != third or main.territory.BoundariesFor(selected).size() != 2:
		return fail("um segundo gesto deve ampliar a região sem exigir nova seleção: " + panel._boundary_status.text)
	main.undo()
	if main.territory.OwnerAt(Geo.dir(0, 6)) != neighbor or main.territory.OwnerAt(Geo.dir(0, -1)) != selected:
		return fail("desfazer deve reverter somente o último gesto")
	main.redo()
	if main.territory.OwnerAt(Geo.dir(0, 6)) != selected:
		return fail("refazer deve restaurar o último gesto")
	ok("editor: clique no país, pincel no menu e dois ganhos sucessivos, cada um aplicado depois da prévia")
