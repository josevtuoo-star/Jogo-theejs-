// Biblioteca de shaders GLSL ES 3.0 da engine.
export const SCENE_UBO = `
layout(std140) uniform Scene {
  mat4 uViewProj;
  mat4 uView;
  mat4 uShadowVP[3];
  vec4 uCamPos;      // xyz, tempo
  vec4 uSunDir;      // xyz em direção ao sol
  vec4 uSunColor;    // rgb radiância, w = umidade (chuva)
  vec4 uSkyZenith;   // rgb, w = densidade da névoa
  vec4 uSkyHorizon;  // rgb, w = queda de altura da névoa
  vec4 uGroundCol;   // rgb cor refletida do chão, w = escala do ambiente
  vec4 uFogColor;    // rgb, w = cobertura de nuvens
  vec4 uCascade;     // xyz = distâncias de corte, w = força da sombra
  vec4 uWind;        // xy direção, z força, w rajada
  vec4 uPL[4];       // luzes pontuais: xyz pos, w 1/raio
  vec4 uPLC[4];      // rgb cor, w cos externo do spot (-1 = ponto)
  vec4 uPLD[4];      // xyz direção, w cos interno
  vec4 uMisc;        // x luar, y noite, z texel da sombra, w exposição
};
`;

const HEAD = `#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;
precision highp sampler2DArray;
precision highp sampler2DArrayShadow;
${SCENE_UBO}
`;

// ---------------------------------------------------------------- funções comuns de fragmento
export const LIGHTING = `
#define PI 3.14159265359
uniform sampler2DArrayShadow uShadowMap;

vec3 skyGradient(vec3 d) {
  float t = clamp(d.y, 0.0, 1.0);
  return mix(uSkyHorizon.rgb, uSkyZenith.rgb, pow(t, 0.55));
}
vec3 ambientLight(vec3 n) {
  float t = n.y * 0.5 + 0.5;
  vec3 up = mix(uSkyHorizon.rgb, uSkyZenith.rgb, 0.65);
  return mix(uGroundCol.rgb, up, smoothstep(0.0, 1.0, t)) * uGroundCol.w;
}
float viewDepthOf(vec3 wp) { return -(uView * vec4(wp, 1.0)).z; }

float shadowFactor(vec3 wp, vec3 n, float vz) {
  if (uCascade.w <= 0.0) return 1.0;
  int ci = vz < uCascade.x ? 0 : (vz < uCascade.y ? 1 : 2);
  float lim = ci == 0 ? uCascade.x : (ci == 1 ? uCascade.y : uCascade.z);
  if (vz > uCascade.z) return 1.0;
  float nb = 0.06 * float(ci + 1);
  vec3 p = wp + n * nb;
  vec4 sc = uShadowVP[ci] * vec4(p, 1.0);
  vec3 c = sc.xyz * 0.5 + 0.5;
  if (c.x < 0.0 || c.x > 1.0 || c.y < 0.0 || c.y > 1.0 || c.z > 1.0) return 1.0;
  float bias = 0.0007 + 0.0006 * float(ci);
  float t = uMisc.z;
  float s = 0.0;
  s += texture(uShadowMap, vec4(c.xy + vec2(-t, -t) * 0.5, float(ci), c.z - bias));
  s += texture(uShadowMap, vec4(c.xy + vec2( t, -t) * 0.5, float(ci), c.z - bias));
  s += texture(uShadowMap, vec4(c.xy + vec2(-t,  t) * 0.5, float(ci), c.z - bias));
  s += texture(uShadowMap, vec4(c.xy + vec2( t,  t) * 0.5, float(ci), c.z - bias));
  s *= 0.25;
  float fade = smoothstep(uCascade.z * 0.82, uCascade.z, vz);
  return mix(mix(1.0, s, uCascade.w), 1.0, fade);
}

vec3 shade(vec3 albedo, vec3 N, vec3 V, float rough, float metal, float ao, vec3 wp, float vz) {
  rough = clamp(rough, 0.05, 1.0);
  float wet = uSunColor.w;
  // chuva: superfícies ficam mais escuras e lisas
  albedo *= mix(1.0, 0.72, wet * (1.0 - metal));
  rough = mix(rough, rough * 0.55, wet);
  vec3 F0 = mix(vec3(0.04), albedo, metal);
  vec3 diff = albedo * (1.0 - metal);
  vec3 L = uSunDir.xyz;
  float NL = max(dot(N, L), 0.0);
  float NV = max(dot(N, V), 1e-3);
  vec3 col = vec3(0.0);
  if (NL > 0.0 && uSunDir.y > -0.05) {
    float sh = shadowFactor(wp, N, vz);
    vec3 H = normalize(L + V);
    float NH = max(dot(N, H), 0.0), VH = max(dot(V, H), 0.0);
    float a = rough * rough, a2 = a * a;
    float d = NH * NH * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * d * d + 1e-5);
    float k = (rough + 1.0) * (rough + 1.0) / 8.0;
    float G = (NL / (NL * (1.0 - k) + k)) * (NV / (NV * (1.0 - k) + k));
    vec3 F = F0 + (1.0 - F0) * pow(1.0 - VH, 5.0);
    vec3 spec = D * G * F / (4.0 * NL * NV + 1e-3);
    col += (diff / PI + spec) * uSunColor.rgb * NL * sh * smoothstep(-0.05, 0.08, uSunDir.y);
  }
  // luar
  if (uMisc.x > 0.0) {
    float ml = max(dot(N, vec3(-uSunDir.x, abs(uSunDir.y) * 0.6 + 0.3, -uSunDir.z)), 0.0);
    col += diff * vec3(0.30, 0.38, 0.55) * uMisc.x * ml;
  }
  // ambiente: hemisfério + reflexo do céu
  vec3 R = reflect(-V, N);
  float fr = pow(1.0 - NV, 5.0);
  vec3 Fa = F0 + (max(vec3(1.0 - rough), F0) - F0) * fr;
  vec3 amb = ambientLight(N);
  vec3 refl = mix(skyGradient(R), ambientLight(R), rough) * (0.35 + 0.65 * smoothstep(-0.3, 0.2, R.y));
  float specOcc = clamp(ao * ao + 0.2, 0.0, 1.0);
  col += (diff * amb + Fa * refl * specOcc * (1.0 - 0.6 * rough)) * ao;
  // luzes pontuais / lanternas
  for (int i = 0; i < 4; i++) {
    if (uPLC[i].w == -2.0) continue;
    vec3 lp = uPL[i].xyz - wp;
    float dist = length(lp);
    float inv = uPL[i].w;
    if (dist * inv > 1.0) continue;
    vec3 Ld = lp / dist;
    float att = 1.0 / (1.0 + dist * dist * 0.35);
    float win = clamp(1.0 - pow(dist * inv, 4.0), 0.0, 1.0);
    float cone = 1.0;
    if (uPLC[i].w > -1.5 && uPLC[i].w < 1.0) cone = smoothstep(uPLC[i].w, uPLD[i].w, dot(-Ld, uPLD[i].xyz));
    float nl = max(dot(N, Ld), 0.0);
    vec3 Hh = normalize(Ld + V);
    float sp = pow(max(dot(N, Hh), 0.0), mix(8.0, 120.0, 1.0 - rough)) * (1.0 - rough) * 0.5;
    col += (diff / PI * 3.0 + vec3(sp)) * uPLC[i].rgb * nl * att * win * cone * 8.0;
  }
  return col;
}

vec3 aces(vec3 x) {
  const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}
vec3 applyFog(vec3 c, vec3 wp) {
  vec3 d = wp - uCamPos.xyz;
  float dist = length(d);
  float hAvg = max((wp.y + uCamPos.y) * 0.5 - 6.0, 0.0);
  float dens = uSkyZenith.w * exp(-hAvg * uSkyHorizon.w);
  float f = 1.0 - exp(-pow(dist * dens, 1.15));
  vec3 vd = d / max(dist, 1e-3);
  float sg = pow(max(dot(vd, uSunDir.xyz), 0.0), 6.0);
  vec3 fc = uFogColor.rgb + uSunColor.rgb * 0.045 * sg * (1.0 - uFogColor.w * 0.7);
  return mix(c, fc, clamp(f, 0.0, 1.0));
}
vec3 toSRGB(vec3 c) { return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }
vec3 finalColor(vec3 c, vec3 wp) { c = applyFog(c, wp); return toSRGB(aces(c * uMisc.w)); }
vec3 perturbNormal(vec3 N, vec3 p, vec2 uv, vec3 tn) {
  vec3 dp1 = dFdx(p), dp2 = dFdy(p);
  vec2 duv1 = dFdx(uv), duv2 = dFdy(uv);
  vec3 dp2perp = cross(dp2, N), dp1perp = cross(N, dp1);
  vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
  vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
  float invmax = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-12));
  return normalize(mat3(T * invmax, B * invmax, N) * tn);
}
`;

