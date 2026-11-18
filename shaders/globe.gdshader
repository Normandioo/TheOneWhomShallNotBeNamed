shader_type spatial;
render_mode specular_disabled;

// O globo de Evron: uma camada de imagem (ou a altitude calibrada) sobre a esfera, com o relevo na iluminação.
// A posição na esfera vira lat/lon e daí a coordenada do mapa equiretangular (convenção de EvronGeo).

const float RADIUS = 8282300.0; // metros (EvronGeo.RADIUS_KM)

uniform sampler2D height_map : filter_linear, repeat_enable; // altitude em metros (calibrada)
uniform sampler2D layer_linear : source_color, filter_linear, repeat_enable;   // camada atual, valores contínuos
uniform sampler2D layer_nearest : source_color, filter_nearest, repeat_enable; // a mesma camada, para categorias
uniform bool nearest = false;
uniform int mode = 0;            // 0 camada de imagem, 1 altitude calibrada (MapLayers "kind")
uniform float relief = 6.0;      // exagero do relevo na iluminação
// Rampa da altitude: mesmos pontos de MapLayers.ALTITUDE_OFFSETS/COLORS (mar à esquerda do centro, terra à direita).
const float SEA_FLOOR = -13500.0;
const float PEAK = 9103.4;

varying vec3 obj_pos;

float height(vec2 uv) {
	return textureLod(height_map, vec2(uv.x, clamp(uv.y, 0.0, 1.0)), 0.0).r;
}

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

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(obj_pos);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float lon = atan(n.x, n.z);
	vec2 uv = vec2(lon / TAU + 0.5, clamp(0.5 - lat / PI, 0.0, 1.0));
	float h = height(uv);

	// textureLod 0: o uv dá um salto na longitude 180° e a derivada faria uma costura com mipmaps.
	vec3 col = nearest ? textureLod(layer_nearest, uv, 0.0).rgb : textureLod(layer_linear, uv, 0.0).rgb;
	if (mode == 1) {
		col = pow(altitude_color(h), vec3(2.2)); // cores da legenda são sRGB; ALBEDO é linear
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;

	// Relevo: a inclinação do terreno entorta a normal (só em terra; o fundo do mar fica liso).
	if (h > 0.0) {
		vec2 texel = 1.0 / vec2(textureSize(height_map, 0));
		float coslat = max(cos(lat), 0.05);
		float gx = (height(uv + vec2(texel.x, 0.0)) - height(uv - vec2(texel.x, 0.0))) / (2.0 * TAU * texel.x * coslat * RADIUS);
		float gy = (height(uv - vec2(0.0, texel.y)) - height(uv + vec2(0.0, texel.y))) / (2.0 * PI * texel.y * RADIUS);
		vec3 c = cross(vec3(0.0, 1.0, 0.0), n);
		vec3 east = length(c) > 0.0001 ? normalize(c) : vec3(1.0, 0.0, 0.0);
		vec3 north = cross(n, east);
		vec3 pn = normalize(n - relief * (gx * east + gy * north));
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(pn, 0.0)).xyz);
	}
}
