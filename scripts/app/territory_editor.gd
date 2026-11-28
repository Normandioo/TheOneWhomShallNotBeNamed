extends RefCounted
## O editor territorial (especificação 17.5, TerritoryEditor): as camadas pintáveis (a hierarquia país > província > município e as áreas
## de religião, cultura, etnia, raça e idioma), o modo pintar (pincel, balde, borracha, conta-gotas, fronteira), a imagem composta do
## globo, a paleta e o destaque do selecionado, a máscara (província dentro do país), os avisos, unir, crescer, importar PNG e a gravação
## adiada. Não desenha nada: Main leva a imagem e a paleta à GPU e roteia o mouse. Fala com o resto por sinais e pelo DomainHub (o banco,
## a ficha aberta e como abri-la ou relê-la).

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const TerritoryBoundaryTool = preload("res://scripts/edit/territory_boundary_tool.gd")
const TerritoryEdit = preload("res://scripts/edit/TerritoryEdit.cs")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")

signal painting_changed(on: bool)      # entrou ou saiu do modo pintar
signal draft_ready(info: Dictionary)   # terminou de pintar o rascunho: abre o cartão "Nova região"
signal area_palette_changed(entries: Array)  # as cores das áreas mudaram ([{id, rgb}])
signal draft_closed                      # o rascunho acabou (criado ou descartado)
signal paint_started(kind: String)       # começou uma pintura: o mapa passa a mostrar esse tipo ("" = rascunho sem tipo)
signal palette_changed(entries: Array)  # as cores mudaram ([{id, rgb, top}]): quem desenha atualiza a paleta
signal territory_level_shown(level: String, layer)  # a camada mostrada no globo passou a ser outra
signal selection_changed(top_id: int)  # o país (ou o topo) a destacar no mapa; 0 = nenhum
signal resource_owner_picked(id: int)   # o conta-gotas trocou a área de recurso pintada
signal preview_image(image)             # Image = mostrar a prévia de uma geração; null = voltar ao mapa de verdade

const Territory = preload("res://scripts/world/Territory.cs")
const SNAP_BAND_KM := 60.0  # "assentar no relevo": a fronteira vai até ~6 pixels do mapa (9,8 km cada) atrás de uma crista ou rio
## As camadas pintáveis (Registry.Levels): a hierarquia política e as áreas de predominância (religião, cultura...).
const HIERARCHY := ["pais", "provincia", "municipio"]
const PAINTABLE := ["pais", "provincia", "municipio", "religiao", "cultura", "etnia", "raca", "idioma"]
const AREA_LEVELS := ["religiao", "cultura", "etnia", "raca", "idioma"]  # as áreas de predominância: aparecem sobre os países (cinzas)
const DRAFT := 65535            # o dono reservado do rascunho (nenhum cadastro tem esse id)
const DRAFT_COLOR := 0xc98a82
const DRAFT_NAME := {"pais": "Novo país", "provincia": "Nova subdivisão", "municipio": "Nova subdivisão", "cultura": "Nova cultura", "etnia": "Nova etnia",
	"raca": "Nova raça", "religiao": "Nova religião", "idioma": "Novo idioma"}
const RESOURCE := "recurso:"    # prefixo da camada de um recurso (Registry.ResourceLevelPrefix): os donos são ocorrências, não cadastros

var hub                    # o DomainHub: o banco, a ficha aberta, abrir e reler a ficha
var registry
var territory              # a camada do nível mostrado e editado (Territory, C#): o dono de cada pixel
var layer_factory := Callable()  # cria uma camada vazia (Territory pronto) para um nível ainda não carregado
var levels := {}           # nível -> a camada (carregada na primeira vez que é usada); cada nível é independente
var territory_level := "pais"
var commands               # a pilha de desfazer (a mesma do terreno)
var territory_panel        # a barra do modo pintar
var import_panel           # a janela de importar PNG
var boundary_tool := TerritoryBoundaryTool.new()
var painting_territory := false  # no modo pintar: o botão esquerdo do mouse pinta
var territory_stroking := false  # uma pincelada em andamento
var territory_owner := 0         # quem está sendo pintado
var draft = null                 # a camada do rascunho: o que se pinta sem cadastro, até o cartão "Nova região" dar tipo, nome e a quem pertence
var drafting := false            # há um rascunho (sendo pintado ou esperando o cartão)
var _draft_hint := ""            # o tipo que o cartão já traz marcado (pedido por "pintar no mapa" da ficha)
var _draft_parent := 0           # dentro de quê fica a divisão nova: pedido pela ficha ou decidido no primeiro traço (0 = ainda em aberto)
var _draft_auto := false         # _draft_parent veio do primeiro traço: apagado o desenho, o próximo decide de novo
var _draft_back := "pais"        # o nível que estava na tela antes do rascunho
var territory_mode := "pincel"   # pincel | balde | borracha | conta-gotas | fronteira
var territory_radius := 300.0
var territory_land_only := true
var territory_protect := true    # "Não invadir": a pintura não passa por cima do território dos outros do mesmo nível
var territory_reach := 800.0     # alcance de "crescer" (km de caminho)
var _last_dab := Vector3.ZERO
var _territory_seen := {}        # nível -> a versão vista pela última vez
var _territory_saved := {}       # nível -> a versão gravada no banco
var _territory_changed_ms := 0
var _palette_hash := 0
var _area_palette_hash := 0
var overlay_level := ""         # a área ("cultura", "etnia"...) sobreposta ao mapa que está na tela (a caixa das sobreposições); "" = nenhuma
var previewing := false      # a prévia de uma geração está na tela: o mapa de verdade não é reenviado por cima
var _preview_colors: Array = []
var _force_upload := false     # a próxima imagem política vai à GPU mesmo sem edição (trocou o que está composto)
var _selected_top := 0
var focus_division := 0      # a subdivisão aberta na lista do país: o destaque do mapa vai para ela
var _highlighted := 0        # o que o mapa destaca agora
var subdivisions_view := false  # mapa político por subdivisões: o país selecionado mostra cada província (e município) na sua cor; os outros ficam cinzas
var _live_colors := {}           # cadastro -> cor em prévia (o seletor está aberto; ainda não foi gravada)


