extends Node
## O gerenciador de Evron: o globo com as camadas do mapa, as ferramentas de edição e os painéis por cima.
## Navegar: arrastar = girar · roda = zoom · clique = fixar um ponto · mouse em cima = ler lat/lon e altitude.
## Pincel: arrastar com o esquerdo = pintar o terreno · arrastar com o direito = girar · Ctrl+Z / Ctrl+Y.
##
## Raiz de composição: cria os módulos, liga um ao outro por sinais e roda o quadro. Não tem regra do mundo.
##   data/   os mapas de Evron e a geografia (só funções estáticas).
##   world/  o estado do mundo, sem tela: a altitude, o calendário universal e o relógio oficial (presente, consulta, eventos).
##   edit/   comandos de edição: pincel e a pilha de desfazer/refazer.
##   view/   o globo: material, câmera, blocos e a vista 3D.
##   ui/     os painéis: mostram valores e avisam por sinais quando o usuário mexe.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")
const Terrain = preload("res://scripts/world/Terrain.cs")
const CommandStack = preload("res://scripts/edit/command_stack.gd")
const PerfMonitor = preload("res://scripts/app/perf_monitor.gd")
const GpuSync = preload("res://scripts/app/gpu_sync.gd")
const TerrainBrush = preload("res://scripts/edit/terrain_brush.gd")
const Calendar = preload("res://scripts/world/calendar.gd")
const WorldClock = preload("res://scripts/world/world_clock.gd")
const WorldStore = preload("res://scripts/world/world_store.gd")
const DemoModule = preload("res://scripts/world/demo_module.gd")
const SeasonalTemperature = preload("res://scripts/world/seasonal_temperature.gd")
const GlobeMaterial = preload("res://scripts/view/globe_material.gd")
const GlobeView = preload("res://scripts/view/globe_view.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")
const LegendPanel = preload("res://scripts/ui/legend_panel.gd")
const ModeRail = preload("res://scripts/ui/mode_rail.gd")
const SearchPanel = preload("res://scripts/ui/search_panel.gd")
const SheetPanel = preload("res://scripts/ui/sheet_panel.gd")
const StatusBar = preload("res://scripts/ui/status_bar.gd")
const CalendarPanel = preload("res://scripts/ui/calendar_panel.gd")
const PresencePanel = preload("res://scripts/ui/presence_panel.gd")
const TerritoryPanel = preload("res://scripts/ui/territory_panel.gd")
const NewRegionCard = preload("res://scripts/ui/new_region_card.gd")
const AreaBar = preload("res://scripts/ui/area_bar.gd")
const AreaLabels = preload("res://scripts/view/area_labels.gd")
const Territory = preload("res://scripts/world/Territory.cs")
const TerrainEdit = preload("res://scripts/edit/TerrainEdit.cs")
const DomainHub = preload("res://scripts/app/domain_hub.gd")
const TerritoryEditor = preload("res://scripts/app/territory_editor.gd")
const ResourcePanel = preload("res://scripts/ui/resource_panel.gd")
const ResourceController = preload("res://scripts/app/resource_controller.gd")
const GeneratorController = preload("res://scripts/app/generator_controller.gd")
const WhyCard = preload("res://scripts/ui/why_card.gd")
const SettlementPanel = preload("res://scripts/ui/settlement_panel.gd")
const ProductionController = preload("res://scripts/app/production_controller.gd")
const RulesController = preload("res://scripts/app/rules_controller.gd")
const TypesController = preload("res://scripts/app/types_controller.gd")
const WorldFiles = preload("res://scripts/app/world_files.gd")
const ToolPanel = preload("res://scripts/ui/tool_panel.gd")
const TimeBar = preload("res://scripts/ui/time_bar.gd")
const TopHud = preload("res://scripts/ui/top_hud.gd")
const HudController = preload("res://scripts/app/hud_controller.gd")
const UserSettings = preload("res://scripts/app/user_settings.gd")
const OptionsPanel = preload("res://scripts/ui/options_panel.gd")
const TutorialOverlay = preload("res://scripts/ui/tutorial_overlay.gd")
const TutorialController = preload("res://scripts/app/tutorial_controller.gd")
const RecordsReset = preload("res://scripts/app/records_reset.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")


@onready var hud: Control = $Hud

## Banco dos cadastros de domínio (país, cultura, etnia...). Os testes com cena usam ":memory:" para não tocar no do usuário.
var _terrain_loaded := false
var domains_db := "user://evron_world.db"

var terrain: Terrain
var territory: Territory  # a camada dos países: o dono de cada pixel
var commands := CommandStack.new()
var _perf: PerfMonitor  # F3: monitor de desempenho
var brush: TerrainBrush
var material := GlobeMaterial.new()
var globe: GlobeView
var layer_panel: LayerPanel
var mode_rail: ModeRail
var status_bar: StatusBar
var _dock := {}  # os painéis que o _layout() posiciona: search, sheet, presence
var _help: AcceptDialog
var legend: LegendPanel
var _country_names := true  # a sobreposição "Nomes dos países"
var domains: DomainHub                # as fichas (busca, ficha, calendários) e o contexto dos outros controladores
var territories: TerritoryEditor      # pintar território, camadas, paleta e seleção do mapa
var resources := ResourceController.new()
var generator := GeneratorController.new()
var production := ProductionController.new()
var rules := RulesController.new()
var types := TypesController.new()
var world_files := WorldFiles.new()
var tool_panel: ToolPanel
var top_hud: TopHud              # emblema, números e categorias do selecionado
var windows := HudController.new()  # o que o alto mostra e a janela única da esquerda
var options_path := "user://evron_options.cfg"  # "" = não grava nem lê as opções (os testes o esvaziam antes de pôr a cena na árvore)
var settings := UserSettings.new()
var options_panel: OptionsPanel
var tutorial_overlay: TutorialOverlay
var tutorials := TutorialController.new()
var records := RecordsReset.new()  # Opções → Cadastros: apagar categorias, com cópia antes
var backup_dir := "user://copias"  # onde ficam as cópias do mundo feitas antes de apagar
var _presence: PresencePanel
var _tooltip_theme := {}  # o visual das dicas, guardado enquanto elas estão desligadas
var clock := WorldClock.new()
var demo := DemoModule.new()
var seasonal: SeasonalTemperature  # null se os mapas em °C não foram gerados (tools/import_maps.py)
var time_bar: TimeBar
var save_path := WorldStore.DEFAULT_PATH  # "" = não grava nem lê (os testes o esvaziam antes de pôr a cena na árvore)
var _since_save := 0.0

