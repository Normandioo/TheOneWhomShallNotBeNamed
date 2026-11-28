extends RefCounted
## O texto dos tutoriais: o que cada menu tem, o que cada botão faz e o que experimentar. Cada passo diz também onde está a parte de que
## fala (para o contorno) e, quando dá, um estado do jogo que mostra que a experiência foi feita.
##
## Passo: {title, text, try, tip, find: [Callable() -> Array[Control]] (o primeiro grupo que está na tela é o destaque),
## watch: Callable() -> Variant (mudou = feito), prep: Callable() (deixa a parte na tela, depois de o menu estar aberto)}


static func step(title: String, text: String, find: Array = [], attempt := "", watch := Callable(), extra := {}) -> Dictionary:
	var s := {"title": title, "text": text, "find": find, "try": attempt, "watch": watch}
	s.merge(extra)
	return s


# --- onde estão as coisas ---------------------------------------------------------------------------------------------

## Os controles fixos.
static func these(controls: Array) -> Callable:
	return func() -> Array: return controls


## O cartão da ficha (ou de outro painel) que tem esse título.
static func box(root: Callable, title: String) -> Callable:
	return func() -> Array:
		var node = root.call()
		if node == null:
			return []
		for l in node.find_children("*", "Label", true, false):
			if l.text == title and l.get_parent() is VBoxContainer and l.get_parent().get_parent() is PanelContainer:
				return [l.get_parent().get_parent()]
		return []


## Os botões (e caixas e menus) cujo texto, dica ou dica de digitação começa com um dos textos pedidos.
static func named(root: Callable, starts: Array) -> Callable:
	return func() -> Array:
		var node = root.call()
		if node == null:
			return []
		var out: Array = []
		for start in starts:
			for c in node.find_children("*", "Control", true, false):
				var texts: Array = []
				if c is Button:
					texts = [c.text, c.tooltip_text]
				elif c is LineEdit or c is TextEdit:
					texts = [c.placeholder_text]
				elif c is Label:
					texts = [c.text]
				if c.is_visible_in_tree() and texts.any(func(t: String) -> bool: return t.begins_with(start)):
					out.append(c)
					break
		return out


# --- a lista ------------------------------------------------------------------------------------------------------------

## Os passos de um tutorial. m: a cena principal.
static func of(key: String, m) -> Array:
	match key:
		"basico": return _basic(m)
		"alto": return _top(m)
		"tempo": return _time(m)
		"mapas": return _modes(m)
		"ficha": return _sheet_general(m)
		"governo": return _government(m)
		"povo": return _people(m)
		"populacao": return _population(m)
		"pg_territorio": return _sheet_territory(m)
		"pg_calendarios": return _sheet_calendars(m)
		"registros": return _registry(m)
		"sobreposicoes": return _overlays(m)
		"territorio": return _brush(m)
		"relevo": return _relief(m)
		"recursos": return _resources(m)
		"povoados": return _settlements(m)
		"calendarios": return _calendar_window(m)
		"tipos": return _types(m)
		"regras": return _rules(m)
	return []


static func _basic(m) -> Array:
	var top = m.top_hud
	return [
		step("Girar o globo", "Arraste com o mouse para girar o globo. Use a roda para aproximar e afastar.", [],
			"arraste o globo ou use a roda agora.", func(): return [snappedf(m.globe.camera.yaw, 0.05), snappedf(m.globe.camera.target_dist, 0.05)]),
		step("Escolha um país", "Clique num país no mapa. O alto à esquerda passa a mostrar o emblema e os números dele.", [these([top])],
			"clique num país.", func(): return m.domains.current(), {"tip": "Clicar num número do alto abre a categoria dele."}),
		step("As categorias", "Cada botão abre uma janela à esquerda: Ficha, Governo, Povo, População e assim por diante. Só uma fica aberta por vez.",
			[these(top.category_buttons.values()), these([top])], "abra uma categoria e feche pelo mesmo botão.", func(): return m.windows.window_open(),
			{"tip": "Cada janela tem um botão ? com o tutorial dela."}),
		step("Pintar no mapa", "Aperte Território (ou a tecla T). Escolha o que vai pintar, desenhe e conclua no ✓. Depois dê o nome.", [these([m.tool_panel])],
			"abra o Território e depois cancele ou conclua.", func(): return [m.territories.painting_territory, m._dock["region_card"].visible], {"tip": "Ctrl+Z desfaz."}),
		step("Os mapas", "Aqui você troca o que o globo mostra: países, subdivisões, culturas, religiões, relevo, clima e outros.", [these([m.mode_rail])],
			"clique em outro modo de mapa.", func(): return [m.layer, m.territories.territory_level]),
		step("Plano e Medir", "Plano (tecla M) mostra o mundo num mapa plano, com as mesmas camadas e cadastros do globo. Medir é a régua: clique nos pontos e a distância pela superfície aparece no quadro do ponto fixado.",
			[these([m.tool_panel.flat_toggle, m.tool_panel.ruler_toggle])], "ligue o Plano e desligue de novo.", func(): return m.globe.flat,
			{"tip": "Na régua, Backspace tira o último ponto e Esc encerra."}),
		step("Tempo, busca e mundo", "Pause ou avance o tempo, busque qualquer nome, abra os Registros e o menu Mundo.", [these([m.tool_panel.world_block])],
			"abra os Registros.", func(): return m._dock["search"].visible, {"tip": "Os ícones de aviso logo abaixo mostram o que falta no país selecionado."}),
		step("Pronto", "Você já sabe o básico. Todos os tutoriais estão em Opções → Ajuda; o botão ? no alto à direita leva até lá.", [], "",
			Callable(), {"tip": "As opções ficam em Mundo → Opções."}),
	]


