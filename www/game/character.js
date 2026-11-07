// Personagem: Quaternius "Universal Base Characters" + "Universal Animation Library" (CC0), esqueleto UE-Mannequin.
// Locomoção por blend de clipes, IK de pernas (terreno) e braços (ferramenta), torção/inclinação do tronco pela mira.
import { Skeleton } from '../engine/anim.js';
import { m4, q4, clamp, lerp, smoothstep, angleDiff, damp } from '../engine/math.js';

const REGION = { skin: 0, torso: 1, arms: 2, legs: 3, feet: 4, hands: 5, head: 6 };
function regionOf(name) {
  if (/^(Head|neck)/i.test(name)) return REGION.head;
  if (/hand|thumb|index|middle|ring|pinky/i.test(name)) return REGION.hands;
  if (/clavicle|upperarm|lowerarm/i.test(name)) return REGION.arms;
  if (/foot|ball/i.test(name)) return REGION.feet;
  if (/thigh|calf/i.test(name)) return REGION.legs;
  return REGION.torso;
}
const NODES = {
  Hips: 'pelvis', Spine: 'spine_01', Spine1: 'spine_02', Spine2: 'spine_03', Neck: 'neck_01', Head: 'Head',
  LeftArm: 'upperarm_l', LeftForeArm: 'lowerarm_l', LeftHand: 'hand_l', RightArm: 'upperarm_r', RightForeArm: 'lowerarm_r', RightHand: 'hand_r',
  LeftUpLeg: 'thigh_l', LeftLeg: 'calf_l', LeftFoot: 'foot_l', RightUpLeg: 'thigh_r', RightLeg: 'calf_r', RightFoot: 'foot_r', LeftToe: 'ball_l', RightToe: 'ball_r',
};

export class Character {
  constructor(game, row = 0) {
    this.g = game; this.row = row;
    this.pos = [0, 0, 0]; this.bodyYaw = 0; this.phase = 0; this.speedSm = 0;
    this.fp = false; this.hidden = false;
    this.regionTints = new Float32Array(24).fill(1);
    this.charM = m4.create(); this.airT = 0; this.landT = 0;
    this.deadT = 0; this.equip = {}; this.spineQ = q4.create();
  }
  async init() {
    this.gltf = await this.g.assets.loadCharacter(Character.onPrimitive);
    return this;
  }
  // cores por região (para tingir roupas) a partir do osso dominante de cada vértice
  static onPrimitive(d, gltf) {
    if (!d.joints) return;
    const names = gltf.json.skins[0].joints.map((j) => gltf.json.nodes[j].name || '');
    const n = d.positions.length / 3, colors = new Uint8Array(n * 4);
    for (let i = 0; i < n; i++) {
      let best = 0, bw = -1;
      for (let k = 0; k < 4; k++) { const w = d.weights[i * 4 + k]; if (w > bw) { bw = w; best = d.joints[i * 4 + k]; } }
      colors[i * 4] = 255; colors[i * 4 + 1] = regionOf(names[best]); colors[i * 4 + 2] = 128; colors[i * 4 + 3] = 255;
    }
    d.colors = colors;
  }

  setup() {
    const gltf = this.gltf, s = this.skel = new Skeleton(gltf, 0);
    for (const m of gltf.materials) { m.tint = true; m.regionTints = this.regionTints; m.refreshKey(); m.rough = Math.max(m.rough, 0.7); }
    this.n = {};
    for (const [k, v] of Object.entries(NODES)) { this.n[k] = s.node(v); if (this.n[k] === undefined) console.warn('osso ausente', v); }
    // orientação do esqueleto: descobre para onde os pés apontam e corrige para +Z
    s.resetPose(); s.fk();
    const f = s.pos(this.n.LeftFoot, [0, 0, 0]), t = s.pos(this.n.LeftToe, [0, 0, 0]);
    s.base = m4.rotationY(m4.create(), -Math.atan2(t[0] - f[0], t[2] - f[2]));
    s.fk();
    this.parts = [];
    gltf.nodes.forEach((n) => { if (n.mesh !== undefined) for (const p of gltf.meshes[n.mesh]) this.parts.push({ mesh: p.mesh, material: p.material }); });
    this.setEquipment({});
  }

  setEquipment(slots) {
    const t = this.regionTints, tint = (it, def) => (it && it.def.tint ? it.def.tint.map((c) => c * 1.25) : def);
    const set = (reg, c) => { t[reg * 3] = c[0]; t[reg * 3 + 1] = c[1]; t[reg * 3 + 2] = c[2]; };
    set(REGION.skin, [1, 1, 1]); set(REGION.hands, [1, 1, 1]); set(REGION.head, [1, 1, 1]);
    set(REGION.torso, tint(slots.body, [0.42, 0.45, 0.4])); set(REGION.arms, tint(slots.body, [0.42, 0.45, 0.4]));
    set(REGION.legs, tint(slots.legs, [0.2, 0.22, 0.26])); set(REGION.feet, slots.feet ? [0.2, 0.17, 0.12] : [0.12, 0.12, 0.13]);
    this.equip = slots;
  }