var layer := 0                    # índice em MapLayers.LAYERS
var tool := ToolPanel.NAVIGATE    # -1 navegar; senão TerrainBrush.Op
var selected_dir := Vector3.ZERO  # ponto fixado pelo clique (ZERO = nenhum)
var brush_preview := Vector4.ZERO # o que foi para o parâmetro global "brush" (fora do editor não dá para lê-lo)
var gpu_sync: GpuSync  # leva altitude, rios, política e costa para a GPU a cada quadro


var _flow: Image  # os rios grandes do Gleba, para as camadas criadas depois


## Uma camada pintável vazia, na mesma grade (o DomainHub cria as de província, religião etc. na primeira vez que são usadas).
func _new_layer() -> Territory:
	var t := Territory.new()
	t.Setup(terrain)
	if _flow != null:
		t.SetRiverFlow(_flow)
	return t


const TIP_WIDTH := 48  # caracteres por linha das dicas


func _ready() -> void:
	settings.load_from(options_path)
	_apply_window_mode()
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is BaseButton or n is Range:
			_name_on_hover.call_deferred(n))
	hud.theme = UiKit.map_theme()
	_perf = PerfMonitor.new(commands)
	add_child(_perf)
	if not EvronMaps.available():
		push_error("Mapas não encontrados em data/evron/. Rode: python tools/import_maps.py <caminho>/mapas.zip")
	terrain = Terrain.new()
	terrain.Setup(EvronMaps.load_height())
	brush = TerrainBrush.new(terrain, commands)
	territory = Territory.new()
	territory.Setup(terrain)
	var lakes := EvronMaps.load_layer("Waterbodies.png")
	if lakes != null:
		terrain.SetLakes(lakes)  # lagos do Gleba: água no mapa político e nas fronteiras naturais
	var flow := EvronMaps.load_layer("Waterflow.png")
	if flow != null:
		territory.SetRiverFlow(flow)  # os rios grandes do Gleba seguram as fronteiras naturais
	_flow = flow
	globe = GlobeView.new()
	globe.setup(material.material)
	add_child(globe)
	move_child(globe, 0)  # por baixo dos painéis
	layer_panel = LayerPanel.new()
	mode_rail = ModeRail.new()
	hud.add_child(mode_rail)
	status_bar = StatusBar.new()
	hud.add_child(status_bar)
	legend = LegendPanel.new()
	tool_panel = ToolPanel.new(brush.radius_km, brush.strength, brush.roughness)
	time_bar = TimeBar.new()
	top_hud = TopHud.new()
	for panel in [layer_panel, legend, tool_panel, tool_panel.edit_bar, top_hud, tool_panel.world_block, windows.alerts]:
		hud.add_child(panel)
	tool_panel.time_slot.add_child(time_bar)
	status_bar.add_leading(tool_panel.status_items)
	var search := SearchPanel.new()
	var sheet := SheetPanel.new()
	hud.add_child(search)
	hud.add_child(sheet)
	_dock = {"search": search, "sheet": sheet}
	tool_panel.search_requested.connect(search.focus_query)
	tool_panel.registry_requested.connect(func() -> void: windows.toggle_registry())
	tool_panel.help_requested.connect(func() -> void: options_panel.open("ajuda"))
	tool_panel.config_requested.connect(_open_config)
	search.summary_changed.connect(tool_panel.show_counts)
	hud.resized.connect(_layout)
	search.visibility_changed.connect(_layout)
	sheet.visibility_changed.connect(_layout)
	legend.resized.connect(_layout)
	layer_panel.resized.connect(_layout)
	for piece in [top_hud, tool_panel, tool_panel.world_block, mode_rail]:
		piece.resized.connect(_layout)
	top_hud.minimum_size_changed.connect(func() -> void: _layout.call_deferred())  # minimizar ou expandir muda a altura: a janela acompanha
	search.visible = false  # o mapa abre livre: os Registros são abertos pelo botão do alto (tecla O)
	_layout.call_deferred()
	var calendar_panel := CalendarPanel.new()
	_dock["calendar"] = calendar_panel
	hud.add_child(calendar_panel)  # por último: abre por cima dos outros painéis
	domains = DomainHub.new()
	domains.setup(domains_db, search, sheet, calendar_panel)
	domains.bind_commands(commands)
	_terrain_loaded = domains.usable and domains.registry.LoadTerrain(terrain)
	material.set_height(terrain.HeightImage())
	material.set_rivers(terrain.RiversImage())
	terrain.Dirty = false
	terrain.RiversDirty = false
	var presence_panel := PresencePanel.new()
	_presence = presence_panel
	hud.add_child(presence_panel)
	_dock["presence"] = presence_panel
	presence_panel.hide()  # abre pelo botão Sobreposições da coluna de modos
	mode_rail.overlays_toggled.connect(func(open: bool) -> void:
		presence_panel.visible = open
		_layout())
	presence_panel.resized.connect(_layout)
	hud.move_child(presence_panel, 0)  # por baixo da ficha e da janela de calendários
	domains.bind_map(globe.places, presence_panel, globe.focus)
	layer_panel.political_visibility_changed.connect(presence_panel.set_political_visible)
	presence_panel.political_visibility_changed.connect(_show_political)
	presence_panel.legend_visibility_changed.connect(func(on: bool) -> void:
		legend.set_enabled(on)
		_layout())
	presence_panel.rivers_highlight_changed.connect(func(on: bool) -> void:
		if not material.set_river_highlight(on):
			presence_panel.rivers_check.set_pressed_no_signal(false))
	_show_political("politica" in presence_panel.layers())
	var resource_panel := ResourcePanel.new()
	hud.add_child(resource_panel)
	_dock["resources"] = resource_panel
	resource_panel.visibility_changed.connect(func() -> void:
		tool_panel.resources_toggle.set_pressed_no_signal(resource_panel.visible)
		_layout())
	resources.navigate = func() -> void: set_tool(ToolPanel.NAVIGATE)
	resources.focus_map = globe.focus
	tool_panel.resources_toggled.connect(func(open: bool) -> void:
		if open:
			production.set_open(false)  # um painel lateral por vez
		resources.set_open(open))
	var settlement_panel := SettlementPanel.new()
	hud.add_child(settlement_panel)
	_dock["settlements"] = settlement_panel
	settlement_panel.visibility_changed.connect(func() -> void:
		tool_panel.settlements_toggle.set_pressed_no_signal(settlement_panel.visible)
		_layout())
	production.navigate = func() -> void: set_tool(ToolPanel.NAVIGATE)
	production.focus_map = globe.focus
	tool_panel.settlements_toggled.connect(func(open: bool) -> void:
		if open:
			resources.set_open(false)
		production.set_open(open))
	var territory_panel := TerritoryPanel.new()
	hud.add_child(territory_panel)
	_dock["territory"] = territory_panel
	for bar in [territory_panel, tool_panel.edit_bar]:
		bar.resized.connect(_layout)
		bar.visibility_changed.connect(_layout)
	var region_card := NewRegionCard.new()  # "Nova região": o cartão que aparece depois de pintar sem cadastro aberto
	hud.add_child(region_card)
	_dock["region_card"] = region_card
	region_card.resized.connect(_layout)
	region_card.visibility_changed.connect(_layout)
	region_card.minimum_size_changed.connect(func() -> void: _layout.call_deferred())  # a altura muda quando os tipos se acomodam em linhas
	region_card.lookup = func(text: String, kind: String) -> Array: return domains.sheet.lookup.call(text, kind)
	territories = TerritoryEditor.new()
	var area_bar := AreaBar.new()  # com um mapa de área na tela: criar uma nova e a dica de clicar para editar
	hud.add_child(area_bar)
	_dock["area_bar"] = area_bar
	area_bar.resized.connect(_layout)
	area_bar.new_requested.connect(func(kind: String) -> void:
		if not territories.painting_territory:
			territories.start_draft(kind))
	territories.territory_level_shown.connect(func(level: String, _layer) -> void:
		area_bar.show_kind(level if level in TerritoryEditor.AREA_LEVELS else "")
		presence_panel.set_area_level(territories.overlay_level)
		_layout())
	presence_panel.area_overlay_changed.connect(func(level: String) -> void:  # uma área sobre o mapa que está na tela (não troca de mapa, a não ser para o político)
		if level != "" and MapLayers.LAYERS[layer]["kind"] != "political":
			for i in MapLayers.LAYERS.size():
				if MapLayers.LAYERS[i]["kind"] == "political":
					set_layer(i)
					break
		territories.set_overlay(level))
	territories.painting_changed.connect(func(on: bool) -> void: area_bar.visible = not on and territories.territory_level in TerritoryEditor.AREA_LEVELS)
	territories.draft_ready.connect(region_card.show_draft)
	territories.draft_closed.connect(region_card.hide)
	region_card.kind_chosen.connect(func(kind: String) -> void:
		region_card.hide()
		territories.start_draft(kind))
	region_card.kind_changed.connect(territories.set_draft_kind)
	domains.sheet_loaded.connect(func(_s: Dictionary, _g: Dictionary) -> void:
		if region_card.choosing and region_card.visible:
			region_card.hide())  # selecionou um cadastro: a pergunta do tipo novo perde o sentido
	territories.paint_started.connect(_show_painted_kind)
	region_card.create_requested.connect(territories.draft_create)
	region_card.naming = func(parent: int, level: int) -> Dictionary:
		var registry = domains.registry
		var country: int = 0 if parent == 0 else (parent if String(registry.Kind(parent)) == "pais" else int(registry.CountryOf(parent)))
		return {"inherited": registry.LevelName(country, level), "suggestions": Array(registry.DivisionSuggestions())}
	region_card.discard_requested.connect(territories.discard_draft)
	region_card.more_requested.connect(func() -> void:
		region_card.hide()
		territories.start_draft()
		territories.draft_set_parent(int(region_card._parent.get("id", 0))))  # o "Fica dentro de" do cartão vale para os próximos traços
	territories.palette_changed.connect(material.set_political_palette)
	territories.selection_changed.connect(material.set_political_selected)
	territories.painting_changed.connect(_on_painting_changed)
	territories.setup(domains, territory, commands, territory_panel, {}, _new_layer)  # lê a camada dos países e manda a paleta; as outras sob demanda
	territories.area_palette_changed.connect(material.set_area_palette)
	resources.setup(domains, resource_panel, globe.resources, commands, territories)  # depois do editor: usa as camadas dele
	production.setup(domains, settlement_panel, globe.settlements, terrain, territories, clock)  # registra-se no relógio
	production.month_processed.connect(func(_end: int) -> void: resources.refresh())  # a reserva mostrada mudou
	clock.state_changed.connect(production.refresh)  # o estoque é o da data mostrada: entrar e sair da consulta o muda
	if domains.usable:
		generator.setup(resources, resource_panel.generator, terrain)
		var why_card := WhyCard.new()  # "Por que aqui?": no meio do espaço livre, embaixo
		hud.add_child(why_card)
		_dock["why_card"] = why_card
		why_card.resized.connect(_layout)
		why_card.visibility_changed.connect(_layout)
		why_card.toggle_requested.connect(generator.toggle_explained)
		why_card.closed.connect(generator.hide_why)
		generator.card = why_card
		territories.preview_image.connect(func(img) -> void:
			material.set_political(img if img != null else territories.political_image())
			# A prévia é desenhada pela camada política: aparece mesmo com "Fronteira política" desligada.
			material.show_political(img != null or TerritoryEditor.is_resource(territories.territory_level) or "politica" in presence_panel.layers()))
	var area_labels := AreaLabels.new()
	hud.add_child(area_labels)  # rótulos da interface sobre o globo, por baixo dos painéis
	hud.move_child(area_labels, 0)
	area_labels.setup(territories, domains, globe)
	var country_labels := AreaLabels.new()  # os nomes dos países no mapa político (a caixa das sobreposições)
	country_labels.source_level = "pais"
	country_labels.font_size = 17
	country_labels.size_factor = 0.035  # os países são muitos e pequenos: aparecem com menos zoom
	country_labels.active_when = func() -> bool:  # num mapa de cultura, etnia etc. só os nomes desse tipo
		return _country_names and MapLayers.LAYERS[layer]["kind"] == "political" and not territories.shown_kind() in TerritoryEditor.AREA_LEVELS
	hud.add_child(country_labels)
	hud.move_child(country_labels, 0)
	country_labels.setup(territories, domains, globe)
	presence_panel.country_names_changed.connect(func(on: bool) -> void: _country_names = on)
	material.set_political(territory.OwnersImage())
	territories.territory_level_shown.connect(func(level: String, _layer) -> void:
		material.set_political(territories.political_image())
		# A área de um recurso é desenhada pela camada política: aparece mesmo com "Fronteira política" desligada.
		material.show_political(TerritoryEditor.is_resource(level) or "politica" in presence_panel.layers())
		layer_panel.show_level(level)
		if not level in TerritoryEditor.HIERARCHY:
			territories.set_subdivisions_view(false)
		mode_rail.show_level(level, territories.subdivisions_view))
	layer_panel.level_selected.connect(territories.show_level)
	territories.boundary_tool.preview_changed.connect(func(img) -> void:
		material.set_political(img if img != null else territories.political_image()))
	var import_panel := preload("res://scripts/ui/import_panel.gd").new()
	hud.add_child(import_panel)
	territories.bind_import(import_panel)
	var types_panel := preload("res://scripts/ui/types_panel.gd").new()
	hud.add_child(types_panel)
	_dock["types"] = types_panel
	types.setup(domains, types_panel)
	var rules_panel := preload("res://scripts/ui/rules_panel.gd").new()
	hud.add_child(rules_panel)
	_dock["rules"] = rules_panel
	rules.setup(domains, rules_panel)
	world_files.setup(self)
	if domains.usable:
		windows.setup(top_hud, domains, search, resources, resource_panel, production, settlement_panel, territories)
		windows.paint_new = _start_territory
		windows.layout_changed.connect(_layout)
		domains.refresh_search()
		search.summary_changed.emit(search.summary())  # a contagem foi dada antes de o alto da tela estar ligado
	if domains.usable and not _terrain_loaded:
		world_files.notice.call_deferred("O relevo gravado neste mundo não pôde ser lido (veja o log). O mapa abriu com o relevo original e as "
			+ "edições de relevo desta sessão não serão gravadas; a exportação e a importação do mundo continuam funcionando.")
	tool_panel.export_requested.connect(func() -> void: world_files.open_dialog(true))
	tool_panel.import_requested.connect(func() -> void: world_files.open_dialog(false))
	if save_path != "":
		WorldStore.load_into(clock, save_path)  # sem salvamento válido, abre o cenário técnico, pausado
	demo.attach(clock)
	var temperature := EvronMaps.load_temperature()
	if not temperature.is_empty():
		seasonal = SeasonalTemperature.new(temperature)
		_use_model(SeasonalTemperature.NAME, SeasonalTemperature.VERSION)
	clock.state_changed.connect(_on_clock_changed)
	clock.time_changed.connect(_on_clock_changed)
	time_bar.play_toggled.connect(func() -> void:
		if clock.running:
			clock.pause()
		else:
			clock.play()
		save_clock())
	time_bar.speed_selected.connect(func(s: int) -> void: clock.set_speed(s))
	time_bar.advance_seconds.connect(func(s: int) -> void: _command(clock.advance_by(s)))
	time_bar.advance_months.connect(func(n: int) -> void: _command(clock.advance_months(n)))
	time_bar.advance_to.connect(func(t: int) -> void:
		_command(clock.advance_to(t), "Só dá para avançar até uma data depois do presente. Para ver uma data passada, use \"Consultar data\"."))
	time_bar.view_date.connect(func(t: int) -> void: clock.enter_view(t))
	time_bar.back_to_present.connect(clock.exit_view)
	clock.event_fired.connect(func(e: Dictionary) -> void:
		time_bar.show_message("Marco: %s (%s)" % [e["name"], Calendar.format(e["at"])]))
	_on_clock_changed()
	mode_rail.layer_selected.connect(set_layer)
	mode_rail.level_selected.connect(func(level: String) -> void:  # os modos de mundo são o mapa político num nível
		for i in MapLayers.LAYERS.size():
			if MapLayers.LAYERS[i]["kind"] == "political":
				set_layer(i)
				break
		var subs := level == "subdivisoes"  # o mapa político por subdivisões: os países, com o aberto repartido em províncias
		territories.set_subdivisions_view(subs)
		territories.show_level("pais" if subs else level)  # o mapa de área sozinho, sem as fronteiras políticas
		mode_rail.show_level(territories.territory_level, subs))
	tool_panel.tool_selected.connect(set_tool)
	tool_panel.territory_requested.connect(_start_territory)
	tool_panel.radius_changed.connect(func(km: float) -> void: brush.radius_km = km)
	tool_panel.strength_changed.connect(func(v: float) -> void: brush.strength = v)
	tool_panel.roughness_changed.connect(func(v: float) -> void: brush.roughness = v)
	tool_panel.undo_requested.connect(undo)
	tool_panel.redo_requested.connect(redo)
	commands.changed.connect(_on_history_changed)
	globe.surface_hovered.connect(_on_hover)
	globe.surface_clicked.connect(select)
	gpu_sync = GpuSync.new(terrain, brush, material, territories)
	set_layer(0)
	_setup_options()


