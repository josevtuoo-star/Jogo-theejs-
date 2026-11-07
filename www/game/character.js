// Personagem: Soldier (CC/Mixamo) com esqueleto, blend de animações, IK e roupas por região.
import { Skeleton } from '../engine/anim.js';
import { Material } from '../engine/renderer.js';
import { MeshBuilder } from '../engine/gl.js';
import { m4, q4, v3, clamp, lerp, smoothstep, angleDiff, damp } from '../engine/math.js';
import { MAT } from './assets.js';

const REGION = { skin: 0, torso: 1, arms: 2, legs: 3, feet: 4, hands: 5, head: 6 };
function regionOf(name) {
  name = name.replace('mixamorig:', '');
  if (/Head|Neck/.test(name)) return REGION.head;
  if (/Hand/.test(name)) return REGION.hands;
  if (/Arm|Shoulder/.test(name)) return REGION.arms;
  if (/Foot|Toe/.test(name)) return REGION.feet;
  if (/Leg/.test(name)) return REGION.legs;
  return REGION.torso;
}

export class Character {
  constructor(game, row = 0) {
    this.g = game; this.row = row;
    this.pos = [0, 0, 0]; this.bodyYaw = 0; this.phase = 0; this.speedSm = 0;
    this.crouchT = 0; this.proneT = 0; this.fp = false;
    this.hips = null; this.regionTints = new Float32Array(24).fill(1);
    this.accessories = {};
    this._q = new Float32Array(4);
    this.charM = m4.create();
    this.moveBlend = [0, 0, 0];
    this.reload = 0;
  }

  async init() {
    const g = this.g;
    const gltf = await g.assets.loadSoldier(Character.onPrimitive);
    this.gltf = gltf;
    return this;
  }

  // chamado pelo loader (assets.loadSoldier) para gerar cores por região
  static onPrimitive(d, gltf) {
    if (!d.joints) return;
    let maxJ = 0; for (let i = 0; i < d.joints.length; i++) if (d.joints[i] > maxJ) maxJ = d.joints[i];
    const n = d.positions.length / 3;
    const colors = new Uint8Array(n * 4);
    if (maxJ < 4) { for (let i = 0; i < n; i++) { colors[i * 4] = 255; colors[i * 4 + 1] = 0; colors[i * 4 + 2] = 128; colors[i * 4 + 3] = 255; } d.colors = colors; return; }
    const names = gltf.json.skins[0].joints.map((j) => gltf.json.nodes[j].name || '');
    for (let i = 0; i < n; i++) {
      let best = 0, bw = -1;
      for (let k = 0; k < 4; k++) { const w = d.weights[i * 4 + k]; if (w > bw) { bw = w; best = d.joints[i * 4 + k]; } }
      colors[i * 4] = 255; colors[i * 4 + 1] = regionOf(names[best]); colors[i * 4 + 2] = 128; colors[i * 4 + 3] = 255;
    }
    d.colors = colors;
  }

  setup() {
    const gltf = this.gltf, g = this.g;
    this.skel = new Skeleton(gltf, 0);
    this.skin2 = gltf.skins[1] || null;
    this.joints2 = new Float32Array((this.skin2 ? this.skin2.joints.length : 1) * 16);
    // materiais com tinta por região
    for (const m of gltf.materials) { m.tint = true; m.regionTints = this.regionTints; m.refreshKey(); m.rough = 0.85; }
    // nós usados
    const s = this.skel;
    this.n = {};
    for (const k of ['Hips', 'Spine', 'Spine1', 'Spine2', 'Neck', 'Head', 'LeftArm', 'LeftForeArm', 'LeftHand', 'RightArm', 'RightForeArm', 'RightHand', 'LeftUpLeg', 'LeftLeg', 'LeftFoot', 'RightUpLeg', 'RightLeg', 'RightFoot', 'LeftToeBase', 'RightToeBase']) this.n[k] = s.node(k);
    // pés: referência de repouso em espaço do esqueleto
    // meshes
    this.parts = [];
    gltf.nodes.forEach((n) => { if (n.mesh !== undefined) for (const p of gltf.meshes[n.mesh]) this.parts.push({ mesh: p.mesh, material: p.material, skin: n.skin ?? 0 }); });
    this.buildAccessories();
    this.setEquipment({});
    // distribuição de peso dos clipes
    this.clipNames = Object.keys(s.clips);
  }

