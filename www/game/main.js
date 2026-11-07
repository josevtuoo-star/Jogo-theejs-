// Ponto de entrada: monta a engine, o mundo, o jogador e roda o laço principal.
import { Renderer } from '../engine/renderer.js';
import { Atmosphere } from '../engine/atmosphere.js';
import { Input } from '../engine/input.js';
import { AudioEngine } from '../engine/audio.js';
import { Physics, SURF } from '../engine/physics.js';
import { Particles, FRAME } from '../engine/particles.js';
import { m4, q4, v3, clamp, lerp, smoothstep, damp } from '../engine/math.js';
import { generateWorld, loadWorld, WORLD } from './worldgen.js';
import { Assets, MODEL_NAMES } from './assets.js';
import { Terrain } from './terrain.js';
import { Vegetation } from './vegetation.js';
import { Level } from './world.js';
import { Player } from './player.js';
import { WeaponSystem } from './weapons.js';
import { Character } from './character.js';
import { Vehicle } from './vehicle.js';
import { UI } from './ui.js';
import { bakeIcons } from './icons.js';

const PRESETS = {
  low: { renderScale: 0.55, shadows: 0, shadowSize: 1024, grass: 0, vegDist: 0.6 },
  medium: { renderScale: 0.68, shadows: 1, shadowSize: 1024, grass: 1, vegDist: 0.85 },
  high: { renderScale: 0.8, shadows: 2, shadowSize: 2048, grass: 2, vegDist: 1.0 },
  ultra: { renderScale: 1.0, shadows: 3, shadowSize: 2048, grass: 3, vegDist: 1.25 },
};
const Q = new URLSearchParams(location.search);

function loadSettings() {
  const touch = matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window;
  const base = { quality: 'high', ...PRESETS.high, renderScale: touch ? 0.72 : 0.9, fov: 74, sens: 1, invertY: false, volume: 0.8, showFps: true, debug: false, far: 1800, exposure: 1, aniso: 8, cap60: false, msaa: true, autoRes: touch };
  try { Object.assign(base, JSON.parse(localStorage.getItem('s2x2') || '{}')); } catch {}
  if (Q.get('quality')) Object.assign(base, PRESETS[Q.get('quality')] || {}, { quality: Q.get('quality') });
  if (Q.has('test')) Object.assign(base, { renderScale: 0.5, shadows: 1, shadowSize: 1024, grass: 0, vegDist: 0.8 });
  if (Q.get('scale')) base.renderScale = +Q.get('scale');
  if (Q.get('grass') !== null) base.grass = +Q.get('grass');
  if (Q.get('shadows') !== null && Q.get('shadows') !== undefined) base.shadows = +Q.get('shadows');
  return base;
}

class Game {
  constructor() {
    this.time = 0; this.shake = 0; this.vehicles = [];
    this.settings = loadSettings();
  }
  saveSettings() { try { localStorage.setItem('s2x2', JSON.stringify(this.settings)); } catch {} }
  applyPreset(name) {
    const S = this.settings, p = PRESETS[name]; if (!p) return;
    Object.assign(S, p, { quality: name }); this.r.settings.renderScale = S.renderScale; this.r.resize(); this.r.setShadowQuality(S.shadows, S.shadowSize);
    this.veg.setGrassQuality(S.grass); this.veg.distScale = S.vegDist;
  }

