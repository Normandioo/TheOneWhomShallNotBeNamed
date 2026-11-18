extends Node
## O gerenciador de Evron: o globo com as camadas do mapa e os painéis por cima.
## Arrastar = girar · roda = zoom · clique = fixar um ponto · mouse em cima = ler lat/lon e altitude.
##
## Raiz de composição: cria os módulos, liga um ao outro por sinais e roda o quadro. Não tem regra do mundo.
##   data/  os mapas de Evron e a geografia (só funções estáticas).
##   world/ o calendário universal e o relógio oficial (presente, consulta, eventos), sem tela.
##   view/  o globo: material, câmera e a vista 3D.
##   ui/    os painéis: mostram valores e avisam por sinais quando o usuário mexe.

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")
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
const TimeBar = preload("res://scripts/ui/time_bar.gd")

const AUTOSAVE_SECONDS := 30.0  # reais; o relógio também é salvo a cada comando e ao fechar

@onready var hud: Control = $Hud

var height_img: Image
var material := GlobeMaterial.new()
var globe: GlobeView
var layer_panel: LayerPanel
var legend: LegendPanel
var clock := WorldClock.new()
var demo := DemoModule.new()
var seasonal: SeasonalTemperature  # null se os mapas em °C não foram gerados (tools/import_maps.py)
var time_bar: TimeBar
var save_path := WorldStore.DEFAULT_PATH  # "" = não grava nem lê (os testes o esvaziam antes de pôr a cena na árvore)
var _since_save := 0.0

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
	time_bar = TimeBar.new()
	hud.add_child(layer_panel)
	hud.add_child(legend)
	hud.add_child(time_bar)
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
	globe.surface_hovered.connect(func(n: Vector3) -> void: layer_panel.show_cursor(describe(n)))
	globe.surface_clicked.connect(select)
	set_layer(0)


func _process(delta: float) -> void:
	clock.tick(delta)
	globe.update(delta)
	layer_panel.show_camera_altitude(globe.camera_altitude_km())
	_since_save += delta
	if _since_save >= AUTOSAVE_SECONDS:
		save_clock()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_clock()


func _unhandled_input(e: InputEvent) -> void:
	globe.handle_input(e)


# --- Casos de uso ---------------------------------------------------------------------------------------------

func set_layer(index: int) -> void:
	layer = index
	material.show_layer(MapLayers.LAYERS[index])
	globe.set_tiles(MapLayers.LAYERS[index].get("tiles", ""), material.height_texture)
	legend.show_layer(MapLayers.LAYERS[index])
	layer_panel.show_layer(index)


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
	material.set_season(SeasonalTemperature.july_weight(clock.shown()))
	time_bar.show_clock(clock)
	if selected_dir != Vector3.ZERO:  # o ponto fixado mostra os dados da data exibida
		layer_panel.show_selection("Ponto fixado:\n" + describe(selected_dir))


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


