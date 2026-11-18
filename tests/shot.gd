extends SceneTree
## Executor do autoteste do Protótipo 0: roda as suítes de tests/suites/ na ordem e salva capturas de tela.
## Rodar: godot --path E:\ProjetoMarte -s tests/shot.gd -- <pasta_das_capturas>
## As suítes sem cena rodam primeiro (rápido e sem janela); as com cena dividem a mesma instância do jogo,
## nesta ordem, porque cada uma parte do estado deixado pela anterior. A primeira falha para tudo.

const HEADLESS_SUITES := [
	"res://tests/suites/physics_suite.gd",
	"res://tests/suites/simulation_suite.gd",
	"res://tests/suites/space_physics_suite.gd",
]
const SCENE_SUITES := [
	"res://tests/suites/water_cycle_suite.gd",
	"res://tests/suites/map_views_suite.gd",
	"res://tests/suites/input_suite.gd",
	"res://tests/suites/climate_suite.gd",
	"res://tests/suites/extremes_suite.gd",
	"res://tests/suites/industry_suite.gd",
	"res://tests/suites/time_suite.gd",
	"res://tests/suites/space_view_suite.gd",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	for path in HEADLESS_SUITES:
		if not await _run_suite(path, null, out):
			return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for path in SCENE_SUITES:
		if not await _run_suite(path, main, out):
			return
	quit(0)


## Roda uma suíte; se falhar, encerra o programa com erro e devolve false.
func _run_suite(path: String, main: Node, out: String) -> bool:
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		push_error("não consegui carregar a suíte " + path)  # sem isto o executor ficaria parado para sempre
		quit(1)
		return false
	var suite = script.new()
	suite.setup(self, main, out)
	await suite.run()
	if suite.failed:
		quit(1)
	return not suite.failed