  async boot() {
    const S = this.settings;
    const T0 = performance.now(); this.bootTimes = {};
    const mark = (k) => { this.bootTimes[k] = Math.round(performance.now() - T0); };
    const canvas = document.getElementById('c');
    this.r = new Renderer(canvas, { renderScale: S.renderScale, shadows: S.shadows, shadowSize: S.shadowSize, antialias: S.msaa, preserve: Q.has('test') });
    const ui0 = { loading: (t, p) => { const f = document.getElementById('lfill'), x = document.getElementById('ltext'); if (f) f.style.width = Math.round(p * 100) + '%'; if (x) x.textContent = t; } };
    const step = async (t, p, fn) => { ui0.loading(t, p); await new Promise((r) => setTimeout(r, 16)); return fn(); };
    this.atm = new Atmosphere(); this.env = this.atm.env;
    if (Q.get('hour')) this.atm.hour = +Q.get('hour');
    if (Q.get('weather')) this.atm.setWeather(Q.get('weather'));
    if (Q.get('timescale')) this.atm.timeScale = +Q.get('timescale');
    this.input = new Input(canvas); this.input.sens = S.sens;
    this.audio = new AudioEngine(); this.audio.volume = S.volume;
    this.particles = new Particles(this.r);
    this.assets = new Assets(this.r.gl);
    await step('Texturas do terreno e materiais', 0.04, () => this.assets.loadTextures());
    this.r.matAlb = this.assets.matAlb; this.r.matNor = this.assets.matNor; mark('texturas');
    const wprog = (n, p) => ui0.loading('Mundo 2×2 km · ' + n, 0.1 + p * 0.3);
    try { if (Q.has('gen')) throw new Error('gen'); this.world = await loadWorld('assets/world/', wprog); this.worldBaked = true; }
    catch (e) { this.world = await generateWorld(1337, (n, p) => wprog('gerando ' + n, p)); }
    mark('mundo'); this.phys = new Physics(this.world); this.phys.waterY = WORLD.waterY;
    this.particles.groundFn = (x, z) => this.world.heightAt(x, z);
    let n = 0;
    await step('Modelos 3D (armas, itens, props)', 0.42, () => this.assets.loadModels(MODEL_NAMES, () => { n++; ui0.loading(`Modelos 3D ${n}/${MODEL_NAMES.length}`, 0.42 + (n / MODEL_NAMES.length) * 0.2); }));
    mark('modelos'); this.char = new Character(this, 0);
    await step('Personagem', 0.64, () => this.char.init());
    this.char.setup();
    this.level = new Level(this);
    await step('Construindo vilas, estradas e props', 0.68, async () => this.level.build((t, p) => ui0.loading(t, 0.68 + p * 0.1)));
    this.terrain = new Terrain(this.r, this.world, this.assets);
    await step('Plantando vegetação', 0.8, async () => { this.veg = new Vegetation(this.r, this.world, this.assets, { grass: S.grass, level: this.level, exclude: (x, z, m) => this.level.exclude(x, z, m) }); this.veg.terrain = this.terrain; this.veg.distScale = S.vegDist; });
    // colliders das árvores (troncos)
    for (const t of this.veg.trunks) this.phys.addCyl(t.x, t.z, t.r, t.y0, t.y1, SURF.WOOD, { tree: true });
    mark('vegetacao'); this.weapons = new WeaponSystem(this);
    this.weapons.prepare();
    this.phys.onProjectileHit = (p, hit, speed) => this.weapons.onHit(p, hit, speed);
    this.player = new Player(this);
    this.ui = new UI(this);
    this.player.ui = this.ui;
    await step('Ícones de inventário', 0.9, async () => { this.ui.icons = bakeIcons(this); });
    mark('icones'); this.player.reset();
    this.ui.renderQuick();
    // veículos de teste
    for (const s of this.level.vehicleSpots) this.vehicles.push(new Vehicle(this, s.x, s.z, s.yaw, this.vehicles.length * 3 + 1));
    this.level.vehicleSpots.length = 0;
    this.syncEquipment();
    // eventos
    this.input.wantLock = !this.input.touchMode;
    this.input.onLockChange = (locked) => { if (!locked && !this.ui.invOpen && !this.ui.menuOpen && this.started && !this.player.dead) this.ui.openMenu(); };
    const resume = () => this.audio.resume();
    addEventListener('pointerdown', resume); addEventListener('keydown', resume);
    addEventListener('resize', () => this.r.resize());
    document.addEventListener('visibilitychange', () => { this.hidden = document.hidden; });
    if (Q.get('pos')) { const [x, z] = Q.get('pos').split(',').map(Number); this.teleport(x, z); }
    if (Q.has('tp')) this.player.camMode = 'tp';
    if (Q.get('yaw')) this.player.yaw = +Q.get('yaw');
    if (Q.get('pitch')) this.player.pitch = +Q.get('pitch');
    if (Q.get('hold')) { const it = this.inv.all().find((i) => i.id === Q.get('hold')); if (it) this.player.wield(it); }
    mark('total'); console.log('boot ms', JSON.stringify(this.bootTimes));
    this.ui.loading('Pronto', 1);
    this.started = true;
    this.ui.loadDone();
    if (!this.input.touchMode) { this.ui.toast('Clique na tela para capturar o mouse · Esc abre o menu de testes'); }
    this.ui.toast('Mapa 2×2 km · sem zumbis · use o menu ☰ para testar tudo');
    if (Q.has('manual')) { window.game = this; return; }
    this.last = performance.now();
    requestAnimationFrame((t) => this.frame(t));
  }

  syncEquipment() { if (this.char && this.char.setEquipment) this.char.setEquipment(this.inv.slots); }
  teleport(x, z) { const P = this.player; if (P.inVehicle) P.exitVehicle(); P.pos[0] = x; P.pos[2] = z; P.pos[1] = this.world.heightAt(x, z) + 0.3; P.vel.fill(0); }
  respawn() { this.player.reset(); this.ui.renderQuick(); this.syncEquipment(); }
  spawnVehicle() {
    const P = this.player, d = P.aimDir();
    const x = P.pos[0] + d[0] * 6, z = P.pos[2] + d[2] * 6;
    const v = new Vehicle(this, x, z, Math.atan2(d[0], d[2]), this.vehicles.length * 3 + 2);
    this.vehicles.push(v); this.ui.toast('Veículo criado à frente');
  }

