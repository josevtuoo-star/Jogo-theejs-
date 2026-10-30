import * as THREE from 'three';
import { loadModelFile } from './modelLoader.js';

// Pistola Colt M1911 com as animações de primeira pessoa do arquivo "FPS pistol animations"
// (parado, andando, tiro, recarga com o carregador ainda com bala e recarga vazia).
// O rig de braços desse arquivo não é desenhado: ele só serve de "fonte" de movimento. A cada
// quadro ele é posto na frente dos olhos do personagem (a câmera dele no lugar da nossa) e as
// mãos dele viram alvos para o IK dos braços do NOSSO personagem — os dedos copiam a pegada.
// A Colt fica onde estava a pistola do rig (alinhada pela traseira do ferrolho, escala real) e o
// ferrolho/gatilho dela acompanham os do rig. Sacar e guardar não existem no arquivo: são feitos
// aqui, levando a mão até o coldre na coxa direita e de volta à pose de tiro.

const FLIP = new THREE.Matrix4().makeRotationY(Math.PI); // a câmera do rig olha para +Z; a do jogo, -Z
export const RIG_SCALE = 1.22; // os braços do rig são mais curtos que os do personagem
const DRAW_TIME = 0.8, HOLSTER_TIME = 0.65;
const smooth = (t) => { t = Math.min(1, Math.max(0, t)); return t * t * (3 - 2 * t); };
const damp = (a, b, l, dt) => a + (b - a) * (1 - Math.exp(-l * dt));

const _m = new THREE.Matrix4(), _m2 = new THREE.Matrix4(), _q = new THREE.Quaternion(), _q2 = new THREE.Quaternion();
const _v = new THREE.Vector3(), _s = new THREE.Vector3(), _one = new THREE.Vector3(1, 1, 1), _e = new THREE.Euler();

/** Matriz sem escala (posição + rotação) de um objeto. */
function rigid(o, out = new THREE.Matrix4()) {
  o.matrixWorld.decompose(_v, _q, _s);
  return out.compose(_v, _q, _one);
}
function lerpMatrix(a, b, t, out) {
  const pa = new THREE.Vector3(), qa = new THREE.Quaternion(), pb = new THREE.Vector3(), qb = new THREE.Quaternion();
  a.decompose(pa, qa, _s); b.decompose(pb, qb, _s);
  return out.compose(pa.lerp(pb, t), qa.slerp(qb, t), _one);
}

export class PistolRig {
  constructor(scene) {
    this.scene = scene;
    this.ready = false;
    this.state = 'holstered'; // holstered | drawing | ready | holstering
    this.p = 0;               // 0 = no coldre, 1 = pronta na mão
    this.capacity = 7;
    this.loaded = 7;
    this.reserve = 21;
    this.reloading = null;    // { kind, t, dur, events }
    this.fireCool = 0;
    this.events = [];
    this.muzzleWorld = new THREE.Vector3();
    this.out = {
      wR: 0, wL: 0,
      handR: new THREE.Matrix4(), handL: new THREE.Matrix4(),
      elbowR: new THREE.Vector3(), elbowL: new THREE.Vector3(),
      shoulderR: new THREE.Vector3(), shoulderL: new THREE.Vector3(),
    };
    this.shells = [];
  }

