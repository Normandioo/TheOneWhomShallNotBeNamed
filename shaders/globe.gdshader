shader_type spatial;
render_mode specular_disabled;

const int REGION_COUNT = 11; // = MarsGeo.REGIONS.size()
const float MARS_RADIUS = 3389500.0; // metros
const vec2 TEXEL = vec2(1.0 / 1440.0, 1.0 / 720.0);

uniform sampler2D height_map : filter_linear, repeat_enable; // altitude em metros (MOLA)
uniform float sea_level = -9000.0; // altitude em metros até onde a água líquida sobe
uniform float ice = 0.3;           // gelo no planeta (0..1): tamanho das calotas
uniform float cap_season = 0.0;    // -1..1: +1 = fim do inverno no norte (calota norte cresce, a sul encolhe)
uniform float temperature = 0.0;   // 0..1 (até ~1,58 com "Permitir extremos")
uniform float atmosphere = 0.0;    // 0..1 (até ~1,31 com "Permitir extremos")
uniform int map_mode = 0;          // 0 normal, 1 temperatura, 2 político, 3 umidade, 4 vento, 5 correntes, 6 altitude, 7 massas de ar
uniform vec3 region_dirs[REGION_COUNT];
uniform vec3 region_colors[REGION_COUNT];
uniform float color_steps = 10.0;  // posterização das cores (visual pixel art)
uniform float relief = 12.0;       // exagero do relevo na iluminação
const float LIGHT_BANDS = 4.0;     // faixas de luz (pixel art)
uniform sampler2D climate_map : filter_linear, repeat_enable; // R nuvem, G chuva, B vegetação, A umidade
uniform sampler2D wind_map : filter_linear, repeat_enable;    // RG vento, BA corrente oceânica (leste, norte)
uniform sampler2D temp_map : filter_linear, repeat_enable;    // R temperatura do ar (°C), G anomalia do mar (°C), B nuvem fina, A massa de ar (°C)
uniform sampler2D weather_map : filter_linear, repeat_enable; // R chuva de agora, G neve no chão, B frente (+ quente, - fria)
uniform float cloud_scale = 4.5;
uniform float hum_scale = 4.0;
uniform float rain_scale = 60.0;  // a chuva (média recente) vira cor por 1 - exp(-chuva * escala): não satura de repente
const vec2 GRID = vec2(144.0, 72.0); // = Climate.W, Climate.H
const float ARROW_BLOCK = 6.0;       // uma seta a cada 6 células

varying vec3 obj_pos;

