extends SceneTree
## Executor do autoteste: roda as suítes de tests/suites/ na ordem e salva capturas de tela.
## Rodar (com janela, para as capturas): godot --path . -s tests/shot.gd -- <pasta_das_capturas>
## As suítes sem cena rodam primeiro; as com cena dividem a mesma instância do programa, nesta ordem,
## porque cada uma parte do estado deixado pela anterior. A primeira falha para tudo.

const HEADLESS_SUITES := [
	"res://tests/suites/core_suite.gd",
	"res://tests/suites/geo_suite.gd",
	"res://tests/suites/edit_suite.gd",
	"res://tests/suites/db_suite.gd",
	"res://tests/suites/registry_suite.gd",
	"res://tests/suites/sheet_suite.gd",
	"res://tests/suites/hub_suite.gd",
	"res://tests/suites/local_calendar_suite.gd",
	"res://tests/suites/calendar_use_suite.gd",
	"res://tests/suites/place_suite.gd",
	"res://tests/suites/regression_suite.gd",
	"res://tests/suites/border_suite.gd",
	"res://tests/suites/draw_suite.gd",
	"res://tests/suites/territory_suite.gd",
	"res://tests/suites/paint_suite.gd",
	"res://tests/suites/calendar_suite.gd",
]
const SCENE_SUITES := [
	"res://tests/suites/globe_suite.gd",
	"res://tests/suites/tiles_suite.gd",
	"res://tests/suites/brush_suite.gd",
	"res://tests/suites/brush_gallery_suite.gd",
	"res://tests/suites/time_suite.gd",
	"res://tests/suites/hub_suite.gd",  # com a cena: o hub segue o relógio
	"res://tests/suites/draw_suite.gd",  # com a cena: Main.select no modo desenhar
	"res://tests/suites/paint_suite.gd",  # com a cena: o shader e o Main levam a camada política à GPU
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
	main.domains_db = ":memory:"  # os cadastros do usuário não entram nos testes
	main.save_path = ""  # o teste não lê nem grava o salvamento do usuário
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
