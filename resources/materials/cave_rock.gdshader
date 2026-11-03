shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Rocha das formações de caverna (estalagmites, estalactites) e dos depósitos
// de minério. As malhas são geradas sem UV: a textura é projetada nos três
// eixos do próprio objeto. Minério: pintas e veios (ruído 3D no shader) com a
// cor e o brilho do mineral — carvão preto e lustroso, ferro ocre-ferrugem.

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.62, 0.6, 0.57);
// Tira parte da cor da foto (a rocha de origem é alaranjada).
uniform float desaturate : hint_range(0.0, 1.0) = 0.55;
uniform float tile = 1.2;
uniform vec3 fleck_color : source_color = vec3(0.05, 0.05, 0.05);
uniform float fleck_amount : hint_range(0.0, 1.0) = 0.0;
uniform float fleck_roughness : hint_range(0.0, 1.0) = 0.35;
uniform float fleck_metallic : hint_range(0.0, 1.0) = 0.2;
uniform float fleck_scale = 6.0;
// Umidade: as formações brilham um pouco (água escorrendo).
uniform float wetness : hint_range(0.0, 1.0) = 0.25;

varying vec3 object_position;
varying vec3 object_normal;

void vertex() {
	object_position = VERTEX;
	object_normal = NORMAL;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 w = pow(abs(object_normal), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = object_position / tile;
	vec3 rock = texture(rock_albedo, p.zy).rgb * w.x + texture(rock_albedo, p.xz).rgb * w.y + texture(rock_albedo, p.xy).rgb * w.z;
	// Variação de tom em escala de palmo (manchas de mineral e umidade).
	float stain = value_noise(object_position * 1.7);
	rock = mix(rock, vec3(dot(rock, vec3(0.3, 0.59, 0.11))), desaturate);
	vec3 albedo = rock * tint * mix(0.8, 1.15, stain);
	float rough = mix(0.85, 0.6, wetness * stain);
	float metal = 0.0;
	if (fleck_amount > 0.0) {
		// Pintas grandes + veios finos.
		float n = value_noise(object_position * fleck_scale) * 0.65 + value_noise(object_position * fleck_scale * 2.7) * 0.35;
		float vein = 1.0 - abs(value_noise(object_position * fleck_scale * 0.6 + 3.1) * 2.0 - 1.0);
		float mask = max(smoothstep(1.0 - fleck_amount * 0.55, 1.0 - fleck_amount * 0.4, n), smoothstep(0.93, 0.98, vein) * fleck_amount);
		albedo = mix(albedo, fleck_color * mix(0.8, 1.2, stain), mask);
		rough = mix(rough, fleck_roughness, mask);
		metal = fleck_metallic * mask;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.35;
}
