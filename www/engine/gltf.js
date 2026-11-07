// Carregador GLB/glTF 2.0 (malhas, materiais PBR, skins, animações).
import { Mesh, texFromImage } from './gl.js';
import { Material } from './renderer.js';
import { m4, q4 } from './math.js';

const COMP = { 5120: Int8Array, 5121: Uint8Array, 5122: Int16Array, 5123: Uint16Array, 5125: Uint32Array, 5126: Float32Array };
const NCOMP = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT2: 4, MAT3: 9, MAT4: 16 };

export class GLTF {
  constructor(json, bin) { this.json = json; this.bin = bin; this.nodes = []; this.meshes = []; this.materials = []; this.skins = []; this.animations = []; this.roots = []; this._tex = new Map(); }

  accessor(i) {
    const a = this.json.accessors[i], bv = this.json.bufferViews[a.bufferView];
    const T = COMP[a.componentType], n = NCOMP[a.type];
    const off = (bv.byteOffset || 0) + (a.byteOffset || 0);
    const bytes = T.BYTES_PER_ELEMENT * n;
    const stride = bv.byteStride || bytes;
    const out = new T(a.count * n);
    if (stride === bytes) {
      const src = new Uint8Array(this.bin.buffer, this.bin.byteOffset + off, a.count * bytes);
      new Uint8Array(out.buffer).set(src);
    } else {
      for (let k = 0; k < a.count; k++) {
        const src = new T(this.bin.buffer.slice(this.bin.byteOffset + off + k * stride, this.bin.byteOffset + off + k * stride + bytes));
        out.set(src, k * n);
      }
    }
    out.accessor = a;
    return out;
  }
  floatAccessor(i) { // normaliza tipos inteiros -> float
    const d = this.accessor(i), a = d.accessor;
    if (d instanceof Float32Array) return d;
    const o = new Float32Array(d.length);
    const div = a.normalized ? (d instanceof Uint8Array ? 255 : d instanceof Uint16Array ? 65535 : d instanceof Int8Array ? 127 : 32767) : 1;
    for (let k = 0; k < d.length; k++) o[k] = d[k] / div;
    return o;
  }

  async texture(index, srgb, gl) {
    const key = index + (srgb ? 's' : 'l');
    if (this._tex.has(key)) return this._tex.get(key);
    const p = (async () => {
      const t = this.json.textures[index], im = this.json.images[t.source];
      const bv = this.json.bufferViews[im.bufferView];
      const blob = new Blob([new Uint8Array(this.bin.buffer, this.bin.byteOffset + (bv.byteOffset || 0), bv.byteLength)], { type: im.mimeType });
      const bmp = await createImageBitmap(blob, { premultiplyAlpha: 'none', colorSpaceConversion: 'none' });
      const tex = texFromImage(gl, bmp, { srgb, mips: true, aniso: 8 });
      bmp.close && bmp.close();
      return tex;
    })();
    this._tex.set(key, p);
    return p;
  }

