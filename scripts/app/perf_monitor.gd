extends CanvasLayer
## Monitor de desempenho (F3 liga e desliga; arraste pela barra de título). Seções: quadros (com gráfico), memória, GPU, cena e as
## operações pesadas medidas com PerfMonitor.start()/stop("nome", t). Enquanto ligado, grava uma linha por segundo em user://perf.csv.

const CSV_PATH := "user://perf.csv"
const HITCH_MS := 50.0  # quadro mais longo que isto conta como travada
const GRAPH_FRAMES := 150
const GRAPH_MAX_MS := 50.0
const MB := 1.0 / 1048576.0

static var _events := {}  # nome -> {"last": ms, "max": ms, "n": int}
static var _pos := Vector2(8, 8)  # a posição sobrevive a desligar e ligar

var _panel := PanelContainer.new()
var _graph := Control.new()
var _sections := {}  # nome -> Label
var _ms: Array[float] = []  # os últimos GRAPH_FRAMES quadros
var _window: Array[float] = []  # quadros do último segundo
var _since := 0.0
var _hitches := 0
var _ram_peak := 0.0
var _csv: FileAccess
var _commands: Object  # CommandStack (opcional): bytes do histórico
var _dragging := false


static func start() -> int:
	return Time.get_ticks_usec()


static func stop(event: String, started: int) -> void:
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	var e: Dictionary = _events.get_or_add(event, {"last": 0.0, "max": 0.0, "n": 0})
	e["last"] = ms
	e["max"] = maxf(e["max"], ms)
	e["n"] += 1


func _init(commands: Object = null) -> void:
	_commands = commands
	layer = 100
	visible = false
	set_process(false)
	_panel.position = _pos
	_panel.custom_minimum_size = Vector2(330, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.88)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	# Barra de título: é a alça para arrastar.
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = Control.CURSOR_DRAG
	bar.gui_input.connect(_on_bar_input)
	var title := Label.new()
	title.text = "⠿ Monitor de desempenho   (F3)"
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	bar.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle)
	bar.add_child(close)
	box.add_child(bar)
	_graph.custom_minimum_size = Vector2(0, 46)
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graph.draw.connect(_draw_graph)
	box.add_child(_graph)
	for s in ["quadros", "memoria", "gpu", "cena", "operacoes"]:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", 12)
		_sections[s] = l
		box.add_child(l)
	add_child(_panel)


func toggle() -> void:
	visible = not visible
	set_process(visible)
	if visible:
		_csv = FileAccess.open(CSV_PATH, FileAccess.WRITE)
		if _csv != null:
			_csv.store_line("t_s,fps,fps_min,frame_ms_avg,frame_ms_max,hitches,ram_mb,ram_peak_mb,ram_free_mb,vram_mb,tex_mb,buf_mb,draws,primitives,nodes,objects,orphans,history_mb,events")
		_since = 0.0
		_window.clear()
		_clamp_to_screen()
	else:
		_csv = null  # fecha o arquivo


func _on_bar_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_dragging = e.pressed
	elif e is InputEventMouseMotion and _dragging:
		_panel.position += e.relative
		_clamp_to_screen()


func _clamp_to_screen() -> void:
	var view := _panel.get_viewport().get_visible_rect().size if _panel.is_inside_tree() else Vector2(1280, 720)
	var room := (view - _panel.size).max(Vector2.ZERO)
	_panel.position = _panel.position.clamp(Vector2.ZERO, room)
	_pos = _panel.position


func _color_for(ms: float) -> Color:
	return Color(0.35, 0.8, 0.45) if ms < 17.0 else (Color(0.95, 0.8, 0.3) if ms < 34.0 else Color(0.9, 0.3, 0.3))


