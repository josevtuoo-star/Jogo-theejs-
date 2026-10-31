// Chão de grama procedural (sem textura): manchas de grama verde, seca e terra, com detalhe
// fino de "folhinhas", tudo no espaço do mundo.
shader_type spatial;

uniform vec3 green : source_color = vec3(0.27, 0.38, 0.14);
uniform vec3 dry : source_color = vec3(0.47, 0.44, 0.24);
uniform vec3 dirt : source_color = vec3(0.36, 0.28, 0.19);

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.5 + vnoise(p * 2.1) * 0.3 + vnoise(p * 4.3) * 0.2; }

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.08);
	float mid = fbm(p * 0.45 + 13.0);
	float fine = vnoise(p * 22.0) * 0.6 + vnoise(p * 61.0) * 0.4;
	vec3 c = mix(green, dry, smoothstep(0.45, 0.75, big));
	c = mix(c, dirt, smoothstep(0.62, 0.8, mid) * 0.75);
	c *= 0.78 + 0.4 * fine;
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
	// relevo fino a partir das derivadas do ruído
	float h = fine * 0.004;
	vec3 dpdx = dFdx(VERTEX), dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL), r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	NORMAL = normalize(abs(det) * NORMAL - sign(det) * (dFdx(h) * r1 + dFdy(h) * r2));
}
