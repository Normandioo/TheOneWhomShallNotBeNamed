extends "res://tests/test_suite.gd"
## O calendário e o relógio, sem cena: conversões e regras de data, pausa e velocidade, presente × consulta,
## eventos e passos de módulos em avanços grandes, salvamento e a camada demonstrativa.

const Calendar = preload("res://scripts/world/calendar.gd")
const WorldClock = preload("res://scripts/world/world_clock.gd")
const WorldStore = preload("res://scripts/world/world_store.gd")
const DemoModule = preload("res://scripts/world/demo_module.gd")
const SeasonalTemperature = preload("res://scripts/world/seasonal_temperature.gd")
const EvronMaps = preload("res://scripts/data/evron_maps.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")

const D := Calendar.DAY


## Módulo de teste: anota cada passo que o relógio manda e confere que o presente vale o instante do passo.
class Recorder:
	var every := 0
	var log: Array[int] = []
	var clock
	var consistent := true

	func step_seconds() -> int:
		return every

	func on_step(t: int) -> void:
		consistent = consistent and clock.now == t
		log.append(t)


func run() -> void:
	if not _dates() or not _rules() or not _playback() or not _view() or not _events() or not _persistence() or not _demo() or not _seasonal() or not _seeds():
		return
	ok("calendário completo")


func _dates() -> bool:
	if Calendar.YEAR != 31_536_000 or Calendar.YEAR_DAYS * Calendar.DAY != Calendar.YEAR:
		return _fail("o ano deveria ter 365 dias = 31.536.000 s")
	var days := 0
	for m in Calendar.MONTH_DAYS:
		days += m
	if days != 365:
		return _fail("os 12 meses somam %d dias, não 365" % days)
	# Ida e volta em todo dia de alguns anos (inclusive negativos) e no último segundo de cada dia.
	for year in [-401, -1, 0, 1, 4, 100, 400, 2000]:
		for doy in 365:
			var t: int = year * Calendar.YEAR + doy * D + 86399
			var d := Calendar.from_seconds(t)
			if Calendar.to_seconds(d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]) != t or d["year"] != year:
				return _fail("ida e volta falhou em ano %d, dia %d: %s" % [year, doy, d])
	# Datas inválidas: não há 29 de fevereiro, 31 de abril, mês 13, hora 24...
	for bad in [[1, 2, 29], [4, 2, 29], [400, 2, 29], [1, 4, 31], [1, 13, 1], [1, 0, 1], [1, 1, 0], [1, 1, 32]]:
		if Calendar.valid(bad[0], bad[1], bad[2]) or Calendar.to_seconds(bad[0], bad[1], bad[2]) != Calendar.INVALID:
			return _fail("%s deveria ser rejeitada" % [bad])
	if Calendar.valid(1, 1, 1, 24) or Calendar.valid(1, 1, 1, 0, 60) or Calendar.valid(1, 1, 1, 0, 0, 60):
		return _fail("hora 24, minuto 60 e segundo 60 não existem")
	if not Calendar.valid(1, 12, 31, 23, 59, 59) or not Calendar.valid(1, 2, 28):
		return _fail("31 de dezembro 23:59:59 e 28 de fevereiro existem")
	# 28 de fevereiro -> 1º de março em todo ano, também os divisíveis por 4, 100 e 400 e os negativos.
	for year in [-4, -1, 0, 1, 3, 4, 100, 400, 1900, 2000]:
		var d := Calendar.from_seconds(Calendar.to_seconds(year, 2, 28) + D)
		if d["month"] != 3 or d["day"] != 1 or d["year"] != year:
			return _fail("28/fev + 1 dia no ano %d deu %s" % [year, d])
	# A virada do ano incrementa o ano; e 365 dias voltam ao mesmo dia e horário do ano seguinte.
	var nye := Calendar.from_seconds(Calendar.to_seconds(7, 12, 31, 23, 59, 59) + 1)
	if nye["year"] != 8 or nye["month"] != 1 or nye["day"] != 1 or nye["hour"] != 0:
		return _fail("31 dez 23:59:59 + 1 s deveria ser 1º jan do ano 8: %s" % nye)
	var t0 := Calendar.to_seconds(3, 7, 19, 14, 30, 5)
	var back := Calendar.from_seconds(t0 + 365 * D)
	if back["year"] != 4 or back["month"] != 7 or back["day"] != 19 or back["hour"] != 14 or back["minute"] != 30 or back["second"] != 5:
		return _fail("+365 dias deveria voltar ao mesmo dia no ano seguinte: %s" % back)
	if Calendar.add_years(t0, 1) != t0 + 365 * D or Calendar.add_years(t0, -2) != t0 - 2 * Calendar.YEAR:
		return _fail("1 ano são sempre 365 dias")
	# Âncoras do exemplo sazonal: 181 dias de 15 jan a 15 jul, 184 de 15 jul a 15 jan seguinte.
	var jan := Calendar.to_seconds(1, 1, 15, 12)
	var jul := Calendar.to_seconds(1, 7, 15, 12)
	if (jul - jan) / D != 181 or (Calendar.to_seconds(2, 1, 15, 12) - jul) / D != 184:
		return _fail("as âncoras de 15 jan e 15 jul deveriam ficar a 181 e 184 dias")
	var text := Calendar.format(Calendar.to_seconds(120, 3, 15, 12, 5))
	if text != "15 de março de 120 · 12:05":
		return _fail("formato: " + text)
	ok("datas: 365 dias, ida e volta (anos negativos incluídos), inválidas rejeitadas, viradas de dia, mês e ano")
	return true


