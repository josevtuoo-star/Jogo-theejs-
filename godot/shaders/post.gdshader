// Pós-processamento da imagem final (um retângulo na tela inteira):
// - correção de cor leve em todas as câmeras (contraste, saturação, vinheta suave);
// - bodycam (1ª pessoa): lente grande-angular "olho de peixe" (o centro amplia e as bordas
//   curvam), aberração cromática nas bordas, vinheta forte, cor mais fria e lavada como de
//   câmera de corpo, e um leve borrão de movimento das bordas.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float bodycam : hint_range(0.0, 1.0) = 0.0;
uniform float lens = 0.38;
uniform float saturation = 1.08;
uniform float contrast = 0.12;
uniform vec3 tint = vec3(1.0, 0.99, 0.97);

vec3 grade(vec3 c, float b) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float sat = mix(saturation, 0.82, b);
	c = mix(vec3(l), c, sat);
	c *= mix(tint, vec3(0.96, 1.0, 1.04), b);
	c = clamp(c, 0.0, 1.0);
	float ct = mix(contrast, 0.28, b);
	c = mix(c, c * c * (3.0 - 2.0 * c), ct);
	// pretos um pouco "levantados" na bodycam (sensor pequeno)
	c = mix(c, c * 0.94 + 0.03, b);
	return c;
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	vec2 p = SCREEN_UV * 2.0 - 1.0;
	p.x *= aspect;
	float r2 = dot(p, p);
	float rmax2 = aspect * aspect + 1.0;
	float k = lens * bodycam;
	// barril: o raio de saída r amostra em r * (1 + k r²) / (1 + k rmax²)
	vec2 q = p * (1.0 + k * r2) / (1.0 + k * rmax2);
	float ca = (0.0012 + 0.0055 * bodycam) * r2;
	vec2 uvr = vec2(q.x * (1.0 + ca) / aspect, q.y * (1.0 + ca)) * 0.5 + 0.5;
	vec2 uvg = vec2(q.x / aspect, q.y) * 0.5 + 0.5;
	vec2 uvb = vec2(q.x * (1.0 - ca) / aspect, q.y * (1.0 - ca)) * 0.5 + 0.5;
	vec3 c = vec3(texture(screen_tex, uvr).r, texture(screen_tex, uvg).g, texture(screen_tex, uvb).b);
	c = grade(c, bodycam);
	// vinheta (forte e arredondada na bodycam, como a borda da lente)
	float rn = length(p) / sqrt(rmax2);
	float vig = mix(0.22, 0.6, bodycam);
	c *= 1.0 - vig * smoothstep(mix(0.55, 0.62, bodycam), 1.05, rn);
	COLOR = vec4(c, 1.0);
}
