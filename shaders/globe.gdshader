shader_type spatial;
render_mode specular_disabled;

// O globo de Evron: uma camada de imagem (ou a altitude calibrada) sobre a esfera, com o relevo na iluminação.
// A posição na esfera vira lat/lon e daí a coordenada do mapa equiretangular (convenção de EvronGeo).

#include "res://shaders/relief.gdshaderinc"
#include "res://shaders/brush.gdshaderinc"
#include "res://shaders/political.gdshaderinc"

uniform sampler2D layer_linear : source_color, filter_linear_mipmap, repeat_enable;   // camada atual, valores contínuos
uniform sampler2D layer_nearest : source_color, filter_nearest, repeat_enable; // a mesma camada, para categorias
uniform bool nearest = false;
uniform int mode = 0;            // 0 camada de imagem, 1 altitude calibrada, 2 cor natural, 3 temperatura sazonal, 4 mapa político (GlobeMaterial.MODES)
uniform sampler2D coast_map : filter_linear, repeat_enable;  // mapa político: R = distância com sinal até a costa em km (+ terra), G = lago (Terrain.CoastImage)
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

// Água pela profundidade (h < 0): plataforma rasa clara, talude e fundo escuro, como nas imagens de satélite.
// Lagos acima do nível do mar não têm profundidade nos dados: cor de lago fixa.
vec3 water_color(float h) {
	if (h >= 0.0) return vec3(0.10, 0.24, 0.33);
	float d = -h;
	// Contraste baixo de propósito: o fundo do mar do Gleba é em degraus, e cores muito diferentes viram manchas.
	vec3 col = mix(vec3(0.11, 0.31, 0.43), vec3(0.05, 0.17, 0.34), smoothstep(80.0, 2500.0, d));
	return mix(col, vec3(0.03, 0.09, 0.24), smoothstep(2000.0, 7000.0, d));
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

// A cor do país no mapa: a do cadastro, bem menos saturada e com o brilho puxado para ~0,45 (os tons médios e terrosos da referência).
vec3 map_tone(vec3 c) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 m = mix(vec3(l), c, 0.45) * vec3(1.04, 0.98, 0.9);  // um pouco mais quente
	return clamp(m * (mix(l, 0.45, 0.8) / max(l, 0.05)), 0.0, 1.0);
}

// O mar pela raiz da profundidade (m): #3a6a77 no raso a #0b1722 no fundo.
vec3 sea_ramp(float depth) {
	float s = sqrt(max(depth, 0.0));
	vec3 c = mix(vec3(0.227, 0.416, 0.467), vec3(0.165, 0.325, 0.388), smoothstep(0.0, 8.0, s));
	c = mix(c, vec3(0.114, 0.239, 0.306), smoothstep(8.0, 16.0, s));
	c = mix(c, vec3(0.075, 0.157, 0.227), smoothstep(16.0, 30.0, s));
	c = mix(c, vec3(0.055, 0.118, 0.169), smoothstep(30.0, 50.0, s));
	return mix(c, vec3(0.043, 0.090, 0.133), smoothstep(50.0, 80.0, s));
}

