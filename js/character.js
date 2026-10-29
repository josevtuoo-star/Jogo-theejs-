import * as THREE from 'three';
import { makeFlashlightModel } from './flashlight.js';

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

const HIP_Y = 0.9;
// medidas iguais às do modelo 3D do personagem (ver playerModel.js)
const UPPER_ARM = 0.286;
const FOREARM = 0.32; // até o centro da mão
const WRIST = 0.244;  // cotovelo → punho

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
function solveArmIK(arm, target, pole, weight) {
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
};
const COMBOS = { punch: ['jab', 'cross', 'hook'], knife: ['slash', 'backslash', 'stab'] };
const HEAVY = { punch: 'haymaker', knife: 'overhead' };
const HAND_TWIST = Math.PI / 2;
const KNIFE_REST = -Math.PI / 2 - 0.5; // faca na mão, lâmina para frente
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

    this.root.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    scene.add(this.root);
    this.scene = scene;
    this.skinned = null;

    this.b = { run: 0, move: 0, crouch: 0, air: 0, climb: 0, death: 0, ladder: 0, slide: 0, swim: 0, flash: 0, land: 0, hang: 0, knife: 0, obstruct: 0, guard: 0 };
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
    this.obstructTarget = 0;
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
    // lanterna: na mão esquerda (lente ao longo do antebraço) ou presa no peito, apontando para frente
    if (flashOn) {
      this.armL.hand.add(this.flash);
      this.flash.position.set(0, -0.06, -0.015);
      this.flash.rotation.set(-Math.PI / 2, 0, 0);
    } else {
      this.chestClip.add(this.flash);
      this.flash.position.set(0, 0, 0);
      this.flash.rotation.set(0.15, 0, 0);
    }
    this._heldFlash = flashOn;
    if (this.fpHidden) this._flashLayer();
  }

  /**
   * Troca o corpo procedural pelo modelo 3D (SkinnedMeshes presos nos mesmos ossos).
   * Faca, lanterna e bainha continuam.
   */
  useModel(meshes) {
    const keep = new Set();
    for (const g of [this.knife, this.flash, this.sheath]) g.traverse((o) => keep.add(o));
    this.root.traverse((o) => { if (o.isMesh && !keep.has(o)) o.visible = false; });
    this.skinned = meshes;
    for (const m of meshes) this.scene.add(m);
    this.fpHidden = meshes.filter((m) => m.userData.fpHide);
    this.setFirstPerson(this.firstPerson);
  }

  /** Troca o modelo da faca (mesma convenção: cabo na origem, lâmina em +Y). */
  setKnifeModel(model) {
    this.knife.clear();
    this.knife.add(model);
    this._flashLayer();
  }

  /** Troca para 'hands' (mãos livres) ou 'knife'. Retorna true se começou a trocar. */
  setEquip(equip) {
    if (equip === this.equip || this.swap >= 0) return false;
    this.swap = 0;
    this.swapTo = equip;
    return true;
  }

  setFlashlight(on, intensity = 1) {
    this.flashOn = on;
    this.flash.userData.lensMat.color.setHex(on && intensity > 0.5 ? 0xfff6dc : 0x3a3a34);
  }

  get attackKind() { return this.equip === 'knife' ? 'knife' : 'punch'; }

  /**
   * Golpe leve (emenda combo: jab → direto → gancho; corte → corte de volta → estocada)
   * ou forte (heavy: depois de carregar). Se outro golpe ainda está no meio, fica na fila.
   */
  attack(heavy = false) {
    if (this.swap >= 0) return false;
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
    for (const m of this.fpHidden) m.layers.set(fp ? FP_HIDDEN_LAYER : 0);
    this._flashLayer();
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

  /** Posição dos olhos do corpo no mundo (câmera em 1ª pessoa). */
  getEyeWorldPosition(target) {
    this.root.updateMatrixWorld(true);
    return this.head.localToWorld(target.copy(this.eyeLocal));
  }

  // ---------- animação ----------
  update(dt, player) {
    this.t += dt;
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
    b.knife = damp(b.knife, this.equip === 'knife' && !busyHands && !player.sliding ? 1 : 0, 8, dt);
    b.obstruct = damp(b.obstruct, busyHands ? 0 : this.obstructTarget, 8, dt);
    this.accelLean = damp(this.accelLean, Math.max(-1, Math.min(1, accel / 8)), 5, dt);
    this.runLean = damp(this.runLean, player.onFloor ? yawRate * 0.035 * smoothstep(1, 6, speed) : 0, 6, dt);

    // a lanterna vai para a mão quando liga e volta para o peito quando desliga
    const wantHeld = this.flashOn && b.flash > 0.5;
    if (wantHeld !== this._heldFlash) this._placeItems(this.equip, wantHeld);

    // troca de item: a mão desce até o quadril, troca, e volta
    let swapDip = 0;
    if (this.swap >= 0) {
      this.swap += dt / 0.55;
      swapDip = Math.sin(Math.min(1, this.swap) * Math.PI);
      if (this.swap >= 0.5 && this.equip !== this.swapTo) {
        this.equip = this.swapTo;
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
      HIP_Y - crouchK * 0.4 + bob - b.air * 0.04 - b.land * 0.22 - Math.abs(shift) * 0.012,
      0
    );
    this.hips.rotation.set(0, Math.sin(ph) * 0.1 * thighAmp, Math.sin(ph) * 0.05 * ww * b.move + shift * 0.04 - this.runLean);
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
      -this.hips.rotation.y * 1.4,
      -player.lean * 0.35
    );
    const breath = Math.sin(this.t * (1.6 + player.exertion * 2.2)) * (0.008 + player.exertion * 0.012);
    this.torso.scale.set(1, 1 + breath * (1 - b.move * 0.7), 1);
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
    if (swapDip > 0.001) {
      Bm.upper.rotation.x = lerp(Bm.upper.rotation.x, -0.15, swapDip);
      Bm.upper.rotation.z = lerp(Bm.upper.rotation.z, 0.32, swapDip);
      Bm.elbow.rotation.x = lerp(Bm.elbow.rotation.x, 0.5, swapDip);
    }

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
      this.getEyeWorldPosition(this._t2);
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
      if (arm === Bm && (this.equip === 'knife' || this.swap >= 0.45)) want = 1.45;
      if (arm === A && this._heldFlash) want = 1.35;
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
    if (ch > 0.001 && !this.move) {
      const tremble = Math.sin(this.t * 40) * 0.015 * ch;
      poseArm(armOf(heavyMove), heavyMove.wind.map((v, i) => v + (i === 0 ? tremble : 0)), ch);
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
      poseArm(arm, P, k);
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
      arm.upper.rotation.x -= this.recoil * 0.3;
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
      for (const arm of [this.armL, this.armR]) {
        arm.shoulder.updateWorldMatrix(true, false);
        const sy = arm.shoulder.getWorldPosition(this._t2).y;
        // degrau acima do ombro, alternando entre as mãos
        const want = sy + 0.28 + Math.sin(lp + (arm.side > 0 ? 0 : Math.PI)) * 0.15;
        const rung = lad.bottom + 0.3 + Math.round((want - lad.bottom - 0.3) / 0.3) * 0.3;
        const tgt = this._t1.set(lad.x + lad.tx * arm.side * 0.2 + lad.nx * 0.04, Math.min(rung, lad.top + 0.6), lad.z + lad.tz * arm.side * 0.2 + lad.nz * 0.04);
        solveArmIK(arm, tgt, this._v.set(arm.side * 0.9, -0.3, 0.3), L);
      }
    }
    const altL = Math.sin(lp), altR = Math.sin(lp + Math.PI);
    for (const [leg, alt] of [[this.legL, altR], [this.legR, altL]]) {
      leg.thigh.rotation.x = lerp(leg.thigh.rotation.x, 0.55 + alt * 0.4, L);
      leg.knee.rotation.x = lerp(leg.knee.rotation.x, -0.95 - alt * 0.45, L);
      leg.ankle.rotation.x = lerp(leg.ankle.rotation.x, 0.3, L);
    }
    this.torso.rotation.x = lerp(this.torso.rotation.x, 0.05, L);
  }

  _swimPose(player) {
    const W = this.b.swim;
    if (W < 0.001) return;
    const sp = player.swimPhase;
    const reach = Math.max(0, Math.sin(sp)), sweep = Math.max(0, -Math.sin(sp));
    this.hips.rotation.x = lerp(this.hips.rotation.x, -1.1 - (player.underwater ? 0.2 : 0), W);
    this.hips.position.y = lerp(this.hips.position.y, 1.25, W);
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
    this.hips.position.y = lerp(this.hips.position.y, 0.32, S);
    this.torso.rotation.x = lerp(this.torso.rotation.x, 0.45, S);
    this.armL.upper.rotation.z = lerp(this.armL.upper.rotation.z, -1.0, S);
    this.armR.upper.rotation.z = lerp(this.armR.upper.rotation.z, 0.6, S);
  }

  _rollPose(player) {
    if (!player.rolling) return;
    const k = Math.min(1, player.rollTime / 0.65);
    const tuck = Math.sin(k * Math.PI);
    this.hips.rotation.x = -k * Math.PI * 2;
    this.hips.position.y = lerp(this.hips.position.y, 0.45, tuck);
    for (const leg of [this.legL, this.legR]) {
      leg.thigh.rotation.x = lerp(leg.thigh.rotation.x, 1.6, tuck);
      leg.knee.rotation.x = lerp(leg.knee.rotation.x, -2.2, tuck);
    }
    this.torso.rotation.x = lerp(this.torso.rotation.x, -0.9, tuck);
  }
}
