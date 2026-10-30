import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

// Modelos 3D do jogador (arquivos .glb em /models):
//  - personagem: modelo com esqueleto e pesos de pele próprios (ModelRig, abaixo), dirigido pelo
//    esqueleto procedural do Character — o MESMO corpo em 1ª e 3ª pessoa, com todas as animações;
//  - faca: só é reorientada para a convenção do jogo (lâmina em +Y, fio em -Z, cabo na origem).

const loader = new GLTFLoader();

/**
 * Carrega .glb normalmente. Também aceita glTF em .json cuja geometria está num arquivo de
 * texto base64 (.txt) — usado onde a página não pode buscar .glb nem endereços data: (artifact).
 * A geometria é decodificada aqui e montada num GLB em memória; as texturas continuam .jpg.
 */
async function loadModelFile(url) {
  if (!url.endsWith('.json')) return loader.loadAsync(url);
  const base = url.slice(0, url.lastIndexOf('/') + 1);
  const json = await (await fetch(url)).json();
  const b64 = (await (await fetch(base + json.buffers[0].uri)).text()).trim();
  const raw = atob(b64);
  const bin = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bin[i] = raw.charCodeAt(i);
  delete json.buffers[0].uri;
  json.buffers[0].byteLength = bin.length;
  let js = new TextEncoder().encode(JSON.stringify(json));
  const pad = (n) => (4 - (n % 4)) % 4;
  const jsLen = js.length + pad(js.length), binLen = bin.length + pad(bin.length);
  const glb = new Uint8Array(12 + 8 + jsLen + 8 + binLen);
  const dv = new DataView(glb.buffer);
  dv.setUint32(0, 0x46546c67, true); dv.setUint32(4, 2, true); dv.setUint32(8, glb.length, true);
  dv.setUint32(12, jsLen, true); dv.setUint32(16, 0x4e4f534a, true);
  glb.fill(0x20, 20, 20 + jsLen); glb.set(js, 20);
  dv.setUint32(20 + jsLen, binLen, true); dv.setUint32(24 + jsLen, 0x004e4942, true);
  glb.set(bin, 28 + jsLen);
  return loader.parseAsync(glb.buffer, base);
}

/** Faca do arquivo, reorientada: cabo no centro, lâmina para +Y, fio para -Z. */
export async function loadKnifeModel(url, length = 0.26) {
  const gltf = await loadModelFile(url);
  const m = gltf.scene;
  m.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(m);
  const size = box.max.x - box.min.x; // ao longo de X: ponta em -X, pomo em +X
  const k = length / size;
  // centro do cabo: ~25% do comprimento a partir do pomo
  const gripX = box.max.x - size * 0.25;
  const fix = new THREE.Matrix4().makeBasis(
    new THREE.Vector3(0, -1, 0), // +X (pomo) → -Y
    new THREE.Vector3(0, 0, 1),  // +Y (costas) → +Z, então o fio (-Y) fica em -Z
    new THREE.Vector3(-1, 0, 0),
  ).multiply(new THREE.Matrix4().makeScale(k, k, k))
    .multiply(new THREE.Matrix4().makeTranslation(-gripX, -(box.min.y + box.max.y) / 2, -(box.min.z + box.max.z) / 2));
  const g = new THREE.Group();
  m.traverse((o) => {
    if (!o.isMesh) return;
    const geo = o.geometry.clone();
    geo.applyMatrix4(new THREE.Matrix4().multiplyMatrices(fix, o.matrixWorld));
    const mesh = new THREE.Mesh(geo, o.material);
    o.material.side = THREE.FrontSide;
    mesh.castShadow = true;
    g.add(mesh);
  });
  return g;
}

// ======================================================================
// Personagem com esqueleto próprio (malha com pesos de pele feitos de verdade).
// O esqueleto do jogo (Character) continua sendo animado como antes — captura de movimento,
// IK das armas, escada, escalada — e a cada quadro a pose final é copiada para os ossos do
// modelo: rotação de cada segmento (com o desvio medido numa pose de referência em T), coluna
// distribuída entre as três vértebras, pescoço entre tronco e cabeça, clavículas que apontam
// para o ombro (sobem/avançam junto com o braço) e dedos que fecham conforme a pegada.