func _rules() -> bool:
	var t := Calendar.to_seconds(5, 1, 31, 9, 45)
	var feb := Calendar.add_months(t, 1)
	var mar := Calendar.add_months(feb, 1)
	if feb != Calendar.to_seconds(5, 2, 28, 9, 45) or mar != Calendar.to_seconds(5, 3, 28, 9, 45):
		return _fail("31 jan +1 mês deveria ser 28 fev e depois 28 mar: %s, %s" % [Calendar.format(feb), Calendar.format(mar)])
	if Calendar.add_months(t, 2) != Calendar.to_seconds(5, 3, 31, 9, 45):
		return _fail("31 jan +2 meses deveria ser 31 mar")
	if Calendar.add_months(Calendar.to_seconds(5, 3, 31), 1) != Calendar.to_seconds(5, 4, 30):
		return _fail("31 mar +1 mês deveria ser 30 abr")
	if Calendar.add_months(Calendar.to_seconds(5, 12, 15), 1) != Calendar.to_seconds(6, 1, 15):
		return _fail("15 dez +1 mês deveria cair em 15 jan do ano seguinte")
	if Calendar.add_months(Calendar.to_seconds(5, 1, 15), -1) != Calendar.to_seconds(4, 12, 15):
		return _fail("15 jan -1 mês deveria cair em 15 dez do ano anterior")
	if Calendar.add_months(t, 12) != Calendar.add_years(t, 1) or Calendar.add_months(Calendar.to_seconds(-1, 12, 31), 1) != Calendar.to_seconds(0, 1, 31):
		return _fail("12 meses = 1 ano, também com anos negativos")
	if Calendar.add_months(t, 1) == t + 30 * D or Calendar.from_seconds(t + 30 * D)["month"] != 3:
		return _fail("a partir de 31 jan, +1 mês (28 fev) e +30 dias fixos (março) deveriam diferir")
	ok("+1 mês conserva o dia (31 jan → 28 fev → 28 mar); +30 dias é outra conta")
	return true