// ---------------------------------------------------------------- uber shader (opaco/alpha/instanciado/skin)
export function uberVS(def) {
  return `${HEAD}${def}
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNrm;
layout(location=2) in vec2 aUV;
layout(location=3) in vec4 aCol;
#ifdef SKINNED
layout(location=4) in uvec4 aJ;
layout(location=5) in vec4 aW;
uniform sampler2D uBones;
uniform int uBoneRow;
mat4 bone(uint j) { int x = int(j) * 4; return mat4(texelFetch(uBones, ivec2(x, uBoneRow), 0), texelFetch(uBones, ivec2(x + 1, uBoneRow), 0), texelFetch(uBones, ivec2(x + 2, uBoneRow), 0), texelFetch(uBones, ivec2(x + 3, uBoneRow), 0)); }
#endif
#if INST == 1
layout(location=6) in mat4 aModel;
layout(location=10) in vec4 aInst;
#elif INST == 2
layout(location=6) in vec4 aI0;
layout(location=7) in vec4 aI1;
#else
uniform mat4 uModel;
#endif
uniform float uWindAmp;
uniform float uInstNear;
uniform float uInstFar;
out vec3 vWP; out vec3 vN; out vec2 vUV; out vec4 vCol; out float vVZ; out vec4 vInst;
void main() {
  vec3 lp = aPos; vec3 ln = aNrm;
#ifdef SKINNED
  mat4 sk = aW.x * bone(aJ.x) + aW.y * bone(aJ.y) + aW.z * bone(aJ.z) + aW.w * bone(aJ.w);
  lp = (sk * vec4(aPos, 1.0)).xyz; ln = mat3(sk) * aNrm;
#endif
  vec3 wp, wn;
  vInst = vec4(0.0);
#if INST == 1
  wp = (aModel * vec4(lp, 1.0)).xyz; wn = mat3(aModel) * ln; vInst = aInst;
  { float idist = distance(aModel[3].xz, uCamPos.xz); if ((uInstNear > 0.0 && idist < uInstNear) || (uInstFar > 0.0 && idist > uInstFar)) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); vWP = vec3(0.0); vN = vec3(0, 1, 0); vUV = aUV; vCol = aCol; vVZ = 0.0; return; } }
#elif INST == 2
  float c = cos(aI1.x), s = sin(aI1.x);
  vec3 sp = lp * aI0.w;
  vec3 rp = vec3(c * sp.x + s * sp.z, sp.y, -s * sp.x + c * sp.z);
  wp = aI0.xyz + rp; wn = vec3(c * ln.x + s * ln.z, ln.y, -s * ln.x + c * ln.z);
  vInst = vec4(aI1.y, aI0.w, aI1.z, aI1.w);
  float idist = distance(wp.xz, uCamPos.xz);
  if ((uInstNear > 0.0 && idist < uInstNear) || (uInstFar > 0.0 && idist > uInstFar)) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); vWP = wp; vN = vec3(0, 1, 0); vUV = aUV; vCol = aCol; vVZ = 0.0; return; }
#else
  wp = (uModel * vec4(lp, 1.0)).xyz; wn = mat3(uModel) * ln;
#endif
#ifdef WIND
  {
    float bend = aCol.a;
    float t = uCamPos.w;
    float ph = dot(wp.xz, vec2(0.31, 0.27));
    float gust = sin(t * 0.7 + ph * 0.35) * 0.5 + 0.5;
    float sway = sin(t * 1.6 + ph) * 0.5 + 0.5;
    vec2 w = uWind.xy * (uWind.z * (0.55 + 0.9 * gust) + 0.12) ;
    float amp = uWindAmp * bend * bend;
    wp.xz += w * amp * (0.6 + 0.4 * sway);
    wp.x += sin(t * 5.3 + ph * 3.1 + aPos.y * 4.0) * 0.012 * uWindAmp * bend * (0.5 + uWind.z);
    wp.y -= 0.04 * amp * length(w);
  }
#endif
  vWP = wp; vN = normalize(wn); vUV = aUV; vCol = aCol;
  vec4 cp = uViewProj * vec4(wp, 1.0);
  vVZ = -(uView * vec4(wp, 1.0)).z;
  gl_Position = cp;
}`;
}

