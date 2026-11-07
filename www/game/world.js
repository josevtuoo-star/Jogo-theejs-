// Conteúdo do mundo: vilas, estradas, ponte, postes, props, carros, loot, área de testes.
import { MeshBuilder, InstanceBuffer } from '../engine/gl.js';
import { Material } from '../engine/renderer.js';
import { m4, q4, mulberry32, hash2, clamp, lerp, smoothstep } from '../engine/math.js';
import { SURF } from '../engine/physics.js';
import { WORLD } from './worldgen.js';
import { MAT } from './assets.js';
import * as B from './buildings.js';
import { ITEMS, makeItem, LOOT, rollLoot } from './items.js';
import { makeCarMeshes } from './vehicle.js';

const FOOT = { house: [11, 9], apartment: [19, 11], barn: [15, 10], shed: [5, 4.5], church: [11, 22], tower: [6, 6], kiosk: [7.5, 6.5], warehouse: [17, 11] };
const FN = { house: B.house, apartment: B.apartment, barn: B.barn, shed: B.shed, church: B.church, tower: B.waterTower, kiosk: B.kiosk, warehouse: B.warehouse };

export class Level {
  constructor(game) {
    this.g = game;
    this.gl = game.r.gl;
    this.W = game.world;
    this.phys = game.phys;
    this.rnd = mulberry32(2024);
    this.statics = [];      // {mesh, mat, cx,cz,r}
    this.buildings = [];    // {type,x,z,yaw,w,d,loot[],door}
    this.footprints = [];   // [{x,z,r}] para excluir vegetação
    this.loot = [];         // itens no chão
    this.props = [];        // props estáticos instanciados
    this.dynProps = [];     // corpos rígidos com visual
    this.targets = [];
    this.cars = [];
    this.modelCache = {};
    this.matBuilding = new Material({ layered: true, rough: 1, normalScale: 0.9, vcolorAO: false, name: 'building' });
    this.matRoad = new Material({ layered: true, rough: 1, normalScale: 0.8, vcolorAO: false, name: 'road' });
    this.matRoad.decal = true;
    this.lineYellow = new Material({ color: [0.62, 0.5, 0.12, 1], rough: 0.8, vcolorAO: false, name: 'lineY' }); this.lineYellow.decal = true;
    this.lineWhite = new Material({ color: [0.7, 0.7, 0.68, 1], rough: 0.8, vcolorAO: false, name: 'lineW' }); this.lineWhite.decal = true;
    this.matPole = new Material({ layered: true, rough: 1, vcolorAO: false, name: 'pole' });
    this.matSolid = (c, r = 0.7, m = 0) => new Material({ color: c, rough: r, metal: m, vcolorAO: false });
  }

  exclude(x, z, margin = 0) {
    for (const f of this.footprints) { if (Math.abs(x - f.x) < f.r + margin && Math.abs(z - f.z) < f.r + margin && Math.hypot(x - f.x, z - f.z) < f.r + margin) return true; }
    return false;
  }

  model(name, node = null, withBend = false) {
    const key = name + '|' + node;
    if (this.modelCache[key]) return this.modelCache[key];
    const m = this.g.assets.models[name];
    if (!m) return null;
    const parts = m.bake(this.gl, node, null, true, withBend);
    let mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
    for (const p of parts) { for (let i = 0; i < 3; i++) { mn[i] = Math.min(mn[i], p.mesh.min[i]); mx[i] = Math.max(mx[i], p.mesh.max[i]); } }
    return (this.modelCache[key] = { parts, min: mn, max: mx, size: [mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]], center: [(mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2] });
  }

  // ------------------------------------------------------------------ construção
  build(progress = () => {}) {
    const W = this.W, g = this.g;
    progress('Vilas e construções', 0.0);
    for (const t of W.towns) this.buildTown(t);
    progress('Estradas', 0.35);
    this.buildRoads();
    progress('Ponte', 0.5);
    this.buildBridges();
    progress('Postes e fios', 0.55);
    this.buildPoles();
    progress('Veículos e props', 0.65);
    this.buildWrecks();
    this.buildProps();
    progress('Base militar e polígono', 0.8);
    this.buildMilitary();
    this.buildRange();
    progress('Itens', 0.9);
    this.spawnLoot();
    progress('Pronto', 1);
  }

