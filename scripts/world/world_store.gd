extends RefCounted
## Salva e lê o relógio em JSON. Grava num arquivo temporário e só então troca o salvamento, guardando o anterior
## como .bak: uma queda no meio da gravação nunca deixa o mundo sem salvamento válido.
## shortcut: JSON simples enquanto só o relógio é salvo; o banco (SQLite) da proposta o substitui com o resto do estado.

const SCHEMA := 1
const DEFAULT_PATH := "user://evron_world.json"


## Grava o relógio em path. Devolve false se não conseguiu (o salvamento anterior continua intacto).
static func save(clock, path := DEFAULT_PATH) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"schema": SCHEMA, "clock": clock.to_dict()}))
	f.close()  # fecha antes de trocar os arquivos
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(_abs(path + ".bak"))
		DirAccess.rename_absolute(_abs(path), _abs(path + ".bak"))
	return DirAccess.rename_absolute(_abs(tmp), _abs(path)) == OK


## Lê path no relógio; se estiver ausente ou estragado, tenta o .bak. false = nada válido (o relógio fica como estava).
static func load_into(clock, path := DEFAULT_PATH) -> bool:
	for p in [path, path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var json := JSON.new()  # parse() (e não parse_string) para um arquivo estragado não imprimir erro
		var data = json.data if json.parse(FileAccess.get_file_as_string(p)) == OK else null
		if data is Dictionary and data.get("schema") == SCHEMA and data.get("clock") is Dictionary \
				and clock.restore(data["clock"]):
			return true
	return false


static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)
