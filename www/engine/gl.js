// Camada fina sobre WebGL2: contexto, programas, buffers, texturas, malhas, instancing.
import { v3 } from './math.js';

export const LOC = { POS: 0, NRM: 1, UV: 2, COL: 3, JOINTS: 4, WEIGHTS: 5, INST0: 6, INST1: 7, INST2: 8, INST3: 9, INST4: 10 };

export function createGL(canvas, opts = {}) {
  const gl = canvas.getContext('webgl2', {
    antialias: opts.antialias ?? true, alpha: false, depth: true, stencil: false,
    powerPreference: 'high-performance', preserveDrawingBuffer: !!opts.preserve, failIfMajorPerformanceCaveat: false,
  });
  if (!gl) throw new Error('WebGL2 indisponível neste dispositivo');
  gl.caps = {
    aniso: 1,
    maxTex: gl.getParameter(gl.MAX_TEXTURE_SIZE),
    maxUBO: gl.getParameter(gl.MAX_UNIFORM_BLOCK_SIZE),
    renderer: '', vendor: '',
    floatLinear: !!gl.getExtension('OES_texture_float_linear'),
    colorBufferFloat: !!gl.getExtension('EXT_color_buffer_float'),
    parallel: gl.getExtension('KHR_parallel_shader_compile'),
  };
  const an = gl.getExtension('EXT_texture_filter_anisotropic');
  if (an) { gl.caps.anisoExt = an; gl.caps.aniso = gl.getParameter(an.MAX_TEXTURE_MAX_ANISOTROPY_EXT); }
  const dbg = gl.getExtension('WEBGL_debug_renderer_info');
  if (dbg) { gl.caps.renderer = gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL); gl.caps.vendor = gl.getParameter(dbg.UNMASKED_VENDOR_WEBGL); }
  gl.stats = { draws: 0, tris: 0, programs: 0 };
  return gl;
}

// ------------------------------------------------------------------ programas
export class Program {
  constructor(gl, vsSrc, fsSrc, name = '') {
    this.gl = gl; this.name = name;
    const vs = this._sh(gl.VERTEX_SHADER, vsSrc), fs = this._sh(gl.FRAGMENT_SHADER, fsSrc);
    const p = gl.createProgram();
    gl.attachShader(p, vs); gl.attachShader(p, fs);
    gl.linkProgram(p);
    this.prog = p; this.vs = vs; this.fs = fs;
    this.u = {}; this._checked = false;
    gl.stats.programs++;
  }
  _sh(type, src) {
    const gl = this.gl, s = gl.createShader(type);
    gl.shaderSource(s, src); gl.compileShader(s);
    s.src = src;
    return s;
  }
  check() {
    if (this._checked) return;
    this._checked = true;
    const gl = this.gl;
    if (!gl.getProgramParameter(this.prog, gl.LINK_STATUS)) {
      const log = (gl.getShaderInfoLog(this.vs) || '') + (gl.getShaderInfoLog(this.fs) || '') + gl.getProgramInfoLog(this.prog);
      const numbered = (s) => s.src.split('\n').map((l, i) => (i + 1) + ': ' + l).join('\n');
      console.error('Shader erro [' + this.name + ']\n' + log + '\n--VS--\n' + numbered(this.vs).slice(0, 6000));
      throw new Error('Shader ' + this.name + ': ' + log.slice(0, 400));
    }
    const sceneIdx = gl.getUniformBlockIndex(this.prog, 'Scene');
    if (sceneIdx !== gl.INVALID_INDEX) gl.uniformBlockBinding(this.prog, sceneIdx, 0);
  }
  use() { this.check(); this.gl.useProgram(this.prog); return this; }
  loc(n) { let l = this.u[n]; if (l === undefined) l = this.u[n] = this.gl.getUniformLocation(this.prog, n); return l; }
  i1(n, v) { const l = this.loc(n); if (l) this.gl.uniform1i(l, v); }
  f1(n, v) { const l = this.loc(n); if (l) this.gl.uniform1f(l, v); }
  f2(n, a, b) { const l = this.loc(n); if (l) this.gl.uniform2f(l, a, b); }
  f3(n, a, b, c) { const l = this.loc(n); if (l) this.gl.uniform3f(l, a, b, c); }
  f4(n, a, b, c, d) { const l = this.loc(n); if (l) this.gl.uniform4f(l, a, b, c, d); }
  m4(n, m) { const l = this.loc(n); if (l) this.gl.uniformMatrix4fv(l, false, m); }
  sampler(n, unit) { this.i1(n, unit); }
}