  // ---------- vilas
  buildTown(t) {
    const W = this.W, rnd = mulberry32(Math.floor(t.x * 31 + t.z));
    const b = new B.Build();
    const placed = [];
    const roadPts = [];
    for (const rd of W.roads) {
      const pts = rd.pts;
      for (let i = 2; i < pts.length - 2; i += 3) {
        const p = pts[i]; if (p[3]) continue;
        if (Math.hypot(p[0] - t.x, p[1] - t.z) > t.r * 1.15) continue;
        const a = pts[i - 2], c = pts[i + 2];
        let dx = c[0] - a[0], dz = c[1] - a[1]; const l = Math.hypot(dx, dz) || 1; dx /= l; dz /= l;
        roadPts.push({ x: p[0], z: p[1], dx, dz, hw: rd.width / 2 });
      }
    }
    // embaralha
    for (let i = roadPts.length - 1; i > 0; i--) { const j = (rnd() * (i + 1)) | 0; [roadPts[i], roadPts[j]] = [roadPts[j], roadPts[i]]; }
    const plan = { town: ['church', 'tower', 'kiosk', 'apartment', 'apartment', 'apartment', 'warehouse', ...Array(13).fill('house'), 'shed', 'shed', 'shed', 'house', 'house'], village: ['kiosk', 'house', 'house', 'house', 'house', 'house', 'house', 'shed', 'shed', 'barn', 'house'], farm: ['barn', 'barn', 'house', 'house', 'shed', 'shed', 'house'], outpost: ['warehouse', 'shed', 'shed', 'house', 'shed'] }[t.kind];
    let pi = 0, tries = 0;
    for (const rp of roadPts) {
      if (pi >= plan.length || tries++ > 400) break;
      for (const side of [1, -1]) {
        if (pi >= plan.length) break;
        const type = plan[pi];
        const [fw, fd] = FOOT[type];
        const rad = Math.hypot(fw, fd) / 2;
        const nx = -rp.dz * side, nz = rp.dx * side;
        const off = rp.hw + fd / 2 + 4.5 + rnd() * 4;
        const cx = rp.x + nx * off, cz = rp.z + nz * off;
        if (Math.hypot(cx - t.x, cz - t.z) > t.r * 1.2) continue;
        let ok = true;
        for (const q of placed) if (Math.hypot(cx - q.x, cz - q.z) < rad + q.r + 3.5) { ok = false; break; }
        if (!ok) continue;
        // não colocar sobre estradas/água/inclinações
        if (W.heightAt(cx, cz) < WORLD.waterY + 1.5) continue;
        const hs = [[-fw / 2, -fd / 2], [fw / 2, -fd / 2], [-fw / 2, fd / 2], [fw / 2, fd / 2]].map(([a, c]) => W.heightAt(cx + a, cz + c));
        if (Math.max(...hs) - Math.min(...hs) > 2.2) continue;
        const rr = W.roadIdx.nearest(cx, cz, 30);
        if (rr && rr.d < rr.poly.width / 2 + fd / 2 + 1) continue;
        const f = [-nx, -nz];
        const yaw = Math.atan2(f[0], f[1]);
        const y0 = Math.max(...hs);
        b.at(cx, y0, cz, yaw);
        b.uvo = [rnd() * 5, rnd() * 5];
        const res = FN[type](b, rnd, {});
        res.x = cx; res.z = cz; res.yaw = yaw; res.y = y0;
        this.buildings.push(res);
        placed.push({ x: cx, z: cz, r: rad });
        this.footprints.push({ x: cx, z: cz, r: rad + 1.5 });
        // cerca ao redor de algumas casas
        if (type === 'house' && rnd() < 0.5) {
          const hw = fw / 2 + 5, hd = fd / 2 + 5, c = Math.cos(yaw), s = Math.sin(yaw);
          const corner = (lx, lz) => [cx + lx * c + lz * s, cz - lx * s + lz * c];
          const A = corner(-hw, -hd), Bc = corner(hw, -hd), C = corner(hw, hd), D = corner(-hw, hd);
          const hf = (x, z) => W.heightAt(x, z);
          B.fence(b, A[0], A[1], Bc[0], Bc[1], hf, rnd); B.fence(b, Bc[0], Bc[1], C[0], C[1], hf, rnd); B.fence(b, A[0], A[1], D[0], D[1], hf, rnd);
          const mid = corner(0, hd);
          const g1 = corner(-hw, hd), g2 = corner(-2.0, hd), g3 = corner(2.0, hd), g4 = corner(hw, hd);
          B.fence(b, g1[0], g1[1], g2[0], g2[1], hf, rnd); B.fence(b, g3[0], g3[1], g4[0], g4[1], hf, rnd);
        }
        pi++;
      }
    }
    // coloca no mundo: mesh + colisores
    const mesh = b.mb.build(this.gl);
    this.statics.push({ mesh, mat: this.matBuilding, cx: t.x, cz: t.z, r: t.r * 1.5, y: t.h });
    for (const c of b.cols) {
      if (c.kind === 1) this.phys.addCyl(c.cx, c.cz, c.r, c.y0, c.y1, c.surf);
      else this.phys.addBox(c.cx, c.cy, c.cz, c.hx, c.hy, c.hz, c.yaw, c.surf, { walk: c.walk, noBullet: c.noBullet, ghost: c.ghost });
    }
    // props urbanos ao longo das ruas
    for (let i = 0; i < roadPts.length; i += 3) {
      const rp = roadPts[i], side = rnd() < 0.5 ? 1 : -1;
      const nx = -rp.dz * side, nz = rp.dx * side;
      const x = rp.x + nx * (rp.hw + 2.2), z = rp.z + nz * (rp.hw + 2.2);
      if (this.exclude(x, z, 1)) continue;
      const r = rnd();
      if (t.kind === 'town' && r < 0.3) this.addProp('street_lamp_01', x, z, Math.atan2(nx, nz) + Math.PI, 1, { cyl: 0.12 });
      else if (r < 0.4) this.addProp('fire_hydrant', x, z, rnd() * 6.28, 1, { cyl: 0.2 });
      else if (r < 0.55) this.addProp('metal_trash_can', x, z, rnd() * 6.28, 1, { cyl: 0.28 });
      else if (r < 0.62) this.addProp('utility_box_01', x, z, Math.atan2(nx, nz), 1, { box: true });
      else if (r < 0.72) this.addProp('wooden_picnic_table', x + nx * 3, z + nz * 3, rnd() * 6.28, 1, { box: true });
      else if (r < 0.8) this.addProp('painted_wooden_bench', x, z, Math.atan2(-nx, -nz), 1, { box: true });
      else if (r < 0.88) this.addDyn('wooden_crate_01', x + nx * 2, z + nz * 2, rnd() * 6.28);
      else if (r < 0.96) this.addDyn('barrel_03', x + nx * 2, z + nz * 2, rnd() * 6.28);
    }
  }

