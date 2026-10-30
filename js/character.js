import * as THREE from 'three';
import { loadModelFile, boneName, bonesByName } from './modelLoader.js';

// Personagem: "enemy" (balaclava, blusa, calça tática, coturno) com a pistola dele na mão.
// Animações próprias do arquivo (parado, arma pronta, corrida, andar mirando, agachado
// mirando, mirando parado) + animações públicas do Mesh2Motion convertidas para o esqueleto
// dele (andar, correr, de costas, de lado, agachar, pular, rolar, deslizar, nadar, escada,
// escalar, pendurado, socos, recarga de pistola, pegar, comer/beber, revistar, dano, morte).
// Cada clipe é dividido em pernas e tronco: mirar, recarregar, golpear e usar itens trocam só
// a parte de cima. Mirando, o tronco gira até o cano apontar para o centro da mira.
// Com as mãos ocupadas (escada, nadar, pendurado, escalar, curativo...) a pistola vai para o
// coldre da coxa.

export const FP_HIDDEN_LAYER = 1;

const LOWER = new Set(['Hips', 'LeftUpLeg', 'LeftLeg', 'LeftFoot', 'LeftToeBase', 'LeftToe_End', 'RightUpLeg', 'RightLeg', 'RightFoot', 'RightToeBase', 'RightToe_End']);
// velocidade (m/s) de cada clipe de locomoção
const SPEED = { walk: 0.75, jog: 2.6, sprint: 5.6, walk_back: 0.7, strafe_left: 0.6, strafe_right: 0.6, crouch_walk: 0.6, sneak: 0.7, aim_walk: 1.45 };
// golpes: a coronhada usa a mão da arma, o jab a outra
const MOVES = {
  jab: { clip: 'punch_jab', rate: 1.55, reach: 1.25, power: 3, lunge: 0.6, kind: 'hands' },
  cross: { clip: 'punch_cross', rate: 1.45, reach: 1.3, power: 5, lunge: 0.9, kind: 'hands' },
};

const damp = (a, b, l, dt) => a + (b - a) * (1 - Math.exp(-l * dt));
const smooth = (t) => { t = Math.min(1, Math.max(0, t)); return t * t * (3 - 2 * t); };
const smoothstep = (a, b, x) => smooth((x - a) / (b - a));
const _v1 = new THREE.Vector3(), _v2 = new THREE.Vector3(), _v3 = new THREE.Vector3(), _v4 = new THREE.Vector3(), _v5 = new THREE.Vector3();
const _q1 = new THREE.Quaternion(), _q2 = new THREE.Quaternion(), _q3 = new THREE.Quaternion();
const _m1 = new THREE.Matrix4(), _m2 = new THREE.Matrix4();
const _s = new THREE.Vector3(), _one = new THREE.Vector3(1, 1, 1);

function rigid(o, out) {
  o.matrixWorld.decompose(_v5, _q3, _s);
  return out.compose(_v5, _q3, _one);
}
function setWorldQuat(bone, q) {
  bone.parent.getWorldQuaternion(_q1);
  bone.quaternion.copy(_q1.invert().multiply(q));
}
/** Gira o osso (no mundo) pela rotação q. */
function rotateWorld(bone, q) {
  bone.updateMatrixWorld(true);
  bone.getWorldQuaternion(_q2);
  setWorldQuat(bone, _q3.copy(q).multiply(_q2));
  bone.updateMatrixWorld(true);
}
function aimBone(bone, childPos, targetPos) {
  const p = bone.getWorldPosition(_v4);
  const from = _v1.copy(childPos).sub(p).normalize(), to = _v2.copy(targetPos).sub(p).normalize();
  rotateWorld(bone, new THREE.Quaternion().setFromUnitVectors(from, to));
}

