// Sistema de armas: definições, viewmodel (hip/ADS), tiro balístico, recarga, corpo a corpo, granadas.
import { m4, q4, v3, clamp, lerp, smoothstep, damp, mulberry32 } from '../engine/math.js';
import { SURF } from '../engine/physics.js';
import { FRAME } from '../engine/particles.js';
import { ITEMS, makeItem } from './items.js';

const rotY = (a) => { const m = m4.create(); m4.rotationY(m, a); return m; };

export const WDEFS = {
  mosin: {
    kind: 'rifle', sound: 'rifle', ammo: '762', mag: 5, auto: false, bolt: true, cycle: 0.95, damage: 95, vel: 810, k: 0.00075, zero: 100, mass: 0.0118,
    spread: { hip: 0.03, ads: 0.0007 }, recoil: { pitch: 0.026, yaw: 0.006, kick: 0.11 }, adsFov: 56, sway: 0.0022, reloadRound: 0.7, reloadStart: 0.5,
    model: 'bolt_action_rifle_7_62', parts: ['bolt_action_rifle_7_62', 'bolt_action_rifle_7_62_wrap', 'bolt_action_rifle_7_62_trigger'], bolt: ['bolt_action_rifle_7_62_bolt_a', 'bolt_action_rifle_7_62_bolt_b'],
    grip: [-0.34, 0.0, 0], lhand: [0.22, -0.075, 0], muzzle: [0.6, 0.05, 0], sight: [-0.04, 0.072, 0], eyeDist: 0.5,
    hip: [0.17, -0.2, -0.28], rh: 0.05, lh: 0.05, scale: 1,
  },
  pistol: {
    kind: 'pistol', sound: 'pistol', ammo: '45', mag: 7, auto: false, cycle: 0.1, damage: 42, vel: 255, k: 0.0016, zero: 25, mass: 0.015,
    spread: { hip: 0.04, ads: 0.004 }, recoil: { pitch: 0.036, yaw: 0.008, kick: 0.07 }, adsFov: 62, sway: 0.004, reloadStart: 2.0,
    model: 'service_pistol', parts: ['service_pistol_pistol_a', 'service_pistol_slide_a', 'service_pistol_hammer_a', 'service_pistol_trigger_a', 'service_pistol_magazine_loaded'], magShift: [0.1, 0, 0],
    grip: [-0.01, -0.012, 0], lhand: null, muzzle: [0.176, 0.062, 0], sight: [-0.01, 0.079, 0], eyeDist: 0.62,
    hip: [0.2, -0.17, -0.3], rh: 0.0, scale: 1,
  },
  hatchet: { kind: 'melee', damage: 55, reach: 1.8, rate: 0.75, swing: 0.4, model: 'hatchet', parts: [null], grip: [0, 0.02, 0.0], hip: [0.2, -0.22, -0.4], xf: 'axe', scale: 1.0 },
  machete: { kind: 'melee', damage: 48, reach: 2.0, rate: 0.6, swing: 0.34, model: 'machete', parts: [null], grip: [0, 0.0, 0.0], hip: [0.2, -0.22, -0.4], xf: 'axe', scale: 1.0 },
  crowbar: { kind: 'melee', damage: 40, reach: 1.9, rate: 0.7, swing: 0.4, model: 'crowbar_01', parts: [null], grip: [0, 0.0, 0.0], hip: [0.2, -0.22, -0.4], xf: 'axe', scale: 1.0 },
};

const AMMO_NAMES = { '762': '7,62x54R', '45': '.45 ACP' };

export class WeaponSystem {
  constructor(game) {
    this.g = game;
    this.def = null; this.item = null;
    this.state = 'idle'; this.stateT = 0;
    this.adsT = 0; this.aiming = false;
    this.kick = 0; this.kickRot = 0; this.reloadAnim = 0;
    this.bob = 0; this.sway = [0, 0]; this.turnLag = [0, 0];
    this.holdBreath = 0; this.breathLeft = 5;
    this.fireT = 0; this.shots = 0;
    this.swingT = -1;
    this.parts = {};
    this.worldM = m4.create();
    this.rnd = mulberry32(777);
    this.hitMarker = 0;
    this.lastHit = null;
    this.nades = [];
    this.clip = 0;
  }

