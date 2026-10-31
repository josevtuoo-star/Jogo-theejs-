// Madeira procedural (caixas, banco, mesas): tábuas com veios, nós e frestas escuras,
// no espaço do objeto (a textura anda junto com a caixa).
shader_type spatial;

uniform vec3 light_wood : source_color = vec3(0.62, 0.45, 0.27);
uniform vec3 dark_wood : source_color = vec3(0.4, 0.27, 0.15);
uniform float plank_width = 0.16;

varying vec3 lpos;
varying vec3 lnrm;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i.x + i.y * 57.0), b = hash(i.x + 1.0 + i.y * 57.0);
	float c = hash(i.x + (i.y + 1.0) * 57.0), d = hash(i.x + 1.0 + (i.y + 1.0) * 57.0);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() { lpos = VERTEX; lnrm = NORMAL; }

void fragment() {
	vec3 n = abs(lnrm);
	// tábuas correm ao longo de X (ou de Z nas faces laterais)
	vec2 uv = n.y > 0.5 ? lpos.xz : (n.x > n.z ? lpos.zy : lpos.xy);
	float row = floor(uv.y / plank_width);
	float v = fract(uv.y / plank_width);
	float grain = vnoise(vec2(uv.x * 3.0 + row * 7.3, v * 18.0)) * 0.6 + vnoise(vec2(uv.x * 0.7, v * 50.0 + row)) * 0.4;
	vec3 c = mix(dark_wood, light_wood, grain * 0.7 + hash(row) * 0.3);
	float gap = smoothstep(0.0, 0.05, v) * smoothstep(1.0, 0.95, v);
	c *= mix(0.45, 1.0, gap);
	ALBEDO = c;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
}
