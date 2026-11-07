// Veículo com suspensão por raycast, atrito de pneu e motor, sobre o corpo rígido da engine.
import { MeshBuilder } from '../engine/gl.js';
import { Material } from '../engine/renderer.js';
import { m4, q4, v3, clamp, lerp } from '../engine/math.js';
import { MAT } from './assets.js';
import { SURF } from '../engine/physics.js';

export function makeCarMeshes(gl) {
  const cm = new MeshBuilder();
  const box = (x0, y0, z0, x1, y1, z1, layer = MAT.metal, o = {}) => cm.box(x0, y0, z0, x1, y1, z1, layer, { uvScale: 0.4, ...o });
  box(-0.84, 0.35, -2.1, 0.84, 0.92, 2.1);
  box(-0.8, 0.92, -0.95, 0.8, 1.42, 1.15);
  box(-0.82, 0.82, 1.15, 0.82, 0.96, 2.05);
  box(-0.82, 0.82, -2.05, 0.82, 0.96, -0.95);
  box(-0.86, 0.3, 2.05, 0.86, 0.62, 2.22); box(-0.86, 0.3, -2.22, 0.86, 0.62, -2.05);
  // vidros (escuros)
  const gl2 = new MeshBuilder();
  gl2.box(-0.81, 0.97, -0.9, 0.81, 1.38, 1.1, MAT.darkwood, { uvScale: 0.4 });
  gl2.box(-0.7, 0.55, 2.2, -0.45, 0.75, 2.24, MAT.metal, { uvScale: 1 });
  gl2.box(0.45, 0.55, 2.2, 0.7, 0.75, 2.24, MAT.metal, { uvScale: 1 });
  const wb = new MeshBuilder();
  wb.cylinder(0, 0, 0, 0.33, 0.33, 0.22, 14, MAT.darkwood, { uvScale: 0.6, cap: true });
  wb.cylinder(0, 0.215, 0, 0.2, 0.2, 0.012, 10, MAT.metal, { uvScale: 1, cap: true });
  return { body: cm.build(gl), glass: gl2.build(gl), wheel: wb.build(gl) };
}

const WHEELS = [
  { lx: 0.86, lz: 1.32, front: true, drive: true }, { lx: -0.86, lz: 1.32, front: true, drive: true },
  { lx: 0.86, lz: -1.3, front: false, drive: false }, { lx: -0.86, lz: -1.3, front: false, drive: false },
];

