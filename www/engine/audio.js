// Áudio procedural (WebAudio): tiros, passos, impactos, vento, chuva, pássaros, UI. Sem arquivos de som.
export class AudioEngine {
  constructor() {
    this.ctx = null; this.enabled = true; this.volume = 0.8;
    this.listener = { pos: [0, 0, 0], yaw: 0 };
    this.wind = 0.3; this.rain = 0; this.night = 0; this.nearWater = 0;
  }
  init() {
    if (this.ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) { this.enabled = false; return; }
    const ctx = this.ctx = new AC({ latencyHint: 'interactive' });
    this.master = ctx.createGain(); this.master.gain.value = this.volume;
    const comp = ctx.createDynamicsCompressor(); comp.threshold.value = -14; comp.ratio.value = 6;
    this.master.connect(comp); comp.connect(ctx.destination);
    // buffers de ruído
    const mk = (len, f) => { const b = ctx.createBuffer(1, ctx.sampleRate * len, ctx.sampleRate), d = b.getChannelData(0); f(d); return b; };
    this.white = mk(2, (d) => { for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1; });
    this.pink = mk(4, (d) => { let a = 0, b = 0, c = 0; for (let i = 0; i < d.length; i++) { const w = Math.random() * 2 - 1; a = 0.99765 * a + w * 0.099046; b = 0.963 * b + w * 0.2965164; c = 0.57 * c + w * 1.0526913; d[i] = (a + b + c + w * 0.1848) * 0.2; } });
    // reverb por impulso gerado
    const irLen = ctx.sampleRate * 2.2, ir = ctx.createBuffer(2, irLen, ctx.sampleRate);
    for (let ch = 0; ch < 2; ch++) { const d = ir.getChannelData(ch); for (let i = 0; i < irLen; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / irLen, 2.6); }
    this.reverb = ctx.createConvolver(); this.reverb.buffer = ir;
    this.revGain = ctx.createGain(); this.revGain.gain.value = 0.28;
    this.reverb.connect(this.revGain); this.revGain.connect(this.master);
    // loops de ambiente
    const loop = (buf, type, freq, q) => { const s = ctx.createBufferSource(); s.buffer = buf; s.loop = true; const f = ctx.createBiquadFilter(); f.type = type; f.frequency.value = freq; f.Q.value = q || 0.7; const g = ctx.createGain(); g.gain.value = 0; s.connect(f); f.connect(g); g.connect(this.master); s.start(); return { s, f, g }; };
    this.windL = loop(this.pink, 'lowpass', 500, 0.6);
    this.rainL = loop(this.white, 'highpass', 1800, 0.5);
    this.waterL = loop(this.pink, 'bandpass', 700, 0.4);
    this._birdT = 0;
  }
  resume() { if (!this.ctx) this.init(); if (this.ctx && this.ctx.state !== 'running') this.ctx.resume(); }
  setVolume(v) { this.volume = v; if (this.master) this.master.gain.value = v; }

