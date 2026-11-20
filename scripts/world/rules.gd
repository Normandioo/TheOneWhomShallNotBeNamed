extends RefCounted
## Monta as definições de regra (o grafo de nós declarativo que o Registry valida e executa; formato em RegistryRules.cs).
## Usado pela janela de regras e pelos testes.

const VERSION := 1
const MATH := {"add": "+", "sub": "−", "mul": "×", "div": "÷", "min": "menor de", "max": "maior de"}
const COMPARE := {"gt": ">", "ge": "≥", "lt": "<", "le": "≤", "eq": "=", "ne": "≠"}


static func number(v: float) -> Dictionary:
	return {"op": "const", "value": v}


static func field(code: String) -> Dictionary:
	return {"op": "field", "code": code}


static func links(type: String) -> Dictionary:
	return {"op": "links", "type": type}


static func population() -> Dictionary:
	return {"op": "population"}


static func area() -> Dictionary:
	return {"op": "area"}


static func distance(to: int) -> Dictionary:
	return {"op": "distance", "to": to}


static func calc(a: Dictionary, op: String, b: Dictionary) -> Dictionary:
	return {"op": op, "a": a, "b": b}


static func when(a: Dictionary, compare: String, b: Dictionary, then: Dictionary, otherwise: Dictionary) -> Dictionary:
	return {"op": "if", "cond": {"op": compare, "a": a, "b": b}, "then": then, "else": otherwise}


static func rule(kind: String, target: String, expr: Dictionary) -> Dictionary:
	return {"version": VERSION, "kind": kind, "field": target, "expr": expr}


## A regra em uma linha legível (para a lista): os nomes dos campos e vínculos vêm de `names` (código -> nome).
static func describe(node: Dictionary, names: Dictionary) -> String:
	match String(node.get("op", "")):
		"const":
			return str(node.value)
		"field":
			return names.get(node.code, node.code)
		"links":
			return "nº de \"%s\"" % names.get(node.type, node.type)
		"population":
			return "população"
		"area":
			return "área (km²)"
		"distance":
			return "distância até %s (km)" % names.get("#%d" % int(node.to), "entidade %d" % int(node.to))
		"if":
			var c: Dictionary = node.cond
			return "se %s %s %s então %s senão %s" % [describe(c.a, names), COMPARE.get(c.op, c.op), describe(c.b, names),
				describe(node.then, names), describe(node["else"], names)]
		var op:
			if op in ["min", "max"]:
				return "%s(%s; %s)" % [MATH[op], describe(node.a, names), describe(node.b, names)]
			return "(%s %s %s)" % [describe(node.a, names), MATH.get(op, op), describe(node.b, names)]
