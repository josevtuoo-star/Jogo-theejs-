import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

// Armas novas feitas em código (mesma convenção do revólver: origem na empunhadura da mão
// direita, cano/lâmina para -Z, +Y para cima):
//  - Espingarda de cano duplo (abre na dobradiça, dois cartuchos, chumbo espalhado)
//  - Besta (corda que arma e solta, virote que voa com gravidade e crava)
//  - Taco de beisebol com arame farpado (corpo a corpo, duas mãos)

const steel = () => new THREE.MeshStandardMaterial({ color: 0x3a3e45, metalness: 0.9, roughness: 0.3 });
const dark = () => new THREE.MeshStandardMaterial({ color: 0x16181b, metalness: 0.7, roughness: 0.45 });

function woodTexture(seed = 1, base = '#5a341b') {
  const c = document.createElement('canvas');
  c.width = 64; c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = base;
  g.fillRect(0, 0, 64, 256);
  let s = seed;
  const r = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  for (let i = 0; i < 26; i++) {
    g.strokeStyle = `rgba(${20 + r() * 30},${10 + r() * 15},5,${0.25 + r() * 0.25})`;
    g.lineWidth = 0.6 + r() * 1.8;
    g.beginPath();
    const x = r() * 64;
    g.moveTo(x, 0);
    g.bezierCurveTo(x + (r() - 0.5) * 14, 80, x + (r() - 0.5) * 14, 170, x + (r() - 0.5) * 8, 256);
    g.stroke();
  }
  // desgaste: pontos claros e riscos
  for (let i = 0; i < 40; i++) { g.fillStyle = `rgba(200,170,130,${r() * 0.12})`; g.fillRect(r() * 64, r() * 256, 1 + r() * 3, 1 + r() * 8); }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(6, 6);
  return t;
}

/** Perfil lateral (u = frente, v = cima) extrudado com borda arredondada → frente vira -Z. */
function profile(pts, depth, bevel) {
  const sh = new THREE.Shape();
  sh.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length; i++) {
    const p = pts[i];
    if (p.length === 4) sh.quadraticCurveTo(p[0], p[1], p[2], p[3]); else sh.lineTo(p[0], p[1]);
  }
  const geo = new THREE.ExtrudeGeometry(sh, { depth: Math.max(0.001, depth - bevel * 2), bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel, bevelSegments: 2, curveSegments: 6 });
  geo.translate(0, 0, -(depth - bevel * 2) / 2);
  geo.rotateY(Math.PI / 2);
  return geo;
}

function flashSprite(scene) {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d');
  const rg = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  rg.addColorStop(0, 'rgba(255,250,220,1)'); rg.addColorStop(0.3, 'rgba(255,190,80,0.85)'); rg.addColorStop(1, 'rgba(255,90,0,0)');
  g.fillStyle = rg; g.fillRect(0, 0, 64, 64);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: t, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
  s.visible = false;
  scene.add(s);
  return s;
}

const add = (parent, geo, mat, x = 0, y = 0, z = 0) => {
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x, y, z);
  m.castShadow = true;
  parent.add(m);
  return m;
};
const cylZ = (r1, r2, len, seg = 14) => { const g = new THREE.CylinderGeometry(r1, r2, len, seg); g.rotateX(Math.PI / 2); return g; };