// ------------------------------------------------------------------ texturas
export function bindTex(gl, unit, tex, target = gl.TEXTURE_2D) { gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(target, tex); }

function applyFilter(gl, target, { mips = true, aniso = 8, wrap = gl.REPEAT, nearest = false } = {}) {
  gl.texParameteri(target, gl.TEXTURE_WRAP_S, wrap);
  gl.texParameteri(target, gl.TEXTURE_WRAP_T, wrap);
  if (nearest) { gl.texParameteri(target, gl.TEXTURE_MIN_FILTER, gl.NEAREST); gl.texParameteri(target, gl.TEXTURE_MAG_FILTER, gl.NEAREST); return; }
  gl.texParameteri(target, gl.TEXTURE_MIN_FILTER, mips ? gl.LINEAR_MIPMAP_LINEAR : gl.LINEAR);
  gl.texParameteri(target, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  if (mips && gl.caps.anisoExt) gl.texParameterf(target, gl.caps.anisoExt.TEXTURE_MAX_ANISOTROPY_EXT, Math.min(aniso, gl.caps.aniso));
}

export function texFromImage(gl, img, o = {}) {
  const t = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, t);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, !!o.flipY);
  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  const w = img.width, h = img.height, levels = (o.mips ?? true) ? Math.floor(Math.log2(Math.max(w, h))) + 1 : 1;
  const ifmt = o.srgb ? gl.SRGB8_ALPHA8 : gl.RGBA8;
  gl.texStorage2D(gl.TEXTURE_2D, levels, ifmt, w, h);
  gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, gl.RGBA, gl.UNSIGNED_BYTE, img);
  if (levels > 1) gl.generateMipmap(gl.TEXTURE_2D);
  applyFilter(gl, gl.TEXTURE_2D, { mips: levels > 1, aniso: o.aniso ?? 8, wrap: o.wrap ?? gl.REPEAT });
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
  t.w = w; t.h = h;
  return t;
}

export function texFromData(gl, w, h, data, o = {}) {
  const t = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, t);
  const ifmt = o.internal ?? gl.RGBA8, fmt = o.format ?? gl.RGBA, type = o.type ?? gl.UNSIGNED_BYTE;
  const levels = o.mips ? Math.floor(Math.log2(Math.max(w, h))) + 1 : 1;
  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  gl.texStorage2D(gl.TEXTURE_2D, levels, ifmt, w, h);
  if (data) gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, w, h, fmt, type, data);
  if (levels > 1) gl.generateMipmap(gl.TEXTURE_2D);
  applyFilter(gl, gl.TEXTURE_2D, { mips: levels > 1, wrap: o.wrap ?? gl.CLAMP_TO_EDGE, nearest: o.nearest, aniso: o.aniso ?? 4 });
  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
  t.w = w; t.h = h;
  return t;
}

// array de texturas (camadas de material). As camadas são enviadas depois por setLayer().
export function texArray(gl, w, h, layers, o = {}) {
  const t = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D_ARRAY, t);
  const levels = Math.floor(Math.log2(Math.max(w, h))) + 1;
  gl.texStorage3D(gl.TEXTURE_2D_ARRAY, levels, o.srgb ? gl.SRGB8_ALPHA8 : gl.RGBA8, w, h, layers);
  applyFilter(gl, gl.TEXTURE_2D_ARRAY, { mips: true, aniso: o.aniso ?? 8 });
  t.w = w; t.h = h; t.layers = layers; t.levels = levels;
  return t;
}
export function setLayer(gl, arr, layer, img) {
  gl.bindTexture(gl.TEXTURE_2D_ARRAY, arr);
  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  if (img.width !== arr.w || img.height !== arr.h) {
    const c = document.createElement('canvas'); c.width = arr.w; c.height = arr.h;
    const g = c.getContext('2d', { willReadFrequently: false });
    g.imageSmoothingQuality = 'high'; g.drawImage(img, 0, 0, arr.w, arr.h); img = c;
  }
  gl.texSubImage3D(gl.TEXTURE_2D_ARRAY, 0, 0, 0, layer, arr.w, arr.h, 1, gl.RGBA, gl.UNSIGNED_BYTE, img);
}
export function finishArray(gl, arr) { gl.bindTexture(gl.TEXTURE_2D_ARRAY, arr); gl.generateMipmap(gl.TEXTURE_2D_ARRAY); }