  buildAccessories() {
    const gl = this.g.r.gl;
    const bp = (w, h, d, big) => {
      const b = new MeshBuilder();
      b.box(-w / 2, -h / 2, -d / 2, w / 2, h / 2, d / 2, 0, { uvScale: 1 });
      b.box(-w * 0.4, -h * 0.5, -d * 0.5 - 0.06, w * 0.4, -h * 0.05, -d * 0.5, 0, { uvScale: 1 });
      b.box(-w * 0.52, -h * 0.35, -d * 0.2, -w * 0.5, h * 0.1, d * 0.2, 0, {});
      b.box(w * 0.5, -h * 0.35, -d * 0.2, w * 0.52, h * 0.1, d * 0.2, 0, {});
      if (big) b.box(-w * 0.45, h * 0.45, -d * 0.45, w * 0.45, h * 0.55, d * 0.45, 0, {});
      return b.build(gl);
    };
    this.meshes = { small: bp(0.32, 0.4, 0.2, false), big: bp(0.4, 0.62, 0.26, true) };
    // capacete
    const hb = new MeshBuilder(), seg = 10, rows = 5;
    for (let j = 0; j < rows; j++) for (let i = 0; i <= seg; i++) {
      const a = i / seg * Math.PI * 2, e0 = j / rows * Math.PI / 2, e1 = (j + 1) / rows * Math.PI / 2, R = 0.125;
      if (i === 0) continue;
      const p = (aa, e) => [Math.cos(aa) * Math.cos(e) * R, Math.sin(e) * R * 0.95, Math.sin(aa) * Math.cos(e) * R * 1.1];
      const a0 = (i - 1) / seg * Math.PI * 2;
      const P00 = p(a0, e0), P10 = p(a, e0), P01 = p(a0, e1), P11 = p(a, e1);
      const n = (P) => { const l = Math.hypot(...P) || 1; return [P[0] / l, P[1] / l, P[2] / l]; };
      const f = hb.vcount;
      [P00, P10, P11, P01].forEach((P) => { const nn = n(P); hb.vert(P[0], P[1], P[2], nn[0], nn[1], nn[2], 0, 0, 255, 0, 128, 0); });
      hb.quad(f, f + 1, f + 2, f + 3); hb.quad(f, f + 3, f + 2, f + 1);
    }
    this.meshes.helmet = hb.build(gl);
    this.matAcc = new Material({ color: [0.3, 0.3, 0.3, 1], rough: 0.8, vcolorAO: false, doubleSided: true });
    this.matAcc2 = new Material({ layered: true, rough: 0.9, vcolorAO: false, doubleSided: true, color: [1, 1, 1, 1] });
  }

  // equipment: mapa slot->item
  setEquipment(slots) {
    const t = this.regionTints;
    const col = (it, def = [1, 1, 1]) => (it && it.def.tint ? it.def.tint.map((c) => c * 1.25) : def);
    const set = (reg, c) => { t[reg * 3] = c[0]; t[reg * 3 + 1] = c[1]; t[reg * 3 + 2] = c[2]; };
    set(REGION.skin, [1, 1, 1]);
    set(REGION.torso, col(slots.body, [0.55, 0.6, 0.55])); set(REGION.arms, col(slots.body, [0.55, 0.6, 0.55]));
    set(REGION.legs, col(slots.legs, [0.5, 0.5, 0.5])); set(REGION.feet, slots.feet ? [0.35, 0.3, 0.2] : [0.5, 0.5, 0.5]);
    set(REGION.hands, [1, 1, 1]); set(REGION.head, [1, 1, 1]);
    this.equip = slots;
  }