  // prepara malhas das armas (uma vez)
  prepare() {
    const lvl = this.g.level, gl = this.g.r.gl;
    this.meshes = {};
    for (const [id, d] of Object.entries(WDEFS)) {
      const gltf = this.g.assets.models[d.model];
      if (!gltf) continue;
      const out = { parts: [], bolt: [], size: null };
      const xf = this._xf(d);
      for (const nm of d.parts) {
        const extra = nm && nm.includes('magazine') ? m4.translation(m4.create(), ...(d.magShift || [0, 0, 0])) : null;
        const T = extra ? m4.multiply(m4.create(), xf, extra) : xf;
        const ps = gltf.bake(gl, nm, T, false);
        for (const p of ps) out.parts.push({ ...p, name: nm });
      }
      if (d.bolt) d.bolt.forEach((nm, i) => { out.bolt[i] = gltf.bake(gl, nm, xf, false); });
      this.meshes[id] = out;
    }
  }
  // model -> frame da arma (origem na mão direita, -Z à frente)
  _xf(d) {
    const m = m4.create();
    if (d.xf === 'axe') {
      // machadinha: cabo ao longo de +y do modelo; frente da arma = -z; lâmina para a frente
      const R = m4.create(); const q = q4.fromEuler(new Float32Array(4), 0, -Math.PI / 2 * 0, 0);
      m4.fromTRS(m, [0, 0, 0], q4.mul(new Float32Array(4), q4.axisAngle(new Float32Array(4), 1, 0, 0, -Math.PI * 0.30), q4.create()), null);
      const t = m4.translation(m4.create(), -d.grip[0], -d.grip[1], -d.grip[2]);
      return m4.multiply(m4.create(), m, t);
    }
    const t = m4.translation(m4.create(), -d.grip[0], -d.grip[1], -d.grip[2]);
    m4.rotationY(m, Math.PI / 2);
    return m4.multiply(m4.create(), m, t);
  }

  equip(item) {
    const g = this.g;
    if (this.item === item) return;
    this.item = item;
    this.def = item ? WDEFS[item.def.weapon] : null;
    this.state = item ? 'draw' : 'idle'; this.stateT = 0; this.reloadAnim = 0; this.swingT = -1; this.aiming = false;
    if (item) g.audio.click(null, 0.3, 1400);
  }
  ammoAvailable() { const d = this.def; if (!d || !d.ammo) return 0; return this.g.inv.count('ammo_' + d.ammo); }
  get isGun() { return this.def && (this.def.kind === 'rifle' || this.def.kind === 'pistol'); }
  get isMelee() { return this.def && this.def.kind === 'melee'; }

