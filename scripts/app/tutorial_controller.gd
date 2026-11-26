extends RefCounted
## Os tutoriais de cada menu e ferramenta: abre o menu, mostra os passos (o texto vem de tutorial_steps.gd), oferece o tutorial na
## primeira vez que o menu aparece e leva o cartão para dentro das janelas (Tipos, Regras). O jogo continua valendo durante os passos.
## O que já foi perguntado e visto fica no UserSettings.

const TerritoryEditor = preload("res://scripts/app/territory_editor.gd")
const Steps = preload("res://scripts/app/tutorial_steps.gd")

const BASIC := "basico"
## [grupo, [[chave, nome]]]: a ordem do menu Opções → Ajuda
const GROUPS := [
	["Começo", [["basico", "Tutorial básico"], ["alto", "O alto da tela"], ["tempo", "Tempo, busca e menu Mundo"], ["mapas", "Modos de mapa"]]],
	["Menus do cadastro selecionado", [["ficha", "Ficha"], ["governo", "Governo e relações"], ["povo", "Povo"], ["populacao", "População"], ["pg_territorio", "Território"], ["pg_calendarios", "Calendários do cadastro"]]],
	["Telas", [["registros", "Registros"], ["sobreposicoes", "Sobreposições"]]],
	["Ferramentas", [["territorio", "Pincel de território"], ["relevo", "Relevo"], ["recursos", "Recursos"], ["povoados", "Povoados"]]],
	["Janelas do menu Mundo", [["calendarios", "Calendários do mundo"], ["tipos", "Tipos, campos e vínculos"], ["regras", "Regras"]]],
]
## chave -> a página da ficha
const SHEET_PAGES := {"ficha": "Ficha", "governo": "Governo", "povo": "Povo", "populacao": "População", "pg_territorio": "Território", "pg_calendarios": "Calendários"}
const ALWAYS_THERE := ["basico", "alto", "tempo", "mapas"]  # estão sempre na tela: não há "primeira vez que abre"
const DIALOGS := {"tipos": "types", "regras": "rules"}  # os que são janelas: chave -> painel no _dock do Main

var overlay
var current := ""        # o tutorial perguntado ou em andamento ("" = nenhum)
var auto := false        # oferecer sozinho (no jogo de verdade; nos testes só quando eles ligam)
var _main
var _settings
var _pending := ""       # pedido no menu ou no "?": começa quando o menu aparecer


func setup(main, tutorial_overlay, settings) -> void:
	_main = main
	_settings = settings
	overlay = tutorial_overlay
	overlay.accepted.connect(func() -> void:
		var key := current
		_answered(key)
		_run(key))
	overlay.declined.connect(func() -> void:
		_answered(current)
		_pending = ""
		_end())
	overlay.never_requested.connect(func() -> void:
		_answered(current)
		_settings.set_value("offer_tool_tutorials", false)
		_end())
	overlay.finished.connect(func() -> void:
		_answered(current)
		_end())
	var tool_panel = main.tool_panel
	var sheet = main.domains.sheet
	main._dock["territory"].tutorial_requested.connect(request.bind("territorio"))
	tool_panel.relief_tutorial_requested.connect(request.bind("relevo"))
	main._dock["resources"].tutorial_requested.connect(request.bind("recursos"))
	main._dock["settlements"].tutorial_requested.connect(request.bind("povoados"))
	main._dock["search"].tutorial_requested.connect(request.bind("registros"))
	main._presence.tutorial_requested.connect(request.bind("sobreposicoes"))
	main.mode_rail.tutorial_requested.connect(request.bind("mapas"))
	main._dock["calendar"].tutorial_requested.connect(request.bind("calendarios"))
	main._dock["types"].tutorial_requested.connect(request.bind("tipos"))
	main._dock["rules"].tutorial_requested.connect(request.bind("regras"))
	for pair in [["territorio", main._dock["territory"]], ["relevo", tool_panel.edit_bar], ["recursos", main._dock["resources"]], ["povoados", main._dock["settlements"]],
			["registros", main._dock["search"]], ["sobreposicoes", main._presence], ["calendarios", main._dock["calendar"]]]:
		pair[1].visibility_changed.connect(_on_menu.bind(pair[0]))
	for key in DIALOGS:
		var dialog: Window = _dialog(key)
		dialog.visibility_changed.connect(_on_menu.bind(key))
	if sheet != null:
		sheet.tutorial_requested.connect(func() -> void: request(_sheet_key()))
		sheet.visibility_changed.connect(_on_sheet)
		sheet.page_changed.connect(func(_page: String) -> void: _on_sheet())


