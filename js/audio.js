// Sons procedurais com Web Audio (sem arquivos de áudio).
//
// Roteamento:  efeitos ─┬─────────────────────────┐
//                       └─ eco (convolução) ──────┤→ mestre → filtro "debaixo d'água" → saída
//              vento, pássaros ───────────────────┘
// O eco aumenta dentro de casas; debaixo d'água tudo fica abafado. Sons com posição no mundo
// (fogueira, objetos, portas) passam por um PannerNode 3D que acompanha a câmera.

export class GameAudio {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.volume = 0.7;
    this.birdTimer = 3;
    this.crackleTimer = 0;
    this.heartTimer = 0;
    this.bubbleTimer = 0;
    this.indoor = 0;
    this._dest = null;
  }

  /** Precisa ser chamado a partir de um gesto do usuário (clique/toque). */
  unlock() {
    if (this.ctx) { this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    const ctx = this.ctx = new AC();

    this.under = ctx.createBiquadFilter();
    this.under.type = 'lowpass';
    this.under.frequency.value = 20000;
    this.under.connect(ctx.destination);
    this.master = ctx.createGain();
    this.master.gain.value = this.volume;
    this.master.connect(this.under);

    this.sfx = ctx.createGain();
    this.sfx.connect(this.master);
    this.reverbSend = ctx.createGain();
    this.reverbSend.gain.value = 0;
    this.convolver = ctx.createConvolver();
    this.convolver.buffer = this._impulse(1.4, 2.8);
    this.sfx.connect(this.reverbSend).connect(this.convolver).connect(this.master);

    const len = ctx.sampleRate * 2;
    this.noise = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = this.noise.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;

    this.firePanners = new Map();
    this._startWind();
  }

  /** Resposta de sala sintética (ruído decaindo) para o eco dentro de casa. */
  _impulse(seconds, decay) {
    const rate = this.ctx.sampleRate, n = Math.floor(rate * seconds);
    const buf = this.ctx.createBuffer(2, n, rate);
    for (let c = 0; c < 2; c++) {
      const d = buf.getChannelData(c);
      for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / n, decay);
    }
    return buf;
  }

  setVolume(v) {
    this.volume = v;
    if (this.master) this.master.gain.value = v;
  }

  suspend() { this.ctx?.suspend(); }

  /** Atualiza a posição/orientação do "ouvido" (câmera). */
  setListener(pos, forward, up) {
    if (!this.ctx) return;
    const L = this.ctx.listener;
    const t = this.ctx.currentTime;
    if (L.positionX) {
      L.positionX.setValueAtTime(pos.x, t); L.positionY.setValueAtTime(pos.y, t); L.positionZ.setValueAtTime(pos.z, t);
      L.forwardX.setValueAtTime(forward.x, t); L.forwardY.setValueAtTime(forward.y, t); L.forwardZ.setValueAtTime(forward.z, t);
      L.upX.setValueAtTime(up.x, t); L.upY.setValueAtTime(up.y, t); L.upZ.setValueAtTime(up.z, t);
    } else {
      L.setPosition(pos.x, pos.y, pos.z);
      L.setOrientation(forward.x, forward.y, forward.z, up.x, up.y, up.z);
    }
  }

  /** Nó 3D numa posição do mundo, ligado aos efeitos. */
  _panner(pos, refDistance = 2) {
    const p = this.ctx.createPanner();
    p.panningModel = 'HRTF';
    p.distanceModel = 'inverse';
    p.refDistance = refDistance;
    p.maxDistance = 60;
    p.rolloffFactor = 1.2;
    if (p.positionX) { p.positionX.value = pos.x; p.positionY.value = pos.y; p.positionZ.value = pos.z; }
    else p.setPosition(pos.x, pos.y, pos.z);
    p.connect(this.sfx);
    return p;
  }

  /** Executa `fn` mandando os sons para uma posição 3D. */
  _at(pos, fn, refDistance) {
    if (!this.ctx) return;
    this._dest = this._panner(pos, refDistance);
    fn();
    const node = this._dest;
    this._dest = null;
    setTimeout(() => node.disconnect(), 3000);
  }

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
    src.connect(f).connect(g).connect(this._dest ?? this.sfx);
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
    node.connect(this._dest ?? (pan ? this.master : this.sfx));
    o.start(t);
    o.stop(t + duration + 0.02);
  }

  // ---------- jogador ----------
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
        if (Math.random() < 0.15) this._tone(380 + Math.random() * 120, 0.3, 0.02, 'sawtooth', 0.02, 0.85, 0, 700); // rangido
        break;
      case 'metal':
        this._burst({ duration: 0.05, freq: 2500, q: 2, gain: 0.15 * k, type: 'bandpass' });
        this._tone(480 + Math.random() * 60, 0.25, 0.05 * k, 'sine');
        this._tone(1270 + Math.random() * 90, 0.18, 0.025 * k, 'sine');
        break;
      case 'water':
        this.splash(0.25 * k);
        break;
      default: // grama / terra / folhas secas
        this._burst({ duration: run ? 0.14 : 0.11, freq: 380 + Math.random() * 220, q: 0.8, gain: 0.2 * k });
        this._burst({ duration: 0.09, freq: 3600, q: 0.8, gain: 0.07 * k, type: 'bandpass', delay: 0.01 });
    }
  }

  jump() {
    this._burst({ duration: 0.08, freq: 500, gain: 0.15 });
    this._burst({ duration: 0.18, freq: 1200, q: 0.8, gain: 0.05, type: 'bandpass', attack: 0.03 }); // roupa
  }

  land(speed, surface = 'grass') {
    const k = Math.min(speed / 15, 1);
    this._burst({ duration: 0.18 + k * 0.15, freq: 220 + k * 120, q: 0.7, gain: 0.25 + k * 0.4 });
    if (surface !== 'grass') this.step(surface, true);
  }

  climb() {
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

  swing() {
    this._burst({ duration: 0.18, freq: 1800, q: 2.5, gain: 0.12, type: 'bandpass', attack: 0.06 });
  }

  /** Faca acertando uma superfície. */
  knifeHit(surface, pos) {
    this._at(pos, () => {
      switch (surface) {
        case 'metal':
          this._tone(1900 + Math.random() * 300, 0.35, 0.12, 'triangle');
          this._tone(3100, 0.2, 0.05, 'sine');
          this._burst({ duration: 0.05, freq: 4000, q: 2, gain: 0.25, type: 'bandpass' });
          break;
        case 'wood':
          this._burst({ duration: 0.12, freq: 600, q: 4, gain: 0.6, type: 'bandpass' });
          this._tone(220, 0.1, 0.12, 'triangle');
          break;
        case 'concrete':
          this._burst({ duration: 0.07, freq: 2600, q: 1.5, gain: 0.4, type: 'bandpass' });
          this._tone(1400, 0.08, 0.04, 'square');
          break;
        default:
          this._burst({ duration: 0.1, freq: 500, q: 1, gain: 0.35 });
      }
    });
  }

  /** Objeto com física batendo em algo. */
  impact(kind, strength, pos) {
    const k = Math.max(0.15, strength);
    this._at(pos, () => {
      switch (kind) {
        case 'can':
          this._tone(1500 + Math.random() * 700, 0.12, 0.06 * k, 'triangle');
          this._burst({ duration: 0.05, freq: 3500, q: 3, gain: 0.25 * k, type: 'bandpass' });
          break;
        case 'glass':
          this._tone(3200 + Math.random() * 1500, 0.25, 0.05 * k, 'sine');
          this._tone(5200 + Math.random() * 800, 0.15, 0.025 * k, 'sine');
          break;
        case 'hollow':
          this._burst({ duration: 0.2, freq: 260, q: 6, gain: 0.6 * k, type: 'bandpass' });
          break;
        case 'wood':
          this._burst({ duration: 0.1, freq: 450, q: 4, gain: 0.5 * k, type: 'bandpass' });
          break;
        default: // metal
          this._tone(700 + Math.random() * 300, 0.4, 0.06 * k, 'triangle');
          this._burst({ duration: 0.06, freq: 2200, q: 2, gain: 0.25 * k, type: 'bandpass' });
      }
    }, 1.2);
  }

  doorOpen(pos) {
    this._at(pos, () => {
      this._burst({ duration: 0.05, freq: 2400, q: 3, gain: 0.25, type: 'bandpass' }); // trinco
      // rangido: dente-de-serra filtrado com vibrato
      const t = this.ctx.currentTime + 0.05;
      const o = this.ctx.createOscillator();
      o.type = 'sawtooth';
      o.frequency.setValueAtTime(260 + Math.random() * 60, t);
      o.frequency.linearRampToValueAtTime(170 + Math.random() * 40, t + 0.7);
      const lfo = this.ctx.createOscillator();
      lfo.frequency.value = 23;
      const lg = this.ctx.createGain();
      lg.gain.value = 18;
      lfo.connect(lg).connect(o.frequency);
      const f = this.ctx.createBiquadFilter();
      f.type = 'bandpass'; f.frequency.value = 900; f.Q.value = 3;
      const g = this.ctx.createGain();
      g.gain.setValueAtTime(0, t);
      g.gain.linearRampToValueAtTime(0.06, t + 0.1);
      g.gain.linearRampToValueAtTime(0.0, t + 0.75);
      o.connect(f).connect(g).connect(this._dest);
      o.start(t); lfo.start(t);
      o.stop(t + 0.8); lfo.stop(t + 0.8);
    });
  }

  doorClose(pos) {
    this._at(pos, () => {
      this._burst({ duration: 0.25, freq: 160, gain: 0.7 });
      this._burst({ duration: 0.06, freq: 2000, q: 3, gain: 0.25, type: 'bandpass', delay: 0.02 });
    });
  }

  splash(strength = 1) {
    const k = Math.min(1, strength);
    this._burst({ duration: 0.25 + k * 0.4, freq: 1400, q: 0.5, gain: 0.25 + k * 0.4, attack: 0.01 });
    this._burst({ duration: 0.4 + k * 0.4, freq: 600, q: 0.7, gain: 0.15 + k * 0.3, delay: 0.05 });
  }

  swimStroke(under) {
    if (under) this._burst({ duration: 0.4, freq: 350, q: 0.8, gain: 0.25, attack: 0.1 });
    else this._burst({ duration: 0.35, freq: 1100 + Math.random() * 400, q: 0.6, gain: 0.18, attack: 0.06 });
  }

  _bubbles() {
    const n = 2 + Math.floor(Math.random() * 4);
    for (let i = 0; i < n; i++) this._tone(500 + Math.random() * 700, 0.06, 0.05, 'sine', i * 0.05 + Math.random() * 0.04, 1.8);
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

  _heartbeat(k) {
    this._tone(62, 0.16, 0.35 * k, 'sine', 0, 0.7);
    this._tone(55, 0.18, 0.25 * k, 'sine', 0.22, 0.7);
  }

  click() {
    this._tone(1800, 0.04, 0.08, 'sine');
    this._burst({ duration: 0.03, freq: 3000, q: 2, gain: 0.08, type: 'bandpass' });
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
   * indoor 0..1 (eco, vento abafado); fires: posições das fogueiras; underwater; health 0..100.
   */
  update(dt, { indoor = 0, fires = [], firePlayerDist = Infinity, underwater = false, health = 100 } = {}) {
    if (!this.ctx || this.ctx.state !== 'running') return;
    const t = this.ctx.currentTime;
    this.indoor += (indoor - this.indoor) * Math.min(1, dt * 3);
    this.reverbSend.gain.setTargetAtTime(this.indoor * 0.45, t, 0.2);
    this.under.frequency.setTargetAtTime(underwater ? 500 : 20000, t, 0.08);
    if (this.windGain) {
      this.windGain.gain.value = 0.05 * (1 - this.indoor * 0.75) * (underwater ? 0.2 : 1);
      this.windFilter.Q.value = 0.6 + this.indoor * 1.5;
    }
    if (!underwater) {
      this.birdTimer -= dt;
      if (this.birdTimer <= 0) {
        if (Math.random() < 0.25) this._crow(); else this._bird();
        this.birdTimer = 3 + Math.random() * 8;
      }
    } else {
      this.bubbleTimer -= dt;
      if (this.bubbleTimer <= 0) { this._bubbles(); this.bubbleTimer = 0.8 + Math.random() * 1.5; }
    }
    // fogueira: som 3D vindo dela
    if (firePlayerDist < 25) {
      this.crackleTimer -= dt;
      if (this.crackleTimer <= 0) {
        this.crackleTimer = 0.03 + Math.random() * 0.16;
        for (const pos of fires) {
          if (!this.firePanners.has(pos)) this.firePanners.set(pos, this._panner(pos, 1.5));
          this._dest = this.firePanners.get(pos);
          this._burst({ duration: 0.03 + Math.random() * 0.04, freq: 1500 + Math.random() * 3000, q: 1.5, gain: 0.35, type: 'bandpass' });
          if (Math.random() < 0.25) this._burst({ duration: 0.35, freq: 300, gain: 0.25, attack: 0.1 });
          this._dest = null;
        }
      }
    }
    // coração acelerado com pouca vida
    if (health > 0 && health < 35) {
      this.heartTimer -= dt;
      if (this.heartTimer <= 0) {
        const k = 1 - health / 35;
        this._heartbeat(0.4 + k * 0.6);
        this.heartTimer = 1.1 - k * 0.45;
      }
    }
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
    // variação lenta da intensidade e do tom do vento (rajadas)
    const lfo = this.ctx.createOscillator();
    lfo.frequency.value = 0.07;
    const lfoGain = this.ctx.createGain();
    lfoGain.gain.value = 180;
    lfo.connect(lfoGain).connect(f.frequency);
    const lfo2 = this.ctx.createOscillator();
    lfo2.frequency.value = 0.11;
    const lfo2Gain = this.ctx.createGain();
    lfo2Gain.gain.value = 0.45;
    const swell = this.ctx.createGain();
    lfo2.connect(lfo2Gain).connect(swell.gain);
    swell.gain.value = 1;
    lfo.start();
    lfo2.start();
    src.connect(f).connect(g).connect(swell).connect(this.master);
    src.start();
  }
}
