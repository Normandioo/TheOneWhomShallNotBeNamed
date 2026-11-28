shader_type spatial;
// Especular só na água da cor natural (brilho do sol no mar); nas outras camadas SPECULAR = 0.

// O globo de Evron: uma camada de imagem (ou a altitude calibrada) sobre a esfera, com o relevo na iluminação.
// A posição na esfera vira lat/lon e daí a coordenada do mapa equiretangular (convenção de EvronGeo).

#include "res://shaders/relief.gdshaderinc"
#include "res://shaders/brush.gdshaderinc"
#include "res://shaders/political.gdshaderinc"
#include "res://shaders/natural.gdshaderinc"
#include "res://shaders/experimental.gdshaderinc"

uniform bool experimental = false;

uniform sampler2D layer_linear : source_color, filter_linear_mipmap_anisotropic, repeat_enable; // camada atual, valores contínuos
uniform sampler2D layer_nearest : source_color, filter_nearest, repeat_enable; // a mesma camada, para categorias
uniform bool nearest = false;
// Rios com largura em metros (tools/build_rivers.py; GlobeMaterial liga rivers_on quando os arquivos existem).
uniform bool rivers_on = false;
uniform sampler2D river_offset : filter_linear, repeat_enable; // km (leste, norte) até a linha central do rio
uniform sampler2D river_width : filter_linear, repeat_enable;  // largura: 0..1 = log de RIVER_W_MIN a RIVER_W_MAX
const float RIVER_W_MIN = 0.1; // km (build_rivers.W_MIN / W_MAX)
const float RIVER_W_MAX = 5.0;
uniform int mode = 0;            // 0 camada de imagem, 1 altitude calibrada, 2 cor natural, 3 temperatura sazonal, 4 mapa político (GlobeMaterial.MODES)
// Temperatura sazonal: °C de janeiro e de julho, misturados pelo peso de julho (SeasonalTemperature.july_weight) e só
// então pintados com a escala magma da legenda (misturar as cores da legenda daria valores sem sentido).
uniform sampler2D temp_jan : filter_linear, repeat_enable;
uniform sampler2D temp_jul : filter_linear, repeat_enable;
uniform sampler2D temp_ramp : source_color, filter_linear;
uniform float season_july = 0.0;
// Rampa da altitude: mesmos pontos de MapLayers.ALTITUDE_OFFSETS/COLORS (mar à esquerda do centro, terra à direita).
const float SEA_FLOOR = -13500.0;
const float PEAK = 9103.4;

varying vec3 obj_pos;
// Mapa plano: a mesma malha (uma grade de lat/lon com UV equiretangular) desdobrada no plano z = 0, com x = lon · raio e y = lat · raio.
// O fragmento continua lendo a direção da esfera (obj_pos): é o mesmo mapa, só a geometria muda.
uniform float flat_map = 0.0;
// Onde a água editada difere da do Gleba, costa e lagos (Terrain.CoastChangeImage): 1 = virou terra, 0,5 = virou água. Os mapas de imagem seguem a costa nova.
uniform sampler2D coast_change : hint_default_black, filter_nearest, repeat_enable;
// A mesma máscara com filtro e mipmaps: quanto de cada ponto mudou, sem os degraus de 10 km na borda da área editada.
uniform sampler2D coast_change_soft : hint_default_black, filter_linear_mipmap, repeat_enable;

vec3 altitude_color(float h) {
	float t = h < 0.0 ? 0.5 + 0.5 * h / -SEA_FLOOR : 0.5 + 0.5 * h / PEAK;
	t = clamp(t, 0.0, 1.0);
	if (t < 0.499) return mix(vec3(0.02, 0.05, 0.25), vec3(0.45, 0.7, 0.9), t / 0.499);
	if (t < 0.5) return vec3(0.45, 0.7, 0.9);
	if (t < 0.62) return mix(vec3(0.25, 0.55, 0.25), vec3(0.85, 0.8, 0.45), (t - 0.5) / 0.12);
	if (t < 0.78) return mix(vec3(0.85, 0.8, 0.45), vec3(0.6, 0.4, 0.25), (t - 0.62) / 0.16);
	if (t < 0.92) return mix(vec3(0.6, 0.4, 0.25), vec3(0.85, 0.82, 0.8), (t - 0.78) / 0.14);
	return mix(vec3(0.85, 0.82, 0.8), vec3(0.98, 0.98, 0.98), (t - 0.92) / 0.08);
}

