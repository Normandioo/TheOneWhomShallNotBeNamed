// A camada política, comum ao globo e aos blocos: cada pixel do mapa tem UM dono (o id de um país) e a cor do país cobre o seu território, com uma linha
// escura onde dois países se encontram. Parâmetros globais (project.godot, shader_globals), escritos por GlobeMaterial:
//   political_map     RG8, mesma grade da altitude: dono = r + 256·g (0 = ninguém)
//   political_palette RGBA8 de 256×256: a cor do país de id = (x = id & 255, y = id >> 8); alfa 0 = sem país (um dono que foi apagado fica sem cor)
//   political_on      1 = mostra a camada, 0 = esconde
//   political_top     RG8 de 256×256: para cada id, o id do topo da hierarquia (o país de uma província; o próprio id para um país, uma
//                     religião etc.). Estilo Europa Universalis: a província tem a cor do país; entre países a linha é forte, entre
//                     províncias do mesmo país é fina e discreta
//   political_selected o topo selecionado na ficha (0 = nenhum): fica destacado, com as províncias mais evidentes
// A borda é suavizada: cada ponto olha os 4 pixels em volta e fica com o dono de maior peso (interpolação bilinear dos pesos), o que troca os degraus
// por diagonais; a linha vale onde o segundo colocado é de outro país e a disputa está quase empatada.
global uniform sampler2D political_map;
global uniform sampler2D political_palette;
global uniform float political_on;
global uniform sampler2D political_top;
global uniform int political_selected;
// A área (cultura, etnia, raça, religião, idioma) sobre o mapa político: os países ficam cinzas e a área aparece com a sua cor e uma borda tracejada.
global uniform sampler2D area_map;
global uniform sampler2D area_palette;
global uniform float area_on;
global uniform float area_gray;  // 1 = o mapa de baixo são os países (ficam cinzas); 0 = outro mapa de área (a cor dele fica, a sobreposição vai por cima)
// A costa de todos os mapas: R = distância com sinal até a costa em km (+ terra), G = lago (Terrain.CoastImage). Global para o mapa político e as outras
// camadas desenharem a MESMA linha de costa.
global uniform sampler2D coast_map : filter_linear, repeat_enable;
// As linhas do pincel de fronteira (Territory.Walls): perto delas a borda sai em cima da linha, mais fina que o pixel do mapa.
// wall_index: uma célula por 4×4 pixels do mapa, com o início e a quantidade de trechos; wall_segments (1024 de largura): x0, y0, x1, y1
// em pixels do mapa (o centro do pixel i é i + 0,5). wall_on 0 = não há linha à vista.
global uniform sampler2D wall_index : filter_nearest;
global uniform sampler2D wall_segments : filter_nearest;
global uniform float wall_on;

float wall_cross(vec2 a, vec2 b) {
	return a.x * b.y - a.y * b.x;
}

// Terra pela costa do mapa político (0..1, com a borda de um pixel de tela). known = false enquanto a costa não foi calculada.
float coast_land(vec2 uv, out bool known) {
	vec2 c = textureLod(coast_map, vec2(uv.x, clamp(uv.y, 0.0, 1.0)), 0.0).rg;
	known = c.r != 0.0 || c.g != 0.0;
	float km_px = max(fwidth(c.r), 0.001);
	return smoothstep(-0.5 * km_px, 0.5 * km_px, c.r);
}

// A "terra sólida" da imagem de uma camada (solid, 0..1) cortada pela costa do mapa político, só a até 20 km dela: a costa da imagem passa até meio pixel
// do mapa além da desenhada, e essa faixa aparecia como terra no mar. Longe da costa (gelo marinho, por exemplo) não mexe.
float coast_clip(vec2 uv, float solid) {
	bool known;
	float land = coast_land(uv, known);
	float d = textureLod(coast_map, vec2(uv.x, clamp(uv.y, 0.0, 1.0)), 0.0).r;
	return (known && d > -20.0) ? min(solid, land) : solid;
}