// ======================================================================
/** Espingarda de cano duplo lado a lado, calibre 12. */
export class Shotgun {
  /** light: luz do clarão (pode ser a do revólver: uma luz a menos para o celular). */
  constructor(scene, light = null) {
    this.scene = scene;
    this.kind = 'shotgun';
    this.capacity = 2;
    this.loaded = 2;
    this.reserve = 6;
    this.longGun = true;
    this.sightY = 0.074; // o olho um pouco acima da telha: dá para ver os canos até a massa
    this.readyFP = [0.13, -0.19, 0.26, -0.14, 0.22, 0.2]; // 1ª pessoa: inclinada, mostrando o lado
    this.reloadTime = 2.3;
    const g = new THREE.Group();
    const wood = new THREE.MeshStandardMaterial({ map: woodTexture(7, '#4a2a14'), roughness: 0.55 });
    const st = steel(), dk = dark();
    // coronha (com a "garganta" da empunhadura) e chapa da soleira
    // (com "queda" de verdade: a crista desce abaixo da linha de mira, o rosto apoia nela)
    add(g, profile([[0.03, 0.045], [0.0, 0.03], [-0.03, -0.035, -0.05, -0.04], [-0.12, -0.04], [-0.31, -0.085], [-0.32, -0.09], [-0.33, 0.005],
      [-0.32, 0.015], [-0.18, 0.018], [-0.06, 0.036]], 0.036, 0.007), wood);
    add(g, profile([[-0.32, -0.09], [-0.335, -0.091], [-0.342, 0.006], [-0.328, 0.006]], 0.038, 0.003), dk);
    // báscula (ação)
    add(g, profile([[0.12, 0.05], [0.03, 0.05], [0.025, 0.012], [0.11, 0.012]], 0.046, 0.004), st); // (topo abaixo da telha: a mira passa por cima)
    // guarda-mato e gatilhos
    const guard = add(g, new THREE.TorusGeometry(0.02, 0.0025, 6, 14, Math.PI * 1.15), st, 0, 0.0, -0.045);
    guard.rotation.set(0, Math.PI / 2, Math.PI * 0.95);
    for (const z of [-0.04, -0.052]) add(g, new THREE.BoxGeometry(0.004, 0.02, 0.004), dk, 0, 0.004, z);
    // canos + telha + guarda-mão: giram juntos na dobradiça para abrir
    this.barrels = new THREE.Group();
    this.barrels.position.set(0, 0.018, -0.12);
    g.add(this.barrels);
    for (const x of [-0.0118, 0.0118]) {
      add(this.barrels, cylZ(0.0118, 0.0118, 0.5, 16), st, x, 0.03, -0.25);
      const bore = add(this.barrels, new THREE.CircleGeometry(0.0092, 12), new THREE.MeshBasicMaterial({ color: 0x050505 }), x, 0.03, -0.501);
      bore.rotation.y = Math.PI;
    }
    add(this.barrels, new THREE.BoxGeometry(0.008, 0.006, 0.5), st, 0, 0.044, -0.25);       // telha
    add(this.barrels, new THREE.BoxGeometry(0.02, 0.008, 0.44), st, 0, 0.016, -0.27);        // entre os canos (embaixo)
    add(this.barrels, new THREE.SphereGeometry(0.0028, 8, 6), new THREE.MeshStandardMaterial({ color: 0xd8d0b8, metalness: 0.8, roughness: 0.3 }), 0, 0.049, -0.49); // massa
    add(this.barrels, profile([[-0.02, 0.012], [-0.24, 0.012], [-0.25, -0.006], [-0.03, -0.012]], 0.046, 0.006), wood); // guarda-mão
    // cartuchos nas câmaras (aparecem com a arma aberta)
    this.shells = [];
    const shellMat = new THREE.MeshStandardMaterial({ color: 0x9b1d14, roughness: 0.6 });
    const brass = new THREE.MeshStandardMaterial({ color: 0xc09643, metalness: 0.9, roughness: 0.3 });
    this.brassMat = brass; this.shellMat = shellMat;
    for (const x of [-0.0118, 0.0118]) {
      const sgrp = new THREE.Group();
      sgrp.position.set(x, 0.03, 0.002);
      add(sgrp, cylZ(0.0098, 0.0098, 0.004, 12), brass, 0, 0, 0);
      this.barrels.add(sgrp);
      this.shells.push(sgrp);
    }
    this.model = g;
    this.muzzleLocal = new THREE.Vector3(0, 0.048, -0.63);
    // palma esquerda embaixo do guarda-mão (que gira junto com os canos ao abrir)
    this.supportParent = this.barrels;
    this.support = new THREE.Vector3(-0.006, -0.036, -0.07); // logo à frente da báscula
    this.reloadPoint = new THREE.Object3D();                // boca das câmaras (onde entram os cartuchos)
    this.reloadPoint.position.set(0, 0.05, 0.03);
    this.barrels.add(this.reloadPoint);
    this.flash = flashSprite(scene);
    this.light = light ?? new THREE.PointLight(0xffb060, 0, 12, 2);
    if (!light) scene.add(this.light);
    this.flashT = 0;
    this.open = 0;
    this.cock = 0;
    this.shellsOut = [];
    this.shellGeo = cylZ(0.0098, 0.0098, 0.065, 10);
    this._v = new THREE.Vector3();
    this.setLoaded(2);
  }
  setLoaded(n) { this.loaded = n; this.shells.forEach((s, i) => { s.visible = i < n; }); }
  get muzzleWorld() { this.model.updateWorldMatrix(true, false); return this.model.localToWorld(this._v.copy(this.muzzleLocal)); }
  fire() {
    this.loaded--;
    this.shells[this.loaded].userData.spent = true;
    this.flashT = 0.07;
    const p = this.muzzleWorld;
    this.flash.position.copy(p);
    this.flash.material.rotation = Math.random() * 6;
    this.flash.scale.setScalar(0.3 + Math.random() * 0.15);
    this.light.position.copy(p);
  }
  /** Cápsulas pulam para trás quando abre (extrator). */
  ejectShells(count) {
    this.model.updateWorldMatrix(true, true);
    for (let i = this.capacity - count; i < this.capacity; i++) { // os vazios (os carregados ficam)
      const m = new THREE.Mesh(this.shellGeo, this.shellMat);
      this.shells[i].getWorldPosition(m.position);
      m.quaternion.setFromRotationMatrix(this.barrels.matrixWorld);
      m.castShadow = true;
      this.scene.add(m);
      const back = new THREE.Vector3(0, 0.6, 1.2).applyQuaternion(m.quaternion);
      this.shellsOut.push({ m, v: back.add(new THREE.Vector3((Math.random() - 0.5) * 0.6, 1.2, (Math.random() - 0.5) * 0.6)), spin: new THREE.Vector3(Math.random() * 12, Math.random() * 6, 0), life: 3, bounced: false });
    }
  }
  /** Recarga: abre (canos caem), cápsulas saltam, a esquerda põe dois cartuchos, fecha com tranco. */
  reloadAnim(t, spent) {
    const k = smooth(0, 0.25, t) * (1 - smooth(2.0, 2.3, t));
    const open = smooth(0.2, 0.4, t) * (1 - smooth(1.65, 1.8, t));
    return {
      k, open, pitch: -0.25 * open + 0.15 * smooth(1.7, 1.8, t) * (1 - smooth(1.8, 2.0, t)), roll: 0.35 * open,
      marks: [[0.3, 'brkOpen'], [0.45, 'eject'], [1.15, 'loadRounds'], [1.72, 'brkClose']],
      left: t < 0.5 ? 'support' : t < 0.95 ? 'pouch' : t < 1.45 ? 'reload' : 'support',
    };
  }
  update(dt, groundAt, onBounce) {
    this.barrels.rotation.x = -this.open * 0.62; // canos caem (a boca das câmaras sobe)
    updateFlash(this, dt, 38);
    updateShells(this.shellsOut, this.scene, dt, groundAt, onBounce);
  }
}

