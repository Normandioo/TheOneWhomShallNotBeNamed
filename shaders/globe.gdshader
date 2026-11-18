shader_type spatial;
// Especular só na água da cor natural (brilho do sol no mar); nas outras camadas SPECULAR = 0.

// O globo de Evron: uma camada de imagem (ou a altitude calibrada) sobre a esfera, com o relevo na iluminação.
// A posição na esfera vira lat/lon e daí a coordenada do mapa equiretangular (convenção de EvronGeo).

#include "res://shaders/relief.gdshaderinc"

uniform sampler2D layer_linear : source_color, filter_linear_mipmap_anisotropic, repeat_enable; // camada atual, valores contínuos
uniform sampler2D layer_nearest : source_color, filter_nearest, repeat_enable; // a mesma camada, para categorias
uniform bool nearest = false;
// Rios com largura em metros (tools/build_rivers.py; GlobeMaterial liga rivers_on quando os arquivos existem).
uniform bool rivers_on = false;
uniform sampler2D river_offset : filter_linear, repeat_enable; // km (leste, norte) até a linha central do rio
uniform sampler2D river_width : filter_linear, repeat_enable;  // largura: 0..1 = log de RIVER_W_MIN a RIVER_W_MAX
const float RIVER_W_MIN = 0.1; // km (build_rivers.W_MIN / W_MAX)
const float RIVER_W_MAX = 5.0;
uniform int mode = 0;            // 0 camada de imagem, 1 altitude calibrada, 2 cor natural (GlobeMaterial.MODES)
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

// Água do mar pela profundidade (h < 0): plataforma rasa clara, talude e fundo escuro, como nas imagens de satélite.
// Nos trópicos a água rasa e quente fica turquesa (areia clara e recife no fundo). `lat` em radianos.
vec3 water_color(float h, float lat) {
	float d = max(-h, 0.0);
	// Contraste baixo de propósito: o fundo do mar do Gleba é em degraus, e cores muito diferentes viram manchas.
	// Só a lâmina bem rasa (< ~200 m): a plataforma do Gleba é larga, e turquesa nela toda vira mancha clara.
	float reef = smoothstep(0.6, 0.35, abs(lat)) * (1.0 - smoothstep(15.0, 200.0, d));
	vec3 shelf = mix(vec3(0.06, 0.28, 0.46), vec3(0.07, 0.37, 0.47), reef);  // mais saturado: menos "água rasa pálida"
	vec3 col = mix(shelf, vec3(0.03, 0.15, 0.37), smoothstep(80.0, 2500.0, d));
	return mix(col, vec3(0.02, 0.08, 0.27), smoothstep(2000.0, 7000.0, d));
}

// Ruído de valor 3D com hash inteiro (o mesmo de tools/build_natural.py): sem padrão repetido em escala de planeta.
float hash3(ivec3 i) {
	uvec3 u = uvec3(i);
	uint h = (u.x * 0x8DA6B343u) ^ (u.y * 0xD8163841u) ^ (u.z * 0xCB1AB31Fu);
	h ^= h >> 15u; h *= 0x2C1B3C6Du; h ^= h >> 12u; h *= 0x297A2D39u; h ^= h >> 15u;
	return float(h) * (1.0 / 4294967295.0);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = p - i;
	vec3 u = f * f * (3.0 - 2.0 * f);
	ivec3 c = ivec3(i);
	float x00 = mix(hash3(c), hash3(c + ivec3(1, 0, 0)), u.x);
	float x10 = mix(hash3(c + ivec3(0, 1, 0)), hash3(c + ivec3(1, 1, 0)), u.x);
	float x01 = mix(hash3(c + ivec3(0, 0, 1)), hash3(c + ivec3(1, 0, 1)), u.x);
	float x11 = mix(hash3(c + ivec3(0, 1, 1)), hash3(c + ivec3(1, 1, 1)), u.x);
	return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z) * 2.0 - 1.0;
}