func _playback() -> bool:
	var c := WorldClock.new()
	var t0 := c.now
	if c.running:
		return _fail("a campanha deveria abrir pausada")
	c.tick(0.5)
	if c.now != t0:
		return _fail("pausado não deveria acumular tempo")
	c.play()
	c.set_speed(Calendar.HOUR)
	c.tick(1.0)
	if c.now != t0 + Calendar.HOUR:
		return _fail("1 s real a 1 hora/s deveria somar 3600 s, somou %d" % (c.now - t0))
	c.pause()
	for i in 600:
		c.tick(0.016)  # girar a câmera durante a pausa: o relógio não se move
	if c.now != t0 + Calendar.HOUR:
		return _fail("a pausa acumulou tempo")
	# A mesma duração real e velocidade dão o mesmo avanço a 60, 30 e 7 quadros/s (dentro de 1 s do mundo).
	var totals := []
	for fps in [60, 30, 7]:
		var k := WorldClock.new()
		k.set_speed(Calendar.MINUTE)
		k.play()
		for i in fps * 10:
			k.tick(1.0 / fps)
		totals.append(k.now - t0)
	if totals.any(func(v: int) -> bool: return absi(v - 600) > 1):
		return _fail("10 s reais a 1 min/s deveriam dar 600 s do mundo em qualquer taxa, deu %s" % [totals])
	# A fração não se perde: 5 quadros de 0,4 s a 1 s/s = 2 s (cada quadro sozinho arredondaria para 0).
	var f := WorldClock.new()
	f.set_speed(1)
	f.play()
	for i in 5:
		f.tick(0.4)
	if f.now - t0 != 2:
		return _fail("5 × 0,4 s a 1 s/s deveria somar 2 s, somou %d" % (f.now - t0))
	if WorldClock.new().advance_by(0) or WorldClock.new().advance_by(-5) or WorldClock.new().advance_months(0):
		return _fail("avanço zero ou negativo deveria ser recusado")
	ok("pausa não acumula; mesma duração real = mesmo avanço a 60, 30 e 7 quadros/s; fração preservada")
	return true


func _view() -> bool:
	var c := WorldClock.new()
	var present := c.now
	var past := Calendar.to_seconds(-110, 6, 1)
	c.enter_view(past)
	if not c.viewing or c.shown() != past or c.now != present:
		return _fail("consultar só muda a data mostrada, não o presente")
	c.set_speed(Calendar.DAY)
	c.play()
	c.tick(1.0)
	if c.now != present or c.running:
		return _fail("em consulta a reprodução fica parada e não mexe no presente")
	if c.advance_by(D) or c.advance_months(1) or c.advance_to(present + D) or c.now != present:
		return _fail("em consulta, os avanços deveriam ser recusados")
	c.exit_view()
	if c.viewing or c.shown() != present or c.running:
		return _fail("voltar ao presente mostra o presente e continua pausado")
	if c.to_dict().has("view_time") or c.to_dict()["now"] != present:
		return _fail("a consulta não deve ir para o salvamento")
	ok("consulta: o presente não muda, reprodução parada, avanços recusados, volta pausado")
	return true


