## Os perfis prontos de recurso: um ponto de partida com indícios que somam aptidão. A aptidão mínima fica ao menos 10% longe das
## somas que decidem, para uma mudança pequena de peso não virar o resultado. Os PESOS E LIMITES SÃO ESCOLHAS DE PROJETO,
## sem calibração. As ligações entre rocha e recurso vêm de resumos de busca de material do USGS (o site recusou a leitura das
## páginas completas em 25/11/2026): ver docs/recursos/perfis.md. Nada aqui diz o que existe no mundo.

## Cada indício em palavras de quem não estudou geologia (aparece no cartão "Por que aqui?").
const PLAIN := {
	"Granodiorito ou diorito": "Rochas de magma que esfriou no fundo da terra. Esta regra as liga ao cobre.",
	"Andesito ou dacito": "Rochas de lava, de regiões vulcânicas.",
	"Cinturão de montanhas": "Região onde a terra foi dobrada e erguida em serras (o nome desta camada do mapa é uma hipótese).",
	"Vulcanismo de arco a até 300 km": "Há vulcanismo por perto, do tipo ligado ao encontro de placas (o tipo é uma hipótese do mapa).",
	"Granito": "Rocha dura de magma que esfriou no fundo da terra. Esta regra a liga ao estanho.",
	"Skarn": "Rocha que se forma quando o calor do magma transforma o calcário vizinho.",
	"Sílex": "Rocha dura rica em sílica, que aparece junto de certas camadas de ferro. Sozinha é um sinal fraco.",
	"Quartzito, xisto verde ou rocha verde": "Rochas transformadas por calor e pressão.",
	"Dolomito": "Rocha parecida com o calcário. Aqui é só um reforço pequeno.",
	"Halita (sal-gema)": "O próprio sal em forma de rocha.",
	"Clima árido": "Lugar seco, onde a água evapora.",
	"Árido e quase plano": "Planície seca, onde a água pode parar, evaporar e deixar o sal.",
}

const PROFILES := [
	{"name": "Cobre", "about": "Cobre de pórfiro: rochas intrusivas intermediárias em arco vulcânico. Não cobre o cobre em rochas sedimentares.",
		"rule": {"output": "area", "count": 20, "size_km": 150.0, "min_score": 50, "prefer": [
			{"name": "Granodiorito ou diorito", "rocks": ["granodiorito", "diorito"], "weight": 40},
			{"name": "Andesito ou dacito", "rocks": ["andesito", "dacito"], "weight": 30},
			{"name": "Cinturão de montanhas", "provinces": ["orogeno"], "weight": 30},
			{"name": "Vulcanismo de arco a até 300 km", "volcanoes": ["arco"], "volcano_km": 300.0, "weight": 30}]}},
	{"name": "Estanho", "about": "Estanho ligado a granitos e a skarn, melhor em cinturões de montanhas. Não cobre os depósitos em cascalho de rio.",
		"rule": {"output": "area", "count": 12, "size_km": 200.0, "min_score": 45, "prefer": [
			{"name": "Granito", "rocks": ["granito"], "weight": 50},
			{"name": "Skarn", "rocks": ["skarn"], "weight": 50},
			{"name": "Cinturão de montanhas", "provinces": ["orogeno"], "weight": 35}]}},
	{"name": "Ferro", "about": "Ferro em formações bandadas (sílex e rochas metamórficas) e em skarn. Os mapas não dão a idade das rochas: é o perfil mais fraco.",
		"rule": {"output": "area", "count": 25, "size_km": 150.0, "min_score": 35, "prefer": [
			{"name": "Sílex", "rocks": ["silex"], "weight": 40},
			{"name": "Quartzito, xisto verde ou rocha verde", "rocks": ["quartzito", "xisto_verde", "rocha_verde"], "weight": 60},
			{"name": "Skarn", "rocks": ["skarn"], "weight": 60},
			{"name": "Dolomito", "rocks": ["dolomito"], "weight": 10}]}},
	{"name": "Sal", "about": "Sal em lugar seco e plano ou em halita. Bacias fechadas não entram: o mapa delas não tem legenda.",
		"rule": {"output": "area", "count": 15, "size_km": 200.0, "min_score": 60, "prefer": [
			{"name": "Halita (sal-gema)", "rocks": ["halita"], "weight": 70},
			{"name": "Clima árido", "climates": ["B"], "weight": 40},
			{"name": "Árido e quase plano", "climates": ["B"], "slope_max": 0.3, "weight": 30}]}},
]