func _draw_graph() -> void:
	var size := _graph.size
	_graph.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	for line: float in [16.7, 33.3]:  # 60 e 30 quadros por segundo
		var y := size.y * (1.0 - line / GRAPH_MAX_MS)
		_graph.draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.15))
	var w := size.x / GRAPH_FRAMES
	for i in _ms.size():
		var h := clampf(_ms[i] / GRAPH_MAX_MS, 0.02, 1.0) * size.y
		_graph.draw_rect(Rect2((i + GRAPH_FRAMES - _ms.size()) * w, size.y - h, maxf(w - 0.5, 1.0), h), _color_for(_ms[i]))


func _process(delta: float) -> void:
	var ms := delta * 1000.0
	_ms.append(ms)
	if _ms.size() > GRAPH_FRAMES:
		_ms.pop_front()
	_window.append(ms)
	if ms > HITCH_MS:
		_hitches += 1
	_graph.queue_redraw()
	_since += delta
	if _since < 1.0:
		return
	_since = 0.0
	_refresh_text()
	_window.clear()
	_panel.reset_size()  # encolhe quando uma seção diminui
	_clamp_to_screen()


func _refresh_text() -> void:
	var sum := 0.0
	var worst := 0.0
	for f in _window:
		sum += f
		worst = maxf(worst, f)
	var avg := sum / maxf(_window.size(), 1)
	var fps := Engine.get_frames_per_second()
	var fps_min := 1000.0 / maxf(worst, 0.001)
	var ram := OS.get_static_memory_usage() * MB
	_ram_peak = maxf(_ram_peak, ram)
	var info := OS.get_memory_info()
	var phys: float = info.get("physical", 0) * MB
	var free: float = minf(info.get("available", info.get("free", -1)) * MB, phys)  # "free" no Windows inclui o arquivo de paginação: passava do total
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) * MB
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) * MB
	var buf := Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) * MB
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var hist: float = (_commands.bytes() * MB) if _commands != null else 0.0
	var cpu := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var cpu_phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var win := DisplayServer.window_get_size()
	_sections["quadros"].text = "QUADROS\n  %d FPS (mín %d)   médio %.1f ms   pior %.1f ms\n  CPU: processo %.1f ms   física %.1f ms\n  travadas > %d ms: %d" % [
		fps, fps_min, avg, worst, cpu, cpu_phys, HITCH_MS, _hitches]
	_sections["memoria"].text = "MEMÓRIA (RAM)\n  jogo %.0f MB   pico %.0f MB   histórico %.0f MB\n  livre no sistema %.0f de %.0f MB" % [
		ram, _ram_peak, hist, free, phys]
	_sections["gpu"].text = "GPU\n  %s\n  %s   janela %dx%d\n  memória total %.0f MB   texturas %.0f   buffers %.0f\n  desenhos %d   primitivas %d" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(), win.x, win.y, vram, tex, buf, draws, prims]
	_sections["cena"].text = "CENA\n  nós %d   objetos %d   órfãos %d" % [nodes, objects, orphans]
	var ev := ""
	var lines := "OPERAÇÕES (último / pior / vezes)"
	var names := _events.keys()
	names.sort_custom(func(a, b): return _events[a]["max"] > _events[b]["max"])  # a mais pesada primeiro
	for name in names:
		var e: Dictionary = _events[name]
		ev += "%s=%.1f/%.1f/%d;" % [name, e["last"], e["max"], e["n"]]
		lines += "\n  %s: %.1f / %.1f ms / %dx" % [name, e["last"], e["max"], e["n"]]
	if names.is_empty():
		lines += "\n  (nenhuma ainda)"
	_sections["operacoes"].text = lines + "\n\nregistro: " + ProjectSettings.globalize_path(CSV_PATH)
	if _csv != null:
		_csv.store_line("%.0f,%d,%d,%.2f,%.2f,%d,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%d,%d,%d,%d,%d,%.0f,%s" % [Time.get_ticks_msec() / 1000.0,
			fps, fps_min, avg, worst, _hitches, ram, _ram_peak, free, vram, tex, buf, draws, prims, nodes, objects, orphans, hist, ev])
		_csv.flush()