static func _top(m) -> Array:
	var top = m.top_hud
	return [
		step("O emblema", "Mostra o que está selecionado, na cor dele. Clicar abre a ficha. O ✕ tira a seleção (Esc também). Sem seleção, mostra o Mundo.",
			[these([top._emblem]), these([top])], "selecione um país no mapa.", func(): return m.domains.current()),
		step("Os números", "População, área, subdivisões, cidades e a maior cultura, religião e idioma do selecionado. Número em amarelo está faltando.",
			[these(top.stat_buttons), these([top])], "clique num número para abrir a categoria dele.", func(): return m.domains.sheet.active_page() if m.domains.sheet.visible else ""),
		step("As categorias", "Ficha, Governo, Povo, População, Território, Recursos, Economia e Calendários. Os apagados precisam de um país selecionado.",
			[these(top.category_buttons.values()), these([top])], "abra e feche uma categoria.", func(): return m.windows.window_open()),
		step("Minimizar", "O botão ^ recolhe o alto numa faixa fina com o nome; a seta da faixa traz de volta.", [these([top._fold]), these([top._expand])],
			"minimize e depois expanda.", func(): return top.minimized),
		step("Avisos", "Os ícones amarelos, no alto à direita, aparecem quando falta algo no selecionado: território, população total, subdivisões sem área. Clicar leva ao lugar certo.",
			[these([m.windows.alerts]), these([m.tool_panel.world_block])], "passe o mouse sobre um aviso para ler.", Callable()),
	]


static func _time(m) -> Array:
	var bar = m.time_bar
	var block = func(): return m.tool_panel.world_block
	return [
		step("Pausar e continuar", "O botão ▶ faz o tempo do mundo correr; apertar de novo pausa. A data aparece ao lado.", [these([bar._play])],
			"ligue o tempo e pause de novo.", func(): return m.clock.running),
		step("Velocidade", "Quanto tempo do mundo passa a cada segundo: 1 minuto, 1 hora ou 1 dia.", [these([bar._speed])],
			"troque a velocidade.", func(): return m.clock.speed),
		step("Calendário universal", "O relógio abre uma janelinha: consultar uma data (o presente é preservado), avançar até ela, voltar ao presente e ver os marcos.",
			[named(block, ["Calendário:"])], "abra a janelinha do relógio.", func(): return bar._window.visible),
		step("Avançar", "Abre os saltos: +1 hora, +1 dia, +7 dias, +1 mês e +1 ano. Os meses que passam fazem os povoados produzirem.",
			[named(block, ["Avançar…"])], "abra os saltos de tempo.", Callable()),
		step("Buscar", "Procura cadastros, lugares e nomes, até os antigos (Ctrl+F).", [named(block, ["Buscar…"])],
			"clique em Buscar e digite um nome.", func(): return m._dock["search"].query()),
		step("Registros", "A árvore com todos os cadastros do mundo, por tipo (tecla O).", [named(block, ["Registros"])],
			"abra os Registros.", func(): return m._dock["search"].visible),
		step("Menu Mundo", "Opções, Tipos/campos/vínculos, Regras, Calendários, e exportar ou importar o mundo (uma pasta .world).",
			[named(block, ["Mundo"])], "abra o menu para ver os itens.", Callable(), {"tip": "Importar troca o mundo atual: exporte antes se quiser guardá-lo."}),
		step("Ajuda", "O ? leva a Opções → Ajuda, com todos os tutoriais. F1 mostra a lista de atalhos.", [named(block, ["Ajuda"])]),
	]