## Liga ao hub (banco e ficha), à camada dos países, à pilha de desfazer e à barra de pintar. Lê do banco o que estava gravado.
## more: camadas já criadas de outros níveis ({"provincia": Territory}); factory cria as que faltarem, sob demanda.
func setup(domain_hub, t, stack, panel, more := {}, factory := Callable()) -> void:
	hub = domain_hub
	registry = hub.registry
	hub.territories = self
	territory = t
	layer_factory = factory
	commands = stack
	territory_panel = panel
	_adopt("pais", t)
	for level in more:
		_adopt(level, more[level])
	for level in HIERARCHY:
		layer(level)  # províncias e municípios aparecem no mapa desde o começo (com a cor do país)
	boundary_tool.name_of = owner_name
	boundary_tool.kind_of = owner_kind
	boundary_tool.setup(territory, hub.map, panel, commands)
	boundary_tool.record_edit = _record_edit
	panel.snap_rivers_changed.connect(func(on: bool) -> void: boundary_tool.snap_rivers = on)
	panel.mode_changed.connect(_set_territory_mode)
	panel.radius_changed.connect(func(km: float) -> void: territory_radius = km)
	panel.protect_changed.connect(set_territory_protect)
	panel.land_only_changed.connect(func(on: bool) -> void:
		territory_land_only = on
		boundary_tool.land_only = on)
	panel.finish_requested.connect(stop_painting)
	panel.reach_changed.connect(func(km: float) -> void: territory_reach = km)
	panel.grow_requested.connect(territory_grow)
	panel.snap_requested.connect(territory_snap)
	panel.merge_requested.connect(territory_merge)
	panel.import_requested.connect(func() -> void:
		if import_panel != null and painting_territory:
			import_panel.pick_file())
	stack.changed.connect(_on_commands_changed)
	if hub.usable:
		var sheet = hub.sheet
		sheet.territory_paint_requested.connect(func() -> void: start_painting(hub.current()))
		sheet.territory_boundary_requested.connect(func() -> void: start_painting(hub.current(), "fronteira"))
		sheet.territory_clear_requested.connect(_on_territory_clear)
		sheet.paint_kind_requested.connect(func(kind: String, parent: int) -> void:
			start_draft(kind)
			if drafting:
				draft_set_parent(parent))
		sheet.division_paint_requested.connect(start_painting)
		sheet.division_focused.connect(set_focus_division)
		sheet.entity_color_changed.connect(_on_color_changed)
	refresh_palette()


## Liga a janela de importar PNG.
func bind_import(panel) -> void:
	import_panel = panel
	panel.file_chosen.connect(_on_import_file)
	panel.apply_requested.connect(_on_import_apply)
	panel.focus_requested.connect(func(lat: float, lon: float) -> void:
		if hub.focus_map.is_valid():
			hub.focus_map.call(EvronGeo.dir(lat, lon), 1.6))


## O PNG escolhido: separa as regiões e abre o mapeamento com as entidades do nível pintado.
func _on_import_file(path: String) -> void:
	if drafting:
		return  # o rascunho ainda não é um cadastro
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		territory_panel.set_message("Não consegui ler a imagem.")
		return
	var regions = territory.AnalyzeImage(img, 4)
	if regions == null or regions.is_empty():
		territory_panel.set_message("Nenhuma região colorida (opaca) na imagem.")
		return
	var entities: Array = []
	for p in registry.Palette(territory_level):
		entities.append({"id": int(p.id), "name": registry.Name(int(p.id)), "rgb": int(_live_colors.get(int(p.id), p.rgb))})
	import_panel.show_regions(regions, entities, UiKit.kind_label(territory_level))


func _on_import_apply(indices: PackedInt32Array, owners: PackedInt32Array) -> void:
	if indices.is_empty() or not painting_territory:
		return
	territory_end()
	var edit = territory.ApplyImport(indices, owners)
	if edit == null:
		territory_panel.set_message("A importação não mudou nada.")
		return
	_record_edit("Importar PNG (%d pontos)" % edit.Count, edit)
	territory_panel.set_area(territory.AreaKm2(territory_owner))
	territory_panel.set_message("")
	_show_warnings()


# --- pintar território -----------------------------------------------------------------------------------------------

## Entra no modo pintar território para o país: o botão esquerdo do mouse no globo passa a pintar (Main roteia), com pincel, balde ou borracha.
func start_painting(id: int, mode := "pincel") -> void:
	if drafting and id != 0:
		discard_draft()  # pintar um cadastro abandona o rascunho
	if not hub.usable or territory == null or painting_territory or id == 0:
		return
	var kind: String = registry.Kind(id)
	if not kind in PAINTABLE or id > 65535 or layer(kind) == null:
		hub.sheet.show_territory_message("Este tipo de cadastro não tem área pintável (ou o id passa de 65535).")
		return
	show_level(kind)
	_apply_mask(id)
	_begin_painting(id, mode)


## Pinta a área de uma ocorrência de recurso, com as mesmas ferramentas dos países, na camada do recurso.
func start_resource(level: String, occurrence: int, mode := "pincel") -> void:
	if drafting:
		discard_draft()
	if not hub.usable or territory == null or painting_territory or occurrence <= 0 or occurrence >= DRAFT or layer(level) == null:
		return
	show_level(level)
	territory.SetMask(null, 0)
	_begin_painting(occurrence, mode)


static func is_resource(level: String) -> bool:
	return level.begins_with(RESOURCE)


## O tipo e o nome de um dono da camada na tela: um cadastro ou, na camada de um recurso, uma ocorrência dele.
func owner_kind(id: int) -> String:
	if not is_resource(territory_level):
		return registry.Kind(id)
	var type: int = registry.OccurrenceType(id)
	return RESOURCE + str(type) if type > 0 else ""


func owner_name(id: int) -> String:
	return registry.OccurrenceLabel(id) if is_resource(territory_level) else registry.Name(id)


## "Não invadir": pintando um cadastro que já existe, o pincel só pega terra livre (e o que já é dele).
func _protect_painting() -> void:
	if painting_territory and not drafting:
		territory.SetTaken(territory if territory_protect else null, territory_owner)


