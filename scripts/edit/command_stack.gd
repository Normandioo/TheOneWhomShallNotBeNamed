## Pilha de desfazer e refazer. Cada comando é uma alteração rastreável já aplicada: um nome e um objeto com
## Undo(), Redo() e Bytes (por exemplo TerrainEdit, que guarda só arrays: dá para gravar como acontecimento no banco).
## Quem edita aplica a mudança e empurra o comando; a pilha só anda para trás e para frente.

signal changed

const LIMIT_BYTES := 256 * 1024 * 1024  # memória do histórico; os comandos mais antigos saem (o último fica sempre)

var _undo: Array[Dictionary] = []  # {"name": String, "cmd": Object}
var _redo: Array[Dictionary] = []
var _bytes := 0  # soma de Bytes de _undo e _redo


## Registra um comando que já foi aplicado. Um comando novo apaga o que dava para refazer.
func push(name: String, cmd: Object) -> void:
	for c in _redo:
		_bytes -= c["cmd"].Bytes
	_redo.clear()
	_undo.append({"name": name, "cmd": cmd})
	_bytes += cmd.Bytes
	while _bytes > LIMIT_BYTES and _undo.size() > 1:
		_bytes -= _undo.pop_front()["cmd"].Bytes
	changed.emit()


func undo() -> bool:
	if _undo.is_empty():
		return false
	var c: Dictionary = _undo.pop_back()
	c["cmd"].Undo()
	_redo.append(c)
	changed.emit()
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	var c: Dictionary = _redo.pop_back()
	c["cmd"].Redo()
	_undo.append(c)
	changed.emit()
	return true


## Remove comandos ligados a um cadastro excluído definitivamente.
func discard_matching(matches: Callable) -> void:
	for history in [_undo, _redo]:
		for i in range(history.size() - 1, -1, -1):
			var cmd: Object = history[i]["cmd"]
			if matches.call(cmd):
				_bytes -= cmd.Bytes
				history.remove_at(i)
	changed.emit()


## Algum comando que dá para desfazer é desse tipo (o script do objeto, como TerrainEdit.cs)? Para saber o que foi editado.
func has_undoable(script: Script) -> bool:
	for c in _undo:
		if c["cmd"].get_script() == script:
			return true
	return false


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Memória ocupada pelo histórico, em bytes.
func bytes() -> int:
	return _bytes


## Nome do comando que o próximo desfazer vai desfazer ("" se não há).
func undo_name() -> String:
	return "" if _undo.is_empty() else _undo.back()["name"]


func redo_name() -> String:
	return "" if _redo.is_empty() else _redo.back()["name"]
