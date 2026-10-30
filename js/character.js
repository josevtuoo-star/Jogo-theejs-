import * as THREE from 'three';
import { makeFlashlightModel } from './flashlight.js';
import { Revolver, SIGHT_Y, CAPACITY, GRIP } from './revolver.js';
import { Shotgun, Crossbow, makeBat } from './weapons.js';
import { makePose, blendPose } from './mocap.js';

// Corpo do personagem — o MESMO em 1ª e 3ª pessoa.
// Em 1ª pessoa a câmera fica nos olhos dele. Cabeça e tronco somem da câmera (continuam fazendo
// sombra) para não taparem a visão; braços, mãos, faca, lanterna, quadril, pernas e botas
// continuam visíveis — são exatamente os mesmos que aparecem em 3ª pessoa.
//
// Animação procedural em camadas:
//  1. locomoção: ciclo de passo realista (andar, trotar, correr, agachado), com joelho, tornozelo,
//     quadril balançando/girando, ombros em contrarrotação e inclinação conforme a velocidade;
//  2. parte de cima: pose do item na mão (mãos livres, faca pronta, lanterna apontada), troca de
//     item, soco e golpe de faca;
//  3. ações: escalar/pular obstáculo/pendurar (mãos apoiadas na borda com IK), escada de mão
//     (mãos nos degraus com IK), nadar, deslizar, rolar, inclinar e morrer.

export const FP_HIDDEN_LAYER = 1;

// medidas do esqueleto: as do corpo procedural; com um modelo 3D com esqueleto próprio elas
// passam a ser as do modelo (Character.adaptRig, chamado por playerModel.js)
let HIP_Y = 0.9;
let HS = 1;                 // escala das alturas do quadril (pernas mais longas → agacha mais)
let UPPER_ARM = 0.286;
let FOREARM_PALM = 0.32; // até o centro da mão
let WRIST = 0.244;  // cotovelo → punho

function damp(a, b, lambda, dt) {
  return a + (b - a) * (1 - Math.exp(-lambda * dt));
}
function smoothstep(a, b, x) {
  const t = Math.min(Math.max((x - a) / (b - a), 0), 1);
  return t * t * (3 - 2 * t);
}
const lerp = THREE.MathUtils.lerp;

/** Membro arredondado pendurado num pivô (ombro, cotovelo, quadril, joelho). */
function limb(w, h, d, mat, top = 0.02) {
  const pivot = new THREE.Group();
  const mesh = new THREE.Mesh(new THREE.CapsuleGeometry(w / 2, Math.max(0.01, h - w), 4, 10), mat);
  mesh.scale.z = d / w;
  mesh.position.y = -h / 2 + top;
  pivot.add(mesh);
  return pivot;
}

function part(geo, mat, x, y, z) {
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x, y, z);
  return m;
}

function makeKnife() {
  const knife = new THREE.Group();
  // faca de caça: cabo de 11 cm, lâmina de 13 cm com ponta e costas retas
  const handle = part(new THREE.CylinderGeometry(0.014, 0.016, 0.105, 8), new THREE.MeshStandardMaterial({ color: 0x2a1c12, roughness: 0.75 }), 0, 0, 0);
  const guard = part(new THREE.BoxGeometry(0.045, 0.01, 0.014), new THREE.MeshStandardMaterial({ color: 0x555555, metalness: 0.8, roughness: 0.4 }), 0, 0.056, 0);
  const shape = new THREE.Shape();
  shape.moveTo(-0.014, 0); shape.lineTo(-0.012, 0.1); shape.quadraticCurveTo(-0.004, 0.13, 0.013, 0.135);
  shape.lineTo(0.015, 0.02); shape.lineTo(0.015, 0); shape.lineTo(-0.014, 0);
  const bladeGeo = new THREE.ExtrudeGeometry(shape, { depth: 0.004, bevelEnabled: false });
  bladeGeo.translate(0, 0, -0.002);
  bladeGeo.rotateY(Math.PI / 2);
  const blade = part(bladeGeo, new THREE.MeshStandardMaterial({ color: 0xa8acb0, metalness: 0.85, roughness: 0.35 }), 0, 0.06, 0);
  knife.add(handle, guard, blade);
  knife.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  return knife; // lâmina ao longo de +Y
}

/**
 * IK de dois ossos (ombro → cotovelo → mão). Calcula a rotação do braço e o ângulo do
 * cotovelo para a mão chegar em `target` (mundo); `pole` (local do ombro) diz para onde o
 * cotovelo aponta.
 */
const _d = new THREE.Vector3(), _u = new THREE.Vector3(), _w = new THREE.Vector3(), _p = new THREE.Vector3();
const _x = new THREE.Vector3(), _y = new THREE.Vector3(), _z = new THREE.Vector3();
const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _dn = new THREE.Vector3();
function solveArmIK(arm, target, pole, weight, FOREARM = FOREARM_PALM) {
  if (weight <= 0.001) return;
  const { shoulder, upper, elbow } = arm;
  shoulder.updateWorldMatrix(true, false);
  _d.copy(target);
  shoulder.worldToLocal(_d);
  const D = Math.min(Math.max(_d.length(), 0.08), UPPER_ARM + FOREARM - 0.002);
  _dn.copy(_d).normalize();
  const a1 = (UPPER_ARM * UPPER_ARM - FOREARM * FOREARM + D * D) / (2 * D);
  const b = Math.sqrt(Math.max(0, UPPER_ARM * UPPER_ARM - a1 * a1));
  _p.copy(pole).addScaledVector(_dn, -pole.dot(_dn)).normalize();
  _u.copy(_dn).multiplyScalar(a1).addScaledVector(_p, b);
  _w.copy(_dn).multiplyScalar(D).sub(_u).normalize();
  _u.normalize();
  _y.copy(_u).negate();
  _z.copy(_w).addScaledVector(_u, -_w.dot(_u)).normalize().negate();
  _x.crossVectors(_y, _z);
  _m.makeBasis(_x, _y, _z);
  _q.setFromRotationMatrix(_m);
  upper.quaternion.slerp(_q, weight);
  elbow.rotation.x = lerp(elbow.rotation.x, Math.acos(Math.max(-1, Math.min(1, _u.dot(_w)))), weight);
}

/**
 * IK de perna (quadril → joelho → tornozelo): coxa e joelho para o tornozelo chegar em `target`
 * (mundo); `pole` (espaço do quadril) é para onde o joelho aponta. O joelho dobra para trás
 * (rotação x negativa), ao contrário do cotovelo.
 */
function solveLegIK(leg, target, pole, weight) {
  if (weight <= 0.001) return;
  const L1 = -leg.knee.position.y, L2 = -leg.ankle.position.y;
  leg.thigh.parent.updateWorldMatrix(true, false);
  _d.copy(target);
  leg.thigh.parent.worldToLocal(_d).sub(leg.thigh.position);
  const D = Math.min(Math.max(_d.length(), 0.1), L1 + L2 - 0.002);
  _dn.copy(_d).normalize();
  const a1 = (L1 * L1 - L2 * L2 + D * D) / (2 * D);
  const b = Math.sqrt(Math.max(0, L1 * L1 - a1 * a1));
  _p.copy(pole).addScaledVector(_dn, -pole.dot(_dn)).normalize();
  _u.copy(_dn).multiplyScalar(a1).addScaledVector(_p, b);
  _w.copy(_dn).multiplyScalar(D).sub(_u).normalize();
  _u.normalize();
  _y.copy(_u).negate();
  _z.copy(_w).addScaledVector(_u, -_w.dot(_u)).normalize();
  _x.crossVectors(_y, _z);
  _m.makeBasis(_x, _y, _z);
  _q.setFromRotationMatrix(_m);
  leg.thigh.quaternion.slerp(_q, weight);
  leg.knee.rotation.x = lerp(leg.knee.rotation.x, -Math.acos(Math.max(-1, Math.min(1, _u.dot(_w)))), weight);
}

/** Orienta a mão no mundo (a partir do antebraço já posicionado). */
const _hq0 = new THREE.Quaternion(), _hq1 = new THREE.Quaternion();
function setHandWorld(arm, q, w) {
  if (w <= 0.001) return;
  arm.elbow.updateWorldMatrix(true, false);
  arm.elbow.getWorldQuaternion(_hq0);
  _hq1.copy(_hq0).invert().multiply(q);
  arm.hand.quaternion.slerp(_hq1, w);
}

/**
 * Base de orientação da mão no espaço da arma. palm = para onde a palma olha,
 * fingers = para onde os dedos apontam (antes de fechar). A mão direita tem a palma em -X
 * local, a esquerda em +X; os dedos em -Y; o polegar em -Z.
 */
function handBasis(side, palm, fingers) {
  const y = new THREE.Vector3(...fingers).normalize().negate();
  const n = new THREE.Vector3(...palm).normalize();
  const x = side > 0 ? n.clone().negate() : n.clone();
  x.addScaledVector(y, -x.dot(y)).normalize();
  const z = new THREE.Vector3().crossVectors(x, y);
  return new THREE.Quaternion().setFromRotationMatrix(new THREE.Matrix4().makeBasis(x, y, z));
}
/** Punho a partir do centro da palma (a palma fica 5 cm à frente do punho e 1,5 cm "para dentro"). */
function wristFrom(palmCenter, palm, fingers) {
  const f = new THREE.Vector3(...fingers).normalize(), n = new THREE.Vector3(...palm).normalize();
  return palmCenter.clone().addScaledVector(f, -0.05).addScaledVector(n, -0.015);
}
// mão direita na empunhadura: palma na lateral direita (olhando para -X), dedos para frente
// envolvendo a frente da empunhadura, polegar por cima
const R_PALM = [-1, 0, 0], R_FING = [0, -0.25, -0.97];
const HAND_R_GUN = handBasis(1, R_PALM, R_FING);
const WRIST_R_GUN = wristFrom(GRIP.clone().add(new THREE.Vector3(0.018, 0, 0)), R_PALM, R_FING);
// mão esquerda apoiando: palma para a direita/cima, por baixo e por fora dos dedos da direita
const L_PALM = [0.85, 0.42, -0.1], L_FING = [0.12, -0.45, -0.88];
const HAND_L_GUN = handBasis(-1, L_PALM, L_FING);
const WRIST_L_GUN = wristFrom(new THREE.Vector3(-0.022, -0.02, -0.004), L_PALM, L_FING);
// lanterna na mão esquerda: a palma por baixo do corpo da lanterna e os dedos fechando pelo
// lado direito; a lente sai à frente, do lado do polegar (a lanterna fica no mundo, como as armas)
const FL_PALM = [0.25, 1, 0], FL_FING = [0.95, 0.1, -0.3];
const HAND_FLASH = handBasis(-1, FL_PALM, FL_FING);
const WRIST_FLASH = wristFrom(new THREE.Vector3(-0.004, -0.034, 0.045), FL_PALM, FL_FING);
// lanterna sozinha no espaço do olhar: à esquerda, baixa, apontando um pouco para o centro
export const FLASH_POSE = [-0.12, -0.155, 0.31, 0.03, 0.1, -0.06];
const FLASH_ON_GUN = new THREE.Vector3(-0.13, -0.005, -0.03); // com o revólver: ao lado da arma
// armas longas: direita na empunhadura da coronha, esquerda por baixo do guarda-mão
// (palma para cima, dedos envolvendo pelo lado direito)
const LR_PALM = [-1, 0, 0], LR_FING = [0, -0.7, -0.7];
const LL_PALM = [0.3, 1, 0], LL_FING = [0.72, 0.1, -0.68];
const LONG_HANDS = {
  shotgun: { qR: handBasis(1, LR_PALM, LR_FING), wR: wristFrom(new THREE.Vector3(0.02, -0.022, 0.036), LR_PALM, LR_FING) }, // (baixa: não tapa a mira)
  crossbow: { qR: handBasis(1, R_PALM, [0, -0.45, -0.89]), wR: wristFrom(new THREE.Vector3(0.018, -0.026, 0.026), R_PALM, [0, -0.45, -0.89]) },
};
const HAND_L_LONG = handBasis(-1, LL_PALM, LL_FING);
const WRIST_L_LONG_OFF = wristFrom(new THREE.Vector3(), LL_PALM, LL_FING); // punho a partir do centro da palma
// taco: as duas mãos fechadas em volta do cabo (direita em cima, esquerda embaixo, perto do pomo)
const BR_PALM = [-1, 0, 0], BR_FING = [0, -1, 0.05];
const BL_PALM = [1, 0, 0], BL_FING = [0, -1, -0.05];
const HAND_R_BAT = handBasis(1, BR_PALM, BR_FING);
const WRIST_R_BAT = wristFrom(new THREE.Vector3(0.02, 0, -0.1), BR_PALM, BR_FING);
const HAND_L_BAT = handBasis(-1, BL_PALM, BL_FING);
const WRIST_L_BAT = wristFrom(new THREE.Vector3(-0.02, 0, -0.005), BL_PALM, BL_FING);
// armas longas no espaço do olhar (a coronha encosta no ombro; em "pronto" o cano fica baixo)
// (os braços do personagem são curtos: a arma fica perto do rosto e o tronco gira de lado)
export const LONG_POSES = {
  ready: [0.11, -0.24, 0.25, -0.3, 0.06, 0.1],
  point: [0.05, -0.15, 0.26, -0.03, 0.02, 0.03],
  sprint: [0.12, -0.34, 0.2, -0.85, 0.75, 0.55],
  ads: [0, -0.067, 0.25, 0, 0, 0],
  reload: [0.05, -0.22, 0.24, 0, 0, 0.3],
};
// taco no espaço do olhar: [direita, cima, frente, inclinação, giro, guinada]; a ponta é -Z
export const BAT_POSES = {
  ready: [0.2, -0.3, 0.32, 1.05, -0.35, -0.25],   // apoiado em diagonal, ponta para cima/direita
  sprint: [0.24, -0.45, 0.2, 0.55, -0.5, -0.3],
};
// poses do revólver no espaço do olhar: [direita, cima, frente, inclinação, giro, guinada]
// (a guinada vira o cano um pouco para dentro: em 1ª pessoa se vê a lateral da arma)
export const GUN_POSES = {
  // (distâncias dentro do alcance real dos braços: o punho fica ~0,5 m do ombro)
  ready: [0.15, -0.19, 0.37, -0.12, 0.1, 0.18],
  point: [0.08, -0.12, 0.39, 0, 0.03, 0.06],
  sprint: [0.17, -0.42, 0.18, -1.15, 0.45, 0.1],
  ads: [0, -SIGHT_Y, 0.4, 0, 0, 0],
  reload: [0.03, -0.17, 0.3, 0, 0, 0.1],
};
// tempo de cada troca (sacar/guardar)
const SWAP_TIME = { hands: 0.45, knife: 0.8, gun: 0.95, bat: 0.9, shotgun: 1.15, crossbow: 1.2 };
const FIREARMS = ['gun', 'shotgun', 'crossbow'];
export const isFirearm = (it) => FIREARMS.includes(it);
export const ITEMS = ['hands', 'knife', 'gun', 'shotgun', 'crossbow', 'bat']; // ordem das teclas 1–6