export function uberFS(def) {
  return `${HEAD}${def}
${LIGHTING}
in vec3 vWP; in vec3 vN; in vec2 vUV; in vec4 vCol; in float vVZ; in vec4 vInst;
uniform vec4 uColor;
uniform vec4 uMat;       // rugosidade, metal, corte alfa, escala normal
uniform vec3 uEmis;
#ifdef HAS_ALBEDO
uniform sampler2D uAlbedo;
#endif
#ifdef HAS_NORMAL
uniform sampler2D uNormalTex;
#endif
#ifdef HAS_ORM
uniform sampler2D uORM;
#endif
#ifdef LAYERED
uniform sampler2DArray uMatAlb;
uniform sampler2DArray uMatNor;
#endif
#ifdef TINT
uniform vec3 uRegion[8];
#endif
out vec4 oColor;
void main() {
  vec3 N = normalize(vN);
  if (!gl_FrontFacing) N = -N;
  vec4 base = uColor;
  float rough = uMat.x, metal = uMat.y, ao = 1.0;
  vec3 tn = vec3(0.0, 0.0, 1.0); bool hasN = false;
#ifdef LAYERED
  {
    float layer = floor(vCol.g * 255.0 + 0.5);
    vec4 a = texture(uMatAlb, vec3(vUV, layer));
    vec4 nr = texture(uMatNor, vec3(vUV, layer));
    base.rgb *= a.rgb * (0.82 + 0.36 * vCol.b);
    rough = nr.a * uMat.x; tn = nr.rgb * 2.0 - 1.0; tn.xy *= uMat.w; hasN = true;
  }
#endif
#ifdef HAS_ALBEDO
  { vec4 t = texture(uAlbedo, vUV); base *= t; }
#endif
#ifdef ALPHA_TEST
  if (base.a < uMat.z) discard;
#endif
#ifdef HAS_ORM
  { vec3 o = texture(uORM, vUV).rgb; ao = o.r; rough *= o.g; metal *= o.b; }
#endif
#ifdef HAS_NORMAL
  { vec3 n = texture(uNormalTex, vUV).rgb * 2.0 - 1.0; tn = vec3(n.xy * uMat.w, n.z); hasN = true; }
#endif
#ifdef VCOLOR_AO
  ao *= mix(1.0, vCol.r, 0.9);
#endif
#if INST_TINT == 1
  base.rgb *= vec3(0.78, 0.94, 0.78) * (0.78 + 0.45 * vInst.x);
#elif INST_TINT == 3
  { float rr = vInst.x; vec3 cn = vec3(0.78, 0.94, 0.78) * (0.78 + 0.45 * rr);
    vec3 g = vec3(0.68, 0.9, 0.38), y = vec3(1.3, 1.1, 0.38), o = vec3(1.5, 0.62, 0.2);
    vec3 cb = mix(mix(g, y, smoothstep(0.28, 0.6, rr)), o, smoothstep(0.72, 0.95, rr)) * (0.85 + 0.3 * fract(rr * 7.3));
    base.rgb *= mix(cn, cb, vInst.z); }
#elif INST_TINT == 2
  { float rr = vInst.x; vec3 g = vec3(0.68, 0.9, 0.38), y = vec3(1.3, 1.1, 0.38), o = vec3(1.5, 0.62, 0.2);
    base.rgb *= mix(mix(g, y, smoothstep(0.28, 0.6, rr)), o, smoothstep(0.72, 0.95, rr)) * (0.85 + 0.3 * fract(rr * 7.3)); }
#endif
#ifdef TINT
  { int r = int(vCol.g * 255.0 + 0.5); vec3 tr = uRegion[r & 7]; if (tr != vec3(1.0)) { float lu = dot(base.rgb, vec3(0.3, 0.55, 0.15)); base.rgb = tr * (0.28 + 2.2 * lu); } }
#endif
  if (hasN) N = perturbNormal(N, vWP, vUV, normalize(tn));
#ifdef FOLIAGE
  // folhagem: normal "suavizada" para cima e translucidez falsa
  N = normalize(mix(N, vec3(0.0, 1.0, 0.0), 0.45));
#endif
  vec3 V = normalize(uCamPos.xyz - vWP);
  vec3 c = shade(base.rgb, N, V, rough, metal, ao, vWP, vVZ);
#ifdef FOLIAGE
  { float tr = max(dot(-N, uSunDir.xyz), 0.0) * 0.35; c += base.rgb * base.rgb * uSunColor.rgb * tr * smoothstep(-0.05, 0.1, uSunDir.y); }
#endif
  c += uEmis;
  oColor = vec4(finalColor(c, vWP), base.a);
}`;
}