const _q1 = new THREE.Quaternion(), _q2 = new THREE.Quaternion(), _q3 = new THREE.Quaternion(), _qs = new THREE.Quaternion(), _v1 = new THREE.Vector3(), _v2 = new THREE.Vector3();
const DOWN = new THREE.Vector3(0, -1, 0);
const FINGERS = ['index', 'middle', 'ring', 'pinky', 'thumb'];

export class ModelRig {
  constructor(gltf) {
    this.root = new THREE.Group();
    this.root.rotation.y = Math.PI; // o arquivo olha para +Z; o jogo, para -Z
    this.root.add(gltf.scene);
    this.meshes = [];
    const B = (this.B = {});
    gltf.scene.traverse((o) => {
      if (o.isBone) B[o.name] = o;
      if (o.isSkinnedMesh) {
        o.frustumCulled = false;
        o.castShadow = true;
        o.receiveShadow = true;
        for (const m of Array.isArray(o.material) ? o.material : [o.material]) { m.envMapIntensity = 0.6; m.side = THREE.FrontSide; }
        this.meshes.push(o);
      }
    });
    this.fp = false;
    this.root.updateMatrixWorld(true);
  }

  _w(name) { return this.B[name].getWorldPosition(new THREE.Vector3()); }

  /** Medidas das juntas (espaço do personagem, em pé, frente -Z) para Character.adaptRig. */
  measure() {
    const w = (n) => this._w(n).toArray();
    const head = this._w('head');
    return {
      pelvis: w('pelvis'), spine: w('spine_01'),
      thigh: w('thigh_r'), knee: w('calf_r'), ankle: w('foot_r'),
      shoulder: w('upperarm_r'), elbow: w('lowerarm_r'), wrist: w('hand_r'),
      palm: this._w('hand_r').distanceTo(this._w('middle_01_r')) * 0.6,
      head: head.toArray(),
      eye: [0, 0.045, -0.076], // olhos em relação à junta da cabeça
    };
  }