  // ---------------------------------------------------------------- tiro
  canFire() { return this.isGun && this.state === 'idle' && this.item.mag > 0 && this.item.chamber !== false; }
  tryFire() {
    const g = this.g, d = this.def, it = this.item;
    if (!d) return;
    if (this.isMelee) { if (this.state === 'idle') this.startSwing(); return; }
    if (!this.isGun || this.state !== 'idle') return;
    if (g.player.sprinting) return;
    if (it.mag <= 0) { g.audio.dryFire(g.player.eye); this.state = 'cycle'; this.stateT = -0.25; this.dryT = 1; return; }
    this.fireGun();
  }
  fireGun() {
    const g = this.g, d = this.def, it = this.item, P = g.player;
    it.mag--;
    this.shots++;
    const dir = P.aimDir(), eye = P.eye;
    // espalhamento
    let spread = lerp(d.spread.hip, d.spread.ads, smoothstep(0, 1, this.adsT));
    const moving = Math.min(1, Math.hypot(P.vel[0], P.vel[2]) / 4);
    spread *= 1 + moving * 1.8 + (P.grounded ? 0 : 3);
    spread *= P.stance === 1 ? 0.75 : P.stance === 2 ? 0.55 : 1;
    spread *= 1 + this.kick * 2.0;
    if (this.holdBreath > 0.5) spread *= 0.5;
    const rnd = this.rnd;
    const up = [0, 1, 0], right = v3.normalize([0, 0, 0], v3.cross([0, 0, 0], dir, up)), up2 = v3.cross([0, 0, 0], right, dir);
    const a = rnd() * Math.PI * 2, r = Math.sqrt(rnd()) * spread;
    // zeragem: eleva o cano para acertar o ponto de mira na distância `zero`
    const zeroAng = 0.5 * 9.81 * d.zero / (d.vel * d.vel) * (1 + d.k * d.zero * 0.5);
    const dd = [dir[0] + right[0] * Math.cos(a) * r + up2[0] * (Math.sin(a) * r + zeroAng), dir[1] + right[1] * Math.cos(a) * r + up2[1] * (Math.sin(a) * r + zeroAng), dir[2] + right[2] * Math.cos(a) * r + up2[2] * (Math.sin(a) * r + zeroAng)];
    v3.normalize(dd, dd);
    const org = [eye[0] + dir[0] * 0.5, eye[1] + dir[1] * 0.5 - 0.02, eye[2] + dir[2] * 0.5];
    const muzzle = this.muzzleWorld();
    g.phys.fire(org, dd, d.vel, { k: d.k, damage: d.damage, mass: d.mass, owner: null, kind: 'bullet', data: { weapon: it.id, from: [org[0], org[1], org[2]] }, tracer: muzzle });
    // efeitos
    g.audio.shot(d.sound, muzzle);
    g.particles.muzzleFlash(muzzle[0], muzzle[1], muzzle[2], d.kind === 'rifle' ? 0.55 : 0.4);
    g.particles.smoke(muzzle[0] + dir[0] * 0.2, muzzle[1] + dir[1] * 0.2, muzzle[2] + dir[2] * 0.2, 3, 0.3, 0.2, [0.7, 0.7, 0.7, 0.35], 1.2);
    g.env.lights[3] = { pos: muzzle, radius: 18, color: [1, 0.75, 0.4], intensity: 6, spot: false, flash: 0.05 };
    // recuo
    const rc = d.recoil;
    P.addRecoil(rc.pitch * (0.85 + 0.3 * rnd()) * (P.stance === 2 ? 0.6 : 1) * (this.adsT > 0.5 ? 0.8 : 1), (rnd() - 0.5) * 2 * rc.yaw);
    this.kick = Math.min(1.2, this.kick + 1);
    this.kickRot = Math.min(1.2, this.kickRot + 1);
    if (d.bolt) { this.state = 'cycle'; this.stateT = 0; this.boltPhase = 0; }
    else { this.state = 'cycle'; this.stateT = 0; this.boltPhase = 0; this.slideBack = 1;
      // ejeta cápsula
      const wm = this.worldM;
      g.particles.emit({ x: muzzle[0] - dir[0] * 0.15, y: muzzle[1] - 0.02, z: muzzle[2] - dir[2] * 0.15, vx: right[0] * 2 + (rnd() - 0.5), vy: 1.5, vz: right[2] * 2 + (rnd() - 0.5), s0: 0.02, s1: 0.02, life: 1.3, c0: [1.2, 0.9, 0.3, 1], c1: [1.2, 0.9, 0.3, 1], frame: FRAME.DEBRIS, grav: 9.8, spin: 20, collide: true });
    }
    g.ui.flashMuzzle && g.ui.flashMuzzle();
  }
  muzzleWorld() {
    const d = this.def; if (!d || !d.muzzle) return this.g.player.eye;
    const p = [d.muzzle[0] - d.grip[0], d.muzzle[1] - d.grip[1], d.muzzle[2] - d.grip[2]];
    const R = m4.rotationY(m4.create(), Math.PI / 2);
    const pr = m4.transformPoint([0, 0, 0], R, p);
    return m4.transformPoint([0, 0, 0], this.worldM, pr);
  }

