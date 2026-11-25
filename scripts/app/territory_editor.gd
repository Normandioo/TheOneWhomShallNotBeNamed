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
signal palette_changed(entries: Array)  # as cores mudaram ([{id, rgb, top}]): quem desenha atualiza a paleta
signal territory_level_shown(level: String, layer)  # a camada mostrada no globo passou a ser outra
signal selection_changed(top_id: int)  # o país (ou o topo) a destacar no mapa; 0 = nenhum

const SNAP_BAND_KM := 60.0  # "assentar no relevo": a fronteira vai até ~6 pixels do mapa (9,8 km cada) atrás de uma crista ou rio
## As camadas pintáveis (Registry.Levels): a hierarquia política e as áreas de predominância (religião, cultura...).
const HIERARCHY := ["pais", "provincia", "municipio"]
const PAINTABLE := ["pais", "provincia", "municipio", "religiao", "cultura", "etnia", "raca", "idioma"]
const AREA_LEVELS := ["religiao", "cultura", "etnia", "raca", "idioma"]  # as áreas de predominância: aparecem sobre os países (cinzas)
const DRAFT := 65535            # o dono reservado do rascunho (nenhum cadastro tem esse id)
const DRAFT_COLOR := 0xc98a82

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
var _draft_back := "pais"        # o nível que estava na tela antes do rascunho
var territory_mode := "pincel"   # pincel | balde | borracha | conta-gotas | fronteira
var territory_radius := 300.0
var territory_land_only := true
var territory_reach := 800.0     # alcance de "crescer" (km de caminho)
var _last_dab := Vector3.ZERO
var _territory_seen := {}        # nível -> a versão vista pela última vez
var _territory_saved := {}       # nível -> a versão gravada no banco
var _territory_changed_ms := 0
var _palette_hash := 0
var _area_palette_hash := 0
var overlay_level := ""         # a área ("cultura", "etnia"...) sobreposta ao mapa que está na tela (a caixa das sobreposições); "" = nenhuma
var _force_upload := false     # a próxima imagem política vai à GPU mesmo sem edição (trocou o que está composto)
var _selected_top := 0
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
		sheet.paint_kind_requested.connect(func(kind: String) -> void: start_draft(kind))
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
		territory.SetMask(layer(String(registry.Kind(parent))), parent)  # o cadastro de cima pode ser o país mesmo para um município
	else:
		territory_panel.set_message("%s não está ligada a um(a) %s: pinta sem limite." % [registry.Name(id), UiKit.kind_label(HIERARCHY[i - 1]).to_lower()])


func _refresh_merge_choices() -> void:
	if drafting:
		return  # o rascunho não tem nível: ainda não há com quem unir
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
	_force_upload = true
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
	if drafting and territory_level == "rascunho":  # o rascunho por cima, sobre a hierarquia toda
		var with_draft: Array = [draft]
		for k in range(HIERARCHY.size() - 1, -1, -1):
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
	return overlay_level != ""


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
			"sem_pais": lines.append("⚠ %s não está ligado a um(a) %s (vínculo \"%s de\")" % [registry.Name(int(w.id)),
				UiKit.kind_label(upper).to_lower(), UiKit.kind_label(territory_level)])
			"lacuna": lines.append("⚠ %s: %s km² sem %s" % [registry.Name(int(w.id)), km, UiKit.kind_label(territory_level).to_lower()])
	territory_panel.set_message("\n".join(lines.slice(0, 6)) + ("\n…" if lines.size() > 6 else ""))


# --- rascunho: pintar primeiro, dar o nome depois -----------------------------------------------------------------------

## Pintar sem cadastro aberto: a área vira um rascunho (dono reservado, só na tela) até o cartão "Nova região" dar tipo, nome e a quem pertence.
func start_draft(kind_hint := "") -> void:
	if kind_hint != "" or not drafting:
		_draft_hint = kind_hint  # "Pintar mais" (já em rascunho) mantém o tipo pedido
	if not hub.usable or territory == null or hub.is_drawing() or painting_territory or not layer_factory.is_valid():
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
	territory_mode = "pincel"
	territory_panel.set_mode("pincel")
	territory_panel.show_state("Região nova", draft.AreaKm2(DRAFT))
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
	var info := _draft_info()
	if _draft_hint != "":
		info.kind = _draft_hint
	draft_ready.emit(info)