func _events() -> bool:
	var start := WorldClock.new().now
	# O mesmo mundo avançado de três formas: 30 dias de uma vez, 30 vezes 1 dia e "avançar até".
	var logs := []
	for mode in ["once", "daily", "advance_to"]:
		var c := WorldClock.new()
		var daily := Recorder.new()
		daily.every = D
		daily.clock = c
		var hourly := Recorder.new()
		hourly.every = Calendar.HOUR
		hourly.clock = c
		var fired := []
		c.event_fired.connect(func(e: Dictionary) -> void: fired.append([e["id"], e["at"], c.now]))
		c.register(daily)
		c.register(hourly)
		if not c.schedule("b", start + 20 * D + 5, "segundo") or not c.schedule("a", start + 20 * D + 5, "simultâneo") \
				or not c.schedule("c", start + 3 * D, "primeiro"):
			return _fail("não cadastrou os eventos")
		match mode:
			"once":
				c.advance_by(30 * D)
			"daily":
				for i in 30:
					c.advance_by(D)
			"advance_to":
				c.advance_to(start + 30 * D)
		if c.now != start + 30 * D:
			return _fail("%s: o presente deveria ser +30 dias" % mode)
		if not daily.consistent or not hourly.consistent:
			return _fail("%s: durante um passo, o presente deveria valer o instante do passo" % mode)
		logs.append([fired, daily.log, hourly.log])
	if logs[0] != logs[1] or logs[0] != logs[2]:
		return _fail("30 dias de uma vez, 30 × 1 dia e 'avançar até' deveriam produzir os mesmos eventos e passos")
	var fired: Array = logs[0][0]
	if fired.map(func(f: Array) -> String: return f[0]) != ["c", "b", "a"]:
		return _fail("ordem: por instante, e iguais na ordem de cadastro (b antes de a): %s" % [fired])
	if fired.any(func(f: Array) -> bool: return f[1] != f[2]):
		return _fail("durante o evento, o presente deveria valer o instante dele")
	if logs[0][1].size() != 30 or logs[0][2].size() != 30 * 24:
		return _fail("passos diários e horários: %d e %d" % [logs[0][1].size(), logs[0][2].size()])
	# Cada ocorrência é aplicada uma vez; evento no passado ou repetido é recusado; avançar até o passado também.
	var c := WorldClock.new()
	var count := [0]
	c.event_fired.connect(func(_e: Dictionary) -> void: count[0] += 1)
	c.schedule("x", start + D, "x")
	c.advance_by(5 * D)
	c.advance_by(5 * D)
	if count[0] != 1:
		return _fail("o evento deveria disparar uma única vez, disparou %d" % count[0])
	if c.schedule("x", start + 20 * D, "repetido") or c.schedule("y", c.now, "agora") or c.schedule("z", start, "passado"):
		return _fail("evento repetido ou que não seja futuro deveria ser recusado")
	if c.advance_to(c.now) or c.advance_to(start):
		return _fail("avançar até o presente ou o passado deveria ser recusado")
	# O comando de calendário (+1 mês) também alcança o evento do meio do caminho.
	var m := WorldClock.new()
	var seen := []
	m.event_fired.connect(func(e: Dictionary) -> void: seen.append(e["id"]))
	m.schedule("meio", Calendar.add_months(m.now, 1) - D, "meio")
	m.advance_months(1)
	if seen != ["meio"]:
		return _fail("+1 mês deveria alcançar o evento do meio do caminho")
	ok("avanço grande: eventos e passos idênticos a 30 × 1 dia, uma ocorrência cada, ordem estável")
	return true


func _persistence() -> bool:
	var path := out_dir.path_join("calendar_test_save.json")
	for p in [path, path + ".bak", path + ".tmp"]:
		DirAccess.remove_absolute(p)
	var c := WorldClock.new()
	c.schedule("passou", c.now + D, "já ocorreu")
	c.schedule("futuro", c.now + 9 * D, "ainda vai ocorrer")
	c.set_speed(Calendar.DAY)
	c.play()
	c.tick(0.4)
	c.tick(0.7)  # deixa uma fração de segundo acumulada
	c.pause()
	c.advance_by(2 * D)  # dispara "passou"
	c.enter_view(Calendar.to_seconds(-3, 1, 1))
	if not WorldStore.save(c, path):
		return _fail("não gravou o salvamento")
	var r := WorldClock.new()
	if not WorldStore.load_into(r, path):
		return _fail("não leu o salvamento")
	if r.now != c.now or r.speed != c.speed or r.running or r.viewing or r.events() != c.events() or r._frac != c._frac:
		return _fail("o relógio restaurado deveria ter o mesmo presente, velocidade e eventos, pausado e sem consulta")
	# Reabrir não avança o tempo, e o evento que já ocorreu não ocorre de novo.
	var fired := []
	r.event_fired.connect(func(e: Dictionary) -> void: fired.append(e["id"]))
	r.advance_by(20 * D)
	if fired != ["futuro"]:
		return _fail("depois de reabrir, só 'futuro' deveria disparar, disparou %s" % [fired])
	# Uma segunda gravação guarda a primeira como .bak; o arquivo estragado cai para o .bak; versão errada é recusada.
	if not WorldStore.save(r, path) or not FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".tmp"):
		return _fail("a segunda gravação deveria deixar um .bak e nenhum .tmp")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ estragado")
	f.close()
	var b := WorldClock.new()
	if not WorldStore.load_into(b, path) or b.now != c.now:
		return _fail("com o salvamento estragado, deveria ler o .bak (o estado anterior)")
	var bad := c.to_dict()
	bad["calendar_version"] = Calendar.VERSION + 1
	var keep := WorldClock.new()
	var keep_now := keep.now
	if keep.restore(bad) or keep.now != keep_now:
		return _fail("calendário de outra versão deveria ser recusado sem mudar nada")
	if WorldClock.new().restore({"calendar_version": Calendar.VERSION, "now": 5, "frac": 0.0, "speed": 1, "events": [{"id": "x"}]}):
		return _fail("evento malformado deveria ser recusado")
	for p in [path, path + ".bak"]:
		DirAccess.remove_absolute(p)
	if WorldStore.load_into(WorldClock.new(), path):
		return _fail("sem arquivo, nada para ler")
	ok("salvamento: presente, fração e eventos ida e volta; reabrir não avança; .bak, versão e dados malformados")
	return true