  // ---------------------------------------------------------------- reload
  startReload() {
    const g = this.g, d = this.def, it = this.item;
    if (!this.isGun || this.state === 'reload') return;
    const free = d.mag - it.mag;
    if (free <= 0) { g.ui.toast('Carregador cheio'); return; }
    if (this.ammoAvailable() <= 0) { g.ui.toast('Sem munição ' + AMMO_NAMES[d.ammo]); return; }
    this.state = 'reload'; this.stateT = 0; this.reloaded = 0; this.aiming = false;
    this.reloadStartAt = d.reloadStart; g.audio.reload(g.player.eye, d.bolt ? 'shell' : 'mag');
  }
  _finishReloadStep() {
    const d = this.def, it = this.item, g = this.g;
    if (d.bolt) { // 1 cartucho por vez
      if (this.ammoAvailable() > 0 && it.mag < d.mag) { g.inv.consume('ammo_' + d.ammo, 1); it.mag++; g.audio.reload(g.player.eye, 'shell'); }
    }
  }

  // ---------------------------------------------------------------- melee
  startSwing() { const d = this.def; if (this.swingT >= 0) return; this.swingT = 0; this.state = 'melee'; this.swingHit = false; this.g.audio.click(null, 0.3, 700); }

  // ---------------------------------------------------------------- granada
  throwGrenade() {
    const g = this.g, P = g.player;
    if (g.inv.count('grenade') <= 0) return;
    g.inv.consume('grenade', 1);
    const dir = P.aimDir(), eye = P.eye;
    const body = g.phys.addBody({ shape: 'sphere', radius: 0.06, mass: 0.6, pos: [eye[0] + dir[0] * 0.6, eye[1] + dir[1] * 0.6 - 0.1, eye[2] + dir[2] * 0.6], vel: [dir[0] * 17 + P.vel[0], dir[1] * 17 + 3 + P.vel[1] * 0.2, dir[2] * 17 + P.vel[2]], w: [8, 2, 0], rest: 0.35, fric: 0.5 });
    this.nades.push({ body, t: 4.0 });
    g.audio.click(null, 0.5, 900);
    g.ui.toast('Granada lançada!');
    // próximo item
    if (g.inv.count('grenade') <= 0) { g.player.holster(); }
  }

  explodeAt(pos) {
    const g = this.g;
    g.particles.explosion(pos[0], pos[1], pos[2]);
    g.audio.explosion(pos);
    g.phys.explode(pos, 11, 14);
    g.shake = Math.max(g.shake || 0, 1.0 / (1 + Math.hypot(pos[0] - g.player.pos[0], pos[2] - g.player.pos[2]) * 0.12));
    const d = Math.hypot(pos[0] - g.player.pos[0], pos[1] - g.player.pos[1] - 1, pos[2] - g.player.pos[2]);
    if (d < 9) { const los = !g.phys.segment(pos, [g.player.pos[0], g.player.pos[1] + 1, g.player.pos[2]], {}); if (los || d < 3) g.player.damage((1 - d / 9) * 160, 'explosion'); }
    g.particles.decal(pos[0], g.world.heightAt(pos[0], pos[2]) + 0.01, pos[2], 0, 1, 0, 4, FRAME.SCORCH, [0.05, 0.04, 0.03, 0.8], 90);
    for (const t of g.level.targets) if (Math.hypot(t.x - pos[0], t.z - pos[2]) < 8) { t.hit = 1; t.t = 0; t.angle = 0.02; }
  }

