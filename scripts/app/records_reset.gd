extends RefCounted
## Opções → Cadastros: o que há para apagar, a cópia do mundo antes e a arrumação da tela depois. Sem a cópia, nada é apagado.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const TerritoryEditor = preload("res://scripts/app/territory_editor.gd")
const TerritoryEdit = preload("res://scripts/edit/TerritoryEdit.cs")

const PLURAL := {"pais": "Países", "provincia": "Subdivisões de 1º nível", "municipio": "Subdivisões de 2º nível", "cultura": "Culturas", "etnia": "Etnias",
	"raca": "Raças", "religiao": "Religiões", "idioma": "Idiomas"}

var _main


func setup(main) -> void:
	_main = main


## As categorias de cadastro: [{kind, label, count}], as de fábrica na ordem de sempre e depois as criadas.
func categories() -> Array:
	var hub = _main.domains
	if not hub.usable:
		return []
	var out: Array = []
	var order: Array = PLURAL.keys()
	for kind in UiKit.all_kinds():
		if not kind in order:
			order.append(kind)
	for kind in order:
		out.append({"kind": kind, "label": PLURAL.get(kind, UiKit.kind_label(kind)), "count": int(hub.registry.Count(kind))})
	return out


## Lugares que hoje não estão ligados a nada.
func loose_places() -> int:
	return int(_main.domains.registry.CountLoosePlaces()) if _main.domains.usable else 0


## O que vale saber antes de confirmar.
func warnings(kinds: Array) -> Array:
	var counts := {}
	for c in categories():
		counts[c.kind] = c.count
	var out: Array = []
	if "pais" in kinds and not "provincia" in kinds and counts.get("provincia", 0) > 0:
		out.append("As %d subdivisões de 1º nível continuam no mundo, sem país." % counts.provincia)
	if ("pais" in kinds or "provincia" in kinds) and not "municipio" in kinds and counts.get("municipio", 0) > 0:
		out.append("As %d subdivisões de 2º nível continuam no mundo, sem o cadastro de cima que for apagado." % counts.municipio)
	out.append("Recursos, povoados, receitas, calendários, regras, tipos, campos e o relevo continuam.")
	return out


## Guarda a cópia, apaga as categorias e arruma a tela. Devolve {ok, message, backup}.
func run(kinds: Array, loose: bool) -> Dictionary:
	var hub = _main.domains
	if not hub.usable or (kinds.is_empty() and not loose):
		return {"ok": false, "message": "Nada para apagar.", "backup": ""}
	var terr = _main.territories
	if terr.drafting:
		terr.discard_draft()
	if terr.painting_territory:
		terr.stop_painting()
	_main.set_tool(-1)
	var copy := _backup()
	if copy.why != "":
		return {"ok": false, "message": "Nada foi apagado: não consegui guardar a cópia do mundo (%s)." % copy.why, "backup": ""}

	# Os donos de território de cada categoria, antes que os cadastros sumam.
	var painted: Array = []  # [camada, ids]
	for kind in kinds:
		if not kind in TerritoryEditor.PAINTABLE:
			continue
		var ids := PackedInt32Array()
		for id in hub.registry.IdsOfKinds(PackedStringArray([kind])):
			if id <= 65535:
				ids.append(id)
		var layer = terr.layer(kind)
		if layer != null and not ids.is_empty():
			painted.append([layer, ids])
	hub.deselect()
	var done = hub.registry.DeleteKinds(PackedStringArray(kinds), loose)
	if done == null:
		return {"ok": false, "message": "Nada foi apagado: o banco recusou a exclusão (veja o registro do jogo). A cópia ficou em:\n" + copy.path, "backup": copy.path}
	for pair in painted:
		pair[0].ClearOwners(pair[1])
		for id in pair[1]:
			pair[0].ForgetOwnerBoundaries(id)
	# O desfazer não pode trazer de volta o território de quem não existe mais.
	_main.commands.discard_matching(func(cmd: Object) -> bool: return cmd.get_script() == TerritoryEdit)
	var saved: bool = terr.flush()
	hub.forget_cached()
	terr.refresh_palette()
	_main.resources.refresh()
	_main.production.refresh()

	var parts: Array = ["%d cadastro%s apagado%s" % [done.entities, "" if done.entities == 1 else "s", "" if done.entities == 1 else "s"]]
	if loose:
		parts.append("%d lugar%s solto%s" % [done.places, "" if done.places == 1 else "es", "" if done.places == 1 else "s"])
	var text := " e ".join(parts) + "."
	if not saved:
		text += "\nAtenção: o mapa pintado não pôde ser gravado agora; ele será gravado de novo em instantes."
	text += "\n\nA cópia do mundo de antes está em:\n%s\nPara voltar atrás: Mundo → Importar mundo… e escolha essa pasta." % copy.path
	return {"ok": true, "message": text, "backup": copy.path}


## Exporta o mundo como está para uma pasta nova. {path, why}: why vazio = deu certo.
func _backup() -> Dictionary:
	if not _main.save_terrain(true):
		return {"path": "", "why": _main.terrain_problem()}
	_main.save_clock()
	if not _main.territories.flush():
		return {"path": "", "why": "o mapa pintado não pôde ser gravado"}
	var base := ProjectSettings.globalize_path(_main.backup_dir)
	if DirAccess.make_dir_recursive_absolute(base) != OK:
		return {"path": "", "why": "não consegui criar a pasta " + base}
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var path := base.path_join("antes-de-apagar-%s-%d.world" % [stamp, Time.get_ticks_usec() % 1000000])
	var why: String = _main.domains.registry.ExportWorld(path, _main.world_files._clock_path())
	return {"path": path, "why": why}
