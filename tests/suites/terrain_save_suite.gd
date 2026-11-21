extends "res://tests/test_suite.gd"
## O relevo editado e o mundo que não o consegue ler: sem edições novas, exportar e importar continuam valendo; com edições que não
## podem ser gravadas (o relevo gravado não carregou), o salvamento recusa sem escrever por cima, e a mensagem diz a causa certa.
## Roda com a cena (argumento "scene").


func run() -> void:
	var ok_saved: bool = main.save_terrain()
	if not ok_saved or main.terrain.HasEdits:
		return fail("com o relevo carregado e sem edições, salvar funciona")
	main.terrain.SetH(100, 5.0)
	if not main.terrain.HasEdits or not main.save_terrain() or main.terrain.HasEdits:
		return fail("com o relevo carregado, as edições são gravadas e as marcas limpas")
	ok("relevo carregado: edições gravadas")

	main._terrain_loaded = false  # como se o relevo gravado não tivesse carregado ao abrir
	if not main.save_terrain():
		return fail("sem edições novas, um relevo que não carregou não bloqueia exportar nem importar")
	main.terrain.SetH(200, 7.0)
	if main.save_terrain() or not main.terrain.HasEdits:
		return fail("com edições novas e o relevo gravado ilegível, não grava por cima e as edições seguem pendentes")
	if not main.terrain_problem().contains("não pôde ser lido") or main.terrain_problem().contains("não foram gravadas"):
		return fail("a mensagem fala em leitura, não em falha de gravação: " + main.terrain_problem())
	main._terrain_loaded = true
	if not main.terrain_problem().contains("não foram gravadas"):
		return fail("com o relevo carregado, a mensagem fala em gravação")
	ok("relevo que não carregou: não grava por cima, só bloqueia com edições novas, e a mensagem diz a causa")
