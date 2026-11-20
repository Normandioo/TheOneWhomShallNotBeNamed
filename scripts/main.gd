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
const SearchPanel = preload("res://scripts/ui/search_panel.gd")
const SheetPanel = preload("res://scripts/ui/sheet_panel.gd")
const CalendarPanel = preload("res://scripts/ui/calendar_panel.gd")
const PresencePanel = preload("res://scripts/ui/presence_panel.gd")
const DrawPanel = preload("res://scripts/ui/draw_panel.gd")
const TerritoryPanel = preload("res://scripts/ui/territory_panel.gd")
const Territory = preload("res://scripts/world/Territory.cs")
const TerrainEdit = preload("res://scripts/edit/TerrainEdit.cs")
const DomainHub = preload("res://scripts/world/domain_hub.gd")
const ToolPanel = preload("res://scripts/ui/tool_panel.gd")
const TimeBar = preload("res://scripts/ui/time_bar.gd")

const HEIGHT_UPLOAD_SECONDS := 0.1  # durante a pincelada a altitude vai para a GPU no máximo 10x por segundo
const AUTOSAVE_SECONDS := 30.0  # reais; o relógio também é salvo a cada comando e ao fechar

@onready var hud: Control = $Hud

## Banco dos cadastros de domínio (país, cultura, etnia...). Os testes com cena usam ":memory:" para não tocar no do usuário.
var domains_db := "user://evron_world.db"

var terrain: Terrain
var territory: Territory  # a camada dos países: o dono de cada pixel
var provinces: Territory  # a camada das províncias, independente da dos países
var municipalities: Territory  # a camada dos municípios
var commands := CommandStack.new()
var brush: TerrainBrush
var material := GlobeMaterial.new()
var globe: GlobeView
var layer_panel: LayerPanel
var legend: LegendPanel
var domains: DomainHub
var tool_panel: ToolPanel
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
var _since_upload := 0.0
var _since_political := 0.0
var _coast_stale := true  # a costa do mapa político está atrasada em relação à altitude


