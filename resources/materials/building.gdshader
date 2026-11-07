shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Prédios e casas abandonados das vilas e cidades (etapa 9), todos numa só
// malha por pedaço. As paredes têm UV em metros (u ao longo da parede, v a
// partir do chão) e a cor do vértice diz o que desenhar:
//   r = estilo/7 (0 tijolo, 1 reboco, 2 concreto, 3 tábuas, 4 telha, 5 zinco)
//   g = variação de tom, b = 1 janelas pintadas / 0,5 face interna / 0 fachada
//   lisa, a = semente do prédio.
// Janelas e portas são desenhadas aqui (sem geometria): vidro escuro, vidro
// quebrado (buraco preto) ou tábuas pregadas; porta ou vitrine no térreo.
// Abandono: encardido escorrendo das janelas, base suja e trepadeiras subindo
// pelas paredes, com manchas de musgo nos telhados.

uniform sampler2D brick_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D plaster_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D concrete_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D planks_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D roof_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tin_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float floor_height = 3.2;
uniform float bay_width = 3.0;
uniform vec3 vine_color : source_color = vec3(0.12, 0.19, 0.07);

varying vec4 info;

void vertex() {
	info = COLOR;
}

float hash2(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	int style = int(round(info.r * 7.0));
	vec2 uv = UV;
	vec3 base;
	if (style == 0) {
		base = texture(brick_albedo, uv / 2.2).rgb;
	} else if (style == 1) {
		base = texture(plaster_albedo, uv / 3.0).rgb * mix(vec3(0.98, 0.9, 0.76), vec3(0.78, 0.85, 0.86), info.g);
	} else if (style == 2) {
		base = texture(concrete_albedo, uv / 3.0).rgb;
	} else if (style == 3) {
		base = texture(planks_albedo, vec2(uv.y, uv.x) / 2.0).rgb;
	} else if (style == 4) {
		base = texture(roof_albedo, uv / 2.5).rgb;
	} else {
		base = texture(tin_albedo, uv / 2.0).rgb;
	}
	base *= mix(0.82, 1.08, info.g);
	float rough = 0.9;
	float spec = 0.3;
	// b: 1 = fachada com janelas pintadas, 0,5 = face interna, 0 = fachada lisa.
	float wall = step(0.75, info.b);
	float interior = step(0.25, info.b) * (1.0 - wall);
	if (wall > 0.5 && uv.y > 0.0) {
		float level = floor(uv.y / floor_height);
		float fy = mod(uv.y, floor_height);
		float bay = floor(uv.x / bay_width);
		float fx = mod(uv.x, bay_width);
		float pick = hash2(vec2(bay, level) + info.a * 91.0);
		vec2 lo = vec2(0.75, 0.9);
		vec2 hi = vec2(bay_width - 0.75, 2.45);
		bool door = false;
		if (level < 0.5) {
			if (pick < 0.3) {
				door = true;
				lo = vec2(0.95, 0.0);
				hi = vec2(bay_width - 0.95, 2.2);
			} else if (style == 2 || style == 0) {
				lo = vec2(0.3, 0.35); // vitrine de loja
				hi = vec2(bay_width - 0.3, 2.6);
			}
		}
		float inside = step(lo.x, fx) * step(fx, hi.x) * step(lo.y, fy) * step(fy, hi.y);
		// Escorrido de sujeira abaixo das janelas.
		float below = step(lo.x + 0.1, fx) * step(fx, hi.x - 0.1) * step(fy, lo.y) * smoothstep(lo.y - 1.6, lo.y, fy);
		base *= 1.0 - below * 0.35 * vnoise(vec2(uv.x * 6.0, 0.0));
		if (inside > 0.5) {
			float edge = min(min(fx - lo.x, hi.x - fx), min(fy - lo.y, hi.y - fy));
			float state = hash2(vec2(bay * 1.7, level * 3.1) + info.a * 13.0);
			vec3 glass = vec3(0.02, 0.025, 0.03);
			if (door) {
				// Porta de madeira velha (às vezes arrombada: vão escuro).
				glass = state < 0.4 ? vec3(0.015) : texture(planks_albedo, vec2(fy, fx) / 1.5).rgb * 0.55;
				rough = 0.9;
			} else if (state < 0.22) {
				// Tábuas pregadas.
				float board = step(0.12, fract(fy * 2.2 + hash2(vec2(bay, level)) * 3.0));
				glass = mix(vec3(0.01), texture(planks_albedo, vec2(fx, fy) / 1.2).rgb * 0.75, board);
				rough = 0.9;
			} else if (state < 0.55) {
				// Vidro quebrado: o buraco escuro com cacos nos cantos.
				float shard = step(0.82, vnoise(vec2(fx, fy) * 7.0 + state * 50.0)) * step(edge, 0.35);
				glass = mix(vec3(0.008), vec3(0.08, 0.09, 0.1), shard);
				rough = mix(0.95, 0.1, shard);
				spec = mix(0.1, 0.8, shard);
			} else {
				// Vidro inteiro, sujo, refletindo o céu.
				glass = vec3(0.04, 0.05, 0.055) + vec3(0.05) * vnoise(vec2(fx, fy) * 3.0);
				rough = 0.12;
				spec = 0.8;
			}
			float frame = 1.0 - step(0.07, edge);
			base = mix(glass, vec3(0.2, 0.19, 0.17), frame);
			if (frame > 0.5) {
				rough = 0.8;
				spec = 0.3;
			}
		}
	}
	// Base suja e escorridos verticais.
	base *= mix(0.65, 1.0, smoothstep(0.0, 1.4, uv.y)) * mix(0.85, 1.0, vnoise(vec2(uv.x * 3.0, uv.y * 0.25)));
	// Trepadeiras subindo das paredes (mais altas em alguns trechos).
	float reach = 1.2 + vnoise(vec2(uv.x * 0.35, info.a * 40.0)) * 6.5 * info.g;
	float leaves = smoothstep(0.42, 0.62, vnoise(uv * 2.3 + info.a * 17.0)) * (1.0 - smoothstep(reach - 1.2, reach, uv.y));
	float green = wall > 0.5 ? leaves : smoothstep(0.62, 0.8, vnoise(uv * 0.8 + info.a * 9.0)) * 0.7;
	if (info.b < 0.25 && abs(NORMAL.y) < 0.5) {
		green = leaves; // fachada lisa (casa com vãos de verdade): trepadeiras também
	}
	green *= 1.0 - interior;
	base = mix(base, vine_color * (0.65 + 0.7 * vnoise(uv * 11.0)), green * 0.9);
	rough = mix(rough, 0.95, green);
	ALBEDO = base;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