  _pan(pos, maxDist = 400) {
    // retorna {pan, gain, delay, lp}
    const L = this.listener, dx = pos[0] - L.pos[0], dy = pos[1] - L.pos[1], dz = pos[2] - L.pos[2];
    const d = Math.hypot(dx, dy, dz);
    const rx = Math.cos(L.yaw), rz = -Math.sin(L.yaw);
    const pan = d > 0.5 ? Math.max(-1, Math.min(1, (dx * rx + dz * rz) / d)) : 0;
    return { pan, d, gain: 1 / (1 + d * 0.035) , delay: d / 343, lp: Math.max(900, 14000 / (1 + d * 0.05)) };
  }
  _out(pos, vol, extraDelay = 0, reverb = 0.3) {
    const ctx = this.ctx;
    const g = ctx.createGain();
    const p = pos ? this._pan(pos) : { pan: 0, gain: 1, delay: 0, lp: 16000, d: 0 };
    g.gain.value = vol * p.gain;
    let node = g;
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = p.lp;
    const pn = ctx.createStereoPanner ? ctx.createStereoPanner() : null; if (pn) pn.pan.value = p.pan;
    g.connect(lp); let last = lp; if (pn) { lp.connect(pn); last = pn; }
    last.connect(this.master);
    if (reverb > 0) { const rg = ctx.createGain(); rg.gain.value = reverb; last.connect(rg); rg.connect(this.reverb); }
    return { node: g, t0: ctx.currentTime + p.delay + extraDelay, dist: p.d };
  }
  _noise(out, t0, dur, buf, filt, f0, f1, q, gain, attack = 0.002) {
    const ctx = this.ctx, s = ctx.createBufferSource(); s.buffer = buf; s.loop = true;
    s.playbackRate.value = 0.8 + Math.random() * 0.4;
    const f = ctx.createBiquadFilter(); f.type = filt; f.frequency.setValueAtTime(f0, t0); f.frequency.exponentialRampToValueAtTime(Math.max(30, f1), t0 + dur); f.Q.value = q;
    const g = ctx.createGain(); g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(gain, t0 + attack); g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    s.connect(f); f.connect(g); g.connect(out); s.start(t0, Math.random()); s.stop(t0 + dur + 0.05);
  }
  _tone(out, t0, dur, f0, f1, type, gain) {
    const ctx = this.ctx, o = ctx.createOscillator(); o.type = type; o.frequency.setValueAtTime(f0, t0); o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t0 + dur);
    const g = ctx.createGain(); g.gain.setValueAtTime(gain, t0); g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    o.connect(g); g.connect(out); o.start(t0); o.stop(t0 + dur + 0.02);
  }

  // tipos: rifle, pistol, shotgun
  shot(type, pos, silenced = false) {
    if (!this.ctx || !this.enabled) return;
    const o = this._out(pos, type === 'rifle' ? 1.1 : type === 'shotgun' ? 1.2 : 0.8, 0, type === 'pistol' ? 0.35 : 0.6), t = o.t0;
    const vol = silenced ? 0.25 : 1;
    if (type === 'rifle') {
      this._noise(o.node, t, 0.55, this.white, 'lowpass', 7000, 250, 0.7, 1.0 * vol);
      this._noise(o.node, t, 0.12, this.white, 'bandpass', 2500, 900, 1.2, 0.9 * vol);
      this._tone(o.node, t, 0.35, 140, 38, 'sine', 1.3 * vol);
      this._noise(o.node, t + 0.05, 1.2, this.pink, 'lowpass', 900, 120, 0.5, 0.4 * vol, 0.03);
    } else if (type === 'shotgun') {
      this._noise(o.node, t, 0.7, this.white, 'lowpass', 5000, 160, 0.6, 1.2 * vol);
      this._tone(o.node, t, 0.45, 100, 30, 'sine', 1.5 * vol);
      this._noise(o.node, t + 0.03, 1.0, this.pink, 'lowpass', 700, 100, 0.5, 0.5 * vol, 0.03);
    } else {
      this._noise(o.node, t, 0.28, this.white, 'bandpass', 3200, 800, 0.9, 0.9 * vol);
      this._tone(o.node, t, 0.2, 220, 60, 'triangle', 0.8 * vol);
      this._noise(o.node, t + 0.02, 0.5, this.pink, 'lowpass', 1500, 200, 0.5, 0.25 * vol, 0.02);
    }
  }
  dryFire(pos) { this.click(pos, 0.5, 2400); }
  click(pos, vol = 0.4, f = 1800) {
    if (!this.ctx) return; const o = this._out(pos, vol, 0, 0.05), t = o.t0;
    this._noise(o.node, t, 0.04, this.white, 'bandpass', f, f * 0.7, 3, 1, 0.001);
    this._tone(o.node, t, 0.03, f * 0.6, f * 0.4, 'square', 0.12);
  }
  reload(pos, kind = 'mag') {
    if (!this.ctx) return; const o = this._out(pos, 0.6, 0, 0.1), t = o.t0;
    const seq = kind === 'bolt' ? [0, 0.25, 0.55, 0.95] : kind === 'shell' ? [0, 0.2] : [0, 0.35, 0.8, 1.15];
    seq.forEach((dt, i) => { this._noise(o.node, t + dt, 0.06, this.white, 'bandpass', 1400 + i * 400, 900, 4, 0.9, 0.001); this._tone(o.node, t + dt, 0.05, 700 - i * 80, 300, 'square', 0.12); });
  }
  bolt(pos) { this.reload(pos, 'bolt'); }
  step(surf, vol = 1, pos = null) {
    if (!this.ctx) return; const o = this._out(pos, 0.5 * vol, 0, 0.05), t = o.t0;
    const S = { 0: ['lowpass', 520, 0.35], 1: ['lowpass', 700, 0.3], 2: ['bandpass', 900, 0.4], 3: ['bandpass', 1800, 0.35], 4: ['bandpass', 1300, 0.4], 5: ['lowpass', 1100, 0.5], 6: ['bandpass', 1500, 0.35], 8: ['lowpass', 450, 0.3] };
    const [ty, f, g] = S[surf] || S[0];
    this._noise(o.node, t, 0.13, this.white, ty, f * 1.3, f * 0.5, 0.8, g * 1.2, 0.004);
    this._tone(o.node, t, 0.1, 90, 55, 'sine', 0.35 * g);
  }
  jump(pos) { this.step(1, 1.2, pos); }
  land(speed, surf = 1) { this.step(surf, Math.min(2.5, 0.8 + speed * 0.15)); this._tone(this._out(null, 0.7, 0, 0.1).node, this.ctx.currentTime, 0.2, 90, 35, 'sine', 0.8); }
  impact(surf, pos) {
    if (!this.ctx) return; const o = this._out(pos, 0.7, 0, 0.2), t = o.t0;
    if (surf === 3) { this._noise(o.node, t, 0.25, this.white, 'bandpass', 3500, 2400, 6, 0.8, 0.001); this._tone(o.node, t, 0.2, 1700, 900, 'triangle', 0.25); }
    else if (surf === 2) { this._noise(o.node, t, 0.12, this.white, 'bandpass', 900, 500, 2, 1.0, 0.001); this._tone(o.node, t, 0.1, 200, 90, 'sine', 0.6); }
    else if (surf === 4) { this._noise(o.node, t, 0.15, this.white, 'bandpass', 2200, 1200, 2.5, 0.9, 0.001); }
    else if (surf === 5) { this._noise(o.node, t, 0.3, this.white, 'lowpass', 2500, 400, 0.7, 0.7, 0.003); }
    else { this._noise(o.node, t, 0.12, this.white, 'lowpass', 1200, 300, 0.7, 0.8, 0.001); }
  }
  whiz(pos) { if (!this.ctx) return; const o = this._out(pos, 0.6, 0, 0.1); this._noise(o.node, o.t0, 0.18, this.white, 'bandpass', 5000, 1500, 3, 0.5, 0.01); }
  explosion(pos) {
    if (!this.ctx) return; const o = this._out(pos, 1.6, 0, 0.8), t = o.t0;
    this._noise(o.node, t, 1.6, this.white, 'lowpass', 3500, 80, 0.6, 1.5, 0.003);
    this._tone(o.node, t, 1.0, 90, 24, 'sine', 2);
    this._noise(o.node, t + 0.1, 2.5, this.pink, 'lowpass', 500, 60, 0.5, 0.9, 0.05);
  }
  thud(pos, vol = 0.6, surf = 2) { if (!this.ctx) return; const o = this._out(pos, vol, 0, 0.1); this._tone(o.node, o.t0, 0.12, surf === 3 ? 380 : 140, 60, surf === 3 ? 'triangle' : 'sine', 0.9); this._noise(o.node, o.t0, 0.06, this.white, 'bandpass', surf === 3 ? 2400 : 700, 500, 2, 0.5, 0.001); }
  eat() { if (!this.ctx) return; const o = this._out(null, 0.5, 0, 0.05); for (let i = 0; i < 5; i++) this._noise(o.node, o.t0 + i * 0.16, 0.08, this.white, 'bandpass', 1500 + Math.random() * 600, 700, 2, 0.9, 0.003); }
  drink() { if (!this.ctx) return; const o = this._out(null, 0.5, 0, 0.05); for (let i = 0; i < 4; i++) { this._tone(o.node, o.t0 + i * 0.22, 0.14, 300 + i * 30, 160, 'sine', 0.35); this._noise(o.node, o.t0 + i * 0.22, 0.1, this.white, 'lowpass', 900, 400, 0.7, 0.35, 0.01); } }
  bandage() { if (!this.ctx) return; const o = this._out(null, 0.5, 0, 0.05); this._noise(o.node, o.t0, 0.7, this.white, 'bandpass', 3000, 5000, 1.5, 0.6, 0.02); }
  hurt() { if (!this.ctx) return; const o = this._out(null, 0.7, 0, 0.2); this._tone(o.node, o.t0, 0.25, 190, 110, 'sawtooth', 0.4); this._noise(o.node, o.t0, 0.15, this.white, 'bandpass', 700, 400, 1, 0.5); }
  ui(kind = 'tap') { if (!this.ctx) return; const o = this._out(null, 0.25, 0, 0); this._tone(o.node, o.t0, 0.06, kind === 'ok' ? 900 : 600, kind === 'ok' ? 1300 : 500, 'sine', 0.5); }
  splash(pos) { if (!this.ctx) return; const o = this._out(pos, 0.9, 0, 0.3); this._noise(o.node, o.t0, 0.6, this.white, 'lowpass', 3000, 300, 0.7, 0.9, 0.01); }
  engine(rpm, load, vol) {
    if (!this.ctx) return;
    if (!this._eng) { const ctx = this.ctx; const o1 = ctx.createOscillator(), o2 = ctx.createOscillator(); o1.type = 'sawtooth'; o2.type = 'square'; const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 600; const g = ctx.createGain(); g.gain.value = 0; o1.connect(f); o2.connect(f); f.connect(g); g.connect(this.master); o1.start(); o2.start(); this._eng = { o1, o2, f, g }; }
    const e = this._eng, t = this.ctx.currentTime;
    const hz = 18 + rpm * 62;
    e.o1.frequency.setTargetAtTime(hz, t, 0.05); e.o2.frequency.setTargetAtTime(hz * 0.5, t, 0.05);
    e.f.frequency.setTargetAtTime(300 + rpm * 900 + load * 700, t, 0.08);
    e.g.gain.setTargetAtTime(vol * (0.05 + 0.1 * load), t, 0.1);
  }

  // por frame
  update(dt, cam, yaw, env) {
    if (!this.ctx) return;
    this.listener.pos = cam; this.listener.yaw = yaw;
    const t = this.ctx.currentTime;
    this.windL.g.gain.setTargetAtTime(0.03 + env.windStrength * 0.16, t, 0.5);
    this.windL.f.frequency.setTargetAtTime(280 + env.windStrength * 700 + Math.sin(t * 0.3) * 120, t, 0.4);
    this.rainL.g.gain.setTargetAtTime(env.rain * 0.12, t, 0.6);
    this.waterL.g.gain.setTargetAtTime(env.nearWater * 0.14, t, 0.3);
    // pássaros (dia)
    this._birdT -= dt;
    if (this._birdT <= 0 && env.night < 0.5 && env.rain < 0.3) {
      this._birdT = 1.2 + Math.random() * 5;
      const ang = Math.random() * 6.28, d = 20 + Math.random() * 60;
      const o = this._out([cam[0] + Math.cos(ang) * d, cam[1] + 8, cam[2] + Math.sin(ang) * d], 0.25, 0, 0.3), t0 = o.t0;
      const n = 2 + (Math.random() * 4 | 0), base = 2200 + Math.random() * 2200;
      for (let i = 0; i < n; i++) this._tone(o.node, t0 + i * 0.11, 0.08, base, base * (1.1 + Math.random() * 0.4), 'sine', 0.5);
    } else if (this._birdT <= 0 && env.night > 0.6) {
      this._birdT = 4 + Math.random() * 8; // grilos
      const o = this._out(null, 0.05, 0, 0.1); for (let i = 0; i < 8; i++) this._tone(o.node, o.t0 + i * 0.05, 0.03, 4200, 4200, 'sine', 0.3);
    }
  }
}
