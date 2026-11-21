extends RefCounted
## O mundo como pasta portátil (Evron.world, aceite 12): exportar (cria Evron-<data>.world na pasta escolhida) e importar (confere a pasta
## antes, troca o banco e o relógio e recarrega a cena). Quem copia, confere e troca os arquivos é o Registry (RegistryWorldFile.cs).

const Registry = preload("res://scripts/world/Registry.cs")

var main  # a cena principal: o hub (banco), o caminho do banco e do relógio, o HUD onde os diálogos aparecem


func setup(main_scene) -> void:
	main = main_scene


## export = true: escolhe onde criar a pasta; false: escolhe a pasta .world a importar.
func open_dialog(export: bool) -> void:
	if not main.domains.usable or main.domains_db == ":memory:":
		return
	var files := FileDialog.new()
	files.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	files.access = FileDialog.ACCESS_FILESYSTEM
	files.use_native_dialog = true
	files.title = "Onde criar a pasta do mundo" if export else "Escolha a pasta .world a importar"
	files.dir_selected.connect(func(dir: String) -> void:
		files.queue_free()
		if export:
			export_world(dir)
		else:
			_confirm_import(dir))
	files.canceled.connect(files.queue_free)
	main.hud.add_child(files)
	files.popup_centered_ratio(0.6)


func export_world(parent: String) -> void:
	if not main.save_terrain(true):
		_message("Não deu para exportar: alterações no relevo não foram gravadas.")
		return
	main.save_clock()
	if main.territories != null and not main.territories.flush():
		_message("Não deu para exportar: alterações territoriais não foram gravadas.")
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var dir := parent.path_join("Evron-%s.world" % (stamp + "-" + str(Time.get_ticks_usec())))
	var why: String = main.domains.registry.ExportWorld(dir, _clock_path())
	_message("Mundo exportado para:\n" + dir if why == "" else "Não deu para exportar: " + why)


func _confirm_import(dir: String) -> void:
	var why: String = main.domains.registry.CheckWorld(dir)
	if why != "":
		_message("Essa pasta não pode ser importada: " + why)
		return
	var ask := ConfirmationDialog.new()
	ask.dialog_text = "Trocar o mundo aberto pelo de\n%s?\n\nO mundo atual fica guardado ao lado do banco como .antes-importacao." % dir
	ask.ok_button_text = "Importar"
	ask.confirmed.connect(func() -> void: import_world(dir))
	ask.canceled.connect(ask.queue_free)
	main.hud.add_child(ask)
	ask.popup_centered()


## Fecha o banco (gravando o que faltava), troca os arquivos e recarrega a cena: tudo é lido do mundo novo.
func import_world(dir: String) -> void:
	if not main.save_terrain(true):
		_message("Não deu para importar: o relevo do mundo atual não foi gravado.")
		return
	main.save_clock()
	main.domains.close()
	var why: String = Registry.new().ImportWorld(dir, ProjectSettings.globalize_path(main.domains_db), _clock_path())
	if why != "":
		push_error(why)
		var scene_tree := main.get_tree() as SceneTree
		scene_tree.scene_changed.connect(func() -> void:
			scene_tree.current_scene.world_files._message("Não deu para importar: " + why), CONNECT_ONE_SHOT)
	main.save_path = ""  # a cena que sai não regrava o relógio por cima do importado
	main.get_tree().reload_current_scene()


func _clock_path() -> String:
	return ProjectSettings.globalize_path(main.save_path) if main.save_path != "" else ""


func _message(text: String) -> void:
	var box := AcceptDialog.new()
	box.dialog_text = text
	box.confirmed.connect(box.queue_free)
	box.canceled.connect(box.queue_free)
	main.hud.add_child(box)
	box.popup_centered()