// Golpes. a = fim da preparação, hit = instante do impacto, r = começo da volta, dur = fim.
// reach (m), power (força no alvo), lunge (passo à frente, m/s). Poses: [braço.x, braço.y, braço.z, cotovelo]
// (y e z espelhados para o braço esquerdo), wind = preparação, strike = golpe estendido.
export const MOVES = {
  jab:      { kind: 'punch', hand: -1, a: 0.06, hit: 0.1, r: 0.16, dur: 0.34, reach: 1.25, power: 2, lunge: 0.6, twist: -0.25,
              wind: [0.95, -0.3, 0.2, 2.0], strike: [1.5, -0.1, 0.02, 0.05] },
  cross:    { kind: 'punch', hand: 1, a: 0.07, hit: 0.12, r: 0.2, dur: 0.42, reach: 1.35, power: 3, lunge: 0.9, twist: -0.45,
              wind: [0.85, -0.35, 0.25, 2.1], strike: [1.5, -0.3, 0.0, 0.05] },
  hook:     { kind: 'punch', hand: -1, a: 0.1, hit: 0.17, r: 0.25, dur: 0.52, reach: 1.15, power: 4, lunge: 0.8, twist: 0.6,
              wind: [1.1, 0.5, 1.1, 1.5], strike: [1.35, -0.75, 0.45, 1.45] },
  haymaker: { kind: 'punch', hand: 1, a: 0.0, hit: 0.13, r: 0.26, dur: 0.6, reach: 1.45, power: 7, lunge: 2.4, twist: -0.8, heavy: true,
              wind: [-0.35, 0.3, 0.5, 1.7], strike: [1.6, -0.35, 0.0, 0.1] },
  slash:    { kind: 'knife', hand: 1, a: 0.09, hit: 0.15, r: 0.24, dur: 0.48, reach: 1.75, power: 4, lunge: 0.6, twist: -0.35, grip: 0,
              wind: [1.8, 0.6, 0.55, 1.5], strike: [1.05, -0.6, -0.1, 0.25] },
  backslash:{ kind: 'knife', hand: 1, a: 0.09, hit: 0.15, r: 0.24, dur: 0.48, reach: 1.75, power: 4, lunge: 0.6, twist: 0.4, grip: 0,
              wind: [1.35, -0.75, -0.2, 1.75], strike: [1.25, 0.65, 0.65, 0.3] },
  stab:     { kind: 'knife', hand: 1, a: 0.09, hit: 0.14, r: 0.24, dur: 0.5, reach: 1.9, power: 5, lunge: 1.4, twist: -0.3, grip: 1,
              wind: [0.55, 0.1, 0.35, 1.95], strike: [1.6, -0.12, 0.05, 0.05] },
  overhead: { kind: 'knife', hand: 1, a: 0.0, hit: 0.16, r: 0.3, dur: 0.72, reach: 1.95, power: 9, lunge: 2.6, twist: -0.25, heavy: true, grip: 1,
              wind: [2.85, 0.15, 0.45, 1.35], strike: [0.95, -0.15, 0.0, 0.2] },
  // taco: poses no espaço do olhar (como as armas), as duas mãos seguem o cabo
  batSwing: { kind: 'bat', hand: 1, a: 0.14, hit: 0.22, r: 0.34, dur: 0.66, reach: 2.0, power: 7, lunge: 0.7, twist: -0.55,
              wind: [0.3, -0.1, 0.12, 0.45, -1.3, -1.9], strike: [0.1, -0.18, 0.4, 0.05, -1.45, 0.75], follow: [-0.25, -0.28, 0.25, -0.15, -1.3, 2.0] },
  batBack:  { kind: 'bat', hand: 1, a: 0.13, hit: 0.21, r: 0.33, dur: 0.64, reach: 2.0, power: 6, lunge: 0.6, twist: 0.5,
              wind: [-0.25, -0.1, 0.15, 0.45, 1.3, 1.9], strike: [-0.05, -0.18, 0.4, 0.05, 1.45, -0.75], follow: [0.3, -0.3, 0.22, -0.15, 1.3, -2.0] },
  batJab:   { kind: 'bat', hand: 1, a: 0.1, hit: 0.16, r: 0.24, dur: 0.5, reach: 1.9, power: 5, lunge: 1.2, twist: -0.25,
              wind: [0.1, -0.24, 0.12, 0.05, 0, 0.05], strike: [0.04, -0.2, 0.5, -0.02, 0, 0.02] },
  batSmash: { kind: 'bat', hand: 1, a: 0.0, hit: 0.2, r: 0.34, dur: 0.8, reach: 2.1, power: 12, lunge: 2.4, twist: -0.25, heavy: true,
              wind: [0.2, 0.06, 0.12, 2.3, 0.3, -0.4], strike: [0.02, -0.32, 0.45, -0.75, 0, 0.0], follow: [0.0, -0.45, 0.3, -1.2, 0, 0.1] },
};
const COMBOS = { punch: ['jab', 'cross', 'hook'], knife: ['slash', 'backslash', 'stab'], bat: ['batSwing', 'batBack', 'batJab'] };
const HEAVY = { punch: 'haymaker', knife: 'overhead', bat: 'batSmash' };
const HAND_TWIST = Math.PI / 2;
const KNIFE_REST = -Math.PI / 2 - 0.5;
const _UP = new THREE.Vector3(0, 1, 0);
const _QI = new THREE.Quaternion();
const _mq1 = new THREE.Quaternion(), _mq2 = new THREE.Quaternion(), _mq3 = new THREE.Quaternion(), _me = new THREE.Euler(); // faca na mão, lâmina para frente
const KNIFE_STAB = -Math.PI * 0.97;    // lâmina alinhada com o antebraço

export class Character {
  constructor(scene) {
    const M = {
      jacket: new THREE.MeshStandardMaterial({ color: 0x46503a, roughness: 0.9 }),
      jacketDark: new THREE.MeshStandardMaterial({ color: 0x343c2c, roughness: 0.9 }),
      pants: new THREE.MeshStandardMaterial({ color: 0x343c4c, roughness: 0.9 }),
      skin: new THREE.MeshStandardMaterial({ color: 0xc69a7a, roughness: 0.65 }),
      boots: new THREE.MeshStandardMaterial({ color: 0x2e2218, roughness: 0.8 }),
      sole: new THREE.MeshStandardMaterial({ color: 0x141210, roughness: 0.9 }),
      bag: new THREE.MeshStandardMaterial({ color: 0x5e4e34, roughness: 0.9 }),
      leather: new THREE.MeshStandardMaterial({ color: 0x3a2a1c, roughness: 0.7 }),
      buckle: new THREE.MeshStandardMaterial({ color: 0x8a8a80, roughness: 0.4, metalness: 0.8 }),
      beanie: new THREE.MeshStandardMaterial({ color: 0x6a2e24, roughness: 1 }),
      eye: new THREE.MeshStandardMaterial({ color: 0x1a1612, roughness: 0.3 }),
      beard: new THREE.MeshStandardMaterial({ color: 0x3a2c22, roughness: 1 }),
      glove: new THREE.MeshStandardMaterial({ color: 0x2a2620, roughness: 0.8 }),
    };
    this.fpHidden = [];

    this.root = new THREE.Group();
    this.root.rotation.order = 'YXZ'; // gira (yaw) primeiro, depois tomba no eixo do corpo
    this.hips = new THREE.Group();
    this.hips.position.y = HIP_Y;
    this.root.add(this.hips);

    // ---------- quadril, cinto, bainha da faca ----------
    const pelvis = part(new THREE.CapsuleGeometry(0.11, 0.14, 4, 10), M.pants, 0, -0.03, 0);
    pelvis.rotation.z = Math.PI / 2;
    pelvis.scale.set(1, 1, 0.95);
    this.hips.add(pelvis);
    this.hips.add(part(new THREE.BoxGeometry(0.36, 0.05, 0.23), M.leather, 0, 0.08, 0));
    this.hips.add(part(new THREE.BoxGeometry(0.06, 0.05, 0.02), M.buckle, 0, 0.08, -0.12));
    this.sheath = new THREE.Group();
    this.sheath.position.set(0.215, -0.02, 0.035);
    this.sheath.add(part(new THREE.BoxGeometry(0.04, 0.2, 0.03), M.leather, 0, -0.06, 0));
    this.hips.add(this.sheath);

    // ---------- tronco ----------
    this.torso = new THREE.Group();
    this.torso.position.y = 0.06;
    this.hips.add(this.torso);
    const chest = part(new THREE.CapsuleGeometry(0.19, 0.26, 4, 12), M.jacket, 0, 0.27, 0);
    chest.scale.set(1.12, 1, 0.66);
    this.torso.add(chest);
    this.torso.add(part(new THREE.BoxGeometry(0.012, 0.4, 0.01), M.jacketDark, 0, 0.26, -0.128));
    for (const s of [-1, 1]) this.torso.add(part(new THREE.BoxGeometry(0.1, 0.09, 0.02), M.jacketDark, s * 0.1, 0.16, -0.122));
    const collar = part(new THREE.TorusGeometry(0.095, 0.034, 6, 12), M.jacketDark, 0, 0.52, 0);
    collar.rotation.x = Math.PI / 2;
    this.torso.add(collar);
    // mochila com saco de dormir e alças
    this.torso.add(part(new THREE.BoxGeometry(0.33, 0.4, 0.16), M.bag, 0, 0.28, 0.19));
    this.torso.add(part(new THREE.BoxGeometry(0.27, 0.13, 0.04), M.leather, 0, 0.17, 0.28));
    const roll = part(new THREE.CylinderGeometry(0.075, 0.075, 0.36, 10), M.jacketDark, 0, 0.53, 0.19);
    roll.rotation.z = Math.PI / 2;
    this.torso.add(roll);
    for (const s of [-1, 1]) {
      const strap = part(new THREE.BoxGeometry(0.05, 0.34, 0.015), M.leather, s * 0.1, 0.33, -0.125);
      strap.rotation.z = s * 0.08;
      this.torso.add(strap);
    }
    // presilha da lanterna na alça esquerda (onde ela fica quando desligada)
    this.chestClip = new THREE.Group();
    this.chestClip.position.set(-0.09, 0.34, -0.118);
    this.torso.add(this.chestClip);

    // ---------- pescoço e cabeça (escondidos da câmera em 1ª pessoa) ----------
    const neck = part(new THREE.CylinderGeometry(0.052, 0.062, 0.09, 8), M.skin, 0, 0.55, 0);
    this.torso.add(neck);
    this.head = new THREE.Group();
    this.head.position.y = 0.58;
    const skull = part(new THREE.SphereGeometry(0.12, 14, 12), M.skin, 0, 0.12, 0);
    skull.scale.set(0.95, 1.12, 1.02);
    const beanie = part(new THREE.SphereGeometry(0.128, 14, 8, 0, Math.PI * 2, 0, Math.PI / 2), M.beanie, 0, 0.15, 0.005);
    beanie.scale.set(1, 1.15, 1.05);
    const fold = part(new THREE.CylinderGeometry(0.13, 0.13, 0.04, 14), M.beanie, 0, 0.155, 0.005);
    const beard = part(new THREE.SphereGeometry(0.096, 10, 8, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), M.beard, 0, 0.09, -0.03);
    beard.scale.set(1.05, 0.8, 1.05);
    const nose = part(new THREE.BoxGeometry(0.03, 0.045, 0.04), M.skin, 0, 0.11, -0.125);
    this.head.add(skull, beanie, fold, beard, nose);
    for (const s of [-1, 1]) {
      this.head.add(part(new THREE.BoxGeometry(0.03, 0.018, 0.01), M.eye, s * 0.043, 0.14, -0.113));
      this.head.add(part(new THREE.SphereGeometry(0.024, 6, 6), M.skin, s * 0.12, 0.11, 0));
    }
    this.torso.add(this.head);
    this.eyeLocal = new THREE.Vector3(0, 0.14, -0.1); // olhos, no espaço da cabeça
    // em 1ª pessoa: tudo do tronco para cima some da câmera (menos braços e itens)
    this.torso.traverse((o) => { if (o.isMesh) this.fpHidden.push(o); });

    // ---------- braços: ombro → cotovelo → mão ----------
    const makeArm = (s) => {
      const shoulder = new THREE.Group();
      shoulder.position.set(s * 0.198, 0.47, 0.039);
      const ball = part(new THREE.SphereGeometry(0.072, 10, 8), M.jacket, 0, 0, 0);
      shoulder.add(ball);
      this.fpHidden.push(ball);
      const upper = limb(0.115, UPPER_ARM + 0.04, 0.115, M.jacket);
      shoulder.add(upper);
      const elbow = limb(0.1, 0.28, 0.1, M.jacket);
      elbow.position.y = -UPPER_ARM;
      upper.add(elbow);
      const hand = new THREE.Group();
      hand.position.y = -WRIST;
      const palm = part(new THREE.CapsuleGeometry(0.037, 0.05, 3, 8), M.glove, 0, -0.04, 0);
      palm.scale.z = 0.75;
      const thumb = part(new THREE.CapsuleGeometry(0.014, 0.03, 3, 6), M.glove, -s * 0.034, -0.03, -0.028);
      thumb.rotation.z = s * 0.5;
      hand.add(palm, thumb);
      // dedos (fecham em punho para segurar a faca e socar)
      const fingers = new THREE.Group();
      fingers.position.y = -0.0785;
      hand.add(fingers);
      const fingers2 = new THREE.Group();
      fingers2.position.y = -0.038;
      fingers.add(fingers2);
      elbow.add(hand);
      this.torso.add(shoulder);
      return { shoulder, upper, elbow, hand, fingers, fingers2, side: s, fist: 0 };
    };
    this.armL = makeArm(-1);
    this.armR = makeArm(1);

    // itens: faca (mão direita ou bainha) e lanterna (mão esquerda ou presilha do peito)
    this.knife = makeKnife();
    this.flash = makeFlashlightModel(1.25);
    this._placeItems('hands', false);

    // ---------- pernas: quadril → joelho → tornozelo → pé ----------
    const makeLeg = (x) => {
      const thigh = limb(0.165, 0.39, 0.175, M.pants);
      thigh.position.set(x, -0.042, 0.013);
      const knee = limb(0.145, 0.44, 0.15, M.pants);
      knee.position.y = -0.352;
      const ankle = new THREE.Group();
      ankle.position.y = -0.414;
      const boot = part(new THREE.BoxGeometry(0.12, 0.09, 0.26), M.boots, 0, -0.045, -0.055);
      boot.add(part(new THREE.BoxGeometry(0.13, 0.03, 0.28), M.sole, 0, -0.05, 0));
      const cuff = part(new THREE.CylinderGeometry(0.065, 0.07, 0.08, 10), M.boots, 0, 0.03, 0);
      ankle.add(boot, cuff);
      knee.add(ankle);
      thigh.add(knee);
      return { thigh, knee, ankle };
    };
    this.legL = makeLeg(-0.104);
    this.legR = makeLeg(0.104);
    this.hips.add(this.legL.thigh, this.legR.thigh);

    // revólver: no coldre da coxa direita ou na mão (posicionado a partir dos olhos)
    this.revolver = new Revolver(scene);
    this.gunHolster = new THREE.Group();
    this.gunHolster.position.set(0.15, -0.03, 0.055);
    this.gunHolster.rotation.set(-Math.PI / 2 + 0.12, 0, 0.08);
    this.legR.thigh.add(this.gunHolster);
    // espingarda e besta: penduradas nas costas em diagonal (a empunhadura perto do ombro
    // direito / do quadril direito, por onde a mão direita puxa)
    this.shotgun = new Shotgun(scene, this.revolver.light);
    this.crossbow = new Crossbow(scene);
    const sling = (x, y, z, dir, up = new THREE.Vector3(0, 0, 1)) => {
      const g = new THREE.Group();
      g.position.set(x, y, z);
      const f = dir.clone().normalize().negate(); // o cano (-Z da arma) aponta para `dir`
      const u = up.clone().addScaledVector(f, -up.dot(f)).normalize();
      g.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(new THREE.Vector3().crossVectors(u, f), u, f));
      this.torso.add(g);
      return g;
    };
    this.mounts = {
      gun: this.gunHolster,
      shotgun: sling(0.13, 0.43, 0.15, new THREE.Vector3(-0.42, -0.9, 0)),
      crossbow: sling(0.15, 0.06, 0.21, new THREE.Vector3(-0.32, 0.95, 0)),
    };
    this.guns = { gun: this.revolver, shotgun: this.shotgun, crossbow: this.crossbow };
    this._gunKey = 'gun';
    // taco com arame farpado: preso no cinto do lado esquerdo, cabo para cima
    this.bat = new THREE.Group();
    const batModel = makeBat();
    batModel.rotation.x = -Math.PI / 2; // ponta do taco para -Z (como o cano das armas)
    this.bat.add(batModel);
    this.batMount = new THREE.Group();
    this.batMount.position.set(-0.2, 0.06, 0.07);
    this.batMount.rotation.set(-Math.PI / 2 - 0.25, 0, -0.1);
    this.hips.add(this.batMount);

