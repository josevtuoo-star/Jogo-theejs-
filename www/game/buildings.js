// Construtor procedural de edifícios, estradas, ponte, postes, cercas e veículos (mesh + colisores).
import { MeshBuilder } from '../engine/gl.js';
import { mulberry32, hash2, clamp, lerp, smoothstep } from '../engine/math.js';
import { MAT } from './assets.js';
import { SURF } from '../engine/physics.js';

// ------------------------------------------------------------------ construtor orientado
export class Build {
  constructor() { this.mb = new MeshBuilder(); this.cols = []; this.loot = []; this.ox = 0; this.oz = 0; this.oy = 0; this.yaw = 0; this.c = 1; this.s = 0; this.tint = 128; this.uvo = [0, 0]; }
  at(x, y, z, yaw) { this.ox = x; this.oy = y; this.oz = z; this.yaw = yaw; this.c = Math.cos(yaw); this.s = Math.sin(yaw); return this; }
  W(lx, lz) { return [this.ox + lx * this.c + lz * this.s, this.oz - lx * this.s + lz * this.c]; }
  // caixa alinhada ao eixo local (x0..x1, y0..y1, z0..z1) em coordenadas locais (y relativo a oy)
  box(x0, y0, z0, x1, y1, z1, layer, o = {}) {
    const cx = (x0 + x1) / 2, cz = (z0 + z1) / 2, hx = (x1 - x0) / 2, hy = (y1 - y0) / 2, hz = (z1 - z0) / 2;
    const [wx, wz] = this.W(cx, cz);
    const wy = this.oy + (y0 + y1) / 2;
    this.obox(wx, wy, wz, hx, hy, hz, this.yaw, layer, o);
    if (o.col !== false && !o.noCol) this.cols.push({ cx: wx, cy: wy, cz: wz, hx, hy, hz, yaw: this.yaw, surf: o.surf ?? SURF.WOOD, walk: !!o.walk, noBullet: !!o.noBullet, ghost: !!o.ghost });
  }
  // caixa orientada em coordenadas de mundo
  obox(cx, cy, cz, hx, hy, hz, yaw, layer, o = {}) {
    const b = this.mb, c = Math.cos(yaw), s = Math.sin(yaw);
    const ex = [c, 0, -s], ez = [s, 0, c];
    const P = (sx, sy, sz) => [cx + ex[0] * hx * sx + ez[0] * hz * sz, cy + hy * sy, cz + ex[2] * hx * sx + ez[2] * hz * sz];
    const uvs = o.uvScale ?? 1, tint = o.tint ?? this.tint, ao = o.ao ?? 255;
    const faces = o.faces ?? 63;
    const L = (i) => (o.layers ? o.layers[i] : layer);
    const uo = this.uvo;
    const q = (p0, p1, p2, p3, n, w, h, ly, uoff, voff) => {
      const f = b.vcount;
      const ww = w * uvs, hh = h * uvs;
      const a = [uo[0] + uoff, uo[1] + voff];
      b.vert(p0[0], p0[1], p0[2], n[0], n[1], n[2], a[0], a[1] + hh, ao, ly, tint, 0);
      b.vert(p1[0], p1[1], p1[2], n[0], n[1], n[2], a[0] + ww, a[1] + hh, ao, ly, tint, 0);
      b.vert(p2[0], p2[1], p2[2], n[0], n[1], n[2], a[0] + ww, a[1], ao, ly, tint, 0);
      b.vert(p3[0], p3[1], p3[2], n[0], n[1], n[2], a[0], a[1], ao, ly, tint, 0);
      b.quad(f, f + 1, f + 2, f + 3);
    };
    // UV: u ao longo do eixo horizontal local, v vertical (metros); offsets deixam texturas contínuas por parede
    const ox = (o.u0 ?? 0), oyv = (o.v0 ?? 0);
    if (faces & 1) q(P(1, -1, 1), P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), [ex[0], 0, ex[2]], 2 * hz, 2 * hy, L(0), ox + this.ou(cz, cx, 1, ez), oyv);
    if (faces & 2) q(P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1), P(-1, 1, -1), [-ex[0], 0, -ex[2]], 2 * hz, 2 * hy, L(1), ox + this.ou(cz, cx, -1, ez), oyv);
    if (faces & 4) q(P(-1, 1, 1), P(1, 1, 1), P(1, 1, -1), P(-1, 1, -1), [0, 1, 0], 2 * hx, 2 * hz, L(2), ox, oyv);
    if (faces & 8) q(P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1), [0, -1, 0], 2 * hx, 2 * hz, L(3), ox, oyv);
    if (faces & 16) q(P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1), [ez[0], 0, ez[2]], 2 * hx, 2 * hy, L(4), ox + this.ou(cx, cz, 1, ex), oyv);
    if (faces & 32) q(P(1, -1, -1), P(-1, -1, -1), P(-1, 1, -1), P(1, 1, -1), [-ez[0], 0, -ez[2]], 2 * hx, 2 * hy, L(5), ox + this.ou(cx, cz, -1, ex), oyv);
  }
  ou(a, b, s, axis) { return ((a * axis[2] + b * axis[0]) * 0.37) % 7; }
  // plano inclinado (telhado). p0..p3 em coordenadas locais [x,y,z]; normal calculada
  quadL(p0, p1, p2, p3, layer, uvm = 1, tint) {
    const b = this.mb, w = [p0, p1, p2, p3].map((p) => { const [x, z] = this.W(p[0], p[2]); return [x, this.oy + p[1], z]; });
    const e1 = [w[1][0] - w[0][0], w[1][1] - w[0][1], w[1][2] - w[0][2]], e2 = [w[3][0] - w[0][0], w[3][1] - w[0][1], w[3][2] - w[0][2]];
    let n = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
    const l = Math.hypot(...n) || 1; n = [n[0] / l, n[1] / l, n[2] / l];
    const L1 = Math.hypot(...e1) * uvm, L2 = Math.hypot(...e2) * uvm, t = tint ?? this.tint;
    const f = b.vcount;
    b.vert(...w[0], ...n, 0, 0, 255, layer, t, 0); b.vert(...w[1], ...n, L1, 0, 255, layer, t, 0);
    b.vert(...w[2], ...n, L1, L2, 255, layer, t, 0); b.vert(...w[3], ...n, 0, L2, 255, layer, t, 0);
    b.quad(f, f + 1, f + 2, f + 3);
  }
  triL(p0, p1, p2, layer, uvm = 1) {
    const b = this.mb, w = [p0, p1, p2].map((p) => { const [x, z] = this.W(p[0], p[2]); return [x, this.oy + p[1], z]; });
    const e1 = [w[1][0] - w[0][0], w[1][1] - w[0][1], w[1][2] - w[0][2]], e2 = [w[2][0] - w[0][0], w[2][1] - w[0][1], w[2][2] - w[0][2]];
    let n = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
    const l = Math.hypot(...n) || 1; n = [n[0] / l, n[1] / l, n[2] / l];
    const f = b.vcount;
    b.vert(...w[0], ...n, p0[0] * uvm, p0[1] * uvm, 255, layer, this.tint, 0);
    b.vert(...w[1], ...n, p1[0] * uvm, p1[1] * uvm, 255, layer, this.tint, 0);
    b.vert(...w[2], ...n, p2[0] * uvm, p2[1] * uvm, 255, layer, this.tint, 0);
    b.tri(f, f + 1, f + 2);
  }

  // parede ao longo de x local (z fixo) com aberturas [{x0,x1,y0,y1}]; y0..y1 altura da parede
  wall(x0, x1, z, t, y0, y1, layer, openings = [], o = {}) {
    const pieces = [];
    const ops = openings.slice().sort((a, b) => a.x0 - b.x0);
    let cur = x0;
    for (const op of ops) {
      if (op.x0 > cur) pieces.push([cur, op.x0, y0, y1]);
      if (op.y0 > y0) pieces.push([op.x0, op.x1, y0, op.y0]);
      if (op.y1 < y1) pieces.push([op.x0, op.x1, op.y1, y1]);
      cur = op.x1;
    }
    if (cur < x1) pieces.push([cur, x1, y0, y1]);
    for (const [a, b, ya, yb] of pieces) this.box(a, ya, z - t / 2, b, yb, z + t / 2, layer, { ...o, u0: a * (o.uvScale ?? 1) });
  }
  // parede ao longo de z local (x fixo)
  wallZ(z0, z1, x, t, y0, y1, layer, openings = [], o = {}) {
    const pieces = [];
    const ops = openings.slice().sort((a, b) => a.x0 - b.x0);
    let cur = z0;
    for (const op of ops) {
      if (op.x0 > cur) pieces.push([cur, op.x0, y0, y1]);
      if (op.y0 > y0) pieces.push([op.x0, op.x1, y0, op.y0]);
      if (op.y1 < y1) pieces.push([op.x0, op.x1, op.y1, y1]);
      cur = op.x1;
    }
    if (cur < z1) pieces.push([cur, z1, y0, y1]);
    for (const [a, b, ya, yb] of pieces) this.box(x - t / 2, ya, a, x + t / 2, yb, b, layer, { ...o, u0: a * (o.uvScale ?? 1) });
  }
  // telhado de duas águas (cumeeira ao longo de x local)
  gable(x0, x1, z0, z1, yEave, rise, layer, ov = 0.5, o = {}) {
    const zm = (z0 + z1) / 2, yr = yEave + rise;
    const xa = x0 - ov, xb = x1 + ov, za = z0 - ov, zb = z1 + ov;
    const sl = Math.hypot(zb - zm, rise) / (zb - zm);
    const ya = yEave - (ov) * rise / (zm - z0);
    const um = o.uvm ?? 0.25;
    this.quadL([xa, ya, za], [xb, ya, za], [xb, yr, zm], [xa, yr, zm], layer, um);   // lado -z
    this.quadL([xb, ya, zb], [xa, ya, zb], [xa, yr, zm], [xb, yr, zm], layer, um);   // lado +z
    // face de baixo (forro)
    this.quadL([xb, ya, za], [xa, ya, za], [xa, yr, zm], [xb, yr, zm], layer, um);
    this.quadL([xa, ya, zb], [xb, ya, zb], [xb, yr, zm], [xa, yr, zm], layer, um);
    // empena
    this.triL([x0, yEave, z0], [x0, yEave, z1], [x0, yr, zm], o.gableLayer ?? MAT.plaster, 0.5);
    this.triL([x1, yEave, z1], [x1, yEave, z0], [x1, yr, zm], o.gableLayer ?? MAT.plaster, 0.5);
    // colisor aproximado (para balas e jogador acima)
    const [wx, wz] = this.W((x0 + x1) / 2, zm);
    this.cols.push({ cx: wx, cy: this.oy + yEave + rise * 0.4, cz: wz, hx: (x1 - x0) / 2 + ov, hy: rise * 0.4 + 0.1, hz: (z1 - z0) / 2 + ov, yaw: this.yaw, surf: SURF.WOOD, noBullet: false, ghost: false });
  }
  pyramid(cx, cz, half, y0, y1, layer) {
    const p = (sx, sz) => [cx + sx * half, y0, cz + sz * half], top = [cx, y1, cz];
    this.triL(p(-1, -1), p(1, -1), top, layer, 0.3); this.triL(p(1, -1), p(1, 1), top, layer, 0.3);
    this.triL(p(1, 1), p(-1, 1), top, layer, 0.3); this.triL(p(-1, 1), p(-1, -1), top, layer, 0.3);
  }
  cyl(lx, y0, lz, r0, r1, h, seg, layer, o = {}) {
    const [x, z] = this.W(lx, lz);
    this.mb.cylinder(x, this.oy + y0, z, r0, r1, h, seg, layer, { uvScale: o.uvScale ?? 0.5, cap: o.cap });
    if (o.col) this.cols.push({ kind: 1, cx: x, cz: z, r: r0, y0: this.oy + y0, y1: this.oy + y0 + h, surf: o.surf ?? SURF.METAL });
  }
}