  /**
   * Pose de referência: o esqueleto do jogo em T, com cada segmento apontando exatamente como o
   * osso do modelo na pose de amarração; daí sai o desvio de rotação de cada par (grupo → osso).
   */
  calibrate(ch) {
    const B = this.B;
    const saveP = ch.root.position.clone(), saveQ = ch.root.quaternion.clone();
    ch.root.position.set(0, 0, 0);
    ch.root.quaternion.identity();
    const groups = [ch.hips, ch.torso, ch.head];
    for (const arm of [ch.armL, ch.armR]) groups.push(arm.shoulder, arm.upper, arm.elbow, arm.hand, arm.fingers, arm.fingers2);
    for (const leg of [ch.legL, ch.legR]) groups.push(leg.thigh, leg.knee, leg.ankle);
    for (const g of groups) g.quaternion.identity();
    ch.root.add(this.root);
    ch.root.updateMatrixWorld(true);
    const align = (g, from, to) => {
      const d = this._w(to).sub(this._w(from)).normalize();
      g.parent.updateWorldMatrix(true, false);
      d.applyQuaternion(g.parent.getWorldQuaternion(_q1).invert());
      g.quaternion.setFromUnitVectors(DOWN, d);
      g.updateMatrixWorld(true);
    };
    for (const [arm, s] of [[ch.armL, 'l'], [ch.armR, 'r']]) {
      align(arm.upper, `upperarm_${s}`, `lowerarm_${s}`);
      align(arm.elbow, `lowerarm_${s}`, `hand_${s}`);
      align(arm.hand, `hand_${s}`, `middle_01_${s}`);
    }
    for (const [leg, s] of [[ch.legL, 'l'], [ch.legR, 'r']]) {
      align(leg.thigh, `thigh_${s}`, `calf_${s}`);
      align(leg.knee, `calf_${s}`, `foot_${s}`);
    }
    ch.root.updateMatrixWorld(true);
    const off = (g, name) => g.getWorldQuaternion(new THREE.Quaternion()).invert().multiply(B[name].getWorldQuaternion(new THREE.Quaternion()));
    const M = (this.map = {});
    M.pelvis = off(ch.hips, 'pelvis');
    for (const n of ['spine_01', 'spine_02', 'spine_03', 'neck_01']) M[n] = B[n].getWorldQuaternion(new THREE.Quaternion());
    M.spine_03 = off(ch.torso, 'spine_03');
    M.head = off(ch.head, 'head');
    // (coluna e pescoço: desvio em relação à mistura quadril→tronco e tronco→cabeça, iguais na referência)
    this.arms = [];
    for (const [arm, s] of [[ch.armL, 'l'], [ch.armR, 'r']]) {
      const clav = B[`clavicle_${s}`];
      const fingers = [];
      for (const f of FINGERS) {
        for (let k = 1; k <= 3; k++) {
          const b = B[`${f}_0${k}_${s}`];
          const c = B[`${f}_0${k + 1}_${s}`] ?? B[`${f}_04_leaf_${s}`];
          if (!b || !c) continue;
          const dir = this._w(c.name).sub(this._w(b.name)).normalize();
          const axis = new THREE.Vector3().crossVectors(dir, DOWN).normalize();
          axis.applyQuaternion(b.getWorldQuaternion(_q1).invert());
          fingers.push({ b, bind: b.quaternion.clone(), axis, k, thumb: f === 'thumb' });
        }
      }
      this.arms.push({
        arm, clav, clavBind: clav.quaternion.clone(), upperLocal: B[`upperarm_${s}`].position.clone(),
        upper: B[`upperarm_${s}`], lower: B[`lowerarm_${s}`], hand: B[`hand_${s}`],
        oUpper: off(arm.upper, `upperarm_${s}`), oLower: off(arm.elbow, `lowerarm_${s}`), oHand: off(arm.hand, `hand_${s}`),
        fingers,
      });
    }
    this.legs = [];
    for (const [leg, s] of [[ch.legL, 'l'], [ch.legR, 'r']]) {
      this.legs.push({ leg, thigh: B[`thigh_${s}`], calf: B[`calf_${s}`], foot: B[`foot_${s}`],
        oThigh: off(leg.thigh, `thigh_${s}`), oCalf: off(leg.knee, `calf_${s}`), oFoot: off(leg.ankle, `foot_${s}`) });
    }
    for (const g of groups) g.quaternion.identity();
    ch.root.position.copy(saveP);
    ch.root.quaternion.copy(saveQ);
    ch.root.updateMatrixWorld(true);
    // pescoço escondido em 1ª pessoa: 16 cm para baixo e 6 cm para trás, no espaço do peito
    this.neckBind = B.neck_01.position.clone();
    this.neckHide = new THREE.Vector3(0, -0.16, 0.06).applyQuaternion(B.spine_03.getWorldQuaternion(new THREE.Quaternion()).invert());
    this.setFirstPerson(this.fp);
    // estado de cada osso nesta passada (rotação/posição no mundo)
    for (const b of Object.values(B)) b.userData.wq = new THREE.Quaternion(), b.userData.wp = new THREE.Vector3();
  }

  /**
   * Em 1ª pessoa a cabeça e o pescoço somem: o osso do pescoço encolhe e afunda para dentro do
   * peito (senão o toco do pescoço aparecia na frente da câmera ao olhar para baixo).
   */
  setFirstPerson(fp) {
    this.fp = fp;
    const n = this.B.neck_01;
    n.scale.setScalar(fp ? 0.001 : 1);
    if (this.neckBind) n.position.copy(this.neckBind).addScaledVector(this.neckHide, fp ? 1 : 0);
  }