int political_id(ivec2 p, ivec2 size) {
	vec2 rg = texelFetch(political_map, ivec2(((p.x % size.x) + size.x) % size.x, clamp(p.y, 0, size.y - 1)), 0).rg;
	return int(rg.r * 255.0 + 0.5) + 256 * int(rg.g * 255.0 + 0.5);
}

vec4 political_color(int id) {
	return texelFetch(political_palette, ivec2(id & 255, id >> 8), 0);
}

int political_top_id(int id) {
	vec2 rg = texelFetch(political_top, ivec2(id & 255, id >> 8), 0).rg;
	int top = int(rg.r * 255.0 + 0.5) + 256 * int(rg.g * 255.0 + 0.5);
	return top == 0 ? id : top;
}

// Pesos da B-spline cúbica nas posições −1, 0, 1 e 2 em volta de t (somam 1).
vec4 political_bspline(float t) {
	float t2 = t * t, t3 = t2 * t;
	return vec4((1.0 - t) * (1.0 - t) * (1.0 - t), 3.0 * t3 - 6.0 * t2 + 4.0, -3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0, t3) / 6.0;
}

// O dono suavizado em uv (0 = ninguém ou país sem cor) e a força da linha de borda com outro país (0..1). width: largura da linha em pixels de tela.
// Cada um dos 4×4 pixels em volta vota com o peso da B-spline cúbica: a borda sai em curva (sem a escada nem as diagonais da grade de 4K) e passa
// a menos de meio pixel de onde a camada a põe.
// sub: a linha entre duas províncias do mesmo país (então line = 0), mais fina (60% da largura).
// coast_km: a distância até a costa desenhada (km, + em terra), se quem chama a tem; negativa = não sabe, e a costa é achada pela altitude em volta.
int political_owner(vec2 uv, float width, float coast_km, out float line, out float sub) {
	line = 0.0;
	sub = 0.0;
	ivec2 size = textureSize(political_map, 0);
	vec2 p = vec2(uv.x * float(size.x), clamp(uv.y, 0.0, 1.0) * float(size.y)) - 0.5;
	float texels_per_pixel = max(length(fwidth(p)), 0.0001);  // antes de qualquer desvio: derivada fora de fluxo condicional
	ivec2 i0 = ivec2(floor(p)) - 1;
	vec4 wx = political_bspline(fract(p.x)), wy = political_bspline(fract(p.y));
	// Em terra perto do mar, o "ninguém" que é ÁGUA no mapa não vota: a costa desenhada pode passar um pouco além de onde dá para pintar, e a faixa
	// entre os dois ficava sem cor. Assim o país mais próximo cobre essa faixa (até ~1,5 pixel do mapa). Terra sem dono continua votando: sem isso o
	// país vazava por cima dela em quadrados do tamanho do pixel do mapa, onde a borda pintada cruzava o litoral.
	vec2 reach = 2.0 / vec2(size);
	float h0 = height(uv), h1 = height(uv + vec2(reach.x, 0.0)), h2 = height(uv - vec2(reach.x, 0.0));
	float h3 = height(uv + vec2(0.0, reach.y)), h4 = height(uv - vec2(0.0, reach.y));
	// Costa = há terra e há mar nesses 5 pontos. Não basta o centro ser terra: a costa desenhada (a distância suavizada) passa até meio pixel além de onde
	// a altitude interpolada vira negativa, e a faixa de fora ficava sem dono.
	bool coastal = coast_km >= 0.0 ? (coast_km > 0.0 && coast_km < 30.0) : max(max(h0, h1), max(max(h2, h3), h4)) > 0.0 && min(min(h0, h1), min(min(h2, h3), h4)) <= 0.0;
	int ids[16];
	float w[16];
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			ivec2 texel = i0 + ivec2(i, j);
			ids[j * 4 + i] = political_id(texel, size);
			bool silent = coastal && ids[j * 4 + i] == 0 && height((vec2(texel) + 0.5) / vec2(size)) < 0.0;
			w[j * 4 + i] = silent ? 0.0 : wx[i] * wy[j];
		}
	}
	// Perto de uma linha desenhada, um pixel do mapa do outro lado dela não vota aqui. "Do outro lado" = o segmento deste ponto até o
	// centro dele cruza a linha: vale para cantos, pontas e encontros de várias linhas. Só de perto (de longe a diferença não aparece) e
	// onde os 16 pixels não são todos do mesmo dono.
	float wall_dist = 1e9;
	float across_w[16];
	bool walled = false;
	bool mixed = false;
	for (int j = 0; j < 16; j++) {
		across_w[j] = 0.0;
		mixed = mixed || ids[j] != ids[0];
	}
	if (wall_on > 0.5 && mixed && texels_per_pixel < 0.6) {
		vec2 here = p + 0.5;
		ivec2 cells = textureSize(wall_index, 0);
		ivec2 cell = ivec2(int(fract(uv.x) * float(cells.x)), clamp(int(uv.y * float(cells.y)), 0, cells.y - 1));
		vec2 span = texelFetch(wall_index, cell, 0).rg;
		int hidden = 0;  // um bit por pixel: 1 = do outro lado
		for (int k = 0; k < min(int(span.y + 0.5), 192); k++) {
			int address = int(span.x + 0.5) + k;
			vec4 segment = texelFetch(wall_segments, ivec2(address % 1024, address / 1024), 0);
			vec2 a = segment.xy - here;
			float turn = float(size.x) * floor(a.x / float(size.x) + 0.5);  // a volta na longitude
			a.x -= turn;
			vec2 b = segment.zw - here - vec2(turn, 0.0);
			if (any(greaterThan(min(a, b), vec2(2.0))) || any(lessThan(max(a, b), vec2(-2.0)))) {
				continue;  // longe demais para passar entre este ponto e algum dos 16 pixels
			}
			vec2 along = b - a;
			wall_dist = min(wall_dist, length(a + clamp(-dot(a, along) / max(dot(along, along), 1e-12), 0.0, 1.0) * along));
			float side_here = wall_cross(along, -a);
			for (int c = 0; c < 16; c++) {
				vec2 q = vec2(i0 + ivec2(c % 4, c / 4)) + 0.5 - here;
				if ((wall_cross(q, a) > 0.0) != (wall_cross(q, b) > 0.0) && (side_here > 0.0) != (wall_cross(along, q - a) > 0.0)) {
					hidden ^= 1 << c;  // cruzar duas vezes volta para o mesmo lado
				}
			}
		}
		if (hidden != 0) {
			float visible = 0.0;
			for (int c = 0; c < 16; c++) {
				visible += (hidden & (1 << c)) != 0 ? 0.0 : w[c];
			}
			if (visible > 0.00001) {
				walled = true;
				for (int c = 0; c < 16; c++) {
					if ((hidden & (1 << c)) != 0) {
						across_w[c] = wx[c % 4] * wy[c / 4];
						w[c] = 0.0;
					}
				}
			}
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
		if (walled && s <= 0.0) {
			continue;  // só do outro lado da linha: não disputa
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
	// A borda com outro país ou com terra sem dono (second_id 0): só do lado de quem tem dono, como no Europa Universalis.
	if (second_id >= 0 && (second_id == 0 || political_color(second_id).a > 0.5)) {
		float d = (best - second) * 0.75 / texels_per_pixel;
		if (second_id != 0 && political_top_id(best_id) == political_top_id(second_id)) {
			sub = 1.0 - smoothstep(0.3 * width - 0.5, 0.3 * width + 0.5, d);
		} else {
			line = 1.0 - smoothstep(0.5 * width - 0.5, 0.5 * width + 0.5, d);  // largura total ≈ width
		}
	}
	// A borda escura em cima da própria linha, quando o outro lado é de outro.
	if (walled) {
		int other = -1;
		float other_w = 0.0;
		for (int c = 0; c < 16; c++) {
			if (across_w[c] > other_w) {
				other_w = across_w[c];
				other = ids[c];
			}
		}
		if (other >= 0 && other != best_id && (other == 0 || political_color(other).a > 0.5)) {
			float on_line = 1.0 - smoothstep(0.5 * width - 0.5, 0.5 * width + 0.5, wall_dist / texels_per_pixel);
			if (other != 0 && political_top_id(best_id) == political_top_id(other)) {
				sub = max(sub, on_line);
			} else {
				line = max(line, on_line);
			}
		}
	}
	return best_id;
}

int area_id(ivec2 p, ivec2 size) {
	vec2 rg = texelFetch(area_map, ivec2(((p.x % size.x) + size.x) % size.x, clamp(p.y, 0, size.y - 1)), 0).rg;
	return int(rg.r * 255.0 + 0.5) + 256 * int(rg.g * 255.0 + 0.5);
}

vec4 area_color(int id) {
	return texelFetch(area_palette, ivec2(id & 255, id >> 8), 0);
}

// O dono da área em uv, suavizado como political_owner (a mesma B-spline: a borda sai em curva, sem escada). Só a cor: não há linha de borda.
int area_owner(vec2 uv) {
	ivec2 size = textureSize(area_map, 0);
	vec2 p = vec2(uv.x * float(size.x), clamp(uv.y, 0.0, 1.0) * float(size.y)) - 0.5;
	ivec2 i0 = ivec2(floor(p)) - 1;
	vec4 wx = political_bspline(fract(p.x)), wy = political_bspline(fract(p.y));
	int ids[16];
	float w[16];
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			ids[j * 4 + i] = area_id(i0 + ivec2(i, j), size);
			w[j * 4 + i] = wx[i] * wy[j];
		}
	}
	float best = -1.0;
	int best_id = -1;
	for (int k = 0; k < 16; k++) {
		float s = 0.0;
		for (int j = 0; j < 16; j++) {
			s += ids[j] == ids[k] ? w[j] : 0.0;
		}
		if (s > best) {
			best = s;
			best_id = ids[k];
		}
	}
	return (best_id > 0 && area_color(best_id).a > 0.5) ? best_id : 0;
}