float height(vec2 uv) {
	return textureLod(height_map, vec2(uv.x, clamp(uv.y, 0.0, 1.0)), 0.0).r;
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

vec3 temp_ramp(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 cold = vec3(0.1, 0.2, 0.8);
	vec3 mild = vec3(0.95, 0.9, 0.3);
	vec3 hot = vec3(0.9, 0.15, 0.1);
	return t < 0.5 ? mix(cold, mild, t * 2.0) : mix(mild, hot, t * 2.0 - 1.0);
}

// Seta no bloco de ARROW_BLOCK células deste ponto, apontando para onde o vento (ou a corrente) vai.
// max_sp = velocidade que dá a seta mais comprida; vetores quase nulos (terra, para correntes) não têm seta.
bool arrow(vec2 uv, bool use_current, float max_sp) {
	vec2 g = vec2(uv.x, clamp(uv.y, 0.001, 0.999)) * GRID / ARROW_BLOCK;
	vec2 p = fract(g) - 0.5;
	vec4 s = textureLod(wind_map, (floor(g) + 0.5) * ARROW_BLOCK / GRID, 0.0);
	vec2 w = use_current ? s.ba : s.rg;
	float sp = length(w);
	if (sp < 0.02) {
		return false;
	}
	vec2 dir = vec2(w.x, -w.y) / sp; // v norte = para cima na tela
	float along = dot(p, dir);
	float across = length(p - along * dir);
	float half_len = 0.25 + 0.2 * clamp(sp / max_sp, 0.0, 1.0);
	bool shaft = abs(along) < half_len && across < 0.08;
	bool head = along > half_len - 0.25 && along < half_len && across < (half_len - along) * 0.8;
	return shaft || head;
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 geo_normal = NORMAL;
	vec3 n = normalize(obj_pos);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float lon = atan(n.x, n.z);
	vec2 uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
	float h = height(uv);
	float hn = smoothstep(-7000.0, 9000.0, h); // altitude normalizada para cores
	float alat = abs(lat) / (PI * 0.5);         // 0 no equador, 1 no polo

	vec3 col = mix(vec3(0.45, 0.15, 0.09), vec3(0.85, 0.43, 0.25), hn);  // terra seca: mais vermelha (menos verde e azul que o laranja de antes)

	// Clima simulado: nuvem, chuva, vegetação e umidade.
	vec4 cs = textureLod(climate_map, vec2(uv.x, clamp(uv.y, 0.001, 0.999)), 0.0);

	// Vegetação cresce onde chove, em manchas.
	if (h >= sea_level && cs.b > vnoise(n * 25.0) * 0.9) {
		col = mix(vec3(0.2, 0.42, 0.15), vec3(0.4, 0.55, 0.2), hn);
		// Tundra: no frio a vegetação é musgo e líquen, mais pálida e acinzentada.
		float tund = smoothstep(8.0, -4.0, textureLod(temp_map, vec2(uv.x, clamp(uv.y, 0.001, 0.999)), 0.0).r);
		col = mix(col, vec3(0.45, 0.47, 0.36), tund);
	}

	// Neve no chão, em manchas como a vegetação.
	if (h >= sea_level && textureLod(weather_map, vec2(uv.x, clamp(uv.y, 0.001, 0.999)), 0.0).g > vnoise(n * 18.0) * 0.9 + 0.05) {
		col = mix(vec3(0.82, 0.86, 0.92), vec3(0.95, 0.96, 1.0), hn);
	}

	bool ocean = h < sea_level;
	if (ocean) {
		float depth = clamp((sea_level - h) / 3000.0, 0.0, 1.0);
		col = mix(vec3(0.02, 0.07, 0.29), vec3(0.0, 0.0, 0.2), depth);  // o mar da textura da Terra (Blue Marble): raso e fundo
	}

	// Calotas polares: crescem com o gelo do planeta e com o inverno de cada polo; borda irregular pelo ruído.
	// 0.337 de amplitude: sem gelo permanente, a calota de inverno chega a ~57° de latitude, como a de Marte hoje.
	if (alat > mix(0.97, 0.45, ice) - cap_season * sign(lat) * 0.337 + (vnoise(n * 9.0) - 0.5) * 0.1) {
		col = vec3(0.92, 0.94, 0.98);
	}

	// Nuvens: compositadas depois da pixelização do terreno (mais abaixo), pra ficarem macias
	// em vez de virar blocos poligonais junto com o resto do visual retrô.
	float cloud_alpha = 0.0;
	vec3 cloud_col = vec3(1.0);
	if (map_mode == 0 || map_mode == 4) {
		// A grade do clima é grossa (144x72 células, ~2,5° cada). cloud_scale amplia tanto a diferença
		// de uma célula pra outra que a borda da célula virava uma linha reta visível. Essa borradinha
		// de 5 amostras tira o degrau antes de medir a densidade.
		vec2 ct = 0.6 / GRID;
		vec2 cuv = vec2(uv.x, clamp(uv.y, 0.001, 0.999));
		float cloud_r = textureLod(climate_map, cuv, 0.0).r * 0.4
			+ textureLod(climate_map, cuv + vec2(ct.x, 0.0), 0.0).r * 0.15
			+ textureLod(climate_map, cuv - vec2(ct.x, 0.0), 0.0).r * 0.15
			+ textureLod(climate_map, cuv + vec2(0.0, ct.y), 0.0).r * 0.15
			+ textureLod(climate_map, cuv - vec2(0.0, ct.y), 0.0).r * 0.15;
		// Ruído em grade sozinho faz borda de célula virar linha reta visível ("cortado"). Distorcer a
		// amostragem com outro ruído mais largo curva essas bordas, em vez de evitar o problema só com escala.
		// Sem ruído fino aqui: a tela inteira é renderizada numa resolução baixa (Pixel Nx) e ampliada depois
		// (visual retrô de propósito), e qualquer detalhe mais fino que essa grade vira bagunça quadriculada.
		vec3 warp = vec3(vnoise(n * 6.0 + vec3(5.0, 1.0, 9.0)), vnoise(n * 6.0 + vec3(9.0, 3.0, 2.0)), vnoise(n * 6.0 + vec3(2.0, 7.0, 5.0))) - 0.5;
		float wisp = vnoise(n * 14.0 + warp * 2.5 + vec3(0.0, 0.0, 17.0)) - 0.5;  // forma principal, alongada
		float dens = cloud_r * cloud_scale + wisp * 0.6;
		cloud_alpha = smoothstep(0.35, 0.75, dens) * 0.92;
		cloud_col = mix(vec3(0.76, 0.80, 0.87), vec3(1.0, 1.0, 1.0), clamp(wisp + 0.6, 0.0, 1.0));
		// Nuvem fina (não chove): faixas e redemoinhos alongados no sentido leste-oeste, como os das latitudes médias.
		// O ruído é periódico em longitude (círculo no plano xy) e esticado em latitude, o que alonga as formas.
		float haze_r = textureLod(temp_map, cuv, 0.0).b * 0.4
			+ textureLod(temp_map, cuv + vec2(ct.x, 0.0), 0.0).b * 0.15
			+ textureLod(temp_map, cuv - vec2(ct.x, 0.0), 0.0).b * 0.15
			+ textureLod(temp_map, cuv + vec2(0.0, ct.y), 0.0).b * 0.15
			+ textureLod(temp_map, cuv - vec2(0.0, ct.y), 0.0).b * 0.15;
		vec3 hp = vec3(cos(lon) * 7.0, sin(lon) * 7.0, lat * 13.0);
		vec3 hwarp = vec3(vnoise(hp * 0.7 + vec3(3.0, 1.0, 7.0)), vnoise(hp * 0.7 + vec3(8.0, 2.0, 4.0)), vnoise(hp * 0.7 + vec3(1.0, 9.0, 5.0))) - 0.5;
		float hn = vnoise(hp + hwarp * 3.0 + vec3(0.0, 0.0, 31.0));
		// Sobre o mar, mais transparente: com 0,7 o oceano escuro virava cinza-azulado sob a névoa.
		float haze_alpha = smoothstep(0.4, 0.8, haze_r * 1.7 + (hn - 0.5)) * (ocean ? 0.3 : 0.7);
		cloud_alpha = 1.0 - (1.0 - cloud_alpha) * (1.0 - haze_alpha);
	}

	// Regiões: a mais próxima vence; a borda fica onde as duas mais próximas empatam.
	float best = -2.0;
	float second = -2.0;
	int idx = 0;
	for (int i = 0; i < REGION_COUNT; i++) {
		float d = dot(n, region_dirs[i]);
		if (d > best) {
			second = best;
			best = d;
			idx = i;
		} else if (d > second) {
			second = d;
		}
	}
	float border = 1.0 - smoothstep(0.0, 0.006, best - second);

	if (map_mode == 1) {
		// Temperatura simulada do ar: de -70 °C (azul) a +30 °C (vermelho).
		float tc = textureLod(temp_map, vec2(uv.x, clamp(uv.y, 0.001, 0.999)), 0.0).r;
		col = temp_ramp((tc + 70.0) / 100.0);
	} else if (map_mode == 2) {
		// Cor do dono, mantendo o relevo visível pela luminosidade.
		col = region_colors[idx] * (0.55 + 0.7 * dot(col, vec3(0.3, 0.5, 0.2)));
	} else if (map_mode == 3) {
		// Umidade do ar (azul) e chuva (amarelo).
		col = mix(col * 0.5, vec3(0.1, 0.4, 0.95), clamp(cs.a * hum_scale, 0.0, 1.0) * 0.8);
		// Chuva recente: amarelo suave; chuva caindo agora: laranja forte por cima.
		col = mix(col, vec3(1.0, 0.95, 0.3), (1.0 - exp(-cs.g * rain_scale)) * 0.55);
		col = mix(col, vec3(1.0, 0.4, 0.05), 1.0 - exp(-textureLod(weather_map, vec2(uv.x, clamp(uv.y, 0.001, 0.999)), 0.0).r * rain_scale));
	} else if (map_mode == 4) {
		col *= 0.6;
		if (arrow(uv, false, 3.0)) {
			col = vec3(0.4, 0.95, 1.0);
		}
	} else if (map_mode == 5) {
		// Correntes oceânicas: cor = anomalia de temperatura do mar, setas = direção da corrente.
		if (ocean) {
			float an = textureLod(temp_map, vec2(uv.x, clamp(uv.y, 0.001, 0.999)), 0.0).g;
			float t = clamp(0.5 + an / 30.0, 0.0, 1.0);
			vec3 neutral = vec3(0.75, 0.85, 0.9);
			col = t < 0.5 ? mix(vec3(0.15, 0.3, 0.9), neutral, t * 2.0) : mix(neutral, vec3(0.95, 0.25, 0.15), t * 2.0 - 1.0);
			if (arrow(uv, true, 0.5)) {
				col = vec3(0.05, 0.08, 0.25);
			}
		} else {
			col *= 0.45;
		}
	} else if (map_mode == 6) {
		// Altitude em faixas (a mesma escala da legenda): o nível do mar não conta, o fundo das bacias também aparece.
		col = h < -4000.0 ? vec3(0.25, 0.12, 0.45)
			: h < 0.0 ? vec3(0.15, 0.35, 0.7)
			: h < 2000.0 ? vec3(0.3, 0.62, 0.42)
			: h < 5000.0 ? vec3(0.82, 0.78, 0.35)
			: h < 9000.0 ? vec3(0.8, 0.45, 0.2)
			: vec3(0.93, 0.9, 0.88);
	} else if (map_mode == 7) {
		// Massas de ar: o quanto o ar que chegou é mais quente (vermelho) ou frio (azul) que o normal do lugar;
		// linhas fortes onde ele avança sobre outro (frente quente vermelha, fria azul).
		vec2 tuv = vec2(uv.x, clamp(uv.y, 0.001, 0.999));
		float t = clamp(0.5 + textureLod(temp_map, tuv, 0.0).a / 10.0, 0.0, 1.0);  // ±5 °C já é cor cheia
		vec3 neutral = vec3(0.8, 0.8, 0.78) * (0.6 + 0.5 * dot(col, vec3(0.3, 0.5, 0.2)));
		col = t < 0.5 ? mix(vec3(0.15, 0.35, 0.95), neutral, t * 2.0) : mix(neutral, vec3(0.95, 0.3, 0.12), t * 2.0 - 1.0);
		float fr = textureLod(weather_map, tuv, 0.0).b;
		col = mix(col, fr > 0.0 ? vec3(0.85, 0.05, 0.05) : vec3(0.02, 0.1, 0.7), smoothstep(0.05, 0.15, abs(fr)));
	}
	// A fronteira entre regiões só aparece no mapa político: fora dele, é uma linha fina e dura
	// demais, que cortava qualquer coisa clara por cima (nuvem, gelo) de um jeito estranho.
	col = mix(col, col * 0.35, border * (map_mode == 2 ? 1.0 : 0.0));

	ALBEDO = floor(col * color_steps + 0.5) / color_steps;
	if (cloud_alpha > 0.0) {
		ALBEDO = mix(ALBEDO, cloud_col, cloud_alpha);
	}
	ROUGHNESS = 1.0;

	// Relevo: a inclinação do terreno entorta a normal, e a luz realça crateras e vulcões.
	if (!ocean) {
		float coslat = max(cos(lat), 0.05);
		float gx = (height(uv + vec2(TEXEL.x, 0.0)) - height(uv - vec2(TEXEL.x, 0.0)))
			/ (2.0 * TAU * TEXEL.x * coslat * MARS_RADIUS);
		float gy = (height(uv - vec2(0.0, TEXEL.y)) - height(uv + vec2(0.0, TEXEL.y)))
			/ (2.0 * PI * TEXEL.y * MARS_RADIUS);
		vec3 up = n;
		vec3 east = vec3(1.0, 0.0, 0.0);
		vec3 north = vec3(0.0, 0.0, -1.0);
		vec3 c = cross(vec3(0.0, 1.0, 0.0), n);
		east = length(c) > 0.0001 ? normalize(c) : vec3(1.0, 0.0, 0.0);
		north = cross(n, east);
		vec3 pn = normalize(up - relief * (gx * east + gy * north));
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(pn, 0.0)).xyz);
	}

	// Atmosfera: brilho na borda do planeta, de poeira laranja a céu azul.
	float fres = pow(1.0 - clamp(dot(geo_normal, VIEW), 0.0, 1.0), 3.0);
	// Metade do que era: com mais, o brilho clareava o mar escuro até a metade do disco.
	EMISSION = mix(vec3(0.9, 0.5, 0.3), vec3(0.4, 0.65, 1.0), clamp(atmosphere, 0.0, 1.0)) * fres * (0.12 + atmosphere * 0.6);
}

void light() {
	// Luz em faixas, para combinar com a pixel art.
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	ndl = floor(ndl * LIGHT_BANDS + 0.6) / LIGHT_BANDS;
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / PI;
}