  // mistura sequencial de clipes: [clip, fase(0..1) ou segundos(abs), peso, abs]
  _blend(list) {
    const s = this.skel; let acc = 0, first = true;
    for (const [clip, t, w, abs] of list) {
      const c = s.clips[clip];
      if (w <= 0.001 || !c) continue;
      const time = abs ? t % c.duration : (((t % 1) + 1) % 1) * c.duration;
      acc += w;
      s.sample(c, time, first ? 1 : w / acc);
      first = false;
    }
    if (first) s.sample('Idle_Loop', 0, 1);
  }

  // st: { pos, aimYaw, aimPitch, vel:[x,z], stance:0|1, fp, swimming, grounded, vehicle, vehicleYaw, weapon:{rh,lh}|null, dead, action:{clip,t}|null }
  update(dt, st) {
    const s = this.skel, N = this.n, g = this.g;
    this.fp = st.fp; this.pos = st.pos;
    const speed = Math.hypot(st.vel[0], st.vel[1]);
    this.speedSm = damp(this.speedSm, speed, 10, dt);
    // yaw do corpo segue o movimento; o tronco torce para a mira
    const moveYaw = speed > 0.3 ? Math.atan2(-st.vel[0], -st.vel[1]) : st.aimYaw;
    const rel = angleDiff(st.aimYaw, moveYaw);
    let reverse = false, targetBody = st.aimYaw;
    if (speed > 0.3 && !st.vehicle) {
      if (Math.abs(rel) > Math.PI * 0.62) { reverse = true; targetBody = st.aimYaw + (rel > 0 ? rel - Math.PI : rel + Math.PI) * 0.6; }
      else targetBody = st.aimYaw + clamp(rel, -1.1, 1.1) * 0.8;
    }
    if (st.vehicle) targetBody = st.vehicleYaw ?? st.aimYaw;
    if (speed > 0.3 || st.vehicle || Math.abs(angleDiff(this.bodyYaw, st.aimYaw)) > 1.0) this.bodyYaw += angleDiff(this.bodyYaw, targetBody) * Math.min(1, dt * (st.vehicle ? 20 : speed > 0.3 ? 9 : 6));
    const twist = st.vehicle ? 0 : clamp(angleDiff(this.bodyYaw, st.aimYaw), -1.5, 1.5);

    // estados no ar / pouso / morte
    if (!st.grounded && !st.swimming) this.airT += dt; else { if (this.airT > 0.3 && st.grounded) this.landT = 0.45; this.airT = 0; }
    this.landT = Math.max(0, this.landT - dt);
    this.deadT = st.dead ? this.deadT + dt : 0;

    // ---------------- pose base (clipes da Universal Animation Library)
    const stride = lerp(1.7, 3.4, smoothstep(1.6, 4.8, speed));
    this.phase += dt * (this.speedSm / stride) * (reverse ? -1 : 1);
    const ph = this.phase, v = this.speedSm, C = s.clips;
    s.resetPose(); s.clearHooks();
    let plain = false;
    if (st.dead && C.Death01) { this._blend([['Death01', Math.min(this.deadT, C.Death01.duration - 0.03), 1, true]]); plain = true; }
    else if (st.vehicle) { this._blend([['Driving_Loop', g.time, 1, true]]); plain = true; }
    else if (st.swimming) { const wf = smoothstep(0.3, 1.0, v); this._blend([['Swim_Idle_Loop', g.time * 0.8, 1 - wf, true], ['Swim_Fwd_Loop', g.time * 0.9, wf, true]]); plain = true; }
    else if (!st.grounded && this.airT > 0.12) { this._blend([[this.airT < 0.3 ? 'Jump_Start' : 'Jump_Loop', this.airT < 0.3 ? this.airT : g.time, 1, true]]); plain = true; }
    else if (this.landT > 0 && v < 2.2) { this._blend([['Jump_Land', 0.45 - this.landT, 1, true]]); plain = true; }
    else if (st.action && st.action.clip && v < 1.0 && C[st.action.clip]) this._blend([[st.action.clip, st.action.t, 1, true]]);
    else if (st.stance === 1) {
      const wm = smoothstep(0.2, 1.0, v);
      this._blend([['Crouch_Idle_Loop', g.time * 0.5, 1 - wm, true], ['Crouch_Fwd_Loop', ph * 0.8, wm, false]]);
    } else {
      const wSp = smoothstep(4.7, 5.6, v), wJog = smoothstep(2.4, 3.2, v) * (1 - wSp), wWalk = smoothstep(0.12, 0.9, v) * (1 - wJog - wSp), wIdle = Math.max(0, 1 - wWalk - wJog - wSp);
      this._blend([['Idle_Loop', g.time * 0.35, wIdle, true], ['Walk_Loop', ph, wWalk, false], ['Jog_Fwd_Loop', ph, wJog, false], ['Sprint_Loop', ph, wSp, false]]);
    }
    if (st.fp) s.hide.add(N.Head); else s.hide.delete(N.Head);
    // ---------------- tronco: torção e inclinação para a mira
    const pitch = clamp(st.aimPitch, -1.2, 1.2);
    const spineQ = q4.create();
    if (!plain) {
      const wts = [0.25, 0.35, 0.4];
      [N.Spine, N.Spine1, N.Spine2].forEach((n, i) => {
        const q = q4.mul(new Float32Array(4), q4.axisAngle(new Float32Array(4), 0, 1, 0, twist * wts[i]), q4.axisAngle(new Float32Array(4), -1, 0, 0, pitch * wts[i] * 0.85));
        s.setHook(n, { delta: q }); q4.mul(spineQ, q, spineQ);
      });
      s.setHook(N.Head, { delta: q4.axisAngle(new Float32Array(4), -1, 0, 0, pitch * 0.15) });
    }
    this.spineQ = spineQ;
    s.fk();
    // ---------------- IK de pernas (pés acompanham o relevo)
    const cM = this.computeCharM(st), inv = m4.invert(m4.create(), cM);
    const toW = (p) => m4.transformPoint([0, 0, 0], cM, p), toS = (p) => m4.transformPoint([0, 0, 0], inv, p);
    if (!plain) {
      const doLeg = (up, mid, end) => {
        const ft = s.pos(end, [0, 0, 0]), fw = toW(ft), gy = g.phys.groundAt(fw[0], fw[2], st.pos[1] + 0.6, 0.6);
        s.solveTwoBone(up, mid, end, toS([fw[0], st.pos[1] + ft[1] + (gy - st.pos[1]) * (st.grounded ? 1 : 0), fw[2]]), [0, 0.12, 1]);
      };
      const lf = s.pos(N.LeftFoot, [0, 0, 0]), rf = s.pos(N.RightFoot, [0, 0, 0]);
      // alvos calculados antes de alterar qualquer perna
      const tl = (() => { const fw = toW(lf), gy = g.phys.groundAt(fw[0], fw[2], st.pos[1] + 0.6, 0.6); return toS([fw[0], st.pos[1] + lf[1] + (gy - st.pos[1]) * (st.grounded ? 1 : 0), fw[2]]); })();
      const tr = (() => { const fw = toW(rf), gy = g.phys.groundAt(fw[0], fw[2], st.pos[1] + 0.6, 0.6); return toS([fw[0], st.pos[1] + rf[1] + (gy - st.pos[1]) * (st.grounded ? 1 : 0), fw[2]]); })();
      s.solveTwoBone(N.LeftUpLeg, N.LeftLeg, N.LeftFoot, tl, [0, 0.12, 1]);
      s.solveTwoBone(N.RightUpLeg, N.RightLeg, N.RightFoot, tr, [0, 0.12, 1]);
    }
    // ---------------- IK de braços (ferramenta/objeto nas mãos)
    if (st.weapon) {
      const w = st.weapon;
      s.solveTwoBone(N.RightArm, N.RightForeArm, N.RightHand, toS(w.rh), [-0.55, -1, 0.1]);
      if (w.lh) s.solveTwoBone(N.LeftArm, N.LeftForeArm, N.LeftHand, toS(w.lh), [0.6, -1, 0.1]);
    }
    s.fk();
    g.r.setBones(this.row, s.computeJoints());
    this.charM = cM;
  }

