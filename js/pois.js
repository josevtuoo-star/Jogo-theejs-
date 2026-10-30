import * as THREE from 'three';

// Lugares espalhados pelo mapa grande: vilas, fazenda, bloqueio militar, engavetamento,
// torre de rádio e cabanas na mata. Tudo feito com as peças do World (paredes com portas que
// abrem, caixas, carros, sacos de areia, contêineres, escadas) e com "pontos de saque" —
// armários, caixas, porta-malas e barracas que dá para revistar (F / USAR).

function rng(seed) {
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
}
const at = (cx, cz, rot) => (lx, lz) => [cx + lx * Math.cos(rot) + lz * Math.sin(rot), cz - lx * Math.sin(rot) + lz * Math.cos(rot)];

const LOOT_LABEL = { cabinet: 'REVISTAR O ARMÁRIO', crate: 'REVISTAR A CAIXA', car: 'REVISTAR O PORTA-MALAS', tent: 'REVISTAR A BARRACA', fridge: 'REVISTAR A GELADEIRA', locker: 'REVISTAR O ARMÁRIO MILITAR', bag: 'REVISTAR A MOCHILA' };

/** Ponto de saque: caixa invisível (para a mira) com o tipo e se já foi revistado. */
function loot(w, kind, x, y, z, size = [0.8, 1, 0.8]) {
  const hit = new THREE.Mesh(new THREE.BoxGeometry(...size), w.hitboxMat);
  hit.position.set(x, y + size[1] / 2, z);
  hit.updateMatrixWorld(true);
  const spot = { isLoot: true, kind, mesh: hit, center: hit.position, label: LOOT_LABEL[kind] ?? 'REVISTAR', searched: false };
  hit.userData.loot = spot;
  w.lootSpots.push(spot);
  w.scene.add(hit);
  return spot;
}

/** Triângulo da empena (fecha o telhado de duas águas). */
function gableGeo(halfDepth, h, thick) {
  const sh = new THREE.Shape();
  sh.moveTo(-halfDepth, 0); sh.lineTo(halfDepth, 0); sh.lineTo(0, h); sh.lineTo(-halfDepth, 0);
  const g = new THREE.ExtrudeGeometry(sh, { depth: thick, bevelEnabled: false });
  g.translate(0, 0, -thick / 2);
  g.rotateY(Math.PI / 2);
  return g;
}

/**
 * Casa: piso, quatro paredes (porta que abre na frente, janelas), telhado de duas águas com
 * empenas, móveis e pontos de saque. (cx, cz) centro, rot giro, y chão.
 */
