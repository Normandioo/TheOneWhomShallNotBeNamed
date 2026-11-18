extends SceneTree
## Executor do autoteste: roda as suítes de tests/suites/ na ordem e salva capturas de tela.
## Rodar (com janela, para as capturas): godot --path . -s tests/shot.gd -- <pasta_das_capturas>
## As suítes sem cena rodam primeiro; as com cena dividem a mesma instância do programa, nesta ordem,
## porque cada uma parte do estado deixado pela anterior. A primeira falha para tudo.

const HEADLESS_SUITES := [
	"res://tests/suites/geo_suite.gd",
	"res://tests/suites/edit_suite.gd",
]
const SCENE_SUITES := [
	"res://tests/suites/globe_suite.gd",
	"res://tests/suites/tiles_suite.gd",
	"res://tests/suites/brush_suite.gd",
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