// --- Mapa político (docs/mapa-politico.md, etapa 2): as cores e as medidas vêm de tools/mapa_politico.py, que as tirou da referência. Tudo em sRGB.

// Altura da terra (mar = 0) suavizada: média 2×2 de amostras bilineares a meio texel (spline quadrática). Sem isso o gradiente da bilinear muda
// de inclinação em cada texel e, de perto, o sombreado mostra facetas quadradas.
float land_smooth(vec2 uv, vec2 t) {
	return 0.25 * (max(height(uv + vec2(0.5, 0.5) * t), 0.0) + max(height(uv + vec2(-0.5, 0.5) * t), 0.0)
		+ max(height(uv + vec2(0.5, -0.5) * t), 0.0) + max(height(uv + vec2(-0.5, -0.5) * t), 0.0));
}

// Sombreado de mapa (1 = plano): luz fixa do noroeste a 40°, não o sol. Duas escalas: o relevo macio e bem exagerado (±2 texels) e um pouco do fino.
float map_shade(vec3 n, vec2 uv) {
	vec2 t = 1.0 / vec2(textureSize(height_map, 0));
	float coslat = max(sqrt(1.0 - n.y * n.y), 0.05);
	float ex = TAU * t.x * coslat * RADIUS, ey = PI * t.y * RADIUS;  // metros por texel (leste, norte)
	vec3 L = vec3(-0.5417, 0.5417, 0.6428);  // (leste, norte, cima), unitário
	float s = 0.0;
	for (int k = 1; k <= 2; k++) {
		float r = float(k);
		float gx = (land_smooth(uv + vec2(r * t.x, 0.0), t) - land_smooth(uv - vec2(r * t.x, 0.0), t)) / (2.0 * r * ex);
		float gy = (land_smooth(uv - vec2(0.0, r * t.y), t) - land_smooth(uv + vec2(0.0, r * t.y), t)) / (2.0 * r * ey);
		float exag = k == 2 ? 20.0 : 5.0;
		s += (k == 2 ? 0.75 : 0.25) * dot(normalize(vec3(-gx * exag, -gy * exag, 1.0)), L) / L.z;
	}
	return s;
}

// A cor do país no mapa (estilo Europa Universalis): a do cadastro, quase com a saturação cheia e o brilho puxado de leve para ~0,5. Os tons
// continuam variados entre países vizinhos; o que dá a cara terrosa é a borda interna, a altitude e o relevo por cima (political_style).
vec3 map_tone(vec3 c) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 m = mix(vec3(l), c, 1.35);
	return clamp(m * (mix(l, 0.55, 0.30) / max(l, 0.05)), 0.0, 1.0);
}

// O mar pela profundidade (m): azul acinzentado #4a7f96 no raso a azul-petróleo #1d4259 no fundo (estilo Europa Universalis).
vec3 sea_ramp(float depth) {
	return mix(vec3(0.290, 0.498, 0.588), vec3(0.114, 0.259, 0.349), pow(clamp(depth / 5000.0, 0.0, 1.0), 0.6));
}

// Ruído de valor com período inteiro (sem costura na longitude 180°): freq = ciclos no mapa todo, em u e v.
float pol_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float pol_noise(vec2 uv, vec2 freq) {
	vec2 p = vec2(uv.x * freq.x, clamp(uv.y, 0.0, 1.0) * freq.y);
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 i1 = i + 1.0;
	i = vec2(mod(i.x, freq.x), i.y);
	i1 = vec2(mod(i1.x, freq.x), i1.y);
	return mix(mix(pol_hash(i), pol_hash(vec2(i1.x, i.y)), f.x), mix(pol_hash(vec2(i.x, i1.y)), pol_hash(i1), f.x), f.y);
}

