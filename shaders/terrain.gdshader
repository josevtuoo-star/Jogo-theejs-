// Terreno: grama seca/morta procedural misturada com cascalho (Ground.png) e estrada com marcas
// de pneu (Road.png) conforme uma máscara pintada pelo gerador do mapa (R = estrada, G = terra).
shader_type spatial;

uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform sampler2D gravel_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float map_size = 1000.0;
uniform vec3 grass_a : source_color = vec3(0.33, 0.33, 0.18);
uniform vec3 grass_b : source_color = vec3(0.45, 0.4, 0.24);
uniform vec3 mud : source_color = vec3(0.27, 0.22, 0.16);

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = wpos.xz;
	vec4 m = texture(mask_tex, p / map_size + 0.5);
	float big = vnoise(p * 0.03) * 0.6 + vnoise(p * 0.11) * 0.4;
	float fine = vnoise(p * 9.0) * 0.5 + vnoise(p * 27.0) * 0.5;
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.35, 0.75, big)) * (0.75 + 0.45 * fine);
	grass = mix(grass, mud * (0.8 + 0.3 * fine), smoothstep(0.62, 0.85, vnoise(p * 0.05 + 9.0)) * 0.7);
	vec3 gravel = texture(gravel_tex, p * 0.35).rgb * vec3(0.85, 0.82, 0.78);
	vec3 road = texture(road_tex, vec2(p.x * 0.12, p.y * 0.12)).rgb * vec3(0.55, 0.55, 0.56);
	vec3 c = mix(grass, gravel, smoothstep(0.1, 0.6, m.g + (fine - 0.5) * 0.3));
	c = mix(c, road, smoothstep(0.25, 0.7, m.r + (fine - 0.5) * 0.2));
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.8, m.r);
	SPECULAR = 0.3;
}
