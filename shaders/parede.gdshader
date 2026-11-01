// Casas do sertão: reboco pintado (cor por casa, no COLOR), desbotado, manchado de barro
// embaixo e descascando; telhado de telha colonial (barro) ou zinco enferrujado.
// UV2.x: 0 = parede, 1 = telha, 2 = zinco, 3 = piso de cimento
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D reboco : filter_linear_mipmap, repeat_enable;
uniform sampler2D zinco : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 wpos;
varying float tipo;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tipo = UV2.x;
}

void fragment() {
	vec3 r = texture(reboco, UV * 0.22).rgb;
	vec3 c;
	float rough = 0.95;
	if (tipo < 0.5) {
		c = COLOR.rgb * (0.82 + 0.3 * r.r) * (0.94 + 0.12 * r.g);
		// descascado: aparece o tijolo/reboco cru
		c = mix(c, vec3(0.55, 0.38, 0.3) * (0.8 + 0.4 * r.g), smoothstep(0.75, 1.0, r.b) * 0.6);
		// barrado: faixa de baixo pintada mais escura (comum nas casas do sertão)
		c = mix(c, c * vec3(0.55, 0.5, 0.48), step(UV.y, 0.85) * step(0.0, UV.y) * 0.8);
		c *= 0.85;
		// barro subindo pela parede e escorrido de chuva
		float h = UV.y; // altura na parede (m)
		c = mix(c, vec3(0.42, 0.32, 0.22), (1.0 - smoothstep(0.0, 0.7, h)) * 0.55);
		c *= 0.85 + 0.15 * smoothstep(0.0, 2.5, h);
	} else if (tipo < 1.5) {
		// telha colonial: fileiras de canal
		float row = fract(UV.y * 2.6);
		float col = fract(UV.x * 5.0);
		float shade = 0.65 + 0.35 * sin(col * 3.14159);
		c = vec3(0.56, 0.3, 0.2) * shade * (0.8 + 0.4 * r.r) * (0.85 + 0.15 * smoothstep(0.0, 0.15, row));
		c = mix(c, vec3(0.25, 0.22, 0.18), smoothstep(0.55, 0.8, r.r) * 0.5); // limo e sujeira
		rough = 0.85;
	} else if (tipo < 2.5) {
		c = texture(zinco, UV * vec2(0.5, 0.5)).rgb;
		rough = 0.7;
		METALLIC = 0.3;
	} else {
		c = vec3(0.5, 0.48, 0.45) * (0.8 + 0.3 * r.r);
		rough = 0.9;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.2;
}
