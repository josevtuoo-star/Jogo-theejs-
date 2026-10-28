import * as THREE from 'three';
import { Octree } from 'three/addons/math/Octree.js';
import * as TEX from './textures.js';

// Constrói o cenário (vilarejo abandonado no meio da floresta) e a malha de colisão.
// Tudo que é sólido entra em `colliders`, que alimenta um Octree usado pela física do jogador.

const WORLD_SIZE = 300;
const WORLD_HALF = 140; // limite caminhável
const TOWN_RADIUS = 42; // área plana central

// ---------- ruído para o relevo ----------
function hash(x, z) {
  const s = Math.sin(x * 127.1 + z * 311.7) * 43758.5453;
  return s - Math.floor(s);
}
function valueNoise(x, z) {
  const xi = Math.floor(x), zi = Math.floor(z);
  const xf = x - xi, zf = z - zi;
  const u = xf * xf * (3 - 2 * xf), v = zf * zf * (3 - 2 * zf);
  const a = hash(xi, zi), b = hash(xi + 1, zi), c = hash(xi, zi + 1), d = hash(xi + 1, zi + 1);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
function smoothstep(a, b, x) {
  const t = Math.min(Math.max((x - a) / (b - a), 0), 1);
  return t * t * (3 - 2 * t);
}
export function terrainHeight(x, z) {
  let h = 0, amp = 1, freq = 0.02;
  for (let i = 0; i < 4; i++) {
    h += (valueNoise(x * freq, z * freq) - 0.5) * amp;
    amp *= 0.5; freq *= 2.1;
  }
  const dist = Math.hypot(x, z);
  const flat = smoothstep(TOWN_RADIUS, TOWN_RADIUS + 35, dist);
  // morros mais altos perto da borda do mapa
  const edge = smoothstep(WORLD_HALF - 40, WORLD_HALF + 10, Math.max(Math.abs(x), Math.abs(z)));
  return h * 9 * flat + edge * 14;
}

// ---------- utilidades de geometria ----------
/** Caixa com UVs proporcionais ao tamanho (textura não estica). */
function boxGeo(w, h, d, metersPerRepeat = 2) {
  const g = new THREE.BoxGeometry(w, h, d);
  const uv = g.attributes.uv;
  const dims = [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]]; // px nx py ny pz nz
  for (let f = 0; f < 6; f++) {
    for (let i = 0; i < 4; i++) {
      const idx = f * 4 + i;
      uv.setXY(idx, uv.getX(idx) * dims[f][0] / metersPerRepeat, uv.getY(idx) * dims[f][1] / metersPerRepeat);
    }
  }
  return g;
}

/**
 * Prisma triangular (rampa sólida): base em y=0, sobe de z=0 até altura h em z=len.
 * Triângulos com normais para fora (o Octree depende da orientação).
 */
function wedgeGeo(w, len, h) {
  const x = w / 2;
  const A = [-x, 0, 0], B = [x, 0, 0], C = [-x, 0, len], D = [x, 0, len], E = [-x, h, len], F = [x, h, len];
  const tris = [A, F, B, A, E, F, C, D, F, C, F, E, A, B, D, A, D, C, A, C, E, B, F, D];
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(tris.flat(), 3));
  return g;
}

