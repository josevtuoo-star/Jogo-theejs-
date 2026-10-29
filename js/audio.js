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
  /** Muitos "grãos" curtíssimos de ruído: estalos de folha seca, cascalho, areia. */
  _grains(n, span, { fMin = 2000, fMax = 6000, q = 1.2, gain = 0.06, dur = 0.012, delay = 0 } = {}) {
    for (let i = 0; i < n; i++) {
      this._burst({
        duration: dur * (0.5 + Math.random()), freq: fMin + Math.random() * (fMax - fMin), q,
        gain: gain * (0.4 + Math.random() * 0.8), type: 'bandpass', attack: 0.001,
        delay: delay + Math.pow(Math.random(), 1.6) * span,
      });
    }
  }

  /** Passo: calcanhar + rolagem do pé + ponta, com textura de cada piso. */
  step(surface = 'grass', run = false, crouch = false, speed = 3) {
    const k = crouch ? 0.4 : run ? 1.35 : Math.min(1.1, 0.55 + speed * 0.15);
    const toe = run ? 0.05 : 0.09; // tempo entre calcanhar e ponta
    switch (surface) {
      case 'concrete':
        this._burst({ duration: 0.025, freq: 2400 + Math.random() * 600, q: 2, gain: 0.22 * k, type: 'bandpass' });
        this._burst({ duration: 0.05, freq: 160, gain: 0.22 * k });
        this._grains(7, 0.05, { fMin: 3500, fMax: 8000, gain: 0.035 * k, dur: 0.008 });
        this._burst({ duration: 0.05, freq: 1700, q: 1.3, gain: 0.1 * k, type: 'bandpass', delay: toe, attack: 0.01 }); // arrasto da ponta
        break;
      case 'wood':
        this._burst({ duration: 0.13, freq: 260 + Math.random() * 60, q: 6, gain: 0.55 * k, type: 'bandpass' });
        this._tone(120 + Math.random() * 25, 0.11, 0.14 * k, 'triangle');
        this._burst({ duration: 0.06, freq: 900, q: 3, gain: 0.12 * k, type: 'bandpass', delay: toe });
        if (Math.random() < 0.2) this._tone(330 + Math.random() * 120, 0.35, 0.018, 'sawtooth', 0.03, 0.82, 0, 650); // rangido da tábua
        break;
      case 'metal':
        this._burst({ duration: 0.03, freq: 3000, q: 2, gain: 0.16 * k, type: 'bandpass' });
        for (const [f, g] of [[430, 0.045], [1170, 0.025], [2310, 0.012]]) this._tone(f * (0.95 + Math.random() * 0.1), 0.3, g * k, 'sine');
        this._burst({ duration: 0.04, freq: 140, gain: 0.15 * k });
        break;
      case 'water':
        this.splash(0.22 * k);
        break;
      default: // grama alta, terra e folhas secas
        this._burst({ duration: 0.06, freq: 170, gain: 0.2 * k });                                   // pé no chão
        this._grains(run ? 26 : 18, run ? 0.07 : 0.1, { fMin: 1800, fMax: 7000, gain: 0.05 * k, dur: 0.014 }); // folhas estalando
        this._burst({ duration: 0.14, freq: 1100, q: 0.7, gain: 0.05 * k, type: 'bandpass', attack: 0.02 }); // grama roçando
    }
    this._foley(k, run, speed);
  }

  /** Roupa roçando e equipamento balançando a cada passo. */
  _foley(k, run, speed) {
    this._burst({ duration: 0.16, freq: 1300 + Math.random() * 500, q: 0.6, gain: 0.03 * k, type: 'bandpass', attack: 0.05, delay: 0.02 });
    if (speed > 3) {
      // fivelas e alças da mochila
      for (let i = 0; i < (run ? 3 : 1); i++) this._tone(3200 + Math.random() * 2500, 0.05, 0.008 * k, 'sine', 0.03 + Math.random() * 0.06);
      this._burst({ duration: 0.09, freq: 420, q: 2, gain: 0.04 * k, type: 'bandpass', delay: 0.04 }); // mochila batendo nas costas
    }
  }

  /** Esforço curto (pulo, escalada): som de garganta com formantes. */
  grunt(strength = 1) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const o = this.ctx.createOscillator();
    o.type = 'sawtooth';
    o.frequency.setValueAtTime(115 + Math.random() * 20, t);
    o.frequency.linearRampToValueAtTime(95, t + 0.18);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(0.035 * strength, t + 0.03);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.22);
    const f1 = this.ctx.createBiquadFilter(); f1.type = 'bandpass'; f1.frequency.value = 550; f1.Q.value = 4;
    const f2 = this.ctx.createBiquadFilter(); f2.type = 'bandpass'; f2.frequency.value = 1050; f2.Q.value = 5;
    o.connect(f1).connect(g);
    o.connect(f2).connect(g);
    g.connect(this.sfx);
    o.start(t);
    o.stop(t + 0.25);
    this._burst({ duration: 0.18, freq: 900, q: 1, gain: 0.05 * strength, type: 'bandpass', attack: 0.02 }); // ar saindo
  }

  /** Respiração com formantes; intensity 0..1 (ofegante depois de correr). */
  breathEffort(intensity, inhale) {
    const k = 0.25 + intensity * 0.75;
    this._burst({
      duration: inhale ? 0.32 : 0.42, freq: inhale ? 1500 : 900, q: 1.2,
      gain: 0.06 * k, type: 'bandpass', attack: inhale ? 0.1 : 0.05,
    });
    this._burst({ duration: inhale ? 0.3 : 0.4, freq: inhale ? 2600 : 1700, q: 2, gain: 0.025 * k, type: 'bandpass', attack: 0.08 });
  }

  unsheath() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const src = this.ctx.createBufferSource();
    src.buffer = this.noise;
    const f = this.ctx.createBiquadFilter();
    f.type = 'bandpass'; f.Q.value = 6;
    f.frequency.setValueAtTime(2500, t);
    f.frequency.exponentialRampToValueAtTime(6500, t + 0.3);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(0.12, t + 0.05);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.32);
    src.connect(f).connect(g).connect(this.sfx);
    src.start(t, Math.random());
    src.stop(t + 0.35);
    this._tone(4200, 0.25, 0.02, 'sine', 0.22);
  }

  sheathe() {
    this._burst({ duration: 0.18, freq: 3000, q: 3, gain: 0.08, type: 'bandpass', attack: 0.03 });
    this._burst({ duration: 0.05, freq: 600, q: 2, gain: 0.12, type: 'bandpass', delay: 0.16 });
  }

  punch(heavy = false) {
    // braço cortando o ar + roupa
    this._sweep(heavy ? 1400 : 1100, heavy ? 380 : 450, heavy ? 0.3 : 0.16, heavy ? 0.16 : 0.1, 1.4);
    this._burst({ duration: 0.14, freq: 1300, q: 0.8, gain: 0.04, type: 'bandpass', attack: 0.03 });
    if (heavy) this.grunt(1);
    else if (Math.random() < 0.3) this.grunt(0.45);
  }

  /** Ruído com filtro deslizando (golpes cortando o ar). */
  _sweep(f0, f1, dur, gain, q = 3) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const src = this.ctx.createBufferSource();
    src.buffer = this.noise;
    const f = this.ctx.createBiquadFilter();
    f.type = 'bandpass'; f.Q.value = q;
    f.frequency.setValueAtTime(f0, t);
    f.frequency.exponentialRampToValueAtTime(f1, t + dur);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(gain, t + dur * 0.35);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    src.connect(f).connect(g).connect(this._dest ?? this.sfx);
    src.start(t, Math.random());
    src.stop(t + dur + 0.02);
  }

  // ---------- revólver ----------
  /** Tiro de .357: estalo seco, estrondo grave e o eco voltando do vale. */
  gunshot(indoor = 0) {
    if (!this.ctx) return;
    this._burst({ duration: 0.035, freq: 3200, q: 0.7, gain: 1.1, type: 'bandpass', attack: 0.001 }); // estalo
    this._burst({ duration: 0.09, freq: 1200, q: 0.6, gain: 0.9, attack: 0.001 });
    this._burst({ duration: 0.45, freq: 260, q: 0.5, gain: 1.2, attack: 0.002 });                    // estrondo
    this._tone(70, 0.35, 0.6, 'sine', 0, 0.5);                                                       // pancada no peito
    this._tone(5200 + Math.random() * 600, 0.06, 0.05, 'triangle', 0.02);                            // mecanismo
    // eco ao ar livre (some dentro de casa, onde o reverb faz o papel)
    const k = 1 - indoor;
    if (k > 0.05) {
      this._burst({ duration: 0.6, freq: 420, q: 0.6, gain: 0.32 * k, delay: 0.22, attack: 0.02 });
      this._burst({ duration: 0.9, freq: 300, q: 0.6, gain: 0.18 * k, delay: 0.62, attack: 0.05 });
      this._burst({ duration: 1.2, freq: 220, q: 0.6, gain: 0.1 * k, delay: 1.3, attack: 0.1 });
    }
  }

  dryFire() {
    this._tone(2600, 0.04, 0.12, 'square', 0, 0.8, 0, 2600);
    this._burst({ duration: 0.03, freq: 4000, q: 3, gain: 0.15, type: 'bandpass' });
  }

  /** Sacar do coldre / guardar: couro raspando e o clique do metal. */
  holster(draw = true) {
    this._burst({ duration: 0.22, freq: 1500, q: 1.2, gain: 0.12, type: 'bandpass', attack: 0.04 });
    this._tone(draw ? 3400 : 2900, 0.06, 0.04, 'triangle', draw ? 0.18 : 0.12);
    this._burst({ duration: 0.03, freq: 2500, q: 3, gain: 0.12, type: 'bandpass', delay: draw ? 0.2 : 0.14 });
  }

  cylinderOpen() {
    this._burst({ duration: 0.04, freq: 3000, q: 4, gain: 0.2, type: 'bandpass' });
    this._tone(1800, 0.08, 0.05, 'triangle', 0.03, 0.9);
  }

  cylinderClose() {
    this._burst({ duration: 0.035, freq: 2400, q: 4, gain: 0.3, type: 'bandpass' });
    this._tone(1400, 0.1, 0.08, 'triangle', 0, 0.85);
    this._burst({ duration: 0.02, freq: 5000, q: 3, gain: 0.08, type: 'bandpass', delay: 0.05 });
  }

  ejectShells(count) {
    // cápsulas deslizando para fora do tambor
    for (let i = 0; i < count; i++) this._tone(3600 + Math.random() * 1500, 0.07, 0.03, 'triangle', i * 0.012);
    this._burst({ duration: 0.08, freq: 2800, q: 2, gain: 0.08, type: 'bandpass' });
  }

  loadRounds() {
    for (let i = 0; i < 3; i++) this._burst({ duration: 0.025, freq: 3000 + i * 300, q: 4, gain: 0.12, type: 'bandpass', delay: i * 0.04 });
    this._tone(2200, 0.05, 0.04, 'triangle', 0.1);
  }

  /** Cápsula batendo no chão: tilintar de latão. */
  shellClink(pos) {
    this._at(pos, () => {
      this._tone(4200 + Math.random() * 1800, 0.12, 0.05, 'sine');
      this._tone(6800 + Math.random() * 1500, 0.08, 0.025, 'sine', 0.06);
    }, 1.2);
  }

  /** Bala acertando: cada material tem seu som; às vezes ricocheteia. */
  bulletHit(surface, pos, ricochet = false) {
    this._at(pos, () => {
      switch (surface) {
        case 'metal':
          this._tone(2400 + Math.random() * 600, 0.3, 0.12, 'triangle');
          this._burst({ duration: 0.05, freq: 4500, q: 2, gain: 0.35, type: 'bandpass' });
          break;
        case 'wood':
          this._burst({ duration: 0.08, freq: 900, q: 2, gain: 0.55, type: 'bandpass' });
          this._burst({ duration: 0.06, freq: 2500, q: 1.5, gain: 0.2, type: 'bandpass', delay: 0.01 }); // lascas
          break;
        case 'concrete':
          this._burst({ duration: 0.06, freq: 3000, q: 1.2, gain: 0.5, type: 'bandpass' });
          this._grains(6, 0.1, { fMin: 3000, fMax: 7000, gain: 0.05 });
          break;
        case 'water':
          this._burst({ duration: 0.25, freq: 900, q: 0.8, gain: 0.3, attack: 0.01 });
          break;
        case 'sack':
          this._burst({ duration: 0.1, freq: 220, gain: 0.45 });
          this._grains(8, 0.12, { fMin: 2500, fMax: 6500, gain: 0.05 });
          break;
        default:
          this._burst({ duration: 0.09, freq: 400, gain: 0.4 });
          this._grains(5, 0.1, { fMin: 1500, fMax: 4000, gain: 0.05 });
      }
      if (ricochet) {
        // zunido do ricochete: tom que cai rápido
        this._tone(3800 + Math.random() * 1500, 0.35, 0.06, 'sine', 0.01, 0.45);
      }
    }, 3);
  }

  pickup() {
    this._burst({ duration: 0.12, freq: 1400, q: 1, gain: 0.12, type: 'bandpass', attack: 0.02 });
    for (let i = 0; i < 4; i++) this._tone(3000 + Math.random() * 1200, 0.05, 0.03, 'triangle', 0.08 + i * 0.03);
  }

  /** Golpe acertando o boneco de estopa: baque abafado, palha e (faca) o pano rasgando. */
  sackHit(pos, knife, power = 4) {
    const k = Math.min(1, power / 8);
    this._at(pos, () => {
      this._burst({ duration: 0.14 + k * 0.08, freq: 150 + k * 60, q: 0.8, gain: 0.45 + k * 0.4 });
      this._burst({ duration: 0.1, freq: 700, q: 1.2, gain: 0.12 + k * 0.1, type: 'bandpass' });
      this._grains(6 + Math.round(k * 8), 0.12, { fMin: 2500, fMax: 6500, gain: 0.05 }); // palha
      if (knife) {
        this._burst({ duration: 0.16, freq: 2200, q: 2.5, gain: 0.2, type: 'bandpass', attack: 0.01 }); // rasgo
        this._burst({ duration: 0.08, freq: 4200, q: 3, gain: 0.08, type: 'bandpass', delay: 0.04 });
      }
    });
  }

  punchHit(pos) {
    this._at(pos, () => {
      this._burst({ duration: 0.09, freq: 220, gain: 0.5 });
      this._burst({ duration: 0.04, freq: 1500, q: 1.5, gain: 0.15, type: 'bandpass' });
    });
  }

  grab() {
    this._burst({ duration: 0.05, freq: 700, q: 2, gain: 0.25, type: 'bandpass' });
    this._burst({ duration: 0.05, freq: 900, q: 2, gain: 0.2, type: 'bandpass', delay: 0.07 });
    this.grunt(0.8);
  }

  jump() {
    this._burst({ duration: 0.08, freq: 300, gain: 0.18 });
    this._burst({ duration: 0.18, freq: 1200, q: 0.8, gain: 0.05, type: 'bandpass', attack: 0.03 }); // roupa
    if (Math.random() < 0.5) this.grunt(0.5);
  }

  land(speed, surface = 'grass') {
    const k = Math.min(speed / 12, 1);
    this._burst({ duration: 0.16 + k * 0.15, freq: 160 + k * 100, q: 0.7, gain: 0.25 + k * 0.45 }); // corpo
    this.step(surface, true, false, 6);
    this.step(surface, true, false, 6);
    // equipamento chacoalhando
    for (let i = 0; i < 2 + k * 4; i++) this._tone(2800 + Math.random() * 3000, 0.05, 0.012, 'sine', 0.03 + Math.random() * 0.12);
    if (speed > 8) this.grunt(0.8);
  }

  climb(heavy = false) {
    this._burst({ duration: 0.35, freq: 1300, q: 0.7, gain: 0.12, type: 'bandpass', attack: 0.08 }); // roupa raspando
    this._burst({ duration: 0.06, freq: 700, q: 2, gain: 0.22, type: 'bandpass', delay: 0.04 });     // mãos na borda
    this._burst({ duration: 0.06, freq: 650, q: 2, gain: 0.18, type: 'bandpass', delay: 0.1 });
    this.grunt(heavy ? 1 : 0.6);
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

  swing(heavy = false, stab = false) {
    // corte no ar: o tom do vento cai conforme a lâmina passa
    if (!this.ctx) return;
    if (heavy || stab) {
      this._sweep(stab ? 2600 : 3600, stab ? 1400 : 600, heavy ? 0.32 : 0.15, heavy ? 0.17 : 0.11, 3);
      if (heavy) this.grunt(1);
      return;
    }
    const t = this.ctx.currentTime;
    const src = this.ctx.createBufferSource();
    src.buffer = this.noise;
    const f = this.ctx.createBiquadFilter();
    f.type = 'bandpass'; f.Q.value = 3;
    f.frequency.setValueAtTime(3200, t);
    f.frequency.exponentialRampToValueAtTime(800, t + 0.2);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(0.14, t + 0.07);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.22);
    src.connect(f).connect(g).connect(this.sfx);
    src.start(t, Math.random());
    src.stop(t + 0.25);
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