static func _modes(m) -> Array:
	var rail = m.mode_rail
	var mode = func(): return [m.layer, m.territories.territory_level, m.territories.subdivisions_view]
	return [
		step("Modos de mapa", "O título diz o que o globo está mostrando agora.", [these([rail])]),
		step("Político", "Pol mostra os países. Clicar num país no mapa o seleciona.", [these([rail._level_buttons["pais"]])], "clique em Pol.", mode),
		step("Subdivisões", "Sub reparte o país selecionado nas subdivisões dele, cada uma na sua cor; os outros ficam em cinza.", [these([rail._level_buttons["subdivisoes"]])],
			"com um país selecionado, clique em Sub.", mode),
		step("Povo no mapa", "Rel, Cul, Etn, Raç e Idi mostram as áreas de religião, cultura, etnia, raça e idioma. Clicar numa área abre o cadastro dela.",
			[these([rail._level_buttons["religiao"], rail._level_buttons["cultura"], rail._level_buttons["etnia"], rail._level_buttons["raca"], rail._level_buttons["idioma"]])],
			"abra o mapa de culturas.", mode),
		step("Biomas", "Bio mostra todos os biomas da camada editável: nasce igual ao mapa do Gleba e muda quando você pinta biomas pela barra do Relevo.",
			[these([rail._level_buttons["bioma"]])], "clique em Bio.", mode),
		step("Recursos", "Rec mostra todos os recursos da natureza juntos, cada um na sua cor, com os pontos marcados. A legenda acima dos modos liga e desliga cada recurso; clicar num lugar abre o recurso no painel.",
			[these([rail._level_buttons["recursos"]])], "clique em Rec.", func(): return m.resources.rec),
		step("Satélite e visão geral", "O primeiro ícone da linha Planeta abre as vistas do planeta (satélites e o mapa político); a bolinha marca a atual.",
			[these([rail._group_buttons["Visão geral"]])], "escolha uma vista.", mode),
		step("Planeta", "Relevo, clima, ecologia, solos, hidrologia, geologia e organização. Cada ícone abre a lista das camadas do grupo.",
			[these(rail._group_buttons.values().filter(func(b): return b != rail._group_buttons["Visão geral"]))], "abra um grupo e escolha uma camada.", mode),
		step("Sobreposições", "Abre o painel com o que vai por cima do mapa: legenda, nomes, rios, áreas e marcadores.", [these([rail._overlays])],
			"abra as Sobreposições.", func(): return m._presence.visible),
	]


static func _sheet_root(m, page: String) -> Callable:
	return func(): return m.domains.sheet._pages.get(page)


static func _sheet_value(m, what: String) -> Callable:
	return func():
		var id: int = m.domains.current()
		if id == 0:
			return null
		var s = m.domains.registry.Sheet(id, m.domains.shown_t)
		return null if s == null else str(s[what])


static func _sheet_general(m) -> Array:
	var page := _sheet_root(m, "Ficha")
	return [
		step("Nome", "O nome do cadastro. Mudar aqui corrige a grafia; vale ao apertar Enter ou sair do campo.", [box(page, "Identidade")],
			"corrija o nome e aperte Enter (Ctrl+Z não desfaz nomes: escreva o antigo de volta).", _sheet_value(m, "name"),
			{"tip": "Uma mudança de nome na história do mundo é registrada em Nomes."}),
		step("Resumo e etiquetas", "O resumo é um texto livre. Em ＋ etiqueta, escreva uma palavra e aperte Enter; o ✕ ao lado de uma etiqueta a remove.",
			[named(page, ["Opcional", "＋ etiqueta"]), box(page, "Identidade")], "crie uma etiqueta e depois remova.", _sheet_value(m, "tags")),
		step("Nomes", "Outros nomes do cadastro: escolha o tipo (alternativo, oficial, gentílico…), escreva e aperte ＋. A busca acha por qualquer um deles.",
			[box(page, "Nomes")], "veja a lista de tipos de nome.", _sheet_value(m, "names")),
		step("Conteúdo", "＋ Adicionar informação mostra um campo deste tipo de cadastro. Cada campo diz se é conhecido, desconhecido ou não se aplica.",
			[box(page, "Conteúdo")], "abra a lista de informações.", Callable(), {"tip": "Campos novos são criados em Mundo → Tipos, campos e vínculos."}),
		step("Ações", "Duplicar faz uma cópia (com vínculos, se marcado). Excluir… apaga um cadastro criado por engano: pede confirmação e não dá para desfazer.",
			[box(page, "Ações")], "", Callable()),
	]


static func _government(m) -> Array:
	var page := _sheet_root(m, "Governo")
	var sheet = m.domains.sheet
	var covered: bool = String(sheet._sheet.get("kind", "")) in ["pais", "provincia", "municipio"]
	var relations := step("Outras relações", "Vínculos com outros cadastros. Escolha o tipo, busque o outro e aperte Vincular; o ✕ apaga um vínculo criado por engano.",
		[named(page, ["Outras relações"]), box(page, "Relações"), box(page, "Outras relações")], "abra as relações e veja os tipos de vínculo.", _sheet_value(m, "links"))
	if not covered:
		return [relations]
	var out: Array = []
	if String(sheet._sheet.get("kind", "")) in ["provincia", "municipio"]:
		out.append(step("Pertence a", "A cadeia até o país. Clicar num nome abre a ficha dele. Digite no campo para trocar o país ou a subdivisão de cima; o ✕ tira o vínculo (a pintura continua). No alto da ficha, Como se chama muda o nome do tipo só desta.",
			[box(page, "Pertence a")], "clique no nome do país.", func(): return m.domains.current()))
	out.append(step("Ações rápidas", "Pintar território abre o pincel no território deste cadastro.", [these([sheet._actions])], "", Callable()))
	out.append(relations)
	return out