// ======================================================================
/** Besta (estilo a do Daryl): trilho, braços, corda e mira de ponto vermelho. */
export class Crossbow {
  constructor(scene) {
    this.scene = scene;
    this.kind = 'crossbow';
    this.capacity = 1;
    this.loaded = 1;
    this.reserve = 8;
    this.longGun = true;
    this.sightY = 0.082;
    this.reloadTime = 1.9;
    this.readyFP = [0.07, -0.17, 0.28, -0.1, 0.1, 0.08]; // 1ª pessoa: mais alta (não some embaixo da tela)
    const g = new THREE.Group();
    const body = new THREE.MeshStandardMaterial({ color: 0x23262a, metalness: 0.4, roughness: 0.55 });
    const camo = new THREE.MeshStandardMaterial({ color: 0x3f3b2c, roughness: 0.8 });
    const dk = dark();
    // coronha esqueletada + empunhadura + trilho
    add(g, profile([[0.02, 0.04], [0.0, 0.02], [-0.025, -0.06, -0.04, -0.07], [-0.07, -0.06], [-0.1, -0.02], [-0.3, -0.06], [-0.33, 0.03], [-0.2, 0.035], [-0.06, 0.05]], 0.032, 0.005), camo);
    add(g, profile([[0.6, 0.045], [-0.02, 0.05], [-0.02, 0.02], [0.6, 0.028]], 0.04, 0.004), body);
    const guard = add(g, new THREE.TorusGeometry(0.018, 0.0025, 6, 14, Math.PI * 1.1), dk, 0, 0.003, -0.04);
    guard.rotation.set(0, Math.PI / 2, Math.PI * 0.95);
    add(g, new THREE.BoxGeometry(0.004, 0.018, 0.004), dk, 0, 0.006, -0.038);
    // estribo na ponta
    const stirrup = add(g, new THREE.TorusGeometry(0.05, 0.005, 6, 16, Math.PI), dk, 0, 0.0, -0.64);
    stirrup.rotation.set(Math.PI / 2, 0, 0);
    // braços (dois lados, curvados para trás) e polias
    this.tips = [];
    for (const s of [-1, 1]) {
      const limb = new THREE.Group();
      limb.position.set(s * 0.02, 0.04, -0.55);
      g.add(limb);
      const lg = new THREE.BoxGeometry(0.3, 0.012, 0.03);
      lg.translate(0.15, 0, 0);
      const lm = add(limb, lg, camo);
      limb.rotation.y = s > 0 ? -0.35 : Math.PI + 0.35;
      const tip = new THREE.Object3D();
      tip.position.set(0.3, 0, 0);
      tip.updateMatrix();
      limb.add(tip);
      add(tip, cylZ(0.016, 0.016, 0.012, 12).rotateY(Math.PI / 2).rotateZ(Math.PI / 2), dk);
      this.tips.push(tip);
      lm.castShadow = true;
    }
    // corda: segmento de cada ponta até o trinco (armada) ou até a frente (solta)
    this.stringMat = new THREE.MeshStandardMaterial({ color: 0x14130f, roughness: 0.6 });
    this.strings = [0, 1].map(() => add(g, new THREE.CylinderGeometry(0.0018, 0.0018, 1, 4), this.stringMat));
    // mira de ponto vermelho: tubo aberto (se olha por dentro) com o ponto no meio
    const tube = new THREE.CylinderGeometry(0.017, 0.017, 0.07, 18, 1, true);
    tube.rotateX(Math.PI / 2);
    add(g, tube, new THREE.MeshStandardMaterial({ color: 0x16181b, metalness: 0.7, roughness: 0.45, side: THREE.DoubleSide }), 0, 0.082, -0.08);
    add(g, new THREE.BoxGeometry(0.012, 0.016, 0.05), dk, 0, 0.058, -0.08); // base no trilho
    add(g, new THREE.CircleGeometry(0.0016, 8), new THREE.MeshBasicMaterial({ color: 0xff2010 }), 0, 0.082, -0.06);
    // virote no trilho
    this.bolt = makeBolt();
    this.bolt.position.set(0, 0.058, -0.12);
    g.add(this.bolt);
    this.model = g;
    this.muzzleLocal = new THREE.Vector3(0, 0.058, -0.62);
    this.supportParent = g;
    this.support = new THREE.Vector3(-0.006, 0.0, -0.2);
    this.reloadPoint = new THREE.Object3D(); // a mão puxa a corda por aqui (acompanha o trinco)
    g.add(this.reloadPoint);
    this.flash = null;
    this.cocked = 1;   // corda armada (0..1)
    this.open = 0;
    this.cock = 0;
    this.shellsOut = [];
    this._v = new THREE.Vector3();
    this.setLoaded(1);
    this._updateStrings();
  }
  setLoaded(n) { this.loaded = n; this.bolt.visible = n > 0; }
  get muzzleWorld() { this.model.updateWorldMatrix(true, false); return this.model.localToWorld(this._v.copy(this.muzzleLocal)); }
  fire() { this.loaded--; this.bolt.visible = false; this.cocked = 0; this.fired = true; }
  ejectShells() {}
  reloadAnim(t) {
    const k = smooth(0, 0.25, t) * (1 - smooth(1.6, 1.9, t));
    // aponta para baixo, puxa a corda até o trinco, põe o virote
    return {
      k, open: 0, pitch: -0.32 * smooth(0.15, 0.4, t) * (1 - smooth(1.4, 1.7, t)), roll: 0.3, drop: 0.0, fwd: 0.04,
      marks: [[0.55, 'stringPull'], [0.95, 'stringLatch'], [1.35, 'loadRounds']],
      left: t < 0.35 ? 'support' : t < 1.0 ? 'reload' : t < 1.2 ? 'pouch' : t < 1.45 ? 'reload' : 'support',
      cock: smooth(0.5, 0.95, t),
    };
  }
  _updateStrings() {
    const latch = new THREE.Vector3(0, 0.058, THREE.MathUtils.lerp(-0.47, -0.12, this.cocked));
    this.tips.forEach((tip, i) => {
      tip.parent.updateMatrix();
      const a = new THREE.Vector3().setFromMatrixPosition(tip.parent.matrix.clone().multiply(tip.matrix));
      const s = this.strings[i];
      s.position.lerpVectors(a, latch, 0.5);
      s.scale.y = a.distanceTo(latch);
      s.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), latch.clone().sub(a).normalize());
    });
  }
  update() {
    this._updateStrings();
    this.reloadPoint.position.set(0, 0.058, THREE.MathUtils.lerp(-0.47, -0.12, this.cocked));
  }
}