  // ---------------------------------------------------------------- impacto de projétil
  onHit(p, hit, speed) {
    const g = this.g, P = g.particles, a = g.audio;
    const n = hit.normal, pt = hit.point;
    const dirv = v3.normalize([0, 0, 0], p.vel);
    const surf = hit.surf;
    const dust = { [SURF.DIRT]: [0.5, 0.4, 0.3, 0.6], [SURF.GRASS]: [0.35, 0.4, 0.2, 0.5], [SURF.SAND]: [0.7, 0.65, 0.5, 0.6], [SURF.STONE]: [0.6, 0.6, 0.6, 0.6], [SURF.ASPHALT]: [0.4, 0.4, 0.4, 0.5], [SURF.WOOD]: [0.55, 0.4, 0.22, 0.7], [SURF.METAL]: [0.6, 0.6, 0.6, 0.4] }[surf] || [0.5, 0.45, 0.4, 0.6];
    if (surf === SURF.WATER) { P.splash(pt[0], pt[1], pt[2], 8); a.splash(pt); return false; }
    P.dust(pt[0], pt[1], pt[2], 7, dust, 2.2, n);
    if (surf === SURF.METAL) P.sparks(pt[0], pt[1], pt[2], 8, n);
    if (surf === SURF.WOOD || surf === SURF.STONE) P.debris(pt[0], pt[1], pt[2], 6, dust, n, 4);
    a.impact(surf, pt);
    P.decal(pt[0], pt[1], pt[2], n[0], n[1], n[2], 0.1 + this.rnd() * 0.04, FRAME.HOLE, surf === SURF.METAL ? [0.2, 0.2, 0.22, 0.95] : [1, 1, 1, 0.9], 60);
    // feedback
    this.hitMarker = 1; this.lastHit = { surf, dist: p.dist + 0, type: hit.type, t: performance.now() };
    if (hit.type === 'col' && hit.col.target) { g.level.hitTarget(hit.col); a.impact(SURF.METAL, pt); g.ui.hitInfo && g.ui.hitInfo(p.dist, p.data); }
    else g.ui.hitInfo && g.ui.hitInfo(p.dist, p.data, true);
    if (hit.type === 'body') {
      const J = p.mass * speed * 7;
      g.phys.applyImpulse(hit.body, [dirv[0] * J, dirv[1] * J, dirv[2] * J], pt);
      if (hit.body.userdata && hit.body.userdata.loot) { /* item atingido */ }
    }
    // penetração em materiais finos
    if (hit.type === 'col' && !hit.col.target && p.pen > 0 && speed > 350) {
      const c = hit.col;
      const thick = c.kind === 0 ? Math.min(c.hx, c.hz) * 2 : c.r * 2;
      const lim = surf === SURF.WOOD ? 0.34 : surf === SURF.METAL ? 0.12 : surf === SURF.STONE ? 0.07 : 0;
      if (thick < lim) { p.vel[0] *= 0.55; p.vel[1] *= 0.55; p.vel[2] *= 0.55; p.pen--; return true; }
    }
    return false;
  }

