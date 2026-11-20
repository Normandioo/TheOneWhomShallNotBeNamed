extends Node
## Importar PNG para a camada territorial: escolher o arquivo e mapear cada REGIÃO (mancha conectada de uma cor) para uma entidade
## do nível, ou ignorar. Manchas separadas da mesma cor são linhas separadas: a mesma cor não é assumida como a mesma entidade.
## Só mostra e pede: quem analisa e aplica é o DomainHub.

const LayerPanel = preload("res://scripts/ui/layer_panel.gd")  # só para o separador de milhares
const MAX_ROWS := 300  # as maiores; o resto não é importado (fica dito na janela)

signal file_chosen(path: String)
signal apply_requested(indices: PackedInt32Array, owners: PackedInt32Array)
signal focus_requested(lat: float, lon: float)

var _files: FileDialog
var _dialog: ConfirmationDialog
var _rows: VBoxContainer
var _note: Label
var _picks: Array = []  # [região, OptionButton, ids do menu]


func _ready() -> void:
	_files = FileDialog.new()
	_files.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_files.access = FileDialog.ACCESS_FILESYSTEM
	_files.filters = PackedStringArray(["*.png ; Imagem PNG"])
	_files.title = "Importar território de um PNG"
	_files.use_native_dialog = true
	_files.file_selected.connect(file_chosen.emit)
	add_child(_files)
	_dialog = ConfirmationDialog.new()
	_dialog.title = "Mapear regiões do PNG"
	_dialog.ok_button_text = "Aplicar"
	_dialog.cancel_button_text = "Cancelar"
	_dialog.min_size = Vector2i(560, 480)
	_dialog.confirmed.connect(_apply)
	var box := VBoxContainer.new()
	_dialog.add_child(box)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	add_child(_dialog)


func pick_file() -> void:
	_files.popup_centered_ratio(0.6)


## regions: [{index, rgb, area_km2, lat, lon}] (as maiores primeiro). entities: [{id, name, rgb}] do nível. A sugestão é a entidade de
## mesma cor (o autor costuma pintar com as cores do cadastro); sem cor igual, "Ignorar".
func show_regions(regions: Array, entities: Array, level_label: String) -> void:
	for c in _rows.get_children():
		c.queue_free()
	_picks.clear()
	var by_rgb := {}
	for e in entities:
		by_rgb[int(e.rgb)] = int(e.id)
	var shown := regions.slice(0, MAX_ROWS)
	_note.text = "%d regiões encontradas%s. Escolha a %s de cada uma; \"Ignorar\" deixa o mapa como está ali. Aplicar é um passo só (Ctrl+Z desfaz)." % [
		regions.size(), " (só as %d maiores entram)" % MAX_ROWS if regions.size() > MAX_ROWS else "", level_label.to_lower()]
	for r in shown:
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = Color8((int(r.rgb) >> 16) & 255, (int(r.rgb) >> 8) & 255, int(r.rgb) & 255)
		swatch.custom_minimum_size = Vector2(22, 22)
		row.add_child(swatch)
		var info := Label.new()
		info.text = "≈ %s km²  (%.1f°, %.1f°)" % [LayerPanel._thousands(roundi(r.area_km2)), r.lat, r.lon]
		info.custom_minimum_size = Vector2(210, 0)
		row.add_child(info)
		var menu := OptionButton.new()
		menu.fit_to_longest_item = false
		menu.custom_minimum_size = Vector2(200, 0)
		var ids: Array = [-1, 0]
		menu.add_item("Ignorar")
		menu.add_item("Apagar (sem dono)")
		for e in entities:
			ids.append(int(e.id))
			menu.add_item(String(e.name))
		var suggested: int = ids.find(by_rgb.get(int(r.rgb), -1))
		menu.select(maxi(suggested, 0))
		row.add_child(menu)
		var go := Button.new()
		go.text = "Ver"
		go.tooltip_text = "Leva a câmera até esta região"
		var lat: float = r.lat
		var lon: float = r.lon
		go.pressed.connect(func() -> void: focus_requested.emit(lat, lon))
		row.add_child(go)
		_rows.add_child(row)
		_picks.append([int(r.index), menu, ids])
	_dialog.popup_centered()


func _apply() -> void:
	var indices := PackedInt32Array()
	var owners := PackedInt32Array()
	for p in _picks:
		var owner: int = p[2][p[1].selected]
		if owner >= 0:
			indices.append(p[0])
			owners.append(owner)
	apply_requested.emit(indices, owners)
