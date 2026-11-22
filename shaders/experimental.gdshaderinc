// Cor natural: água do mar pela profundidade e grão fino sintetizado, comuns ao globo (globe.gdshader) e aos
// blocos de perto (globe_tile.gdshader, bloco "natural").

global uniform sampler2D satellite_optics : filter_linear, repeat_enable;
global uniform sampler2D satellite_river_atlas : filter_nearest, repeat_disable;
global uniform float satellite_optics_on;
global uniform float satellite_rivers_on;
global uniform sampler2D satellite_water_preview : filter_linear, repeat_disable;
// xy: centro em UV. zw: largura e altura do recorte. Zero desliga a prévia.
global uniform vec4 satellite_water_region;

// Água aberta pela batimetria. Temperatura e aporte de sedimentos modulam só a faixa rasa.
vec3 experimental_water_color(float h, float warm, float sediment, float coast) {
	float d = max(-h, 0.0);
	// A profundidade controla a transição principal. A máscara costeira só modula sua intensidade.
	float shallows = (1.0 - smoothstep(20.0, 520.0, d)) * mix(0.28, 0.52, smoothstep(0.0, 1.0, coast));
	vec3 deep = mix(vec3(0.041, 0.122, 0.214), vec3(0.028, 0.087, 0.164), smoothstep(700.0, 7200.0, d));
	vec3 shelf = mix(vec3(0.063, 0.196, 0.259), vec3(0.072, 0.289, 0.326), warm);
	vec3 ocean = mix(deep, shelf, shallows);
	return mix(ocean, vec3(0.275, 0.357, 0.297), sediment * (1.0 - smoothstep(65.0, 620.0, d)) * 0.64);
}

// Ruído de valor 3D com hash inteiro (o mesmo de tools/build_natural.py): sem padrão repetido em escala de planeta.
float experimental_hash3(ivec3 i) {
	uvec3 u = uvec3(i);
	uint h = (u.x * 0x8DA6B343u) ^ (u.y * 0xD8163841u) ^ (u.z * 0xCB1AB31Fu);
	h ^= h >> 15u; h *= 0x2C1B3C6Du; h ^= h >> 12u; h *= 0x297A2D39u; h ^= h >> 15u;
	return float(h) * (1.0 / 4294967295.0);
}

float experimental_vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = p - i;
	vec3 u = f * f * (3.0 - 2.0 * f);
	ivec3 c = ivec3(i);
	float x00 = mix(experimental_hash3(c), experimental_hash3(c + ivec3(1, 0, 0)), u.x);
	float x10 = mix(experimental_hash3(c + ivec3(0, 1, 0)), experimental_hash3(c + ivec3(1, 1, 0)), u.x);
	float x01 = mix(experimental_hash3(c + ivec3(0, 0, 1)), experimental_hash3(c + ivec3(1, 0, 1)), u.x);
	float x11 = mix(experimental_hash3(c + ivec3(0, 1, 1)), experimental_hash3(c + ivec3(1, 1, 1)), u.x);
	return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z) * 2.0 - 1.0;
}

// Detalhe abaixo do pixel da imagem até 50 m: oitavas que só entram quando cabem em ~3 pixels da tela,
// para não cintilar de longe. `pos_m` = posição na esfera em metros; `px_m` = metros por pixel da tela.
// Devolve x = variação de brilho (-1..1), y = deslocamento em metros (para o relevo fino).
vec2 experimental_fine_detail(vec3 pos_m, float px_m) {
	float wl = 6400.0;
	float amp = 1.0;
	vec2 acc = vec2(0.0);
	for (int o = 0; o < 8; o++) {
		float fade = clamp(wl / (3.0 * max(px_m, 0.1)) - 1.0, 0.0, 1.0);
		if (fade <= 0.0) {
			break;
		}
		float v = experimental_vnoise(pos_m / wl + float(o) * 17.31);
		acc += fade * vec2(amp * v, v * wl * 0.08);
		wl *= 0.5;
		amp *= 0.7;
	}
	return acc * vec2(0.45, 1.0);
}

vec4 river_texel(int address) {
	return texelFetch(satellite_river_atlas, ivec2(address % 1024, address / 1024), 0);
}

// Avalia cada trecho próximo separadamente. A união preserva curvas e confluências entre amostras e entre mosaicos.
// min_px = 0: o desenho do satélite (rio mais fino que um pixel some aos poucos). min_px > 0: a sobreposição "Rios em destaque": os rios largos para o
// zoom saem com min_px pixels de tela, os finos com 1 pixel (mais transparentes de longe).
float satellite_river(vec2 uv, float cos_lat, float pixel_km, float min_px) {
	ivec2 cell = ivec2(int(fract(uv.x) * 1024.0), clamp(int(uv.y * 512.0), 0, 511));
	ivec2 span = ivec2(texelFetch(satellite_river_atlas, cell, 0).rg);
	vec2 km = vec2(TAU * cos_lat, PI) * (RADIUS * 0.001);
	float aa = min(pixel_km, 20.0);
	float coverage = 0.0;
	for (int i = 0; i < min(span.y, 128); i++) {  // teto de trechos por célula; 32 picava os rios em tracinhos onde a célula é densa
		int address = span.x + i * 2;
		vec4 segment = river_texel(address);
		vec2 origin = vec2(fract(segment.x - uv.x + 0.5) - 0.5, segment.y - uv.y) * km;
		vec2 delta = segment.zw * km;
		float t = clamp(-dot(origin, delta) / max(dot(delta, delta), 1e-8), 0.0, 1.0);
		float distance_km = length(origin + t * delta);
		vec2 widths = river_texel(address + 1).rg;
		float width_km = mix(widths.x, widths.y, t);
		// Sobreposição: os rios largos para o zoom (largura acima de ~4-20% do pixel) levam o traço grosso; os finos ficam em 1 pixel e, de longe,
		// mais transparentes. A passagem é contínua (a largura varia ao longo do rio): um corte seco picaria o traço em tracinhos.
		float tier = min_px > 0.0 ? smoothstep(0.04, 0.2, width_km / pixel_km) : 0.0;
		float draw_px = min_px > 0.0 ? mix(1.0, min_px, tier) : 0.0;
		float line = clamp((0.5 * max(width_km, max(aa, pixel_km * draw_px)) - distance_km) / aa + 0.5, 0.0, 1.0);
		float fade = min_px > 0.0 ? mix(mix(1.0, 0.3, smoothstep(8.0, 30.0, pixel_km)), 1.0, tier) : min(1.0, width_km / pixel_km);
		coverage = max(coverage, line * fade);
		if (coverage >= 0.999) {
			break;
		}
	}
	return coverage;
}

