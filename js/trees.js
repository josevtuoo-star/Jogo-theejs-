import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

// Copas de árvore feitas de "cartões" com recorte (técnica dos jogos atuais): dezenas de
// planos cruzados com textura de galho de pinheiro ou cacho de folhas com transparência,
// em volta de um miolo escuro. As normais apontam para fora da copa (luz volumosa, sem cara de
// plano) e a sombra respeita os furos entre as folhas.

function rng(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

function canvasTex(size, draw) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  draw(g, size);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

/** Galho de pinheiro visto de cima: haste da esquerda para a direita com agulhas. */
export function pineBranchTexture() {
  return canvasTex(256, (g, s) => {
    const r = rng(11);
    // ramos secundários
    const stems = [[0, s / 2, s * 0.98, s / 2, 1]];
    for (let i = 0; i < 9; i++) {
      const x = s * (0.12 + i * 0.095), side = i % 2 ? 1 : -1;
      stems.push([x, s / 2, x + s * (0.16 + r() * 0.08) * (1 - i * 0.06), s / 2 + side * s * (0.2 + r() * 0.12) * (1 - i * 0.07), 0.6]);
    }
    for (const [x0, y0, x1, y1, w] of stems) {
      g.strokeStyle = 'rgb(70,52,36)';
      g.lineWidth = 3 * w;
      g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke();
      // agulhas ao longo do ramo
      const n = Math.floor(Math.hypot(x1 - x0, y1 - y0) / 2.2);
      for (let k = 0; k < n; k++) {
        const t = k / n, x = x0 + (x1 - x0) * t, y = y0 + (y1 - y0) * t;
        const ang = Math.atan2(y1 - y0, x1 - x0);
        const len = (9 + r() * 7) * (1 - t * 0.35) * (w > 0.8 ? 1.25 : 1);
        for (const sd of [-1, 1]) {
          const a = ang + sd * (0.9 + r() * 0.35);
          const v = 0.55 + r() * 0.45;
          g.strokeStyle = `rgb(${(46 * v) | 0},${(78 * v) | 0},${(40 * v) | 0})`;
          g.lineWidth = 1.3;
          g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.cos(a) * len, y + Math.sin(a) * len); g.stroke();
        }
      }
    }
  });
}

/** Cacho de folhas (claro, a cor de outono vem da cor de cada árvore). */
export function leafClusterTexture() {
  return canvasTex(256, (g, s) => {
    const r = rng(23);
    // galhinhos
    g.strokeStyle = 'rgb(80,62,45)';
    for (let i = 0; i < 7; i++) {
      g.lineWidth = 2;
      g.beginPath(); g.moveTo(s / 2, s * 0.95);
      g.quadraticCurveTo(s * (0.2 + r() * 0.6), s * 0.6, s * (0.1 + r() * 0.8), s * (0.1 + r() * 0.5));
      g.stroke();
    }
    // folhas: elipses pontudas, muitas, em tons claros (o tom final é a cor da árvore)
    for (let i = 0; i < 230; i++) {
      const a = r() * Math.PI * 2, d = Math.sqrt(r()) * s * 0.42;
      const x = s / 2 + Math.cos(a) * d, y = s * 0.45 + Math.sin(a) * d * 0.9;
      const v = 0.6 + r() * 0.4;
      const warm = r();
      g.fillStyle = `rgb(${(235 * v) | 0},${((200 + warm * 40) * v) | 0},${((150 + warm * 30) * v) | 0})`;
      g.save(); g.translate(x, y); g.rotate(r() * Math.PI * 2);
      const L = 9 + r() * 8;
      g.beginPath(); g.moveTo(-L, 0); g.quadraticCurveTo(0, -L * 0.55, L, 0); g.quadraticCurveTo(0, L * 0.55, -L, 0); g.fill();
      g.strokeStyle = `rgba(90,60,30,${0.35 * v})`; g.lineWidth = 0.8;
      g.beginPath(); g.moveTo(-L, 0); g.lineTo(L, 0); g.stroke();
      g.restore();
    }
  });
}

