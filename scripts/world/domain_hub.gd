extends RefCounted
## Liga os painéis de cadastro ao Registry: cada sinal do painel vira uma chamada ao núcleo, e o que o núcleo devolve volta
## para o painel. Não tem regra de mundo (quem valida e grava é o Registry) e não conhece o globo.
## Quem o cria precisa guardar uma referência (os sinais dos painéis só guardam funções deste objeto).

const UiKit = preload("res://scripts/ui/ui_kit.gd")

## Instante em que as fichas são lidas. Sem o relógio do mundo nesta ramificação, é "o que não tem fim"; quando o relógio
## existir, quem o liga troca este valor pela data mostrada.
var shown_t := 9223372036854775806

var registry
var search
var sheet
var _current := 0


## db_path: arquivo do banco ("user://..." é traduzido) ou ":memory:" nos testes.
func setup(db_path: String, search_panel, sheet_panel) -> void:
	registry = load("res://scripts/world/Registry.cs").new()
	registry.Open(db_path if db_path == ":memory:" else ProjectSettings.globalize_path(db_path))
	search = search_panel
	sheet = sheet_panel
	search.query_changed.connect(func(_t: String, _k: String) -> void: refresh_search())
	search.entity_chosen.connect(open)
	search.create_requested.connect(_on_create)
	search.society_requested.connect(_on_society)
	sheet.name_changed.connect(func(t: String) -> void:
		registry.Correct(_current, t)
		refresh_search())
	sheet.summary_changed.connect(func(t: String) -> void: registry.SetSummary(_current, t))
	sheet.field_edited.connect(_on_field)
	sheet.alias_added.connect(func(role: String, n: String) -> void:
		registry.AddName(_current, n, role, 0)
		_reload())
	sheet.tag_added.connect(func(t: String) -> void:
		registry.AddTag(_current, t)
		_reload())
	sheet.tag_removed.connect(func(t: String) -> void:
		registry.RemoveTag(_current, t)
		_reload())
	sheet.link_added.connect(func(type: String, other: int) -> void:
		registry.Link(_current, other, type)
		_reload())
	sheet.link_removed.connect(func(id: int) -> void:
		registry.DeleteLink(id)
		_reload())
	sheet.link_search.connect(_on_link_search)
	sheet.open_entity.connect(open)
	sheet.duplicate_requested.connect(func(copy_links: bool) -> void:
		open(registry.Duplicate(_current, copy_links, "")))
	sheet.delete_requested.connect(func() -> void:
		sheet.confirm_delete(registry.Name(_current), registry.AffectedLinks(_current)))
	sheet.delete_confirmed.connect(_on_delete)
	sheet.closed.connect(func() -> void: _current = 0)
	refresh_search()


func close() -> void:
	registry.Close()


func current() -> int:
	return _current


func open(id: int) -> void:
	_current = id
	_reload()


func refresh_search() -> void:
	search.show_results(registry.Search(search.query(), search.kind_filter(), "", 0, shown_t), _current)


# --- tratadores ---------------------------------------------------------------------------------------------------

func _on_create(kind: String, name: String) -> void:
	var text := name.strip_edges()
	open(registry.Create(kind, text if text != "" else "Sem nome (%s)" % UiKit.kind_label(kind)))


func _on_society(name: String) -> void:
	var text := name.strip_edges()
	var ids: Array = registry.CreateSociety(text if text != "" else "Sem nome", PackedStringArray(["pais", "cultura", "etnia"]))
	open(ids[0])  # a ficha do país; as outras abrem pelas relações


func _on_field(code: String, state: String, value: String) -> void:
	registry.SetField(_current, code, state, value)
	var now: Dictionary = registry.GetField(_current, code)
	sheet.update_field(code, now.state, now.value)  # mostra o que ficou (corrige o que foi recusado)


func _on_link_search(text: String, dst_kind: String) -> void:
	sheet.show_link_candidates(registry.Search(text, dst_kind, "", 0, shown_t))


func _on_delete() -> void:
	registry.Delete(_current)
	_current = 0
	sheet.hide_sheet()
	refresh_search()


## Relê a ficha atual e refaz a lista de busca.
func _reload() -> void:
	var s: Dictionary = registry.Sheet(_current, shown_t)
	sheet.show_sheet(s, registry.LinkTypesFor(s.kind))
	refresh_search()
