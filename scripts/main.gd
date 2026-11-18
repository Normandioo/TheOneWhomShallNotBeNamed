extends Node
## O jogo: o sistema solar em 3D com Marte em foco (o planeta que o jogador terraforma) e os painéis por cima.
## Arrastar = girar a câmera em volta do corpo · roda = zoom, da superfície ao sistema solar · clique em Marte =
## selecionar uma região · clique em outro corpo = focar nele.
##
## Raiz de composição: cria os módulos, liga um ao outro por sinais e roda o quadro. Não tem regra de jogo.
##   sim/    a simulação (estado do planeta, clima, calendário, efemérides): não conhece cena nem interface.
##   view/   materiais e colônias de Marte.
##   space/  a vista 3D: câmera, cena, marcadores.
##   ui/     os painéis: mostram valores e avisam por sinais quando o jogador mexe.
## Os dados fluem num sentido só: a simulação avisa por sinais, e a interface pede mudanças por métodos.

const MarsGeo = preload("res://scripts/data/mars_geo.gd")
const MolaReader = preload("res://scripts/data/mola_reader.gd")
const Climate = preload("res://scripts/sim/climate.gd")
const ClimateRunner = preload("res://scripts/sim/climate_runner.gd")
const Hypsometry = preload("res://scripts/sim/hypsometry.gd")
const PlanetState = preload("res://scripts/sim/planet_state.gd")
const AutoTerraformer = preload("res://scripts/sim/auto_terraformer.gd")
const GameClock = preload("res://scripts/sim/game_clock.gd")
const Ephemeris = preload("res://scripts/sim/ephemeris.gd")
const SolarBodies = preload("res://scripts/sim/solar_bodies.gd")
const PlanetMaterials = preload("res://scripts/view/planet_materials.gd")
const ColonyLayer = preload("res://scripts/view/colony_layer.gd")
const SpaceView = preload("res://scripts/space/space_view.gd")
const ControlPanel = preload("res://scripts/ui/control_panel.gd")
const TimePanel = preload("res://scripts/ui/time_panel.gd")
const GaugePanel = preload("res://scripts/ui/gauge_panel.gd")
const LegendPanel = preload("res://scripts/ui/legend_panel.gd")
const RegionInfo = preload("res://scripts/ui/region_info.gd")

@onready var hud: Control = $Hud

# Simulação.
var height_img: Image
var climate: Climate
var planet: PlanetState
var clock := GameClock.new()
var auto_terraformer := AutoTerraformer.new()
var climate_runner: ClimateRunner

# Vista.
var materials: PlanetMaterials
var space: SpaceView
var colonies := ColonyLayer.new()

# Interface.
var control_panel: ControlPanel
var time_panel: TimePanel
var gauge: GaugePanel
var legend: LegendPanel

var selected_dir := Vector3.ZERO


func _ready() -> void:
	_build_simulation()
	_build_view()
	_build_ui()
	_connect_signals()


func _build_simulation() -> void:
	height_img = MolaReader.load_global_height()
	climate = Climate.new()
	climate.setup(height_img)
	var hypsometry := Hypsometry.new()
	hypsometry.setup(climate.hgt, climate.weight)
	planet = PlanetState.new(hypsometry)
	climate_runner = ClimateRunner.new(climate)


func _build_view() -> void:
	materials = PlanetMaterials.new()
	materials.setup(height_img, MarsGeo.region_dirs(), climate)
	space = SpaceView.new()
	space.setup(clock, materials.globe)
	add_child(space)
	move_child(space, 0)  # por baixo dos painéis
	colonies.setup(space.scene.body_node(SolarBodies.Id.MARS), SolarBodies.radius_units(SolarBodies.Id.MARS))
	materials.set_region_colors(colonies.owner_colors())


func _build_ui() -> void:
	control_panel = ControlPanel.new()
	time_panel = TimePanel.new(clock.time_scale)
	gauge = GaugePanel.new()
	legend = LegendPanel.new()
	for panel in [control_panel, time_panel, gauge, legend]:
		hud.add_child(panel)
	for p in PlanetState.CONTROLS:
		control_panel.set_control_value(p, planet.get_control(p))
	legend.show_mode(0)