func _ready() -> void:
	if not EvronMaps.available():
		push_error("Mapas não encontrados em data/evron/. Rode: python tools/import_maps.py <caminho>/mapas.zip")
	terrain = Terrain.new()
	terrain.Setup(EvronMaps.load_height())
	brush = TerrainBrush.new(terrain, commands)
	territory = Territory.new()
	territory.Setup(terrain)
	provinces = Territory.new()
	provinces.Setup(terrain)
	municipalities = Territory.new()
	municipalities.Setup(terrain)
	var lakes := EvronMaps.load_layer("Waterbodies.png")
	if lakes != null:
		terrain.SetLakes(lakes)  # lagos do Gleba: água no mapa político e nas fronteiras naturais
	var flow := EvronMaps.load_layer("Waterflow.png")
	if flow != null:
		territory.SetRiverFlow(flow)  # os rios grandes do Gleba seguram as fronteiras naturais
		provinces.SetRiverFlow(flow)
		municipalities.SetRiverFlow(flow)
	material.set_height(terrain.HeightImage())
	material.set_rivers(terrain.RiversImage())
	globe = GlobeView.new()
	globe.setup(material.material)
	add_child(globe)
	move_child(globe, 0)  # por baixo dos painéis
	layer_panel = LayerPanel.new()
	legend = LegendPanel.new()
	tool_panel = ToolPanel.new(brush.radius_km, brush.strength, brush.roughness)
	time_bar = TimeBar.new()
	for panel in [layer_panel, legend, tool_panel, time_bar]:
		hud.add_child(panel)
	var search := SearchPanel.new()
	var sheet := SheetPanel.new()
	hud.add_child(search)
	hud.add_child(sheet)
	var calendar_panel := CalendarPanel.new()
	hud.add_child(calendar_panel)  # por último: abre por cima dos outros painéis
	domains = DomainHub.new()
	domains.setup(domains_db, search, sheet, calendar_panel)
	var presence_panel := PresencePanel.new()
	hud.add_child(presence_panel)
	hud.move_child(presence_panel, 0)  # por baixo da ficha e da janela de calendários
	domains.bind_map(globe.places, presence_panel, globe.focus)
	layer_panel.political_visibility_changed.connect(presence_panel.set_political_visible)
	presence_panel.political_visibility_changed.connect(_show_political)
	_show_political("politica" in presence_panel.layers())
	var draw_panel := DrawPanel.new()
	hud.add_child(draw_panel)
	domains.bind_draw(draw_panel)
	var territory_panel := TerritoryPanel.new()
	hud.add_child(territory_panel)
	domains.palette_changed.connect(material.set_political_palette)
	domains.painting_changed.connect(_on_painting_changed)
	domains.bind_territory(territory, commands, territory_panel, {"provincia": provinces, "municipio": municipalities})  # lê as camadas gravadas e manda a paleta
	material.set_political(territory.OwnersImage())
	domains.territory_level_shown.connect(func(level: String, layer) -> void:
		material.set_political(layer.OwnersImage())
		layer_panel.show_level(level))
	layer_panel.level_selected.connect(domains.show_level)
	layer_panel.export_requested.connect(func() -> void: _world_dialog(true))
	layer_panel.import_requested.connect(func() -> void: _world_dialog(false))
	var types_panel := preload("res://scripts/ui/types_panel.gd").new()
	hud.add_child(types_panel)
	domains.bind_types(types_panel)
	var rules_panel := preload("res://scripts/ui/rules_panel.gd").new()
	hud.add_child(rules_panel)
	domains.bind_rules(rules_panel)
	var import_panel := preload("res://scripts/ui/import_panel.gd").new()
	hud.add_child(import_panel)
	domains.bind_import(import_panel)
	domains.boundary_tool.preview_changed.connect(func(img) -> void:
		material.set_political(img if img != null else domains.territory.OwnersImage()))
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
		_command(clock.advance_to(t), "Só dá para avançar até uma data depois do presente."))
	time_bar.view_date.connect(func(t: int) -> void: clock.enter_view(t))
	time_bar.back_to_present.connect(clock.exit_view)
	clock.event_fired.connect(func(e: Dictionary) -> void:
		time_bar.show_message("Marco: %s (%s)" % [e["name"], Calendar.format(e["at"])]))
	_on_clock_changed()
	layer_panel.layer_selected.connect(set_layer)
	tool_panel.tool_selected.connect(set_tool)
	tool_panel.radius_changed.connect(func(km: float) -> void: brush.radius_km = km)
	tool_panel.strength_changed.connect(func(v: float) -> void: brush.strength = v)
	tool_panel.roughness_changed.connect(func(v: float) -> void: brush.roughness = v)
	tool_panel.undo_requested.connect(undo)
	tool_panel.redo_requested.connect(redo)
	commands.changed.connect(_on_history_changed)
	globe.surface_hovered.connect(_on_hover)
	globe.surface_clicked.connect(select)
	set_layer(0)


func _exit_tree() -> void:
	if domains != null:
		domains.close()