## Todo botão mostra o próprio nome ao passar o mouse (o texto pode estar cortado; o "✕" é "Fechar"). Os que já têm dica não mudam, mas dicas
## compridas são quebradas em linhas curtas: assim o balão fica ao lado do cursor, em vez de uma faixa larga que o Godot empurra para a borda da tela.
func _name_on_hover(c: Control) -> void:
	if not is_instance_valid(c):
		return
	if c.tooltip_text == "" and c is BaseButton:
		var label: String = c.text.strip_edges()
		c.tooltip_text = "Fechar" if label == "✕" else label
	if c.tooltip_text.length() > TIP_WIDTH and not c.tooltip_text.contains("\n"):
		var lines: PackedStringArray = []
		var line := ""
		for word in c.tooltip_text.split(" "):
			if line != "" and line.length() + word.length() + 1 > TIP_WIDTH:
				lines.append(line)
				line = word
			else:
				line = word if line == "" else line + " " + word
		lines.append(line)
		c.tooltip_text = "\n".join(lines)


func _exit_tree() -> void:
	if gpu_sync != null:
		gpu_sync.finish()  # a thread da costa lê o relevo: terminar antes de gravar e de fechar (fechar com ela rodando derrubava o programa)
	if domains != null:
		_remember_session()
		save_terrain(true)
		domains.close()


