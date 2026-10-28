import * as THREE from 'three';
import { Octree } from 'three/addons/math/Octree.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import * as TEX from './textures.js';

// Constrói o cenário (vilarejo abandonado numa floresta de outono) e a malha de colisão.
// Tudo que é sólido entra em `colliders`, que alimenta um Octree usado pela física do jogador.
// Os objetos estáticos visíveis são fundidos por material no final (poucos draw calls = mais FPS).

const WORLD_SIZE = 300;
const WORLD_HALF = 140; // limite caminhável
const TOWN_RADIUS = 42; // área plana central
const ROAD_X = -4;      // estrada norte-sul
const ROAD_HALF = 4;

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
  // a estrada corta o relevo mais suave
  const road = 0.25 + 0.75 * smoothstep(ROAD_HALF + 1, ROAD_HALF + 10, Math.abs(x - ROAD_X));
  // morros mais altos perto da borda do mapa
  const edge = smoothstep(WORLD_HALF - 40, WORLD_HALF + 10, Math.max(Math.abs(x), Math.abs(z)));
  return h * 9 * flat * road + edge * 14;
}

// trilhas de terra saindo das entradas da cerca
const TRAILS = [
  [[36, 4], [55, 10], [75, 22], [100, 30], [128, 26]],
  [[-36, -4], [-58, -12], [-80, -8], [-105, -20], [-132, -24]],
  [[30, -22], [42, -40], [60, -55], [70, -80], [95, -110]],
];
function distToSegment(px, pz, ax, az, bx, bz) {
  const dx = bx - ax, dz = bz - az;
  const t = Math.max(0, Math.min(1, ((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz)));
  return Math.hypot(px - (ax + dx * t), pz - (az + dz * t));
}
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
    this.firePositions = [];
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
      glass: new THREE.MeshStandardMaterial({ color: 0x1b2328, roughness: 0.1, metalness: 0.8 }),
      tire: new THREE.MeshStandardMaterial({ color: 0x151515, roughness: 0.9 }),
      barrel: new THREE.MeshStandardMaterial({ color: 0x4f6a38, roughness: 0.55, metalness: 0.4 }),
      metal: new THREE.MeshStandardMaterial({ color: 0x4a4a48, roughness: 0.45, metalness: 0.75 }),
      roof: new THREE.MeshStandardMaterial({ color: 0x3b3430, roughness: 0.95 }),
      paint: new THREE.MeshStandardMaterial({ color: 0xc9c4b8, roughness: 0.8 }),
      redPaint: new THREE.MeshStandardMaterial({ color: 0x8a2a20, roughness: 0.7 }),
      fabric: new THREE.MeshStandardMaterial({ color: 0x5b5f4a, roughness: 1 }),
      sandbag: new THREE.MeshStandardMaterial({ color: 0x8a7a58, roughness: 1, flatShading: true }),
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
      [M.glass, 'metal'], [M.redPaint, 'metal'],
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
    this._buildCampfire();
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
      uZenith: { value: new THREE.Color(0x56708c) },
      uHorizon: { value: new THREE.Color(0xc2bba8) },
      uGround: { value: new THREE.Color(0x6e6858) },
      uSunColor: { value: new THREE.Color(0xffc488) },
      uTime: { value: 0 },
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
        uniform vec3 uSunDir, uZenith, uHorizon, uGround, uSunColor;
        uniform float uTime;
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
            vec3 cloud = mix(vec3(0.52, 0.53, 0.56), vec3(1.0, 0.92, 0.82), clamp(pow(sd, 3.0) * 0.9 + shade * 0.35, 0.0, 1.0));
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
    this.scene.fog = new THREE.Fog(0xaaa79a, 35, 230);
  }

  _buildLights() {
    const hemi = new THREE.HemisphereLight(0xa6b8c8, 0x4b4232, 0.55);
    this.scene.add(hemi);

    const sun = new THREE.DirectionalLight(0xffd6a6, 2.6);
    sun.castShadow = true;
    const sm = this.quality === 'low' ? 1024 : 2048;
    sun.shadow.mapSize.set(sm, sm);
    const r = 40;
    Object.assign(sun.shadow.camera, { left: -r, right: r, top: r, bottom: -r, near: 1, far: 260 });
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

  /** Vento, nuvens e área de sombra centrada no jogador. */
  update(playerPos, time = 0) {
    this.windUniform.value = time;
    this.skyUniforms.uTime.value = time;
    const snap = 4; // reduz "tremido" da sombra
    const x = Math.round(playerPos.x / snap) * snap;
    const z = Math.round(playerPos.z / snap) * snap;
    this.sun.target.position.set(x, 0, z);
    this.sun.position.set(x, 0, z).addScaledVector(this.sunDir, 120);
    this.sky.position.set(playerPos.x, playerPos.y, playerPos.z);
    // grama longe não aparece (some na neblina de qualquer jeito)
    const maxD = this.grassDistance + 28;
    for (const g of this.grassChunks) {
      g.visible = Math.hypot(g.userData.center.x - playerPos.x, g.userData.center.y - playerPos.z) < maxD;
    }
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
    const seg = this.quality === 'low' ? 100 : 140;
    const geo = new THREE.PlaneGeometry(WORLD_SIZE, WORLD_SIZE, seg, seg);
    geo.rotateX(-Math.PI / 2);
    const pos = geo.attributes.position;
    for (let i = 0; i < pos.count; i++) pos.setY(i, terrainHeight(pos.getX(i), pos.getZ(i)));
    geo.computeVertexNormals();

    // cores por vértice: grama verde/seca, manchas escuras, terra, trilhas e pedra nas encostas
    const nrm = geo.attributes.normal;
    const cGrass = new THREE.Color(0x5b6a33), cDry = new THREE.Color(0x8f8148), cDark = new THREE.Color(0x3f4c26);
    const cDirt = new THREE.Color(0x6e563a), cRock = new THREE.Color(0x77736a), cLeafy = new THREE.Color(0x8a5a2c);
    const colors = new Float32Array(pos.count * 3);
    const c = new THREE.Color();
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i), z = pos.getZ(i);
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
    const uv = geo.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * 90, uv.getY(i) * 90);

    const ground = new THREE.Mesh(geo, this.mat.ground);
    ground.receiveShadow = true;
    this.scene.add(ground);
    this.colliders.add(new THREE.Mesh(geo, this.colliderMat));

    // estrada de asfalto velho acompanhando o relevo, de ponta a ponta do mapa
    const road = new THREE.PlaneGeometry(ROAD_HALF * 2, WORLD_HALF * 2, 1, 140);
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
      { at: 3, width: 1.4, bottom: 0, top: 2.3 },
      { at: 7.2, width: 1.6, bottom: 1.0, top: 2.2 },
    ] });
    this.wall(x0, z0, x1, z0, { height: h, frames: true, openings: [{ at: 5, width: 2, bottom: 1.0, top: 2.2 }] });
    this.wall(x0, z0, x0, z1, { height: h, frames: true, openings: [{ at: 4, width: 1.4, bottom: 1.0, top: 2.2 }] });
    this.wall(x1, z0, x1, z1, { height: h });
    // divisória interna com vão
    this.wall(cx + 1, z0, cx + 1, z1, { height: h, thick: 0.15, mat: M.paint, openings: [{ at: 5.5, width: 1.2, bottom: 0, top: 2.3 }] });
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
      { at: 3.5, width: 1.2, bottom: 0, top: 2.2 },
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
      { at: 1.0, width: 1.1, bottom: 0, top: 2.2 }, { at: 2.6, width: 1.3, bottom: 0.9, top: 2.1 },
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
    this.car(-6, 8, 0.2, M.carBody);
    this.car(-2.5, -18, Math.PI + 0.35, M.carRed);
    this.car(4, 26, Math.PI / 2 - 0.2, M.carBody);
    this.car(-1.5, 52, 0.05, M.carRed);
    this.car(-6.5, -60, Math.PI - 0.25, M.carBody, true); // capotado

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
      const skip = (i % 14 === 0) || (i % 14 === 1) || i === 23 || i === 38; // 4 entradas + 2 partes quebradas
      if (skip) continue;
      const xa = Math.cos(a0) * R, za = Math.sin(a0) * R;
      const xb = Math.cos(a1) * R, zb = Math.sin(a1) * R;
      const tilt = (hash(i, 3) - 0.5) * 0.12;
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

    // ===== Mesa de piquenique =====
    this.box(1.8, 0.06, 0.8, M.wood, 8, 0.78, 3, 0.4);
    this.invisibleCollider(new THREE.BoxGeometry(1.8, 0.8, 0.8), new THREE.Vector3(8, 0.4, 3), new THREE.Euler(0, 0.4, 0));
    for (const s of [-1, 1]) {
      const ox = -Math.sin(0.4) * 0.65 * s, oz = -Math.cos(0.4) * 0.65 * s;
      this.box(1.8, 0.05, 0.28, M.wood, 8 + ox, 0.45, 3 + oz, 0.4, 1, false);
    }
  }

  sandbags(x, z, rot) {
    const c = Math.cos(rot), s = Math.sin(rot);
    for (let row = 0; row < 3; row++) {
      for (let i = 0; i < 5 - (row === 2 ? 1 : 0); i++) {
        const off = (i - 2 + (row % 2) * 0.5) * 0.62;
        const g = lumpy(new THREE.CapsuleGeometry(0.17, 0.32, 3, 8), 0.12, row * 10 + i);
        g.rotateZ(Math.PI / 2);
        g.scale(1, 0.75, 1.15);
        const m = new THREE.Mesh(g, this.mat.sandbag);
        m.position.set(x + c * off, 0.14 + row * 0.27, z - s * off);
        m.rotation.y = rot + (hash(row, i) - 0.5) * 0.15;
        this.solid(m, false);
      }
    }
    this.invisibleCollider(new THREE.BoxGeometry(3.2, 0.85, 0.45), new THREE.Vector3(x, 0.42, z), new THREE.Euler(0, rot, 0));
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

  car(x, z, rotY, paint, flipped = false) {
    const g = new THREE.Group();
    const M = this.mat;
    const body = new THREE.Mesh(boxGeo(4.2, 0.7, 1.8), paint);
    body.position.y = 0.72;
    const hood = new THREE.Mesh(boxGeo(1.2, 0.12, 1.7), paint);
    hood.position.set(1.45, 1.1, 0);
    hood.rotation.z = -0.06;
    const cabin = new THREE.Mesh(boxGeo(2.1, 0.62, 1.62), paint);
    cabin.position.set(-0.25, 1.38, 0);
    const glass = new THREE.Mesh(boxGeo(2.16, 0.46, 1.64), M.glass);
    glass.position.set(-0.25, 1.38, 0);
    const bumperF = new THREE.Mesh(boxGeo(0.15, 0.2, 1.8), M.metal);
    bumperF.position.set(2.15, 0.5, 0);
    const bumperB = bumperF.clone();
    bumperB.position.x = -2.15;
    g.add(body, hood, cabin, glass, bumperF, bumperB);
    for (const [wx, wz] of [[1.3, 0.85], [1.3, -0.85], [-1.3, 0.85], [-1.3, -0.85]]) {
      const wheel = new THREE.Mesh(new THREE.CylinderGeometry(0.38, 0.38, 0.26, 14), M.tire);
      wheel.rotation.x = Math.PI / 2;
      wheel.position.set(wx, 0.38, wz);
      g.add(wheel);
    }
    g.position.set(x, flipped ? 1.85 : 0, z);
    g.rotation.set(flipped ? Math.PI : 0, rotY, flipped ? 0 : 0.03, 'YXZ');
    this.scene.add(g);
    g.updateMatrixWorld(true);
    for (const m of [...g.children]) this.solid(m, m === body || m === cabin);
    this.noGrass.push([x - 2.4, z - 2.4, x + 2.4, z + 2.4]);
  }

  barrel(x, z, mat, lying = false) {
    const m = new THREE.Mesh(new THREE.CylinderGeometry(0.35, 0.35, 1, 16), mat);
    if (lying) { m.rotation.set(Math.PI / 2, 0.7, 0, 'YXZ'); m.position.set(x, 0.35, z); }
    else m.position.set(x, 0.5, z);
    this.solid(m);
    for (const y of [-0.3, 0.3]) { // aros
      if (lying) continue;
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.355, 0.02, 4, 16), this.mat.metal);
      ring.rotation.x = Math.PI / 2;
      ring.position.set(x, 0.5 + y, z);
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

  // ---------- floresta ----------
  _isFree(x, z, margin = 0) {
    for (const [x0, z0, x1, z1] of this.noGrass) {
      if (x > x0 - margin && x < x1 + margin && z > z0 - margin && z < z1 + margin) return false;
    }
    return true;
  }

  _buildForest() {
    const low = this.quality === 'low';
    const rand = makeRng(7);
    const nPine = low ? 120 : 200, nBroad = low ? 70 : 120, nDead = low ? 25 : 40, nBush = low ? 140 : 280;
    const up = new THREE.Vector3(0, 1, 0);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3();
    const color = new THREE.Color();

    const leafMat = this.mat.foliage;
    this.addWind(leafMat, 0.05, 0.12);

    const trunkGeo = new THREE.CylinderGeometry(0.16, 0.3, 5, 7);
    trunkGeo.translate(0, 2.5, 0);
    const trunks = new THREE.InstancedMesh(trunkGeo, this.mat.bark, nPine + nBroad + nDead);

    // pinheiros: 4 cones empilhados
    const pineLevels = [[2.1, 2.6, 2.4], [1.7, 2.3, 3.6], [1.25, 2.0, 4.7], [0.7, 1.5, 5.7]].map(([r, h, y]) => {
      const g = lumpy(new THREE.ConeGeometry(r, h, 8, 2), 0.12, r * 10);
      g.translate(0, y, 0);
      return new THREE.InstancedMesh(g, leafMat, nPine);
    });
    // árvores de folhas: 3 copas arredondadas
    const crownGeos = [[1.8, 0, 5.0, 0], [1.3, 1.0, 4.3, 0.5], [1.25, -0.9, 4.5, -0.5]].map(([r, x, y, z], k) => {
      const g = lumpy(new THREE.IcosahedronGeometry(r, 1), 0.3, k + 5);
      g.translate(x, y, z);
      return new THREE.InstancedMesh(g, leafMat, nBroad);
    });
    const branchGeo = new THREE.CylinderGeometry(0.03, 0.1, 2.2, 5);
    branchGeo.translate(0, 1.1, 0);
    const branches = new THREE.InstancedMesh(branchGeo, this.mat.bark, nDead * 3 + nBroad * 2);

    const colGeo = new THREE.CylinderGeometry(0.3, 0.3, 6, 6);
    colGeo.translate(0, 3, 0);

    const pinePalette = [0x2f4228, 0x34492a, 0x3b4f2c, 0x2b3a24];
    const broadPalette = [0x5a6a2c, 0x6f7230, 0x9a7a30, 0xa8622a, 0x8c3e1e, 0xb8903a, 0x4f5f2a];

    const place = (minTown) => {
      for (;;) {
        const x = (rand() - 0.5) * WORLD_HALF * 2, z = (rand() - 0.5) * WORLD_HALF * 2;
        if (Math.hypot(x, z) < minTown) continue;
        if (!this._isFree(x, z, 1.5) || trailMask(x, z) > 0.05) continue;
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
      for (const lvl of pineLevels) { lvl.setMatrixAt(i, m); lvl.setColorAt(i, color); }
    }
    for (let i = 0; i < nBroad; i++) {
      const [x, z] = place(TOWN_RADIUS - 6);
      const y = terrainHeight(x, z), sc = 0.75 + rand() * 0.6;
      addTrunk(x, y, z, sc, 0.85);
      q.setFromAxisAngle(up, rand() * Math.PI * 2);
      m.compose(p.set(x, y, z), q, s.set(sc, sc, sc));
      color.setHex(broadPalette[Math.floor(rand() * broadPalette.length)]).offsetHSL(0, 0, (rand() - 0.5) * 0.05);
      for (const cg of crownGeos) { cg.setMatrixAt(i, m); cg.setColorAt(i, color); }
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

    // arbustos
    const bushGeo = lumpy(new THREE.IcosahedronGeometry(0.85, 1), 0.35, 3);
    bushGeo.scale(1, 0.65, 1);
    bushGeo.translate(0, 0.35, 0);
    const bushes = new THREE.InstancedMesh(bushGeo, leafMat, nBush);
    for (let i = 0; i < nBush; i++) {
      const [x, z] = place(rand() < 0.3 ? 20 : TOWN_RADIUS - 4);
      const sc = 0.6 + rand() * 0.8;
      q.setFromAxisAngle(up, rand() * Math.PI * 2);
      m.compose(p.set(x, terrainHeight(x, z) - 0.1, z), q, s.set(sc, sc * (0.7 + rand() * 0.5), sc));
      bushes.setMatrixAt(i, m);
      color.setHex(broadPalette[Math.floor(rand() * broadPalette.length)]).offsetHSL(0, -0.05, -0.04);
      bushes.setColorAt(i, color);
    }

    for (const im of [trunks, ...pineLevels, ...crownGeos, branches, bushes]) {
      im.castShadow = true;
      im.receiveShadow = true;
      im.instanceMatrix.needsUpdate = true;
      this.scene.add(im);
    }

    // pedras e troncos caídos
    for (let i = 0; i < 55; i++) {
      const [x, z] = place(14);
      const sc = 0.4 + rand() * 1.3;
      const r = new THREE.Mesh(lumpy(new THREE.DodecahedronGeometry(1, 1), 0.35, i), this.mat.rock);
      r.scale.set(sc * (1 + rand() * 0.6), sc * 0.65, sc);
      r.rotation.set(rand() * 0.4, rand() * 6, rand() * 0.4);
      r.position.set(x, terrainHeight(x, z) + sc * 0.1, z);
      this.solid(r);
    }
    for (let i = 0; i < 18; i++) {
      const [x, z] = place(TOWN_RADIUS + 2);
      const len = 3 + rand() * 4, rad = 0.22 + rand() * 0.15, a = rand() * Math.PI;
      const y = Math.max(terrainHeight(x + Math.cos(a) * len / 2, z - Math.sin(a) * len / 2),
        terrainHeight(x - Math.cos(a) * len / 2, z + Math.sin(a) * len / 2));
      this.cylinder(rad * 0.85, rad, len, this.mat.bark, x, y + rad * 0.7, z, { seg: 8, rz: Math.PI / 2, ry: a });
    }
  }

  // ---------- grama (instanciada, balança com o vento) ----------
  _buildGrass() {
    const count = this.quality === 'low' ? 8000 : 20000;
    // um tufo = 5 folhas finas; cada folha tem os dois lados com normal para cima
    // (iluminada como o chão, sem lado escuro)
    const pos = [];
    for (let i = 0; i < 5; i++) {
      const a = (i / 5) * Math.PI * 2 + i;
      const r = 0.05 + (i % 2) * 0.03;
      const bx = Math.cos(a) * r, bz = Math.sin(a) * r;  // base da folha
      const w = 0.018;
      const px = -Math.sin(a) * w, pz = Math.cos(a) * w; // largura perpendicular
      const tipX = bx * 2.2, tipZ = bz * 2.2, tipY = 0.26 + (i % 3) * 0.06;
      const A = [bx - px, 0, bz - pz], B = [bx + px, 0, bz + pz], C = [tipX, tipY, tipZ];
      pos.push(...A, ...B, ...C, ...B, ...A, ...C);
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    geo.setAttribute('normal', new THREE.Float32BufferAttribute(new Array(pos.length / 3).fill([0, 1, 0]).flat(), 3));

    const mat = new THREE.MeshLambertMaterial();
    this.addWind(mat, 0.25, 1.0);

    // a grama é dividida em blocos: cada bloco só é desenhado se estiver na tela e perto
    const CHUNK = 40;
    const chunks = new Map();
    const rand = makeRng(99);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), sc = new THREE.Vector3(), p = new THREE.Vector3();
    const color = new THREE.Color();
    const up = new THREE.Vector3(0, 1, 0);
    let n = 0;
    while (n < count) {
      // mais densa perto do vilarejo
      const r = rand() < 0.65 ? Math.sqrt(rand()) * 60 : Math.sqrt(rand()) * WORLD_HALF;
      const a = rand() * Math.PI * 2;
      const x = Math.cos(a) * r, z = Math.sin(a) * r;
      if (!this._isFree(x, z) || trailMask(x, z) > 0.4 || Math.abs(x) > WORLD_HALF || Math.abs(z) > WORLD_HALF) continue;
      const s = 0.7 + rand() * 0.8;
      q.setFromAxisAngle(up, rand() * Math.PI * 2);
      sc.set(s, s * (0.6 + rand() * 0.9), s);
      m.compose(p.set(x, terrainHeight(x, z) - 0.02, z), q, sc);
      // tons de verde e de palha, combinando com o chão
      const dry = valueNoise(x * 0.035, z * 0.035);
      color.setHSL(0.2 - dry * 0.07 + rand() * 0.03, 0.3 + rand() * 0.15, 0.14 + dry * 0.08 + rand() * 0.06);
      const key = Math.floor(x / CHUNK) + ',' + Math.floor(z / CHUNK);
      if (!chunks.has(key)) chunks.set(key, { matrices: [], colors: [], cx: (Math.floor(x / CHUNK) + 0.5) * CHUNK, cz: (Math.floor(z / CHUNK) + 0.5) * CHUNK });
      const c = chunks.get(key);
      c.matrices.push(m.clone());
      c.colors.push(color.clone());
      n++;
    }
    this.grassChunks = [];
    for (const c of chunks.values()) {
      const im = new THREE.InstancedMesh(geo, mat, c.matrices.length);
      c.matrices.forEach((mm, i) => { im.setMatrixAt(i, mm); im.setColorAt(i, c.colors[i]); });
      im.computeBoundingSphere();
      im.receiveShadow = true;
      im.userData.center = new THREE.Vector2(c.cx, c.cz);
      im.userData.full = c.matrices.length;
      this.scene.add(im);
      this.grassChunks.push(im);
    }
    this.grassDensity = 1;
    this.grassDistance = 75;
  }

  /** Fração da grama desenhada (qualidade gráfica). */
  setGrassDensity(k) {
    this.grassDensity = k;
    for (const g of this.grassChunks) g.count = Math.floor(g.userData.full * k);
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
