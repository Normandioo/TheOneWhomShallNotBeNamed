extends "res://tests/test_suite.gd"
## Cadastros dos domínios (etapa 1), sem cena. Cobre os critérios de aceitação 1 a 5 do plano e a persistência em disco.
## As linhas "ERROR" das recusas testadas no fim são esperadas: o C# registra a exceção e o teste confere que nada foi gravado.

const KINDS := ["cultura", "pais", "raca", "etnia", "idioma", "religiao"]
const FOREVER := 9223372036854775807


func run() -> void:
	var path := out_dir.path_join("registry_suite.db")
	for ext in ["", "-journal", "-wal", "-shm"]:
		DirAccess.remove_absolute(path + ext)
	var r = load("res://scripts/world/Registry.cs").new()
	r.Open(path)

	# 1. Cada tipo nasce só com o nome; o resto fica vazio e isso não atrapalha.
	var ids := {}
	for k in KINDS:
		ids[k] = r.Create(k, "Provisório " + k)
		if r.Kind(ids[k]) != k or r.Name(ids[k]) != "Provisório " + k or r.Summary(ids[k]) != "":
			return fail("criar só com nome falhou para " + k)
	r.SetSummary(ids.pais, "Resumo escrito depois")
	if r.Summary(ids.pais) != "Resumo escrito depois" or r.Count("pais") != 1:
		return fail("completar depois não funcionou")
	ok("1: seis tipos criados só com nome; resumo preenchido depois")

	# 2. Um país com várias culturas/etnias/religiões/línguas; a mesma cultura em dois países, sem duplicar.
	var pais_a: int = ids.pais
	var pais_b: int = r.Create("pais", "Reino B")
	var cultura_2: int = r.Create("cultura", "Cultura 2")
	var etnia_2: int = r.Create("etnia", "Etnia 2")
	for c in [ids.cultura, cultura_2]:
		r.Link(pais_a, c, "cultura_presente")
	r.Link(pais_b, ids.cultura, "cultura_presente")  # a MESMA cultura em outro país
	r.Link(pais_a, ids.etnia, "etnia_presente")
	r.Link(pais_a, etnia_2, "etnia_presente")
	r.Link(pais_a, ids.raca, "raca_presente")
	r.Link(pais_a, ids.religiao, "religiao_reconhecida")
	r.Link(pais_a, ids.idioma, "idioma_oficial")
	var antes: int = r.Count("cultura")
	if r.Linked(pais_a, "cultura_presente", 0, false) != [ids.cultura, cultura_2]:
		return fail("o país A deveria ter 2 culturas: %s" % [r.Linked(pais_a, "cultura_presente", 0, false)])
	if r.Linked(ids.cultura, "cultura_presente", 0, true) != [pais_a, pais_b]:
		return fail("a cultura deveria estar nos dois países (sentido contrário)")
	if r.Count("cultura") != antes or antes != 2:
		return fail("reutilizar a cultura não pode duplicá-la")
	ok("2: várias culturas/etnias/raças/religiões/línguas num país; mesma cultura em dois países")

	# 3. Etnia sem país e religião sem divindades: existem sem vínculo nem dado artificial.
	var sem_pais: int = r.Create("etnia", "Povo errante")
	var sem_deus: int = r.Create("religiao", "Via do silêncio")
	if r.Linked(sem_pais, "etnia_presente", 0, true).size() != 0 or r.Summary(sem_deus) != "":
		return fail("etnia sem país ou religião sem divindades deveria ficar vazia")
	ok("3: etnia sem país e religião sem divindades")

	# 4. Gentílico, etnônimo, raça e denominação cultural com o mesmo texto continuam distintos (papel + entidade).
	var pais_aren: int = r.Create("pais", "Reino de Aren")
	var etnia_aren: int = r.Create("etnia", "Arenos")
	var raca_aren: int = r.Create("raca", "Aren")
	var cultura_aren: int = r.Create("cultura", "Cultura aren")
	r.AddName(pais_aren, "aren", "gentilico", 0)
	r.AddName(etnia_aren, "aren", "etnonimo", 0)
	r.AddName(cultura_aren, "aren", "denominacao_coletiva", 0)
	if r.NamesWithRole(pais_aren, "gentilico") != PackedStringArray(["aren"]) or r.NamesWithRole(pais_aren, "etnonimo").size() != 0:
		return fail("o gentílico do país não pode virar etnônimo")
	if r.NamesWithRole(etnia_aren, "etnonimo") != PackedStringArray(["aren"]) or r.NamesWithRole(etnia_aren, "gentilico").size() != 0:
		return fail("o etnônimo da etnia não pode virar gentílico")
	var achados: Array = r.Find("AREN")
	for e in [pais_aren, etnia_aren, cultura_aren, raca_aren]:  # a raça acha pelo nome principal; os outros, pelo papel
		if not achados.has(e):
			return fail("a busca por 'AREN' deveria achar a entidade %d" % e)
	if achados.size() != 4:
		return fail("a busca por 'AREN' deveria achar exatamente 4 entidades: %s" % [achados])
	ok("4: mesmo texto, papéis e entidades distintos; a busca acha as quatro, sem diferenciar maiúsculas")

	# 5. Renomear mantém os vínculos pelo ID; o nome anterior é consultável quando a mudança é histórica.
	var t_mudanca := 1000000
	r.RenameAt(pais_a, "Reino Novo", t_mudanca)
	if r.Name(pais_a) != "Reino Novo" or r.NameAt(pais_a, t_mudanca - 1) != "Provisório pais" or r.NameAt(pais_a, t_mudanca) != "Reino Novo":
		return fail("nome histórico: antes=%s, depois=%s" % [r.NameAt(pais_a, t_mudanca - 1), r.NameAt(pais_a, t_mudanca)])
	if r.Linked(pais_a, "cultura_presente", 0, false).size() != 2:
		return fail("renomear não pode perder vínculos (eles seguem o ID)")
	if not r.Find("Provisório pais").has(pais_a):
		return fail("o nome anterior deveria continuar achando a entidade")
	r.Correct(pais_a, "Reino Novo (grafia corrigida)")  # correção de cadastro: sem história
	if r.NameAt(pais_a, t_mudanca - 1) != "Provisório pais" or r.Name(pais_a) != "Reino Novo (grafia corrigida)":
		return fail("corrigir a grafia não pode mexer no nome antigo")
	ok("5: renomear por ID, nome anterior consultável, correção de grafia separada da mudança histórica")

	# Vínculo datado: o idioma oficial muda em t (a consulta antes e depois dá os vínculos certos).
	var idioma_2: int = r.Create("idioma", "Idioma novo")
	var antigo: int = r.Linked(pais_a, "idioma_oficial", 0, false)[0]
	var vinculo: int = r.Link(pais_b, antigo, "idioma_oficial")
	r.EndLink(vinculo, 500)
	r.LinkDuring(pais_b, idioma_2, "idioma_oficial", 500, FOREVER)
	if r.Linked(pais_b, "idioma_oficial", 499, false) != [antigo] or r.Linked(pais_b, "idioma_oficial", 500, false) != [idioma_2]:
		return fail("o idioma oficial deveria trocar exatamente em 500 (fim excluído)")
	ok("vínculo datado: [início, fim) sem sobreposição na virada")

	# Recusas (as linhas ERROR vêm daqui): nada pode ter sido gravado.
	var n_nomes: int = r.NamesWithRole(pais_a, "principal").size()
	r.Create("planeta", "x")
	r.Create("pais", "   ")
	r.Link(pais_a, ids.cultura, "inexistente")
	r.Link(ids.cultura, pais_a, "idioma_oficial")  # origem precisa ser país e destino, idioma
	r.Link(pais_a, ids.cultura, "cultura_presente")  # repetição do mesmo vínculo
	if r.Count("pais") != 3 or r.Linked(pais_a, "cultura_presente", 0, false).size() != 2 or r.NamesWithRole(pais_a, "principal").size() != n_nomes:
		return fail("uma recusa deixou lixo gravado")
	ok("recusas: tipo de entidade, nome vazio, tipo de vínculo, tipos incompatíveis e repetição")

	# Persistência: fechar e reabrir o arquivo conserva IDs, nomes, história e vínculos.
	r.Close()
	r.Open(path)
	if r.Name(pais_a) != "Reino Novo (grafia corrigida)" or r.NameAt(pais_a, 0) != "Provisório pais" or r.Linked(pais_a, "cultura_presente", 0, false).size() != 2:
		return fail("reabrir o arquivo perdeu dados")
	ok("reabrir o arquivo conserva IDs, nomes, história e vínculos")
	r.Close()