export class World {
  constructor(scene, { quality = 'high' } = {}) {
    this.scene = scene;
    this.quality = quality;
    this.colliders = new THREE.Group(); // nunca renderizado, só física
    this.spawn = new THREE.Vector3(0, 0, 14);

    this.mat = {
      grass: new THREE.MeshStandardMaterial({ map: TEX.grassTexture(), roughness: 1 }),
      concrete: new THREE.MeshStandardMaterial({ map: TEX.concreteTexture(), roughness: 0.95 }),
      brick: new THREE.MeshStandardMaterial({ map: TEX.brickTexture(), roughness: 0.9 }),
      wood: new THREE.MeshStandardMaterial({ map: TEX.woodTexture(), roughness: 0.85 }),
      rust: new THREE.MeshStandardMaterial({ map: TEX.rustTexture(), roughness: 0.8, metalness: 0.2 }),
      bark: new THREE.MeshStandardMaterial({ map: TEX.barkTexture(), roughness: 1 }),
      leaves: new THREE.MeshStandardMaterial({ color: 0x36472b, roughness: 1, flatShading: true }),
      deadLeaves: new THREE.MeshStandardMaterial({ color: 0x4a4430, roughness: 1, flatShading: true }),
      rock: new THREE.MeshStandardMaterial({ color: 0x5f5d58, roughness: 1, flatShading: true }),
      carBody: new THREE.MeshStandardMaterial({ color: 0x5d6e76, roughness: 0.6, metalness: 0.25 }),
      glass: new THREE.MeshStandardMaterial({ color: 0x1b2328, roughness: 0.2, metalness: 0.6 }),
      tire: new THREE.MeshStandardMaterial({ color: 0x151515, roughness: 0.9 }),
      barrel: new THREE.MeshStandardMaterial({ color: 0x40562e, roughness: 0.7, metalness: 0.3 }),
      metal: new THREE.MeshStandardMaterial({ color: 0x3a3a3a, roughness: 0.6, metalness: 0.6 }),
      roof: new THREE.MeshStandardMaterial({ color: 0x3b3430, roughness: 0.95 }),
    };
    this.colliderMat = new THREE.MeshBasicMaterial();

    this._buildSky();
    this._buildLights();
    this._buildTerrain();
    this._buildTown();
    this._buildForest();
    this._buildBounds();

    this.octree = new Octree();
    this.octree.fromGraphNode(this.colliders);
  }

  // ---------- helpers ----------
  /** Adiciona um mesh visível e registra uma cópia dele como colisor. */
  solid(mesh, collide = true) {
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    this.scene.add(mesh);
    if (collide) {
      mesh.updateMatrixWorld(true);
      const c = new THREE.Mesh(mesh.geometry, this.colliderMat);
      c.matrixAutoUpdate = false;
      c.matrix.copy(mesh.matrixWorld);
      this.colliders.add(c);
    }
    return mesh;
  }

  /** Colisor invisível (ex.: rampa por baixo de uma escada, troncos instanciados). */
  invisibleCollider(geometry, position, rotation = new THREE.Euler()) {
    const c = new THREE.Mesh(geometry, this.colliderMat);
    c.position.copy(position);
    c.rotation.copy(rotation);
    c.updateMatrix();
    c.matrixAutoUpdate = false;
    this.colliders.add(c);
    return c;
  }

  box(w, h, d, mat, x, y, z, rotY = 0, uvScale = 2, collide = true) {
    const m = new THREE.Mesh(boxGeo(w, h, d, uvScale), mat);
    m.position.set(x, y, z);
    m.rotation.y = rotY;
    return this.solid(m, collide);
  }

  /**
   * Parede de (x1,z1) a (x2,z2) com aberturas (portas/janelas).
   * openings: [{ at: distância do início, width, bottom, top }]
   */
  wall(x1, z1, x2, z2, { height = 3, thick = 0.25, base = 0, mat = this.mat.brick, openings = [] } = {}) {
    const len = Math.hypot(x2 - x1, z2 - z1);
    const dir = new THREE.Vector2((x2 - x1) / len, (z2 - z1) / len);
    const rot = -Math.atan2(dir.y, dir.x);
    const piece = (from, to, y0, y1) => {
      if (to - from < 0.01 || y1 - y0 < 0.01) return;
      const mid = (from + to) / 2;
      this.box(to - from, y1 - y0, thick, mat,
        x1 + dir.x * mid, base + (y0 + y1) / 2, z1 + dir.y * mid, rot);
    };
    const ops = [...openings].sort((a, b) => a.at - b.at);
    let cursor = 0;
    for (const o of ops) {
      const a = o.at - o.width / 2, b = o.at + o.width / 2;
      piece(cursor, a, 0, height);
      piece(a, b, 0, o.bottom);
      piece(a, b, o.top, height);
      cursor = b;
    }
    piece(cursor, len, 0, height);
  }