func _connect_signals() -> void:
	# O jogador pede, a simulação decide, e a interface mostra o resultado.
	control_panel.control_changed.connect(planet.set_control)
	control_panel.map_mode_selected.connect(set_map_mode)
	control_panel.found_requested.connect(found_colony)
	time_panel.speed_selected.connect(clock.set_speed)
	time_panel.auto_terraform_toggled.connect(func(on: bool) -> void: auto_terraformer.enabled = on)
	time_panel.extremes_toggled.connect(planet.set_extremes)
	clock.speed_changed.connect(time_panel.show_speed)
	planet.control_changed.connect(_on_control_changed)
	planet.limits_changed.connect(_on_limits_changed)
	planet.sea_level_changed.connect(_on_sea_level_changed)
	climate_runner.step_finished.connect(_on_climate_step_finished)
	space.surface_clicked.connect(select)


func _process(delta: float) -> void:
	var years := clock.tick(delta)  # parado em pausa
	planet.step(years)
	materials.show_water(planet.sea_level, planet.ice)
	climate.season_t = clock.season_t
	climate.season_amp = 1.0 if clock.seasons_on else 0.0
	climate_runner.tick(delta, clock.time_scale, planet.effective_temp_c(), planet.atmosphere, planet.sea_level)
	auto_terraformer.step(planet, years)
	space.update(delta)
	colonies.apply_distance(space.distance_in_radii(SolarBodies.Id.MARS))
	_refresh_hud(delta)


func _refresh_hud(delta: float) -> void:
	control_panel.show_water(planet.liquid, planet.ice, planet.vapor, planet.vegetation)
	time_panel.show_date(space.jd)
	gauge.show_climate(planet.effective_temp_c(), planet.greenhouse_c, planet.veg_warming_c, planet.atmosphere)
	gauge.show_season(climate.ls, clock.seasons_on)
	materials.show_seasons(climate.ls, climate.season_amp, delta)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE:
		clock.toggle_pause()
	space.handle_input(e)


# --- Casos de uso: o que o jogador pode fazer, juntando mais de um módulo -------------------------------------

func set_map_mode(mode: int) -> void:
	materials.set_map_mode(mode)
	legend.show_mode(mode)


func select(n: Vector3) -> void:
	selected_dir = n.normalized()
	_show_selection()


func found_colony() -> void:
	colonies.found(selected_dir)
	materials.set_region_colors(colonies.owner_colors())
	climate.set_industry(colonies.directions())  # a colônia vira usina de chuva
	colonies.apply_distance(space.distance_in_radii(SolarBodies.Id.MARS))


## Roda `total` segundos de clima de uma vez (para pular o tempo).
func advance_climate(total: float, dt := 0.5) -> void:
	climate_runner.advance(total, dt, planet.effective_temp_c(), planet.atmosphere, planet.sea_level)


func _show_selection() -> void:
	var info := RegionInfo.describe(selected_dir, height_img, planet.sea_level, planet.atmosphere)
	control_panel.show_selection(info["text"], not info["ocean"] and not colonies.is_rival(info["region"]))


# --- Reações aos sinais ---------------------------------------------------------------------------------------

func _on_control_changed(param: String, value: float) -> void:
	control_panel.set_control_value(param, value)
	match param:
		"temperature", "atmosphere":
			materials.set_param(param, value)
	if param == "atmosphere":
		space.set_atmosphere(value)


func _on_limits_changed() -> void:
	for p in PlanetState.CONTROLS:
		control_panel.set_control_max(p, planet.control_max(p))


func _on_sea_level_changed(level: float) -> void:
	if selected_dir != Vector3.ZERO:
		_show_selection()


func _on_climate_step_finished() -> void:
	planet.vegetation = climate.mean_veg
	materials.upload_climate(climate)