  async load(fpsUrl, coltUrl) {
    const [f, c] = await Promise.all([loadModelFile(fpsUrl), loadModelFile(coltUrl)]);
    let meta = null;
    f.scene.traverse((o) => { if (!meta && o.userData?.meta) meta = o.userData.meta; });
    this.meta = meta;
    const rig = this.rig = f.scene;
    rig.matrixAutoUpdate = false;
    const R = this.R = {};
    rig.traverse((o) => { R[o.name.replace(/_\d+$/, '')] = o; });
    // dados de repouso (antes de qualquer animação), para o personagem calibrar mãos e dedos
    rig.matrix.identity(); rig.updateMatrixWorld(true);
    this.restQ = {}; this.restP = {};
    rig.traverse((o) => { this.restQ[o.name] = o.getWorldQuaternion(new THREE.Quaternion()); this.restP[o.name] = o.getWorldPosition(new THREE.Vector3()); });
    this.camInv = this.R.Head_Cam.matrixWorld.clone().invert();
    // dedos: cada cadeia começa num "metacarpo" (Bone_X004, 008, 012, 016) e o polegar (020)
    const chain = (side, start, n) => Array.from({ length: n }, (_, i) => R[`Bone_${side}${String(start + i).padStart(3, '0')}`]);
    this.fingers = {};
    for (const side of ['L', 'R']) {
      const chains = [4, 8, 12, 16].map((s) => chain(side, s, 4));
      const thumb = chain(side, 20, 3);
      // indicador = o mais perto do polegar; depois médio, anelar, mínimo
      const tp = this.restP[thumb[0].name];
      chains.sort((a, b) => this.restP[a[1].name].distanceTo(tp) - this.restP[b[1].name].distanceTo(tp));
      this.fingers[side] = { Index: chains[0].slice(1), Middle: chains[1].slice(1), Ring: chains[2].slice(1), Pinky: chains[3].slice(1), Thumb: thumb };
    }
    this.mag = rig.getObjectByName('carregador');
    if (this.mag) { this.mag.scale.setScalar(1 / RIG_SCALE); this.mag.castShadow = true; this.mag.frustumCulled = false; }
    rig.traverse((o) => { if (o.isMesh) o.material.envMapIntensity = 0.7; });
    rig.visible = false;
    this.scene.add(rig);

    // animações
    this.mixer = new THREE.AnimationMixer(rig);
    const clip = (n) => f.animations.find((a) => a.name.includes(n));
    const act = (n, loop = true) => {
      const a = this.mixer.clipAction(clip(n));
      if (!loop) { a.setLoop(THREE.LoopOnce, 1); a.clampWhenFinished = true; }
      return a;
    };
    this.A = { idle: act('Idle'), walk: act('Walk'), fire: act('Fire', false), easy: act('Reload_easy', false), full: act('Reload_full', false) };
    this.A.idle.play(); this.A.walk.play(); this.A.walk.weight = 0;

    // Colt
    const gun = this.gun = new THREE.Group();
    gun.matrixAutoUpdate = false;
    gun.add(c.scene);
    c.scene.traverse((o) => {
      if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; o.frustumCulled = false; o.material.envMapIntensity = 0.8; o.material.side = THREE.FrontSide; }
      if (o.isBone) {
        if (/slide/.test(o.name)) this.slideJ = o;
        if (/trigger/.test(o.name)) this.trigJ = o;
      }
    });
    this.scene.add(gun);
    const M = meta.colt;
    this.align = new THREE.Matrix4().fromArray(M.align);
    const inv = this.align.clone().invert();
    this.muzzleLocal = new THREE.Vector3().fromArray(meta.muzzle).applyMatrix4(inv);
    this.ejectLocal = new THREE.Vector3().fromArray(meta.rearSight).lerp(new THREE.Vector3().fromArray(meta.muzzle), 0.35).applyMatrix4(inv);
    this.aPB = new THREE.Vector3().fromArray(meta.aPB);
    this.rifRest = new THREE.Vector3().fromArray(meta.rifRest);
    this.trigRestQ = new THREE.Quaternion().fromArray(meta.trigRestQ);
    this.pmagRest = new THREE.Vector3().fromArray(meta.pmagRest);
    this.slideDir = new THREE.Vector3().fromArray(M.slideDir);
    this.slideRest = new THREE.Vector3().fromArray(M.slideRest);
    this.trigDir = new THREE.Vector3().fromArray(M.trigDir);
    this.trigRest = new THREE.Vector3().fromArray(M.trigRest);

