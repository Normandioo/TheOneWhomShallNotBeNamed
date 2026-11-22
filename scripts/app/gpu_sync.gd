extends RefCounted
## Leva o que mudou no mundo para a GPU, uma vez por quadro: altitude, rios, camada política e a costa do mapa político.
## Durante a pincelada limita a frequência (altitude e política, no máximo 10x por segundo; rios e costa só ao soltar o mouse).

const PerfMonitor = preload("res://scripts/app/perf_monitor.gd")

const UPLOAD_SECONDS := 0.1

var coast_stale := true  # a costa do mapa político está atrasada em relação à altitude
var _terrain
var _brush
var _material
var _territories
var _since_upload := 0.0
var _since_political := 0.0
var _coast_task := -1  # tarefa da thread que calcula a costa (-1 = nenhuma)
var _coast_started := 0
var _coast_image: Image


func _init(terrain, brush, material, territories) -> void:
	_terrain = terrain
	_brush = brush
	_material = material
	_territories = territories


## Há costa sendo calculada ou pedida? (os testes esperam isso acabar)
func coast_pending() -> bool:
	return coast_stale or _coast_task != -1


func tick(delta: float) -> void:
	_since_upload += delta
	if _terrain.Dirty and (not _brush.active or _since_upload >= UPLOAD_SECONDS):
		var t_h := PerfMonitor.start()
		_material.refresh_height(_terrain.HeightImage())
		PerfMonitor.stop("altura->GPU", t_h)
		_terrain.Dirty = false
		_since_upload = 0.0
		coast_stale = true
	_tick_coast()
	# Só as camadas mostradas (a do nível e as de cima) vão à GPU, compostas; durante a pincelada, no máximo 10x por segundo (16 MiB).
	if (not _territories.territory_stroking or _since_political >= UPLOAD_SECONDS) and _territories.political_dirty():
		var t_p := PerfMonitor.start()
		_material.refresh_political(_territories.political_image())
		PerfMonitor.stop("político->GPU", t_p)
		_since_political = 0.0
	_since_political += delta
	if _terrain.RiversDirty and not _brush.active:  # os rios só mudam ao soltar o mouse, desfazer ou refazer
		_material.refresh_rivers(_terrain.RiversImage())
		_terrain.RiversDirty = false


## A costa de todas as camadas leva ~1 s: calculada numa thread, fora da pincelada. Uma edição durante o cálculo pede outro depois.
func _tick_coast() -> void:
	if _coast_task != -1 and WorkerThreadPool.is_task_completed(_coast_task):
		WorkerThreadPool.wait_for_task_completion(_coast_task)
		_coast_task = -1
		PerfMonitor.stop("costa", _coast_started)
		if _coast_image != null:  # null = sem memória: fica a anterior
			_material.set_coast(_coast_image)
		_coast_image = null
	if coast_stale and _coast_task == -1 and not _brush.active:
		coast_stale = false
		_coast_started = PerfMonitor.start()
		_coast_task = WorkerThreadPool.add_task(func() -> void: _coast_image = _terrain.CoastImage())
