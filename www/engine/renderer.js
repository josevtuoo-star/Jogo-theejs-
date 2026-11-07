// Renderer forward PBR com sombras em cascata, instancing e skinning.
import { createGL, Program, bindTex, LOC, texFromData } from './gl.js';
import { m4, v3, Frustum, clamp } from './math.js';
import * as SH from './shaders.js';

const SAMPLER_UNITS = {
  uAlbedo: 0, uNormalTex: 1, uORM: 2, uBones: 3, uShadowMap: 4, uMatAlb: 5, uMatNor: 6, uHeight: 7,
  uNormalMap: 8, uSplat0: 9, uSplat1: 10, uTerrAlb: 11, uTerrNor: 12, uHeightF: 13, uAtlas: 14,
};

export class Material {
  constructor(o = {}) {
    this.albedo = o.albedo || null;
    this.normal = o.normal || null;
    this.orm = o.orm || null;
    this.color = o.color || [1, 1, 1, 1];
    this.rough = o.rough ?? 0.8;
    this.metal = o.metal ?? 0;
    this.emissive = o.emissive || [0, 0, 0];
    this.alphaTest = o.alphaTest ?? 0;      // corte alfa (0 = desligado)
    this.blend = !!o.blend;
    this.doubleSided = !!o.doubleSided;
    this.layered = !!o.layered;             // usa array de materiais (camada = cor.g do vértice)
    this.wind = o.wind ?? 0;                // amplitude do vento
    this.foliage = !!o.foliage;
    this.tint = !!o.tint;                   // regiões do personagem
    this.instTint = o.instTint || 0;        // variação de cor por instância (1 conífera, 2 folhosa)
    this.regionTints = o.regionTints || new Float32Array(24).fill(1);
    this.normalScale = o.normalScale ?? 1;
    this.vcolorAO = o.vcolorAO ?? true;
    this.noShadow = !!o.noShadow;
    this.depthWrite = o.depthWrite ?? !o.blend;
    this.name = o.name || '';
    this.refreshKey();
  }
  refreshKey() {
    this.flagKey = [
      this.albedo ? 'A' : '', this.normal ? 'N' : '', this.orm ? 'O' : '', this.alphaTest > 0 ? 'T' : '', this.layered ? 'L' : '',
      this.wind > 0 ? 'W' : '', this.foliage ? 'F' : '', this.tint ? 'R' : '', this.vcolorAO ? 'V' : '', this.instTint ? 'I' + this.instTint : '',
    ].join('');
  }
}

