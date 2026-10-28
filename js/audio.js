// Sons procedurais com Web Audio (sem arquivos): passos, pulo, pouso, golpe e vento.

export class GameAudio {
  constructor() {
    this.ctx = null;
    this.master = null;
  }

  /** Precisa ser chamado a partir de um gesto do usuário (clique/toque). */
  unlock() {
    if (this.ctx) { this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    this.ctx = new AC();
    this.master = this.ctx.createGain();
    this.master.gain.value = 0.6;
    this.master.connect(this.ctx.destination);

    const len = this.ctx.sampleRate * 2;
    this.noise = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const d = this.noise.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;

    this._startWind();
  }

  suspend() { this.ctx?.suspend(); }

  _burst({ duration = 0.12, freq = 600, q = 1, gain = 0.3, type = 'lowpass', attack = 0.005 }) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const src = this.ctx.createBufferSource();
    src.buffer = this.noise;
    src.playbackRate.value = 0.8 + Math.random() * 0.4;
    const f = this.ctx.createBiquadFilter();
    f.type = type;
    f.frequency.value = freq;
    f.Q.value = q;
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(gain, t + attack);
    g.gain.exponentialRampToValueAtTime(0.001, t + duration);
    src.connect(f).connect(g).connect(this.master);
    src.start(t, Math.random() * 1.5);
    src.stop(t + duration + 0.05);
  }

  step(run, crouch) {
    const gain = crouch ? 0.08 : run ? 0.32 : 0.2;
    this._burst({ duration: run ? 0.14 : 0.11, freq: 380 + Math.random() * 220, q: 0.8, gain });
    this._burst({ duration: 0.05, freq: 2400, q: 1.5, gain: gain * 0.25, type: 'bandpass' }); // folhas/cascalho
  }

  jump() {
    this._burst({ duration: 0.08, freq: 500, gain: 0.15 });
  }

  land(speed) {
    const k = Math.min(speed / 15, 1);
    this._burst({ duration: 0.18 + k * 0.15, freq: 220 + k * 120, q: 0.7, gain: 0.25 + k * 0.4 });
  }

  swing() {
    this._burst({ duration: 0.18, freq: 1800, q: 2.5, gain: 0.12, type: 'bandpass', attack: 0.06 });
  }

  click() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const o = this.ctx.createOscillator();
    const g = this.ctx.createGain();
    o.frequency.value = 1800;
    g.gain.setValueAtTime(0.08, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.04);
    o.connect(g).connect(this.master);
    o.start(t);
    o.stop(t + 0.05);
  }

  _startWind() {
    const src = this.ctx.createBufferSource();
    src.buffer = this.noise;
    src.loop = true;
    const f = this.ctx.createBiquadFilter();
    f.type = 'bandpass';
    f.frequency.value = 400;
    f.Q.value = 0.6;
    const g = this.ctx.createGain();
    g.gain.value = 0.05;
    // variação lenta da intensidade e do tom do vento
    const lfo = this.ctx.createOscillator();
    lfo.frequency.value = 0.07;
    const lfoGain = this.ctx.createGain();
    lfoGain.gain.value = 180;
    lfo.connect(lfoGain).connect(f.frequency);
    lfo.start();
    src.connect(f).connect(g).connect(this.master);
    src.start();
  }
}