func set_territory_protect(on: bool) -> void:
	territory_protect = on
	if drafting:
		_limit_draft()
	else:
		_protect_painting()
	territory_panel.set_message("" if on else "Pintando por cima, o território dos outros passa para este.")


func _begin_painting(id: int, mode: String) -> void:
	territory_owner = id
	painting_territory = true
	territory_stroking = false
	territory_mode = mode
	territory_panel.set_mode(mode)
	territory_panel.set_territory_actions(not is_resource(territory_level))
	_protect_painting()
	territory_panel.show_state(owner_name(id), territory.AreaKm2(id))
	_refresh_merge_choices()
	_show_warnings()
	if territory_mode == "fronteira":
		hub.sheet.hide()
		boundary_tool.start(territory_owner)
	refresh_palette()  # pintando província ou município, cada um aparece na própria cor
	if not is_resource(territory_level):
		paint_started.emit(territory_level)
	painting_changed.emit(true)


## O tipo de coisa que o mapa está mostrando: o do rascunho enquanto há um, senão o nível na tela.
func shown_kind() -> String:
	return _draft_hint if drafting and _draft_hint != "" else territory_level


## Pintando (ou com um rascunho de) uma província ou um município, o mapa distingue as divisões desse nível; "" = não.
func _divisions_painted() -> String:
	var kind := _draft_hint if drafting else (territory_level if painting_territory else "")
	return kind if kind in ["provincia", "municipio"] else ""


## Os limites do rascunho: uma subdivisão não passa da fronteira de quem a contém; com "Não invadir", nenhum rascunho toma o que já é de
## outro do mesmo tipo. Sem tipo escolhido não há com quem comparar.
func _limit_draft() -> void:
	if draft == null:
		return
	draft.SetMask(null, 0)
	draft.SetTaken(null, 0)
	if not drafting or _draft_hint == "" or layer(_draft_hint) == null:
		return
	if _draft_hint in ["provincia", "municipio"] and _draft_parent != 0 and _draft_parent <= 65535:
		draft.SetMask(layer(String(registry.Kind(_draft_parent))), _draft_parent)
	if territory_protect:
		draft.SetTaken(layer(_draft_hint), 0)


## Diz dentro de quê a divisão do rascunho fica (a ficha ou o cartão): vale para os próximos traços.
func draft_set_parent(parent: int) -> void:
	if not drafting or not _draft_hint in ["provincia", "municipio"]:
		return
	_draft_parent = parent
	_draft_auto = false
	_limit_draft()
	_palette_hash = 0
	_force_upload = true
	refresh_palette()
	if parent != 0:
		territory_panel.set_message("Dentro de %s: não passa da fronteira nem por cima de outra subdivisão." % registry.Name(parent))


## Uma subdivisão sem lugar definido fica onde o primeiro traço começa: no país dali ou, começando sobre uma do 1º nível, dentro dela.
## n: o ponto do traço. Chamado antes de cada ferramenta que pinta.
func draft_anchor(n: Vector3) -> void:
	if not drafting or not _draft_hint in ["provincia", "municipio"] or territory_mode in ["borracha", "conta-gotas"] or n == Vector3.ZERO:
		return
	if (_draft_parent == 0 or _draft_auto) and draft.Pixels(DRAFT) == 0:
		var province: int = layer("provincia").OwnerAt(n)
		_draft_parent = province if province != 0 else int(layer("pais").OwnerAt(n))
		_draft_auto = true
		var level := "municipio" if _draft_parent != 0 and String(registry.Kind(_draft_parent)) == "provincia" else "provincia"
		if level != _draft_hint:
			set_draft_kind(level)
		_limit_draft()
		_palette_hash = 0
		refresh_palette()
	var taken: int = layer(_draft_hint).OwnerAt(n)
	if taken != 0:
		territory_panel.set_message("Aí já é de %s: a divisão nova não passa por cima. Para criar dentro dela, use ＋ Pintar dentro na linha dela." % registry.Name(taken))
	elif _draft_parent != 0 and int(layer(String(registry.Kind(_draft_parent))).OwnerAt(n)) != _draft_parent:
		territory_panel.set_message("Aí fica fora de %s." % registry.Name(_draft_parent))
	elif _draft_parent != 0:
		territory_panel.set_message("Dentro de %s: não passa da fronteira nem por cima de outra subdivisão." % registry.Name(_draft_parent))
	else:
		territory_panel.set_message("Fora de qualquer país: sem fronteira, mas não passa por cima de outra subdivisão.")


## O tipo do rascunho foi trocado no cartão: o mapa acompanha.
func set_draft_kind(kind: String) -> void:
	if not drafting or not kind in PAINTABLE:
		return
	_draft_hint = kind
	layer(kind)
	_limit_draft()
	_palette_hash = 0
	_force_upload = true
	refresh_palette()
	paint_started.emit(kind)


## Província e município só pintam dentro do cadastro de cima a que estão ligados (vínculo "Província de", "Município de").
func _apply_mask(id: int) -> void:
	territory.SetMask(null, 0)
	var i := HIERARCHY.find(territory_level)
	if i < 1:
		return
	var parent: int = registry.TerritoryParent(id)
	if parent != 0 and parent <= 65535:
		territory.SetMask(layer(String(registry.Kind(parent))), parent)  # o cadastro de cima pode ser o país mesmo para um município
	else:
		territory_panel.set_message("%s não está dentro de um país nem de outra subdivisão: pinta sem limite." % registry.Name(id))


func _refresh_merge_choices() -> void:
	if drafting or is_resource(territory_level):
		return  # o rascunho não tem nível, e a barra de um recurso não tem as ações de país
	var others: Array = []
	for p in registry.Palette(territory_level):
		if int(p.id) != territory_owner and territory.AreaKm2(int(p.id)) > 0.0:
			others.append({"id": int(p.id), "name": registry.Name(int(p.id))})
	territory_panel.show_merge_choices(others)


## Unir: o território inteiro de outro cadastro do mesmo nível passa para o que está sendo pintado.
func territory_merge(from_id: int) -> void:
	if drafting:
		return  # o rascunho ainda não é um cadastro
	if not painting_territory or registry.Kind(from_id) != territory_level:
		return
	territory_end()
	var edit = territory.ReplaceOwner(from_id, territory_owner)
	if edit == null:
		territory_panel.set_message("%s não tem território para unir." % registry.Name(from_id))
		return
	_record_edit("Unir %s a %s (%d pontos)" % [registry.Name(from_id), registry.Name(territory_owner), edit.Count], edit)
	territory_panel.set_area(territory.AreaKm2(territory_owner))
	territory_panel.set_message("")
	_refresh_merge_choices()
	_show_warnings()


