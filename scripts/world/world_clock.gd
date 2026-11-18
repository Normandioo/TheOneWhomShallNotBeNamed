extends RefCounted
## O relógio oficial do mundo: o presente da campanha, a data de consulta e o coordenador dos módulos.
## Não conhece a tela: avisa por sinais. A velocidade é do mundo (Engine.time_scale também mexeria em timers).
##
## Presente × consulta: `now` é o instante oficial e só anda por avanço ou reprodução. Consultar uma data (enter_view)
## só muda `shown()`, o filtro que a interface e as camadas usam; o presente fica intacto e pausado.
##
## Contrato de um módulo (register): `step_seconds() -> int` (passo próprio, ≥ 1; 0 = só eventos) e `on_step(t: int)`,
## chamado em cada múltiplo do passo (contado desde a época) dentro de (anterior, destino]. Um avanço de 30 dias chama
## os mesmos passos que 30 avanços de 1 dia, porque os passos são do relógio e não do tamanho do avanço.
## Eventos (schedule) disparam uma vez, em (anterior, destino]. No mesmo instante: primeiro os eventos, na ordem de
## cadastro, depois os módulos, na ordem de registro. `now` vale o instante em curso durante cada chamada.

const Calendar = preload("res://scripts/world/calendar.gd")

signal time_changed         # o presente andou (depois de processar todo o intervalo)
signal state_changed        # pausa, velocidade, consulta ou eventos mudaram
signal event_fired(event: Dictionary)  # {id, at, name}

const MAX_TICK := 1.0  # s reais por quadro; evita um salto enorme depois de a janela ficar parada

var now := Calendar.to_seconds(Calendar.TECHNICAL_START_YEAR, 1, 1)  # cenário técnico de teste
var running := false          # a campanha começa pausada
var speed := Calendar.HOUR    # segundos do mundo por segundo real
var viewing := false
var view_time := 0
var scenario := "Cenário técnico de teste (não é data da história de Evron)"
var world_seed := 1           # semente do mundo (a do cenário técnico é fixa); módulos derivam as suas com derived_seed
var models := {}              # nome do modelo -> versão com que o mundo foi calculado; main.gd registra, o salvamento guarda

var _frac := 0.0              # fração de segundo acumulada na reprodução, para não perder tempo a cada quadro
var _events: Array[Dictionary] = []  # ordenado por (at, ordem de cadastro); {id, at, name, fired}
var _modules: Array[Object] = []


## Semente própria de um módulo: hash estável (SHA-256) de semente do mundo + nome. Não usa `hash()` do Godot, que não
## promete o mesmo valor entre versões; assim o mesmo mundo repete os mesmos números depois de reabrir.
func derived_seed(module_name: String) -> int:
	return ("%d:%s" % [world_seed, module_name]).sha256_buffer().decode_s64(0)


## O instante que a tela e as camadas devem mostrar.
func shown() -> int:
	return view_time if viewing else now


# --- Controles -----------------------------------------------------------------------------------------------

func play() -> void:
	if viewing or running:
		return
	running = true
	state_changed.emit()


func pause() -> void:
	if running:
		running = false
		state_changed.emit()


func set_speed(seconds_per_real_second: int) -> void:
	speed = maxi(1, seconds_per_real_second)
	state_changed.emit()


## A cada quadro, com o delta real. Parado ou em consulta não acumula nada.
func tick(real_delta: float) -> void:
	if not running or viewing:
		return
	_frac += minf(real_delta, MAX_TICK) * speed
	var whole := int(_frac)
	_frac -= whole
	if whole > 0:
		_move_to(now + whole)


## +n segundos fixos (hora, dia e semana são durações fixas). Recusado em consulta ou com n ≤ 0.
func advance_by(seconds: int) -> bool:
	if viewing or seconds <= 0:
		return false
	_move_to(now + seconds)
	return true


## +n meses do calendário (o dia se conserva quando possível). Recusado em consulta ou com n ≤ 0.
func advance_months(n: int) -> bool:
	return n > 0 and advance_by(Calendar.add_months(now, n) - now)


## Leva o presente até t, processando tudo o que vence no caminho. Só para o futuro.
func advance_to(t: int) -> bool:
	return advance_by(t - now)