static func _people(m) -> Array:
	var page := _sheet_root(m, "Povo")
	return [
		step("Povo e cultura", "Culturas, etnias, raças, religiões e idiomas deste território. Clicar num nome abre o cadastro dele.", [box(page, "Povo e cultura")],
			"clique no nome de uma cultura (volte pelo emblema ou pelos Registros).", func(): return m.domains.current()),
		step("De onde vem o número", "“pelo mapa” é a parte da área coberta pelas áreas pintadas. “à mão” é um vínculo feito na ficha, sem porcentagem, que o ✕ remove.",
			[box(page, "Povo e cultura")]),
		step("Escolher na lista", "Liga a este território um cadastro que já existe: abre um campo de busca.", [named(page, ["＋ Escolher na lista"])],
			"abra a busca e feche clicando de novo.", Callable()),
		step("Pintar no mapa", "Desenha a área onde aquilo predomina. O mapa passa a mostrar o tipo e a porcentagem sai da sobreposição.", [named(page, ["Pintar no mapa"])],
			"comece a pintar e descarte com Esc.", func(): return m.territories.drafting),
		step("Categorias vazias", "As que não têm nada ficam em uma linha no fim, com (0). Clicar abre a categoria para ligar a primeira.",
			[named(page, ["Culturas (0)", "Etnias (0)", "Raças (0)", "Religiões (0)", "Idiomas (0)"]), box(page, "Povo e cultura")]),
	]


static func _population(m) -> Array:
	var page := _sheet_root(m, "População")
	var total = func():
		var id: int = m.domains.current()
		return null if id == 0 else str(m.domains.registry.PopulationOf(id, m.domains.shown_t))
	return [
		step("População total", "O número exato de habitantes na data mostrada pelo relógio. Escreva e aperte Definir; o ✕ ao lado do total o apaga.",
			[named(page, ["número exato", "Definir"]), box(page, "População")], "defina um total.", total,
			{"tip": "Em outra data você pode registrar outro número: o histórico fica."}),
		step("Por cidade", "Quanto desse total mora em cada cidade. O ✕ tira a cidade. “Fora das cidades” é o que sobra; se as cidades passarem do total, aparece um aviso.",
			[box(page, "População")]),
		step("Adicionar cidade", "Escolha uma cidade deste cadastro, escreva os habitantes e aperte Adicionar cidade.",
			[named(page, ["habitantes da cidade", "Adicionar cidade"]), box(page, "População")], "adicione uma cidade.", total),
		step("Cidade nova", "Na lista, “＋ Nova cidade…” cria uma cidade: antes, clique no globo para fixar onde ela fica, depois dê o nome e os habitantes.",
			[named(page, ["＋ Nova cidade"]), box(page, "População")], "clique no globo para fixar um ponto.", func(): return m.domains.fixed_dir),
		step("Composição", "＋ Composição diz quanto da população, numa cidade ou numa região, é de cada cultura, etnia, raça, religião ou idioma. Exclusivas e lista completa precisam somar 100%; a ficha avisa o que corrigir. O ✕ de cada composição a apaga (Ctrl+Z desfaz).",
			[named(page, ["＋ Composição"]), box(page, "População")], "abra o formulário e feche.", Callable()),
	]