func _demo() -> bool:
	var c := WorldClock.new()
	var demo := DemoModule.new()
	demo.attach(c)
	var n := EvronGeo.dir(40.0, 10.0)
	var t := c.now + 100 * D
	var a := DemoModule.value_at(n, t)
	var b := DemoModule.value_at(n, t + Calendar.YEAR)
	if a["state"] != DemoModule.STATE or not is_equal_approx(a["value"], b["value"]):
		return _fail("a camada de teste deveria se repetir a cada ano e se declarar demonstrativa")
	if DemoModule.value_at(n, t + 40 * D)["value"] == a["value"]:
		return _fail("trocar a data deveria mudar o valor da camada")
	var before := DemoModule.value_at(n, c.now - 1)
	if before.has("value") or before["state"] != "indisponível":
		return _fail("antes do início do cenário não há dado: 'indisponível', nunca o estado atual")
	c.advance_by(30 * D)
	if demo.steps != 30 or not c.events()[0]["fired"]:
		return _fail("30 dias: 30 passos diários e o evento demonstrativo disparado (%d, %s)" % [demo.steps, c.events()])
	ok("camada e evento demonstrativos exercitam o contrato")
	return true


func _seasonal() -> bool:
	var jan := Calendar.to_seconds(7, 1, 15, 12)
	var jul := Calendar.to_seconds(7, 7, 15, 12)
	var w := SeasonalTemperature.july_weight
	if w.call(jan) != 0.0 or w.call(jul) != 1.0 or w.call(Calendar.to_seconds(-3, 1, 15, 12)) != 0.0:
		return _fail("o peso de julho deveria ser exatamente 0 em 15 jan 12h e 1 em 15 jul 12h (também em anos negativos)")
	if not is_equal_approx(w.call((jan + jul) / 2), 0.5) or w.call(jan) != w.call(jan + 3 * Calendar.YEAR):
		return _fail("o ponto médio entre as âncoras deveria pesar 0,5 e o ciclo repetir todo ano")
	# Sem salto na virada do ano, monótono entre as âncoras, sempre dentro de 0..1 (amostra de hora em hora).
	var year_end := Calendar.to_seconds(8, 1, 1)
	if absf(w.call(year_end - 1) - w.call(year_end)) > 1e-5:
		return _fail("o peso saltou na virada do ano: %f -> %f" % [w.call(year_end - 1), w.call(year_end)])
	var prev: float = w.call(jan)
	for t in range(jan, jul + 1, Calendar.HOUR):
		var v: float = w.call(t)
		if v < prev or v < 0.0 or v > 1.0:
			return _fail("janeiro→julho deveria subir de 0 a 1 sem sair da faixa")
		prev = v
	for t in range(jul, jan + Calendar.YEAR + 1, Calendar.HOUR):
		var v: float = w.call(t)
		if v > prev or v < 0.0 or v > 1.0:
			return _fail("julho→janeiro seguinte deveria descer de 1 a 0 sem sair da faixa")
		prev = v

	var maps := EvronMaps.load_temperature()
	if maps.is_empty():
		return _fail("mapas de temperatura em °C ausentes: rode tools/import_maps.py")
	var s := SeasonalTemperature.new(maps)
	var jan_img: Image = maps["jan"]
	var jul_img: Image = maps["jul"]
	for ll in [Vector2(0, 0), Vector2(45, 10), Vector2(-30, 120), Vector2(70, -100)]:
		var n := EvronGeo.dir(ll.x, ll.y)
		var p := EvronGeo.pixel(n, jan_img.get_size())
		var a := s.value_at(n, jan)
		var b := s.value_at(n, jul)
		if a["value"] != jan_img.get_pixel(p.x, p.y).r or b["value"] != jul_img.get_pixel(p.x, p.y).r:
			return _fail("em 15 jan e 15 jul a temperatura deveria passar exatamente pelos mapas (%s)" % [ll])
		if absf(s.value_at(n, year_end - 1)["value"] - s.value_at(n, year_end)["value"]) > 0.01:
			return _fail("a temperatura saltou na virada do ano em %s" % [ll])
		if s.value_at(n, jan + Calendar.YEAR)["value"] != a["value"]:
			return _fail("o ciclo deveria se repetir a cada ano em %s" % [ll])
	var mid := s.value_at(EvronGeo.dir(45, 10), (jan + jul) / 2)
	var ends := [s.value_at(EvronGeo.dir(45, 10), jan)["value"], s.value_at(EvronGeo.dir(45, 10), jul)["value"]]
	if not is_equal_approx(mid["value"], (ends[0] + ends[1]) / 2.0):
		return _fail("no meio entre as âncoras o valor deveria ser a média dos dois mapas")
	# Condição, origem e incerteza sempre vêm junto; o polo em janeiro satura (≤ −20 °C) e isso é declarado.
	var pole := s.value_at(EvronGeo.dir(85, 0), jan)
	if mid["state"] != "estimado" or not mid.has("source") or not mid.has("uncertainty") or mid["unit"] != "°C":
		return _fail("o resultado deveria declarar condição, unidade, origem e incerteza")
	if not pole["saturated"] or pole["value"] > SeasonalTemperature.FLOOR_C + 0.5:
		return _fail("o polo norte em janeiro deveria estar saturado em ≤ −20 °C: %s" % [pole])
	if s.value_at(EvronGeo.dir(0, 0), jan)["value"] < s.value_at(EvronGeo.dir(85, 0), jan)["value"]:
		return _fail("o equador deveria ser mais quente que o polo em janeiro")
	ok("temperatura sazonal: passa pelos dois mapas nas âncoras, sem salto na virada do ano, estimada e com incerteza")
	return true


func _seeds() -> bool:
	var a := WorldClock.new()
	var b := WorldClock.new()
	if a.derived_seed("ondas") != b.derived_seed("ondas") or a.derived_seed("ondas") == a.derived_seed("vento"):
		return _fail("a semente derivada deveria repetir para o mesmo nome e diferir entre nomes")
	b.world_seed = 2
	if a.derived_seed("ondas") == b.derived_seed("ondas"):
		return _fail("outra semente do mundo deveria dar outra semente derivada")
	b.models = {"temperatura_sazonal": 1}
	var path := out_dir.path_join("calendar_seed_save.json")
	if not WorldStore.save(b, path):
		return _fail("não gravou")
	var r := WorldClock.new()
	if not WorldStore.load_into(r, path) or r.world_seed != 2 or int(r.models.get("temperatura_sazonal", 0)) != 1 \
			or r.derived_seed("ondas") != b.derived_seed("ondas"):
		return _fail("semente do mundo e versões dos modelos deveriam voltar do salvamento")
	for p in [path, path + ".bak"]:
		DirAccess.remove_absolute(p)
	ok("semente do mundo, sementes derivadas estáveis e versões dos modelos no salvamento")
	return true


func _fail(msg: String) -> bool:
	fail(msg)
	return false
