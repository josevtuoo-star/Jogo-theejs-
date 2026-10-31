// Azulejos da piscina/lago: grade de azulejos claros com rejunte, no espaço do mundo.
shader_type spatial;

uniform vec3 tile : source_color = vec3(0.62, 0.78, 0.82);
uniform vec3 grout : source_color = vec3(0.35, 0.42, 0.44);
uniform float size = 0.25;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(wnrm);
	vec2 uv = n.y > 0.5 ? wpos.xz : (n.x > n.z ? wpos.zy : wpos.xy);
	vec2 g = abs(fract(uv / size) - 0.5);
	float line = smoothstep(0.47, 0.49, max(g.x, g.y));
	vec2 id = floor(uv / size);
	float v = fract(sin(dot(id, vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = mix(tile * (0.92 + 0.08 * v), grout, line);
	ROUGHNESS = mix(0.25, 0.8, line);
}