/** Material das copas: recorte por alpha, dos dois lados, cor por instância. */
export function foliageCardMaterial(map) {
  // alphaToCoverage: com o antisserrilhado, a borda recortada das folhas também fica lisa
  const m = new THREE.MeshStandardMaterial({ map, alphaTest: 0.45, alphaToCoverage: true, side: THREE.DoubleSide, roughness: 0.9 });
  const depth = new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, map, alphaTest: 0.45, side: THREE.DoubleSide });
  return { material: m, depth };
}

/** Plano com normais "infladas" (apontando para fora a partir de `center`). */
function card(w, h, center, place) {
  const g = new THREE.PlaneGeometry(w, h);
  place(g);
  const pos = g.attributes.position, nrm = g.attributes.normal;
  const v = new THREE.Vector3();
  for (let i = 0; i < pos.count; i++) {
    v.fromBufferAttribute(pos, i).sub(center);
    v.y *= 0.6;
    v.normalize();
    v.y = v.y * 0.7 + 0.3;
    v.normalize();
    nrm.setXYZ(i, v.x, v.y, v.z);
  }
  return g;
}

/** Pinheiro: verticilos de galhos que caem com o peso, mais curtos para o topo. */
export function pineCardsGeometry(seed = 1) {
  const r = rng(seed);
  const parts = [];
  const tiers = 13;
  for (let t = 0; t < tiers; t++) {
    const k = t / (tiers - 1);
    const y = 1.4 + k * 4.9;
    const len = 2.6 * (1 - k * 0.8) + 0.4;
    const n = Math.round(9 - k * 4);
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + t * 0.7 + r() * 0.4;
      const droop = 0.35 + k * 0.1 + r() * 0.15;
      const center = new THREE.Vector3(0, y, 0);
      parts.push(card(len, len * 0.75, center, (g) => {
        g.rotateX(-Math.PI / 2);          // deitado
        g.translate(len / 2, 0, 0);       // base no tronco
        g.rotateZ(-droop);                // cai com o peso
        g.rotateY(-a);
        g.translate(0, y, 0);
      }));
    }
  }
  // ponta
  for (let i = 0; i < 2; i++) {
    parts.push(card(0.5, 1.3, new THREE.Vector3(0, 6.4, 0), (g) => { g.rotateY(i * Math.PI / 2); g.translate(0, 6.6, 0); }));
  }
  return mergeGeometries(parts);
}

/** Árvore de folhas: cachos espalhados num volume arredondado (três lóbulos). */
export function broadCardsGeometry(seed = 2) {
  const r = rng(seed);
  const parts = [];
  const lobes = [[0, 5.0, 0, 1.9], [1.0, 4.3, 0.5, 1.4], [-0.9, 4.5, -0.5, 1.35]];
  const center = new THREE.Vector3(0, 4.6, 0);
  for (const [lx, ly, lz, lr] of lobes) {
    const n = Math.round(lr * 22);
    for (let i = 0; i < n; i++) {
      // ponto na casca do lóbulo (um pouco para dentro)
      const u = r() * 2 - 1, th = r() * Math.PI * 2, d = lr * (0.7 + r() * 0.35);
      const s = Math.sqrt(1 - u * u);
      const px = lx + Math.cos(th) * s * d, py = ly + u * d * 0.85, pz = lz + Math.sin(th) * s * d;
      const size = 1.1 + r() * 0.6;
      parts.push(card(size, size, center, (g) => {
        g.rotateX((r() - 0.5) * 1.2);
        g.rotateY(th + Math.PI / 2 + (r() - 0.5) * 0.8);
        g.rotateZ((r() - 0.5) * 0.8);
        g.translate(px, py, pz);
      }));
    }
  }
  return mergeGeometries(parts);
}

/** Arbusto: cachos baixos. */
export function bushCardsGeometry(seed = 3) {
  const r = rng(seed);
  const parts = [];
  const center = new THREE.Vector3(0, 0.4, 0);
  for (let i = 0; i < 14; i++) {
    const th = r() * Math.PI * 2, d = 0.25 + r() * 0.55, size = 0.7 + r() * 0.4;
    parts.push(card(size, size * 0.8, center, (g) => {
      g.rotateY(th + (r() - 0.5));
      g.rotateX((r() - 0.5) * 0.6);
      g.translate(Math.cos(th) * d, 0.3 + r() * 0.45, Math.sin(th) * d);
    }));
  }
  return mergeGeometries(parts);
}
