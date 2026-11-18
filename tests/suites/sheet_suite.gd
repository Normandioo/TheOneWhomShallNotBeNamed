extends "res://tests/test_suite.gd"
## Ficha dos cadastros (etapa 4), sem cena: campos como dados, os quatro estados de vazio, busca, etiquetas, duplicar, excluir,
## sociedade. As linhas "ERROR" das recusas são esperadas: o teste confere que nada foi gravado.

const NOW := 9223372036854775806  # "agora" até haver o relógio: tudo o que não tem fim


func _field(sheet: Dictionary, code: String) -> Dictionary:
	for f in sheet.fields:
		if f.code == code:
			return f
	return {}


func run() -> void:
	var path := out_dir.path_join("sheet_suite.db")
	for ext in ["", "-journal"]:
		DirAccess.remove_absolute(path + ext)
	var r = load("res://scripts/world/Registry.cs").new()
	r.Open(path)

	# Campos semeados: um por tópico do plano, só nos tipos certos.
	var expected := {"cultura": 10, "pais": 11, "raca": 9, "etnia": 10, "idioma": 11, "religiao": 11}
	for k in expected:
		if r.FieldsFor(k).size() != expected[k]:
			return fail("%s deveria ter %d campos, tem %d" % [k, expected[k], r.FieldsFor(k).size()])
	ok("62 campos semeados, nos seis tipos (10, 11, 9, 10, 11, 11)")

	# Os quatro estados: não preenchido, desconhecido, não se aplica, e valor (inclusive vazio->limpa).
	var pais: int = r.Create("pais", "Reino de Aren")
	if _field(r.Sheet(pais, NOW), "pais.governo").state != "unfilled":
		return fail("campo novo deveria estar 'não preenchido'")
	r.SetField(pais, "pais.governo", "known", "Monarquia eletiva")
	var f := _field(r.Sheet(pais, NOW), "pais.governo")
	if f.state != "known" or f.value != "Monarquia eletiva":
		return fail("valor conhecido não voltou: %s" % [f])
	r.SetField(pais, "pais.governo", "unknown", "")
	if _field(r.Sheet(pais, NOW), "pais.governo").state != "unknown":
		return fail("deveria ficar 'desconhecido'")
	r.SetField(pais, "pais.governo", "na", "")
	if _field(r.Sheet(pais, NOW), "pais.governo").state != "na":
		return fail("deveria ficar 'não se aplica'")
	r.SetField(pais, "pais.governo", "known", "  ")  # texto em branco = volta a não preenchido
	if _field(r.Sheet(pais, NOW), "pais.governo").state != "unfilled":
		return fail("texto em branco deveria voltar a 'não preenchido'")
	ok("estados: não preenchido, valor, desconhecido, não se aplica; em branco limpa")

	# Campo personalizado: número com unidade, em dois tipos; zero é valor, não ausência.
	var code: String = r.AddField("Área aproximada", "number", "km²", "", PackedStringArray(["pais", "etnia"]))
	var etnia: int = r.Create("etnia", "Arenos")
	var religiao: int = r.Create("religiao", "Via do silêncio")
	if _field(r.Sheet(etnia, NOW), code).is_empty() or not _field(r.Sheet(religiao, NOW), code).is_empty():
		return fail("o campo personalizado deveria valer em país e etnia, não em religião")
	if _field(r.Sheet(pais, NOW), code).unit != "km²" or not _field(r.Sheet(pais, NOW), code).custom:
		return fail("unidade/personalizado não vieram na definição")
	r.SetField(pais, code, "known", "0")
	var zero := _field(r.Sheet(pais, NOW), code)
	if zero.state != "known" or float(zero.value) != 0.0:
		return fail("zero deveria ser um valor conhecido: %s" % [zero])
	r.SetField(pais, code, "known", "1234,5")  # vírgula decimal
	if float(_field(r.Sheet(pais, NOW), code).value) != 1234.5:
		return fail("1234,5 deveria virar 1234.5")
	var cod_escolha: String = r.AddField("Regime", "choice", "", "aberto\nfechado\nmisto", PackedStringArray(["pais"]))
	r.SetField(pais, cod_escolha, "known", "misto")
	ok("campo personalizado (número com unidade e escolha); 0 é valor conhecido; vírgula decimal")

	# Recusas: número inválido, escolha fora das opções, campo de outro tipo de entidade, estado inválido.
	r.SetField(pais, code, "known", "muito")
	r.SetField(pais, cod_escolha, "known", "caótico")
	r.SetField(religiao, "pais.governo", "known", "x")
	r.SetField(pais, "pais.governo", "talvez", "x")
	if float(_field(r.Sheet(pais, NOW), code).value) != 1234.5 or _field(r.Sheet(pais, NOW), cod_escolha).value != "misto":
		return fail("uma recusa alterou um valor")
	if r.Sheet(religiao, NOW).fields.any(func(x): return x.state != "unfilled"):
		return fail("o campo de país entrou numa religião")
	ok("recusas de valor inválido, de campo alheio e de estado inválido")

	# Vínculos na ficha, nos dois sentidos, com o rótulo de cada lado.
	var idioma: int = r.Create("idioma", "Arenês")
	r.Link(pais, idioma, "idioma_oficial")
	r.Link(pais, etnia, "etnia_presente")
	var lp: Array = r.Sheet(pais, NOW).links
	var li: Array = r.Sheet(idioma, NOW).links
	if lp.size() != 2 or li.size() != 1:
		return fail("vínculos na ficha: país %d, idioma %d" % [lp.size(), li.size()])
	if li[0].label != "Idioma oficial de" or li[0].outgoing or li[0].other_name != "Reino de Aren":
		return fail("o idioma deveria listar 'Idioma oficial de: Reino de Aren': %s" % [li[0]])
	if lp.filter(func(l): return l.label == "Idioma oficial" and l.outgoing and l.other_name == "Arenês").size() != 1:
		return fail("o país deveria listar 'Idioma oficial: Arenês'")
	if r.LinkTypesFor("religiao").any(func(t): return t.code == "idioma_oficial"):
		return fail("religião não pode ser origem de idioma oficial")
	ok("vínculos nos dois sentidos, com o rótulo de cada ficha")

	# Busca: sem acentos nem maiúsculas, por tipo, etiqueta e vínculo.
	r.AddName(etnia, "Arên", "autodenominacao", 0)
	r.AddTag(pais, "reino")
	r.AddTag(etnia, "reino")
	r.AddTag(etnia, "reino")  # repetida: sem efeito
	if r.Tags(etnia) != PackedStringArray(["reino"]):
		return fail("etiqueta repetida deveria contar uma vez")
	var res: Array = r.Search("AREN", "", "", 0, NOW)
	var ids := res.map(func(x): return x.id)
	if not (ids.has(pais) and ids.has(etnia) and ids.has(idioma)):
		return fail("'AREN' deveria achar país, etnia (por 'Arên') e idioma: %s" % [ids])
	if r.Search("aren", "etnia", "", 0, NOW).map(func(x): return x.id) != [etnia]:
		return fail("filtro por tipo")
	r.AddName(etnia, "Gente do Vale", "alternativo", 0)
	var hit: Dictionary = r.Search("vale", "etnia", "", 0, NOW)[0]
	if hit.name != "Arenos" or hit.match != "Gente do Vale":
		return fail("o resultado deveria mostrar o nome principal e o nome que casou: %s" % [hit])
	if r.Search("", "", "reino", 0, NOW).size() != 2:
		return fail("filtro por etiqueta")
	if r.Search("", "", "", pais, NOW).map(func(x): return x.id) != [idioma, etnia]:  # ordenado por nome: Arenês, Arenos
		return fail("filtro por vínculo com o país: %s" % [r.Search("", "", "", pais, NOW).map(func(x): return x.id)])
	if r.Search("zzz", "", "", 0, NOW).size() != 0:
		return fail("busca sem resultado")
	r.RenameAt(etnia, "Povo aren", 500)
	if r.Search("aren", "etnia", "", 0, 100).map(func(x): return x.name) != ["Arenos"] or r.Search("aren", "etnia", "", 0, NOW).map(func(x): return x.name) != ["Povo aren"]:
		return fail("a busca deveria mostrar o nome principal da data consultada")
	ok("busca por nome (sem acento/caixa, nomes alternativos), tipo, etiqueta, vínculo e data")

	# Duplicar: nova identidade com valores e etiquetas; vínculos só se pedido; nomes alternativos não vão.
	var copia: int = r.Duplicate(pais, false, "Reino de Aren II")
	var sc: Dictionary = r.Sheet(copia, NOW)
	if copia == pais or sc.name != "Reino de Aren II" or sc.links.size() != 0 or sc.tags != PackedStringArray(["reino"]) or float(_field(sc, code).value) != 1234.5:
		return fail("duplicar sem vínculos: %s" % [sc])
	var copia2: int = r.Duplicate(pais, true, "")
	if r.Sheet(copia2, NOW).name != "Cópia de Reino de Aren" or r.Sheet(copia2, NOW).links.size() != 2:
		return fail("duplicar com vínculos")
	if r.Sheet(pais, NOW).links.size() != 2 or r.Count("pais") != 3:
		return fail("a original não pode mudar")
	ok("duplicar: identidade nova, valores e etiquetas copiados, vínculos opcionais")

	# Excluir por erro: avisa quantos vínculos e leva tudo da entidade; as outras ficam.
	if r.AffectedLinks(copia2) != 2 or r.Delete(copia2) != 2:
		return fail("excluir deveria afetar 2 vínculos")
	if r.Count("pais") != 2 or r.Sheet(idioma, NOW).links.size() != 1:
		return fail("excluir a cópia não pode mexer no idioma nem na original")
	var spare: int = r.Create("idioma", "Língua sem país")
	r.AddName(spare, "x", "alternativo", 0)
	var com_lang: int = r.Create("pais", "País com nome em arenês")
	r.AddName(com_lang, "Aren-ta", "popular", idioma)
	r.Delete(idioma)  # o idioma some; o nome que o citava continua, sem idioma
	if r.Sheet(com_lang, NOW).names[1].lang != "" or r.Count("idioma") != 1:
		return fail("excluir um idioma não pode apagar os nomes escritos nele")
	ok("excluir: informa os vínculos, apaga só o da entidade, nomes que citavam o idioma ficam")

	# Sociedade: a ficha antiga começa por país + cultura + etnia ligados; outros tipos recusados.
	var soc: Array = r.CreateSociety("Dravos", PackedStringArray(["pais", "cultura", "etnia"]))
	if soc.size() != 3 or r.Kind(soc[0]) != "pais" or r.Sheet(soc[0], NOW).links.size() != 2 or r.Sheet(soc[2], NOW).links.size() != 2:
		return fail("sociedade: país e etnia deveriam ter 2 vínculos cada: %s" % [r.Sheet(soc[0], NOW).links])
	var so_cultura: Array = r.CreateSociety("Só cultura", PackedStringArray(["cultura"]))
	if so_cultura.size() != 1 or r.Sheet(so_cultura[0], NOW).links.size() != 0:
		return fail("sociedade só com cultura")
	var n_raca: int = r.Count("raca")
	var n_pais: int = r.Count("pais")
	r.CreateSociety("Inválida", PackedStringArray(["pais", "raca"]))
	if r.Count("raca") != n_raca or r.Count("pais") != n_pais:
		return fail("uma sociedade recusada deixou lixo (pais %d -> %d)" % [n_pais, r.Count("pais")])
	ok("sociedade: país+cultura+etnia ligados; cultura sozinha; tipos inválidos recusados sem lixo")

	# Persistência dos valores.
	r.Close()
	r.Open(path)
	if _field(r.Sheet(pais, NOW), code).value != "1234.5" or _field(r.Sheet(pais, NOW), cod_escolha).value != "misto" or r.Tags(pais) != PackedStringArray(["reino"]):
		return fail("reabrir perdeu campos ou etiquetas")
	if r.FieldsFor("pais").size() != 13:
		return fail("os campos personalizados deveriam sobreviver: %d" % r.FieldsFor("pais").size())
	ok("reabrir conserva valores, etiquetas e campos personalizados")
	r.Close()