vec3 political_style(vec3 n, vec2 uv, float h) {
	vec2 c = textureLod(coast_map, vec2(uv.x, clamp(uv.y, 0.0, 1.0)), 0.0).rg;
	float d = c.r;
	float km_px = max(fwidth(d), 0.001);  // km por pixel de tela (o campo é uma distância)
	float line;
	int id = political_owner(uv, 1.4, line);
	// Terra: o país (ou a terra sem dono, #a08a62) sob o sombreado; a sombra puxa para um marrom escuro; fronteira #1a1716.
	vec3 base = id != 0 ? map_tone(political_color(id).rgb) : vec3(0.627, 0.541, 0.384);
	float t = map_shade(n, uv) - 1.0;
	float lit = clamp(t, 0.0, 0.6), dark = clamp(-t, 0.0, 0.85);
	vec3 land = base * (1.0 + 0.4 * lit) * (1.0 - 0.62 * dark) + dark * 0.10 * vec3(0.165, 0.102, 0.078);
	land = mix(land, vec3(0.102, 0.090, 0.086), line * 0.9);
	// Água: mar pela profundidade, lago de cor fixa; halo claro e anéis paralelos à costa (somem quando o pixel passa de ~6 km).
	bool lake = c.g > 0.5;
	float dist = max(-d, 0.0);
	vec3 water = lake ? vec3(0.122, 0.306, 0.353) : sea_ramp(-h);
	water = mix(water, lake ? vec3(0.298, 0.522, 0.565) : vec3(0.247, 0.455, 0.502), lake ? 0.3 * exp(-dist / 3.0) : 0.5 * exp(-dist / 14.0));
	vec3 ring_km = lake ? vec3(4.0, 9.0, -99.0) : vec3(10.0, 22.0, 38.0);
	vec3 ring_a = lake ? vec3(0.25, 0.15, 0.0) : vec3(0.32, 0.22, 0.13);
	float rings = 0.0;
	for (int k = 0; k < 3; k++) {
		rings = max(rings, ring_a[k] * (1.0 - smoothstep(0.4, 1.0, abs(dist - ring_km[k]) / km_px)));
	}
	water = mix(water, vec3(0.416, 0.604, 0.647), rings * smoothstep(6.0, 2.0, km_px));
	// Costa: troca de terra para água em um pixel e a linha escura #15191c.
	vec3 col = mix(water, land, smoothstep(-0.5 * km_px, 0.5 * km_px, d));
	return mix(col, vec3(0.082, 0.098, 0.110), 0.85 * (1.0 - smoothstep(0.45, 1.0, abs(d) / km_px)));
}

void vertex() {
	obj_pos = VERTEX;
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
	if (mode == 1) {
		col = pow(altitude_color(h), vec3(2.2)); // cores da legenda são sRGB; ALBEDO é linear
	} else if (mode == 2) {
		// natural.png: RGB = terra e gelo, A = superfície sólida. O resto é água, pintada ao vivo pela altitude.
		float solid = smoothstep(0.3, 0.7, lin.a);
		col = mix(pow(water_color(h), vec3(2.2)), col, solid);
		// Halo azul da atmosfera na borda do disco.
		EMISSION = vec3(0.10, 0.22, 0.55) * pow(1.0 - clamp(dot(geo_normal, VIEW), 0.0, 1.0), 4.0);
	}
	if (mode == 3) {
		vec2 tuv = vec2(uv.x, clamp(uv.y, 0.0, 1.0));
		float c = mix(textureLod(temp_jan, tuv, 0.0).r, textureLod(temp_jul, tuv, 0.0).r, season_july);
		col = textureLod(temp_ramp, vec2(clamp((c + 20.0) / 60.0, 0.0, 1.0), 0.5), 0.0).rgb;
	}
	if (mode == 4) {
		// Cor pronta, com a luz de mapa já dentro: vai na emissão, sem o sol (só um leve escurecer na borda do disco).
		float r = textureLod(river_map, vec2(uv.x, clamp(uv.y, 0.0, 1.0)), 0.0).r;
		vec3 m = mix(political_style(n, uv, h), vec3(0.478, 0.663, 0.714), smoothstep(0.12, 0.35, r));
		ALBEDO = vec3(0.0);
		EMISSION = brush_preview(n, pow(m, vec3(2.2))) * mix(0.8, 1.0, clamp(dot(geo_normal, VIEW), 0.0, 1.0));
	} else {
		ALBEDO = col;
		ALBEDO = river_paint(uv, ALBEDO);
		ALBEDO = political_paint(uv, ALBEDO);
		ALBEDO = brush_preview(n, ALBEDO);
		NORMAL = relief_normal(n, uv, h, NORMAL, VIEW_MATRIX * MODEL_MATRIX);
	}
	ROUGHNESS = 1.0;
}
