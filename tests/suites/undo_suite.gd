extends "res://tests/test_suite.gd"
## Desfazer e refazer nos cadastros (aceite A01), sem cena: o registro de mudanças do Registry (BeginRecord/EndRecord) e o hub com a pilha.
## Lugar: criar, editar, mover o ponto (a área vai junto), duplicar e excluir um cadastro com tudo o que é dele, e desfazer e refazer cada
## coisa; o desfeito continua desfeito depois de fechar e reabrir o banco. As linhas "ERROR" das recusas são esperadas.

const SearchPanel = preload("res://scripts/ui/search_panel.gd")
const SheetPanel = preload("res://scripts/ui/sheet_panel.gd")
const DomainHub = preload("res://scripts/app/domain_hub.gd")
const CommandStack = preload("res://scripts/edit/command_stack.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const T1 := 1000


## Tudo o que o banco diz de uma entidade e de um lugar, para comparar antes e depois.
func _state(r, id: int, place: int) -> String:
	var parts := [r.Sheet(id, T1) if r.Kind(id) != "" else null, r.Place(place) if place != 0 else null,
		r.PresencesOf(id, T1), r.EstimatesOf(id, T1), r.CompositionsOf(id, T1), r.Count("pais"), r.Count("cultura")]
	return var_to_str(parts)


func run() -> void:
	var path := out_dir.path_join("undo_suite.db")
	for ext in ["", "-journal"]:
		DirAccess.remove_absolute(path + ext)
	var r = load("res://scripts/world/Registry.cs").new()
	r.Open(path)

	# Um país com nomes, campo, etiqueta, vínculo, lugar, presença, estimativa e distribuição.
	var pais: int = r.Create("pais", "Reino de Aren")
	var cultura: int = r.Create("cultura", "Cultura aren")
	var idioma: int = r.Create("idioma", "Arenês")
	r.AddName(pais, "Arenos", "gentilico", 0)
	r.AddTag(pais, "norte")
	r.SetSummary(pais, "um reino")
	r.Link(pais, idioma, "idioma_oficial")
	var cidade: int = r.AddPlace("Valdória", "assentamento", 10.123456789012345, 20.987654321098765, 0.0, "")
	r.AddPresence(pais, cidade, "capital", "alta")
	var est: int = r.AddEstimate(pais, cidade, T1, 1000.0, 1000.0, "alta", "")
	r.AddDistribution(pais, cidade, T1, "cultura", est, true, false, "media", "", PackedInt64Array([cultura]), PackedFloat64Array([60.0]))
	var before := _state(r, pais, cidade)

	# Editar e mover o lugar: desfazer volta bit a bit (o REAL não passa por texto).
	r.BeginRecord()
	r.UpdatePlace(cidade, "Valdória Nova", "regiao", -33.3, 150.5, 120.0)
	var move = r.EndRecord()
	if move == null or r.Place(cidade).name != "Valdória Nova" or r.Place(cidade).radius_km != 120.0:
		return fail("editar o lugar")
	move.Undo()
	var back = r.Place(cidade)
	if back.lat != 10.123456789012345 or back.lon != 20.987654321098765 or back.name != "Valdória" or back.radius_km != 0.0:
		return fail("desfazer o lugar não devolveu os valores exatos: %s" % [back])
	move.Redo()
	if r.Place(cidade).lat != -33.3 or r.Place(cidade).kind != "regiao":
		return fail("refazer o lugar")
	move.Undo()
	if _state(r, pais, cidade) != before:
		return fail("o estado depois de desfazer e refazer o lugar mudou")
	ok("lugar: editar nome, tipo, raio e posição; desfazer devolve os valores exatos; refazer de novo")

	# Nada mudou = nada a desfazer; o registro aninhado só fecha no de fora.
	r.BeginRecord()
	if r.EndRecord() != null:
		return fail("um registro sem mudança não deveria virar comando")
	r.BeginRecord()
	r.BeginRecord()
	r.SetSummary(pais, "outro")
	if r.EndRecord() != null:
		return fail("o registro de dentro não fecha")
	var nested = r.EndRecord()
	if nested == null:
		return fail("o registro de fora deveria ter a mudança")
	nested.Undo()
	if r.Summary(pais) != "um reino":
		return fail("desfazer o registro aninhado")
	ok("registro: sem mudança não vira comando; aninhado fecha só no de fora")

	# Excluir com tudo o que vai junto (nomes, vínculos, presenças, estimativas, distribuições) e desfazer.
	r.BeginRecord()
	r.Delete(pais)
	var deletion = r.EndRecord()
	if deletion == null or r.Kind(pais) != "" or r.EstimatesOf(pais, T1).size() != 0:
		return fail("excluir o país")
	deletion.Undo()
	if _state(r, pais, cidade) != before:
		return fail("desfazer a exclusão não devolveu tudo:\n%s\n%s" % [before, _state(r, pais, cidade)])
	deletion.Redo()
	if r.Kind(pais) != "":
		return fail("refazer a exclusão")
	deletion.Undo()
	ok("excluir: desfazer devolve o cadastro com o mesmo id e tudo o que era dele; refazer exclui de novo")

	# Duplicar e desfazer: a cópia some, o original fica.
	r.BeginRecord()
	var copy: int = r.Duplicate(pais, true, "")
	var dup = r.EndRecord()
	if copy == 0 or r.Count("pais") != 2:
		return fail("duplicar")
	dup.Undo()
	if r.Kind(copy) != "" or _state(r, pais, cidade) != before:
		return fail("desfazer a duplicação")
	dup.Redo()
	if r.Kind(copy) != "pais" or r.Name(copy) == "":
		return fail("refazer a duplicação devolve a cópia com o mesmo id")
	dup.Undo()
	ok("duplicar: desfazer tira a cópia; refazer a devolve com o mesmo id")

	# O desfeito fica gravado: fechar e reabrir o banco.
	r.Close()
	r = load("res://scripts/world/Registry.cs").new()
	r.Open(path)
	if _state(r, pais, cidade) != before:
		return fail("depois de reabrir, o estado não é o do último desfazer")
	r.BeginRecord()  # os gatilhos voltam a valer no banco reaberto
	r.SetSummary(pais, "reaberto")
	var again = r.EndRecord()
	if again == null:
		return fail("o registro não funciona depois de reabrir")
	again.Undo()
	r.Close()
	ok("persistência: o estado desfeito é o que reabre, e o desfazer continua valendo no banco reaberto")

	await _hub_flow()


## O mesmo pela interface: os sinais da ficha, a pilha de desfazer e o clique que move o lugar.
func _hub_flow() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var search := SearchPanel.new()
	var sheet := SheetPanel.new()
	host.add_child(search)
	host.add_child(sheet)
	var hub := DomainHub.new()
	hub.setup(":memory:", search, sheet)
	var stack := CommandStack.new()
	hub.bind_commands(stack)
	var r = hub.registry

	search._query.text = "Aren"
	search._on_new(UiKit.all_kinds().find("pais"))
	var pais := sheet.current_id()
	if pais == 0 or not stack.can_undo():
		return fail("criar pela busca deveria ir para a pilha")
	hub.set_fixed_point(EvronGeo.dir(10.0, 20.0))
	sheet.place_created.emit("Valdória", "assentamento", 0.0, "capital")
	var place := int(r.PresencesOf(pais, hub.shown_t)[0].place_id)

	sheet.place_edited.emit(place, "Valdória Velha", "assentamento", 50.0)
	if r.Place(place).name != "Valdória Velha" or r.Place(place).radius_km != 50.0:
		return fail("editar o lugar pela ficha")
	sheet.place_move_requested.emit(place)
	if not hub.place_click(EvronGeo.dir(-5.0, 30.0)):
		return fail("o clique deveria mover o lugar")
	if absf(r.Place(place).lat + 5.0) > 1e-6 or absf(r.Place(place).lon - 30.0) > 1e-6 or r.Place(place).radius_km != 50.0:
		return fail("mover leva o ponto e mantém o raio da área: %s" % [r.Place(place)])
	if hub.place_click(EvronGeo.dir(0.0, 0.0)):
		return fail("um clique depois de mover não move de novo")
	if stack.undo_name() != "Mover Valdória Velha":
		return fail("nome do comando: %s" % stack.undo_name())
	stack.undo()
	if absf(r.Place(place).lat - 10.0) > 1e-6:
		return fail("desfazer o movimento")
	stack.undo()
	if r.Place(place).name != "Valdória" or r.Place(place).radius_km != 0.0:
		return fail("desfazer a edição")
	stack.redo()
	stack.redo()
	if absf(r.Place(place).lat + 5.0) > 1e-6:
		return fail("refazer as duas")
	sheet.place_move_requested.emit(place)
	if not hub.cancel_move() or hub.place_click(EvronGeo.dir(0.0, 0.0)):
		return fail("Esc cancela o mover")
	ok("interface: editar e mover o lugar pela ficha e pelo clique; desfazer e refazer pela pilha; Esc cancela")

	# Duplicar e excluir o lugar (a cidade), com desfazer.
	var place_copy := hub.duplicate_place(place)
	if place_copy == 0 or r.Place(place_copy).name != "Cópia de Valdória Velha" or r.PresencesOf(pais, hub.shown_t).size() != 2:
		return fail("duplicar o lugar cria a cópia no mesmo ponto, ligada à ficha")
	sheet.place_removed.emit(place)
	if r.Place(place) != null or r.PresencesOf(pais, hub.shown_t).size() != 1:
		return fail("excluir o lugar tira ele e a presença nele")
	stack.undo()
	if r.Place(place) == null or r.PresencesOf(pais, hub.shown_t).size() != 2:
		return fail("desfazer a exclusão devolve o lugar e a presença")
	stack.undo()
	if r.Place(place_copy) != null or r.PresencesOf(pais, hub.shown_t).size() != 1:
		return fail("desfazer a duplicação tira a cópia")
	ok("interface: duplicar e excluir a cidade, com desfazer")

	# Excluir e desfazer pela pilha: a ficha volta a abrir.
	hub._delete_target = pais
	hub._on_delete()
	if hub.current() != 0 or r.Kind(pais) != "":
		return fail("excluir pela ficha")
	stack.undo()
	if hub.current() != pais or r.PresencesOf(pais, hub.shown_t).size() != 1:
		return fail("desfazer a exclusão deveria reabrir a ficha com o lugar (aberta: %d)" % hub.current())
	stack.redo()
	if hub.current() != 0:
		return fail("refazer a exclusão fecha a ficha")
	stack.undo()

	# Duplicar e desfazer; campo e resumo.
	sheet.duplicate_requested.emit(false)
	var copy := hub.current()
	if copy == pais or r.Kind(copy) != "pais":
		return fail("duplicar pela ficha")
	stack.undo()
	if r.Kind(copy) != "" or hub.current() == copy:
		return fail("desfazer a duplicação fecha a cópia")
	sheet.summary_changed.emit(pais, "resumo novo")
	stack.undo()
	if r.Summary(pais) != "":
		return fail("desfazer o resumo")
	ok("interface: excluir, duplicar e resumo desfazem e refazem; desfazer a exclusão reabre a ficha")
	host.queue_free()
	await frames(1)

