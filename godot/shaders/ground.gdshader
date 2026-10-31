// Chão de terra e grama: a textura é aplicada no espaço do mundo em duas escalas misturadas
// por um ruído grande, para não aparecer repetição de "azulejo" no pátio.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale = 0.22;
uniform float normal_strength = 0.8;
uniform vec3 dry_tint : source_color = vec3(0.78, 0.7, 0.55);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = wpos.xz * scale;
	vec2 uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * wpos.xz * scale * 0.37 + 0.31;
	float m = vnoise(wpos.xz * 0.06) * 0.65 + vnoise(wpos.xz * 0.2) * 0.35;
	vec3 a = mix(texture(albedo_tex, uv).rgb, texture(albedo_tex, uv2).rgb, smoothstep(0.35, 0.65, m));
	// manchas mais secas/pisadas
	float dry = smoothstep(0.55, 0.8, vnoise(wpos.xz * 0.09 + 7.0));
	a = mix(a, a * dry_tint * 1.25, dry * 0.6);
	ALBEDO = a;
	NORMAL_MAP = mix(texture(normal_tex, uv).rgb, texture(normal_tex, uv2).rgb, smoothstep(0.35, 0.65, m));
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = 0.95;
	SPECULAR = 0.3;
}
