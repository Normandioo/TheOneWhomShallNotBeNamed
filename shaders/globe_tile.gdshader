shader_type spatial;
render_mode specular_disabled, cull_disabled;

// Um bloco da pirâmide (TileLayer): a imagem do bloco pelo UV do pedaço de esfera, com o mesmo relevo do globo.
// cull_disabled: os blocos atrás do horizonte já saem pela escolha da TileLayer; assim a ordem dos vértices não importa.

#include "res://shaders/relief.gdshaderinc"

uniform sampler2D tile : source_color, filter_linear_mipmap, repeat_disable;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(obj_pos);
	vec2 guv = globe_uv(n);
	ALBEDO = texture(tile, UV).rgb;
	ROUGHNESS = 1.0;
	NORMAL = relief_normal(n, guv, height(guv), NORMAL, VIEW_MATRIX * MODEL_MATRIX);
}