export async function loadImage(url, premultiply = 'none') {
  const r = await fetch(url);
  if (!r.ok) throw new Error('falha ao carregar ' + url + ' (' + r.status + ')');
  const blob = await r.blob();
  return createImageBitmap(blob, { premultiplyAlpha: premultiply, colorSpaceConversion: 'none' });
}

// ------------------------------------------------------------------ malha
function vbo(gl, data, target = gl.ARRAY_BUFFER, usage = gl.STATIC_DRAW) {
  const b = gl.createBuffer(); gl.bindBuffer(target, b); gl.bufferData(target, data, usage); return b;
}

export class Mesh {
  // d: {positions, normals?, uvs?, colors?(Uint8 normalized 4c), indices, joints?(Uint8/16 4c), weights?(Float32 4c)}
  constructor(gl, d) {
    this.gl = gl;
    this.attribs = [];
    this.vao = gl.createVertexArray();
    gl.bindVertexArray(this.vao);
    const add = (loc, data, size, type = gl.FLOAT, norm = false, integer = false) => {
      const b = vbo(gl, data);
      this.attribs.push({ loc, buf: b, size, type, norm, integer });
      gl.enableVertexAttribArray(loc);
      if (integer) gl.vertexAttribIPointer(loc, size, type, 0, 0); else gl.vertexAttribPointer(loc, size, type, norm, 0, 0);
    };
    add(LOC.POS, d.positions, 3);
    const n = d.positions.length / 3;
    add(LOC.NRM, d.normals || new Float32Array(n * 3).fill(0), 3);
    add(LOC.UV, d.uvs || new Float32Array(n * 2), 2);
    if (d.colors) add(LOC.COL, d.colors, 4, gl.UNSIGNED_BYTE, true);
    else { gl.disableVertexAttribArray(LOC.COL); gl.vertexAttrib4f(LOC.COL, 1, 0, 0, 1); }
    if (d.joints) {
      const jt = d.joints instanceof Uint16Array ? gl.UNSIGNED_SHORT : gl.UNSIGNED_BYTE;
      add(LOC.JOINTS, d.joints, 4, jt, false, true);
      add(LOC.WEIGHTS, d.weights, 4);
      this.skinned = true;
    }
    this.ibo = vbo(gl, d.indices, gl.ELEMENT_ARRAY_BUFFER);
    this.indexType = d.indices instanceof Uint32Array ? gl.UNSIGNED_INT : gl.UNSIGNED_SHORT;
    this.indexCount = d.indices.length;
    this.tris = this.indexCount / 3;
    gl.bindVertexArray(null);
    // limites
    const p = d.positions;
    let mnx = 1e9, mny = 1e9, mnz = 1e9, mxx = -1e9, mxy = -1e9, mxz = -1e9;
    for (let i = 0; i < p.length; i += 3) {
      if (p[i] < mnx) mnx = p[i]; if (p[i] > mxx) mxx = p[i];
      if (p[i + 1] < mny) mny = p[i + 1]; if (p[i + 1] > mxy) mxy = p[i + 1];
      if (p[i + 2] < mnz) mnz = p[i + 2]; if (p[i + 2] > mxz) mxz = p[i + 2];
    }
    this.min = [mnx, mny, mnz]; this.max = [mxx, mxy, mxz];
    this.center = [(mnx + mxx) / 2, (mny + mxy) / 2, (mnz + mxz) / 2];
    this.radius = Math.hypot(mxx - mnx, mxy - mny, mxz - mnz) / 2;
    this.positions = d.indices.length < 400000 ? d.positions : null; // para colisão/raycast opcional
    this.indices = d.indices.length < 400000 ? d.indices : null;
  }
  draw() {
    const gl = this.gl;
    gl.bindVertexArray(this.vao);
    gl.drawElements(gl.TRIANGLES, this.indexCount, this.indexType, 0);
    gl.stats.draws++; gl.stats.tris += this.tris;
  }
  dispose() { const gl = this.gl; this.attribs.forEach((a) => gl.deleteBuffer(a.buf)); gl.deleteBuffer(this.ibo); gl.deleteVertexArray(this.vao); }
}

