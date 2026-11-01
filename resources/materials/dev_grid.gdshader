shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Grade de calibração em coordenadas do mundo: 1 célula = 1 metro.
// Calculada no fragment shader, sem texturas (barata em GPUs móveis).

uniform vec3 base_color : source_color = vec3(0.36, 0.37, 0.36);
uniform vec3 line_color : source_color = vec3(0.18, 0.19, 0.18);
uniform float cell_size : hint_range(0.05, 10.0) = 1.0;
uniform float line_width : hint_range(0.001, 0.2) = 0.02;
uniform float checker_strength : hint_range(0.0, 0.5) = 0.06;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.88;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 plane = n.y >= max(n.x, n.z) ? world_position.xz : (n.x >= n.z ? world_position.zy : world_position.xy);
	vec2 cell = plane / cell_size;
	vec2 distance_to_line = abs(fract(cell - 0.5) - 0.5);
	vec2 aa = fwidth(cell);
	vec2 lines = 1.0 - smoothstep(vec2(line_width) - aa, vec2(line_width) + aa, distance_to_line);
	float line = max(lines.x, lines.y);
	float checker = mod(floor(cell.x) + floor(cell.y), 2.0);
	vec3 base = base_color * (1.0 - checker_strength * checker);
	ALBEDO = mix(base, line_color, line);
	ROUGHNESS = roughness_value;
}
