shader_type spatial;
render_mode cull_disabled;

// Um bloco da pirâmide (TileLayer): a imagem do bloco pelo UV do pedaço de esfera, com o mesmo relevo do globo.
// cull_disabled: os blocos atrás do horizonte já saem pela escolha da TileLayer; assim a ordem dos vértices não importa.

#include "res://shaders/relief.gdshaderinc"
#include "res://shaders/brush.gdshaderinc"
#include "res://shaders/political.gdshaderinc"
#include "res://shaders/natural.gdshaderinc"

uniform sampler2D tile : source_color, filter_linear_mipmap, repeat_disable;
uniform bool satellite = false;
uniform float tile_inset = 0.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(obj_pos);
	vec2 guv = globe_uv(n);
	float h = height(guv);
	vec4 texel = texture(tile, mix(vec2(tile_inset), vec2(1.0 - tile_inset), UV));
	float detail_m = 0.0;
	float wet = 0.0;
	vec3 color = texel.rgb;
	if (satellite) {
		color = satellite_surface(texel, n, guv, h, detail_m, wet);
		EMISSION = vec3(0.055, 0.115, 0.26) * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	}
	ALBEDO = color;
	ALBEDO = river_paint(guv, ALBEDO);
	ALBEDO = political_paint(guv, ALBEDO);
	ALBEDO = brush_preview(n, ALBEDO);
	SPECULAR = 0.14 * wet;
	ROUGHNESS = mix(1.0, 0.36, wet);
	NORMAL = relief_normal(n, guv, h, NORMAL, VIEW_MATRIX * MODEL_MATRIX);
	if (satellite) {
		NORMAL = bump(NORMAL, VERTEX, detail_m * relief * 1e-6);
	}
}