function house(w, cx, cz, rot, y, R, { width = 8, depth = 6, height = 2.8, mat, roofMat, interior = 'home', doorAt = 0.5, big = false } = {}) {
  const M = w.mat, T = at(cx, cz, rot), hw = width / 2, hd = depth / 2;
  mat = mat ?? M.brick; roofMat = roofMat ?? M.roof;
  w.box(width, 0.2, depth, M.plank, cx, y + 0.1, cz, rot, 1.5);
  const base = y + 0.2;
  const win = (a) => ({ at: a, width: 1.1, bottom: 1.0, top: 2.0 });
  const door = big ? { at: width * doorAt, width: 3.6, bottom: 0, top: Math.min(height - 0.3, 3.2) } : { at: width * doorAt, width: 1.1, bottom: 0, top: 2.2, door: true };
  const frontOps = [door];
  if (!big) for (const a of [width * 0.2, width * 0.8]) if (Math.abs(a - door.at) > 1.6) frontOps.push(win(a));
  const wall = (lx1, lz1, lx2, lz2, ops) => { const [ax, az] = T(lx1, lz1), [bx, bz] = T(lx2, lz2); w.wall(ax, az, bx, bz, { height, base, mat, openings: ops, frames: !big }); };
  wall(-hw, hd, hw, hd, frontOps);
  wall(hw, -hd, -hw, -hd, big ? [] : [win(width * 0.3), win(width * 0.7)]);
  wall(-hw, -hd, -hw, hd, big ? [] : [win(depth * 0.5)]);
  wall(hw, hd, hw, -hd, big ? [] : [win(depth * 0.5)]);
  // telhado
  const a = big ? 0.42 : 0.5, over = 0.45;
  const run = hd + over, L = run / Math.cos(a), rise = hd * Math.tan(a);
  for (const s of [1, -1]) {
    const m = new THREE.Mesh(new THREE.BoxGeometry(width + 0.6, 0.14, L), roofMat);
    const [px, pz] = T(0, s * run / 2);
    m.position.set(px, base + height + rise - (run / 2) * Math.tan(a) + 0.12, pz);
    m.rotation.set(s * a, rot, 0, 'YXZ');
    w.solid(m);
  }
  for (const s of [-1, 1]) {
    const g = new THREE.Mesh(gableGeo(hd, rise, 0.22), mat);
    const [px, pz] = T(s * (hw - 0.11), 0);
    g.position.set(px, base + height, pz);
    g.rotation.y = rot;
    w.solid(g);
  }
  // sem grama dentro
  const c = [T(-hw - 1, -hd - 1), T(hw + 1, -hd - 1), T(-hw - 1, hd + 1), T(hw + 1, hd + 1)];
  w.noGrass.push([Math.min(...c.map((p) => p[0])), Math.min(...c.map((p) => p[1])), Math.max(...c.map((p) => p[0])), Math.max(...c.map((p) => p[1]))]);
  // móveis e saque
  const put = (lx, lz) => T(lx, lz);
  if (interior === 'home') {
    let [x, z] = put(-hw + 1.2, -hd + 0.5);
    w.box(0.7, 1.8, 0.45, M.wood, x, base + 0.9, z, rot, 1); loot(w, 'cabinet', x, base, z, [0.8, 1.8, 0.6]);
    [x, z] = put(0.6, -0.4);
    w.box(1.3, 0.06, 0.8, M.wood, x, base + 0.76, z, rot, 1);
    for (const [ox, oz] of [[-0.58, -0.34], [0.58, -0.34], [-0.58, 0.34], [0.58, 0.34]]) { const [lx, lz] = put(0.6 + ox, -0.4 + oz); w.box(0.06, 0.74, 0.06, M.wood, lx, base + 0.37, lz, rot, 1, false); }
    w.propSpots.push({ type: R() < 0.5 ? 'can' : 'bottle', x, y: base + 0.79, z });
    [x, z] = put(hw - 1.1, -hd + 1.3);
    w.box(0.95, 0.45, 1.95, M.fabric, x, base + 0.22, z, rot, 1);
    if (R() < 0.7) { [x, z] = put(hw - 0.6, hd - 0.7); w.box(0.65, 1.6, 0.6, M.paint, x, base + 0.8, z, rot, 1); loot(w, 'fridge', x, base, z, [0.75, 1.6, 0.7]); }
    if (R() < 0.6) { [x, z] = put(-hw + 0.8, hd - 0.8); w.box(0.6, 0.6, 0.6, M.wood, x, base + 0.3, z, rot + 0.3, 1); loot(w, 'crate', x, base, z, [0.7, 0.7, 0.7]); }
  } else if (interior === 'store') {
    for (let i = -1; i <= 1; i++) {
      const [x, z] = put(i * 2.2, -0.5);
      w.box(1.6, 1.5, 0.5, M.metal, x, base + 0.75, z, rot, 1);
      loot(w, 'cabinet', x, base, z, [1.7, 1.5, 0.7]);
    }
    const [x, z] = put(-hw + 1.4, hd - 1.2);
    w.box(2.2, 1.0, 0.7, M.wood, x, base + 0.5, z, rot, 1);
  } else if (interior === 'barn') {
    for (let i = 0; i < 5; i++) {
      const [x, z] = put((R() - 0.5) * (width - 3), (R() - 0.5) * (depth - 3));
      w.cylinder(0.6, 0.6, 1.1, M.sandbag, x, base + 0.6, z, { seg: 12, rz: Math.PI / 2, ry: R() * 3 });
    }
    const [x, z] = put(hw - 1.2, -hd + 1);
    w.box(0.8, 0.8, 0.8, M.wood, x, base + 0.4, z, rot, 1); loot(w, 'crate', x, base, z);
  } else if (interior === 'cabin') {
    const [x, z] = put(-hw + 0.8, -hd + 0.6);
    w.box(0.6, 0.6, 0.6, M.wood, x, base + 0.3, z, rot, 1); loot(w, 'crate', x, base, z, [0.7, 0.7, 0.7]);
    const [bx, bz] = put(hw - 0.7, 0);
    w.box(0.9, 0.4, 1.9, M.fabric, bx, base + 0.2, bz, rot + Math.PI / 2, 1);
  }
}

