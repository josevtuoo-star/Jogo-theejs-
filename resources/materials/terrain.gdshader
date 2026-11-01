shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Terreno PBR em três camadas (chão de floresta, grama, lama), misturadas
// pelas cores de vértice geradas em tools/build_demo_map.gd (R = grama,
// G = lama/estrada; o resto é chão de floresta). A transição usa a "altura"
// da textura (luminância) para a lama entrar nas frestas da grama em vez de
// um degradê liso. Coordenadas no plano do mundo: sem esticar em encostas
// suaves e sem costuras entre pedaços.

uniform sampler2D floor_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D floor_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D floor_arm : filter_linear_mipmap_anisotropic;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_arm : filter_linear_mipmap_anisotropic;
uniform sampler2D mud_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D mud_arm : filter_linear_mipmap_anisotropic;
// Metros por repetição de cada textura.
uniform float floor_tile = 3.0;
uniform float grass_tile = 2.5;
uniform float mud_tile = 3.0;
uniform float blend_sharpness : hint_range(1.0, 16.0) = 6.0;
// Variação de tom em grande escala (quebra a repetição).
uniform float macro_variation : hint_range(0.0, 0.5) = 0.18;
// Correção de albedo por camada: os scans são claros para uso direto; solo de
// floresta real reflete ~20-30% da luz.
uniform vec3 floor_tint : source_color = vec3(0.50, 0.47, 0.44);
uniform vec3 grass_tint : source_color = vec3(0.50, 0.66, 0.36);
uniform vec3 mud_tint : source_color = vec3(0.78, 0.74, 0.70);

varying vec3 world_position;
varying vec3 weights;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	weights = COLOR.rgb;
}

vec3 blend_heights(vec3 w, float h0, float h1, float h2) {
	vec3 hw = w * vec3(h0, h1, h2);
	vec3 boost = pow(hw + 0.0001, vec3(blend_sharpness));
	return boost / (boost.x + boost.y + boost.z);
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 uv_floor = p / floor_tile;
	vec2 uv_grass = p / grass_tile;
	vec2 uv_mud = p / mud_tile;
	vec4 a_floor = texture(floor_albedo, uv_floor) * vec4(floor_tint, 1.0);
	vec4 a_grass = texture(grass_albedo, uv_grass) * vec4(grass_tint, 1.0);
	vec4 a_mud = texture(mud_albedo, uv_mud) * vec4(mud_tint, 1.0);
	float g = clamp(weights.r, 0.0, 1.0);
	float m = clamp(weights.g, 0.0, 1.0);
	vec3 w = vec3(max(1.0 - g - m, 0.0), g, m);
	vec3 bw = blend_heights(w + 0.02, dot(a_floor.rgb, vec3(0.33)) + 0.3, dot(a_grass.rgb, vec3(0.33)) + 0.3, dot(a_mud.rgb, vec3(0.33)) + 0.3);
	vec3 albedo = a_floor.rgb * bw.x + a_grass.rgb * bw.y + a_mud.rgb * bw.z;
	vec3 n = texture(floor_normal, uv_floor).rgb * bw.x + texture(grass_normal, uv_grass).rgb * bw.y + texture(mud_normal, uv_mud).rgb * bw.z;
	vec3 arm = texture(floor_arm, uv_floor).rgb * bw.x + texture(grass_arm, uv_grass).rgb * bw.y + texture(mud_arm, uv_mud).rgb * bw.z;
	float macro = sin(p.x * 0.031 + sin(p.y * 0.023) * 2.0) * sin(p.y * 0.027 + 1.7);
	ALBEDO = albedo * (1.0 + macro * macro_variation);
	NORMAL_MAP = n;
	AO = arm.r;
	// Solo natural é quase difuso: sem isto, em ângulo rasante o Fresnel reflete
	// o céu claro de neblina e o chão distante "embranquece".
	ROUGHNESS = mix(0.82, 1.0, arm.g);
	SPECULAR = 0.25;
	METALLIC = 0.0;
}
