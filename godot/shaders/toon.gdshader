// Sombreado de cómic: la luz se reparte en 3 tonos planos en vez de un degradado.
// La sombra toma el color ambiente (azulado), así parece tinta aguada.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(0.6, 0.6, 0.6, 1.0);
// textura de "mancha" para que las superficies no parezcan plástico
uniform float grit : hint_range(0.0, 1.0) = 0.25;
uniform float grit_scale = 1.6;
// sangre / acento rojo que brilla un poco (ojos de zombi, luces)
uniform float emission = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// las mallas fusionadas llevan su color en los vértices (blanco si no)
	vec3 c = albedo.rgb * COLOR.rgb;
	if (grit > 0.0) {
		// proyección triplanar barata: cada cara usa el plano que le toca
		vec3 an = abs(world_normal);
		vec2 p = an.y > max(an.x, an.z) ? world_pos.xz : (an.x > an.z ? world_pos.zy : world_pos.xy);
		float n = vnoise(p * grit_scale) * 0.65 + vnoise(p * grit_scale * 4.3 + 7.0) * 0.35;
		c *= mix(1.0 - grit * 0.55, 1.0 + grit * 0.15, smoothstep(0.25, 0.75, n));
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	EMISSION = c * emission;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	// tres tonos: luz, media luz y sombra (la sombra la pone el ambiente)
	float lit = smoothstep(0.34, 0.37, ndl);
	float mid = smoothstep(0.05, 0.08, ndl) * 0.5;
	DIFFUSE_LIGHT += max(lit, mid) * LIGHT_COLOR / PI;
}