/** Torre de vigia com escada (bloqueio militar). */
function watchtower(w, cx, cz, y, top = 5.4) {
  const M = w.mat, half = 1.4;
  for (const dx of [-half, half]) for (const dz of [-half, half]) w.box(0.22, top + 2.6, 0.22, M.wood, cx + dx, y + (top + 2.6) / 2, cz + dz, 0, 1);
  w.box(3.4, 0.2, 3.4, M.plank, cx, y + top - 0.1, cz, 0, 1.5);
  const rail = { height: 1.0, base: y + top, thick: 0.08, mat: M.plank };
  w.wall(cx - 1.7, cz - 1.7, cx + 1.7, cz - 1.7, rail);
  w.wall(cx - 1.7, cz - 1.7, cx - 1.7, cz + 1.7, rail);
  w.wall(cx + 1.7, cz - 1.7, cx + 1.7, cz + 1.7, rail);
  w.wall(cx - 1.7, cz + 1.7, cx + 1.7, cz + 1.7, { ...rail, openings: [{ at: 1.7, width: 1.0, bottom: 0, top: 1.0 }] });
  w.box(4.2, 0.12, 4.2, M.rust, cx, y + top + 2.6, cz, 0, 2);
  w.ladder(cx, cz + 1.7 + 0.12, 0, 1, y, y + top);
  w.box(0.7, 0.5, 0.45, M.metal, cx - 1, y + top + 0.25, cz - 1.1, 0, 1);
  loot(w, 'locker', cx - 1, y + top, cz - 1.1, [0.8, 0.6, 0.6]);
}

function tent(w, x, z, rot, y, mat) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(0.01, 2.0, 1.9, 4, 1, true), mat);
  m.position.set(x, y + 0.95, z);
  m.rotation.y = rot + Math.PI / 4;
  m.scale.set(1, 1, 1.5);
  w.solid(m, false);
  w.invisibleCollider(new THREE.BoxGeometry(2.2, 1.2, 3.2), new THREE.Vector3(x, y + 0.6, z), new THREE.Euler(0, rot, 0));
  loot(w, 'tent', x, y, z, [2.4, 1.4, 3.4]);
}

