## Pilha de desfazer e refazer. Cada comando é uma alteração rastreável: nome, como desfazer e como refazer.
## Quem edita aplica a mudança e empurra o comando já feito; a pilha só anda para trás e para frente.
## (A persistência vai gravar estes mesmos comandos como acontecimentos com data: ver o Modelo de Dados.)

signal changed

const LIMIT := 200  # comandos guardados; os mais antigos saem (cada pincelada guarda só os pixels que mexeu)

var _undo: Array[Dictionary] = []  # {"name": String, "undo": Callable, "redo": Callable}
var _redo: Array[Dictionary] = []


## Registra um comando que já foi aplicado. Um comando novo apaga o que dava para refazer.
func push(name: String, undo: Callable, redo: Callable) -> void:
	_undo.append({"name": name, "undo": undo, "redo": redo})
	_redo.clear()
	if _undo.size() > LIMIT:
		_undo.pop_front()
	changed.emit()


func undo() -> bool:
	if _undo.is_empty():
		return false
	var c: Dictionary = _undo.pop_back()
	c["undo"].call()
	_redo.append(c)
	changed.emit()
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	var c: Dictionary = _redo.pop_back()
	c["redo"].call()
	_undo.append(c)
	changed.emit()
	return true


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Nome do comando que o próximo desfazer vai desfazer ("" se não há).
func undo_name() -> String:
	return "" if _undo.is_empty() else _undo.back()["name"]


func redo_name() -> String:
	return "" if _redo.is_empty() else _redo.back()["name"]