  // osso ← rotação no mundo (o pai já foi resolvido nesta passada)
  _set(b, q) {
    const p = b.parent.userData;
    b.quaternion.copy(_qs.copy(p.wq).invert().multiply(q));
    b.userData.wq.copy(q);
    b.userData.wp.copy(b.position).applyQuaternion(p.wq).add(p.wp);
  }

  update(ch) {
    const B = this.B, M = this.map;
    if (!M) return;
    ch.root.updateMatrixWorld(true);
    const R = B.root;
    R.updateWorldMatrix(true, false);
    R.getWorldQuaternion(R.userData.wq);
    R.getWorldPosition(R.userData.wp);
    const gq = (g, out) => g.getWorldQuaternion(out);
    const qH = gq(ch.hips, new THREE.Quaternion()), qT = gq(ch.torso, new THREE.Quaternion()), qC = gq(ch.head, new THREE.Quaternion());
    // quadril: rotação e posição
    const pel = B.pelvis;
    ch.hips.getWorldPosition(_v1);
    pel.position.copy(_v1).sub(R.userData.wp).applyQuaternion(_q1.copy(R.userData.wq).invert());
    this._set(pel, _q1.copy(qH).multiply(M.pelvis));
    // coluna em três partes, pescoço no meio do caminho
    this._set(B.spine_01, _q1.slerpQuaternions(qH, qT, 0.35).multiply(M.spine_01));
    this._set(B.spine_02, _q1.slerpQuaternions(qH, qT, 0.7).multiply(M.spine_02));
    this._set(B.spine_03, _q1.copy(qT).multiply(M.spine_03));
    this._set(B.neck_01, _q1.slerpQuaternions(qT, qC, 0.5).multiply(M.neck_01));
    this._set(B.head, _q1.copy(qC).multiply(M.head));
    for (const a of this.arms) {
      // clavícula: gira (até um limite) para o ombro do modelo ir aonde está o ombro do esqueleto
      const clav = a.clav, pq = clav.parent.userData.wq;
      const rest = _q3.copy(pq).multiply(a.clavBind);
      clav.userData.wp.copy(clav.position).applyQuaternion(pq).add(clav.parent.userData.wp);
      const from = _v1.copy(a.upperLocal).applyQuaternion(rest).normalize();
      const to = a.arm.shoulder.getWorldPosition(_v2).sub(clav.userData.wp).normalize();
      _q2.setFromUnitVectors(from, to);
      const ang = 2 * Math.acos(Math.min(1, Math.abs(_q2.w)));
      if (ang > 0.5) _q2.slerp(_q1.identity(), 1 - 0.5 / ang);
      this._set(clav, _q2.multiply(rest));
      this._set(a.upper, gq(a.arm.upper, _q1).multiply(a.oUpper));
      this._set(a.lower, gq(a.arm.elbow, _q1).multiply(a.oLower));
      this._set(a.hand, gq(a.arm.hand, _q1).multiply(a.oHand));
      // dedos: fecham em volta do que a mão segura (o quanto vem da pegada do esqueleto)
      const fist = a.arm.fist ?? 0.35;
      for (const f of a.fingers) {
        const ang = f.thumb ? fist * (f.k === 1 ? 0.15 : 0.35) : fist * (f.k === 1 ? 0.8 : f.k === 2 ? 1.0 : 0.7);
        f.b.quaternion.copy(f.bind).multiply(_q1.setFromAxisAngle(f.axis, ang));
      }
    }
    for (const l of this.legs) {
      this._set(l.thigh, gq(l.leg.thigh, _q1).multiply(l.oThigh));
      this._set(l.calf, gq(l.leg.knee, _q1).multiply(l.oCalf));
      this._set(l.foot, gq(l.leg.ankle, _q1).multiply(l.oFoot));
    }
  }
}

/** Carrega o personagem com esqueleto próprio e liga ao esqueleto do jogo. */
export async function loadRiggedPlayer(character, url) {
  const gltf = await loadModelFile(url);
  const rig = new ModelRig(gltf);
  character.adaptRig(rig.measure());
  rig.calibrate(character);
  character.useRig(rig);
  return true;
}