// Buffer de instâncias. mode 1: mat4+vec4 (20 floats). mode 2: compacto (8 floats: pos,escala,rotY,rand,...)
export class InstanceBuffer {
  constructor(gl, data, mode = 1, dynamic = false) {
    this.gl = gl; this.mode = mode; this.stride = mode === 1 ? 20 : 8;
    this.data = data; this.count = data.length / this.stride;
    this.buf = vbo(gl, data, gl.ARRAY_BUFFER, dynamic ? gl.DYNAMIC_DRAW : gl.STATIC_DRAW);
    this.vaos = new Map();
    this.cap = data.length;
    // volume para culling (opcional)
    this.sphere = null;
  }
  update(data, count) {
    const gl = this.gl;
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buf);
    if (data.length > this.cap) { gl.bufferData(gl.ARRAY_BUFFER, data, gl.DYNAMIC_DRAW); this.cap = data.length; }
    else gl.bufferSubData(gl.ARRAY_BUFFER, 0, data, 0, count * this.stride);
    this.count = count;
  }
  vaoFor(mesh) {
    let v = this.vaos.get(mesh);
    if (v) return v;
    const gl = this.gl;
    v = gl.createVertexArray();
    gl.bindVertexArray(v);
    for (const a of mesh.attribs) {
      gl.bindBuffer(gl.ARRAY_BUFFER, a.buf);
      gl.enableVertexAttribArray(a.loc);
      if (a.integer) gl.vertexAttribIPointer(a.loc, a.size, a.type, 0, 0); else gl.vertexAttribPointer(a.loc, a.size, a.type, a.norm, 0, 0);
    }
    if (!mesh.attribs.some((a) => a.loc === LOC.COL)) { gl.disableVertexAttribArray(LOC.COL); gl.vertexAttrib4f(LOC.COL, 1, 0, 0, 1); }
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ibo);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buf);
    if (this.mode === 1) {
      for (let i = 0; i < 4; i++) { gl.enableVertexAttribArray(LOC.INST0 + i); gl.vertexAttribPointer(LOC.INST0 + i, 4, gl.FLOAT, false, 80, i * 16); gl.vertexAttribDivisor(LOC.INST0 + i, 1); }
      gl.enableVertexAttribArray(LOC.INST4); gl.vertexAttribPointer(LOC.INST4, 4, gl.FLOAT, false, 80, 64); gl.vertexAttribDivisor(LOC.INST4, 1);
    } else {
      for (let i = 0; i < 2; i++) { gl.enableVertexAttribArray(LOC.INST0 + i); gl.vertexAttribPointer(LOC.INST0 + i, 4, gl.FLOAT, false, 32, i * 16); gl.vertexAttribDivisor(LOC.INST0 + i, 1); }
    }
    gl.bindVertexArray(null);
    this.vaos.set(mesh, v);
    return v;
  }
  dispose() { const gl = this.gl; gl.deleteBuffer(this.buf); this.vaos.forEach((v) => gl.deleteVertexArray(v)); }
}

// ------------------------------------------------------------------ framebuffer simples (cor + profundidade)
export function createRenderTarget(gl, w, h, { depth = true } = {}) {
  const fb = gl.createFramebuffer();
  gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
  const tex = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, tex);
  gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, w, h);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
  let rb = null;
  if (depth) {
    rb = gl.createRenderbuffer();
    gl.bindRenderbuffer(gl.RENDERBUFFER, rb);
    gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, w, h);
    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, rb);
  }
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  tex.w = w; tex.h = h;
  return { fb, tex, rb, w, h };
}

