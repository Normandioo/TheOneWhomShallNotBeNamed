// A camada política, comum ao globo e aos blocos: cada pixel do mapa tem UM dono (o id de um país) e a cor do país cobre o seu território, com uma linha
// escura onde dois países se encontram. Parâmetros globais (project.godot, shader_globals), escritos por GlobeMaterial:
//   political_map     RG8, mesma grade da altitude: dono = r + 256·g (0 = ninguém)
//   political_palette RGBA8 de 256×256: a cor do país de id = (x = id & 255, y = id >> 8); alfa 0 = sem país (um dono que foi apagado fica sem cor)
//   political_on      1 = mostra a camada, 0 = esconde
// A borda é suavizada: cada ponto olha os 4 pixels em volta e fica com o dono de maior peso (interpolação bilinear dos pesos), o que troca os degraus
// por diagonais; a linha vale onde o segundo colocado é de outro país e a disputa está quase empatada.
global uniform sampler2D political_map;
global uniform sampler2D political_palette;
global uniform float political_on;

int political_id(ivec2 p, ivec2 size) {
	vec2 rg = texelFetch(political_map, ivec2(((p.x % size.x) + size.x) % size.x, clamp(p.y, 0, size.y - 1)), 0).rg;
	return int(rg.r * 255.0 + 0.5) + 256 * int(rg.g * 255.0 + 0.5);
}

vec4 political_color(int id) {
	return texelFetch(political_palette, ivec2(id & 255, id >> 8), 0);
}

// Pesos da B-spline cúbica nas posições −1, 0, 1 e 2 em volta de t (somam 1).
vec4 political_bspline(float t) {
	float t2 = t * t, t3 = t2 * t;
	return vec4((1.0 - t) * (1.0 - t) * (1.0 - t), 3.0 * t3 - 6.0 * t2 + 4.0, -3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0, t3) / 6.0;
}

// O dono suavizado em uv (0 = ninguém ou país sem cor) e a força da linha de borda com outro país (0..1). width: largura da linha em pixels de tela.
// Cada um dos 4×4 pixels em volta vota com o peso da B-spline cúbica: a borda sai em curva (sem a escada nem as diagonais da grade de 4K) e passa
// a menos de meio pixel de onde a camada a põe.
int political_owner(vec2 uv, float width, out float line) {
	line = 0.0;
	ivec2 size = textureSize(political_map, 0);
	vec2 p = vec2(uv.x * float(size.x), clamp(uv.y, 0.0, 1.0) * float(size.y)) - 0.5;
	float texels_per_pixel = max(length(fwidth(p)), 0.0001);  // antes de qualquer desvio: derivada fora de fluxo condicional
	ivec2 i0 = ivec2(floor(p)) - 1;
	vec4 wx = political_bspline(fract(p.x)), wy = political_bspline(fract(p.y));
	int ids[16];
	float w[16];
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			ids[j * 4 + i] = political_id(i0 + ivec2(i, j), size);
			w[j * 4 + i] = wx[i] * wy[j];
		}
	}
	// O voto de cada candidato = soma dos pesos dos pixels que têm o mesmo id; o primeiro e o segundo colocados.
	float best = -1.0, second = 0.0;
	int best_id = -1, second_id = -1;
	for (int k = 0; k < 16; k++) {
		if (ids[k] == best_id || ids[k] == second_id) {
			continue;
		}
		float s = 0.0;
		for (int j = 0; j < 16; j++) {
			s += ids[j] == ids[k] ? w[j] : 0.0;
		}
		if (s > best) {
			second = best;
			second_id = best_id;
			best = s;
			best_id = ids[k];
		} else if (s > second) {
			second = s;
			second_id = ids[k];
		}
	}
	if (best_id <= 0 || political_color(best_id).a < 0.5) {
		return 0;
	}
	// A linha de borda onde o segundo colocado é outro país com cor. Numa borda reta a diferença entre os votos cresce 4/3 por texel (a B-spline
	// vale 2/3 no centro): daí a distância à borda em pixels de tela. (A derivada de tela da diferença salta onde o segundo colocado troca.)
	if (second_id > 0 && political_color(second_id).a > 0.5) {
		line = 1.0 - smoothstep(0.5 * width - 0.5, 0.5 * width + 0.5, (best - second) * 0.75 / texels_per_pixel);  // largura total ≈ width
	}
	return best_id;
}

vec3 political_paint(vec2 uv, vec3 col) {
	float line;
	int id = political_owner(uv, 2.0, line);
	if (political_on < 0.5 || id == 0) {
		return col;
	}
	vec3 country = pow(political_color(id).rgb, vec3(2.2)); // a paleta guarda cor sRGB; ALBEDO é linear
	return mix(mix(col, country, 0.55), country * 0.22, line * 0.9);
}
