// Áudio: amostras reais (CC0: Kenney, OpenGameArt) + loops de ambiente + alguns sons sintetizados leves.
// O AudioContext é criado cedo e "destravado" em qualquer gesto válido (no toque, pointerup/touchend/click contam; pointerdown não).
const FILES = {
  car_engine: 'car_engine.ogg', car_skid: 'car_skid.ogg', car_impact: 'car_impact.ogg',
  jump_0: 'jump_a.ogg', jump_1: 'jump_b.ogg', jump_2: 'jump_c.ogg', land_0: 'land.ogg',
  step_grass_0: 'step_grass_0.ogg', step_grass_1: 'step_grass_1.ogg', step_dirt_0: 'step_dirt_0.ogg', step_dirt_1: 'step_dirt_1.ogg',
  step_gravel_0: 'step_gravel_0.ogg', step_stone_0: 'step_stone_0.ogg', step_stone_1: 'step_stone_1.ogg', step_stone_2: 'step_stone_2.ogg',
  step_wood_0: 'step_wood_0.ogg', step_wood_1: 'step_wood_1.ogg', step_wood_2: 'step_wood_2.ogg',
  step_water_0: 'step_water_0.ogg', step_water_1: 'step_water_1.ogg', step_water_2: 'step_water_2.ogg',
  hit_wood_0: 'hit_wood_0.ogg', hit_wood_1: 'hit_wood_1.ogg', hit_wood_2: 'hit_wood_2.ogg', hit_wood_3: 'hit_wood_3.ogg',
  hit_rock_0: 'hit_rock_0.ogg', hit_rock_1: 'hit_rock_1.ogg', hit_rock_2: 'hit_rock_2.ogg',
  break_rock_0: 'break_rock_0.ogg', break_rock_1: 'break_rock_1.ogg', break_wood_0: 'break_wood_0.ogg', tree_fall_0: 'tree_fall.ogg',
  swing_0: 'swing_0.ogg', swing_1: 'swing_1.ogg', pickup_0: 'pickup_0.ogg', pickup_1: 'pickup_1.ogg', click_0: 'click.ogg',
  drop_0: 'drop_0.ogg', drop_1: 'drop_1.ogg', drop_2: 'drop_2.ogg', drop_metal_0: 'drop_metal.ogg', thunder_0: 'thunder.ogg',
  amb_water: 'amb_water.ogg', amb_day: 'amb_day.ogg', amb_rain: 'amb_rain.ogg', amb_forest: 'amb_forest.mp3',
};
const SURF_STEP = { 0: ['step_dirt', 1], 1: ['step_grass', 1], 2: ['step_wood', 1], 3: ['step_stone', 1.15], 4: ['step_stone', 1], 5: ['step_water', 1], 6: ['step_stone', 0.95], 8: ['step_gravel', 0.9] };
const SURF_HIT = { 0: 'drop', 1: 'drop', 2: 'hit_wood', 3: 'drop_metal', 4: 'hit_rock', 6: 'hit_rock', 8: 'drop' };

export class AudioEngine {
  constructor(base = 'assets/audio/') {
    this.base = base; this.ctx = null; this.enabled = true; this.volume = 0.8;
    this.buffers = {}; this.groups = {}; this.loops = {};
    this.listener = { pos: [0, 0, 0], yaw: 0 };
    this._birdT = 0; this._thunderT = 25; this._loading = null; this.unlocked = false;
  }
  init() {
    if (this.ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) { this.enabled = false; return; }
    const ctx = this.ctx = new AC({ latencyHint: 'interactive' });
    this.master = ctx.createGain(); this.master.gain.value = this.volume;
    const comp = ctx.createDynamicsCompressor(); comp.threshold.value = -16; comp.ratio.value = 4; comp.attack.value = 0.005; comp.release.value = 0.2;
    this.master.connect(comp); comp.connect(ctx.destination);
    // ruído sintético apenas para sons curtos (comer/beber) e vento
    const mk = (len, f) => { const b = ctx.createBuffer(1, ctx.sampleRate * len, ctx.sampleRate), d = b.getChannelData(0); f(d); return b; };
    this.white = mk(2, (d) => { for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1; });
    this.pink = mk(4, (d) => { let a = 0, b = 0, c = 0; for (let i = 0; i < d.length; i++) { const w = Math.random() * 2 - 1; a = 0.99765 * a + w * 0.099046; b = 0.963 * b + w * 0.2965164; c = 0.57 * c + w * 1.0526913; d[i] = (a + b + c + w * 0.1848) * 0.2; } });
    const wind = ctx.createBufferSource(); wind.buffer = this.pink; wind.loop = true;
    const wf = ctx.createBiquadFilter(); wf.type = 'lowpass'; wf.frequency.value = 400; const wg = ctx.createGain(); wg.gain.value = 0;
    wind.connect(wf); wf.connect(wg); wg.connect(this.master); wind.start();
    this.wind = { f: wf, g: wg };
    this._loadAll();
  }
  async _loadAll() {
    if (this._loading) return this._loading;
    const ctx = this.ctx;
    this._loading = Promise.all(Object.entries(FILES).map(async ([key, file]) => {
      try {
        const r = await fetch(this.base + file); if (!r.ok) return;
        const ab = await r.arrayBuffer();
        this.buffers[key] = await new Promise((res, rej) => ctx.decodeAudioData(ab, res, rej));
        const g = key.replace(/_\d+$/, ''); (this.groups[g] = this.groups[g] || []).push(key);
      } catch (e) { /* som opcional */ }
    })).then(() => { this._startLoops(); });
    return this._loading;
  }
  // chamado em QUALQUER gesto (pointerup/touchend/click/keydown): destrava o áudio
  unlock() {
    if (!this.ctx) this.init();
    const ctx = this.ctx; if (!ctx) return;
    if (ctx.state !== 'running') ctx.resume().catch(() => {});
    if (!this.unlocked) {
      try { const s = ctx.createBufferSource(); s.buffer = ctx.createBuffer(1, 1, 22050); s.connect(ctx.destination); s.start(0); } catch (e) { /* ok */ }
      this.unlocked = true;
    }
  }
  resume() { this.unlock(); }
  setVolume(v) { this.volume = v; if (this.master) this.master.gain.value = v; }

