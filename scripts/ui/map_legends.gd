## Os modos de mapa: o nome no menu e a legenda de cada um.
## A ordem é a do uniform map_mode do shader (globe.gdshader): 0 normal, 1 temperatura, 2 político, 3 umidade,
## 4 vento, 5 correntes, 6 altitude, 7 massas de ar. Mudar a ordem aqui exige mudar o shader.
## "items" = cores soltas; "gradient" = degradê com 3 rótulos.

const MODES := [
	{"menu": "Mapa: normal", "title": "Mapa normal", "text": "O planeta como se vê do espaço.", "items": [
		[Color(0.8, 0.38, 0.22), "Terra seca"], [Color(0.01, 0.04, 0.25), "Oceano"],
		[Color(0.3, 0.5, 0.18), "Vegetação"], [Color(0.92, 0.94, 0.98), "Gelo e neve"], [Color(0.96, 0.96, 1.0), "Nuvens"]]},
	{"menu": "Mapa: temperatura", "title": "Temperatura do ar", "text": "Cai com a latitude e a altitude. Costas de correntes quentes ficam mais quentes.",
		"gradient": [Color(0.1, 0.2, 0.8), Color(0.95, 0.9, 0.3), Color(0.9, 0.15, 0.1)], "labels": ["-70 °C", "-20 °C", "+30 °C"]},
	{"menu": "Mapa: político", "title": "Político", "text": "Cada cor é o dono da região. Linhas escuras são as fronteiras.", "items": [
		[Color(0.2, 0.55, 1.0), "Você"], [Color(1.0, 0.3, 0.2), "Rival"], [Color(0.35, 0.3, 0.28), "Sem dono"]]},
	{"menu": "Mapa: umidade e chuva", "title": "Umidade e chuva", "text": "O vento leva o vapor do mar. Ele vira chuva quando o ar sobe e esfria: nas montanhas, nas frentes e nas pancadas. Amarelo suave: choveu há pouco. Laranja: está chovendo agora.", "items": [
		[Color(0.3, 0.2, 0.15), "Ar seco"], [Color(0.1, 0.4, 0.95), "Ar úmido"], [Color(1.0, 0.95, 0.3), "Chuva recente"], [Color(1.0, 0.4, 0.05), "Chovendo agora"]]},
	{"menu": "Mapa: vento", "title": "Vento", "text": "Seta mais comprida = vento mais forte. Nos trópicos o vento sopra de leste para oeste.", "items": [
		[Color(0.4, 0.95, 1.0), "Seta: para onde o ar vai"]]},
	{"menu": "Mapa: correntes oceânicas", "title": "Correntes oceânicas",
		"text": "Cor = temperatura do mar comparada à da sua latitude. Setas escuras = direção da corrente. Só existe onde há água líquida.",
		"gradient": [Color(0.15, 0.3, 0.9), Color(0.75, 0.85, 0.9), Color(0.95, 0.25, 0.15)], "labels": ["Fria", "Normal", "Quente"]},
	{"menu": "Mapa: altitude", "title": "Altitude", "text": "Altura do terreno acima do nível de referência de Marte (MOLA). Não depende do nível do mar: mostra também o fundo das bacias.", "items": [
		[Color(0.25, 0.12, 0.45), "Abaixo de -4 km"], [Color(0.15, 0.35, 0.7), "-4 a 0 km"], [Color(0.3, 0.62, 0.42), "0 a 2 km"],
		[Color(0.82, 0.78, 0.35), "2 a 5 km"], [Color(0.8, 0.45, 0.2), "5 a 9 km"], [Color(0.93, 0.9, 0.88), "Acima de 9 km"]]},
	{"menu": "Mapa: massas de ar", "title": "Massas de ar e frentes",
		"text": "O vento leva a temperatura de onde o ar veio. Cor = ar mais quente ou mais frio que o normal do lugar. Linhas fortes = frentes, onde uma massa avança sobre a outra e chove. Só aparecem com atmosfera grossa: no ar fino o ar esquece de onde veio.",
		"items": [[Color(0.15, 0.35, 0.95), "Massa fria"], [Color(0.95, 0.3, 0.12), "Massa quente"],
		[Color(0.02, 0.1, 0.7), "Frente fria"], [Color(0.85, 0.05, 0.05), "Frente quente"]]},
]
