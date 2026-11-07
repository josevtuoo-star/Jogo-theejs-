// Vegetação: árvores procedurais (4 LODs), cobertura de solo (modelos CC0), grama instanciada na GPU.
import { Mesh, MeshBuilder, InstanceBuffer, texFromImage } from '../engine/gl.js';
import { Material } from '../engine/renderer.js';
import { m4, mulberry32, hash2, clamp, lerp, smoothstep } from '../engine/math.js';
import { grassVS, GRASS_FS } from '../engine/shaders.js';
import { WORLD } from './worldgen.js';
import { MAT } from './assets.js';

const CELL = 64, G = Math.ceil(WORLD.size / CELL), SUPER = 256, GS = Math.ceil(WORLD.size / SUPER);
export const TREE = { SPRUCE: 0, PINE: 1, BROAD: 2 };

// ------------------------------------------------------------------ texturas procedurais
function canvasTex(gl, w, h, draw, srgb = true) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const g = c.getContext('2d'); draw(g, w, h);
  return texFromImage(gl, c, { srgb, mips: true, aniso: 4, wrap: gl.CLAMP_TO_EDGE });
}
function needleBranchTex(gl) {
  return canvasTex(gl, 256, 128, (g, W, H) => {
    const rnd = mulberry32(7);
    g.clearRect(0, 0, W, H);
    const cy = H / 2;
    g.lineCap = 'round';
    // base densa (silhueta)
    const grad = g.createLinearGradient(0, 0, W, 0);
    grad.addColorStop(0, 'rgba(24,52,22,0.95)'); grad.addColorStop(1, 'rgba(34,70,28,0.95)');
    g.fillStyle = grad;
    g.beginPath();
    g.moveTo(4, cy);
    for (let i = 0; i <= 20; i++) { const t = i / 20; g.lineTo(4 + t * (W - 12), cy - Math.sin(Math.PI * Math.pow(t, 0.75)) * H * 0.34 * (1 - 0.15 * t)); }
    for (let i = 20; i >= 0; i--) { const t = i / 20; g.lineTo(4 + t * (W - 12), cy + Math.sin(Math.PI * Math.pow(t, 0.75)) * H * 0.34 * (1 - 0.15 * t)); }
    g.fill();
    // galho central
    g.strokeStyle = 'rgb(70,48,30)'; g.lineWidth = 2.2;
    g.beginPath(); g.moveTo(2, cy); g.lineTo(W - 6, cy); g.stroke();
    // agulhas
    for (let i = 0; i < 520; i++) {
      const t = Math.pow(rnd(), 0.9), x = 6 + t * (W - 20);
      const side = rnd() < 0.5 ? -1 : 1;
      const len = (0.55 + 0.45 * Math.sin(Math.PI * Math.pow(t, 0.7))) * H * 0.4 * (0.6 + 0.6 * rnd());
      const ang = (0.55 + rnd() * 0.75) * side * (rnd() < 0.5 ? 1 : 0.7);
      const shade = 0.55 + 0.7 * rnd();
      g.strokeStyle = `rgb(${(22 + 38 * shade) | 0},${(54 + 78 * shade) | 0},${(20 + 28 * shade) | 0})`;
      g.lineWidth = 1.3 + rnd() * 0.9;
      g.beginPath(); g.moveTo(x, cy); g.lineTo(x + Math.sin(ang) * len * 0.5 + len * 0.45, cy + Math.cos(ang) * len * side * 0.9 * 0 + Math.sin(ang) * len); g.stroke();
    }
  });
}
function leafClusterTex(gl) {
  return canvasTex(gl, 256, 256, (g, W, H) => {
    const rnd = mulberry32(21);
    g.clearRect(0, 0, W, H);
    // massa base
    const rg = g.createRadialGradient(W / 2, H / 2, 4, W / 2, H / 2, W * 0.46);
    rg.addColorStop(0, 'rgba(60,92,30,1)'); rg.addColorStop(0.75, 'rgba(60,92,30,0.95)'); rg.addColorStop(1, 'rgba(60,92,30,0)');
    g.fillStyle = rg; g.fillRect(0, 0, W, H);
    for (let i = 0; i < 360; i++) {
      const a = rnd() * Math.PI * 2, r = Math.sqrt(rnd()) * W * 0.46;
      const x = W / 2 + Math.cos(a) * r, y = H / 2 + Math.sin(a) * r * 0.92;
      const s = 7 + rnd() * 9, sh = 0.5 + 0.9 * rnd();
      g.fillStyle = `rgb(${(46 + 66 * sh) | 0},${(70 + 92 * sh) | 0},${(18 + 34 * sh) | 0})`;
      g.save(); g.translate(x, y); g.rotate(rnd() * Math.PI);
      g.beginPath(); g.ellipse(0, 0, s, s * 0.52, 0, 0, Math.PI * 2); g.fill(); g.restore();
    }
    // recorte irregular nas bordas
    g.globalCompositeOperation = 'destination-out';
    for (let i = 0; i < 70; i++) { const a = rnd() * Math.PI * 2, r = W * (0.4 + rnd() * 0.14); g.beginPath(); g.arc(W / 2 + Math.cos(a) * r, H / 2 + Math.sin(a) * r, 5 + rnd() * 12, 0, 7); g.fill(); }
    g.globalCompositeOperation = 'source-over';
  });
}