func _process(delta: float) -> void:
	clock.tick(delta)
	domains.tick()
	globe.update(delta)
	domains.boundary_tool.update_zoom(globe.camera_altitude_km())
	layer_panel.show_camera_altitude(globe.camera_altitude_km())
	_since_upload += delta
	if terrain.Dirty and (not brush.active or _since_upload >= HEIGHT_UPLOAD_SECONDS):
		material.refresh_height(terrain.HeightImage())
		terrain.Dirty = false
		_since_upload = 0.0
		_coast_stale = true
	if _coast_stale and not brush.active and MapLayers.LAYERS[layer]["kind"] == "political":
		material.set_coast(terrain.CoastImage())  # só com o mapa político na tela e fora da pincelada
		_coast_stale = false
	var shown = domains.territory  # só a camada do nível mostrado vai à GPU; a outra é enviada inteira ao ser mostrada
	if shown.Dirty and (not domains.territory_stroking or _since_political >= 0.1):
		material.refresh_political(shown.OwnersImage())  # durante a pincelada, no máximo 10x por segundo (a camada inteira: 16 MiB)
		shown.Dirty = false
		_since_political = 0.0
	_since_political += delta
	if terrain.RiversDirty and not brush.active:  # os rios só mudam ao soltar o mouse, desfazer ou refazer
		material.refresh_rivers(terrain.RiversImage())
		terrain.RiversDirty = false
	_since_save += delta
	if _since_save >= AUTOSAVE_SECONDS:
		save_clock()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_clock()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and domains != null:
		domains.boundary_tool.cancel()
		domains.territory_end()


func _input(e: InputEvent) -> void:
	# Conclui o gesto mesmo quando o botão é solto sobre um painel do HUD.
	if domains == null or not domains.painting_territory or not (e is InputEventMouseButton) or e.pressed or e.button_index != MOUSE_BUTTON_LEFT:
		return
	if domains.boundary_tool.dragging or domains.territory_stroking:
		domains.boundary_tool.release()
		domains.territory_end()
		get_viewport().set_input_as_handled()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.ctrl_pressed:
		if e.keycode == KEY_Z and not e.shift_pressed:
			undo()
			return
		if e.keycode == KEY_Y or (e.keycode == KEY_Z and e.shift_pressed):
			redo()
			return
	# No modo pintar território, o botão esquerdo pinta (a câmera só gira com o direito), como no pincel de terreno.
	if domains.painting_territory:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				var n := globe.pick(e.position)
				if domains.territory_mode == "fronteira":
					domains.boundary_tool.press(n, e.position, globe.camera_altitude_km())
				else:
					domains.territory_begin(n)
			return
		if e is InputEventMouseMotion and domains.boundary_tool.dragging:
			domains.boundary_tool.drag(globe.pick(e.position), e.position)
			return
		if e is InputEventMouseMotion and domains.territory_stroking:
			domains.territory_drag(globe.pick(e.position))
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


# --- Casos de uso ---------------------------------------------------------------------------------------------

func set_layer(index: int) -> void:
	layer = index
	var selected: Dictionary = MapLayers.LAYERS[index]
	material.show_layer(selected)
	var tiles: String = selected.get("tiles", "")
	if selected["kind"] == "natural" and (material.layer_file != selected["file"] or
			not FileAccess.file_exists(EvronMaps.DIR + "tiles/" + tiles + "/manifest.json")):
		tiles = ""
	globe.set_tiles(tiles, material.height_texture, material.river_texture)
	legend.show_layer(MapLayers.LAYERS[index])
	_refresh_stale()
	layer_panel.show_layer(index)


func _show_political(on: bool) -> void:
	material.show_political(on)
	layer_panel.show_political(on)


## -1 = navegar; senão uma operação do pincel (TerrainBrush.Op).
func set_tool(op: int) -> void:
	if domains.painting_territory:  # escolher uma ferramenta da barra sai do modo pintar território
		domains.stop_painting()
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
	domains.territory_end()
	commands.undo()


func redo() -> void:
	domains.territory_end()
	commands.redo()


## Exportar (escolhe a pasta onde criar Evron-<data>.world) ou importar (escolhe a pasta .world) o mundo inteiro.
func _world_dialog(export: bool) -> void:
	if not domains.usable or domains_db == ":memory:":
		return
	var files := FileDialog.new()
	files.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	files.access = FileDialog.ACCESS_FILESYSTEM
	files.use_native_dialog = true
	files.title = "Onde criar a pasta do mundo" if export else "Escolha a pasta .world a importar"
	files.dir_selected.connect(func(dir: String) -> void:
		files.queue_free()
		if export:
			_export_world(dir)
		else:
			_confirm_import(dir))
	files.canceled.connect(files.queue_free)
	hud.add_child(files)
	files.popup_centered_ratio(0.6)