export class Character {
  constructor(scene) {
    this.scene = scene;
    this.root = new THREE.Group();
    scene.add(this.root);
    this.loaded = false;
    this.yaw = 0;
    this.firstPerson = true;
    this.aiming = false;
    this.b = { aim: 0 };
    this.events = [];
    this.charge = 0;
    this.recoil = 0;
    this.reach = null;
    this.action = null; // comer, beber, curativo, revistar
    this.headSway = { x: 0, z: 0 };
    this.aimTarget = new THREE.Vector3();
    this._eye = new THREE.Vector3();
    this.w = {}; this.t = {};
    this.phase = 0;
    this.move = null;
    this.ovW = 0;
    this._land = 0;
    this._alert = 0;   // depois de atirar fica um tempo com a arma pronta
    this._kick = 0;    // recuo do tiro
    this.gun = { capacity: 15, loaded: 15, reserve: 30, muzzleWorld: new THREE.Vector3() };
    this.reloadT = -1;
    this.fireCool = 0;
    this.holsterBlend = 0;
  }

  get reloading() { return this.reloadT >= 0; }

  async load(url) {
    const g = await loadModelFile(url);
    const model = this.model = g.scene;
    let meta = null;
    model.traverse((o) => { if (!meta && o.userData?.meta) meta = o.userData.meta; });
    this.meta = meta;
    model.traverse((o) => {
      if (o.isMesh) {
        o.castShadow = true; o.receiveShadow = true; o.frustumCulled = false;
        for (const m of [o.material].flat()) m.envMapIntensity = 0.7;
      }
    });
    this.root.add(model);
    const B = this.B = bonesByName(model);
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
    this._pose({ idle: 1 }, { idle: 0 });
    const P = (b) => B[b].getWorldPosition(new THREE.Vector3());
    // olhos / GoPro na testa
    const eye = P('Head').lerp(P('HeadTop_End'), 0.45).add(new THREE.Vector3(0, 0, 0.1));
    this.eyeOff = eye.clone().applyMatrix4(rigid(B.Head, new THREE.Matrix4()).invert());
    const hq = B.Head.getWorldQuaternion(new THREE.Quaternion()).invert();
    this.headFwd = new THREE.Vector3(0, 0, 1).applyQuaternion(hq);
    this.headUp = new THREE.Vector3(0, 1, 0).applyQuaternion(hq);
    // pistola dele: partes e pontos (boca do cano, traseira) no espaço da pistola
    const pis = this.pistol = model.getObjectByName('pistolLOW');
    this.slide = model.getObjectByName('slide');
    this.mag = model.getObjectByName('mag');
    this.trigger = model.getObjectByName('trigger');
    this.slideRest = this.slide.position.clone();
    this.magRest = this.mag.position.clone();
    this.trigRest = this.trigger.position.clone();
    this.muzzleLocal = new THREE.Vector3().fromArray(meta.pistol.muzzle);
    this.rearLocal = new THREE.Vector3().fromArray(meta.pistol.rear);
    this.barrelLocal = this.muzzleLocal.clone().sub(this.rearLocal).normalize();
    this.handPistol = pis.matrix.clone(); // pistola na mão (local da mão)
    // coldre na coxa direita (lado direito do modelo é -X): cano para baixo, ferrolho para a frente
    model.updateMatrixWorld(true);
    const thigh = P('RightUpLeg'), knee = P('RightLeg');
    const sc = new THREE.Vector3().setFromMatrixScale(pis.matrixWorld).x;
    const upLocal = this.slide.position.clone().sub(model.getObjectByName('base').position).normalize();
    const have = new THREE.Matrix4().makeBasis(this.barrelLocal, upLocal, this.barrelLocal.clone().cross(upLocal));
    const want = new THREE.Matrix4().makeBasis(new THREE.Vector3(0, -1, 0), new THREE.Vector3(0, 0, 1), new THREE.Vector3(-1, 0, 0));
    const rot = want.multiply(have.transpose()).multiply(new THREE.Matrix4().makeScale(sc, sc, sc));
    const mid = this.muzzleLocal.clone().lerp(this.rearLocal, 0.5).applyMatrix4(rot);
    const at = thigh.clone().lerp(knee, 0.28).add(new THREE.Vector3(-0.1, 0, 0));
    rot.setPosition(at.sub(mid));
    this.holsterLocal = rigid(B.RightUpLeg, new THREE.Matrix4()).invert().multiply(rot);
    // golpes: momento do contato (mão mais à frente)
    for (const m of Object.values(MOVES)) {
      const a = this.A[m.clip];
      let best = -1e9, bt = 0.4;
      for (let i = 0; i <= 30; i++) {
        this._pose({ [m.clip]: 1 }, { [m.clip]: (i / 30) * a.d });
        const hips = P('Hips');
        for (const h of ['LeftHand', 'RightHand']) { const d = P(h).sub(hips).z; if (d > best) { best = d; bt = i / 30; } }
      }
      m.contact = bt; m.dur = a.d;
    }
    this._pose({ idle: 1 }, { idle: 0 });
    // clarão e cápsulas
    const fc = document.createElement('canvas'); fc.width = fc.height = 64;
    const gg = fc.getContext('2d'), rg = gg.createRadialGradient(32, 32, 0, 32, 32, 32);
    rg.addColorStop(0, 'rgba(255,250,225,1)'); rg.addColorStop(0.25, 'rgba(255,200,110,0.8)'); rg.addColorStop(1, 'rgba(255,140,40,0)');
    gg.fillStyle = rg; gg.fillRect(0, 0, 64, 64);
    this.flash = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(fc), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
    this.flash.visible = false;
    this.flashLight = new THREE.PointLight(0xffc27a, 0, 8, 2);
    this.scene.add(this.flash, this.flashLight);
    this.flashT = 0;
    this.shells = [];
    this.shellGeo = new THREE.CylinderGeometry(0.0048, 0.0048, 0.019, 8);
    this.shellMat = new THREE.MeshStandardMaterial({ color: 0xc9a14a, metalness: 0.9, roughness: 0.3 });
    this.loaded = true;
  }

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
  setObstruction() {}
  setCharge(c) { this.charge = c; }
  hitRecoil() { if (this.move) this.move.t = Math.max(this.move.t, this.move.m.contact * this.move.m.dur + 0.05); this.recoil = 1; }

