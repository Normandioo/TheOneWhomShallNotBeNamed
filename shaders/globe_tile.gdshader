shader_type spatial;
render_mode cull_disabled;

// Um bloco da pirâmide (TileLayer): a imagem do bloco pelo UV do pedaço de esfera, com o mesmo relevo do globo.
// cull_disabled: os blocos atrás do horizonte já saem pela escolha da TileLayer; assim a ordem dos vértices não importa.
// natural = true: o bloco é da pirâmide "natural" (RGBA, mesma convenção do natural.png): A = terra/gelo sólido,
// o resto é mar pintado ao vivo pela altitude, com o mesmo grão fino do globo (shaders/natural.gdshaderinc).

#include "res://shaders/relief.gdshaderinc"
#include "res://shaders/natural.gdshaderinc"
#include "res://shaders/experimental.gdshaderinc"

uniform bool experimental = false;

uniform sampler2D tile : source_color, filter_linear_mipmap, repeat_disable;
uniform bool natural = false;
uniform float tile_inset = 0.0;

varying vec3 obj_pos;


void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(obj_pos);
	vec2 guv = globe_uv(n);
	float h = height(guv);
	vec4 tex = texture(tile, mix(vec2(tile_inset), vec2(1.0 - tile_inset), UV));
	vec3 col = tex.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float detail_m = 0.0;
	if (experimental) {
		float wet;
		col = satellite_surface(tex, n, guv, h, detail_m, wet);
		SPECULAR = 0.14 * wet;
		ROUGHNESS = mix(1.0, 0.36, wet);
	} else if (natural) {
		float solid = smoothstep(0.3, 0.7, tex.a);
		float lat = asin(clamp(n.y, -1.0, 1.0));
		vec3 water = h >= 0.0 ? tex.rgb : pow(water_color(h, lat), vec3(2.2));
		vec3 pos_m = n * RADIUS;
		float px_m = length(fwidth(pos_m));
		vec2 fd = fine_detail(pos_m, px_m);
		float rough = 0.35 + 0.65 * smoothstep(200.0, 2500.0, h);
		col = tex.rgb * (1.0 + 0.22 * fd.x * solid);
		detail_m = fd.y * rough * solid;
		col = mix(water, col, solid);
		float wet = 1.0 - solid;
		SPECULAR = 0.35 * wet;
		ROUGHNESS = mix(1.0, 0.32, wet);
	}
	ALBEDO = col;
	NORMAL = relief_normal(n, guv, h, NORMAL, VIEW_MATRIX * MODEL_MATRIX);
	if (natural || experimental) {
		NORMAL = bump(NORMAL, VERTEX, detail_m * relief * 1e-6);
	}
}