func _process(delta: float) -> void:
	clock.tick(delta)
	domains.tick()
	globe.update(delta)
	territories.boundary_tool.update_zoom(globe.camera_altitude_km())
	status_bar.show_camera_altitude(globe.camera_altitude_km())
	gpu_sync.tick(delta)
	territories.boundary_tool.tick()  # prévia do traço de fronteira quando o mouse para
	_since_save += delta
	if _since_save >= float(settings.value("autosave_seconds")):
		save_clock()
		if not brush.active:
			save_terrain()
			tool_panel.show_saved(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_remember_session()
		save_clock()
		save_terrain(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and domains != null and not get_window().unfocusable:  # a janela dos testes nunca tem foco: perdê-lo não cancela o traço
		territories.boundary_tool.cancel()
		territories.territory_end()


func _input(e: InputEvent) -> void:
	# Conclui o gesto mesmo quando o botão é solto sobre um painel do HUD.
	if domains == null or not territories.painting_territory or not (e is InputEventMouseButton) or e.pressed or e.button_index != MOUSE_BUTTON_LEFT:
		return
	if territories.boundary_tool.dragging or territories.territory_stroking:
		territories.boundary_tool.release()
		territories.territory_end()
		get_viewport().set_input_as_handled()


func _unhandled_input(e: InputEvent) -> void:
	if (options_panel != null and options_panel.visible) or (tutorial_overlay != null and tutorial_overlay.blocking()):
		return  # com o menu ou um tutorial na tela, os atalhos e o globo esperam
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F3:
		_perf.toggle()
		return
	if e is InputEventKey and e.pressed and not e.echo and not e.ctrl_pressed and not e.alt_pressed and not e.meta_pressed:
		var typing := get_viewport().gui_get_focus_owner()
		if not (typing is LineEdit or typing is TextEdit or typing is SpinBox):
			match e.keycode:
				KEY_V:
					set_tool(ToolPanel.NAVIGATE)
					return
				KEY_T:
					_start_territory()
					return
				KEY_R:
					set_tool(0)
					return
				KEY_O:
					windows.toggle_registry()
					return
				KEY_ESCAPE:
					if domains.cancel_move():
						return
					if _can_dismiss():  # Esc fecha a janela; sem janela, tira a seleção (não consome: os painéis também ouvem Esc)
						if windows.window_open():
							windows.close_window()
						elif domains.current() != 0:
							domains.deselect()
						else:
							options_panel.open()
						return
				KEY_F1:
					_show_help()
					return
	if e is InputEventKey and e.pressed and not e.echo and e.ctrl_pressed:
		if e.keycode == KEY_F and domains.usable:  # busca global: abre o Índice na aba Busca
			domains.search.focus_query()
			get_viewport().set_input_as_handled()
			return
		if e.keycode == KEY_Z and not e.shift_pressed:
			undo()
			return
		if e.keycode == KEY_Y or (e.keycode == KEY_Z and e.shift_pressed):
			redo()
			return
	# No modo pintar território, o botão esquerdo pinta (a câmera só gira com o direito), como no pincel de terreno.
	if territories.painting_territory:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				var n := globe.pick(e.position)
				if territories.territory_mode == "fronteira":
					territories.draft_anchor(n)
					territories.boundary_tool.press(n, e.position, globe.camera_altitude_km())
				else:
					territories.territory_begin(n)
			return
		if e is InputEventMouseMotion and territories.boundary_tool.dragging:
			territories.boundary_tool.drag(globe.pick(e.position), e.position)
			return
		if e is InputEventMouseMotion and territories.territory_stroking:
			territories.territory_drag(globe.pick(e.position))
		globe.handle_input(e)
		return
	# Com um pincel ativo, o botão esquerdo pinta (a câmera só gira com o direito).
	if tool != ToolPanel.NAVIGATE and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var n := globe.pick(e.position)
		if e.pressed and n != Vector3.ZERO:
			brush.begin(n)
		elif not e.pressed and brush.active:
			brush.end()
		return
	if brush.active and e is InputEventMouseMotion:
		var n := globe.pick(e.position)
		if n != Vector3.ZERO:
			brush.drag(n)
	globe.handle_input(e)


# --- Disposição do HUD -----------------------------------------------------------------------------------------

## Põe os painéis no lugar: no alto à esquerda o selecionado e as categorias; no alto à direita o tempo, a busca e o menu Mundo, com os
## avisos embaixo; à esquerda a janela única, entre o alto e a barra de estado; embaixo à direita os modos de mapa; embaixo ao centro a
## barra de ferramentas (e, em cima dela, só a barra da ferramenta em uso). A legenda e o ponto fixado ficam ao lado da janela.
const NARROW := 1500.0  # abaixo disto as categorias ficam só com o ícone

func _layout() -> void:
	if _dock.is_empty() or tool_panel == null or top_hud == null:
		return
	var width := hud.size.x
	var bottom := hud.size.y - StatusBar.HEIGHT
	var compact := width < NARROW
	top_hud.set_compact(compact)
	var block: Control = tool_panel.world_block
	block.custom_minimum_size.x = 440.0 if compact else float(ToolPanel.BLOCK_WIDTH)
	block.size = block.get_combined_minimum_size()
	block.position = Vector2(width - block.size.x, 0)
	top_hud.fit_stats(width - block.size.x - (150.0 if compact else 200.0))
	top_hud.position = Vector2.ZERO
	top_hud.size = top_hud.get_combined_minimum_size()
	windows.alerts.position = Vector2(width - windows.alerts.size.x - 10.0, block.size.y + 8.0)
	var top := top_hud.size.y + 4.0

	var left := 0.0
	for key in ["sheet", "search", "resources", "settlements"]:
		var window: Control = _dock.get(key)
		if window != null and window.visible:
			window.position = Vector2(0, top)
			window.size = Vector2(SheetPanel.WIDTH, bottom - top)
			left = SheetPanel.WIDTH

	mode_rail.size = mode_rail.get_combined_minimum_size()
	mode_rail.position = Vector2(width - mode_rail.size.x, bottom - mode_rail.size.y)
	var free_right := mode_rail.position.x

	# Ferramentas embaixo ao centro; pintando território, a barra dele toma o lugar.
	var painting: bool = _dock.get("territory") != null and _dock["territory"].visible
	tool_panel.visible = not painting
	var lift := 0.0
	var bars: Array = [tool_panel, _dock.get("territory"), tool_panel.edit_bar, _dock.get("region_card"), _dock.get("why_card")]
	var highest_left := width
	var highest_top := bottom
	for bar in bars:
		if bar == null or not bar.visible:
			continue
		bar.size = bar.get_combined_minimum_size()
		var x := clampf((left + free_right) / 2.0 - bar.size.x / 2.0, left + 8.0, maxf(left + 8.0, free_right - bar.size.x - 8.0))
		# Uma barra mais larga que o espaço livre sobe acima dos modos de mapa, em vez de ficar por baixo deles; se nem ao lado
		# da janela ela cabe, avança sobre a janela: nenhum botão sai da tela.
		var floor_y := bottom - 8.0
		if x + bar.size.x > free_right:
			floor_y = minf(floor_y, mode_rail.position.y - 8.0)
			x = clampf(x, minf(left + 8.0, maxf(8.0, width - bar.size.x - 8.0)), maxf(8.0, width - bar.size.x - 8.0))
		bar.position = Vector2(x, floor_y - bar.size.y - lift)
		highest_left = minf(highest_left, x)
		highest_top = minf(highest_top, bar.position.y)
		lift += bar.size.y + 8.0

	var legend_floor := bottom - 12.0
	if highest_left < left + 12.0 + legend.size.x + 8.0:
		legend_floor = minf(legend_floor, highest_top - 8.0)  # uma barra chega até a legenda: ela sobe
	legend.position = Vector2(left + 12.0, legend_floor - legend.size.y)
	var overlays: Control = _dock.get("presence")
	if overlays != null and overlays.visible:
		overlays.size = overlays.get_combined_minimum_size()
		overlays.position = Vector2(width - overlays.size.x, maxf(top, mode_rail.position.y - overlays.size.y - 6.0))
	layer_panel.position = Vector2(left + 12.0, top + 8.0)  # o ponto fixado, em cima do globo
	var area_bar: Control = _dock.get("area_bar")
	if area_bar != null:
		area_bar.position = Vector2(left + 12.0, top + 8.0 + (layer_panel.size.y + 8.0 if layer_panel.visible else 0.0))


## Uma pintura começou: o mapa mostra o tipo de coisa que se pinta (o político, no nível dele). Depois dá para trocar de camada à vontade.
func _show_painted_kind(kind: String) -> void:
	if MapLayers.LAYERS[layer]["kind"] != "political":
		for i in MapLayers.LAYERS.size():
			if MapLayers.LAYERS[i]["kind"] == "political":
				set_layer(i)
				break
	var divisions := kind in ["provincia", "municipio"]
	mode_rail.show_level(kind if kind != "" else "pais", divisions)


## Esc pode fechar a janela ou tirar a seleção? Não enquanto há uma ferramenta, uma pintura ou um clique esperado no globo (o Esc é deles).
func _can_dismiss() -> bool:
	if _dock.has("region_card") and _dock["region_card"].visible:
		return false
	if tool != ToolPanel.NAVIGATE or territories.painting_territory or territories.drafting:
		return false
	for key in ["resources", "settlements"]:
		var panel = _dock.get(key)
		if panel != null and panel.visible and panel.waiting:
			return false
	return true


## O menu Mundo: abre as janelas de tipos, regras e calendários (as mesmas dos Registros).
func _open_config(which: String) -> void:
	var index: Control = _dock["search"]
	match which:
		"opcoes":
			options_panel.open()
		"tipos":
			index.types_requested.emit()
		"regras":
			index.rules_requested.emit()
		"calendarios":
			index.calendars_requested.emit()


## O modo Território: pinta o cadastro aberto na ficha (T ou o botão da barra de cima).
func _start_territory() -> void:
	resources.cancel_click()
	if territories.drafting:
		territories.start_draft()  # volta a pintar o rascunho, do tipo já escolhido
	elif domains.current() == 0:
		tool_panel.show_territory_editing(false)
		_dock["region_card"].show_choice()  # nada selecionado: primeiro o tipo, depois o pincel
		return
	else:
		territories.start_painting(domains.current())
	if not territories.painting_territory:  # um tipo sem área pintável
		tool_panel.show_territory_editing(false)
		time_bar.show_message("Este cadastro não tem área pintável.")


## F1: os atalhos que existem.
func _show_help() -> void:
	if _help == null:
		_help = UiKit.themed(AcceptDialog.new())
		_help.title = "Atalhos"
		_help.dialog_text = "V  Navegar
T  Território: pintar o cadastro aberto na ficha (sem ficha aberta, cria uma região nova)
R  Relevo
O  Abrir ou fechar os Registros
" 			+ "Ctrl+F  Buscar
Ctrl+Z / Ctrl+Y  Desfazer e refazer
Esc  Concluir o modo de edição; fechar a janela; tirar a seleção; abrir as opções
F1  Esta ajuda"
		add_child(_help)
	_help.popup_centered()


# --- Opções e tutoriais -----------------------------------------------------------------------------------------

func _setup_options() -> void:
	options_panel = OptionsPanel.new()
	hud.add_child(options_panel)
	records.setup(self)
	options_panel.setup(settings, TutorialController.GROUPS, records)
	tutorial_overlay = TutorialOverlay.new()
	hud.add_child(tutorial_overlay)  # por último: por cima de tudo
	tutorials.setup(self, tutorial_overlay, settings)
	tutorials.auto = options_path != ""
	options_panel.tutorial_requested.connect(tutorials.request)
	options_panel.quit_requested.connect(func() -> void:
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)  # grava o relógio e o relevo, como ao fechar a janela
		get_tree().quit())
	settings.changed.connect(_apply_option)
	for key in UserSettings.OPTIONS:
		if key != "window_mode":
			_apply_option(key)
	_restore_session()
	tutorials.offer_basic.call_deferred()


func _apply_option(key: String) -> void:
	match key:
		"window_mode":
			_apply_window_mode()
		"ui_scale":
			get_window().content_scale_factor = clampf(float(settings.value(key)), 0.75, 1.5)
		"max_fps":
			Engine.max_fps = maxi(int(settings.value(key)), 0)
		"vsync":
			if DisplayServer.get_name() != "headless" and options_path != "":
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.value(key) else DisplayServer.VSYNC_DISABLED)
		"orbit_speed":
			globe.camera.orbit_speed = clampf(float(settings.value(key)), 0.25, 2.0)
		"zoom_speed":
			globe.camera.zoom_speed = clampf(float(settings.value(key)), 0.25, 2.0)
		"tooltips":
			_apply_tooltips(settings.value(key))