// ---------------------------------------------------------------- sombra
export function shadowVS(def) {
  return `${HEAD}${def}
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNrm;
layout(location=2) in vec2 aUV;
layout(location=3) in vec4 aCol;
#ifdef SKINNED
layout(location=4) in uvec4 aJ;
layout(location=5) in vec4 aW;
uniform sampler2D uBones;
uniform int uBoneRow;
mat4 bone(uint j) { int x = int(j) * 4; return mat4(texelFetch(uBones, ivec2(x, uBoneRow), 0), texelFetch(uBones, ivec2(x + 1, uBoneRow), 0), texelFetch(uBones, ivec2(x + 2, uBoneRow), 0), texelFetch(uBones, ivec2(x + 3, uBoneRow), 0)); }
#endif
#if INST == 1
layout(location=6) in mat4 aModel;
#elif INST == 2
layout(location=6) in vec4 aI0;
layout(location=7) in vec4 aI1;
#else
uniform mat4 uModel;
#endif
uniform mat4 uLightVP;
uniform float uWindAmp;
uniform float uInstNear;
uniform float uInstFar;
out vec2 vUV;
void main() {
  vec3 lp = aPos;
#ifdef SKINNED
  mat4 sk = aW.x * bone(aJ.x) + aW.y * bone(aJ.y) + aW.z * bone(aJ.z) + aW.w * bone(aJ.w);
  lp = (sk * vec4(aPos, 1.0)).xyz;
#endif
  vec3 wp;
#if INST == 1
  wp = (aModel * vec4(lp, 1.0)).xyz;
  { float idist = distance(aModel[3].xz, uCamPos.xz); if ((uInstNear > 0.0 && idist < uInstNear) || (uInstFar > 0.0 && idist > uInstFar)) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); vUV = aUV; return; } }
#elif INST == 2
  float c = cos(aI1.x), s = sin(aI1.x);
  vec3 sp = lp * aI0.w;
  wp = aI0.xyz + vec3(c * sp.x + s * sp.z, sp.y, -s * sp.x + c * sp.z);
  { float idist = distance(wp.xz, uCamPos.xz); if ((uInstNear > 0.0 && idist < uInstNear) || (uInstFar > 0.0 && idist > uInstFar)) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); vUV = aUV; return; } }
#else
  wp = (uModel * vec4(lp, 1.0)).xyz;
#endif
#ifdef WIND
  { float bend = aCol.a; float t = uCamPos.w; float ph = dot(wp.xz, vec2(0.31, 0.27));
    float gust = sin(t * 0.7 + ph * 0.35) * 0.5 + 0.5; float sway = sin(t * 1.6 + ph) * 0.5 + 0.5;
    vec2 w = uWind.xy * (uWind.z * (0.55 + 0.9 * gust) + 0.12); wp.xz += w * uWindAmp * bend * bend * (0.6 + 0.4 * sway); }
#endif
  vUV = aUV;
  gl_Position = uLightVP * vec4(wp, 1.0);
}`;
}
export function shadowFS(def) {
  return `${HEAD}${def}
in vec2 vUV;
#ifdef ALPHA_TEST
uniform sampler2D uAlbedo; uniform vec4 uColor; uniform vec4 uMat;
#endif
void main() {
#ifdef ALPHA_TEST
  if (texture(uAlbedo, vUV).a * uColor.a < uMat.z) discard;
#endif
}`;
}

