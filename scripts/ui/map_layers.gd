## As camadas do mapa: nome no menu, arquivo em data/evron/ e legenda. A ordem é a do menu.
## "kind": "image" mostra o PNG do arquivo; "altitude" pinta a altitude calibrada no shader (globe.gdshader).
## "nearest": cores que são categorias ou identificadores (sem misturar pixels vizinhos).
## Legenda: "items" = cores soltas; "gradient" = [offsets, cores] com 3 rótulos (esquerda, centro, direita).
## Os valores vêm da calibração (docs/calibracao): a confiança de cada uma está lá e no texto da legenda.

const VIRIDIS := [Color(0.267, 0.005, 0.329), Color(0.279, 0.175, 0.483), Color(0.230, 0.322, 0.546), Color(0.173, 0.449, 0.558),
	Color(0.128, 0.567, 0.551), Color(0.158, 0.684, 0.502), Color(0.369, 0.789, 0.383), Color(0.678, 0.864, 0.190), Color(0.993, 0.906, 0.144)]
const MAGMA := [Color(0.001, 0.000, 0.014), Color(0.113, 0.065, 0.277), Color(0.317, 0.072, 0.485), Color(0.513, 0.148, 0.508),
	Color(0.716, 0.215, 0.475), Color(0.904, 0.320, 0.388), Color(0.987, 0.536, 0.382), Color(0.997, 0.770, 0.535), Color(0.987, 0.991, 0.750)]
const NINE := [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0]
# Altitude: o mar ocupa a metade esquerda e a terra a direita, então 0 m fica no centro (mesmos pontos do shader).
const ALTITUDE_OFFSETS := [0.0, 0.499, 0.5, 0.62, 0.78, 0.92, 1.0]
const ALTITUDE_COLORS := [Color(0.02, 0.05, 0.25), Color(0.45, 0.7, 0.9), Color(0.25, 0.55, 0.25), Color(0.85, 0.8, 0.45),
	Color(0.6, 0.4, 0.25), Color(0.85, 0.82, 0.8), Color(0.98, 0.98, 0.98)]

const T_RAIN := "Média do mês em mm (Average = média mensal, não total anual). Estimado pelas regras de Köppen: confiança média. Roxo-escuro abaixo do início = menos de 20 mm."
const T_HUM := "Umidade do Gleba (valor interno × 100). Faixa suposta, sem regra física para conferir: confiança baixa."
const T_REL := "Só a ordem dos valores é conhecida (0 a 1); a unidade ainda não foi calibrada."
const T_IDS := "Cada cor é uma entidade diferente (identificador), não um valor."