  _pan(pos) {
    const L = this.listener, dx = pos[0] - L.pos[0], dy = pos[1] - L.pos[1], dz = pos[2] - L.pos[2];
    const d = Math.hypot(dx, dy, dz), rx = Math.cos(L.yaw), rz = -Math.sin(L.yaw);
    return { pan: d > 0.5 ? Math.max(-1, Math.min(1, (dx * rx + dz * rz) / d)) : 0, gain: 1 / (1 + d * d * 0.012), d };
  }
  // toca uma amostra ou grupo (variação aleatória). opts: vol, rate, pos
  play(name, o = {}) {
    const ctx = this.ctx; if (!ctx || !this.enabled || ctx.state !== 'running') return null;
    let key = name;
    if (!this.buffers[key]) { const g = this.groups[name]; if (!g || !g.length) return null; key = g[(Math.random() * g.length) | 0]; }
    const src = ctx.createBufferSource(); src.buffer = this.buffers[key];
    src.playbackRate.value = (o.rate ?? 1) * (o.jitter === false ? 1 : 0.95 + Math.random() * 0.1);
    const g = ctx.createGain(); let vol = o.vol ?? 1;
    let pan = null;
    if (o.pos) { const p = this._pan(o.pos); vol *= p.gain; if (ctx.createStereoPanner) { pan = ctx.createStereoPanner(); pan.pan.value = p.pan; } }
    g.gain.value = vol;
    src.connect(g); if (pan) { g.connect(pan); pan.connect(this.master); } else g.connect(this.master);
    src.start(ctx.currentTime + (o.delay || 0));
    return src;
  }
  _loop(key, vol = 0) {
    if (this.loops[key] || !this.buffers[key]) return this.loops[key];
    const ctx = this.ctx, s = ctx.createBufferSource(); s.buffer = this.buffers[key]; s.loop = true;
    const g = ctx.createGain(); g.gain.value = vol; s.connect(g); g.connect(this.master); s.start(0, Math.random() * Math.min(10, s.buffer.duration * 0.5));
    return (this.loops[key] = { s, g });
  }
  _startLoops() { for (const k of ['amb_day', 'amb_forest', 'amb_rain', 'amb_water']) this._loop(k, 0); }
  _setLoop(key, v, tc = 0.8) { const l = this.loops[key]; if (l) l.g.gain.setTargetAtTime(v, this.ctx.currentTime, tc); }