  // ---------- céu e luz ----------
  _buildSky() {
    const geo = new THREE.SphereGeometry(400, 24, 12);
    const colors = [];
    const top = new THREE.Color(0x5d6a73), horizon = new THREE.Color(0xa3aaa8);
    const pos = geo.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      const t = Math.max(0, pos.getY(i) / 400);
      const c = horizon.clone().lerp(top, Math.pow(t, 0.6));
      colors.push(c.r, c.g, c.b);
    }
    geo.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
    const sky = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide, fog: false, depthWrite: false }));
    sky.renderOrder = -1;
    this.sky = sky;
    this.scene.add(sky);
    this.scene.background = horizon;
    this.scene.fog = new THREE.Fog(0x9aa2a2, 25, 170);
  }

  _buildLights() {
    const hemi = new THREE.HemisphereLight(0xb9c3c8, 0x4a4434, 1.5);
    this.scene.add(hemi);

    const sun = new THREE.DirectionalLight(0xfff0dd, 1.6);
    sun.position.set(40, 70, 25);
    sun.castShadow = true;
    const sm = this.quality === 'low' ? 1024 : 2048;
    sun.shadow.mapSize.set(sm, sm);
    const r = 45;
    Object.assign(sun.shadow.camera, { left: -r, right: r, top: r, bottom: -r, near: 1, far: 200 });
    sun.shadow.bias = -0.0005;
    sun.shadow.normalBias = 0.03;
    this.scene.add(sun);
    this.scene.add(sun.target);
    this.sun = sun;
    this.sunOffset = sun.position.clone();
  }

  /** Mantém a área de sombra centrada no jogador. */
  update(playerPos) {
    const snap = 4; // reduz "tremido" da sombra
    const x = Math.round(playerPos.x / snap) * snap;
    const z = Math.round(playerPos.z / snap) * snap;
    this.sun.target.position.set(x, 0, z);
    this.sun.position.set(x + this.sunOffset.x, this.sunOffset.y, z + this.sunOffset.z);
    this.sky.position.set(playerPos.x, 0, playerPos.z);
  }

  // ---------- terreno ----------
  _buildTerrain() {
    const seg = this.quality === 'low' ? 90 : 120;
    const geo = new THREE.PlaneGeometry(WORLD_SIZE, WORLD_SIZE, seg, seg);
    geo.rotateX(-Math.PI / 2);
    const pos = geo.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      pos.setY(i, terrainHeight(pos.getX(i), pos.getZ(i)));
    }
    geo.computeVertexNormals();
    const uv = geo.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * 75, uv.getY(i) * 75);

    const ground = new THREE.Mesh(geo, this.mat.grass);
    ground.receiveShadow = true;
    this.scene.add(ground);
    const c = new THREE.Mesh(geo, this.colliderMat);
    this.colliders.add(c);

    // estrada de terra/asfalto velho cortando o vilarejo
    const road = new THREE.Mesh(boxGeo(8, 0.04, 90, 4), this.mat.concrete);
    road.position.set(-4, 0.02, 0);
    road.receiveShadow = true;
    this.scene.add(road);
  }

  // ---------- vilarejo ----------
  _buildTown() {
    const M = this.mat;

    // ===== Casa de tijolos com terraço =====
    {
      const cx = 14, cz = -8, w = 10, d = 8, h = 3.2;
      const x0 = cx - w / 2, x1 = cx + w / 2, z0 = cz - d / 2, z1 = cz + d / 2;
      // piso
      this.box(w, 0.2, d, M.concrete, cx, 0.1, cz, 0, 2);
      // parede frontal (z1) com porta e janela
      this.wall(x0, z1, x1, z1, { height: h, openings: [
        { at: 3, width: 1.4, bottom: 0, top: 2.3 },
        { at: 7.2, width: 1.6, bottom: 1.0, top: 2.2 },
      ] });
      // fundos com janela
      this.wall(x0, z0, x1, z0, { height: h, openings: [{ at: 5, width: 2, bottom: 1.0, top: 2.2 }] });
      // laterais
      this.wall(x0, z0, x0, z1, { height: h, openings: [{ at: 4, width: 1.4, bottom: 1.0, top: 2.2 }] });
      this.wall(x1, z0, x1, z1, { height: h });
      // divisória interna com vão
      this.wall(cx + 1, z0, cx + 1, z1, { height: h, thick: 0.15, mat: M.concrete, openings: [{ at: 5.5, width: 1.2, bottom: 0, top: 2.3 }] });
      // laje / terraço
      this.box(w + 0.6, 0.25, d + 0.6, M.roof, cx, h + 0.12, cz, 0, 3);
      // mureta do terraço (com abertura onde chega a escada)
      const ph = 0.7, top = h + 0.25;
      this.wall(x0 - 0.3, z0 - 0.3, x1 + 0.3, z0 - 0.3, { height: ph, base: top, thick: 0.15, mat: M.concrete });
      this.wall(x0 - 0.3, z1 + 0.3, x1 + 0.3, z1 + 0.3, { height: ph, base: top, thick: 0.15, mat: M.concrete });
      this.wall(x0 - 0.3, z0 - 0.3, x0 - 0.3, z1 + 0.3, { height: ph, base: top, thick: 0.15, mat: M.concrete });
      // abertura na mureta alinhada com o patamar da escada (z = cz - 2.6)
      this.wall(x1 + 0.3, z0 - 0.3, x1 + 0.3, z1 + 0.3, { height: ph, base: top, thick: 0.15, mat: M.concrete,
        openings: [{ at: (cz - 2.6) - (z0 - 0.3), width: 1.4, bottom: 0, top: ph }] });

      // escada externa encostada na lateral, subindo em direção aos fundos
      this.stairs(x1 + 1.1, cz + 4, x1 + 1.1, cz - 2, top, 1.5);

      // móveis simples
      this.box(1.6, 0.8, 0.9, M.wood, cx - 3, 0.6, cz - 2.6);  // mesa
      this.box(0.9, 1.8, 0.5, M.wood, cx + 4.2, 1.1, cz - 3.4); // armário
      this.box(2, 0.5, 1, M.wood, cx + 3.5, 0.45, cz + 2.5);    // cama
    }

    // ===== Contêineres (parkour) =====
    this.container(-20, -14, 0);
    this.container(-20, -11.4, 0);
    this.container(-20, -12.7, 0, 2.6); // empilhado
    this.container(-28, 6, Math.PI / 2.4);
    // rampa até o contêiner de cima
    {
      const len = 8, rise = 5.2;
      const ang = Math.atan2(rise, len);
      const ramp = new THREE.Mesh(boxGeo(2.4, 0.2, Math.hypot(len, rise), 1.5), M.wood);
      // a ponta alta encosta na borda do contêiner de cima (z = -12.7 + 1.2)
      ramp.position.set(-20, rise / 2, -11.5 + len / 2);
      ramp.rotation.x = ang;
      this.solid(ramp);
    }

    // ===== Carros abandonados =====
    this.car(-6, 8, 0.2);
    this.car(-2.5, -18, Math.PI + 0.35);
    this.car(4, 26, Math.PI / 2 - 0.2);

    // ===== Caixotes e barris =====
    const crates = [[3, 3], [3.6, 4.2], [-12, 2], [-12, 3.1], [24, 6], [24.6, 7.2], [8, -20], [-30, -2]];
    crates.forEach(([x, z], i) => this.box(1.1, 1.1, 1.1, M.wood, x, 0.55, z, i * 0.4, 1.1));
    this.box(1.1, 1.1, 1.1, M.wood, 3.2, 1.65, 3.5, 0.2, 1.1); // caixote empilhado
    const barrels = [[6, 10], [6.8, 10.5], [-14, -6], [20, 14], [-8, 22]];
    barrels.forEach(([x, z]) => this.barrel(x, z));

    // ===== Cerca de madeira ao redor do vilarejo (com aberturas) =====
    const R = 36, posts = 56;
    for (let i = 0; i < posts; i++) {
      const a0 = (i / posts) * Math.PI * 2, a1 = ((i + 1) / posts) * Math.PI * 2;
      const skip = (i % 14 === 0) || (i % 14 === 1) || i === 23 || i === 38; // 4 entradas + 2 partes quebradas
      if (skip) continue;
      const xa = Math.cos(a0) * R, za = Math.sin(a0) * R;
      const xb = Math.cos(a1) * R, zb = Math.sin(a1) * R;
      this.box(0.15, 1.3, 0.15, M.wood, xa, 0.65, za, 0, 1, false);
      const len = Math.hypot(xb - xa, zb - za);
      const rot = -Math.atan2(zb - za, xb - xa);
      // trilhos visuais + um colisor único por trecho
      this.box(len, 0.12, 0.06, M.wood, (xa + xb) / 2, 0.45, (za + zb) / 2, rot, 1, false);
      this.box(len, 0.12, 0.06, M.wood, (xa + xb) / 2, 0.95, (za + zb) / 2, rot, 1, false);
      this.invisibleCollider(new THREE.BoxGeometry(len, 1.1, 0.2), new THREE.Vector3((xa + xb) / 2, 0.55, (za + zb) / 2), new THREE.Euler(0, rot, 0));
    }

    // ===== Postes de luz caídos/em pé =====
    [[2, -2], [-10, 14], [-10, -14]].forEach(([x, z]) => {
      const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.12, 6, 8), M.metal);
      pole.position.set(x, 3, z);
      this.solid(pole);
      this.box(1.4, 0.1, 0.2, M.metal, x + 0.6, 5.9, z, 0, 1, false);
    });

    // ===== Muro em ruínas =====
    this.wall(-34, -24, -16, -30, { height: 2.2, thick: 0.35, mat: M.concrete, openings: [
      { at: 6, width: 2.5, bottom: 0, top: 2.2 },
      { at: 12, width: 2, bottom: 1.1, top: 2.2 },
    ] });
  }

  stairs(xStart, zStart, xEnd, zEnd, height, width) {
    const len = Math.hypot(xEnd - xStart, zEnd - zStart);
    const steps = Math.round(height / 0.22);
    const stepRise = height / steps, stepRun = len / steps;
    const dx = (xEnd - xStart) / len, dz = (zEnd - zStart) / len;
    const rotY = Math.atan2(dx, dz);
    for (let i = 0; i < steps; i++) {
      const t = (i + 0.5) * stepRun;
      const h = (i + 1) * stepRise;
      this.box(width, h, stepRun, this.mat.concrete, xStart + dx * t, h / 2, zStart + dz * t, rotY, 1, false);
    }
    // patamar no topo
    this.box(width, 0.2, 1.2, this.mat.concrete, xEnd + dx * 0.6, height - 0.1, zEnd + dz * 0.6, rotY, 1);
    // colisão em forma de cunha: o capsule sobe suave em vez de travar em cada degrau
    this.invisibleCollider(wedgeGeo(width, len, height), new THREE.Vector3(xStart, 0, zStart), new THREE.Euler(0, rotY, 0));
  }

  container(x, z, rotY, baseY = 0) {
    const L = 6, H = 2.6, W = 2.4;
    this.box(L, H, W, this.mat.rust, x, baseY + H / 2, z, rotY, 2.6);
  }

  car(x, z, rotY) {
    const g = new THREE.Group();
    const M = this.mat;
    const body = new THREE.Mesh(boxGeo(4.2, 0.8, 1.8), M.carBody);
    body.position.y = 0.75;
    const cabin = new THREE.Mesh(boxGeo(2.2, 0.65, 1.6), M.carBody);
    cabin.position.set(-0.2, 1.47, 0);
    const glass = new THREE.Mesh(boxGeo(2.25, 0.5, 1.62), M.glass);
    glass.position.set(-0.2, 1.45, 0);
    g.add(body, cabin, glass);
    for (const [wx, wz] of [[1.3, 0.85], [1.3, -0.85], [-1.3, 0.85], [-1.3, -0.85]]) {
      const wheel = new THREE.Mesh(new THREE.CylinderGeometry(0.38, 0.38, 0.28, 12), M.tire);
      wheel.rotation.x = Math.PI / 2;
      wheel.position.set(wx, 0.38, wz);
      g.add(wheel);
    }
    g.position.set(x, 0, z);
    g.rotation.y = rotY;
    g.rotation.z = 0.03; // carro levemente torto (pneu murcho)
    g.updateMatrixWorld(true);
    g.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    this.scene.add(g);
    for (const m of [body, cabin]) {
      const c = new THREE.Mesh(m.geometry, this.colliderMat);
      c.matrixAutoUpdate = false;
      c.matrix.copy(m.matrixWorld);
      this.colliders.add(c);
    }
  }

  barrel(x, z) {
    const m = new THREE.Mesh(new THREE.CylinderGeometry(0.35, 0.35, 1, 14), this.mat.barrel);
    m.position.set(x, 0.5, z);
    this.solid(m);
  }

  // ---------- floresta ----------
  _buildForest() {
    const count = this.quality === 'low' ? 160 : 260;
    const rand = (() => { let s = 7; return () => ((s = (s * 16807) % 2147483647) / 2147483647); })();
    const trunkGeo = new THREE.CylinderGeometry(0.18, 0.32, 4.5, 7);
    trunkGeo.translate(0, 2.25, 0);
    const coneGeo = new THREE.ConeGeometry(1.8, 3.6, 7);
    const deadGeo = new THREE.CylinderGeometry(0.03, 0.12, 2.2, 4);

    const trunks = new THREE.InstancedMesh(trunkGeo, this.mat.bark, count);
    const leavesA = new THREE.InstancedMesh(coneGeo, this.mat.leaves, count);
    const leavesB = new THREE.InstancedMesh(coneGeo, this.mat.leaves, count);
    const branches = new THREE.InstancedMesh(deadGeo, this.mat.bark, count * 2);
    const colGeo = new THREE.CylinderGeometry(0.3, 0.3, 5, 6);
    colGeo.translate(0, 2.5, 0);

    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3();
    const up = new THREE.Vector3(0, 1, 0);
    let placed = 0, branchIdx = 0;
    while (placed < count) {
      const x = (rand() - 0.5) * WORLD_HALF * 2;
      const z = (rand() - 0.5) * WORLD_HALF * 2;
      if (Math.hypot(x, z) < TOWN_RADIUS + 2) continue;
      const y = terrainHeight(x, z);
      const sc = 0.8 + rand() * 0.7;
      const dead = rand() < 0.25;
      q.setFromAxisAngle(up, rand() * Math.PI * 2);
      s.set(sc, sc * (0.9 + rand() * 0.4), sc);
      p.set(x, y - 0.1, z);
      m.compose(p, q, s);
      trunks.setMatrixAt(placed, m);

      if (dead) {
        // árvore morta: sem copa, com galhos secos
        m.makeScale(0, 0, 0);
        leavesA.setMatrixAt(placed, m);
        leavesB.setMatrixAt(placed, m);
        for (let b = 0; b < 2; b++) {
          const bq = new THREE.Quaternion().setFromEuler(new THREE.Euler(0.9 * (b ? 1 : -1), rand() * 6, 0));
          m.compose(new THREE.Vector3(x, y + 3 * sc, z), bq, new THREE.Vector3(sc, sc, sc));
          branches.setMatrixAt(branchIdx++, m);
        }
      } else {
        m.compose(p.set(x, y + 4.2 * s.y, z), q, s);
        leavesA.setMatrixAt(placed, m);
        m.compose(p.set(x, y + 5.6 * s.y, z), q, new THREE.Vector3(s.x * 0.7, s.y * 0.75, s.z * 0.7));
        leavesB.setMatrixAt(placed, m);
      }

      const col = this.invisibleCollider(colGeo, new THREE.Vector3(x, y - 0.5, z));
      col.scale.set(sc, 1, sc);
      col.updateMatrix();
      placed++;
    }
    branches.count = branchIdx;
    for (const im of [trunks, leavesA, leavesB, branches]) {
      im.castShadow = true;
      im.receiveShadow = true;
      im.instanceMatrix.needsUpdate = true;
      this.scene.add(im);
    }

    // pedras
    const rockGeo = new THREE.DodecahedronGeometry(1, 0);
    for (let i = 0; i < 45; i++) {
      const x = (rand() - 0.5) * WORLD_HALF * 2;
      const z = (rand() - 0.5) * WORLD_HALF * 2;
      if (Math.hypot(x, z) < 12) continue;
      const r = new THREE.Mesh(rockGeo, this.mat.rock);
      const sc = 0.4 + rand() * 1.3;
      r.scale.set(sc * (1 + rand() * 0.6), sc * 0.7, sc);
      r.rotation.set(rand(), rand() * 6, rand());
      r.position.set(x, terrainHeight(x, z) + sc * 0.2, z);
      this.solid(r);
    }
  }

  // ---------- limites do mapa ----------
  _buildBounds() {
    const H = 60, T = 2;
    const g = new THREE.BoxGeometry(WORLD_HALF * 2 + T * 2, H, T);
    const g2 = new THREE.BoxGeometry(T, H, WORLD_HALF * 2 + T * 2);
    this.invisibleCollider(g, new THREE.Vector3(0, H / 2 - 10, -WORLD_HALF - T / 2));
    this.invisibleCollider(g, new THREE.Vector3(0, H / 2 - 10, WORLD_HALF + T / 2));
    this.invisibleCollider(g2, new THREE.Vector3(-WORLD_HALF - T / 2, H / 2 - 10, 0));
    this.invisibleCollider(g2, new THREE.Vector3(WORLD_HALF + T / 2, H / 2 - 10, 0));
  }
}
