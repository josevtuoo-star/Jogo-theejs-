// Animação esquelética: amostragem de clipes, blend, FK com ganchos em espaço de mundo e IK de 2 ossos.
import { m4, q4, v3, clamp } from './math.js';

export class Skeleton {
  constructor(gltf, skinIndex = 0) {
    this.g = gltf;
    const skin = gltf.skins[skinIndex];
    this.skin = skin;
    this.joints = skin.joints;
    this.nJ = this.joints.length;
    this.ibm = skin.ibm;
    const N = gltf.nodes.length;
    this.N = N;
    // pose local por nó
    this.T = new Float32Array(N * 3); this.R = new Float32Array(N * 4); this.S = new Float32Array(N * 3);
    gltf.nodes.forEach((n, i) => {
      this.T.set(n.t, i * 3); this.R.set(n.r, i * 4); this.S.set(n.s, i * 3);
    });
    this.restT = this.T.slice(); this.restR = this.R.slice(); this.restS = this.S.slice();
    // ordem topológica
    this.order = [];
    const visit = (i) => { this.order.push(i); gltf.nodes[i].children.forEach(visit); };
    gltf.roots.forEach(visit);
    this.parent = gltf.nodes.map((n) => n.parent);
    this.world = new Float32Array(N * 16);
    this.jointIndex = new Map(); this.joints.forEach((n, j) => this.jointIndex.set(n, j));
    this.byName = new Map(); gltf.nodes.forEach((n) => this.byName.set(n.name.replace('mixamorig:', ''), n.i));
    this.out = new Float32Array(this.nJ * 16);
    this.hooks = new Map(); // nó -> {delta?:quat, abs?:quat}
    this.hide = new Set();  // nós com escala zero (ex.: cabeça em 1ª pessoa)
    this._tmp = m4.create();
    this.clips = {};
    gltf.animations.forEach((a) => {
      const ch = a.channels.map((c) => ({ ...c }));
      this.clips[a.name] = { name: a.name, duration: a.duration, channels: ch };
    });
    this.root = m4.create();
  }
  node(name) { return this.byName.get(name); }
  resetPose() { this.T.set(this.restT); this.R.set(this.restR); this.S.set(this.restS); }

  // amostra um clipe em t (loop), misturando no pose atual com peso w (w=1 substitui)
  sample(clip, time, w = 1, loop = true) {
    const c = typeof clip === 'string' ? this.clips[clip] : clip;
    if (!c) return;
    let t = time;
    if (loop) t = ((t % c.duration) + c.duration) % c.duration; else t = clamp(t, 0, c.duration);
    for (const ch of c.channels) {
      const times = ch.times, n = times.length;
      let i = 0, lo = 0, hi = n - 1;
      if (t <= times[0]) i = 0; else if (t >= times[n - 1]) i = n - 1;
      else { while (hi - lo > 1) { const m = (lo + hi) >> 1; if (times[m] <= t) lo = m; else hi = m; } i = lo; }
      const i1 = Math.min(i + 1, n - 1);
      const f = i1 === i ? 0 : (t - times[i]) / (times[i1] - times[i]);
      const nd = ch.node;
      if (ch.path === 'rotation') {
        const v = ch.values, a = [v[i * 4], v[i * 4 + 1], v[i * 4 + 2], v[i * 4 + 3]], b = [v[i1 * 4], v[i1 * 4 + 1], v[i1 * 4 + 2], v[i1 * 4 + 3]];
        const q = q4.slerp(new Float32Array(4), a, b, f);
        if (w >= 1) { this.R.set(q, nd * 4); } else {
          const cur = [this.R[nd * 4], this.R[nd * 4 + 1], this.R[nd * 4 + 2], this.R[nd * 4 + 3]];
          this.R.set(q4.slerp(new Float32Array(4), cur, q, w), nd * 4);
        }
      } else {
        const arr = ch.path === 'translation' ? this.T : this.S, v = ch.values;
        for (let k = 0; k < 3; k++) {
          const val = v[i * 3 + k] + (v[i1 * 3 + k] - v[i * 3 + k]) * f;
          arr[nd * 3 + k] = w >= 1 ? val : arr[nd * 3 + k] + (val - arr[nd * 3 + k]) * w;
        }
      }
    }
  }