  // ---------------------------------------------------------------- por frame
  update(dt) {
    const g = this.g, P = g.player, d = this.def, it = this.item, inp = g.input;
    // granadas
    for (const n of this.nades) { n.t -= dt; if (n.t <= 0 && !n.done) { n.done = true; this.explodeAt(n.body.pos.slice()); g.phys.removeBody(n.body); } }
    this.nades = this.nades.filter((n) => !n.done);
    this.hitMarker = Math.max(0, this.hitMarker - dt * 3);
    if (g.env.lights[3] && g.env.lights[3].flash) { g.env.lights[3].flash -= dt; if (g.env.lights[3].flash <= 0) g.env.lights[3] = null; }
    this.kick = damp(this.kick, 0, 12, dt); this.kickRot = damp(this.kickRot, 0, 9, dt);
    if (!d || !it) { this.adsT = damp(this.adsT, 0, 12, dt); return; }
    // ADS
    const wantAds = this.aiming && this.isGun && !P.sprinting && this.state !== 'reload' && !P.inVehicle;
    this.adsT = damp(this.adsT, wantAds ? 1 : 0, 11, dt);
    // segurar a respiração
    if (wantAds && inp.isHeld('sprint') && this.breathLeft > 0) { this.holdBreath = Math.min(1, this.holdBreath + dt * 4); this.breathLeft -= dt; }
    else { this.holdBreath = Math.max(0, this.holdBreath - dt * 3); this.breathLeft = Math.min(5, this.breathLeft + dt * (this.holdBreath > 0.1 ? 0 : 0.8)); }
    // máquina de estados
    this.stateT += dt;
    if (this.state === 'draw' && this.stateT > 0.5) this.state = 'idle';
    if (this.state === 'cycle') {
      const cyc = d.cycle || 0.1;
      if (d.bolt) {
        const t = this.stateT;
        this.boltPhase = t < 0.18 ? t / 0.18 : t < cyc - 0.2 ? 1 : Math.max(0, (cyc - t) / 0.2);
        if (!this.boltClick && t > 0.35 && !this.dryT) { this.boltClick = true; g.audio.bolt(g.player.eye); }
        if (t >= cyc) { this.state = 'idle'; this.boltClick = false; }
      } else {
        this.slideBack = Math.max(0, 1 - this.stateT / 0.09);
        if (this.stateT >= cyc) { this.state = 'idle'; this.dryT = 0; }
      }
      if (this.dryT && this.stateT >= 0) { this.state = 'idle'; this.dryT = 0; }
    }
    if (this.state === 'reload') {
      if (d.bolt) {
        // um cartucho a cada reloadRound; interrompe ao fechar o gatilho/ficar cheio
        const need = this.reloadStartAt + (this.reloaded + 1) * d.reloadRound;
        if (this.stateT >= need) { this._finishReloadStep(); this.reloaded++; if (it.mag >= d.mag || this.ammoAvailable() <= 0) { this.state = 'cycle'; this.stateT = 0; this.boltPhase = 0; this.cycleAfter = true; g.audio.bolt(g.player.eye); } }
        this.reloadAnim = Math.sin(clamp(this.stateT / (this.reloadStartAt + d.mag * d.reloadRound), 0, 1) * Math.PI);
      } else {
        const T = d.reloadStart;
        if (this.stateT > T * 0.45 && !this.magOut) { this.magOut = true; g.audio.reload(g.player.eye, 'mag'); }
        if (this.stateT >= T) {
          const need = d.mag - it.mag, take = Math.min(need, this.ammoAvailable());
          g.inv.consume('ammo_' + d.ammo, take); it.mag += take; it.chamber = true; this.magOut = false; this.state = 'idle';
          g.audio.click(null, 0.4, 1100);
        }
        this.reloadAnim = Math.sin(clamp(this.stateT / T, 0, 1) * Math.PI);
      }
      if (this.state !== 'reload') this.reloadAnim = 0;
    }
    if (!this.reloadAnim || this.state !== 'reload') this.reloadAnim = damp(this.reloadAnim || 0, 0, 10, dt);
    // melee
    if (this.state === 'melee') {
      this.swingT += dt;
      const sw = d.swing;
      if (!this.swingHit && this.swingT > sw * 0.45) { this.swingHit = true; this.doMeleeHit(); }
      if (this.swingT > sw + 0.15) { this.state = 'idle'; this.swingT = -1; }
    }
    // disparo automático/semiauto via input
    if (inp.pressed('fire') && !g.ui.menuOpen && !g.ui.invOpen) this.tryFire();
    if (inp.isHeld('fire') && d.auto && !g.ui.menuOpen) this.tryFire();
    // arremesso/granada tratado em Player
  }
  doMeleeHit() {
    const g = this.g, P = g.player, d = this.def;
    const eye = P.eye, dir = P.aimDir();
    let best = null;
    for (const off of [[0, 0], [-0.25, 0], [0.25, 0], [0, -0.3]]) {
      const right = v3.normalize([0, 0, 0], v3.cross([0, 0, 0], dir, [0, 1, 0]));
      const dd = v3.normalize([0, 0, 0], [dir[0] + right[0] * off[0] * 0.3, dir[1] + off[1] * 0.3, dir[2] + right[2] * off[0] * 0.3]);
      const h = g.phys.raycast(eye, dd, d.reach, {});
      if (h && (!best || h.t < best.t)) best = h;
    }
    g.audio.click(null, 0.4, 500);
    if (!best) return;
    const n = best.normal;
    g.particles.dust(best.point[0], best.point[1], best.point[2], 5, [0.55, 0.45, 0.35, 0.6], 1.5, n);
    g.audio.impact(best.surf, best.point);
    this.hitMarker = 1;
    if (best.type === 'body') { g.phys.applyImpulse(best.body, [dir[0] * d.damage * 0.35, dir[1] * 3, dir[2] * d.damage * 0.35], best.point); }
    if (best.type === 'col' && best.col.target) g.level.hitTarget(best.col);
    g.particles.decal(best.point[0], best.point[1], best.point[2], n[0], n[1], n[2], 0.12, FRAME.HOLE, [1, 1, 1, 0.5], 40);
    P.stamina = Math.max(0, P.stamina - 6);
  }