// ------------------------------------------------------------------ tipos de edifício
// cada função recebe (B: Build, rnd, opts) com B.at() já posicionado; retorna {w, d, loot:[...]}
const WALLS = [MAT.plaster, MAT.plasterY, MAT.planks, MAT.brick, MAT.concrete];

function foundation(B, x0, x1, z0, z1, depth, layer = MAT.concrete) {
  B.box(x0 - 0.15, -depth, z0 - 0.15, x1 + 0.15, 0.12, z1 + 0.15, layer, { surf: SURF.STONE, walk: true, uvScale: 0.5 });
}

export function house(B, rnd, o = {}) {
  const W = o.w ?? (7 + rnd() * 4), D = o.d ?? (6 + rnd() * 3), H = 2.7, t = 0.22;
  const wallLayer = o.wall ?? WALLS[(rnd() * 4) | 0];
  const roofLayer = rnd() < 0.55 ? MAT.roof : rnd() < 0.5 ? MAT.roofGrey : MAT.iron;
  const x0 = -W / 2, x1 = W / 2, z0 = -D / 2, z1 = D / 2;
  const fd = o.fdepth ?? 1.3;
  foundation(B, x0, x1, z0, z1, fd);
  const fy = 0.12;
  B.tint = 90 + (rnd() * 90) | 0;
  // frente = +z (voltada para a rua). porta + janelas
  const doorX = (rnd() - 0.5) * (W - 3.2);
  const front = [{ x0: doorX - 0.5, x1: doorX + 0.5, y0: fy, y1: fy + 2.15 }];
  const nWin = Math.max(1, Math.floor((W - 2) / 3.2));
  for (let i = 0; i < nWin; i++) {
    const wx = x0 + 1.4 + i * ((W - 2.8) / Math.max(nWin - 1, 1)) * (nWin > 1 ? 1 : 0.5) + (nWin === 1 ? (W - 2.8) / 2 : 0);
    if (Math.abs(wx - doorX) < 1.5) continue;
    front.push({ x0: wx - 0.55, x1: wx + 0.55, y0: fy + 0.9, y1: fy + 2.1 });
  }
  const back = [{ x0: x0 + 1.5, x1: x0 + 2.6, y0: fy + 0.9, y1: fy + 2.1 }, { x0: x1 - 2.6, x1: x1 - 1.5, y0: fy + 0.9, y1: fy + 2.1 }];
  if (rnd() < 0.5) back.push({ x0: -0.55, x1: 0.55, y0: fy, y1: fy + 2.15 });
  const side = [{ x0: -0.55, x1: 0.55, y0: fy + 0.9, y1: fy + 2.1 }];
  B.wall(x0, x1, z1 - t / 2, t, fy, fy + H, wallLayer, front, { surf: SURF.WOOD });
  B.wall(x0, x1, z0 + t / 2, t, fy, fy + H, wallLayer, back, { surf: SURF.WOOD });
  B.wallZ(z0 + t, z1 - t, x0 + t / 2, t, fy, fy + H, wallLayer, side, { surf: SURF.WOOD });
  B.wallZ(z0 + t, z1 - t, x1 - t / 2, t, fy, fy + H, wallLayer, rnd() < 0.5 ? side : [], { surf: SURF.WOOD });
  // piso interno, forro
  B.box(x0 + t, fy - 0.1, z0 + t, x1 - t, fy + 0.03, z1 - t, MAT.floor, { walk: true, surf: SURF.WOOD, uvScale: 0.6, faces: 4 + 8 });
  B.quadL([x0, fy + H, z1], [x1, fy + H, z1], [x1, fy + H, z0], [x0, fy + H, z0], MAT.planks, 0.5);
  // parede interna com porta
  if (W > 7.5) {
    const px = x0 + W * (0.4 + rnd() * 0.2);
    B.wallZ(z0 + t, z1 - t, px, 0.12, fy, fy + H, MAT.plaster, [{ x0: z0 + D * 0.5 - 0.5, x1: z0 + D * 0.5 + 0.5, y0: fy, y1: fy + 2.1 }], { surf: SURF.WOOD });
  }
  B.gable(x0, x1, z0, z1, fy + H, 1.9 + rnd() * 0.8, roofLayer, 0.55, { gableLayer: wallLayer });
  // chaminé
  if (rnd() < 0.6) B.box(x1 - 1.2, fy + H, -0.5, x1 - 0.7, fy + H + 3.0, 0.0, MAT.brick, { surf: SURF.STONE });
  // móveis simples + pontos de loot
  const loot = [];
  const tbl = [x0 + 1.4, z0 + 1.1];
  B.box(tbl[0] - 0.55, fy, tbl[1] - 0.4, tbl[0] + 0.55, fy + 0.75, tbl[1] + 0.4, MAT.darkwood, { surf: SURF.WOOD });
  loot.push([tbl[0], fy + 0.75, tbl[1]], [x1 - 1.1, fy, z0 + 1.0], [0, fy, z1 - 1.2 - rnd() * 1.0]);
  if (rnd() < 0.7) { B.box(x1 - 1.5, fy, z0 + 0.35, x1 - 0.3, fy + 1.9, z0 + 0.85, MAT.darkwood, { surf: SURF.WOOD }); loot.push([x1 - 0.9, fy + 1.0, z0 + 0.6]); }
  if (rnd() < 0.5) { B.box(x0 + 0.3, fy, z1 - 2.2, x0 + 1.2, fy + 0.55, z1 - 0.4, MAT.darkwood, { surf: SURF.WOOD }); }
  return { w: W + 1, d: D + 1, loot: loot.map(([a, y, b]) => [...B.W(a, b), B.oy + y]), type: 'house', door: B.W(doorX, z1 + 1.5), top: fy + H + 2.5 };
}