  setHook(nodeIdx, h) { const o = this.hooks.get(nodeIdx); this.hooks.set(nodeIdx, o && o.offset && !h.offset ? { ...h, offset: o.offset } : h); }
  setOffset(nodeIdx, off) { const o = this.hooks.get(nodeIdx) || {}; this.hooks.set(nodeIdx, { ...o, offset: off }); }
  clearHooks() { this.hooks.clear(); }

  // FK completo. rootM = matriz do mundo do personagem (opcional, para posições em mundo use depois).
  fk() {
    const W = this.world, T = this.T, R = this.R, S = this.S, tmp = this._tmp;
    for (const i of this.order) {
      m4.fromTRS(tmp, [T[i * 3], T[i * 3 + 1], T[i * 3 + 2]], [R[i * 4], R[i * 4 + 1], R[i * 4 + 2], R[i * 4 + 3]], [S[i * 3], S[i * 3 + 1], S[i * 3 + 2]]);
      if (this.hide.has(i)) { tmp[0] = tmp[1] = tmp[2] = tmp[4] = tmp[5] = tmp[6] = tmp[8] = tmp[9] = tmp[10] = 0; }
      const p = this.parent[i];
      const out = W.subarray(i * 16, i * 16 + 16);
      if (p >= 0) m4.multiply(out, W.subarray(p * 16, p * 16 + 16), tmp); else out.set(tmp);
      const h = this.hooks.get(i);
      if (h && (h.delta || h.abs)) {
        const x = out[12], y = out[13], z = out[14];
        // extrai escala e rotação atuais
        if (h.delta) {
          const q = h.delta, rm = m4.fromTRS(m4.create(), [0, 0, 0], q, null);
          const o = out.slice();
          // R3' = Rd * R3
          for (let c = 0; c < 3; c++) {
            const a = o[c * 4], b = o[c * 4 + 1], d = o[c * 4 + 2];
            out[c * 4] = rm[0] * a + rm[4] * b + rm[8] * d; out[c * 4 + 1] = rm[1] * a + rm[5] * b + rm[9] * d; out[c * 4 + 2] = rm[2] * a + rm[6] * b + rm[10] * d;
          }
        } else if (h.abs) {
          const sx = Math.hypot(out[0], out[1], out[2]), sy = Math.hypot(out[4], out[5], out[6]), sz = Math.hypot(out[8], out[9], out[10]);
          const rm = m4.fromTRS(m4.create(), [0, 0, 0], h.abs, null);
          out[0] = rm[0] * sx; out[1] = rm[1] * sx; out[2] = rm[2] * sx;
          out[4] = rm[4] * sy; out[5] = rm[5] * sy; out[6] = rm[6] * sy;
          out[8] = rm[8] * sz; out[9] = rm[9] * sz; out[10] = rm[10] * sz;
        }
        out[12] = x; out[13] = y; out[14] = z;
      }
      if (h && h.offset) { out[12] += h.offset[0]; out[13] += h.offset[1]; out[14] += h.offset[2]; }
    }
  }
  pos(nodeIdx, o = [0, 0, 0]) { const w = this.world, k = nodeIdx * 16; o[0] = w[k + 12]; o[1] = w[k + 13]; o[2] = w[k + 14]; return o; }
  worldQuat(nodeIdx) {
    const w = this.world, k = nodeIdx * 16, m = m4.create();
    const sx = Math.hypot(w[k], w[k + 1], w[k + 2]) || 1, sy = Math.hypot(w[k + 4], w[k + 5], w[k + 6]) || 1, sz = Math.hypot(w[k + 8], w[k + 9], w[k + 10]) || 1;
    m[0] = w[k] / sx; m[1] = w[k + 1] / sx; m[2] = w[k + 2] / sx; m[4] = w[k + 4] / sy; m[5] = w[k + 5] / sy; m[6] = w[k + 6] / sy; m[8] = w[k + 8] / sz; m[9] = w[k + 9] / sz; m[10] = w[k + 10] / sz;
    return m4.toQuat(new Float32Array(4), m);
  }

