## Os perfis prontos de recurso: um ponto de partida com indícios que somam aptidão. A aptidão mínima fica ao menos 10% longe das
## somas que decidem, para uma mudança pequena de peso não virar o resultado. A densidade (quantidade por km²) é um ponto de partida inventado. Os PESOS E LIMITES SÃO ESCOLHAS DE PROJETO,
## sem calibração. As ligações entre rocha e recurso vêm de resumos de busca de material do USGS (o site recusou a leitura das
## páginas completas em 25/11/2026): ver docs/recursos/perfis.md. Nada aqui diz o que existe no mundo.

## Cada indício em palavras de quem não estudou geologia (aparece no cartão "Por que aqui?").
const PLAIN := {
	"Granodiorito ou diorito": "Rochas de magma que esfriou no fundo da terra. É onde se forma o cobre de pórfiro, a maior fonte de cobre.",
	"Andesito ou dacito": "Rochas de lava de regiões vulcânicas, acima dessas intrusões.",
	"Cinturão de montanhas": "Região onde a terra foi dobrada e erguida em serras (o nome desta camada do mapa é uma hipótese).",
	"Vulcanismo de arco a até 300 km": "Há vulcanismo por perto, do tipo ligado ao encontro de placas (o tipo é uma hipótese do mapa).",
	"Granito": "Rocha dura de magma que esfriou no fundo da terra. O estanho aparece em certos granitos.",
	"Skarn": "Rocha que se forma quando o calor do magma transforma o calcário vizinho; guarda estanho e ferro.",
	"Granito perto de rio grande": "O rio desgasta o granito e acumula o estanho no cascalho: a maior parte do estanho do mundo vem desses cascalhos.",
	"Rocha verde, xisto verde ou anfibolito": "Rochas de cinturões muito antigos, onde costumam estar as formações de ferro em faixas.",
	"Ferro de pântano": "Em brejos e beiras de rio de clima temperado ou frio, a água deixa o ferro no fundo. Foi o ferro dos povos do norte.",
	"Laterita": "Em clima quente e úmido, a chuva lava a rocha e deixa uma crosta vermelha rica em ferro.",
	"Sílex": "Rocha rica em sílica que acompanha certas camadas de ferro. Sozinha não basta: é só um reforço.",
	"Halita (sal-gema)": "O próprio sal em forma de rocha.",
	"Lago em região árida": "Lago de lugar seco: a água evapora e o sal se acumula.",
	"Costa árida e plana": "Beira de mar seca e plana, onde a água do mar evapora em salinas.",
	"Clima árido": "Lugar seco, onde a água evapora.",
	"Planície perto de rio grande": "Terra plana que o rio inunda e fertiliza (planície aluvial): onde a agricultura antiga prosperou.",
	"Clima temperado": "Estações marcadas e chuva regular, bom para muitos cultivos.",
}

const PROFILES := [
	{"name": "Cobre", "about": "Cobre de pórfiro: rochas intrusivas intermediárias em arco vulcânico. Não cobre o cobre em rochas sedimentares.",
		"rule": {"output": "area", "count": 20, "size_km": 300.0, "auto": true, "density": 200.0, "min_score": 55, "prefer": [
			{"name": "Granodiorito ou diorito", "rocks": ["granodiorito", "diorito"], "weight": 45},
			{"name": "Andesito ou dacito", "rocks": ["andesito", "dacito"], "weight": 30},
			{"name": "Cinturão de montanhas", "provinces": ["orogeno"], "weight": 25},
			{"name": "Vulcanismo de arco a até 300 km", "volcanoes": ["arco"], "volcano_km": 300.0, "weight": 25}]}},
	{"name": "Estanho", "about": "Estanho em granitos, em skarn e no cascalho dos rios que descem do granito.",
		"rule": {"output": "area", "count": 12, "size_km": 300.0, "auto": true, "density": 50.0, "min_score": 55, "prefer": [
			{"name": "Granito", "rocks": ["granito"], "weight": 40},
			{"name": "Skarn", "rocks": ["skarn"], "weight": 55},
			{"name": "Cinturão de montanhas", "provinces": ["orogeno"], "weight": 30},
			{"name": "Granito perto de rio grande", "rocks": ["granito"], "water": ["rio"], "water_km": 20.0, "weight": 30}]}},
	{"name": "Ferro", "about": "Ferro de pântano, laterita, skarn e cinturões antigos. Os mapas não dão a idade das rochas.",
		"rule": {"output": "area", "count": 25, "size_km": 300.0, "auto": true, "density": 500.0, "min_score": 50, "prefer": [
			{"name": "Ferro de pântano", "climates": ["C", "D"], "water": ["lago", "rio"], "water_km": 20.0, "slope_max": 0.5, "weight": 55},
			{"name": "Laterita", "climates": ["A"], "rocks": ["basalto", "picrobasalto", "gabro", "diorito", "andesito"], "slope_max": 1.0, "weight": 55},
			{"name": "Skarn", "rocks": ["skarn"], "weight": 60},
			{"name": "Rocha verde, xisto verde ou anfibolito", "rocks": ["rocha_verde", "xisto_verde", "anfibolito"], "weight": 50},
			{"name": "Sílex", "rocks": ["silex"], "weight": 15}]}},
	{"name": "Sal", "about": "Sal-gema, lagos de região seca e salinas de costa árida.",
		"rule": {"output": "area", "count": 15, "size_km": 300.0, "auto": true, "density": 1000.0, "min_score": 60, "prefer": [
			{"name": "Halita (sal-gema)", "rocks": ["halita"], "weight": 70},
			{"name": "Lago em região árida", "climates": ["B"], "water": ["lago"], "water_km": 15.0, "weight": 60},
			{"name": "Costa árida e plana", "climates": ["B"], "water": ["mar"], "water_km": 10.0, "slope_max": 0.3, "weight": 60},
			{"name": "Clima árido", "climates": ["B"], "weight": 15}]}},
]