// ------------------------------------------------------------------ construtor de geometria procedural
export class MeshBuilder {
  constructor() { this.p = []; this.n = []; this.uv = []; this.c = []; this.i = []; }
  get vcount() { return this.p.length / 3; }
  vert(x, y, z, nx, ny, nz, u, v, r = 255, g = 0, b = 0, a = 255) {
    this.p.push(x, y, z); this.n.push(nx, ny, nz); this.uv.push(u, v); this.c.push(r, g, b, a);
    return this.p.length / 3 - 1;
  }
  tri(a, b, c) { this.i.push(a, b, c); }
  quad(a, b, c, d) { this.i.push(a, b, c, a, c, d); }
  // quad com 4 pontos (sentido anti-horário visto da frente); material layer em g
  quad4(p0, p1, p2, p3, n, uvs, layer = 0, ao = 255, bend = 0) {
    const u = uvs;
    const a = this.vert(p0[0], p0[1], p0[2], n[0], n[1], n[2], u[0], u[1], ao, layer, 0, bend);
    const b = this.vert(p1[0], p1[1], p1[2], n[0], n[1], n[2], u[2], u[3], ao, layer, 0, bend);
    const c = this.vert(p2[0], p2[1], p2[2], n[0], n[1], n[2], u[4], u[5], ao, layer, 0, bend);
    const d = this.vert(p3[0], p3[1], p3[2], n[0], n[1], n[2], u[6], u[7], ao, layer, 0, bend);
    this.quad(a, b, c, d);
  }
  // caixa alinhada (x0..x1, y0..y1, z0..z1), UV em metros, faces selecionáveis
  box(x0, y0, z0, x1, y1, z1, layer = 0, o = {}) {
    const s = o.uvScale ?? 1, ao = o.ao ?? 255;
    const faces = o.faces ?? 63; // bits: +x -x +y -y +z -z
    const dx = (x1 - x0) * s, dy = (y1 - y0) * s, dz = (z1 - z0) * s;
    const L = (l) => o.layers ? o.layers[l] ?? layer : layer;
    if (faces & 1) this.quad4([x1, y0, z1], [x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [1, 0, 0], [0, 0, dz, 0, dz, dy, 0, dy], L(0), ao);
    if (faces & 2) this.quad4([x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0], [-1, 0, 0], [0, 0, dz, 0, dz, dy, 0, dy], L(1), ao);
    if (faces & 4) this.quad4([x0, y1, z1], [x1, y1, z1], [x1, y1, z0], [x0, y1, z0], [0, 1, 0], [0, 0, dx, 0, dx, dz, 0, dz], L(2), ao);
    if (faces & 8) this.quad4([x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1], [0, -1, 0], [0, 0, dx, 0, dx, dz, 0, dz], L(3), ao);
    if (faces & 16) this.quad4([x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1], [0, 0, 1], [0, 0, dx, 0, dx, dy, 0, dy], L(4), ao);
    if (faces & 32) this.quad4([x1, y0, z0], [x0, y0, z0], [x0, y1, z0], [x1, y1, z0], [0, 0, -1], [0, 0, dx, 0, dx, dy, 0, dy], L(5), ao);
  }
  // cilindro/cone vertical (r0 base, r1 topo)
  cylinder(cx, y0, cz, r0, r1, h, seg, layer = 0, o = {}) {
    const first = this.vcount, s = o.uvScale ?? 1, bend0 = o.bend0 ?? 0, bend1 = o.bend1 ?? 0;
    const sl = Math.atan2(r0 - r1, h);
    for (let i = 0; i <= seg; i++) {
      const a = (i / seg) * Math.PI * 2, c = Math.cos(a), sn = Math.sin(a);
      const nx = c * Math.cos(sl), nz = sn * Math.cos(sl), ny = Math.sin(sl);
      const u = (i / seg) * Math.PI * 2 * Math.max(r0, 0.01) * s;
      this.vert(cx + c * r0, y0, cz + sn * r0, nx, ny, nz, u, 0, o.ao0 ?? 255, layer, 0, bend0);
      this.vert(cx + c * r1, y0 + h, cz + sn * r1, nx, ny, nz, u * (r1 / Math.max(r0, 0.01)), h * s, o.ao1 ?? 255, layer, 0, bend1);
    }
    for (let i = 0; i < seg; i++) { const a = first + i * 2; this.quad(a, a + 2, a + 3, a + 1); }
    if (o.cap) {
      const t = this.vert(cx, y0 + h, cz, 0, 1, 0, 0.5, 0.5, 255, layer, 0, bend1);
      for (let i = 0; i < seg; i++) { const a = first + i * 2 + 1; this.tri(a + 2, t, a); }
    }
  }
  build(gl) {
    const idx = this.p.length / 3 > 65535 ? new Uint32Array(this.i) : new Uint16Array(this.i);
    return new Mesh(gl, { positions: new Float32Array(this.p), normals: new Float32Array(this.n), uvs: new Float32Array(this.uv), colors: new Uint8Array(this.c), indices: idx });
  }
  // transforma e anexa outro builder (matriz 4x4)
  append(b, m) {
    const base = this.vcount;
    const n = b.p.length / 3;
    for (let i = 0; i < n; i++) {
      const x = b.p[i * 3], y = b.p[i * 3 + 1], z = b.p[i * 3 + 2];
      const nx = b.n[i * 3], ny = b.n[i * 3 + 1], nz = b.n[i * 3 + 2];
      this.p.push(m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13], m[2] * x + m[6] * y + m[10] * z + m[14]);
      this.n.push(m[0] * nx + m[4] * ny + m[8] * nz, m[1] * nx + m[5] * ny + m[9] * nz, m[2] * nx + m[6] * ny + m[10] * nz);
      this.uv.push(b.uv[i * 2], b.uv[i * 2 + 1]);
      this.c.push(b.c[i * 4], b.c[i * 4 + 1], b.c[i * 4 + 2], b.c[i * 4 + 3]);
    }
    for (const k of b.i) this.i.push(k + base);
  }
}