static func _sheet_territory(m) -> Array:
	var page := _sheet_root(m, "Território")
	var sheet = m.domains.sheet
	return [
		step("Pintar", "Pintar território abre o pincel. Pincel de fronteira desenha o limite à mão.",
			[these([sheet._actions, sheet._boundary_brush])], "abra o pincel e conclua no ✓.", func(): return m.territories.painting_territory),
		step("Área e cor", "A área pintada, o quadrado da cor no mapa e Apagar, que tira todo o território deste cadastro (Ctrl+Z desfaz).",
			[box(page, "Território"), box(page, "Área no mapa")], "abra a cor e feche sem mudar.", Callable()),
	] + ([
		step("Dividir", "Dividir abre o lápis de fronteira: uma linha de uma borda até a outra tira um lado, que vira um cadastro novo, com as subdivisões que ficam desse lado. A capital e as outras ligações ficam com o original. \"Outro lado\" troca; Ctrl+Z desfaz tudo de uma vez.",
			[named(page, ["Dividir"]), box(page, "Território")], "", Callable()),
	] if String(sheet._sheet.get("kind", "")) in ["pais", "provincia", "municipio"] else []) + ([
		step("Reivindicação", "Pintar reivindicação pinta o que este país reivindica, inclusive sobre outro país: a fronteira não muda. A seção diz quanto ele reivindica de quem; no mapa, as reivindicações aparecem em listras (Sobreposições → Reivindicações).",
			[named(func(): return m.domains.sheet, ["Pintar reivindicação"]), box(page, "Território")], "", Callable()),
	] if String(sheet._sheet.get("kind", "")) == "pais" else []) + ([
		step("Subdivisões", "A lista das subdivisões daqui. Clicar num nome abre a linha ali mesmo: nome, como se chama, população, área e cor, pintar, ver no mapa, ficha completa e excluir. No mapa de subdivisões, clicar numa delas abre a linha.",
			[box(page, "Subdivisões")], "clique numa subdivisão da lista.", func(): return sheet.open_division),
		step("Nova divisão", "＋ Pintar divisão abre o pincel; depois o cartão pergunta o nome e como ela se chama, e ela aparece aberta na lista. Ligar existente… junta uma que já existe.",
			[named(page, ["＋ Pintar divisão", "Ligar existente"])], "abra Ligar existente… e veja a busca.", Callable()),
	] if String(sheet._sheet.get("kind", "")) in ["pais", "provincia"] else []) + [
		step("Lugares", "Os lugares ligados ao cadastro, como a capital. Clicar no nome leva o mapa até lá; o ✕ desliga o lugar. O ✎ edita o lugar: nome, tipo e raio, Mover no globo (o próximo clique leva o ponto e a área), Duplicar e Excluir lugar. Tudo desfaz com Ctrl+Z.", [box(page, "Lugares")],
			"clique no nome de um lugar.", func(): return [snappedf(m.globe.camera.yaw, 0.05), snappedf(m.globe.camera.pitch, 0.05)]),
		step("＋ Existente", "Liga um lugar que já existe no mundo, dizendo o papel dele (capital, sede, origem…).", [named(page, ["＋ Existente"])],
			"abra e feche o formulário.", Callable()),
		step("＋ No ponto fixado", "Cria um lugar onde você clicou no globo: nome, raio (0 é um ponto), tipo e papel.", [named(page, ["＋ No ponto fixado"])],
			"clique no globo para fixar um ponto e abra o formulário.", func(): return m.domains.fixed_dir),
	]


static func _sheet_calendars(m) -> Array:
	var page := _sheet_root(m, "Calendários")
	return [
		step("Calendários em uso", "A data universal e a mesma data em cada calendário que este cadastro usa. O ✕ apaga um uso criado por engano.",
			[box(page, "Calendários")]),
		step("Usar um calendário", "Escolha o calendário, para que ele serve e aperte Usar.", [named(page, ["Usar"]), box(page, "Calendários")],
			"", Callable(), {"tip": "Sem nenhum na lista, crie um em Mundo → Calendários…"}),
	]


static func _registry(m) -> Array:
	var panel = m._dock["search"]
	var root = func(): return panel
	return [
		step("Buscar por nome", "Acha qualquer cadastro, também por nomes alternativos e antigos, sem ligar para acentos. Com texto, vira uma lista com filtro por tipo.",
			[named(root, ["Buscar por nome"]), these([panel])], "digite parte de um nome e depois apague.", func(): return panel.query()),
		step("A árvore", "Uma seção por tipo, com a contagem; o título abre e fecha. Nos países, as subdivisões ficam dentro de cada um, com o nome do tipo.",
			[these([panel._sections]), these([panel])], "feche uma seção e abra de novo.", Callable()),
		step("Abrir um cadastro", "Clicar num nome abre a ficha dele (os Registros dão lugar à ficha).", [these([panel._sections]), these([panel])],
			"clique num nome.", func(): return m.domains.current()),
		step("Vários de uma vez", "Com texto na busca, Ctrl ou Shift + clique marcam vários resultados. Com dois ou mais, aparece a barra: Etiquetar põe a mesma etiqueta em todos e Excluir marcados apaga todos, com o território. Um Ctrl+Z desfaz a operação inteira.",
			[named(root, ["Buscar por nome"]), these([panel])], "", Callable()),
		step("Criar", "＋ País e ＋ Sociedade (país, cultura e etnia juntos) usam o texto da busca como nome. ＋ Outro cria cadastros dos demais tipos.",
			[named(root, ["＋ País", "＋ Sociedade", "＋ Outro"]), these([panel])], "abra ＋ Outro para ver os tipos.", Callable()),
	]