    this.root.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    scene.add(this.root);
    this.scene = scene;
    this.skinned = null;

    this.b = { run: 0, move: 0, crouch: 0, air: 0, climb: 0, death: 0, ladder: 0, slide: 0, swim: 0, flash: 0, land: 0, hang: 0, knife: 0, obstruct: 0, guard: 0, gun: 0, aim: 0, point: 0, bat: 0 };
    this.t = 0;
    this.yaw = 0;
    this.prevYaw = 0;
    this.turnStep = 0;
    this.turnPhase = 0;
    this.runLean = 0;
    this.accelLean = 0;
    this.prevSpeed = 0;
    this.equip = 'hands';
    this.flashOn = false;
    this.swap = -1;          // troca de item em andamento (0..1)
    this.swapTo = 'hands';
    this.attackT = -1;
    this.move = null;        // golpe em andamento (MOVES)
    this.comboIndex = -1;
    this.comboTimer = 0;     // janela para emendar o próximo golpe
    this.queued = null;      // golpe apertado durante o anterior (entra assim que der)
    this.charge = 0;         // golpe forte sendo carregado (0..1)
    this.combatTimer = 0;    // guarda alta por alguns segundos depois de lutar
    this.hitDone = false;
    this.events = [];        // { type: 'swing' | 'hit', move }
    this.recoil = 0;
    this.aiming = false;     // botão de mirar (revólver)
    this.gunPoint = 0;       // depois de atirar, a arma fica erguida um tempo
    this.gunKick = 0;        // recuo do tiro
    this.fireCooldown = 0;
    this.reloadT = -1;       // recarga em andamento (s)
    this.legYaw = 0;         // quadril virado para a direção do passo (andar de lado)
    this.obstructTarget = 0;
    this._batK = 0;          // golpe do taco em andamento (peso da pose do golpe)
    this._batP = [0, 0, 0, 0, 0, 0];
    this._lh = new THREE.Vector3(); // alvo suavizado da mão esquerda na recarga das armas longas
    this.firstPerson = true;
    this.setFirstPerson(true);
    this._v = new THREE.Vector3();
    this._t1 = new THREE.Vector3();
    this._t2 = new THREE.Vector3();
  }

  // ---------- itens ----------
  _placeItems(equip, flashOn) {
    // faca: na mão direita (lâmina para cima/frente) ou na bainha (lâmina para baixo)
    if (equip === 'knife') {
      this.armR.hand.add(this.knife);
      this.knife.position.set(-0.022, -0.078, 0); // na palma (o lado da palma é -X na mão direita)
      this.knife.rotation.set(-Math.PI / 2 - 0.5, 0, 0);
    } else {
      this.sheath.add(this.knife);
      this.knife.position.set(0, 0.01, 0);
      this.knife.rotation.set(Math.PI, 0, 0);
    }
    // armas e taco: na mão (controlados no mundo, a partir dos olhos) ou no coldre/costas/cinto
    const stow = (obj, mount) => { mount.add(obj); obj.position.set(0, 0, 0); obj.quaternion.identity(); };
    for (const [k, G] of Object.entries(this.guns ?? {})) {
      if (equip === k) this.scene.add(G.model); else stow(G.model, this.mounts[k]);
    }
    if (this.bat) { if (equip === 'bat') this.scene.add(this.bat); else stow(this.bat, this.batMount); }
    // lanterna: na mão esquerda (posicionada no mundo por _flashPose) ou presa no peito
    if (flashOn) {
      this.chestClip.updateWorldMatrix(true, false);
      this.flash.updateWorldMatrix(true, false);
      this.flash.matrixWorld.decompose(this.flash.position, this.flash.quaternion, new THREE.Vector3());
      this.scene.add(this.flash);
    } else {
      this.chestClip.add(this.flash);
      this.flash.position.set(0, 0, 0);
      this.flash.rotation.set(0.15, 0, 0);
    }
    this._heldFlash = flashOn;
    if (this.fpHidden) this._flashLayer();
    this._stowLayers();
  }

  /** Em 1ª pessoa as armas penduradas nas costas somem da câmera (ficariam na frente do rosto). */
  _stowLayers() {
    if (!this.guns) return;
    for (const k of ['shotgun', 'crossbow']) {
      const hide = this.firstPerson && this.guns[k].model.parent === this.mounts[k];
      this.guns[k].model.traverse((o) => { if (o.isMesh) o.layers.set(hide ? FP_HIDDEN_LAYER : 0); });
    }
  }

  /** Arma de fogo na mão (ou a última usada). */
  get gun() { return this.guns?.[this._gunKey]; }

  /**
   * Troca o corpo procedural pelo modelo 3D (SkinnedMeshes presos nos mesmos ossos).
   * Faca, lanterna e bainha continuam.
   */
  useModel(meshes) {
    const keep = new Set();
    for (const g of [this.knife, this.flash, this.sheath, this.bat, ...Object.values(this.guns).map((G) => G.model)]) g.traverse((o) => keep.add(o));
    this.root.traverse((o) => { if (o.isMesh && !keep.has(o)) o.visible = false; });
    this.skinned = meshes;
    for (const m of meshes) this.scene.add(m);
    this.fpHidden = meshes.filter((m) => m.userData.fpHide);
    this.setFirstPerson(this.firstPerson);
    this._stowLayers();
  }

  /**
   * Ajusta o esqueleto às medidas de um modelo 3D com esqueleto próprio (posições das juntas no
   * espaço do personagem, em pé, metros, frente -Z). As animações e a IK passam a usar essas
   * medidas, então a mão do modelo cai exatamente onde a IK manda.
   */
  adaptRig(d) {
    const v = (a) => new THREE.Vector3(...a);
    HIP_Y = d.pelvis[1];
    const legLen = v(d.thigh).distanceTo(v(d.knee)) + v(d.knee).distanceTo(v(d.ankle));
    HS = legLen / 0.766;
    this._hipZ = d.pelvis[2];
    this.hips.position.set(0, HIP_Y, this._hipZ);
    const P = v(d.pelvis), S = v(d.spine);
    for (const leg of [this.legL, this.legR]) {
      const s = leg === this.legR ? 1 : -1;
      leg.thigh.position.set(s * Math.abs(d.thigh[0]), d.thigh[1] - P.y, d.thigh[2] - P.z);
      leg.knee.position.set(0, -v(d.thigh).distanceTo(v(d.knee)), 0);
      leg.ankle.position.set(0, -v(d.knee).distanceTo(v(d.ankle)), 0);
    }
    this.torso.position.set(0, S.y - P.y, S.z - P.z);
    UPPER_ARM = v(d.shoulder).distanceTo(v(d.elbow));
    WRIST = v(d.elbow).distanceTo(v(d.wrist));
    FOREARM_PALM = WRIST + d.palm;
    for (const arm of [this.armL, this.armR]) {
      arm.shoulder.position.set(arm.side * Math.abs(d.shoulder[0]), d.shoulder[1] - S.y, d.shoulder[2] - S.z);
      arm.elbow.position.set(0, -UPPER_ARM, 0);
      arm.hand.position.set(0, -WRIST, 0);
    }
    this._shoulderZ = d.shoulder[2] - S.z;
    this.head.position.set(0, d.head[1] - S.y, d.head[2] - S.z);
    this.eyeLocal.set(...d.eye);
    // armas nas costas: para fora das costas do modelo (mais largo que o corpo procedural)
    for (const k of ['shotgun', 'crossbow']) this.mounts[k].position.z += d.back ?? 0.07;
    this.root.updateMatrixWorld(true);
  }

  /** Usa um modelo com esqueleto próprio (o "motorista" copia a pose deste esqueleto para ele). */
  useRig(driver) {
    const keep = new Set();
    for (const g of [this.knife, this.flash, this.sheath, this.bat, ...Object.values(this.guns).map((G) => G.model), driver.root]) g.traverse((o) => keep.add(o));
    this.root.traverse((o) => { if (o.isMesh && !keep.has(o)) o.visible = false; });
    this.rigDriver = driver;
    this.fpHidden = [];
    this.setFirstPerson(this.firstPerson);
  }

  /** Troca o modelo da faca (mesma convenção: cabo na origem, lâmina em +Y). */
  setKnifeModel(model) {
    this.knife.clear();
    this.knife.add(model);
    this._flashLayer();
  }

  /** Tiro. Retorna 'fired', 'dry' (sem bala) ou null (não dá agora). */
  fireGun() {
    const G = this.gun;
    if (!isFirearm(this.equip) || this.swap >= 0 || this.reloadT >= 0 || this.b.gun < 0.8 || this.fireCooldown > 0) return null;
    if (G.loaded <= 0) {
      this.fireCooldown = 0.3;
      G.cock = 1;
      return 'dry';
    }
    G.fire();
    // revólver de ação dupla: puxar o gatilho leva um tempinho; espingarda: segundo cano logo em seguida
    this.fireCooldown = { gun: 0.32, shotgun: 0.24, crossbow: 0.4 }[this.equip];
    this.gunKick = { gun: 1, shotgun: 1.35, crossbow: 0.35 }[this.equip];
    this.gunPoint = 1.6;
    this._kickSide = (Math.random() - 0.5) * 0.04;
    return 'fired';
  }

  /** Começa a recarregar (se der). */
  reload() {
    const g = this.gun;
    if (!isFirearm(this.equip) || this.swap >= 0 || this.reloadT >= 0 || g.loaded >= g.capacity || g.reserve <= 0 || this.b.gun < 0.5) return false;
    this.reloadT = 0;
    this._reloadDone = new Set();
    this._spent = g.capacity - g.loaded;
    if (this.equip !== 'gun') { this.gun.supportParent.updateWorldMatrix(true, false); this._lh.copy(this.gun.supportParent.localToWorld(this._t1.copy(this.gun.support))); }
    return true;
  }

  get reloading() { return this.reloadT >= 0; }

  /** Troca para 'hands' (mãos livres), 'knife', 'bat', 'gun', 'shotgun' ou 'crossbow'. Retorna true se começou a trocar. */
  setEquip(equip) {
    if (equip === this.equip || this.swap >= 0) return false;
    this.reloadT = -1;
    for (const G of Object.values(this.guns)) G.open = 0;
    this.crossbow.cocked = Math.round(this.crossbow.cocked);
    this.move = null; this.attackT = -1; this.charge = 0; this.queued = null;
    this._swapFrom = this.equip;
    this.swap = 0;
    this.swapTo = equip;
    return true;
  }

  setFlashlight(on, intensity = 1) {
    this.flashOn = on;
    const lit = on && intensity > 0.5;
    this.flash.userData.lensMat.color.setHex(lit ? 0xfff6dc : 0x3a3a34);
    this.flash.userData.lensMat.opacity = lit ? 1 : 0.35;
  }

  get attackKind() { return { knife: 'knife', bat: 'bat' }[this.equip] ?? 'punch'; }

  /**
   * Golpe leve (emenda combo: jab → direto → gancho; corte → corte de volta → estocada)
   * ou forte (heavy: depois de carregar). Se outro golpe ainda está no meio, fica na fila.
   */
  attack(heavy = false) {
    if (this.swap >= 0 || isFirearm(this.equip)) return false;
    const kind = this.attackKind;
    let name;
    if (heavy) name = HEAVY[kind];
    else {
      const chain = COMBOS[kind];
      const next = this.comboTimer > 0 && this.comboIndex < chain.length - 1 ? this.comboIndex + 1 : 0;
      name = chain[next];
    }
    // ainda golpeando: só aceita a partir do impacto (fica na fila)
    if (this.move && this.attackT < this.move.r) {
      if (this.attackT > this.move.hit - 0.05) this.queued = heavy ? 'heavy' : 'light';
      return false;
    }
    this._startMove(name, heavy);
    return true;
  }

  _startMove(name, heavy) {
    const m = MOVES[name];
    // com a lanterna na mão esquerda, os socos saem todos da direita
    this.move = this.flashOn && m.hand < 0 ? { ...m, hand: 1, wind: [m.wind[0], -Math.abs(m.wind[1]), m.wind[2], m.wind[3]] } : m;
    this.moveName = name;
    if (!heavy) this.comboIndex = COMBOS[m.kind].indexOf(name);
    else this.comboIndex = -1;
    this.attackT = heavy ? Math.max(0.02, this.charge * 0.05) : 0;
    this.charge = 0;
    this.hitDone = false;
    this.queued = null;
    this.combatTimer = 3.5;
    this.events.push({ type: 'swing', move: this.move, name });
  }

  /** Carregando o golpe forte (segurando o botão): 0..1. */
  setCharge(c) {
    if (this.swap >= 0 || (this.move && this.attackT < this.move.r)) c = 0;
    this.charge = c;
    if (c > 0) this.combatTimer = 3.5;
  }

  get isAttacking() { return !!this.move; }

  /** Golpe acertou algo duro: o braço volta com tranco. */
  hitRecoil(strength = 1) {
    this.recoil = Math.min(1, strength);
    if (this.move && this.attackT < this.move.r) this.attackT = this.move.r;
  }

  /** Distância livre à frente: perto de paredes os braços recolhem. */
  setObstruction(dist) {
    this.obstructTarget = Math.max(0, Math.min(1, (0.8 - dist) / 0.45));
  }

  /** Em 1ª pessoa, só a cabeça some da câmera (continua projetando sombra). */
  setFirstPerson(fp) {
    this.firstPerson = fp;
    this.rigDriver?.setFirstPerson(fp);
    for (const m of this.fpHidden) m.layers.set(fp ? FP_HIDDEN_LAYER : 0);
    this._flashLayer();
    this._stowLayers();
  }

  /** Lanterna presa no peito some em 1ª pessoa (o peito também some); na mão, aparece. */
  _flashLayer() {
    const hide = this.firstPerson && !this._heldFlash;
    this.flash.traverse((o) => { if (o.isMesh) o.layers.set(hide ? FP_HIDDEN_LAYER : 0); });
  }

  getLensWorldPosition(target) {
    this.root.updateMatrixWorld(true);
    return this.flash.userData.lens.getWorldPosition(target);
  }

  /**
   * Câmera de 1ª pessoa: nos olhos; mirando com arma longa, o rosto encosta na coronha e a
   * câmera recua um pouco (a mão e a coronha não tapam a tela).
   */
  getCameraWorldPosition(target, forward) {
    this.getEyeWorldPosition(target);
    const k = this.gun?.longGun && isFirearm(this.equip) ? this.b.aim : 0;
    if (k > 0.001) target.addScaledVector(forward, -0.14 * k);
    return target;
  }

  /** Ponto de vista das armas: os olhos; em 1ª pessoa, presos na cápsula como a câmera. */
  _viewEye(player, target) {
    this.getEyeWorldPosition(target);
    return this.firstPerson ? player.clampView(target) : target;
  }

  /** Posição dos olhos do corpo no mundo (câmera em 1ª pessoa). */
  getEyeWorldPosition(target) {
    this.root.updateMatrixWorld(true);
    return this.head.localToWorld(target.copy(this.eyeLocal));
  }

  // ---------- animação ----------
  update(dt, player) {
    this.t += dt;
    this._dt = dt;
    const b = this.b;
    this.root.position.copy(player.feetPosition);
    for (const e of player.events) if (e.type === 'land' && e.speed > 3.5) b.land = Math.min(1, e.speed / 11);
    b.land = damp(b.land, 0, 5, dt);
    this.recoil = damp(this.recoil, 0, 9, dt);

    // corpo gira para onde se olha (na escada/borda, de frente para a parede)
    let targetYaw = player.yaw;
    if (player.onLadder) targetYaw = Math.atan2(player.ladder.l.nx, player.ladder.l.nz);
    else if (player.isHanging) targetYaw = Math.atan2(-player.hang.normal.x, -player.hang.normal.z);
    let dy = targetYaw - this.yaw;
    dy = Math.atan2(Math.sin(dy), Math.cos(dy));
    this.yaw += dy * (1 - Math.exp(-16 * dt));
    this.root.rotation.y = this.yaw;
    let yawRate = (this.yaw - this.prevYaw) / Math.max(dt, 1e-4);
    yawRate = Math.max(-6, Math.min(6, yawRate));
    this.prevYaw = this.yaw;

    const speed = player.horizontalSpeed;
    const accel = (speed - this.prevSpeed) / Math.max(dt, 1e-4);
    this.prevSpeed = speed;
    const grounded = player.onFloor && !player.sliding;
    b.move = damp(b.move, grounded ? smoothstep(0.08, 0.9, speed) : 0, 10, dt);
    b.run = damp(b.run, smoothstep(2.3, 3.6, speed), 6, dt);
    const sprint = smoothstep(4.4, 6, speed);
    b.crouch = damp(b.crouch, player.crouched && !player.sliding && !player.isClimbing ? 1 : 0, 9, dt);
    b.air = damp(b.air, player.onFloor || player.isClimbing || player.onLadder || player.swimming || player.isHanging ? 0 : 1, 8, dt);
    b.climb = damp(b.climb, player.isClimbing && !player.climb?.toLadder ? 1 : 0, 16, dt);
    b.hang = damp(b.hang, player.isHanging ? 1 : 0, 14, dt);
    b.ladder = damp(b.ladder, player.onLadder || player.climb?.toLadder ? 1 : 0, 10, dt);
    b.slide = damp(b.slide, player.sliding ? 1 : 0, 12, dt);
    b.swim = damp(b.swim, player.swimming ? 1 : 0, 5, dt);
    b.death = damp(b.death, player.dead ? 1 : 0, player.dead ? 3 : 30, dt);
    const busyHands = player.onLadder || player.isClimbing || player.isHanging || player.swimming || player.dead;
    b.flash = damp(b.flash, this.flashOn && !busyHands ? 1 : 0, 7, dt);
    const leaving = this.swap >= 0 && this.swapTo !== this.equip; // guardando o item atual
    b.knife = damp(b.knife, this.equip === 'knife' && !leaving && !busyHands && !player.sliding ? 1 : 0, 8, dt);
    b.obstruct = damp(b.obstruct, busyHands ? 0 : this.obstructTarget, 8, dt);
    this.accelLean = damp(this.accelLean, Math.max(-1, Math.min(1, accel / 8)), 5, dt);
    this.runLean = damp(this.runLean, player.onFloor ? yawRate * 0.035 * smoothstep(1, 6, speed) : 0, 6, dt);

    // a lanterna vai para a mão quando liga e volta para o peito quando desliga
    // (com espingarda/besta as duas mãos estão na arma: ela continua acesa presa no peito)
    const isLong = (it) => it === 'shotgun' || it === 'crossbow';
    // (recarregando o revólver ela volta para o peito: as duas mãos trabalham na arma)
    const wantHeld = this.flashOn && b.flash > 0.5 && !isLong(this.equip) && !(this.swap >= 0 && isLong(this.swapTo)) &&
      !(this.reloadT >= 0 && this.equip === 'gun');
    if (wantHeld !== this._heldFlash) this._placeItems(this.equip, wantHeld);

    // troca de item: a mão desce até o quadril, troca, e volta
    let swapDip = 0;
    if (this.swap >= 0) {
      this.swap += dt / Math.max(SWAP_TIME[this.swapTo], SWAP_TIME[this._swapFrom] ?? 0.5);
      swapDip = Math.sin(Math.min(1, this.swap) * Math.PI);
      if (this.swap >= 0.5 && this.equip !== this.swapTo) {
        this.equip = this.swapTo;
        if (isFirearm(this.equip)) this._gunKey = this.equip;
        this._placeItems(this.equip, this._heldFlash);
      }
      if (this.swap >= 1) this.swap = -1;
    }

    // ================= 1) locomoção =================
    const backwards = player.moveInput.y < -0.1 ? -1 : 1;
    const ph = player.stepPhase * backwards;
    const wr = b.run, ww = 1 - wr;
    const crouchK = b.crouch;
    const thighAmp = (lerp(0.4, 0.62 + 0.28 * sprint, wr) * (1 - crouchK * 0.4)) * b.move;
    const kneeSwing = lerp(0.85, 1.45 + 0.6 * sprint, wr) * b.move;
    const L = this.legL, R = this.legR;
    const legPose = (leg, phase) => {
      const s = Math.sin(phase), c = Math.cos(phase);
      const swingK = Math.pow(Math.max(0, c), 1.2);               // perna indo para frente (no ar)
      const thigh = thighAmp * s + (wr * 0.12 + crouchK * 0.95) * b.move + crouchK * 1.05 * (1 - b.move);
      const knee = -(0.06 + kneeSwing * swingK + 0.22 * b.move * Math.max(0, -c) * ww + crouchK * 1.75);
      leg.thigh.rotation.set(thigh, 0, 0);
      leg.knee.rotation.set(knee, 0, 0);
      // pé fica paralelo ao chão no apoio; empurra com a ponta no fim do passo
      const toeOff = Math.max(0, -s) * Math.max(0, -c) * 0.5 * b.move;
      leg.ankle.rotation.set(-(thigh + knee) * 0.85 + toeOff, 0, 0);
    };
    legPose(L, ph);
    legPose(R, ph + Math.PI);

    // girando parado: passinhos
    const standing = player.onFloor && speed < 0.4;
    this.turnStep = damp(this.turnStep, standing && Math.abs(yawRate) > 0.8 ? 1 : 0, 10, dt);
    this.turnPhase += Math.abs(yawRate) * dt * 2.2 * this.turnStep;
    if (this.turnStep > 0.01) {
      for (const [leg, off] of [[L, 0], [R, Math.PI]]) {
        const lift = Math.max(0, Math.sin(this.turnPhase + off)) * 0.32 * this.turnStep;
        leg.thigh.rotation.x += lift; leg.knee.rotation.x -= lift * 1.6; leg.ankle.rotation.x += lift * 0.6;
      }
    }

    // quadril: sobe e desce duas vezes por ciclo, gira com a perna da frente, cai para o lado
    const idle = (1 - b.move) * (1 - b.air);
    const shift = Math.sin(this.t * 0.45) * idle * (1 - crouchK);
    const bob = -Math.cos(ph * 2) * lerp(0.018, 0.04, wr) * b.move;
    this.hips.position.set(
      player.lean * 0.05 + shift * 0.025,
      HIP_Y + (-crouchK * 0.4 + bob - b.air * 0.04 - b.land * 0.22 - Math.abs(shift) * 0.012) * HS,
      this._hipZ ?? 0
    );
    // andando de lado/diagonal: o quadril e as pernas viram para a direção do passo, o tronco continua mirando
    const mi = player.moveInput;
    let legYawT = 0;
    if (b.move > 0.05 && Math.hypot(mi.x, mi.y) > 0.2 && !player.sliding) {
      let a = Math.atan2(mi.x, mi.y);
      if (Math.abs(a) > Math.PI / 2 + 0.01) a -= Math.sign(a) * Math.PI; // de costas: espelha
      legYawT = -a * 0.62;
    }
    this.legYaw = damp(this.legYaw, legYawT, 7, dt);
    const hipSwing = Math.sin(ph) * 0.1 * thighAmp;
    this.hips.rotation.set(0, hipSwing + this.legYaw, Math.sin(ph) * 0.05 * ww * b.move + shift * 0.04 - this.runLean);
    // pouso: amortece dobrando as pernas
    if (b.land > 0.01) {
      for (const leg of [L, R]) { leg.thigh.rotation.x += b.land * 0.7; leg.knee.rotation.x -= b.land * 1.3; leg.ankle.rotation.x += b.land * 0.5; }
    }
    // no ar: pernas encolhidas
    if (b.air > 0.01) {
      L.thigh.rotation.x += b.air * 0.55; L.knee.rotation.x -= b.air * 0.9;
      R.thigh.rotation.x += b.air * 0.15; R.knee.rotation.x -= b.air * 0.45;
    }

    // tronco: inclina com a velocidade e a aceleração, contra-gira os ombros, acompanha o olhar
    const look = player.pitch;
    this.torso.rotation.set(
      -(0.03 + wr * 0.12 + sprint * 0.14 + crouchK * 0.3) - this.accelLean * 0.08 * b.move + look * 0.25,
      -hipSwing * 1.4 - this.legYaw,
      -player.lean * 0.35
    );
    // respiração: a fase é somada aos poucos (multiplicar o tempo total pela frequência fazia o
    // ritmo "pular" quando o cansaço mudava, e o peito — e a câmera junto — tremia)
    const ex = this._ex = damp(this._ex ?? 0, player.exertion, 1.5, dt);
    this._breathPh = ((this._breathPh ?? 0) + dt * (1.6 + ex * 2.0)) % (Math.PI * 2);
    const breath = Math.sin(this._breathPh);
    this.torso.scale.set(1, 1 + breath * (0.006 + ex * 0.008) * (1 - b.move * 0.7), 1);
    // cansado e parado: ombros sobem e descem com a respiração ofegante, tronco um pouco curvado
    const pant = ex * (1 - b.move);
    this.torso.rotation.x += pant * (0.08 + breath * 0.012);
    // cabeça estabilizada: aponta para onde o jogador olha
    this.head.rotation.set(look * 0.75 - this.torso.rotation.x - this.hips.rotation.x, -this.torso.rotation.y * 0.8, -this.torso.rotation.z * 0.5);

    // ================= 2) braços =================
    const A = this.armL, Bm = this.armR;
    const armAmp = lerp(0.32, 0.75 + 0.2 * sprint, wr) * b.move;
    // balanço natural (oposto às pernas), cotovelos mais dobrados correndo
    const swingArm = (arm, phase) => {
      const s = Math.sin(phase);
      arm.upper.rotation.set(armAmp * s + wr * 0.15 + b.air * 0.45, 0, arm.side * (0.07 + b.air * 0.35));
      arm.elbow.rotation.set(lerp(0.18, 1.35, wr) * Math.max(b.move, 0.25) + Math.max(0, s) * 0.3 * b.move + 0.1, 0, 0);
    };
    swingArm(A, ph + Math.PI); // braço esquerdo vai junto com a perna direita
    swingArm(Bm, ph);

    // ----- captura de movimento real: andar/trotar/correr/agachado (mocap.js) -----
    // substitui a passada procedural quando o corpo está andando; parado continua procedural
    const mc = this.mocap;
    const wMo = mc && mc.has('walk') ? b.move * (1 - b.slide) * (1 - b.swim) : 0;
    if (wMo > 0.001) {
      const u = ph / (Math.PI * 2);
      const P = this._moP ?? (this._moP = makePose()), Q = this._moQ ?? (this._moQ = makePose());
      mc.sample('walk', u, P);
      const tJog = smoothstep(1.9, 3.4, speed), tRun = smoothstep(4.0, 5.8, speed);
      if (tJog > 0.001 && mc.has('jog')) blendPose(P, mc.sample('jog', u, Q), tJog);
      if (tRun > 0.001 && mc.has('run')) blendPose(P, mc.sample('run', u, Q), tRun);
      if (crouchK > 0.01 && mc.has('crouch')) blendPose(P, mc.sample('crouch', u, Q), crouchK);
      // as gravações de corrida são de ~3 m/s; correndo a 6 m/s a passada precisa ser bem maior
      // (senão o pé desliza no chão): amplia o balanço das coxas, joelhos e braços
      // (só as coxas e os braços; dobrar mais os joelhos tirava os pés do chão)
      const amp = 1 + 0.22 * sprint * (1 - crouchK);
      if (amp > 1.001) {
        for (const k of ['thighL', 'thighR', 'upperL', 'upperR']) P[k].slerpQuaternions(_QI, _mq3.copy(P[k]), amp);
      }
      const w = wMo;
      const yq = _mq1.setFromAxisAngle(_UP, this.legYaw);
      const hipsT = _mq2.copy(yq).multiply(P.hips);
      this.hips.quaternion.slerp(hipsT, w);
      this.hips.position.x = lerp(this.hips.position.x, P.hipsPos[0] + player.lean * 0.05, w);
      this.hips.position.y = lerp(this.hips.position.y, HIP_Y + (P.hipsPos[1] - b.land * 0.22) * HS, w);
      // tronco: postura da captura, sem o giro das pernas (continua mirando) + olhar e inclinação
      const torsoT = _mq3.copy(hipsT).invert().multiply(P.hips).multiply(P.torso);
      _me.set(look * 0.25 - this.accelLean * 0.06, 0, -player.lean * 0.35);
      torsoT.multiply(_mq1.setFromEuler(_me));
      this.torso.quaternion.slerp(torsoT, w);
      for (const [leg, Lr] of [[L, 'L'], [R, 'R']]) {
        leg.thigh.quaternion.slerp(P['thigh' + Lr], w);
        leg.knee.rotation.x = lerp(leg.knee.rotation.x, P['knee' + Lr], w);
        leg.ankle.rotation.x = lerp(leg.ankle.rotation.x, P['ankle' + Lr], w);
      }
      for (const [arm, Lr] of [[A, 'L'], [Bm, 'R']]) {
        arm.upper.quaternion.slerp(P['upper' + Lr], w);
        arm.elbow.rotation.x = lerp(arm.elbow.rotation.x, P['elbow' + Lr], w);
      }
      if (b.land > 0.01) for (const leg of [L, R]) { leg.thigh.rotation.x += b.land * 0.5 * w; leg.knee.rotation.x -= b.land * 1.0 * w; }
      // andando agachado: mais baixo que a gravação (os olhos ficam na altura da câmera agachada)
      const deep = crouchK * w;
      if (deep > 0.001) {
        this.hips.position.y -= 0.13 * deep * HS;
        for (const leg of [L, R]) { leg.thigh.rotateX(0.35 * deep); leg.knee.rotation.x -= 0.6 * deep; leg.ankle.rotation.x += 0.25 * deep; }
      }
      // cabeça continua estável olhando para a mira
      this.head.rotation.set(look * 0.75 - this.torso.rotation.x - this.hips.rotation.x, -this.torso.rotation.y * 0.8, -this.torso.rotation.z * 0.5);
    }

    // a cabeça não pode sair da frente da cápsula (agachado, curvado): o corpo recua junto
    // (senão a câmera, presa na cápsula, ficava atrás dos olhos, entre os ombros)
    {
      const free = player.onFloor && !player.sliding && !player.rolling && !busyHands;
      const e = this.getEyeWorldPosition(this._t2);
      const ox = e.x - this.root.position.x, oz = e.z - this.root.position.z;
      const r = Math.hypot(ox, oz), lim = 0.18;
      const k = free && r > lim ? (r - lim) / r : 0;
      const sh = this._rootShift ?? (this._rootShift = new THREE.Vector3());
      sh.x = damp(sh.x, -ox * k, 10, dt);
      sh.z = damp(sh.z, -oz * k, 10, dt);
      this.root.position.x += sh.x;
      this.root.position.z += sh.z;
    }
    // alcançando algo baixo (pegar do chão/da mesa): curva o tronco e dobra os joelhos
    const low = this._reachLow ?? 0;
    if (low > 0.001) {
      this.torso.rotation.x -= 0.8 * low;
      this.head.rotation.x += 0.55 * low;
      this.hips.position.y -= 0.3 * low * HS;
      for (const leg of [L, R]) { leg.thigh.rotation.x += 0.8 * low; leg.knee.rotation.x -= 1.45 * low; leg.ankle.rotation.x += 0.6 * low; }
    }
    // 1ª pessoa: os ombros vêm um pouco à frente quando as mãos trabalham na frente do rosto
    // (o tronco não aparece; os braços alcançam a arma, a lanterna e a escada sem esticar)
    const reach = this.firstPerson ? Math.max(b.gun, b.bat, b.flash, b.guard, b.ladder, Math.min(1, this.charge * 2), b.knife * 0.6) : 0;
    this._fpReach = damp(this._fpReach ?? 0, reach, 10, dt);
    for (const arm of [A, Bm]) arm.shoulder.position.z = (this._shoulderZ ?? 0.039) - 0.09 * this._fpReach;

    // faca pronta: mão direita à frente do peito (aparece no canto da tela em 1ª pessoa)
    const fpRaise = this.firstPerson ? 0.1 : 0;
    const K = b.knife * (1 - sprint * 0.55) * (1 - b.obstruct * 0.8);
    if (K > 0.001) {
      const sway = Math.sin(ph) * 0.06 * b.move;
      Bm.upper.rotation.x = lerp(Bm.upper.rotation.x, 0.85 + fpRaise + look * 0.55 + sway, K);
      Bm.upper.rotation.y = lerp(Bm.upper.rotation.y, 0.02, K);
      Bm.upper.rotation.z = lerp(Bm.upper.rotation.z, 0.2, K);
      Bm.elbow.rotation.x = lerp(Bm.elbow.rotation.x, 1.15 - look * 0.2, K);
    }
    // lanterna ligada: braço esquerdo apontando para frente
    const F = b.flash * (1 - sprint * 0.5) * (1 - b.obstruct * 0.7);
    if (F > 0.001) {
      A.upper.rotation.x = lerp(A.upper.rotation.x, 1.15 + fpRaise + look * 0.75, F);
      A.upper.rotation.y = lerp(A.upper.rotation.y, -0.25, F);
      A.upper.rotation.z = lerp(A.upper.rotation.z, -0.18, F);
      A.elbow.rotation.x = lerp(A.elbow.rotation.x, 0.55 - look * 0.25, F);
    }
    // perto de parede: braços recolhem junto ao peito
    if (b.obstruct > 0.01) {
      for (const arm of [A, Bm]) {
        arm.upper.rotation.x = lerp(arm.upper.rotation.x, 0.3, b.obstruct * 0.7);
        arm.elbow.rotation.x = lerp(arm.elbow.rotation.x, 1.9, b.obstruct * 0.7);
      }
    }
    // troca de item: a mão direita vai até a bainha no quadril
    // (a mão indo até o coldre/bainha é feita com IK em _swapPose, depois da arma)

    // ----- luta -----
    this.comboTimer = Math.max(0, this.comboTimer - dt);
    this.combatTimer = Math.max(0, this.combatTimer - dt);
    const canFight = !busyHands && !player.sliding && !player.rolling;
    // guarda: punhos na altura do queixo enquanto está brigando (mãos livres)
    const guardWant = this.equip === 'hands' && canFight && (this.combatTimer > 0 || this.charge > 0) ? 1 : 0;
    b.guard = damp(b.guard ?? 0, guardWant * (1 - sprint * 0.7), 9, dt);
    const fp = this.firstPerson ? 1 : 0; // em 1ª pessoa os punhos ficam um pouco mais à frente para aparecer na tela
    // punhos à frente do rosto (IK a partir dos olhos, então seguem o olhar e aparecem na tela)
    const guardIK = (arm, w) => {
      if (w < 0.001 || (arm === A && F > 0.5)) return; // esquerda segurando a lanterna
      const s = arm.side, lead = arm === A ? 1 : 0; // a esquerda fica mais à frente
      const bobG = Math.sin(this.t * 2.2 + s) * 0.012 + Math.sin(ph * 2) * 0.012 * b.move;
      this._viewEye(player, this._t2);
      const cy = Math.cos(player.yaw), sy = Math.sin(player.yaw), cp = Math.cos(look), sp = Math.sin(look);
      // frente, direita e cima do olhar
      const fx = -sy * cp, fy = sp, fz = -cy * cp;
      const ux = sy * sp, uy = cp, uz = cy * sp;
      const fwdD = 0.33 + lead * 0.06 + fp * 0.12, down = 0.16 + fp * 0.06 - bobG, sideD = 0.12;
      this._t1.set(
        this._t2.x + fx * fwdD + cy * s * sideD - ux * down,
        this._t2.y + fy * fwdD - uy * down,
        this._t2.z + fz * fwdD - sy * s * sideD - uz * down,
      );
      solveArmIK(arm, this._t1, this._v.set(s * 0.45, -0.9, 0.35), w);
    };
    guardIK(A, b.guard);
    guardIK(Bm, b.guard);
    // dedos: punho fechado segurando a faca, socando ou em guarda; meio abertos relaxados
    for (const arm of [A, Bm]) {
      let want = 0.35;
      if (arm === Bm && (this.equip === 'knife' || this.equip === 'bat' || this.swap >= 0.45)) want = 1.45;
      if (arm === A && b.bat > 0.3 && !this._heldFlash) want = 1.45;
      if (arm === A && this._heldFlash) want = 1.35;
      if (b.gun > 0.3) want = arm === Bm ? 1.3 : 1.2;
      if (b.guard > 0.3 || (this.move && this.move.hand === arm.side)) want = Math.max(want, 1.5);
      if (b.climb > 0.3 || b.hang > 0.3 || b.ladder > 0.3) want = 0.9;
      arm.fist = damp(arm.fist, want, 14, dt);
      arm.fingers.rotation.set(0, 0, -arm.side * arm.fist * 1.1);
      arm.fingers2.rotation.set(0, 0, -arm.side * arm.fist * 1.3);
    }

    // carregando o golpe forte: braço vai para trás e o corpo gira
    const heavyMove = MOVES[HEAVY[this.attackKind]];
    const ch = smoothstep(0, 1, this.charge);
    const armOf = (m) => (m.hand > 0 || this.flashOn ? Bm : A);
    const poseArm = (arm, P, w) => {
      const s = arm.side;
      arm.upper.rotation.x = lerp(arm.upper.rotation.x, P[0] + look * 0.6 * Math.max(0, Math.min(1, P[0] / 1.2)), w);
      arm.upper.rotation.y = lerp(arm.upper.rotation.y, P[1] * s, w);
      arm.upper.rotation.z = lerp(arm.upper.rotation.z, P[2] * s, w);
      arm.elbow.rotation.x = lerp(arm.elbow.rotation.x, P[3] - (P[0] > 1.2 ? look * 0.2 : 0), w);
    };
    let grip = 0;
    this._batK = 0;
    if (ch > 0.001 && !this.move) {
      const tremble = Math.sin(this.t * 40) * 0.015 * ch;
      if (heavyMove.kind === 'bat') { for (let i = 0; i < 6; i++) this._batP[i] = heavyMove.wind[i] + (i === 3 ? tremble * 2 : 0); this._batK = ch; }
      else {
        poseArm(armOf(heavyMove), heavyMove.wind.map((v, i) => v + (i === 0 ? tremble : 0)), ch);
        // em 1ª pessoa o braço lá atrás some da tela: o punho recua até o lado do rosto (a faca sobe
        // acima da cabeça), tremendo com a força, e a outra mão protege
        if (this.firstPerson) {
          const arm = armOf(heavyMove), tr = Math.sin(this.t * 38) * 0.006 * ch;
          const E = heavyMove.kind === 'knife' ? [0.13, 0.07 + tr, 0.22, 0, 0, 0] : [0.17, -0.07 + tr, 0.19, 0, 0, 0];
          this._eyeSpace(E, 0, look, player, this._t1, this._chq ?? (this._chq = new THREE.Quaternion()));
          solveArmIK(arm, this._t1, this._v.set(arm.side * 0.8, -0.5, 0.2), ch);
          if (heavyMove.kind === 'punch') guardIK(arm === A ? Bm : A, ch);
        }
      }
      this.torso.rotation.y += -heavyMove.twist * 0.6 * ch;
      this.torso.rotation.x -= heavyMove.kind === 'knife' ? 0.12 * ch : -0.05 * ch;
      grip = heavyMove.grip ? ch : 0;
    }

    // golpe em andamento
    if (this.move) {
      const m = this.move;
      this.attackT += dt;
      const t = this.attackT;
      if (!this.hitDone && t >= m.hit) { this.hitDone = true; this.events.push({ type: 'hit', move: m, name: this.moveName }); }
      const wind = m.a > 0 ? smoothstep(0, m.a, t) : 1;
      const strike = smoothstep(m.a, m.hit + 0.02, t);
      const back = smoothstep(m.r, m.dur, t);
      const k = wind * (1 - back);
      this._moveK = m.kind === 'punch' ? k : 0;
      const P = m.wind.map((v, i) => lerp(v, m.strike[i], strike));
      const arm = armOf(m);
      if (m.kind === 'bat') {
        // taco: passa do ponto de impacto até o fim do arco (follow-through) e volta
        const fol = m.follow ? smoothstep(m.hit, m.r + 0.04, t) : 0;
        for (let i = 0; i < 6; i++) this._batP[i] = m.follow ? lerp(P[i], m.follow[i], fol) : P[i];
        this._batK = k;
      } else poseArm(arm, P, k);
      if (m.kind === 'punch') {
        // a outra mão volta para proteger o rosto
        const other = arm === A ? Bm : A;
        guardIK(other, k * 0.85);
      }
      // o corpo gira e avança junto com o golpe
      const tw = lerp(-m.twist * 0.6, m.twist, strike) * k;
      this.torso.rotation.y += tw;
      this.hips.rotation.y += tw * 0.35;
      this.torso.rotation.x -= (m.heavy ? 0.22 : 0.08) * Math.sin(strike * Math.PI) * k;
      if (m.grip) grip = Math.max(grip, k);
      if (m.kind !== 'bat') arm.upper.rotation.x -= this.recoil * 0.3;
      if (t >= m.dur) {
        this.move = null;
        this.attackT = -1;
        this.comboTimer = 0.4;
      } else if (this.queued && t >= m.r) {
        const heavy = this.queued === 'heavy';
        this.queued = null;
        this.attack(heavy);
      }
    }
    if (!this.move) this._moveK = 0;
    // punho de briga: gira o antebraço para os nós dos dedos ficarem à frente (palma para dentro)
    for (const arm of [A, Bm]) {
      let tw = b.guard;
      if (arm === A && F > 0.5) tw = 0;
      tw = Math.max(tw, this._moveK || 0) * (1 - b.climb) * (1 - b.hang);
      arm.hand.rotation.set(0, arm.side * HAND_TWIST * tw, 0);
    }
    // pegada da faca: normal (lâmina à frente) ou alinhada ao braço (estocada)
    if (this.knife.parent !== this.sheath) this.knife.rotation.x = lerp(KNIFE_REST, KNIFE_STAB, grip);

    this._gunPose(dt, player, look, ph, sprint, yawRate, busyHands);
    this._batPose(dt, player, look, ph, sprint, yawRate, busyHands);
    this._flashPose(player, look, ph);
    this._reachPose(dt, player);
    this._swapPose();

    // ================= 3) ações de corpo inteiro =================
    this._climbPose(dt, player);
    this._hangPose(player);
    this._ladderPose(player);
    this._swimPose(player);
    this._slidePose(player);
    this._rollPose(player);

    // morte: cai de costas
    const d = b.death;
    this.root.rotation.x = d * 1.45;
    this.root.position.y += d * 0.12;
    if (d > 0.01) {
      A.upper.rotation.z -= d * 0.6;
      Bm.upper.rotation.z += d * 0.6;
    }
    // modelo 3D com esqueleto próprio: copia a pose final para os ossos dele
    this.rigDriver?.update(this);
  }

  /**
   * Revólver na mão: a arma é posicionada no espaço dos olhos (baixa, apontada, mirando pela
   * alça e massa, correndo, recarregando) e as duas mãos vão até ela com IK — então em 1ª pessoa a
   * mira fica exatamente no centro da tela e em 3ª pessoa o corpo faz o mesmo movimento.
   */
  _gunPose(dt, player, look, ph, sprint, yawRate, busyHands) {
    const b = this.b, G = this.gun, key = this._gunKey;
    const out = this.equip === key;
    const long = G.longGun;
    const leaving = this.swap >= 0 && this.swapTo !== key;
    b.gun = damp(b.gun, out && !leaving && !busyHands && !player.sliding && !player.rolling ? 1 : 0, 9, dt);
    this.fireCooldown = Math.max(0, this.fireCooldown - dt);
    this.gunPoint = Math.max(0, this.gunPoint - dt);
    this.gunKick = damp(this.gunKick, 0, 11, dt);
    const reloading = this.reloadT >= 0;
    b.aim = damp(b.aim, out && this.aiming && !busyHands && !reloading && sprint < 0.5 ? 1 : 0, 13, dt);
    b.point = damp(b.point, this.gunPoint > 0 ? 1 : 0, 14, dt);

    // ----- recarga -----
    // revólver: abre o tambor, ejeta as cápsulas, põe as balas (speedloader), fecha
    // espingarda: abre a báscula, os cartuchos vazios saltam, põe dois novos, fecha com tranco
    // besta: aponta para baixo, puxa a corda até o trinco, põe o virote no trilho
    let rk = 0, rPitch = 0, rRoll = 0, open = 0, leftMode = 'support', rDrop = 0, rFwd = 0;
    if (reloading) {
      const t = (this.reloadT += dt);
      const done = this._reloadDone;
      const mark = (at, type) => { if (t >= at && !done.has(type)) { done.add(type); this.events.push({ type, count: this._spent, weapon: key }); return true; } return false; };
      if (!long) {
        rk = smoothstep(0, 0.3, t) * (1 - smoothstep(2.15, 2.55, t));
        open = smoothstep(0.28, 0.42, t) * (1 - smoothstep(1.82, 1.95, t));
        rPitch = 0.95 * smoothstep(0.4, 0.55, t) * (1 - smoothstep(0.78, 0.95, t)) - 0.55 * smoothstep(0.85, 1.05, t) * (1 - smoothstep(1.8, 2.05, t));
        rRoll = 0.55 * smoothstep(0.3, 0.5, t) * (1 - smoothstep(1.85, 2.1, t));
        mark(0.3, 'cylOpen');
        if (mark(0.58, 'eject')) G.ejectShells(this._spent);
        mark(1.5, 'loadRounds');
        mark(1.86, 'cylClose');
        if (t >= 2.55) this.reloadT = -1;
      } else {
        const A = G.reloadAnim(t);
        rk = A.k; open = A.open; rPitch = A.pitch; rRoll = A.roll; leftMode = A.left; rDrop = A.drop ?? 0; rFwd = A.fwd ?? 0;
        if (A.cock !== undefined) G.cocked = Math.max(G.cocked, A.cock);
        for (const [at, type] of A.marks) {
          if (mark(at, type) && type === 'eject') { G.ejectShells(this._spent); G.setLoaded(G.loaded); }
        }
        if (t >= G.reloadTime) this.reloadT = -1;
      }
    }
    G.open = open;
    if (b.gun < 0.001 && !out) return;

    // ----- pose da arma no espaço do olhar: [direita, cima, frente, inclinação, giro, guinada] -----
    const GP = long ? LONG_POSES : GUN_POSES;
    // (em 1ª pessoa algumas armas ficam mais altas e de lado para aparecerem na tela)
    const P = (this.firstPerson && G.readyFP ? G.readyFP : GP.ready).slice();
    const mix = (Q, w) => { if (w > 0.001) for (let i = 0; i < 6; i++) P[i] = lerp(P[i], Q[i], w); };
    mix(GP.point, b.point);
    mix(GP.sprint, sprint * (1 - b.aim));
    const ads = this._ads ?? (this._ads = GP.ads.slice());
    for (let i = 0; i < 6; i++) ads[i] = GP.ads[i];
    ads[1] = -G.sightY;
    mix(ads, b.aim);
    mix([GP.reload[0], GP.reload[1] - rDrop, GP.reload[2] + rFwd, rPitch, rRoll, GP.reload[5]], rk);
    // perto de parede: recolhe
    P[2] -= 0.16 * b.obstruct * (1 - b.aim * 0.5);
    P[3] -= 0.7 * b.obstruct;
    // balanço: respiração, passos, atraso ao girar e recuo
    // com a lanterna na outra mão a arma fica bem menos firme; arma longa no ombro é mais firme
    const oneHanded = this._heldFlash && !long ? 1 : 0;
    const steady = (1 - b.aim * 0.65) * (1 + oneHanded * 1.2) * (long ? 0.75 : 1);
    const kickK = 1 + oneHanded * 0.6;
    const t = this.t;
    let yawOff = Math.sin(t * 0.9) * 0.006 * steady - Math.max(-0.08, Math.min(0.08, yawRate * 0.012 * (long ? 1.3 : 1)));
    P[3] += Math.sin(t * 1.3) * 0.007 * steady + Math.sin(t * 3.1) * 0.003 * oneHanded + this.gunKick * 0.32 * kickK;
    P[1] += Math.sin(ph * 2) * 0.011 * b.move * steady + this.gunKick * 0.012;
    P[0] += Math.sin(ph) * 0.009 * b.move * steady;
    P[2] -= this.gunKick * 0.04;
    yawOff += (this.gunKick > 0.5 ? (this._kickSide ?? 0) : 0);

    // arma longa: postura de tiro de lado (ombro esquerdo à frente, coronha no ombro direito)
    if (long && out) {
      const tw = 0.4 * b.gun;
      this.torso.rotation.y -= tw;
      this.head.rotation.y += tw * 0.85;
      this.torso.updateMatrixWorld(true);
    }
    const pos = this._gunPos ?? (this._gunPos = new THREE.Vector3());
    const q = this._gunQ ?? (this._gunQ = new THREE.Quaternion());
    this._eyeSpace(P, yawOff, look, player, pos, q);
    const M = G.model;
    if (out) {
      // saindo do coldre/das costas: parte de lá e vai até a mão; guardar faz o caminho inverso
      if (b.gun < 0.999) this._fromMount(this.mounts[key], b.gun, pos, q, long ? [0.22, 0.14] : [0.1, 0]);
      M.position.copy(pos);
      M.quaternion.copy(q);
      M.updateMatrixWorld(true);
    }
    // ----- mãos: direita na empunhadura; esquerda apoiando, na lanterna ou na recarga -----
    // a mão direita fica na arma o tempo todo (também saindo/entrando no coldre)
    const wR = out ? Math.min(1, b.gun * 6) : 0;
    if (wR < 0.001) return;
    const join = smoothstep(0.65, 1, b.gun); // a esquerda só entra quando a arma já está na frente
    const qW = this._qW ?? (this._qW = new THREE.Quaternion());
    if (long) {
      const H = LONG_HANDS[key];
      solveArmIK(this.armR, M.localToWorld(this._t1.copy(H.wR)), this._v.set(0.7, -0.7, 0.25), wR, WRIST);
      setHandWorld(this.armR, qW.multiplyQuaternions(M.quaternion, H.qR), wR);
      // esquerda: embaixo do guarda-mão; na recarga vai à bolsa do cinto e às câmaras / à corda
      const sp = G.supportParent;
      sp.updateWorldMatrix(true, false);
      const qS = sp.getWorldQuaternion(this._qS ?? (this._qS = new THREE.Quaternion()));
      const t3 = this._t3 ?? (this._t3 = new THREE.Vector3());
      if (leftMode === 'pouch') {
        this.hips.updateWorldMatrix(true, false);
        this.hips.localToWorld(t3.set(-0.19, 0.0, -0.06));
      } else if (leftMode === 'reload') {
        G.reloadPoint.getWorldPosition(t3);
        t3.y -= 0.03;
      } else sp.localToWorld(t3.copy(G.support).add(WRIST_L_LONG_OFF));
      if (reloading) this._lh.lerp(t3, 1 - Math.exp(-18 * dt)); else this._lh.copy(t3);
      solveArmIK(this.armL, this._lh, this._v.set(-0.3, -1, 0.15), join, WRIST);
      const ori = leftMode === 'support' ? join : join * 0.4;
      setHandWorld(this.armL, qW.multiplyQuaternions(qS, HAND_L_LONG), ori);
      return;
    }
    solveArmIK(this.armR, M.localToWorld(this._t1.copy(WRIST_R_GUN)), this._v.set(0.55, -0.85, 0.35), wR, WRIST);
    setHandWorld(this.armR, qW.multiplyQuaternions(M.quaternion, HAND_R_GUN), wR);
    const oneHand = sprint * (1 - b.aim) * (1 - rk);
    if (reloading) {
      // esquerda: empurra a vareta (ejeta) → vai ao cinto pegar o speedloader → põe no tambor → fecha
      const tr = this.reloadT;
      const sup = M.localToWorld(new THREE.Vector3(-0.03, -0.014, 0.002));
      const cylP = G.cyl.getWorldPosition(new THREE.Vector3());
      const rodP = M.localToWorld(new THREE.Vector3(0, 0.03, -0.1));
      this.hips.updateWorldMatrix(true, false);
      const pouch = this.hips.localToWorld(new THREE.Vector3(-0.17, 0.02, -0.08));
      let tgt;
      if (tr < 0.35) tgt = sup.lerp(cylP, smoothstep(0.1, 0.35, tr));
      else if (tr < 0.72) tgt = cylP.lerp(rodP, smoothstep(0.42, 0.58, tr) * (1 - smoothstep(0.6, 0.72, tr)));
      else if (tr < 1.15) tgt = cylP.lerp(pouch, smoothstep(0.72, 0.95, tr));
      else if (tr < 1.55) tgt = pouch.lerp(cylP, smoothstep(1.15, 1.45, tr));
      else if (tr < 2.0) tgt = cylP;
      else tgt = cylP.lerp(sup, smoothstep(2.0, 2.35, tr));
      solveArmIK(this.armL, tgt, this._v.set(-0.6, -0.8, 0.3), wR);
    } else if (this._heldFlash) {
      // a esquerda segura a lanterna ao lado da arma (_flashPose)
    } else {
      const wL = join * (1 - oneHand);
      solveArmIK(this.armL, M.localToWorld(this._t1.copy(WRIST_L_GUN)), this._v.set(-0.6, -0.8, 0.3), wL, WRIST);
      setHandWorld(this.armL, qW.multiplyQuaternions(M.quaternion, HAND_L_GUN), wL);
    }
  }

  /**
   * Lanterna na mão esquerda: posicionada no espaço do olhar (ou ao lado do revólver) e a mão
   * vai até ela com IK, envolvendo o corpo da lanterna — sem atravessar a mão. Ao ligar, a mão
   * a tira da presilha do peito.
   */
  _flashPose(player, look, ph) {
    if (!this._heldFlash) return;
    const b = this.b, F = this.flash;
    const pos = this._flPos ?? (this._flPos = new THREE.Vector3());
    const q = this._flQ ?? (this._flQ = new THREE.Quaternion());
    const P = FLASH_POSE.slice();
    P[1] += Math.sin(ph * 2) * 0.01 * b.move;
    P[0] += Math.sin(ph + 1) * 0.008 * b.move;
    P[3] += Math.sin(this.t * 1.1) * 0.01;
    P[2] -= 0.12 * b.obstruct;
    this._eyeSpace(P, 0, look, player, pos, q);
    const gk = this.equip === 'gun' ? smoothstep(0.65, 1, b.gun) : 0;
    if (gk > 0.001) {
      const M = this.revolver.model;
      pos.lerp(M.localToWorld(this._t1.copy(FLASH_ON_GUN)), gk);
      q.slerp(M.quaternion, gk);
    }
    const kd = smoothstep(0.5, 0.95, b.flash);
    if (kd < 0.999) {
      this.chestClip.updateWorldMatrix(true, false);
      const cp = this.chestClip.getWorldPosition(this._t1);
      const cq = this.chestClip.getWorldQuaternion(this._cq ?? (this._cq = new THREE.Quaternion()));
      pos.lerpVectors(cp, pos, kd);
      q.slerpQuaternions(cq, q, kd);
    }
    F.position.copy(pos);
    F.quaternion.copy(q);
    F.updateMatrixWorld(true);
    const w = smoothstep(0.5, 0.75, b.flash);
    const wrist = (this._t3 ?? (this._t3 = new THREE.Vector3())).copy(WRIST_FLASH).applyQuaternion(q).add(pos);
    solveArmIK(this.armL, wrist, this._v.set(-0.6, -0.9, 0.2), w, WRIST);
    const qW = this._qW ?? (this._qW = new THREE.Quaternion());
    setHandWorld(this.armL, qW.multiplyQuaternions(q, HAND_FLASH), w);
  }

  /**
   * Interação com o cenário: a mão vai até um ponto (maçaneta, objeto) — encosta no instante
   * `contact` (aí a ação acontece: a porta começa a abrir, o objeto vai para a mão), segura um
   * pouco acompanhando o ponto (empurra a porta) e volta. Se o ponto é baixo, ele se abaixa.
   * Usa a mão livre: a direita com as mãos vazias, senão a esquerda.
   */
  reachTo(getPoint, { contact = 0.3, hold = 0.3, onContact = null, palm = null } = {}) {
    if (this.reach) return false;
    const arm = this.equip === 'hands' && !this.move ? this.armR : this.armL;
    this.reach = { get: getPoint, t: 0, contact, end: contact + hold + 0.32, onContact, fired: false, arm, palm };
    return true;
  }

  _reachPose(dt, player) {
    const r = this.reach;
    if (!r) { this._reachLow = damp(this._reachLow ?? 0, 0, 8, dt); return; }
    r.t += dt;
    if (!r.fired && r.t >= r.contact) { r.fired = true; r.onContact?.(); }
    const w = smoothstep(0, r.contact * 0.9, r.t) * (1 - smoothstep(r.end - 0.3, r.end, r.t));
    const p = r.get(this._t3 ?? (this._t3 = new THREE.Vector3()));
    const arm = r.arm, s = arm.side;
    arm.shoulder.updateWorldMatrix(true, false);
    const sh = arm.shoulder.getWorldPosition(this._t1);
    const lowT = Math.max(0, Math.min(1, (sh.y - p.y - 0.42) / 0.75)) * (r.t < r.end - 0.15 ? 1 : 0);
    this._reachLow = damp(this._reachLow ?? 0, lowT, 7, dt);
    // palma virada para o ponto (porta) ou para baixo (pegar), dedos para frente
    const fx = -Math.sin(this.yaw), fz = -Math.cos(this.yaw);
    const palm = r.palm ?? (lowT > 0.2 ? [0, -1, 0] : [fx, -0.2, fz]);
    const fing = lowT > 0.2 ? [fx, -0.3, fz] : [0, 1, 0];
    solveArmIK(arm, p, this._v.set(s * 0.6, -0.8, 0.25), w, FOREARM_PALM);
    setHandWorld(arm, handBasis(s, palm, fing), w * 0.8);
    arm.fist = lerp(arm.fist, r.fired ? 1.1 : 0.15, w);
    if (r.t >= r.end) this.reach = null;
  }

  /** Pose [direita, cima, frente, inclinação, giro, guinada] no espaço do olhar → posição/rotação no mundo. */
  _eyeSpace(P, yawOff, look, player, pos, q) {
    const eye = this._viewEye(player, this._t2);
    const yaw = player.yaw, cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(look), sp = Math.sin(look);
    const fx = -sy * cp, fy = sp, fz = -cy * cp;      // frente
    const ux = sy * sp, uy = cp, uz = cy * sp;        // cima
    const rx = cy, rz = -sy;                          // direita
    pos.set(
      eye.x + rx * P[0] + ux * P[1] + fx * P[2],
      eye.y + uy * P[1] + fy * P[2],
      eye.z + rz * P[0] + uz * P[1] + fz * P[2],
    );
    const e = this._gunEuler ?? (this._gunEuler = new THREE.Euler(0, 0, 0, 'YXZ'));
    e.set(look + P[3], yaw + yawOff + P[5], -P[4]);
    q.setFromEuler(e);
  }

  /**
   * Sacando/guardando: o item parte do coldre (costas, cinto) e vai até a pose, primeiro
   * puxando (arco para cima/para o lado) e depois girando para frente; guardar faz o inverso.
   */
  _fromMount(mount, k, pos, q, arc) {
    mount.updateWorldMatrix(true, false);
    const hp = mount.getWorldPosition(this._t1);
    const hq = mount.getWorldQuaternion(this._hq ?? (this._hq = new THREE.Quaternion()));
    const kk = smoothstep(0, 1, k);
    pos.lerpVectors(hp, pos, kk);
    const a = Math.sin(kk * Math.PI);
    pos.y += a * arc[0];
    if (arc[1]) { pos.x += Math.cos(this.yaw) * a * arc[1]; pos.z -= Math.sin(this.yaw) * a * arc[1]; }
    q.slerpQuaternions(hq, q, smoothstep(0.25, 0.9, kk));
  }

  /**
   * Taco com arame farpado: como as armas, posicionado no espaço do olhar (pronto, correndo e os
   * golpes — arco horizontal, de volta, estocada com a ponta e o golpe forte de cima) e as duas
   * mãos vão até o cabo com IK. Com a lanterna ligada, golpeia com uma mão só.
   */
  _batPose(dt, player, look, ph, sprint, yawRate, busyHands) {
    const b = this.b;
    const out = this.equip === 'bat';
    const leaving = this.swap >= 0 && this.swapTo !== 'bat';
    b.bat = damp(b.bat, out && !leaving && !busyHands && !player.sliding && !player.rolling ? 1 : 0, 9, dt);
    if (!out) return;
    const P = BAT_POSES.ready.slice();
    const mix = (Q, w) => { if (w > 0.001) for (let i = 0; i < 6; i++) P[i] = lerp(P[i], Q[i], w); };
    mix(BAT_POSES.sprint, sprint * (1 - this._batK));
    mix(this._batP, this._batK);
    // perto de parede: recolhe e levanta
    P[2] -= 0.14 * b.obstruct;
    P[3] += 0.4 * b.obstruct;
    // balanço do passo, respiração e atraso ao girar
    P[1] += Math.sin(ph * 2) * 0.012 * b.move + Math.sin(this.t * 1.4) * 0.004;
    P[0] += Math.sin(ph) * 0.01 * b.move;
    const yawOff = -Math.max(-0.1, Math.min(0.1, yawRate * 0.015)) * (1 - this._batK);
    const pos = this._batPos ?? (this._batPos = new THREE.Vector3());
    const q = this._batQ ?? (this._batQ = new THREE.Quaternion());
    this._eyeSpace(P, yawOff, look, player, pos, q);
    if (b.bat < 0.999) this._fromMount(this.batMount, b.bat, pos, q, [0.12, -0.05]);
    const B = this.bat;
    B.position.copy(pos);
    B.quaternion.copy(q);
    B.updateMatrixWorld(true);
    const wR = Math.min(1, b.bat * 6);
    const qW = this._qW ?? (this._qW = new THREE.Quaternion());
    solveArmIK(this.armR, B.localToWorld(this._t1.copy(WRIST_R_BAT)), this._v.set(0.6, -0.6, 0.3), wR, WRIST);
    setHandWorld(this.armR, qW.multiplyQuaternions(B.quaternion, HAND_R_BAT), wR);
    if (!this._heldFlash) {
      const wL = smoothstep(0.6, 1, b.bat);
      solveArmIK(this.armL, B.localToWorld(this._t1.copy(WRIST_L_BAT)), this._v.set(-0.5, -0.8, 0.3), wL, WRIST);
      setHandWorld(this.armL, qW.multiplyQuaternions(B.quaternion, HAND_L_BAT), wL);
    }
  }

  /**
   * Sacar/guardar: a mão direita vai até o coldre (revólver), a bainha (faca), as costas
   * (espingarda e besta) ou o cinto (taco), pega/solta o item no meio da troca e volta.
   * Entre dois itens guardados, passa de um lugar ao outro.
   */
  _swapPose() {
    if (this.swap < 0) return;
    const from = this._swapFrom, to = this.swapTo, s = this.swap;
    const stored = (it) => it !== 'hands';
    const where = (it, v) => {
      if (it === 'knife') return this.sheath.localToWorld(v.set(0, 0.005, 0));
      return (it === 'bat' ? this.batMount : this.mounts[it]).getWorldPosition(v);
    };
    this.root.updateMatrixWorld(true);
    let tgt;
    if (stored(from) && stored(to)) {
      const a = where(from, this._t1), bp = where(to, new THREE.Vector3());
      tgt = a.lerp(bp, smoothstep(0.38, 0.62, s));
    } else if (stored(from) || stored(to)) {
      tgt = where(stored(from) ? from : to, this._t1);
    } else return;
    // 1ª metade: guardando, o item vai junto com a mão (pela própria pose) e a IK só fecha a
    // chegada; com a mão vazia, ela desce até o coldre/bainha. 2ª metade: sacando, a pose do item
    // assume logo (a mão leva o item); voltando vazia, a mão sobe devagar.
    let w;
    if (s < 0.5) w = stored(from) ? smoothstep(0.3, 0.5, s) : smoothstep(0, 0.42, s);
    else w = stored(to) ? 1 - smoothstep(0.5, 0.6, s) : 1 - smoothstep(0.55, 1, s);
    if (w < 0.001) return;
    const it = s < 0.5 ? from : to;
    // cotovelo: para cima (pegar nas costas por cima do ombro), para fora (cinto do outro lado)
    const pole = { shotgun: [0.45, 0.9, -0.15], crossbow: [0.7, -0.3, 0.7], bat: [0.6, -0.3, -0.7] }[it] ?? [0.55, -0.1, 1];
    solveArmIK(this.armR, tgt, this._v.set(pole[0], pole[1], pole[2]), w);
    // o corpo acompanha: ombro desce/gira para o lado do item
    if (it === 'bat') { this.torso.rotation.y += 0.2 * w; this.torso.rotation.x += 0.06 * w; }
    else if (it === 'shotgun') { this.torso.rotation.z += 0.05 * w; this.torso.rotation.y -= 0.18 * w; }
    else { this.torso.rotation.z -= 0.08 * w; this.torso.rotation.y -= 0.12 * w; }
  }

  /** Mãos apoiadas na borda (IK) durante as escaladas, pernas subindo. */
  _climbPose(dt, player) {
    const c = this.b.climb;
    if (c < 0.001 || !player.climb?.edge) return;
    const cl = player.climb;
    const pr = player.climbProgress;
    const n = cl.normal;
    const rx = -n.z, rz = n.x; // direita ao longo da borda
    const kind = cl.kind;
    const along = Math.sin(pr * Math.PI);
    // quanto as mãos ficam na borda (soltam no fim, quando o corpo já passou)
    const handsOn = c * (1 - smoothstep(0.78, 0.95, pr));
    for (const arm of [this.armL, this.armR]) {
      let w = handsOn;
      // salto rápido: só a mão esquerda apoia; passar por cima: a direita apoia primeiro
      if (kind === 'speedvault' && arm.side > 0) w = 0;
      if (kind === 'stepover' && arm.side < 0) w *= smoothstep(0.25, 0.45, pr);
      const tgt = this._t1.set(cl.edge.x + rx * arm.side * 0.22 + n.x * 0.06, cl.topY + 0.03, cl.edge.z + rz * arm.side * 0.22 + n.z * 0.06);
      solveArmIK(arm, tgt, this._v.set(arm.side * 0.8, -0.2, 0.6), w);
    }
    // pernas: um joelho sobe até a borda; nos saltos, as pernas passam encolhidas
    const L = this.legL, R = this.legR;
    if (kind === 'speedvault') {
      for (const leg of [L, R]) { leg.thigh.rotation.x = lerp(leg.thigh.rotation.x, 1.3, c * along); leg.knee.rotation.x = lerp(leg.knee.rotation.x, -1.5, c * along); }
      L.thigh.rotation.z = R.thigh.rotation.z = -0.5 * c * along; // pernas de lado
      this.hips.rotation.z += 0.35 * c * along;
    } else if (kind === 'stepover') {
      const first = Math.sin(Math.min(1, pr * 1.6) * Math.PI), second = Math.sin(Math.max(0, pr * 1.6 - 0.6) * Math.PI);
      R.thigh.rotation.x = lerp(R.thigh.rotation.x, 1.4, c * first); R.knee.rotation.x = lerp(R.knee.rotation.x, -1.2, c * first);
      L.thigh.rotation.x = lerp(L.thigh.rotation.x, 1.2, c * second); L.knee.rotation.x = lerp(L.knee.rotation.x, -1.4, c * second);
    } else {
      R.thigh.rotation.x = lerp(R.thigh.rotation.x, 1.5, c * along); R.knee.rotation.x = lerp(R.knee.rotation.x, -2.1, c * along);
      L.thigh.rotation.x = lerp(L.thigh.rotation.x, 0.4 * along, c); L.knee.rotation.x = lerp(L.knee.rotation.x, -0.5 * along, c);
    }
    this.torso.rotation.x = lerp(this.torso.rotation.x, -0.55 * along, c);
  }

  /** Pendurado: braços esticados segurando a borda, pernas soltas balançando. */
  _hangPose(player) {
    const h = this.b.hang;
    if (h < 0.001 || !player.hang) return;
    const g = player.hang;
    const rx = -g.normal.z, rz = g.normal.x;
    const shimmy = Math.sin((g.shimmy || 0) * 3) * 0.05;
    for (const arm of [this.armL, this.armR]) {
      const tgt = this._t1.set(g.edge.x + rx * (arm.side * 0.23 + shimmy * arm.side) + g.normal.x * 0.05, g.topY + 0.02, g.edge.z + rz * (arm.side * 0.23 + shimmy * arm.side) + g.normal.z * 0.05);
      solveArmIK(arm, tgt, this._v.set(arm.side * 0.9, 0, 0.4), h);
    }
    const swing = Math.sin(this.t * 1.8) * 0.12;
    for (const leg of [this.legL, this.legR]) {
      leg.thigh.rotation.x = lerp(leg.thigh.rotation.x, 0.15 + swing, h);
      leg.knee.rotation.x = lerp(leg.knee.rotation.x, -0.3, h);
      leg.ankle.rotation.x = lerp(leg.ankle.rotation.x, 0.3, h);
    }
    this.torso.rotation.x = lerp(this.torso.rotation.x, 0.08, h);
  }

  /** Escada de mão: mãos nos degraus (IK) e pés alternados. */
  _ladderPose(player) {
    const L = this.b.ladder;
    if (L < 0.001) return;
    const lad = player.ladder?.l;
    const lp = player.ladderPhase;
    if (lad) {
      // as mãos agarram o degrau na frente do corpo (o jogador pode estar fora do centro da
      // escada); em 1ª pessoa mais juntas, para as duas aparecerem na tela
      const fp = player.feetPosition, lim = (lad.width ?? 0.6) / 2 - 0.05;
      const off = (fp.x - lad.x) * lad.tx + (fp.z - lad.z) * lad.tz;
      const spread = this.firstPerson ? 0.17 : 0.21;
      for (const arm of [this.armL, this.armR]) {
        arm.shoulder.updateWorldMatrix(true, false);
        const sy = arm.shoulder.getWorldPosition(this._t2).y;
        // degrau acima do ombro, alternando entre as mãos
        // (em 1ª pessoa as mãos pegam degraus mais baixos: o braço não passa na frente do rosto)
        const want = sy + (this.firstPerson ? 0.17 : 0.28) + Math.sin(lp + (arm.side > 0 ? 0 : Math.PI)) * (this.firstPerson ? 0.12 : 0.15);
        const rung = lad.bottom + 0.3 + Math.round((want - lad.bottom - 0.3) / 0.3) * 0.3;
        // (só degraus que existem: perto do topo a mão não fica agarrando o ar acima da escada)
        const lastRung = lad.bottom + 0.3 + Math.floor((lad.top + 0.2 - lad.bottom - 0.3) / 0.3) * 0.3;
        // a direita de quem sobe é -tangente (quem sobe olha para -normal); antes as mãos
        // trocavam de lado e os braços se cruzavam na frente do rosto. As mãos ficam perto dos
        // montantes, com a palma virada para a escada e os dedos fechando por cima do degrau.
        const lat = Math.max(-lim, Math.min(lim, off - arm.side * spread));
        const raw = this._t1.set(lad.x + lad.tx * lat + lad.nx * 0.05, Math.min(rung, lastRung, sy + 0.45) - 0.02, lad.z + lad.tz * lat + lad.nz * 0.05);
        // a mão passa de um degrau ao outro (sem teletransportar)
        const k = arm.side > 0 ? '_ladHR' : '_ladHL';
        const tgt = this[k] && this[k].distanceTo(raw) < 0.8 ? this[k].lerp(raw, 1 - Math.exp(-14 * this._dt)) : (this[k] = raw.clone());
        solveArmIK(arm, tgt, this._v.set(arm.side * 0.9, -0.6, 0.1), L, FOREARM_PALM);
        const hq = lad._hq ?? (lad._hq = [handBasis(-1, [-lad.nx, 0.35, -lad.nz], [0, 1, 0]), handBasis(1, [-lad.nx, 0.35, -lad.nz], [0, 1, 0])]);
        setHandWorld(arm, hq[arm.side > 0 ? 1 : 0], L);
      }
    }
    const altL = Math.sin(lp), altR = Math.sin(lp + Math.PI);
    for (const [leg, alt] of [[this.legL, altR], [this.legR, altL]]) {
      leg.thigh.rotation.x = lerp(leg.thigh.rotation.x, 0.55 + alt * 0.4, L);
      leg.knee.rotation.x = lerp(leg.knee.rotation.x, -0.95 - alt * 0.45, L);
      leg.ankle.rotation.x = lerp(leg.ankle.rotation.x, 0.3, L);
    }
    this.torso.rotation.x = lerp(this.torso.rotation.x, 0.05, L);
    // pés nos degraus: cada pé apoia a ponta num degrau de verdade (IK de perna, joelho
    // apontando para a escada, sola nivelada) e sobe de degrau em degrau alternando com o outro
    if (lad) {
      const fp = player.feetPosition, feet = fp.y, lim = (lad.width ?? 0.6) / 2 - 0.05;
      const off = (fp.x - lad.x) * lad.tx + (fp.z - lad.z) * lad.tz;
      const yawQ = _mq1.setFromAxisAngle(_UP, this.yaw);
      for (const leg of [this.legL, this.legR]) {
        const side = leg === this.legR ? 1 : -1;
        const want = feet + 0.12 + Math.sin(lp + (side > 0 ? Math.PI : 0)) * 0.13;
        let rung = lad.bottom + 0.3 + Math.round((want - lad.bottom - 0.3) / 0.3) * 0.3;
        rung = Math.max(rung, lad.bottom + 0.3);
        const ground = rung > feet + 0.45 || want < lad.bottom + 0.15;
        const y = ground ? Math.max(feet, lad.bottom) + 0.09 : rung + 0.075;
        // tornozelo um pouco atrás do degrau: a ponta do pé fica em cima dele
        const lat = Math.max(-lim, Math.min(lim, off - side * 0.12));
        const raw = this._t1.set(lad.x + lad.tx * lat + lad.nx * 0.17, y, lad.z + lad.tz * lat + lad.nz * 0.17);
        const k = side > 0 ? '_ladFR' : '_ladFL';
        const tgt = this[k] && this[k].distanceTo(raw) < 0.8 ? this[k].lerp(raw, 1 - Math.exp(-12 * this._dt)) : (this[k] = raw.clone());
        solveLegIK(leg, tgt, this._v.set(0, 0.2, -1), L);
        // sola nivelada, ponta para a escada
        leg.knee.updateWorldMatrix(true, false);
        leg.ankle.quaternion.slerp(leg.knee.getWorldQuaternion(_mq2).invert().multiply(yawQ), L);
      }
    }
  }

  _swimPose(player) {
    const W = this.b.swim;
    if (W < 0.001) return;
    const sp = player.swimPhase;
    const reach = Math.max(0, Math.sin(sp)), sweep = Math.max(0, -Math.sin(sp));
    this.hips.rotation.x = lerp(this.hips.rotation.x, -1.1 - (player.underwater ? 0.2 : 0), W);
    this.hips.position.y = lerp(this.hips.position.y, 1.25 * HS, W);
    this.torso.rotation.x = lerp(this.torso.rotation.x, 0.3, W);
    for (const arm of [this.armL, this.armR]) {
      arm.upper.rotation.x = lerp(arm.upper.rotation.x, 2.4 + reach * 0.6, W);
      arm.upper.rotation.y = lerp(arm.upper.rotation.y, 0, W);
      arm.upper.rotation.z = lerp(arm.upper.rotation.z, arm.side * (0.2 + sweep * 1.0), W);
      arm.elbow.rotation.x = lerp(arm.elbow.rotation.x, 0.3 + sweep * 0.9, W);
    }
    const kick = Math.sin(sp * 2.5) * 0.4;
    this.legL.thigh.rotation.x = lerp(this.legL.thigh.rotation.x, kick, W);
    this.legR.thigh.rotation.x = lerp(this.legR.thigh.rotation.x, -kick, W);
    this.legL.knee.rotation.x = lerp(this.legL.knee.rotation.x, -0.3 - Math.max(0, kick), W);
    this.legR.knee.rotation.x = lerp(this.legR.knee.rotation.x, -0.3 - Math.max(0, -kick), W);
  }

  _slidePose() {
    const S = this.b.slide;
    if (S < 0.001) return;
    this.legL.thigh.rotation.x = lerp(this.legL.thigh.rotation.x, 1.45, S);
    this.legL.knee.rotation.x = lerp(this.legL.knee.rotation.x, -0.15, S);
    this.legR.thigh.rotation.x = lerp(this.legR.thigh.rotation.x, 0.9, S);
    this.legR.knee.rotation.x = lerp(this.legR.knee.rotation.x, -1.6, S);
    this.hips.position.y = lerp(this.hips.position.y, 0.32 * HS, S);
    this.torso.rotation.x = lerp(this.torso.rotation.x, 0.45, S);
    this.armL.upper.rotation.z = lerp(this.armL.upper.rotation.z, -1.0, S);
    this.armR.upper.rotation.z = lerp(this.armR.upper.rotation.z, 0.6, S);
  }

  _rollPose(player) {
    if (!player.rolling) return;
    const k = Math.min(1, player.rollTime / 0.65);
    const tuck = Math.sin(k * Math.PI);
    this.hips.rotation.x = -k * Math.PI * 2;
    this.hips.position.y = lerp(this.hips.position.y, 0.45 * HS, tuck);
    for (const leg of [this.legL, this.legR]) {
      leg.thigh.rotation.x = lerp(leg.thigh.rotation.x, 1.6, tuck);
      leg.knee.rotation.x = lerp(leg.knee.rotation.x, -2.2, tuck);
    }
    this.torso.rotation.x = lerp(this.torso.rotation.x, -0.9, tuck);
  }
}

/** Para ajustes finos (console/testes): pontos das mãos na arma. */
export const GUN_HANDS = { WRIST_R_GUN, WRIST_L_GUN, WRIST_FLASH };
