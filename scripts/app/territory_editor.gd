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
signal palette_changed(entries: Array)  # as cores mudaram ([{id, rgb, top}]): quem desenha atualiza a paleta
signal territory_level_shown(level: String, layer)  # a camada mostrada no globo passou a ser outra
signal selection_changed(top_id: int)  # o país (ou o topo) a destacar no mapa; 0 = nenhum

const SNAP_BAND_KM := 60.0  # "assentar no relevo": a fronteira vai até ~6 pixels do mapa (9,8 km cada) atrás de uma crista ou rio
## As camadas pintáveis (Registry.Levels): a hierarquia política e as áreas de predominância (religião, cultura...).
const HIERARCHY := ["pais", "provincia", "municipio"]
const PAINTABLE := ["pais", "provincia", "municipio", "religiao", "cultura", "etnia", "raca", "idioma"]

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
var territory_mode := "pincel"   # pincel | balde | borracha | conta-gotas | fronteira
var territory_radius := 300.0
var territory_land_only := true
var territory_reach := 800.0     # alcance de "crescer" (km de caminho)
var _last_dab := Vector3.ZERO
var _territory_seen := {}        # nível -> a versão vista pela última vez
var _territory_saved := {}       # nível -> a versão gravada no banco
var _territory_changed_ms := 0
var _palette_hash := 0
var _selected_top := 0
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
	boundary_tool.setup(territory, registry, hub.map, panel, commands)
	boundary_tool.record_edit = _record_edit
	panel.mode_changed.connect(_set_territory_mode)
	panel.radius_changed.connect(func(km: float) -> void: territory_radius = km)
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
		sheet.subdivision_requested.connect(_on_subdivide)
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
	if not hub.usable or territory == null or hub.is_drawing() or painting_territory or id == 0:
		return
	var kind: String = registry.Kind(id)
	if not kind in PAINTABLE or id > 65535 or layer(kind) == null:
		hub.sheet.show_territory_message("Este tipo de cadastro não tem área pintável (ou o id passa de 65535).")
		return
	show_level(kind)
	territory_owner = id
	_apply_mask(id)
	painting_territory = true
	territory_stroking = false
	territory_mode = mode
	territory_panel.set_mode(mode)
	territory_panel.show_state(registry.Name(id), territory.AreaKm2(id))
	_refresh_merge_choices()
	_show_warnings()
	if territory_mode == "fronteira":
		hub.sheet.hide()
		boundary_tool.start(territory_owner)
	painting_changed.emit(true)


## Província e município só pintam dentro do cadastro de cima a que estão ligados (vínculo "Província de", "Município de").
func _apply_mask(id: int) -> void:
	territory.SetMask(null, 0)
	var i := HIERARCHY.find(territory_level)
	if i < 1:
		return
	var parent: int = registry.TerritoryParent(id)
	if parent != 0 and parent <= 65535:
		territory.SetMask(layer(HIERARCHY[i - 1]), parent)
	else:
		territory_panel.set_message("%s não está ligada a um(a) %s: pinta sem limite." % [registry.Name(id), UiKit.kind_label(HIERARCHY[i - 1]).to_lower()])


func _refresh_merge_choices() -> void:
	var others: Array = []
	for p in registry.Palette(territory_level):
		if int(p.id) != territory_owner and territory.AreaKm2(int(p.id)) > 0.0:
			others.append({"id": int(p.id), "name": registry.Name(int(p.id))})
	territory_panel.show_merge_choices(others)


## Unir: o território inteiro de outro cadastro do mesmo nível passa para o que está sendo pintado.
func territory_merge(from_id: int) -> void:
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
	if owner == 0 or registry.Kind(owner) != territory_level:
		territory_panel.set_message("Sem território deste nível aí.")
		return
	territory_owner = owner
	territory_panel.show_state(registry.Name(owner), territory.AreaKm2(owner))
	_refresh_merge_choices()
	_set_territory_mode("pincel")
	territory_panel.set_mode("pincel")
	if owner != hub.current():
		hub.open(owner)


## Mostra e edita a camada de um nível. As outras ficam como estão (e continuam gravadas).
func show_level(level: String) -> void:
	if layer(level) == null or level == territory_level:
		return
	territory_end()
	territory_level = level
	territory = levels[level]
	boundary_tool.use_territory(territory)
	boundary_tool.below = shown_below()
	_palette_hash = 0
	refresh_palette()
	territory_level_shown.emit(level, territory)


## A camada de um nível, carregada do banco na primeira vez; null se o nível não é pintável ou não há como criá-la.
func layer(level: String):
	if levels.has(level):
		return levels[level]
	if not level in PAINTABLE or not layer_factory.is_valid():
		return null
	_adopt(level, layer_factory.call())
	return levels[level]


func _adopt(level: String, t) -> void:
	levels[level] = t
	if hub.usable:
		registry.LoadTerritoryLevel(level, t)
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
	if not territory_level in HIERARCHY:
		return [territory]
	var out: Array = []
	for k in range(HIERARCHY.size() - 1, -1, -1):
		if levels.has(HIERARCHY[k]):
			out.append(levels[HIERARCHY[k]])
	return out


