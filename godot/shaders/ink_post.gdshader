// Postproceso "novela gráfica": contornos de tinta, color apagado salvo el rojo,
// tramado en las sombras y grano de papel. Va en un plano que cubre la pantalla.
// Necesita el renderizador Forward+ (usa la textura de normales).
shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_nearest;

uniform vec4 ink : source_color = vec4(0.07, 0.065, 0.075, 1.0);
uniform vec4 paper : source_color = vec4(0.95, 0.91, 0.82, 1.0);
// color de los contornos (de noche se aclara; la trama sigue usando la tinta)
uniform vec4 line_color : source_color = vec4(0.07, 0.065, 0.075, 1.0);
// viñeta de impacto: 1 = fotograma en blanco y negro puro
uniform float impact : hint_range(0.0, 1.0) = 0.0;
// contornos
uniform float line_width = 1.3;
uniform float depth_threshold = 0.9;
uniform float normal_threshold = 0.35;
uniform float line_fade_start = 30.0;
uniform float line_fade_end = 80.0;
// trazo "vivo": el contorno tiembla un poco varias veces por segundo, como dibujado a mano
uniform float boil_fps = 6.0;
uniform float boil_pixels = 0.8;
// color
uniform float saturation : hint_range(0.0, 1.0) = 0.38;
uniform float exposure = 1.05;
// tramado en sombras
uniform float hatch_strength : hint_range(0.0, 1.0) = 0.55;
uniform float hatch_lines_per_screen = 170.0;
uniform float hatch_dark = 0.16;
uniform float crosshatch_dark = 0.06;
// papel
uniform float grain = 0.07;
uniform float vignette = 0.35;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// 1/profundidad lineal: en un plano es lineal en pantalla, así el suelo no da falsos bordes
float inv_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_texture, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return 1.0 / max(-v.z / v.w, 0.001);
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_texture, uv).xyz * 2.0 - 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float t = floor(TIME * boil_fps);
	vec2 wobble = (vec2(vnoise(uv * 24.0 + t * 7.31), vnoise(uv * 24.0 + 31.7 + t * 3.17)) - 0.5) * 2.0;
	vec2 suv = uv + wobble * boil_pixels * px;
	vec2 o = px * line_width;

	// --- contornos por profundidad
	float i0 = inv_depth(suv, INV_PROJECTION_MATRIX);
	float il = inv_depth(suv - vec2(o.x, 0.0), INV_PROJECTION_MATRIX);
	float ir = inv_depth(suv + vec2(o.x, 0.0), INV_PROJECTION_MATRIX);
	float id = inv_depth(suv - vec2(0.0, o.y), INV_PROJECTION_MATRIX);
	float iu = inv_depth(suv + vec2(0.0, o.y), INV_PROJECTION_MATRIX);
	float lap = (abs(il + ir - 2.0 * i0) + abs(id + iu - 2.0 * i0)) / max(i0, 1e-5);
	float depth_edge = smoothstep(depth_threshold * 0.05, depth_threshold * 0.1, lap);

	// --- contornos por normales (pliegues, esquinas de paredes)
	vec3 n0 = view_normal(suv);
	float nd = 0.0;
	nd = max(nd, 1.0 - dot(n0, view_normal(suv - vec2(o.x, 0.0))));
	nd = max(nd, 1.0 - dot(n0, view_normal(suv + vec2(o.x, 0.0))));
	nd = max(nd, 1.0 - dot(n0, view_normal(suv - vec2(0.0, o.y))));
	nd = max(nd, 1.0 - dot(n0, view_normal(suv + vec2(0.0, o.y))));
	float normal_edge = smoothstep(normal_threshold, normal_threshold + 0.15, nd);

	float dist = 1.0 / i0;
	bool sky = texture(depth_texture, suv).r <= 0.0;
	if (sky) normal_edge = 0.0;
	float edge = max(depth_edge, normal_edge) * (1.0 - smoothstep(line_fade_start, line_fade_end, dist));

	// --- color: apagado salvo los rojos (sangre, ojos)
	vec3 col = texture(screen_texture, uv).rgb * exposure;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	// solo rojos de verdad (verde y azul parecidos y bajos): el naranja no cuenta
	float redness = clamp((col.r - max(col.g, col.b)) * 5.0, 0.0, 1.0) * (1.0 - clamp(abs(col.g - col.b) * 8.0, 0.0, 1.0));
	col = mix(vec3(lum), col, mix(saturation, 1.0, redness));
	col *= paper.rgb;

	// --- tramado diagonal en las sombras (y cruzado en las más oscuras)
	vec2 fc = FRAGCOORD.xy / VIEWPORT_SIZE.y * hatch_lines_per_screen;
	float jitter = vnoise(fc * 0.35 + t * 1.3) * 0.35;
	float line1 = 1.0 - smoothstep(0.12, 0.3, abs(fract(fc.x + fc.y + jitter) - 0.5));
	float line2 = 1.0 - smoothstep(0.12, 0.3, abs(fract(fc.x - fc.y + jitter) - 0.5));
	float h1 = line1 * (1.0 - smoothstep(hatch_dark * 0.6, hatch_dark, lum));
	float h2 = line2 * (1.0 - smoothstep(crosshatch_dark * 0.6, crosshatch_dark, lum));
	if (sky) { h1 = 0.0; h2 = 0.0; }
	col = mix(col, ink.rgb, max(h1, h2) * hatch_strength);

	// --- papel: fibras, grano y viñeta
	float fibers = vnoise(FRAGCOORD.xy * 0.035) * 0.6 + vnoise(FRAGCOORD.xy * 0.21) * 0.4;
	col *= 1.0 - (fibers - 0.5) * grain * 1.5;
	col *= 1.0 + (hash(FRAGCOORD.xy + t) - 0.5) * grain;
	float v = smoothstep(0.35, 0.95, length((uv - 0.5) * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0)) * 1.1);
	col *= 1.0 - v * vignette;

	col = mix(col, line_color.rgb, edge);
	// golpe fuerte: un fotograma de tinta y papel sin grises, como una viñeta de impacto
	if (impact > 0.0) {
		float l2 = dot(col, vec3(0.299, 0.587, 0.114));
		vec3 stark = mix(ink.rgb, paper.rgb, step(0.12, l2));
		stark = mix(stark, ink.rgb, edge);
		col = mix(col, stark, impact);
	}
	ALBEDO = col;
}
