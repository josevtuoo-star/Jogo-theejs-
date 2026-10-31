// Correção de cor final (um retângulo na tela inteira): contraste suave, saturação um pouco
// menor e tom levemente frio (clima de sobrevivência), vinheta discreta. Sem distorção.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float saturation = 0.92;
uniform float contrast = 0.12;
uniform vec3 tint = vec3(0.98, 1.0, 1.01);
uniform float vignette = 0.25;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = clamp(mix(vec3(l), c, saturation) * tint, 0.0, 1.0);
	c = mix(c, c * c * (3.0 - 2.0 * c), contrast);
	vec2 p = SCREEN_UV * 2.0 - 1.0;
	c *= 1.0 - vignette * smoothstep(0.7, 1.6, length(p * vec2(1.0, 0.8)));
	COLOR = vec4(c, 1.0);
}
