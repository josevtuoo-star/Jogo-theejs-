// Material de protótipo: grade de 1 m e xadrez de 4 m no espaço do mundo (não estica em
// paredes, rampas nem caixas de tamanhos diferentes).
shader_type spatial;

uniform vec3 color_a : source_color = vec3(0.56, 0.57, 0.6);
uniform vec3 color_b : source_color = vec3(0.5, 0.51, 0.54);
uniform vec3 line_color : source_color = vec3(0.32, 0.33, 0.36);
uniform float cell = 1.0;
uniform float roughness = 0.85;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid_line(vec2 g) {
	vec2 f = abs(fract(g - 0.5) - 0.5) / max(fwidth(g), vec2(1e-4));
	return 1.0 - min(min(f.x, f.y), 1.0);
}

void fragment() {
	vec3 n = abs(wnrm);
	vec2 uv = n.y > 0.577 ? wpos.xz : (n.x > n.z ? wpos.zy : wpos.xy);
	vec2 g = uv / cell;
	vec2 g4 = uv / (cell * 4.0);
	float checker = mod(floor(g4.x) + floor(g4.y), 2.0);
	vec3 c = mix(color_a, color_b, checker);
	c = mix(c, line_color, max(grid_line(g) * 0.45, grid_line(g4) * 0.8));
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
}