func _export_world(parent: String) -> void:
	save_clock()
	domains.save_now()
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var dir := parent.path_join("Evron-%s.world" % stamp.left(13))
	var why: String = domains.registry.ExportWorld(dir, ProjectSettings.globalize_path(save_path) if save_path != "" else "")
	_world_message("Mundo exportado para:
" + dir if why == "" else "Não deu para exportar: " + why)


func _confirm_import(dir: String) -> void:
	var why: String = domains.registry.CheckWorld(dir)
	if why != "":
		_world_message("Essa pasta não pode ser importada: " + why)
		return
	var ask := ConfirmationDialog.new()
	ask.dialog_text = "Trocar o mundo aberto pelo de
%s?

O mundo atual fica guardado ao lado do banco como .antes-importacao." % dir
	ask.ok_button_text = "Importar"
	ask.confirmed.connect(func() -> void: _import_world(dir))
	ask.canceled.connect(ask.queue_free)
	hud.add_child(ask)
	ask.popup_centered()


## Fecha o banco (gravando o que faltava), troca os arquivos e recarrega a cena: tudo é lido do mundo novo.
func _import_world(dir: String) -> void:
	save_clock()
	domains.close()
	var why: String = load("res://scripts/world/Registry.cs").new().ImportWorld(dir, ProjectSettings.globalize_path(domains_db),
		ProjectSettings.globalize_path(save_path) if save_path != "" else "")
	if why != "":
		push_error(why)
	save_path = ""  # a cena que sai não regrava o relógio por cima do importado
	get_tree().reload_current_scene()


func _world_message(text: String) -> void:
	var box := AcceptDialog.new()
	box.dialog_text = text
	box.confirmed.connect(box.queue_free)
	box.canceled.connect(box.queue_free)
	hud.add_child(box)
	box.popup_centered()


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
	if domains.drawing:  # no modo desenhar fronteira, o clique marca um ponto do contorno (cola a vértices de fronteiras vizinhas até ~2% da altura)
		domains.draw_click(n, maxf(8.0, globe.camera_altitude_km() * 0.02))
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
	layer_panel.show_cursor(describe(n))
	if domains.painting_territory and not domains.territory_mode in ["fronteira", "conta-gotas"]:
		_show_brush(n, domains.territory_radius)  # o anel do pincel de território
	if tool != ToolPanel.NAVIGATE:
		_show_brush(n)


## Círculo do pincel no globo (parâmetro global "brush" dos shaders); ZERO esconde.
func _show_brush(n: Vector3, km := -1.0) -> void:
	var a := (km if km > 0.0 else brush.radius_km) / EvronGeo.RADIUS_KM if n != Vector3.ZERO else 0.0
	brush_preview = Vector4(n.x, n.y, n.z, a)
	RenderingServer.global_shader_parameter_set("brush", brush_preview)


## Entrou ou saiu do modo pintar território: a barra de ferramentas volta a Navegar e o anel do pincel some.
func _on_painting_changed(on: bool) -> void:
	tool = ToolPanel.NAVIGATE
	tool_panel.show_tool(ToolPanel.NAVIGATE)
	_show_brush(Vector3.ZERO)


func _on_history_changed() -> void:
	_refresh_stale()
	tool_panel.show_history(commands.can_undo(), commands.can_redo(), commands.undo_name(), commands.redo_name())


## Só a camada Altitude acompanha as edições; as imagens do Gleba (clima, biomas, rios...) ficam desatualizadas.
func _refresh_stale() -> void:
	legend.show_stale(commands.has_undoable(TerrainEdit) and MapLayers.LAYERS[layer]["kind"] != "altitude")  # só o terreno deixa as imagens do Gleba desatualizadas (o território não)
