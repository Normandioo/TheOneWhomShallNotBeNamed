extends RefCounted
## Conversão entre o calendário universal e um calendário local (etapa 3 do plano de domínios). Só funções sobre uma DEFINIÇÃO
## (o Dictionary de Registry.CalendarDef): sem estado, sem banco, sem tela. A aritmética de dias e meses é a do calendar.gd.
##
## Um calendário local desta etapa conserva os meses e dias do universal (365 dias, sem bissextos) e varia:
##  · a numeração dos anos, por eras (marco em segundos universais, direção da contagem e número do ano do marco);
##  · a virada do dia (day_offset: segundos depois da meia-noite universal; o ano e o mês viram junto);
##  · os nomes dos meses e o formato.
## O número do ano muda a cada virada de ano do calendário. O ano do marco é o ano em que cai o marco (se ele cai no meio do ano,
## esse ano é parcial e já tem o número first). Direção "up": números crescem com o tempo; "down": crescem para o passado.
##
## Exato ou nada: sem era válida, calendário marcado como indisponível, data que não existe ou fora da validade da era dão um status
## explicando o motivo e NUNCA um instante inventado. Uma data só com ano ou mês vira um intervalo (span), não um instante.
## Na volta (to_universal) o instante é exato; na ida (to_local) vale a era de maior prioridade que cobre o instante.

const Calendar = preload("res://scripts/world/calendar.gd")

const OK := "exata"
const UNAVAILABLE := "indisponivel"
const INVALID := "invalida"
const OUT_OF_RANGE := "fora_da_validade"


## A era que vale em t neste calendário (maior prioridade; empate: a que começou por último), ou {} se nenhuma.
static func era_at(def: Dictionary, t: int) -> Dictionary:
	var best := {}
	for e in def["eras"]:
		if e["valid_from"] <= t and t < e["valid_to"]:
			if best.is_empty() or e["priority"] > best["priority"] or (e["priority"] == best["priority"] and e["valid_from"] > best["valid_from"]):
				best = e
	return best


## Data local de um instante universal: {status: "exata", era_id, era, abbreviation, year, month, day, hour, minute, second,
## month_name, reliability} ou {status: "indisponivel", reason}.
static func to_local(def: Dictionary, t: int) -> Dictionary:
	if def["reliability"] == UNAVAILABLE:
		return {"status": UNAVAILABLE, "reason": "o autor marcou este calendário como sem conversão"}
	var era := era_at(def, t)
	if era.is_empty():
		return {"status": UNAVAILABLE, "reason": "nenhuma era vale nesta data neste calendário"}
	var d := Calendar.from_seconds(t - int(def["day_offset"]))
	var start_year: int = _start_year(def, era)
	var n: int = int(era["first"]) + (d["year"] - start_year if era["direction"] == "up" else start_year - d["year"])
	return {"status": OK, "era_id": era["era_id"], "era": era["name"], "abbreviation": era["abbreviation"], "year": n,
		"month": d["month"], "day": d["day"], "hour": d["hour"], "minute": d["minute"], "second": d["second"],
		"month_name": month_name(def, d["month"]), "reliability": def["reliability"]}


## Instante universal de uma data local EXATA (era, ano, mês, dia e hora). {status: "exata", t} ou um status de recusa com reason.
static func to_universal(def: Dictionary, era_id: int, year: int, month: int, day: int, hour := 0, minute := 0, second := 0) -> Dictionary:
	var u := _local_seconds(def, era_id, year, month, day, hour, minute, second)
	if u.has("status"):
		return u
	return _check_range(def, era_id, int(u["t"]))


## O intervalo de uma data só com ano (month = 0) ou com ano e mês: {status: "exata", from, to, precision: "ano" | "mes"}, com
## from incluído e to excluído. Não existe instante exato para essa data; quem usa precisa manter a precisão.
static func span(def: Dictionary, era_id: int, year: int, month := 0) -> Dictionary:
	var first := _local_seconds(def, era_id, year, maxi(month, 1), 1, 0, 0, 0)
	if first.has("status"):
		return first
	var from: int = first["t"]
	var to: int
	if month == 0:
		to = from + Calendar.YEAR
	else:
		to = from + int(Calendar.MONTH_DAYS[month - 1]) * Calendar.DAY
	var a := _check_range(def, era_id, from)
	if a["status"] != OK:
		return a
	var b := _check_range(def, era_id, to - 1)  # o último segundo também precisa estar na validade
	if b["status"] != OK:
		return b
	return {"status": OK, "from": from, "to": to, "precision": "ano" if month == 0 else "mes"}


## "15 de Frostmoon de 312 AE · 12:00". Para status diferente de "exata", o motivo.
static func format(local: Dictionary, with_time := true) -> String:
	if local["status"] != OK:
		return "indisponível (%s)" % local.get("reason", "sem conversão")
	var s := "%d de %s de %d" % [local["day"], local["month_name"], local["year"]]
	if local["abbreviation"] != "":
		s += " " + local["abbreviation"]
	elif local["era"] != "":
		s += " (" + local["era"] + ")"
	if with_time:
		s += " · %02d:%02d" % [local["hour"], local["minute"]]
	return s


static func month_name(def: Dictionary, month: int) -> String:
	var names: Array = def["month_names"]
	return names[month - 1] if names.size() == 12 else Calendar.MONTH_NAMES[month - 1]


# --- internos -----------------------------------------------------------------------------------------------------

## Ano universal (já com a virada do dia do calendário) em que cai o marco da era.
static func _start_year(def: Dictionary, era: Dictionary) -> int:
	return Calendar.from_seconds(int(era["start"]) - int(def["day_offset"]))["year"]


static func _find_era(def: Dictionary, era_id: int) -> Dictionary:
	for e in def["eras"]:
		if e["era_id"] == era_id:
			return e
	return {}


## Segundos universais da data local, sem olhar a validade: {t} ou {status, reason}.
static func _local_seconds(def: Dictionary, era_id: int, year: int, month: int, day: int, hour: int, minute: int, second: int) -> Dictionary:
	if def["reliability"] == UNAVAILABLE:
		return {"status": UNAVAILABLE, "reason": "o autor marcou este calendário como sem conversão"}
	var era := _find_era(def, era_id)
	if era.is_empty():
		return {"status": INVALID, "reason": "este calendário não usa essa era"}
	var start_year := _start_year(def, era)
	var universal_year: int = start_year + (year - int(era["first"]) if era["direction"] == "up" else int(era["first"]) - year)
	var u := Calendar.to_seconds(universal_year, month, day, hour, minute, second)
	if u == Calendar.INVALID:
		return {"status": INVALID, "reason": "essa data não existe neste calendário"}
	return {"t": u + int(def["day_offset"])}


## O instante precisa estar num período em que o calendário usa a era.
static func _check_range(def: Dictionary, era_id: int, t: int) -> Dictionary:
	for e in def["eras"]:
		if e["era_id"] == era_id and e["valid_from"] <= t and t < e["valid_to"]:
			return {"status": OK, "t": t}
	return {"status": OUT_OF_RANGE, "reason": "a era não é usada por este calendário nessa data"}
