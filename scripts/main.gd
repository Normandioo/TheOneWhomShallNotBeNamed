extends Node
## O gerenciador de Evron: o globo com as camadas do mapa e os painéis por cima.
## Arrastar = girar · roda = zoom · clique = fixar um ponto · mouse em cima = ler lat/lon e altitude.
##
## Raiz de composição: cria os módulos, liga um ao outro por sinais e roda o quadro. Não tem regra do mundo.
##   data/  os mapas de Evron e a geografia (só funções estáticas).
##   view/  o globo: material, câmera e a vista 3D.
##   ui/    os painéis: mostram valores e avisam por sinais quando o usuário mexe.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")
const GlobeMaterial = preload("res://scripts/view/globe_material.gd")
const GlobeView = preload("res://scripts/view/globe_view.gd")
const MapLayers = preload("res://scripts/ui/map_layers.gd")
const LayerPanel = preload("res://scripts/ui/layer_panel.gd")
const LegendPanel = preload("res://scripts/ui/legend_panel.gd")
const SearchPanel = preload("res://scripts/ui/search_panel.gd")
const SheetPanel = preload("res://scripts/ui/sheet_panel.gd")
const DomainHub = preload("res://scripts/world/domain_hub.gd")

@onready var hud: Control = $Hud

## Banco dos cadastros de domínio (país, cultura, etnia...). Os testes com cena usam ":memory:" para não tocar no do usuário.
var domains_db := "user://evron_world.db"

var height_img: Image
var material := GlobeMaterial.new()
var globe: GlobeView
var layer_panel: LayerPanel
var legend: LegendPanel
var domains: DomainHub

var layer := 0                    # índice em MapLayers.LAYERS
var selected_dir := Vector3.ZERO  # ponto fixado pelo clique (ZERO = nenhum)


func _ready() -> void:
	if not EvronMaps.available():
		push_error("Mapas não encontrados em data/evron/. Rode: python tools/import_maps.py <caminho>/mapas.zip")
	height_img = EvronMaps.load_height()
	material.set_height(height_img)
	globe = GlobeView.new()
	globe.setup(material.material)
	add_child(globe)
	move_child(globe, 0)  # por baixo dos painéis
	layer_panel = LayerPanel.new()
	legend = LegendPanel.new()
	hud.add_child(layer_panel)
	hud.add_child(legend)
	var search := SearchPanel.new()
	var sheet := SheetPanel.new()
	hud.add_child(search)
	hud.add_child(sheet)
	domains = DomainHub.new()
	domains.setup(domains_db, search, sheet)
	layer_panel.layer_selected.connect(set_layer)
	globe.surface_hovered.connect(func(n: Vector3) -> void: layer_panel.show_cursor(describe(n)))
	globe.surface_clicked.connect(select)
	set_layer(0)


func _exit_tree() -> void:
	if domains != null:
		domains.close()


func _process(delta: float) -> void:
	globe.update(delta)
	layer_panel.show_camera_altitude(globe.camera_altitude_km())


func _unhandled_input(e: InputEvent) -> void:
	globe.handle_input(e)


# --- Casos de uso ---------------------------------------------------------------------------------------------

func set_layer(index: int) -> void:
	layer = index
	material.show_layer(MapLayers.LAYERS[index])
	globe.set_tiles(MapLayers.LAYERS[index].get("tiles", ""), material.height_texture)
	legend.show_layer(MapLayers.LAYERS[index])
	layer_panel.show_layer(index)


func select(n: Vector3) -> void:
	selected_dir = n
	layer_panel.show_selection("Ponto fixado:\n" + describe(n) if n != Vector3.ZERO else "Clique para fixar um ponto.")


## Texto do ponto n: coordenadas, altitude e se é terra ou mar.
func describe(n: Vector3) -> String:
	if n == Vector3.ZERO:
		return "Fora do planeta."
	var ll := EvronGeo.lat_lon(n)
	var h := EvronMaps.height_at(height_img, n)
	var coords := ("Lat %.2f° %s · Lon %.2f° %s" % [
		absf(ll.x), "N" if ll.x >= 0.0 else "S", absf(ll.y), "L" if ll.y >= 0.0 else "O"]).replace(".", ",")
	return "%s\nAltitude %s m (%s)" % [coords, LayerPanel._thousands(roundi(h)), "terra" if h >= 0.0 else "mar"]