## O jogo abre como o jogador pediu (maximizado, se nada foi pedido). A janela dos testes fica como nasceu: maximizar a traria para a tela.
func _apply_window_mode() -> void:
	if domains_db == ":memory:" or get_window().unfocusable:
		return
	match String(settings.value("window_mode")):
		"cheia":
			get_window().mode = Window.MODE_FULLSCREEN
		"janela":
			get_window().mode = Window.MODE_WINDOWED
			var screen := DisplayServer.screen_get_usable_rect(get_window().current_screen)
			get_window().size = Vector2i(Vector2(screen.size) * 0.85)
			get_window().position = screen.position + (screen.size - get_window().size) / 2
		_:
			get_window().mode = Window.MODE_MAXIMIZED


## Dicas desligadas: o balão fica invisível (o Godot não tem um interruptor que valha com o jogo aberto).
func _apply_tooltips(on: bool) -> void:
	var theme := hud.theme
	if on:
		if _tooltip_theme.is_empty():
			return
		theme.set_stylebox("panel", "TooltipPanel", _tooltip_theme.panel)
		theme.set_color("font_color", "TooltipLabel", _tooltip_theme.font)
		theme.set_color("font_shadow_color", "TooltipLabel", _tooltip_theme.shadow)
		theme.set_font_size("font_size", "TooltipLabel", _tooltip_theme.size)
		_tooltip_theme = {}
	elif _tooltip_theme.is_empty():
		_tooltip_theme = {"panel": theme.get_stylebox("panel", "TooltipPanel"), "font": theme.get_color("font_color", "TooltipLabel"),
			"shadow": theme.get_color("font_shadow_color", "TooltipLabel"), "size": theme.get_font_size("font_size", "TooltipLabel")}
		theme.set_stylebox("panel", "TooltipPanel", StyleBoxEmpty.new())
		theme.set_color("font_color", "TooltipLabel", Color.TRANSPARENT)
		theme.set_color("font_shadow_color", "TooltipLabel", Color.TRANSPARENT)
		theme.set_font_size("font_size", "TooltipLabel", 1)


