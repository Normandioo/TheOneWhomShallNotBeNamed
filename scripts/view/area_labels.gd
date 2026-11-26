extends Control
## Os nomes das áreas (cultura, etnia, raça, religião, idioma) sobre o globo, no centro de cada uma. São rótulos da interface postos na posição da tela de cada
## centro (o planeta não os esconde por profundidade: somem os do lado de trás e os das áreas pequenas demais para o zoom).

const UiKit = preload("res://scripts/ui/ui_kit.gd")

const MAX_LABELS := 80
var font_size := 18
var size_factor := 0.08       # o nome aparece quando o raio da área passa desta fração da altitude da câmera
var source_level := ""        # "pais": os nomes dos países (fixo, ligado por active_when); "" = o da área mostrada ou sobreposta
var active_when := Callable()  # só com source_level: quando os nomes aparecem

var _territories      # o TerritoryEditor
var _hub              # o DomainHub (nomes)
var _globe            # o GlobeView (raio e câmera)
var _labels: Array = []   # [{node, dir, radius_km}]
var _built_for := {}      # o nível, a versão e a instância da camada para a qual os nomes foram feitos
var _since := 0.0


func setup(territories, hub, globe) -> void:
	_territories = territories
	_hub = hub
	_globe = globe
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _territories == null:
		return
	_since += delta
	var level: String = _territories.overlay_level if _territories.area_active() else _territories.shown_kind()
	if source_level != "":
		level = source_level
	var wanted: bool = (active_when.call() if source_level != "" else level in _territories.AREA_LEVELS) and _hub.usable and not _territories.territory_stroking
	if not wanted:
		if not _labels.is_empty():
			_clear()
		return
	if _since >= 0.4 or _labels.is_empty():
		_since = 0.0
		var layer = _territories.layer(source_level if source_level != "" else level)
		var key := {"level": level, "version": layer.Version, "id": layer.get_instance_id()}
		if key != _built_for:
			_built_for = key
			_rebuild(layer)
	var cam: Camera3D = _globe.camera.cam
	var altitude: float = _globe.camera_altitude_km()
	var eye: Vector3 = cam.global_position.normalized()
	for l in _labels:
		var world: Vector3 = (l.dir as Vector3) * _globe.RADIUS
		var show: bool = l.radius_km > altitude * size_factor and (l.dir as Vector3).dot(eye) > 0.25 and not cam.is_position_behind(world)
		l.node.visible = show
		if show:
			l.node.position = cam.unproject_position(world) - l.node.size / 2.0


func _rebuild(layer) -> void:
	_clear(false)
	var centers: Dictionary = layer.Centroids()
	var rows: Array = []
	for id in centers:
		rows.append({"id": int(id), "dir": centers[id][0], "area": float(centers[id][1])})
	rows.sort_custom(func(a, b) -> bool: return a.area > b.area)
	for r in rows.slice(0, MAX_LABELS):
		var node := Label.new()
		node.text = String(_hub.registry.Name(r.id))
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_theme_font_override("font", UiKit.heading_font())
		node.add_theme_font_size_override("font_size", font_size)
		node.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
		node.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.04, 0.95))
		node.add_theme_constant_override("outline_size", 5)
		node.visible = false
		add_child(node)
		node.size = node.get_minimum_size()
		_labels.append({"node": node, "dir": (r.dir as Vector3), "radius_km": sqrt(r.area / PI)})


func _clear(reset := true) -> void:
	for l in _labels:
		l.node.queue_free()
	_labels.clear()
	if reset:
		_built_for = {}