static func _overlays(m) -> Array:
	var panel = m._presence
	var root = func(): return panel
	return [
		step("Legenda, nomes e rios", "Legenda do mapa mostra as cores no canto. Nomes dos países escreve os nomes no globo. Rios em destaque os realça por cima de qualquer mapa.",
			[these([panel.legend_check, panel.names_check, panel.rivers_check]), these([panel])], "desligue e ligue os nomes dos países.",
			func(): return [panel.legend_check.button_pressed, panel.names_check.button_pressed, panel.rivers_check.button_pressed]),
		step("Áreas sobre o mapa", "Mostra culturas, etnias, raças, religiões ou idiomas por cima dos países, que ficam em cinza. Reivindicações vão em listras na cor de quem reivindica, com os países na cor deles. Uma de cada vez.",
			[these(panel._area_checks.values()), these([panel])], "ligue uma área e depois desligue.", func(): return m.territories.overlay_level),
		step("Marcadores por lugar", "Os círculos e áreas ligados a lugares: escolha entre os da ficha aberta e os de todos, e quais camadas aparecem.",
			[named(root, ["▸ Marcadores", "▾ Marcadores"]), these([panel])], "abra os marcadores.", Callable()),
	]


static func _brush(m) -> Array:
	var bar = m._dock["territory"]
	var painted = func(): return [m.territories.territory.Version if m.territories.territory != null else 0, m.territories.painting_territory]
	return [
		step("A barra do pincel", "Ela aparece enquanto você pinta. O nome à esquerda diz o que está sendo pintado.", [these([bar])],
			"arraste no globo com o botão esquerdo (o direito gira).", painted, {"tip": "Ctrl+Z desfaz o que você experimentar."}),
		step("Os modos", "Pincel: arraste para pintar.\nBalde: preenche uma área cercada.\nBorracha: apaga só o território deste.\nConta-gotas: passa a pintar o território clicado.\nFronteira: o lápis. Um traço que começa e termina na borda vira a borda; um contorno fechado em terra livre vira território.",
			[these(bar._buttons.values())], "troque de modo.", func(): return m.territories.territory_mode),
		step("Tamanho e costa", "O controle muda o raio do pincel. Só em terra faz a costa do território seguir a costa do mapa. Não invadir (ligado) para o pincel na fronteira dos outros; desligue para tomar território deles.", [these([bar._brush_controls]), these([bar])],
			"mude o raio.", func(): return m.territories.territory_radius),
		step("Ações", "Unir com outro, importar um PNG, crescer este país pela terra sem dono, crescer todos e assentar as fronteiras no relevo.", [these([bar._actions]), these([bar])],
			"passe o mouse em cada ícone para ler o que faz.", Callable(), {"tip": "Valem para cadastros que já existem; num cadastro novo, crie antes."}),
		step("Concluir", "O ✓ (ou Esc) sai da pintura. Num cadastro novo, vem o cartão para dar o nome.", [these([bar.done_button])],
			"conclua quando quiser.", func(): return m.territories.painting_territory),
	]


static func _relief(m) -> Array:
	var tools = m.tool_panel
	return [
		step("Esculpir o relevo", "Com um pincel de relevo ativo, o botão esquerdo esculpe e o direito gira o globo.", [these([tools.edit_bar])],
			"arraste sobre a terra.", func(): return m.commands.can_undo()),
		step("Os pincéis", "Elevar e Rebaixar mudam a altura. Nivelar leva à altura de onde você começou; Suavizar tira asperezas. Montanhas, Erosão e Vales criam formas.",
			[these(tools._buttons.slice(0, 7))], "escolha outro pincel.", func(): return m.tool),
		step("Costa", "Terra e Mar mudam a costa: o miolo do pincel vira terra baixa ou mar raso. Os mapas de imagem (clima, solos...) passam a mostrar o mar novo e a terra nova em tom neutro, porque o Gleba não tem dado para ela.",
			[these(tools._buttons.slice(7))], "escolha Terra ou Mar.", func(): return m.tool),
		step("Lagos e biomas", "Escolha a categoria e aperte Pintar lagos ou Pintar biomas: abre o pincel do território nessa camada. Lago pinta água; Seco tira um lago do Gleba; a borracha devolve o original. Os biomas aparecem no modo de mapa Bio.",
			[named(func(): return tools.edit_bar, ["Pintar lagos", "Pintar biomas"])], "", Callable()),
		step("Controles", "Raio é o tamanho do pincel. Intensidade é a força. Rugosidade vai de liso a irregular.", [these([tools.radius.get_parent().get_parent()])],
			"mude um dos controles.", func(): return [m.brush.radius_km, m.brush.strength, m.brush.roughness]),
		step("Desfazer e sair", "Ctrl+Z desfaz e Ctrl+Y refaz. Navegar (V) sai da ferramenta.", [these([tools._navigate, tools._undo, tools._redo])],
			"desfaça o que esculpiu e volte a Navegar.", func(): return m.tool, {"tip": "Clima, solos e os outros mapas do Gleba não são recalculados: só seguem a costa nova."}),
	]


