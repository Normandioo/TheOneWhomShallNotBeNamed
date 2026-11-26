extends RefCounted
## A janela de regras (E3): monta, valida, grava, executa na data mostrada pelo relógio e fixa valores. Quem valida e executa é o Registry.

const Calendar = preload("res://scripts/world/calendar.gd")
const Rules = preload("res://scripts/world/rules.gd")

var hub                    # o DomainHub: o banco, a data mostrada, reler a ficha
var registry
var rules_panel


## Liga a janela de regras ao hub: montar, executar na data mostrada e fixar valores.
func setup(domain_hub, panel) -> void:
	hub = domain_hub
	registry = hub.registry
	rules_panel = panel
	if not hub.usable:
		return
	hub.search.rules_requested.connect(func() -> void:
		_refresh_rules_panel()
		panel.open_dialog())
	panel.kind_selected.connect(func(kind: String) -> void:
		panel.show_inputs(_numeric_fields(kind), registry.LinkTypesFor(kind), registry.Outline(hub.shown_t)))
	panel.save_requested.connect(func(rule_id: int, rule_name: String, definition: String) -> void:
		if rule_name.strip_edges() == "":
			panel.show_message("Dê um nome à regra.")
			return
		var why: String = registry.ValidateRule(definition)
		if why != "":
			panel.show_message("A regra não vale: " + why)
			return
		var saved = registry.SaveRule(rule_id, rule_name, definition)
		if saved == null:
			panel.show_message("Não deu para salvar a regra.")
			return
		panel.saved(int(saved))
		panel.show_message("Regra salva%s." % (" (versão nova)" if rule_id != 0 else ""))
		_refresh_rules_panel()
		hub.refresh_sheet())
	panel.run_requested.connect(func(rule_id: int) -> void:
		var result = registry.RunRule(rule_id, hub.shown_t)
		if result == null:
			panel.show_message("A regra não executou (está desativada?).")
			return
		result["when"] = _when()
		panel.show_run(result, rule_id))
	panel.mode_requested.connect(func(rule_id: int, _mode: String) -> void:
		for r in registry.Rules():
			if int(r.id) == rule_id:
				var modes: Array = panel.MODES
				registry.SetRuleMode(rule_id, modes[(modes.find(r.mode) + 1) % modes.size()])
		_refresh_rules_panel()
		hub.refresh_sheet())
	panel.pin_requested.connect(func(entity_id: int, code: String, value: float, reason: String) -> void:
		if registry.PinField(entity_id, code, value, hub.shown_t, 9223372036854775807, reason) == null:
			panel.show_message("Não deu para fixar esse valor.")
		else:
			panel.show_message("%s fixado em %s a partir de %s. Execute de novo: a regra respeita o valor fixado." % [
				registry.Name(entity_id), str(value), _when()])
			hub.refresh_sheet())


func _numeric_fields(kind: String) -> Array:
	return registry.FieldsFor(kind).filter(func(f): return f.type == "number")


func _refresh_rules_panel() -> void:
	var kinds: Array = []
	for t in registry.EntityTypes():
		if not _numeric_fields(String(t.code)).is_empty():
			kinds.append(String(t.code))
	rules_panel.show_kinds(kinds)
	var rules: Array = []
	for r in registry.Rules():
		var def = JSON.parse_string(r.definition)
		var names := {}
		for f in registry.FieldsFor(def.kind):
			names[f.code] = f.label
		for l in registry.LinkTypesFor(def.kind):
			names[l.code] = l.label
		for e in registry.Outline(hub.shown_t):
			names["#%d" % int(e.id)] = e.name
		var row: Dictionary = r.duplicate()
		row["text"] = "%s = %s" % [names.get(def.field, def.field), Rules.describe(def.expr, names)]
		rules.append(row)
	rules_panel.show_rules(rules)


func _when() -> String:
	return Calendar.format(hub.shown_t, false) if hub.has_clock else str(hub.shown_t)