static var LAYERS := [  # static var (não const): Color8 não é aceito em expressão constante
	{"group": "Visão geral", "menu": "Satélite", "file": "Satelite.png", "kind": "image", "title": "Cor natural",
		"text": "Aparência aproximada do planeta, gerada pelo Gleba. Não representa uma variável medida."},
	{"group": "Relevo", "menu": "Altitude (calibrada)", "kind": "altitude", "title": "Altitude",
		"text": "Altitude de Evron em metros, da calibração do projeto. O mar ocupa a metade esquerda da escala.",
		"gradient": [ALTITUDE_OFFSETS, ALTITUDE_COLORS], "labels": ["−13.500 m", "0 m", "+9.103 m"]},
	{"group": "Relevo", "menu": "Elevação (cores do Gleba)", "file": "Elevação.png", "kind": "image", "title": "Elevação do Gleba",
		"text": "Paleta hipsométrica original do Gleba, inclui gelo. Para valores, use Altitude (calibrada)."},
	{"group": "Relevo", "menu": "Elevação sem gelo", "file": "Elevation no Ice Age.png", "kind": "image", "title": "Elevação sem gelo",
		"text": "Relevo sem a cobertura de gelo, em faixas do Gleba."},
	{"group": "Relevo", "menu": "Elevação na era glacial", "file": "Elevation Ice Age.png", "kind": "image", "title": "Era glacial",
		"text": "Elevação e gelo no último máximo glacial do Gleba."},
	{"group": "Relevo", "menu": "Declividade (Gleba)", "file": "Slope.png", "kind": "image", "title": "Declividade do Gleba",
		"text": "Referência: o projeto vai recalcular a declividade com a altitude e o raio de Evron.",
		"gradient": [NINE, VIRIDIS], "labels": ["plano", "", "íngreme"]},

	{"group": "Clima", "menu": "Temperatura — janeiro", "file": "Temperatura Janeiro.png", "kind": "image", "title": "Temperatura de janeiro",
		"text": "Média do mês. Calibrada pelos limiares de Köppen (erro ≤ 0,5 °C). O início da escala significa −20 °C ou menos.",
		"gradient": [NINE, MAGMA], "labels": ["≤ −20 °C", "+10 °C", "+40 °C"]},
	{"group": "Clima", "menu": "Temperatura — julho", "file": "Temperatura Julho.png", "kind": "image", "title": "Temperatura de julho",
		"text": "Média do mês. Calibrada pelos limiares de Köppen (erro ≤ 0,5 °C). O início da escala significa −20 °C ou menos.",
		"gradient": [NINE, MAGMA], "labels": ["≤ −20 °C", "+10 °C", "+40 °C"]},
	{"group": "Clima", "menu": "Chuva — média mensal", "file": "Average Rainfall.png", "kind": "image", "title": "Chuva média por mês",
		"text": T_RAIN, "gradient": [NINE, VIRIDIS], "labels": ["20 mm", "169 mm", "318 mm"]},
	{"group": "Clima", "menu": "Chuva — janeiro", "file": "January Rainfall.png", "kind": "image", "title": "Chuva de janeiro",
		"text": T_RAIN, "gradient": [NINE, VIRIDIS], "labels": ["20 mm", "169 mm", "318 mm"]},
	{"group": "Clima", "menu": "Chuva — julho", "file": "July Rainfall.png", "kind": "image", "title": "Chuva de julho",
		"text": T_RAIN, "gradient": [NINE, VIRIDIS], "labels": ["20 mm", "169 mm", "318 mm"]},
	{"group": "Clima", "menu": "Umidade — média", "file": "Umidade Média.png", "kind": "image", "title": "Umidade média",
		"text": T_HUM, "gradient": [NINE, VIRIDIS], "labels": ["0%", "50%", "100%"]},
	{"group": "Clima", "menu": "Umidade — janeiro", "file": "Umidade Janeiro.png", "kind": "image", "title": "Umidade de janeiro",
		"text": T_HUM, "gradient": [NINE, VIRIDIS], "labels": ["0%", "50%", "100%"]},
	{"group": "Clima", "menu": "Umidade — julho", "file": "Umidade Julho.png", "kind": "image", "title": "Umidade de julho",
		"text": T_HUM, "gradient": [NINE, VIRIDIS], "labels": ["0%", "50%", "100%"]},
	{"group": "Clima", "menu": "Clima de Köppen", "file": "Clima.png", "kind": "image", "nearest": true, "title": "Köppen-Geiger",
		"text": "Paleta padrão de Beck et al. (2018); as 24 classes estão em docs/calibracao.", "items": [
		[Color8(0, 0, 255), "Af equatorial"], [Color8(70, 169, 255), "Aw savana"], [Color8(255, 0, 0), "BWh deserto quente"],
		[Color8(245, 163, 0), "BSh estepe quente"], [Color8(198, 255, 78), "Cfa subtropical úmido"], [Color8(102, 255, 51), "Cfb oceânico"],
		[Color8(56, 199, 255), "Dfb continental"], [Color8(0, 126, 126), "Dfc subártico"], [Color8(178, 178, 178), "ET tundra"],
		[Color8(104, 104, 104), "EF gelo"]]},
	{"group": "Clima", "menu": "Sombra de chuva", "file": "Rain shadows.png", "kind": "image", "title": "Sombra de chuva",
		"text": T_REL, "gradient": [NINE, VIRIDIS], "labels": ["fraca", "", "forte"]},
	{"group": "Clima", "menu": "Continentalidade", "file": "Continentalism.png", "kind": "image", "title": "Continentalidade",
		"text": "Caráter continental do clima (escala do Gleba, não calibrada)."},
	{"group": "Clima", "menu": "Ventos", "file": "Ventos.png", "kind": "image", "title": "Ventos de superfície",
		"text": "Pressão e sentido do vento nas costas.", "items": [
		[Color(0.3, 0.45, 0.9), "Alta pressão"], [Color(0.95, 0.85, 0.3), "Baixa pressão"],
		[Color(0.9, 0.15, 0.1), "Costa: vento da terra para o mar"], [Color(0.15, 0.3, 0.95), "Costa: vento do mar para a terra"]]},
	{"group": "Clima", "menu": "Correntes oceânicas", "file": "Oceano.png", "kind": "image", "title": "Correntes oceânicas",
		"text": "Correntes do Gleba; as cores não têm valores documentados."},
	{"group": "Clima", "menu": "ZCIT", "file": "ITCZ.png", "kind": "image", "nearest": true, "title": "Zona de convergência intertropical",
		"text": "Posição da ZCIT no momento da exportação."},
	{"group": "Clima", "menu": "Altas subtropicais", "file": "STHZ.png", "kind": "image", "nearest": true, "title": "Altas pressões subtropicais",
		"text": "Posição da faixa no momento da exportação."},
	{"group": "Clima", "menu": "Frente polar", "file": "polar front.png", "kind": "image", "nearest": true, "title": "Frente polar",
		"text": "Posição da frente polar no momento da exportação."},

	{"group": "Ecologia", "menu": "Biomas", "file": "BiomasGleba.png", "kind": "image", "nearest": true, "title": "Biomas do Gleba",
		"text": "Classificação própria do Gleba (100% das cores conferidas). Deserto e terreno rochoso têm a mesma cor.", "items": [
		[Color8(255, 246, 213), "Deserto / rochoso"], [Color8(135, 222, 205), "Tundra"], [Color8(236, 236, 236), "Geleira"],
		[Color8(44, 160, 90), "Taiga"], [Color8(0, 85, 0), "Floresta de coníferas"], [Color8(113, 200, 55), "Floresta temperada mista"],
		[Color8(205, 222, 135), "Estepe"], [Color8(200, 113, 55), "Mediterrânea"], [Color8(198, 175, 233), "Campos de montanha"],
		[Color8(255, 221, 85), "Savana"], [Color8(212, 170, 0), "Floresta tropical seca"], [Color8(68, 120, 33), "Floresta tropical úmida"],
		[Color8(255, 255, 255), "Água"]]},
	{"group": "Ecologia", "menu": "Vegetação", "file": "Vegetação.png", "kind": "image", "title": "Composição da vegetação",
		"text": "Canais de cor misturados: quanto mais forte, maior a fração.", "items": [
		[Color(0.1, 0.8, 0.1), "Gramíneas"], [Color(0.85, 0.1, 0.1), "Arbustos"], [Color(0.1, 0.2, 0.9), "Árvores"], [Color(0, 0, 0), "Sem vegetação"]]},

	{"group": "Solos", "menu": "Textura do solo", "file": "Soil Texture.png", "kind": "image", "title": "Textura do solo",
		"text": "Canais de cor misturados.", "items": [
		[Color(0.9, 0.1, 0.1), "Areia"], [Color(0.1, 0.8, 0.1), "Silte"], [Color(0.1, 0.2, 0.9), "Argila"]]},
	{"group": "Solos", "menu": "Riqueza do solo", "file": "Soil Richness.png", "kind": "image", "title": "Riqueza do solo",
		"text": "Índice de nutrientes do Gleba. Faixa suposta: confiança baixa.", "gradient": [NINE, VIRIDIS], "labels": ["0%", "50%", "100%"]},
	{"group": "Solos", "menu": "Espessura do solo", "file": "Soil Depth.png", "kind": "image", "title": "Espessura do solo",
		"text": T_REL, "gradient": [NINE, VIRIDIS], "labels": ["rasa", "", "profunda"]},
	{"group": "Solos", "menu": "Permeabilidade do solo", "file": "Soil Permeability.png", "kind": "image", "title": "Permeabilidade do solo",
		"text": T_REL, "gradient": [NINE, VIRIDIS], "labels": ["baixa", "", "alta"]},

	{"group": "Hidrologia", "menu": "Terra e água", "file": "Landmask.png", "kind": "image", "nearest": true, "title": "Terra e água",
		"text": "Máscara do contorno (medida no arquivo).", "items": [[Color8(80, 80, 80), "Terra"], [Color8(30, 30, 30), "Água"]]},
	{"group": "Hidrologia", "menu": "Rios principais", "file": "River.png", "kind": "image", "nearest": true, "title": "Rios principais",
		"text": "Rios selecionados por um corte do fluxo de água.", "items": [[Color8(254, 231, 36), "Rio"], [Color8(68, 1, 84), "Terra"]]},
	{"group": "Hidrologia", "menu": "Fluxo de água", "file": "Waterflow.png", "kind": "image", "title": "Fluxo de água",
		"text": "Água que atravessa cada ponto (sem unidade no Gleba). " + T_REL, "gradient": [NINE, VIRIDIS], "labels": ["pouco", "", "muito"]},
	{"group": "Hidrologia", "menu": "Corpos de água", "file": "Waterbodies.png", "kind": "image", "nearest": true, "title": "Corpos de água",
		"text": T_IDS},
	{"group": "Hidrologia", "menu": "Bacias endorreicas", "file": "Bacias Endorreicas.png", "kind": "image", "nearest": true,
		"title": "Bacias endorreicas", "text": "Bacias sem saída para o mar, máximos (vermelho) e mínimos (verde) locais de altitude."},
	{"group": "Hidrologia", "menu": "Drenagem (Gleba)", "file": "Downflow.png", "kind": "image", "title": "Drenagem",
		"text": "Diagnóstico de drenagem do Gleba; depende da célula escolhida na exportação."},
	{"group": "Hidrologia", "menu": "Aquíferos", "file": "Aquiferos.png", "kind": "image", "nearest": true, "title": "Aquíferos", "text": T_IDS},
	{"group": "Hidrologia", "menu": "Profundidade dos aquíferos", "file": "Profundidade de Aquíferos.png", "kind": "image",
		"title": "Profundidade dos aquíferos", "text": "Faixa do guia do Gleba (0 a 1.500 m); linearidade suposta.",
		"gradient": [NINE, VIRIDIS], "labels": ["0 m", "750 m", "1.500 m"]},
	{"group": "Hidrologia", "menu": "Espessura dos aquíferos", "file": "Aquifer Thickness.png", "kind": "image",
		"title": "Espessura dos aquíferos", "text": "Faixa do guia do Gleba (0 a 100 m); linearidade suposta.",
		"gradient": [NINE, VIRIDIS], "labels": ["0 m", "50 m", "100 m"]},
	{"group": "Hidrologia", "menu": "Distância ao oceano", "file": "Inacessibilidade.png", "kind": "image", "title": "Inacessibilidade",
		"text": "Distância ao oceano do Gleba; será recalculada sobre a esfera de Evron.", "gradient": [NINE, VIRIDIS], "labels": ["costa", "", "interior"]},

	{"group": "Geologia", "menu": "Rocha do substrato", "file": "Bedrock.png", "kind": "image", "nearest": true, "title": "Rocha do substrato",
		"text": "37 tipos de rocha do guia do Gleba (100% conferidos); no mar a cor fica 5x mais escura. Tabela completa no guia."},
	{"group": "Geologia", "menu": "Placas tectônicas", "file": "Placas tectonicas.png", "kind": "image", "nearest": true,
		"title": "Placas tectônicas", "text": T_IDS},
	{"group": "Geologia", "menu": "Microplacas", "file": "Microplacas.png", "kind": "image", "nearest": true, "title": "Microplacas", "text": T_IDS},
	{"group": "Geologia", "menu": "Limites de placas", "file": "Plate Boundaries.png", "kind": "image", "title": "Limites de placas",
		"text": "Limites e colisões; as cores não identificam o tipo de limite."},
	{"group": "Geologia", "menu": "Orogenia", "file": "Orogeny Strenght.png", "kind": "image", "title": "Intensidade da orogenia",
		"text": T_REL, "gradient": [NINE, VIRIDIS], "labels": ["fraca", "", "forte"]},
	{"group": "Geologia", "menu": "Vulcanismo", "file": "Vulcanismo.png", "kind": "image", "nearest": true, "title": "Vulcanismo",
		"text": "Nomes prováveis (hipótese). A versão escura de cada cor parece ser atividade menor.", "items": [
		[Color8(0, 250, 50), "Arco / montanha"], [Color8(255, 255, 255), "Zona de colisão"], [Color8(250, 0, 0), "Rifte / dorsal"],
		[Color8(250, 150, 0), "Ponto quente"]]},
	{"group": "Geologia", "menu": "Províncias geológicas", "file": "Provincias geologicas.png", "kind": "image", "nearest": true,
		"title": "Províncias geológicas", "text": "Nomes prováveis (hipótese).", "items": [
		[Color8(50, 50, 50), "Crosta continental / plataforma"], [Color8(136, 153, 170), "Bacia oceânica"],
		[Color8(170, 187, 204), "Crosta oceânica 2"], [Color8(204, 221, 238), "Crosta oceânica 3"],
		[Color8(153, 255, 204), "Orógeno"], [Color8(153, 102, 153), "Grande província ígnea"]]},

	{"group": "Organização", "menu": "Regiões geográficas", "file": "Geographic Regions.png", "kind": "image", "nearest": true,
		"title": "Regiões geográficas", "text": "Unidades do Gleba do tamanho de ducados. " + T_IDS},
	{"group": "Organização", "menu": "Super-regiões", "file": "Geographic Superregions.png", "kind": "image", "nearest": true,
		"title": "Super-regiões", "text": "Unidades do Gleba do tamanho de reinos. " + T_IDS},
	{"group": "Organização", "menu": "Subcontinentes", "file": "Geographic Subcontinents.png", "kind": "image", "nearest": true,
		"title": "Subcontinentes", "text": "Unidades do Gleba do tamanho de impérios. " + T_IDS},
	{"group": "Organização", "menu": "Latitude e longitude", "file": "Latitude Longitude.png", "kind": "image", "title": "Latitude e longitude",
		"text": "Diagnóstico do Gleba; as coordenadas oficiais vêm da projeção do mapa."},
]