  // IK de dois ossos. Retorna {dUpper, dLower} (deltas em espaço de mundo do esqueleto) e aplica ganchos.
  // target no espaço do esqueleto; pole: direção (espaço do esqueleto) para onde o joelho/cotovelo aponta.
  solveTwoBone(upper, mid, end, target, pole, opts = {}) {
    const a = this.pos(upper), b = this.pos(mid), c = this.pos(end);
    const l1 = v3.dist(a, b), l2 = v3.dist(b, c);
    const to = [target[0] - a[0], target[1] - a[1], target[2] - a[2]];
    let d = Math.hypot(...to);
    const maxReach = (l1 + l2) * 0.9995, minReach = Math.abs(l1 - l2) * 1.001 + 0.001;
    const dc = clamp(d, minReach, maxReach);
    const dir = [to[0] / (d || 1), to[1] / (d || 1), to[2] / (d || 1)];
    // posição desejada do cotovelo/joelho: lei dos cossenos
    const cosA = clamp((l1 * l1 + dc * dc - l2 * l2) / (2 * l1 * dc), -1, 1);
    const sinA = Math.sqrt(1 - cosA * cosA);
    // direção perpendicular conforme pole
    let pl = [pole[0] - dir[0] * (pole[0] * dir[0] + pole[1] * dir[1] + pole[2] * dir[2]), pole[1] - dir[1] * (pole[0] * dir[0] + pole[1] * dir[1] + pole[2] * dir[2]), pole[2] - dir[2] * (pole[0] * dir[0] + pole[1] * dir[1] + pole[2] * dir[2])];
    const pn = Math.hypot(...pl) || 1; pl = [pl[0] / pn, pl[1] / pn, pl[2] / pn];
    const kn = [a[0] + dir[0] * cosA * l1 + pl[0] * sinA * l1, a[1] + dir[1] * cosA * l1 + pl[1] * sinA * l1, a[2] + dir[2] * cosA * l1 + pl[2] * sinA * l1];
    const norm = (v) => { const l = Math.hypot(...v) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };
    const cur1 = norm([b[0] - a[0], b[1] - a[1], b[2] - a[2]]), des1 = norm([kn[0] - a[0], kn[1] - a[1], kn[2] - a[2]]);
    const dq1 = q4.fromTo(new Float32Array(4), cur1, des1);
    // posição do fim após o primeiro giro
    const c1 = q4.rotate([0, 0, 0], dq1, [c[0] - a[0], c[1] - a[1], c[2] - a[2]]);
    const cNew = [a[0] + c1[0], a[1] + c1[1], a[2] + c1[2]];
    const cur2 = norm([cNew[0] - kn[0], cNew[1] - kn[1], cNew[2] - kn[2]]);
    const tgt = [a[0] + dir[0] * dc, a[1] + dir[1] * dc, a[2] + dir[2] * dc];
    const des2 = norm([tgt[0] - kn[0], tgt[1] - kn[1], tgt[2] - kn[2]]);
    const dq2 = q4.fromTo(new Float32Array(4), cur2, des2);
    const w = opts.weight ?? 1;
    if (w < 1) { q4.slerp(dq1, q4.create(), dq1, w); q4.slerp(dq2, q4.create(), dq2, w); }
    this.setHook(upper, { delta: dq1 });
    this.setHook(mid, { delta: q4.mul(new Float32Array(4), dq2, dq1) });
    // o delta do nó médio deve incluir o giro do pai (pois o gancho substitui R3 resultante de FK já com pai girado)
    // -> como o FK já propagou dq1 ao nó médio via matriz do pai, aplicamos só dq2 sobre ele:
    this.setHook(mid, { delta: dq2 });
    return { dq1, dq2 };
  }
  // fixa rotação absoluta (mundo/esqueleto) de um nó final (mão/pé)
  setAbs(node, q) { this.setHook(node, { abs: q }); }
  addDelta(node, q) { const h = this.hooks.get(node); if (h && h.delta) this.setHook(node, { delta: q4.mul(new Float32Array(4), q, h.delta) }); else this.setHook(node, { delta: q }); }
  // posições de um conjunto de juntas para um skin secundário (ex.: viseira) com as mesmas matrizes de mundo
  jointsFor(skin, out) {
    const tmp = this._tmp;
    for (let j = 0; j < skin.joints.length; j++) { m4.multiply(tmp, this.world.subarray(skin.joints[j] * 16, skin.joints[j] * 16 + 16), skin.ibm.subarray(j * 16, j * 16 + 16)); out.set(tmp, j * 16); }
    return out;
  }

  // gera matrizes de junta (espaço do esqueleto) a partir do FK atual
  computeJoints() {
    const W = this.world, out = this.out, tmp = this._tmp;
    for (let j = 0; j < this.nJ; j++) {
      const n = this.joints[j];
      m4.multiply(tmp, W.subarray(n * 16, n * 16 + 16), this.ibm.subarray(j * 16, j * 16 + 16));
      out.set(tmp, j * 16);
    }
    return out;
  }
}