  async build(gl, opts = {}) {
    const j = this.json;
    // materiais
    for (const m of j.materials || [{}]) {
      const pbr = m.pbrMetallicRoughness || {};
      const o = {
        color: pbr.baseColorFactor || [1, 1, 1, 1], rough: pbr.roughnessFactor ?? 1, metal: pbr.metallicFactor ?? 0,
        emissive: m.emissiveFactor || [0, 0, 0], doubleSided: !!m.doubleSided, name: m.name,
      };
      if (m.alphaMode === 'MASK') o.alphaTest = m.alphaCutoff ?? 0.5;
      if (m.alphaMode === 'BLEND') o.alphaTest = 0.35; // folhagem/grama: trata como recorte
      if (pbr.baseColorTexture) o.albedo = await this.texture(pbr.baseColorTexture.index, true, gl);
      if (pbr.metallicRoughnessTexture) o.orm = await this.texture(pbr.metallicRoughnessTexture.index, false, gl);
      if (m.normalTexture) { o.normal = await this.texture(m.normalTexture.index, false, gl); o.normalScale = m.normalTexture.scale ?? 1; }
      if (o.alphaTest > 0 && opts.foliage) { o.foliage = true; }
      if (opts.matOverride) Object.assign(o, opts.matOverride(m, o));
      this.materials.push(new Material(o));
    }
    if (!j.materials) this.materials.push(new Material({}));
    // malhas
    for (const m of j.meshes || []) {
      const prims = [];
      for (const p of m.primitives) {
        const at = p.attributes;
        const d = { positions: this.floatAccessor(at.POSITION), indices: null };
        if (at.NORMAL !== undefined) d.normals = this.floatAccessor(at.NORMAL);
        if (at.TEXCOORD_0 !== undefined) d.uvs = this.floatAccessor(at.TEXCOORD_0);
        if (at.JOINTS_0 !== undefined) {
          const jj = this.accessor(at.JOINTS_0);
          d.joints = jj instanceof Uint8Array || jj instanceof Uint16Array ? jj : new Uint16Array(jj);
          d.weights = this.floatAccessor(at.WEIGHTS_0);
        }
        d.indices = p.indices !== undefined ? this.accessor(p.indices) : Uint32Array.from({ length: d.positions.length / 3 }, (_, i) => i);
        if (d.indices instanceof Uint8Array) d.indices = new Uint16Array(d.indices);
        if (!d.normals) d.normals = new Float32Array(d.positions.length);
        if (opts.onPrimitive) opts.onPrimitive(d, this);
        const mesh = new Mesh(gl, d);
        mesh.name = m.name;
        prims.push({ mesh, material: this.materials[p.material ?? 0] });
      }
      this.meshes.push(prims);
    }
    // nós
    j.nodes.forEach((n, i) => {
      const node = { i, name: n.name || ('n' + i), children: n.children || [], mesh: n.mesh, skin: n.skin, parent: -1, t: n.translation || [0, 0, 0], r: n.rotation || [0, 0, 0, 1], s: n.scale || [1, 1, 1], world: m4.create(), local: m4.create() };
      if (n.matrix) { node.matrix = n.matrix; }
      this.nodes.push(node);
    });
    this.nodes.forEach((n) => n.children.forEach((c) => (this.nodes[c].parent = n.i)));
    this.roots = (j.scenes ? j.scenes[j.scene || 0].nodes : this.nodes.filter((n) => n.parent < 0).map((n) => n.i));
    this.updateWorld();
    // skins
    for (const s of j.skins || []) {
      const ibm = s.inverseBindMatrices !== undefined ? this.floatAccessor(s.inverseBindMatrices) : null;
      this.skins.push({ joints: s.joints, ibm, skeleton: s.skeleton });
    }
    // animações
    for (const a of j.animations || []) {
      const ch = a.channels.map((c) => {
        const s = a.samplers[c.sampler];
        return { node: c.target.node, path: c.target.path, interp: s.interpolation || 'LINEAR', times: this.floatAccessor(s.input), values: this.floatAccessor(s.output) };
      });
      const duration = Math.max(...ch.map((c) => c.times[c.times.length - 1]));
      this.animations.push({ name: a.name, channels: ch, duration });
    }
    return this;
  }

  setLocal(n) {
    if (n.matrix) { n.local.set(n.matrix); return; }
    m4.fromTRS(n.local, n.t, n.r, n.s);
  }
  updateWorld() {
    const rec = (i, parentW) => {
      const n = this.nodes[i];
      this.setLocal(n);
      if (parentW) m4.multiply(n.world, parentW, n.local); else n.world.set(n.local);
      n.children.forEach((c) => rec(c, n.world));
    };
    this.roots.forEach((r) => rec(r, null));
  }
  node(name) { return this.nodes.find((n) => n.name === name); }

  // lista de partes desenháveis [{mesh, material, matrix}], opcionalmente só a subárvore `rootName`
  // (nesse caso a translação do nó raiz é descartada: usa a origem local da variante)
  parts(rootName = null, { ignoreRootTransform = true } = {}) {
    const out = [];
    const walk = (i, parent) => {
      const n = this.nodes[i];
      this.setLocal(n);
      const w = m4.create();
      if (parent) m4.multiply(w, parent, n.local); else w.set(n.local);
      if (n.mesh !== undefined) for (const p of this.meshes[n.mesh]) out.push({ mesh: p.mesh, material: p.material, matrix: w, name: n.name });
      n.children.forEach((c) => walk(c, w));
    };
    if (rootName) {
      const r = typeof rootName === 'string' ? this.node(rootName) : this.nodes[rootName];
      if (!r) return out;
      const saved = { t: r.t, r: r.r, s: r.s, matrix: r.matrix };
      if (ignoreRootTransform) { r.t = [0, 0, 0]; r.r = [0, 0, 0, 1]; r.s = [1, 1, 1]; r.matrix = null; }
      walk(r.i, null);
      Object.assign(r, saved);
    } else this.roots.forEach((r) => walk(r, null));
    return out;
  }
}