// Quão perto da borda do país (ou da costa) este ponto está, por dentro: 0 = longe, 1 = colado. Três anéis de 8 direções em volta (1,5, 3,5 e 6
// pixels do mapa, uns 15 a 60 km); conta quem é de outro país ou de ninguém. A província do mesmo país não conta.
float political_edge_cell(ivec2 c, ivec2 size, int top) {
	float acc = 0.0;
	for (int r = 0; r < 2; r++) {
		float radius = r == 0 ? 2.0 : 5.0;
		float count = 0.0;
		for (int k = 0; k < 8; k++) {
			float a = float(k) * 0.785398;
			count += political_top_id(political_id(c + ivec2(int(round(cos(a) * radius)), int(round(sin(a) * radius))), size)) != top ? 1.0 : 0.0;
		}
		acc += (r == 0 ? 0.55 : 0.45) * min(count / 4.0, 1.0);
	}
	return acc;
}

// Calculado nos 4 pixels do mapa em volta e interpolado: sem isso a sombra da borda sai em degraus do tamanho do pixel do mapa.
float political_edge(vec2 uv, int id) {
	ivec2 size = textureSize(political_map, 0);
	vec2 p = vec2(uv.x * float(size.x), clamp(uv.y, 0.0, 1.0) * float(size.y)) - 0.5;
	ivec2 c = ivec2(floor(p));
	vec2 f = fract(p);
	int top = political_top_id(id);
	float a = political_edge_cell(c, size, top), b = political_edge_cell(c + ivec2(1, 0), size, top);
	float d = political_edge_cell(c + ivec2(0, 1), size, top), e = political_edge_cell(c + ivec2(1, 1), size, top);
	return clamp(mix(mix(a, b, f.x), mix(d, e, f.x), f.y), 0.0, 1.0);
}

float pol_coast_dist(vec2 uv) {
	return textureLod(coast_map, vec2(uv.x, clamp(uv.y, 0.0, 1.0)), 0.0).r;
}

// A cor do país dono da costa mais perto, para tingir a água ao redor (como no Europa Universalis). amount (0..1) = fração das 5 amostras que acharam um país.
// O gradiente da distância aponta para a terra; as amostras abrem um leque para a cor do vizinho não deixar raios na água.
vec3 political_sea_tint(vec2 uv, float dist_km, out float amount) {
	amount = 0.0;
	vec2 ct = 1.0 / vec2(textureSize(coast_map, 0));
	vec2 g = vec2(pol_coast_dist(uv + vec2(ct.x, 0.0)) - pol_coast_dist(uv - vec2(ct.x, 0.0)),
		pol_coast_dist(uv + vec2(0.0, ct.y)) - pol_coast_dist(uv - vec2(0.0, ct.y)));
	if (length(g) < 0.0001) {
		return vec3(0.0);
	}
	vec2 dir = normalize(g);
	ivec2 size = textureSize(political_map, 0);
	vec2 p = vec2(uv.x * float(size.x), clamp(uv.y, 0.0, 1.0) * float(size.y));
	float reach = dist_km / 9.77 + 1.5;  // pixels do mapa até a costa (o pixel do mapa tem ~9,77 km no equador)
	vec3 acc = vec3(0.0);
	float found = 0.0;
	for (int k = 0; k < 5; k++) {
		float a = (float(k) - 2.0) * 0.28;
		vec2 v = vec2(cos(a) * dir.x - sin(a) * dir.y, sin(a) * dir.x + cos(a) * dir.y);
		int o = political_id(ivec2(floor(p + v * reach)), size);
		if (o > 0 && political_color(o).a > 0.5) {
			acc += map_tone(political_color(o).rgb);
			found += 1.0;
		}
	}
	amount = found / 5.0;
	return found > 0.0 ? acc / found : vec3(0.0);
}

