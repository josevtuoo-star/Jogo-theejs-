shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, depth_prepass_alpha;

// Árvore por impostor: três planos cruzados com o atlas renderizado a partir
// do modelo realista (tools/bake_tree_impostors.gd).
// - recorte alfa (barato no celular e compatível com sombras)
// - normal "esférica": a luz envolve a copa como volume, não como placa
// - translucidez das agulhas contra a luz
// - balanço de vento que cresce com a altura, com fase por árvore

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.42;
uniform vec3 tint : source_color = vec3(0.78, 0.86, 0.76);
uniform vec3 translucency : source_color = vec3(0.16, 0.20, 0.10);
// Altura do plano em unidades do modelo (antes da escala da instância).
uniform float card_height = 9.0;
uniform float wind_strength : hint_range(0.0, 0.2) = 0.035;
uniform float wind_speed = 0.8;

void vertex() {
	float h = clamp(VERTEX.y / card_height, 0.0, 1.0);
	NORMAL = normalize(vec3(VERTEX.x, card_height * 0.18 + VERTEX.y * 0.12, VERTEX.z));
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = TIME * wind_speed + root.x * 0.13 + root.z * 0.17;
	float sway = h * h * card_height * wind_strength;
	VERTEX.x += sin(phase) * sway;
	VERTEX.z += cos(phase * 0.83 + 1.3) * sway * 0.6;
}

void fragment() {
	vec4 color = texture(atlas, UV);
	ALBEDO = color.rgb * tint;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	BACKLIGHT = translucency;
}
