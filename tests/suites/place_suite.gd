extends "res://tests/test_suite.gd"
## Lugares, presenças no mapa e demografia (etapa 5 do plano de domínios; critério 6), sem cena: o lugar compartilhado, as camadas que não
## se confundem, o clique que acha o cadastro, estimativas datadas, distribuições com denominador e as recusas de soma sem base comum.
## As linhas "ERROR" das recusas são esperadas: o teste confere que nada foi gravado.

const FOREVER := 9223372036854775807
const T1 := 1000
const T2 := 2000
const T3 := 3000
var ALL_LAYERS := PackedStringArray(["politica", "cultural", "etnica", "linguistica", "religiosa", "racial"])  # lista vazia = nenhuma camada


func run() -> void:
	var path := out_dir.path_join("place_suite.db")
	for ext in ["", "-journal"]:
		DirAccess.remove_absolute(path + ext)
	var r = load("res://scripts/world/Registry.cs").new()
	r.Open(path)

	var pais: int = r.Create("pais", "Reino de Aren")
	var cultura: int = r.Create("cultura", "Cultura aren")
	var etnia: int = r.Create("etnia", "Arenos")
	var religiao: int = r.Create("religiao", "Via do silêncio")
	var idioma: int = r.Create("idioma", "Arenês")
	var raca: int = r.Create("raca", "Elfos do vale")

	# Lugares: ponto e disco, validação das coordenadas, busca sem acento.
	var valdoria: int = r.AddPlace("Valdória", "assentamento", 10.0, 20.0, 0.0, "")
	var vale: int = r.AddPlace("Vale de Aren", "regiao", 12.0, 21.0, 600.0, "área aproximada")
	var n: int = r.Places("").size()
	r.AddPlace("Polo errado", "assentamento", 91.0, 0.0, 0.0, "")          # latitude fora de −90..90
	r.AddPlace("Longe demais", "assentamento", 0.0, 181.0, 0.0, "")        # longitude fora de −180..180
	r.AddPlace("Raio negativo", "regiao", 0.0, 0.0, -5.0, "")
	r.AddPlace("Tipo estranho", "planeta", 0.0, 0.0, 0.0, "")
	r.AddPlace("   ", "assentamento", 0.0, 0.0, 0.0, "")
	if r.Places("").size() != n or r.Places("valdoria").size() != 1 or r.Place(vale).radius_km != 600.0:
		return fail("lugares: validação ou busca (%d)" % r.Places("").size())
	ok("lugares: ponto e disco; latitude, longitude, raio, tipo e nome inválidos recusados; busca sem acento")

	# O mesmo lugar em várias fichas (é o mesmo registro) e cada tipo de entidade numa camada diferente.
	var cap: int = r.AddPresence(pais, valdoria, "capital", "alta")
	r.AddPresence(religiao, valdoria, "sede", "alta")                  # a sede da religião é o MESMO lugar
	r.AddPresence(pais, vale, "territorio", "media")
	r.AddPresence(cultura, vale, "presenca", "media")
	r.AddPresence(etnia, vale, "origem", "baixa")
	r.AddPresence(idioma, vale, "presenca", "media")
	r.AddPresence(raca, vale, "presenca", "desconhecida")
	if r.Places("").size() != n:
		return fail("reutilizar o lugar não pode duplicá-lo")
	var camadas := {}
	for it in r.MapItems(ALL_LAYERS, 0, T1):
		camadas[it.layer] = true
	if camadas.keys().size() != 6 or not camadas.has("politica") or not camadas.has("racial"):
		return fail("deveria haver as 6 camadas, uma por tipo de entidade: %s" % [camadas.keys()])
	if r.MapItems(PackedStringArray(["religiosa"]), 0, T1).size() != 1 or r.MapItems(PackedStringArray(["politica", "cultural"]), 0, T1).size() != 3:
		return fail("filtro por camada")
	if r.MapItems(ALL_LAYERS, pais, T1).size() != 2 or r.PresencesOf(pais, T1)[0].place != "Valdória" or r.PresencesOf(pais, T1)[0].role != "capital":
		return fail("as presenças de uma entidade só")
	r.AddPresence(pais, valdoria, "capital", "alta")                   # repetição: mesma entidade + lugar + função
	r.AddPresence(pais, valdoria, "planeta", "alta")                   # função inválida
	if r.PresencesOf(pais, T1).size() != 2:
		return fail("presença repetida ou função inválida foi aceita")
	if r.MapItems(PackedStringArray(), 0, T1).size() != 0 or r.EntitiesAt(12.5, 21.5, 0.0, PackedStringArray(), 0, T1).size() != 0:
		return fail("sem nenhuma camada pedida não há presença (lista vazia não significa todas)")
	ok("o mesmo lugar em duas fichas (capital do país, sede da religião); seis camadas, uma por tipo; filtro por camada e por entidade; repetição recusada")

	# Presença datada: a capital muda de lugar; consultar antes e depois.
	var novo: int = r.AddPlace("Nova Aren", "assentamento", 15.0, 25.0, 0.0, "")
	r.EndPresence(cap, T2)
	r.AddPresenceDuring(pais, novo, "capital", "alta", T2, FOREVER)
	var antes: Array = r.PresencesOf(pais, T2 - 1).filter(func(p): return p.role == "capital")
	var depois: Array = r.PresencesOf(pais, T2).filter(func(p): return p.role == "capital")
	if antes.size() != 1 or antes[0].place != "Valdória" or depois.size() != 1 or depois[0].place != "Nova Aren":
		return fail("a capital deveria mudar exatamente em %d (fim excluído)" % T2)
	r.EndPresence(cap, T3)  # já encerrada: recusado
	ok("presença datada: a capital muda de lugar numa data, fim excluído")

	# O clique: acha pelo disco ou pela tolerância do ponto; o mais específico primeiro; as camadas e a entidade filtram.
	var no_vale: Array = r.EntitiesAt(12.5, 21.5, 0.0, ALL_LAYERS, 0, T1)
	if no_vale.size() != 5 or not no_vale[0].inside:
		return fail("dentro do Vale de Aren deveria haver 5 presenças (país, cultura, etnia, idioma, raça): %d" % no_vale.size())
	if r.EntitiesAt(12.5, 21.5, 0.0, PackedStringArray(["politica"]), 0, T1).size() != 1 or r.EntitiesAt(12.5, 21.5, 0.0, ALL_LAYERS, etnia, T1).size() != 1:
		return fail("o clique também respeita a camada e a entidade")
	if r.EntitiesAt(10.0, 20.5, 0.0, ALL_LAYERS, 0, T1).filter(func(h): return h.place == "Valdória").size() != 0:
		return fail("0,5° (~72 km) de um ponto sem tolerância não é um clique nele")
	if r.EntitiesAt(10.0, 20.5, 100.0, ALL_LAYERS, 0, T1).filter(func(h): return h.place == "Valdória" and not h.inside).size() != 2:
		return fail("com 100 km de tolerância, o ponto (capital e sede) deveria ser achado, fora do disco")
	if r.EntitiesAt(-40.0, -100.0, 50.0, ALL_LAYERS, 0, T1).size() != 0:
		return fail("um clique em lugar nenhum não acha nada")
	ok("clique no mapa: dentro do disco, tolerância no ponto, mais específico primeiro, filtro de camada e de entidade")

	# O disco atravessa o limite de longitude e cobre o polo (distância pela esfera, não pela grade).
	var emenda: int = r.AddPlace("Linha da data", "regiao", 0.0, 179.9, 100.0, "")
	var topo: int = r.AddPlace("Gelo do norte", "regiao", 89.9, 0.0, 100.0, "")
	r.AddPresence(raca, emenda, "presenca", "baixa")
	r.AddPresence(raca, topo, "presenca", "baixa")
	if r.EntitiesAt(0.0, -179.9, 0.0, ALL_LAYERS, raca, T1).filter(func(h): return h.place == "Linha da data").size() != 1:
		return fail("o disco deveria atravessar a longitude 180°")
	if r.EntitiesAt(89.9, 180.0, 0.0, ALL_LAYERS, raca, T1).filter(func(h): return h.place == "Gelo do norte").size() != 1:
		return fail("o disco deveria cobrir o polo")
	ok("disco atravessando a longitude 180° e cobrindo o polo")

	# Estimativas: número (faixa) ou nível, nunca os dois e nunca um virando o outro; datadas, sem olhar para o futuro.
	var e1: int = r.AddEstimate(pais, vale, T1, 1000, 1500, "media", "censo antigo")
	var e2: int = r.AddEstimate(pais, vale, T2, 2000, 2000, "alta", "censo novo")
	var nivel: int = r.AddEstimateLevel(pais, valdoria, T1, "alta", "baixa", "rumor")
	var antes_ests: int = r.EstimatesOf(pais, FOREVER - 1).size()
	r.AddEstimate(pais, vale, T3, 500, 100, "media", "")               # faixa invertida
	r.AddEstimate(pais, vale, T3, -5, 10, "media", "")                 # negativa
	r.AddEstimateLevel(pais, vale, T3, "enorme", "media", "")          # nível desconhecido
	r.AddEstimate(pais, vale, T3, 1, 2, "certeza total", "")           # certeza fora da lista
	if r.EstimatesOf(pais, FOREVER - 1).size() != antes_ests:
		return fail("uma estimativa inválida foi aceita")
	var agora: Array = r.EstimatesOf(pais, T2)
	var do_vale: Dictionary = agora.filter(func(e): return e.place == "Vale de Aren")[0]
	var do_passado: Dictionary = r.EstimatesOf(pais, T2 - 1).filter(func(e): return e.place == "Vale de Aren")[0]
	var da_cidade: Dictionary = agora.filter(func(e): return e.place == "Valdória")[0]
	if do_vale.low != 2000.0 or do_vale.basis != "habitantes" or do_passado.low != 1000.0 or do_passado.high != 1500.0:
		return fail("a estimativa vigente em cada data: %s | %s" % [do_vale, do_passado])
	if da_cidade.level != "alta" or da_cidade.low is float or str(da_cidade.low) != "":
		return fail("nível sem número não pode ganhar número: %s" % [da_cidade])
	if r.EstimatesOf(pais, T1 - 1).size() != 0:
		return fail("antes da primeira estimativa não há estimativa (nada é projetado para trás)")
	ok("estimativas: faixa ou nível, datadas (cada data mostra a vigente), nível não vira número, entradas inválidas recusadas")

	# Critério 6: o idioma oficial é um vínculo; os falantes são outra informação (e a base de contagem é outra).
	r.Link(pais, idioma, "idioma_oficial")
	var falantes: int = r.AddEstimate(idioma, vale, T2, 800, 900, "baixa", "")
	var eh_oficial: bool = r.Linked(pais, "idioma_oficial", T2, false) == [idioma]
	var ests_idioma: Array = r.EstimatesOf(idioma, T2)
	if not eh_oficial or ests_idioma.size() != 1 or ests_idioma[0].basis != "falantes" or do_vale.basis != "habitantes":
		return fail("idioma oficial e falantes são informações distintas, em bases distintas")
	var bases := [r.EstimatesOf(etnia, T2), r.EstimatesOf(religiao, T2)]
	var e_etnia: int = r.AddEstimate(etnia, vale, T2, 1200, 1300, "media", "")
	var e_rel: int = r.AddEstimate(religiao, vale, T2, 700, 800, "media", "")
	if r.EstimatesOf(etnia, T2)[0].basis != "integrantes" or r.EstimatesOf(religiao, T2)[0].basis != "adeptos":
		return fail("etnia conta integrantes; religião, adeptos")
	ok("critério 6: idioma oficial (vínculo) e falantes (estimativa) distintos; habitantes, integrantes, falantes e adeptos são bases diferentes")

	# Somas: só com base, lugar e data comuns, número e categorias declaradas exclusivas.
	var s: Dictionary = r.SumEstimates(PackedInt64Array([e2, falantes]))
	if s.ok or not s.reason.contains("bases diferentes"):
		return fail("habitantes + falantes não se somam: %s" % [s])
	s = r.SumEstimates(PackedInt64Array([e_etnia, e_rel]))
	if s.ok or not s.reason.contains("bases diferentes"):
		return fail("integrantes + adeptos não se somam: %s" % [s])
	var outra_etnia: int = r.Create("etnia", "Dravos")
	var ee1: int = r.AddEstimate(etnia, vale, T2, 1200, 1300, "media", "")
	var ee2: int = r.AddEstimate(outra_etnia, vale, T2, 300, 400, "media", "")
	s = r.SumEstimates(PackedInt64Array([ee1, ee2]))
	if s.ok or not s.reason.contains("exclusivas"):
		return fail("duas etnias sem exclusividade declarada não se somam (uma pessoa pode ser das duas): %s" % [s])
	if r.SumEstimates(PackedInt64Array([e1, e2])).ok or not r.SumEstimates(PackedInt64Array([e1, e2])).reason.contains("datas diferentes"):
		return fail("estimativas de datas diferentes não se somam")
	if r.SumEstimates(PackedInt64Array([e2, nivel])).ok or r.SumEstimates(PackedInt64Array([e2])).ok or r.SumEstimates(PackedInt64Array([e2, e2])).ok:
		return fail("lugares diferentes, uma só estimativa e a mesma entidade duas vezes não se somam")
	var so_nivel: int = r.AddEstimateLevel(outra_etnia, vale, T2, "baixa", "baixa", "")
	if r.SumEstimates(PackedInt64Array([ee1, so_nivel])).ok:
		return fail("estimativa só com nível não tem número")
	# Declaradas exclusivas na mesma distribuição (mesmo lugar e data): agora soma.
	var den: int = r.AddEstimate(pais, vale, T2, 1600, 1800, "media", "")
	var d_etnia: int = r.AddDistribution(pais, vale, T2, "etnia", den, true, true, "media", "", PackedInt64Array([etnia, outra_etnia]), PackedFloat64Array([75.0, 25.0]))
	s = r.SumEstimates(PackedInt64Array([ee1, ee2]))
	if not s.ok or s.low != 1500.0 or s.high != 1700.0:
		return fail("com as categorias exclusivas declaradas a soma é 1500–1700: %s" % [s])
	ok("somas: bases diferentes, datas diferentes, só nível, mesma entidade, uma só e etnias sem exclusividade recusadas; com exclusividade declarada, soma a faixa")

	# Distribuições: completa+exclusiva = 100%; incompleta guarda o desconhecido; não exclusiva (idiomas) pode passar de 100.
	var rel2: int = r.Create("religiao", "Culto das águas")
	var n_dist: int = r.CompositionsOf(pais, T3).size()
	r.AddDistribution(pais, vale, T3, "religiao", 0, true, true, "media", "", PackedInt64Array([religiao, rel2]), PackedFloat64Array([60.0, 30.0]))       # completa e só 90%
	r.AddDistribution(pais, vale, T3, "religiao", 0, true, false, "media", "", PackedInt64Array([religiao, rel2]), PackedFloat64Array([70.0, 40.0]))      # exclusiva passando de 100
	r.AddDistribution(pais, vale, T3, "religiao", 0, true, false, "media", "", PackedInt64Array([etnia]), PackedFloat64Array([10.0]))                    # categoria do tipo errado
	r.AddDistribution(pais, vale, T3, "religiao", 0, true, false, "media", "", PackedInt64Array([religiao, religiao]), PackedFloat64Array([10.0, 10.0]))  # repetida
	r.AddDistribution(pais, vale, T3, "religiao", 0, true, false, "media", "", PackedInt64Array([religiao]), PackedFloat64Array([120.0]))               # acima de 100
	r.AddDistribution(pais, vale, T3, "cor", 0, true, false, "media", "", PackedInt64Array([religiao]), PackedFloat64Array([10.0]))                     # dimensão inválida
	r.AddDistribution(pais, vale, T3, "religiao", den, true, false, "media", "", PackedInt64Array([religiao]), PackedFloat64Array([10.0]))              # denominador de outra data
	if r.CompositionsOf(pais, T3).size() != n_dist:
		return fail("uma distribuição inválida foi aceita (%d)" % r.CompositionsOf(pais, T3).size())
	var inc: int = r.AddDistribution(pais, vale, T3, "religiao", 0, true, false, "media", "", PackedInt64Array([religiao, rel2]), PackedFloat64Array([60.0, 30.0]))
	var c_inc: Dictionary = r.Composition(inc)
	if c_inc.unknown_pct != 10.0 or c_inc.exclusive != true or c_inc.complete != false or c_inc.shares[0].name != "Via do silêncio" or c_inc.denominator.size() != 0 or c_inc.shares[0].has("low"):
		return fail("incompleta e exclusiva guarda 10%% desconhecidos, sem denominador não há absoluto: %s" % [c_inc])
	var langs: int = r.Create("idioma", "Língua do rio")
	var multi: int = r.AddDistribution(pais, vale, T3, "idioma", 0, false, true, "baixa", "", PackedInt64Array([idioma, langs]), PackedFloat64Array([90.0, 70.0]))
	var c_multi: Dictionary = r.Composition(multi)
	if c_multi.unknown_pct != -1.0 or c_multi.shares.size() != 2:
		return fail("não exclusiva: falantes de vários idiomas contam em cada um (90% + 70%)")
	ok("distribuição: completa+exclusiva soma 100%; exclusiva não passa de 100; incompleta guarda o desconhecido; idiomas (não exclusivos) podem somar mais de 100; tipo errado, repetida, dimensão e denominador inválidos recusados")

	# Com denominador numérico: faixa absoluta derivada (e só então). Completa e exclusiva soma 100.
	var c_etnia: Dictionary = r.Composition(d_etnia)
	if c_etnia.denominator.id != den or c_etnia.shares[0].low != 1200.0 or c_etnia.shares[0].high != 1350.0 or c_etnia.shares[1].low != 400.0:
		return fail("75%% de 1600–1800 = 1200–1350: %s" % [c_etnia.shares[0]])
	var den_nivel: int = r.AddEstimateLevel(pais, vale, T3, "media", "baixa", "")
	var d_nivel: int = r.AddDistribution(pais, vale, T3, "cultura", den_nivel, true, false, "baixa", "", PackedInt64Array([cultura]), PackedFloat64Array([50.0]))
	if r.Composition(d_nivel).shares[0].has("low") or r.Composition(d_nivel).unknown_pct != 50.0:
		return fail("denominador só com nível não gera número absoluto")
	if r.Composition(d_nivel).denominator.level != "media":
		return fail("o nível do denominador deveria aparecer")
	var vigentes: Array = r.CompositionsOf(pais, T2)
	if vigentes.size() != 1 or vigentes[0].dimension != "etnia":
		return fail("em T2 vale só a composição por etnia (as outras são de T3): %d" % vigentes.size())
	ok("denominador numérico gera a faixa absoluta; só nível não gera número; a composição vigente depende da data")

	# Ficha e exclusão: a ficha traz presenças, estimativas e composições; excluir leva o que é da entidade e a lista deixa de ser completa.
	var ficha: Dictionary = r.Sheet(pais, T3)
	if ficha.presences.size() != 2 or ficha.estimates.size() < 2 or ficha.compositions.size() < 3:
		return fail("a ficha: %d presenças, %d estimativas, %d composições" % [ficha.presences.size(), ficha.estimates.size(), ficha.compositions.size()])
	r.Delete(outra_etnia)  # era categoria da composição exclusiva e completa por etnia
	var depois_c: Dictionary = r.Composition(d_etnia)
	if depois_c.complete or depois_c.shares.size() != 1 or depois_c.unknown_pct != 25.0:
		return fail("sem a categoria, a lista deixa de ser completa e sobra 25%% desconhecido: %s" % [depois_c])
	var copia: int = r.Duplicate(pais, true, "")
	if r.PresencesOf(copia, T3).size() != 2 or r.EstimatesOf(copia, T3).size() != 0:
		return fail("duplicar com vínculos copia as presenças em aberto e não copia estimativas")
	r.Delete(copia)
	if r.MapItems(ALL_LAYERS, copia, T3).size() != 0:
		return fail("excluir a entidade leva as presenças")
	r.DeletePlace(vale)  # em uso: recusado
	r.DeletePlace(emenda)  # em uso pela raça
	var livre: int = r.AddPlace("Engano", "outro", 0.0, 0.0, 0.0, "")
	r.DeletePlace(livre)
	if r.Places("Vale").size() != 1 or r.Places("Engano").size() != 0:
		return fail("excluir lugar: só o que não está em uso")
	ok("a ficha traz presenças, estimativas e composições; excluir leva o que é da entidade (e a lista perde o 'completa'); lugar em uso não se exclui")

	# Persistência.
	r.Close()
	r.Open(path)
	if r.PresencesOf(pais, T3).size() != 2 or r.Composition(d_etnia).shares.size() != 1 or r.EstimatesOf(pais, T2).size() != 2 or r.Place(vale).radius_km != 600.0:
		return fail("reabrir perdeu lugares, presenças ou demografia")
	ok("reabrir conserva lugares, presenças, estimativas e distribuições")
	r.Close()