## Guarda como a tela estava (o alto, as sobreposições e o modo de mapa).
func _remember_session() -> void:
	if options_panel == null or territories == null:
		return
	settings.set_value("hud_minimized", top_hud.minimized)
	settings.set_value("legend", _presence.legend_check.button_pressed)
	settings.set_value("country_names", _country_names)
	settings.set_value("rivers", _presence.rivers_check.button_pressed)
	settings.set_value("area_overlay", territories.overlay_level)
	var level: String = territories.territory_level
	settings.set_value("map_layer", layer)
	settings.set_value("map_level", level if level in TerritoryEditor.PAINTABLE and not territories.drafting else "pais")
	settings.set_value("map_subdivisions", territories.subdivisions_view)


func _restore_session() -> void:
	if settings.value("remember_hud") and settings.value("hud_minimized"):
		top_hud.set_minimized(true)
	if settings.value("remember_overlays"):
		_presence.legend_check.button_pressed = settings.value("legend")
		_presence.names_check.button_pressed = settings.value("country_names")
		_presence.rivers_check.button_pressed = settings.value("rivers")
		var overlay: String = settings.value("area_overlay")
		if overlay in TerritoryEditor.AREA_LEVELS and domains.usable:
			_presence.set_area_level(overlay)
			territories.set_overlay(overlay)
	if settings.value("remember_map"):
		var index := int(settings.value("map_layer"))
		if index > 0 and index < MapLayers.LAYERS.size():
			set_layer(index)
		var level: String = settings.value("map_level")
		if domains.usable and level in TerritoryEditor.PAINTABLE and MapLayers.LAYERS[layer]["kind"] == "political":
			var subs: bool = settings.value("map_subdivisions") and level == "pais"
			territories.set_subdivisions_view(subs)
			territories.show_level(level)
			mode_rail.show_level(territories.territory_level, subs)