export class Renderer {
  constructor(canvas, settings = {}) {
    this.canvas = canvas;
    this.settings = Object.assign({ renderScale: 1, shadows: 2, shadowSize: 2048, antialias: true, maxDPR: 3, aniso: 8 }, settings);
    const gl = this.gl = createGL(canvas, { antialias: this.settings.antialias, preserve: settings.preserve });
    this.programs = new Map();
    this.pass = 'main';
    this.mainFrustum = new Frustum();
    this.shadowFrustum = new Frustum();
    this.frustum = this.mainFrustum;
    this.vp = m4.create(); this.view = m4.create(); this.proj = m4.create(); this.invVP = m4.create();
    this.cam = { pos: v3.create(), fwd: v3.create(0, 0, -1), right: v3.create(1, 0, 0), up: v3.create(0, 1, 0), fov: 70 * Math.PI / 180, near: 0.1, far: 1500, aspect: 1 };
    this.env = null;
    this.time = 0;
    this._boundTex = new Array(16).fill(null);
    this._state = {};
    this.transparents = [];
    this.uboData = new Float32Array(168);
    this.ubo = gl.createBuffer();
    gl.bindBuffer(gl.UNIFORM_BUFFER, this.ubo);
    gl.bufferData(gl.UNIFORM_BUFFER, this.uboData.byteLength, gl.DYNAMIC_DRAW);
    gl.bindBufferBase(gl.UNIFORM_BUFFER, 0, this.ubo);
    this.white = texFromData(gl, 1, 1, new Uint8Array([255, 255, 255, 255]), { wrap: gl.REPEAT });
    // texturas de ossos (RGBA32F: 4 texels por junta)
    this.boneRows = 24;
    this.boneTex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, this.boneTex);
    gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA32F, 256, this.boneRows);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    this.matAlb = null; this.matNor = null;
    this.shadowLightVP = [m4.create(), m4.create(), m4.create()];
    this.shadowCascades = 0;
    this.shadowSplits = [20, 80, 260];
    this._initShadow();
    this.skyProg = this._prog('sky', SH.SKY_VS, SH.SKY_FS);
    this.emptyVAO = gl.createVertexArray();
    this.resize();
    gl.enable(gl.DEPTH_TEST);
    gl.depthFunc(gl.LEQUAL);
    gl.enable(gl.CULL_FACE);
    gl.cullFace(gl.BACK);
    gl.clearColor(0, 0, 0, 1);
  }

  // ------------------------------------------------------------ programas
  _prog(name, vs, fs) {
    let p = this.programs.get(name);
    if (p) return p;
    p = new Program(this.gl, vs, fs, name);
    this.programs.set(name, p);
    p._needInit = true;
    return p;
  }
  prog(name, vs, fs) { return this._prog(name, vs, fs); }
  use(p) {
    if (this._curProg !== p) {
      p.use();
      if (p._needInit) {
        p._needInit = false;
        for (const [n, u] of Object.entries(SAMPLER_UNITS)) p.i1(n, u);
      }
      this._curProg = p;
    }
    return p;
  }
  _defs(o) { return Object.entries(o).filter(([, v]) => v !== false && v !== undefined).map(([k, v]) => `#define ${k} ${v === true ? 1 : v}\n`).join(''); }
  _uber(mat, inst, skinned) {
    const key = 'u' + mat.flagKey + inst + (skinned ? 'S' : '');
    let p = this.programs.get(key);
    if (p) return p;
    const d = this._defs({
      INST: inst, SKINNED: skinned, HAS_ALBEDO: !!mat.albedo, HAS_NORMAL: !!mat.normal, HAS_ORM: !!mat.orm,
      ALPHA_TEST: mat.alphaTest > 0, LAYERED: mat.layered, WIND: mat.wind > 0, FOLIAGE: mat.foliage, TINT: mat.tint, VCOLOR_AO: mat.vcolorAO, INST_TINT: mat.instTint || 0,
    });
    return this._prog(key, SH.uberVS(d), SH.uberFS(d));
  }
  _shadowP(mat, inst, skinned) {
    const key = 's' + (mat.alphaTest > 0 ? 'T' : '') + (mat.wind > 0 ? 'W' : '') + inst + (skinned ? 'S' : '');
    let p = this.programs.get(key);
    if (p) return p;
    const d = this._defs({ INST: inst, SKINNED: skinned, ALPHA_TEST: mat.alphaTest > 0, WIND: mat.wind > 0 });
    return this._prog(key, SH.shadowVS(d), SH.shadowFS(d));
  }

  // ------------------------------------------------------------ tamanho
  resize(cssW, cssH) {
    const c = this.canvas;
    cssW = cssW || c.clientWidth || window.innerWidth; cssH = cssH || c.clientHeight || window.innerHeight;
    const dpr = Math.min(window.devicePixelRatio || 1, this.settings.maxDPR);
    const s = this.settings.renderScale;
    const w = Math.max(64, Math.round(cssW * dpr * s)), h = Math.max(64, Math.round(cssH * dpr * s));
    if (c.width !== w || c.height !== h) { c.width = w; c.height = h; }
    this.width = w; this.height = h;
    this.cam.aspect = w / h;
  }

  // ------------------------------------------------------------ sombras
  _initShadow() {
    const gl = this.gl;
    if (this.shadowTex) { gl.deleteTexture(this.shadowTex); gl.deleteFramebuffer(this.shadowFB); }
    const n = this.settings.shadows, size = this.settings.shadowSize;
    this.shadowCascades = n; this.shadowSize = size;
    if (!n) return;
    const t = this.shadowTex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D_ARRAY, t);
    gl.texStorage3D(gl.TEXTURE_2D_ARRAY, 1, gl.DEPTH_COMPONENT24, size, size, 3);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_COMPARE_MODE, gl.COMPARE_REF_TO_TEXTURE);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_COMPARE_FUNC, gl.LEQUAL);
    this.shadowFB = gl.createFramebuffer();
  }
  setShadowQuality(cascades, size) {
    this.settings.shadows = cascades; this.settings.shadowSize = size;
    this._initShadow();
  }

  _fitCascades() {
    const env = this.env, cam = this.cam, n = this.shadowCascades, size = this.shadowSize;
    const S = env.sunDir, tanY = Math.tan(cam.fov / 2), tanX = tanY * cam.aspect;
    const up = Math.abs(S[1]) > 0.97 ? [0, 0, 1] : [0, 1, 0];
    const splits = this.shadowSplits;
    for (let i = 0; i < n; i++) {
      const zn = i === 0 ? cam.near : splits[i - 1], zf = splits[i];
      const c = [];
      for (const z of [zn, zf]) {
        const cx = cam.pos[0] + cam.fwd[0] * z, cy = cam.pos[1] + cam.fwd[1] * z, cz = cam.pos[2] + cam.fwd[2] * z;
        for (const sx of [-1, 1]) for (const sy of [-1, 1]) {
          c.push([cx + (cam.right[0] * sx * tanX + cam.up[0] * sy * tanY) * z, cy + (cam.right[1] * sx * tanX + cam.up[1] * sy * tanY) * z, cz + (cam.right[2] * sx * tanX + cam.up[2] * sy * tanY) * z]);
        }
      }
      const ctr = [0, 0, 0];
      for (const p of c) { ctr[0] += p[0] / 8; ctr[1] += p[1] / 8; ctr[2] += p[2] / 8; }
      let r = 0;
      for (const p of c) r = Math.max(r, Math.hypot(p[0] - ctr[0], p[1] - ctr[1], p[2] - ctr[2]));
      r = Math.ceil(r * 8) / 8;
      const ext = 160 + i * 60;
      const eye = [ctr[0] + S[0] * (r + ext), ctr[1] + S[1] * (r + ext), ctr[2] + S[2] * (r + ext)];
      const lv = m4.lookAt(m4.create(), eye, ctr, up);
      const lp = m4.ortho(m4.create(), -r, r, -r, r, 0, r * 2 + ext + 40);
      const vp = m4.multiply(this.shadowLightVP[i], lp, lv);
      // snap ao texel
      const p0 = [0, 0, 0]; m4.transformPoint(p0, lv, ctr);
      const cx = p0[0] / r, cy = p0[1] / r; // [-1,1]
      const tex = 2 / size;
      const dx = Math.round(cx / tex) * tex - cx, dy = Math.round(cy / tex) * tex - cy;
      vp[12] += dx; vp[13] += dy;
    }
  }

  // ------------------------------------------------------------ câmera / ambiente / UBO
  setCamera(pos, yaw, pitch, fov, near = 0.08, far = 1600, roll = 0) {
    const c = this.cam;
    v3.copy(c.pos, pos); c.fov = fov; c.near = near; c.far = far;
    const cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch);
    c.fwd[0] = -sy * cp; c.fwd[1] = sp; c.fwd[2] = -cy * cp;
    c.right[0] = cy; c.right[1] = 0; c.right[2] = -sy;
    v3.cross(c.up, c.right, c.fwd);
    if (roll) { const cr = Math.cos(roll), sr = Math.sin(roll); const r0 = [c.right[0], c.right[1], c.right[2]], u0 = [c.up[0], c.up[1], c.up[2]]; for (let i = 0; i < 3; i++) { c.right[i] = r0[i] * cr + u0[i] * sr; c.up[i] = u0[i] * cr - r0[i] * sr; } }
    const tgt = [pos[0] + c.fwd[0], pos[1] + c.fwd[1], pos[2] + c.fwd[2]];
    m4.lookAt(this.view, pos, tgt, c.up);
    m4.perspective(this.proj, fov, c.aspect, near, far);
    m4.multiply(this.vp, this.proj, this.view);
    m4.invert(this.invVP, this.vp);
    this.mainFrustum.set(this.vp);
  }
  setEnv(env) { this.env = env; }

  _uploadScene() {
    const e = this.env, u = this.uboData, c = this.cam, gl = this.gl;
    u.set(this.vp, 0); u.set(this.view, 16);
    for (let i = 0; i < 3; i++) u.set(this.shadowLightVP[i], 32 + i * 16);
    let o = 80;
    const put4 = (a, b, cc, d) => { u[o++] = a; u[o++] = b; u[o++] = cc; u[o++] = d; };
    put4(c.pos[0], c.pos[1], c.pos[2], this.time);
    put4(e.sunDir[0], e.sunDir[1], e.sunDir[2], 0);
    put4(e.sunColor[0], e.sunColor[1], e.sunColor[2], e.wetness);
    put4(e.zenith[0], e.zenith[1], e.zenith[2], e.fogDensity);
    put4(e.horizon[0], e.horizon[1], e.horizon[2], e.fogFalloff);
    put4(e.ground[0], e.ground[1], e.ground[2], e.ambientScale);
    put4(e.fog[0], e.fog[1], e.fog[2], e.cloud);
    const sp = this.shadowSplits, n = this.shadowCascades;
    put4(sp[0], n >= 2 ? sp[1] : sp[Math.max(n - 1, 0)], n >= 3 ? sp[2] : sp[Math.max(n - 1, 0)], this.shadowActive ? e.shadowStrength : 0);
    put4(e.wind[0], e.wind[1], e.wind[2], e.wind[3]);
    for (let i = 0; i < 4; i++) { const l = e.lights[i]; if (l) put4(l.pos[0], l.pos[1], l.pos[2], 1 / l.radius); else put4(0, 0, 0, 0); }
    for (let i = 0; i < 4; i++) { const l = e.lights[i]; if (l) put4(l.color[0] * l.intensity, l.color[1] * l.intensity, l.color[2] * l.intensity, l.spot ? l.cosOuter : -1); else put4(0, 0, 0, -2); }
    for (let i = 0; i < 4; i++) { const l = e.lights[i]; if (l && l.spot) put4(l.dir[0], l.dir[1], l.dir[2], l.cosInner); else put4(0, 0, 1, 1); }
    put4(e.moon, e.night, 1 / this.shadowSize, e.exposure);
    gl.bindBuffer(gl.UNIFORM_BUFFER, this.ubo);
    gl.bufferSubData(gl.UNIFORM_BUFFER, 0, u);
  }

  // ------------------------------------------------------------ estados
  _cull(on) { if (this._state.cull !== on) { this._state.cull = on; on ? this.gl.enable(this.gl.CULL_FACE) : this.gl.disable(this.gl.CULL_FACE); } }
  _blend(on) {
    if (this._state.blend !== on) {
      this._state.blend = on;
      const gl = this.gl;
      if (on) { gl.enable(gl.BLEND); gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA); } else gl.disable(gl.BLEND);
    }
  }
  _depthWrite(on) { if (this._state.dw !== on) { this._state.dw = on; this.gl.depthMask(on); } }
  tex(unit, tex, target) {
    if (this._boundTex[unit] !== tex || target) { bindTex(this.gl, unit, tex, target || this.gl.TEXTURE_2D); this._boundTex[unit] = tex; if (target) this._boundTex[unit] = null; }
  }

  // ------------------------------------------------------------ desenho
  // o: { model: Float32Array(16), inst: InstanceBuffer, count, skinRow }
  draw(mesh, mat, o = {}) {
    const gl = this.gl, shadow = this.pass === 'shadow';
    if (shadow && (mat.blend || mat.noShadow)) return;
    const inst = o.inst, im = inst ? inst.mode : 0;
    if (inst && inst.count === 0) return;
    const skinned = !!mesh.skinned && o.skinRow !== undefined;
    const p = this.use(shadow ? this._shadowP(mat, im, skinned) : this._uber(mat, im, skinned));
    if (shadow) { p.m4('uLightVP', this.lightVP); }
    // texturas são estado global: sempre (re)vincula (o cache interno evita chamadas repetidas)
    if (mat.albedo && (!shadow || mat.alphaTest > 0)) this.tex(0, mat.albedo);
    if (!shadow) {
      if (mat.normal) this.tex(1, mat.normal);
      if (mat.orm) this.tex(2, mat.orm);
      if (mat.layered) { this.tex(5, this.matAlb, gl.TEXTURE_2D_ARRAY); this.tex(6, this.matNor, gl.TEXTURE_2D_ARRAY); }
    }
    // uniformes são por programa: só reenvia se o material mudou
    if (p._mat !== mat || p._pass !== this.pass) {
      p._mat = mat; p._pass = this.pass;
      if (!shadow) {
        p.f4('uColor', mat.color[0], mat.color[1], mat.color[2], mat.color[3]);
        p.f3('uEmis', mat.emissive[0], mat.emissive[1], mat.emissive[2]);
        if (mat.tint) { const l = p.loc('uRegion[0]'); if (l) gl.uniform3fv(l, mat.regionTints); }
      } else p.f4('uColor', 1, 1, 1, mat.color[3]);
      p.f4('uMat', mat.rough, mat.metal, mat.alphaTest, mat.normalScale);
      p.f1('uWindAmp', mat.wind);
    } else if (mat.tint && !shadow) { const l = p.loc('uRegion[0]'); if (l) gl.uniform3fv(l, mat.regionTints); }
    if (skinned) { this.tex(3, this.boneTex); p.i1('uBoneRow', o.skinRow); }
    if (!shadow) {
      this._cull(!mat.doubleSided);
      this._blend(mat.blend);
      this._depthWrite(mat.depthWrite);
      const dc = !!mat.decal;
      if (dc !== this._state.decal) { this._state.decal = dc; if (dc) { gl.enable(gl.POLYGON_OFFSET_FILL); gl.polygonOffset(-2, -6); } else gl.disable(gl.POLYGON_OFFSET_FILL); }
    } else this._cull(!mat.doubleSided);
    if (!inst) p.m4('uModel', o.model || this._identity || (this._identity = m4.create()));
    else if (im === 2) p.f1('uInstNear', o.instNear || 0);
    if (inst) {
      gl.bindVertexArray(inst.vaoFor(mesh));
      const n = o.count ?? inst.count;
      gl.drawElementsInstanced(gl.TRIANGLES, mesh.indexCount, mesh.indexType, 0, n);
      gl.stats.draws++; gl.stats.tris += mesh.tris * n;
    } else {
      gl.bindVertexArray(mesh.vao);
      gl.drawElements(gl.TRIANGLES, mesh.indexCount, mesh.indexType, 0);
      gl.stats.draws++; gl.stats.tris += mesh.tris;
    }
  }

  setBones(row, data) {
    const gl = this.gl;
    gl.activeTexture(gl.TEXTURE0 + 3);
    gl.bindTexture(gl.TEXTURE_2D, this.boneTex);
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, row, data.length / 4, 1, gl.RGBA, gl.FLOAT, data);
    this._boundTex[3] = null;
  }

  // visibilidade na passada atual
  visible(x, y, z, r) { return this.frustum.sphere(x, y, z, r); }
  visibleBox(a, b, c, d, e, f) { return this.frustum.aabb(a, b, c, d, e, f); }

  // ------------------------------------------------------------ frame
  // scene: { drawShadow(r, cascade), draw(r), drawTransparent(r) }
  render(scene, t) {
    const gl = this.gl;
    this.time = t;
    gl.stats.draws = 0; gl.stats.tris = 0;
    const e = this.env;
    this.shadowActive = this.shadowCascades > 0 && e.sunDir[1] > 0.03 && e.shadowStrength > 0;
    this._curProg = null;
    this._boundTex.fill(null);
    if (this.shadowActive) this._fitCascades();
    this._uploadScene();
    // --- sombras
    if (this.shadowActive) {
      this.pass = 'shadow';
      gl.bindFramebuffer(gl.FRAMEBUFFER, this.shadowFB);
      gl.viewport(0, 0, this.shadowSize, this.shadowSize);
      gl.colorMask(false, false, false, false);
      gl.enable(gl.POLYGON_OFFSET_FILL); gl.polygonOffset(1.6, 3.0);
      gl.depthMask(true); this._state.dw = true;
      for (let i = 0; i < this.shadowCascades; i++) {
        gl.framebufferTextureLayer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, this.shadowTex, 0, i);
        gl.clear(gl.DEPTH_BUFFER_BIT);
        this.lightVP = this.shadowLightVP[i];
        this.frustum = this.shadowFrustum;
        this.frustum.set(this.lightVP);
        this.cascadeIndex = i;
        this._curProg = null;
        scene.drawShadow(this, i);
      }
      gl.disable(gl.POLYGON_OFFSET_FILL);
      gl.colorMask(true, true, true, true);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    }
    // --- principal
    this.pass = 'main';
    this._state.decal = false; gl.disable(gl.POLYGON_OFFSET_FILL);
    gl.viewport(0, 0, this.width, this.height);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    this._curProg = null;
    this.frustum = this.mainFrustum;
    this._depthWrite(true); this._blend(false); this._cull(true);
    if (this.shadowActive) this.tex(4, this.shadowTex, gl.TEXTURE_2D_ARRAY);
    else if (this.shadowTex) this.tex(4, this.shadowTex, gl.TEXTURE_2D_ARRAY);
    scene.draw(this);
    this.drawSky();
    this._boundTex.fill(null);
    if (this.shadowTex) this.tex(4, this.shadowTex, gl.TEXTURE_2D_ARRAY);
    if (scene.drawTransparent) scene.drawTransparent(this);
    this._depthWrite(true); this._blend(false);
  }

  drawSky() {
    const gl = this.gl, p = this.use(this.skyProg), e = this.env;
    p.m4('uInvVP', this.invVP);
    p.f4('uMoon', e.moonDir[0], e.moonDir[1], e.moonDir[2], 0);
    this._cull(false); this._blend(false); this._depthWrite(false);
    gl.bindVertexArray(this.emptyVAO);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    this._depthWrite(true);
  }
}
