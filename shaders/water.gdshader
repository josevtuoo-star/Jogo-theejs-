// Água do lago: transparente, ondinhas animadas (normais de ruído), reflexo do céu nas bordas
// (Fresnel) e cor mais escura/esverdeada no fundo.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 shallow : source_color = vec3(0.18, 0.42, 0.45);
uniform vec3 deep : source_color = vec3(0.04, 0.16, 0.2);

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float waves(vec2 p, float t) {
	return vnoise(p * 1.3 + vec2(t * 0.35, t * 0.2)) * 0.6 + vnoise(p * 3.1 - vec2(t * 0.5, -t * 0.3)) * 0.4;
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float e = 0.05;
	float h = waves(wpos.xz, TIME);
	float hx = waves(wpos.xz + vec2(e, 0.0), TIME);
	float hz = waves(wpos.xz + vec2(0.0, e), TIME);
	vec3 n = normalize(vec3((h - hx) * 0.6, 1.0, (h - hz) * 0.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, shallow, 0.4 + 0.3 * h);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = clamp(0.62 + fres * 0.35, 0.0, 0.95);
}