  // ---------------------------------------------------------------- sons do jogo
  step(surf, vol = 1, crouch = false) {
    const [g, rate] = SURF_STEP[surf] || SURF_STEP[1];
    this.play(g, { vol: (crouch ? 0.35 : 0.7) * vol, rate: rate * (crouch ? 0.95 : 1) });
  }
  jump() { this.play('jump', { vol: 0.5 }); }
  land(speed, surf = 1) { this.play('land', { vol: Math.min(1, 0.4 + speed * 0.08) }); this.step(surf, Math.min(1.6, 0.8 + speed * 0.1)); }
  hit(surf, vol = 1, pos = null) { this.play(SURF_HIT[surf] || 'drop', { vol: 0.9 * vol, pos }); }
  chopTree(pos) { this.play('hit_wood', { vol: 1, rate: 0.9, pos }); }
  mineRock(pos) { this.play('hit_rock', { vol: 1, rate: 0.9, pos }); }
  breakRock(pos) { this.play('break_rock', { vol: 1, pos }); }
  treeFall(pos) { this.play('tree_fall', { vol: 1, pos, jitter: false }); this.play('break_wood', { vol: 0.8, pos, delay: 0.1 }); }
  swing() { this.play('swing', { vol: 0.8 }); }
  pickup() { this.play('pickup', { vol: 0.8 }); }
  click(pos, vol = 0.5) { this.play('click', { vol }); }
  ui(kind = 'tap') { this.play('click', { vol: kind === 'ok' ? 0.55 : 0.4, rate: kind === 'ok' ? 1.25 : 1 }); }
  drop(speed, pos, metal = false) { this.play(metal ? 'drop_metal' : 'drop', { vol: Math.min(1, 0.15 + speed * 0.08), pos }); }
  splash(pos) { this.play('step_water', { vol: 1, rate: 0.7, pos }); }
  carImpact(v) { this.play('car_impact', { vol: Math.min(1, 0.3 + v * 0.05) }); }
  thunder() { this.play('thunder', { vol: 0.8, jitter: false }); }
  // sons curtos sintetizados (comer/beber/curativo/dor): sem amostra CC0 adequada no pacote
  _env(dur, gain, f0, f1, type, q, buf) {
    const ctx = this.ctx; if (!ctx || ctx.state !== 'running') return;
    const t0 = ctx.currentTime, s = ctx.createBufferSource(); s.buffer = buf || this.white; s.loop = true;
    const f = ctx.createBiquadFilter(); f.type = type; f.frequency.setValueAtTime(f0, t0); f.frequency.exponentialRampToValueAtTime(Math.max(40, f1), t0 + dur); f.Q.value = q;
    const g = ctx.createGain(); g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(gain, t0 + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    s.connect(f); f.connect(g); g.connect(this.master); s.start(t0, Math.random()); s.stop(t0 + dur + 0.05);
  }
  eat() { for (let i = 0; i < 5; i++) setTimeout(() => this._env(0.09, 0.5, 1700, 800, 'bandpass', 2), i * 170); }
  drink() { for (let i = 0; i < 4; i++) setTimeout(() => this._env(0.16, 0.35, 900, 350, 'lowpass', 0.8), i * 230); }
  bandage() { this._env(0.7, 0.4, 3000, 5200, 'bandpass', 1.5); }
  hurt() { this._env(0.2, 0.5, 600, 250, 'bandpass', 1); this.play('drop', { vol: 0.6, rate: 0.7 }); }

  // motor do carro: loop da amostra com taxa proporcional à rotação
  engine(rpm, load, vol) {
    if (!this.ctx || !this.buffers.car_engine) return;
    let l = this.loops.car_engine; if (!l) l = this._loop('car_engine', 0); if (!l) return;
    const t = this.ctx.currentTime;
    l.s.playbackRate.setTargetAtTime(0.55 + rpm * 1.5, t, 0.08);
    l.g.gain.setTargetAtTime(vol * (0.25 + 0.5 * load), t, 0.1);
  }
  skid(amount) {
    if (!this.ctx || !this.buffers.car_skid) return;
    let l = this.loops.car_skid; if (!l) l = this._loop('car_skid', 0); if (!l) return;
    l.g.gain.setTargetAtTime(Math.min(0.8, amount), this.ctx.currentTime, 0.05);
  }

  // por frame: ambiente conforme hora/clima/lugar
  update(dt, cam, yaw, env) {
    const ctx = this.ctx; if (!ctx) return;
    if (ctx.state !== 'running') { ctx.resume().catch(() => {}); return; }
    this.listener.pos = cam; this.listener.yaw = yaw;
    const day = 1 - env.night, rain = env.rain;
    this._setLoop('amb_day', 0.55 * day * (1 - rain * 0.85));
    this._setLoop('amb_forest', 0.45 * env.night * (1 - rain * 0.5));
    this._setLoop('amb_rain', 0.85 * rain);
    this._setLoop('amb_water', 0.8 * env.nearWater, 0.4);
    const t = ctx.currentTime;
    this.wind.g.gain.setTargetAtTime(0.02 + env.windStrength * 0.1, t, 0.6);
    this.wind.f.frequency.setTargetAtTime(260 + env.windStrength * 600 + Math.sin(t * 0.3) * 100, t, 0.5);
    if (rain > 0.7) { this._thunderT -= dt; if (this._thunderT <= 0) { this.thunder(); this._thunderT = 18 + Math.random() * 40; } }
    if (!env.driving) { this._setLoop('car_engine', 0, 0.2); this._setLoop('car_skid', 0, 0.1); }
  }
}
