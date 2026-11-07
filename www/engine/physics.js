// Física própria: colisores estáticos (OBB/cilindro), heightfield, character controller (cápsula),
// corpos rígidos (caixa/esfera) com atrito e restituição, raycast e balística com arrasto e vento.
import { v3, q4, m4, clamp, lerp } from './math.js';

export const G = 9.81;
const CELL = 16;
export const SURF = { DIRT: 0, GRASS: 1, WOOD: 2, METAL: 3, STONE: 4, WATER: 5, ASPHALT: 6, FLESH: 7, SAND: 8 };

export class Physics {
  constructor(world) {
    this.world = world;
    this.cols = [];
    this.grid = new Map();
    this.bodies = [];
    this.wind = [0, 0];
    this.waterY = 6.0;
    this.events = [];
    this.projectiles = [];
    this.hooks = [];
    this.onProjectileHit = null;
    this._acc = 0;
  }

  // ------------------------------------------------------------ colisores estáticos
  _index(c) {
    const x0 = Math.floor(c.minx / CELL), x1 = Math.floor(c.maxx / CELL), z0 = Math.floor(c.minz / CELL), z1 = Math.floor(c.maxz / CELL);
    for (let x = x0; x <= x1; x++) for (let z = z0; z <= z1; z++) { const k = x * 4096 + z; let l = this.grid.get(k); if (!l) this.grid.set(k, (l = [])); l.push(c); }
  }
  // OBB girada em yaw. surf: material. flags: { walk: pode andar em cima, ghost: só bala, noBullet }
  addBox(cx, cy, cz, hx, hy, hz, yaw = 0, surf = SURF.WOOD, flags = {}) {
    const c = { kind: 0, cx, cz, hx, hz, y0: cy - hy, y1: cy + hy, cos: Math.cos(yaw), sin: Math.sin(yaw), surf, yaw, ...flags };
    const ex = Math.abs(c.cos) * hx + Math.abs(c.sin) * hz, ez = Math.abs(c.sin) * hx + Math.abs(c.cos) * hz;
    c.minx = cx - ex; c.maxx = cx + ex; c.minz = cz - ez; c.maxz = cz + ez;
    c.id = this.cols.length; this.cols.push(c); this._index(c);
    return c;
  }
  addCyl(x, z, r, y0, y1, surf = SURF.WOOD, flags = {}) {
    const c = { kind: 1, cx: x, cz: z, r, y0, y1, minx: x - r, maxx: x + r, minz: z - r, maxz: z + r, surf, ...flags };
    c.id = this.cols.length; this.cols.push(c); this._index(c);
    return c;
  }
  removeCol(c) {
    c.dead = true;
    const x0 = Math.floor(c.minx / CELL), x1 = Math.floor(c.maxx / CELL), z0 = Math.floor(c.minz / CELL), z1 = Math.floor(c.maxz / CELL);
    for (let x = x0; x <= x1; x++) for (let z = z0; z <= z1; z++) { const l = this.grid.get(x * 4096 + z); if (l) { const i = l.indexOf(c); if (i >= 0) l.splice(i, 1); } }
  }
  near(x, z, r, out = []) {
    out.length = 0;
    const x0 = Math.floor((x - r) / CELL), x1 = Math.floor((x + r) / CELL), z0 = Math.floor((z - r) / CELL), z1 = Math.floor((z + r) / CELL);
    this._stamp = (this._stamp || 0) + 1;
    for (let i = x0; i <= x1; i++) for (let j = z0; j <= z1; j++) {
      const l = this.grid.get(i * 4096 + j); if (!l) continue;
      for (const c of l) if (c._s !== this._stamp) { c._s = this._stamp; out.push(c); }
    }
    return out;
  }