  // ---------------------------------------------------------------- por frame
  // st: { pos, aimYaw, aimPitch, vel:[x,z], stance:0|1|2, fp, swimming, grounded, weapon:{rh,lh,q}|null, lean, dead }
  update(dt, st) {
    const s = this.skel, N = this.n, g = this.g;
    this.fp = st.fp;
    this.pos = st.pos;
    const speed = Math.hypot(st.vel[0], st.vel[1]);
    this.speedSm = damp(this.speedSm, speed, 10, dt);
    // direção do movimento relativa à mira
    const moveYaw = speed > 0.3 ? Math.atan2(-st.vel[0], -st.vel[1]) : st.aimYaw; // yaw da velocidade (forward=-z)
    let rel = angleDiff(st.aimYaw, moveYaw);
    let reverse = false;
    let targetBody;
    if (speed > 0.3 && !st.prone) {
      if (Math.abs(rel) > Math.PI * 0.62) { reverse = true; targetBody = st.aimYaw + (rel > 0 ? rel - Math.PI : rel + Math.PI) * 0.6; }
      else targetBody = st.aimYaw + clamp(rel, -1.1, 1.1) * 0.8;
    } else targetBody = st.aimYaw;
    const diff = angleDiff(this.bodyYaw, targetBody);
    if (speed > 0.3 || Math.abs(angleDiff(this.bodyYaw, st.aimYaw)) > 1.0) this.bodyYaw += diff * Math.min(1, dt * (speed > 0.3 ? 9 : 6));
    if (st.prone) this.bodyYaw = st.aimYaw;
    const twist = clamp(angleDiff(this.bodyYaw, st.aimYaw), -1.5, 1.5);

    // estado de pose: stance
    this.crouchT = damp(this.crouchT, st.stance === 1 ? 1 : 0, 9, dt);
    this.proneT = damp(this.proneT, st.stance === 2 ? 1 : 0, 6, dt);

    // fase do ciclo
    const stride = lerp(1.35, 3.1, smoothstep(1.6, 4.5, speed));
    this.phase += dt * (this.speedSm / stride) * (reverse ? -1 : 1);
    const wRun = smoothstep(2.4, 3.9, this.speedSm) * (1 - this.proneT * 0.5);
    const wWalk = smoothstep(0.12, 0.9, this.speedSm) * (1 - wRun);
    const wIdle = Math.max(0, 1 - wRun - wWalk);

    s.resetPose(); s.clearHooks();
    const ph = ((this.phase % 1) + 1) % 1;
    const clips = s.clips;
    // idle sempre como base, depois mistura walk e run
    s.sample('Idle', g.time * 0.5 % clips.Idle.duration, 1);
    if (wWalk > 0.01) s.sample('Walk', ph * clips.Walk.duration, wWalk + wRun * 0.0);
    if (wRun > 0.01) s.sample('Run', ph * clips.Run.duration, Math.min(1, wRun / Math.max(wRun + wWalk * 0.2, 0.01)));
    // translação do quadril: remover movimento horizontal (root motion)
    const hipsN = N.Hips;
    this.hipsRest = this.hipsRest || [s.restT[hipsN * 3], s.restT[hipsN * 3 + 1], s.restT[hipsN * 3 + 2]];
    // FK pass A (sem ganchos): posições do pé na animação
    s.fk();
    const footA = { L: s.pos(N.LeftFoot, [0, 0, 0]), R: s.pos(N.RightFoot, [0, 0, 0]) };
    const hipsA = s.pos(N.Hips, [0, 0, 0]);
    // remove deriva horizontal do quadril da animação (fica centrado)
    const driftX = hipsA[0], driftZ = hipsA[2];
    // ganchos: quadril abaixa ao agachar
    const crouchDrop = 0.42 * this.crouchT + (st.swimming ? 0.35 : 0);
    s.setOffset(hipsN, [-driftX * 0.9, -crouchDrop, -driftZ * 0.9 + 0.08 * this.crouchT]);
    // torso: pitch e torção distribuídos
    const pitch = clamp(st.aimPitch, -1.3, 1.3) * (1 - this.proneT * 0.4);
    const lean = (st.lean || 0) * 0.25;
    const sp = [N.Spine, N.Spine1, N.Spine2];
    const wts = [0.25, 0.35, 0.4];
    let accQ = q4.create();
    const spineQs = [];
    sp.forEach((n, i) => {
      const qy = q4.axisAngle(new Float32Array(4), 0, 1, 0, twist * wts[i]);
      const qp = q4.axisAngle(new Float32Array(4), -1, 0, 0, pitch * wts[i] * 0.85);
      const ql = q4.axisAngle(new Float32Array(4), 0, 0, 1, lean * wts[i]);
      const q = q4.mul(new Float32Array(4), q4.mul(new Float32Array(4), qy, ql), qp);
      s.setHook(n, { delta: q });
      q4.mul(accQ, q, accQ);
    });
    this.spineQ = accQ;
    // cabeça: olha na direção da mira (parte do pitch restante)
    s.setHook(N.Head, { delta: q4.axisAngle(new Float32Array(4), -1, 0, 0, pitch * 0.15) });
    if (st.fp) { s.hide.add(N.Head); } else s.hide.delete(N.Head);
    // FK pass B
    s.fk();
    // IK de pernas (terreno)
    const ground = (x, z) => g.phys.groundAt(x, z, st.pos[1] + 0.6, 0.6);
    const cM = this.computeCharM(st);
    const inv = m4.invert(m4.create(), cM);
    const toW = (p) => m4.transformPoint([0, 0, 0], cM, p);
    const toS = (p) => m4.transformPoint([0, 0, 0], inv, p);
    const ankle = 0.095;
    const doLeg = (up, mid, end, foot) => {
      const fw = toW(foot);
      const gy = ground(fw[0], fw[2]);
      const lift = Math.max(0, foot[1] - 0.04);              // altura do pé na animação (acima do chão do esqueleto)
      let ty = st.grounded || st.swimming === false ? gy + ankle + lift * 0.0 : fw[1];
      // mantém a altura da animação em relação ao chão base, somando o relevo
      const base = st.pos[1];
      ty = base + foot[1] + (gy - base) * (st.grounded ? 1 : 0.0);
      if (st.swimming) ty = fw[1];
      const target = toS([fw[0], ty, fw[2]]);
      s.solveTwoBone(up, mid, end, target, [0, 0.12, 1], { weight: st.prone ? 0 : 1 });
    };
    doLeg(N.LeftUpLeg, N.LeftLeg, N.LeftFoot, footA.L);
    doLeg(N.RightUpLeg, N.RightLeg, N.RightFoot, footA.R);
    // IK de braços (arma)
    if (st.weapon) {
      const w = st.weapon;
      const rh = toS(w.rh), lh = w.lh ? toS(w.lh) : null;
      s.solveTwoBone(N.RightArm, N.RightForeArm, N.RightHand, rh, [-0.55, -1, -0.15]);
      if (lh) s.solveTwoBone(N.LeftArm, N.LeftForeArm, N.LeftHand, lh, [0.6, -1, -0.15]);
      // orientação das mãos acompanha a arma (espaço do esqueleto)
      if (w.q) {
        const invQ = q4.conj(new Float32Array(4), q4.fromEuler(new Float32Array(4), this.charYaw, 0, 0));
        const qs = q4.mul(new Float32Array(4), invQ, w.q);
        s.setAbs(N.RightHand, q4.mul(new Float32Array(4), qs, w.rhOff || q4.create()));
        if (lh) s.setAbs(N.LeftHand, q4.mul(new Float32Array(4), qs, w.lhOff || q4.create()));
      }
    }
    s.fk();
    // ossos para o shader
    const out = s.computeJoints();
    g.r.setBones(this.row, out);
    if (this.skin2) { s.jointsFor(this.skin2, this.joints2); g.r.setBones(this.row + 1, this.joints2); }
    this.charM = cM;
    this.headPos = s.pos(N.Head, [0, 0, 0]);
  }

