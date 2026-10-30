import * as THREE from 'three';

// Imagem final: a cena é desenhada numa textura (com antisserrilhado MSAA) e passada para a
// tela numa passada única que faz:
//  - lente de GoPro em 1ª pessoa: distorção "barril" (o centro amplia e as bordas comprimem,
//    como a grande-angular da câmera presa na cabeça). Para o centro não perder nitidez, a
//    textura é desenhada maior na proporção da ampliação;
//  - nitidez adaptativa (estilo AMD CAS): realça bordas sem estourar nem criar halo;
//  - tom (ACES) e conversão para sRGB, que o three faria ao desenhar direto na tela.
// Sem granulado/ruído.

const vertexShader = /* glsl */`
  varying vec2 vUv;
  void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;

const fragmentShader = /* glsl */`
  uniform sampler2D tScene;
  uniform float uK, uAspect, uSharp, uExposure, uSat, uContrast;
  uniform vec3 uTint;
  uniform vec2 uTexel;
  varying vec2 vUv;

  vec3 RRTAndODTFit(vec3 v) {
    vec3 a = v * (v + 0.0245786) - 0.000090537;
    vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return a / b;
  }
  vec3 aces(vec3 color) {
    const mat3 ACESInputMat = mat3(vec3(0.59719, 0.07600, 0.02840), vec3(0.35458, 0.90834, 0.13383), vec3(0.04823, 0.01566, 0.83777));
    const mat3 ACESOutputMat = mat3(vec3(1.60475, -0.10208, -0.00327), vec3(-0.53108, 1.10813, -0.07276), vec3(-0.07367, -0.00605, 1.07602));
    color *= uExposure / 0.6;
    color = ACESInputMat * color;
    color = RRTAndODTFit(color);
    color = ACESOutputMat * color;
    return clamp(color, 0.0, 1.0);
  }
  vec3 tap(vec2 uv) { return aces(texture2D(tScene, uv).rgb); }
  vec3 toSRGB(vec3 c) { return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }

  void main() {
    // barril: raio de saída r -> amostra em r * (1 + k r²) / (1 + k rmax²)
    vec2 p = vUv * 2.0 - 1.0;
    p.x *= uAspect;
    float f = (1.0 + uK * dot(p, p)) / (1.0 + uK * (uAspect * uAspect + 1.0));
    vec2 q = p * f;
    q.x /= uAspect;
    vec2 uv = q * 0.5 + 0.5;
    // nitidez adaptativa (cruz de 5 amostras)
    vec3 c = tap(uv);
    vec3 n = tap(uv + vec2(0.0, uTexel.y)), s = tap(uv - vec2(0.0, uTexel.y));
    vec3 e = tap(uv + vec2(uTexel.x, 0.0)), w = tap(uv - vec2(uTexel.x, 0.0));
    vec3 mn = min(c, min(min(n, s), min(e, w))), mx = max(c, max(max(n, s), max(e, w)));
    vec3 amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, 1e-4), 0.0, 1.0));
    vec3 wgt = -amp * mix(0.125, 0.2, uSharp);
    vec3 col = (c + (n + s + e + w) * wgt) / (1.0 + 4.0 * wgt);
    // gradação de cor: saturação, contraste suave (curva S) e tom (frio de noite, quente à tarde)
    float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(l), col, uSat) * uTint;
    col = clamp(col, 0.0, 1.0);
    col = mix(col, col * col * (3.0 - 2.0 * col), uContrast);
    // leve escurecimento nas bordas da lente
    float vig = 1.0 - 0.18 * uK * 6.0 * smoothstep(0.6, 1.6, length(p));
    gl_FragColor = vec4(toSRGB(clamp(col * vig, 0.0, 1.0)), 1.0);
  }`;

export class LensPass {
  constructor(renderer, { samples = 4 } = {}) {
    this.renderer = renderer;
    const gl2 = renderer.capabilities.isWebGL2;
    // textura em ponto flutuante (o tom é aplicado depois); sem suporte, 8 bits
    const ext = renderer.extensions;
    const half = gl2 && (ext.has('EXT_color_buffer_float') || ext.has('EXT_color_buffer_half_float'));
    this.rt = new THREE.WebGLRenderTarget(4, 4, {
      type: half ? THREE.HalfFloatType : THREE.UnsignedByteType, samples: gl2 ? samples : 0, depthBuffer: true,
      minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter,
    });
    this.rt.texture.generateMipmaps = false;
    this.material = new THREE.ShaderMaterial({
      uniforms: {
        tScene: { value: this.rt.texture }, uK: { value: 0 }, uAspect: { value: 1 }, uSharp: { value: 0.6 },
        uExposure: { value: renderer.toneMappingExposure }, uTexel: { value: new THREE.Vector2() },
        uSat: { value: 1.05 }, uContrast: { value: 0.18 }, uTint: { value: new THREE.Vector3(1, 1, 1) },
      },
      vertexShader, fragmentShader, depthTest: false, depthWrite: false, toneMapped: false,
    });
    this.quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), this.material);
    this.quad.frustumCulled = false;
    this.screen = new THREE.Scene();
    this.screen.add(this.quad);
    this.cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    this.k = 0;
    this.maxScale = 1.35; // ampliação máxima da textura (para não perder nitidez no centro)
    this._size = new THREE.Vector2();
  }

  /** Quanto o centro amplia com a distorção atual. */
  get magnification() {
    const a = this.material.uniforms.uAspect.value;
    return 1 + this.k * (a * a + 1);
  }

  _resize() {
    const r = this.renderer;
    r.getDrawingBufferSize(this._size);
    const scale = Math.min(this.maxScale, this.magnification);
    // no máximo ~4K de largura na textura
    const s = Math.min(scale, 3840 / Math.max(1, this._size.x));
    const w = Math.max(4, Math.round(this._size.x * s)), h = Math.max(4, Math.round(this._size.y * s));
    if (this.rt.width !== w || this.rt.height !== h) this.rt.setSize(w, h);
    this.material.uniforms.uAspect.value = this._size.x / Math.max(1, this._size.y);
    this.material.uniforms.uTexel.value.set(1 / w, 1 / h);
  }

  /** k: força da lente (0 = sem distorção). */
  render(scene, camera, k = 0) {
    const r = this.renderer;
    this.k = k;
    this._resize();
    this.material.uniforms.uK.value = k;
    this.material.uniforms.uExposure.value = r.toneMappingExposure;
    r.setRenderTarget(this.rt);
    r.clear();
    r.render(scene, camera);
    r.setRenderTarget(null);
    r.render(this.screen, this.cam);
  }
}
