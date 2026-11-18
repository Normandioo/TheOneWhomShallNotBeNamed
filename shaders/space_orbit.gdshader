shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Linha de órbita: uma cor e uma transparência que o código ajusta pelo tamanho que a órbita tem na tela.

uniform vec4 line_color : source_color = vec4(1.0);
uniform float alpha = 1.0;

void fragment() {
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a * alpha;
}