export class Vehicle {
  constructor(game, x, z, yaw, matIdx = 0) {
    this.g = game;
    const phys = game.phys;
    const y = game.world.heightAt(x, z) + 1.0;
    this.mass = 1150;
    this.body = phys.addBody({ shape: 'box', half: [0.86, 0.5, 2.15], mass: this.mass, pos: [x, y, z], q: q4.fromEuler(new Float32Array(4), yaw, 0, 0), rest: 0.1, fric: 0.5, surf: SURF.METAL, drag: 0.002, adrag: 0.6 });
    this.body.userdata = { vehicle: this };
    // inércia maior (estabilidade): reduz invI
    this.body.invI = this.body.invI.map((v) => v * 0.45);
    this.pos = this.body.pos; this.vel = this.body.vel;
    this.yaw = yaw;
    this.input = { throttle: 0, brake: 0, steer: 0, handbrake: false };
    this.wheels = WHEELS.map((w) => ({ ...w, comp: 0.1, spin: 0, steer: 0, grounded: false, contact: [0, 0, 0] }));
    this.steer = 0; this.rpm = 0; this.fuel = 40; this.lights = false; this.driver = null; this.matIdx = matIdx;
    this.speed = 0;
    this.hook = (dt) => this.step(dt);
    phys.hooks.push(this.hook);
    this.restLen = 0.42; this.radius = 0.33; this.k = 30000; this.c = 3100;
  }
  step(dt) {
    const b = this.body, g = this.g, phys = g.phys, inp = this.input;
    if (b.dead) return;
    phys.wake(b);
    const q = b.q;
    const up = q4.rotate([0, 0, 0], q, [0, 1, 0]), fwd = q4.rotate([0, 0, 0], q, [0, 0, 1]), right = q4.rotate([0, 0, 0], q, [1, 0, 0]);
    this.yaw = Math.atan2(fwd[0], fwd[2]);
    const vlong = v3.dot(b.vel, fwd);
    this.speed = vlong;
    // direção: reduz com a velocidade
    const maxS = lerp(0.52, 0.18, clamp(Math.abs(vlong) / 30, 0, 1));
    this.steer += (inp.steer * maxS - this.steer) * Math.min(1, dt * 7);
    const hasFuel = this.fuel > 0 && !!this.driver;
    let throttle = hasFuel ? inp.throttle : 0, brake = inp.brake;
    let reverse = false;
    if (brake > 0.05 && vlong < 0.8 && throttle < 0.05 && hasFuel) { reverse = true; throttle = brake; brake = 0; }
    let grounded = 0;
    for (const w of this.wheels) {
      const mx = w.lx, my = -0.2, mz = w.lz;
      const mp = q4.rotate([0, 0, 0], q, [mx, my, mz]); mp[0] += b.pos[0]; mp[1] += b.pos[1]; mp[2] += b.pos[2];
      const gy = phys.groundAt(mp[0], mp[2], mp[1] - 0.8, 0.9);
      const n = g.world.normalAt(mp[0], mp[2]);
      const d = (mp[1] - gy) / Math.max(0.3, up[1]);
      const len = this.restLen + this.radius;
      w.comp = clamp(len - d, 0, this.restLen + 0.12);
      w.grounded = d < len;
      w.mount = mp; w.gy = gy;
      if (!w.grounded) { w.spin += (w.drive ? throttle * 60 * (reverse ? -1 : 1) : vlong / this.radius) * dt * 0.0 + vlong / this.radius * dt; continue; }
      grounded++;
      const r = [mp[0] - b.pos[0], mp[1] - b.pos[1], mp[2] - b.pos[2]];
      const vp = [b.vel[0] + (b.w[1] * r[2] - b.w[2] * r[1]), b.vel[1] + (b.w[2] * r[0] - b.w[0] * r[2]), b.vel[2] + (b.w[0] * r[1] - b.w[1] * r[0])];
      const vn = v3.dot(vp, n);
      const Fs = Math.max(0, this.k * w.comp - this.c * vn * (w.comp > 0.01 ? 1 : 0));
      const cp = [mp[0], gy + 0.05, mp[2]];
      const push = [n[0] * Fs * dt, n[1] * Fs * dt, n[2] * Fs * dt];
      phys.applyImpulse(b, push, [mp[0], mp[1] - 0.1, mp[2]]);
      // pneu
      const st = w.front ? this.steer : 0;
      const cs = Math.cos(st), sn = Math.sin(st);
      let wf = [fwd[0] * cs + right[0] * sn, fwd[1] * cs + right[1] * sn, fwd[2] * cs + right[2] * sn];
      const dn = v3.dot(wf, n); wf = [wf[0] - n[0] * dn, wf[1] - n[1] * dn, wf[2] - n[2] * dn]; v3.normalize(wf, wf);
      const wr = v3.normalize([0, 0, 0], v3.cross([0, 0, 0], n, wf));
      const vl = v3.dot(vp, wf), vs = v3.dot(vp, wr);
      const surfMu = [SURF.ASPHALT, SURF.STONE].includes(phys.surfaceAt(mp[0], mp[2])) ? 1.35 : phys.surfaceAt(mp[0], mp[2]) === SURF.GRASS ? 0.85 : 0.95;
      const wet = g.atm.env.wetness;
      let mu = surfMu * (1 - wet * 0.3);
      if (!w.front && inp.handbrake) mu *= 0.32;
      const Nload = Math.max(Fs, 300);
      const maxF = mu * Nload * dt;
      const mEff = this.mass / 4;
      let Jlat = clamp(-vs * mEff * 0.85, -maxF, maxF);
      let Jlong = 0;
      if (w.drive && throttle > 0.01) { const sp = Math.abs(vl); const F = throttle * 8200 * Math.max(0, 1 - sp / (reverse ? 9 : 38)); Jlong += (reverse ? -1 : 1) * F * dt * 0.5; }
      if (brake > 0.01) Jlong += clamp(-vl * mEff, -brake * 9000 * dt * 0.5, brake * 9000 * dt * 0.5);
      if (inp.handbrake && !w.front) Jlong += clamp(-vl * mEff, -9000 * dt * 0.5, 9000 * dt * 0.5);
      Jlong += -vl * 0.006 * mEff * (throttle > 0.01 ? 0.1 : 1); // resistência de rolamento
      const lim = Math.hypot(Jlat, Jlong), mf = Math.hypot(maxF, 1e-9);
      if (lim > maxF * 1.05) { const s = maxF * 1.05 / lim; Jlat *= s; Jlong *= s; }
      const hp = [mp[0], mp[1] - 0.45, mp[2]];
      phys.applyImpulse(b, [wf[0] * Jlong + wr[0] * Jlat, wf[1] * Jlong + wr[1] * Jlat, wf[2] * Jlong + wr[2] * Jlat], hp);
      w.spin += vl / this.radius * dt;
      w.slip = Math.abs(vs);
      if (w.slip > 3.5 && g.phys.surfaceAt(mp[0], mp[2]) !== SURF.WATER && Math.random() < 0.3) g.particles.dust(cp[0], cp[1], cp[2], 1, [0.5, 0.45, 0.4, 0.4], 0.8);
    }
    // arrasto aerodinâmico
    const sp = Math.hypot(b.vel[0], b.vel[1], b.vel[2]);
    const dr = 0.42 * sp * dt / this.mass * 1.0;
    b.vel[0] -= b.vel[0] * dr; b.vel[1] -= b.vel[1] * dr * 0.3; b.vel[2] -= b.vel[2] * dr;
    // downforce leve
    if (grounded) b.vel[1] -= sp * 0.0008;
    // consumo
    if (this.driver) this.fuel = Math.max(0, this.fuel - dt * (0.002 + Math.abs(throttle) * 0.01));
    this.rpm = clamp(Math.abs(vlong) / 28 * 0.8 + throttle * 0.25 + 0.12, 0.1, 1);
    this.grounded = grounded;
    // nos limites do mapa
    b.pos[0] = clamp(b.pos[0], 4, 1996); b.pos[2] = clamp(b.pos[2], 4, 1996);
  }
  matrix(out) {
    const b = this.body;
    // origem do mesh: chão sob o centro do chassi
    m4.fromTRS(out, b.pos, b.q, null);
    const off = q4.rotate([0, 0, 0], b.q, [0, -0.85, 0]);
    out[12] += off[0]; out[13] += off[1]; out[14] += off[2];
    return out;
  }
  wheelMatrix(i, out) {
    const w = this.wheels[i], b = this.body;
    const M = m4.fromTRS(m4.create(), b.pos, b.q, null);
    const cy = -0.2 - (this.restLen - w.comp) ;
    const local = m4.translation(m4.create(), w.lx, cy, w.lz);
    const st = w.front ? this.steer : 0;
    const R1 = m4.rotationY(m4.create(), st);
    const R2 = m4.rotationX(m4.create(), -w.spin);
    const Rz = m4.fromTRS(m4.create(), [0, 0, 0], q4.axisAngle(new Float32Array(4), 0, 0, 1, Math.PI / 2 * (w.lx > 0 ? -1 : 1)), null);
    const off = m4.translation(m4.create(), 0, w.lx > 0 ? -0.0 : 0.0, 0);
    m4.multiply(out, M, local); m4.multiply(out, out, R1); m4.multiply(out, out, R2); m4.multiply(out, out, Rz);
    // cilindro ao longo de +y: centraliza em y
    m4.multiply(out, out, m4.translation(m4.create(), 0, -0.11, 0));
    return out;
  }
  draw(r, meshes, mats) {
    const M = this.matrix(m4.create());
    r.draw(meshes.body, mats.paint[this.matIdx % mats.paint.length], { model: M });
    r.draw(meshes.glass, mats.glass, { model: M });
    const wm = m4.create();
    for (let i = 0; i < 4; i++) { this.wheelMatrix(i, wm); r.draw(meshes.wheel, mats.wheel, { model: wm }); }
  }
  remove() { const i = this.g.phys.hooks.indexOf(this.hook); if (i >= 0) this.g.phys.hooks.splice(i, 1); this.g.phys.removeBody(this.body); }
}
