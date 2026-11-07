shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, depth_prepass_alpha;

// Árvore por impostor: três planos cruzados com o atlas renderizado a partir
// do modelo realista (tools/bake_tree_impostors.gd).
// - recorte alfa (barato no celular e compatível com sombras)
// - normal "esférica": a luz envolve a copa como volume, não como placa
// - translucidez das agulhas contra a luz
// - balanço de vento que cresce com a altura, com fase por árvore
// - sem cintilar em movimento: o plano visto de lado (faixa esticada) e o
//   plano colado à câmera (ao passar rente ou por dentro da copa) somem num
//   pontilhado fixo na tela; as bordas do recorte usam alfa para cobertura
//   (MSAA), sem o serrilhado que pisca quando a câmera anda

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.42;
uniform vec3 tint : source_color = vec3(0.78, 0.86, 0.76);
uniform vec3 translucency : source_color = vec3(0.16, 0.20, 0.10);
// Altura do plano em unidades do modelo (antes da escala da instância).
uniform float card_height = 9.0;
uniform float wind_strength : hint_range(0.0, 0.2) = 0.035;
// Intensidade do vento do mundo (autoload Wind): 0 = calmaria, 1 = vendaval.
global uniform float wind_intensity;
uniform float wind_speed = 0.8;

void vertex() {
	float h = clamp(VERTEX.y / card_height, 0.0, 1.0);
	NORMAL = normalize(vec3(VERTEX.x, card_height * 0.18 + VERTEX.y * 0.12, VERTEX.z));
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = TIME * wind_speed * (0.7 + 0.8 * wind_intensity) + root.x * 0.13 + root.z * 0.17;
	float sway = h * h * card_height * wind_strength * (0.25 + 2.2 * wind_intensity);
	VERTEX.x += sin(phase) * sway;
	VERTEX.z += cos(phase * 0.83 + 1.3) * sway * 0.6;
}

// Limiar de pontilhado ordenado 4×4 (estável na tela, sem ruído no tempo).
float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int index = i.x + i.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[index] + 0.5) / 16.0;
}

void fragment() {
	vec4 color = texture(atlas, UV);
	// Normal real do plano (as normais da malha são "esféricas").
	vec3 flat_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float facing = abs(dot(flat_normal, normalize(-VERTEX)));
	float keep = smoothstep(0.05, 0.16, facing) * smoothstep(0.5, 1.6, length(VERTEX));
	if (keep < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = color.rgb * tint;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(atlas, 0));
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	BACKLIGHT = translucency;
}