func enter_view(t: int) -> void:
	running = false
	viewing = true
	view_time = t
	state_changed.emit()


## Sai da consulta e mostra o presente. Continua pausado até o usuário retomar.
func exit_view() -> void:
	if viewing:
		viewing = false
		state_changed.emit()


# --- Módulos e eventos ---------------------------------------------------------------------------------------

func register(module: Object) -> void:
	_modules.append(module)


## Cadastra um evento futuro. Recusa id repetido e instante que não seja depois do presente.
func schedule(id: String, at: int, event_name: String) -> bool:
	if at <= now or _events.any(func(e: Dictionary) -> bool: return e["id"] == id):
		return false
	var i := _events.size()
	while i > 0 and _events[i - 1]["at"] > at:  # estável: iguais ficam na ordem de cadastro
		i -= 1
	_events.insert(i, {"id": id, "at": at, "name": event_name, "fired": false})
	state_changed.emit()
	return true


func events() -> Array[Dictionary]:
	return _events


# --- Estado para salvar --------------------------------------------------------------------------------------

## O que vai para o disco: o presente, a velocidade e os eventos (com o que já disparou). Não vai: a consulta e
## a pausa (a campanha sempre abre pausada), nem os módulos (quem os registra é o código, a cada abertura).
func to_dict() -> Dictionary:
	return {"calendar_version": Calendar.VERSION, "now": now, "frac": _frac, "speed": speed,
		"scenario": scenario, "world_seed": world_seed, "models": models.duplicate(), "events": _events.duplicate(true)}


## Restaura de um to_dict. Recusa (sem mudar nada) um calendário de outra versão ou dados malformados.
## A ordem salva (já por instante, com a ordem de cadastro entre iguais) é mantida. Não avança o tempo: o período em que o programa ficou fechado não conta.
func restore(d: Dictionary) -> bool:
	if d.get("calendar_version") != Calendar.VERSION or not d.has_all(["now", "frac", "speed", "events"]):
		return false
	var events: Array[Dictionary] = []
	for e in d["events"]:
		if not (e is Dictionary and e.has_all(["id", "at", "name", "fired"])):
			return false
		events.append({"id": str(e["id"]), "at": int(e["at"]), "name": str(e["name"]), "fired": bool(e["fired"])})
	now = int(d["now"])
	_frac = float(d["frac"])
	speed = maxi(1, int(d["speed"]))
	scenario = str(d.get("scenario", scenario))
	world_seed = int(d.get("world_seed", world_seed))
	var saved_models = d.get("models", {})
	models = saved_models.duplicate() if saved_models is Dictionary else {}
	_events = events
	running = false
	viewing = false
	state_changed.emit()
	time_changed.emit()
	return true


# --- Processamento do intervalo -------------------------------------------------------------------------------

func _move_to(target: int) -> void:
	var from := now
	while true:
		var t := target
		var e := _first_unfired()
		if e >= 0 and _events[e]["at"] > from:
			t = mini(t, _events[e]["at"])
		for m in _modules:
			var step: int = m.step_seconds()
			if step > 0:
				t = mini(t, (Calendar.floordiv(from, step) + 1) * step)
		now = t
		# `<= t` (e não `== t`): um evento atrasado, vindo de um salvamento editado, dispara no primeiro limite.
		# O índice é buscado de novo a cada disparo: um ouvinte pode cadastrar outro evento.
		e = _first_unfired()
		while e >= 0 and _events[e]["at"] <= t:
			_events[e]["fired"] = true
			event_fired.emit({"id": _events[e]["id"], "at": _events[e]["at"], "name": _events[e]["name"]})
			e = _first_unfired()
		for m in _modules:
			var step: int = m.step_seconds()
			if step > 0 and posmod(t, step) == 0:
				m.on_step(t)
		if t >= target:
			break
		from = t
	time_changed.emit()


## Índice do primeiro evento ainda não disparado (a lista é ordenada por instante), ou -1.
## shortcut: busca linear a cada limite; com milhares de eventos, guardar um ponteiro.
func _first_unfired() -> int:
	for i in _events.size():
		if not _events[i]["fired"]:
			return i
	return -1