// Sobreposição "Rios em destaque" em qualquer camada: os MESMOS rios do satélite experimental (satellite_river, trechos com largura de
// tools/build_indexed_rivers.py), em azul vivo. O traço nunca fica mais fino que 2,5 pixels de tela; a borda é
// endurecida para o traço ficar firme. color: azul na mesma escala (sRGB ou linear) de col.
global uniform float river_hl_on;

vec3 river_highlight(vec2 uv, vec3 col, vec3 color) {
	if (river_hl_on < 0.5) {
		return col;
	}
	float px_km = max(fwidth(uv.y) * 20015.0, 0.0001);  // km por pixel de tela
	float cos_lat = max(cos((0.5 - clamp(uv.y, 0.0, 1.0)) * PI), 0.02);
	float river = smoothstep(0.1, 0.6, satellite_river(uv, cos_lat, px_km, 3.0));
	return mix(col, color, river);
}

vec3 satellite_surface(vec4 texel, vec3 n, vec2 uv, float h, out float detail_m, out float wet) {
	// Mantém a borda na mesma isolinha. A largura segue o pixel da tela,
	// inclusive onde os texels se comprimem perto dos polos.
	float edge_width = clamp(0.55 * fwidth(texel.a), 0.008, 0.19);
	float solid = smoothstep(0.5 - edge_width, 0.5 + edge_width, texel.a);
	vec4 optics = vec4(0.0, 1.0 - smoothstep(0.28, 0.70, abs(asin(clamp(n.y, -1.0, 1.0)))), h >= 0.0 ? 1.0 : 0.0, 0.35);
	if (satellite_optics_on > 0.5) {
		float pole = 0.5 / float(textureSize(satellite_optics, 0).y);
		optics = texture(satellite_optics, vec2(uv.x, clamp(uv.y, pole, 1.0 - pole)));
	}
	float water_height = h;
	float coast_weight = optics.a;
	float preview_coverage = 0.0;
	if (satellite_water_region.z > 0.0) {
		vec2 offset = uv - satellite_water_region.xy;
		offset.x = fract(offset.x + 0.5) - 0.5;
		vec2 local_uv = offset / satellite_water_region.zw + 0.5;
		vec4 preview = texture(satellite_water_preview, local_uv);
		float coverage = preview.b;
		preview_coverage = coverage;
		water_height = mix(h, -preview.r, coverage);
		coast_weight = mix(optics.a, preview.g, coverage);
	}
	vec3 ocean = pow(experimental_water_color(water_height, optics.g, optics.r, coast_weight), vec3(2.2));
	// Terra x mar pela costa do mapa político (a mesma linha em todas as camadas); onde a água de pré-visualização cobre, vale a dela.
	bool coast_known;
	float coast_w = coast_land(uv, coast_known);
	float land_w = smoothstep(0.22, 0.67, optics.b);
	if (coast_known) {
		land_w = mix(coast_w, land_w, preview_coverage);
	}
	vec3 water = mix(ocean, texel.rgb, land_w);
	if (preview_coverage < 0.5) {
		solid = coast_clip(uv, solid);
	}
	vec3 pos_m = n * RADIUS;
	float px_m = length(fwidth(pos_m));
	vec2 grain = experimental_fine_detail(pos_m, px_m);
	float relief_strength = mix(0.22, 0.68, smoothstep(250.0, 2800.0, h));
	vec3 color = mix(water, texel.rgb * (1.0 + 0.16 * grain.x), solid);
	detail_m = grain.y * relief_strength * solid;
	float river = 0.0;
	if (satellite_rivers_on > 0.5 && solid > 0.0) {
		float cos_lat = sqrt(max(0.0, 1.0 - n.y * n.y));
		river = satellite_river(uv, cos_lat, max(px_m * 0.001, 0.0001), 0.0) * solid;
		color = mix(color, pow(vec3(0.093, 0.196, 0.211), vec3(2.2)), river);
		detail_m *= 1.0 - river;
	}
	wet = max(1.0 - solid, river);
	return color;
}

// Normal entortada por um deslocamento `d` (mesma unidade de `pos`), pelas derivadas da tela (Mikkelsen 2010).
vec3 experimental_bump(vec3 N, vec3 pos, float d) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	vec3 r1 = cross(dpdy, N);
	vec3 r2 = cross(N, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(d) * r1 + dFdy(d) * r2);
	return normalize(abs(det) * N - grad);
}