  /** 'fired' | 'dry' | null */
  fireGun() {
    if (!this.loaded || this.reloadT >= 0 || this.fireCool > 0 || this.holsterBlend > 0.5 || this.action || this.move) return null;
    this.fireCool = 0.13;
    this._alert = 5;
    if (this.gun.loaded <= 0) return 'dry';
    this.gun.loaded--;
    this._kick = 1;
    this.flashT = 0.05;
    this._spawnShell = true;
    return 'fired';
  }

  reload() {
    if (!this.loaded || this.reloadT >= 0 || this.gun.loaded >= this.gun.capacity || this.gun.reserve <= 0 || this.holsterBlend > 0.5 || this.action) return false;
    this.reloadT = 0;
    return true;
  }

  /** Golpe: toque = jab/coronhada alternando; forte = coronhada. */
  attack(heavy) {
    if (!this.loaded || this.action || this.reloadT >= 0 || this.holsterBlend > 0.5) return;
    const cur = this.move;
    if (cur && cur.t < (cur.m.contact + 0.18) * cur.m.dur) return;
    const name = heavy ? 'cross' : cur && cur.name === 'jab' ? 'cross' : 'jab';
    const m = { ...MOVES[name], heavy: !!heavy, power: MOVES[name].power * (heavy ? 1.5 : 1) };
    this.move = { name, m, t: 0 };
    this.events.push({ type: 'swing', move: m, name });
  }

  /** Ação com a parte de cima (ou o corpo todo): comer, beber, curativo, revistar. */
  playAction(kind, { duration, onDone, full = false } = {}) {
    if (this.action || !this.loaded) return false;
    const clip = { eat: 'consume', drink: 'consume', bandage: 'consume', search: 'kneel_search', pickup: 'pickup' }[kind] ?? 'interact';
    this.action = { kind, clip, t: 0, dur: duration ?? this.A[clip].d, onDone, full };
    this.reloadT = -1;
    this.move = null;
    return true;
  }

  cancelAction() { this.action = null; }

  reachTo(getPoint, { contact = 0.3, hold = 0.3, onContact } = {}) {
    if (this.reach) return;
    this.reach = { getPoint, contact, hold, onContact, t: 0, w: 0, low: 0 };
  }

