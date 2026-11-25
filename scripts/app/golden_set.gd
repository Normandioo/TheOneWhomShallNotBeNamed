## O gabarito: os lugares que o autor julgou na avaliação às cegas ("faz sentido" ou "não faz") viram o teste de qualquer regra.
## Mede concordância com o julgamento do autor, não se há jazida. Um terço dos lugares fica reservado para o teste final: quem
## ajusta a regra olhando o resultado acaba "aprendendo" os lugares que vê.

const FEW := 5  # respostas mínimas de cada tipo para comparar


## As respostas de um recurso: {places: [{lat, lon, yes, reserved}], rule: a regra da avaliação mais recente ("" = não há)}.
## Um lugar julgado duas vezes vale pela última resposta; "Não sei" não entra.
static func load_set(path: String, resource_name: String) -> Dictionary:
	var latest := {}
	var rule := ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		file.get_csv_line()  # cabeçalho: data, recurso, regra, lat, lon, origem, resposta
		while not file.eof_reached():
			var line := file.get_csv_line()
			if line.size() < 7 or line[1].to_lower() != resource_name.to_lower():
				continue
			rule = line[2]
			var key := line[3] + " " + line[4]
			if line[6] in ["sim", "nao"]:
				latest[key] = {"lat": float(line[3]), "lon": float(line[4]), "yes": line[6] == "sim", "reserved": is_reserved(key)}
			else:
				latest.erase(key)
	return {"places": latest.values(), "rule": rule}


## Sempre o mesmo terço, decidido só pelas coordenadas (sha256 não muda entre versões do Godot; hash() não promete isso).
static func is_reserved(key: String) -> bool:
	return key.sha256_text().substr(0, 8).hex_to_int() % 3 == 0


## accepted: um valor por lugar (a aptidão da regra ali; 0 = recusa). Devolve {yes, yes_total, no, no_total, agreement},
## com yes = aprovados que a regra aceita, no = rejeitados que ela recusa e agreement = a média das duas proporções (0..1),
## para que aceitar tudo, ou recusar tudo, valha só 50%.
static func measure(places: Array, accepted: PackedInt32Array) -> Dictionary:
	var out := {"yes": 0, "yes_total": 0, "no": 0, "no_total": 0, "agreement": 0.0}
	for i in places.size():
		if places[i].yes:
			out.yes_total += 1
			out.yes += 1 if accepted[i] > 0 else 0
		else:
			out.no_total += 1
			out.no += 1 if accepted[i] == 0 else 0
	if out.yes_total > 0 and out.no_total > 0:
		out.agreement = (float(out.yes) / out.yes_total + float(out.no) / out.no_total) / 2.0
	return out


## O resultado em palavras. before = a regra da avaliação; now = a regra na tela.
static func report(now: Dictionary, before: Dictionary, same_rule: bool, final_test: bool) -> String:
	var title := "Teste final (parte reservada)" if final_test else "Gabarito"
	if now.yes_total < FEW or now.no_total < FEW:
		return "%s: poucas respostas para comparar (%d aprovados, %d rejeitados; são precisos %d de cada)." % [
			title, now.yes_total, now.no_total, FEW]
	var text := "%s: aceita %d de %d aprovados e recusa %d de %d rejeitados. Concordância: %d%% (aceitar ou recusar tudo daria 50%%)." % [
		title, now.yes, now.yes_total, now.no, now.no_total, roundi(100 * now.agreement)]
	if same_rule:
		return text + "\nÉ a mesma regra que você avaliou."
	var change: float = now.agreement - before.agreement
	var verdict := "Melhorou" if change > 0.0001 else ("Piorou" if change < -0.0001 else "Empatou")
	var moved: int = absi(now.yes - before.yes) + absi(now.no - before.no)
	text += "\n%s em relação à regra avaliada (%d%%)." % [verdict, roundi(100 * before.agreement)]
	if moved > 0 and moved <= 2:
		text += " A diferença é de poucos lugares: pode ser acaso."
	return text