  // ---------------------------------------------------------------- matriz do viewmodel
  // eye/aim: posição e rotação (yaw,pitch) da mira. Retorna matriz do mundo da arma.
  computeWorld(P, dt) {
    const d = this.def; if (!d) return null;
    const g = this.g;
    const eye = P.eye, yaw = P.yaw, pitch = P.pitch + P.recoilPitch * 0.0;
    // offsets em espaço da mira
    const ads = smoothstep(0, 1, this.adsT);
    const hip = d.hip;
    // posição ADS: linha de visada alinhada ao centro da câmera
    const sx = d.sight ? d.sight[0] - d.grip[0] : 0, sy = d.sight ? d.sight[1] - d.grip[1] : 0.08;
    const adsPos = [0, -sy, -(d.eyeDist || 0.3) - (-(sx))];
    let off = [lerp(hip[0], adsPos[0], ads), lerp(hip[1], adsPos[1], ads), lerp(hip[2], adsPos[2], ads)];
    // bob / sway
    const spd = Math.hypot(P.vel[0], P.vel[2]);
    this.bob += dt * (spd > 0.5 ? (P.sprinting ? 11 : 8) : 1.2);
    const bobAmt = Math.min(1, spd / 3.5) * (1 - ads * 0.85) * (P.grounded ? 1 : 0.2);
    off[0] += Math.sin(this.bob) * 0.012 * bobAmt; off[1] += Math.abs(Math.cos(this.bob)) * 0.014 * bobAmt - 0.004 * bobAmt;
    const t = g.time;
    const swayAmt = d.sway * ads * (1 - this.holdBreath * 0.9) * (P.stance === 2 ? 0.4 : 1);
    this.sway[0] = (Math.sin(t * 1.3) + Math.sin(t * 2.9) * 0.4) * swayAmt; this.sway[1] = (Math.sin(t * 1.1 + 1) + Math.cos(t * 2.3) * 0.5) * swayAmt;
    // recuo do modelo
    off[2] += this.kick * d.recoil.kick * (d.kind === 'pistol' ? 0.9 : 1); off[1] += this.kick * 0.012;
    // recarga: abaixa e inclina
    off[1] -= this.reloadAnim * 0.11; off[0] -= this.reloadAnim * 0.06;
    // sprint: arma baixa e inclinada
    const spr = P.sprinting ? 1 : 0; this._spr = damp(this._spr || 0, spr, 8, dt);
    off[1] -= this._spr * 0.1; off[0] += this._spr * 0.06;
    // draw/holster
    const drawT = this.state === 'draw' ? 1 - clamp(this.stateT / 0.5, 0, 1) : 0;
    off[1] -= drawT * drawT * 0.3;
    // parede: empurra para trás e levanta
    const dirc = P.aimDir();
    const hitw = g.phys.raycast(eye, dirc, 1.1, { noBodies: true });
    this.clip = damp(this.clip, hitw ? clamp(1 - hitw.t / 1.0, 0, 1) : 0, 14, dt);
    off[2] += this.clip * 0.5; off[1] -= this.clip * 0.1;
    // melee: balanço do golpe
    let rx = -this.kickRot * (d.kind === 'pistol' ? 0.1 : 0.06) + this.reloadAnim * 0.5 + this._spr * 0.25 + this.clip * 0.9 + drawT * 0.6;
    let ry = this._spr * -0.35 + this.sway[0] * 0.4;
    let rz = this._spr * 0.2;
    if (d.kind === 'melee' && this.swingT >= 0) {
      const u = clamp(this.swingT / d.swing, 0, 1.3), sw = Math.sin(Math.min(u, 1) * Math.PI);
      const wind = u < 0.35 ? u / 0.35 : 1 - (u - 0.35) / 0.65;
      rx += (u < 0.35 ? -wind * 0.9 : (1 - wind) * 1.4 * Math.sin(Math.min(1, (u - 0.35) / 0.4) * Math.PI)); off[2] -= sw * 0.28; off[1] += (u < 0.35 ? wind * 0.12 : -sw * 0.1); ry -= sw * 0.4;
    }
    // atraso de giro
    this.turnLag[0] = damp(this.turnLag[0], 0, 10, dt); this.turnLag[1] = damp(this.turnLag[1], 0, 10, dt);
    ry += this.turnLag[0]; rx += this.turnLag[1];
    const q = q4.fromEuler(new Float32Array(4), yaw + this.sway[0] * 0.5, pitch + this.sway[1] * 0.6 + P.recoilPitch * 0.0, 0);
    const base = m4.fromTRS(m4.create(), eye, q, null);
    const local = m4.fromTRS(m4.create(), off, q4.fromEuler(new Float32Array(4), ry, rx, rz), null);
    this.worldM = m4.multiply(this.worldM, base, local);
    return this.worldM;
  }
  lookDelta(dyaw, dpitch) { this.turnLag[0] += clamp(dyaw * 0.35, -0.02, 0.02); this.turnLag[1] += clamp(dpitch * 0.35, -0.02, 0.02); }

