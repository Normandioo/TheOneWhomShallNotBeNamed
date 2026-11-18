shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
// A atmosfera de Marte: um halo em volta do planeta, mais grosso quanto mais alta a atmosfera. É uma casca esférica
// maior que o planeta; para cada pixel, mede a distância da linha de visão ao centro de Marte e dá densidade
// exponencial a partir da superfície. A espessura é exagerada (ver SpaceScene.ATMOSPHERE_EXAGGERATION).

uniform float planet_radius = 1.0;  // unidades do objeto
uniform float top = 0.1;            // espessura visível do halo, em unidades do objeto
uniform vec3 tint : source_color = vec3(0.9, 0.55, 0.35);
uniform float strength = 0.4;
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0); // mundo, de Marte para o Sol

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float s = length(MODEL_MATRIX[0].xyz); // escala do nó (corpos distantes são encolhidos)
	vec3 center = (VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float b = length(cross(center, normalize(VERTEX))); // distância da linha de visão ao centro
	float r = planet_radius * s;
	float dens;
	if (b < r) {
		dens = 0.1; // sobre o disco: névoa fina
	} else {
		float h = (b - r) / max(top * s, 1e-6);
		dens = exp(-3.0 * h) * (1.0 - smoothstep(0.7, 1.0, h));
	}
	float day = 0.25 + 0.75 * clamp(dot(world_normal, sun_dir) * 0.8 + 0.4, 0.0, 1.0);
	ALBEDO = tint;
	ALPHA = clamp(strength * dens * day, 0.0, 1.0);
}
