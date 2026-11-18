shader_type spatial;
render_mode unshaded;
// Planeta, Lua ou Sol no modo espaço. A luz é calculada aqui (não pela luz do Godot): vem do Sol, que pode estar a
// bilhões de km, e o jogo precisa de faixas de luz, como no globo de Marte. O sol_dir é calculado na CPU, em double.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform vec3 base_color : source_color = vec3(0.7);
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0); // mundo, do corpo para o Sol
uniform bool emissive = false;               // o Sol não recebe luz
uniform vec3 atmosphere_color : source_color = vec3(0.4, 0.65, 1.0);
uniform float atmosphere = 0.0;              // 0 = sem brilho na borda
uniform float color_steps = 16.0;            // posterização, um pouco mais fina que a do globo de Marte (10)
uniform vec2 texel_grid = vec2(512.0, 256.0); // células do mapa (~0,7° cada): a textura vira blocos, como o relevo de Marte
uniform float ambient = 0.05;
// Relevo: mapa de altitude em tons de cinza (0..1 = height_min .. height_min + height_range, em metros). A luz
// usa a normal entortada pela inclinação do terreno, como no globo de Marte (globe.gdshader).
uniform sampler2D height_tex : filter_linear_mipmap, repeat_enable;
uniform bool use_height = false;
uniform float height_min = 0.0;
uniform float height_range = 1.0;
uniform float body_radius_m = 6371000.0;
uniform float relief = 12.0;                  // exagero do relevo na iluminação (o mesmo de Marte)

const float TAU_ = 6.28318530718;

varying vec3 world_normal;
varying vec3 obj_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	obj_normal = NORMAL;
}

float height_at(vec2 cell_uv) {
	float mip = log2(float(textureSize(height_tex, 0).x) / texel_grid.x);
	return height_min + height_range * textureLod(height_tex, vec2(cell_uv.x, clamp(cell_uv.y, 0.0, 1.0)), mip).r;
}

void fragment() {
	vec3 col = base_color;
	if (use_tex) {
		// A malha da esfera tem u = 0 em +Z crescendo para +X; o mapa tem o meridiano zero no meio.
		// Uma cor por célula, a média da célula (mip), em vez de milhares de pixels de detalhe.
		vec2 cell_uv = (floor(vec2(UV.x + 0.5, UV.y) * texel_grid) + 0.5) / texel_grid;
		col = textureLod(albedo_tex, cell_uv, log2(float(textureSize(albedo_tex, 0).x) / texel_grid.x)).rgb;
	}
	vec3 nrm = normalize(world_normal);
	if (use_height) {
		vec2 cell_uv = (floor(vec2(UV.x + 0.5, UV.y) * texel_grid) + 0.5) / texel_grid;
		vec2 d = 1.0 / texel_grid;
		vec3 on = normalize(obj_normal);
		float coslat = max(sqrt(1.0 - on.y * on.y), 0.05);
		float gx = (height_at(cell_uv + vec2(d.x, 0.0)) - height_at(cell_uv - vec2(d.x, 0.0))) / (2.0 * TAU_ * d.x * coslat * body_radius_m);
		float gy = (height_at(cell_uv - vec2(0.0, d.y)) - height_at(cell_uv + vec2(0.0, d.y))) / (2.0 * PI * d.y * body_radius_m);
		vec3 east = normalize(cross(vec3(0.0, 1.0, 0.0), on));
		vec3 north = cross(on, east);
		vec3 pn = normalize(on - relief * (gx * east + gy * north));
		nrm = normalize((MODEL_MATRIX * vec4(pn, 0.0)).xyz);
	}
	float ndl = clamp(dot(nrm, sun_dir), 0.0, 1.0);
	float bands = floor(ndl * 4.0 + 0.6) / 4.0; // faixas de luz, como no globo
	vec3 lit = emissive ? col : col * (ambient + (1.0 - ambient) * bands);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	lit += atmosphere_color * rim * atmosphere * (0.15 + 0.85 * bands);
	// Posteriza no espaço da tela (gama): no linear, o azul-marinho do oceano arredondava para preto.
	vec3 perceptual = pow(lit, vec3(1.0 / 2.2));
	ALBEDO = pow(floor(perceptual * color_steps + 0.5) / color_steps, vec3(2.2));
}