// ---------------------------------------------------------------- céu
export const SKY_VS = `${HEAD}
uniform mat4 uInvVP;
out vec3 vDir;
void main() {
  vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
  vec4 clip = vec4(p * 2.0 - 1.0, 1.0, 1.0);
  vec4 w = uInvVP * clip;
  vDir = w.xyz / w.w - uCamPos.xyz;
  gl_Position = vec4(clip.xy, 0.9999999, 1.0);
}`;
export const SKY_FS = `${HEAD}
in vec3 vDir;
out vec4 oColor;
uniform vec4 uMoon; // xyz dir da lua, w fase
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { float s = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { s += a * vnoise(p); p = p * 2.03 + 17.0; a *= 0.5; } return s; }
vec3 aces(vec3 x) { const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14; return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0); }
vec3 toSRGB(vec3 c) { return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }
void main() {
  vec3 d = normalize(vDir);
  vec3 S = uSunDir.xyz;
  float mu = dot(d, S);
  float y = d.y;
  vec3 col = mix(uSkyHorizon.rgb, uSkyZenith.rgb, pow(clamp(y, 0.0, 1.0), 0.5));
  // brilho de Mie ao redor do sol
  float mie = pow(max(mu, 0.0), 24.0) * 0.35 + pow(max(mu, 0.0), 4.0) * 0.08;
  col += uSunColor.rgb * mie * 0.06 * (1.0 - uFogColor.w * 0.8);
  // estrelas
  float night = uMisc.y;
  if (night > 0.01 && y > 0.0) {
    vec2 sp = d.xz / (d.y + 0.35) * 90.0;
    vec2 cell = floor(sp);
    float r = h21(cell);
    vec2 f = fract(sp) - 0.5;
    float star = step(0.987, r) * smoothstep(0.35, 0.0, length(f)) * (0.4 + 0.6 * h21(cell + 7.0));
    col += vec3(0.8, 0.85, 1.0) * star * night * (1.0 - uFogColor.w) * 1.4;
  }
  // disco solar
  float sunD = smoothstep(0.99955, 0.99985, mu);
  col += uSunColor.rgb * sunD * 12.0 * (1.0 - uFogColor.w * 0.92) * step(0.0, S.y + 0.02);
  // lua
  float moonD = smoothstep(0.99965, 0.9998, dot(d, uMoon.xyz));
  col += vec3(0.75, 0.8, 0.95) * moonD * 1.6 * night * (1.0 - uFogColor.w);
  col += vec3(0.25, 0.3, 0.45) * pow(max(dot(d, uMoon.xyz), 0.0), 60.0) * 0.5 * night;
  // nuvens (plano a 1800 m)
  if (y > 0.015) {
    vec2 cp = (uCamPos.xz + d.xz / (y + 0.06) * 1800.0) * 0.00045 + uWind.xy * uCamPos.w * 0.0004;
    float n = fbm(cp * 3.0) * 0.78 + fbm(cp * 9.0 + 3.1) * 0.22;
    float cover = mix(0.54, 0.22, uFogColor.w);
    float cl = smoothstep(cover, cover + 0.22, n);
    cl *= smoothstep(0.015, 0.16, y);
    float lit = pow(max(dot(d, S), 0.0), 3.0);
    vec3 cdark = mix(uSkyHorizon.rgb, uSkyZenith.rgb, 0.5) * mix(0.55, 0.3, uFogColor.w) + uSunColor.rgb * 0.015 * lit;
    vec3 clit = (uSunColor.rgb * 0.16 + uSkyHorizon.rgb * 0.55) * (0.55 + 0.8 * clamp(S.y * 2.0, 0.0, 1.0)) + uSunColor.rgb * 0.12 * lit;
    vec3 cc = mix(cdark, clit, smoothstep(0.7, 0.35, n) * (1.0 - uFogColor.w * 0.8));
    cc = mix(cc, vec3(dot(cc, vec3(0.33))), uFogColor.w * 0.6) * mix(1.0, 0.55, uFogColor.w);
    col = mix(col, cc, cl * mix(0.9, 1.0, uFogColor.w));
  }
  // abaixo do horizonte: neblina/solo
  float below = smoothstep(0.02, -0.12, y);
  col = mix(col, uFogColor.rgb, below);
  float hz = smoothstep(0.0, 0.25, y);
  col = mix(mix(col, uFogColor.rgb, 0.55 * (1.0 - hz)), col, hz * 0.0 + hz);
  oColor = vec4(toSRGB(aces(col * uMisc.w)), 1.0);
}`;

