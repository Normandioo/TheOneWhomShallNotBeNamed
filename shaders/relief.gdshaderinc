// Relevo na iluminação, comum ao globo e aos blocos: a altitude calibrada entorta a normal.
// Convenção de EvronGeo: dir = (cos lat · sin lon, sin lat, cos lat · cos lon); u = lon/360 + 0,5; v = 0,5 - lat/180.

const float RADIUS = 6371000.0; // metros (EvronGeo.RADIUS_KM)

uniform sampler2D height_map : filter_linear, repeat_enable; // altitude em metros (calibrada)
uniform sampler2D river_map : filter_linear, repeat_enable; // rios do pincel Vales (0..1), mesma grade da altitude
uniform float relief = 6.0;      // exagero do relevo na iluminação

// A longitude dá a volta. Na latitude, a filtragem não pode buscar o polo oposto.
vec2 latitude_clamped_uv(vec2 uv, int rows) {
	float half_texel = 0.5 / float(rows);
	return vec2(uv.x, clamp(uv.y, half_texel, 1.0 - half_texel));
}

float height(vec2 uv) {
	return textureLod(height_map, latitude_clamped_uv(uv, textureSize(height_map, 0).y), 0.0).r;
}

vec2 globe_uv(vec3 n) {
	return vec2(atan(n.x, n.z) / TAU + 0.5, clamp(0.5 - asin(clamp(n.y, -1.0, 1.0)) / PI, 0.0, 1.0));
}

// Normal do terreno em `n` (direção no planeta), já no espaço da vista. Só em terra; o fundo do mar fica liso.
vec3 relief_normal(vec3 n, vec2 uv, float h, vec3 fallback, mat4 view_model) {
	if (h <= 0.0) {
		return fallback;
	}
	float lat = asin(clamp(n.y, -1.0, 1.0));
	vec2 texel = 1.0 / vec2(textureSize(height_map, 0));
	float coslat = max(cos(lat), 0.05);
	float gx = (height(uv + vec2(texel.x, 0.0)) - height(uv - vec2(texel.x, 0.0))) / (2.0 * TAU * texel.x * coslat * RADIUS);
	float gy = (height(uv - vec2(0.0, texel.y)) - height(uv + vec2(0.0, texel.y))) / (2.0 * PI * texel.y * RADIUS);
	vec3 c = cross(vec3(0.0, 1.0, 0.0), n);
	vec3 east = length(c) > 0.0001 ? normalize(c) : vec3(1.0, 0.0, 0.0);
	vec3 north = cross(n, east);
	vec3 pn = normalize(n - relief * (gx * east + gy * north));
	return normalize((view_model * vec4(pn, 0.0)).xyz);
}

// Rios criados pelo pincel Vales, por cima de qualquer camada. A textura é linear: a linha de 1 pixel fica lisa.
float terrain_river_at(vec2 uv) {
	return textureLod(river_map, latitude_clamped_uv(uv, textureSize(river_map, 0).y), 0.0).r;
}

vec3 river_paint(vec2 uv, vec3 col) {
	float r = terrain_river_at(uv);
	return mix(col, pow(vec3(0.12, 0.38, 0.72), vec3(2.2)), smoothstep(0.12, 0.35, r));
}