// ------------------------------------------------------------------ geradores de árvore
const rotY = (x, z, a) => [x * Math.cos(a) + z * Math.sin(a), -x * Math.sin(a) + z * Math.cos(a)];

function addFrond(b, base, dir, len, width, droop, roll, ao, bendY, segs, normalUp, layer = 0) {
  // dir: unit horizontal-ish vector [x,y,z] ; faixa com largura variando (sin) e queda quadrática
  const up = [0, 1, 0];
  // eixo lateral = perp horizontal rotacionado por roll
  let side = [-dir[2], 0, dir[0]]; const sl = Math.hypot(side[0], side[2]) || 1; side = [side[0] / sl, 0, side[2] / sl];
  const sUp = [Math.sin(roll), Math.cos(roll), 0];
  const lat = [side[0] * Math.cos(roll), Math.sin(roll), side[2] * Math.cos(roll)];
  const first = b.vcount;
  for (let i = 0; i <= segs; i++) {
    const u = i / segs;
    const w = width * Math.sin(Math.PI * Math.pow(u, 0.7)) * 0.5 + 0.02;
    const cx = base[0] + dir[0] * len * u, cy = base[1] + dir[1] * len * u - droop * len * u * u, cz = base[2] + dir[2] * len * u;
    const bend = clamp(bendY * 0.75 + u * 0.25, 0, 1);
    const a = clamp(ao * (0.6 + 0.4 * u), 0, 1) * 255;
    const n = [normalUp[0] * 0.5, 0.7, normalUp[2] * 0.5];
    b.vert(cx - lat[0] * w, cy - lat[1] * w, cz - lat[2] * w, n[0], n[1], n[2], u, 0, a, layer, 0, bend * 255);
    b.vert(cx + lat[0] * w, cy + lat[1] * w, cz + lat[2] * w, n[0], n[1], n[2], u, 1, a, layer, 0, bend * 255);
  }
  for (let i = 0; i < segs; i++) { const k = first + i * 2; b.quad(k, k + 1, k + 3, k + 2); }
}