export function apartment(B, rnd, o = {}) {
  const W = o.w ?? 18, D = o.d ?? 10, floors = 3, FH = 2.9, t = 0.28, fy = 0.15;
  const wallLayer = rnd() < 0.5 ? MAT.concrete : MAT.plasterY;
  const x0 = -W / 2, x1 = W / 2, z0 = -D / 2, z1 = D / 2;
  foundation(B, x0, x1, z0, z1, 1.5);
  B.tint = 100 + (rnd() * 60) | 0;
  const top = fy + FH * floors;
  const winRow = (xa, xb, f, skip) => { const r = []; for (let x = xa + 1.5; x < xb - 1.2; x += 3.1) { if (skip && Math.abs(x - skip) < 1.6) continue; r.push({ x0: x - 0.6, x1: x + 0.6, y0: fy + f * FH + 0.9, y1: fy + f * FH + 2.2 }); } return r; };
  const dx = (rnd() - 0.5) * 6;
  let frontOps = [{ x0: dx - 0.7, x1: dx + 0.7, y0: fy, y1: fy + 2.3 }];
  let backOps = [];
  for (let f = 0; f < floors; f++) { frontOps = frontOps.concat(winRow(x0, x1, f, f === 0 ? dx : 0).filter((w) => !(f === 0 && Math.abs((w.x0 + w.x1) / 2 - dx) < 1.5))); backOps = backOps.concat(winRow(x0, x1, f, 0)); }
  // paredes por andar para permitir vãos entre andares sem peças gigantes
  B.wall(x0, x1, z1 - t / 2, t, fy, top, wallLayer, frontOps, { surf: SURF.STONE });
  B.wall(x0, x1, z0 + t / 2, t, fy, top, wallLayer, backOps, { surf: SURF.STONE });
  const sideOps = []; for (let f = 0; f < floors; f++) sideOps.push({ x0: -0.6, x1: 0.6, y0: fy + f * FH + 0.9, y1: fy + f * FH + 2.2 });
  B.wallZ(z0 + t, z1 - t, x0 + t / 2, t, fy, top, wallLayer, sideOps, { surf: SURF.STONE });
  B.wallZ(z0 + t, z1 - t, x1 - t / 2, t, fy, top, wallLayer, sideOps, { surf: SURF.STONE });
  for (let f = 0; f < floors; f++) B.box(x0, fy + f * FH - 0.05, z0, x1, fy + f * FH + 0.1, z1, f === 0 ? MAT.concrete : MAT.floor, { walk: true, surf: SURF.STONE, faces: f === 0 ? 4 : 63, uvScale: 0.5 });
  B.box(x0 - 0.2, top, z0 - 0.2, x1 + 0.2, top + 0.35, z1 + 0.2, MAT.concrete, { surf: SURF.STONE });
  B.box(x0 + 0.5, fy, -0.15, x1 - 0.5, fy + FH, 0.15, MAT.plaster, { surf: SURF.STONE, ghost: false });
  const loot = [[x0 + 2, fy + 0.1, z0 + 1.5], [x1 - 2, fy + 0.1, z1 - 1.5], [0.8, fy + 0.1, z1 - 1.5], [x0 + 3, fy + 0.1, z1 - 1.5]];
  return { w: W + 1, d: D + 1, loot: loot.map(([a, y, b]) => [...B.W(a, b), B.oy + y]), type: 'apartment', door: B.W(dx, z1 + 1.5), top: top + 1 };
}

