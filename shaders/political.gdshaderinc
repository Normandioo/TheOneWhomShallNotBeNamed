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

vec3 political_paint(vec2 uv, vec3 col) {
	if (political_on < 0.5) {
		return col;
	}
	ivec2 size = textureSize(political_map, 0);
	vec2 p = vec2(uv.x * float(size.x), clamp(uv.y, 0.0, 1.0) * float(size.y)) - 0.5;
	ivec2 i0 = ivec2(floor(p));
	vec2 f = fract(p);
	int ids[4] = int[4](political_id(i0, size), political_id(i0 + ivec2(1, 0), size), political_id(i0 + ivec2(0, 1), size), political_id(i0 + ivec2(1, 1), size));
	float w[4] = float[4]((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	// O dono de cada candidato = soma dos pesos dos cantos que têm o mesmo id.
	float best = -1.0;
	int best_id = 0;
	for (int k = 0; k < 4; k++) {
		float s = 0.0;
		for (int j = 0; j < 4; j++) {
			s += ids[j] == ids[k] ? w[j] : 0.0;
		}
		if (s > best) {
			best = s;
			best_id = ids[k];
		}
	}
	vec4 pal = political_color(best_id);
	if (best_id == 0 || pal.a < 0.5) {
		return col;
	}
	vec3 country = pow(pal.rgb, vec3(2.2)); // a paleta guarda cor sRGB; ALBEDO é linear
	vec3 painted = mix(col, country, 0.55);
	// O segundo colocado (outro país, com cor): a linha de borda, com ~2 pixels de tela de largura.
	float second = 0.0;
	int second_id = 0;
	for (int k = 0; k < 4; k++) {
		if (ids[k] == best_id) {
			continue;
		}
		float s = 0.0;
		for (int j = 0; j < 4; j++) {
			s += ids[j] == ids[k] ? w[j] : 0.0;
		}
		if (s > second) {
			second = s;
			second_id = ids[k];
		}
	}
	if (second_id != 0 && political_color(second_id).a > 0.5) {
		float texels_per_pixel = max(length(fwidth(p)), 0.0001);
		float half_width = clamp(1.2 * texels_per_pixel, 0.06, 0.5);
		float line = 1.0 - smoothstep(half_width * 0.5, half_width, best - 0.5);
		painted = mix(painted, country * 0.22, line * 0.9);
	}
	return painted;
}