  // pontos das mãos em mundo
  handPoints() {
    const d = this.def; if (!d) return null;
    const R = m4.rotationY(m4.create(), Math.PI / 2);
    const rh = m4.transformPoint([0, 0, 0], this.worldM, [0, -0.01, d.rh ? -d.rh : 0]);
    let lh = null;
    if (d.lhand) { const p = [d.lhand[0] - d.grip[0], d.lhand[1] - d.grip[1], d.lhand[2] - d.grip[2]]; lh = m4.transformPoint([0, 0, 0], this.worldM, m4.transformPoint([0, 0, 0], R, p)); }
    else if (d.kind === 'pistol') lh = m4.transformPoint([0, 0, 0], this.worldM, [-0.035, -0.08, -0.02]);
    return { rh, lh };
  }

  draw(r, shadowPass, hidden) {
    const d = this.def; if (!d || !this.meshes[this.item.def.weapon]) return;
    const set = this.meshes[this.item.def.weapon];
    const M = this.worldM;
    for (const p of set.parts) {
      // desloca o ferrolho/slide
      let m = M;
      if (d.kind === 'pistol' && (p.name || '').includes('slide') && this.slideBack > 0) { m = m4.multiply(m4.create(), M, m4.translation(m4.create(), 0, 0, this.slideBack * 0.035)); }
      if (d.kind === 'pistol' && (p.name || '').includes('magazine') && this.state === 'reload' && this.stateT > d.reloadStart * 0.15 && this.stateT < d.reloadStart * 0.55) m = m4.multiply(m4.create(), M, m4.translation(m4.create(), 0, -0.2, 0));
      r.draw(p.mesh, p.material, { model: m });
    }
    if (set.bolt.length) {
      const open = this.state === 'cycle' && this.boltPhase > 0.5 || this.state === 'reload' && this.stateT < this.reloadStartAt + 0.1;
      const parts = open ? set.bolt[1] : set.bolt[0];
      const back = this.state === 'cycle' ? this.boltPhase : 0;
      const m = m4.multiply(m4.create(), M, m4.translation(m4.create(), 0, 0, back * 0.07));
      for (const p of parts || []) r.draw(p.mesh, p.material, { model: m });
    }
  }
}
