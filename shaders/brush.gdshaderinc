// Prévia do pincel, comum ao globo e aos blocos: um anel no raio do pincel e um véu claro por dentro.
// Parâmetro global (project.godot, shader_globals): xyz = direção do centro, w = raio angular em rad (0 = sem pincel).
global uniform vec4 brush;

vec3 brush_preview(vec3 n, vec3 col) {
	if (brush.w <= 0.0) {
		return col;
	}
	float ang = acos(clamp(dot(n, brush.xyz), -1.0, 1.0));
	float px = fwidth(ang);
	float ring = 1.0 - smoothstep(px, px * 2.5, abs(ang - brush.w));
	float inside = ang < brush.w ? 0.12 : 0.0;
	return mix(col, vec3(1.0), max(ring * 0.9, inside));
}
