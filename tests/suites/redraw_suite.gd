extends "res://tests/test_suite.gd"
## "O traço vira a fronteira": um traço aberto de borda a borda do território passa a ser a borda dele. O que faltava até o traço entra, o
## que passava dele sai e fica sem dono; vizinho protegido não é tocado; ilhas ficam; desfazer volta tudo; e um traço longo (mais de 256
## pontos), inclusive um que só recorta, é gravado e relido.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const Territory = preload("res://scripts/world/Territory.cs")

const CENTER := Vector2(0.0, 100.0)   # lat, lon
const KM := 500.0
const EDGE := KM / 111.19            # o raio do disco em graus


func run() -> void:
	var reg = main.domains.registry
	var terr = main.territories
	var countries = main.territory
	await frames(3)
	var land: int = reg.Create("pais", "Pincel")
	var island := EvronGeo.dir(-14.0, 100.0)
	var paint := func(owner: int, center: Vector3, radius: float) -> void:
		countries.Begin()
		countries.Dab(center, radius, owner, false, -1)
		countries.End()
	paint.call(land, EvronGeo.dir(CENTER.x, CENTER.y), KM)
	paint.call(land, island, 150.0)
	var original: PackedByteArray = countries.Pack()

	# Um traço que vai e volta em relação à borda leste: começa e termina nela, sai 0,7° e entra 0,7°. 400 pontos.
	var weave := func(t: float) -> float: return EDGE + 0.7 * sin(TAU * 1.5 * t)
	var stroke := _arc(weave, -45.0, 45.0, 400)
	countries.SetTaken(countries, land)
	var plan = countries.PlanStroke(land, stroke, 0, false).get("plan")
	if plan == null or not plan.IsRedraw:
		return fail("de borda a borda, o traço redesenha a borda")
	if countries.Pack() != original:
		return fail("calcular não muda o mapa")
	if Territory.Walls([countries], plan).count == 0:
		return fail("a prévia mostra a linha")
	var edit = countries.ApplyBoundary(plan)
	var wrong := _sides(countries, land, weave, -38.0, 38.0)
	if wrong.total < 60 or wrong.bad > 0:
		return fail("depois, de um lado do traço é o país e do outro não: %d errados de %d (%s)" % [wrong.bad, wrong.total, wrong.example])
	if countries.OwnerAt(EvronGeo.dir(0.0, 96.0)) != land or countries.OwnerAt(island) != land:
		return fail("o resto do país e a ilha ficam")
	var walls: Dictionary = Territory.Walls([countries], null)
	var covered := 0
	var wanted := 0
	for i in range(30, stroke.size() - 30, 4):
		var at := EvronGeo.lat_lon(stroke[i])
		wanted += 1
		if _closest(walls, countries, at.x, at.y) < 0.15:
			covered += 1
	if covered < wanted * 0.85:
		return fail("a borda exata acompanha o traço: %d de %d" % [covered, wanted])
	ok("traço de borda a borda: entra o que faltava, sai o que passava, ilha e resto ficam, e a linha exata o acompanha")

	edit.Undo()
	if countries.Pack() != original or countries.BoundariesFor(land).size() != 0:
		return fail("desfazer volta o mapa e tira a linha")
	edit.Redo()
	if countries.BoundariesFor(land)[0].points.size() != stroke.size():
		return fail("o traço guarda todos os pontos: %d de %d" % [countries.BoundariesFor(land)[0].points.size(), stroke.size()])
	ok("desfazer e refazer; o traço longo guarda todos os pontos")

	# Desenhar de novo por cima, uns 13 km para fora (menos de 1,5 pixel do mapa). Duas linhas juntas se anulariam na tela: um trecho
	# refeito deixa guardado o traço antigo (ele ainda vale no resto), mas ali só o novo aparece; refeito inteiro, o antigo é aposentado.
	countries.SetTaken(countries, land)
	for span in [20.0, 45.0]:
		var shifted := func(t: float) -> float: return weave.call((lerpf(-span, span, t) + 45.0) / 90.0) + 0.12
		var on_top := _arc(shifted, -span, span, 200)
		var second_plan = countries.PlanStroke(land, on_top, 0, false).get("plan")
		if second_plan == null or not second_plan.IsRedraw:
			return fail("traço por cima de outro (%.0f°)" % span)
		var second = countries.ApplyBoundary(second_plan)
		var kept: int = countries.BoundariesFor(land).size()
		if kept != (2 if span < 45.0 else 1):
			return fail("traços guardados depois de refazer %.0f°: %d" % [span, kept])
		var both: Dictionary = Territory.Walls([countries], null)
		var near_new := 0
		var near_old := 0
		var samples := 0
		for i in range(40, 161, 6):
			var new_at := EvronGeo.lat_lon(on_top[i])
			var turn := lerpf(-span, span, i / 199.0)
			var old_r: float = weave.call((turn + 45.0) / 90.0)
			samples += 1
			near_new += int(_closest(both, countries, new_at.x, new_at.y) < 0.15)
			near_old += int(_closest(both, countries, CENTER.x + old_r * sin(deg_to_rad(turn)), CENTER.y + old_r * cos(deg_to_rad(turn))) < 0.5)
		if near_new < samples * 0.85 or near_old > samples * 0.15:
			return fail("por cima (%.0f°): vale só o traço novo (novo %d, antigo %d de %d)" % [span, near_new, near_old, samples])
		second.Undo()
		if countries.BoundariesFor(land).size() != 1 or countries.BoundariesFor(land)[0].points != stroke:
			return fail("desfazer devolve o traço antigo")
	edit.Undo()
	ok("traço por cima de outro: só o novo vale ali, e desfazer devolve o antigo")

	# Só recortar: começa e termina na borda, passando por dentro. A faixa sai; "Outro lado" troca qual pedaço fica.
	var inward := func(t: float) -> float: return EDGE - 1.2 * sin(PI * t)
	var cut = countries.PlanStroke(land, _arc(inward, -40.0, 40.0, 120), 0, false).get("plan")
	if cut == null or not cut.IsRedraw or countries.PlanAreaKm2(cut) != 0.0 or countries.PlanFreedKm2(cut) <= 0.0 or cut.ChoiceCount != 2:
		return fail("um traço por dentro só recorta, com a outra escolha disponível")
	var before_km2: float = countries.AreaKm2(land)
	var trimmed = countries.ApplyBoundary(cut)
	var strip: float = before_km2 - countries.AreaKm2(land)
	if strip <= 0.0 or strip > 0.4 * before_km2 or countries.OwnerAt(EvronGeo.dir(CENTER.x, CENTER.y + EDGE - 0.4)) != 0 \
			or countries.OwnerAt(EvronGeo.dir(CENTER.x, CENTER.y)) != land:
		return fail("sai só a faixa além do traço (%.0f km²)" % strip)
	# Gravar e reabrir um redesenho que só tirou área (sem pixel nenhum acrescentado).
	countries.SetTaken(null, 0)
	if not reg.SaveTerritoryLevels({"pais": countries}):
		return fail("gravar")
	var again = Territory.new()
	again.Setup(main.terrain)
	if not reg.LoadTerritoryLevel("pais", again) or again.Pack() != countries.Pack() or again.BoundariesFor(land).size() != 1:
		return fail("reabrir um redesenho que só recortou")
	trimmed.Undo()
	countries.SetTaken(countries, land)
	cut.Choose(1)
	var other = countries.ApplyBoundary(cut) if cut.Version == countries.Version else null
	if other == null:
		var redo = countries.PlanStroke(land, _arc(inward, -40.0, 40.0, 120), 0, false).get("plan")
		redo.Choose(1)
		other = countries.ApplyBoundary(redo)
	if countries.OwnerAt(EvronGeo.dir(CENTER.x, CENTER.y + EDGE - 0.4)) != land or countries.OwnerAt(EvronGeo.dir(CENTER.x, CENTER.y)) != 0:
		return fail("o outro lado: fica a faixa, sai o corpo")
	other.Undo()
	ok("traço que só recorta: sai a faixa (ou o outro lado), e o resultado é gravado e relido")

	# Vizinho protegido: o traço passa por cima dele e não toma nada.
	var neighbor: int = reg.Create("pais", "Vizinho")
	countries.SetTaken(null, 0)
	countries.SetTaken(countries, neighbor)
	paint.call(neighbor, EvronGeo.dir(CENTER.x, CENTER.y + EDGE + 2.5), 300.0)
	countries.SetTaken(countries, land)
	var neighbor_km2: float = countries.AreaKm2(neighbor)
	var wide := func(t: float) -> float: return EDGE + 2.2 * sin(PI * t)
	var over = countries.PlanStroke(land, _arc(wide, -40.0, 40.0, 160), 0, false).get("plan")
	if over == null:
		return fail("o traço por cima do vizinho ainda amplia pela terra livre")
	countries.ApplyBoundary(over)
	if countries.AreaKm2(neighbor) != neighbor_km2 or countries.AreaKm2(land) <= before_km2:
		return fail("o vizinho fica inteiro (%.0f -> %.0f) e o país cresce" % [neighbor_km2, countries.AreaKm2(neighbor)])
	ok("com Não invadir, o redesenho cresce pela terra livre e não toca o vizinho")
	countries.SetTaken(null, 0)

	# O mesmo traço guardado duas vezes (como num mundo em que se desenhou por cima com o lápis antigo): a tela usa um só.
	var single: int = Territory.Walls([countries], null).count
	countries.AdoptBoundaries(countries, land, land)
	var doubled: int = Territory.Walls([countries], null).count
	if single == 0 or doubled != single:
		return fail("duas linhas iguais valem como uma: %d trechos com uma, %d com duas" % [single, doubled])
	ok("duas linhas iguais não se anulam: a tela usa uma só")

	for id in [land, neighbor]:
		countries.ClearOwner(id)
		countries.ForgetOwnerBoundaries(id)
		reg.Delete(id)
	terr.refresh_palette()