## A imagem dos donos que vai para o globo.
func political_image() -> Image:
	var comp := _composed()
	return comp[0].Composite(comp.slice(1))


## Alguma das camadas mostradas mudou desde a última imagem? (zera as marcas)
func political_dirty() -> bool:
	var dirty := false
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
			"sem_pais": lines.append("⚠ %s não está ligado a um(a) %s (vínculo \"%s de\")" % [registry.Name(int(w.id)),
				UiKit.kind_label(upper).to_lower(), UiKit.kind_label(territory_level)])
			"lacuna": lines.append("⚠ %s: %s km² sem %s" % [registry.Name(int(w.id)), km, UiKit.kind_label(territory_level).to_lower()])
	territory_panel.set_message("\n".join(lines.slice(0, 6)) + ("\n…" if lines.size() > 6 else ""))


func stop_painting() -> void:
	if not painting_territory:
		return
	if territory_stroking:
		territory_end()
	if boundary_tool.has_preview():
		boundary_tool.apply_preview()  # Terminar com a prévia na tela confirma o traço (antes ela era descartada e o país sumia)
	boundary_tool.stop()
	territory.SetMask(null, 0)
	painting_territory = false
	territory_panel.hide_panel()
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
		if boundary_tool.has_preview():
			boundary_tool.apply_preview()  # trocar de ferramenta também confirma o traço em prévia
		boundary_tool.stop()
	painting_changed.emit(true)


## O botão esquerdo apertou no globo em n. Pincel e borracha começam uma pincelada; o balde preenche na hora.
func territory_begin(n: Vector3) -> void:
	if not painting_territory or territory_mode == "fronteira" or n == Vector3.ZERO:
		return
	if territory_mode == "conta-gotas":
		_pick_owner(n)
		return
	if territory_mode == "balde":
		var edit = territory.Fill(n, territory_owner, territory_land_only)
		if edit != null:
			_record_edit("Balde (%d pontos)" % edit.Count, edit)
			territory_panel.set_area(territory.AreaKm2(territory_owner))
		return
	territory.Begin()
	territory_stroking = true
	_dab(n)


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


## "Nova província" / "Novo município": cria o cadastro de baixo, liga ao aberto e já pinta (só dentro dele).
func _on_subdivide() -> void:
	var parent: int = hub.current()
	var i := HIERARCHY.find(registry.Kind(parent))
	if parent == 0 or i < 0 or i + 1 >= HIERARCHY.size():
		return
	var child_kind: String = HIERARCHY[i + 1]
	var made = registry.Create(child_kind, "%s de %s" % [{"provincia": "Nova província", "municipio": "Novo município"}[child_kind], registry.Name(parent)])
	if made == null:
		return
	var child := int(made)
	registry.Link(child, parent, child_kind + "_de")
	hub.open(child)
	start_painting(child)


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
	var shown_levels: Array = HIERARCHY if territory_level in HIERARCHY else [territory_level]
	var colors := {}
	for level in shown_levels:
		for p in registry.Palette(level):
			colors[int(p.id)] = int(_live_colors.get(int(p.id), p.rgb))
	for id in colors:
		var top := _top(id)
		entries.append({"id": id, "rgb": colors.get(top, colors[id]), "top": top})
	var key: int = entries.hash()
	if key != _palette_hash:
		_palette_hash = key
		palette_changed.emit(entries)


## O topo da hierarquia de um cadastro: o país de uma província ou município (subindo pelos vínculos); o próprio id para os outros.
func _top(id: int) -> int:
	var top := id
	for _i in 3:
		var parent: int = registry.TerritoryParent(top)
		if parent == 0:
			break
		top = parent
	return top


func refresh_selection() -> void:
	var top := 0
	var id: int = hub.current()
	if id != 0 and id <= 65535 and registry.Kind(id) in PAINTABLE:
		top = _top(id)
	if top != _selected_top:
		_selected_top = top
		selection_changed.emit(top)


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

## O dono a abrir no clique do globo: o da camada do nível ou, onde ela não tem dono, o das de cima (o país sob a província). 0 = nenhum.
func owner_at(dir: Vector3) -> int:
	if territory == null:
		return 0
	for shown in [territory] + shown_below():
		var owner: int = shown.OwnerAt(dir)
		if owner != 0:
			return owner
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


## Depois de apagar: tira o território e as fronteiras dele, e da pilha de desfazer os comandos que o mencionam.
func after_delete(id: int, deleted_layer) -> void:
	if deleted_layer == null:
		return
	deleted_layer.ClearOwner(id)
	deleted_layer.ForgetOwnerBoundaries(id)
	commands.discard_matching(func(cmd: Object) -> bool:
		return cmd.get_script() == TerritoryEdit and cmd.TouchesOwner(id))


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