export function buildPOIs(w, POIS) {
  const M = w.mat;
  const P = Object.fromEntries(POIS.map((p) => [p.kind + (p.kind === 'village' ? (p.x > 0 ? 'E' : 'W') : ''), p]));
  const gy = (x, z) => w.groundHeight(x, z);

  // ---------- vilas (casas dos dois lados da rua) ----------
  for (const [key, seed] of [['villageE', 11], ['villageW', 23]]) {
    const p = P[key], R = rng(seed), y = p.baseY;
    const along = new THREE.Vector2(1, 0); // a rua passa na direção X
    const n = key === 'villageE' ? 4 : 3;
    for (let i = 0; i < n; i++) for (const side of [-1, 1]) {
      const x = p.x + (i - (n - 1) / 2) * 15 + (R() - 0.5) * 2, z = p.z + side * 14;
      const store = i === 1 && side === 1;
      house(w, x, z, side > 0 ? Math.PI : 0, y, R, {
        width: store ? 11 : 8 + Math.round(R() * 2), depth: store ? 8 : 6 + Math.round(R()), height: store ? 3.2 : 2.8,
        mat: R() < 0.5 ? M.brick : M.paint, roofMat: R() < 0.5 ? M.roof : M.rust, interior: store ? 'store' : 'home', doorAt: 0.3 + R() * 0.4,
      });
    }
    // carros e entulho na rua
    for (let i = 0; i < 4; i++) {
      const x = p.x + (R() - 0.5) * 60, z = p.z + (R() - 0.5) * 5;
      w.car(x, z, along.angle() + (R() - 0.5) * 0.8 + (R() < 0.5 ? Math.PI : 0), { y, burnt: R() < 0.3, color: [0x5d6e76, 0x7a2a22, 0x2f4a36, 0xb8b0a0][i % 4], seed: seed + i });
      loot(w, 'car', x, y, z, [4.4, 1.4, 2]);
    }
    for (let i = 0; i < 6; i++) w.barrel(p.x + (R() - 0.5) * 70, p.z + (R() < 0.5 ? -7 : 7), R() < 0.5 ? M.barrel : M.rust, R() < 0.3, y);
    w.propSpots.push({ type: 'bucket', x: p.x + 3, y: y + 0.02, z: p.z + 6 }, { type: 'can', x: p.x - 8, y: y + 0.02, z: p.z - 6 });
  }

  // ---------- fazenda ----------
  {
    const p = P.farm, R = rng(5), y = p.baseY;
    house(w, p.x - 16, p.z + 14, -0.2, y, R, { width: 9, depth: 7, mat: M.paint, roofMat: M.roof });
    house(w, p.x + 16, p.z - 8, 0.15, y, R, { width: 14, depth: 10, height: 4.6, mat: M.plank, roofMat: M.rust, interior: 'barn', big: true, doorAt: 0.5 });
    w.cylinder(2.6, 2.6, 11, M.metal, p.x + 30, y + 5.5, p.z + 8, { seg: 18 });
    w.cylinder(2.7, 0.3, 1.6, M.rust, p.x + 30, y + 11.8, p.z + 8, { seg: 18 });
    // cercas
    for (let i = 0; i < 18; i++) {
      const a = (i / 18) * Math.PI * 2, x = p.x + Math.cos(a) * 40, z = p.z + Math.sin(a) * 36;
      if (Math.abs(a - 3.6) < 0.25) continue;
      w.box(0.12, 1.1, 0.12, M.wood, x, y + 0.55, z, 0, 1, false);
      const b = (i + 0.5) / 18 * Math.PI * 2, x2 = p.x + Math.cos(b) * 40, z2 = p.z + Math.sin(b) * 36;
      const nx = p.x + Math.cos((i + 1) / 18 * Math.PI * 2) * 40, nz = p.z + Math.sin((i + 1) / 18 * Math.PI * 2) * 36;
      w.box(Math.hypot(nx - x, nz - z), 0.1, 0.05, M.wood, x2, y + 0.85, z2, -Math.atan2(nz - z, nx - x), 1, false);
    }
    w.car(p.x - 2, p.z - 12, 0.8, { y, color: 0x7a2a22, seed: 9 }); loot(w, 'car', p.x - 2, y, p.z - 12, [4.4, 1.4, 2]);
    for (let i = 0; i < 8; i++) w.cylinder(0.65, 0.65, 1.2, M.sandbag, p.x + (R() - 0.5) * 50, y + 0.65, p.z - 20 + (R() - 0.5) * 10, { seg: 12, rz: Math.PI / 2, ry: R() * 3 });
  }

  // ---------- bloqueio militar ----------
  {
    const p = P.military, R = rng(41), y = p.baseY;
    for (const [dx, dz, r] of [[-8, -6, 0], [8, -6, 0], [-8, 6, 0], [8, 6, 0], [-14, 0, Math.PI / 2], [14, 0, Math.PI / 2]]) w.sandbags(p.x + dx, p.z + dz, r, y);
    for (const [dx, dz, r] of [[-20, -10, 0.1], [20, -12, -0.1], [22, 10, Math.PI / 2]]) w.container(p.x + dx, p.z + dz, r, y, R() < 0.5 ? M.rust : M.barrel);
    tent(w, p.x - 22, p.z + 12, 0.2, y, M.tentGreen);
    tent(w, p.x - 26, p.z + 4, -0.1, y, M.tentGreen);
    watchtower(w, p.x + 12, p.z + 16, y);
    for (let i = 0; i < 3; i++) { const x = p.x + 18 + i * 1.2, z = p.z - 2; w.box(0.9, 0.55, 0.5, M.barrel, x, y + 0.28, z, 0.2, 1); loot(w, 'locker', x, y, z, [1, 0.6, 0.6]); }
    w.car(p.x - 2, p.z + 2, Math.PI / 2 + 0.3, { y, color: 0x3e4a32, seed: 41 }); loot(w, 'car', p.x - 2, y, p.z + 2, [4.4, 1.4, 2]);
    w.car(p.x + 4, p.z - 18, 0.2, { y, burnt: true });
  }

  // ---------- engavetamento na estrada ----------
  {
    const p = P.pileup, R = rng(77), y = p.baseY;
    for (let i = 0; i < 12; i++) {
      const x = p.x + (R() - 0.5) * 7, z = p.z + (i - 6) * 4.6 + (R() - 0.5) * 2;
      w.car(x, z, Math.PI / 2 + (R() - 0.5) * 1.4 + (R() < 0.5 ? Math.PI : 0), { y: gy(x, z), burnt: R() < 0.35, flipped: R() < 0.12, color: [0x5d6e76, 0x7a2a22, 0x2f4a36, 0xb8b0a0, 0x22303a][i % 5], seed: 70 + i });
      if (R() < 0.6) loot(w, 'car', x, gy(x, z), z, [2, 1.4, 4.4]);
    }
  }

  // ---------- torre de rádio ----------
  {
    const p = P.radio, y = p.baseY, H = 24, half = 1.6, R = rng(8);
    for (const dx of [-half, half]) for (const dz of [-half, half]) w.box(0.16, H, 0.16, M.metal, p.x + dx, y + H / 2, p.z + dz, 0, 1);
    for (let k = 1; k < 8; k++) {
      const yy = y + k * 3, r = half;
      w.box(r * 2, 0.08, 0.08, M.metal, p.x, yy, p.z - r, 0, 1, false);
      w.box(r * 2, 0.08, 0.08, M.metal, p.x, yy, p.z + r, 0, 1, false);
      w.box(0.08, 0.08, r * 2, M.metal, p.x - r, yy, p.z, 0, 1, false);
      w.box(0.08, 0.08, r * 2, M.metal, p.x + r, yy, p.z, 0, 1, false);
    }
    w.box(4.2, 0.18, 4.2, M.metal, p.x, y + 12, p.z, 0, 1.5);
    w.ladder(p.x, p.z + half + 0.15, 0, 1, y, y + 12);
    w.cylinder(0.05, 0.05, 6, M.redPaint, p.x, y + H + 3, p.z, { seg: 6, collide: false });
    house(w, p.x - 9, p.z + 5, 0.4, y, R, { width: 5, depth: 4, height: 2.6, mat: M.concrete, roofMat: M.rust, interior: 'cabin' });
  }

  // ---------- cabanas na mata ----------
  {
    const p = P.cabins, R = rng(31), y = p.baseY;
    for (let i = 0; i < 4; i++) {
      const a = i / 4 * Math.PI * 2 + 0.4, x = p.x + Math.cos(a) * 22, z = p.z + Math.sin(a) * 22;
      house(w, x, z, -a - Math.PI / 2, y, R, { width: 6, depth: 5, height: 2.5, mat: M.wood, roofMat: M.plank, interior: 'cabin' });
    }
    w.firePositions.push(new THREE.Vector3(p.x, y, p.z));
    for (let i = 0; i < 8; i++) { const a = i / 8 * Math.PI * 2; w.box(0.25, 0.18, 0.18, M.rock, p.x + Math.cos(a) * 0.55, y + 0.08, p.z + Math.sin(a) * 0.55, a, 1, false); }
    loot(w, 'bag', p.x + 3, y, p.z - 2, [0.6, 0.4, 0.5]);
    w.box(0.5, 0.35, 0.3, M.tentGreen, p.x + 3, y + 0.17, p.z - 2, 0.6, 1, false);
  }
}