export function barn(B, rnd) {
  const W = 14, D = 9, H = 4.2, t = 0.2, fy = 0.1;
  const x0 = -W / 2, x1 = W / 2, z0 = -D / 2, z1 = D / 2;
  foundation(B, x0, x1, z0, z1, 1.2, MAT.concrete);
  B.tint = 100 + (rnd() * 40) | 0;
  B.wall(x0, x1, z1 - t / 2, t, fy, fy + H, MAT.planks, [{ x0: -1.6, x1: 1.6, y0: fy, y1: fy + 3.2 }], { surf: SURF.WOOD });
  B.wall(x0, x1, z0 + t / 2, t, fy, fy + H, MAT.planks, [{ x0: 3, x1: 4.2, y0: fy + 1.5, y1: fy + 2.4 }], { surf: SURF.WOOD });
  B.wallZ(z0 + t, z1 - t, x0 + t / 2, t, fy, fy + H, MAT.planks, [], { surf: SURF.WOOD });
  B.wallZ(z0 + t, z1 - t, x1 - t / 2, t, fy, fy + H, MAT.planks, [{ x0: -0.6, x1: 0.6, y0: fy, y1: fy + 2 }], { surf: SURF.WOOD });
  B.box(x0 + t, fy - 0.1, z0 + t, x1 - t, fy + 0.03, z1 - t, MAT.floor, { walk: true, surf: SURF.WOOD, faces: 4 });
  B.gable(x0, x1, z0, z1, fy + H, 3.4, MAT.iron, 0.6, { uvm: 0.3, gableLayer: MAT.planks });
  for (let i = 0; i < 4; i++) B.box(-5 + i * 3.3, fy, -3.5, -4.0 + i * 3.3, fy + 1.0, -2.5, MAT.planks, { surf: SURF.WOOD });
  const loot = [[-5, fy, 3], [5, fy, -3], [0, fy, 0], [5.5, fy, 2.5], [-3, fy, -3]];
  return { w: W + 1, d: D + 1, loot: loot.map(([a, y, b]) => [...B.W(a, b), B.oy + y]), type: 'barn', door: B.W(0, z1 + 1.5), top: fy + H + 3.6 };
}