  computeCharM(st) {
    const m = this.charM, q = q4.fromEuler(new Float32Array(4), this.bodyYaw + Math.PI, 0, 0);
    m4.fromTRS(m, [this.pos[0], st.swimming ? this.g.phys.waterY - 1.05 : this.pos[1], this.pos[2]], q, null);
    return m;
  }

  attach(node, offset, rotQ) {
    const s = this.skel, p = s.pos(node, [0, 0, 0]), q = rotQ || q4.create(), o = q4.rotate([0, 0, 0], q, offset);
    return m4.multiply(m4.create(), this.charM, m4.fromTRS(m4.create(), [p[0] + o[0], p[1] + o[1], p[2] + o[2]], q, null));
  }

  draw(r) {
    for (const p of this.parts) {
      if (this.fp && /Hair|Eye/i.test(p.material.name || '')) continue;   // em 1ª pessoa a cabeça fica oculta (cabelo/olhos não podem colapsar na câmera)
      r.draw(p.mesh, p.material, { model: this.charM, skinRow: this.row });
    }
    const eq = this.equip || {};
    if (this.fp || !this.g.level) return;
    // chapéu e máscara: modelos CC0 do Poly Haven presos à cabeça
    const hat = eq.head && eq.head.def.model === 'fishermans_hat' ? this.g.level.model('fishermans_hat') : null;
    if (hat) { const m = this.attach(this.n.Head, [0, 0.1, 0.0], this.spineQ); for (const p of hat.parts) r.draw(p.mesh, p.material, { model: m }); }
    const mask = eq.face && eq.face.def.model === 'old_gas_mask' ? this.g.level.model('old_gas_mask') : null;
    if (mask) { const m = this.attach(this.n.Head, [0, 0.07, 0.08], this.spineQ); for (const p of mask.parts) r.draw(p.mesh, p.material, { model: m }); }
  }
}