  getEyeWorldPosition(target) { return target.copy(this._eye); }
  getCameraWorldPosition(target) { return target.copy(this._eye); }

  update(dt, player) {
    if (!this.loaded) return;
    const B = this.B, A = this.A;
    this.recoil = damp(this.recoil, 0, 9, dt);
    this.fireCool -= dt;
    this._alert = Math.max(0, this._alert - dt);
    this.root.position.copy(player.feetPosition);
    let targetYaw = player.yaw;
    if (player.onLadder) targetYaw = Math.atan2(player.ladder.l.nx, player.ladder.l.nz);
    else if (player.isHanging) targetYaw = Math.atan2(-player.hang.normal.x, -player.hang.normal.z);
    let dy = targetYaw - this.yaw;
    dy = Math.atan2(Math.sin(dy), Math.cos(dy));
    this.yaw += dy * (1 - Math.exp(-14 * dt));
    this.root.rotation.y = this.yaw + Math.PI;

    for (const e of player.events) {
      if (e.type === 'land' && e.speed > 4) this._land = Math.min(1, e.speed / 9);
      if (e.type === 'damage') this._hit = 0;
    }

    const busyHands = player.onLadder || player.isClimbing || player.isHanging || player.swimming || player.dead;
    // mirar: segurando o botão, ou logo depois de atirar (mesmo sem mirar)
    const canAim = !busyHands && !player.rolling && !player.sliding && !(player.sprinting && player.horizontalSpeed > 4) && !this.action && this.holsterBlend < 0.2 && !this.move;
    const aimT = canAim && (this.aiming || this.fireCool > -0.6) ? 1 : 0;
    this.b.aim = damp(this.b.aim, aimT, aimT ? 14 : 8, dt);
    const aim = this.b.aim;

    // ----- corpo -----
    const W = {};
    const speed = player.horizontalSpeed;
    const mi = player.moveInput, ml = Math.hypot(mi.x, mi.y) || 1;
    const fx = mi.x / ml, fy = mi.y / ml;
    let locoRate = 0;
    const full = this.action?.full ? this.action.clip : null;
    if (player.dead) W.death = 1;
    else if (full) W[full] = 1;
    else if (player.swimming) { const k = smoothstep(0.3, 1.2, speed); W.swim = k; W.swim_idle = 1 - k; }
    else if (player.onLadder || player.climb?.toLadder) {
      const k = smoothstep(0.05, 0.4, Math.abs(player.ladderVy ?? 0) + (player.climb?.toLadder ? 1 : 0));
      W.ladder_climb = k; W.ladder_idle = 1 - k;
    } else if (player.isHanging) W.ledge_hang = 1;
    else if (player.isClimbing) W.climb_up = 1;
    else if (player.rolling) W.roll = 1;
    else if (player.sliding) W.slide = 1;
    else if (!player.onFloor && player.timeSinceGround > 0.12) W.jump_air = 1;
    else if (player.crouched) {
      const k = smoothstep(0.1, 0.5, speed);
      W.crouch_walk = k; W.crouch_idle = (1 - k) * (1 - aim); W.crouch_aim = (1 - k) * aim;
      locoRate = speed / SPEED.crouch_walk / A.crouch_walk.d * (fy < -0.3 ? -1 : 1);
    } else {
      const moving = smoothstep(0.1, 0.6, speed);
      const tiredK = smoothstep(22, 4, player.stamina ?? 100) * (1 - moving) * (1 - aim);
      const idle = player.health < 35 ? 'idle_hurt' : this._alert > 0 ? 'aim_ready' : 'idle';
      W[idle] = (1 - moving) * (1 - tiredK); W.tired = tiredK;
      const wf = Math.max(0, fy) ** 2, wb = Math.max(0, -fy) ** 2, wr = Math.max(0, fx) ** 2, wl = Math.max(0, -fx) ** 2;
      const sum = wf + wb + wr + wl || 1;
      const kf = moving * wf / sum;
      const v = speed;
      if (aim > 0.5) {
        // mirando e andando para a frente: a animação de andar mirando do próprio personagem
        W.aim_walk = kf;
        locoRate = v / (SPEED.aim_walk * A.aim_walk.d);
      } else {
        const wWalk = 1 - smoothstep(SPEED.walk + 0.3, SPEED.jog, v), wSprint = smoothstep(SPEED.jog + 0.6, SPEED.sprint, v);
        const wJog = 1 - wWalk - wSprint;
        const walkName = player.walkMode ? 'sneak' : 'walk';
        W[walkName] = kf * wWalk; W.jog = kf * wJog; W.sprint = kf * wSprint;
        const cycle = (SPEED[walkName] * A[walkName].d) * wWalk + (SPEED.jog * A.jog.d) * wJog + (SPEED.sprint * A.sprint.d) * wSprint;
        locoRate = v / Math.max(0.3, cycle);
      }
      W.walk_back = moving * wb / sum; W.strafe_right = moving * wr / sum; W.strafe_left = moving * wl / sum;
    }
    if (this._land > 0) this._land = Math.max(0, this._land - dt * 2.2);
    let sum = 0;
    for (const n in this.w) { this.w[n] = damp(this.w[n], W[n] ?? 0, player.dead ? 6 : 12, dt); sum += this.w[n]; }
    for (const n in this.w) this.w[n] /= sum || 1;
    // tempos
    const T = this.t;
    const wrap = (n, x) => { const d = A[n].d; return ((x % d) + d) % d; };
    this.phase = (this.phase + dt * locoRate + 1) % 1;
    for (const n of ['walk', 'sneak', 'jog', 'sprint', 'aim_walk']) T[n] = this.phase * A[n].d;
    T.crouch_walk = wrap('crouch_walk', T.crouch_walk + dt * locoRate * A.crouch_walk.d);
    for (const n of ['walk_back', 'strafe_left', 'strafe_right']) T[n] = wrap(n, T[n] + dt * Math.max(0.6, speed / SPEED[n]));
    for (const n of ['idle', 'idle_hurt', 'aim_ready', 'aim_idle', 'crouch_idle', 'crouch_aim', 'swim_idle', 'ladder_idle', 'ledge_hang', 'jump_air', 'slide', 'tired', 'kneel_search']) T[n] = wrap(n, T[n] + dt);
    T.swim = wrap('swim', T.swim + dt * Math.max(0.7, speed / 1.6));
    T.ladder_climb = wrap('ladder_climb', T.ladder_climb + dt * (player.ladderVy ?? 0) / 0.95 * A.ladder_climb.d);
    T.climb_up = player.isClimbing ? 0.1 * A.climb_up.d + player.climbProgress * 0.85 * A.climb_up.d : 0;
    T.roll = player.rolling ? Math.min(1, player.rollTime / 0.65) * A.roll.d * 0.9 : 0;
    T.death = player.dead ? Math.min(A.death.d, T.death + dt) : 0;

    // ----- parte de cima -----
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
    // recarga (animação pública de pistola, um pouco mais rápida)
    if (this.reloadT >= 0) {
      const d = A.pistol_reload.d, before = this.reloadT;
      this.reloadT += dt * 1.25;
      const k = this.reloadT / d;
      if (before / d < 0.22 && k >= 0.22) this.events.push({ type: 'magOut' });
      if (before / d < 0.62 && k >= 0.62) {
        this.events.push({ type: 'magIn' });
        const n = Math.min(this.gun.capacity - this.gun.loaded, this.gun.reserve);
        this.gun.reserve -= n; this.gun.loaded += n;
      }
      if (before / d < 0.8 && k >= 0.8) this.events.push({ type: 'slide' });
      if (k >= 1 || busyHands) this.reloadT = -1;
      else if (!ovName) { ovName = 'pistol_reload'; ovT = this.reloadT; ovTarget = 1; }
    }
    // ação (comer, beber, curativo...)
    const ac = this.action;
    if (ac) {
      ac.t += dt;
      if (ac.t >= ac.dur || player.dead || (busyHands && !ac.full)) { const cb = ac.onDone; const ok = ac.t >= ac.dur && !player.dead; this.action = null; if (ok) cb?.(); }
      else if (!ac.full && !ovName) { ovName = ac.clip; ovT = wrap(ac.clip, ac.t * (A[ac.clip].d / ac.dur)); ovTarget = 1; }
    }
    if (this._hit >= 0) {
      this._hit += dt;
      if (this._hit > A.hit.d * 0.8) this._hit = -1;
      else if (!ovName) { ovName = 'hit'; ovT = this._hit; ovTarget = 0.8; }
    }
    // mirando parado em pé: braços estendidos (mirando andando o clipe do corpo já mira)
    if (!ovName && aim > 0.01 && !player.crouched && !busyHands) {
      ovName = 'aim_idle'; ovT = T.aim_idle; ovTarget = aim * (1 - (this.w.aim_walk ?? 0));
    }
    this.ovW = damp(this.ovW, ovTarget, ovTarget > 0 ? 18 : 10, dt);
    if (ovName) this._ov = ovName;
    const wUp = {}, wLo = { ...this.w };
    for (const n in this.w) wUp[n] = this.w[n] * (1 - this.ovW);
    if (this._ov) wUp[this._ov] = (wUp[this._ov] ?? 0) + this.ovW;
    const tUp = { ...T };
    if (ovName) { tUp[ovName] = ovT; this._ovT = ovT; } else if (this._ov) tUp[this._ov] = this._ovT;
    if (this._land > 0 && player.onFloor) {
      const k = Math.sin(Math.min(1, this._land) * Math.PI * 0.5) * 0.6;
      for (const n in wLo) wLo[n] *= 1 - k;
      wLo.jump_land = (wLo.jump_land ?? 0) + k; T.jump_land = A.jump_land.d * 0.18;
    }
    if (this.reach?.low > 0) {
      const k = this.reach.low;
      for (const n in wLo) wLo[n] *= 1 - k;
      wLo.crouch_idle = (wLo.crouch_idle ?? 0) + k;
    }
    for (const [n, a] of Object.entries(A)) {
      a.lo.weight = wLo[n] ?? 0; a.up.weight = wUp[n] ?? 0;
      a.lo.time = T[n] ?? 0; a.up.time = tUp[n] ?? T[n] ?? 0;
    }
    this.mixer.update(0);
    this.root.updateMatrixWorld(true);

    // ----- olhar para cima/baixo -----
    const lookW = (busyHands || player.rolling || player.sliding ? 0.25 : 1) * (1 - aim);
    this._look = damp(this._look ?? 0, -player.pitch * lookW, 14, dt);
    const lat = _v3.set(1, 0, 0).applyQuaternion(this.root.quaternion).clone();
    for (const [n, k] of [['Spine', 0.25], ['Spine2', 0.3], ['Neck', 0.2], ['Head', 0.25]]) rotateWorld(B[n], new THREE.Quaternion().setFromAxisAngle(lat, this._look * k));

    // ----- mira: tronco gira até o cano apontar para o alvo -----
    if (aim > 0.01) {
      for (let it = 0; it < 2; it++) {
        this.model.updateMatrixWorld(true);
        const mz = this.muzzleLocal.clone().applyMatrix4(this.pistol.matrixWorld);
        const rr = this.rearLocal.clone().applyMatrix4(this.pistol.matrixWorld);
        const have = mz.clone().sub(rr).normalize();
        const want = this.aimTarget.clone().sub(mz).normalize();
        // alvo atrás/colado no corpo (câmera esquisita): não torce o tronco
        const fwd = new THREE.Vector3(0, 0, 1).applyQuaternion(this.root.quaternion);
        if (want.dot(fwd) < 0.2 || this.aimTarget.distanceTo(mz) < 1.2) break;
        const full = new THREE.Quaternion().setFromUnitVectors(have, want);
        const ang = 2 * Math.acos(Math.min(1, Math.abs(full.w)));
        const q = new THREE.Quaternion().slerp(full, aim * Math.min(1, 0.8 / Math.max(ang, 1e-3)));
        rotateWorld(B.Spine, new THREE.Quaternion().slerp(q, 0.45));
        rotateWorld(B.Spine2, new THREE.Quaternion().slerp(q, 0.55));
      }
    }
    // ----- recuo do tiro -----
    this._kick = damp(this._kick, 0, 16, dt);
    if (this._kick > 0.01) {
      rotateWorld(B.RightForeArm, new THREE.Quaternion().setFromAxisAngle(lat, -0.3 * this._kick));
      rotateWorld(B.RightHand, new THREE.Quaternion().setFromAxisAngle(lat, -0.25 * this._kick));
    }

    // cabeça some em 1ª pessoa
    B.Head.scale.setScalar(this.firstPerson ? 0.001 : 1);
    this.model.updateMatrixWorld(true);
    const headR = rigid(B.Head, _m1);
    this._eye.copy(this.eyeOff).applyMatrix4(headR);
    // balanço da cabeça (GoPro)
    _q1.setFromRotationMatrix(headR);
    const hf = _v1.copy(this.headFwd).applyQuaternion(_q1), hu = _v2.copy(this.headUp).applyQuaternion(_q1);
    const side = _v4.crossVectors(hf, hu).normalize();
    const bobP = Math.asin(Math.max(-1, Math.min(1, hf.y))) + this._look, bobR = Math.atan2(-side.y, hu.y);
    this._swayRef = this._swayRef ?? { x: bobP, z: bobR };
    this._swayRef.x = damp(this._swayRef.x, bobP, 0.8, dt); this._swayRef.z = damp(this._swayRef.z, bobR, 0.8, dt);
    const clampS = (x) => Math.max(-0.08, Math.min(0.08, x));
    this.headSway.x = clampS(bobP - this._swayRef.x) * (1 - aim * 0.7); this.headSway.z = clampS(bobR - this._swayRef.z) * (1 - aim * 0.7);

    // ----- pistola: mão ou coldre; ferrolho, carregador, gatilho -----
    const holsterT = busyHands || (this.action && this.action.kind !== 'search') ? 1 : 0;
    this.holsterBlend = damp(this.holsterBlend, holsterT, 10, dt);
    const pis = this.pistol;
    if (this.holsterBlend > 0.5) {
      pis.matrixAutoUpdate = false;
      rigid(B.RightUpLeg, _m2).multiply(this.holsterLocal);
      pis.matrix.copy(B.RightHand.matrixWorld).invert().multiply(_m2);
    } else {
      pis.matrixAutoUpdate = false;
      pis.matrix.copy(this.handPistol);
    }
    pis.matrixWorldNeedsUpdate = true;
    const slideBack = Math.max(0, this._kick - 0.35) / 0.65;
    this.slide.position.copy(this.slideRest).addScaledVector(this.barrelLocal, -slideBack * 3.0);
    this.trigger.position.copy(this.trigRest).addScaledVector(this.barrelLocal, -Math.min(1, this._kick * 2) * 0.35);
    let magOff = 0;
    if (this.reloadT >= 0) { const k = this.reloadT / A.pistol_reload.d; magOff = k < 0.22 ? 0 : k < 0.3 ? (k - 0.22) / 0.08 : k < 0.52 ? 1 : k < 0.62 ? 1 - (k - 0.52) / 0.1 : 0; }
    this.mag.position.copy(this.magRest);
    this.mag.position.y -= magOff * 14;
    this.mag.visible = magOff < 0.98;
    this.model.updateMatrixWorld(true);
    this.gun.muzzleWorld.copy(this.muzzleLocal).applyMatrix4(pis.matrixWorld);

    // clarão
    this.flashT -= dt;
    const fl = this.flashT > 0;
    this.flash.visible = fl;
    this.flashLight.intensity = fl ? 35 : 0;
    if (fl) {
      this.flash.position.copy(this.gun.muzzleWorld);
      this.flash.scale.setScalar(0.12 + Math.random() * 0.08);
      this.flash.material.rotation = Math.random() * 6.3;
      this.flashLight.position.copy(this.gun.muzzleWorld);
    }
    this._updateShells(dt);
    this._reachPose(dt, player);
    this.model.updateMatrixWorld(true);
  }