    // pose de referência (parado, olhos na origem olhando -Z): mão direita x arma, mira
    this._place(new THREE.Matrix4());
    this.mixer.setTime(0);
    rig.updateMatrixWorld(true);
    const handR = rigid(R.Hand_R), gunW = this._gunFromRig(new THREE.Matrix4());
    this.gunInHand = handR.clone().invert().multiply(gunW);
    this.handInGun = this.gunInHand.clone().invert();
    // mira (alça e massa): leva a linha de visada ao centro da tela
    const pbW = rigid(R.PBody);
    const rear = new THREE.Vector3().fromArray(meta.rearSight).applyMatrix4(pbW);
    const front = new THREE.Vector3().fromArray(meta.frontSight).applyMatrix4(pbW);
    const dir = front.clone().sub(rear).normalize();
    const up = new THREE.Vector3(0, 1, 0).applyQuaternion(_q.setFromRotationMatrix(pbW)).projectOnPlane(dir).normalize();
    const basisGun = new THREE.Matrix4().makeBasis(dir, up, dir.clone().cross(up));
    const basisCam = new THREE.Matrix4().makeBasis(new THREE.Vector3(0, 0, -1), new THREE.Vector3(0, 1, 0), new THREE.Vector3(0, 0, -1).cross(new THREE.Vector3(0, 1, 0)));
    this.adsQ = new THREE.Quaternion().setFromRotationMatrix(basisCam.multiply(basisGun.transpose()));
    this.adsT = new THREE.Vector3(0, -0.026, -0.3).sub(rear.clone().applyQuaternion(this.adsQ));
    this.adsM = new THREE.Matrix4().compose(this.adsT, this.adsQ, _one);
    // pose "pronta" (sem mirar): a arma sobe um pouco e o cano converge para a mira (~15 m),
    // girando em volta da mão direita
    const lift = new THREE.Vector3(0.015, 0.06, 0.01);
    const muzzleA = new THREE.Vector3().fromArray(meta.muzzle).applyMatrix4(pbW).add(lift);
    const qHip = new THREE.Quaternion().setFromUnitVectors(dir, new THREE.Vector3(0, 0, -15).sub(muzzleA).normalize());
    const grip = new THREE.Vector3().setFromMatrixPosition(handR);
    this.hipM = new THREE.Matrix4().makeTranslation(grip.x + lift.x, grip.y + lift.y, grip.z + lift.z)
      .multiply(new THREE.Matrix4().makeRotationFromQuaternion(qHip)).multiply(new THREE.Matrix4().makeTranslation(-grip.x, -grip.y, -grip.z));
    // tempos da recarga: quando o carregador sai e volta, e quando o ferrolho fecha
    this.reloadEvents = {};
    for (const k of ['easy', 'full']) {
      const a = this.A[k], cl = a.getClip();
      this.mixer.stopAllAction(); a.reset().play();
      let out = -1, back = -1, slide = -1, was = false;
      for (let t = 0; t <= cl.duration; t += 1 / 60) {
        this.mixer.setTime(t); rig.updateMatrixWorld(true);
        const d = this._magOffset();
        if (!was && d > 0.012) { was = true; if (out < 0) out = t; }
        if (was && d < 0.012) { was = false; back = t; }
        if (back > 0 && slide < 0 && this._slideTravel() > -0.004 && t > back + 0.1) slide = t;
      }
      this.reloadEvents[k] = { dur: cl.duration, magOut: Math.max(0.05, out), magIn: back > 0 ? back : cl.duration * 0.65, slide: k === 'full' ? (slide > 0 ? slide : cl.duration * 0.85) : -1 };
    }
    this.mixer.stopAllAction();
    this.A.idle.reset().play(); this.A.walk.reset().play(); this.A.walk.weight = 0;

