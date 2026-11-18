extends SceneTree
## Roda UMA suíte (para iterar rápido): godot --path . -s tests/run_suite.gd -- tests/suites/x_suite.gd <pasta_das_capturas>
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var script := load("res://" + args[0]) as GDScript
	if script == null or not script.can_instantiate():
		push_error("não consegui carregar a suíte " + args[0])  # sem isto o executor ficaria parado para sempre
		quit(1)
		return
	var out: String = args[1] if args.size() > 1 else OS.get_user_data_dir()
	var main: Node = null
	if args.size() > 2 and args[2] == "scene":
		main = load("res://scenes/main.tscn").instantiate()
		main.domains_db = ":memory:"  # os cadastros do usuário não entram nos testes
		main.save_path = ""  # o teste não lê nem grava o salvamento do usuário
		root.add_child(main)
	var suite = script.new()
	suite.setup(self, main, out)
	await suite.run()
	quit(1 if suite.failed else 0)
