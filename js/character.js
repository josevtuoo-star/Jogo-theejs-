import * as THREE from 'three';
import { loadModelFile, boneName, bonesByName } from './modelLoader.js';
import { PistolRig, RIG_SCALE } from './pistol.js';

// Personagem: robô policial (modelo com esqueleto Mixamo) animado por clipes prontos — andar,
// trotar, correr, agachar, pular, rolar, deslizar, nadar, escada, escalar, socos, morte... (da
// biblioteca de animações do Mesh2Motion, convertidas para este esqueleto). Cada clipe é dividido
// em parte de baixo (quadril e pernas) e de cima (tronco, braços, cabeça): o corpo todo segue a
// locomoção e, por cima, os golpes trocam só a parte de cima. Com a pistola na mão os braços
// seguem as animações de FPS da arma (IK, ver pistol.js). Em 1ª pessoa a câmera fica presa na
// cabeça (estilo GoPro) e só a cabeça some; o resto do corpo aparece.

export const FP_HIDDEN_LAYER = 1;
export const ITEMS = ['hands', 'pistol'];
export const isFirearm = (it) => it === 'pistol';

const LOWER = new Set(['Hips', 'LeftUpLeg', 'LeftLeg', 'LeftFoot', 'LeftToeBase', 'LeftToe_End', 'RightUpLeg', 'RightLeg', 'RightFoot', 'RightToeBase', 'RightToe_End']);
// velocidade (m/s) de cada clipe de locomoção na velocidade normal
const SPEED = { walk: 0.75, jog: 2.8, sprint: 4.4, walk_back: 0.7, strafe_left: 0.6, strafe_right: 0.6, crouch_walk: 0.45, sneak: 0.7 };
// golpes de mãos livres: [clipe, velocidade de reprodução, alcance, força, impulso]
const MOVES = {
  jab: { clip: 'punch_jab', rate: 1.55, reach: 1.25, power: 3, lunge: 0.6, kind: 'hands' },
  cross: { clip: 'punch_cross', rate: 1.45, reach: 1.3, power: 4.5, lunge: 0.9, kind: 'hands' },
  hook: { clip: 'punch_hook', rate: 0.95, reach: 1.3, power: 7.5, lunge: 1.4, heavy: true, kind: 'hands' },
};

const damp = (a, b, l, dt) => a + (b - a) * (1 - Math.exp(-l * dt));
const smooth = (t) => { t = Math.min(1, Math.max(0, t)); return t * t * (3 - 2 * t); };
const smoothstep = (a, b, x) => smooth((x - a) / (b - a));
const _v1 = new THREE.Vector3(), _v2 = new THREE.Vector3(), _v3 = new THREE.Vector3(), _v4 = new THREE.Vector3(), _v5 = new THREE.Vector3();
const _q1 = new THREE.Quaternion(), _q2 = new THREE.Quaternion(), _q3 = new THREE.Quaternion();
const _m1 = new THREE.Matrix4(), _m2 = new THREE.Matrix4();
const _s = new THREE.Vector3(), _one = new THREE.Vector3(1, 1, 1);
const _e = new THREE.Euler(0, 0, 0, 'YXZ');

/** Matriz posição+rotação (sem escala) de um objeto. */
function rigid(o, out) {
  o.matrixWorld.decompose(_v5, _q3, _s);
  return out.compose(_v5, _q3, _one);
}
/** Gira o osso (no mundo) pela rotação q, mantendo o resto. */
function setWorldQuat(bone, q) {
  bone.parent.getWorldQuaternion(_q1);
  bone.quaternion.copy(_q1.invert().multiply(q));
}
/** Gira o osso para que o filho (em childPos) vá para targetPos. */
function aimBone(bone, childPos, targetPos) {
  const p = bone.getWorldPosition(_v4);
  const from = _v1.copy(childPos).sub(p).normalize(), to = _v2.copy(targetPos).sub(p).normalize();
  _q2.setFromUnitVectors(from, to);
  bone.getWorldQuaternion(_q3);
  setWorldQuat(bone, _q2.multiply(_q3));
  bone.updateMatrixWorld(true);
}
/** Rotação que leva a base (dir, lado) do alvo na da origem. */
function alignQ(pt, st, ps, ss) {
  if (!st || !ss) return new THREE.Quaternion().setFromUnitVectors(pt.clone().normalize(), ps.clone().normalize());
  const frame = (p, s) => {
    const x = p.clone().normalize(), z = new THREE.Vector3().crossVectors(x, s).normalize(), y = new THREE.Vector3().crossVectors(z, x);
    return new THREE.Quaternion().setFromRotationMatrix(new THREE.Matrix4().makeBasis(x, y, z));
  };
  return frame(ps, ss).multiply(frame(pt, st).invert());
}