static func name_of(key: String) -> String:
	for group in GROUPS:
		for t in group[1]:
			if t[0] == key:
				return t[1]
	return key


## Na primeira vez que o jogo abre: quer ver o tutorial? Qualquer resposta vale para sempre.
func offer_basic() -> void:
	if not auto or _settings.value("tutorial_asked") or current != "":
		return
	current = BASIC
	overlay.ask("Bem-vindo ao Evron", "Quer ver um tutorial rápido? São 7 passos mostrando cada parte da tela. Dá para usar o jogo enquanto ele está aberto, e parar quando quiser.",
		"Para ver depois: Opções → Ajuda.", true, false, "Não, obrigado")


## Pedido pelo menu ou pelo botão "?": mostra agora; se o menu está fechado, abre e mostra.
func request(key: String) -> void:
	overlay.close()
	_end()
	if is_open(key):
		_run(key)
		return
	_pending = key
	var missing := _open(key)
	if is_open(key):
		if _pending == key:  # abriu na hora, sem passar pelo aviso de visibilidade
			_pending = ""
			_run.call_deferred(key)
	elif missing != "":
		current = key
		overlay.notice(name_of(key), missing)


## O menu daquele tutorial está na tela?
func is_open(key: String) -> bool:
	var m = _main
	if key in ALWAYS_THERE:
		return true
	if SHEET_PAGES.has(key):
		var sheet = m.domains.sheet
		return sheet != null and sheet.visible and sheet.active_page() == SHEET_PAGES[key]
	match key:
		"territorio":
			return m._dock["territory"].visible
		"relevo":
			return m.tool_panel.edit_bar.visible
		"recursos":
			return m._dock["resources"].visible
		"povoados":
			return m._dock["settlements"].visible
		"registros":
			return m._dock["search"].visible
		"sobreposicoes":
			return m._presence.visible
		"calendarios":
			return m._dock["calendar"].visible
		"tipos", "regras":
			return _dialog(key).visible
	return false


## Abre o menu. Devolve o que falta quando não dá para abrir sozinho ("" = abriu ou está abrindo).
func _open(key: String) -> String:
	var m = _main
	if SHEET_PAGES.has(key):
		var page: String = SHEET_PAGES[key]
		var sheet = m.domains.sheet
		if m.domains.current() == 0:
			return "Clique num país no mapa (ou escolha um cadastro nos Registros): o tutorial começa quando a ficha estiver aberta."
		sheet.show_page(page)
		if sheet.current_id() != m.domains.current():
			m.domains.refresh_sheet()
		if not sheet.has_page(page):
			return "Este cadastro não tem a página %s. Selecione um país, uma província ou um município: o tutorial começa sozinho." % page
		return ""
	match key:
		"territorio":
			m._start_territory()  # sem nada selecionado vem a pergunta do tipo: o tutorial começa quando o pincel aparecer
		"relevo":
			m.set_tool(0)
		"recursos":
			m.resources.set_open(true)
		"povoados":
			m.production.set_open(true)
		"registros":
			m._dock["search"].visible = true
		"sobreposicoes":
			m.mode_rail._overlays.button_pressed = true
		"calendarios":
			m._open_config("calendarios")
		"tipos", "regras":
			m._open_config(key)
	return ""


func _dialog(key: String) -> Window:
	return _main._dock[DIALOGS[key]]._dialog


func _sheet_key() -> String:
	for key in SHEET_PAGES:
		if SHEET_PAGES[key] == _main.domains.sheet.active_page():
			return key
	return "ficha"


## A ficha apareceu, sumiu ou trocou de página.
func _on_sheet() -> void:
	var sheet = _main.domains.sheet
	if not sheet.visible:
		if overlay.asking and SHEET_PAGES.has(current) and _pending == "":
			overlay.close()
			_end()
		return
	_appeared(_sheet_key())


## Um menu apareceu ou sumiu.
func _on_menu(key: String) -> void:
	if is_open(key):
		_appeared(key)
		return
	if current != key:
		return
	if overlay.asking and _pending != key:  # fechou antes de responder: pergunta de novo na próxima vez
		overlay.close()
		_end()
	elif DIALOGS.has(key):  # a janela levou o cartão junto: o tutorial acaba com ela
		overlay.close()
		_end()


