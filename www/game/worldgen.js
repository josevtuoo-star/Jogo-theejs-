// Geração procedural determinística do mapa de 2 x 2 km.
import { Noise2D, clamp, lerp, smoothstep, hash2, mulberry32 } from '../engine/math.js';

export const WORLD = { size: 2000, hn: 1001, spacing: 2, waterY: 6.0, splatN: 1024 };

const tick = () => new Promise((r) => setTimeout(r, 0));

// Catmull-Rom 2D -> pontos a cada `step` metros
function spline(ctrl, step = 4) {
  const pts = [];
  const P = (i) => ctrl[clamp(i, 0, ctrl.length - 1)];
  for (let i = 0; i < ctrl.length - 1; i++) {
    const p0 = P(i - 1), p1 = P(i), p2 = P(i + 1), p3 = P(i + 2);
    const len = Math.hypot(p2[0] - p1[0], p2[1] - p1[1]);
    const n = Math.max(2, Math.ceil(len / step));
    for (let k = 0; k < n; k++) {
      const t = k / n, t2 = t * t, t3 = t2 * t;
      const f = (a, b, c, d) => 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
      pts.push([f(p0[0], p1[0], p2[0], p3[0]), f(p0[1], p1[1], p2[1], p3[1])]);
    }
  }
  pts.push([...ctrl[ctrl.length - 1]]);
  return pts;
}

// grade espacial de pontos de polilinha para distância mais próxima
class PolyIndex {
  constructor(polys, cell = 24) {
    this.cell = cell; this.map = new Map(); this.polys = polys;
    polys.forEach((poly, pi) => {
      for (let i = 0; i < poly.pts.length - 1; i++) {
        const a = poly.pts[i], b = poly.pts[i + 1];
        const x0 = Math.floor((Math.min(a[0], b[0]) - 40) / cell), x1 = Math.floor((Math.max(a[0], b[0]) + 40) / cell);
        const z0 = Math.floor((Math.min(a[1], b[1]) - 40) / cell), z1 = Math.floor((Math.max(a[1], b[1]) + 40) / cell);
        for (let x = x0; x <= x1; x++) for (let z = z0; z <= z1; z++) {
          const k = x * 4096 + z; let l = this.map.get(k); if (!l) this.map.set(k, (l = []));
          l.push(pi, i);
        }
      }
    });
  }
  // devolve {d, s(índice interpolado), poly}
  nearest(x, z, maxD = 60) {
    const c = this.cell, cx = Math.floor(x / c), cz = Math.floor(z / c);
    let best = null;
    const r = Math.ceil(maxD / c);
    for (let dx = -r; dx <= r; dx++) for (let dz = -r; dz <= r; dz++) {
      const l = this.map.get((cx + dx) * 4096 + (cz + dz)); if (!l) continue;
      for (let q = 0; q < l.length; q += 2) {
        const poly = this.polys[l[q]], i = l[q + 1], a = poly.pts[i], b = poly.pts[i + 1];
        const abx = b[0] - a[0], abz = b[1] - a[1];
        let t = ((x - a[0]) * abx + (z - a[1]) * abz) / (abx * abx + abz * abz + 1e-9); t = clamp(t, 0, 1);
        const d = Math.hypot(x - (a[0] + abx * t), z - (a[1] + abz * t));
        if (!best || d < best.d) { if (!best) best = {}; best.d = d; best.s = i + t; best.poly = poly; best.i = i; best.t = t; }
      }
    }
    return best;
  }
}

