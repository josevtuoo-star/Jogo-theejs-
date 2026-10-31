// Concreto procedural: manchas grandes, poros e relevo leve no espaço do mundo (serve para
// blocos de qualquer tamanho sem esticar).
shader_type spatial;

uniform vec3 color_a : source_color = vec3(0.58, 0.57, 0.54);
uniform vec3 color_b : source_color = vec3(0.47, 0.46, 0.44);

varying vec3 wpos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
	vec3 i = floor(x), f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float big = vnoise(wpos * 0.6) * 0.6 + vnoise(wpos * 1.7) * 0.4;
	float fine = vnoise(wpos * 9.0) * 0.6 + vnoise(wpos * 23.0) * 0.4;
	vec3 c = mix(color_a, color_b, smoothstep(0.25, 0.85, big));
	c *= 0.92 + 0.14 * fine;
	ALBEDO = c;
	ROUGHNESS = 0.85 + 0.1 * fine;
	SPECULAR = 0.35;
	float h = fine * 0.006;
	vec3 dpdx = dFdx(VERTEX), dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL), r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	NORMAL = normalize(abs(det) * NORMAL - sign(det) * (dFdx(h) * r1 + dFdy(h) * r2));
}
