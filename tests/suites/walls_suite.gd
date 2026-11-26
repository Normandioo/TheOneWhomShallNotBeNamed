extends "res://tests/test_suite.gd"
## As linhas do pincel de fronteira na tela (Territory.Walls): saem inteiras, até em bicos mais finos que um pixel do mapa; só valem onde a
## pintura continua como o traço a deixou (pintar por cima e desfazer cuidam disso sozinhos); aparecem na prévia; e o rascunho as leva
## para o cadastro novo, que as guarda no banco.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const Territory = preload("res://scripts/world/Territory.cs")

# Um retângulo com uma fenda em V que termina num bico, em graus (lat, lon).
const TIP := [0.0, 22.0]
const SHAPE := [[-6.0, 20.0], [-6.0, 32.0], [-0.8, 32.0], [0.0, 22.0], [0.8, 32.0], [6.0, 32.0], [6.0, 20.0]]


func run() -> void:
	var reg = main.domains.registry
	var terr = main.territories
	var countries = main.territory
	await frames(3)
	if terr.walls().count != 0:
		return fail("sem pincel de fronteira não há linha à vista")
	# Pontos próximos, como o pincel de fronteira os colhe (o arredondamento do traço corta cantos na proporção do passo).
	var points := PackedVector3Array()
	for i in SHAPE.size():
		var a := Vector2(SHAPE[i][0], SHAPE[i][1])
		var b := Vector2(SHAPE[(i + 1) % SHAPE.size()][0], SHAPE[(i + 1) % SHAPE.size()][1])
		var steps := int(ceil(a.distance_to(b) / 0.4))
		for s in steps:
			var at: Vector2 = a.lerp(b, float(s) / steps)
			points.append(EvronGeo.dir(at.x, at.y))

	# Pelo rascunho: a prévia já mostra a linha; criar leva a linha para o país.
	main.domains.deselect()
	terr.start_draft("pais")
	var traced: Dictionary = terr.draft.PlanLoopClaim(terr.DRAFT, points, 0, false)
	if not traced.has("plan"):
		return fail("o contorno de teste: %s" % [traced])
	if Territory.Walls([terr.draft], traced.plan).count == 0 or Territory.Walls([terr.draft], null).count != 0:
		return fail("a linha aparece na prévia, antes de aplicar")
	terr.draft.ApplyBoundary(traced.plan)
	terr.draft_create("pais", "Linha", 0)
	await frames(6)
	var made: int = main.domains.current()
	if countries.BoundariesFor(made).size() != 1 or terr.draft.BoundariesFor(terr.DRAFT).size() != 0:
		return fail("o rascunho passa a linha ao país e fica sem ela: %d / %d" % [countries.BoundariesFor(made).size(), terr.draft.BoundariesFor(terr.DRAFT).size()])
	var full: Dictionary = terr.walls()
	# Perto do bico, a linha enviada é a mesma curva que a pintura usou, sem buraco: ali os dois lados têm o mesmo pixel de mapa.
	var closed := points.duplicate()
	closed.append(points[0])
	var checked := 0
	for n in countries.SmoothBoundary(closed):
		var at := EvronGeo.lat_lon(n)
		if Vector2(at.x - TIP[0], at.y - TIP[1]).length() > 1.5:
			continue
		checked += 1
		if _closest(full, at.x, at.y) > 0.1:
			return fail("falta linha junto à ponta do bico, em %s: %.2f pixels do mapa" % [at, _closest(full, at.x, at.y)])
	if full.count == 0 or checked < 10:
		return fail("o bico não foi conferido: %d pontos, %d trechos" % [checked, full.count])
	var side := [-6.0, 26.0]  # no meio do lado de baixo
	if _closest(full, side[0], side[1]) > 0.15:
		return fail("o lado reto também está na linha")
	if full.longest > 192:
		return fail("uma célula com trechos demais para a tela: %d" % full.longest)
	if int(main.gpu_sync.wall_stats.get("count", 0)) != int(full.count):
		return fail("as linhas vão para a placa de vídeo: %s" % [main.gpu_sync.wall_stats])
	await save("linhas_pais")
	ok("rascunho: linha na prévia, levada ao país, inteira até a ponta do bico, e enviada para a tela")

	# Pintar por cima: ali a linha sai; o resto fica. Desfazer a traz de volta.
	countries.Begin()
	countries.Dab(EvronGeo.dir(side[0], side[1]), 150.0, 0, false, made)
	var erased = countries.End()
	var cut: Dictionary = Territory.Walls([countries], null)
	if _closest(cut, side[0], side[1]) < 5.0 or _closest(cut, TIP[0], TIP[1]) > 2.0:
		return fail("apagado um pedaço, a linha sai só dali: %.2f e %.2f" % [_closest(cut, side[0], side[1]), _closest(cut, TIP[0], TIP[1])])
	erased.Undo()
	if _closest(Territory.Walls([countries], null), side[0], side[1]) > 0.15:
		return fail("desfazer traz a linha de volta")
	ok("apagar por cima tira a linha só daquele trecho, e desfazer a devolve")

	# Gravada no banco e relida.
	terr.flush()
	var again = Territory.new()
	again.Setup(main.terrain)
	reg.LoadTerritoryLevel("pais", again)
	if again.BoundariesFor(made).size() != 1 or Territory.Walls([again], null).count != Territory.Walls([countries], null).count:
		return fail("a linha volta do banco")
	# Sem a área, sem a linha; o próximo rascunho começa limpo.
	countries.ClearOwner(made)
	if Territory.Walls([countries], null).count != 0:
		return fail("sem território não sobra linha")
	terr.start_draft("pais")
	if Territory.Walls([terr.draft], null).count != 0:
		return fail("um rascunho novo não herda linhas")
	terr.discard_draft()
	reg.Delete(made)
	main.domains.deselect()
	terr.refresh_palette()
	ok("a linha é gravada com o mapa e some junto com o território")

	# O uso relatado: uma área feita com o pincel redondo e, com o pincel de fronteira, um ajuste que sai pouco mais de um pixel do mapa
	# para fora dela. Junto da linha ficam pixels que o traço não pintou, e ela tem de aparecer mesmo assim.
	var painted: int = reg.Create("pais", "Pincel")
	countries.Begin()
	countries.Dab(EvronGeo.dir(0.0, 60.0), 500.0, painted, false, -1)
	countries.End()
	var edge: float = 500.0 / 111.19  # o raio em graus
	var outer := func(i: int) -> Vector3:
		var turn := deg_to_rad(-30.0 + 1.5 * i)
		return EvronGeo.dir((edge + 0.11) * sin(turn), 60.0 + (edge + 0.11) * cos(turn))
	var lens := PackedVector3Array()
	for i in 41:  # o lado de fora, um fio além da borda pintada
		lens.append(outer.call(i))
	for i in range(40, -1, -5):  # a volta por dentro da área pintada
		var turn := deg_to_rad(-30.0 + 1.5 * i)
		lens.append(EvronGeo.dir((edge - 0.8) * sin(turn), 60.0 + (edge - 0.8) * cos(turn)))
	var adjust: Dictionary = countries.PlanLoopClaim(painted, lens, 0, false)
	if not adjust.has("plan") or countries.ApplyBoundary(adjust.plan) == null:
		return fail("o ajuste de teste: %s" % [adjust])
	var adjusted: Dictionary = Territory.Walls([countries], null)
	var covered := 0
	var wanted := 0
	for i in range(6, 35):
		var at := EvronGeo.lat_lon(outer.call(i))
		wanted += 1
		if _closest(adjusted, at.x, at.y) < 0.5:
			covered += 1
	if covered < wanted - 2:
		return fail("o ajuste de uma área do pincel redondo deve aparecer: %d de %d pontos (%d trechos)" % [covered, wanted, adjusted.count])
	countries.ClearOwner(painted)
	reg.Delete(painted)
	terr.refresh_palette()
	ok("ajuste fino de uma área do pincel redondo: a linha aparece")


## A distância (em pixels do mapa) do ponto até o trecho mais perto enviado para a tela.
func _closest(walls: Dictionary, lat: float, lon: float) -> float:
	if int(walls.count) == 0:
		return INF
	var size: Vector2i = main.territory.Size
	var at := Vector2((lon / 360.0 + 0.5) * size.x, (0.5 - lat / 180.0) * size.y)
	var data: PackedFloat32Array = walls.segments.get_data().to_float32_array()
	var best := INF
	for i in range(0, data.size(), 4):
		var a := Vector2(data[i], data[i + 1])
		var b := Vector2(data[i + 2], data[i + 3])
		if a == b:
			continue
		best = minf(best, Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at))
	return best