vec3 political_style(vec3 n, vec2 uv, float h, vec2 frag) {
	vec2 c = textureLod(coast_map, vec2(uv.x, clamp(uv.y, 0.0, 1.0)), 0.0).rg;
	float d = c.r;
	float km_px = max(fwidth(d), 0.001);  // km por pixel de tela (o campo é uma distância)
	float line, sub;
	int id = political_owner(uv, 1.4, max(d, 0.0), line, sub);
	// Terra (estilo Europa Universalis): o país (ou a terra sem dono, pergaminho claro) com manchas suaves, as montanhas mais cinzentas, a borda por
	// dentro mais escura que o miolo e o relevo por cima. Fronteira marrom quase preta. Províncias têm a cor do país: só uma linha fina e discreta.
	// O país selecionado fica mais claro, com um aro de luz por dentro; os outros ficam um pouco apagados.
	float focus = id != 0 ? political_focus(id) : (political_selected != 0 ? -1.0 : 0.0);
	float edge = id != 0 ? political_edge(uv, id) : 0.0;
	vec3 base = id != 0 ? map_tone(political_color(id).rgb) : vec3(0.82, 0.76, 0.60);
	int aid = 0;
	if (area_on > 0.5) {  // uma área sobreposta: se o mapa de baixo são os países, eles ficam cinzas (a fronteira continua)
		aid = area_owner(uv);
		if (area_gray > 0.5 && area_gray < 1.5) {
			base = vec3(0.34 + 0.30 * dot(base, vec3(0.299, 0.587, 0.114)));
		}
	}
	float patch = pol_noise(uv, vec2(96.0, 48.0)) * 0.6 + pol_noise(uv, vec2(384.0, 192.0)) * 0.4 - 0.5;
	base *= 1.0 + patch * 0.16;
	base = mix(base, vec3(0.55, 0.54, 0.51), smoothstep(1300.0, 3900.0, h) * 0.20);
	base *= (1.0 - 0.26 * edge) * (1.0 + 0.05 * (1.0 - edge));
	if (focus > 0.5) {
		base = mix(base, vec3(1.0), 0.14);
	} else if (focus < -0.5) {
		base = mix(base, vec3(dot(base, vec3(0.299, 0.587, 0.114))), 0.35) * 0.85;
	}
	float t = map_shade(n, uv) - 1.0;
	float lit = clamp(t, 0.0, 0.6), dark = clamp(-t, 0.0, 0.85);
	vec3 land = base * (1.0 + 0.4 * lit) * (1.0 - 0.62 * dark) + dark * 0.10 * vec3(0.165, 0.102, 0.078);
	land = mix(land, land * 0.55, sub * (focus > 0.5 ? 0.85 : 0.4));
	if (focus > 0.5) {
		land += vec3(1.0, 0.95, 0.78) * edge * 0.30;
	}
	float dist_fade = 1.0 - 0.6 * smoothstep(4.0, 25.0, km_px);  // de longe as linhas afinam e ficam mais claras, sem ar de desenho animado
	land = mix(land, focus > 0.5 ? vec3(0.98, 0.93, 0.70) : land * 0.30, line * 0.75 * dist_fade);
	if (aid != 0) {
		vec3 tint = map_tone(area_color(aid).rgb) * (1.0 + 0.4 * lit) * (1.0 - 0.62 * dark);
		if (area_gray > 1.5) {  // reivindicação: listras diagonais de largura fixa na tela, com a cor do país de baixo entre elas
			float stripe = smoothstep(0.35, 0.5, abs(fract((frag.x + frag.y) / 12.0) - 0.5) * 2.0);
			land = mix(land, tint, 0.78 * stripe);
		} else {
			land = mix(land, tint, mix(0.6, 0.82, area_gray));
		}
	}
	// Água: mar pela profundidade com manchas; lago de cor fixa; halo claro na costa; perto da costa a água pega a cor do país dono.
	bool lake = c.g > 0.5;
	float dist = max(-d, 0.0);
	vec3 water = lake ? vec3(0.122, 0.306, 0.353) : sea_ramp(-h);
	float sea_patch = pol_noise(uv, vec2(120.0, 60.0)) * 0.6 + pol_noise(uv, vec2(420.0, 210.0)) * 0.4 - 0.5;
	water *= 1.0 + sea_patch * 0.20;
	water = mix(water, lake ? vec3(0.298, 0.522, 0.565) : vec3(0.525, 0.722, 0.776), lake ? 0.3 * exp(-dist / 3.0) : 0.40 * exp(-dist / 45.0));
	if (!lake && dist < 150.0) {
		float amount;
		vec3 tint = political_sea_tint(uv, dist, amount);
		water = mix(water, tint * 0.85, amount * 0.46 * exp(-dist / 60.0) * (1.0 - area_on * float(area_gray > 0.5 && area_gray < 1.5)));
	}
	// Costa: troca de terra para água em um pixel e a linha escura #15191c.
	vec3 col = mix(water, land, smoothstep(-0.5 * km_px, 0.5 * km_px, d));
	return mix(col, vec3(0.12, 0.14, 0.15), 0.85 * dist_fade * (1.0 - smoothstep(0.45, 1.0, abs(d) / km_px)));
}

