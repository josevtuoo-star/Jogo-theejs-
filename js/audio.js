// Sons procedurais com Web Audio (sem arquivos): passos por tipo de piso, pulo, pouso,
// escalada, escada de mão, deslize, rolamento, golpe, dor, vento (abafado em ambientes
// fechados), pássaros e corvos ao longe e o crepitar da fogueira.

export class GameAudio {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.volume = 0.7;
    this.birdTimer = 3;
    this.crackleTimer = 0;
    this.indoor = 0;
  }

  /** Precisa ser chamado a partir de um gesto do usuário (clique/toque). */
  unlock() {
    if (this.ctx) { this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    this.ctx = new AC();
    this.master = this.ctx.createGain();
    this.master.gain.value = this.volume;
    this.master.connect(this.ctx.destination);

    const len = this.ctx.sampleRate * 2;
    this.noise = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const d = this.noise.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;

    this._startWind();
  }

  setVolume(v) {
    this.volume = v;
    if (this.master) this.master.gain.value = v;
  }

  suspend() { this.ctx?.suspend(); }

  _burst({ duration = 0.12, freq = 600, q = 1, gain = 0.3, type = 'lowpass', attack = 0.005, delay = 0, rate = 1 }) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime + delay;
    const src = this.ctx.createBufferSource();
    src.buffer = this.noise;
    src.playbackRate.value = rate * (0.85 + Math.random() * 0.3);
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

  _tone(freq, duration, gain, type = 'sine', delay = 0, slide = 1, pan = 0, filterFreq = 0) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime + delay;
    const o = this.ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (slide !== 1) o.frequency.exponentialRampToValueAtTime(freq * slide, t + duration);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(0.0008, t);
    g.gain.exponentialRampToValueAtTime(gain, t + Math.min(0.01, duration * 0.2));
    g.gain.exponentialRampToValueAtTime(0.0008, t + duration);
    let node = o.connect(g);
    if (filterFreq) {
      const f = this.ctx.createBiquadFilter();
      f.type = 'bandpass';
      f.frequency.value = filterFreq;
      f.Q.value = 1.5;
      node = node.connect(f);
    }
    if (pan && this.ctx.createStereoPanner) {
      const p = this.ctx.createStereoPanner();
      p.pan.value = pan;
      node = node.connect(p);
    }
    node.connect(this.master);
    o.start(t);
    o.stop(t + duration + 0.02);
  }

  step(surface = 'grass', run = false, crouch = false) {
    const k = crouch ? 0.35 : run ? 1.3 : 1;
    switch (surface) {
      case 'concrete':
        this._burst({ duration: 0.05, freq: 1400 + Math.random() * 400, q: 0.9, gain: 0.22 * k, type: 'bandpass' });
        this._burst({ duration: 0.06, freq: 260, gain: 0.18 * k });
        break;
      case 'wood':
        this._burst({ duration: 0.1, freq: 320 + Math.random() * 80, q: 5, gain: 0.5 * k, type: 'bandpass' });
        this._tone(140 + Math.random() * 30, 0.08, 0.12 * k, 'triangle');
        break;
      case 'metal':
        this._burst({ duration: 0.05, freq: 2500, q: 2, gain: 0.15 * k, type: 'bandpass' });
        this._tone(480 + Math.random() * 60, 0.25, 0.05 * k, 'sine');
        this._tone(1270 + Math.random() * 90, 0.18, 0.025 * k, 'sine');
        break;
      default: // grama / terra
        this._burst({ duration: run ? 0.14 : 0.11, freq: 380 + Math.random() * 220, q: 0.8, gain: 0.2 * k });
        this._burst({ duration: 0.07, freq: 3200, q: 1.2, gain: 0.06 * k, type: 'bandpass', delay: 0.01 });
    }
  }

  jump() {
    this._burst({ duration: 0.08, freq: 500, gain: 0.15 });
  }

  land(speed, surface = 'grass') {
    const k = Math.min(speed / 15, 1);
    this._burst({ duration: 0.18 + k * 0.15, freq: 220 + k * 120, q: 0.7, gain: 0.25 + k * 0.4 });
    if (surface !== 'grass') this.step(surface, true);
  }

  climb() {
    // roupa raspando + apoio das mãos
    this._burst({ duration: 0.35, freq: 1300, q: 0.7, gain: 0.12, type: 'bandpass', attack: 0.08 });
    this._burst({ duration: 0.07, freq: 400, gain: 0.25, delay: 0.05 });
    this.breath(0.6);
  }

  ladderStep() {
    this._tone(620 + Math.random() * 80, 0.14, 0.05, 'triangle');
    this._burst({ duration: 0.05, freq: 2200, q: 2, gain: 0.12, type: 'bandpass' });
  }

  slide() {
    this._burst({ duration: 0.7, freq: 900, q: 0.6, gain: 0.3, attack: 0.04, rate: 0.7 });
    this._burst({ duration: 0.5, freq: 3000, q: 1, gain: 0.06, type: 'bandpass', attack: 0.05 });
  }

  roll() {
    this._burst({ duration: 0.4, freq: 600, q: 0.7, gain: 0.3, attack: 0.03 });
    this._burst({ duration: 0.12, freq: 180, gain: 0.35, delay: 0.25 });
  }

  /** Pássaro cantando ao longe (posição estéreo aleatória). */
  _bird() {
    const pan = Math.random() * 1.6 - 0.8;
    const base = 2300 + Math.random() * 1500;
    const notes = 2 + Math.floor(Math.random() * 4);
    for (let i = 0; i < notes; i++) {
      this._tone(base * (0.9 + Math.random() * 0.25), 0.09, 0.02, 'sine', i * 0.13, 1.25, pan);
    }
  }

  /** Corvo grasnando ao longe. */
  _crow() {
    const pan = Math.random() * 1.6 - 0.8;
    const n = 1 + Math.floor(Math.random() * 3);
    for (let i = 0; i < n; i++) {
      this._tone(430 + Math.random() * 40, 0.32, 0.035, 'sawtooth', i * 0.45, 0.82, pan, 1100);
    }
  }

  /**
   * Sons de ambiente, chamado todo quadro.
   * indoor: 0..1 (abafa o vento); fire: 0..1 (proximidade da fogueira).
   */
  update(dt, { indoor = 0, fire = 0 } = {}) {
    if (!this.ctx || this.ctx.state !== 'running') return;
    this.indoor += (indoor - this.indoor) * Math.min(1, dt * 3);
    if (this.windGain) {
      this.windGain.gain.value = 0.05 * (1 - this.indoor * 0.75);
      this.windFilter.Q.value = 0.6 + this.indoor * 1.5;
    }
    this.birdTimer -= dt;
    if (this.birdTimer <= 0) {
      if (Math.random() < 0.25) this._crow(); else this._bird();
      this.birdTimer = 3 + Math.random() * 8;
    }
    if (fire > 0.01) {
      this.crackleTimer -= dt;
      if (this.crackleTimer <= 0) {
        this.crackleTimer = 0.03 + Math.random() * 0.18;
        this._burst({ duration: 0.03 + Math.random() * 0.04, freq: 1500 + Math.random() * 3000, q: 1.5, gain: 0.12 * fire, type: 'bandpass' });
        if (Math.random() < 0.2) this._burst({ duration: 0.3, freq: 300, gain: 0.08 * fire, attack: 0.1 });
      }
    }
  }

  swing() {
    this._burst({ duration: 0.18, freq: 1800, q: 2.5, gain: 0.12, type: 'bandpass', attack: 0.06 });
  }

  /** Respiração (intensidade 0..1). */
  breath(intensity = 1) {
    this._inhale = !this._inhale;
    this._burst({
      duration: this._inhale ? 0.45 : 0.55, freq: this._inhale ? 1100 : 750, q: 0.9,
      gain: 0.08 * intensity, type: 'bandpass', attack: 0.15,
    });
  }

  hurt() {
    this._tone(180, 0.25, 0.15, 'sawtooth', 0, 0.6);
    this._burst({ duration: 0.25, freq: 700, gain: 0.2, type: 'bandpass', q: 1.5 });
  }

  click() {
    this._tone(1800, 0.04, 0.08, 'sine');
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
    this.windGain = g;
    this.windFilter = f;
    // variação lenta da intensidade e do tom do vento
    const lfo = this.ctx.createOscillator();
    lfo.frequency.value = 0.07;
    const lfoGain = this.ctx.createGain();
    lfoGain.gain.value = 180;
    lfo.connect(lfoGain).connect(f.frequency);
    const lfo2 = this.ctx.createOscillator();
    lfo2.frequency.value = 0.11;
    const lfo2Gain = this.ctx.createGain();
    lfo2Gain.gain.value = 0.45;
    const swell = this.ctx.createGain(); // rajadas de vento
    lfo2.connect(lfo2Gain).connect(swell.gain);
    swell.gain.value = 1;
    lfo.start();
    lfo2.start();
    src.connect(f).connect(g).connect(swell).connect(this.master);
    src.start();
  }
}
