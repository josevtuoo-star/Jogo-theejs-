// Ferramentas de trabalho: machado e picareta (modelos CC0 do Poly Haven). Golpe animado, IK das mãos e coleta de recursos.
import { m4, q4, v3, clamp, lerp, smoothstep, damp } from '../engine/math.js';
import { SURF } from '../engine/physics.js';
import { FRAME } from '../engine/particles.js';

export const TDEFS = {
  axe: { id: 'axe', model: 'wooden_axe', reach: 2.9, swing: 0.92, hitAt: 0.5, dmgTree: 1, dmgRock: 0, grip: [0, -0.1, 0], tilt: -0.5, yaw: Math.PI, hip: [0.26, -0.3, -0.48], sound: 'wood' },
  pickaxe: { id: 'pickaxe', model: 'picke_dirty_01', reach: 2.9, swing: 1.02, hitAt: 0.5, dmgTree: 0, dmgRock: 1, grip: [0, -0.2, 0], tilt: -0.95, yaw: Math.PI / 2, hip: [0.26, -0.34, -0.55], sound: 'rock' },
};

export class ToolSystem {
  constructor(game) {
    this.g = game; this.def = null; this.item = null;
    this.swingT = -1; this.hitDone = false; this.worldM = m4.create();
    this.meshes = {}; this.bob = 0; this._spr = 0; this.clip = 0; this.turnLag = [0, 0];
    this.cooldown = 0;
  }
  prepare() {
    const gl = this.g.r.gl;
    for (const [id, d] of Object.entries(TDEFS)) {
      const gltf = this.g.assets.models[d.model];
      if (!gltf) continue;
      const T = m4.translation(m4.create(), -d.grip[0], -d.grip[1], -d.grip[2]);
      const Ry = m4.rotationY(m4.create(), d.yaw), Rx = m4.rotationX(m4.create(), d.tilt);
      const xf = m4.multiply(m4.create(), Rx, m4.multiply(m4.create(), Ry, T));
      this.meshes[id] = gltf.bake(gl, null, xf, true);
    }
  }
  equip(item) {
    this.item = item && TDEFS[item.def.tool] ? item : null;
    this.def = this.item ? TDEFS[this.item.def.tool] : null;
    this.swingT = -1;
    if (this.item) this.g.audio.play('click', { vol: 0.5 });
  }
  get active() { return !!this.def; }
  get swinging() { return this.swingT >= 0; }

  startSwing() {
    if (!this.def || this.swingT >= 0 || this.cooldown > 0) return false;
    this.swingT = 0; this.hitDone = false;
    this.g.audio.play('swing', { vol: 0.8, rate: 0.95 + Math.random() * 0.1 });
    return true;
  }

  update(dt) {
    this.cooldown = Math.max(0, this.cooldown - dt);
    if (this.swingT >= 0) {
      this.swingT += dt;
      const d = this.def;
      if (!this.hitDone && this.swingT >= d.swing * d.hitAt) { this.hitDone = true; this.strike(); }
      if (this.swingT >= d.swing) { this.swingT = -1; this.cooldown = 0.12; }
    }
  }

  // detecção do golpe: raios em leque à frente da câmera
  strike() {
    const g = this.g, P = g.player, d = this.def;
    const eye = P.eye, dir = P.aimDir();
    const right = v3.normalize([0, 0, 0], v3.cross([0, 0, 0], dir, [0, 1, 0]));
    let best = null;
    for (const [ox, oy] of [[0, 0], [-0.22, 0], [0.22, 0], [0, -0.28], [0, 0.2]]) {
      const dd = v3.normalize([0, 0, 0], [dir[0] + right[0] * ox, dir[1] + oy, dir[2] + right[2] * ox]);
      const h = g.phys.raycast(eye, dd, d.reach, {});
      if (h && (!best || h.t < best.t)) best = h;
    }
    P.stamina = Math.max(0, P.stamina - 7);
    // recurso (árvore/rocha) à frente tem prioridade e não depende do raio bater no cilindro
    const R = P.findResource(d.reach + 0.2);
    if (R) { if (R.kind === 'tree') g.veg.hitTree(R.col, d.dmgTree, R.point); else g.veg.hitRock(R.col, d.dmgRock, R.point); return; }
    if (!best) return;
    const n = best.normal, pt = best.point;
    if (best.type === 'col' && best.col.tree) { g.veg.hitTree(best.col, d.dmgTree, pt); return; }
    if (best.type === 'col' && best.col.rock) { g.veg.hitRock(best.col, d.dmgRock, pt); return; }
    // outras superfícies: baque + faíscas/poeira
    g.audio.hit(best.surf, 0.6);
    g.particles.dust(pt[0], pt[1], pt[2], 4, [0.55, 0.45, 0.35, 0.5], 1.2, n);
    if (best.type === 'body') g.phys.applyImpulse(best.body, [dir[0] * 18, dir[1] * 4, dir[2] * 18], pt);
  }