// Detalhe abaixo do pixel da imagem (6,4 km) até 50 m: oitavas que só entram quando cabem em ~3 pixels da tela,
// para não cintilar de longe. `pos_m` = posição na esfera em metros; `px_m` = metros por pixel da tela.
// Devolve x = variação de brilho (-1..1), y = deslocamento em metros (para o relevo fino).
vec2 fine_detail(vec3 pos_m, float px_m) {
	float wl = 6400.0;
	float amp = 1.0;
	vec2 acc = vec2(0.0);
	for (int o = 0; o < 8; o++) {
		float fade = clamp(wl / (3.0 * px_m) - 1.0, 0.0, 1.0);
		if (fade <= 0.0) {
			break;
		}
		float v = vnoise(pos_m / wl + float(o) * 17.31);
		acc += fade * vec2(amp * v, v * wl * 0.08);
		wl *= 0.5;
		amp *= 0.7;
	}
	return acc * vec2(0.45, 1.0);
}

// Normal entortada por um deslocamento `d` (mesma unidade de `pos`), pelas derivadas da tela (Mikkelsen 2010).
vec3 bump(vec3 N, vec3 pos, float d) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	vec3 r1 = cross(dpdy, N);
	vec3 r2 = cross(N, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(d) * r1 + dFdy(d) * r2);
	return normalize(abs(det) * N - grad);
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(obj_pos);
	vec2 uv = globe_uv(n);
	float h = height(uv);

	// textureLod 0: o uv dá um salto na longitude 180° e a derivada faria uma costura com mipmaps.
	vec3 col = nearest ? textureLod(layer_nearest, uv, 0.0).rgb : textureLod(layer_linear, uv, 0.0).rgb;
	vec3 geo_normal = NORMAL;
	float solid = 1.0;
	float detail_m = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	if (mode == 1) {
		col = pow(altitude_color(h), vec3(2.2)); // cores da legenda são sRGB; ALBEDO é linear
	} else if (mode == 2) {
		// A imagem de 8K tem mipmaps: de longe a média dos pixels, não um pixel ao acaso (que cintila).
		// Derivadas sem costura: na longitude 180° o u salta de 1 para 0; o u deslocado de meia volta não salta lá.
		vec2 dx = dFdx(uv), dy = dFdy(uv);
		vec2 uv2 = vec2(fract(uv.x + 0.5), uv.y);
		vec2 dx2 = dFdx(uv2), dy2 = dFdy(uv2);
		if (abs(dx2.x) + abs(dy2.x) < abs(dx.x) + abs(dy.x)) {
			dx = dx2;
			dy = dy2;
		}
		vec4 nat = textureGrad(layer_linear, uv, dx, dy);
		// natural.png: RGB = terra e gelo, A = superfície sólida. O resto é água: o mar pintado ao vivo pela altitude;
		// acima do nível do mar (lagos) a cor da água vem da imagem (doce ou salgada).
		solid = smoothstep(0.3, 0.7, nat.a);
		float lat = asin(clamp(n.y, -1.0, 1.0));
		vec3 water = h >= 0.0 ? nat.rgb : pow(water_color(h, lat), vec3(2.2));
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
		// Halo azul da atmosfera na borda do disco.
		EMISSION = vec3(0.10, 0.22, 0.55) * pow(1.0 - clamp(dot(geo_normal, VIEW), 0.0, 1.0), 4.0);
	}
	ALBEDO = col;
	NORMAL = relief_normal(n, uv, h, NORMAL, VIEW_MATRIX * MODEL_MATRIX);
	if (mode == 2) { // fora do if de `solid`: derivadas só valem em fluxo uniforme (na água detail_m = 0)
		// Deslocamento em unidades da cena (1 = 1000 km), com o mesmo exagero do relevo.
		NORMAL = bump(NORMAL, VERTEX, detail_m * relief * 1e-6);
	}
}
