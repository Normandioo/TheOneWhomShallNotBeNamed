shader_type spatial;
render_mode specular_disabled;

// O globo de Evron: uma camada de imagem (ou a altitude calibrada) sobre a esfera, com o relevo na iluminação.
// A posição na esfera vira lat/lon e daí a coordenada do mapa equiretangular (convenção de EvronGeo).

#include "res://shaders/relief.gdshaderinc"

uniform sampler2D layer_linear : source_color, filter_linear, repeat_enable;   // camada atual, valores contínuos
uniform sampler2D layer_nearest : source_color, filter_nearest, repeat_enable; // a mesma camada, para categorias
uniform bool nearest = false;
uniform int mode = 0;            // 0 camada de imagem, 1 altitude calibrada, 2 cor natural, 3 temperatura sazonal (GlobeMaterial.MODES)
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
	if (mode == 1) {
		col = pow(altitude_color(h), vec3(2.2)); // cores da legenda são sRGB; ALBEDO é linear
	} else if (mode == 2) {
		// natural.png: RGB = terra e gelo, A = superfície sólida. O resto é água, pintada ao vivo pela altitude.
		float solid = smoothstep(0.3, 0.7, textureLod(layer_linear, uv, 0.0).a);
		col = mix(pow(water_color(h), vec3(2.2)), col, solid);
		// Halo azul da atmosfera na borda do disco.
		EMISSION = vec3(0.10, 0.22, 0.55) * pow(1.0 - clamp(dot(geo_normal, VIEW), 0.0, 1.0), 4.0);
	}
	if (mode == 3) {
		vec2 tuv = vec2(uv.x, clamp(uv.y, 0.0, 1.0));
		float c = mix(textureLod(temp_jan, tuv, 0.0).r, textureLod(temp_jul, tuv, 0.0).r, season_july);
		col = textureLod(temp_ramp, vec2(clamp((c + 20.0) / 60.0, 0.0, 1.0), 0.5), 0.0).rgb;
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	NORMAL = relief_normal(n, uv, h, NORMAL, VIEW_MATRIX * MODEL_MATRIX);
}