  // ---------- estradas
  buildRoads() {
    const W = this.W, gl = this.gl;
    const mb = new MeshBuilder(), yl = new MeshBuilder(), wl = new MeshBuilder();
    for (const rd of W.roads) {
      if (rd.type !== 'asphalt') continue;
      const pts = rd.pts, hw = rd.width / 2;
      let dist = 0;
      const rows = [];
      for (let i = 0; i < pts.length; i++) {
        const a = pts[Math.max(i - 1, 0)], c = pts[Math.min(i + 1, pts.length - 1)];
        let dx = c[0] - a[0], dz = c[1] - a[1]; const l = Math.hypot(dx, dz) || 1; dx /= l; dz /= l;
        if (i > 0) dist += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]);
        rows.push({ x: pts[i][0], z: pts[i][1], y: pts[i][2] + 0.04, nx: -dz, nz: dx, d: dist, bridge: pts[i][3] });
      }
      const first = mb.vcount;
      rows.forEach((r) => {
        mb.vert(r.x + r.nx * hw, r.y, r.z + r.nz * hw, 0, 1, 0, 0, r.d / 3.5, 255, MAT.asphalt, 128, 0);
        mb.vert(r.x - r.nx * hw, r.y, r.z - r.nz * hw, 0, 1, 0, rd.width / 3.5, r.d / 3.5, 255, MAT.asphalt, 128, 0);
      });
      for (let i = 0; i < rows.length - 1; i++) { const k = first + i * 2; mb.quad(k, k + 1, k + 3, k + 2); }
      // faixa central tracejada e laterais
      const ln = (bld, off, w, fromD, toD) => {
        const f = bld.vcount; let n = 0;
        for (let i = 0; i < rows.length; i++) {
          const r = rows[i]; if (r.d < fromD || r.d > toD) continue;
          bld.vert(r.x + r.nx * (off + w), r.y + 0.012, r.z + r.nz * (off + w), 0, 1, 0, 0, 0, 255, 0, 128, 0);
          bld.vert(r.x + r.nx * (off - w), r.y + 0.012, r.z + r.nz * (off - w), 0, 1, 0, 1, 0, 255, 0, 128, 0);
          if (n > 0) { const k = f + (n - 1) * 2; bld.quad(k, k + 1, k + 3, k + 2); }
          n++;
        }
      };
      const total = dist;
      for (let s = 3; s < total - 6; s += 9) ln(yl, 0, 0.09, s, s + 4.2);
      ln(wl, hw - 0.4, 0.07, 0, total); ln(wl, -(hw - 0.4), 0.07, 0, total);
    }
    this.statics.push({ mesh: mb.build(gl), mat: this.matRoad, cx: 1000, cz: 1000, r: 1800, y: 0, noShadow: true, road: true });
    this.statics.push({ mesh: yl.build(gl), mat: this.lineYellow, cx: 1000, cz: 1000, r: 1800, y: 0, noShadow: true });
    this.statics.push({ mesh: wl.build(gl), mat: this.lineWhite, cx: 1000, cz: 1000, r: 1800, y: 0, noShadow: true });
  }

  buildBridges() {
    const W = this.W, b = new B.Build();
    for (const br of W.bridges) {
      const pts = br.road.pts, hw = br.road.width / 2;
      for (let i = br.a; i < br.b; i++) {
        const p = pts[i], q = pts[i + 1];
        const dx = q[0] - p[0], dz = q[1] - p[1], L = Math.hypot(dx, dz) || 1;
        const yaw = Math.atan2(-dz, dx);
        const cx = (p[0] + q[0]) / 2, cz = (p[1] + q[1]) / 2, y = (p[2] + q[2]) / 2;
        // tabuleiro + guarda-corpos
        b.obox(cx, y - 0.3, cz, L / 2 + 0.05, 0.28, hw + 0.6, yaw, MAT.concrete, { uvScale: 0.5 });
        b.cols.push({ cx, cy: y - 0.3, cz, hx: L / 2 + 0.05, hy: 0.28, hz: hw + 0.6, yaw, surf: SURF.STONE, walk: true });
        for (const s of [-1, 1]) {
          const ox = -Math.sin(yaw) * 0, rx = Math.sin(yaw) * s * (hw + 0.45), rz = Math.cos(yaw) * s * (hw + 0.45);
          b.obox(cx + rx, y + 0.45, cz + rz, L / 2 + 0.05, 0.5, 0.15, yaw, MAT.concrete, { uvScale: 0.5 });
          b.cols.push({ cx: cx + rx, cy: y + 0.45, cz: cz + rz, hx: L / 2 + 0.05, hy: 0.5, hz: 0.15, yaw, surf: SURF.STONE });
        }
      }
      // encontros nas cabeceiras
      for (const idx of [br.a, br.b]) {
        const p = pts[idx], gy = W.heightAt(p[0], p[1]);
        const n = pts[Math.min(idx + 1, pts.length - 1)], m = pts[Math.max(idx - 1, 0)];
        const yaw = Math.atan2(-(n[1] - m[1]), n[0] - m[0]);
        const hgt = Math.max(0.6, p[2] - gy + 1.2);
        b.obox(p[0], p[2] - 0.55 - hgt / 2 + 0.3, p[1], 1.2, hgt / 2, hw + 0.6, yaw, MAT.concrete, { uvScale: 0.5 });
      }
    }
    if (b.mb.vcount) {
      this.statics.push({ mesh: b.mb.build(this.gl), mat: this.matBuilding, cx: 1000, cz: 1000, r: 2000, y: 0 });
      for (const c of b.cols) this.phys.addBox(c.cx, c.cy, c.cz, c.hx, c.hy, c.hz, c.yaw, c.surf, { walk: c.walk });
    }
  }

  // ---------- postes e fios
  buildPoles() {
    const W = this.W, gl = this.gl;
    const pm = new MeshBuilder();
    pm.cylinder(0, 0, 0, 0.17, 0.11, 9.2, 8, MAT.darkwood, { uvScale: 0.5, bend0: 0, bend1: 0 });
    pm.box(-1.1, 8.55, -0.07, 1.1, 8.7, 0.07, MAT.darkwood, { uvScale: 0.5 });
    for (const x of [-0.9, 0, 0.9]) pm.cylinder(x, 8.7, 0, 0.04, 0.03, 0.14, 5, MAT.metal, {});
    this.poleMesh = pm.build(gl);
    const inst = [], lineVerts = [];
    const colors = [0.05, 0.05, 0.06, 1];
    for (const rd of W.roads) {
      if (rd.type !== 'asphalt') continue;
      const pts = rd.pts, hw = rd.width / 2;
      let acc = 0, prev = null, last = null;
      for (let i = 1; i < pts.length - 1; i++) {
        acc += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]);
        if (acc < 42) continue; acc = 0;
        if (pts[i][3]) { prev = null; continue; }
        const a = pts[i - 1], c = pts[i + 1];
        let dx = c[0] - a[0], dz = c[1] - a[1]; const l = Math.hypot(dx, dz) || 1; dx /= l; dz /= l;
        const nx = -dz, nz = dx;
        const x = pts[i][0] + nx * (hw + 4.2), z = pts[i][1] + nz * (hw + 4.2);
        if (W.heightAt(x, z) < WORLD.waterY + 1) { prev = null; continue; }
        if (W.riverIdx.nearest(x, z, 20) && W.riverIdx.nearest(x, z, 20).d < 12) { prev = null; continue; }
        const y = W.heightAt(x, z);
        const yaw = Math.atan2(-dz, dx) ; // braço do poste perpendicular à estrada
        const m = m4.create(); m4.rotationY(m, yaw + Math.PI / 2 * 0); m[12] = x; m[13] = y - 0.1; m[14] = z;
        const arr = new Float32Array(20); arr.set(m); arr[16] = arr[17] = arr[18] = arr[19] = 0;
        inst.push(...arr);
        this.phys.addCyl(x, z, 0.2, y, y + 9, SURF.WOOD);
        // pontas dos isoladores no espaço do mundo (braço ao longo do eixo x local do poste, após rotação yaw)
        const ex = [Math.cos(yaw), -Math.sin(yaw)];
        const top = [0, 0.9, -0.9].map((o) => [x + ex[0] * o, y + 8.85, z + ex[1] * o]);
        if (prev) {
          for (let k = 0; k < 3; k++) {
            const A = prev[k], Bp = top[k], segs = 7, sag = 0.9;
            for (let s = 0; s < segs; s++) {
              const t0 = s / segs, t1 = (s + 1) / segs;
              const P = (t) => [lerp(A[0], Bp[0], t), lerp(A[1], Bp[1], t) - sag * 4 * t * (1 - t), lerp(A[2], Bp[2], t)];
              lineVerts.push(...P(t0), ...colors, ...P(t1), ...colors);
            }
          }
        }
        prev = top;
      }
    }
    this.poleInst = inst.length ? new InstanceBuffer(gl, new Float32Array(inst), 1) : null;
    this.poleCount = inst.length / 20;
    // linhas estáticas
    if (lineVerts.length) {
      const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(lineVerts), gl.STATIC_DRAW);
      const vao = gl.createVertexArray(); gl.bindVertexArray(vao);
      gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 28, 0);
      gl.enableVertexAttribArray(3); gl.vertexAttribPointer(3, 4, gl.FLOAT, false, 28, 12);
      gl.bindVertexArray(null);
      this.wires = { vao, n: lineVerts.length / 7 };
    }
  }

  // ---------- props (modelos CC0)
  addProp(name, x, z, yaw, scale = 1, o = {}) {
    const m = this.model(name); if (!m) return;
    const y = this.W.heightAt(x, z);
    const mat = m4.create(); m4.rotationY(mat, yaw);
    mat[0] *= scale; mat[1] *= scale; mat[2] *= scale; mat[4] *= scale; mat[5] *= scale; mat[6] *= scale; mat[8] *= scale; mat[9] *= scale; mat[10] *= scale;
    mat[12] = x; mat[13] = y - 0.02; mat[14] = z;
    let list = this.props.find((p) => p.name === name);
    if (!list) this.props.push((list = { name, model: m, data: [], inst: null }));
    const arr = new Float32Array(20); arr.set(mat); list.data.push(...arr);
    this.footprints.push({ x, z, r: 0.8 });
    if (o.cyl) this.phys.addCyl(x, z, o.cyl * scale, y, y + m.size[1] * scale, SURF.METAL);
    else if (o.box) { const sx = m.size[0] * scale / 2, sz = m.size[2] * scale / 2; this.phys.addBox(x, y + m.size[1] * scale / 2, z, sx, m.size[1] * scale / 2, sz, yaw, SURF.WOOD); }
  }
  finishProps() {
    for (const p of this.props) p.inst = new InstanceBuffer(this.gl, new Float32Array(p.data), 1);
  }
  buildProps() {
    const W = this.W, rnd = mulberry32(77);
    // alguns troncos caídos e pneus pelas estradas / campos
    for (const rd of W.roads) {
      for (let i = 20; i < rd.pts.length - 20; i += 30) {
        const p = rd.pts[i]; if (p[3] || rnd() > 0.28) continue;
        const a = rd.pts[i - 1], c = rd.pts[i + 1]; const l = Math.hypot(c[0] - a[0], c[1] - a[1]) || 1;
        const nx = -(c[1] - a[1]) / l, nz = (c[0] - a[0]) / l, side = rnd() < 0.5 ? 1 : -1;
        const x = p[0] + nx * side * (rd.width / 2 + 2.5 + rnd() * 2), z = p[1] + nz * side * (rd.width / 2 + 2.5 + rnd() * 2);
        if (W.heightAt(x, z) < WORLD.waterY + 1 || this.exclude(x, z, 1)) continue;
        const r = rnd();
        if (r < 0.35) this.addDyn('old_tyre', x, z, rnd() * 6.28);
        else if (r < 0.65) this.addDyn('barrel_03', x, z, rnd() * 6.28);
        else if (r < 0.85) this.addDyn('cardboard_box_01', x, z, rnd() * 6.28);
        else this.addDyn('wooden_crate_01', x, z, rnd() * 6.28);
      }
    }
    this.finishProps();
  }

  // corpos rígidos com visual
  addDyn(name, x, z, yaw, o = {}) {
    const m = this.model(name); if (!m) return null;
    const sc = o.scale ?? 1;
    const hx = m.size[0] / 2 * sc, hy = m.size[1] / 2 * sc, hz = m.size[2] / 2 * sc;
    const y = (o.y ?? this.W.heightAt(x, z)) + hy + 0.02;
    const mass = o.mass ?? Math.max(0.5, hx * hy * hz * 8 * 220);
    const q = q4.fromEuler(new Float32Array(4), yaw, 0, 0);
    const body = this.phys.addBody({ shape: 'box', half: [hx, hy, hz], mass, pos: [x, y, z], q, rest: 0.3, fric: 0.55, surf: name.includes('barrel') || name.includes('trash') ? SURF.METAL : SURF.WOOD });
    body.asleep = true; body.sleep = 1;
    const dp = { body, model: m, scale: sc, name, mat: m4.create() };
    this.dynProps.push(dp);
    return dp;
  }

  // ---------- carros abandonados
  buildWrecks() {
    const W = this.W, rnd = mulberry32(31);
    const meshes = makeCarMeshes(this.gl);
    this.carBody = meshes.body; this.carGlass = meshes.glass; this.carWheel = meshes.wheel;
    this.carMats = [[0.45, 0.07, 0.05], [0.1, 0.2, 0.26], [0.6, 0.55, 0.42], [0.06, 0.06, 0.07], [0.22, 0.3, 0.12], [0.4, 0.4, 0.42]].map((c) => new Material({ rough: 0.5, metal: 0.35, color: [c[0], c[1], c[2], 1], vcolorAO: false, name: 'car' }));
    this.matGlass = new Material({ layered: true, rough: 0.12, metal: 0.0, color: [0.08, 0.1, 0.12, 1], vcolorAO: false });
    this.matWheel = new Material({ layered: true, rough: 0.95, vcolorAO: false, color: [0.14, 0.14, 0.14, 1] });
    this.carMatSet = { paint: this.carMats, glass: this.matGlass, wheel: this.matWheel };
    this.carMeshes = meshes;
    const spots = [];
    for (const rd of W.roads) for (let i = 30; i < rd.pts.length - 30; i += 38) {
      const p = rd.pts[i]; if (p[3] || rnd() > 0.35) continue;
      const a = rd.pts[i - 1], c = rd.pts[i + 1]; const l = Math.hypot(c[0] - a[0], c[1] - a[1]) || 1;
      const dx = (c[0] - a[0]) / l, dz = (c[1] - a[1]) / l, side = rnd() < 0.5 ? 1 : -1;
      const off = rd.width / 2 - 1.1 + rnd() * 1.4;
      const x = p[0] - dz * side * off, z = p[1] + dx * side * off;
      spots.push({ x, z, yaw: Math.atan2(dx, dz) + (rnd() < 0.5 ? 0 : Math.PI) + (rnd() - 0.5) * 0.25, mat: (rnd() * this.carMats.length) | 0 });
    }
    for (const t of W.towns) for (let k = 0; k < 3; k++) { const a = rnd() * 6.28, d = 20 + rnd() * t.r * 0.7, x = t.x + Math.cos(a) * d, z = t.z + Math.sin(a) * d; if (!this.exclude(x, z, 3)) spots.push({ x, z, yaw: rnd() * 6.28, mat: (rnd() * 6) | 0 }); }
    const groups = this.carMats.map(() => []), wheels = [];
    for (const s of spots) {
      if (this.exclude(s.x, s.z, 2.2)) continue;
      const c = Math.cos(s.yaw), sn = Math.sin(s.yaw);
      const y = Math.max(W.heightAt(s.x + 1.3, s.z), W.heightAt(s.x - 1.3, s.z), W.heightAt(s.x, s.z + 2), W.heightAt(s.x, s.z - 2));
      if (y < WORLD.waterY + 0.5) continue;
      const m = m4.create(); m4.rotationY(m, s.yaw); m[12] = s.x; m[13] = y - 0.05; m[14] = s.z;
      const arr = new Float32Array(20); arr.set(m); groups[s.mat].push(...arr);
      this.phys.addBox(s.x, y + 0.85, s.z, 0.88, 0.62, 2.15, s.yaw, SURF.METAL);
      this.footprints.push({ x: s.x, z: s.z, r: 2.5 });
      this.cars.push({ x: s.x, z: s.z, yaw: s.yaw, y });
      for (const [lx, lz] of [[0.86, 1.32], [-0.86, 1.32], [0.86, -1.3], [-0.86, -1.3]]) {
        const wm = m4.create(); m4.rotationY(wm, s.yaw);
        wm[12] = s.x + lx * c + lz * sn; wm[13] = y + 0.28; wm[14] = s.z - lx * sn + lz * c;
        const Rz = m4.fromTRS(m4.create(), [0, 0, 0], q4.axisAngle(new Float32Array(4), 0, 0, 1, Math.PI / 2 * (lx > 0 ? -1 : 1)), null);
        m4.multiply(wm, wm, Rz); m4.multiply(wm, wm, m4.translation(m4.create(), 0, -0.11, 0));
        const a2 = new Float32Array(20); a2.set(wm); wheels.push(...a2);
      }
    }
    this.carInst = groups.map((g) => (g.length ? new InstanceBuffer(this.gl, new Float32Array(g), 1) : null));
    this.wheelInst = wheels.length ? new InstanceBuffer(this.gl, new Float32Array(wheels), 1) : null;
    this.glassInst = this.carInst;
  }

  // ---------- base militar (loot melhor) e polígono de testes
  buildMilitary() {
    const W = this.W, b = new B.Build(), rnd = mulberry32(909);
    // base militar no canto sudeste: 3 galpões + torre de guarda
    const cx = 1280, cz = 1790;
    // aplaina a área (altura lida do terreno; apenas coloca construções onde há espaço)
    const y0 = W.heightAt(cx, cz);
    const spots = [[-22, -10, 0], [22, -12, 0.1], [0, 18, Math.PI], [-26, 16, 0.2]];
    this.milLoot = [];
    spots.forEach(([dx, dz, yaw], i) => {
      const x = cx + dx, z = cz + dz;
      const hs = [-8, 8].flatMap((a) => [-5, 5].map((c) => W.heightAt(x + a, z + c)));
      b.at(x, Math.max(...hs), z, yaw);
      const res = i < 3 ? B.warehouse(b, rnd) : B.shed(b, rnd);
      res.x = x; res.z = z; res.yaw = yaw; res.type = 'military';
      this.buildings.push(res);
      this.footprints.push({ x, z, r: 11 });
    });
    this.statics.push({ mesh: b.mb.build(this.gl), mat: this.matBuilding, cx, cz, r: 90, y: y0 });
    for (const c of b.cols) this.phys.addBox(c.cx, c.cy, c.cz, c.hx, c.hy, c.hz, c.yaw, c.surf, { walk: c.walk });
    for (let i = 0; i < 10; i++) this.addDyn(i % 2 ? 'old_military_crate' : 'barrel_03', cx + (rnd() - 0.5) * 60, cz + (rnd() - 0.5) * 50, rnd() * 6.28);
    // estrada de terra até a base já definida por trilhas; marca
    W.landmarks.push({ name: 'Base Militar', x: cx, z: cz });
  }

  buildRange() {
    const W = this.W, g = this.g, rnd = mulberry32(5);
    const sx = W.spawn.x, sz = W.spawn.z;
    // faixa de tiro orientada para +x a partir do spawn
    const dirs = [1, 0];
    this.range = { x: sx, z: sz };
    this.targetMat = new Material({ color: [0.75, 0.72, 0.1, 1], rough: 0.5, metal: 0.6, vcolorAO: false, doubleSided: true });
    this.targetMat2 = new Material({ color: [0.9, 0.9, 0.9, 1], rough: 0.6, metal: 0.2, vcolorAO: false, doubleSided: true });
    const pm = new MeshBuilder();
    pm.box(-0.35, 0, -0.02, 0.35, 0.9, 0.02, 0, { uvScale: 1 });
    this.targetMesh = pm.build(this.gl);
    const post = new MeshBuilder(); post.box(-0.04, 0, -0.04, 0.04, 1.4, 0.04, MAT.darkwood, { uvScale: 1 });
    this.targetPost = post.build(this.gl);
    // marcações de distância
    const dists = [25, 50, 100, 150, 200, 300];
    const baseY = (x, z) => W.heightAt(x, z);
    dists.forEach((d, i) => {
      const x = sx + 40 + d, z = sz + (i % 2 ? 3 : -3) * 1.5, y = baseY(x, z);
      this.targets.push({ x, z, y, d, hit: 0, angle: 0, down: false, t: 0, big: d >= 150 });
      this.phys.addBox(x, y + 0.9, z, 0.35 * (d >= 150 ? 1.6 : 1), 0.45 * (d >= 150 ? 1.6 : 1), 0.04, Math.PI / 2, SURF.METAL, { target: this.targets[this.targets.length - 1] });
    });
    // pirâmide de caixas + barris (física)
    const px = sx + 14, pz = sz - 16;
    for (let r = 0; r < 4; r++) for (let c = 0; c < 4 - r; c++) {
      const d = this.addDyn('wooden_crate_01', px + (c - (3 - r) / 2) * 0.62, pz, 0, { y: this.W.heightAt(px, pz) + r * 0.6 + 0.01 });
    }
    for (let i = 0; i < 6; i++) this.addDyn('barrel_03', px + 4 + (i % 3) * 0.75, pz - 3 + Math.floor(i / 3) * 0.75, rnd() * 6);
    for (let i = 0; i < 4; i++) this.addDyn('old_tyre', px - 4 + i * 0.5, pz + 3, rnd() * 6, { y: this.W.heightAt(px, pz) + i * 0.3 });
    for (let i = 0; i < 4; i++) this.addDyn('cardboard_box_01', px - 2, pz - 5 + i * 0.5, rnd() * 6, { y: this.W.heightAt(px, pz) + i * 0.4 });
    // degraus para testar subida (boxes walk)
    for (let i = 0; i < 6; i++) this.phys.addBox(sx - 12, W.heightAt(sx - 12, sz + 8) + 0.1 * (i + 1) * 2 + 0.0, sz + 8 + i * 0.5 - 1, 1.2, 0.1 * (i + 1) + 0.05, 0.25, 0, SURF.STONE, { walk: true });
    this.stairMesh = null;
    // paredes de teste (madeira / concreto / metal) para balística e atravessamento
    const wallsB = new B.Build(); wallsB.at(sx + 8, W.heightAt(sx + 8, sz + 12), sz + 12, 0);
    wallsB.box(-1.5, 0, -0.1, -0.1, 2.2, 0.1, MAT.planks, { surf: SURF.WOOD });
    wallsB.box(0.1, 0, -0.15, 1.5, 2.2, 0.15, MAT.concrete, { surf: SURF.STONE });
    wallsB.box(1.7, 0, -0.04, 3.1, 2.2, 0.04, MAT.metal, { surf: SURF.METAL });
    this.statics.push({ mesh: wallsB.mb.build(this.gl), mat: this.matBuilding, cx: sx + 9, cz: sz + 12, r: 8, y: 0 });
    for (const c of wallsB.cols) this.phys.addBox(c.cx, c.cy, c.cz, c.hx, c.hy, c.hz, c.yaw, c.surf);
    this.footprints.push({ x: sx + 30, z: sz, r: 60 });
    // carros jogáveis perto do spawn
    this.vehicleSpots = [{ x: sx - 8, z: sz - 6, yaw: 1.2 }, { x: sx - 8, z: sz - 11, yaw: 1.4 }];
    this.footprints.push({ x: sx - 8, z: sz - 8, r: 8 });
  }

  // ---------- loot
  spawnLoot() {
    const rnd = mulberry32(8080);
    const tableFor = (type) => LOOT[type] || LOOT.house;
    for (const b of this.buildings) {
      const tbl = tableFor(b.type);
      for (const [x, z, y] of b.loot) {
        if (rnd() > (b.type === 'military' ? 0.8 : 0.55)) continue;
        const [id, qty] = rollLoot(tbl, rnd);
        this.dropLootAt(id, qty, x, z, y);
      }
    }
    // galpões da base militar (muito loot bom)
    for (const b of this.buildings.filter((b) => b.type === 'military')) for (const [x, z, y] of b.loot) { const [id, qty] = rollLoot(LOOT.military, rnd); this.dropLootAt(id, qty, x, z, y); }
    // itens soltos pelo mapa
    for (let i = 0; i < 70; i++) {
      const x = 80 + rnd() * 1840, z = 80 + rnd() * 1840, h = this.W.heightAt(x, z);
      if (h < WORLD.waterY + 1) continue;
      const [id, qty] = rollLoot(LOOT.outside, rnd); this.dropLootAt(id, qty, x, z, h);
    }
    // kit de testes ao lado do spawn
    const sx = this.W.spawn.x, sz = this.W.spawn.z;
    const kit = ['mosin', 'ammo_762', 'm1911', 'ammo_45', 'grenade', 'hatchet', 'machete', 'crowbar', 'medkit', 'bandage', 'water', 'fish_can', 'milk_can', 'ration', 'flashlight', 'binoculars', 'backpack_big', 'vest', 'jacket', 'jeans', 'helmet', 'hat', 'gasmask', 'boots', 'jerrycan'];
    kit.forEach((id, i) => {
      const a = (i / kit.length) * 6.28, d = 3.2 + (i % 3) * 0.4;
      const x = sx + Math.cos(a) * d, z = sz + 2 + Math.sin(a) * d;
      this.dropLootAt(id, undefined, x, z, this.W.heightAt(x, z) + 0.0);
    });
  }
  itemVisual(id) {
    const d = ITEMS[id];
    if (d.model) {
      const m = this.model(d.model, d.node || null);
      if (m) return m;
    }
    return null;
  }
  dropLootAt(id, qty, x, z, y, extra = {}) {
    const item = extra.item || makeItem(id, qty);
    const e = { item, x, y, z, yaw: extra.yaw ?? this.rnd() * 6.28, body: extra.body || null, visual: this.itemVisual(item.id), tilt: 0 };
    // coloca deitado: o visual é "em pé" no eixo de maior dimensão? usa bbox para ficar no chão
    e.onGround = !e.body;
    this.loot.push(e);
    return e;
  }
  // item com corpo rígido (arremessado/derrubado pelo jogador)
  spawnItemBody(item, pos, vel) {
    const vis = this.itemVisual(item.id);
    const sz = vis ? vis.size : [0.15, 0.15, 0.15];
    const half = [Math.max(0.03, sz[0] / 2), Math.max(0.03, sz[1] / 2), Math.max(0.03, sz[2] / 2)];
    const body = this.phys.addBody({ shape: 'box', half, mass: Math.max(0.1, item.def.weight * (item.def.stack > 1 ? item.qty : 1)), pos: pos.slice(), vel, w: [(Math.random() - 0.5) * 6, (Math.random() - 0.5) * 6, (Math.random() - 0.5) * 6], rest: 0.25, fric: 0.6, q: q4.fromEuler(new Float32Array(4), Math.random() * 6, Math.random() * 0.5, Math.random() * 0.5) });
    const e = { item, x: pos[0], y: pos[1], z: pos[2], yaw: 0, body, visual: vis };
    this.loot.push(e);
    return e;
  }
  removeLoot(e) { const i = this.loot.indexOf(e); if (i >= 0) this.loot.splice(i, 1); if (e.body) this.phys.removeBody(e.body); }

  // ------------------------------------------------------------------ desenho
  draw(r, cam, shadowPass, game) {
    const f = r.frustum, I = m4.create();
    for (const s of this.statics) {
      if (shadowPass && s.noShadow) continue;
      if (!s.road && !f.sphere(s.cx, s.y + 6, s.cz, s.r)) continue;
      if (shadowPass && Math.hypot(cam[0] - s.cx, cam[2] - s.cz) > s.r + 330) continue;
      r.draw(s.mesh, s.mat, { model: I });
    }
    // postes
    if (this.poleInst && !shadowPass) r.draw(this.poleMesh, this.matPole, { inst: this.poleInst });
    // props instanciados
    for (const p of this.props) {
      if (!p.inst) continue;
      for (const part of p.model.parts) r.draw(part.mesh, part.material, { inst: p.inst });
    }
    // carros
    this.carInst && this.carInst.forEach((ib, i) => { if (ib) { r.draw(this.carBody, this.carMats[i], { inst: ib }); r.draw(this.carGlass, this.matGlass, { inst: ib }); } });
    if (this.wheelInst) r.draw(this.carWheel, this.matWheel, { inst: this.wheelInst });
    // corpos rígidos
    for (const dp of this.dynProps) {
      const b = dp.body; if (b.dead) continue;
      const dx = b.pos[0] - cam[0], dz = b.pos[2] - cam[2];
      if (dx * dx + dz * dz > (shadowPass ? 60 * 60 : 260 * 260)) continue;
      if (!f.sphere(b.pos[0], b.pos[1], b.pos[2], b.R + 0.3)) continue;
      const m = dp.mat; m4.fromTRS(m, b.pos, b.q, [dp.scale, dp.scale, dp.scale]);
      const c = dp.model.center, s = dp.scale;
      // desloca para que o centro do bbox coincida com o centro do corpo
      m[12] -= (m[0] * c[0] + m[4] * c[1] + m[8] * c[2]) * 1; m[13] -= (m[1] * c[0] + m[5] * c[1] + m[9] * c[2]); m[14] -= (m[2] * c[0] + m[6] * c[1] + m[10] * c[2]);
      for (const p of dp.model.parts) r.draw(p.mesh, p.material, { model: m });
    }
    // itens no chão
    const lm = m4.create();
    for (const e of this.loot) {
      if (!e.visual) continue;
      const dx = e.x - cam[0], dz = e.z - cam[2];
      if (dx * dx + dz * dz > (shadowPass ? 25 * 25 : 90 * 90)) continue;
      if (e.body) { m4.fromTRS(lm, e.body.pos, e.body.q, null); const c = e.visual.center; lm[12] -= (lm[0] * c[0] + lm[4] * c[1] + lm[8] * c[2]); lm[13] -= (lm[1] * c[0] + lm[5] * c[1] + lm[9] * c[2]); lm[14] -= (lm[2] * c[0] + lm[6] * c[1] + lm[10] * c[2]); }
      else this.lootMatrix(e, lm);
      for (const p of e.visual.parts) {
        let mat = p.material;
        const t = e.item.def.tint; if (t && e.item.def.model === 'ammo_box') mat = this._tinted(mat, t);
        r.draw(p.mesh, mat, { model: lm });
      }
    }
    // alvos
    for (const t of this.targets) this.drawTarget(r, t, shadowPass);
  }
  _tinted(mat, t) {
    if (!mat._tints) mat._tints = {}; const k = t.join();
    if (!mat._tints[k]) { const m = Object.assign(Object.create(Object.getPrototypeOf(mat)), mat); m.color = [t[0], t[1], t[2], 1]; mat._tints[k] = m; }
    return mat._tints[k];
  }
  lootMatrix(e, out) {
    // deita o objeto: o maior eixo fica horizontal. Usa rotação em Z/X conforme bbox.
    const v = e.visual, s = v.size;
    m4.identity(out);
    const stand = s[1] > Math.max(s[0], s[2]) * 1.3; // objeto alto (garrafa/lata): em pé
    const R = m4.create();
    if (!stand && s[1] < Math.max(s[0], s[2])) { m4.rotationY(R, e.yaw); }
    else if (stand) { m4.rotationY(R, e.yaw); }
    else m4.rotationY(R, e.yaw);
    out.set(R);
    out[12] = e.x; out[13] = e.y - v.min[1] * 1 + 0.005; out[14] = e.z;
    return out;
  }
  drawTarget(r, t, shadowPass) {
    const m = m4.create(), q = q4.axisAngle(new Float32Array(4), 1, 0, 0, t.angle);
    // chapa gira em torno da base (eixo x no pé)
    const sc = t.big ? 1.6 : 1;
    m4.fromTRS(m, [t.x, t.y + 0.5, t.z], q4.mul(new Float32Array(4), q4.axisAngle(new Float32Array(4), 0, 1, 0, Math.PI / 2), q4.axisAngle(new Float32Array(4), 1, 0, 0, t.angle)), [sc, sc, 1]);
    r.draw(this.targetMesh, t.big ? this.targetMat2 : this.targetMat, { model: m });
    const m2 = m4.create(); m4.fromTRS(m2, [t.x, t.y, t.z], q4.axisAngle(new Float32Array(4), 0, 1, 0, 0), null);
    r.draw(this.targetPost, this.matBuilding, { model: m2 });
  }
  update(dt) {
    for (const t of this.targets) {
      if (t.hit > 0) { t.t += dt; t.angle = Math.min(1.45, t.angle + dt * 10 * (t.t < 0.2 ? 1 : 0)); if (t.t > 3) { t.hit = 0; t.t = 0; } }
      else t.angle += (0 - t.angle) * Math.min(1, dt * 6);
    }
  }
  hitTarget(col) { const t = col.target; if (t) { t.hit = 1; t.t = 0; t.angle = 0.02; } }

  drawWires(r) {
    if (!this.wires) return;
    const gl = this.gl, p = r.use(this.g.particles.lineProg);
    p.f1('uUnlit', 0);
    r._cull(false); r._blend(false); r._depthWrite(true);
    gl.bindVertexArray(this.wires.vao);
    gl.drawArrays(gl.LINES, 0, this.wires.n);
  }
}