export function shed(B, rnd) {
  const W = 3.4 + rnd() * 1.6, D = 3 + rnd() * 1.2, H = 2.3, t = 0.14, fy = 0.08;
  const x0 = -W / 2, x1 = W / 2, z0 = -D / 2, z1 = D / 2;
  B.tint = 80 + (rnd() * 80) | 0;
  B.box(x0 - 0.1, -0.5, z0 - 0.1, x1 + 0.1, fy, z1 + 0.1, MAT.concrete, { walk: true, surf: SURF.STONE });
  const L = rnd() < 0.5 ? MAT.planks : MAT.iron;
  B.wall(x0, x1, z1 - t / 2, t, fy, fy + H, L, [{ x0: -0.5, x1: 0.5, y0: fy, y1: fy + 2.0 }], { surf: SURF.WOOD });
  B.wall(x0, x1, z0 + t / 2, t, fy, fy + H, L, [], { surf: SURF.WOOD });
  B.wallZ(z0 + t, z1 - t, x0 + t / 2, t, fy, fy + H, L, [], { surf: SURF.WOOD });
  B.wallZ(z0 + t, z1 - t, x1 - t / 2, t, fy, fy + H, L, [{ x0: -0.4, x1: 0.4, y0: fy + 0.9, y1: fy + 1.8 }], { surf: SURF.WOOD });
  B.quadL([x0 - 0.3, fy + H, z1 + 0.4], [x1 + 0.3, fy + H, z1 + 0.4], [x1 + 0.3, fy + H + 0.5, z0 - 0.3], [x0 - 0.3, fy + H + 0.5, z0 - 0.3], MAT.iron, 0.3);
  B.box(x0 - 0.3, fy + H + 0.0, z0 - 0.3, x1 + 0.3, fy + H + 0.3, z1 + 0.4, MAT.iron, { faces: 0, noCol: false, ghost: false });
  B.box(x0 + 0.3, fy, z0 + 0.3, x0 + 1.3, fy + 0.9, z0 + 0.9, MAT.darkwood, { surf: SURF.WOOD });
  return { w: W + 1, d: D + 1, loot: [[...B.W(x0 + 0.8, z0 + 0.6), B.oy + fy + 0.9], [...B.W(0, 0), B.oy + fy]], type: 'shed', door: B.W(0, z1 + 1.2), top: fy + H + 0.6 };
}