## Conta-gotas: o território clicado (do mesmo nível) passa a ser o pintado; a ferramenta volta ao pincel.
func _pick_owner(n: Vector3) -> void:
	var owner: int = territory.OwnerAt(n)
	if owner == 0 or owner_kind(owner) != territory_level:
		territory_panel.set_message("Sem território deste nível aí.")
		return
	territory_owner = owner
	_protect_painting()
	territory_panel.show_state(owner_name(owner), territory.AreaKm2(owner))
	_refresh_merge_choices()
	_set_territory_mode("pincel")
	territory_panel.set_mode("pincel")
	if is_resource(territory_level):
		resource_owner_picked.emit(owner)
	elif owner != hub.current():
		hub.open(owner)


## A prévia de uma geração: a imagem com donos de mentira e as cores deles. end_preview volta ao mapa de verdade.
func show_preview(image: Image, colors: Array) -> void:
	previewing = true
	_preview_colors = colors
	refresh_palette()
	preview_image.emit(image)


func end_preview() -> void:
	if not previewing:
		return
	previewing = false
	_preview_colors = []
	_force_upload = true
	refresh_palette()
	preview_image.emit(null)


## Mostra e edita a camada de um nível. As outras ficam como estão (e continuam gravadas).
func show_level(level: String) -> void:
	if layer(level) == null or level == territory_level:
		return
	if painting_territory:
		stop_painting()  # o dono pintado é da camada que sai: noutra, o número seria de outra coisa
	territory_end()
	territory_level = level
	territory = levels[level]
	boundary_tool.use_territory(territory)
	boundary_tool.below = shown_below()
	_palette_hash = 0
	_force_upload = true
	refresh_palette()
	territory_level_shown.emit(level, territory)


## A camada de um nível, carregada do banco na primeira vez; null se o nível não é pintável ou não há como criá-la.
func layer(level: String):
	if levels.has(level):
		return levels[level]
	if not (level in PAINTABLE or is_resource(level)) or not layer_factory.is_valid():
		return null
	# shortcut: cada camada de recurso aberta fica na memória (~32 MiB) até fechar; descartar as já gravadas se pesar.
	var made = layer_factory.call()
	made.IsResource = is_resource(level)
	_adopt(level, made)
	return levels[level]


func _adopt(level: String, t) -> void:
	levels[level] = t
	if hub.usable:
		registry.LoadTerritoryLevel(level, t)
		if not is_resource(level):
			registry.UseTerritory(level, t)  # o nó "área" das regras lê a área pintada
	_territory_seen[level] = t.Version
	_territory_saved[level] = t.Version


## As camadas que a tela mostra por baixo da do nível: os níveis de cima da hierarquia, o mais próximo primeiro
## (províncias mostram os países onde não há província). As áreas de religião, cultura etc. aparecem sozinhas.
func shown_below() -> Array:
	var i := HIERARCHY.find(territory_level)
	var out: Array = []
	for k in range(i - 1, -1, -1):
		var l = layer(HIERARCHY[k])
		if l != null:
			out.append(l)
	return out


## As camadas que formam a imagem do globo, a de cima primeiro: na hierarquia política, todas (municípios sobre províncias sobre
## países; a cor é sempre a do país, estilo Europa Universalis); nas áreas de religião etc., só a do nível.
func _composed() -> Array:
	if drafting and territory_level == "rascunho":  # o rascunho por cima do mapa do tipo que se pinta
		var with_draft: Array = [draft]
		if _draft_hint in AREA_LEVELS:
			with_draft.append(layer(_draft_hint))
			return with_draft
		var deepest := HIERARCHY.find(_draft_hint) if _draft_hint in HIERARCHY else HIERARCHY.size() - 1
		for k in range(deepest, -1, -1):
			if levels.has(HIERARCHY[k]):
				with_draft.append(levels[HIERARCHY[k]])
		return with_draft
	if not territory_level in HIERARCHY:
		return [territory]
	var out: Array = []
	for k in range(HIERARCHY.size() - 1, -1, -1):
		if levels.has(HIERARCHY[k]):
			out.append(levels[HIERARCHY[k]])
	return out


## Está na tela uma área (cultura, etnia, raça, religião ou idioma) sobre o mapa dos países?
func area_active() -> bool:
	return overlay_level != "" and not drafting  # no rascunho o mapa é o do tipo que se pinta: a sobreposição volta depois


## O mapa de baixo são os países? Então eles ficam cinzas sob a área sobreposta.
func area_gray() -> bool:
	return area_active() and territory_level in HIERARCHY


## A camada da sobreposição, ou null.
func area_layer():
	return layer(overlay_level) if overlay_level != "" else null


## Sobrepõe uma área ao mapa que está na tela ("" tira). Não muda o que está sendo mostrado nem editado.
func set_overlay(level: String) -> void:
	overlay_level = level if level in AREA_LEVELS else ""
	_area_palette_hash = 0
	refresh_palette()


## Os donos da área sobreposta (RG8), para a GPU.
func area_image() -> Image:
	return area_layer().Composite([])


## A imagem dos donos que vai para o globo.
func political_image() -> Image:
	var comp := _composed()
	return comp[0].Composite(comp.slice(1))


## Muda quando as linhas à vista podem ter mudado: outras camadas na tela ou uma edição terminada (durante a pincelada, não).
func walls_key() -> Array:
	return _composed().map(func(l): return [l.get_instance_id(), l.Version])


## As linhas do pincel de fronteira das camadas na tela, com a prévia do traço que espera confirmação.
func walls() -> Dictionary:
	return Territory.Walls(_composed(), boundary_tool.pending_plan())


## Alguma das camadas mostradas mudou desde a última imagem? (zera as marcas)
func political_dirty() -> bool:
	var dirty := _force_upload
	_force_upload = false
	for l in _composed():
		dirty = dirty or l.Dirty
		l.Dirty = false
	return dirty


