shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Carcaça de veículo abandonado. Os modelos não têm UV: as texturas são
// projetadas nos três eixos do próprio objeto (acompanham a carcaça).
// Por instância (MultiMesh, INSTANCE_CUSTOM): rgb = cor da pintura desbotada,
// a = quanto a ferrugem já tomou (0 = pintura quase inteira, 1 = só ferrugem).
// A ferrugem nasce do desenho da textura de ferrugem e começa por baixo
// (respingo da estrada) e pelo teto (água parada).

uniform sampler2D rust_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D paint_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float tile = 1.6;
uniform float body_height = 1.6;

varying vec3 object_position;
varying vec3 object_normal;
varying vec4 custom;

void vertex() {
	object_position = VERTEX;
	object_normal = NORMAL;
	custom = INSTANCE_CUSTOM;
}

vec3 triplanar_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec4 triplanar(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.zy) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

void fragment() {
	vec3 w = triplanar_weights(object_normal);
	vec3 p = object_position / tile;
	vec3 rust = triplanar(rust_albedo, p * 0.7, w).rgb;
	vec3 streaks = triplanar(paint_albedo, p, w).rgb;
	// Pintura desbotada: a cor da instância, sujada pelos escorridos da
	// textura de chapa pintada (sem o vermelho dela).
	float grime = dot(streaks, vec3(0.33));
	vec3 paint = custom.rgb * mix(0.72, 1.0, smoothstep(0.1, 0.5, grime));
	// Máscara de ferrugem: desenho da ferrugem + mais embaixo e no teto.
	float pattern = dot(rust, vec3(0.6, 0.3, 0.1));
	float low = 1.0 - smoothstep(0.0, body_height * 0.45, object_position.y);
	float top = smoothstep(0.6, 0.95, object_normal.y);
	float amount = clamp(custom.a + low * 0.35 + top * 0.25, 0.0, 1.0);
	float mask = smoothstep(amount - 0.15, amount + 0.15, 1.0 - pattern);
	ALBEDO = mix(paint, rust * vec3(0.85, 0.7, 0.6), 1.0 - mask);
	ROUGHNESS = mix(0.95, 0.6, mask);
	METALLIC = mix(0.35, 0.15, mask);
	SPECULAR = 0.4;
}