export function church(B, rnd) {
  const W = 9, D = 15, H = 5.5, t = 0.35, fy = 0.15;
  const x0 = -W / 2, x1 = W / 2, z0 = -D / 2, z1 = D / 2;
  foundation(B, x0 - 0.3, x1 + 0.3, z0, z1 + 4, 1.5);
  B.tint = 150;
  B.wall(x0, x1, z0 + t / 2, t, fy, fy + H, MAT.plaster, [{ x0: -0.6, x1: 0.6, y0: fy + 2.5, y1: fy + 4.2 }]);
  B.wallZ(z0 + t, z1 - t, x0 + t / 2, t, fy, fy + H, MAT.plaster, [0, 1, 2].map((i) => ({ x0: z0 + 3 + i * 3.6 - 0.5, x1: z0 + 3 + i * 3.6 + 0.5, y0: fy + 1.6, y1: fy + 4.2 })));
  B.wallZ(z0 + t, z1 - t, x1 - t / 2, t, fy, fy + H, MAT.plaster, [0, 1, 2].map((i) => ({ x0: z0 + 3 + i * 3.6 - 0.5, x1: z0 + 3 + i * 3.6 + 0.5, y0: fy + 1.6, y1: fy + 4.2 })));
  B.wall(x0, x1, z1 - t / 2, t, fy, fy + H, MAT.plaster, [{ x0: -1.0, x1: 1.0, y0: fy, y1: fy + 3.0 }]);
  B.box(x0 + t, fy - 0.1, z0 + t, x1 - t, fy + 0.04, z1 - t, MAT.floor, { walk: true, faces: 4 });
  B.gable(x0, x1, z0, z1, fy + H, 3.2, MAT.roofGrey, 0.5, { gableLayer: MAT.plaster });
  // torre
  const tz = z1 + 2, tw = 2.4;
  B.wall(-tw, tw, tz + tw - t / 2, t, fy, fy + 14, MAT.plaster, []);
  B.wall(-tw, tw, tz - tw + t / 2, t, fy, fy + 14, MAT.plaster, [{ x0: -0.8, x1: 0.8, y0: fy, y1: fy + 2.8 }]);
  B.wallZ(tz - tw, tz + tw, -tw + t / 2, t, fy, fy + 14, MAT.plaster, [{ x0: tz - 0.4, x1: tz + 0.4, y0: fy + 10, y1: fy + 12.4 }]);
  B.wallZ(tz - tw, tz + tw, tw - t / 2, t, fy, fy + 14, MAT.plaster, [{ x0: tz - 0.4, x1: tz + 0.4, y0: fy + 10, y1: fy + 12.4 }]);
  B.box(-tw, fy + 14, tz - tw, tw, fy + 14.3, tz + tw, MAT.concrete);
  B.pyramid(0, tz, tw + 0.2, fy + 14.3, fy + 21, MAT.roofGrey);
  B.box(-0.08, fy + 21, tz - 0.08, 0.08, fy + 22.6, tz + 0.08, MAT.metal, { noCol: true });
  B.box(-0.5, fy + 22.0, tz - 0.06, 0.5, fy + 22.2, tz + 0.06, MAT.metal, { noCol: true });
  for (let i = 0; i < 5; i++) B.box(-3 + (i % 2) * 6, fy, -4 + i * 2, -1.6 + (i % 2) * 6, fy + 0.5, -3.4 + i * 2, MAT.darkwood);
  return { w: W + 2, d: D + 7, loot: [[...B.W(0, z0 + 1), B.oy + fy], [...B.W(2.5, -2), B.oy + fy + 0.5]], type: 'church', door: B.W(0, z1 + 5), top: 23 };
}