function buildConifer(gl, o, lod) {
  const rnd = mulberry32(o.seed);
  const trunk = new MeshBuilder(), fol = new MeshBuilder();
  const H = o.H;
  // tronco (bend cresce com a altura)
  const seg = lod === 0 ? 8 : 5;
  const rings = lod === 0 ? 5 : 2;
  for (let k = 0; k < rings; k++) {
    const y0 = k / rings * H, y1 = (k + 1) / rings * H;
    const r0 = lerp(o.r0, 0.04, Math.pow(k / rings, 0.8)), r1 = lerp(o.r0, 0.04, Math.pow((k + 1) / rings, 0.8));
    trunk.cylinder(0, y0, 0, r0, r1, y1 - y0, seg, MAT.bark, { uvScale: 0.5, bend0: (y0 / H) * 255, bend1: (y1 / H) * 255 });
  }
  const nW = lod === 0 ? o.whorls : lod === 1 ? Math.round(o.whorls * 0.55) : 6;
  const segs = lod === 0 ? 4 : 2;
  const tipY = H * 0.985;
  for (let w = 0; w < nW; w++) {
    const t = (w + rnd() * 0.5) / nW;
    const y = lerp(H * o.start, tipY, t);
    const k = Math.max(2, Math.round(lerp(o.perWhorl, 2, Math.pow(t, 1.2)) * (lod === 0 ? 1 : 0.8)));
    const Lmax = lerp(o.Lmax, 0.35, Math.pow(t, o.taper)) * (lod === 0 ? 1 : 1.25);
    const a0 = rnd() * Math.PI * 2;
    for (let i = 0; i < k; i++) {
      const a = a0 + (i / k) * Math.PI * 2 + (rnd() - 0.5) * 0.5;
      const pitch = lerp(-0.1, 0.25, rnd()) - lerp(0.0, 0.3, 1 - t) * 0.5;
      const dir = [Math.cos(a) * Math.cos(pitch), Math.sin(pitch), Math.sin(a) * Math.cos(pitch)];
      const len = Lmax * (0.8 + 0.4 * rnd());
      const width = len * (lod === 0 ? 0.66 : 0.8);
      const ao = lerp(0.55, 1, t) * (0.9 + 0.1 * rnd());
      addFrond(fol, [dir[0] * 0.06, y + (rnd() - 0.5) * 0.4, dir[2] * 0.06], dir, len, width, lerp(0.35, 0.18, t) * (0.8 + 0.4 * rnd()), (rnd() - 0.5) * 0.9, ao, y / H, segs, [dir[0], 0, dir[2]]);
    }
  }
  return { trunk: trunk.build(gl), fol: fol.build(gl) };
}

// LOD 2: dois cones empilhados; LOD 3: duas silhuetas cruzadas
function buildConiferFar(gl, o, lod) {
  const b = new MeshBuilder(), H = o.H;
  if (lod === 2) {
    const tiers = o.start > 0.3 ? [[0.5, 0.92, 2.1], [0.78, 1.0, 1.5]] : [[0.1, 0.58, 3.0], [0.4, 0.82, 2.2], [0.68, 1.0, 1.3]];
    for (const [a, c, r] of tiers) {
      const y0 = H * a, y1 = H * c, R = r * o.Lmax / 3.4 * 1.15;
      const seg = 5, first = b.vcount;
      for (let i = 0; i <= seg; i++) {
        const an = i / seg * Math.PI * 2, cs = Math.cos(an), sn = Math.sin(an);
        const nl = Math.hypot(1, R / (y1 - y0));
        b.vert(cs * R, y0, sn * R, cs / nl, 0.55, sn / nl, i / seg, 0, 150, 0, 0, 120);
        b.vert(0, y1, 0, cs * 0.3, 0.95, sn * 0.3, i / seg, 1, 255, 0, 0, 255);
      }
      for (let i = 0; i < seg; i++) { const k = first + i * 2; b.tri(k, k + 1, k + 2); }
    }
    b.cylinder(0, 0, 0, o.r0, o.r0 * 0.5, H * 0.5, 4, MAT.bark, { uvScale: 0.4 });
  } else {
    const R = o.Lmax * 0.62, y0 = H * (o.start > 0.3 ? 0.4 : 0.08);
    for (const a of [0, Math.PI / 2]) {
      const c = Math.cos(a), s = Math.sin(a);
      const f = b.vcount;
      b.vert(-c * R, y0, -s * R, 0, 0.6, 0, 0, 0, 160, 0, 0, 100);
      b.vert(c * R, y0, s * R, 0, 0.6, 0, 1, 0, 160, 0, 0, 100);
      b.vert(0, H, 0, 0, 1, 0, 0.5, 1, 255, 0, 0, 255);
      b.tri(f, f + 1, f + 2); b.tri(f, f + 2, f + 1);
    }
  }
  return b.build(gl);
}

