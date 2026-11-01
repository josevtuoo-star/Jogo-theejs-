shader_type spatial;
// Roupa do personagem pintada por região (COLOR.rgb = cor, COLOR.a = tecido) com trama do
// tecido, desgaste e sujeira. CUSTOM0.xyz = posição do vértice na pose de descanso (a trama
// acompanha o corpo quando ele se mexe).
// tecido: 0 pele, 0,2 jeans, 0,4 lona, 0,55 xadrez, 0,7 couro, 0,9 metal

varying vec3 rp;
varying vec4 col;

void vertex() {
	rp = CUSTOM0.xyz;
	col = COLOR;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03) * 0.3 + vnoise(p * 4.1) * 0.2;
}

void fragment() {
	float kind = col.a;
	vec3 c = col.rgb;
	float rough = 0.9;
	float n = fbm(rp * 18.0);
	// trama fina some de longe (sem serrilhado/moiré)
	float aa = 1.0 - smoothstep(0.0012, 0.004, length(fwidth(rp)));
	if (kind < 0.1) {
		// pele: manchas leves, um pouco de brilho
		c *= 0.92 + 0.12 * n;
		rough = 0.62;
	} else if (kind < 0.3) {
		// jeans: sarja diagonal e desbotado nos joelhos/coxas
		float tw = sin((rp.x + rp.z + rp.y) * 520.0) * 0.5 + 0.5;
		c *= 1.0 - 0.14 * aa * (1.0 - tw);
		float fade = smoothstep(0.55, 0.85, fbm(rp * 6.0 + 3.0));
		c = mix(c, c * 1.45 + vec3(0.03), fade * 0.45);
		rough = 0.95;
	} else if (kind < 0.48) {
		// lona: trama cruzada e desgaste
		float w = (sin(rp.y * 420.0) * sin((rp.x + rp.z) * 420.0)) * 0.5 + 0.5;
		c *= 1.0 - 0.12 * aa * (1.0 - w);
		c *= 0.85 + 0.25 * n;
		rough = 0.92;
	} else if (kind < 0.62) {
		// camisa xadrez de flanela
		float sx = step(0.5, fract((rp.x + rp.z) * 14.0));
		float sy = step(0.5, fract(rp.y * 14.0));
		float thin = step(0.85, fract((rp.x + rp.z) * 28.0)) + step(0.85, fract(rp.y * 28.0));
		c = mix(c, c * 0.35, (sx + sy) * 0.35);
		c = mix(c, vec3(0.55, 0.5, 0.42), clamp(thin, 0.0, 1.0) * 0.25 * aa);
		rough = 0.95;
	} else if (kind < 0.8) {
		// couro: gasto, um pouco brilhante
		c *= 0.8 + 0.4 * n;
		rough = 0.55 + 0.25 * n;
	} else {
		c *= 0.9 + 0.2 * n;
		rough = 0.35;
		METALLIC = 0.7;
	}
	// sujeira: barro de baixo para cima e manchas espalhadas
	if (kind > 0.1) {
		float mud = (1.0 - smoothstep(0.05, 0.6, rp.y)) * (0.55 + 0.45 * fbm(rp * 9.0 + 7.0));
		float stain = smoothstep(0.62, 0.8, fbm(rp * 5.0 + 11.0)) * 0.55;
		vec3 dirt = vec3(0.17, 0.13, 0.09);
		c = mix(c, dirt, clamp(mud * 0.7 + stain * 0.5, 0.0, 0.8));
		rough = mix(rough, 1.0, mud * 0.5);
	} else {
		// sujeira no rosto/mãos
		c = mix(c, vec3(0.3, 0.24, 0.18), smoothstep(0.6, 0.85, fbm(rp * 12.0 + 5.0)) * 0.35);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