  // ------------------------------------------------------------ alturas
  terrainH(x, z) { return this.world.heightAt(x, z); }
  // altura do chão para um pé em feetY (considera topos de caixas "walk")
  groundAt(x, z, feetY, stepUp = 0.55) {
    let h = this.world.heightAt(x, z);
    const list = this.near(x, z, 1.5, this._tmp || (this._tmp = []));
    for (const c of list) {
      if (c.dead || !c.walk) continue;
      if (c.kind === 0) {
        const dx = x - c.cx, dz = z - c.cz;
        const lx = dx * c.cos - dz * c.sin, lz = dx * c.sin + dz * c.cos;
        if (Math.abs(lx) > c.hx || Math.abs(lz) > c.hz) continue;
      } else if (Math.hypot(x - c.cx, z - c.cz) > c.r) continue;
      if (c.y1 <= feetY + stepUp && c.y1 > h) h = c.y1;
    }
    return h;
  }
  surfaceAt(x, z) {
    const w = this.world, h = w.heightAt(x, z);
    if (h < this.waterY + 0.1) return SURF.WATER;
    // índice de splat
    const SN = 1024, i = clamp(Math.floor(x / 2000 * SN), 0, SN - 1), j = clamp(Math.floor(z / 2000 * SN), 0, SN - 1);
    const o = (j * SN + i) * 4;
    const s0 = w.splat0, s1 = w.splat1;
    if (s1[o + 2] > 128) return SURF.ASPHALT;
    if (s1[o + 1] > 128) return SURF.DIRT;
    if (s1[o] > 128) return SURF.SAND;
    if (s0[o + 3] > 128) return SURF.STONE;
    if (s0[o + 2] > 128) return SURF.DIRT;
    return SURF.GRASS;
  }

  // ------------------------------------------------------------ character controller
  // ch: {pos:[x,y,z], vel:[x,y,z], radius, height, grounded, swimming, ...}
  moveCharacter(ch, dt, wishX, wishZ, jump = false) {
    const p = ch.pos, v = ch.vel;
    // horizontal: aceleração suave
    const acc = ch.grounded ? 14 : 2.5;
    const k = 1 - Math.exp(-acc * dt);
    v[0] += (wishX - v[0]) * k; v[2] += (wishZ - v[2]) * k;
    // água
    const wh = this.world.heightAt(p[0], p[2]);
    const waterDepth = this.waterY - wh;
    const wasSwim = ch.swimming;
    ch.swimming = waterDepth > 1.3 && p[1] < this.waterY - 0.55 && !ch.onPlatform;
    ch.wading = waterDepth > 0.25 && !ch.swimming;
    if (ch.swimming) {
      const target = this.waterY - 1.15;
      v[1] += (clamp((target - p[1]) * 3, -3, 3) - v[1]) * Math.min(1, dt * 4);
      if (jump) v[1] = 3;
      ch.grounded = false;
    } else {
      v[1] -= G * dt;
      if (jump && ch.grounded) { v[1] = ch.jumpSpeed || 4.4; ch.grounded = false; }
    }
    let nx = p[0] + v[0] * dt, nz = p[2] + v[2] * dt, ny = p[1] + v[1] * dt;
    // limites do mundo
    nx = clamp(nx, 2, 1998); nz = clamp(nz, 2, 1998);
    // colisores
    const r = ch.radius, top = ny + ch.height, step = ch.grounded ? 0.55 : 0.2;
    const list = this.near(nx, nz, r + 3, this._cl || (this._cl = []));
    for (let it = 0; it < 2; it++) {
      for (const c of list) {
        if (c.dead || c.ghost) continue;
        if (ny + step >= c.y1 || top <= c.y0 + 0.05) continue; // acima (pode subir) ou abaixo
        if (c.kind === 0) {
          const dx = nx - c.cx, dz = nz - c.cz;
          const lx = dx * c.cos - dz * c.sin, lz = dx * c.sin + dz * c.cos;
          const qx = clamp(lx, -c.hx, c.hx), qz = clamp(lz, -c.hz, c.hz);
          let ox = lx - qx, oz = lz - qz;
          const d2 = ox * ox + oz * oz;
          if (d2 >= r * r) continue;
          let pushx, pushz;
          if (d2 > 1e-8) { const d = Math.sqrt(d2), pen = r - d; pushx = ox / d * pen; pushz = oz / d * pen; }
          else { // centro dentro: empurra pelo eixo mais raso
            const px = c.hx - Math.abs(lx), pz = c.hz - Math.abs(lz);
            if (px < pz) { pushx = Math.sign(lx || 1) * (px + r); pushz = 0; } else { pushx = 0; pushz = Math.sign(lz || 1) * (pz + r); }
          }
          nx += pushx * c.cos + pushz * c.sin; nz += -pushx * c.sin + pushz * c.cos;
          const pl = Math.hypot(pushx, pushz) || 1;
          const nxw = (pushx * c.cos + pushz * c.sin) / pl, nzw = (-pushx * c.sin + pushz * c.cos) / pl;
          const vn = v[0] * nxw + v[2] * nzw; if (vn < 0) { v[0] -= vn * nxw; v[2] -= vn * nzw; }
        } else {
          const dx = nx - c.cx, dz = nz - c.cz, d = Math.hypot(dx, dz), rr = r + c.r;
          if (d >= rr || d < 1e-6) continue;
          const pen = rr - d, ux = dx / d, uz = dz / d;
          nx += ux * pen; nz += uz * pen;
          const vn = v[0] * ux + v[2] * uz; if (vn < 0) { v[0] -= vn * ux; v[2] -= vn * uz; }
        }
      }
    }
    // inclinação máxima do terreno
    const ng = this.world.heightAt(nx, nz), cg = this.world.heightAt(p[0], p[2]);
    if (ch.grounded && ng - cg > (ch.maxStep ?? 0.62) * Math.hypot(nx - p[0], nz - p[2]) / 0.5 + 0.02 && ng - ny > 0.3) {
      // parede de terreno: desliza
      nx = p[0]; nz = p[2]; v[0] *= 0.2; v[2] *= 0.2;
    }
    const ground = this.groundAt(nx, nz, ny, step);
    if (!ch.swimming) {
      if (ny <= ground + 0.001 && v[1] <= 0.0 || (ch.grounded && ny - ground < 0.18 && v[1] <= 0.5 && !jump)) {
        // pouso / seguir o chão
        if (!ch.grounded && v[1] < -6) ch.landSpeed = -v[1];
        ny = ground; v[1] = 0; ch.grounded = true;
      } else if (ny > ground + 0.05) ch.grounded = false;
    }
    ch.pos[0] = nx; ch.pos[1] = ny; ch.pos[2] = nz;
    ch.groundY = ground;
    ch.onSlope = this.world.normalAt(nx, nz)[1];
    // teto
    if (v[1] > 0) {
      for (const c of list) {
        if (c.dead || c.ghost) continue;
        if (c.kind === 0) { const dx = nx - c.cx, dz = nz - c.cz; const lx = dx * c.cos - dz * c.sin, lz = dx * c.sin + dz * c.cos; if (Math.abs(lx) > c.hx + r * 0.5 || Math.abs(lz) > c.hz + r * 0.5) continue; }
        else if (Math.hypot(nx - c.cx, nz - c.cz) > c.r + r) continue;
        if (c.y0 >= ny + ch.height - 0.3 && c.y0 < ny + ch.height + 0.2) { v[1] = Math.min(v[1], -0.5); }
      }
    }
  }

