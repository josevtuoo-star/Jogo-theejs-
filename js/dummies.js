import * as THREE from 'three';
import { Octree } from 'three/addons/math/Octree.js';

// Bonecos de treino improvisados (saco de estopa recheado de palha num poste, pneu velho na
// base). Servem para treinar os golpes: balançam com mola conforme a força e a direção do
// golpe, ficam marcados com os cortes da faca e soltam palha.

function sackTexture(face = false) {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = '#8c7a55';
  g.fillRect(0, 0, 256, 256);
  // trama da estopa
  for (let i = 0; i < 256; i += 3) {
    g.fillStyle = `rgba(60,45,25,${0.12 + Math.random() * 0.1})`;
    g.fillRect(0, i, 256, 1);
    g.fillStyle = `rgba(200,180,130,${0.06 + Math.random() * 0.06})`;
    g.fillRect(i, 0, 1, 256);
  }
  // manchas de sujeira e sangue velho
  for (let i = 0; i < 14; i++) {
    g.fillStyle = i < 10 ? 'rgba(50,38,22,0.18)' : 'rgba(90,18,12,0.3)';
    g.beginPath();
    g.ellipse(Math.random() * 256, Math.random() * 256, 8 + Math.random() * 26, 6 + Math.random() * 18, Math.random() * 3, 0, Math.PI * 2);
    g.fill();
  }
  // costura
  g.strokeStyle = 'rgba(40,30,18,0.8)';
  g.lineWidth = 2;
  g.setLineDash([6, 5]);
  g.beginPath(); g.moveTo(128, 0); g.lineTo(128, 256); g.stroke();
  if (face) {
    // rosto pintado: olhos em X e boca costurada, olhando para +Z da textura (frente)
    g.setLineDash([]);
    g.strokeStyle = 'rgba(25,20,15,0.9)';
    g.lineWidth = 7;
    for (const x of [100, 156]) {
      g.beginPath(); g.moveTo(x - 12, 95); g.lineTo(x + 12, 119); g.moveTo(x + 12, 95); g.lineTo(x - 12, 119); g.stroke();
    }
    g.lineWidth = 4;
    g.beginPath(); g.moveTo(96, 160); g.lineTo(160, 160); g.stroke();
    for (let x = 100; x <= 156; x += 9) { g.beginPath(); g.moveTo(x, 151); g.lineTo(x, 169); g.stroke(); }
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}

const _v = new THREE.Vector3(), _w = new THREE.Vector3(), _n = new THREE.Vector3(), _inv = new THREE.Matrix4();

export class TrainingDummies {
  constructor(scene, groundAt, spots, mats = {}) {
    this.scene = scene;
    this.list = [];
    const sackMat = new THREE.MeshStandardMaterial({ map: sackTexture(), roughness: 1 });
    const faceTex = sackTexture(true);
    faceTex.offset.x = 0.25; // rosto para frente
    const headMat = new THREE.MeshStandardMaterial({ map: faceTex, roughness: 1 });
    const woodMat = mats.wood ?? new THREE.MeshStandardMaterial({ color: 0x5a4632, roughness: 0.95 });
    const tireMat = new THREE.MeshStandardMaterial({ color: 0x1b1b1b, roughness: 0.92 });
    const ropeMat = new THREE.MeshStandardMaterial({ color: 0x9a8458, roughness: 1 });
    this.cutMat = new THREE.MeshBasicMaterial({ color: 0x1e140a, transparent: true, opacity: 0.85, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 });
    this.cutGeo = new THREE.PlaneGeometry(0.13, 0.014);
    const sackGeo = new THREE.CylinderGeometry(0.19, 0.17, 0.62, 14, 3);
    // estopa estufada: o meio é mais largo
    const sp = sackGeo.attributes.position;
    for (let i = 0; i < sp.count; i++) {
      const y = sp.getY(i);
      const k = 1 + 0.12 * Math.cos((y / 0.31) * Math.PI * 0.5) + (Math.random() - 0.5) * 0.03;
      sp.setX(i, sp.getX(i) * k);
      sp.setZ(i, sp.getZ(i) * k);
    }
    sackGeo.computeVertexNormals();

    for (const [x, z, rot] of spots) {
      const y = groundAt(x, z);
      const base = new THREE.Group();
      base.position.set(x, y, z);
      base.rotation.y = rot;
      scene.add(base);
      // pneu deitado e poste
      const tire = new THREE.Mesh(new THREE.TorusGeometry(0.3, 0.11, 8, 18), tireMat);
      tire.rotation.x = Math.PI / 2;
      tire.position.y = 0.1;
      const postLow = new THREE.Mesh(new THREE.CylinderGeometry(0.055, 0.06, 0.6, 8), woodMat);
      postLow.position.y = 0.3;
      base.add(tire, postLow);
      // parte que balança (mola na base do poste)
      const pivot = new THREE.Group();
      pivot.position.y = 0.55;
      base.add(pivot);
      const post = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.055, 1.05, 8), woodMat);
      post.position.y = 0.5;
      const sack = new THREE.Mesh(sackGeo, sackMat);
      sack.position.y = 0.68;
      const rope = new THREE.Mesh(new THREE.TorusGeometry(0.2, 0.015, 5, 16), ropeMat);
      rope.rotation.x = Math.PI / 2;
      rope.position.y = 0.52;
      const head = new THREE.Mesh(new THREE.SphereGeometry(0.13, 14, 10), headMat);
      head.scale.set(1, 1.12, 0.95);
      head.position.y = 1.15;
      const neck = new THREE.Mesh(new THREE.TorusGeometry(0.07, 0.016, 5, 12), ropeMat);
      neck.rotation.x = Math.PI / 2;
      neck.position.y = 1.03;
      // braços: um sarrafo atravessado com as pontas enroladas em estopa
      const bar = new THREE.Mesh(new THREE.BoxGeometry(0.85, 0.05, 0.05), woodMat);
      bar.position.y = 0.92;
      bar.rotation.z = 0.06;
      pivot.add(post, sack, rope, head, neck, bar);
      for (const s of [-1, 1]) {
        const fist = new THREE.Mesh(new THREE.SphereGeometry(0.06, 8, 6), sackMat);
        fist.position.set(s * 0.43, 0.92 + s * 0.025, 0);
        pivot.add(fist);
      }
      base.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });

      // colisão do jogador (cilindro do tamanho do saco)
      const col = new THREE.Mesh(new THREE.CylinderGeometry(0.24, 0.24, 1.75, 8));
      col.position.set(x, y + 0.88, z);
      col.updateMatrixWorld(true);
      const octree = new Octree().fromGraphNode(col);

      this.list.push({
        base, pivot, sack, head, octree,
        center: new THREE.Vector3(x, y + 1.2, z),
        tilt: new THREE.Vector2(), tiltV: new THREE.Vector2(), // inclinação x/z e velocidade
        twist: 0, twistV: 0,
        cuts: [], nextCut: 0,
      });
    }
  }

  /** Para colisão do jogador e dos objetos (mesma interface das portas). */
  get colliders() { return this.list; }

  /**
   * Golpe corpo a corpo: acha o boneco dentro do alcance e do cone à frente.
   * origin/dir: de onde e para onde o golpe vai (horizontal), reach em metros.
   * Retorna { dummy, point, normal, part } ou null.
   */
  find(origin, dir, reach, cone = 0.6) {
    let best = null, bestD = Infinity;
    for (const d of this.list) {
      d.pivot.updateWorldMatrix(true, true);
      for (const part of [d.head, d.sack]) {
        const c = part.getWorldPosition(_v);
        const r = part === d.head ? 0.15 : 0.22;
        _w.subVectors(c, origin);
        const along = _w.dot(dir);
        if (along < 0) continue;
        const dist = _w.length() - r;
        if (dist > reach) continue;
        // ângulo no plano horizontal + altura razoável
        const h = Math.hypot(_w.x, _w.z);
        const cos = (_w.x * dir.x + _w.z * dir.z) / Math.max(1e-4, h * Math.hypot(dir.x, dir.z));
        if (cos < Math.cos(cone)) continue;
        const dy = Math.abs((origin.y + dir.y * along) - c.y);
        if (dy > r + 0.45) continue;
        if (dist < bestD) {
          bestD = dist;
          // ponto da superfície virado para quem bate
          const n = _n.set(origin.x - c.x, 0, origin.z - c.z).normalize();
          const y = THREE.MathUtils.clamp(origin.y + dir.y * along, c.y - (part === d.head ? 0.1 : 0.28), c.y + (part === d.head ? 0.1 : 0.28));
          best = { dummy: d, part: part === d.head ? 'head' : 'body', normal: n.clone(), point: new THREE.Vector3(c.x + n.x * r, y, c.z + n.z * r) };
        }
      }
    }
    return best;
  }

  /** Aplica o golpe: balanço (mola) e, com faca, deixa o corte marcado. */
  hit(res, dir, power, { knife = false, slashAngle = 0 } = {}) {
    const d = res.dummy;
    // impulso angular: tomba na direção do golpe (no espaço do boneco)
    _v.set(dir.x, 0, dir.z).normalize().applyAxisAngle(_w.set(0, 1, 0), -d.base.rotation.y);
    const k = power * (res.part === 'head' ? 0.5 : 0.36);
    d.tiltV.x += _v.z * k;
    d.tiltV.y += -_v.x * k;
    d.twistV += (Math.random() - 0.5) * power * 0.8 + slashAngle * power * 0.3;
    if (knife) this._cut(d, res, slashAngle);
  }

  _cut(d, res, angle) {
    let m = d.cuts[d.nextCut];
    if (!m) { m = new THREE.Mesh(this.cutGeo, this.cutMat); d.cuts.push(m); }
    d.nextCut = (d.nextCut + 1) % 24;
    const part = res.part === 'head' ? d.head : d.sack;
    part.add(m);
    // ponto e normal no espaço da peça
    part.updateWorldMatrix(true, false);
    const p = part.worldToLocal(_v.copy(res.point).addScaledVector(res.normal, 0.012));
    m.position.copy(p);
    const nLocal = _w.copy(res.normal).transformDirection(_inv.copy(part.matrixWorld).invert());
    m.lookAt(_n.copy(p).add(nLocal));
    m.rotateZ(angle + (Math.random() - 0.5) * 0.3);
    m.scale.set(0.7 + Math.random() * 0.6, 1, 1);
  }

  update(dt) {
    for (const d of this.list) {
      // mola amortecida: volta a ficar em pé
      const kS = 70, damp = 5.5;
      d.tiltV.x += (-kS * d.tilt.x - damp * d.tiltV.x) * dt;
      d.tiltV.y += (-kS * d.tilt.y - damp * d.tiltV.y) * dt;
      d.tilt.addScaledVector(d.tiltV, dt);
      d.tilt.clampScalar(-0.55, 0.55);
      d.twistV += (-40 * d.twist - 4 * d.twistV) * dt;
      d.twist += d.twistV * dt;
      d.pivot.rotation.set(d.tilt.x, d.twist, d.tilt.y);
    }
  }
}