// ---------------------------------------------------------------- terreno
export function terrainVS(def) {
  return `${HEAD}${def}
layout(location=0) in vec3 aG;       // x,z em [0,1]; y = flag de saia
uniform vec4 uChunk;                 // origemX, origemZ, tamanho, profundidade da saia
uniform sampler2D uHeight;           // R32F
uniform vec2 uHInfo;                 // dimensão, espaçamento
out vec3 vWP; out float vVZ;
void main() {
  vec2 xz = uChunk.xy + aG.xz * uChunk.z;
  ivec2 ti = ivec2(floor(xz / uHInfo.y + 0.5));
  ti = clamp(ti, ivec2(0), ivec2(int(uHInfo.x) - 1));
  float h = texelFetch(uHeight, ti, 0).r - aG.y * uChunk.w;
  vec3 wp = vec3(xz.x, h, xz.y);
  vWP = wp;
  vVZ = -(uView * vec4(wp, 1.0)).z;
  gl_Position = uViewProj * vec4(wp, 1.0);
}`;
}
export const TERRAIN_FS = `${HEAD}
${LIGHTING}
in vec3 vWP; in float vVZ;
out vec4 oColor;
uniform sampler2D uNormalMap;   // xz do normal em rg, y em b
uniform sampler2D uSplat0;      // grama, floresta, terra, rocha
uniform sampler2D uSplat1;      // areia, cascalho, asfalto/urbano, umidade
uniform sampler2DArray uTerrAlb;
uniform sampler2DArray uTerrNor;
uniform vec4 uTerrInfo;         // tamanho do mundo, 1/tamanho, -, -
uniform vec3 uLayerAvg[7];
uniform vec3 uLayerTint[7];
uniform vec4 uLayerScale;       // escalas de uv
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }
const float SC[7] = float[7](0.22, 0.2, 0.25, 0.13, 0.2, 0.25, 0.16);
void main() {
  vec2 uvw = vWP.xz * uTerrInfo.y;
  vec3 nm = texture(uNormalMap, uvw).rgb;
  vec3 N = normalize(vec3(nm.r * 2.0 - 1.0, max(nm.b, 0.02), nm.g * 2.0 - 1.0));
  vec4 s0 = texture(uSplat0, uvw), s1 = texture(uSplat1, uvw);
  float w[7] = float[7](s0.r, s0.g, s0.b, s0.a, s1.r, s1.g, s1.b);
  float n1 = vnoise(vWP.xz * 0.35), n2 = vnoise(vWP.xz * 1.9);
  // endurece as transições com ruído
  float tot = 0.0;
  for (int i = 0; i < 7; i++) { w[i] = max(w[i] * (0.75 + 0.5 * n1) + (n2 - 0.5) * 0.08 * w[i], 0.0); w[i] = w[i] * w[i]; tot += w[i]; }
  float dist = vVZ;
  vec3 albedo = vec3(0.0); float rough = 0.0;
  vec3 tn = vec3(0.0, 0.0, 1.0);
  float norm = 1.0 / max(tot, 1e-4);
  if (dist < 70.0) {
    float bestW = 0.0; int best = 0;
    for (int i = 0; i < 7; i++) {
      float wi = w[i] * norm;
      if (wi < 0.03) continue;
      vec2 uv = vWP.xz * SC[i];
      vec3 a = texture(uTerrAlb, vec3(uv, float(i))).rgb;
      a *= mix(texture(uTerrAlb, vec3(uv * 0.113 + 0.37, float(i))).rgb * 1.7, vec3(1.0), 0.45); // quebra de repetição
      albedo += a * uLayerTint[i] * wi;
      if (wi > bestW) { bestW = wi; best = i; }
    }
    if (dist < 32.0 || best == 6) {
      vec4 nt = texture(uTerrNor, vec3(vWP.xz * SC[best], float(best)));
      tn = nt.rgb * 2.0 - 1.0; rough = nt.a;
    } else rough = 0.9;
    // mistura suave com a cor média (macro) no limite
    vec3 macro = vec3(0.0);
    for (int i = 0; i < 7; i++) macro += uLayerAvg[i] * w[i] * norm;
    albedo = mix(albedo, macro * (0.9 + 0.2 * n1), smoothstep(40.0, 70.0, dist));
  } else {
    vec3 macro = vec3(0.0);
    for (int i = 0; i < 7; i++) macro += uLayerAvg[i] * w[i] * norm;
    albedo = macro * (0.85 + 0.3 * n1) * (0.92 + 0.16 * n2);
    rough = 0.92;
  }
  if (dist < 32.0) {
    vec3 dn = vec3(tn.xy * 0.9, tn.z);
    N = perturbNormal(N, vWP, vWP.xz * 0.2, normalize(vec3(dn.x, -dn.y, dn.z)));
  }
  float wet = uSunColor.w + s1.a * 0.5;
  vec3 V = normalize(uCamPos.xyz - vWP);
  vec3 c = shade(albedo, N, V, rough, 0.0, 1.0, vWP, vVZ);
  oColor = vec4(finalColor(c, vWP), 1.0);
}`;

// ---------------------------------------------------------------- grama (instanciada na GPU)
export function grassVS() {
  return `${HEAD}
layout(location=0) in vec3 aPos;     // blade local (x,y,z)
layout(location=1) in vec3 aNrm;
layout(location=2) in vec2 aUV;
layout(location=3) in vec4 aCol;     // r = id do tufo, a = peso de dobra
uniform vec4 uGrass;                 // centro x, z (alinhado a célula), raio, tamanho da célula
uniform float uGridN;
uniform sampler2D uHeight; uniform vec2 uHInfo;
uniform sampler2D uSplat0; uniform vec4 uTerrInfo;
uniform vec3 uTint;
out vec3 vWP; out vec3 vN; out vec2 vUV; out vec4 vCol; out float vVZ; out vec4 vInst;
float hash(vec2 p) { p = fract(p * vec2(443.897, 441.423)); p += dot(p, p.yx + 19.19); return fract((p.x + p.y) * p.x); }
float hfetch(vec2 xz) {
  vec2 g = xz / uHInfo.y; vec2 f = floor(g); vec2 t = g - f; ivec2 i = ivec2(f);
  ivec2 mx = ivec2(int(uHInfo.x) - 1);
  float a = texelFetch(uHeight, clamp(i, ivec2(0), mx), 0).r, b = texelFetch(uHeight, clamp(i + ivec2(1, 0), ivec2(0), mx), 0).r;
  float c = texelFetch(uHeight, clamp(i + ivec2(0, 1), ivec2(0), mx), 0).r, d = texelFetch(uHeight, clamp(i + ivec2(1, 1), ivec2(0), mx), 0).r;
  // mesma triangulação do terreno aproximada por bilinear
  return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}
void main() {
  int id = gl_InstanceID;
  float N = uGridN;
  vec2 cell = vec2(float(id % int(N)), float(id / int(N)));
  vec2 base = uGrass.xy + (cell - N * 0.5) * uGrass.w;
  vec2 rnd = vec2(hash(base), hash(base + 7.7));
  vec2 xz = base + (rnd - 0.5) * uGrass.w;
  float dist = length(xz - uCamPos.xz);
  vec4 sp = texture(uSplat0, xz * uTerrInfo.y);
  float dens = sp.r * 1.0 + sp.g * 0.35;
  float keep = step(rnd.x * 0.9 + 0.05, dens) * step(0.0, xz.x) * step(xz.x, uTerrInfo.x) * step(0.0, xz.y) * step(xz.y, uTerrInfo.x);
  float fade = 1.0 - smoothstep(uGrass.z * 0.55, uGrass.z, dist);
  if (keep < 0.5 || fade < 0.02) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); vWP = vec3(0); vN = vec3(0, 1, 0); vUV = vec2(0); vCol = vec4(0); vVZ = 0.0; vInst = vec4(0); return; }
  float h = hfetch(xz);
  float ang = hash(base + 3.1) * 6.2831853;
  float sc = (0.65 + 0.7 * hash(base + 9.3)) * fade;
  float c = cos(ang), s = sin(ang);
  vec3 lp = aPos;
  lp.xz = vec2(c * aPos.x + s * aPos.z, -s * aPos.x + c * aPos.z);
  vec3 wp = vec3(xz.x, h, xz.y) + lp * vec3(sc * (0.8 + 0.4 * rnd.y), sc, sc * (0.8 + 0.4 * rnd.y));
  // vento
  float bend = aCol.a;
  float t = uCamPos.w;
  float ph = dot(xz, vec2(0.31, 0.27));
  float gust = sin(t * 0.8 + ph * 0.3) * 0.5 + 0.5;
  vec2 wv = uWind.xy * (uWind.z * (0.5 + 0.9 * gust) + 0.1);
  wp.xz += wv * bend * bend * 0.35 + vec2(sin(t * 2.3 + ph * 1.7), cos(t * 2.0 + ph * 1.3)) * 0.035 * bend;
  vWP = wp;
  vec3 outN = normalize(vec3(c * aNrm.x + s * aNrm.z, aNrm.y, -s * aNrm.x + c * aNrm.z));
  vN = normalize(mix(vec3(0.0, 1.0, 0.0), outN, 0.35));
  vUV = aUV;
  float shade = mix(0.5, 1.05, aUV.y);
  float var = 0.8 + 0.4 * hash(base + 1.9);
  vCol = vec4(uTint * shade * var * mix(1.0, 0.82, sp.g), 1.0);
  vVZ = -(uView * vec4(wp, 1.0)).z;
  vInst = vec4(0.0);
  gl_Position = uViewProj * vec4(wp, 1.0);
}`;
}
export const GRASS_FS = `${HEAD}
${LIGHTING}
in vec3 vWP; in vec3 vN; in vec2 vUV; in vec4 vCol; in float vVZ; in vec4 vInst;
out vec4 oColor;
void main() {
  vec3 N = normalize(vN);
  vec3 V = normalize(uCamPos.xyz - vWP);
  vec3 alb = vCol.rgb;
  vec3 c = shade(alb, N, V, 0.9, 0.0, mix(0.55, 1.0, vUV.y), vWP, vVZ);
  float tr = max(dot(-V, uSunDir.xyz), 0.0) * 0.3 * smoothstep(-0.05, 0.1, uSunDir.y);
  c += alb * alb * uSunColor.rgb * tr * vUV.y;
  oColor = vec4(finalColor(c, vWP), 1.0);
}`;