export class WorldData {
  constructor(seed) {
    this.seed = seed;
    this.noise = new Noise2D(seed);
    this.noise2 = new Noise2D(seed * 7 + 3);
    this.hn = WORLD.hn;
    this.heights = new Float32Array(this.hn * this.hn);
    this.roads = []; this.river = null; this.towns = []; this.lake = null;
    this.bridges = []; this.fields = []; this.landmarks = [];
  }
  // ---- consultas de altura (bilinear/triangular, igual ao mesh do terreno)
  heightAt(x, z) {
    const g = WORLD.spacing, hn = this.hn;
    let fx = x / g, fz = z / g;
    fx = clamp(fx, 0, hn - 1.001); fz = clamp(fz, 0, hn - 1.001);
    const ix = Math.floor(fx), iz = Math.floor(fz), tx = fx - ix, tz = fz - iz;
    const H = this.heights, i = iz * hn + ix;
    const a = H[i], b = H[i + 1], c = H[i + hn], d = H[i + hn + 1];
    // diagonal a-d (igual ao índice do mesh de terreno)
    if (tx > tz) return a + (b - a) * tx + (d - b) * tz;
    return a + (c - a) * tz + (d - c) * tx;
  }
  normalAt(x, z, out = [0, 1, 0]) {
    const e = 1.2;
    const hx = this.heightAt(x + e, z) - this.heightAt(x - e, z), hz = this.heightAt(x, z + e) - this.heightAt(x, z - e);
    const l = Math.hypot(hx, 2 * e, hz);
    out[0] = -hx / l; out[1] = 2 * e / l; out[2] = -hz / l; return out;
  }
  isWater(x, z) {
    const h = this.heightAt(x, z);
    if (h < WORLD.waterY - 0.05) return true;
    return false;
  }
  // máscara contínua de floresta [0,1]
  forestAt(x, z, h) {
    if (h === undefined) h = this.heightAt(x, z);
    const n = this.noise.fbm(x / 340 + 40, z / 340 + 11, 3);
    let f = smoothstep(-0.16, 0.2, n + 0.02);
    f *= smoothstep(104, 84, h);
    f *= smoothstep(WORLD.waterY + 0.6, WORLD.waterY + 2.5, h);
    for (const t of this.towns) { const d = Math.hypot(x - t.x, z - t.z); f *= lerp(0.12, 1, smoothstep(t.r * 0.8, t.r * 1.9, d)); }
    for (const fl of this.fields) { const d = Math.hypot(x - fl.x, z - fl.z); f *= smoothstep(fl.r * 0.9, fl.r * 1.15, d); }
    if (this.roadIdx) { const r = this.roadIdx.nearest(x, z, 14); if (r) f *= smoothstep(r.poly.width * 0.5 + 2, r.poly.width * 0.5 + 8, r.d); }
    return f;
  }
}