// "assa" (bake) uma subárvore estática: aplica as matrizes dos nós nos vértices e funde por material.
// Retorna [{mesh, material}]. `xf` (mat4 opcional) é aplicada por último (escala/orientação/origem).
GLTF.prototype.bake = function (gl, rootName = null, xf = null, ignoreRoot = true, withBend = false) {
  const groups = new Map();
  const parts = Array.isArray(rootName) ? rootName.flatMap((n) => this.partsPrim(n, false)) : this.partsPrim(rootName, ignoreRoot);
  for (const pt of parts) {
    let g = groups.get(pt.material);
    if (!g) groups.set(pt.material, (g = { p: [], n: [], uv: [], i: [], base: 0 }));
    const m = xf ? m4.multiply(m4.create(), xf, pt.matrix) : pt.matrix;
    const at = pt.prim.attributes;
    const P = this.floatAccessor(at.POSITION), Nn = at.NORMAL !== undefined ? this.floatAccessor(at.NORMAL) : null, UV = at.TEXCOORD_0 !== undefined ? this.floatAccessor(at.TEXCOORD_0) : null;
    const I = pt.prim.indices !== undefined ? this.accessor(pt.prim.indices) : Uint32Array.from({ length: P.length / 3 }, (_, k) => k);
    const n = P.length / 3;
    for (let k = 0; k < n; k++) {
      const x = P[k * 3], y = P[k * 3 + 1], z = P[k * 3 + 2];
      g.p.push(m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13], m[2] * x + m[6] * y + m[10] * z + m[14]);
      if (Nn) { const a = Nn[k * 3], b = Nn[k * 3 + 1], c = Nn[k * 3 + 2]; const nx = m[0] * a + m[4] * b + m[8] * c, ny = m[1] * a + m[5] * b + m[9] * c, nz = m[2] * a + m[6] * b + m[10] * c; const l = Math.hypot(nx, ny, nz) || 1; g.n.push(nx / l, ny / l, nz / l); } else g.n.push(0, 1, 0);
      if (UV) g.uv.push(UV[k * 2], UV[k * 2 + 1]); else g.uv.push(0, 0);
    }
    // inversão de enrolamento se a matriz refletir
    const det = m[0] * (m[5] * m[10] - m[6] * m[9]) - m[4] * (m[1] * m[10] - m[2] * m[9]) + m[8] * (m[1] * m[6] - m[2] * m[5]);
    for (let k = 0; k < I.length; k += 3) { if (det < 0) g.i.push(I[k] + g.base, I[k + 2] + g.base, I[k + 1] + g.base); else g.i.push(I[k] + g.base, I[k + 1] + g.base, I[k + 2] + g.base); }
    g.base += n;
  }
  const out = [];
  for (const [material, g] of groups) {
    const idx = g.base > 65535 ? new Uint32Array(g.i) : new Uint16Array(g.i);
    let colors;
    if (withBend) {
      let mn = 1e9, mx = -1e9; for (let k = 1; k < g.p.length; k += 3) { mn = Math.min(mn, g.p[k]); mx = Math.max(mx, g.p[k]); }
      colors = new Uint8Array(g.base * 4);
      for (let k = 0; k < g.base; k++) { colors[k * 4] = 255; colors[k * 4 + 3] = Math.max(0, Math.min(1, (g.p[k * 3 + 1] - mn) / Math.max(mx - mn, 0.05))) * 255; }
    }
    out.push({ mesh: new Mesh(gl, { positions: new Float32Array(g.p), normals: new Float32Array(g.n), uvs: new Float32Array(g.uv), indices: idx, colors }), material });
  }
  return out;
};
GLTF.prototype.partsPrim = function (rootName, ignoreRoot) {
  const out = [];
  const walk = (i, parent) => {
    const n = this.nodes[i];
    this.setLocal(n);
    const w = m4.create();
    if (parent) m4.multiply(w, parent, n.local); else w.set(n.local);
    if (n.mesh !== undefined) this.json.meshes[n.mesh].primitives.forEach((prim, k) => out.push({ prim, material: this.materials[prim.material ?? 0], matrix: w, name: n.name }));
    n.children.forEach((c) => walk(c, w));
  };
  if (rootName) {
    const r = typeof rootName === 'string' ? this.node(rootName) : this.nodes[rootName];
    if (!r) return out;
    const saved = { t: r.t, r: r.r, s: r.s, matrix: r.matrix };
    if (ignoreRoot) { r.t = [0, 0, 0]; r.r = [0, 0, 0, 1]; r.s = [1, 1, 1]; r.matrix = null; }
    walk(r.i, null);
    Object.assign(r, saved);
  } else this.roots.forEach((r) => walk(r, null));
  return out;
};

export async function loadGLB(url, gl, opts = {}) {
  const res = await fetch(url);
  if (!res.ok) throw new Error('GLB não encontrado: ' + url);
  const buf = await res.arrayBuffer();
  const dv = new DataView(buf);
  if (dv.getUint32(0, true) !== 0x46546c67) throw new Error('GLB inválido: ' + url);
  let off = 12, json = null, bin = null;
  while (off < buf.byteLength) {
    const len = dv.getUint32(off, true), type = dv.getUint32(off + 4, true);
    const data = new Uint8Array(buf, off + 8, len);
    if (type === 0x4e4f534a) json = JSON.parse(new TextDecoder().decode(data));
    else if (type === 0x004e4942) bin = data;
    off += 8 + len;
  }
  const g = new GLTF(json, bin);
  await g.build(gl, opts);
  g.url = url;
  return g;
}