// ---------------------------------------------------------------- água
export const WATER_VS = `${HEAD}
layout(location=0) in vec3 aPos;
layout(location=2) in vec2 aUV;
uniform mat4 uModel;
out vec3 vWP; out float vVZ; out vec2 vUV;
void main() {
  vec4 w = uModel * vec4(aPos, 1.0);
  vWP = w.xyz; vUV = aUV;
  vVZ = -(uView * w).z;
  gl_Position = uViewProj * w;
}`;
export const WATER_FS = `${HEAD}
${LIGHTING}
in vec3 vWP; in float vVZ; in vec2 vUV;
out vec4 oColor;
uniform sampler2D uHeightF;   // R16F filtrável
uniform vec4 uTerrInfo;
uniform vec2 uFlow;
vec2 waveGrad(vec2 p, float t) {
  vec2 g = vec2(0.0);
  const vec2 D[5] = vec2[5](vec2(0.8, 0.6), vec2(-0.6, 0.8), vec2(0.3, -0.95), vec2(-0.9, -0.4), vec2(0.97, -0.25));
  const float F[5] = float[5](0.9, 1.7, 3.1, 5.3, 8.7);
  const float A[5] = float[5](0.10, 0.07, 0.045, 0.03, 0.02);
  for (int i = 0; i < 5; i++) {
    float ph = dot(D[i], p) * F[i] + t * (0.8 + F[i] * 0.25);
    g += D[i] * cos(ph) * F[i] * A[i];
  }
  return g;
}
void main() {
  float t = uCamPos.w;
  vec2 p = vWP.xz + uFlow * t * 0.6;
  float wf = exp(-vVZ / 140.0);
  vec2 g = (waveGrad(p, t) * (0.35 + 0.65 * uWind.z) * 0.5 + waveGrad(p * 2.7 + 11.0, t * 1.3) * 0.15) * wf;
  vec3 N = normalize(vec3(-g.x, 1.0, -g.y));
  vec3 V = normalize(uCamPos.xyz - vWP);
  float NV = max(dot(N, V), 0.0);
  float fres = 0.02 + 0.98 * pow(1.0 - NV, 5.0);
  vec3 R = reflect(-V, N);
  vec3 refl = skyGradient(vec3(R.x, abs(R.y), R.z)) * 1.0;
  float ground = texture(uHeightF, vWP.xz * uTerrInfo.y).r;
  float depth = max(vWP.y - ground, 0.0);
  vec3 shallow = vec3(0.07, 0.17, 0.14), deep = vec3(0.012, 0.045, 0.06);
  shallow *= ambientLight(vec3(0.0, 1.0, 0.0)) * 1.6 + 0.05;
  deep *= ambientLight(vec3(0.0, 1.0, 0.0)) * 1.4 + 0.02;
  vec3 body = mix(shallow, deep, 1.0 - exp(-depth * 0.7));
  vec3 col = mix(body, refl, fres);
  vec3 H = normalize(uSunDir.xyz + V);
  float sp = pow(max(dot(N, H), 0.0), 220.0) * 4.0;
  col += uSunColor.rgb * sp * smoothstep(0.0, 0.1, uSunDir.y);
  // espuma na margem
  float foam = smoothstep(0.14, 0.0, depth) * (0.5 + 0.5 * sin(t * 1.5 + vWP.x * 2.0 + vWP.z * 1.7)) * wf;
  col = mix(col, vec3(0.7, 0.75, 0.75) * (ambientLight(vec3(0, 1, 0)) + 0.1), foam * 0.3);
  float alpha = clamp(mix(0.35, 0.98, 1.0 - exp(-depth * 1.4)) + fres * 0.4, 0.0, 1.0);
  oColor = vec4(finalColor(col, vWP), alpha);
}`;