/** Virote: haste de carbono, ponta de caça e três penas. */
let boltParts = null; // geometrias e materiais compartilhados por todos os virotes
export function makeBolt() {
  const P = boltParts ?? (boltParts = {
    shaft: cylZ(0.0042, 0.0042, 0.4, 8), tip: cylZ(0.007, 0.0001, 0.03, 8), vane: new THREE.PlaneGeometry(0.05, 0.014).rotateY(Math.PI / 2),
    carbon: new THREE.MeshStandardMaterial({ color: 0x1a1a1a, roughness: 0.4, metalness: 0.3 }),
    steel: new THREE.MeshStandardMaterial({ color: 0x9aa0a6, metalness: 0.9, roughness: 0.3 }),
    feather: new THREE.MeshStandardMaterial({ color: 0xc8b23a, roughness: 0.7, side: THREE.DoubleSide }),
  });
  const g = new THREE.Group();
  add(g, P.shaft, P.carbon);
  add(g, P.tip, P.steel, 0, 0, -0.215); // ponta para -Z
  for (let i = 0; i < 3; i++) {
    const holder = new THREE.Group();
    holder.rotation.z = (i / 3) * Math.PI * 2;
    add(holder, P.vane, P.feather, 0, 0.009, 0.17);
    g.add(holder);
  }
  return g; // origem no meio da haste, ponta em -Z
}

