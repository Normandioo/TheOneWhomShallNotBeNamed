shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never;
// Cinturão de asteroides: cada ponto é uma órbita kepleriana, resolvida aqui a cada quadro.
// VERTEX = (a em UA, e, inclinação em rad), UV = (nó, argumento do periélio) em rad, UV2 = (anomalia média em J2000, brilho).

uniform float days = 0.0;               // dias desde J2000
uniform float unit_per_au = 149597.8707; // unidades da cena por UA (1 unidade = 1000 km)
uniform float point_size = 2.0;
uniform vec4 point_color : source_color = vec4(0.8);
uniform float alpha = 1.0;

varying float brightness;

const float GAUSS_K = 0.01720209895; // rad/dia a 1 UA

void vertex() {
	float a = VERTEX.x;
	float e = VERTEX.y;
	float inc = VERTEX.z;
	float node = UV.x;
	float peri = UV.y;
	float n = GAUSS_K / (a * sqrt(a));
	float m = mod(UV2.x + n * days, TAU);
	if (m > PI) {
		m -= TAU;
	}
	float ea = m + e * sin(m);
	for (int i = 0; i < 6; i++) {
		ea -= (ea - e * sin(ea) - m) / (1.0 - e * cos(ea));
	}
	float xv = a * (cos(ea) - e);
	float yv = a * sqrt(1.0 - e * e) * sin(ea);
	float cw = cos(peri);
	float sw = sin(peri);
	float cn = cos(node);
	float sn = sin(node);
	float ci = cos(inc);
	float si = sin(inc);
	vec3 p = vec3(
		(cw * cn - sw * sn * ci) * xv + (-sw * cn - cw * sn * ci) * yv,
		(cw * sn + sw * cn * ci) * xv + (-sw * sn + cw * cn * ci) * yv,
		(sw * si) * xv + (cw * si) * yv);
	VERTEX = vec3(p.x, p.z, -p.y) * unit_per_au; // eclíptica -> eixos do Godot
	POINT_SIZE = point_size;
	brightness = UV2.y;
}

void fragment() {
	ALBEDO = point_color.rgb * brightness;
	ALPHA = point_color.a * alpha;
}