  // ---------------------------------------------------------------- quadro
  frame(t) {
    requestAnimationFrame((tt) => this.frame(tt));
    if (this.hidden) { this.last = t; return; }
    let dt = (t - this.last) / 1000;
    if (this.settings.cap60 && dt < 1 / 62) return;
    this.last = t;
    dt = Math.min(dt, 0.05);
    this.step(dt);
    this.render();
  }
  // resolução dinâmica: mantém o alvo de ~60 fps ajustando a escala de renderização
  adaptRes(dt) {
    const S = this.settings; if (!S.autoRes || Q.has('test')) return;
    this._ad = this._ad || { t: 0, n: 0, sum: 0, cool: 3 };
    const a = this._ad; a.t += dt; a.n++; a.sum += dt; a.cool -= dt;
    if (a.t < 1.0) return;
    const avg = a.sum / a.n; a.t = 0; a.n = 0; a.sum = 0;
    if (a.cool > 0) return;
    const lo = S.autoMin || 0.45, hi = PRESETS[S.quality] ? Math.max(PRESETS[S.quality].renderScale, S.renderScaleBase || 0) : 1;
    if (S.renderScaleBase === undefined) S.renderScaleBase = S.renderScale;
    const target = S.cap60 ? 1 / 58 : 1 / 54;
    if (avg > target * 1.18 && S.renderScale > lo) { S.renderScale = Math.max(lo, +(S.renderScale - 0.05).toFixed(2)); a.cool = 1.5; }
    else if (avg < target * 0.72 && S.renderScale < S.renderScaleBase) { S.renderScale = Math.min(S.renderScaleBase, +(S.renderScale + 0.03).toFixed(2)); a.cool = 4; }
    else return;
    this.r.settings.renderScale = S.renderScale; this.r.resize();
  }
  step(dt) {
    const S = this.settings, inp = this.input, P = this.player, W = this.weapons;
    this.time += dt;
    this.adaptRes(dt);
    inp.poll();
    // teclas globais
    if (inp.pressed('menu')) { this.ui.invOpen ? this.ui.closeInv() : this.ui.toggleMenu(); }
    if (inp.pressed('inventory')) { if (!this.ui.menuOpen) this.ui.toggleInv(); }
    if (inp.pressed('debug')) S.debug = !S.debug;
    if (inp.pressed('noclip')) { P.noclip = !P.noclip; this.ui.toast(P.noclip ? 'Modo voar ligado' : 'Modo voar desligado'); }
    if (inp.pressed('time')) { this.atm.hour = (this.atm.hour + 3) % 24; }
    if (inp.pressed('vehicle') && !P.inVehicle) this.spawnVehicle();
    if (S.invertY) inp.look[1] *= -1;
    // simulação
    this.atm.update(dt);
    this.phys.wind[0] = this.env.wind[0] * this.env.wind[2] * 6; this.phys.wind[1] = this.env.wind[1] * this.env.wind[2] * 6;
    this.env.exposure *= S.exposure;
    P.update(dt, inp);
    W.update(dt);
    this.phys.step(dt);
    this.level.update(dt);
    this.particles.update(dt);
    // faróis dos veículos
    this.env.lights[1] = this.env.lights[2] = null;
    for (const v of this.vehicles) {
      if (v.driver && v.lights) {
        const M = v.matrix(m4.create());
        for (const [i, sx] of [[1, -0.6], [2, 0.6]]) { const p = m4.transformPoint([0, 0, 0], M, [sx, 0.7, 2.2]); const f = [Math.sin(v.yaw), -0.06, Math.cos(v.yaw)]; this.env.lights[i] = { pos: p, dir: f, radius: 45, color: [1, 0.95, 0.8], intensity: 9, spot: true, cosOuter: Math.cos(0.55), cosInner: Math.cos(0.2) }; }
      }
      if (v.driver) this.audio.engine(v.rpm, Math.abs(v.input.throttle), 0.6); else if (this._engOn) this.audio.engine(0.1, 0, 0);
    }
    // dano de projétil ao jogador por queda de veículo: omitido
    // personagem
    this.updateCharacter(dt);
    // áudio
    if (!this._wt || this.time - this._wt > 0.4) { this._wt = this.time; this._nearW = this.nearWater(); }
    this.audio.update(dt, P.camPos, P.camYaw, { windStrength: this.env.wind[2], rain: this.atm.rainAmount, night: this.env.night, nearWater: this._nearW || 0 });
    if (this.atm.rainAmount > 0.01 && P.camPos) this.particles.updateRain(P.camPos, this.atm.rainAmount, dt, this.env.wind);
    else this.particles.rainN = 0;
    // interface
    this.ui.update(dt, this);
    inp.endFrame();
  }
  nearWater() {
    const P = this.player, w = this.world, lk = w.lake;
    const dl = Math.max(0, Math.hypot((P.pos[0] - lk.x) / lk.rx, (P.pos[2] - lk.z) / lk.rz) - 1) * Math.min(lk.rx, lk.rz);
    const r = w.riverIdx.nearest(P.pos[0], P.pos[2], 60);
    const dr = r ? Math.max(0, r.d - 6) : 999;
    return clamp(1 - Math.min(dl, dr) / 50, 0, 1);
  }