// ======================================================================
/** Taco de beisebol com arame farpado (origem na mão de baixo, ponta para +Y como a faca). */
export function makeBat() {
  const g = new THREE.Group();
  const wood = new THREE.MeshStandardMaterial({ map: woodTexture(3, '#8a6a42'), roughness: 0.6 });
  const pts = [];
  // perfil do taco: pomo, cabo fino, corpo grosso
  const prof = [[0.0, -0.11], [0.027, -0.11], [0.03, -0.1], [0.016, -0.09], [0.015, 0.05], [0.02, 0.2], [0.03, 0.38], [0.036, 0.55], [0.036, 0.69], [0.03, 0.72], [0.0, 0.73]];
  for (const [r, y] of prof) pts.push(new THREE.Vector2(r, y));
  add(g, new THREE.LatheGeometry(pts, 16), wood);
  // fita na empunhadura
  add(g, new THREE.CylinderGeometry(0.0172, 0.0172, 0.15, 12), new THREE.MeshStandardMaterial({ color: 0x1b1b1b, roughness: 0.85 }), 0, 0.0, 0);
  // arame farpado: hélice em volta do corpo + farpas
  const wire = new THREE.MeshStandardMaterial({ color: 0x6b6458, metalness: 0.8, roughness: 0.5 });
  const curve = new THREE.CatmullRomCurve3(Array.from({ length: 60 }, (_, i) => {
    const t = i / 59, y = 0.34 + t * 0.34, a = t * Math.PI * 2 * 5.5, r = 0.036 + (y > 0.55 ? 0 : -0.005 * (0.55 - y) / 0.2) + 0.004;
    return new THREE.Vector3(Math.cos(a) * r, y, Math.sin(a) * r);
  }));
  add(g, new THREE.TubeGeometry(curve, 160, 0.0018, 4, false), wire);
  const barbs = [];
  for (let i = 0; i < 26; i++) {
    const p = curve.getPoint(i / 25);
    const b = new THREE.ConeGeometry(0.0016, 0.016, 4);
    b.translate(0, 0.008, 0);
    const d = new THREE.Vector3(p.x, 0, p.z).normalize();
    b.applyMatrix4(new THREE.Matrix4().makeRotationFromQuaternion(new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.add(new THREE.Vector3(0, (i % 2 ? 0.6 : -0.6), 0)).normalize())));
    b.translate(p.x, p.y, p.z);
    barbs.push(b);
  }
  add(g, mergeGeometries(barbs), wire);
  g.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  g.userData.upperGrip = new THREE.Vector3(0, 0.1, 0); // onde vai a mão esquerda
  g.userData.tip = new THREE.Vector3(0, 0.62, 0);
  return g;
}