# --- Casos de uso ---------------------------------------------------------------------------------------------

func set_layer(index: int) -> void:
	layer = index
	var selected: Dictionary = MapLayers.LAYERS[index]
	var t_l := PerfMonitor.start()
	material.show_layer(selected)
	PerfMonitor.stop("trocar camada (" + str(selected["file"] if selected.has("file") else selected["kind"]) + ")", t_l)
	# Nos mapas que não são o político, a sobreposição "Fronteira política" mostra os países: se o nível ficou numa área independente
	# (religião, cultura…), muitas vezes vazia, os países sumiriam. Volta para os países, a não ser que se esteja pintando.
	if selected["kind"] != "political" and territories != null and not territories.painting_territory 			and not territories.territory_level in TerritoryEditor.HIERARCHY and not TerritoryEditor.is_resource(territories.territory_level):
		territories.show_level("pais")
	var tiles: String = selected.get("tiles", "")
	if selected["kind"] == "natural" and (material.layer_file != selected["file"] or
			not FileAccess.file_exists(EvronMaps.directory() + "tiles/" + tiles + "/manifest.json")):
		tiles = ""
	globe.set_tiles(tiles, material.height_texture, material.river_texture)
	legend.show_layer(MapLayers.LAYERS[index])
	_refresh_stale()
	mode_rail.show_layer(index)


func _show_political(on: bool) -> void:
	material.show_political(on)
	layer_panel.show_political(on)


## -1 = navegar; senão uma operação do pincel (TerrainBrush.Op).
func set_tool(op: int) -> void:
	if op != ToolPanel.NAVIGATE:
		resources.cancel_click()
		production.cancel_click()
	if territories.painting_territory:  # escolher uma ferramenta da barra sai do modo pintar território
		territories.stop_painting()
	if brush.active:
		brush.end()
	tool = op
	if op != ToolPanel.NAVIGATE:
		brush.op = op
	else:
		_show_brush(Vector3.ZERO)
	tool_panel.show_tool(op)


func undo() -> void:
	if brush.active:
		brush.end()
	territories.territory_end()
	commands.undo()


func redo() -> void:
	territories.territory_end()
	commands.redo()


