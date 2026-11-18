extends Node
## O gerenciador de Evron: o globo com as camadas do mapa, as ferramentas de edição e os painéis por cima.
## Navegar: arrastar = girar · roda = zoom · clique = fixar um ponto · mouse em cima = ler lat/lon e altitude.
## Pincel: arrastar com o esquerdo = pintar o terreno · arrastar com o direito = girar · Ctrl+Z / Ctrl+Y.
##
## Raiz de composição: cria os módulos, liga um ao outro por sinais e roda o quadro. Não tem regra do mundo.
##   data/   os mapas de Evron e a geografia (só funções estáticas).
##   world/  o estado do mundo (a altitude), sem tela.
##   edit/   comandos de edição: pincel e a pilha de desfazer/refazer.
##   view/   o globo: material, câmera, blocos e a vista 3D.
##   ui/     os painéis: mostram valores e avisam por sinais quando o usuário mexe.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const CommandStack = preload("res://scripts/edit/command_stack.gd")
const TerrainBrush = preload("res://scripts/edit/terrain_brush.gd")
const GlobeMaterial = preload("res://scripts/view/globe_material.gd")
const GlobeView = preload("res://scripts/view/globe_view.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")
const LegendPanel = preload("res://scripts/ui/legend_panel.gd")
const ToolPanel = preload("res://scripts/ui/tool_panel.gd")

const HEIGHT_UPLOAD_SECONDS := 0.1  # durante a pincelada a altitude vai para a GPU no máximo 10x por segundo

@onready var hud: Control = $Hud

var height_img: Image
var terrain: Terrain
var commands := CommandStack.new()
var brush: TerrainBrush
var material := GlobeMaterial.new()
var globe: GlobeView
var layer_panel: LayerPanel
var legend: LegendPanel
var tool_panel: ToolPanel

var layer := 0                    # índice em MapLayers.LAYERS
var tool := ToolPanel.NAVIGATE    # -1 navegar; senão TerrainBrush.Op
var selected_dir := Vector3.ZERO  # ponto fixado pelo clique (ZERO = nenhum)
var brush_preview := Vector4.ZERO # o que foi para o parâmetro global "brush" (fora do editor não dá para lê-lo)
var _since_upload := 0.0


func _ready() -> void:
	if not EvronMaps.available():
		push_error("Mapas não encontrados em data/evron/. Rode: python tools/import_maps.py <caminho>/mapas.zip")
	height_img = EvronMaps.load_height()
	terrain = Terrain.new(height_img)
	brush = TerrainBrush.new(terrain, commands)
	material.set_height(height_img)
	material.set_rivers(terrain.rivers)
	globe = GlobeView.new()
	globe.setup(material.material)
	add_child(globe)
	move_child(globe, 0)  # por baixo dos painéis
	layer_panel = LayerPanel.new()
	legend = LegendPanel.new()
	tool_panel = ToolPanel.new(brush.radius_km, brush.strength, brush.roughness)
	for panel in [layer_panel, legend, tool_panel]:
		hud.add_child(panel)
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


func _process(delta: float) -> void:
	globe.update(delta)
	layer_panel.show_camera_altitude(globe.camera_altitude_km())
	_since_upload += delta
	if terrain.dirty and (not brush.active or _since_upload >= HEIGHT_UPLOAD_SECONDS):
		material.refresh_height(height_img)
		terrain.dirty = false
		_since_upload = 0.0
	if terrain.rivers_dirty and (not brush.active or _since_upload == 0.0):
		material.refresh_rivers(terrain.rivers)
		terrain.rivers_dirty = false


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.ctrl_pressed:
		if e.keycode == KEY_Z and not e.shift_pressed:
			undo()
			return
		if e.keycode == KEY_Y or (e.keycode == KEY_Z and e.shift_pressed):
			redo()
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
	material.show_layer(MapLayers.LAYERS[index])
	globe.set_tiles(MapLayers.LAYERS[index].get("tiles", ""), material.height_texture, material.river_texture)
	legend.show_layer(MapLayers.LAYERS[index])
	_refresh_stale()
	layer_panel.show_layer(index)


## -1 = navegar; senão uma operação do pincel (TerrainBrush.Op).
func set_tool(op: int) -> void:
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
	commands.undo()


func redo() -> void:
	commands.redo()


func select(n: Vector3) -> void:
	selected_dir = n
	layer_panel.show_selection("Ponto fixado:\n" + describe(n) if n != Vector3.ZERO else "Clique para fixar um ponto.")


## Texto do ponto n: coordenadas, altitude e se é terra ou mar.
func describe(n: Vector3) -> String:
	if n == Vector3.ZERO:
		return "Fora do planeta."
	var ll := EvronGeo.lat_lon(n)
	var h := terrain.height_at(n)
	var coords := ("Lat %.2f° %s · Lon %.2f° %s" % [
		absf(ll.x), "N" if ll.x >= 0.0 else "S", absf(ll.y), "L" if ll.y >= 0.0 else "O"]).replace(".", ",")
	return "%s\nAltitude %s m (%s)" % [coords, LayerPanel._thousands(roundi(h)), "terra" if h >= 0.0 else "mar"]


# --- Reações ---------------------------------------------------------------------------------------------------

func _on_hover(n: Vector3) -> void:
	layer_panel.show_cursor(describe(n))
	if tool != ToolPanel.NAVIGATE:
		_show_brush(n)


## Círculo do pincel no globo (parâmetro global "brush" dos shaders); ZERO esconde.
func _show_brush(n: Vector3) -> void:
	var a := brush.radius_km / EvronGeo.RADIUS_KM if n != Vector3.ZERO else 0.0
	brush_preview = Vector4(n.x, n.y, n.z, a)
	RenderingServer.global_shader_parameter_set("brush", brush_preview)


func _on_history_changed() -> void:
	_refresh_stale()
	tool_panel.show_history(commands.can_undo(), commands.can_redo(), commands.undo_name(), commands.redo_name())


## Só a camada Altitude acompanha as edições; as imagens do Gleba (clima, biomas, rios...) ficam desatualizadas.
func _refresh_stale() -> void:
	legend.show_stale(commands.can_undo() and MapLayers.LAYERS[layer]["kind"] != "altitude")