static func _resources(m) -> Array:
	var panel = m._dock["resources"]
	var root = func(): return panel
	var screen = func(): return [panel.list_box.visible, panel.tab]
	var page = func(index: int): return func() -> Array: return [panel.pages[index]]
	var list = func(): m.resources.panel.back_requested.emit() if not panel.list_box.visible else null
	var open_first = func():
		if panel.list_box.visible:
			var types: Array = m.domains.registry.ResourceTypes("")
			if not types.is_empty():
				panel.type_chosen.emit(int(types[0].id))
	var go_tab = func(index: int): return func():
		open_first.call()
		if not panel.list_box.visible:
			panel.tab_buttons[index].pressed.emit()
	return [
		step("O catálogo", "Os recursos em dois grupos: da natureza (vão para o mapa) e fabricados (feitos nos povoados). O ícone diz a categoria, na cor do recurso; amarelo avisa o que falta. A caixa busca pelo nome. Clique numa linha para abrir.",
			[these([panel])], "clique num recurso e volte com ‹.", screen, {"prep": list}),
		step("Novo recurso", "＋ Novo recurso pede o nome, de onde ele vem (da natureza: mineral, vegetal ou animal; ou fabricado) e a unidade. Um fabricado, como espada ou pão, não vai para o mapa. Se o nome for o de um modelo pronto (Cobre, Estanho, Ferro, Sal), ele oferece os critérios para gerar no mapa.",
			[these([panel.new_toggle]), these([panel])], "abra o formulário e feche sem criar.", Callable(), {"prep": list}),
		step("O menu ⋯", "Na lista: gerar no mapa, de uma vez, todos os recursos que têm critérios (uma prévia; Aplicar grava e Descartar desiste). Dentro de um recurso: editar e excluir. Nos dois: as ferramentas do autor, com os testes da geração.",
			[these([panel.menu_button]), these([panel])], "", Callable(), {"prep": list}),
		step("Pôr no mapa", "Dentro de um recurso, três caminhos: Pintar área, Marcar ponto (um lugar pequeno, como uma mina) ou Gerar sozinho pelos mapas do planeta. Um bem fabricado mostra aqui as receitas e os povoados que o fazem.",
			[these([panel.add_row]), these([panel])], "", Callable(), {"prep": go_tab.call(0)}),
		step("Onde está", "Cada lugar com a quantidade; amarelo é sem quantidade, e aí os povoados não extraem dele. Clique numa linha para abrir o lugar: quantidade, ver, pintar, mover, excluir e proteger. Em Detalhes avançados ficam nome, teor, datas, quem conhece e direitos.",
			[page.call(0), these([panel])], "clique num lugar da lista.", Callable(), {"prep": go_tab.call(0)}),
		step("Gerar sozinho", "1 · Onde procurar: escolha um modelo; as etiquetas dizem o que ele procura e Mudar critérios abre as condições. 2 · Como preencher: Tudo que serve segue o mapa (trechos com menos de 5.000 km² ficam de fora; no máximo 200, os maiores); Alguns lugares faz manchas separadas. 3 · Quanto há é opcional. Mostrar no mapa abre a prévia; embaixo, Aplicar grava e Descartar desiste. ‹ volta para o recurso.",
			[page.call(1), these([panel])], "peça uma prévia e descarte.", Callable(), {"prep": go_tab.call(1)}),
		step("Editar", "Pelo ⋯ do recurso: nome, cor, descrição, categoria e unidade; Salvar alterações grava. Excluir recurso fica no fim e só funciona quando ele não está no mapa. ‹ volta.",
			[page.call(2), these([panel])], "", Callable(), {"prep": go_tab.call(2)}),
	]


static func _settlements(m) -> Array:
	var panel = m._dock["settlements"]
	var screen = func(): return [panel.list_box.visible, panel.selected_box.visible, panel.recipes_box.visible]
	var list = func(): panel.back_requested.emit() if not panel.list_box.visible else null
	var open_first = func():
		if panel.list_box.visible:
			var villages: Array = m.domains.registry.Settlements()
			if not villages.is_empty():
				panel.settlement_chosen.emit(int(villages[0].id))
	var go_tab = func(index: int): return func():
		open_first.call()
		if panel.selected_box.visible:
			panel.tab_buttons[index].pressed.emit()
	var page = func(index: int): return func() -> Array: return [panel.pages[index]]
	return [
		step("Os povoados", "A cada mês do calendário, eles produzem o que dá com os trabalhadores, os insumos e os recursos ao alcance.", [these([panel])],
			"clique num povoado e volte.", screen, {"prep": list}),
		step("Criar um povoado", "Dê um nome, diga quantos trabalhadores há, aperte Colocar no mapa e clique no globo.", [these([panel.new_name, panel.place_button]), these([panel])],
			"", Callable(), {"prep": list}),
		step("Receitas", "O que se pode fazer: trabalho em pessoas-dia, insumos (um pode substituir o de cima), o que sai e o que exige. Em Produz, Criar bem faz ali mesmo um bem fabricado novo, sem lugar no mapa.", [these([panel.recipes_button]), these([panel])],
			"abra as receitas e volte.", screen, {"prep": list}),
		step("Atividades", "Quem faz o quê. As de cima ficam primeiro com os trabalhadores e os insumos; Subir muda a ordem e Tirar remove. O que é feito num mês só pode ser usado no seguinte. Para uma atividade que ainda não existe, use ＋ Criar uma atividade diferente.",
			[page.call(0), these([panel])], "", Callable(), {"prep": go_tab.call(0)}),
		step("Estoque", "O que há no povoado na data mostrada. Pôr no estoque e Tirar do estoque lançam uma quantidade.", [page.call(1), these([panel])],
			"", Callable(), {"prep": go_tab.call(1)}),
		step("Editar", "Nome, trabalhadores, alcance (até onde busca recursos), capacidades, Ver no mapa, Mover e Excluir povoado (só sem histórico).",
			[page.call(2), these([panel])], "", Callable(), {"prep": go_tab.call(2)}),
		step("Ver a produção", "Avance o tempo no alto à direita: a produção acontece a cada mês que passa.", [these([m.tool_panel.time_slot])]),
	]