  computeCharM(st) {
    const m = this.charM, yaw = this.bodyYaw + Math.PI;
    this.charYaw = yaw;
    const p = this.proneT;
    const q = q4.fromEuler(new Float32Array(4), yaw, p * Math.PI / 2 * 0.97, 0);
    // quando deitado, o ponto de referência fica no centro do corpo
    const fwd = [-Math.sin(this.bodyYaw), 0, -Math.cos(this.bodyYaw)];
    const off = p * 0.92;
    m4.fromTRS(m, [this.pos[0] + fwd[0] * off * 0.0 - fwd[0] * 0.0, this.pos[1] + p * 0.12, this.pos[2]], q, null);
    // desloca para trás (pés ficam atrás) quando deitado
    m[12] -= fwd[0] * p * 0.0;
    return m;
  }

  // matriz de anexo: posição de um nó + rotação base (character space)
  attach(node, offset, rotQ, out) {
    const s = this.skel, cM = this.charM;
    const p = s.pos(node, [0, 0, 0]);
    const q = rotQ || q4.create();
    const o = q4.rotate([0, 0, 0], q, offset);
    const m = m4.create();
    m4.fromTRS(m, [p[0] + o[0], p[1] + o[1], p[2] + o[2]], q, null);
    return m4.multiply(out || m4.create(), cM, m);
  }