  _updateShells(dt) {
    if (this._spawnShell) {
      this._spawnShell = false;
      let s = this.shells.find((x) => !x.alive);
      if (!s) { s = { m: new THREE.Mesh(this.shellGeo, this.shellMat), v: new THREE.Vector3(), w: new THREE.Vector3() }; s.m.castShadow = true; this.scene.add(s.m); this.shells.push(s); }
      s.alive = true; s.life = 8; s.bounced = 0; s.m.visible = true;
      s.m.position.copy(this.rearLocal).lerp(this.muzzleLocal, 0.3).applyMatrix4(this.pistol.matrixWorld);
      s.v.set(-1, 0, 0).applyQuaternion(this.root.quaternion).multiplyScalar(1.8 + Math.random() * 0.6);
      s.v.y = 1.6 + Math.random() * 0.6;
      s.w.set(Math.random() * 30, Math.random() * 30, Math.random() * 30);
    }
    for (const s of this.shells) {
      if (!s.alive) continue;
      s.life -= dt;
      if (s.life <= 0) { s.alive = false; s.m.visible = false; continue; }
      if (s.bounced > 2) continue;
      s.v.y -= 9.8 * dt;
      s.m.position.addScaledVector(s.v, dt);
      s.m.rotation.x += s.w.x * dt; s.m.rotation.y += s.w.y * dt; s.m.rotation.z += s.w.z * dt;
      const gy = this.groundHeight ? this.groundHeight(s.m.position.x, s.m.position.z) + 0.005 : -Infinity;
      if (s.m.position.y < gy) {
        s.m.position.y = gy;
        s.v.y = Math.abs(s.v.y) * 0.3; s.v.x *= 0.4; s.v.z *= 0.4; s.w.multiplyScalar(0.5);
        if (s.bounced++ === 0) this.onShellClink?.(s.m.position);
        if (s.bounced > 2) s.m.rotation.set(Math.PI / 2, Math.random() * 6, 0);
      }
    }
  }

