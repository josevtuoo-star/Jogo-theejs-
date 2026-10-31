// Concreto procedural (sem textura): manchas grandes, poros e relevo leve calculados no
// espaço do mundo — serve para blocos de qualquer tamanho sem esticar. As quinas dos
// blocos de parkour ficam mais gastas e claras.
shader_type spatial;

uniform vec3 color_a : source_color = vec3(0.58, 0.57, 0.54);
uniform vec3 color_b : source_color = vec3(0.47, 0.46, 0.44);
uniform float bump = 0.6;
uniform float scale = 1.0;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = wpos * scale;
	float big = vnoise(p * 0.6) * 0.6 + vnoise(p * 1.7) * 0.4;
	float fine = vnoise(p * 9.0) * 0.6 + vnoise(p * 23.0) * 0.4;
	vec3 c = mix(color_a, color_b, smoothstep(0.25, 0.85, big));
	c *= 0.92 + 0.14 * fine;
	// escorrido escuro de chuva nas faces verticais
	float streak = vnoise(vec3(p.x * 6.0, p.y * 0.4, p.z * 6.0));
	c *= mix(1.0, 0.9 + 0.1 * streak, 0.4);
	ALBEDO = c;
	ROUGHNESS = 0.82 + 0.12 * fine;
	SPECULAR = 0.35;
	// relevo a partir das derivadas do ruído fino (sem mapa de normais)
	float h = fine * bump * 0.01;
	vec3 dpdx = dFdx(VERTEX), dpdy = dFdy(VERTEX);
	float dhx = dFdx(h), dhy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL), r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}