func _appeared(key: String) -> void:
	if _pending == key:
		_pending = ""
		if overlay.asking:
			overlay.close()
		current = ""
		_run.call_deferred(key)  # um quadro depois: os controles já estão no lugar
		return
	if overlay.asking and current != BASIC and current != key and _pending == "":
		overlay.close()  # a pergunta era de outro menu
		_end()
	_offer.call_deferred(key)


func _offer(key: String) -> void:
	if not auto or current != "" or not is_open(key) or not _settings.value("offer_tool_tutorials") or key in _settings.value("seen_tools"):
		return
	if key == "territorio" and TerritoryEditor.is_resource(_main.territories.territory_level):
		return  # pintando a área de um recurso: quem se apresenta é o tutorial dos recursos
	var count: int = Steps.of(key, _main).size()
	current = key
	_move_to(key)
	overlay.ask(name_of(key), "É a primeira vez que você abre este menu. Quer ver o que cada botão faz?",
		"%d %s. Depois: botão ? ou Opções → Ajuda." % [count, "passo" if count == 1 else "passos"], false, true)


func _answered(key: String) -> void:
	if key == BASIC:
		_settings.set_value("tutorial_asked", true)
	elif key != "":
		var seen: Array = _settings.value("seen_tools").duplicate()
		if not key in seen:
			seen.append(key)
			_settings.set_value("seen_tools", seen)


func _end() -> void:
	current = ""
	_settle.call_deferred()


## Põe o cartão onde o tutorial atual pede. Sempre depois do que está acontecendo: tirá-lo de dentro de uma janela enquanto ela
## se fecha derrubava o programa.
func _settle() -> void:
	_move_to(current)


func _run(key: String) -> void:
	if key in ["basico", "alto", "tempo", "mapas"]:
		_main.top_hud.set_minimized(false)  # os destaques falam do alto aberto
	current = key
	_move_to(key)
	overlay.run(Steps.of(key, _main).map(func(s): return _prepared(key, s)))


## Leva o cartão para a janela do tutorial (Tipos e Regras ficam por cima da tela) ou de volta para a tela.
func _move_to(key: String) -> void:
	var host: Node = _dialog(key) if DIALOGS.has(key) else _main.hud
	if overlay.get_parent() == host:
		return
	overlay.get_parent().remove_child(overlay)
	host.add_child(overlay)
	overlay.set_card_width(overlay.NARROW_WIDTH if key == "tipos" else overlay.CARD_WIDTH)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## O passo como o cartão o recebe: onde está o destaque (rect) e como pôr a parte falada na tela (show).
func _prepared(key: String, s: Dictionary) -> Dictionary:
	var out := {"title": s.title, "text": s.text, "try": s.get("try", ""), "tip": s.get("tip", ""), "watch": s.get("watch", Callable())}
	var find: Array = s.find
	if not find.is_empty():
		out.rect = func() -> Rect2: return _around(_first(find))
	var prep: Callable = s.get("prep", Callable())
	out.show = func() -> void:
		if not is_open(key):
			_open(key)
		if prep.is_valid():
			prep.call()
		if not find.is_empty():
			_scroll_to.call_deferred(find)
	return out


## O primeiro grupo de controles que está na tela.
static func _first(find: Array) -> Array:
	for group in find:
		var shown: Array = group.call().filter(func(c) -> bool: return c != null and is_instance_valid(c) and c.is_visible_in_tree())
		if not shown.is_empty():
			return shown
	return []


## O retângulo que envolve os controles, cortado pelo que a rolagem deixa ver.
static func _around(controls: Array) -> Rect2:
	var all := Rect2()
	for c in controls:
		var r: Rect2 = c.get_global_rect()
		var parent: Node = c.get_parent()
		while parent != null and not parent is Window:
			if parent is ScrollContainer:
				r = r.intersection(parent.get_global_rect())
			parent = parent.get_parent()
		if r.has_area():
			all = r if not all.has_area() else all.merge(r)
	return all


## Rola a lista até a parte falada.
static func _scroll_to(find: Array) -> void:
	var shown := _first(find)
	if shown.is_empty():
		return
	var control: Control = shown[0]
	var parent: Node = control.get_parent()
	while parent != null and not parent is Window:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
		parent = parent.get_parent()