// ---------------------------------------------------------------- partículas (billboards) e decalques
export const PART_VS = `${HEAD}
layout(location=0) in vec2 aCorner;
layout(location=1) in vec4 aP;     // pos xyz, tamanho
layout(location=2) in vec4 aC;     // cor rgba
layout(location=3) in vec4 aR;     // rot, quadro, esticar, luz(0=sem luz,1=com luz)
out vec2 vUV; out vec4 vC; out vec3 vWP; out float vFrame; out float vLit; out float vVZ;
void main() {
  vec3 right = vec3(uView[0][0], uView[1][0], uView[2][0]);
  vec3 up = vec3(uView[0][1], uView[1][1], uView[2][1]);
  float c = cos(aR.x), s = sin(aR.x);
  vec2 q = vec2(c * aCorner.x - s * aCorner.y, s * aCorner.x + c * aCorner.y);
  vec3 wp;
  if (aR.z > 0.0) { // estica na direção do movimento (chuva): up = direção
    vec3 dir = normalize(vec3(uWind.x * 0.4, -1.0, uWind.y * 0.4));
    vec3 toCam = normalize(uCamPos.xyz - aP.xyz);
    vec3 rgt = normalize(cross(dir, toCam));
    wp = aP.xyz + rgt * aCorner.x * aP.w + dir * aCorner.y * aR.z;
  } else wp = aP.xyz + (right * q.x + up * q.y) * aP.w;
  vWP = wp; vUV = aCorner * 0.5 + 0.5; vC = aC; vFrame = aR.y; vLit = aR.w;
  vVZ = -(uView * vec4(wp, 1.0)).z;
  gl_Position = uViewProj * vec4(wp, 1.0);
}`;
export const PART_FS = `${HEAD}
${LIGHTING}
in vec2 vUV; in vec4 vC; in vec3 vWP; in float vFrame; in float vLit; in float vVZ;
out vec4 oColor;
uniform sampler2D uAtlas;
uniform float uAdd;
void main() {
  float f = floor(vFrame + 0.5);
  vec2 uv = (vec2(mod(f, 4.0), floor(f / 4.0)) + vUV) * 0.25;
  vec4 t = texture(uAtlas, uv);
  vec4 col = t * vC;
  if (col.a < 0.003) discard;
  vec3 rgb = col.rgb;
  if (vLit > 0.5) rgb *= (ambientLight(vec3(0, 1, 0)) * 0.9 + uSunColor.rgb * 0.12 * max(uSunDir.y, 0.0) + 0.03);
  if (uAdd > 0.5) { vec3 d = vWP - uCamPos.xyz; float fg = 1.0 - exp(-length(d) * uSkyZenith.w * 0.8); oColor = vec4(rgb * (1.0 - fg), col.a); }
  else { vec3 fc = applyFog(rgb, vWP); oColor = vec4(toSRGB(aces(fc * uMisc.w)), col.a); }
  if (uAdd > 0.5) oColor.rgb = toSRGB(aces(oColor.rgb * uMisc.w));
}`;

// decalques orientados (buracos de bala, manchas)
export const DECAL_VS = `${HEAD}
layout(location=0) in vec2 aCorner;
layout(location=1) in vec4 aP;     // pos, tamanho
layout(location=2) in vec4 aN;     // normal, rot
layout(location=3) in vec4 aC;     // cor, frame no alfa? (cor rgb + alpha)
out vec2 vUV; out vec4 vC; out vec3 vWP; out float vFrame; out float vLit; out float vVZ;
void main() {
  vLit = 1.0;
  vec3 n = normalize(aN.xyz);
  vec3 t = abs(n.y) > 0.95 ? vec3(1, 0, 0) : normalize(cross(vec3(0, 1, 0), n));
  vec3 b = cross(n, t);
  float fr = floor(aN.w / 10.0), rt = aN.w - fr * 10.0;
  float c = cos(rt), s = sin(rt);
  vec2 q = vec2(c * aCorner.x - s * aCorner.y, s * aCorner.x + c * aCorner.y);
  vec3 wp = aP.xyz + n * 0.012 + (t * q.x + b * q.y) * aP.w;
  vWP = wp; vUV = aCorner * 0.5 + 0.5; vC = aC; vFrame = fr;
  vVZ = -(uView * vec4(wp, 1.0)).z;
  gl_Position = uViewProj * vec4(wp, 1.0);
}`;

// linhas (fios, rastros)
export const LINE_VS = `${HEAD}
layout(location=0) in vec3 aPos;
layout(location=3) in vec4 aCol;
out vec4 vC; out vec3 vWP;
void main() { vC = aCol; vWP = aPos; gl_Position = uViewProj * vec4(aPos, 1.0); }`;
export const LINE_FS = `${HEAD}
${LIGHTING}
in vec4 vC; in vec3 vWP;
out vec4 oColor;
uniform float uUnlit;
void main() {
  vec3 c = vC.rgb;
  if (uUnlit < 0.5) c *= (ambientLight(vec3(0, 1, 0)) + uSunColor.rgb * 0.06 * max(uSunDir.y, 0.0));
  oColor = vec4(finalColor(c, vWP), vC.a);
}`;