  // matriz do mundo da ferramenta (viewmodel): posição relativa à mira, balanço, golpe
  computeWorld(P, dt) {
    const d = this.def; if (!d) return null;
    const g = this.g;
    const eye = P.eye, yaw = P.aimYaw, pitch = P.aimPitch;
    let off = [d.hip[0], d.hip[1], d.hip[2]];
    const spd = Math.hypot(P.vel[0], P.vel[2]);
    this.bob += dt * (spd > 0.5 ? (P.sprinting ? 10 : 7.5) : 1.2);
    const bobAmt = Math.min(1, spd / 3.5) * (P.grounded ? 1 : 0.2);
    off[0] += Math.sin(this.bob) * 0.012 * bobAmt; off[1] += Math.abs(Math.cos(this.bob)) * 0.014 * bobAmt;
    off[1] += Math.sin(g.time * 1.4) * 0.004;
    const spr = P.sprinting ? 1 : 0; this._spr = damp(this._spr, spr, 8, dt);
    off[1] -= this._spr * 0.08; off[0] += this._spr * 0.05;
    // parede à frente: recua
    const h = g.phys.raycast(eye, P.aimDir(), 1.0, { noBodies: true });
    this.clip = damp(this.clip, h ? clamp(1 - h.t / 0.9, 0, 1) : 0, 14, dt);
    off[2] += this.clip * 0.4; off[1] -= this.clip * 0.08;
    let rx = 0.55 + this._spr * 0.3, ry = this._spr * -0.3, rz = 0;
    if (this.swingT >= 0) {
      const u = clamp(this.swingT / d.swing, 0, 1);
      // 0..0.38 prepara (levanta), 0.38..0.62 golpe rápido, resto recupera
      if (u < 0.38) { const k = smoothstep(0, 1, u / 0.38); rx = lerp(0.55, 1.55, k); off[1] += 0.2 * k; off[2] += 0.1 * k; off[0] -= 0.06 * k; }
      else if (u < 0.62) { const k = smoothstep(0, 1, (u - 0.38) / 0.24); rx = lerp(1.55, -0.9, k); off[1] += lerp(0.2, -0.16, k); off[2] += lerp(0.1, -0.34, k); off[0] -= lerp(0.06, 0.0, k); ry = -0.25 * k; }
      else { const k = smoothstep(0, 1, (u - 0.62) / 0.38); rx = lerp(-0.9, 0.55, k); off[1] += lerp(-0.16, 0, k); off[2] += lerp(-0.34, 0, k); ry = -0.25 * (1 - k); }
    }
    this.turnLag[0] = damp(this.turnLag[0], 0, 10, dt); this.turnLag[1] = damp(this.turnLag[1], 0, 10, dt);
    ry += this.turnLag[0]; rx += this.turnLag[1];
    const q = q4.fromEuler(new Float32Array(4), yaw, pitch, 0);
    const base = m4.fromTRS(m4.create(), eye, q, null);
    const local = m4.fromTRS(m4.create(), off, q4.fromEuler(new Float32Array(4), ry, rx, rz), null);
    m4.multiply(this.worldM, base, local);
    return this.worldM;
  }
  lookDelta(dy, dp) { this.turnLag[0] += clamp(dy * 0.35, -0.02, 0.02); this.turnLag[1] += clamp(dp * 0.35, -0.02, 0.02); }

  // mãos: direita no cabo, esquerda um pouco acima (duas mãos)
  handPoints() {
    if (!this.def) return null;
    const M = this.worldM;
    // mão esquerda mais acima, ao longo do cabo (que segue a inclinação da ferramenta)
    const c = Math.cos(this.def.tilt), sn = Math.sin(this.def.tilt), a = 0.27;
    return { rh: m4.transformPoint([0, 0, 0], M, [0, 0.0, 0]), lh: m4.transformPoint([0, 0, 0], M, [-0.025, a * c, a * sn]) };
  }
  draw(r) {
    if (!this.def) return;
    const set = this.meshes[this.def.id]; if (!set) return;
    for (const p of set) r.draw(p.mesh, p.material, { model: this.worldM });
  }
}