static func _calendar_window(m) -> Array:
	var panel = m._dock["calendar"]
	return [
		step("Calendários do mundo", "A lista dos calendários criados, cada um com a data de hoje nele.", [these([panel._list])]),
		step("Nome e era", "O nome do calendário, o nome da era e uma abreviação opcional.", [these([panel._name, panel._era, panel._abbr])],
			"escreva um nome (nada é criado sem o botão).", func(): return panel._name.text),
		step("O marco da era", "A data universal em que a era começa, o número do ano nesse dia, se a contagem cresce para o futuro ou para o passado e a hora em que o dia vira.",
			[these([panel._year, panel._month, panel._day, panel._first, panel._direction, panel._hour])]),
		step("Meses", "Doze nomes, um por linha. Vazio usa os do calendário universal. Os meses e os 365 dias são os mesmos do universal.", [these([panel._months])]),
		step("Criar", "Criar calendário grava. Depois, ligue-o a um país na categoria Calendários da ficha.", [named(func(): return panel, ["Criar calendário"])]),
	]


static func _types(m) -> Array:
	var panel = m._dock["types"]
	return [
		step("Novo tipo de cadastro", "Cria um tipo seu, como Fortaleza. Ele passa a aparecer em ＋ Outro, nos Registros.", [these([panel._type_name.get_parent()])],
			"escreva um nome (nada é criado sem o botão).", func(): return panel._type_name.text),
		step("Novo campo", "Um campo para a ficha: texto, número (com unidade, mínimo e máximo), escolha de uma lista ou sim/não.", [these([panel._field_name.get_parent()])],
			"troque o tipo do campo.", func(): return panel._field_type.selected),
		step("Para quais tipos", "Marque os tipos que terão o campo e aperte Adicionar campo.", [these([panel._kind_checks])]),
		step("Novo tipo de vínculo", "Como o vínculo se lê na origem e no destino (Protege / Protegida por) e entre quais tipos vale.", [these([panel._rel_out.get_parent(), panel._rel_src.get_parent()])]),
		step("Nova camada do mapa", "Uma camada para os marcadores por lugar: nome, cor e quais tipos ela mostra.", [these([panel._layer_name.get_parent(), panel._layer_checks])]),
	]


static func _rules(m) -> Array:
	var panel = m._dock["rules"]
	var root = func(): return panel._dialog
	return [
		step("Suas regras", "Uma regra calcula um campo a partir de outros campos, vínculos, população ou área. ＋ Nova regra começa uma; Abrir no editor mostra a escolhida.",
			[these([panel._list]), named(root, ["＋ Nova regra", "Abrir no editor"])]),
		step("Executar e modo", "Executar na data mostrada calcula agora. Trocar modo alterna entre manual, automática (a ficha mostra o valor) e desativada.",
			[named(root, ["Executar na data mostrada", "Trocar modo"])]),
		step("O que calcula", "O nome da regra, o tipo de cadastro e o campo que ela preenche.", [these([panel._name, panel._kind, panel._target])],
			"escolha um tipo.", func(): return panel._kind.selected),
		step("Os nós", "Cada botão põe um nó: número, campo, vínculos, população, área, distância, operação ou condição.",
			[named(root, ["＋ Número", "＋ Campo", "＋ Vínculos", "＋ População", "＋ Área", "＋ Distância", "＋ Operação", "＋ Se"])],
			"adicione um nó (Delete apaga).", func(): return panel._graph.get_child_count()),
		step("Ligar e salvar", "Ligue a saída (direita) de um nó à entrada (esquerda) de outro, até o Resultado. Salvar regra grava.", [these([panel._graph])]),
		step("Resultado e fixação", "O que a execução calculou. Fixar um valor trava o número de um cadastro a partir da data, com o motivo; a regra não o substitui.",
			[these([panel._results, panel._pin_value, panel._pin_reason])]),
	]