## O que o cartão sugere: o país que cobre mais da metade da área (e a província, se houver) e um tipo pelo tamanho: pequeno dentro de um país parece município.
func _draft_info() -> Dictionary:
	var area: float = draft.AreaKm2(DRAFT)
	var info := {"area_km2": area, "kind": "pais", "country": {}, "province": {}}
	var countries = layer("pais")
	var best := _best_overlap(draft.OverlapKm2(countries, DRAFT), area)
	if not best.is_empty():
		info.country = {"id": best.id, "name": registry.Name(int(best.id)), "share": best.share}
		var fraction: float = area / maxf(float(countries.AreaKm2(int(best.id))), 1.0)
		info.kind = "municipio" if fraction < 0.15 else ("provincia" if fraction < 0.6 else "pais")
	var provinces = layer("provincia")
	var inside := _best_overlap(draft.OverlapKm2(provinces, DRAFT), area)
	if not inside.is_empty() and info.kind == "municipio":
		info.province = {"id": inside.id, "name": registry.Name(int(inside.id)), "share": inside.share}
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
func draft_create(kind: String, region_name: String, parent: int) -> void:
	if not drafting or not kind in PAINTABLE:
		return
	var made = registry.Create(kind, region_name if region_name != "" else "Sem nome (%s)" % UiKit.kind_label(kind))
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
	var edit = target.TakeFrom(draft, DRAFT, id)
	target.SetMask(null, 0)
	if edit != null:
		_record_edit("Criar %s (%d pontos)" % [UiKit.kind_label(kind).to_lower(), edit.Count], edit, kind)
	_close_draft(kind)
	hub.open(id)


## Descarta o rascunho (e volta ao nível que estava na tela).
func discard_draft() -> void:
	if not drafting:
		return
	painting_territory = false
	territory_panel.hide_panel()
	_close_draft(_draft_back)
	painting_changed.emit(false)


func _close_draft(show: String) -> void:
	draft.ClearOwner(DRAFT)
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


## "Nova província" / "Novo município": cria o cadastro de baixo, liga ao aberto e já pinta (só dentro dele).
func _on_subdivide(child_kind := "") -> void:
	var parent: int = hub.current()
	var i := HIERARCHY.find(registry.Kind(parent))
	if parent == 0 or i < 0 or i + 1 >= HIERARCHY.size():
		return
	if child_kind == "":
		child_kind = HIERARCHY[i + 1]
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
	if area_active():  # a área sobreposta vai por uma paleta própria
		var area_entries: Array = []
		for p in registry.Palette(overlay_level):
			area_entries.append({"id": int(p.id), "rgb": int(_live_colors.get(int(p.id), p.rgb))})
		var area_key: int = area_entries.hash()
		if area_key != _area_palette_hash:
			_area_palette_hash = area_key
			area_palette_changed.emit(area_entries)
	var colors := {}
	for level in shown_levels:
		for p in registry.Palette(level):
			colors[int(p.id)] = int(_live_colors.get(int(p.id), p.rgb))
	var focus := _selected_top if subdivisions_view and territory_level in HIERARCHY else 0
	for id in colors:
		var top := _top(id)
		var rgb: int = colors.get(top, colors[id])
		if focus != 0:
			rgb = _subdivision_color(id, colors) if top == focus else _gray_of(rgb)
		entries.append({"id": id, "rgb": rgb, "top": top})
	if drafting:
		entries.append({"id": DRAFT, "rgb": DRAFT_COLOR, "top": DRAFT})
	var key: int = entries.hash()
	if key != _palette_hash:
		_palette_hash = key
		palette_changed.emit(entries)


## A cor de uma subdivisão no modo por subdivisões: a própria; o município de uma província leva a cor dela.
func _subdivision_color(id: int, colors: Dictionary) -> int:
	var parent: int = registry.TerritoryParent(id)
	if registry.Kind(id) == "municipio" and parent != 0 and registry.Kind(parent) == "provincia":
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
		if subdivisions_view:
			refresh_palette()


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
	if territory == null:
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