export function waterTower(B, rnd) {
  const fy = 0.1;
  B.tint = 130;
  B.box(-1.9, -0.8, -1.9, 1.9, fy, 1.9, MAT.concrete, { walk: true });
  const t = 0.3, H = 11;
  B.wall(-1.8, 1.8, 1.8 - t / 2, t, fy, fy + H, MAT.plasterY, [{ x0: -0.55, x1: 0.55, y0: fy, y1: fy + 2.1 }]);
  B.wall(-1.8, 1.8, -1.8 + t / 2, t, fy, fy + H, MAT.plasterY, [{ x0: -0.4, x1: 0.4, y0: fy + 4, y1: fy + 5.2 }, { x0: -0.4, x1: 0.4, y0: fy + 8, y1: fy + 9.2 }]);
  B.wallZ(-1.8, 1.8, -1.8 + t / 2, t, fy, fy + H, MAT.plasterY, [{ x0: -0.4, x1: 0.4, y0: fy + 6, y1: fy + 7.2 }]);
  B.wallZ(-1.8, 1.8, 1.8 - t / 2, t, fy, fy + H, MAT.plasterY, [{ x0: -0.4, x1: 0.4, y0: fy + 6, y1: fy + 7.2 }]);
  B.box(-1.8, fy + H, -1.8, 1.8, fy + H + 0.3, 1.8, MAT.concrete);
  B.box(-2.4, fy + H + 0.3, -2.4, 2.4, fy + H + 3.4, 2.4, MAT.planks);
  B.pyramid(0, 0, 3.0, fy + H + 3.4, fy + H + 5.6, MAT.iron);
  return { w: 5, d: 5, loot: [[...B.W(0, 0), B.oy + fy]], type: 'tower', door: B.W(0, 2.8), top: 0 };
}

export function kiosk(B, rnd) {
  const W = 6.5, D = 5, H = 2.9, t = 0.2, fy = 0.12;
  const x0 = -W / 2, x1 = W / 2, z0 = -D / 2, z1 = D / 2;
  foundation(B, x0, x1, z0, z1, 1);
  B.tint = 140;
  B.wall(x0, x1, z1 - t / 2, t, fy, fy + H, MAT.brick, [{ x0: -0.55, x1: 0.55, y0: fy, y1: fy + 2.2 }, { x0: 1.4, x1: 2.9, y0: fy + 0.9, y1: fy + 2.2 }, { x0: -2.9, x1: -1.4, y0: fy + 0.9, y1: fy + 2.2 }]);
  B.wall(x0, x1, z0 + t / 2, t, fy, fy + H, MAT.brick, []);
  B.wallZ(z0 + t, z1 - t, x0 + t / 2, t, fy, fy + H, MAT.brick, []);
  B.wallZ(z0 + t, z1 - t, x1 - t / 2, t, fy, fy + H, MAT.brick, [{ x0: -0.5, x1: 0.5, y0: fy + 0.9, y1: fy + 2 }]);
  B.box(x0 + t, fy - 0.1, z0 + t, x1 - t, fy + 0.04, z1 - t, MAT.concrete, { walk: true, faces: 4 });
  B.box(x0 - 0.4, fy + H, z0 - 0.4, x1 + 0.4, fy + H + 0.3, z1 + 0.8, MAT.concrete, { surf: SURF.STONE });
  for (let i = 0; i < 3; i++) B.box(x0 + 0.5, fy, -1.6 + i * 1.3, x0 + 1.1, fy + 1.5, -0.8 + i * 1.3, MAT.metal, { surf: SURF.METAL });
  B.box(-1.5, fy, z1 - 1.5, 1.5, fy + 1.0, z1 - 0.9, MAT.darkwood);
  return { w: W + 1, d: D + 2, loot: [[...B.W(x0 + 0.8, -1.2), B.oy + fy + 1.5], [...B.W(-1, z1 - 1.2), B.oy + fy + 1.0], [...B.W(2, 0), B.oy + fy]], type: 'shop', door: B.W(0, z1 + 1.5), top: fy + H + 0.5 };
}

