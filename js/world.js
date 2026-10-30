import * as THREE from 'three';
import { pineBranchTexture, leafClusterTexture, foliageCardMaterial, pineCardsGeometry, broadCardsGeometry, bushCardsGeometry } from './trees.js';
import { Octree } from 'three/addons/math/Octree.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import * as TEX from './textures.js';
import { buildPOIs } from './pois.js';

// Constrói o cenário (vilarejo abandonado numa floresta de outono) e a malha de colisão.
// Tudo que é sólido entra em `colliders`, que alimenta um Octree usado pela física do jogador.
// Os objetos estáticos visíveis são fundidos por material no final (poucos draw calls = mais FPS).

const WORLD_SIZE = 1200;
const WORLD_HALF = 580; // limite caminhável
const TOWN_RADIUS = 42; // área plana central
const ROAD_X = -4;      // estrada norte-sul
const ROAD_HALF = 4;
const GRID = 320;       // células do relevo (3,75 m): a mesma grade desenha e colide
const CELL = WORLD_SIZE / GRID;

// Lugares do mapa (cada um numa área plana) e estradas ligando todos
export const POIS = [
  { name: 'VILAREJO', x: 0, z: 0, r: TOWN_RADIUS, kind: 'town', base: 0 },
  { name: 'FAZENDA', x: 175, z: 150, r: 46, kind: 'farm' },
  { name: 'VILA LESTE', x: 300, z: -235, r: 62, kind: 'village' },
  { name: 'VILA OESTE', x: -330, z: -195, r: 56, kind: 'village' },
  { name: 'BLOQUEIO MILITAR', x: ROAD_X, z: -430, r: 42, kind: 'military' },
  { name: 'ENGAVETAMENTO', x: ROAD_X, z: 310, r: 34, kind: 'pileup' },
  { name: 'TORRE DE RÁDIO', x: 400, z: 345, r: 24, kind: 'radio' },
  { name: 'CABANAS', x: -265, z: 270, r: 44, kind: 'cabins' },
];
export const ROADS = [
  [[ROAD_X, -235], [120, -240], [300, -235], [WORLD_HALF, -228]],
  [[ROAD_X, -200], [-150, -206], [-330, -195], [-WORLD_HALF, -186]],
  [[ROAD_X, 150], [90, 150], [175, 150]],
  [[175, 150], [300, 250], [400, 345]],
];

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
function distToSegment(px, pz, ax, az, bx, bz) {
  const dx = bx - ax, dz = bz - az;
  const t = Math.max(0, Math.min(1, ((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz)));
  return Math.hypot(px - (ax + dx * t), pz - (az + dz * t));
}
/** Distância até a estrada mais próxima (a principal e as secundárias). */
export function roadDistance(x, z) {
  let d = Math.abs(x - ROAD_X);
  for (const r of ROADS) for (let i = 0; i < r.length - 1; i++) d = Math.min(d, distToSegment(x, z, ...r[i], ...r[i + 1]));
  return d;
}
// relevo "selvagem": morros grandes (centenas de metros) + ondulações
function bigHills(x, z) {
  let h = 0, amp = 1, f = 0.0035;
  for (let i = 0; i < 3; i++) { h += (valueNoise(x * f + 31, z * f - 17) - 0.5) * amp; amp *= 0.5; f *= 2.2; }
  const away = smoothstep(70, 220, Math.hypot(x, z));
  return h * 46 * away;
}
function smallHills(x, z) {
  let h = 0, amp = 1, freq = 0.02;
  for (let i = 0; i < 3; i++) {
    h += (valueNoise(x * freq, z * freq) - 0.5) * amp;
    amp *= 0.5; freq *= 2.1;
  }
  return h * 9;
}
function naturalHeight(x, z) {
  const big = bigHills(x, z);
  let h = big + smallHills(x, z) * smoothstep(TOWN_RADIUS, TOWN_RADIUS + 35, Math.hypot(x, z));
  // estradas: seguem só os morros grandes (sem calombos)
  const road = smoothstep(ROAD_HALF + 1, ROAD_HALF + 12, roadDistance(x, z));
  h = big + (h - big) * road;
  // lugares: chão plano (na altura do centro de cada um)
  for (const p of POIS) {
    const w = 1 - smoothstep(p.r, p.r + 38, Math.hypot(x - p.x, z - p.z));
    if (w > 0) h += ((p.baseY ?? 0) - h) * w;
  }
  // serras na borda do mapa
  const edge = smoothstep(WORLD_HALF - 60, WORLD_HALF + 15, Math.max(Math.abs(x), Math.abs(z)));
  return h + edge * 30;
}
for (const p of POIS) p.baseY = p.base ?? (bigHills(p.x, p.z) + smallHills(p.x, p.z) * 0.3);

// lago na floresta (noroeste): margem exatamente no nível da água, fundo de até ~3,4 m
export const LAKE = { x: -62, z: 50, r: 19, y: 0 };
LAKE.y = naturalHeight(LAKE.x, LAKE.z) - 0.3;

function rawHeight(x, z) {
  const h = naturalHeight(x, z);
  const d = Math.hypot(x - LAKE.x, z - LAKE.z);
  if (d > LAKE.r + 12) return h;
  const k = d / LAKE.r;
  const bed = LAKE.y - 3.4 * (1 - k * k);
  return h + (bed - h) * smoothstep(LAKE.r + 12, LAKE.r - 3, d);
}

// grade de alturas (calculada uma vez): o terreno desenhado usa exatamente estes vértices e a
// altura em qualquer ponto é a do triângulo da malha — pés, objetos e física batem com o chão
const HEIGHTS = new Float32Array((GRID + 1) * (GRID + 1));
for (let iz = 0; iz <= GRID; iz++) for (let ix = 0; ix <= GRID; ix++) HEIGHTS[iz * (GRID + 1) + ix] = rawHeight(-WORLD_SIZE / 2 + ix * CELL, -WORLD_SIZE / 2 + iz * CELL);

export function terrainHeight(x, z) {
  const fx = Math.min(GRID - 1e-6, Math.max(0, (x + WORLD_SIZE / 2) / CELL)), fz = Math.min(GRID - 1e-6, Math.max(0, (z + WORLD_SIZE / 2) / CELL));
  const ix = Math.floor(fx), iz = Math.floor(fz), u = fx - ix, v = fz - iz;
  const W = GRID + 1, a = HEIGHTS[iz * W + ix], b = HEIGHTS[(iz + 1) * W + ix], c = HEIGHTS[(iz + 1) * W + ix + 1], d = HEIGHTS[iz * W + ix + 1];
  // mesma diagonal da PlaneGeometry (b-d)
  return u + v <= 1 ? a + (d - a) * u + (b - a) * v : c + (b - c) * (1 - u) + (d - c) * (1 - v);
}
export const TERRAIN = { size: WORLD_SIZE, grid: GRID, heights: HEIGHTS, half: WORLD_HALF };

// trilhas de terra saindo das entradas da cerca
const TRAILS = [
  [[36, 4], [55, 10], [75, 22], [100, 30], [128, 26]],
  [[-36, -4], [-58, -12], [-80, -8], [-105, -20], [-132, -24]],
  [[30, -22], [42, -40], [60, -55], [70, -80], [95, -110]],
  [[-30, 19], [-38, 28], [-44, 36], [-47, 40]], // até o lago
];
function trailMask(x, z) {
  let d = Infinity;
  for (const t of TRAILS) for (let i = 0; i < t.length - 1; i++) d = Math.min(d, distToSegment(x, z, ...t[i], ...t[i + 1]));
  return smoothstep(2.4, 0.9, d);
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

/** Deforma levemente uma geometria (copas e pedras com aspecto orgânico). */
function lumpy(geo, amount, seed = 1) {
  const pos = geo.attributes.position;
  const v = new THREE.Vector3();
  for (let i = 0; i < pos.count; i++) {
    v.fromBufferAttribute(pos, i);
    // mesmo deslocamento para vértices na mesma posição (sem rachaduras)
    const k = hash(Math.round(v.x * 100) + seed, Math.round(v.y * 100) * 3 + Math.round(v.z * 100) * 7);
    v.multiplyScalar(1 + (k - 0.5) * amount);
    pos.setXYZ(i, v.x, v.y, v.z);
  }
  geo.computeVertexNormals();
  return geo;
}

/**
 * Porta que abre e fecha girando na dobradiça. Tem um Octree próprio (só a folha da porta),
 * reconstruído enquanto ela se move, para o jogador e os objetos colidirem com ela.
 */
class Door {
  constructor(world, hx, baseY, hz, wallRot, width, height, mat) {
    this.world = world;
    this.wallRot = wallRot;
    this.angle = 0;
    this.target = 0;
    this.pivot = new THREE.Group();
    this.pivot.position.set(hx, baseY, hz);
    this.pivot.rotation.y = wallRot;
    const slab = new THREE.Mesh(boxGeo(width, height, 0.06, 1.2), mat);
    slab.position.set(width / 2, height / 2, 0);
    slab.castShadow = slab.receiveShadow = true;
    this.pivot.add(slab);
    const knobMat = world.mat.chrome;
    this.knobs = [];
    for (const s of [-1, 1]) {
      const knob = new THREE.Mesh(new THREE.SphereGeometry(0.035, 10, 8), knobMat);
      knob.position.set(width - 0.1, 1.0, s * 0.06);
      knob.castShadow = true;
      this.pivot.add(knob);
      this.knobs.push(knob);
    }
    // tábuas horizontais de reforço
    for (const y of [0.35, height - 0.35]) {
      const brace = new THREE.Mesh(boxGeo(width - 0.08, 0.1, 0.08, 1), mat);
      brace.position.set(width / 2, y, 0);
      this.pivot.add(brace);
    }
    world.scene.add(this.pivot);
    this.slab = slab;
    this.slab.userData.door = this;
    this.center = new THREE.Vector3(hx, baseY + height / 2, hz);
    this._rebuild();
  }

  get isOpen() { return Math.abs(this.target) > 0.1; }

  /** Maçaneta do lado de quem está em `pos` (a mão do personagem vai até ela). */
  knobFor(pos) {
    const local = this.pivot.worldToLocal(pos.clone());
    return this.knobs[local.z > 0 ? 1 : 0];
  }

  _rebuild() {
    this.pivot.updateMatrixWorld(true);
    const g = new THREE.Group();
    const c = new THREE.Mesh(this.slab.geometry, this.world.colliderMat);
    c.matrixAutoUpdate = false;
    c.matrix.copy(this.slab.matrixWorld);
    g.add(c);
    this.octree = new Octree();
    this.octree.fromGraphNode(g);
  }

  /** Abre para longe de quem está empurrando, ou fecha. */
  toggle(fromPos) {
    if (this.isOpen) { this.target = 0; return 'close'; }
    // lado do jogador em relação à porta (eixo z local da dobradiça)
    const local = this.pivot.worldToLocal(fromPos.clone());
    this.target = local.z > 0 ? 1.7 : -1.7;
    return 'open';
  }

  /** Move a porta; para se for bater no jogador. Retorna true se terminou de fechar. */
  update(dt, playerCollider) {
    if (this.angle === this.target) return false;
    const prev = this.angle;
    const before = this.octree.capsuleIntersect(playerCollider);
    const step = 3.4 * dt;
    const diff = this.target - this.angle;
    this.angle += Math.sign(diff) * Math.min(Math.abs(diff), step);
    this.pivot.rotation.y = this.wallRot + this.angle;
    this._rebuild();
    const after = this.octree.capsuleIntersect(playerCollider);
    // só trava se a porta estiver entrando MAIS no jogador (encostado nela, ela ainda abre)
    if (after && after.depth > 0.03 && after.depth > (before ? before.depth : 0) + 0.005) {
      // bateu no jogador: fica onde está
      this.angle = prev;
      this.target = prev;
      this.pivot.rotation.y = this.wallRot + prev;
      this._rebuild();
      return false;
    }
    return this.angle === 0 && prev !== 0;
  }
}

function makeRng(seed) {
  let s = seed;
  return () => ((s = (s * 16807) % 2147483647) / 2147483647);
}

export class World {
  constructor(scene, renderer, { quality = 'high' } = {}) {
    this.scene = scene;
    this.quality = quality;
    this.colliders = new THREE.Group(); // nunca renderizado, só física
    this.spawn = new THREE.Vector3(0, 0, 14);
    this.staticMeshes = [];
    this.noGrass = [];      // retângulos [x0, z0, x1, z1] sem grama/árvore
    this.ladders = [];
    this.doors = [];
    this.firePositions = [];
    this.propSpots = [];
    this.lootSpots = [];   // armários, caixas, porta-malas... (revistar)
    this.hitboxMat = new THREE.MeshBasicMaterial({ visible: false });
    this.lodChunks = [];   // blocos (árvores, construções) escondidos de longe
    this.windUniform = { value: 0 };

    this.mat = {
      ground: new THREE.MeshStandardMaterial({ map: TEX.groundDetailTexture(), vertexColors: true, roughness: 1 }),
      asphalt: new THREE.MeshStandardMaterial({ map: TEX.asphaltTexture(), roughness: 0.95, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 }),
      concrete: new THREE.MeshStandardMaterial({ map: TEX.concreteTexture(), roughness: 0.95 }),
      brick: new THREE.MeshStandardMaterial({ map: TEX.brickTexture(), roughness: 0.9 }),
      wood: new THREE.MeshStandardMaterial({ map: TEX.woodTexture(), roughness: 0.85 }),
      plank: new THREE.MeshStandardMaterial({ map: TEX.plankTexture(), roughness: 0.9 }),
      rust: new THREE.MeshStandardMaterial({ map: TEX.rustTexture(), roughness: 0.75, metalness: 0.2 }),
      bark: new THREE.MeshStandardMaterial({ map: TEX.barkTexture(), roughness: 1 }),
      foliage: new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.95, flatShading: true }),
      rock: new THREE.MeshStandardMaterial({ color: 0x77736a, roughness: 1, flatShading: true }),
      carBody: new THREE.MeshStandardMaterial({ color: 0x5d6e76, roughness: 0.5, metalness: 0.35 }),
      carRed: new THREE.MeshStandardMaterial({ color: 0x7a2a22, roughness: 0.5, metalness: 0.35 }),
      glass: new THREE.MeshStandardMaterial({ color: 0x24302e, roughness: 0.05, metalness: 0.6, transparent: true, opacity: 0.45 }),
      tire: new THREE.MeshStandardMaterial({ color: 0x151515, roughness: 0.9 }),
      barrel: new THREE.MeshStandardMaterial({ color: 0x4f6a38, roughness: 0.55, metalness: 0.4 }),
      metal: new THREE.MeshStandardMaterial({ color: 0x4a4a48, roughness: 0.45, metalness: 0.75 }),
      roof: new THREE.MeshStandardMaterial({ color: 0x3b3430, roughness: 0.95 }),
      paint: new THREE.MeshStandardMaterial({ color: 0xc9c4b8, roughness: 0.8 }),
      redPaint: new THREE.MeshStandardMaterial({ color: 0x8a2a20, roughness: 0.7 }),
      fabric: new THREE.MeshStandardMaterial({ color: 0x5b5f4a, roughness: 1 }),
      sandbag: new THREE.MeshStandardMaterial({ color: 0x8a7a58, roughness: 1, flatShading: true }),
      door: new THREE.MeshStandardMaterial({ map: TEX.plankTexture(), color: 0xb0a090, roughness: 0.85 }),
      water: new THREE.MeshStandardMaterial({
        color: 0x1f3a3a, roughness: 0.06, metalness: 0.1, transparent: true, opacity: 0.86, side: THREE.DoubleSide,
        normalMap: TEX.waterNormalTexture(), normalScale: new THREE.Vector2(0.35, 0.35),
      }),
      reed: new THREE.MeshStandardMaterial({ color: 0x7a7a3e, roughness: 1, side: THREE.DoubleSide }),
      headlight: new THREE.MeshStandardMaterial({ color: 0xdedcc8, roughness: 0.2, metalness: 0.5, emissive: 0x222018 }),
      taillight: new THREE.MeshStandardMaterial({ color: 0x8a1a12, roughness: 0.3, emissive: 0x200404 }),
      seat: new THREE.MeshStandardMaterial({ color: 0x2a2622, roughness: 0.95 }),
      chrome: new THREE.MeshStandardMaterial({ color: 0x8a8e90, roughness: 0.45, metalness: 0.8 }),
      burnt: new THREE.MeshStandardMaterial({ map: TEX.burntTexture(), roughness: 0.95, metalness: 0.3 }),
      burntSeat: new THREE.MeshStandardMaterial({ color: 0x141210, roughness: 1 }),
      crackedGlass: new THREE.MeshStandardMaterial({ map: TEX.crackedGlassTexture(), transparent: true, roughness: 0.1, metalness: 0.5 }),
      trashBag: new THREE.MeshStandardMaterial({ color: 0x141618, roughness: 0.35, metalness: 0.1 }),
      paper: new THREE.MeshStandardMaterial({ color: 0xcfc8b4, roughness: 1, side: THREE.DoubleSide }),
      pothole: new THREE.MeshStandardMaterial({ color: 0x1c1b19, roughness: 0.6, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3 }),
      tentGreen: new THREE.MeshStandardMaterial({ color: 0x4a5636, roughness: 1, side: THREE.DoubleSide }),
      tentOrange: new THREE.MeshStandardMaterial({ color: 0x9a5a26, roughness: 1, side: THREE.DoubleSide }),
    };
    for (const m of Object.values(this.mat)) m.envMapIntensity = 0.65;
    this.colliderMat = new THREE.MeshBasicMaterial();

    // tipo de piso de cada material (define o som dos passos)
    const M = this.mat;
    this.surfaceOf = new Map([
      [M.concrete, 'concrete'], [M.brick, 'concrete'], [M.roof, 'concrete'], [M.rock, 'concrete'],
      [M.asphalt, 'concrete'], [M.paint, 'concrete'], [M.sandbag, 'grass'],
      [M.wood, 'wood'], [M.plank, 'wood'], [M.bark, 'wood'],
      [M.rust, 'metal'], [M.metal, 'metal'], [M.carBody, 'metal'], [M.carRed, 'metal'], [M.barrel, 'metal'],
      [M.glass, 'metal'], [M.redPaint, 'metal'], [M.chrome, 'metal'], [M.door, 'wood'], [M.burnt, 'metal'],
    ]);
    this.surfaceMeshes = [];
    this._raycaster = new THREE.Raycaster();
    this._down = new THREE.Vector3(0, -1, 0);
    this._rayFrom = new THREE.Vector3();

    this._buildSky();
    this._buildLights();
    if (renderer) this._buildEnvironment(renderer);
    this._buildTerrain();
    this._buildBrickHouse();
    this._buildCabin();
    this._buildGasStation();
    this._buildTower();
    this._buildTown();
    buildPOIs(this, POIS);
    this._buildCampfire();
    this._buildLake();
    this._buildForest();
    this._buildGrass();
    this._buildBounds();
    this._mergeStatic();

    this.octree = new Octree();
    this.octree.fromGraphNode(this.colliders);
  }

  // ---------- helpers ----------
  /** Adiciona um mesh visível (estático) e registra uma cópia dele como colisor. */
  solid(mesh, collide = true) {
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    if (!mesh.parent) this.scene.add(mesh);
    mesh.updateMatrixWorld(true);
    this.staticMeshes.push(mesh);
    if (collide) {
      const c = new THREE.Mesh(mesh.geometry, this.colliderMat);
      c.matrixAutoUpdate = false;
      c.matrix.copy(mesh.matrixWorld);
      this.colliders.add(c);
    }
    return mesh;
  }

  /** Tipo de piso sob os pés: 'grass' | 'concrete' | 'wood' | 'metal'. */
  surfaceAt(feet) {
    this._rayFrom.set(feet.x, feet.y + 0.3, feet.z);
    this._raycaster.set(this._rayFrom, this._down);
    this._raycaster.far = 0.7;
    const hit = this._raycaster.intersectObjects(this.surfaceMeshes, false)[0];
    if (hit) return hit.object.userData.surface;
    if (Math.abs(feet.x - ROAD_X) < ROAD_HALF) return 'concrete';
    return 'grass';
  }

  groundHeight(x, z) { return terrainHeight(x, z); }

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

  cylinder(rTop, rBottom, h, mat, x, y, z, { seg = 10, collide = true, rx = 0, rz = 0, ry = 0 } = {}) {
    const m = new THREE.Mesh(new THREE.CylinderGeometry(rTop, rBottom, h, seg), mat);
    m.position.set(x, y, z);
    m.rotation.set(rx, ry, rz);
    return this.solid(m, collide);
  }

  /**
   * Parede de (x1,z1) a (x2,z2) com aberturas (portas/janelas).
   * openings: [{ at: distância do início, width, bottom, top }]
   */
  wall(x1, z1, x2, z2, { height = 3, thick = 0.25, base = 0, mat = this.mat.brick, openings = [], frames = false } = {}) {
    // aberturas com `door: true` ganham uma porta de verdade (abre e fecha)
    const len = Math.hypot(x2 - x1, z2 - z1);
    const dir = new THREE.Vector2((x2 - x1) / len, (z2 - z1) / len);
    const rot = -Math.atan2(dir.y, dir.x);
    const at = (d) => [x1 + dir.x * d, z1 + dir.y * d];
    const piece = (from, to, y0, y1) => {
      if (to - from < 0.01 || y1 - y0 < 0.01) return;
      const [px, pz] = at((from + to) / 2);
      this.box(to - from, y1 - y0, thick, mat, px, base + (y0 + y1) / 2, pz, rot);
    };
    const ops = [...openings].sort((a, b) => a.at - b.at);
    let cursor = 0;
    for (const o of ops) {
      const a = o.at - o.width / 2, b = o.at + o.width / 2;
      piece(cursor, a, 0, height);
      piece(a, b, 0, o.bottom);
      piece(a, b, o.top, height);
      cursor = b;
      if (o.door) {
        const [hx, hz] = at(a + 0.02);
        this.doors.push(new Door(this, hx, base, hz, rot, o.width - 0.04, o.top - 0.02, o.doorMat ?? this.mat.door));
      }
      if (frames) {
        // batentes de madeira em volta da abertura
        const fw = 0.08, ft = thick + 0.06;
        for (const d of [a + fw / 2, b - fw / 2]) {
          const [px, pz] = at(d);
          this.box(fw, o.top - o.bottom, ft, this.mat.wood, px, base + (o.bottom + o.top) / 2, pz, rot, 1, false);
        }
        const [px, pz] = at(o.at);
        this.box(o.width, fw, ft, this.mat.wood, px, base + o.top - fw / 2, pz, rot, 1, false);
        if (o.bottom > 0) this.box(o.width + 0.1, fw, ft + 0.06, this.mat.wood, px, base + o.bottom + fw / 2, pz, rot, 1, false);
      }
    }
    piece(cursor, len, 0, height);
  }

  // ---------- céu, luz e ambiente ----------
  _buildSky() {
    this.sunDir = new THREE.Vector3(-0.55, 0.42, -0.72).normalize();
    const uniforms = {
      uSunDir: { value: this.sunDir },
      uZenith: { value: new THREE.Color(0x5a6874) },
      uHorizon: { value: new THREE.Color(0xb3aa94) },
      uGround: { value: new THREE.Color(0x6e6858) },
      uSunColor: { value: new THREE.Color(0xffbf8a) },
      uTime: { value: 0 },
      uNight: { value: 0 },
      uMoonDir: { value: new THREE.Vector3(0.3, 0.6, 0.7).normalize() },
      uCloudLight: { value: 1 },
    };
    const mat = new THREE.ShaderMaterial({
      uniforms,
      side: THREE.BackSide,
      depthWrite: false,
      fog: false,
      vertexShader: `
        varying vec3 vDir;
        void main() {
          vDir = normalize(position);
          vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
          gl_Position = p.xyww;
        }`,
      fragmentShader: `
        uniform vec3 uSunDir, uZenith, uHorizon, uGround, uSunColor, uMoonDir;
        uniform float uTime, uNight, uCloudLight;
        varying vec3 vDir;
        float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
        float noise(vec2 p) {
          vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
          return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
        }
        float fbm(vec2 p) { float v = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }
        void main() {
          vec3 d = normalize(vDir);
          float h = d.y;
          vec3 col = mix(uHorizon, uZenith, pow(max(h, 0.0), 0.55));
          col = mix(col, uGround, smoothstep(0.0, -0.2, h));
          float sd = max(dot(d, uSunDir), 0.0);
          col += uSunColor * (pow(sd, 6.0) * 0.28 + pow(sd, 48.0) * 0.45);
          if (h > 0.0) {
            vec2 uv = d.xz / (h + 0.12) * 0.9 + vec2(uTime * 0.008, uTime * 0.003);
            float c = fbm(uv * 1.4);
            float cover = smoothstep(0.42, 0.78, c) * smoothstep(0.0, 0.12, h);
            float shade = fbm(uv * 2.8 + 3.0);
            // estrelas e lua (de noite), atrás das nuvens
            if (uNight > 0.01) {
              vec2 sp = d.xz / (h + 0.3) * 160.0;
              float st = step(0.9975, hash(floor(sp))) * (0.5 + 0.5 * sin(uTime * 3.0 + hash(floor(sp) + 3.0) * 40.0));
              col += vec3(st) * uNight * (1.0 - cover) * smoothstep(0.05, 0.3, h);
              float md = dot(d, uMoonDir);
              col += vec3(0.85, 0.9, 1.0) * (smoothstep(0.9993, 0.9996, md) * 1.6 + pow(max(md, 0.0), 60.0) * 0.12) * uNight * (1.0 - cover * 0.85);
            }
            vec3 cloud = mix(vec3(0.52, 0.53, 0.56), vec3(1.0, 0.92, 0.82), clamp(pow(sd, 3.0) * 0.9 + shade * 0.35, 0.0, 1.0)) * uCloudLight;
            col = mix(col, cloud, cover * 0.88);
            col += uSunColor * pow(sd, 700.0) * 5.0 * (1.0 - cover * 0.8);
          }
          gl_FragColor = vec4(col, 1.0);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }`,
    });
    this.skyUniforms = uniforms;
    const sky = new THREE.Mesh(new THREE.SphereGeometry(450, 32, 16), mat);
    sky.renderOrder = -1;
    sky.frustumCulled = false;
    this.sky = sky;
    this.scene.add(sky);
    this.scene.background = new THREE.Color(0xb8b3a2);
    this.scene.fog = new THREE.Fog(0x9f9a8a, 40, 360);
  }

  _buildLights() {
    const hemi = this.hemi = new THREE.HemisphereLight(0xa6b8c8, 0x4b4232, 0.55);
    this.scene.add(hemi);

    const sun = new THREE.DirectionalLight(0xffd0a0, 2.3);
    sun.castShadow = true;
    const sm = this.quality === 'low' ? 1024 : 2048;
    sun.shadow.mapSize.set(sm, sm);
    const r = 52;
    Object.assign(sun.shadow.camera, { left: -r, right: r, top: r, bottom: -r, near: 1, far: 300 });
    sun.shadow.bias = -0.0004;
    sun.shadow.normalBias = 0.04;
    this.scene.add(sun);
    this.scene.add(sun.target);
    this.sun = sun;
  }

  /** Mapa de ambiente gerado a partir do próprio céu: reflexos e luz ambiente realistas. */
  _buildEnvironment(renderer) {
    const pmrem = new THREE.PMREMGenerator(renderer);
    const envScene = new THREE.Scene();
    envScene.add(new THREE.Mesh(this.sky.geometry, this.sky.material));
    this.scene.environment = pmrem.fromScene(envScene, 0.03).texture;
    pmrem.dispose();
  }

  /**
   * Hora do dia (0–24): sol andando no céu (cor de pôr do sol perto do horizonte), luar azulado
   * de noite, céu/neblina/ambiente acompanhando. Os reflexos do céu HDRI escurecem junto.
   */
  setTimeOfDay(h) {
    this.tod = ((h % 24) + 24) % 24;
    const a = (this.tod - 6) / 12 * Math.PI;          // 0 no nascer, PI no pôr
    const el = Math.sin(a) * 0.95;                      // altura do sol
    const az = a * 0.9 - 0.6;
    this.sunDir.set(Math.cos(az) * Math.cos(Math.asin(el)), el, Math.sin(az) * Math.cos(Math.asin(el)) - 0.35).normalize();
    const day = smoothstep(-0.12, 0.3, this.sunDir.y), low = 1 - smoothstep(0.05, 0.45, this.sunDir.y);
    this.dayK = day;
    const night = 1 - smoothstep(-0.2, 0.05, this.sunDir.y);
    const C = (hex) => new THREE.Color(hex);
    const U = this.skyUniforms;
    const pick = (dayC, duskC, nightC) => C(dayC).lerp(C(duskC), low * day).lerp(C(nightC), night);
    U.uZenith.value.copy(pick(0x5a6874, 0x4a5466, 0x0b1220));
    U.uHorizon.value.copy(pick(0xb3aa94, 0xd09a6a, 0x1b2230));
    U.uGround.value.copy(pick(0x6e6858, 0x5a4a3a, 0x0e1014));
    U.uSunColor.value.copy(pick(0xffbf8a, 0xff8a4a, 0x000000)).multiplyScalar(day);
    U.uNight.value = night;
    U.uCloudLight.value = 0.18 + 0.82 * day;
    U.uMoonDir.value.set(-this.sunDir.x, Math.max(0.25, -this.sunDir.y), -this.sunDir.z).normalize();
    // luz direta: sol (dourado ao entardecer) ou lua
    const moon = night > 0.5;
    this.lightDir = moon ? U.uMoonDir.value : this.sunDir;
    this.sun.color.copy(moon ? C(0x8fa6d8) : C(0xffd0a0).lerp(C(0xff9a5a), low));
    this.sun.intensity = moon ? 0.28 * night : 2.4 * day;
    this.hemi.intensity = 0.1 + 0.48 * day + night * 0.06;
    this.hemi.color.copy(C(0xa6b8c8).lerp(C(0x33405e), night));
    this.hemi.groundColor.copy(C(0x4b4232).lerp(C(0x0d0f14), night));
    const fog = U.uHorizon.value.clone().lerp(C(0x9f9a8a), day * 0.5);
    this.scene.fog.color.copy(fog);
    if (this.scene.background?.isColor) this.scene.background.copy(fog);
    this.envK = 0.06 + 0.94 * day;
    this.night = night;
  }

  /** Reflexos/luz do céu HDRI: mais fracos de noite (por material, sem recompilar). */
  _applyEnvIntensity() {
    if (!this._envMats || this._envScan-- <= 0) {
      this._envScan = 20;
      this._envMats = this._envMats ?? new Set();
      this.scene.traverse((o) => { for (const m of o.material ? [o.material].flat() : []) if (m.envMapIntensity !== undefined && !this._envMats.has(m)) { m.userData.envBase = m.envMapIntensity; this._envMats.add(m); } });
    }
    for (const m of this._envMats) m.envMapIntensity = (m.userData.envBase ?? 1) * this.envK;
  }

  /** Vento, nuvens e área de sombra centrada no jogador. */
  update(playerPos, time = 0) {
    this.windUniform.value = time;
    this.skyUniforms.uTime.value = time;
    if (this.tod !== undefined) {
      this._envT = (this._envT ?? 0) - 1;
      if (this._envT <= 0) { this._envT = 15; this._applyEnvIntensity(); }
    }
    if (this.waterMesh) this.waterMesh.material.normalMap.offset.set(time * 0.012, time * 0.007);
    const snap = 4; // reduz "tremido" da sombra
    const x = Math.round(playerPos.x / snap) * snap;
    const z = Math.round(playerPos.z / snap) * snap;
    this.sun.target.position.set(x, 0, z);
    this.sun.position.set(x, 0, z).addScaledVector(this.lightDir ?? this.sunDir, 150);
    this.sky.position.set(playerPos.x, playerPos.y, playerPos.z);
    // tapete de grama acompanha o jogador (de bloco em bloco)
    if (this.grass) {
      const T = this.grassTile;
      this.grassUniforms.uAnchor.value.set(Math.floor(playerPos.x / T) * T, Math.floor(playerPos.z / T) * T);
      this.grassUniforms.uEye.value.copy(playerPos);
    }
    // árvores e construções de longe não são desenhadas (somem na neblina de qualquer jeito)
    const far = this.drawDistance ?? 380;
    for (const c of this.lodChunks) c.visible = Math.hypot(c.userData.center.x - playerPos.x, c.userData.center.y - playerPos.z) < far + 90;
  }

  setShadowMapSize(size) {
    if (this.sun.shadow.mapSize.x === size) return;
    this.sun.shadow.mapSize.set(size, size);
    this.sun.shadow.map?.dispose();
    this.sun.shadow.map = null;
  }

  /** Faz a geometria balançar com o vento (copas, arbustos, grama). */
  addWind(material, amount, heightScale) {
    material.onBeforeCompile = (shader) => {
      shader.uniforms.uTime = this.windUniform;
      shader.vertexShader = 'uniform float uTime;\n' + shader.vertexShader.replace(
        '#include <begin_vertex>',
        `#include <begin_vertex>
        #ifdef USE_INSTANCING
          float ph = instanceMatrix[3][0] * 0.35 + instanceMatrix[3][2] * 0.25;
          float hk = max(position.y, 0.0) * ${heightScale.toFixed(3)};
          float sway = sin(uTime * 1.6 + ph) * 0.6 + sin(uTime * 3.7 + ph * 2.0) * 0.25;
          transformed.x += sway * ${amount.toFixed(3)} * hk;
          transformed.z += cos(uTime * 1.3 + ph) * ${(amount * 0.6).toFixed(3)} * hk;
        #endif`
      );
    };
    material.customProgramCacheKey = () => 'wind' + amount + heightScale;
  }

  // ---------- terreno ----------
  _buildTerrain() {
    const geo = new THREE.PlaneGeometry(WORLD_SIZE, WORLD_SIZE, GRID, GRID);
    geo.rotateX(-Math.PI / 2);
    const pos = geo.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      const ix = Math.round((pos.getX(i) + WORLD_SIZE / 2) / CELL), iz = Math.round((pos.getZ(i) + WORLD_SIZE / 2) / CELL);
      pos.setY(i, HEIGHTS[iz * (GRID + 1) + ix]);
    }
    geo.computeVertexNormals();

    // cores por vértice: grama verde/seca, manchas escuras, terra, trilhas e pedra nas encostas
    const nrm = geo.attributes.normal;
    const cGrass = new THREE.Color(0x5b6a33), cDry = new THREE.Color(0x8f8148), cDark = new THREE.Color(0x3f4c26);
    const cDirt = new THREE.Color(0x6e563a), cRock = new THREE.Color(0x77736a), cLeafy = new THREE.Color(0x8a5a2c);
    const colors = new Float32Array(pos.count * 3);
    // pesos para as texturas fotográficas (grama verde, chão seco com folhas, rocha, terra) e um
    // tom (manchas mais escuras/claras) — usados pelo material do terreno em photoAssets.js
    const splat = new Float32Array(pos.count * 4);
    const tint = new Float32Array(pos.count);
    const c = new THREE.Color();
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i), z = pos.getZ(i);
      {
        const green = 1 - smoothstep(0.36, 0.7, valueNoise(x * 0.035, z * 0.035));
        const forestZone = smoothstep(TOWN_RADIUS, TOWN_RADIUS + 20, Math.hypot(x, z));
        const g = green * (1 - forestZone * 0.6);
        const rock = Math.min(1, smoothstep(0.88, 0.7, nrm.getY(i)) + smoothstep(0.8, 0.93, valueNoise(x * 0.05 + 90, z * 0.05 - 30)) * 0.7);
        const wear = smoothstep(16, 4, Math.hypot(x - 8, z - 6)) * 0.4;
        const dirtW = Math.max(smoothstep(0.74, 0.9, valueNoise(x * 0.15 + 7, z * 0.15 + 3)) * 0.7, trailMask(x, z), wear);
        splat[i * 4] = g * (1 - rock);
        splat[i * 4 + 1] = (1 - g) * (1 - rock) + 0.05;
        splat[i * 4 + 2] = rock;
        splat[i * 4 + 3] = dirtW * (1 - rock * 0.7);
        tint[i] = (1 - 0.28 * smoothstep(0.55, 0.85, valueNoise(x * 0.09 + 20, z * 0.09))) * (0.92 + 0.14 * valueNoise(x * 0.4 + 3, z * 0.4 + 9));
      }
      c.copy(cGrass).lerp(cDry, smoothstep(0.42, 0.78, valueNoise(x * 0.035, z * 0.035)));
      c.lerp(cDark, smoothstep(0.55, 0.85, valueNoise(x * 0.09 + 20, z * 0.09)) * 0.6);
      // folhas secas acumuladas na floresta
      const forest = smoothstep(TOWN_RADIUS, TOWN_RADIUS + 20, Math.hypot(x, z));
      c.lerp(cLeafy, forest * smoothstep(0.5, 0.8, valueNoise(x * 0.12 + 40, z * 0.12)) * 0.55);
      const wear = smoothstep(16, 4, Math.hypot(x - 8, z - 6)) * 0.35; // chão gasto no centro
      const dirt = Math.max(smoothstep(0.72, 0.88, valueNoise(x * 0.15 + 7, z * 0.15 + 3)) * 0.8, trailMask(x, z), wear);
      c.lerp(cDirt, dirt);
      c.lerp(cRock, smoothstep(0.86, 0.7, nrm.getY(i)));
      colors[i * 3] = c.r; colors[i * 3 + 1] = c.g; colors[i * 3 + 2] = c.b;
    }
    geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geo.setAttribute('splat', new THREE.BufferAttribute(splat, 4));
    geo.setAttribute('tint', new THREE.BufferAttribute(tint, 1));
    const uv = geo.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * 90 * WORLD_SIZE / 300, uv.getY(i) * 90 * WORLD_SIZE / 300);

    const ground = new THREE.Mesh(geo, this.mat.ground);
    ground.receiveShadow = true;
    this.terrainMesh = ground;
    this.scene.add(ground);
    // (o terreno não entra no Octree: a colisão com ele é pela grade de alturas — bem mais leve)

    // estrada de asfalto velho acompanhando o relevo, de ponta a ponta do mapa
    const road = new THREE.PlaneGeometry(ROAD_HALF * 2, WORLD_HALF * 2, 1, 600);
    road.rotateX(-Math.PI / 2);
    const rp = road.attributes.position;
    for (let i = 0; i < rp.count; i++) {
      const x = rp.getX(i) + ROAD_X, z = rp.getZ(i);
      rp.setXYZ(i, x, terrainHeight(x, z) + 0.05, z);
    }
    road.computeVertexNormals();
    const ruv = road.attributes.uv;
    for (let i = 0; i < ruv.count; i++) ruv.setXY(i, ruv.getX(i), ruv.getY(i) * WORLD_HALF * 2 / 8);
    const roadMesh = new THREE.Mesh(road, this.mat.asphalt);
    roadMesh.receiveShadow = true;
    this.scene.add(roadMesh);
    this.noGrass.push([ROAD_X - ROAD_HALF - 0.4, -WORLD_HALF, ROAD_X + ROAD_HALF + 0.4, WORLD_HALF]);
    // estradas secundárias: faixas que acompanham o relevo
    for (const r of ROADS) {
      const pts = [];
      for (let i = 0; i < r.length - 1; i++) {
        const [ax, az] = r[i], [bx, bz] = r[i + 1];
        const n = Math.ceil(Math.hypot(bx - ax, bz - az) / 2);
        for (let k = i ? 1 : 0; k <= n; k++) pts.push([ax + (bx - ax) * k / n, az + (bz - az) * k / n]);
      }
      const P = [], UV = [], I = [];
      let along = 0;
      for (let k = 0; k < pts.length; k++) {
        const [x, z] = pts[k], [x0, z0] = pts[Math.max(0, k - 1)], [x1, z1] = pts[Math.min(pts.length - 1, k + 1)];
        let tx = x1 - x0, tz = z1 - z0; const tl = Math.hypot(tx, tz) || 1; tx /= tl; tz /= tl;
        if (k) along += Math.hypot(x - pts[k - 1][0], z - pts[k - 1][1]);
        for (const sgn of [-1, 1]) {
          const px = x - tz * sgn * ROAD_HALF * 0.85, pz = z + tx * sgn * ROAD_HALF * 0.85;
          P.push(px, terrainHeight(px, pz) + 0.06, pz);
          UV.push(sgn < 0 ? 0 : 1, along / 8);
        }
        if (k) { const a = (k - 1) * 2; I.push(a, a + 1, a + 2, a + 1, a + 3, a + 2); }
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3));
      g.setAttribute('uv', new THREE.Float32BufferAttribute(UV, 2));
      g.setIndex(I);
      g.computeVertexNormals();
      const m = new THREE.Mesh(g, this.mat.asphalt);
      m.receiveShadow = true;
      this.scene.add(m);
    }
  }

  /** Sem grama/árvore perto das estradas e dos lugares. */
  _nearRoadOrPoi(x, z, margin = 0) {
    if (roadDistance(x, z) < ROAD_HALF + 1.5 + margin) return true;
    for (const p of POIS) if (Math.hypot(x - p.x, z - p.z) < p.r * 0.8 + margin) return true;
    return false;
  }

  // ---------- construções ----------
  _buildBrickHouse() {
    const M = this.mat;
    const cx = 14, cz = -8, w = 10, d = 8, h = 3.2;
    const x0 = cx - w / 2, x1 = cx + w / 2, z0 = cz - d / 2, z1 = cz + d / 2;
    this.noGrass.push([x0 - 0.5, z0 - 0.6, x1 + 2.2, z1 + 0.6]);
    // piso + fundação aparente
    this.box(w, 0.2, d, M.concrete, cx, 0.1, cz, 0, 2);
    this.box(w + 0.1, 0.3, d + 0.1, M.concrete, cx, -0.05, cz, 0, 2, false);
    // parede frontal (z1) com porta e janela
    this.wall(x0, z1, x1, z1, { height: h, frames: true, openings: [
      { at: 3, width: 1.4, bottom: 0, top: 2.3, door: true },
      { at: 7.2, width: 1.6, bottom: 1.0, top: 2.2 },
    ] });
    this.wall(x0, z0, x1, z0, { height: h, frames: true, openings: [{ at: 5, width: 2, bottom: 1.0, top: 2.2 }] });
    this.wall(x0, z0, x0, z1, { height: h, frames: true, openings: [{ at: 4, width: 1.4, bottom: 1.0, top: 2.2 }] });
    this.wall(x1, z0, x1, z1, { height: h });
    // divisória interna com vão
    this.wall(cx + 1, z0, cx + 1, z1, { height: h, thick: 0.15, mat: M.paint, openings: [{ at: 5.5, width: 1.2, bottom: 0, top: 2.3, door: true }] });
    // laje / terraço + teto interno claro
    this.box(w + 0.6, 0.25, d + 0.6, M.roof, cx, h + 0.12, cz, 0, 3);
    this.box(w - 0.3, 0.02, d - 0.3, M.paint, cx, h - 0.01, cz, 0, 3, false);
    // mureta do terraço (com abertura onde chega a escada)
    const ph = 0.7, top = h + 0.25;
    this.wall(x0 - 0.3, z0 - 0.3, x1 + 0.3, z0 - 0.3, { height: ph, base: top, thick: 0.15, mat: M.concrete });
    this.wall(x0 - 0.3, z1 + 0.3, x1 + 0.3, z1 + 0.3, { height: ph, base: top, thick: 0.15, mat: M.concrete });
    this.wall(x0 - 0.3, z0 - 0.3, x0 - 0.3, z1 + 0.3, { height: ph, base: top, thick: 0.15, mat: M.concrete });
    this.wall(x1 + 0.3, z0 - 0.3, x1 + 0.3, z1 + 0.3, { height: ph, base: top, thick: 0.15, mat: M.concrete,
      openings: [{ at: (cz - 2.6) - (z0 - 0.3), width: 1.4, bottom: 0, top: ph }] });
    // escada externa encostada na lateral, subindo em direção aos fundos
    this.stairs(x1 + 1.1, cz + 4, x1 + 1.1, cz - 2, top, 1.5);
    // caixa d'água no terraço
    this.cylinder(0.6, 0.6, 1.1, M.paint, cx - 3, top + 0.55, cz - 2, { seg: 14 });

    // móveis
    this.box(1.6, 0.08, 0.9, M.wood, cx - 3, 0.96, cz - 2.6);           // tampo da mesa
    for (const [dx, dz] of [[-0.7, -0.35], [0.7, -0.35], [-0.7, 0.35], [0.7, 0.35]]) {
      this.box(0.07, 0.72, 0.07, M.wood, cx - 3 + dx, 0.56, cz - 2.6 + dz, 0, 1, false);
    }
    this.invisibleCollider(new THREE.BoxGeometry(1.6, 0.8, 0.9), new THREE.Vector3(cx - 3, 0.6, cz - 2.6));
    this.box(0.9, 1.8, 0.5, M.wood, cx + 4.2, 1.1, cz - 3.4);           // armário
    this.box(2, 0.3, 1, M.wood, cx + 3.5, 0.35, cz + 2.5);              // cama
    this.box(1.9, 0.18, 0.95, M.fabric, cx + 3.5, 0.59, cz + 2.5, 0, 1, false);
    this.box(0.5, 0.12, 0.8, M.paint, cx + 4.25, 0.72, cz + 2.5, 0, 1, false); // travesseiro
    this.box(1.8, 0.85, 0.5, M.fabric, cx - 3.5, 0.62, cz + 3.4);       // sofá
  }

  _buildCabin() {
    const M = this.mat;
    const cx = 18, cz = 20, w = 7, d = 6, h = 2.7;
    const x0 = cx - w / 2, x1 = cx + w / 2, z0 = cz - d / 2, z1 = cz + d / 2;
    this.noGrass.push([x0 - 0.6, z0 - 1.8, x1 + 0.6, z1 + 0.6]);
    this.box(w, 0.2, d, M.plank, cx, 0.1, cz, 0, 1.5);
    const opts = { height: h, thick: 0.2, mat: M.plank, frames: true };
    this.wall(x0, z0, x1, z0, { ...opts, openings: [
      { at: 3.5, width: 1.2, bottom: 0, top: 2.2, door: true },
      { at: 1.3, width: 1.0, bottom: 1.0, top: 2.0 },
      { at: 5.7, width: 1.0, bottom: 1.0, top: 2.0 },
    ] });
    this.wall(x0, z1, x1, z1, { ...opts, openings: [{ at: 3.5, width: 1.2, bottom: 1.0, top: 2.0 }] });
    this.wall(x0, z0, x0, z1, { ...opts, openings: [{ at: 3, width: 1.0, bottom: 1.0, top: 2.0 }] });
    this.wall(x1, z0, x1, z1, { ...opts });
    // varanda com degrau (rampa invisível suave)
    this.box(w, 0.2, 1.4, M.plank, cx, 0.1, z0 - 0.7, 0, 1.5);
    for (const px of [x0 + 0.1, x1 - 0.1]) this.box(0.14, h, 0.14, M.wood, px, h / 2, z0 - 1.3, 0, 1);
    // telhado de duas águas (chapas de metal enferrujadas)
    const rise = 1.4, run = d / 2 + 0.45;
    const ang = Math.atan2(rise, run), slab = Math.hypot(rise, run);
    for (const s of [-1, 1]) {
      const roof = new THREE.Mesh(boxGeo(w + 0.9, 0.1, slab, 2), M.rust);
      roof.position.set(cx, h + rise / 2 + 0.05, cz + s * run / 2);
      roof.rotation.x = s * ang;
      this.solid(roof);
    }
    // varanda coberta
    const porch = new THREE.Mesh(boxGeo(w + 0.4, 0.08, 1.5, 2), M.rust);
    porch.position.set(cx, h - 0.05, z0 - 0.75);
    porch.rotation.x = -0.18;
    this.solid(porch);
    // empenas triangulares
    const tri = new THREE.Shape();
    tri.moveTo(-d / 2, 0); tri.lineTo(d / 2, 0); tri.lineTo(0, rise); tri.lineTo(-d / 2, 0);
    const gable = new THREE.ExtrudeGeometry(tri, { depth: 0.2, bevelEnabled: false });
    gable.translate(0, 0, -0.1);
    gable.rotateY(Math.PI / 2);
    for (const gx of [x0, x1]) {
      const m = new THREE.Mesh(gable, M.plank);
      m.position.set(gx, h, cz);
      this.solid(m, false);
    }
    // interior
    this.box(1.9, 0.35, 0.9, M.wood, x1 - 1.1, 0.37, z1 - 0.6);         // cama
    this.box(1.8, 0.15, 0.85, M.fabric, x1 - 1.1, 0.62, z1 - 0.6, 0, 1, false);
    this.box(1.2, 0.06, 0.8, M.wood, cx - 1.5, 0.95, cz + 0.5);         // mesa
    this.invisibleCollider(new THREE.BoxGeometry(1.2, 0.8, 0.8), new THREE.Vector3(cx - 1.5, 0.6, cz + 0.5));
    for (const dx of [-0.5, 0.5]) for (const dz of [-0.33, 0.33]) {
      this.box(0.06, 0.72, 0.06, M.wood, cx - 1.5 + dx, 0.56, cz + 0.5 + dz, 0, 1, false);
    }
    this.box(0.45, 0.45, 0.45, M.wood, cx - 1.5, 0.42, cz + 1.25, 0, 1, false); // banquinho
    this.box(0.6, 0.9, 0.6, M.metal, x0 + 0.45, 0.65, z1 - 0.45);       // fogão a lenha
    this.cylinder(0.08, 0.08, 2.4, M.metal, x0 + 0.45, 2.2, z1 - 0.45, { seg: 8, collide: false });
    this.box(1.4, 1.6, 0.35, M.wood, x0 + 1.6, 1.0, z1 - 0.3);          // estante
  }

  _buildGasStation() {
    const M = this.mat;
    const cx = -14, cz = 24;
    this.noGrass.push([cx - 4.6, cz - 3.4, cx + 4.6, cz + 3.4], [-23.5, 20, -18.5, 25.5]);
    this.box(9, 0.12, 6.6, M.concrete, cx, 0.06, cz, 0, 3);              // piso
    for (const dx of [-3, 3]) for (const dz of [-2.2, 2.2]) {
      this.cylinder(0.16, 0.16, 4.3, M.paint, cx + dx, 2.2, cz + dz, { seg: 10 });
    }
    this.box(8.6, 0.45, 6.2, M.paint, cx, 4.55, cz, 0, 3);               // cobertura
    this.box(8.7, 0.25, 6.3, M.redPaint, cx, 4.3, cz, 0, 3, false);      // faixa
    for (const dx of [-1.6, 1.6]) {
      this.box(0.6, 1.3, 0.45, M.redPaint, cx + dx, 0.77, cz);           // bombas
      this.box(0.5, 0.35, 0.47, M.paint, cx + dx, 1.25, cz, 0, 1, false);
      this.box(0.9, 0.25, 0.7, M.concrete, cx + dx, 0.24, cz, 0, 1, false);
    }
    // loja de conveniência
    const kx = -21, kz = 22.75, kw = 4, kd = 3.5, kh = 2.8;
    const opts = { height: kh, thick: 0.2, mat: M.concrete, frames: true };
    this.box(kw, 0.15, kd, M.concrete, kx, 0.075, kz, 0, 2);
    this.wall(kx + kw / 2, kz - kd / 2, kx + kw / 2, kz + kd / 2, { ...opts, openings: [
      { at: 1.0, width: 1.1, bottom: 0, top: 2.2, door: true }, { at: 2.6, width: 1.3, bottom: 0.9, top: 2.1 },
    ] });
    this.wall(kx - kw / 2, kz - kd / 2, kx - kw / 2, kz + kd / 2, opts);
    this.wall(kx - kw / 2, kz - kd / 2, kx + kw / 2, kz - kd / 2, { ...opts, openings: [{ at: 2, width: 1.4, bottom: 1.0, top: 2.0 }] });
    this.wall(kx - kw / 2, kz + kd / 2, kx + kw / 2, kz + kd / 2, opts);
    this.box(kw + 0.4, 0.2, kd + 0.4, M.roof, kx, kh + 0.1, kz, 0, 2);
    this.box(0.6, 1.0, 2.0, M.wood, kx + 0.6, 0.65, kz);                // balcão
    this.box(0.4, 1.8, 2.6, M.metal, kx - 1.7, 1.05, kz);               // prateleira
    // placa
    this.cylinder(0.1, 0.1, 6, M.metal, cx + 5.2, 3, cz - 3.5, { seg: 8 });
    this.box(0.15, 1.2, 2.2, M.redPaint, cx + 5.2, 6.1, cz - 3.5, 0, 1, false);
  }

  _buildTower() {
    const M = this.mat;
    const cx = 30, cz = -22, half = 1.5, top = 5.6;
    this.noGrass.push([cx - 2.2, cz - 2.2, cx + 2.2, cz + 2.6]);
    for (const dx of [-half, half]) for (const dz of [-half, half]) {
      this.box(0.25, 8.2, 0.25, M.wood, cx + dx, 4.1, cz + dz, 0, 1);
    }
    // travamentos em X (visuais)
    for (const s of [-1, 1]) {
      for (const [ax, az, rot] of [[0, -half, 0], [0, half, 0], [-half, 0, Math.PI / 2], [half, 0, Math.PI / 2]]) {
        const b = new THREE.Mesh(boxGeo(0.1, 4.5, 0.1, 1), M.wood);
        b.position.set(cx + ax, 2.6, cz + az);
        b.rotation.set(0, rot, s * 0.6, 'YXZ');
        this.solid(b, false);
      }
    }
    // plataforma, guarda-corpo com vão para a escada e telhado
    this.box(3.6, 0.2, 3.6, M.plank, cx, top - 0.1, cz, 0, 1.5);
    const rail = { height: 1.0, base: top, thick: 0.08, mat: M.plank };
    this.wall(cx - 1.8, cz - 1.8, cx + 1.8, cz - 1.8, rail);
    this.wall(cx - 1.8, cz - 1.8, cx - 1.8, cz + 1.8, rail);
    this.wall(cx + 1.8, cz - 1.8, cx + 1.8, cz + 1.8, rail);
    this.wall(cx - 1.8, cz + 1.8, cx + 1.8, cz + 1.8, { ...rail, openings: [{ at: 1.8, width: 1.0, bottom: 0, top: 1.0 }] });
    this.box(4.4, 0.12, 4.4, M.rust, cx, 8.25, cz, 0, 2);
    this.ladder(cx, cz + 1.8 + 0.12, 0, 1, 0, top);
    this.box(0.6, 0.6, 0.4, M.wood, cx + 1.1, top + 0.3, cz - 1.2, 0, 1); // caixote lá em cima
  }

  /**
   * Escada de mão. (nx, nz) = direção para onde a escada "olha" (o lado de quem sobe).
   */
  ladder(x, z, nx, nz, bottom, top, width = 0.6) {
    const tx = -nz, tz = nx; // tangente (largura)
    const rot = Math.atan2(tx, tz) + Math.PI / 2;
    const len = top - bottom + 0.9;
    for (const s of [-1, 1]) {
      this.box(0.06, len, 0.06, this.mat.metal, x + tx * s * width / 2, bottom + len / 2, z + tz * s * width / 2, rot, 1, false);
    }
    for (let y = bottom + 0.3; y < top + 0.2; y += 0.3) {
      const r = new THREE.Mesh(new THREE.CylinderGeometry(0.022, 0.022, width, 6), this.mat.metal);
      r.position.set(x, y, z);
      r.rotation.set(0, rot, Math.PI / 2, 'YXZ');
      this.solid(r, false);
    }
    this.ladders.push({ x, z, nx, nz, tx, tz, width, bottom, top });
  }

  // ---------- objetos do vilarejo ----------
  _buildTown() {
    const M = this.mat;

    // ===== Contêineres (parkour) =====
    this.container(-20, -14, 0, 0, M.rust);
    this.container(-20, -11.4, 0, 0, M.rust);
    this.container(-20, -12.7, 0, 2.6, M.rust); // empilhado
    this.container(-28, 6, Math.PI / 2.4, 0, M.rust);
    this.noGrass.push([-23.2, -15.4, -16.8, -10]);
    // rampa até o contêiner de cima
    {
      const len = 8, rise = 5.2;
      const ramp = new THREE.Mesh(boxGeo(2.4, 0.2, Math.hypot(len, rise), 1.5), M.plank);
      ramp.position.set(-20, rise / 2, -11.5 + len / 2);
      ramp.rotation.x = Math.atan2(rise, len);
      this.solid(ramp);
    }
    // escada de mão no fundo da pilha
    this.ladder(-23.1, -12.7, -1, 0, 0, 5.2);

    // ===== Carros abandonados =====
    this.car(-6, 8, 0.2, { color: 0x4f6670, seed: 1, flat: ['fl'], doorOpen: true, cracked: true });
    this.car(-2.5, -18, Math.PI + 0.35, { color: 0x7a2a22, seed: 2, hoodOpen: true, cracked: true, flat: ['rl', 'rr'] });
    this.car(4, 26, Math.PI / 2 - 0.2, { burnt: true });
    this.car(-1.5, 52, 0.05, { color: 0x6a6a3a, seed: 3, doorOpen: true, missingGlass: true });
    this.car(-6.5, -60, Math.PI - 0.25, { burnt: true, flipped: true }); // capotado
    this._buildRoadblock();
    this._buildDebris();
    this._buildCamp();
    this._buildDecals();

    // ===== Caixotes, barris, pneus, sacos de areia =====
    const crates = [[3, 3], [3.6, 4.2], [-12, 2], [-12, 3.1], [24, 6], [24.6, 7.2], [8, -20], [-30, -2], [-15.5, 21.5]];
    crates.forEach(([x, z], i) => this.box(1.1, 1.1, 1.1, M.wood, x, 0.55, z, i * 0.4, 1.1));
    this.box(1.1, 1.1, 1.1, M.wood, 3.2, 1.65, 3.5, 0.2, 1.1); // caixote empilhado
    const barrels = [[6, 10], [6.8, 10.5], [-14, -6], [20, 14], [-8, 22], [-11.5, 27.5], [-12.2, 27.9]];
    barrels.forEach(([x, z], i) => this.barrel(x, z, i % 3 === 0 ? M.rust : M.barrel));
    this.barrel(-14.5, -5.4, M.barrel, true); // tombado
    for (const [x, z] of [[-24, -6], [-24.3, -5.2]]) {
      for (let k = 0; k < 3; k++) {
        const t = new THREE.Mesh(new THREE.TorusGeometry(0.33, 0.14, 8, 14), M.tire);
        t.rotation.x = Math.PI / 2;
        t.position.set(x, 0.14 + k * 0.27, z);
        this.solid(t, k === 0);
      }
    }
    this.sandbags(25, -14, 0.3);
    this.sandbags(-31, -16, Math.PI / 2 + 0.2);

    // ===== Cerca de madeira ao redor do vilarejo (com aberturas) =====
    const R = 36, posts = 56;
    for (let i = 0; i < posts; i++) {
      const a0 = (i / posts) * Math.PI * 2, a1 = ((i + 1) / posts) * Math.PI * 2;
      // 4 entradas + partes quebradas/derrubadas
      const skip = (i % 14 === 0) || (i % 14 === 1) || i === 23 || i === 38 || i === 9 || i === 31 || i === 46 || i === 52;
      if (skip) continue;
      const xa = Math.cos(a0) * R, za = Math.sin(a0) * R;
      const xb = Math.cos(a1) * R, zb = Math.sin(a1) * R;
      const tilt = (hash(i, 3) - 0.5) * 0.3;
      const post = new THREE.Mesh(boxGeo(0.15, 1.3, 0.15, 1), M.wood);
      post.position.set(xa, 0.65, za);
      post.rotation.set(tilt, 0, tilt * 0.5);
      this.solid(post, false);
      const len = Math.hypot(xb - xa, zb - za);
      const rot = -Math.atan2(zb - za, xb - xa);
      // trilhos visuais + um colisor único por trecho
      this.box(len, 0.12, 0.06, M.wood, (xa + xb) / 2, 0.45, (za + zb) / 2, rot, 1, false);
      if (i % 5 !== 2) this.box(len, 0.12, 0.06, M.wood, (xa + xb) / 2, 0.95, (za + zb) / 2, rot, 1, false);
      this.invisibleCollider(new THREE.BoxGeometry(len, 1.1, 0.2), new THREE.Vector3((xa + xb) / 2, 0.55, (za + zb) / 2), new THREE.Euler(0, rot, 0));
    }

    // ===== Postes de luz =====
    [[2, -2, 0], [-10, 14, 0], [-10, -14, 0.12]].forEach(([x, z, tilt]) => {
      this.cylinder(0.09, 0.13, 6, M.metal, x, 3, z, { seg: 8, rz: tilt });
      this.box(1.4, 0.1, 0.2, M.metal, x + 0.6 - tilt * 6, 5.9, z, 0, 1, false);
    });

    // ===== Muro em ruínas =====
    this.wall(-34, -24, -16, -30, { height: 2.2, thick: 0.35, mat: M.concrete, openings: [
      { at: 6, width: 2.5, bottom: 0, top: 2.2 },
      { at: 12, width: 2, bottom: 1.1, top: 2.2 },
    ] });
    for (let i = 0; i < 6; i++) { // entulho
      const r = new THREE.Mesh(lumpy(new THREE.DodecahedronGeometry(0.35, 0), 0.4, i), M.concrete);
      r.position.set(-26 + i * 0.5 + hash(i, 1), 0.15, -27 + hash(i, 2) * 1.2);
      r.rotation.set(i, i * 2, 0);
      this.solid(r, false);
    }

    // ===== Objetos soltos (com física) =====
    const P = (type, x, y, z) => this.propSpots.push({ type, x, y, z });
    P('can', 10.6, 1.0, -10.5); P('bottle', 11.2, 1.0, -10.75); P('can', 11.5, 1.0, -10.4); P('pot', 10.9, 1.0, -10.9);
    P('bucket', 16.6, 0.2, -5.4); P('pot', 18, 0.2, -11.2);
    P('pot', 16.3, 0.98, 20.4); P('bottle', 16.9, 0.98, 20.6); P('can', 16.05, 0.98, 20.75);
    P('can', -20.4, 1.15, 22.2); P('can', -20.4, 1.15, 22.6); P('can', -20.35, 1.15, 23.1); P('bottle', -20.4, 1.15, 23.5);
    P('jerrycan', -12.4, 0.12, 25.3); P('jerrycan', -15.9, 0.12, 22.5); P('bucket', -11, 0.12, 22);
    P('can', 7.8, 0.81, 3.1); P('can', 8.35, 0.81, 2.85); P('bottle', 8.1, 0.81, 3.25);
    P('pot', 7.7, 0, 16.7); P('can', 6.1, 0, 17.5); P('bottle', 8.3, 0, 15.2); P('can', 5.6, 0, 15.6);
    P('can', -3, 0.05, 5); P('can', -5.5, 0.05, -10); P('bottle', -1.5, 0.05, 18);
    P('crate', -17.4, 0, -9); P('crate', -16.7, 0, -8.4); P('crate', -17.1, 0.36, -8.8);
    P('bucket', 15, 0.2, 16.6); P('can', 30.6, 5.6, -22.5); P('bucket', 12, 3.45, -6);
    P('jerrycan', 26.5, 0, -12.6); P('can', 25.6, 0.85, -14.2);

    // ===== Mesa de piquenique =====
    this.box(1.8, 0.06, 0.8, M.wood, 8, 0.78, 3, 0.4);
    this.invisibleCollider(new THREE.BoxGeometry(1.8, 0.8, 0.8), new THREE.Vector3(8, 0.4, 3), new THREE.Euler(0, 0.4, 0));
    for (const s of [-1, 1]) {
      const ox = -Math.sin(0.4) * 0.65 * s, oz = -Math.cos(0.4) * 0.65 * s;
      this.box(1.8, 0.05, 0.28, M.wood, 8 + ox, 0.45, 3 + oz, 0.4, 1, false);
    }
  }

  sandbags(x, z, rot, by = 0) {
    const c = Math.cos(rot), s = Math.sin(rot);
    for (let row = 0; row < 3; row++) {
      for (let i = 0; i < 5 - (row === 2 ? 1 : 0); i++) {
        const off = (i - 2 + (row % 2) * 0.5) * 0.62;
        const g = lumpy(new THREE.CapsuleGeometry(0.17, 0.32, 3, 8), 0.12, row * 10 + i);
        g.rotateZ(Math.PI / 2);
        g.scale(1, 0.75, 1.15);
        const m = new THREE.Mesh(g, this.mat.sandbag);
        m.position.set(x + c * off, by + 0.14 + row * 0.27, z - s * off);
        m.rotation.y = rot + (hash(row, i) - 0.5) * 0.15;
        this.solid(m, false);
      }
    }
    this.invisibleCollider(new THREE.BoxGeometry(3.2, 0.85, 0.45), new THREE.Vector3(x, by + 0.42, z), new THREE.Euler(0, rot, 0));
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
    // corrimão
    const rail = new THREE.Mesh(boxGeo(0.05, 0.05, Math.hypot(len, height)), this.mat.metal);
    const ox = Math.cos(rotY) * (width / 2), oz = -Math.sin(rotY) * (width / 2);
    rail.position.set(xStart + dx * len / 2 + ox, height / 2 + 0.9, zStart + dz * len / 2 + oz);
    rail.rotation.set(-Math.atan2(height, len), rotY, 0, 'YXZ');
    this.solid(rail, false);
    // colisão em forma de cunha: o capsule sobe suave em vez de travar em cada degrau
    this.invisibleCollider(wedgeGeo(width, len, height), new THREE.Vector3(xStart, 0, zStart), new THREE.Euler(0, rotY, 0));
  }

  container(x, z, rotY, baseY, mat) {
    const L = 6, H = 2.6, W = 2.4;
    this.box(L, H, W, mat, x, baseY + H / 2, z, rotY, 2.6);
    // portas e barras de travamento na ponta
    const c = Math.cos(rotY), s = Math.sin(rotY);
    for (const k of [-0.5, 0.5]) {
      const px = x + c * (L / 2 + 0.02) + s * k * 0.9, pz = z - s * (L / 2 + 0.02) + c * k * 0.9;
      this.box(0.04, H - 0.2, 0.05, this.mat.metal, px, baseY + H / 2, pz, rotY, 1, false);
    }
  }

  /**
   * Carro abandonado. opts: color, seed, burnt (queimado, sem vidros e pneus), flipped (capotado),
   * flat: ['fl','fr','rl','rr'] pneus murchos, doorOpen, hoodOpen, cracked (para-brisa trincado),
   * missingGlass (vidros quebrados).
   */
  car(x, z, rotY, opts = {}) {
    const g = new THREE.Group();
    const M = this.mat;
    const burnt = !!opts.burnt;
    const paint = burnt ? M.burnt : new THREE.MeshStandardMaterial({
      map: TEX.carPaintTexture(opts.color ?? 0x5d6e76, opts.seed ?? 1), roughness: 0.75, metalness: 0.25, envMapIntensity: 0.5,
    });
    this.surfaceOf.set(paint, 'metal');
    const seat = burnt ? M.burntSeat : M.seat;
    const add = (geo, mat, px, py, pz, rx = 0, ry = 0, rz = 0) => {
      const m = new THREE.Mesh(geo, mat);
      m.position.set(px, py, pz);
      m.rotation.set(rx, ry, rz);
      g.add(m);
      return m;
    };
    // carroceria
    const body = add(boxGeo(4.2, 0.62, 1.8), paint, 0, 0.74, 0);
    if (opts.hoodOpen) {
      const hood = add(boxGeo(1.25, 0.06, 1.72), paint, 0, 0, 0);
      hood.geometry.translate(0.62, 0, 0); // dobradiça na parte de trás do capô
      hood.position.set(0.82, 1.1, 0);
      hood.rotation.z = 0.95; // capô levantado
      add(boxGeo(0.9, 0.35, 1.2), M.burnt, 1.5, 0.95, 0); // motor exposto
    } else {
      add(boxGeo(1.25, 0.1, 1.72), paint, 1.45, 1.08, 0, 0, 0, -0.06);
    }
    add(boxGeo(0.8, 0.1, 1.72), paint, -1.75, 1.08, 0);
    // cabine: teto, colunas, vidros (trincados/quebrados) e bancos
    add(boxGeo(1.9, 0.07, 1.6), paint, -0.3, 1.66, 0);
    for (const [px, pz] of [[0.62, 0.77], [0.62, -0.77], [-1.22, 0.77], [-1.22, -0.77]]) {
      add(boxGeo(0.07, 0.6, 0.06), paint, px, 1.36, pz, 0, 0, px > 0 ? 0.35 : -0.25);
    }
    if (!burnt) {
      add(boxGeo(0.04, 0.55, 1.5), opts.cracked ? M.crackedGlass : M.glass, 0.72, 1.36, 0, 0, 0, 0.42);
      if (!opts.missingGlass) add(boxGeo(0.04, 0.5, 1.5), M.glass, -1.3, 1.36, 0, 0, 0, -0.3);
      add(boxGeo(1.75, 0.5, 0.03), M.glass, -0.3, 1.36, -0.79);
      if (!opts.missingGlass && !opts.doorOpen) add(boxGeo(1.75, 0.5, 0.03), M.glass, -0.3, 1.36, 0.79);
    }
    for (const sx of [0.05, -0.85]) {
      add(boxGeo(0.5, 0.15, 1.4), seat, sx, 1.1, 0);
      add(boxGeo(0.12, 0.55, 1.4), seat, sx - 0.25, 1.35, 0, 0, 0, -0.15);
    }
    add(new THREE.TorusGeometry(0.15, 0.025, 6, 16), seat, 0.4, 1.32, 0.38, 0, Math.PI / 2, 0.5);
    if (opts.doorOpen) {
      // porta do motorista aberta, pendurada na dobradiça
      const door = add(boxGeo(1.0, 0.6, 0.05), paint, 0, 0, 0);
      door.geometry.translate(-0.5, 0, 0);
      door.position.set(0.55, 0.95, 0.92);
      door.rotation.y = 0.9;
    }
    for (const s of [-1, 1]) {
      if (!burnt) {
        add(boxGeo(0.06, 0.16, 0.34), M.headlight, 2.11, 0.86, s * 0.62);
        add(boxGeo(0.06, 0.14, 0.3), M.taillight, -2.11, 0.86, s * 0.65);
      }
      add(boxGeo(0.18, 0.1, 0.06), paint, 0.55, 1.2, s * 0.94);
    }
    add(boxGeo(0.15, 0.18, 1.86), burnt ? M.burnt : M.chrome, 2.17, 0.52, 0);
    add(boxGeo(0.15, 0.18, 1.86), burnt ? M.burnt : M.chrome, -2.17, 0.52, 0, 0, 0, 0.12); // para-choque torto
    add(boxGeo(0.03, 0.14, 0.42), M.paint, -2.25, 0.72, 0);
    // rodas: pneus (murchos ou queimados até o aro)
    const flat = new Set(opts.flat ?? []);
    const wheels = { fl: [1.3, 0.85], fr: [1.3, -0.85], rl: [-1.3, 0.85], rr: [-1.3, -0.85] };
    for (const [k, [wx, wz]] of Object.entries(wheels)) {
      if (!burnt) {
        const tire = add(new THREE.CylinderGeometry(0.38, 0.38, 0.26, 16), M.tire, wx, flat.has(k) ? 0.3 : 0.38, wz, Math.PI / 2);
        if (flat.has(k)) tire.scale.z = 0.72;
      }
      add(new THREE.CylinderGeometry(0.22, 0.22, 0.24, 10), burnt ? M.rust : M.chrome, wx, burnt ? 0.22 : (flat.has(k) ? 0.3 : 0.38), wz, Math.PI / 2);
    }
    // carro inclinado para o lado dos pneus murchos / queimado sentado no aro
    let roll = 0, pitch = 0;
    if (flat.has('fl') || flat.has('rl')) roll += 0.035;
    if (flat.has('fr') || flat.has('rr')) roll -= 0.035;
    if (flat.has('fl') || flat.has('fr')) pitch -= 0.03;
    if (flat.has('rl') || flat.has('rr')) pitch += 0.03;
    g.position.set(x, (opts.y ?? 0) + (opts.flipped ? 1.72 : burnt ? -0.15 : 0), z);
    g.rotation.set(opts.flipped ? Math.PI : roll, rotY, opts.flipped ? 0 : pitch, 'YXZ');
    this.scene.add(g);
    g.updateMatrixWorld(true);
    for (const m of [...g.children]) this.solid(m, m === body);
    // colisor da cabine inteira (os vidros e colunas são finos demais)
    const cabin = new THREE.Mesh(new THREE.BoxGeometry(2.0, 0.62, 1.62), this.colliderMat);
    cabin.position.set(-0.3, 1.36, 0);
    g.add(cabin);
    g.updateMatrixWorld(true);
    const c = new THREE.Mesh(cabin.geometry, this.colliderMat);
    c.matrixAutoUpdate = false;
    c.matrix.copy(cabin.matrixWorld);
    this.colliders.add(c);
    cabin.removeFromParent();
    this.noGrass.push([x - 2.4, z - 2.4, x + 2.4, z + 2.4]);
  }

  // ---------- barricada na estrada ----------
  _buildRoadblock() {
    const z = -44;
    this.car(-6.2, z, 1.25, { color: 0x6a5a48, seed: 5, flat: ['fl', 'rl'], cracked: true });
    this.car(-1.2, z - 2.5, 1.95, { burnt: true });
    this.sandbags(-4, z + 3.2, 0.05);
    this.barrel(-8.6, z + 2, this.mat.rust);
    // barril com fogo
    this.barrel(0.8, z + 2.6, this.mat.burnt);
    this.firePositions.push(new THREE.Vector3(0.8, 1.0, z + 2.6));
    // placa de aviso
    this.cylinder(0.05, 0.05, 2.2, this.mat.metal, -4.5, 1.1, z + 4.2, { seg: 6, collide: false });
    const sign = new THREE.Mesh(new THREE.PlaneGeometry(1.6, 0.8), new THREE.MeshStandardMaterial({
      map: TEX.decalTexture('text', 'ZONA\nINFECTADA', '#d8d0c0', 9), color: 0x7a1a14, roughness: 0.8, side: THREE.DoubleSide,
    }));
    sign.position.set(-4.5, 2.0, z + 4.23);
    sign.rotation.z = 0.08;
    sign.castShadow = true;
    this.scene.add(sign);
  }

  // ---------- lixo e entulho ----------
  _buildDebris() {
    const rand = makeRng(4242);
    const M = this.mat;
    // sacos de lixo
    const bagGeo = lumpy(new THREE.IcosahedronGeometry(0.3, 1), 0.35, 8);
    bagGeo.scale(1, 0.75, 1);
    const spots = [[9.4, -3.3], [9.9, -3.1], [9.6, -2.6], [-18.6, 20.3], [-18.2, 20.8], [-11, 6], [21.8, 16.6], [-14, -9], [5, -14]];
    for (const [x, z] of spots) {
      const m = new THREE.Mesh(bagGeo, M.trashBag);
      m.position.set(x + (rand() - 0.5) * 0.3, 0.2, z + (rand() - 0.5) * 0.3);
      m.rotation.y = rand() * 6;
      m.scale.setScalar(0.8 + rand() * 0.5);
      this.solid(m, false);
    }
    // tábuas soltas e pneus jogados
    for (let i = 0; i < 10; i++) {
      const x = (rand() - 0.5) * 60, z = (rand() - 0.5) * 60;
      if (!this._isFree(x, z, 1)) { i--; continue; }
      const plank = new THREE.Mesh(boxGeo(1.6 + rand(), 0.04, 0.18, 1), M.plank);
      plank.position.set(x, 0.03, z);
      plank.rotation.set(0, rand() * 6, (rand() - 0.5) * 0.1);
      this.solid(plank, false);
    }
    for (const [x, z] of [[-9.5, -1], [2.5, 31], [-7.5, -38]]) {
      const t = new THREE.Mesh(new THREE.TorusGeometry(0.33, 0.14, 8, 14), M.tire);
      t.rotation.set(Math.PI / 2 + (rand() - 0.5) * 0.4, 0, rand());
      t.position.set(x, 0.15, z);
      this.solid(t, false);
    }
    // papéis e folhas de jornal espalhados
    const paperGeo = new THREE.PlaneGeometry(0.28, 0.2);
    paperGeo.rotateX(-Math.PI / 2);
    const papers = new THREE.InstancedMesh(paperGeo, M.paper, 160);
    const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), sc = new THREE.Vector3(1, 1, 1), p = new THREE.Vector3();
    for (let i = 0; i < 160; i++) {
      const a = rand() * Math.PI * 2, r = Math.sqrt(rand()) * 40;
      const x = Math.cos(a) * r, z = Math.sin(a) * r;
      q.setFromEuler(new THREE.Euler((rand() - 0.5) * 0.2, rand() * 6, (rand() - 0.5) * 0.2));
      m4.compose(p.set(x, terrainHeight(x, z) + 0.06, z), q, sc.setScalar(0.6 + rand() * 0.7));
      papers.setMatrixAt(i, m4);
    }
    papers.receiveShadow = true;
    this.scene.add(papers);
    // buracos e manchas de óleo no asfalto
    for (let i = 0; i < 14; i++) {
      const z = (rand() - 0.5) * 220, x = ROAD_X + (rand() - 0.5) * 6;
      const d = new THREE.Mesh(new THREE.CircleGeometry(0.4 + rand() * 0.8, 10), M.pothole);
      d.rotation.set(-Math.PI / 2, 0, rand() * 6);
      d.scale.set(1, 0.6 + rand() * 0.6, 1);
      d.position.set(x, terrainHeight(x, z) + 0.065, z);
      d.receiveShadow = true;
      this.scene.add(d);
    }
  }

  // ---------- acampamento abandonado ----------
  _buildCamp() {
    const cx = 48, cz = -8;
    this.noGrass.push([cx - 5, cz - 5, cx + 5, cz + 5]);
    const y0 = terrainHeight(cx, cz);
    const tri = new THREE.Shape();
    tri.moveTo(-1.1, 0); tri.lineTo(1.1, 0); tri.lineTo(0, 1.3); tri.lineTo(-1.1, 0);
    const tentGeo = new THREE.ExtrudeGeometry(tri, { depth: 2.2, bevelEnabled: false });
    tentGeo.translate(0, 0, -1.1);
    for (const [dx, dz, rot, mat, sag] of [[-1.5, 0, 0.3, this.mat.tentGreen, 0], [2, 1, -0.5, this.mat.tentOrange, 0.35]]) {
      const t = new THREE.Mesh(tentGeo, mat);
      t.position.set(cx + dx, terrainHeight(cx + dx, cz + dz) - 0.02, cz + dz);
      t.rotation.set(0, rot, sag); // a laranja está meio desabada
      this.solid(t, true);
    }
    // fogueira apagada, saco de dormir e mochila largada
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      const r = new THREE.Mesh(lumpy(new THREE.DodecahedronGeometry(0.14, 0), 0.4, i + 30), this.mat.rock);
      r.position.set(cx + 0.5 + Math.cos(a) * 0.45, y0 + 0.06, cz + 3 + Math.sin(a) * 0.45);
      this.solid(r, false);
    }
    const ash = new THREE.Mesh(new THREE.CircleGeometry(0.4, 10), this.mat.burnt);
    ash.rotation.x = -Math.PI / 2;
    ash.position.set(cx + 0.5, y0 + 0.03, cz + 3);
    this.scene.add(ash);
    this.box(0.7, 0.12, 1.9, this.mat.tentOrange, cx - 2.6, y0 + 0.06, cz + 2.4, 0.4, 1, false);
    this.box(0.35, 0.45, 0.22, this.mat.fabric, cx + 1.6, y0 + 0.22, cz + 3.2, 0.9, 1, false);
    this.propSpots.push({ type: 'pot', x: cx + 0.9, y: y0, z: cz + 3.3 }, { type: 'can', x: cx + 0.1, y: y0, z: cz + 2.5 });
  }

  // ---------- pichações, sangue e musgo ----------
  decal(kind, text, x, y, z, rotY, w, h, color, { ground = false } = {}) {
    const mat = new THREE.MeshStandardMaterial({
      map: TEX.decalTexture(kind, text, color, Math.round(x * 7 + z)),
      transparent: true, depthWrite: false, roughness: 0.9,
      polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4,
    });
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), mat);
    m.position.set(x, y, z);
    if (ground) m.rotation.set(-Math.PI / 2, 0, rotY);
    else m.rotation.y = rotY;
    m.receiveShadow = true;
    this.scene.add(m);
    return m;
  }

  _buildDecals() {
    // casa de tijolos (frente em z = -4, olhando para +z)
    this.decal('text', 'SOCORRO', 10.15, 1.7, -3.86, 0, 1.9, 0.95, '#c8c2b0');
    this.decal('hand', '', 13.1, 1.25, -3.86, 0, 0.7, 0.7);
    this.decal('blood', '', 12.4, 0.215, -6.2, 0.4, 1.8, 1.3, undefined, { ground: true });
    this.decal('moss', '', 14, 0.6, -12.14, Math.PI, 10, 1.2);
    // cabana (frente em z = 17, olhando para -z)
    this.decal('tally', '', 15.6, 1.6, 16.88, Math.PI, 0.9, 0.8, '#e8e2d0');
    this.decal('text', 'NÃO ABRA\nMORTOS DENTRO', 20.2, 1.5, 16.88, Math.PI, 1.6, 0.8, '#a01812');
    // loja do posto (fundos em z = 24.5)
    this.decal('text', 'SEM COMIDA\nSEM ÁGUA', -21, 1.5, 24.62, 0, 3.2, 1.6, '#d6cfc0');
    // muro em ruínas e contêiner
    this.decal('text', 'ELES OUVEM', -31.1, 1.25, -24.77, 0.32, 2.6, 1.0, '#9a1a12');
    this.decal('arrow', 'ABRIGO', -20, 1.5, -15.22, Math.PI, 2.6, 1.3, '#e0d8c4');
    this.decal('blood', '', -3.5, 0.07, -16.5, 1.2, 2.2, 1.4, undefined, { ground: true });
    // janelas fechadas com tábuas
    this.boards(14, 1.6, -12.17, 0, 2.0, 1.2);
    this.boards(8.83, 1.6, -8, Math.PI / 2, 1.4, 1.2);
    this.boards(18, 1.5, 23.13, 0, 1.0, 1.0);
    this.boards(-21, 1.5, 20.87, 0, 1.4, 1.0);
  }

  /** Tábuas pregadas sobre uma janela (bloqueiam a passagem). */
  boards(x, y, z, rotY, w, h) {
    const rand = makeRng(Math.round(x * 13 + z * 7));
    const c = Math.cos(rotY), s = Math.sin(rotY);
    for (let i = 0; i < 4; i++) {
      const plank = new THREE.Mesh(boxGeo(w + 0.25, 0.16, 0.04, 1), this.mat.plank);
      const oy = (i - 1.5) * (h / 4.2);
      plank.position.set(x, y + oy, z);
      plank.rotation.set(0, rotY, (rand() - 0.5) * 0.35);
      this.solid(plank, false);
    }
    this.invisibleCollider(new THREE.BoxGeometry(w, h, 0.1), new THREE.Vector3(x, y, z), new THREE.Euler(0, rotY, 0));
    return [c, s];
  }

  barrel(x, z, mat, lying = false, by = 0) {
    const m = new THREE.Mesh(new THREE.CylinderGeometry(0.35, 0.35, 1, 16), mat);
    if (lying) { m.rotation.set(Math.PI / 2, 0.7, 0, 'YXZ'); m.position.set(x, by + 0.35, z); }
    else m.position.set(x, by + 0.5, z);
    this.solid(m);
    for (const y of [-0.3, 0.3]) { // aros
      if (lying) continue;
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.355, 0.02, 4, 16), this.mat.metal);
      ring.rotation.x = Math.PI / 2;
      ring.position.set(x, by + 0.5 + y, z);
      this.solid(ring, false);
    }
  }

  // ---------- fogueira ----------
  _buildCampfire() {
    const fx = 7, fz = 16;
    this.firePositions.push(new THREE.Vector3(fx, 0, fz));
    this.noGrass.push([fx - 2.4, fz - 2.4, fx + 2.4, fz + 2.4]);
    for (let i = 0; i < 9; i++) {
      const a = (i / 9) * Math.PI * 2;
      const r = new THREE.Mesh(lumpy(new THREE.DodecahedronGeometry(0.16, 0), 0.4, i), this.mat.rock);
      r.position.set(fx + Math.cos(a) * 0.55, 0.08, fz + Math.sin(a) * 0.55);
      this.solid(r, false);
    }
    for (let i = 0; i < 3; i++) { // lenha
      const a = (i / 3) * Math.PI * 2;
      this.cylinder(0.06, 0.06, 0.7, this.mat.bark, fx + Math.cos(a) * 0.1, 0.12, fz + Math.sin(a) * 0.1,
        { seg: 6, collide: false, rz: Math.PI / 2 - 0.3, ry: a });
    }
    // troncos para sentar
    for (const [a, len] of [[0.4, 1.8], [2.4, 1.6], [4.3, 1.7]]) {
      this.cylinder(0.2, 0.22, len, this.mat.bark, fx + Math.cos(a) * 1.8, 0.2, fz + Math.sin(a) * 1.8,
        { seg: 9, rz: Math.PI / 2, ry: -a + Math.PI / 2 });
    }
  }

  // ---------- lago, píer e juncos ----------
  _buildLake() {
    const { x: lx, z: lz, r, y } = LAKE;
    const water = new THREE.Mesh(new THREE.CircleGeometry(r + 2.5, 64), this.mat.water);
    water.rotation.x = -Math.PI / 2;
    water.position.set(lx, y, lz);
    water.receiveShadow = true;
    water.material.normalMap.repeat.set(6, 6);
    this.scene.add(water);
    this.waterMesh = water;

    // píer de madeira saindo da margem voltada para o vilarejo
    const dir = new THREE.Vector2(-lx, -lz).normalize();
    const rot = Math.atan2(dir.x, dir.y);
    const deckY = y + 0.55;
    const start = r + 2.5, end = r - 8;
    const mid = (start + end) / 2, len = start - end;
    const cxp = lx + dir.x * mid, czp = lz + dir.y * mid;
    this.box(1.8, 0.12, len, this.mat.plank, cxp, deckY - 0.06, czp, rot, 1.5, false);
    // colisão do píer vai até dentro d'água: dá para subir nele nadando (não passa por baixo)
    const skirt = deckY - (y - 1.3);
    this.invisibleCollider(new THREE.BoxGeometry(1.8, skirt, len), new THREE.Vector3(cxp, deckY - skirt / 2, czp), new THREE.Euler(0, rot, 0));
    for (let t = end + 0.3; t < start; t += 2) {
      for (const s of [-0.8, 0.8]) {
        const px = lx + dir.x * t + Math.cos(rot) * s, pz = lz + dir.y * t - Math.sin(rot) * s;
        const bottom = terrainHeight(px, pz) - 0.3;
        this.cylinder(0.08, 0.09, deckY - bottom, this.mat.bark, px, (deckY + bottom) / 2 - 0.06, pz, { seg: 7 });
      }
    }
    this.propSpots.push(
      { type: 'bucket', x: lx + dir.x * (end + 1.2) + 0.3, y: deckY, z: lz + dir.y * (end + 1.2) },
      { type: 'bottle', x: lx + dir.x * (end + 2.5) - 0.4, y: deckY, z: lz + dir.y * (end + 2.5) },
    );

    // juncos na margem e vitórias-régias na água
    const rand = makeRng(321);
    const reedGeo = new THREE.ConeGeometry(0.025, 1.4, 4, 1, true);
    reedGeo.translate(0, 0.7, 0);
    const reedMat = this.mat.reed;
    this.addWind(reedMat, 0.12, 0.6);
    const n = this.quality === 'low' ? 260 : 520;
    const reeds = new THREE.InstancedMesh(reedGeo, reedMat, n);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), sc = new THREE.Vector3(), p = new THREE.Vector3();
    for (let i = 0; i < n; i++) {
      const a = rand() * Math.PI * 2;
      // não nasce em cima do píer
      if (Math.abs(Math.atan2(Math.sin(a - Math.atan2(dir.y, dir.x)), Math.cos(a - Math.atan2(dir.y, dir.x)))) < 0.12) { i--; continue; }
      const d = r - 1.5 + rand() * 3;
      const x = lx + Math.cos(a) * d, z = lz + Math.sin(a) * d;
      q.setFromEuler(new THREE.Euler((rand() - 0.5) * 0.3, rand() * 6, (rand() - 0.5) * 0.3));
      const k = 0.6 + rand() * 0.7;
      m.compose(p.set(x, terrainHeight(x, z) - 0.05, z), q, sc.set(k, k, k));
      reeds.setMatrixAt(i, m);
    }
    reeds.castShadow = true;
    this.scene.add(reeds);

    const padGeo = new THREE.CircleGeometry(0.28, 10, 0.3, Math.PI * 2 - 0.6);
    padGeo.rotateX(-Math.PI / 2);
    const pads = new THREE.InstancedMesh(padGeo, new THREE.MeshStandardMaterial({ color: 0x3e5a2a, roughness: 0.6 }), 30);
    for (let i = 0; i < 30; i++) {
      const a = rand() * Math.PI * 2, d = r * (0.55 + rand() * 0.4);
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), rand() * 6);
      const k = 0.6 + rand() * 0.8;
      m.compose(p.set(lx + Math.cos(a) * d, y + 0.01, lz + Math.sin(a) * d), q, sc.set(k, 1, k));
      pads.setMatrixAt(i, m);
    }
    this.scene.add(pads);
  }

  /** Nível da água em (x, z), ou -Infinity se não houver água ali. */
  waterAt(x, z) {
    return Math.hypot(x - LAKE.x, z - LAKE.z) < LAKE.r + 2.4 ? LAKE.y : -Infinity;
  }

  // ---------- floresta ----------
  _isFree(x, z, margin = 0) {
    if (Math.hypot(x - LAKE.x, z - LAKE.z) < LAKE.r + 1 + margin) return false;
    for (const [x0, z0, x1, z1] of this.noGrass) {
      if (x > x0 - margin && x < x1 + margin && z > z0 - margin && z < z1 + margin) return false;
    }
    return true;
  }

  _buildForest() {
    const low = this.quality === 'low';
    const rand = makeRng(7);
    const nPine = low ? 2400 : 4800, nBroad = low ? 1400 : 2700, nDead = low ? 250 : 420, nBush = low ? 2000 : 4200;
    const up = new THREE.Vector3(0, 1, 0);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3();
    const color = new THREE.Color();

    const leafMat = this.mat.foliage;
    this.addWind(leafMat, 0.05, 0.12);

    const trunkGeo = new THREE.CylinderGeometry(0.16, 0.3, 5, 7);
    trunkGeo.translate(0, 2.5, 0);
    const trunks = new THREE.InstancedMesh(trunkGeo, this.mat.bark, nPine + nBroad + nDead);

    // copas de "cartões" com galhos/folhas recortados em volta de um miolo escuro (trees.js)
    const pineCard = foliageCardMaterial(pineBranchTexture());
    const leafCard = foliageCardMaterial(leafClusterTexture());
    for (const fm of [pineCard, leafCard]) this.addWind(fm.material, 0.05, 0.12);
    const cardMesh = (geo, fm, n) => {
      const im = new THREE.InstancedMesh(geo, fm.material, n);
      im.customDepthMaterial = fm.depth;
      return im;
    };
    // pinheiros: miolo (cones menores e escuros) + galhos de agulhas
    const pineLevels = [[0.75, 2.6, 2.4], [0.62, 2.3, 3.6], [0.46, 2.0, 4.7], [0.26, 1.5, 5.7]].map(([r, h, y]) => {
      const g = lumpy(new THREE.ConeGeometry(r, h, 7, 2), 0.12, r * 10);
      g.translate(0, y, 0);
      return new THREE.InstancedMesh(g, leafMat, nPine);
    });
    pineLevels.push(cardMesh(pineCardsGeometry(5), pineCard, nPine));
    // árvores de folhas: miolo (três bolas) + cachos de folhas
    const crownGeos = [[1.05, 0, 5.0, 0], [0.75, 1.0, 4.3, 0.5], [0.7, -0.9, 4.5, -0.5]].map(([r, x, y, z], k) => {
      const g = lumpy(new THREE.IcosahedronGeometry(r, 1), 0.3, k + 5);
      g.translate(x, y, z);
      return new THREE.InstancedMesh(g, leafMat, nBroad);
    });
    const broadCards = cardMesh(broadCardsGeometry(7), leafCard, nBroad);
    const branchGeo = new THREE.CylinderGeometry(0.03, 0.1, 2.2, 5);
    branchGeo.translate(0, 1.1, 0);
    const branches = new THREE.InstancedMesh(branchGeo, this.mat.bark, nDead * 3 + nBroad * 2);

    const colGeo = new THREE.CylinderGeometry(0.3, 0.3, 6, 6);
    colGeo.translate(0, 3, 0);

    const pinePalette = [0x2f4228, 0x34492a, 0x3b4f2c, 0x2b3a24];
    const broadPalette = [0x5a6a2c, 0x6f7230, 0x9a7a30, 0xa8622a, 0x8c3e1e, 0xb8903a, 0x4f5f2a];

    // matas fechadas e campos abertos: a densidade segue um ruído grande
    const place = (minTown) => {
      for (;;) {
        const x = (rand() - 0.5) * WORLD_HALF * 2, z = (rand() - 0.5) * WORLD_HALF * 2;
        if (Math.hypot(x, z) < minTown) continue;
        const dens = smoothstep(0.32, 0.62, valueNoise(x * 0.006 + 5, z * 0.006 - 3));
        if (rand() > 0.12 + 0.88 * dens && Math.hypot(x, z) > 160) continue;
        if (!this._isFree(x, z, 1.5) || trailMask(x, z) > 0.05 || this._nearRoadOrPoi(x, z, 2)) continue;
        return [x, z];
      }
    };

    let ti = 0, bi = 0;
    const addTrunk = (x, y, z, sc, hScale) => {
      q.setFromAxisAngle(up, rand() * Math.PI * 2);
      m.compose(p.set(x, y - 0.15, z), q, s.set(sc, sc * hScale, sc));
      trunks.setMatrixAt(ti++, m);
      const col = this.invisibleCollider(colGeo, new THREE.Vector3(x, y - 0.5, z));
      col.scale.set(sc, 1, sc);
      col.updateMatrix();
    };

    for (let i = 0; i < nPine; i++) {
      const [x, z] = place(TOWN_RADIUS + 3);
      const y = terrainHeight(x, z), sc = 0.8 + rand() * 0.7, hs = 0.9 + rand() * 0.4;
      addTrunk(x, y, z, sc, hs);
      q.setFromAxisAngle(up, rand() * Math.PI * 2);
      m.compose(p.set(x, y, z), q, s.set(sc, sc * hs, sc));
      color.setHex(pinePalette[i % pinePalette.length]).offsetHSL(0, 0, (rand() - 0.5) * 0.04);
      for (const lvl of pineLevels) lvl.setMatrixAt(i, m);
      for (let k = 0; k < 4; k++) pineLevels[k].setColorAt(i, color.clone().multiplyScalar(0.45));
      // galhos: a textura já é verde; a cor da instância só varia o tom (seco/vivo, claro/escuro)
      pineLevels[4].setColorAt(i, color.setRGB(0.85 + rand() * 0.2, 0.85 + rand() * 0.15, 0.75 + rand() * 0.15));
    }
    for (let i = 0; i < nBroad; i++) {
      const [x, z] = place(TOWN_RADIUS - 6);
      const y = terrainHeight(x, z), sc = 0.75 + rand() * 0.6;
      addTrunk(x, y, z, sc, 0.85);
      q.setFromAxisAngle(up, rand() * Math.PI * 2);
      m.compose(p.set(x, y, z), q, s.set(sc, sc, sc));
      color.setHex(broadPalette[Math.floor(rand() * broadPalette.length)]).offsetHSL(0, 0, (rand() - 0.5) * 0.05);
      for (const cg of crownGeos) { cg.setMatrixAt(i, m); cg.setColorAt(i, color.clone().multiplyScalar(0.32)); }
      broadCards.setMatrixAt(i, m);
      broadCards.setColorAt(i, color.clone().multiplyScalar(1.25));
      for (let b = 0; b < 2; b++) {
        const bq = new THREE.Quaternion().setFromEuler(new THREE.Euler(0.8 * (b ? 1 : -1), rand() * 6, 0));
        m.compose(p.set(x, y + 2.6 * sc, z), bq, s.set(sc * 0.8, sc * 0.8, sc * 0.8));
        branches.setMatrixAt(bi++, m);
      }
    }
    for (let i = 0; i < nDead; i++) {
      const [x, z] = place(TOWN_RADIUS);
      const y = terrainHeight(x, z), sc = 0.7 + rand() * 0.6;
      addTrunk(x, y, z, sc * 0.8, 0.9);
      for (let b = 0; b < 3; b++) {
        const bq = new THREE.Quaternion().setFromEuler(new THREE.Euler((0.6 + rand() * 0.5) * (b % 2 ? 1 : -1), rand() * 6, 0));
        m.compose(p.set(x, y + (2 + b * 0.8) * sc, z), bq, s.set(sc, sc, sc));
        branches.setMatrixAt(bi++, m);
      }
    }
    branches.count = bi;
    trunks.count = ti;

    // arbustos: miolo + cachos de folhas
    const bushCards = cardMesh(bushCardsGeometry(9), leafCard, nBush);
    const bushGeo = lumpy(new THREE.IcosahedronGeometry(0.55, 1), 0.35, 3);
    bushGeo.scale(1, 0.65, 1);
    bushGeo.translate(0, 0.35, 0);
    const bushes = new THREE.InstancedMesh(bushGeo, leafMat, nBush);
    for (let i = 0; i < nBush; i++) {
      const [x, z] = place(rand() < 0.3 ? 20 : TOWN_RADIUS - 4);
      const sc = 0.6 + rand() * 0.8;
      q.setFromAxisAngle(up, rand() * Math.PI * 2);
      m.compose(p.set(x, terrainHeight(x, z) - 0.1, z), q, s.set(sc, sc * (0.7 + rand() * 0.5), sc));
      bushes.setMatrixAt(i, m);
      bushCards.setMatrixAt(i, m);
      color.setHex(broadPalette[Math.floor(rand() * broadPalette.length)]).offsetHSL(0, -0.05, -0.04);
      bushes.setColorAt(i, color.clone().multiplyScalar(0.35));
      bushCards.setColorAt(i, color.multiplyScalar(1.15));
    }

    for (const im of [trunks, ...pineLevels, ...crownGeos, broadCards, branches, bushes, bushCards]) {
      im.castShadow = true;
      im.receiveShadow = true;
      this._chunkInstances(im, 120);
    }

    // pedras e troncos caídos
    for (let i = 0; i < (low ? 220 : 400); i++) {
      const [x, z] = place(14);
      const sc = 0.4 + rand() * 1.3;
      const r = new THREE.Mesh(lumpy(new THREE.DodecahedronGeometry(1, 1), 0.35, i), this.mat.rock);
      r.scale.set(sc * (1 + rand() * 0.6), sc * 0.65, sc);
      r.rotation.set(rand() * 0.4, rand() * 6, rand() * 0.4);
      r.position.set(x, terrainHeight(x, z) + sc * 0.1, z);
      this.solid(r);
    }
    for (let i = 0; i < (low ? 70 : 130); i++) {
      const [x, z] = place(TOWN_RADIUS + 2);
      const len = 3 + rand() * 4, rad = 0.22 + rand() * 0.15, a = rand() * Math.PI;
      const y = Math.max(terrainHeight(x + Math.cos(a) * len / 2, z - Math.sin(a) * len / 2),
        terrainHeight(x - Math.cos(a) * len / 2, z + Math.sin(a) * len / 2));
      this.cylinder(rad * 0.85, rad, len, this.mat.bark, x, y + rad * 0.7, z, { seg: 8, rz: Math.PI / 2, ry: a });
    }
  }

  // ---------- grama (instanciada, balança com o vento) ----------
  /**
   * Divide um InstancedMesh espalhado pelo mapa em blocos (size m): cada bloco é descartado
   * fora da tela (frustum) e de longe (distância), em vez de desenhar o mapa inteiro sempre.
   */
  _chunkInstances(im, size) {
    const groups = new Map();
    const m = new THREE.Matrix4(), p = new THREE.Vector3(), c = new THREE.Color();
    for (let i = 0; i < im.count; i++) {
      im.getMatrixAt(i, m);
      p.setFromMatrixPosition(m);
      const key = Math.floor(p.x / size) + ',' + Math.floor(p.z / size);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(i);
    }
    for (const [key, ids] of groups) {
      const part = new THREE.InstancedMesh(im.geometry, im.material, ids.length);
      part.customDepthMaterial = im.customDepthMaterial;
      part.castShadow = im.castShadow;
      part.receiveShadow = im.receiveShadow;
      ids.forEach((id, k) => {
        im.getMatrixAt(id, m); part.setMatrixAt(k, m);
        if (im.instanceColor) { im.getColorAt(id, c); part.setColorAt(k, c); }
      });
      part.computeBoundingSphere();
      const [cx, cz] = key.split(',').map((v) => (Number(v) + 0.5) * size);
      part.userData.center = new THREE.Vector2(cx, cz);
      this.scene.add(part);
      this.lodChunks.push(part);
    }
  }

  /**
   * Grama: um tapete de tufos em volta do jogador, num único desenho. Os tufos ficam presos
   * ao chão do mundo (o tapete anda de bloco em bloco de 16 m) e a altura de cada um vem de
   * uma textura com o relevo; outra textura diz onde não pode ter grama (estradas, casas,
   * lago). Tamanho, giro e cor variam pela posição — não se nota repetição.
   */
  _buildGrass() {
    const low = this.quality === 'low';
    const TILE = 16, TILES = low ? 8 : 11;
    const perTile = low ? 220 : 380;
    const pos = [];
    for (let i = 0; i < 5; i++) {
      const a = (i / 5) * Math.PI * 2 + i;
      const r = 0.05 + (i % 2) * 0.03;
      const bx = Math.cos(a) * r, bz = Math.sin(a) * r;
      const w = 0.018;
      const px = -Math.sin(a) * w, pz = Math.cos(a) * w;
      const tipX = bx * 2.2, tipZ = bz * 2.2, tipY = 0.26 + (i % 3) * 0.06;
      const A = [bx - px, 0, bz - pz], B = [bx + px, 0, bz + pz], C = [tipX, tipY, tipZ];
      pos.push(...A, ...B, ...C, ...B, ...A, ...C);
    }
    const geo = new THREE.InstancedBufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    geo.setAttribute('normal', new THREE.Float32BufferAttribute(new Array(pos.length / 3).fill([0, 1, 0]).flat(), 3));
    const n = TILES * TILES * perTile;
    const offs = new Float32Array(n * 3);
    let k = 0;
    for (let ty = 0; ty < TILES; ty++) for (let tx = 0; tx < TILES; tx++) {
      const r2 = makeRng(1234); // o mesmo padrão em todos os blocos (o tapete anda sem "pular")
      for (let i = 0; i < perTile; i++) {
        offs[k * 3] = (tx - TILES / 2) * TILE + r2() * TILE;
        offs[k * 3 + 1] = r2();
        offs[k * 3 + 2] = (ty - TILES / 2) * TILE + r2() * TILE;
        k++;
      }
    }
    geo.setAttribute('aOffset', new THREE.InstancedBufferAttribute(offs, 3));
    geo.instanceCount = n;
    // relevo e máscara em texturas
    const W = GRID + 1;
    const hTex = new THREE.DataTexture(HEIGHTS, W, W, THREE.RedFormat, THREE.FloatType);
    hTex.needsUpdate = true;
    const MS = 1024, mask = new Uint8Array(MS * MS).fill(255);
    const toM = (v) => Math.round((v + WORLD_SIZE / 2) / WORLD_SIZE * MS);
    const fillRect = (x0, z0, x1, z1) => {
      for (let z = Math.max(0, toM(z0)); z < Math.min(MS, toM(z1)); z++) mask.fill(0, z * MS + Math.max(0, toM(x0)), z * MS + Math.min(MS, toM(x1)));
    };
    for (const [x0, z0, x1, z1] of this.noGrass) fillRect(x0, z0, x1, z1);
    for (let z = 0; z < MS; z++) for (let x = 0; x < MS; x++) {
      const wx = (x + 0.5) / MS * WORLD_SIZE - WORLD_SIZE / 2, wz = (z + 0.5) / MS * WORLD_SIZE - WORLD_SIZE / 2;
      if (Math.abs(wx - ROAD_X) < ROAD_HALF + 0.6 || Math.hypot(wx - LAKE.x, wz - LAKE.z) < LAKE.r + 1) mask[z * MS + x] = 0;
    }
    // estradas secundárias e trilhas: desenhadas como linhas grossas
    const stamp = (x, z, r, v) => {
      const cx = toM(x), cz = toM(z), rr = Math.ceil(r / WORLD_SIZE * MS);
      for (let dz = -rr; dz <= rr; dz++) for (let dx = -rr; dx <= rr; dx++) {
        const X = cx + dx, Z = cz + dz;
        if (X < 0 || Z < 0 || X >= MS || Z >= MS || dx * dx + dz * dz > rr * rr) continue;
        mask[Z * MS + X] = Math.min(mask[Z * MS + X], v);
      }
    };
    const line = (pts, r, v) => {
      for (let i = 0; i < pts.length - 1; i++) {
        const [ax, az] = pts[i], [bx, bz] = pts[i + 1], L = Math.hypot(bx - ax, bz - az);
        for (let d = 0; d <= L; d += 0.8) stamp(ax + (bx - ax) * d / L, az + (bz - az) * d / L, r, v);
      }
    };
    for (const r of ROADS) line(r, ROAD_HALF + 0.6, 0);
    for (const t of TRAILS) line(t, 1.2, 60);
    const mTex = new THREE.DataTexture(mask, MS, MS, THREE.RedFormat, THREE.UnsignedByteType);
    mTex.magFilter = THREE.LinearFilter; mTex.minFilter = THREE.LinearFilter; mTex.needsUpdate = true;
    const mat = new THREE.MeshLambertMaterial();
    const U = this.grassUniforms = {
      uAnchor: { value: new THREE.Vector2() }, uEye: { value: new THREE.Vector3() }, uDist: { value: low ? 58 : 84 },
      uH: { value: hTex }, uMask: { value: mTex }, uSize: { value: WORLD_SIZE }, uGrid: { value: GRID }, uDensity: { value: 1 },
    };
    mat.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, U, { uTime: this.windUniform });
      shader.vertexShader = `
        uniform vec2 uAnchor; uniform vec3 uEye; uniform float uDist, uSize, uGrid, uTime, uDensity;
        uniform sampler2D uH, uMask;
        attribute vec3 aOffset;
        varying vec3 vGrass;
        float gh(vec2 cell) { return texture2D(uH, (cell + 0.5) / (uGrid + 1.0)).r; }
        float terrainH(vec2 p) {
          vec2 f = clamp((p + uSize * 0.5) / (uSize / uGrid), vec2(0.0), vec2(uGrid - 0.001));
          vec2 i = floor(f), t = f - i;
          float a = gh(i), b = gh(i + vec2(0.0, 1.0)), c = gh(i + vec2(1.0, 1.0)), d = gh(i + vec2(1.0, 0.0));
          return (t.x + t.y <= 1.0) ? a + (d - a) * t.x + (b - a) * t.y : c + (b - c) * (1.0 - t.x) + (d - c) * (1.0 - t.y);
        }
        float hs(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
      ` + shader.vertexShader.replace('#include <begin_vertex>', `
        vec2 wp = uAnchor + aOffset.xz;
        float r1 = hs(floor(wp * 4.0) + aOffset.y * 17.0), r2 = hs(wp.yx * 3.1 + 7.0);
        float m = texture2D(uMask, (wp + uSize * 0.5) / uSize).r;
        float dist = length(wp - uEye.xz);
        float keep = step(aOffset.y, uDensity) * smoothstep(uDist, uDist - 18.0, dist) * smoothstep(0.2, 0.55, m);
        float sc = (0.7 + r1 * 0.8) * keep;
        float ang = r2 * 6.2832;
        vec3 transformed = vec3(cos(ang) * position.x - sin(ang) * position.z, position.y * (0.6 + r2 * 0.9), sin(ang) * position.x + cos(ang) * position.z) * sc;
        float ph = wp.x * 0.35 + wp.y * 0.25;
        float sway = sin(uTime * 1.6 + ph) * 0.6 + sin(uTime * 3.7 + ph * 2.0) * 0.25;
        transformed.x += sway * 0.25 * transformed.y;
        transformed.z += cos(uTime * 1.3 + ph) * 0.15 * transformed.y;
        transformed += vec3(wp.x, terrainH(wp) - 0.02, wp.y);
        float dry = hs(floor(wp * 0.05));
        vGrass = vec3(0.16 + r1 * 0.05 + dry * 0.08, 0.2 + r2 * 0.05 + dry * 0.02, 0.07 + dry * 0.02);
      `);
      shader.fragmentShader = 'varying vec3 vGrass;\n' + shader.fragmentShader.replace('vec4 diffuseColor = vec4( diffuse, opacity );', 'vec4 diffuseColor = vec4( diffuse * vGrass * 2.2, opacity );');
    };
    mat.customProgramCacheKey = () => 'grass-carpet';
    const mesh = new THREE.Mesh(geo, mat);
    mesh.frustumCulled = false;
    mesh.receiveShadow = true;
    this.scene.add(mesh);
    this.grass = mesh;
    this.grassTile = TILE;
    this.grassDensity = 1;
  }

  /** Fração da grama desenhada (qualidade gráfica). */
  setGrassDensity(k) {
    this.grassDensity = k;
    if (this.grassUniforms) this.grassUniforms.uDensity.value = k;
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

  // ---------- otimização ----------
  /**
   * Junta os objetos estáticos com o mesmo material, por região de 40 m: poucos draw calls,
   * mas cada bloco ainda pode ser descartado quando está fora da tela ou da área de sombra.
   */
  _mergeStatic() {
    const byKey = new Map();
    const wp = new THREE.Vector3();
    for (const mesh of this.staticMeshes) {
      mesh.updateMatrixWorld(true);
      let g = mesh.geometry.index ? mesh.geometry.toNonIndexed() : mesh.geometry.clone();
      for (const name of Object.keys(g.attributes)) {
        if (name !== 'position' && name !== 'normal' && name !== 'uv') g.deleteAttribute(name);
      }
      if (!g.attributes.normal) g.computeVertexNormals();
      if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
      g.clearGroups();
      g.applyMatrix4(mesh.matrixWorld);
      wp.setFromMatrixPosition(mesh.matrixWorld);
      const key = mesh.material.uuid + ':' + Math.floor(wp.x / 40) + ',' + Math.floor(wp.z / 40);
      if (!byKey.has(key)) byKey.set(key, { mat: mesh.material, geos: [] });
      byKey.get(key).geos.push(g);
      mesh.removeFromParent();
    }
    for (const { mat, geos } of byKey.values()) {
      const merged = mergeGeometries(geos, false);
      for (const g of geos) g.dispose();
      const mesh = new THREE.Mesh(merged, mat);
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      merged.computeBoundingSphere();
      mesh.userData.center = new THREE.Vector2(merged.boundingSphere.center.x, merged.boundingSphere.center.z);
      this.lodChunks.push(mesh);
      const surface = this.surfaceOf.get(mat);
      if (surface) {
        mesh.userData.surface = surface;
        this.surfaceMeshes.push(mesh);
      }
      this.scene.add(mesh);
    }
    // grupos vazios (carros) podem sair da cena
    for (const child of [...this.scene.children]) {
      if (child.isGroup && child.children.length === 0) child.removeFromParent();
    }
    this.staticMeshes.length = 0;
  }
}
