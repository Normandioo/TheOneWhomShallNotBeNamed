// Cor natural: água do mar pela profundidade e grão fino sintetizado, comuns ao globo (globe.gdshader) e aos
// blocos de perto (globe_tile.gdshader, bloco "natural").

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

// Detalhe abaixo do pixel da imagem até 50 m: oitavas que só entram quando cabem em ~3 pixels da tela,
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