## Grava as edições de relevo. Se o relevo gravado não pôde ser lido ao abrir, nada é gravado por cima dele (as edições novas ficam só
## na memória); sem edições novas isso não é um problema, e exportar ou importar o mundo continua valendo.
func save_terrain(finish_stroke := false) -> bool:
	if domains == null or not domains.usable:
		return false
	if finish_stroke and brush.active:
		brush.end()
	if not _terrain_loaded:
		return not terrain.HasEdits
	return domains.registry.SaveTerrain(terrain)


## Por que o relevo não pôde ser gravado (para as mensagens de exportar e importar).
func terrain_problem() -> String:
	if not _terrain_loaded:
		return "o relevo gravado neste mundo não pôde ser lido ao abrir; as edições de relevo desta sessão não podem ser gravadas"
	return "as alterações no relevo não foram gravadas"


func save_clock() -> void:
	_since_save = 0.0
	if save_path != "" and not WorldStore.save(clock, save_path):
		push_error("Não consegui salvar o calendário em " + save_path)


## Resultado de um comando de avanço: recusado mostra o aviso; aceito limpa o aviso e salva.
func _command(accepted: bool, refusal := "") -> void:
	time_bar.show_message("" if accepted else refusal)
	if accepted:
		save_clock()


## Registra a versão de um modelo no relógio (vai para o salvamento) e avisa se o mundo foi salvo com outra.
func _use_model(model_name: String, version: int) -> void:
	var saved := int(clock.models.get(model_name, version))
	if saved != version:
		time_bar.show_message("%s: salvo com a versão %d do modelo, esta é a %d." % [model_name, saved, version])
	clock.models[model_name] = version


func _on_clock_changed() -> void:
	domains.set_time(clock.shown())
	material.set_season(SeasonalTemperature.july_weight(clock.shown()))
	time_bar.show_clock(clock)
	if selected_dir != Vector3.ZERO:  # o ponto fixado mostra os dados da data exibida
		layer_panel.show_selection("Ponto fixado:\n" + describe(selected_dir))


func select(n: Vector3) -> void:
	if production.click(n):
		return
	if resources.click(n, maxf(20.0, globe.camera_altitude_km() * 0.02)):
		return
	if domains.place_click(n):
		return
	selected_dir = n
	domains.set_fixed_point(n)
	domains.pick(n, maxf(40.0, globe.camera_altitude_km() * 0.05))  # o clique em uma presença abre o cadastro (tolerância cresce com a altura)
	layer_panel.show_selection("Ponto fixado:\n" + describe(n) if n != Vector3.ZERO else "Clique para fixar um ponto.")


## Texto do ponto n: coordenadas, altitude e se é terra ou mar.
func describe(n: Vector3) -> String:
	if n == Vector3.ZERO:
		return "Fora do planeta."
	var ll := EvronGeo.lat_lon(n)
	var h := terrain.HeightAt(n)
	var coords := ("Lat %.2f° %s · Lon %.2f° %s" % [
		absf(ll.x), "N" if ll.x >= 0.0 else "S", absf(ll.y), "L" if ll.y >= 0.0 else "O"]).replace(".", ",")
	var head := "%s\nAltitude %s m (%s · estático)" % [coords, LayerPanel._thousands(roundi(h)), "terra" if h >= 0.0 else "mar"]
	if seasonal != null and MapLayers.LAYERS[layer]["kind"] == "season":
		return head + "\n" + _season_line(n)
	var test := DemoModule.value_at(n, clock.shown())
	if not test.has("value"):
		return "%s\n%s: indisponível em %s" % [head, DemoModule.NAME, test["date"]]
	return (head + "\n%s: %+.1f %s (%s · %s)" % [DemoModule.NAME, test["value"], test["unit"], test["state"], test["date"]]).replace(".", ",")


## A temperatura estimada em n na data exibida, com condição, origem e incerteza (nunca como se fosse medida).
func _season_line(n: Vector3) -> String:
	var r := seasonal.value_at(n, clock.shown())
	if not r.has("value"):
		return "Temperatura: indisponível em %s" % r["date"]
	# Uma referência cortada em −20 °C só dá um limite: o real é menor ou igual ao valor mostrado.
	var value := ("%s%+.1f °C" % ["≤ " if r["saturated"] else "", r["value"]]).replace(".", ",")
	return "Temperatura: %s · %s · %s\nOrigem: %s\nIncerteza: %s" % [value, r["state"], r["date"], r["source"], r["uncertainty"]]


# --- Reações ---------------------------------------------------------------------------------------------------

func _on_hover(n: Vector3) -> void:
	status_bar.show_cursor(describe(n))
	if territories.painting_territory and not territories.territory_mode in ["fronteira", "conta-gotas"]:
		_show_brush(n, territories.territory_radius)  # o anel do pincel de território
	if tool != ToolPanel.NAVIGATE:
		_show_brush(n)


## Círculo do pincel no globo (parâmetro global "brush" dos shaders); ZERO esconde.
func _show_brush(n: Vector3, km := -1.0) -> void:
	var a := (km if km > 0.0 else brush.radius_km) / EvronGeo.RADIUS_KM if n != Vector3.ZERO else 0.0
	brush_preview = Vector4(n.x, n.y, n.z, a)
	RenderingServer.global_shader_parameter_set("brush", brush_preview)


## Entrou ou saiu do modo pintar território: a barra de ferramentas volta a Navegar e o anel do pincel some.
func _on_painting_changed(on: bool) -> void:
	if not on and territories.territory_level in ["provincia", "municipio"]:
		mode_rail.show_level("pais")  # terminada a pintura de uma divisão, o mapa volta ao político dos países
	tool = ToolPanel.NAVIGATE
	tool_panel.show_territory_editing(on)
	_show_brush(Vector3.ZERO)


func _on_history_changed() -> void:
	tool_panel.show_saved(false)
	_refresh_stale()
	tool_panel.show_history(commands.can_undo(), commands.can_redo(), commands.undo_name(), commands.redo_name())


## Só a camada Altitude acompanha as edições; as imagens do Gleba (clima, biomas, rios...) ficam desatualizadas.
func _refresh_stale() -> void:
	legend.show_stale(commands.has_undoable(TerrainEdit) and MapLayers.LAYERS[layer]["kind"] != "altitude")  # só o terreno deixa as imagens do Gleba desatualizadas (o território não)
