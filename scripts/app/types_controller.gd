extends RefCounted
## O designer de tipos (E2): cria tipos de entidade, campos (com validação), camadas do mapa e tipos de vínculo. Quem grava é o Registry;
## depois de cada criação, os menus de tipo, as camadas de presença e a ficha aberta se refazem.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

var hub                    # o DomainHub: o banco, a busca, o mapa de presenças, reler a ficha
var registry
var types_panel


## Liga o designer ao hub: tipos de entidade, campos com validação, camadas do mapa e tipos de vínculo, sem mudar código.
func setup(domain_hub, panel) -> void:
	hub = domain_hub
	registry = hub.registry
	types_panel = panel
	if not hub.usable:
		return
	hub.search.types_requested.connect(panel.open_dialog)
	panel.show_types(registry.EntityTypes())
	panel.type_requested.connect(func(label: String) -> void:
		if label.strip_edges() == "":
			panel.show_message("Dê um nome ao tipo.")
			return
		_types_done(registry.CreateEntityType(label), "Tipo \"%s\" criado: já aparece em \"＋ Novo\"." % label.strip_edges(),
			"Não deu para criar o tipo (já existe um com esse nome?)."))
	panel.field_requested.connect(_on_field_requested)
	panel.layer_requested.connect(func(label: String, rgb: int, kinds: PackedStringArray) -> void:
		if label.strip_edges() == "" or kinds.is_empty():
			panel.show_message("Dê um nome à camada e marque ao menos um tipo.")
			return
		_types_done(registry.CreateMapLayer(label, rgb, kinds), "Camada \"%s\" criada: aparece em Presenças no mapa." % label.strip_edges(),
			"Não deu para criar a camada (já existe uma com esse nome?)."))
	panel.relation_requested.connect(func(out_label: String, in_label: String, src: String, dst: String) -> void:
		if out_label.strip_edges() == "" or in_label.strip_edges() == "":
			panel.show_message("Escreva o nome do vínculo nas duas pontas.")
			return
		_types_done(registry.CreateRelationType(out_label, in_label, src, dst), "Vínculo \"%s\" criado: aparece na ficha em Vínculos." % out_label.strip_edges(),
			"Não deu para criar o vínculo."))


func _on_field_requested(label: String, type: String, unit: String, options: String, min_value: float, max_value: float, kinds: PackedStringArray) -> void:
	if label.strip_edges() == "" or kinds.is_empty():
		types_panel.show_message("Dê um nome ao campo e marque ao menos um tipo.")
		return
	if not is_nan(min_value) and not is_nan(max_value) and min_value > max_value:
		types_panel.show_message("O mínimo é maior que o máximo.")
		return
	var code = registry.AddField(label, type, unit, options, kinds)
	if code != null and type == "number" and (not is_nan(min_value) or not is_nan(max_value)):
		registry.SetFieldLimits(code, min_value, max_value)
	_types_done(code, "Campo \"%s\" criado." % label.strip_edges(), "Não deu para criar o campo (escolha precisa de 2 opções).")


func _types_done(result, ok_text: String, fail_text: String) -> void:
	if result == null:
		types_panel.show_message(fail_text)
		return
	types_panel.show_message(ok_text)
	types_panel.clear_inputs()
	UiKit.set_types(registry.EntityTypes())
	UiKit.set_layers(registry.MapLayers())
	hub.search.refresh_kinds()
	if hub.presence_panel != null:
		hub.presence_panel.refresh_layers()
		hub.redraw_map()
	types_panel.show_types(registry.EntityTypes())
	hub.refresh_sheet()