// O destaque do topo selecionado: 1 = é ele, 0 = não há seleção, -1 = há seleção e é outro.
float political_focus(int id) {
	if (political_selected == 0) {
		return 0.0;
	}
	return political_top_id(id) == political_selected ? 1.0 : -1.0;
}

// A cor do país nas outras camadas: só em terra, pela MESMA costa do mapa político (a da imagem de cada camada difere em até meio pixel do mapa).
// Mais de 20 km mar adentro não corta: território pintado em água (águas territoriais) continua à vista.
vec3 political_paint(vec2 uv, vec3 col) {
	float line, sub;
	bool known;
	float land = coast_land(uv, known);
	float coast_km = textureLod(coast_map, vec2(uv.x, clamp(uv.y, 0.0, 1.0)), 0.0).r;
	int id = political_owner(uv, 2.0, known ? max(coast_km, 0.0) : -1.0, line, sub);
	land = (!known || coast_km < -20.0) ? 1.0 : land;
	if (political_on < 0.5 || id == 0 || land <= 0.0) {
		return col;
	}
	vec3 country = pow(political_color(id).rgb, vec3(2.2)); // a paleta guarda cor sRGB; ALBEDO é linear
	float focus = political_focus(id);
	vec3 c = mix(col, country, (focus > 0.5 ? 0.7 : focus < -0.5 ? 0.35 : 0.55) * land);
	c = mix(c, country * 0.35, sub * (focus > 0.5 ? 0.6 : 0.25) * land);
	vec3 edge = focus > 0.5 ? vec3(1.0, 0.92, 0.6) : country * 0.22;
	return mix(c, edge, line * 0.9 * land);
}