    // clarão do tiro e luz
    const fc = document.createElement('canvas'); fc.width = fc.height = 64;
    const g = fc.getContext('2d'), rg = g.createRadialGradient(32, 32, 0, 32, 32, 32);
    rg.addColorStop(0, 'rgba(255,250,225,1)'); rg.addColorStop(0.25, 'rgba(255,200,110,0.8)'); rg.addColorStop(1, 'rgba(255,140,40,0)');
    g.fillStyle = rg; g.fillRect(0, 0, 64, 64);
    this.flash = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(fc), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
    this.flash.visible = false;
    this.flashLight = new THREE.PointLight(0xffc27a, 0, 7, 2);
    this.scene.add(this.flash, this.flashLight);
    this.flashT = 0;
    // cápsulas de latão
    this.shellGeo = new THREE.CylinderGeometry(0.0058, 0.0058, 0.023, 8);
    this.shellMat = new THREE.MeshStandardMaterial({ color: 0xc9a14a, metalness: 0.9, roughness: 0.3 });
    this.ready = true;
  }

  /** Coloca o rig: a "câmera" dele no ponto e direção dados (anchor: olhos, olhando -Z). */
  _place(anchor) {
    _m.makeScale(RIG_SCALE, RIG_SCALE, RIG_SCALE);
    this.rig.matrix.copy(anchor).multiply(FLIP).multiply(_m).multiply(this.camInv);
    this.rig.matrixWorld.copy(this.rig.matrix);
  }

  _gunFromRig(out) {
    return rigid(this.R.PBody, out).multiply(this.align);
  }

  /** Quanto o carregador saiu do lugar (m). */
  _magOffset() {
    const pb = this.R.PBody;
    _m.copy(pb.matrixWorld).invert();
    return this.R.Pmag.getWorldPosition(_v).applyMatrix4(_m).distanceTo(this.pmagRest) * RIG_SCALE;
  }

  /** Recuo do ferrolho do rig ao longo do cano (m; negativo = para trás). */
  _slideTravel() {
    return _v.copy(this.R.Rif.position).sub(this.rifRest).dot(this.aPB);
  }

  get busy() { return this.state !== 'ready' || !!this.reloading; }

  draw() {
    if (this.state === 'ready' || this.state === 'drawing') return false;
    this.state = 'drawing';
    this.events.push({ type: 'draw' });
    return true;
  }

  holster() {
    if (this.state === 'holstered' || this.state === 'holstering') return false;
    this.state = 'holstering';
    this.reloading = null;
    this.events.push({ type: 'holster' });
    return true;
  }

  /** 'fired' | 'dry' | null */
  fire() {
    if (this.state !== 'ready' || this.reloading || this.fireCool > 0) return null;
    this.fireCool = 0.14;
    if (this.loaded <= 0) return 'dry';
    this.loaded--;
    const a = this.A.fire;
    a.reset(); a.setEffectiveWeight(1); a.play();
    this.flashT = 0.05;
    this._spawnShell = true;
    return 'fired';
  }

  reload() {
    if (this.state !== 'ready' || this.reloading || this.loaded >= this.capacity || this.reserve <= 0) return false;
    const kind = this.loaded === 0 ? 'full' : 'easy';
    const a = this.A[kind];
    this.A.fire.stop();
    a.reset(); a.setEffectiveWeight(1); a.play();
    this.reloading = { kind, t: 0, ...this.reloadEvents[kind], done: {} };
    return true;
  }

  /**
   * anchor: matriz dos olhos (olhando -Z); holster: matriz da arma no coldre (mundo).
   * move: 0..1 andando; ads: 0..1 mirando; sprint: 0..1 correndo.
   */
  update(dt, { anchor, holster, move = 0, speed = 0, ads = 0, sprint = 0, groundHeight, onClink }) {
    if (!this.ready) return;
    this.fireCool -= dt;
    // sacar / guardar
    if (this.state === 'drawing') { this.p += dt / DRAW_TIME; if (this.p >= 1) { this.p = 1; this.state = 'ready'; } }
    if (this.state === 'holstering') {
      const before = this.p;
      this.p -= dt / HOLSTER_TIME;
      if (before > 0.3 && this.p <= 0.3) this.events.push({ type: 'holstered' });
      if (this.p <= 0) { this.p = 0; this.state = 'holstered'; }
    }
    // animação do rig
    const r = this.reloading;
    if (r) {
      const t0 = r.t; r.t += dt;
      for (const k of ['magOut', 'magIn', 'slide']) if (r[k] >= 0 && t0 < r[k] && r.t >= r[k]) this.events.push({ type: k });
      if (r.t >= r.magIn && !r.done.load) {
        r.done.load = true;
        const n = Math.min(this.capacity - this.loaded, this.reserve);
        this.reserve -= n; this.loaded += n;
      }
      if (r.t >= r.dur) { this.reloading = null; this.A[r.kind].fadeOut(0.15); }
    }
    const mv = move * (1 - ads * 0.75) * (r ? 0.4 : 1);
    this.A.walk.weight = damp(this.A.walk.weight, mv, 8, dt);
    this.A.walk.timeScale = 0.55 + Math.min(1.2, speed * 0.22);
    this.A.idle.weight = 1 - this.A.walk.weight;
    this.mixer.update(dt);

    // posição: olhos + mira (alça e massa) + arma baixa correndo
    this._adsK = damp(this._adsK ?? 0, this.state === 'ready' && !r ? ads : 0, 14, dt);
    this._spr = damp(this._spr ?? 0, sprint, 8, dt);
    const A = _m2.copy(anchor);
    A.multiply(lerpMatrix(this.hipM, this.adsM, this._adsK, _m));
    if (this._spr > 0.001) {
      const k = this._spr;
      A.multiply(_m.compose(_v.set(0.02 * k, -0.06 * k, 0.04 * k), _q.setFromEuler(_e.set(-0.55 * k, 0.42 * k, 0.35 * k)), _one));
    }
    this._place(A);
    this.rig.updateMatrixWorld(true);

    // saída para o IK do personagem
    const o = this.out;
    const R = this.R;
    const rigHandR = rigid(R.Hand_R, this._hr ?? (this._hr = new THREE.Matrix4())), rigHandL = rigid(R.Hand_L, o.handL);
    R.Forearm_R.getWorldPosition(o.elbowR); R.Forearm_L.getWorldPosition(o.elbowL);
    R.UpArm_R.getWorldPosition(o.shoulderR); R.UpArm_L.getWorldPosition(o.shoulderL);
    const p = this.p;
    const gripAtHolster = _m.copy(holster).multiply(this.handInGun);
    let gunM;
    if (p <= 0.3) {
      // a mão vai até o coldre (o IK entra devagar a partir da pose do corpo)
      o.wR = smooth(p / 0.3);
      o.handR.copy(gripAtHolster);
      gunM = holster;
    } else {
      // puxa a arma do coldre e traz para a frente, num arco (sobe rente ao corpo)
      const q = smooth((p - 0.3) / 0.7);
      o.wR = 1;
      lerpMatrix(gripAtHolster, rigHandR, q, o.handR);
      if (q < 1) {
        _v.setFromMatrixPosition(o.handR);
        _v.y += Math.sin(q * Math.PI) * 0.1;
        o.handR.setPosition(_v);
        gunM = new THREE.Matrix4().copy(o.handR).multiply(this.gunInHand);
      } else {
        gunM = this._gunFromRig(new THREE.Matrix4());
      }
    }
    o.wL = smooth((p - 0.7) / 0.3);
    this.gun.matrix.copy(gunM);
    this.gun.matrixWorld.copy(gunM);
    this.gun.updateMatrixWorld(true);
    this.muzzleWorld.copy(this.muzzleLocal).applyMatrix4(gunM);

    // ferrolho, gatilho e carregador acompanham o rig (só com a arma na mão)
    const inHand = p >= 1;
    const travel = inHand ? this._slideTravel() : 0;
    if (this.slideJ) this.slideJ.position.copy(this.slideRest).addScaledVector(this.slideDir, travel * this.meta.colt.slideScale);
    if (this.trigJ) {
      const ang = inHand ? R.Trigger.quaternion.angleTo(this.trigRestQ) : 0;
      this.trigJ.position.copy(this.trigRest).addScaledVector(this.trigDir, -0.004 * Math.min(1, ang / 0.3) * this.meta.colt.trigScale);
    }
    this.rig.visible = true;
    if (this.mag) this.mag.visible = inHand && this._magOffset() > 0.012;

    // clarão
    this.flashT -= dt;
    const fl = this.flashT > 0;
    this.flash.visible = fl;
    this.flashLight.intensity = fl ? 30 : 0;
    if (fl) {
      this.flash.position.copy(this.muzzleWorld);
      this.flash.scale.setScalar(0.12 + Math.random() * 0.08);
      this.flash.material.rotation = Math.random() * 6.3;
      this.flashLight.position.copy(this.muzzleWorld);
    }
    // cápsula ejetada para a direita
    if (this._spawnShell) {
      this._spawnShell = false;
      let s = this.shells.find((x) => !x.alive);
      if (!s) { s = { m: new THREE.Mesh(this.shellGeo, this.shellMat), v: new THREE.Vector3(), w: new THREE.Vector3() }; s.m.castShadow = true; this.scene.add(s.m); this.shells.push(s); }
      s.alive = true; s.life = 6; s.bounced = 0;
      s.m.visible = true;
      s.m.position.copy(this.ejectLocal).applyMatrix4(gunM);
      _q.setFromRotationMatrix(gunM);
      s.v.set(1.6 + Math.random() * 0.6, 1.5 + Math.random() * 0.6, 0.3).applyQuaternion(_q2.setFromRotationMatrix(anchor));
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
      const gy = groundHeight ? groundHeight(s.m.position.x, s.m.position.z) + 0.006 : -Infinity;
      if (s.m.position.y < gy) {
        s.m.position.y = gy;
        s.v.y = Math.abs(s.v.y) * 0.3; s.v.x *= 0.4; s.v.z *= 0.4; s.w.multiplyScalar(0.5);
        if (s.bounced++ === 0) onClink?.(s.m.position);
        if (s.bounced > 2) { s.m.rotation.set(Math.PI / 2, Math.random() * 6, 0); }
      }
    }
  }
}