function buildBroad(gl, o, lod) {
  const rnd = mulberry32(o.seed);
  const trunk = new MeshBuilder(), fol = new MeshBuilder();
  const H = o.H, crownY = H * 0.62, cR = o.crown, cH = o.crownH;
  // tronco + 3 galhos principais
  trunk.cylinder(0, 0, 0, o.r0, o.r0 * 0.55, crownY, lod === 0 ? 8 : 5, MAT.bark, { uvScale: 0.5, bend0: 0, bend1: 120 });
  if (lod === 0) {
    for (let i = 0; i < 3; i++) {
      const a = i / 3 * Math.PI * 2 + rnd();
      const bx = Math.cos(a) * cR * 0.45, bz = Math.sin(a) * cR * 0.45;
      // galho como caixa fina inclinada (aprox. por cilindro de 4 lados com topo deslocado)
      const f = trunk.vcount;
      const r0 = 0.09, r1 = 0.04, y0 = crownY * 0.8, y1 = crownY + cH * 0.45;
      for (let k = 0; k <= 4; k++) {
        const an = k / 4 * Math.PI * 2, cs = Math.cos(an), sn = Math.sin(an);
        trunk.vert(cs * r0, y0, sn * r0, cs, 0, sn, k / 4, 0, 255, MAT.bark, 0, 140);
        trunk.vert(bx + cs * r1, y1, bz + sn * r1, cs, 0, sn, k / 4, 3, 255, MAT.bark, 0, 255);
      }
      for (let k = 0; k < 4; k++) { const q = f + k * 2; trunk.quad(q, q + 2, q + 3, q + 1); }
    }
  }
  const nC = lod === 0 ? 17 : lod === 1 ? 8 : 4;
  const sz = lod === 0 ? 1.0 : 1.55;
  const cc = [0, crownY + cH * 0.45, 0];
  for (let i = 0; i < nC; i++) {
    const a = rnd() * Math.PI * 2, e = Math.acos(1 - 2 * rnd()), r = (0.25 + 0.75 * Math.cbrt(rnd()));
    const px = Math.sin(e) * Math.cos(a) * cR * r, py = Math.cos(e) * cH * 0.55 * r, pz = Math.sin(e) * Math.sin(a) * cR * r;
    const cx = px, cy = cc[1] + py, cz = pz;
    const S = (1.7 + rnd() * 1.1) * sz * (cR / 2.8);
    const ao = lerp(0.55, 1, clamp((py / (cH * 0.55) + 1) / 2, 0, 1));
    const bend = 0.55 + 0.45 * clamp(cy / H, 0, 1);
    const nrm = [px / (cR + 0.1), py / (cH * 0.55 + 0.1) + 0.2, pz / (cR + 0.1)];
    const nl = Math.hypot(...nrm) || 1;
    // 3 quads (plano horizontal inclinado + 2 verticais)
    const planes = [[0, 0], [Math.PI / 3, 1.1], [-Math.PI / 3, 0.9]];
    const base = rnd() * Math.PI;
    for (const [pa, tilt] of planes.slice(0, lod === 2 ? 2 : 3)) {
      const ang = base + pa;
      const ux = Math.cos(ang), uz = Math.sin(ang);
      const vx = -Math.sin(tilt) * uz * 0.5, vy = Math.cos(tilt * 0.6), vz = Math.sin(tilt) * ux * 0.5;
      const vl = Math.hypot(vx, vy, vz);
      const f = fol.vcount;
      const corner = (su, sv, u, v) => fol.vert(cx + (ux * su * S + vx / vl * sv * S) * 0.5, cy + (vy / vl * sv * S) * 0.5, cz + (uz * su * S + vz / vl * sv * S) * 0.5, nrm[0] / nl, nrm[1] / nl, nrm[2] / nl, u, v, ao * 255, 0, 0, bend * 255);
      corner(-1, -1, 0, 1); corner(1, -1, 1, 1); corner(1, 1, 1, 0); corner(-1, 1, 0, 0);
      fol.quad(f, f + 1, f + 2, f + 3);
    }
  }
  return { trunk: trunk.build(gl), fol: fol.build(gl) };
}

function buildBlob(gl, o) {
  const b = new MeshBuilder(), cR = o.crown, cH = o.crownH, y = o.H * 0.62 + cH * 0.45;
  // octaedro-esfera de 8 faces + subdivisão leve
  const pts = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];
  const faces = [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [4, 3, 0], [1, 3, 4], [5, 3, 1], [0, 3, 5]];
  for (const f of faces) {
    const i0 = b.vcount;
    for (const k of f) { const p = pts[k]; b.vert(p[0] * cR * 1.1, y + p[1] * cH * 0.6, p[2] * cR * 1.1, p[0], p[1] * 0.8 + 0.2, p[2], 0.5, 0.5, p[1] < 0 ? 140 : 255, 0, 0, 200); }
    b.tri(i0, i0 + 1, i0 + 2);
  }
  b.cylinder(0, 0, 0, o.r0, o.r0 * 0.6, o.H * 0.64, 4, MAT.bark, { uvScale: 0.4 });
  return b.build(gl);
}