  // ------------------------------------------------------------ raycast
  rayTerrain(o, d, maxT) {
    const w = this.world;
    // marcha com passos adaptativos + bisseção
    let t = 0, prevT = 0, step = 1.0;
    const fy = (tt) => o[1] + d[1] * tt - w.heightAt(o[0] + d[0] * tt, o[2] + d[2] * tt);
    if (fy(0) < 0) return null;
    while (t < maxT) {
      prevT = t; t += step; if (t > maxT) t = maxT;
      if (fy(t) < 0) {
        let a = prevT, b = t;
        for (let i = 0; i < 12; i++) { const m = (a + b) / 2; if (fy(m) < 0) b = m; else a = m; }
        return b;
      }
      step = clamp(Math.abs(fy(t)) * 0.6, 0.6, 24);
      if (t >= maxT) break;
    }
    return null;
  }
  // devolve {t, point[3], normal[3], type:'terrain'|'col'|'body', col, body, surf}
  raycast(o, d, maxT = 1000, opts = {}) {
    let best = null;
    const tt = this.rayTerrain(o, d, maxT);
    if (tt !== null) {
      const px = o[0] + d[0] * tt, py = o[1] + d[1] * tt, pz = o[2] + d[2] * tt;
      const n = this.world.normalAt(px, pz);
      best = { t: tt, point: [px, py, pz], normal: n, type: 'terrain', surf: this.surfaceAt(px, pz) };
      if (best.surf === SURF.WATER) best.point[1] = this.waterY;
    }
    // água (plano) quando o terreno é mais fundo
    if (d[1] < 0 && o[1] > this.waterY) {
      const tw = (this.waterY - o[1]) / d[1];
      if (tw > 0 && tw < maxT && (!best || tw < best.t)) {
        const px = o[0] + d[0] * tw, pz = o[2] + d[2] * tw;
        if (this.world.heightAt(px, pz) < this.waterY) best = { t: tw, point: [px, this.waterY, pz], normal: [0, 1, 0], type: 'water', surf: SURF.WATER };
      }
    }
    const lim = best ? best.t : maxT;
    // colisores ao longo do raio
    const seen = new Set();
    const steps = Math.ceil(lim / (CELL * 0.5)) + 1;
    for (let s = 0; s <= steps; s++) {
      const t = Math.min(lim, s * CELL * 0.5);
      const cx = Math.floor((o[0] + d[0] * t) / CELL), cz = Math.floor((o[2] + d[2] * t) / CELL);
      for (let i = -1; i <= 1; i++) for (let j = -1; j <= 1; j++) {
        const l = this.grid.get((cx + i) * 4096 + (cz + j)); if (!l) continue;
        for (const c of l) {
          if (seen.has(c) || c.dead || c.noBullet || (opts.ignore && opts.ignore === c)) continue;
          seen.add(c);
          const h = this._rayCol(o, d, c, best ? best.t : lim);
          if (h && (!best || h.t < best.t)) best = h;
        }
      }
    }
    // corpos rígidos
    if (!opts.noBodies) for (const b of this.bodies) {
      if (b.dead || (opts.ignore && opts.ignore === b)) continue;
      const h = this._rayBody(o, d, b, best ? best.t : lim);
      if (h && (!best || h.t < best.t)) best = h;
    }
    // alvos extras (jogadores/entidades) via callback
    if (opts.extra) { const h = opts.extra(o, d, best ? best.t : lim); if (h && (!best || h.t < best.t)) best = h; }
    return best;
  }
  _rayCol(o, d, c, maxT) {
    if (c.kind === 1) {
      const ox = o[0] - c.cx, oz = o[2] - c.cz, a = d[0] * d[0] + d[2] * d[2];
      if (a < 1e-9) return null;
      const b = ox * d[0] + oz * d[2], cc = ox * ox + oz * oz - c.r * c.r, disc = b * b - a * cc;
      if (disc < 0) return null;
      const sq = Math.sqrt(disc); let t = (-b - sq) / a;
      if (t < 0) t = (-b + sq) / a; if (t < 0 || t > maxT) return null;
      const y = o[1] + d[1] * t; if (y < c.y0 || y > c.y1) return null;
      const px = o[0] + d[0] * t, pz = o[2] + d[2] * t;
      return { t, point: [px, y, pz], normal: [(px - c.cx) / c.r, 0, (pz - c.cz) / c.r], type: 'col', col: c, surf: c.surf };
    }
    // OBB: transforma o raio para o espaço local
    const ox = o[0] - c.cx, oz = o[2] - c.cz;
    const lo = [ox * c.cos - oz * c.sin, o[1], ox * c.sin + oz * c.cos];
    const ld = [d[0] * c.cos - d[2] * c.sin, d[1], d[0] * c.sin + d[2] * c.cos];
    let tmin = 0, tmax = maxT, nAxis = -1, nSign = 0;
    const mn = [-c.hx, c.y0, -c.hz], mx = [c.hx, c.y1, c.hz];
    for (let a = 0; a < 3; a++) {
      if (Math.abs(ld[a]) < 1e-9) { if (lo[a] < mn[a] || lo[a] > mx[a]) return null; continue; }
      let t1 = (mn[a] - lo[a]) / ld[a], t2 = (mx[a] - lo[a]) / ld[a], s = -1;
      if (t1 > t2) { const t = t1; t1 = t2; t2 = t; s = 1; }
      if (t1 > tmin) { tmin = t1; nAxis = a; nSign = s; }
      if (t2 < tmax) tmax = t2;
      if (tmin > tmax) return null;
    }
    if (nAxis < 0) return null; // origem dentro
    const ln = [0, 0, 0]; ln[nAxis] = nSign;
    const wn = [ln[0] * c.cos + ln[2] * c.sin, ln[1], -ln[0] * c.sin + ln[2] * c.cos];
    return { t: tmin, point: [o[0] + d[0] * tmin, o[1] + d[1] * tmin, o[2] + d[2] * tmin], normal: wn, type: 'col', col: c, surf: c.surf };
  }
  _rayBody(o, d, b, maxT) {
    // espaço local do corpo
    const qc = q4.conj(new Float32Array(4), b.q);
    const rel = [o[0] - b.pos[0], o[1] - b.pos[1], o[2] - b.pos[2]];
    const lo = q4.rotate([0, 0, 0], qc, rel), ld = q4.rotate([0, 0, 0], qc, d);
    let h = b.half;
    if (b.shape === 'sphere') {
      const bq = lo[0] * ld[0] + lo[1] * ld[1] + lo[2] * ld[2], cq = lo[0] ** 2 + lo[1] ** 2 + lo[2] ** 2 - b.radius ** 2, disc = bq * bq - cq;
      if (disc < 0) return null; const t = -bq - Math.sqrt(disc); if (t < 0 || t > maxT) return null;
      const pt = [o[0] + d[0] * t, o[1] + d[1] * t, o[2] + d[2] * t];
      return { t, point: pt, normal: v3.normalize([0, 0, 0], [pt[0] - b.pos[0], pt[1] - b.pos[1], pt[2] - b.pos[2]]), type: 'body', body: b, surf: b.surf ?? SURF.WOOD };
    }
    let tmin = 0, tmax = maxT, nAxis = -1, nSign = 0;
    for (let a = 0; a < 3; a++) {
      if (Math.abs(ld[a]) < 1e-9) { if (Math.abs(lo[a]) > h[a]) return null; continue; }
      let t1 = (-h[a] - lo[a]) / ld[a], t2 = (h[a] - lo[a]) / ld[a], s = -1;
      if (t1 > t2) { const t = t1; t1 = t2; t2 = t; s = 1; }
      if (t1 > tmin) { tmin = t1; nAxis = a; nSign = s; }
      if (t2 < tmax) tmax = t2;
      if (tmin > tmax) return null;
    }
    if (nAxis < 0) return null;
    const ln = [0, 0, 0]; ln[nAxis] = nSign;
    return { t: tmin, point: [o[0] + d[0] * tmin, o[1] + d[1] * tmin, o[2] + d[2] * tmin], normal: q4.rotate([0, 0, 0], b.q, ln), type: 'body', body: b, surf: b.surf ?? SURF.WOOD };
  }
  // segmento (para balística): retorna hit com t em metros ou null
  segment(a, b, opts) {
    const d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], L = Math.hypot(...d);
    if (L < 1e-6) return null;
    d[0] /= L; d[1] /= L; d[2] /= L;
    return this.raycast(a, d, L, opts);
  }

  // ------------------------------------------------------------ corpos rígidos
  addBody(o) {
    const b = {
      shape: o.shape || 'box', half: o.half ? o.half.slice() : [0.2, 0.2, 0.2], radius: o.radius || 0.2,
      mass: o.mass || 1, pos: o.pos.slice(), q: o.q ? q4.copy(new Float32Array(4), o.q) : q4.create(), vel: o.vel ? o.vel.slice() : [0, 0, 0], w: o.w ? o.w.slice() : [0, 0, 0],
      rest: o.rest ?? 0.25, fric: o.fric ?? 0.6, sleep: 0, asleep: false, userdata: o.userdata, surf: o.surf ?? SURF.WOOD, dead: false,
      drag: o.drag ?? 0.02, adrag: o.adrag ?? 0.25, floatY: o.floats ? 1 : 0, buoyant: !!o.buoyant,
    };
    if (b.shape === 'box') { const h = b.half, m = b.mass; b.invI = [3 / (m * (h[1] ** 2 + h[2] ** 2)), 3 / (m * (h[0] ** 2 + h[2] ** 2)), 3 / (m * (h[0] ** 2 + h[1] ** 2))]; b.R = Math.hypot(...h); }
    else { const r = b.radius; b.invI = [2.5 / (b.mass * r * r), 2.5 / (b.mass * r * r), 2.5 / (b.mass * r * r)]; b.R = r; }
    b.invM = 1 / b.mass;
    this.bodies.push(b);
    return b;
  }
  removeBody(b) { b.dead = true; }
  wake(b) { b.asleep = false; b.sleep = 0; }
  applyImpulse(b, J, point) {
    this.wake(b);
    b.vel[0] += J[0] * b.invM; b.vel[1] += J[1] * b.invM; b.vel[2] += J[2] * b.invM;
    if (point) {
      const r = [point[0] - b.pos[0], point[1] - b.pos[1], point[2] - b.pos[2]];
      const tq = v3.cross([0, 0, 0], r, J);
      // inverte para espaço local, aplica I^-1, volta ao mundo
      const qc = q4.conj(new Float32Array(4), b.q);
      const l = q4.rotate([0, 0, 0], qc, tq); l[0] *= b.invI[0]; l[1] *= b.invI[1]; l[2] *= b.invI[2];
      const w = q4.rotate([0, 0, 0], b.q, l);
      b.w[0] += w[0]; b.w[1] += w[1]; b.w[2] += w[2];
    }
  }
  _contact(b, p, n, pen, r2) {
    // p: ponto de contato (mundo); n: normal (pra fora da superfície)
    const rx = p[0] - b.pos[0], ry = p[1] - b.pos[1], rz = p[2] - b.pos[2];
    // correção de posição
    const corr = Math.min(pen, 0.6) * 0.8;
    b.pos[0] += n[0] * corr; b.pos[1] += n[1] * corr; b.pos[2] += n[2] * corr;
    const vx = b.vel[0] + (b.w[1] * rz - b.w[2] * ry), vy = b.vel[1] + (b.w[2] * rx - b.w[0] * rz), vz = b.vel[2] + (b.w[0] * ry - b.w[1] * rx);
    const vn = vx * n[0] + vy * n[1] + vz * n[2];
    if (vn >= 0) return 0;
    // massa efetiva
    const rn = [ry * n[2] - rz * n[1], rz * n[0] - rx * n[2], rx * n[1] - ry * n[0]];
    const qc = q4.conj(new Float32Array(4), b.q);
    const ln = q4.rotate([0, 0, 0], qc, rn); ln[0] *= b.invI[0]; ln[1] *= b.invI[1]; ln[2] *= b.invI[2];
    const wn = q4.rotate([0, 0, 0], b.q, ln);
    const cr = [wn[1] * rz - wn[2] * ry, wn[2] * rx - wn[0] * rz, wn[0] * ry - wn[1] * rx];
    const kN = b.invM + (cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2]);
    const e = Math.abs(vn) < 1.2 ? 0 : b.rest;
    const jn = -(1 + e) * vn / kN;
    this._imp(b, [n[0] * jn, n[1] * jn, n[2] * jn], [rx, ry, rz]);
    // atrito
    const tx = vx - vn * n[0], ty = vy - vn * n[1], tz = vz - vn * n[2], tl = Math.hypot(tx, ty, tz);
    if (tl > 1e-4) {
      const t = [tx / tl, ty / tl, tz / tl];
      const rt = [ry * t[2] - rz * t[1], rz * t[0] - rx * t[2], rx * t[1] - ry * t[0]];
      const lt = q4.rotate([0, 0, 0], qc, rt); lt[0] *= b.invI[0]; lt[1] *= b.invI[1]; lt[2] *= b.invI[2];
      const wt = q4.rotate([0, 0, 0], b.q, lt);
      const crt = [wt[1] * rz - wt[2] * ry, wt[2] * rx - wt[0] * rz, wt[0] * ry - wt[1] * rx];
      const kT = b.invM + (crt[0] * t[0] + crt[1] * t[1] + crt[2] * t[2]);
      let jt = -tl / kT; const lim = b.fric * jn; jt = clamp(jt, -lim, lim);
      this._imp(b, [t[0] * jt, t[1] * jt, t[2] * jt], [rx, ry, rz]);
    }
    return -vn;
  }
  _imp(b, J, r) {
    b.vel[0] += J[0] * b.invM; b.vel[1] += J[1] * b.invM; b.vel[2] += J[2] * b.invM;
    const tq = [r[1] * J[2] - r[2] * J[1], r[2] * J[0] - r[0] * J[2], r[0] * J[1] - r[1] * J[0]];
    const qc = q4.conj(new Float32Array(4), b.q);
    const l = q4.rotate([0, 0, 0], qc, tq); l[0] *= b.invI[0]; l[1] *= b.invI[1]; l[2] *= b.invI[2];
    const w = q4.rotate([0, 0, 0], b.q, l);
    b.w[0] += w[0]; b.w[1] += w[1]; b.w[2] += w[2];
  }
  _stepBody(b, dt) {
    if (b.asleep) return;
    b.vel[1] -= G * dt;
    // água: empuxo/arrasto
    if (b.pos[1] < this.waterY && this.world.heightAt(b.pos[0], b.pos[2]) < this.waterY) {
      const sub = clamp((this.waterY - b.pos[1]) / (b.R * 2), 0, 1);
      const dens = b.buoyant ? 1.5 : 0.5; b.vel[1] += G * dens * sub * dt * 2.0;
      const dr = 1 - Math.min(1, 3 * dt * sub); b.vel[0] *= dr; b.vel[1] *= dr; b.vel[2] *= dr; b.w[0] *= dr; b.w[1] *= dr; b.w[2] *= dr;
    }
    b.pos[0] += b.vel[0] * dt; b.pos[1] += b.vel[1] * dt; b.pos[2] += b.vel[2] * dt;
    // integra orientação
    const wl = Math.hypot(b.w[0], b.w[1], b.w[2]);
    if (wl > 1e-5) { const dq = q4.axisAngle(new Float32Array(4), b.w[0] / wl, b.w[1] / wl, b.w[2] / wl, wl * dt); q4.mul(b.q, dq, b.q); q4.normalize(b.q, b.q); }
    const dm = 1 - b.drag * dt * 10, da = 1 - b.adrag * dt;
    b.vel[0] *= dm; b.vel[1] *= dm; b.vel[2] *= dm; b.w[0] *= da; b.w[1] *= da; b.w[2] *= da;
    // colisões
    let maxImp = 0, touching = false;
    const pts = this._pts(b);
    for (const lp of pts) {
      const wp = q4.rotate([0, 0, 0], b.q, lp); wp[0] += b.pos[0]; wp[1] += b.pos[1]; wp[2] += b.pos[2];
      const off = b.shape === 'sphere' ? b.radius : 0;
      const h = this.world.heightAt(wp[0], wp[2]);
      if (wp[1] - off < h) {
        const n = this.world.normalAt(wp[0], wp[2]);
        const pen = h - (wp[1] - off);
        touching = true;
        const cp = b.shape === 'sphere' ? [b.pos[0] - n[0] * b.radius, b.pos[1] - n[1] * b.radius, b.pos[2] - n[2] * b.radius] : [wp[0], h, wp[2]];
        maxImp = Math.max(maxImp, this._contact(b, cp, n, pen, 0));
      }
      // colisores estáticos
      const list = this.near(wp[0], wp[2], 1.5, this._bl || (this._bl = []));
      for (const c of list) {
        if (c.dead || c.ghost) continue;
        if (wp[1] + off < c.y0 || wp[1] - off > c.y1) continue;
        let n, pen;
        if (c.kind === 0) {
          const dx = wp[0] - c.cx, dz = wp[2] - c.cz;
          const lx = dx * c.cos - dz * c.sin, lz = dx * c.sin + dz * c.cos;
          const px = c.hx - Math.abs(lx) + off, pz = c.hz - Math.abs(lz) + off, py1 = c.y1 - wp[1] + off, py0 = wp[1] - c.y0 + off;
          if (px < 0 || pz < 0) continue;
          const m = Math.min(px, pz, py1, py0);
          if (m === py1) { n = [0, 1, 0]; pen = py1; }
          else if (m === py0) { n = [0, -1, 0]; pen = py0; }
          else if (m === px) { const s = Math.sign(lx || 1); n = [s * c.cos, 0, -s * c.sin]; pen = px; }
          else { const s = Math.sign(lz || 1); n = [s * c.sin, 0, s * c.cos]; pen = pz; }
        } else {
          const dx = wp[0] - c.cx, dz = wp[2] - c.cz, d = Math.hypot(dx, dz);
          if (d > c.r + off) continue;
          n = [dx / (d || 1), 0, dz / (d || 1)]; pen = c.r + off - d;
        }
        touching = true;
        maxImp = Math.max(maxImp, this._contact(b, wp, n, pen, 0));
      }
    }
    if (maxImp > 2.5 && b.onImpact) b.onImpact(b, maxImp);
    // sono
    const sp = Math.hypot(b.vel[0], b.vel[1], b.vel[2]) + Math.hypot(b.w[0], b.w[1], b.w[2]) * 0.3;
    if (touching && sp < 0.25) { b.sleep += dt; if (b.sleep > 0.8) { b.asleep = true; b.vel[0] = b.vel[1] = b.vel[2] = 0; b.w[0] = b.w[1] = b.w[2] = 0; } } else b.sleep = 0;
  }
  _pts(b) {
    if (b.shape === 'sphere') return [[0, 0, 0]];
    if (b._pts) return b._pts;
    const h = b.half, p = [];
    for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) p.push([sx * h[0], sy * h[1], sz * h[2]]);
    // pontos médios das arestas longas para melhor apoio
    b._pts = p; return p;
  }

  // ------------------------------------------------------------ balística
  fire(origin, dir, speed, o = {}) {
    const p = { pos: origin.slice(), vel: [dir[0] * speed, dir[1] * speed, dir[2] * speed], k: o.k ?? 0.0008, life: o.life ?? 4, damage: o.damage ?? 40, mass: o.mass ?? 0.01, owner: o.owner, kind: o.kind || 'bullet', dist: 0, pen: o.pen ?? 1, tracer: o.tracer, data: o.data };
    this.projectiles.push(p);
    return p;
  }
  _stepProjectile(p, dt) {
    const sub = Math.max(1, Math.ceil(Math.hypot(...p.vel) * dt / 20));
    const h = dt / sub;
    for (let s = 0; s < sub; s++) {
      const sp = Math.hypot(p.vel[0], p.vel[1], p.vel[2]);
      const wx = this.wind[0], wz = this.wind[1];
      // arrasto quadrático relativo ao ar (vento)
      const rvx = p.vel[0] - wx, rvz = p.vel[2] - wz, rv = Math.hypot(rvx, p.vel[1], rvz);
      p.vel[0] -= p.k * rv * rvx * h; p.vel[1] -= p.k * rv * p.vel[1] * h; p.vel[2] -= p.k * rv * rvz * h;
      p.vel[1] -= G * h;
      const np = [p.pos[0] + p.vel[0] * h, p.pos[1] + p.vel[1] * h, p.pos[2] + p.vel[2] * h];
      const hit = this.segment(p.pos, np, { ignore: p.owner });
      if (hit) {
        p.dist += hit.t;
        p.prev = p.pos;
        const speedNow = Math.hypot(p.vel[0], p.vel[1], p.vel[2]);
        let cont = false;
        if (this.onProjectileHit) cont = this.onProjectileHit(p, hit, speedNow) === true;
        if (!cont) { p.dead = true; return; }
        p.pos = [hit.point[0] + p.vel[0] / speedNow * 0.05, hit.point[1] + p.vel[1] / speedNow * 0.05, hit.point[2] + p.vel[2] / speedNow * 0.05];
        continue;
      }
      p.dist += Math.hypot(np[0] - p.pos[0], np[1] - p.pos[1], np[2] - p.pos[2]);
      p.prev = p.pos; p.pos = np;
      if (np[0] < -20 || np[0] > 2020 || np[2] < -20 || np[2] > 2020 || np[1] < -30) { p.dead = true; return; }
    }
    p.life -= dt;
    if (p.life <= 0) p.dead = true;
  }

  // ------------------------------------------------------------ passo
  step(dt) {
    this._acc += Math.min(dt, 0.1);
    const FIXED = 1 / 120;
    let n = 0;
    while (this._acc >= FIXED && n < 8) {
      for (const h of this.hooks) h(FIXED);
      for (const b of this.bodies) if (!b.dead) this._stepBody(b, FIXED);
      this._acc -= FIXED; n++;
    }
    for (const p of this.projectiles) if (!p.dead) this._stepProjectile(p, dt);
    this.projectiles = this.projectiles.filter((p) => !p.dead);
    if (this.bodies.length > 0 && (this._clean = (this._clean || 0) + 1) % 120 === 0) this.bodies = this.bodies.filter((b) => !b.dead);
  }

  // explosão radial
  explode(pos, radius, power, onVictim) {
    for (const b of this.bodies) {
      if (b.dead) continue;
      const dx = b.pos[0] - pos[0], dy = b.pos[1] - pos[1], dz = b.pos[2] - pos[2], d = Math.hypot(dx, dy, dz);
      if (d > radius) continue;
      const f = (1 - d / radius) * power * Math.min(b.mass, 20) ;
      const dl = d || 1;
      this.applyImpulse(b, [dx / dl * f, dy / dl * f + f * 0.45, dz / dl * f], [b.pos[0] - dx / dl * 0.2, b.pos[1] - 0.1, b.pos[2] - dz / dl * 0.2]);
    }
    if (onVictim) onVictim(pos, radius);
  }
}