export class Character {
  constructor(scene) {
    this.scene = scene;
    this.root = new THREE.Group();
    scene.add(this.root);
    this.loaded = false;
    this.yaw = 0;
    this.firstPerson = true;
    this.equip = 'hands';
    this.swap = -1;
    this.swapTo = 'hands';
    this.aiming = false;
    this.b = { aim: 0 };
    this.events = [];
    this.charge = 0;
    this.recoil = 0;
    this.reach = null;
    this.flashOn = false;
    this.pistol = new PistolRig(scene);
    this.guns = { pistol: this.pistol };
    this.headSway = { x: 0, z: 0 };
    this._eye = new THREE.Vector3();
    this.w = {};       // peso atual de cada clipe (corpo)
    this.t = {};       // tempo de cada clipe
    this.phase = 0;    // passada (0..1) dos clipes de andar/correr
    this.move = null;  // golpe em andamento
    this.ovW = 0;      // peso da parte de cima do golpe
    this._land = 0;
    this._jump = -1;
  }

  get gun() { return this.pistol; }
  get reloading() { return !!this.pistol.reloading; }

  async load(url, fpsUrl, coltUrl) {
    const [g] = await Promise.all([loadModelFile(url), this.pistol.load(fpsUrl, coltUrl)]);
    const model = this.model = g.scene;
    let meta = null;
    model.traverse((o) => { if (!meta && o.userData?.meta) meta = o.userData.meta; });
    this.meta = meta;
    model.traverse((o) => {
      if (o.isMesh) {
        o.castShadow = true; o.receiveShadow = true; o.frustumCulled = false;
        for (const m of [o.material].flat()) { m.envMapIntensity = 0.6; m.side = THREE.FrontSide; }
      }
    });
    this.root.add(model);
    const B = this.B = bonesByName(model);
    // ----- clipes: parte de baixo e de cima -----
    this.mixer = new THREE.AnimationMixer(model);
    this.A = {};
    for (const c of g.animations) {
      const lo = [], up = [];
      for (const t of c.tracks) (LOWER.has(boneName(t.name.split('.')[0])) ? lo : up).push(t);
      const mk = (tracks, sfx) => {
        const a = this.mixer.clipAction(new THREE.AnimationClip(c.name + sfx, c.duration, tracks));
        a.play(); a.weight = 0; a.timeScale = 0;
        return a;
      };
      this.A[c.name] = { lo: mk(lo, '_lo'), up: mk(up, '_up'), d: c.duration };
      this.w[c.name] = 0; this.t[c.name] = 0;
    }
    this.w.idle = 1;
    // ----- calibração (pose de repouso, raiz na origem) -----
    model.updateMatrixWorld(true);
    const P = (b) => B[b].getWorldPosition(new THREE.Vector3());
    const Q = (b) => B[b].getWorldQuaternion(new THREE.Quaternion());
    // olhos (a GoPro fica na testa): entre a base e o topo da cabeça, um pouco à frente
    const eye = P('Head').lerp(P('HeadTop_End'), 0.42).add(new THREE.Vector3(0, 0, 0.085));
    this.eyeOff = eye.clone().applyMatrix4(rigid(B.Head, new THREE.Matrix4()).invert());
    const hq = Q('Head').invert();
    this.headFwd = new THREE.Vector3(0, 0, 1).applyQuaternion(hq);
    this.headUp = new THREE.Vector3(0, 1, 0).applyQuaternion(hq);
    // coldre na coxa direita (o lado direito do modelo é -X): arma de cano para baixo, ferrolho para a frente
    const hipsR = rigid(B.Hips, new THREE.Matrix4());
    const gunBarrel = new THREE.Vector3(-1, 0, 0), gunUp = new THREE.Vector3(0, 1, 0); // eixos da Colt no arquivo
    const want = new THREE.Matrix4().makeBasis(new THREE.Vector3(0, -1, 0).applyAxisAngle(new THREE.Vector3(0, 0, 1), 0.12), new THREE.Vector3(0, 0, 1), new THREE.Vector3(-1, 0, 0));
    const have = new THREE.Matrix4().makeBasis(gunBarrel, gunUp, gunBarrel.clone().cross(gunUp));
    const sc = new THREE.Vector3().setFromMatrixScale(this.pistol.align).x; // unidades do arquivo -> metros
    const rot = want.multiply(have.transpose()).multiply(new THREE.Matrix4().makeScale(sc, sc, sc));
    const thigh = P('RightUpLeg');
    const pos = new THREE.Vector3(thigh.x - 0.085, thigh.y - 0.1, thigh.z + 0.0);
    // centro da Colt (no arquivo) vai para "pos"
    const colt = this.pistol.gun.children[0];
    colt.updateWorldMatrix(true, true);
    const box = this.coltBox = new THREE.Box3().setFromObject(colt);
    const cen = box.getCenter(new THREE.Vector3()).applyMatrix4(rot);
    rot.setPosition(pos.clone().sub(cen));
    this.holsterLocal = hipsR.clone().invert().multiply(rot);
    // coldre de couro
    const leather = new THREE.MeshStandardMaterial({ color: 0x241a12, roughness: 0.75, metalness: 0.05 });
    const hol = this.holsterMesh = new THREE.Group();
    hol.matrixAutoUpdate = false;
    const bodyG = new THREE.BoxGeometry(0.05, 0.17, 0.11);
    const pouch = new THREE.Mesh(bodyG, leather); pouch.position.set(0, -0.035, 0.0); pouch.castShadow = true;
    const strap = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.03, 0.13), leather); strap.position.set(0.004, -0.09, 0.0);
    hol.add(pouch, strap);
    this.scene.add(hol);
    // mãos e dedos: desvio entre a pose de repouso do rig da pistola e a do personagem
    const pr = this.pistol;
    const RP = (o) => pr.restP[o.name], RQ = (o) => pr.restQ[o.name];
    this.arms = {};
    for (const [S, side, sign] of [['Right', 'R', -1], ['Left', 'L', 1]]) {
      const F = pr.fingers[side], hand = pr.R['Hand_' + side];
      const latT = P(S + 'HandIndex1').sub(P(S + 'HandPinky1'));
      const latS = RP(F.Index[0]).clone().sub(RP(F.Pinky[0]));
      const K = (bot, fps, dirT, dirS, lat) => {
        const q = alignQ(dirT, lat ? latT : null, dirS, lat ? latS : null);
        return RQ(fps).clone().invert().multiply(q).multiply(Q(bot));
      };
      const fingers = [];
      for (const f of ['Index', 'Middle', 'Ring', 'Pinky', 'Thumb']) {
        for (let k = 0; k < 3; k++) {
          const bot = S + 'Hand' + f + (k + 1), next = S + 'Hand' + f + (k + 2);
          const fps = F[f][k], fnext = F[f][k + 1] ?? fps.children[0];
          if (!B[bot] || !B[next] || !fps || !fnext) continue;
          fingers.push({ bone: B[bot], fps, K: K(bot, fps, P(next).sub(P(bot)), RP(fnext).clone().sub(RP(fps)), f !== 'Thumb') });
        }
      }
      // pegada: o que tem que coincidir é a base dos dedos (as mãos têm palmas de tamanhos diferentes)
      const botGrip = P(S + 'HandMiddle1').sub(P(S + 'Hand')).applyQuaternion(Q(S + 'Hand').invert());
      const fpsGrip = RP(F.Middle[0]).clone().sub(RP(hand)).applyQuaternion(RQ(hand).clone().invert()).multiplyScalar(RIG_SCALE);
      this.arms[side] = {
        side: sign, shoulder: B[S + 'Shoulder'], upper: B[S + 'Arm'], fore: B[S + 'ForeArm'], hand: B[S + 'Hand'], botGrip, fpsGrip,
        handK: K(S + 'Hand', hand, P(S + 'HandMiddle1').sub(P(S + 'Hand')), RP(F.Middle[0]).clone().sub(RP(hand)), true),
        fingers,
      };
    }
    // golpes: momento em que a mão chega mais longe (contato) em cada clipe de soco
    for (const m of Object.values(MOVES)) {
      const a = this.A[m.clip];
      let best = 0, bt = 0.4;
      for (let i = 0; i <= 30; i++) {
        this._pose({ [m.clip]: 1 }, { [m.clip]: (i / 30) * a.d });
        const hips = P('Hips');
        for (const h of ['LeftHand', 'RightHand']) { const d = P(h).sub(hips).z; if (d > best) { best = d; bt = i / 30; } }
      }
      m.contact = bt; m.dur = a.d;
    }
    // lanterna presa na alça do ombro esquerdo
    this._buildChestLight();
    const spine2 = rigid(B.Spine2, new THREE.Matrix4());
    const lampAt = P('LeftShoulder').lerp(P('LeftArm'), 0.45).add(new THREE.Vector3(0, 0.0, 0.075));
    this.lampLocal = spine2.clone().invert().multiply(new THREE.Matrix4().makeTranslation(lampAt.x, lampAt.y, lampAt.z));
    this._pose({ idle: 1 }, { idle: 0 });
    this.loaded = true;
  }

  _buildChestLight() {
    const g = this.lamp = new THREE.Group();
    g.matrixAutoUpdate = false;
    const metal = new THREE.MeshStandardMaterial({ color: 0x1b1d20, roughness: 0.4, metalness: 0.8 });
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.017, 0.015, 0.075, 16), metal);
    body.rotation.x = Math.PI / 2; body.castShadow = true;
    const head = new THREE.Mesh(new THREE.CylinderGeometry(0.022, 0.018, 0.022, 16), metal);
    head.rotation.x = Math.PI / 2; head.position.z = 0.045;
    this.lensMat = new THREE.MeshStandardMaterial({ color: 0xfff3d8, emissive: 0xfff1d6, emissiveIntensity: 0, roughness: 0.1 });
    const lens = new THREE.Mesh(new THREE.CircleGeometry(0.019, 16), this.lensMat);
    lens.position.z = 0.0565;
    const clip = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.035, 0.01), metal);
    clip.position.set(0, 0.012, -0.025);
    g.add(body, head, lens, clip);
    this.lensPoint = new THREE.Vector3(0, 0, 0.06);
    this.scene.add(g);
  }

  /** Aplica pesos/tempos aos clipes e avalia o esqueleto. */
  _pose(wLo, tm, wUp = wLo) {
    for (const [n, a] of Object.entries(this.A)) {
      a.lo.weight = wLo[n] ?? 0; a.up.weight = wUp[n] ?? 0;
      const t = tm[n] ?? 0;
      a.lo.time = t; a.up.time = t;
    }
    this.mixer.update(0);
    this.model.updateMatrixWorld(true);
  }

  setFirstPerson(fp) { this.firstPerson = fp; }
  setObstruction() { /* (os braços não recolhem: a câmera fica na cabeça) */ }
  setCharge(c) { this.charge = c; }
  hitRecoil() { if (this.move) this.move.t = Math.max(this.move.t, this.move.m.contact * this.move.m.dur + 0.05); this.recoil = 1; }

  setEquip(it) {
    if (!this.loaded) return false;
    if (it === (this.swap >= 0 ? this.swapTo : this.equip)) return false;
    this.swapTo = it;
    this.swap = 0;
    this.move = null;
    if (it === 'pistol') this.pistol.draw(); else this.pistol.holster();
    return true;
  }

  reload() { return this.pistol.reload(); }
  fireGun() { return this.pistol.fire(); }

  /** Golpe de mãos livres: toque = jab/direto alternando; forte = gancho. */
  attack(heavy) {
    if (!this.loaded || this.equip !== 'hands' || this.swap >= 0) return;
    const cur = this.move;
    if (cur && cur.t < (cur.m.contact + 0.18) * cur.m.dur / 1) return;
    const name = heavy ? 'hook' : cur && cur.name === 'jab' ? 'cross' : 'jab';
    const m = MOVES[name];
    this.move = { name, m, t: 0, hit: false };
    this.events.push({ type: 'swing', move: m, name });
  }

  /** A mão vai até um ponto (maçaneta, objeto) e a ação acontece quando encosta. */
  reachTo(getPoint, { contact = 0.3, hold = 0.3, onContact } = {}) {
    if (this.reach) return;
    const arm = this.equip === 'pistol' || this.swap >= 0 ? this.arms.L : this.arms.R;
    this.reach = { getPoint, contact, hold, onContact, t: 0, arm, w: 0, low: 0 };
  }

  getEyeWorldPosition(target) { return target.copy(this._eye); }
  getCameraWorldPosition(target) { return target.copy(this._eye); }
  getLensWorldPosition(target) {
    if (!this.lamp) return target.set(0, 0, 0);
    return target.copy(this.lensPoint).applyMatrix4(this.lamp.matrixWorld);
  }
  setFlashlight(on, k = 1) {
    this.flashOn = on;
    if (this.lensMat) this.lensMat.emissiveIntensity = on ? 2.5 * k : 0;
  }

  update(dt, player) {
    if (!this.loaded) return;
    const B = this.B;
    this.recoil = damp(this.recoil, 0, 9, dt);
    this.root.position.copy(player.feetPosition);
    // corpo vira para onde se olha (na escada/borda, de frente para a parede)
    let targetYaw = player.yaw;
    if (player.onLadder) targetYaw = Math.atan2(player.ladder.l.nx, player.ladder.l.nz);
    else if (player.isHanging) targetYaw = Math.atan2(-player.hang.normal.x, -player.hang.normal.z);
    let dy = targetYaw - this.yaw;
    dy = Math.atan2(Math.sin(dy), Math.cos(dy));
    this.yaw += dy * (1 - Math.exp(-14 * dt));
    this.root.rotation.y = this.yaw + Math.PI; // o modelo olha para +Z

    for (const e of player.events) {
      if (e.type === 'jump') this._jump = 0;
      if (e.type === 'land' && e.speed > 4) this._land = Math.min(1, e.speed / 9);
      if (e.type === 'damage') this._hit = 0;
    }

    // ----- estado do corpo -> peso alvo de cada clipe -----
    const W = {};
    const speed = player.horizontalSpeed;
    const mi = player.moveInput, ml = Math.hypot(mi.x, mi.y) || 1;
    const fx = mi.x / ml, fy = mi.y / ml;
    const busyHands = player.onLadder || player.isClimbing || player.isHanging || player.swimming || player.dead;
    let locoRate = 0;
    if (player.dead) W.death = 1;
    else if (player.swimming) { const k = smoothstep(0.3, 1.2, speed); W.swim = k; W.swim_idle = 1 - k; }
    else if (player.onLadder || player.climb?.toLadder) {
      const vy = player.ladderVy ?? 0;
      const k = smoothstep(0.05, 0.4, Math.abs(vy) + (player.climb?.toLadder ? 1 : 0));
      W.ladder_climb = k; W.ladder_idle = 1 - k;
    } else if (player.isHanging) W.ledge_hang = 1;
    else if (player.isClimbing) W.climb_up = 1;
    else if (player.rolling) W.roll = 1;
    else if (player.sliding) W.slide = 1;
    else if (!player.onFloor && player.timeSinceGround > 0.12) W.jump_air = 1;
    else if (player.crouched) {
      const k = smoothstep(0.1, 0.5, speed);
      W.crouch_walk = k; W.crouch_idle = 1 - k;
      locoRate = speed / SPEED.crouch_walk / this.A.crouch_walk.d * (fy < -0.3 ? -1 : 1);
    } else {
      const moving = smoothstep(0.1, 0.6, speed);
      const idle = this.equip === 'hands' && player.health < 35 ? 'idle_hurt' : 'idle';
      W[idle] = 1 - moving;
      // 2D: frente (andar/trotar/correr), trás e lados
      const wf = Math.max(0, fy) ** 2, wb = Math.max(0, -fy) ** 2, wr = Math.max(0, fx) ** 2, wl = Math.max(0, -fx) ** 2;
      const sum = wf + wb + wr + wl || 1;
      const kf = moving * wf / sum;
      // trote x corrida x andar pela velocidade
      const v = speed;
      const wWalk = 1 - smoothstep(SPEED.walk, SPEED.jog, v), wSprint = smoothstep(SPEED.jog, SPEED.sprint, v);
      const wJog = 1 - wWalk - wSprint;
      const walkName = player.walkMode ? 'sneak' : 'walk';
      W[walkName] = kf * wWalk; W.jog = kf * wJog; W.sprint = kf * wSprint;
      W.walk_back = moving * wb / sum; W.strafe_right = moving * wr / sum; W.strafe_left = moving * wl / sum;
      // passada única para os clipes de frente (sincronizados)
      const cycle = (SPEED[walkName] * this.A[walkName].d) * wWalk + (SPEED.jog * this.A.jog.d) * wJog + (SPEED.sprint * this.A.sprint.d) * wSprint;
      locoRate = v / Math.max(0.3, cycle);
    }
    // pouso: dobra as pernas um instante
    if (this._land > 0) { this._land = Math.max(0, this._land - dt * 2.2); }
    // ----- pesos suaves (normalizados) -----
    let sum = 0;
    for (const n in this.w) { this.w[n] = damp(this.w[n], W[n] ?? 0, player.dead ? 6 : 12, dt); sum += this.w[n]; }
    for (const n in this.w) this.w[n] /= sum || 1;
    // ----- tempos -----
    const T = this.t, A = this.A;
    const wrap = (n, x) => { const d = A[n].d; return ((x % d) + d) % d; };
    this.phase = (this.phase + dt * locoRate + 1) % 1;
    for (const n of ['walk', 'sneak', 'jog', 'sprint']) T[n] = this.phase * A[n].d;
    T.crouch_walk = wrap('crouch_walk', T.crouch_walk + dt * locoRate * A.crouch_walk.d);
    for (const n of ['walk_back', 'strafe_left', 'strafe_right']) T[n] = wrap(n, T[n] + dt * Math.max(0.6, speed / SPEED[n]));
    for (const n of ['idle', 'idle_hurt', 'crouch_idle', 'swim_idle', 'ladder_idle', 'ledge_hang', 'jump_air', 'slide', 'tired', 'fight_idle']) T[n] = wrap(n, T[n] + dt);
    T.swim = wrap('swim', T.swim + dt * Math.max(0.7, speed / 1.6));
    // escada: anda com a subida (e volta descendo)
    T.ladder_climb = wrap('ladder_climb', T.ladder_climb + dt * (player.ladderVy ?? 0) / 0.95 * A.ladder_climb.d);
    T.climb_up = player.isClimbing ? 0.1 * A.climb_up.d + player.climbProgress * 0.85 * A.climb_up.d : 0;
    T.roll = player.rolling ? Math.min(1, player.rollTime / 0.65) * A.roll.d * 0.9 : 0;
    T.death = player.dead ? Math.min(A.death.d, T.death + dt) : 0;

    // ----- parte de cima: golpe / reação / alcançar -----
    let ovName = null, ovT = 0, ovTarget = 0;
    const mv = this.move;
    if (mv) {
      const before = mv.t;
      mv.t += dt * mv.m.rate;
      const ct = mv.m.contact * mv.m.dur;
      if (before < ct && mv.t >= ct) this.events.push({ type: 'hit', move: mv.m, name: mv.name });
      if (mv.t >= mv.m.dur * 0.92 || busyHands) this.move = null;
      else { ovName = mv.m.clip; ovT = mv.t; ovTarget = 1; }
    }
    if (this._hit >= 0) {
      this._hit += dt;
      if (this._hit > A.hit.d * 0.8) this._hit = -1;
      else if (!ovName) { ovName = 'hit'; ovT = this._hit; ovTarget = 0.8; }
    }
    this.ovW = damp(this.ovW, ovTarget, ovTarget > 0 ? 25 : 10, dt);
    if (ovName) this._ov = ovName;
    const wUp = {}, wLo = { ...this.w };
    for (const n in this.w) wUp[n] = this.w[n] * (1 - this.ovW);
    if (this._ov) { wUp[this._ov] = (wUp[this._ov] ?? 0) + this.ovW; }
    const tUp = { ...T };
    if (ovName) { tUp[ovName] = ovT; this._ovT = ovT; } else if (this._ov) tUp[this._ov] = this._ovT;
    // pouso: mistura um pouco do "pouso" nas pernas
    if (this._land > 0 && player.onFloor) {
      const k = Math.sin(Math.min(1, this._land) * Math.PI * 0.5) * 0.6;
      for (const n in wLo) wLo[n] *= 1 - k;
      wLo.jump_land = (wLo.jump_land ?? 0) + k; T.jump_land = A.jump_land.d * 0.18;
    }
    // pegar algo baixo: agacha as pernas
    if (this.reach?.low > 0) {
      const k = this.reach.low;
      for (const n in wLo) { wLo[n] *= 1 - k; wUp[n] *= 1 - k * 0.5; }
      wLo.crouch_idle = (wLo.crouch_idle ?? 0) + k; wUp.crouch_idle = (wUp.crouch_idle ?? 0) + k * 0.5;
    }
    // aplica (tempos iguais para baixo/cima, exceto o golpe)
    for (const [n, a] of Object.entries(A)) {
      a.lo.weight = wLo[n] ?? 0; a.up.weight = wUp[n] ?? 0;
      a.lo.time = T[n] ?? 0; a.up.time = tUp[n] ?? T[n] ?? 0;
    }
    this.mixer.update(0);

    // ----- olhar para cima/baixo: o tronco e a cabeça acompanham -----
    const lookW = busyHands || player.rolling || player.sliding ? 0.25 : 1;
    this._look = damp(this._look ?? 0, -player.pitch * lookW, 14, dt);
    const pistolOut = this.pistol.p > 0.3;
    this.root.updateMatrixWorld(true);
    _v3.set(1, 0, 0).applyQuaternion(this.root.quaternion); // eixo lateral (direita do modelo é -X)
    const parts = pistolOut ? [['Spine', 0.2], ['Spine1', 0.22], ['Spine2', 0.22], ['Neck', 0.14], ['Head', 0.22]] : [['Spine', 0.12], ['Spine1', 0.15], ['Spine2', 0.18], ['Neck', 0.2], ['Head', 0.35]];
    for (const [n, k] of parts) {
      const b = B[n];
      b.updateMatrixWorld(true);
      b.getWorldQuaternion(_q2);
      _q1.setFromAxisAngle(_v3, this._look * k);
      setWorldQuat(b, _q1.multiply(_q2));
    }
    // cabeça some em 1ª pessoa (a câmera está nela)
    const hs = this.firstPerson ? 0.001 : 1;
    B.Head.scale.setScalar(hs);
    this.model.updateMatrixWorld(true);

    // olhos / GoPro
    const headR = rigid(B.Head, _m1);
    this._eye.copy(this.eyeOff).applyMatrix4(headR);
    // balanço da cabeça (para a GoPro): quanto a cabeça sobe/desce e inclina com a animação,
    // além do olhar comandado (só a parte que varia: um filtro tira a inclinação parada)
    _q1.setFromRotationMatrix(headR);
    const hf = _v1.copy(this.headFwd).applyQuaternion(_q1), hu = _v2.copy(this.headUp).applyQuaternion(_q1);
    const side = _v4.crossVectors(hf, hu).normalize();
    const bobP = Math.asin(Math.max(-1, Math.min(1, hf.y))) + this._look, bobR = Math.atan2(-side.y, hu.y);
    this._swayRef = this._swayRef ?? { x: bobP, z: bobR };
    this._swayRef.x = damp(this._swayRef.x, bobP, 0.8, dt); this._swayRef.z = damp(this._swayRef.z, bobR, 0.8, dt);
    const clampS = (x) => Math.max(-0.08, Math.min(0.08, x));
    this.headSway.x = clampS(bobP - this._swayRef.x); this.headSway.z = clampS(bobR - this._swayRef.z);

    // ----- pistola -----
    // pendurado, escada, nadando...: a arma volta ao coldre e volta para a mão depois
    if (busyHands && this.pistol.state !== 'holstered' && this.pistol.state !== 'holstering') { this.pistol.holster(); this._redraw = this.equip === 'pistol' || this.swapTo === 'pistol'; }
    if (!busyHands && this._redraw && this.pistol.state === 'holstered') { this._redraw = false; this.pistol.draw(); }
    if (this.swap >= 0) {
      if (this.swapTo === 'pistol' && this.pistol.state === 'ready') { this.equip = 'pistol'; this.swap = -1; }
      if (this.swapTo === 'hands' && this.pistol.state === 'holstered') { this.equip = 'hands'; this.swap = -1; }
    }
    this.b.aim = damp(this.b.aim, this.aiming && this.pistol.state === 'ready' && !this.pistol.reloading ? 1 : 0, 12, dt);
    const anchor = _m2.compose(this._eye, _q1.setFromEuler(_e.set(player.pitch, player.yaw, 0, 'YXZ')), _one);
    const holster = rigid(B.Hips, new THREE.Matrix4()).multiply(this.holsterLocal);
    this.pistol.update(dt, {
      anchor, holster, move: player.onFloor ? smoothstep(0.2, 2.2, speed) : 0, speed,
      ads: this.b.aim, sprint: player.sprinting && speed > 4 ? 1 : 0,
      groundHeight: this.groundHeight, onClink: this.onShellClink,
    });
    for (const e of this.pistol.events) this.events.push(e);
    this.pistol.events.length = 0;
    // coldre (couro) e lanterna seguem o corpo
    this.holsterMesh.matrix.copy(holster).multiply(this._holsterOffset ?? (this._holsterOffset = this._holsterFromGun()));
    this.holsterMesh.matrixWorld.copy(this.holsterMesh.matrix);
    this.holsterMesh.updateMatrixWorld(true);
    this.lamp.matrix.copy(rigid(B.Spine2, _m1)).multiply(this.lampLocal);
    this.lamp.visible = !this.firstPerson; // (em 1ª pessoa ficaria colada na câmera)
    this.lamp.matrixWorld.copy(this.lamp.matrix);
    this.lamp.updateMatrixWorld(true);

    // ----- IK dos braços (pistola) -----
    const o = this.pistol.out;
    if (o.wR > 0.001) this._armIK(this.arms.R, o.handR, o.elbowR, o.shoulderR, o.wR, this.pistol.p < 1 ? 0.6 : 1);
    if (o.wL > 0.001) this._armIK(this.arms.L, o.handL, o.elbowL, o.shoulderL, o.wL, 1);

    // ----- alcançar (porta, objeto) -----
    this._reachPose(dt, player);

    // ----- eventos de passos do corpo etc. -----
    this.model.updateMatrixWorld(true);
  }

  _holsterFromGun() {
    // o couro cobre o cano/ferrolho da arma (no espaço da arma no coldre)
    // no espaço da arma (unidades do arquivo da Colt; o cano aponta para -X): o couro cobre
    // ferrolho, cano e guarda-mato e deixa o cabo (+X, embaixo) para fora
    const box = this.coltBox;
    const size = box.getSize(new THREE.Vector3());
    const c = box.getCenter(new THREE.Vector3());
    const m = new THREE.Matrix4().makeTranslation(c.x - size.x * 0.17, c.y + size.y * 0.16, c.z);
    const g = this.holsterMesh;
    const pouch = g.children[0], strap = g.children[1];
    pouch.geometry.dispose();
    pouch.geometry = new THREE.BoxGeometry(size.x * 0.7, size.y * 0.62, size.z * 1.45);
    strap.geometry.dispose();
    strap.geometry = new THREE.BoxGeometry(size.x * 0.09, size.y * 0.95, size.z * 1.7);
    pouch.position.set(0, 0, 0); strap.position.set(size.x * 0.22, -size.y * 0.1, 0);
    pouch.updateMatrix(); strap.updateMatrix();
    return m;
  }

  /** Braço vai para a mão do rig: IK de dois ossos com o cotovelo para o lado do rig, mão e dedos copiados. */
  _armIK(arm, handM, fpsElbow, fpsShoulder, w, fingerW, grip = true) {
    const target = _v3.setFromMatrixPosition(handM);
    const handQ = _q2.setFromRotationMatrix(handM);
    if (grip) {
      // pulso do personagem = base dos dedos do rig - (base dos dedos do personagem, girada)
      target.add(_v1.copy(arm.fpsGrip).applyQuaternion(handQ));
      handQ.multiply(arm.handK);
      target.sub(_v1.copy(arm.botGrip).applyQuaternion(handQ));
    }
    arm.hand.getWorldPosition(_v4);
    const T = _v5.copy(_v4).lerp(target, w);
    const S = arm.upper.getWorldPosition(new THREE.Vector3());
    const E = arm.fore.getWorldPosition(new THREE.Vector3());
    const Wp = arm.hand.getWorldPosition(new THREE.Vector3());
    const a = S.distanceTo(E), b = E.distanceTo(Wp);
    const toT = T.clone().sub(S);
    let d = toT.length();
    const dir = toT.divideScalar(d || 1);
    d = Math.min(d, (a + b) * 0.999);
    // lado do cotovelo: o mesmo do rig (perpendicular à linha ombro-mão dele)
    const fdir = target.clone().sub(fpsShoulder).normalize();
    const bend = fpsElbow.clone().sub(fpsShoulder);
    bend.addScaledVector(fdir, -bend.dot(fdir));
    bend.addScaledVector(dir, -bend.dot(dir));
    if (bend.lengthSq() < 1e-6) bend.set(0, -1, 0);
    bend.normalize();
    const x = (a * a - b * b + d * d) / (2 * d), h = Math.sqrt(Math.max(0, a * a - x * x));
    const En = S.clone().addScaledVector(dir, x).addScaledVector(bend, h);
    const Wn = S.clone().addScaledVector(dir, d);
    aimBone(arm.upper, E, En);
    aimBone(arm.fore, arm.hand.getWorldPosition(new THREE.Vector3()), Wn);
    // mão: rotação do rig (com o desvio de calibração)
    _q2.setFromRotationMatrix(handM).multiply(arm.handK);
    arm.hand.getWorldQuaternion(_q3);
    setWorldQuat(arm.hand, _q3.slerp(_q2, w));
    arm.hand.updateMatrixWorld(true);
    // dedos
    const fw = w * fingerW;
    if (fw > 0.001) {
      for (const f of arm.fingers) {
        f.fps.getWorldQuaternion(_q2).multiply(f.K);
        f.bone.getWorldQuaternion(_q3);
        setWorldQuat(f.bone, _q3.slerp(_q2, fw));
        f.bone.updateMatrixWorld(true);
      }
    }
  }

  _reachPose(dt, player) {
    const r = this.reach;
    if (!r) return;
    r.t += dt;
    const P = r.getPoint(_v3);
    if (r.t >= r.contact && !r.done) { r.done = true; r.onContact?.(); }
    const end = r.contact + r.hold;
    r.w = r.t < r.contact ? smooth(r.t / r.contact) : r.t < end ? 1 : 1 - smooth((r.t - end) / 0.35);
    // objeto baixo: agacha
    const low = smoothstep(0.9, 0.3, P.y - player.feetPosition.y);
    r.low = low * r.w;
    if (r.t > end + 0.35 || player.dead) { this.reach = null; return; }
    const arm = r.arm;
    const target = _v4.copy(P);
    // a mão para um pouco antes (a palma encosta, não o pulso)
    const S = arm.upper.getWorldPosition(new THREE.Vector3());
    const toward = target.clone().sub(S).normalize();
    target.addScaledVector(toward, -0.07);
    const handM = _m1.copy(arm.hand.matrixWorld);
    handM.setPosition(target);
    const pole = S.clone().add(_v1.set(arm.side * -0.3, -1, -0.2).applyQuaternion(this.root.quaternion));
    // mantém a rotação atual da mão (handK neutro): usa o próprio osso
    const keep = arm.handK;
    arm.handK = _q1.setFromRotationMatrix(handM).invert().multiply(arm.hand.getWorldQuaternion(_q2)).clone();
    this._armIK(arm, handM, pole, S, r.w, 0, false);
    arm.handK = keep;
  }
}
