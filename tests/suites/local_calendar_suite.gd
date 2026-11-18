extends "res://tests/test_suite.gd"
## Conversão entre o calendário universal e calendários locais (critérios 8 e 10 do plano de domínios), sem cena e sem banco:
## definições feitas à mão. Cobre a volta ao mesmo instante e as viradas de dia, mês, ano e era.

const Calendar = preload("res://scripts/world/calendar.gd")
const LocalCalendar = preload("res://scripts/world/local_calendar.gd")

const FOREVER := 9223372036854775807
const ALWAYS := -9223372036854775807 - 1


func _era(id: int, name: String, abbr: String, start: int, direction: String, first: int, from := ALWAYS, to := FOREVER, priority := 0) -> Dictionary:
	return {"era_id": id, "name": name, "abbreviation": abbr, "start": start, "direction": direction, "first": first,
		"valid_from": from, "valid_to": to, "priority": priority}


func _def(eras: Array, offset := 0, months: Array = [], reliability := "exata") -> Dictionary:
	return {"id": 1, "name": "teste", "description": "", "source": "", "month_names": months, "day_offset": offset, "reliability": reliability, "eras": eras}


func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# O calendário "idêntico" ao universal (era no ano 0, número 0): a data local é a do universal e a volta é exata.
	var same := _def([_era(1, "Universal", "", 0, "up", 0)])
	for i in 2000:
		var t := rng.randi_range(-200 * Calendar.YEAR, 200 * Calendar.YEAR)
		var u := Calendar.from_seconds(t)
		var l := LocalCalendar.to_local(same, t)
		if l.status != "exata" or l.year != u.year or l.month != u.month or l.day != u.day or l.hour != u.hour or l.minute != u.minute or l.second != u.second:
			return fail("o calendário idêntico divergiu em t=%d: %s vs %s" % [t, l, u])
		var back := LocalCalendar.to_universal(same, 1, l.year, l.month, l.day, l.hour, l.minute, l.second)
		if back.status != "exata" or back.t != t:
			return fail("a volta não deu o mesmo instante em t=%d: %s" % [t, back])
	ok("calendário idêntico ao universal: 2000 instantes (inclusive antes da época) ida e volta, sem perder um segundo")

	# Numeração por era com o marco no meio do ano: o ano do marco é parcial e já é o número 1; a virada de ano do calendário muda o número.
	var marco := Calendar.to_seconds(100, 3, 15, 12)
	var aren := _def([_era(1, "Era de Aren", "EA", marco, "up", 1)], 0, ["Gelo", "Neve", "Brota", "Chuva", "Flor", "Sol", "Calor", "Seca", "Colheita", "Névoa", "Geada", "Longa noite"])
	var l := LocalCalendar.to_local(aren, marco)
	if l.year != 1 or l.month != 3 or l.day != 15 or l.month_name != "Brota" or LocalCalendar.format(l) != "15 de Brota de 1 EA · 12:00":
		return fail("o marco deveria ser 15 de Brota de 1 EA: %s" % [LocalCalendar.format(l)])
	if LocalCalendar.to_local(aren, Calendar.to_seconds(100, 12, 31, 23, 59, 59)).year != 1:
		return fail("o fim do ano do marco ainda é o ano 1")
	var virada := LocalCalendar.to_local(aren, Calendar.to_seconds(101, 1, 1))
	if virada.year != 2 or virada.month != 1 or virada.day != 1 or virada.month_name != "Gelo":
		return fail("a virada de ano deveria dar o ano 2: %s" % [virada])
	if LocalCalendar.to_local(aren, Calendar.to_seconds(99, 12, 31)).year != 0:
		return fail("antes do marco a contagem continua para trás (ano 0)")
	ok("era com marco no meio do ano: ano parcial = 1, virada de ano, nomes de mês próprios e formato")

	# AD/BC: duas eras no mesmo marco, uma crescente e uma regressiva, e a virada de era no segundo exato.
	var ad := Calendar.to_seconds(500, 1, 1)
	var cristal := _def([_era(1, "Depois da Fundação", "DF", ad, "up", 1, ad, FOREVER), _era(2, "Antes da Fundação", "AF", ad, "down", 0, ALWAYS, ad)])
	var a1 := LocalCalendar.to_local(cristal, ad - 1)
	var a2 := LocalCalendar.to_local(cristal, ad)
	if a1.abbreviation != "AF" or a1.year != 1 or a1.month != 12 or a1.day != 31 or a2.abbreviation != "DF" or a2.year != 1 or a2.month != 1 or a2.day != 1:
		return fail("virada de era: %s | %s" % [LocalCalendar.format(a1), LocalCalendar.format(a2)])
	if LocalCalendar.to_local(cristal, Calendar.to_seconds(400, 6, 1)).year != 100:
		return fail("o ano 400 está a 100 anos do marco: 100 AF")
	for t in [ad - 1, ad, ad - 5 * Calendar.YEAR, ad + 7 * Calendar.YEAR + 12345]:
		var x := LocalCalendar.to_local(cristal, t)
		var b := LocalCalendar.to_universal(cristal, x.era_id, x.year, x.month, x.day, x.hour, x.minute, x.second)
		if b.status != "exata" or b.t != t:
			return fail("ida e volta com duas eras em t=%d: %s" % [t, b])
	ok("era crescente + regressiva no mesmo marco: virada de era no segundo exato e ida e volta nas duas")

	# Viradas de dia (o dia vira às 6h), de mês e de ano.
	var seis := _def([_era(1, "E", "", 6 * Calendar.HOUR, "up", 0)], 6 * Calendar.HOUR)  # marco = 1º de janeiro do ano 0 às 6h (a virada do dia): ano local = ano do universal deslocado
	var antes := LocalCalendar.to_local(seis, Calendar.to_seconds(5, 1, 1, 5, 59, 59))
	var depois := LocalCalendar.to_local(seis, Calendar.to_seconds(5, 1, 1, 6, 0, 0))
	if antes.year != 4 or antes.month != 12 or antes.day != 31 or antes.hour != 23 or antes.second != 59 or depois.year != 5 or depois.month != 1 or depois.day != 1 or depois.hour != 0:
		return fail("virada do dia às 6h (ano e mês viram junto): %s | %s" % [LocalCalendar.format(antes), LocalCalendar.format(depois)])
	var fev := LocalCalendar.to_local(same, Calendar.to_seconds(7, 2, 28, 23, 59, 59))
	var mar := LocalCalendar.to_local(same, Calendar.to_seconds(7, 2, 28, 23, 59, 59) + 1)
	if fev.month != 2 or fev.day != 28 or mar.month != 3 or mar.day != 1:
		return fail("virada de mês: fevereiro tem 28 dias")
	for t in [Calendar.to_seconds(5, 1, 1, 5, 59, 59), Calendar.to_seconds(5, 1, 1, 6), Calendar.to_seconds(5, 6, 30, 5, 59, 59)]:
		var x := LocalCalendar.to_local(seis, t)
		if LocalCalendar.to_universal(seis, 1, x.year, x.month, x.day, x.hour, x.minute, x.second).t != t:
			return fail("a volta com virada do dia às 6h em t=%d" % t)
	ok("virada do dia às 6h (leva o mês e o ano junto), virada de mês e volta exata")

	# Duas eras no mesmo instante: vale a de maior prioridade (e a de menor volta a valer fora do período).
	var prio := _def([_era(1, "A", "A", 0, "up", 1, ALWAYS, FOREVER, 0), _era(2, "B", "B", 0, "up", 1000, 500, FOREVER, 1)])
	if LocalCalendar.to_local(prio, 400).abbreviation != "A" or LocalCalendar.to_local(prio, 600).abbreviation != "B" or LocalCalendar.to_local(prio, 600).year != 1000:
		return fail("prioridade de era")
	ok("eras sobrepostas: vale a de maior prioridade no período dela")

	# Nada de precisão inventada: sem era, calendário indisponível, data inexistente, fora da validade.
	var sem_ancora := _def([])
	var indisponivel := _def([_era(1, "E", "", 0, "up", 1)], 0, [], "indisponivel")
	if LocalCalendar.to_local(sem_ancora, 5).status != "indisponivel" or LocalCalendar.to_local(indisponivel, 5).status != "indisponivel":
		return fail("sem era ou indisponível deveria recusar a conversão")
	if LocalCalendar.to_universal(indisponivel, 1, 3, 1, 1).status != "indisponivel" or LocalCalendar.to_universal(sem_ancora, 1, 3, 1, 1).status != "invalida":
		return fail("a volta sem âncora também recusa")
	if LocalCalendar.to_universal(same, 1, 5, 2, 29).status != "invalida" or LocalCalendar.to_universal(same, 1, 5, 13, 1).status != "invalida" or LocalCalendar.to_universal(same, 1, 5, 4, 31).status != "invalida":
		return fail("29 de fevereiro, mês 13 e 31 de abril não existem")
	if LocalCalendar.to_universal(cristal, 1, -5, 6, 1).status != "fora_da_validade" or LocalCalendar.to_universal(cristal, 2, -3, 6, 1).status != "fora_da_validade":
		return fail("DF ano -5 cai antes do marco e AF ano -3 cai depois: fora da validade da era")
	if LocalCalendar.to_universal(cristal, 1, 3, 6, 1).status != "exata" or LocalCalendar.to_universal(cristal, 2, 3, 6, 1).status != "exata":
		return fail("3 DF e 3 AF existem")
	if not LocalCalendar.format(LocalCalendar.to_local(sem_ancora, 5)).begins_with("indisponível"):
		return fail("o texto de uma conversão indisponível")
	var aprox := _def([_era(1, "E", "", 0, "up", 1)], 0, [], "aproximada")
	if LocalCalendar.to_local(aprox, 5).reliability != "aproximada":
		return fail("a confiabilidade 'aproximada' deveria acompanhar o resultado")
	ok("sem âncora, indisponível, data inexistente e fora da validade: recusados com o motivo, sem instante")

	# Data só com ano ou mês é um intervalo, não um instante.
	var sp := LocalCalendar.span(same, 1, 5)
	if sp.status != "exata" or sp.precision != "ano" or sp.from != Calendar.to_seconds(5, 1, 1) or sp.to - sp.from != Calendar.YEAR:
		return fail("intervalo de um ano: %s" % [sp])
	var sm := LocalCalendar.span(same, 1, 5, 2)
	if sm.precision != "mes" or sm.to - sm.from != 28 * Calendar.DAY or sm.from != Calendar.to_seconds(5, 2, 1):
		return fail("intervalo de fevereiro: %s" % [sm])
	var aren_depois := _def([_era(1, "Era de Aren", "EA", marco, "up", 1, marco, FOREVER)])  # a era só vale a partir do marco
	if LocalCalendar.span(aren_depois, 1, 1).status != "fora_da_validade" or LocalCalendar.span(aren_depois, 1, 2).status != "exata":
		return fail("o ano 1 EA começa antes do marco: o intervalo inteiro não está na validade da era; o ano 2 está")
	if LocalCalendar.span(cristal, 2, 1).status != "exata" or LocalCalendar.span(cristal, 2, 1).to != ad:
		return fail("1 AF termina exatamente no marco")
	ok("data só com ano ou mês vira um intervalo [de, até); o que sai da validade da era é recusado")

	# Ida e volta aleatória em calendários sem sobreposição.
	for d in [same, aren, cristal, seis]:
		for i in 1500:
			var t := rng.randi_range(-300 * Calendar.YEAR, 300 * Calendar.YEAR)
			var x := LocalCalendar.to_local(d, t)
			if x.status != "exata":
				continue  # fora das eras deste calendário
			var b := LocalCalendar.to_universal(d, x.era_id, x.year, x.month, x.day, x.hour, x.minute, x.second)
			if b.status != "exata" or b.t != t:
				return fail("ida e volta aleatória falhou em t=%d (%s): %s" % [t, d.eras[0].name, b])
	ok("6000 instantes aleatórios em 4 calendários: sempre voltam ao mesmo instante")
