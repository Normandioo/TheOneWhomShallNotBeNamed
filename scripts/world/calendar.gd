extends RefCounted
## O calendário universal de Evron: só conversões, sem estado. Tempo = segundos do mundo (int de 64 bits) desde 1º de
## janeiro do ano 0, 00:00 (época técnica). Versão 1 (proposta): 12 meses de duração usual, fevereiro sempre com 28 dias,
## nenhum ano bissexto: o ano tem 365 dias. O Time do Godot não serve aqui: ele segue o gregoriano, com bissextos.
## Ano, era e data inicial da campanha são decisões narrativas em aberto: nada aqui estabelece um ano canônico.

const VERSION := 1  # grava-se no salvamento: mudar as regras do calendário muda o número
const MINUTE := 60
const HOUR := 3600
const DAY := 86400
const YEAR_DAYS := 365
const YEAR := YEAR_DAYS * DAY  # 31.536.000 s

const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const MONTH_NAMES := ["janeiro", "fevereiro", "março", "abril", "maio", "junho",
	"julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]
const INVALID := -9223372036854775808  # to_seconds devolve isto para uma data que não existe

## Cenário técnico de teste: 1º de janeiro do ano técnico 1, meia-noite. Não é uma data da história de Evron.
const TECHNICAL_START_YEAR := 1


## Data e hora existem neste calendário? (mês 1–12, dia dentro do mês, hora 0–23, minuto e segundo 0–59)
static func valid(year: int, month: int, day: int, hour := 0, minute := 0, second := 0) -> bool:
	return month >= 1 and month <= 12 and day >= 1 and day <= MONTH_DAYS[month - 1] \
		and hour >= 0 and hour < 24 and minute >= 0 and minute < 60 and second >= 0 and second < 60


## Segundos do mundo de uma data legível, ou INVALID se ela não existe.
static func to_seconds(year: int, month: int, day: int, hour := 0, minute := 0, second := 0) -> int:
	if not valid(year, month, day, hour, minute, second):
		return INVALID
	var day_of_year := day - 1
	for m in month - 1:
		day_of_year += MONTH_DAYS[m]
	return year * YEAR + day_of_year * DAY + hour * HOUR + minute * MINUTE + second


## {year, month, day, hour, minute, second} de um instante. Funciona antes da época (instantes negativos).
static func from_seconds(t: int) -> Dictionary:
	var year := floordiv(t, YEAR)
	var rest := t - year * YEAR  # sempre 0 ≤ rest < YEAR: o resto de int do GDScript seria negativo antes da época
	var day_of_year := rest / DAY
	var month := 1
	while day_of_year >= MONTH_DAYS[month - 1]:
		day_of_year -= MONTH_DAYS[month - 1]
		month += 1
	var sec := rest % DAY
	return {"year": year, "month": month, "day": day_of_year + 1,
		"hour": sec / HOUR, "minute": sec % HOUR / MINUTE, "second": sec % MINUTE}


## Soma n meses (n pode ser negativo) mantendo dia e hora; se o dia não existe no destino, usa o último dia dele.
## 31 de janeiro + 1 mês = 28 de fevereiro; mais 1 mês = 28 de março (cada passo parte da data do passo anterior).
static func add_months(t: int, n: int) -> int:
	var d := from_seconds(t)
	var index: int = d["year"] * 12 + (d["month"] - 1) + n
	var year := floordiv(index, 12)
	var month := index - year * 12 + 1
	return to_seconds(year, month, mini(d["day"], MONTH_DAYS[month - 1]), d["hour"], d["minute"], d["second"])


## Soma n anos: sempre 365 dias cada (sem bissextos), então 1 ano = 12 meses = 365 dias.
static func add_years(t: int, n: int) -> int:
	return t + n * YEAR


## Dia do ano de 1 a 365.
static func day_of_year(t: int) -> int:
	return (t - floordiv(t, YEAR) * YEAR) / DAY + 1


## "15 de março de 1 · 12:00" (o ano é só o número técnico; sem era, sem "depois de").
static func format(t: int, with_time := true) -> String:
	var d := from_seconds(t)
	var s := "%d de %s de %d" % [d["day"], MONTH_NAMES[d["month"] - 1], d["year"]]
	if with_time:
		s += " · %02d:%02d" % [d["hour"], d["minute"]]
	return s


## Divisão de inteiros arredondada para baixo (o "/" do GDScript arredonda para zero).
static func floordiv(a: int, b: int) -> int:
	return (a - posmod(a, b)) / b