export async function generateWorld(seed = 1337, onProgress = () => {}) {
  const W = new WorldData(seed);
  const N = W.noise, N2 = W.noise2, hn = W.hn, S = WORLD.size, g = WORLD.spacing;

  // ---------- definições fixas: vilas, lago, rio, estradas
  W.lake = { x: 430, z: 1560, rx: 250, rz: 300 };
  W.towns = [
    { name: 'Vila Nova', x: 1010, z: 1000, r: 120, kind: 'town' },
    { name: 'Porto do Lago', x: 640, z: 1190, r: 80, kind: 'village' },
    { name: 'Serra Alta', x: 1480, z: 560, r: 85, kind: 'village' },
    { name: 'Campo Seco', x: 1580, z: 1560, r: 90, kind: 'farm' },
    { name: 'Posto Norte', x: 520, z: 420, r: 60, kind: 'outpost' },
  ];
  W.fields = [{ x: 1620, z: 1700, r: 150 }, { x: 1380, z: 1520, r: 60 }];
  // rio (do planalto NE para o lago)
  const riverCtrl = [[1560, 150], [1420, 330], [1330, 520], [1250, 700], [1070, 800], [880, 930], [790, 1060], [720, 1220], [640, 1330], [560, 1420]];
  const riverPts = spline(riverCtrl, 6);
  W.river = { pts: riverPts, width: 11, half: 5.5 };
  let acc = 0; const rl = [0];
  for (let i = 1; i < riverPts.length; i++) { acc += Math.hypot(riverPts[i][0] - riverPts[i - 1][0], riverPts[i][1] - riverPts[i - 1][1]); rl.push(acc); }
  riverPts.forEach((p, i) => { const s = rl[i] / acc; p[2] = lerp(34, WORLD.waterY + 0.35, Math.pow(s, 0.85)); });
  const riverIdx = new PolyIndex([{ pts: riverPts, kind: 'river' }], 24);
  W.riverIdx = riverIdx;
  const riverLevel = (r) => { const a = riverPts[r.i], b = riverPts[r.i + 1]; return a[2] + (b[2] - a[2]) * r.t; };

  // estradas principais (asfalto) e trilhas de terra
  const roadDefs = [
    { name: 'Estrada Principal', width: 7, type: 'asphalt', ctrl: [[1010, 1000], [880, 1060], [760, 1130], [640, 1190]] },
    { name: 'Rodovia Leste', width: 7, type: 'asphalt', ctrl: [[1010, 1000], [1150, 920], [1280, 760], [1400, 640], [1480, 560]] },
    { name: 'Rodovia Sul', width: 7, type: 'asphalt', ctrl: [[1010, 1000], [1060, 1180], [1200, 1340], [1400, 1480], [1580, 1560]] },
    { name: 'Rodovia Norte', width: 7, type: 'asphalt', ctrl: [[1010, 1000], [930, 860], [800, 700], [660, 540], [520, 420]] },
    { name: 'Estrada do Lago', width: 5, type: 'dirt', ctrl: [[640, 1190], [600, 1320], [640, 1440], [700, 1560]] },
    { name: 'Trilha Fazenda', width: 4, type: 'dirt', ctrl: [[1580, 1560], [1620, 1700], [1700, 1830]] },
    { name: 'Trilha Serra', width: 4, type: 'dirt', ctrl: [[1480, 560], [1620, 420], [1740, 330]] },
    { name: 'Trilha Leste', width: 4, type: 'dirt', ctrl: [[1580, 1560], [1700, 1380], [1760, 1180]] },
  ];
  for (const rd of roadDefs) { rd.pts = spline(rd.ctrl, 4); W.roads.push(rd); }

  // ---------- altura base
  const mdx = 1750, mdz = 300;
  const baseH = (x, z) => {
    let h = 30 + 18 * N.fbm(x / 720, z / 720, 3) + 12 * N.fbm(x / 240 + 5, z / 240, 4) + 2.4 * N.fbm(x / 48, z / 48, 3);
    const m = smoothstep(1, 0.15, Math.hypot(x - mdx, z - mdz) / 720);
    h += m * (28 + 70 * Math.pow(N2.ridged(x / 430 + 2, z / 430, 5), 1.6));
    const m2 = smoothstep(1, 0.2, Math.hypot(x - 200, z - 250) / 380);
    h += m2 * 22 * (0.5 + N2.fbm(x / 120, z / 120, 3));
    const e = Math.min(x, z, S - x, S - z);
    h += smoothstep(170, 0, e) * 70;
    return h;
  };
  const lk = W.lake;
  const H = W.heights;
  for (let j = 0; j < hn; j++) {
    const z = j * g;
    for (let i = 0; i < hn; i++) {
      const x = i * g;
      let h = baseH(x, z);
      // lago
      const d = Math.hypot((x - lk.x) / lk.rx, (z - lk.z) / lk.rz);
      const bowl = smoothstep(1.25, 0.45, d);
      h = lerp(h, WORLD.waterY - 3.2 + 2 * N.fbm(x / 60, z / 60, 2), bowl);
      H[j * hn + i] = h;
    }
    if (j % 40 === 0) { onProgress('Relevo', j / hn * 0.45); await tick(); }
  }

  // ---------- planícies das vilas
  for (const t of W.towns) {
    let sum = 0, c = 0;
    for (let k = 0; k < 16; k++) { const a = k / 16 * Math.PI * 2; sum += baseHeightAt(W, t.x + Math.cos(a) * t.r * 0.6, t.z + Math.sin(a) * t.r * 0.6); c++; }
    t.h = Math.max(sum / c, WORLD.waterY + 3.5);
    const R0 = t.r * 0.95, R1 = t.r * 1.9;
    const i0 = Math.floor((t.x - R1) / g), i1 = Math.ceil((t.x + R1) / g), j0 = Math.floor((t.z - R1) / g), j1 = Math.ceil((t.z + R1) / g);
    for (let j = Math.max(0, j0); j <= Math.min(hn - 1, j1); j++) for (let i = Math.max(0, i0); i <= Math.min(hn - 1, i1); i++) {
      const d = Math.hypot(i * g - t.x, j * g - t.z);
      const w = 1 - smoothstep(R0, R1, d);
      if (w > 0) { const k = j * hn + i; const gentle = t.h + 1.2 * N.fbm(i * g / 70, j * g / 70, 2); H[k] = lerp(H[k], gentle, w); }
    }
  }
  function baseHeightAt(Wd, x, z) { const i = clamp(Math.round(x / g), 0, hn - 1), j = clamp(Math.round(z / g), 0, hn - 1); return Wd.heights[j * hn + i]; }

  // ---------- rio: planície + canal
  onProgress('Rio', 0.5); await tick();
  for (let j = 0; j < hn; j++) {
    for (let i = 0; i < hn; i++) {
      const x = i * g, z = j * g;
      const r = riverIdx.nearest(x, z, 70);
      if (!r) continue;
      const lvl = riverLevel(r);
      const k = j * hn + i;
      const flood = 1 - smoothstep(16, 68, r.d);
      let h = lerp(H[k], lvl + 1.0 + 0.5 * N.fbm(x / 40, z / 40, 2), flood);
      const chan = 1 - smoothstep(3.0, 8.5, r.d);
      h = lerp(h, lvl - 1.3, chan);
      H[k] = h;
    }
    if (j % 80 === 0) await tick();
  }

  // ---------- estradas: alturas suavizadas ao longo da linha + terraplenagem
  onProgress('Estradas', 0.6); await tick();
  const bridges = [];
  for (const rd of W.roads) {
    const pts = rd.pts;
    const hs = pts.map((p) => W.heightAt(p[0], p[1]));
    // marca pontos sobre o rio (ponte)
    const onRiver = pts.map((p) => { const r = riverIdx.nearest(p[0], p[1], 20); return r ? r.d < 11 : false; });
    // suaviza altura
    let cur = hs.slice();
    for (let pass = 0; pass < 6; pass++) {
      const nx = cur.slice();
      for (let i = 0; i < cur.length; i++) {
        let s = 0, c = 0;
        for (let k = -8; k <= 8; k++) { const q = cur[clamp(i + k, 0, cur.length - 1)]; s += q; c++; }
        nx[i] = s / c;
      }
      cur = nx;
    }
    // trechos de ponte: interpola linear entre as margens
    let i = 0;
    while (i < pts.length) {
      if (onRiver[i]) {
        let a = i; while (a > 0 && onRiver[a]) a--; a = Math.max(0, a - 5);
        let b = i; while (b < pts.length - 1 && onRiver[b]) b++; b = Math.min(pts.length - 1, b + 5);
        const ha = cur[a], hb = cur[b];
        const lvl = Math.max(ha, hb);
        for (let k = a; k <= b; k++) cur[k] = lerp(ha, hb, (k - a) / (b - a || 1));
        bridges.push({ road: rd, a, b, h0: cur[a], h1: cur[b], p0: pts[a], p1: pts[b] });
        for (let k = a; k <= b; k++) onRiver[k] = true;
        i = b + 1;
      } else i++;
    }
    pts.forEach((p, k) => { p[2] = cur[k]; p[3] = onRiver[k] ? 1 : 0; });
    rd.hasBridge = onRiver.some(Boolean);
  }
  W.bridges = bridges;
  W.roadIdx = new PolyIndex(W.roads, 24);
  // aplica terraplenagem
  for (let j = 0; j < hn; j++) {
    for (let i = 0; i < hn; i++) {
      const x = i * g, z = j * g;
      const r = W.roadIdx.nearest(x, z, 26);
      if (!r) continue;
      const pts = r.poly.pts, a = pts[r.i], b = pts[r.i + 1];
      if (a[3] && b[3]) continue; // ponte: não mexe no terreno
      const rh = a[2] + (b[2] - a[2]) * r.t;
      const hw = r.poly.width * 0.5;
      const w = 1 - smoothstep(hw + 0.8, hw + 11, r.d);
      const k = j * hn + i;
      H[k] = lerp(H[k], rh - 0.06, w);
    }
    if (j % 60 === 0) await tick();
  }

  // ---------- normais + splat
  onProgress('Materiais', 0.72); await tick();
  const normals = new Uint8Array(hn * hn * 4);
  for (let j = 0; j < hn; j++) {
    for (let i = 0; i < hn; i++) {
      const hl = H[j * hn + Math.max(i - 1, 0)], hr = H[j * hn + Math.min(i + 1, hn - 1)];
      const hd = H[Math.max(j - 1, 0) * hn + i], hu = H[Math.min(j + 1, hn - 1) * hn + i];
      const nx = (hl - hr), nz = (hd - hu), ny = 2 * g;
      const l = Math.hypot(nx, ny, nz);
      const o = (j * hn + i) * 4;
      normals[o] = (nx / l * 0.5 + 0.5) * 255; normals[o + 1] = (nz / l * 0.5 + 0.5) * 255; normals[o + 2] = (ny / l) * 255; normals[o + 3] = 255;
    }
  }
  W.normalMap = normals;
  const SN = WORLD.splatN;
  const sp0 = new Uint8Array(SN * SN * 4), sp1 = new Uint8Array(SN * SN * 4);
  const cell = S / SN;
  for (let j = 0; j < SN; j++) {
    const z = (j + 0.5) * cell;
    for (let i = 0; i < SN; i++) {
      const x = (i + 0.5) * cell;
      const h = W.heightAt(x, z);
      const nrm = W.normalAt(x, z);
      const sl = Math.sqrt(Math.max(0, 1 - nrm[1] * nrm[1]));
      let rock = smoothstep(0.40, 0.66, sl) + smoothstep(98, 128, h) * 0.8;
      let sand = 0, wet = 0;
      const dLake = Math.hypot((x - lk.x) / lk.rx, (z - lk.z) / lk.rz);
      if (h < WORLD.waterY + 1.8) sand = smoothstep(WORLD.waterY + 1.8, WORLD.waterY + 0.1, h);
      if (h < WORLD.waterY + 3) wet = smoothstep(WORLD.waterY + 3, WORLD.waterY, h);
      const rr = riverIdx.nearest(x, z, 22);
      if (rr) { sand = Math.max(sand, (1 - smoothstep(4, 11, rr.d)) * 0.85); }
      const F = W.forestAt(x, z, h);
      let forest = F * (1 - rock), grass = (1 - F) * (1 - rock);
      let dirt = smoothstep(0.32, 0.55, N.fbm(x / 38 + 90, z / 38, 3)) * 0.65 * (1 - F * 0.6);
      for (const fl of W.fields) { const d = Math.hypot(x - fl.x, z - fl.z); if (d < fl.r) { const stripes = 0.5 + 0.5 * Math.sin((x * 0.7 + z * 0.35) * 0.35 + N.noise(x / 50, z / 50) * 3); dirt = Math.max(dirt, smoothstep(fl.r, fl.r * 0.85, d) * (0.55 + 0.4 * stripes)); grass *= 1 - dirt * 0.7; } }
      let gravel = 0, asphalt = 0;
      for (const t of W.towns) {
        const d = Math.hypot(x - t.x, z - t.z);
        if (d < t.r * 1.15) { const yard = 1 - smoothstep(t.r * 0.5, t.r * 1.15, d); dirt = Math.max(dirt, yard * 0.3 * (0.5 + N.fbm(x / 9, z / 9, 2))); }
      }
      const rn = W.roadIdx.nearest(x, z, 14);
      if (rn) {
        const hw = rn.poly.width * 0.5;
        if (rn.poly.type === 'asphalt') { asphalt = 1 - smoothstep(hw - 0.3, hw + 0.8, rn.d); gravel = Math.max(gravel, (1 - smoothstep(hw + 0.3, hw + 2.8, rn.d)) * 0.9); }
        else gravel = Math.max(gravel, 1 - smoothstep(hw * 0.55, hw * 1.15, rn.d));
      }
      const o = (j * SN + i) * 4;
      let wts = [grass, forest, dirt, rock, sand, gravel, asphalt];
      // prioridade: asfalto/cascalho/areia dominam
      const dom = Math.max(asphalt, gravel * 0.98, sand * 0.9);
      const base = 1 - dom;
      wts[0] *= base; wts[1] *= base; wts[2] *= base * (1 - sand); wts[3] *= base * (1 - sand);
      wts[4] = sand * (1 - Math.max(asphalt, gravel));
      wts[5] = gravel * (1 - asphalt); wts[6] = asphalt;
      let tot = wts.reduce((a, b) => a + b, 0) || 1;
      sp0[o] = wts[0] / tot * 255; sp0[o + 1] = wts[1] / tot * 255; sp0[o + 2] = wts[2] / tot * 255; sp0[o + 3] = wts[3] / tot * 255;
      sp1[o] = wts[4] / tot * 255; sp1[o + 1] = wts[5] / tot * 255; sp1[o + 2] = wts[6] / tot * 255; sp1[o + 3] = wet * 255;
    }
    if (j % 32 === 0) { onProgress('Materiais', 0.72 + j / SN * 0.26); await tick(); }
  }
  W.splat0 = sp0; W.splat1 = sp1;
  W.spawn = { x: 1075, z: 1150 };
  onProgress('Pronto', 1);
  return W;
}