## Os avisos de inconsistência com o nível de cima, na barra de pintar (só ao pintar província ou município: varre a camada inteira).
func _show_warnings() -> void:
	var order := ["pais", "provincia", "municipio"]
	var i := order.find(territory_level)
	if not painting_territory or i < 1 or layer(order[i - 1]) == null:
		return
	var upper: String = order[i - 1]
	var lines: Array = []
	for w in registry.LevelWarnings(territory_level, levels[upper], territory):
		var km := LayerPanel._thousands(roundi(w.area_km2))
		match String(w.kind):
			"fora": lines.append("⚠ %s: %s km² fora de %s" % [registry.Name(int(w.id)), km, registry.Name(int(w.country))])
			"sem_pais": lines.append("⚠ %s não está dentro de nada: diga na ficha dela onde fica" % registry.Name(int(w.id)))
			"lacuna": lines.append("⚠ %s: %s km² sem subdivisão dentro" % [registry.Name(int(w.id)), km])
	territory_panel.set_message("\n".join(lines.slice(0, 6)) + ("\n…" if lines.size() > 6 else ""))


# --- rascunho: pintar primeiro, dar o nome depois -----------------------------------------------------------------------

## Pintar sem cadastro aberto: a área vira um rascunho (dono reservado, só na tela) até o cartão "Nova região" dar tipo, nome e a quem pertence.
func start_draft(kind_hint := "") -> void:
	if kind_hint != "" or not drafting:
		_draft_hint = kind_hint  # "Pintar mais" (já em rascunho) mantém o tipo pedido
		_draft_parent = 0
		_draft_auto = false
	if _draft_hint != "" and hub.usable and territory != null:
		layer(_draft_hint)  # a camada do tipo precisa estar carregada para aparecer sob o rascunho
	if not hub.usable or territory == null or painting_territory or not layer_factory.is_valid():
		return
	if draft == null:
		draft = layer_factory.call()
	if not drafting:
		draft.ClearOwner(DRAFT)
		_draft_back = territory_level
		territory_end()
		territory_level = "rascunho"
		territory = draft
		territory.SetMask(null, 0)
		boundary_tool.use_territory(territory)
		boundary_tool.below = []
		drafting = true
		_palette_hash = 0
		refresh_palette()
	territory_owner = DRAFT
	painting_territory = true
	territory_stroking = false
	_limit_draft()
	territory_mode = "pincel"
	territory_panel.set_mode("pincel")
	territory_panel.show_state(DRAFT_NAME.get(_draft_hint, "Região nova"), draft.AreaKm2(DRAFT))
	_palette_hash = 0
	_force_upload = true
	refresh_palette()
	paint_started.emit(_draft_hint)
	painting_changed.emit(true)


## Terminou de pintar: sem nada pintado o rascunho se encerra; com área, abre o cartão com o tipo e o "pertence a" sugeridos pelo lugar.
func _finish_draft() -> void:
	if territory_stroking:
		territory_end()
	painting_territory = false
	territory_panel.hide_panel()
	painting_changed.emit(false)
	if draft.AreaKm2(DRAFT) <= 0.0:
		discard_draft()
		return
	draft_ready.emit(_draft_info())


## O que o cartão sugere: o país que cobre mais da metade da área; um tipo pelo tamanho (bem menor que o país parece subdivisão); e, numa
## subdivisão, a subdivisão direta em que ela está quase toda e é bem menor (aí fica no 2º nível, dentro dela). Pedida pela ficha, vale a ficha.
func _draft_info() -> Dictionary:
	var area: float = draft.AreaKm2(DRAFT)
	var info := {"area_km2": area, "kind": "pais", "country": {}, "province": {}}
	var countries = layer("pais")
	var best := _best_overlap(draft.OverlapKm2(countries, DRAFT), area)
	if not best.is_empty():
		info.country = {"id": best.id, "name": registry.Name(int(best.id)), "share": best.share}
		var fraction: float = area / maxf(float(countries.AreaKm2(int(best.id))), 1.0)
		info.kind = "provincia" if fraction < 0.6 else "pais"
	if _draft_hint != "":  # o tipo escolhido antes de pintar vale mais que o palpite pelo tamanho
		info.kind = _draft_hint
	if not info.kind in ["provincia", "municipio"]:
		return info
	var provinces = layer("provincia")
	var asked := String(registry.Kind(_draft_parent)) if _draft_parent != 0 else ""
	var inside := _best_overlap(draft.OverlapKm2(provinces, DRAFT), area)
	if asked == "pais":
		info.country = {"id": _draft_parent, "name": registry.Name(_draft_parent)}
		inside = {}
	elif asked == "provincia":
		inside = {"id": _draft_parent, "share": 1.0}
	elif not inside.is_empty() and (inside.share < 0.8 or area >= 0.6 * float(provinces.AreaKm2(int(inside.id)))):
		inside = {}
	if not inside.is_empty():
		info.province = {"id": int(inside.id), "name": registry.Name(int(inside.id)), "share": inside.share, "label": registry.DivisionName(int(inside.id))}
	info.kind = "municipio" if not inside.is_empty() else "provincia"
	return info


## Entre os donos de `over` (dono -> km²), o que cobre mais da metade da área; {} se nenhum.
func _best_overlap(over: Dictionary, area: float) -> Dictionary:
	var best_id := 0
	var best_km := 0.0
	for o in over:
		if int(o) != 0 and float(over[o]) > best_km:
			best_id = int(o)
			best_km = float(over[o])
	if best_id == 0 or best_km < 0.5 * area:
		return {}
	return {"id": best_id, "share": best_km / area}