export function warehouse(B, rnd) {
  const W = 16, D = 10, H = 5, t = 0.2, fy = 0.12;
  const x0 = -W / 2, x1 = W / 2, z0 = -D / 2, z1 = D / 2;
  foundation(B, x0, x1, z0, z1, 1.2);
  B.tint = 110;
  B.wall(x0, x1, z1 - t / 2, t, fy, fy + H, MAT.iron, [{ x0: -2, x1: 2, y0: fy, y1: fy + 3.6 }]);
  B.wall(x0, x1, z0 + t / 2, t, fy, fy + H, MAT.iron, [{ x0: 5, x1: 6, y0: fy, y1: fy + 2.2 }]);
  B.wallZ(z0 + t, z1 - t, x0 + t / 2, t, fy, fy + H, MAT.iron, [{ x0: -0.5, x1: 0.5, y0: fy + 2.5, y1: fy + 3.6 }]);
  B.wallZ(z0 + t, z1 - t, x1 - t / 2, t, fy, fy + H, MAT.iron, []);
  B.box(x0 + t, fy - 0.1, z0 + t, x1 - t, fy + 0.04, z1 - t, MAT.concrete, { walk: true, faces: 4 });
  B.gable(x0, x1, z0, z1, fy + H, 2.2, MAT.iron, 0.4, { gableLayer: MAT.iron });
  const loot = [];
  for (let i = 0; i < 6; i++) { const a = -6 + i * 2.3; B.box(a, fy, -3.6, a + 1.4, fy + 1.1, -2.2, MAT.metal, { surf: SURF.METAL }); loot.push([a + 0.7, fy + 1.1, -2.9]); }
  return { w: W + 1, d: D + 1, loot: loot.map(([a, y, b]) => [...B.W(a, b), B.oy + y]), type: 'warehouse', door: B.W(0, z1 + 1.5), top: fy + H + 2.4 };
}

// cerca de madeira: segmento reto em coordenadas de mundo
export function fence(B, x0, z0, x1, z1, y0fn, rnd) {
  const L = Math.hypot(x1 - x0, z1 - z0), n = Math.max(1, Math.round(L / 2.4));
  const yaw = Math.atan2(-(z1 - z0), (x1 - x0));
  for (let i = 0; i < n; i++) {
    const a = i / n, b = (i + 1) / n;
    const xa = x0 + (x1 - x0) * a, za = z0 + (z1 - z0) * a, xb = x0 + (x1 - x0) * b, zb = z0 + (z1 - z0) * b;
    const xm = (xa + xb) / 2, zm = (za + zb) / 2, ym = y0fn(xm, zm);
    if (rnd() < 0.12) continue; // vão
    const segL = L / n;
    B.mb.p.length;
    B.obox(xa, y0fn(xa, za) + 0.55, za, 0.06, 0.55, 0.06, yaw, MAT.darkwood, { ao: 255, tint: 128, uvScale: 1 });
    B.obox(xm, ym + 0.55, zm, segL / 2, 0.45, 0.025, yaw, MAT.planks, { tint: 120 + (rnd() * 50 | 0), uvScale: 0.8 });
    B.cols.push({ cx: xm, cy: ym + 0.55, cz: zm, hx: segL / 2, hy: 0.55, hz: 0.06, yaw, surf: SURF.WOOD, walk: false });
  }
}

// ------------------------------------------------------------------ veículo procedural (carro velho)
export function carMesh(color = 0) {
  const b = new MeshBuilder();
  const L = layerCar;
  const box = (x0, y0, z0, x1, y1, z1, layer = MAT.metal, o = {}) => b.box(x0, y0, z0, x1, y1, z1, layer, { uvScale: 0.5, ...o });
  // carroceria (z = frente +)
  box(-0.82, 0.38, -2.15, 0.82, 0.95, 2.15);            // base
  box(-0.78, 0.95, -0.9, 0.78, 1.5, 1.35);              // cabine
  box(-0.84, 0.35, 1.95, 0.84, 0.75, 2.2);              // para-choque frente
  box(-0.84, 0.35, -2.2, 0.84, 0.75, -1.95);            // traseiro
  box(-0.8, 0.8, 1.35, 0.8, 0.98, 2.1);                 // capô
  box(-0.8, 0.8, -2.1, 0.8, 0.98, -0.9);                // porta-malas
  return b;
}
const layerCar = MAT.metal;
