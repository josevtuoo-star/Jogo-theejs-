shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Pele e roupa dos zumbis (estilo apodrecido de série de zumbis): a cor
// base da parte (pele ou tecido) recebe encardido, manchas de sangue seco e,
// na pele, veias escuras e palidez. As manchas vêm das cores de vértice
// (r = encardido, g = sangue, b = veias), calculadas na pose de repouso, então
// não "escorregam" pelo corpo quando ele anima.

uniform vec3 base_color : source_color = vec3(0.5, 0.5, 0.45);
uniform float is_skin : hint_range(0.0, 1.0) = 0.0;
uniform float grime : hint_range(0.0, 1.0) = 0.6;
uniform float blood : hint_range(0.0, 1.0) = 0.5;
uniform vec3 blood_color : source_color = vec3(0.22, 0.025, 0.02);
uniform vec3 vein_color : source_color = vec3(0.22, 0.24, 0.3);

void fragment() {
	float dirt = COLOR.r;
	float splat = COLOR.g;
	float vein = COLOR.b;
	vec3 albedo = base_color * mix(1.0, 0.5, dirt * grime);
	// Tecido gasto: desbota onde não está sujo.
	albedo = mix(albedo, vec3(dot(albedo, vec3(0.33))), 0.25 * (1.0 - is_skin));
	if (is_skin > 0.5) {
		albedo = mix(albedo, vein_color, smoothstep(0.6, 0.9, vein) * 0.55);
	}
	float wet = smoothstep(0.55, 0.8, splat) * blood;
	albedo = mix(albedo, blood_color, wet);
	ALBEDO = albedo;
	ROUGHNESS = mix(0.9, 0.45, wet);
	SPECULAR = mix(0.3, 0.55, wet);
}
