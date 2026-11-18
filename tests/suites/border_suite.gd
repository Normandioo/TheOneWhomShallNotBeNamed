extends "res://tests/test_suite.gd"
## Fronteiras desenhadas à mão (contornos) no núcleo, sem cena: validação, área, "está dentro" (inclusive atravessando a longitude 180° e cobrindo
## o polo), distância até a borda, troca de contorno e persistência. As linhas "ERROR" das recusas são esperadas.

const R := 8282.3
const T := 1000
var ALL := PackedStringArray(["politica", "cultural", "etnica", "linguistica", "religiosa", "racial"])


func _hits(r, lat: float, lon: float, tol: float, entity: int = 0) -> Array:
	return r.EntitiesAt(lat, lon, tol, ALL, entity, T)


func run() -> void:
	var path := out_dir.path_join("border_suite.db")
	for ext in ["", "-journal"]:
		DirAccess.remove_absolute(path + ext)
	var r = load("res://scripts/world/Registry.cs").new()
	r.Open(path)
	var pais: int = r.Create("pais", "Reino quadrado")
	var outro: int = r.Create("pais", "Reino vizinho")

	# Um contorno de 4 pontos: guarda os vértices, o centro vai para lat/lon e o raio é 0 (quem tem vértices é contorno).
	var quad := PackedFloat64Array([5, 15, 5, 25, 15, 25, 15, 15])
	var q: int = r.AddPolygonPlace("Quadrado", "regiao", quad, "desenhado à mão")
	var pl: Dictionary = r.Place(q)
	if r.PlaceVertices(q) != quad or pl.vertex_count != 4 or pl.radius_km != 0.0 or absf(pl.lat - 10.0) > 0.3 or absf(pl.lon - 20.0) > 0.01:
		return fail("o contorno guardado: %s / vértices %s" % [pl, r.PlaceVertices(q)])
	var esperado: float = R * R * deg_to_rad(10.0) * (sin(deg_to_rad(15.0)) - sin(deg_to_rad(5.0)))  # entre paralelos; os lados são arcos de círculo máximo, então difere um pouco
	if absf(r.PlaceAreaKm2(q) / esperado - 1.0) > 0.01:
		return fail("área do quadrado de 10°: %.0f km² (esperado ~%.0f)" % [r.PlaceAreaKm2(q), esperado])
	# Um octante da esfera tem área exata de 4πR²/8.
	var octante: int = r.AddPolygonPlace("Octante", "regiao", PackedFloat64Array([0, 0, 0, 90, 90, 0]), "")
	if absf(r.PlaceAreaKm2(octante) / (PI * R * R / 2.0) - 1.0) > 1e-9:
		return fail("o octante deveria ter πR²/2 = %.1f km², deu %.1f" % [PI * R * R / 2.0, r.PlaceAreaKm2(octante)])
	var fechado: int = r.AddPolygonPlace("Já fechado", "regiao", PackedFloat64Array([5, 15, 5, 25, 15, 25, 15, 15, 5, 15]), "")  # repetir o primeiro ponto no fim é aceito
	if r.Place(fechado).vertex_count != 4:
		return fail("o ponto final repetido deveria ser descartado")
	ok("contorno guardado (vértices, centro, raio 0); área do quadrado e do octante (πR²/2 exato)")

	# Recusas: nada pode ficar gravado.
	var n: int = r.Places("").size()
	r.AddPolygonPlace("Dois pontos", "regiao", PackedFloat64Array([0, 0, 10, 10]), "")
	r.AddPolygonPlace("Ímpar", "regiao", PackedFloat64Array([0, 0, 10, 10, 5]), "")
	r.AddPolygonPlace("Gravata", "regiao", PackedFloat64Array([5, 15, 15, 25, 15, 15, 5, 25]), "")           # os lados se cruzam
	r.AddPolygonPlace("Repetido", "regiao", PackedFloat64Array([5, 15, 5, 15, 15, 25, 15, 15]), "")         # dois pontos seguidos iguais
	r.AddPolygonPlace("Fora do planeta", "regiao", PackedFloat64Array([5, 15, 91, 25, 15, 25]), "")
	r.AddPolygonPlace("Em linha", "regiao", PackedFloat64Array([0, 0, 0, 10, 0, 20]), "")                  # sem área
	r.AddPolygonPlace("Gigante", "regiao", PackedFloat64Array([0, 0, 0, 120, 0, -120]), "")                # dá a volta no planeta
	r.AddPolygonPlace("   ", "regiao", quad, "")
	r.AddPolygonPlace("Tipo estranho", "planeta", quad, "")
	var demais := PackedFloat64Array()
	for i in 2001:
		demais.append_array([5.0 + sin(i) * 0.001, 5.0 + i * 0.001])
	r.AddPolygonPlace("Pontos demais", "regiao", demais, "")
	if r.Places("").size() != n:
		return fail("um contorno inválido foi aceito (%d lugares, eram %d)" % [r.Places("").size(), n])
	ok("recusados: 2 pontos, par incompleto, lados que se cruzam, ponto repetido, fora do planeta, sem área, grande demais, nome vazio, tipo e 2001 pontos")

	# Dentro e fora: contorno simples; o clique acha por dentro e por tolerância na borda.
	r.AddPresence(pais, q, "territorio", "alta")
	var dentro: Array = _hits(r, 10.0, 20.0, 0.0)
	if dentro.size() != 1 or not dentro[0].inside or dentro[0].distance_km != 0.0 or dentro[0].entity_id != pais:
		return fail("o centro do quadrado está dentro: %s" % [dentro])
	if _hits(r, 20.0, 20.0, 0.0).size() != 0:
		return fail("(20°, 20°) está fora do quadrado")
	var perto: Array = _hits(r, 15.3, 20.0, 100.0)
	var borda := rad_to_deg(atan(tan(deg_to_rad(15.0)) / cos(deg_to_rad(5.0))))  # o lado de 15°N é um círculo máximo: no meio (lon 20°) ele sobe a ~15,05°
	var esperada := (15.3 - borda) * R * PI / 180.0
	if perto.size() != 1 or perto[0].inside or absf(perto[0].distance_km - esperada) > 1.0:
		return fail("a ~%.0f km fora da borda norte, com tolerância de 100 km, é achado a essa distância: %s" % [esperada, perto.map(func(h): return h.distance_km)])
	if _hits(r, 15.3, 20.0, 20.0).size() != 0:
		return fail("com 20 km de tolerância o ponto a ~%.0f km da borda não é achado" % esperada)
	if _hits(r, 10.0, 20.0, 0.0, outro).size() != 0:
		return fail("o filtro por entidade vale para contornos")
	ok("contorno: dentro (distância 0), fora, tolerância na borda (~36 km) e filtro por entidade")

	# Contorno côncavo (um L): o vão do L está fora.
	var ele: int = r.AddPolygonPlace("Em L", "regiao", PackedFloat64Array([0, 0, 0, 10, 5, 10, 5, 5, 10, 5, 10, 0]), "")
	r.AddPresence(outro, ele, "territorio", "media")
	if _hits(r, 2.0, 2.0, 0.0, outro).size() != 1 or _hits(r, 7.0, 2.0, 0.0, outro).size() != 1 or _hits(r, 2.0, 8.0, 0.0, outro).size() != 1:
		return fail("os dois braços do L e o canto estão dentro")
	if _hits(r, 8.0, 8.0, 0.0, outro).size() != 0:
		return fail("o vão do L (8°, 8°) está fora")
	ok("contorno côncavo (L): braços dentro, vão fora")

	# Atravessa a longitude 180° e cobre o polo, sem caso especial.
	var linha: int = r.AddPolygonPlace("Ilhas da linha", "regiao", PackedFloat64Array([-5, 175, -5, -175, 5, -175, 5, 175]), "")
	var norte: int = r.AddPolygonPlace("Calota do norte", "regiao", PackedFloat64Array([80, -135, 80, -45, 80, 45, 80, 135]), "")
	var povo: int = r.Create("etnia", "Povo dos extremos")
	r.AddPresence(povo, linha, "presenca", "media")
	r.AddPresence(povo, norte, "presenca", "media")
	var lado_a := _hits(r, 0.0, 180.0, 0.0, povo).size()
	var lado_b := _hits(r, 0.0, -178.0, 0.0, povo).size()
	var lado_c := _hits(r, 0.0, 178.0, 0.0, povo).size()
	if lado_a != 1 or lado_b != 1 or lado_c != 1 or _hits(r, 0.0, 170.0, 0.0, povo).size() != 0 or _hits(r, 0.0, 0.0, 0.0, povo).size() != 0:
		return fail("o contorno deveria atravessar 180°: %d/%d/%d" % [lado_a, lado_b, lado_c])
	if _hits(r, 90.0, 0.0, 0.0, povo).size() != 1 or _hits(r, 88.0, 100.0, 0.0, povo).size() != 1 or _hits(r, 75.0, 0.0, 0.0, povo).size() != 0:
		return fail("a calota deveria conter o polo e 88°N, e não 75°N")
	ok("contorno atravessando a longitude 180° e cobrindo o polo")

	# O mais específico primeiro: um contorno pequeno dentro de um grande.
	var cidade: int = r.AddPolygonPlace("Bairro", "assentamento", PackedFloat64Array([9, 19, 9, 21, 11, 21, 11, 19]), "")
	var capital: int = r.Create("pais", "Cidade-estado")
	r.AddPresence(capital, cidade, "capital", "alta")
	var dois: Array = _hits(r, 10.0, 20.0, 0.0)
	if dois.size() != 2 or dois[0].entity_id != capital or dois[1].entity_id != pais:
		return fail("o bairro (menor) vem antes do quadrado: %s" % [dois.map(func(h): return h.place)])
	ok("o contorno menor vem primeiro quando há contornos aninhados")

	# MapItems traz os vértices e a área (do contorno e do disco); ponto não tem.
	var disco: int = r.AddPlace("Disco", "regiao", 30.0, 30.0, 600.0, "")
	var ponto: int = r.AddPlace("Ponto", "assentamento", 31.0, 31.0, 0.0, "")
	r.AddPresence(capital, disco, "presenca", "media")
	r.AddPresence(capital, ponto, "sede", "media")
	var itens: Array = r.MapItems(ALL, capital, T)
	var d_q: Dictionary = itens.filter(func(i): return i.place == "Bairro")[0]
	var d_d: Dictionary = itens.filter(func(i): return i.place == "Disco")[0]
	var d_p: Dictionary = itens.filter(func(i): return i.place == "Ponto")[0]
	if d_q.vertices.size() != 8 or d_q.area_km2 <= 0.0 or d_d.vertices.size() != 0 or absf(d_d.area_km2 / (PI * 600.0 * 600.0) - 1.0) > 0.01 or d_p.area_km2 != 0.0:
		return fail("MapItems: vértices e área do contorno, do disco e do ponto")
	ok("MapItems traz vértices e área (contorno e disco) e ponto sem área")

	# Trocar o contorno: valida, desfaz tudo se recusar; transforma disco em contorno; lugar inexistente é recusado.
	var antes: PackedFloat64Array = r.PlaceVertices(cidade)
	r.SetPlaceVertices(cidade, PackedFloat64Array([9, 19, 11, 21, 11, 19, 9, 21]))    # gravata: recusado
	if r.PlaceVertices(cidade) != antes:
		return fail("a troca recusada não pode alterar o contorno antigo")
	var novo := PackedFloat64Array([40, 40, 40, 44, 44, 44, 44, 40])
	if r.SetPlaceVertices(cidade, novo) != 1 or r.PlaceVertices(cidade) != novo or absf(r.Place(cidade).lat - 42.0) > 0.2:
		return fail("trocar o contorno")
	if _hits(r, 10.0, 20.0, 0.0, capital).size() != 0 or _hits(r, 42.0, 42.0, 0.0, capital).size() != 1:
		return fail("depois da troca o contorno vale no lugar novo, não no antigo")
	if r.SetPlaceVertices(disco, PackedFloat64Array([29, 29, 29, 31, 31, 31, 31, 29])) != 1 or r.Place(disco).radius_km != 0.0 or r.Place(disco).vertex_count != 4:
		return fail("um disco vira contorno e perde o raio")
	r.SetPlaceVertices(99999, novo)
	ok("trocar o contorno: valida, recusa sem alterar, disco vira contorno, lugar inexistente recusado")

	# Excluir: lugar em uso fica; livre leva os vértices.
	var livre: int = r.AddPolygonPlace("Engano", "regiao", PackedFloat64Array([50, 50, 50, 52, 52, 52]), "")
	r.DeletePlace(q)       # em uso pelo país
	r.DeletePlace(livre)
	if r.PlaceVertices(q).size() != 8 or r.PlaceVertices(livre).size() != 0 or r.Places("Engano").size() != 0:
		return fail("excluir: o lugar em uso fica com os vértices; o livre some com os dele")
	ok("excluir lugar: em uso fica; livre leva os vértices")

	# Um contorno de 2000 pontos (círculo de 5°): valida e responde rápido.
	var grande := PackedFloat64Array()
	for i in 2000:
		var a := TAU * i / 2000.0
		grande.append_array([60.0 + 5.0 * sin(a), 100.0 + 5.0 * cos(a) / cos(deg_to_rad(60.0))])
	var t0 := Time.get_ticks_msec()
	var g: int = r.AddPolygonPlace("Círculo de 2000 pontos", "regiao", grande, "")
	var reino_g: int = r.Create("pais", "Reino redondo")
	r.AddPresence(reino_g, g, "territorio", "media")
	var dentro_g := _hits(r, 60.0, 100.0, 0.0, reino_g).size()
	var ms := Time.get_ticks_msec() - t0
	print("MEDIDA     contorno de 2000 pontos: criar + consultar em %d ms" % ms)
	if g == 0 or dentro_g != 1 or ms > 3000:
		return fail("2000 pontos: dentro=%d, %d ms" % [dentro_g, ms])
	ok("contorno de 2000 pontos valida e responde em %d ms" % ms)

	# Persistência.
	r.Close()
	r.Open(path)
	if r.PlaceVertices(q) != quad or r.PlaceVertices(cidade) != novo or _hits(r, 10.0, 20.0, 0.0, pais).size() != 1 or r.Place(q).vertex_count != 4:
		return fail("reabrir perdeu os contornos")
	ok("reabrir conserva os contornos e as consultas")
	r.Close()