  updateCharacter(dt) {
    const P = this.player, W = this.weapons, C = this.char;
    if (P.inVehicle) { C.hidden = true; return; }
    C.hidden = false;
    const hasWeapon = !!P.hands;
    // viewmodel
    let wpn = null;
    if (hasWeapon && W.def) {
      W.computeWorld(P, dt);
      const hp = W.handPoints();
      if (hp) wpn = { rh: hp.rh, lh: hp.lh };
    } else if (hasWeapon) {
      // item na mão sem arma: segura à frente
      const dirq = q4.fromEuler(new Float32Array(4), P.aimYaw, P.aimPitch, 0);
      const m = m4.fromTRS(m4.create(), P.eye, dirq, null);
      wpn = { rh: m4.transformPoint([0, 0, 0], m, [0.2, -0.3, -0.45]), lh: m4.transformPoint([0, 0, 0], m, [-0.1, -0.3, -0.5]) };
      this.heldMatrix = m4.multiply(m4.create(), m, m4.translation(m4.create(), 0.2, -0.3, -0.45));
    }
    const st = {
      pos: P.pos, aimYaw: P.aimYaw, aimPitch: P.aimPitch, vel: [P.vel[0], P.vel[2]], stance: P.stance, prone: P.stance === 2, fp: P.camMode === 'fp',
      swimming: P.swimming, grounded: P.grounded, weapon: wpn, lean: P.lean, dead: P.dead,
    };
    C.g.time = this.time;
    C.update(dt, st);
  }

  // ---------------------------------------------------------------- desenho
  render() {
    const P = this.player, W = this.weapons, S = this.settings, r = this.r;
    let fov = S.fov * Math.PI / 180;
    if (W.def && W.def.adsFov) fov = lerp(fov, W.def.adsFov * Math.PI / 180, smoothstep(0, 1, W.adsT));
    if (P.zoomBino) fov = 12 * Math.PI / 180;
    fov += P.sprinting ? 0.06 : 0;
    r.settings.aniso = S.aniso;
    r.setCamera(P.camPos, P.camYaw, P.camPitch, fov, 0.05, S.far, P.camRoll || 0);
    r.setEnv(this.env);
    r.shadowSplits = [18 * Math.max(0.6, S.vegDist), 70, 240];
    const cam = P.camPos, me = this;
    r.render({
      drawShadow(rr, ci) {
        me.level.draw(rr, cam, true, me);
        me.veg.draw(rr, cam, true);
        me.drawActors(rr, true);
      },
      draw(rr) {
        me.terrain.draw(rr, cam, false);
        me.level.draw(rr, cam, false, me);
        me.veg.draw(rr, cam, false);
        me.veg.drawGrass(rr, cam);
        me.level.drawWires(rr);
        me.drawActors(rr, false);
      },
      drawTransparent(rr) { me.terrain.drawWater(rr); me.particles.draw(rr); },
    }, this.time);
  }
  drawActors(rr, shadow) {
    const P = this.player, W = this.weapons, C = this.char;
    if (!C.hidden && !(P.dead && false)) C.draw(rr, shadow);
    if (W.def && !C.hidden) W.draw(rr, shadow);
    else if (P.hands && this.heldMatrix && !C.hidden && P.hands.def.model) {
      const vis = this.level.itemVisual(P.hands.id);
      if (vis) for (const p of vis.parts) rr.draw(p.mesh, p.material, { model: this.heldMatrix });
    }
    for (const v of this.vehicles) v.draw(rr, this.level.carMeshes, this.level.carMatSet);
    for (const n of W.nades) { const m = m4.fromTRS(m4.create(), n.body.pos, n.body.q, null); const vis = this.level.itemVisual('grenade'); if (vis) { m[12] -= vis.center[0]; m[13] -= vis.center[1]; m[14] -= vis.center[2]; for (const p of vis.parts) rr.draw(p.mesh, p.material, { model: m }); } }
  }
}

const game = new Game();
window.game = game;
game.boot().catch((e) => { console.error(e); try { game.ui ? game.ui.loadError(e) : (document.getElementById('lerr').textContent = 'Erro: ' + e.message + '\n' + (e.stack || '').split('\n').slice(0, 4).join('\n')); } catch {} });
