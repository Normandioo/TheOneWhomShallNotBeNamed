extends SceneTree
## Roda UMA suíte (para iterar rápido): godot --path . -s tests/run_suite.gd -- tests/suites/x_suite.gd <pasta_das_capturas>
## A suíte falha se chamar fail() ou se houver um erro de SCRIPT durante ela (um erro de script interrompe a função em silêncio e,
## sem isto, a suíte terminava "verde" sem ter rodado o resto). Os ERROR esperados das recusas do C# são de outro tipo e não contam.


## Conta os erros de script (ERROR_TYPE_SCRIPT) registrados enquanto a suíte roda.
class ScriptErrors extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" and not "visivel" in args:  # a janela desenha fora da tela e sem pegar o foco
		root.mode = Window.MODE_WINDOWED
		root.unfocusable = true
		await process_frame  # sair do maximizado leva um quadro: antes disso a posição é ignorada
		root.position = Vector2i(-20000, -20000)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED  # os testes mandam o mouse em pixels da janela: sem a escala do projeto (canvas_items)
	var script := load("res://" + args[0]) as GDScript
	if script == null or not script.can_instantiate():
		push_error("não consegui carregar a suíte " + args[0])  # sem isto o executor ficaria parado para sempre
		quit(1)
		return
	var errors := ScriptErrors.new()
	OS.add_logger(errors)
	var out: String = args[1] if args.size() > 1 else OS.get_user_data_dir()
	var main: Node = null
	if args.size() > 2 and args[2] == "scene":
		main = load("res://scenes/main.tscn").instantiate()
		main.domains_db = ":memory:"  # os cadastros do usuário não entram nos testes
		main.save_path = ""  # o teste não lê nem grava o salvamento do usuário
		main.options_path = ""  # nem as opções dele, e nenhum tutorial se oferece sozinho
		root.add_child(main)
	var suite = script.new()
	suite.setup(self, main, out)
	await suite.run()
	OS.remove_logger(errors)
	if errors.count > 0:
		printerr("FALHOU: %d erro(s) de script durante a suíte (ela pode ter parado no meio)" % errors.count)
	quit(1 if suite.failed or errors.count > 0 else 0)