  draw(r, shadow, opts = {}) {
    if (this.fp && shadow === false && !opts.showBody) { /* corpo sempre desenhado (cabeça escondida) */ }
    const M = this.charM;
    for (const p of this.parts) r.draw(p.mesh, p.material, { model: M, skinRow: this.row + (p.skin === 1 ? 1 : 0) });
    // acessórios
    const eq = this.equip || {};
    const spineQ = this.spineQ || q4.create();
    if (eq.back && eq.back.def.pack) {
      const big = eq.back.def.pack === 'big';
      const m = this.attach(this.n.Spine2, [0, 0.0, big ? -0.24 : -0.2], spineQ);
      const mat = this.matAcc2; mat.color = [...eq.back.def.tint.map((c) => c * 2.2), 1];
      r.draw(this.meshes[big ? 'big' : 'small'], mat, { model: m });
    }
    if (eq.vest && !this.fp) {
      const m = this.attach(this.n.Spine2, [0, -0.02, 0.0], spineQ);
      this.matAcc.color = [...eq.vest.def.tint.map((c) => c * 1.5), 1];
      // colete simples: caixa em torno do tronco
      if (!this.vestMesh) { const b = new MeshBuilder(); b.box(-0.2, -0.22, -0.13, 0.2, 0.2, 0.15, 0, {}); this.vestMesh = b.build(this.g.r.gl); }
      r.draw(this.vestMesh, this.matAcc, { model: m });
    }
    if (!this.fp) {
      if (eq.head && eq.head.id === 'helmet') {
        const m = this.attach(this.n.Head, [0, 0.12, 0.02], this.skel.worldQuat(this.n.Head));
        const q = this.skel.worldQuat(this.n.Head);
        // o osso da cabeça tem eixo Y para cima; o capacete é simétrico
        this.matAcc.color = [...eq.head.def.tint.map((c) => c * 1.5), 1];
        r.draw(this.meshes.helmet, this.matAcc, { model: this.attachHead([0, 0.07, 0.0]) });
      }
    }
  }
  attachHead(off) {
    // usa a posição do osso da cabeça e a orientação do corpo (sem torção da cabeça)
    const s = this.skel, p = s.pos(this.n.Head, [0, 0, 0]);
    const q = q4.mul(new Float32Array(4), this.spineQ || q4.create(), q4.create());
    const m = m4.create(); m4.fromTRS(m, [p[0] + off[0], p[1] + off[1], p[2] + off[2]], q, null);
    return m4.multiply(m4.create(), this.charM, m);
  }
}
