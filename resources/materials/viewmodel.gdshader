shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// Material dos braços em primeira pessoa.
// A profundidade é comprimida para perto do plano próximo da câmera (o Godot
// 4.3+ usa profundidade reversa: z/w = 1 no plano próximo). Assim os braços
// nunca atravessam paredes ou objetos colados na câmera, sem precisar de uma
// segunda câmera ou SubViewport (caro em celulares). A ordem de profundidade
// entre as partes do próprio braço é preservada.

uniform vec3 base_color : source_color = vec3(0.32, 0.30, 0.22);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
// Trama do tecido (0 = pele lisa).
uniform float weave_strength : hint_range(0.0, 0.3) = 0.06;
uniform float weave_scale = 180.0;
// Variação de tom ao longo do membro (sujeira, desgaste).
uniform float grime_strength : hint_range(0.0, 0.5) = 0.12;
// Fração da faixa de profundidade usada pelos braços (0 = normal).
uniform float depth_compress : hint_range(0.0, 0.999) = 0.985;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.z, POSITION.w, depth_compress);
}

void fragment() {
	float weave = sin(UV.x * weave_scale) * sin(UV.y * weave_scale * 0.7);
	float grime = sin(UV.y * 9.0 + UV.x * 3.0) * 0.5 + 0.5;
	vec3 color = base_color * (1.0 + weave * weave_strength) * (1.0 - grime * grime_strength);
	ALBEDO = color;
	ROUGHNESS = roughness_value;
}