## O cartão pediu "Criar": cria o cadastro, liga ao de cima, passa a área do rascunho para a camada do tipo e abre a ficha.
## division_name: como a subdivisão se chama ("" = o que o país já usa).
func draft_create(kind: String, region_name: String, parent: int, division_name := "") -> void:
	if not drafting or not kind in PAINTABLE:
		return
	var made = registry.Create(kind, region_name if region_name != "" else "Sem nome (%s)" % UiKit.short_label(kind).to_lower())
	if made == null:
		return
	var id := int(made)
	var target = layer(kind)
	if target == null or id >= DRAFT:
		territory_panel.set_message("Não foi possível pintar este cadastro (o id passa de 65534).")
		return
	var upper: bool = parent > 0 and kind in ["provincia", "municipio"]
	if upper:
		registry.Link(id, parent, kind + "_de")
		target.SetMask(layer(String(registry.Kind(parent))), parent)  # só dentro do de cima
	else:
		target.SetMask(null, 0)
	if division_name != "" and kind in ["provincia", "municipio"]:
		registry.NameNewDivision(id, division_name)
	if territory_protect:
		target.SetTaken(target, 0)  # o novo não toma o que já é de outro
	var edit = target.TakeFrom(draft, DRAFT, id)
	target.SetMask(null, 0)
	target.SetTaken(null, 0)
	if edit != null:
		target.AdoptBoundaries(draft, DRAFT, id)  # o traço continua exato no cadastro novo
	if edit != null:
		_record_edit("Criar %s (%d pontos)" % [UiKit.short_label(kind).to_lower(), edit.Count], edit, kind)
	_close_draft(kind)
	hub.choose(id)  # uma subdivisão aparece aberta na lista do país


## Descarta o rascunho (e volta ao nível que estava na tela).
func discard_draft() -> void:
	if not drafting:
		return
	painting_territory = false
	territory_panel.hide_panel()
	_close_draft(_draft_back)
	painting_changed.emit(false)


func _close_draft(show: String) -> void:
	draft.SetMask(null, 0)
	draft.SetTaken(null, 0)
	_draft_parent = 0
	_draft_auto = false
	draft.ClearOwner(DRAFT)
	draft.ForgetOwnerBoundaries(DRAFT)  # o próximo rascunho começa sem as linhas deste
	drafting = false
	painting_territory = false
	territory_level = ""  # força show_level a trocar de camada
	show_level(show if layer(show) != null else "pais")
	_palette_hash = 0
	refresh_palette()
	draft_closed.emit()


func stop_painting() -> void:
	if not painting_territory:
		return
	if drafting:
		_finish_draft()
		return
	if territory_stroking:
		territory_end()
	boundary_tool.finish_pending()  # Terminar confirma o traço (a prévia na tela ou o que ainda está sendo calculado)
	boundary_tool.stop()
	territory.SetMask(null, 0)
	territory.SetTaken(null, 0)
	painting_territory = false
	territory_panel.hide_panel()
	refresh_palette()  # as divisões voltam à cor do país
	painting_changed.emit(false)
	hub.refresh_sheet()  # a área da ficha


func _set_territory_mode(mode: String) -> void:
	if mode == territory_mode:
		return
	territory_end()
	territory_mode = mode
	if mode == "fronteira":
		hub.sheet.hide()
		boundary_tool.start(territory_owner)
	else:
		boundary_tool.finish_pending()  # trocar de ferramenta também confirma o traço
		boundary_tool.stop()
	painting_changed.emit(true)


## O botão esquerdo apertou no globo em n. Pincel e borracha começam uma pincelada; o balde preenche na hora.
func territory_begin(n: Vector3) -> void:
	if not painting_territory or territory_mode == "fronteira" or n == Vector3.ZERO:
		return
	if territory_mode == "conta-gotas":
		_pick_owner(n)
		return
	draft_anchor(n)
	_warn_taken(n)
	if territory_mode == "balde":
		var edit = territory.Fill(n, territory_owner, territory_land_only)
		if edit != null:
			_record_edit("Balde (%d pontos)" % edit.Count, edit)
			territory_panel.set_area(territory.AreaKm2(territory_owner))
		return
	territory.Begin()
	territory_stroking = true
	_dab(n)


## Um traço que começa no território de outro não pinta ali: a barra diz por quê (numa subdivisão nova, quem avisa é draft_anchor).
func _warn_taken(n: Vector3) -> void:
	if not territory_protect or territory_mode == "borracha" or (drafting and (_draft_hint == "" or _draft_hint in ["provincia", "municipio"])):
		return
	var map = layer(_draft_hint) if drafting else territory
	var other: int = map.OwnerAt(n)
	if other != 0 and other != (0 if drafting else territory_owner):
		territory_panel.set_message("Aí é de %s: com “Não invadir” ligado, a pintura não passa por cima. Desligue na barra para tomar." % owner_name(other))


## O mouse andou com o botão apertado: nova marca a cada 1/4 do raio percorrido.
func territory_drag(n: Vector3) -> void:
	if territory_stroking and n != Vector3.ZERO and EvronGeo.distance_km(n, _last_dab) >= territory_radius * 0.25:
		_dab(n)


## O botão soltou: a pincelada vira UM comando na pilha de desfazer.
func territory_end() -> void:
	if not territory_stroking:
		return
	territory_stroking = false
	var edit = territory.End()
	if edit != null:
		_record_edit("%s território (%d pontos)" % ["Apagar" if territory_mode == "borracha" else "Pintar", edit.Count], edit)
		territory_panel.set_area(territory.AreaKm2(territory_owner))


func _dab(n: Vector3) -> void:
	_last_dab = n
	if territory_mode == "borracha":
		territory.Dab(n, territory_radius, 0, false, territory_owner)  # a borracha de um país só apaga o dele
	else:
		territory.Dab(n, territory_radius, territory_owner, territory_land_only, -1)


## Fronteiras naturais: os países crescem pela terra sem dono a partir do território e da capital (a presença "capital" vigente na data
## mostrada). all = todos crescem; senão só o país pintado ganha terra, parando onde os vizinhos chegariam antes.
func territory_grow(all: bool) -> void:
	if drafting:
		return  # o rascunho ainda não é um cadastro
	if not painting_territory:
		return
	var owners := PackedInt32Array()
	var lats := PackedFloat64Array()
	var lons := PackedFloat64Array()
	for it in registry.MapItems(PackedStringArray(["politica"]), 0, hub.shown_t):
		if it.role == "capital" and it.kind == "pais" and int(it.entity_id) <= 65535:
			owners.append(int(it.entity_id))
			lats.append(it.lat)
			lons.append(it.lon)
	var edit = territory.Grow(owners, lats, lons, 0 if all else territory_owner, territory_reach)
	_natural_done(edit, "Crescer todos os países" if all else "Crescer território",
		"Nada para crescer: o país precisa de território pintado ou de uma capital, e de terra sem dono ao alcance.")