  /** Mão esquerda vai até um ponto (maçaneta, objeto); a ação acontece quando encosta. */
  _reachPose(dt, player) {
    const r = this.reach;
    if (!r) return;
    r.t += dt;
    const P = r.getPoint(new THREE.Vector3());
    if (r.t >= r.contact && !r.done) { r.done = true; r.onContact?.(); }
    const end = r.contact + r.hold;
    r.w = r.t < r.contact ? smooth(r.t / r.contact) : r.t < end ? 1 : 1 - smooth((r.t - end) / 0.35);
    r.low = smoothstep(0.9, 0.3, P.y - player.feetPosition.y) * r.w;
    if (r.t > end + 0.35 || player.dead) { this.reach = null; return; }
    const B = this.B;
    const upper = B.LeftArm, fore = B.LeftForeArm, hand = B.LeftHand;
    const S = upper.getWorldPosition(new THREE.Vector3());
    const target = P.clone().addScaledVector(P.clone().sub(S).normalize(), -0.08);
    const Wp = hand.getWorldPosition(new THREE.Vector3());
    const Tt = Wp.clone().lerp(target, r.w);
    const E = fore.getWorldPosition(new THREE.Vector3());
    const a = S.distanceTo(E), b = E.distanceTo(Wp);
    const toT = Tt.clone().sub(S);
    let d = toT.length();
    const dir = toT.divideScalar(d || 1);
    d = Math.min(d, (a + b) * 0.999);
    const bend = new THREE.Vector3(0.3, -1, -0.2).applyQuaternion(this.root.quaternion);
    bend.addScaledVector(dir, -bend.dot(dir)).normalize();
    const x = (a * a - b * b + d * d) / (2 * d), h = Math.sqrt(Math.max(0, a * a - x * x));
    aimBone(upper, E, S.clone().addScaledVector(dir, x).addScaledVector(bend, h));
    aimBone(fore, hand.getWorldPosition(new THREE.Vector3()), S.clone().addScaledVector(dir, d));
  }
}
