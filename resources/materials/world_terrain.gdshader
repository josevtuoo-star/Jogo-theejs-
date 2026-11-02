shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Terreno do mundo procedural (superfície e cavernas, malha de surface nets).
// Camadas: chão de floresta, grama, asfalto rachado, cascalho/lama (acostamento
// e chão de caverna) — projetadas de cima — e rocha com musgo, projetada nos
// três eixos, nos barrancos, paredes e tetos de caverna.
// Cores de vértice (WorldGenerator._vertex_weights): R = grama, G = asfalto,
// B = cascalho, A = céu aberto (0 no fundo da caverna: tira a luz difusa do
// céu, que não chega lá dentro).

uniform sampler2D floor_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float floor_tile = 3.0;
uniform float grass_tile = 2.5;
uniform float road_tile = 4.0;
uniform float gravel_tile = 3.0;
uniform float rock_tile = 4.5;
uniform float normal_strength = 0.8;
uniform float macro_variation : hint_range(0.0, 0.5) = 0.18;
// Scans claros para uso direto: solo real reflete ~20-30% da luz.
uniform vec3 floor_tint : source_color = vec3(0.50, 0.47, 0.44);
uniform vec3 grass_tint : source_color = vec3(0.46, 0.58, 0.34);
uniform vec3 road_tint : source_color = vec3(0.62, 0.62, 0.62);
uniform vec3 gravel_tint : source_color = vec3(0.62, 0.58, 0.54);
uniform vec3 rock_tint : source_color = vec3(0.72, 0.71, 0.68);

varying vec3 world_position;
varying vec3 world_normal;
varying vec4 weights;
varying vec2 road_frame;
varying vec2 road_info;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	weights = COLOR;
	road_frame = UV;
	road_info = UV2;
}

// Asfalto velho: a textura "road damaged" é marrom; puxa para o cinza do
// asfalto gasto e pinta as faixas (tracejada amarela no meio, brancas nas
// bordas), apagadas pelo desgaste (manchas escuras da própria textura).
vec3 asphalt(vec2 p, vec2 frame, vec2 info) {
	vec3 a = texture(road_albedo, p / road_tile).rgb;
	float l = dot(a, vec3(0.3, 0.59, 0.11));
	vec3 grey = mix(vec3(l), a, 0.3) * road_tint;
	if (info.x > 0.5) {
		float offset = abs(frame.x);
		float wear = smoothstep(0.18, 0.3, l + texture(road_albedo, p / 1.3).r * 0.25);
		float center = (1.0 - smoothstep(0.06, 0.09, offset)) * step(fract(frame.y / 9.0), 0.42);
		float edge = 1.0 - smoothstep(0.05, 0.08, abs(offset - (info.y - 0.45)));
		grey = mix(grey, vec3(0.52, 0.42, 0.16), center * wear * 0.8);
		grey = mix(grey, vec3(0.55, 0.55, 0.52), edge * wear * 0.7);
	}
	return grey;
}

// Normal de uma textura projetada de cima, somada à normal da superfície.
vec3 top_normal(sampler2D tex, vec2 uv, vec3 n) {
	vec3 t = texture(tex, uv).rgb * 2.0 - 1.0;
	return vec3(t.x, 0.0, -t.y);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec2 p = world_position.xz;
	float sky = clamp(weights.a, 0.0, 1.0);
	float grass = clamp(weights.r, 0.0, 1.0);
	float road = clamp(weights.g, 0.0, 1.0);
	float gravel = clamp(weights.b, 0.0, 1.0);
	// Rocha: barrancos íngremes e paredes/tetos dentro da terra.
	float steep = 1.0 - smoothstep(0.5, 0.78, n.y);
	float rock = clamp(max(steep, (1.0 - sky) * (1.0 - smoothstep(0.55, 0.85, n.y))), 0.0, 1.0);
	float ground = max(1.0 - grass - road - gravel, 0.0);
	vec3 albedo = vec3(0.0);
	vec3 bump = vec3(0.0);
	float rough = 0.0;
	float flat_weight = 1.0 - rock;
	if (flat_weight > 0.01) {
		vec4 w = vec4(ground, grass, road, gravel);
		w /= max(w.x + w.y + w.z + w.w, 0.0001);
		vec3 a = vec3(0.0);
		vec3 b = vec3(0.0);
		if (w.x > 0.01) {
			a += texture(floor_albedo, p / floor_tile).rgb * floor_tint * w.x;
			b += top_normal(floor_normal, p / floor_tile, n) * w.x;
		}
		if (w.y > 0.01) {
			a += texture(grass_albedo, p / grass_tile).rgb * grass_tint * w.y;
			b += top_normal(grass_normal, p / grass_tile, n) * w.y;
		}
		if (w.z > 0.01) {
			a += asphalt(p, road_frame, road_info) * w.z;
			b += top_normal(road_normal, p / road_tile, n) * w.z;
		}
		if (w.w > 0.01) {
			a += texture(gravel_albedo, p / gravel_tile).rgb * gravel_tint * w.w;
			b += top_normal(gravel_normal, p / gravel_tile, n) * w.w;
		}
		albedo += a * flat_weight;
		bump += b * flat_weight;
		rough += mix(0.9, 0.82, w.z) * flat_weight;
	}
	if (rock > 0.01) {
		vec3 tw = pow(abs(n), vec3(4.0));
		tw /= (tw.x + tw.y + tw.z);
		vec3 q = world_position / rock_tile;
		vec3 a = texture(rock_albedo, q.zy).rgb * tw.x + texture(rock_albedo, q.xz).rgb * tw.y + texture(rock_albedo, q.xy).rgb * tw.z;
		vec3 tx = texture(rock_normal, q.zy).rgb * 2.0 - 1.0;
		vec3 ty = texture(rock_normal, q.xz).rgb * 2.0 - 1.0;
		vec3 tz = texture(rock_normal, q.xy).rgb * 2.0 - 1.0;
		vec3 b = vec3(0.0, tx.y, tx.x) * tw.x + vec3(ty.x, 0.0, -ty.y) * tw.y + vec3(tz.x, tz.y, 0.0) * tw.z;
		albedo += a * rock_tint * rock;
		bump += b * rock;
		rough += 0.88 * rock;
	}
	float macro = sin(p.x * 0.031 + sin(p.y * 0.023) * 2.0) * sin(p.y * 0.027 + 1.7);
	// Dentro da terra: úmido e escuro.
	ALBEDO = albedo * (1.0 + macro * macro_variation) * mix(0.8, 1.0, sky);
	vec3 world_bumped = normalize(n + bump * normal_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_bumped, 0.0)).xyz);
	ROUGHNESS = mix(0.7, rough, sky);
	SPECULAR = 0.25;
	AO = mix(0.03, 1.0, sky * sky);
	AO_LIGHT_AFFECT = 0.0;
}