## Assenta as fronteiras do país pintado com os vizinhos na crista ou no rio grande mais perto.
func territory_snap() -> void:
	if drafting:
		return  # o rascunho ainda não é um cadastro
	if painting_territory:
		_natural_done(territory.Snap(territory_owner, SNAP_BAND_KM), "Assentar fronteiras",
			"Nada mudou: o país não faz fronteira com outro, ou ela já está no relevo.")


func _natural_done(edit, name: String, nothing: String) -> void:
	if edit == null:
		territory_panel.set_message(nothing)
		return
	_record_edit("%s (%d pontos)" % [name, edit.Count], edit)
	territory_panel.set_area(territory.AreaKm2(territory_owner))
	territory_panel.set_message("")


func _on_territory_clear() -> void:
	var id: int = hub.current()
	var cleared = layer(registry.Kind(id)) if id != 0 else null
	if cleared == null:
		return
	var edit = cleared.ClearOwner(id)
	if edit != null:
		_record_edit("Apagar território (%d pontos)" % edit.Count, edit, registry.Kind(id))
	hub.refresh_sheet()


func _record_edit(title: String, edit, level := "") -> void:
	var i := HIERARCHY.find(territory_level if level.is_empty() else level)
	if i >= 0:
		var parent_edit = edit
		for k in range(i + 1, HIERARCHY.size()):
			var child = levels.get(HIERARCHY[k])
			if child == null:
				break
			parent_edit = parent_edit.TrimSubdivisions(child, registry)
			if parent_edit == null:
				break
		var direct = levels.get("municipio") if HIERARCHY[i] == "pais" else null  # os municípios ligados direto ao país
		if direct != null:
			edit.TrimDirectSubdivisions(direct, registry)
	commands.push(title, edit)


func _on_commands_changed() -> void:
	if painting_territory and not territory_stroking:
		territory_panel.set_area(territory.AreaKm2(territory_owner))  # desfazer e refazer mudam a área
		_refresh_merge_choices()
		_show_warnings()


## A cor de um país: a prévia (seletor aberto) só vai para a paleta; ao fechar o seletor ela é gravada.
func _on_color_changed(id: int, rgb: int, final: bool) -> void:
	if not hub.usable:
		return
	if final:
		registry.SetEntityColor(id, rgb)
		_live_colors.erase(id)
	else:
		_live_colors[id] = rgb
	refresh_palette()


## Manda a paleta do nível mostrado (id e cor) a quem desenha, se mudou.
func refresh_palette() -> void:
	if not hub.usable:
		return
	var entries: Array = []
	var shown_levels: Array = HIERARCHY if (territory_level in HIERARCHY or territory_level == "rascunho") else [territory_level]
	if drafting and _draft_hint in AREA_LEVELS:
		shown_levels = [_draft_hint]
	if area_active():  # a área sobreposta vai por uma paleta própria
		var area_entries: Array = []
		for p in registry.Palette(overlay_level):
			area_entries.append({"id": int(p.id), "rgb": int(_live_colors.get(int(p.id), p.rgb))})
		var area_key: int = area_entries.hash()
		if area_key != _area_palette_hash:
			_area_palette_hash = area_key
			area_palette_changed.emit(area_entries)
	var colors := {}
	var kinds := {}  # o nível de cada dono: sem perguntar um a um ao banco
	for level in shown_levels:
		for p in registry.Palette(level):
			colors[int(p.id)] = int(p.rgb) if is_resource(level) else int(_live_colors.get(int(p.id), p.rgb))
			kinds[int(p.id)] = level
	var parents: Dictionary = registry.TerritoryParents()
	var home := _top(_draft_parent, parents) if drafting and _draft_parent != 0 else 0
	var highlighted := focus_division if focus_division != 0 and focus_division == _highlighted else 0
	var divisions := _divisions_painted()
	var focus := _selected_top if subdivisions_view and territory_level in HIERARCHY else 0
	for id in colors:
		var top := _top(id, parents)
		var rgb: int = colors.get(top, colors[id])
		if divisions != "" and home != 0:  # rascunho com lugar: só o país dele (e as irmãs) em cores; os vizinhos em cinza
			rgb = colors[id] if id == _draft_parent or (top == home and kinds[id] == divisions) else _gray_of(colors[id])
		elif divisions != "":  # as divisões do nível pintado na própria cor; o resto, cinza
			rgb = colors[id] if kinds[id] == divisions else _gray_of(colors[id])
		elif focus != 0:
			rgb = _subdivision_color(id, colors, kinds, parents) if top == focus else _gray_of(rgb)
		if highlighted != 0 and (id == highlighted or int(parents.get(id, 0)) == highlighted):
			top = highlighted  # o destaque do mapa pega só a divisão aberta (e as de dentro), na cor dela
			rgb = colors.get(highlighted, rgb)
		entries.append({"id": id, "rgb": rgb, "top": top})
	if drafting:
		entries.append({"id": DRAFT, "rgb": DRAFT_COLOR, "top": DRAFT})
	entries.append_array(_preview_colors)
	var key: int = entries.hash()
	if key != _palette_hash:
		_palette_hash = key
		palette_changed.emit(entries)


## A cor de uma subdivisão no modo por subdivisões: a própria; o município de uma província leva a cor dela.
func _subdivision_color(id: int, colors: Dictionary, kinds: Dictionary, parents: Dictionary) -> int:
	var parent: int = parents.get(id, 0)
	if kinds[id] == "municipio" and kinds.get(parent, "") == "provincia":
		return colors.get(parent, colors[id])
	return colors[id]


func _gray_of(rgb: int) -> int:
	var lum := (((rgb >> 16) & 255) * 0.299 + ((rgb >> 8) & 255) * 0.587 + (rgb & 255) * 0.114) / 255.0
	var g := roundi((0.34 + 0.30 * lum) * 255.0)
	return (g << 16) | (g << 8) | g


func set_subdivisions_view(on: bool) -> void:
	subdivisions_view = on
	refresh_palette()


