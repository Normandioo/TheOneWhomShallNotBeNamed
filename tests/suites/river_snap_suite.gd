extends "res://tests/test_suite.gd"
## "Grudar no rio" (RiverSnap): com um índice de rios inventado, um traço solto de poucos pontos vai para o leito e segue todas as curvas,
## sem entrar no afluente; longe de rio, fica onde foi desenhado.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const RiverSnap = preload("res://scripts/world/RiverSnap.cs")
const PATH := "user://rios_de_teste.rgbaf"


func run() -> void:
	var bed := func(lon: float) -> float: return 0.12 * sin(TAU * lon / 0.8)
	var river: Array[Vector2] = []  # (lon, lat)
	for i in 101:
		river.append(Vector2(20.0 + 0.05 * i, bed.call(20.0 + 0.05 * i)))
	var branch: Array[Vector2] = []
	for i in 9:
		branch.append(river[50] + Vector2(0.0, 0.05 * i))
	_write([river, branch])

	var stroke := PackedVector3Array()
	for i in 11:  # um ponto a cada meia curva, ~5 km acima do leito
		var lon := 20.4 + 0.4 * i
		stroke.append(EvronGeo.dir(bed.call(lon) + 0.045, lon))
		if i == 5:  # a mão sobe um pouco pelo afluente
			stroke.append(EvronGeo.dir(river[50].y + 0.2, river[50].x + 0.02))
	var away := EvronGeo.dir(3.0, 25.0)
	stroke.append(away)
	var out: PackedVector3Array = RiverSnap.Snap(PATH, stroke, 15.0, 4096)

	for i in range(9, 87):
		var node := EvronGeo.dir(river[i].y, river[i].x)
		if _distance(out, node) > 0.4:
			return fail("a linha segue todas as curvas do leito: a %.1f km do rio em lon %.2f" % [_distance(out, node), river[i].x])
	var bank := PackedVector3Array()
	for at in river:
		bank.append(EvronGeo.dir(at.y, at.x))
	for i in out.size() - 1:
		if _distance(bank, out[i]) > 0.2:
			return fail("os pontos ficam no leito (sem entrar no afluente): %s a %.1f km" % [EvronGeo.lat_lon(out[i]), _distance(bank, out[i])])
	if EvronGeo.distance_km(out[-1], away) > 0.01:
		return fail("longe de rio o ponto fica onde foi desenhado")
	if RiverSnap.Snap("user://nao_existe", stroke, 15.0, 4096) != stroke:
		return fail("sem o arquivo de rios o traço não muda")
	if RiverSnap.Snap(PATH, stroke, 15.0, 50).size() > 50:
		return fail("o limite de pontos vale")
	DirAccess.remove_absolute(PATH)
	ok("grudar no rio: segue as curvas, ignora o afluente e solta longe do rio")


## A distância (km) do ponto até a linha.
func _distance(line: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	for i in line.size() - 1:
		best = minf(best, EvronGeo.distance_km(p, Geometry3D.get_closest_point_to_segment(p, line[i], line[i + 1]).normalized()))
	return best


## O mesmo formato de tools/build_indexed_rivers.py, com todos os trechos em todas as células da região.
func _write(courses: Array) -> void:
	var records := PackedFloat32Array()
	for course in courses:
		for i in course.size() - 1:
			var a: Vector2 = course[i]
			var b: Vector2 = course[i + 1]
			records.append_array(PackedFloat32Array([a.x / 360.0 + 0.5, 0.5 - a.y / 180.0, (b.x - a.x) / 360.0, (a.y - b.y) / 180.0, 1, 1, 0, 0]))
	var grid := PackedFloat32Array()
	grid.resize(1024 * 512 * 4)
	for row in range(240, 272):
		for col in range(560, 600):
			grid[(row * 1024 + col) * 4] = 1024 * 512
			grid[(row * 1024 + col) * 4 + 1] = records.size() / 8
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_32(0x32525645)
	file.store_32(512)
	file.store_buffer(grid.to_byte_array())
	file.store_buffer(records.to_byte_array())