## Os pontos de um arco em volta do centro do disco: o raio em graus vem de reach(t), t de 0 a 1.
func _arc(reach: Callable, from_deg: float, to_deg: float, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in count:
		var t := float(i) / (count - 1)
		var turn := deg_to_rad(lerpf(from_deg, to_deg, t))
		var r: float = reach.call(t)
		out.append(EvronGeo.dir(CENTER.x + r * sin(turn), CENTER.y + r * cos(turn)))
	return out


## Pixels do mapa a mais de 1 pixel do traço: 2 por amostra, um de cada lado. Dentro devem ser do país; fora, não.
func _sides(layer, owner: int, reach: Callable, from_deg: float, to_deg: float) -> Dictionary:
	var total := 0
	var bad := 0
	var example := ""
	for i in 41:
		var turn := deg_to_rad(lerpf(-45.0, 45.0, (i + 0.0) / 40.0))
		var t := (rad_to_deg(turn) + 45.0) / 90.0
		if rad_to_deg(turn) < from_deg or rad_to_deg(turn) > to_deg:
			continue
		for offset in [-0.3, 0.3]:
			var r: float = reach.call(t) + offset
			var own: bool = layer.OwnerAt(EvronGeo.dir(CENTER.x + r * sin(turn), CENTER.y + r * cos(turn))) == owner
			total += 1
			if own != (offset < 0.0):
				bad += 1
				example = "ângulo %.0f, lado %.1f, raio %.2f" % [rad_to_deg(turn), offset, r]
	return {"total": total, "bad": bad, "example": example}


func _closest(walls: Dictionary, layer, lat: float, lon: float) -> float:
	if int(walls.count) == 0:
		return INF
	var size: Vector2i = layer.Size
	var at := Vector2((lon / 360.0 + 0.5) * size.x, (0.5 - lat / 180.0) * size.y)
	var data: PackedFloat32Array = walls.segments.get_data().to_float32_array()
	var best := INF
	for i in range(0, data.size(), 4):
		var a := Vector2(data[i], data[i + 1])
		var b := Vector2(data[i + 2], data[i + 3])
		if a != b:
			best = minf(best, Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at))
	return best