## O topo da hierarquia de um cadastro: o país de uma província ou município (subindo pelos vínculos); o próprio id para os outros.
## parents: o de cima de todos (TerritoryParents), quando se pergunta de muitos; sem ele, vai ao banco.
func _top(id: int, parents: Variant = null) -> int:
	if is_resource(territory_level):
		return id  # uma ocorrência não tem cadastro de cima (e o número dela pode ser o de um cadastro)
	var top := id
	for _i in 3:
		var parent: int = registry.TerritoryParent(top) if parents == null else int(parents.get(top, 0))
		if parent == 0:
			break
		top = parent
	return top


func refresh_selection() -> void:
	var top := 0
	var id: int = hub.current()
	if not is_resource(territory_level) and id != 0 and id <= 65535 and registry.Kind(id) in PAINTABLE:
		top = _top(id)
	var changed := top != _selected_top
	_selected_top = top  # o país (ou o topo) do cadastro aberto
	var shown := top
	if focus_division != 0 and top != 0 and not is_resource(territory_level) and _top(focus_division) == top and _has_area(focus_division):
		shown = focus_division  # sem área pintada não há o que destacar: o destaque fica no país
	var moved := shown != _highlighted
	if moved:
		_highlighted = shown
		selection_changed.emit(shown)
	if (changed and subdivisions_view) or (moved and (focus_division != 0 or shown == top)):
		refresh_palette()


func _has_area(id: int) -> bool:
	var map = layer(String(registry.Kind(id)))
	return map != null and map.AreaKm2(id) > 0.0


## A lista do país abriu (ou fechou) uma subdivisão.
func set_focus_division(id: int) -> void:
	if id == focus_division:
		return
	focus_division = id
	refresh_selection()
	refresh_palette()


## Na vista de subdivisões, o clique dentro do país selecionado escolhe a subdivisão mais funda ali. 0 = não há.
func division_at(dir: Vector3, owner: int) -> int:
	if not subdivisions_view or _selected_top == 0 or is_resource(territory_level) or _top(owner) != _selected_top:
		return 0
	for level in ["municipio", "provincia"]:
		var map = layer(level)
		var found: int = map.OwnerAt(dir) if map != null else 0
		if found != 0 and _top(found) == _selected_top:
			return found
	return 0


## A camada política é gravada no banco ~1,5 s depois da última edição (e ao fechar), nunca no meio de uma pincelada.
func save_if_due() -> void:
	if not hub.usable:
		return
	var dirty := false
	for level in levels:
		if levels[level].Version != _territory_seen[level]:
			_territory_seen[level] = levels[level].Version
			_territory_changed_ms = Time.get_ticks_msec()
		dirty = dirty or levels[level].Version != _territory_saved[level]
	if dirty and not territory_stroking and Time.get_ticks_msec() - _territory_changed_ms >= 1500:
		save()


func save() -> bool:
	if not hub.usable:
		return false
	var pending := {}
	for level in levels:
		if levels[level].Version != _territory_saved[level]:
			pending[level] = levels[level]
	if pending.is_empty():
		return true
	if not registry.SaveTerritoryLevels(pending):
		_territory_changed_ms = Time.get_ticks_msec()
		return false
	for level in pending:
		_territory_saved[level] = pending[level].Version
	return true


# --- o que o DomainHub pede ------------------------------------------------------------------------------------------

## O dono a abrir no clique do globo: o da camada do nível ou, onde ela não tem dono, o das de cima (o país sob a província) e, por fim, o das
## de baixo que o mapa também desenha (província ou município sem país). 0 = nenhum.
func owner_at(dir: Vector3) -> int:
	if territory == null or is_resource(territory_level):
		return 0
	for shown in [territory] + shown_below():
		var owner: int = shown.OwnerAt(dir)
		if owner != 0:
			return owner
	# Por último, as camadas de baixo da hierarquia que o mapa também desenha (a província cujo país foi apagado, por exemplo): o que se vê se clica.
	var i := HIERARCHY.find(territory_level)
	if i >= 0:
		for k in range(i + 1, HIERARCHY.size()):
			var deeper = levels.get(HIERARCHY[k])
			if deeper != null and deeper.OwnerAt(dir) != 0:
				return deeper.OwnerAt(dir)
	return 0


## O que a seção de território da ficha mostra, ou {} se o tipo não tem área pintável.
func sheet_info(s: Dictionary) -> Dictionary:
	if not s.kind in PAINTABLE or layer(s.kind) == null:
		return {}
	return {"area_km2": layer(s.kind).AreaKm2(int(s.id)), "color": int(_live_colors.get(int(s.id), registry.EntityColor(int(s.id)))), "ok": int(s.id) <= 65535}


## Antes de apagar um cadastro: termina a pincelada e sai do modo pintar se é ele. Devolve a camada dele (ou null).
func before_delete(id: int):
	var deleted_layer = layer(registry.Kind(id)) if id <= 65535 else null
	if deleted_layer != null:
		territory_end()
		if painting_territory and territory_owner == id:
			stop_painting()
	return deleted_layer


## Depois de apagar: tira o território e as fronteiras dele. Devolve a edição da pintura (vai no mesmo desfazer da exclusão) ou null.
## Os comandos antigos que pintam esse cadastro ficam na pilha: a pilha só os alcança depois de desfazer a exclusão, quando ele volta.
## shortcut: as linhas do pincel de fronteira do cadastro não voltam com o desfazer; se fizer falta, guardá-las na edição.
func after_delete(id: int, deleted_layer):
	if deleted_layer == null:
		return null
	var edit = deleted_layer.ClearOwner(id)
	deleted_layer.ForgetOwnerBoundaries(id)
	return edit


## A ficha foi relida: a cor, a área e o destaque acompanham. No pincel de fronteira, a ficha não cobre o globo.
func on_sheet_reloaded() -> void:
	if painting_territory and territory_mode == "fronteira":
		hub.sheet.hide()
	refresh_palette()
	refresh_selection()


## Outro cadastro vai ser aberto: o pincel de fronteira de outro dono sai do modo pintar.
func on_open(id: int) -> void:
	if painting_territory and territory_mode == "fronteira" and id != territory_owner:
		stop_painting()


## Grava agora o que ainda espera a gravação adiada (ao fechar e antes de exportar o mundo).
func flush() -> bool:
	territory_end()
	return save()