void vertex() {
	obj_pos = VERTEX;
	if (flat_map > 0.5) {
		float r = length(VERTEX);
		VERTEX = vec3((UV.x - 0.5) * TAU * r, (0.5 - UV.y) * PI * r, 0.0);
		NORMAL = vec3(0.0, 0.0, 1.0);
	}
}

void fragment() {
	vec3 n = normalize(obj_pos);
	vec2 uv = globe_uv(n);
	float h = height(uv);

	// O u salta de 1 para 0 na longitude 180°, e a derivada desse salto escolheria o mipmap mais grosso (uma costura).
	// Usa as derivadas da coordenada deslocada meia volta, que não salta ali (método de Tarini).
	vec2 dx = dFdx(uv), dy = dFdy(uv);
	vec2 uv_alt = vec2(fract(uv.x + 0.5), uv.y);
	vec2 dx_alt = dFdx(uv_alt), dy_alt = dFdy(uv_alt);
	if (abs(dx_alt.x) + abs(dy_alt.x) < abs(dx.x) + abs(dy.x)) {
		dx = dx_alt;
		dy = dy_alt;
	}
	vec4 lin = textureGrad(layer_linear, uv, dx, dy);
	// Categorias sem mipmap: a média de cores de identificadores vizinhos seria uma cor que não existe.
	vec3 col = nearest ? textureLod(layer_nearest, uv, 0.0).rgb : lin.rgb;
	vec3 geo_normal = NORMAL;
	float solid = 1.0;
	float detail_m = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	if (mode == 1) {
		col = pow(altitude_color(h), vec3(2.2)); // cores da legenda são sRGB; ALBEDO é linear
	} else if (mode == 2) {
		vec4 nat = lin;
		if (experimental) {
			float wet;
			col = satellite_surface(nat, n, uv, h, detail_m, wet);
			SPECULAR = 0.14 * wet;
			ROUGHNESS = mix(1.0, 0.36, wet);
		} else {
		// natural.png: RGB = terra e gelo, A = superfície sólida. O resto é água: o mar pintado ao vivo pela altitude;
		// acima do nível do mar (lagos) a cor da água vem da imagem (doce ou salgada).
		solid = coast_clip(uv, smoothstep(0.3, 0.7, nat.a));
		float lat = asin(clamp(n.y, -1.0, 1.0));
		vec3 water = h >= 0.0 ? nat.rgb : pow(water_color(min(h, -30.0), lat), vec3(2.2));  // lago pintado: acima do mar, como água rasa
		// Detalhe fino na terra e no gelo: brilho e relevo que a imagem não tem (sintetizado, semente fixa).
		vec3 pos_m = n * RADIUS;
		float px_m = length(fwidth(pos_m));
		vec2 fd = fine_detail(pos_m, px_m);
		float rough = 0.35 + 0.65 * smoothstep(200.0, 2500.0, h); // montanha é mais áspera que planície
		col = nat.rgb * (1.0 + 0.22 * fd.x * solid);
		detail_m = fd.y * rough * solid;
		col = mix(water, col, solid);
		// Rio: o vetor até a linha central, interpolado entre texels, dá a distância certa em qualquer ponto; a margem
		// fica nítida com 100 m ou 5 km de largura. Mais fino que um pixel da tela, vira um traço de 1 pixel com
		// opacidade = largura / pixel (de longe o rio quase some, como nas fotos da órbita).
		float river = 0.0;
		if (rivers_on) {
			float dist_km = length(textureLod(river_offset, uv, 0.0).rg);
			float w_km = RIVER_W_MIN * pow(RIVER_W_MAX / RIVER_W_MIN, textureLod(river_width, uv, 0.0).r);
			float px_km = max(px_m * 0.001, 1e-4);
			float line_km = max(w_km, px_km);
			river = clamp((0.5 * line_km - dist_km) / px_km + 0.5, 0.0, 1.0) * min(1.0, w_km / px_km) * solid;
			col = mix(col, pow(vec3(0.08, 0.17, 0.20), vec3(2.2)), river);
			detail_m *= 1.0 - river;
		}
		// A água reflete o sol (o brilho que corre pelo oceano nas fotos da órbita); a terra não.
		float wet = max(1.0 - solid, river);
		SPECULAR = 0.35 * wet;
		ROUGHNESS = mix(1.0, 0.32, wet);
		}
		// Halo azul da atmosfera na borda do disco.
		EMISSION = vec3(0.10, 0.22, 0.55) * pow(1.0 - clamp(dot(geo_normal, VIEW), 0.0, 1.0), 4.0);
	}
	if (mode == 3) {
		vec2 tuv = vec2(uv.x, clamp(uv.y, 0.0, 1.0));
		float c = mix(textureLod(temp_jan, tuv, 0.0).r, textureLod(temp_jul, tuv, 0.0).r, season_july);
		col = textureLod(temp_ramp, vec2(clamp((c + 20.0) / 60.0, 0.0, 1.0), 0.5), 0.0).rgb;
	}
	// A costa editada nos mapas que vêm de imagem (o Gleba não sabe dela). Onde a água mudou, a linha terra × água é a costa suavizada
	// (a mesma do mapa político, não os pixels de 10 km); a água nova vai pela profundidade e a terra nova, no satélite, numa cor de terra
	// pela altitude e latitude, e nos mapas de dados num tom neutro (sem dado). A área editada se funde ao resto em vez de terminar em degrau.
	if (mode == 0 || mode == 2 || mode == 3) {
		vec2 cuv = vec2(uv.x, clamp(uv.y, 0.0, 1.0));
		float changed = clamp(textureLod(coast_change_soft, cuv, 1.0).r * 2.5, 0.0, 1.0);
		if (changed > 0.001) {
			float lat = asin(clamp(n.y, -1.0, 1.0));
			bool known;
			float land = coast_land(uv, known);
			if (!known) {
				land = textureLod(coast_change, cuv, 0.0).r > 0.75 ? 1.0 : 0.0;
			}
			vec3 water = pow(water_color(min(h, -30.0), lat), vec3(2.2));  // lago pintado: acima do mar, como água rasa
			vec3 ground = vec3(0.58, 0.54, 0.42);
			if (mode == 2) {
				ground = mix(vec3(0.31, 0.35, 0.19), vec3(0.47, 0.43, 0.35), smoothstep(300.0, 2500.0, h));
				ground = mix(ground, vec3(0.86, 0.88, 0.91), max(smoothstep(62.0, 72.0, abs(degrees(lat))), smoothstep(4200.0, 5200.0, h)));
			}
			col = mix(col, mix(water, pow(ground, vec3(2.2)), land), changed);
		}
	}
	if (mode == 4) {
		// Cor pronta, com a luz de mapa já dentro: vai na emissão, sem o sol (só um leve escurecer na borda do disco).
		float r = terrain_river_at(uv);
		vec3 m = mix(political_style(n, uv, h, FRAGCOORD.xy), vec3(0.478, 0.663, 0.714), smoothstep(0.12, 0.35, r));
		m = river_highlight(uv, m, vec3(0.05, 0.40, 0.90));
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		EMISSION = brush_preview(n, pow(m, vec3(2.2))) * mix(0.8, 1.0, clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	} else {
		ALBEDO = col;
		ALBEDO = river_paint(uv, ALBEDO);
		ALBEDO = river_highlight(uv, ALBEDO, pow(vec3(0.05, 0.40, 0.90), vec3(2.2)));
		ALBEDO = political_paint(uv, ALBEDO);
		ALBEDO = brush_preview(n, ALBEDO);
		NORMAL = relief_normal(n, uv, h, NORMAL, VIEW_MATRIX * MODEL_MATRIX);
		if (mode == 2) {
			NORMAL = bump(NORMAL, VERTEX, detail_m * relief * 1e-6);
		}
	}
}