const TREE_DEFS = [
  { name: 'spruce', seed: 11, H: 17, r0: 0.34, start: 0.1, whorls: 20, perWhorl: 5, Lmax: 3.3, taper: 0.85 },
  { name: 'pine', seed: 23, H: 23, r0: 0.3, start: 0.48, whorls: 13, perWhorl: 5, Lmax: 2.9, taper: 0.7 },
  { name: 'broad', seed: 5, H: 11, r0: 0.28, crown: 3.4, crownH: 4.6 },
];

// ------------------------------------------------------------------ classe principal
export class Vegetation {
  constructor(renderer, world, assets, opts = {}) {
    const gl = this.gl = renderer.gl;
    this.r = renderer; this.world = world; this.assets = assets;
    this.density = opts.density ?? 1;
    this.grassQuality = opts.grass ?? 2; // 0 off, 1 baixa, 2 média, 3 alta
    this.opts = opts;
    this.needleTex = needleBranchTex(gl);
    this.leafTex = leafClusterTex(gl);
    this.barkMat = new Material({ layered: true, rough: 0.95, wind: 0.0, name: 'bark', normalScale: 0.8 });
    this.barkMatWind = new Material({ layered: true, rough: 0.95, wind: 0.5, name: 'barkw', normalScale: 0.8 });
    this.coniferMat = new Material({ albedo: this.needleTex, alphaTest: 0.42, doubleSided: true, rough: 0.85, foliage: true, wind: 1.0, instTint: 1, vcolorAO: true, name: 'needles' });
    this.broadMat = new Material({ albedo: this.leafTex, alphaTest: 0.4, doubleSided: true, rough: 0.8, foliage: true, wind: 1.2, instTint: 2, vcolorAO: true, name: 'leaves' });
    this.solidConifer = new Material({ color: [0.65, 0.8, 0.62, 1], rough: 0.95, foliage: false, wind: 0.5, doubleSided: true, instTint: 1, name: 'farconifer' });
    this.solidBroad = new Material({ color: [0.8, 0.85, 0.5, 1], rough: 0.95, wind: 0.5, doubleSided: true, instTint: 2, name: 'farbroad' });
    this.solidFar = new Material({ color: [0.62, 0.78, 0.6, 1], rough: 0.95, doubleSided: true, instTint: 3, name: 'farmix' });
    this.types = TREE_DEFS.map((d, i) => {
      const lods = [];
      if (i < 2) {
        for (let l = 0; l < 2; l++) { const m = buildConifer(gl, d, l); lods.push({ trunk: m.trunk, fol: m.fol }); }
        lods.push({ solid: buildConiferFar(gl, d, 2) });
        lods.push({ solid: buildConiferFar(gl, d, 3) });
      } else {
        for (let l = 0; l < 2; l++) { const m = buildBroad(gl, d, l); lods.push({ trunk: m.trunk, fol: m.fol }); }
        lods.push({ solid: buildBlob(gl, d) });
        lods.push({ solid: buildConiferFar(gl, { ...TREE_DEFS[0], H: 11, Lmax: 3.4 }, 3) });
      }
      return { def: d, lods };
    });
    this._place();
    this._buildGrassMesh();
    this.grassProg = renderer.prog('grass', grassVS(), GRASS_FS);
    this._prepCover();
    this.stats = { trees: 0, cover: 0 };
  }