// ---------- utilidades ----------
function smooth(a, b, x) { const t = Math.min(Math.max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t); }
function updateFlash(w, dt, intensity) {
  if (!w.flash) return;
  if (w.flashT > 0) {
    w.flashT -= dt;
    const k = Math.max(0, w.flashT / 0.07);
    w.flash.visible = k > 0;
    w.flash.material.opacity = k;
    w.light.intensity = intensity * k;
  } else if (w.flash.visible) { w.flash.visible = false; w.light.intensity = 0; } // (a luz pode ser compartilhada)
}
function updateShells(list, scene, dt, groundAt, onBounce) {
  for (let i = list.length - 1; i >= 0; i--) {
    const s = list[i];
    s.life -= dt;
    s.v.y -= 9.8 * dt;
    s.m.position.addScaledVector(s.v, dt);
    s.m.rotation.x += s.spin.x * dt;
    s.m.rotation.y += s.spin.y * dt;
    const gy = (groundAt ? groundAt(s.m.position.x, s.m.position.z) : 0) + 0.01;
    if (s.m.position.y < gy) {
      s.m.position.y = gy;
      if (!s.bounced) onBounce?.(s.m.position);
      s.bounced = true;
      s.v.multiplyScalar(0.3);
      s.v.y = Math.abs(s.v.y) * 0.35;
      s.spin.multiplyScalar(0.4);
    }
    if (s.life <= 0) { scene.remove(s.m); list.splice(i, 1); }
  }
}
