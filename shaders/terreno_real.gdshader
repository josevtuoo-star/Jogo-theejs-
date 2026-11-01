// Terreno real: cor da imagem de satélite (Sentinel-2) por baixo; de perto, detalhe de barro
// rachado, pedrinhas e capim seco; estradas de terra com marcas de pneu, asfalto (PB-394) e
// areia no leito do rio, conforme a máscara gerada dos dados do OpenStreetMap/Overture.
shader_type spatial;
render_mode skip_vertex_transform;

uniform sampler2D satelite : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D mascara : filter_linear, repeat_disable;
uniform sampler2D detalhe : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asfalto : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 area = vec4(-1480.0, -1480.0, 2960.0, 5005.0); // x0, z0, largura, altura (m)
uniform float detalhe_dist = 90.0;

varying vec3 wpos;
varying float vdist;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vdist = length(VERTEX);
}

void fragment() {
	vec2 uv = (wpos.xz - area.xy) / area.zw;
	vec3 sat = texture(satelite, uv).rgb;
	vec3 m = texture(mascara, uv).rgb;
	float near = 1.0 - smoothstep(detalhe_dist * 0.5, detalhe_dist, vdist);
	vec3 d = texture(detalhe, wpos.xz * 0.18).rgb;
	vec3 d2 = texture(detalhe, wpos.xz * 0.031 + 0.37).rgb;
	// solo: satélite com variação de perto (manchas, rachaduras, pedrinhas)
	// o satélite vem claro e saturado: escurece para o albedo de solo seco e tira cor
	sat = sat * 0.6;
	float lum = dot(sat, vec3(0.333));
	sat = mix(vec3(lum), sat, 0.72);
	vec3 c = sat * (0.85 + 0.3 * d2.r);
	vec3 barro = vec3(0.4, 0.31, 0.23) * (0.8 + 0.6 * lum);
	c = mix(c, c * (0.88 + 0.24 * d.r), near);
	// rachaduras só no barro claro e de perto, discretas
	float pertinho = 1.0 - smoothstep(12.0, 30.0, vdist);
	c = mix(c, c * 0.8, d.g * pertinho * smoothstep(0.2, 0.32, lum) * 0.3);
	c = mix(c, vec3(0.45, 0.42, 0.38), d.b * near * 0.4);
	// estrada de terra (mais clara, batida, com as duas trilhas de pneu)
	float trilha = smoothstep(0.3, 0.7, d2.g) * 0.12;
	c = mix(c, barro * (0.92 + 0.16 * d.r) - trilha, m.g * 0.85);
	// asfalto da rodovia
	vec3 a = texture(asfalto, wpos.xz * 0.12).rgb;
	c = mix(c, a * 0.36, m.r);
	// areia do rio / beira de açude
	c = mix(c, vec3(0.5, 0.44, 0.34) * (0.85 + 0.3 * d.r), m.b * 0.8);
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.75, m.r);
	SPECULAR = 0.25;
}