  // ---------------------------------------------------------- colocação
  _place() {
    const w = this.world, rnd = mulberry32(99);
    const cells = this.cells = Array.from({ length: G * G }, () => ({ t: [[], [], []], cover: {} }));
    const sup = this.superCells = Array.from({ length: GS * GS }, () => []);
    this.trunks = []; // para colisão: x, z, r, ymax
    const step = 7.5 / Math.sqrt(this.density);
    const N = Math.floor(WORLD.size / step);
    let count = 0;
    for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
      const x = (i + hash2(i, j, 1)) * step, z = (j + hash2(i, j, 2)) * step;
      const h = w.heightAt(x, z);
      const F = w.forestAt(x, z, h);
      let p = F * 0.82;
      // árvores isoladas em campo aberto
      if (F < 0.35) p = Math.max(p, 0.045 * smoothstep(WORLD.waterY + 1.5, WORLD.waterY + 4, h));
      if (hash2(i, j, 3) > p) continue;
      const n = w.normalAt(x, z);
      if (n[1] < 0.8) continue;
      if (this.opts.exclude && this.opts.exclude(x, z, 3.0)) continue;
      // tipo: altitude + ruído -> conífera / folhosa
      const bn = w.noise2.fbm(x / 260 + 7, z / 260, 2) + (h - 40) / 140;
      let type;
      const r3 = hash2(i, j, 4);
      if (bn > 0.12) type = r3 < 0.7 ? TREE.SPRUCE : TREE.PINE;
      else if (bn > -0.12) type = r3 < 0.35 ? TREE.SPRUCE : r3 < 0.6 ? TREE.PINE : TREE.BROAD;
      else type = r3 < 0.18 ? TREE.SPRUCE : TREE.BROAD;
      if (F < 0.35 && type !== TREE.BROAD && hash2(i, j, 5) < 0.5) type = TREE.BROAD;
      const sc = 0.78 + 0.5 * hash2(i, j, 6) * hash2(i, j, 7) + 0.18 * hash2(i, j, 8);
      const rot = hash2(i, j, 9) * Math.PI * 2, rr = hash2(i, j, 10);
      const cx = Math.min(G - 1, Math.floor(x / CELL)), cz = Math.min(G - 1, Math.floor(z / CELL));
      const rec = [x, h - 0.15, z, sc, rot, rr, 0, 0];
      cells[cz * G + cx].t[type].push(...rec);
      sup[Math.min(GS - 1, Math.floor(z / SUPER)) * GS + Math.min(GS - 1, Math.floor(x / SUPER))].push(x, h - 0.15, z, sc * (type === TREE.BROAD ? 0.9 : 1), rot, rr, type === TREE.BROAD ? 1 : 0, type);
      this.trunks.push({ x, z, r: TREE_DEFS[type].r0 * sc * 0.85 + 0.08, y0: h, y1: h + TREE_DEFS[type].H * sc });
      count++;
    }
    this.treeCount = count;
    // cobertura de solo
    const R = mulberry32(555);
    const perCell = Math.round(46 * this.density);
    for (let cz = 0; cz < G; cz++) for (let cx = 0; cx < G; cx++) {
      const c = cells[cz * G + cx];
      const add = (k, rec) => { (c.cover[k] || (c.cover[k] = [])).push(...rec); };
      for (let a = 0; a < perCell; a++) {
        const x = (cx + R()) * CELL, z = (cz + R()) * CELL;
        if (x > WORLD.size || z > WORLD.size) continue;
        const h = w.heightAt(x, z);
        const F = w.forestAt(x, z, h);
        const n = w.normalAt(x, z);
        if (h < WORLD.waterY + 0.7) continue;
        if (this.opts.exclude && this.opts.exclude(x, z, 1.5)) continue;
        const slope = 1 - n[1];
        const rot = R() * Math.PI * 2, r = R();
        if (slope > 0.2 && R() < 0.5) { // rochas em encostas
          const k = r < 0.4 ? 'rock07' : r < 0.7 ? 'rock09' : r < 0.9 ? 'stone01' : 'boulder';
          add(k, [x, h - 0.1, z, 0.8 + R() * 1.3, rot, R(), 0, 0]); continue;
        }
        if (slope > 0.34) continue;
        if (F > 0.45) {
          if (r < 0.55) add('fern', [x, h, z, 0.8 + R() * 0.7, rot, R(), 0, 0]);
          else if (r < 0.7) add('shrub', [x, h, z, 0.8 + R() * 0.5, rot, R(), 0, 0]);
          else if (r < 0.78) add('stump', [x, h, z, 0.8 + R() * 0.5, rot, R(), 0, 0]);
          else if (r < 0.83) add('deadTrunk', [x, h, z, 0.7 + R() * 0.5, rot, R(), 0, 0]);
          else if (r < 0.91) add('rock07', [x, h - 0.05, z, 0.35 + R() * 0.6, rot, R(), 0, 0]);
          else add('stone01', [x, h - 0.05, z, 0.35 + R() * 0.5, rot, R(), 0, 0]);
        } else if (F > 0.05) {
          if (r < 0.2) add('fern', [x, h, z, 0.7 + R() * 0.5, rot, R(), 0, 0]);
          else if (r < 0.34) add('shrub', [x, h, z, 0.7 + R() * 0.7, rot, R(), 0, 0]);
          else if (r < 0.4) add('nettle', [x, h, z, 0.8 + R() * 0.5, rot, R(), 0, 0]);
          else if (r < 0.45) add('rock09', [x, h - 0.05, z, 0.3 + R() * 0.7, rot, R(), 0, 0]);
        }
      }
    }
  }

  _prepCover() {
    const A = this.assets, gl = this.gl;
    const defs = {
      fern: ['fern_02', 'fern_02_a', 1.0, 55, 0.3], shrub: ['shrub_02', 'shrub_02_a', 1.0, 60, 0.4], nettle: ['nettle_plant', null, 1.0, 45, 0.3],
      stump: ['tree_stump_01', null, 1.0, 130, 0.0], deadTrunk: ['dead_tree_trunk', null, 1.0, 150, 0.0],
      rock07: ['rock_07', null, 1.0, 260, 0.0], rock09: ['rock_09', null, 1.0, 260, 0.0], stone01: ['stone_01', null, 1.0, 180, 0.0], boulder: ['boulder_01', null, 1.2, 420, 0.0],
    };
    this.cover = {};
    for (const [k, [model, root, sc, maxD, wind]] of Object.entries(defs)) {
      const m = A.models[model];
      if (!m) continue;
      const parts = m.bake(gl, root || null, null, true, wind > 0);
      for (const p of parts) { if (wind > 0 && p.material.wind !== wind) { p.material.wind = wind * 0.5; p.material.refreshKey(); } }
      // normalização: modelos PH estão em metros reais
      this.cover[k] = { parts, maxD, scale: sc };
    }
  }

  // ---------------------------------------------------------- grama
  _buildGrassMesh() {
    const b = new MeshBuilder(), rnd = mulberry32(3);
    const blades = 8;
    for (let i = 0; i < blades; i++) {
      const a = rnd() * Math.PI * 2, rr = Math.sqrt(rnd()) * 0.28;
      const bx = Math.cos(a) * rr, bz = Math.sin(a) * rr;
      const lean = 0.18 + rnd() * 0.3, h = 0.34 + rnd() * 0.32, wdt = 0.032 + rnd() * 0.02;
      const dirA = a + (rnd() - 0.5) * 1.4, dx = Math.cos(dirA), dz = Math.sin(dirA);
      const sx = -dz, sz = dx;
      const f = b.vcount;
      const nx = sx, nz = sz;
      b.vert(bx - sx * wdt, 0, bz - sz * wdt, dx, 0.3, dz, 0, 0, 255, 0, 0, 0);
      b.vert(bx + sx * wdt, 0, bz + sz * wdt, dx, 0.3, dz, 1, 0, 255, 0, 0, 0);
      b.vert(bx + sx * wdt * 0.7 + dx * lean * 0.55, h * 0.58, bz + sz * wdt * 0.7 + dz * lean * 0.55, dx, 0.6, dz, 1, 0.55, 255, 0, 0, 120);
      b.vert(bx - sx * wdt * 0.7 + dx * lean * 0.55, h * 0.58, bz - sz * wdt * 0.7 + dz * lean * 0.55, dx, 0.6, dz, 0, 0.55, 255, 0, 0, 120);
      b.vert(bx + dx * lean, h, bz + dz * lean, dx, 0.9, dz, 0.5, 1, 255, 0, 0, 255);
      b.quad(f, f + 1, f + 2, f + 3); b.tri(f + 3, f + 2, f + 4);
    }
    this.grassMesh = b.build(this.gl);
  }

  setGrassQuality(q) { this.grassQuality = q; }

  // ---------------------------------------------------------- desenho
  _treeBuf(arr, mode = 2) { return arr._buf || (arr._buf = new InstanceBuffer(this.gl, new Float32Array(arr), mode)); }

  draw(r, cam, shadowPass) {
    const f = r.frustum, cx0 = cam[0], cz0 = cam[2];
    let ntree = 0, ncover = 0;
    const shadowMax = shadowPass ? (r.cascadeIndex === 0 ? 70 : r.cascadeIndex === 1 ? 190 : 330) : 1e9;
    const gl = this.gl;
    // árvores: células finas (LOD 0-2) + super células (LOD 3)
    const ds = this.distScale || 1;
    const L0 = 62 * ds, L1 = 230 * ds, L2 = 520 * ds, L3 = 1250 * ds;
    const wantSuper = !shadowPass;
    for (let cz = 0; cz < G; cz++) for (let cx = 0; cx < G; cx++) {
      const x0 = cx * CELL, z0 = cz * CELL;
      const dx = Math.max(x0 - cx0, 0, cx0 - (x0 + CELL)), dz = Math.max(z0 - cz0, 0, cz0 - (z0 + CELL));
      const d = Math.hypot(dx, dz);
      if (d > L2 || d > shadowMax) continue;
      const c = this.cells[cz * G + cx];
      const hy = this.world.heightAt(x0 + 32, z0 + 32);
      if (!f.aabb(x0 - 4, hy - 60, z0 - 4, x0 + CELL + 4, hy + 60, z0 + CELL + 4)) continue;
      const lod = d < L0 ? 0 : d < L1 ? 1 : 2;
      for (let t = 0; t < 3; t++) {
        const arr = c.t[t]; if (!arr.length) continue;
        const buf = this._treeBuf(arr);
        const tl = this.types[t].lods[lod];
        if (tl.solid) r.draw(tl.solid, t === TREE.BROAD ? this.solidBroad : this.solidConifer, { inst: buf });
        else {
          r.draw(tl.trunk, this.barkMatWind, { inst: buf });
          r.draw(tl.fol, t === TREE.BROAD ? this.broadMat : this.coniferMat, { inst: buf });
        }
        ntree += arr.length / 8;
      }
      // cobertura de solo
      for (const k in c.cover) {
        const cv = this.cover[k]; if (!cv || d > cv.maxD * ds || d > shadowMax) continue;
        const arr = c.cover[k], buf = this._treeBuf(arr);
        for (const p of cv.parts) r.draw(p.mesh, p.material, { inst: buf });
        ncover += arr.length / 8;
      }
    }
    // cobertura em células mais longe (apenas rochas grandes) e super células de árvores
    if (wantSuper) {
      for (let sz = 0; sz < GS; sz++) for (let sx = 0; sx < GS; sx++) {
        const x0 = sx * SUPER, z0 = sz * SUPER;
        const dx = Math.max(x0 - cx0, 0, cx0 - (x0 + SUPER)), dz = Math.max(z0 - cz0, 0, cz0 - (z0 + SUPER));
        const d = Math.hypot(dx, dz);
        if (d > L3 || d + SUPER * 0.7 < L2) continue;
        const arr = this.superCells[sz * GS + sx]; if (!arr.length) continue;
        if (!f.aabb(x0, -20, z0, x0 + SUPER, 220, z0 + SUPER)) continue;
        // desenha por tipo (par conífera / folhosa) -> mesma malha: instTint pelo atributo
        const buf = this._treeBuf(arr);
        // super células cobrem toda a área; as células finas já desenham < L2, então só desenha onde d >= L2-SUPER*0.7 e recorta por clip no shader (uClip) — simplificado: desenha tudo e confia no depth.
        r.draw(this.types[0].lods[3].solid, this.solidFar, { inst: buf, instNear: L2 - 20 });
      }
    }
    this.stats.trees = ntree; this.stats.cover = ncover;
  }

  drawGrass(r, cam) {
    if (!this.grassQuality) return;
    const q = [0, { R: 22, cell: 0.8 }, { R: 32, cell: 0.62 }, { R: 42, cell: 0.5 }][this.grassQuality];
    const gl = this.gl, p = r.use(this.grassProg);
    const N = Math.round(q.R * 2 / q.cell);
    const sx = Math.round(cam[0] / q.cell) * q.cell, sz = Math.round(cam[2] / q.cell) * q.cell;
    r.tex(7, this.terrain.heightTex); r.tex(9, this.terrain.splat0);
    p.f2('uHInfo', WORLD.hn, WORLD.spacing);
    p.f4('uTerrInfo', WORLD.size, 1 / WORLD.size, 0, 0);
    p.f4('uGrass', sx, sz, q.R, q.cell);
    p.f1('uGridN', N);
    p.f3('uTint', 0.11, 0.2, 0.04);
    r._cull(false); r._blend(false); r._depthWrite(true);
    gl.bindVertexArray(this.grassMesh.vao);
    gl.drawElementsInstanced(gl.TRIANGLES, this.grassMesh.indexCount, this.grassMesh.indexType, 0, N * N);
    gl.stats.draws++; gl.stats.tris += this.grassMesh.tris * N * N * 0.5;
  }
}
