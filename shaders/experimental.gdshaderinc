// Cor natural: água do mar pela profundidade e grão fino sintetizado, comuns ao globo (globe.gdshader) e aos
// blocos de perto (globe_tile.gdshader, bloco "natural").

global uniform sampler2D satellite_optics : filter_linear, repeat_enable;
global uniform sampler2D satellite_river_atlas : filter_nearest, repeat_disable;
global uniform float satellite_optics_on;
global uniform float satellite_rivers_on;

// Água aberta pela batimetria. Temperatura e aporte de sedimentos modulam só a faixa rasa.
vec3 experimental_water_color(float h, float warm, float sediment, float coast) {
	float d = max(-h, 0.0);
	float shallows = (1.0 - smoothstep(10.0, 250.0, d)) * mix(0.19, 1.0, sqrt(coast));
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
float satellite_river(vec2 uv, float cos_lat, float pixel_km) {
	ivec2 cell = ivec2(int(fract(uv.x) * 1024.0), clamp(int(uv.y * 512.0), 0, 511));
	ivec2 span = ivec2(texelFetch(satellite_river_atlas, cell, 0).rg);
	vec2 km = vec2(TAU * cos_lat, PI) * (RADIUS * 0.001);
	float aa = min(pixel_km, 20.0);
	float coverage = 0.0;
	for (int i = 0; i < span.y; i++) {
		int address = span.x + i * 2;
		vec4 segment = river_texel(address);
		vec2 origin = vec2(fract(segment.x - uv.x + 0.5) - 0.5, segment.y - uv.y) * km;
		vec2 delta = segment.zw * km;
		float t = clamp(-dot(origin, delta) / max(dot(delta, delta), 1e-8), 0.0, 1.0);
		float distance_km = length(origin + t * delta);
		vec2 widths = river_texel(address + 1).rg;
		float width_km = mix(widths.x, widths.y, t);
		float line = clamp((0.5 * max(width_km, aa) - distance_km) / aa + 0.5, 0.0, 1.0);
		coverage = max(coverage, line * min(1.0, width_km / pixel_km));
		if (coverage >= 0.999) {
			break;
		}
	}
	return coverage;
}

vec3 satellite_surface(vec4 texel, vec3 n, vec2 uv, float h, out float detail_m, out float wet) {
	float solid = smoothstep(0.31, 0.69, texel.a);
	vec4 optics = vec4(0.0, 1.0 - smoothstep(0.28, 0.70, abs(asin(clamp(n.y, -1.0, 1.0)))), h >= 0.0 ? 1.0 : 0.0, 0.35);
	if (satellite_optics_on > 0.5) {
		float pole = 0.5 / float(textureSize(satellite_optics, 0).y);
		optics = texture(satellite_optics, vec2(uv.x, clamp(uv.y, pole, 1.0 - pole)));
	}
	vec3 ocean = pow(experimental_water_color(h, optics.g, optics.r, optics.a), vec3(2.2));
	vec3 water = mix(ocean, texel.rgb, smoothstep(0.22, 0.67, optics.b));
	vec3 pos_m = n * RADIUS;
	float px_m = length(fwidth(pos_m));
	vec2 grain = experimental_fine_detail(pos_m, px_m);
	float relief_strength = mix(0.22, 0.68, smoothstep(250.0, 2800.0, h));
	vec3 color = mix(water, texel.rgb * (1.0 + 0.16 * grain.x), solid);
	detail_m = grain.y * relief_strength * solid;
	float river = 0.0;
	if (satellite_rivers_on > 0.5 && solid > 0.0) {
		float cos_lat = sqrt(max(0.0, 1.0 - n.y * n.y));
		river = satellite_river(uv, cos_lat, max(px_m * 0.001, 0.0001)) * solid;
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
