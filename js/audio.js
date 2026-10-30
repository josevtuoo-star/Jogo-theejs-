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
    this.samples = {};       // gravações reais (assets/sfx): nome → [AudioBuffer]
    this._raw = null;        // arquivos baixados antes do primeiro toque (ainda não decodificados)
    this._last = {};
  }

  /**
   * Baixa as gravações reais (CC0, ver assets/CREDITS.md) já no carregamento. Elas só são
   * decodificadas depois do primeiro toque/clique (o navegador exige um gesto para o áudio).
   * Enquanto não chegam, os sons sintetizados fazem o papel.
   */
  async preload(base = 'assets/sfx/') {
    try {
      const index = await (await fetch(base + 'index.json')).json();
      const jobs = [];
      this._raw = {};
      for (const [name, n] of Object.entries(index)) {
        const files = n === 1 && name.startsWith('amb_') ? [name] : Array.from({ length: n }, (_, i) => `${name}_${i}`);
        jobs.push(Promise.all(files.map((f) => fetch(base + f + '.mp3').then((r) => (r.ok ? r.arrayBuffer() : null)).catch(() => null)))
          .then((bufs) => { this._raw[name] = bufs.filter(Boolean); }));
      }
      await Promise.all(jobs);
      if (this.ctx) this._decodeAll();
    } catch (e) {
      console.warn('sons gravados não carregaram (usando sintetizados):', e);
    }
  }

  async _decodeAll() {
    if (!this._raw || !this.ctx) return;
    const raw = this._raw;
    this._raw = null;
    await Promise.all(Object.entries(raw).map(async ([name, bufs]) => {
      const out = [];
      for (const b of bufs) {
        try { out.push(await this.ctx.decodeAudioData(b.slice(0))); } catch { /* arquivo ruim: ignora */ }
      }
      if (out.length) this.samples[name] = out;
    }));
    this._startAmbience();
  }

  /** Tem a gravação `name` pronta para tocar? */
  has(name) { return !!this.samples[name]; }

  /**
   * Toca uma gravação (variação aleatória, sem repetir a anterior), com leve mudança de tom e
   * volume para nunca soar igual. pos: posição 3D no mundo. Retorna false se ainda não carregou.
   */
  _play(name, { gain = 1, rate = 1, pos = null, ref = 2, delay = 0, vary = 0.06, lowpass = 0, dest = null } = {}) {
    const set = this.samples[name];
    if (!this.ctx || !set) return false;
    let i = Math.floor(Math.random() * set.length);
    if (set.length > 1 && i === this._last[name]) i = (i + 1) % set.length;
    this._last[name] = i;
    const src = this.ctx.createBufferSource();
    src.buffer = set[i];
    src.playbackRate.value = rate * (1 + (Math.random() * 2 - 1) * vary);
    const g = this.ctx.createGain();
    g.gain.value = gain * (1 + (Math.random() * 2 - 1) * vary * 1.5);
    let node = src.connect(g);
    if (lowpass) {
      const f = this.ctx.createBiquadFilter();
      f.type = 'lowpass'; f.frequency.value = lowpass;
      node = node.connect(f);
    }
    let pan = null;
    if (pos) pan = this._panner(pos, ref);
    node.connect(pan ?? dest ?? this._dest ?? this.sfx);
    src.start(this.ctx.currentTime + delay);
    if (pan) setTimeout(() => pan.disconnect(), (set[i].duration / src.playbackRate.value + delay) * 1000 + 500);
    return true;
  }

  /** Ambiente gravado em loop: pássaros e insetos (o vento continua sintetizado). */
  _startAmbience() {
    if (this.ambBirds || !this.ctx) return;
    const loop = (name, vol) => {
      const set = this.samples[name];
      if (!set) return null;
      const src = this.ctx.createBufferSource();
      src.buffer = set[0];
      src.loop = true;
      const g = this.ctx.createGain();
      g.gain.value = vol;
      src.connect(g).connect(this.master);
      src.start(this.ctx.currentTime, Math.random() * set[0].duration);
      return g;
    };
    this.ambBirds = loop('amb_birds', 0.0);
    this.ambInsects = loop('amb_insects', 0.0);
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
    // compressor: tiros e quedas altos não estouram, sons baixos continuam audíveis
    this.comp = ctx.createDynamicsCompressor();
    this.comp.threshold.value = -14;
    this.comp.knee.value = 10;
    this.comp.ratio.value = 6;
    this.comp.attack.value = 0.002;
    this.comp.release.value = 0.25;
    this.comp.connect(this.under);
    this.master = ctx.createGain();
    this.master.gain.value = this.volume;
    this.master.connect(this.comp);

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
    if (this._raw) this._decodeAll();
    this._shotBuffers(); // prepara o som do tiro já (evita travadinha no primeiro disparo)
    // passos: gera um piso de cada vez, sem travar o início do jogo
    ['grass', 'concrete', 'wood', 'metal'].forEach((sfc, i) => setTimeout(() => this._stepBank(sfc), 150 + i * 250));
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
  /**
   * Banco de passos sintetizados amostra a amostra (uma vez), 6 variações por piso:
   * calcanhar + rolagem + ponta, com a textura do piso — grama/terra (folhas e torrões
   * estalando), concreto (estalo da sola e arrasto), madeira (tábua oca ressoando),
   * metal (chapa vibrando).
   */
  _stepBank(surface) {
    this._steps ??= {};
    if (this._steps[surface]) return this._steps[surface];
    const sr = this.ctx.sampleRate, n = Math.floor(sr * 0.36);
    const bank = [];
    // filtro passa-faixa (RBJ) simples, amostra a amostra
    const bp = (f, q) => {
      const w = 2 * Math.PI * f / sr, al = Math.sin(w) / (2 * q), a0 = 1 + al;
      const b0 = al / a0, b2 = -al / a0, a1 = -2 * Math.cos(w) / a0, a2 = (1 - al) / a0;
      let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
      return (x) => { const y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2; x2 = x1; x1 = x; y2 = y1; y1 = y; return y; };
    };
    const lp = (f) => { const a = 1 - Math.exp(-2 * Math.PI * f / sr); let y = 0; return (x) => (y += (x - y) * a); };
    for (let v = 0; v < 6; v++) {
      const buf = this.ctx.createBuffer(1, n, sr);
      const d = buf.getChannelData(0);
      const toe = 0.065 + Math.random() * 0.04;           // calcanhar → ponta
      const heelG = 0.8 + Math.random() * 0.4, toeG = 0.5 + Math.random() * 0.4;
      const thumpLP = lp(220 + Math.random() * 80), scuffBP = bp(1400 + Math.random() * 900, 0.9), rustleBP = bp(2200 + Math.random() * 1500, 0.7);
      const modes = surface === 'wood' ? [[92, 0.09], [178, 0.065], [305, 0.045], [515, 0.03], [860, 0.018]]
        : surface === 'metal' ? [[380, 0.35], [1015, 0.22], [1960, 0.14], [3120, 0.09], [4300, 0.06]] : [];
      const mf = modes.map(([f]) => f * (0.94 + Math.random() * 0.12));
      // estalos (folhas, terra, cascalho): instantes aleatórios depois do calcanhar e da ponta
      const clicks = [];
      const nClicks = surface === 'grass' ? 40 : surface === 'concrete' ? 10 : 4;
      for (let i = 0; i < nClicks; i++) {
        const base = Math.random() < 0.55 ? 0 : toe;
        clicks.push([Math.floor((base + Math.pow(Math.random(), 1.8) * 0.13) * sr), 0.2 + Math.random() * 0.8, 1 + Math.random() * 3]);
      }
      const clickBuf = new Float32Array(n);
      for (const [at, g, ms] of clicks) {
        const len = Math.floor(sr * ms / 1000);
        let hp = 0, prev = 0;
        for (let i = 0; i < len && at + i < n; i++) {
          const w = Math.random() * 2 - 1;
          hp = 0.85 * (hp + w - prev); prev = w; // passa-alta: estalo seco
          clickBuf[at + i] += hp * g * Math.exp(-i / (len * 0.35));
        }
      }
      for (let i = 0; i < n; i++) {
        const t = i / sr;
        const w = Math.random() * 2 - 1;
        const eH = t < 0.002 ? t / 0.002 : Math.exp(-(t - 0.002) / 0.03);
        const tt = t - toe;
        const eT = tt < 0 ? 0 : tt < 0.004 ? tt / 0.004 : Math.exp(-(tt - 0.004) / 0.035);
        const impact = eH * heelG + eT * toeG;
        let x = thumpLP(w) * impact * 3.2 + Math.sin(2 * Math.PI * 78 * t) * Math.exp(-t / 0.035) * 0.35 * heelG;
        switch (surface) {
          case 'concrete': {
            // estalo da sola (curto e agudo) + arrasto da ponta + areia
            const click = (t < 0.004 ? 1 : 0) * w * 0.9 * heelG + (tt > 0 && tt < 0.003 ? w * 0.5 * toeG : 0);
            const scuffEnv = tt > 0 ? Math.min(1, tt / 0.012) * Math.exp(-tt / 0.045) : 0;
            x += click + scuffBP(w) * scuffEnv * 1.1 + clickBuf[i] * 0.35;
            break;
          }
          case 'wood': {
            let r = 0;
            for (let m = 0; m < mf.length; m++) {
              const dec = modes[m][1];
              r += Math.sin(2 * Math.PI * mf[m] * t) * Math.exp(-t / dec) * heelG / (m + 1.5)
                 + (tt > 0 ? Math.sin(2 * Math.PI * mf[m] * tt) * Math.exp(-tt / dec) * toeG / (m + 2) : 0);
            }
            x = x * 0.6 + r * 0.55 + (t < 0.003 ? w * 0.4 : 0) + clickBuf[i] * 0.2;
            break;
          }
          case 'metal': {
            let r = 0;
            for (let m = 0; m < mf.length; m++) {
              const dec = modes[m][1] * 0.6;
              r += Math.sin(2 * Math.PI * mf[m] * t) * Math.exp(-t / dec) * heelG / (m + 1)
                 + (tt > 0 ? Math.sin(2 * Math.PI * mf[m] * tt) * Math.exp(-tt / dec) * toeG / (m + 1.5) : 0);
            }
            x = x * 0.5 + r * 0.35 + (t < 0.002 ? w * 0.6 : 0);
            break;
          }
          default: {
            // grama seca, folhas e terra: estalos + capim roçando no tornozelo
            const rustle = rustleBP(w) * (t < 0.03 ? t / 0.03 : Math.exp(-(t - 0.03) / 0.09)) * 0.55;
            x = x * 0.85 + clickBuf[i] * 0.9 + rustle;
          }
        }
        d[i] = Math.tanh(x * 1.2) * 0.85;
      }
      bank.push(buf);
    }
    this._steps[surface] = bank;
    return bank;
  }

  /** Passo: amostra do piso (variação aleatória), pé esquerdo/direito levemente de lados opostos. */
  step(surface = 'grass', run = false, crouch = false, speed = 3) {
    if (!this.ctx) return;
    if (surface === 'water') { this.splash(0.22 * (run ? 1.3 : 0.8)); this._foley(0.8, run, speed); return; }
    const k = crouch ? 0.38 : run ? 1.25 : Math.min(1.05, 0.5 + speed * 0.15);
    // gravações reais por piso; na grama seca de outono soma o estalar de folhas
    const rate = (run ? 1.06 : 1) * (crouch ? 0.94 : 1);
    const main = surface === 'concrete' || surface === 'metal' ? 'step_concrete' : surface === 'wood' ? 'step_wood' : 'step_grass';
    if (this._play(main, { gain: (surface === 'grass' || !['concrete', 'metal', 'wood'].includes(surface) ? 0.5 : 0.62) * k, rate })) {
      if (main === 'step_grass') this._play('step_snow', { gain: 0.14 * k, rate: rate * 1.15, vary: 0.1 });
      if (surface === 'metal') this._play('imp_metal_light', { gain: 0.16 * k, rate: 0.9 });
      if (surface === 'wood' && Math.random() < 0.12) this._play('creak', { gain: 0.08, rate: 1.2, delay: 0.05 });
      this._foley(k, run, speed);
      return;
    }
    const bank = this._stepBank(surface === 'concrete' || surface === 'wood' || surface === 'metal' ? surface : 'grass');
    const src = this.ctx.createBufferSource();
    src.buffer = bank[Math.floor(Math.random() * bank.length)];
    src.playbackRate.value = (run ? 1.12 : 1) * (0.92 + Math.random() * 0.16) * (crouch ? 0.9 : 1);
    const g = this.ctx.createGain();
    g.gain.value = 0.55 * k * (0.85 + Math.random() * 0.3);
    this._foot = -(this._foot ?? 1);
    let node = src.connect(g);
    if (this.ctx.createStereoPanner) {
      const p = this.ctx.createStereoPanner();
      p.pan.value = this._foot * 0.12;
      node = node.connect(p);
    }
    node.connect(this.sfx);
    src.start();
    if (surface === 'wood' && Math.random() < 0.15) this._tone(330 + Math.random() * 120, 0.35, 0.016, 'sawtooth', 0.03, 0.82, 0, 650); // tábua rangendo
    this._foley(k, run, speed);
  }

  /** Roupa roçando e equipamento balançando a cada passo. */
  _foley(k, run, speed) {
    // roupa: gravação de tecido baixinha, às vezes
    if (this.has('cloth') && Math.random() < (run ? 0.6 : 0.25)) this._play('cloth', { gain: 0.09 * k, rate: 1.1, vary: 0.12 });
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
    if (this._play('knife_draw', { gain: 0.55 })) return;
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
    if (this._play('knife_draw', { gain: 0.35, rate: 1.15 })) { this._play('leather', { gain: 0.3, delay: 0.16 }); return; }
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
  /**
   * Amostra de um tiro de .357 sintetizada amostra a amostra: estalo supersônico (ms), explosão
   * de gás (ruído encorpado), pancada grave que cai de tom, cauda de ar rolando e saturação.
   * Três variações para não soar sempre igual.
   */
  _shotBuffers() {
    if (this._shots) return this._shots;
    const sr = this.ctx.sampleRate, n = Math.floor(sr * 1.6);
    this._shots = [];
    for (let v = 0; v < 3; v++) {
      const buf = this.ctx.createBuffer(2, n, sr);
      for (let c = 0; c < 2; c++) {
        const d = buf.getChannelData(c);
        let lpA = 0, lpB = 0, lpC = 0, ph = 0;
        const aA = 1 - Math.exp(-2 * Math.PI * (2600 + v * 300) / sr);
        const aB = 1 - Math.exp(-2 * Math.PI * 520 / sr);
        const aC = 1 - Math.exp(-2 * Math.PI * 180 / sr);
        for (let i = 0; i < n; i++) {
          const t = i / sr;
          const w = Math.random() * 2 - 1;
          lpA += (w - lpA) * aA; lpB += (w - lpB) * aB; lpC += (w - lpC) * aC;
          const crack = w * Math.exp(-t / 0.0018) * 1.4;
          const blast = lpA * Math.exp(-t / (0.05 + v * 0.008)) * 3.2;
          const f = 42 + 110 * Math.exp(-t / 0.025);
          ph += (2 * Math.PI * f) / sr;
          const thump = Math.sin(ph) * Math.exp(-t / 0.085) * 0.95;
          const roll = (lpB * 2.2 * Math.exp(-t / 0.35) + lpC * 3.5 * Math.exp(-t / 0.7)) * (1 + 0.35 * Math.sin(2 * Math.PI * (5 + v) * t + c));
          const x = crack + blast + thump + roll * 0.6;
          d[i] = Math.tanh(x * 1.8) * 0.9;
        }
      }
      this._shots.push(buf);
    }
    return this._shots;
  }

  /** Tiro: amostra sintetizada + eco do vale ao ar livre (dentro de casa o reverb faz o papel). */
  gunshot(indoor = 0, shotgun = false) {
    if (!this.ctx) return;
    const ctx = this.ctx, t = ctx.currentTime;
    const bufs = this._shotBuffers();
    const g = ctx.createGain();
    g.connect(this.sfx);
    // tiro gravado de verdade (CC0): pistola um pouco mais grave para soar como .357, ou a
    // espingarda calibre 12; somado à pancada grave sintetizada; sem a gravação, só o sintetizado
    const rec = shotgun ? this._play('sg_shot', { gain: 1.0, rate: 0.93, vary: 0.03, dest: g }) : this._play('gun_shot', { gain: 1.0, rate: 0.84, vary: 0.03, dest: g });
    const src = ctx.createBufferSource();
    src.buffer = bufs[Math.floor(Math.random() * bufs.length)];
    src.playbackRate.value = (shotgun ? 0.72 : 0.95) + Math.random() * 0.1;
    const sg = ctx.createGain();
    sg.gain.value = rec ? (shotgun ? 0.7 : 0.55) : 1.0;
    src.connect(sg).connect(g);
    // eco: cópia abafada e atrasada, duas vezes (morro e floresta)
    const k = 1 - indoor;
    if (k > 0.05) {
      const ek = shotgun ? 1.35 : 1;
      for (const [delay, gain, freq] of [[0.28, 0.32 * ek, 900], [0.75, 0.18 * ek, 600], [1.4, 0.1 * ek, 400]]) {
        const dl = ctx.createDelay(2);
        dl.delayTime.value = delay + Math.random() * 0.05;
        const lp = ctx.createBiquadFilter();
        lp.type = 'lowpass'; lp.frequency.value = freq;
        const eg = ctx.createGain();
        eg.gain.value = gain * k;
        g.connect(dl).connect(lp).connect(eg).connect(this.master);
        setTimeout(() => { dl.disconnect(); eg.disconnect(); }, 4000);
      }
    }
    src.start(t);
    // mecanismo (cão batendo)
    if (!shotgun) this._tone(5200 + Math.random() * 600, 0.04, 0.04, 'triangle', 0.005);
  }

  // ---------- espingarda ----------
  /** Abrir a báscula: trava soltando e os canos caindo. */
  breakOpen() {
    if (this._play('metal_latch', { gain: 0.55, rate: 0.9 })) { this._play('sg_rack', { gain: 0.25, rate: 1.25, delay: 0.05 }); return; }
    this._burst({ duration: 0.05, freq: 1800, q: 4, gain: 0.25, type: 'bandpass' });
    this._tone(900, 0.1, 0.06, 'triangle', 0.04, 0.8);
  }

  /** Fechar: tranco seco do metal. */
  breakClose() {
    if (this._play('metal_click', { gain: 0.75, rate: 0.7 })) { this._play('metal_latch', { gain: 0.35, rate: 1.1, delay: 0.02 }); return; }
    this._burst({ duration: 0.04, freq: 1500, q: 4, gain: 0.4, type: 'bandpass' });
    this._tone(700, 0.12, 0.1, 'triangle', 0, 0.8);
  }

  /** Cartuchos saltando do extrator. */
  shellsEject() {
    if (this._play('sg_shell', { gain: 0.35, rate: 1.3 })) return;
    this._burst({ duration: 0.06, freq: 2200, q: 2, gain: 0.1, type: 'bandpass' });
  }

  /** Cartucho entrando na câmara. */
  shellIn(delay = 0) {
    if (this._play('sg_shell', { gain: 0.5, delay })) return;
    this._burst({ duration: 0.04, freq: 1600, q: 3, gain: 0.2, type: 'bandpass', delay });
  }

  /** Arma longa saindo/entrando na bandoleira das costas: tecido, correia e metal. */
  sling(draw = true) {
    if (this._play('cloth', { gain: 0.5 })) {
      this._play('cloth_belt', { gain: 0.35, delay: 0.12 });
      if (draw) this._play('gun_handle', { gain: 0.35, delay: 0.42 });
      return;
    }
    this._burst({ duration: 0.3, freq: 1200, q: 1, gain: 0.12, type: 'bandpass', attack: 0.06 });
    this._tone(2400, 0.06, 0.04, 'triangle', 0.35);
  }

  // ---------- besta ----------
  /** Disparo: estalo do gatilho, corda vibrando e o "vuup" do virote. */
  crossbowShot() {
    if (!this.ctx) return;
    this._burst({ duration: 0.03, freq: 3200, q: 3, gain: 0.25, type: 'bandpass' });
    // corda: tom grave que cai e treme
    this._tone(118, 0.32, 0.2, 'sawtooth', 0, 0.82, 0, 900);
    this._tone(236, 0.2, 0.06, 'triangle', 0.005, 0.85);
    this._burst({ duration: 0.09, freq: 500, q: 1, gain: 0.35, type: 'lowpass' });
    this._sweep(2400, 900, 0.22, 0.09, 2);
  }

  /** Puxar a corda até o trinco (estica e trava). */
  crossbowCock() {
    this._burst({ duration: 0.4, freq: 700, q: 2, gain: 0.06, type: 'bandpass', attack: 0.3 });
    this._play('metal_click', { gain: 0.5, rate: 1.2, delay: 0.38 }) || this._burst({ duration: 0.03, freq: 3000, q: 4, gain: 0.25, type: 'bandpass', delay: 0.38 });
  }

  /** Virote encaixando no trilho. */
  boltLoad() {
    if (this._play('leather', { gain: 0.25, rate: 1.3 })) { this._play('metal_click', { gain: 0.2, rate: 1.6, delay: 0.1 }); return; }
    this._burst({ duration: 0.05, freq: 2400, q: 3, gain: 0.12, type: 'bandpass' });
  }

  /** Virote cravando: pancada seca e a haste vibrando. */
  boltHit(surface, pos) {
    const rec = { metal: 'imp_metal_light', wood: 'imp_wood_heavy', concrete: 'imp_mining', sack: 'imp_soft_heavy' }[surface] ?? 'imp_soft_medium';
    this._play(rec, { gain: 0.7, pos, rate: 0.9 });
    this._at(pos, () => this._tone(160 + Math.random() * 40, 0.25, 0.08, 'triangle', 0.01, 0.95), 3);
  }

  // ---------- taco ----------
  batSwing(heavy = false) {
    this._sweep(heavy ? 900 : 1100, heavy ? 180 : 260, heavy ? 0.42 : 0.3, heavy ? 0.22 : 0.16, 1.2);
    if (heavy) this.grunt(1); else if (Math.random() < 0.4) this.grunt(0.6);
  }

  batHit(surface, pos, power = 5) {
    const rec = { metal: 'imp_metal_heavy', wood: 'imp_wood_heavy', concrete: 'imp_mining', sack: 'imp_punch_heavy' }[surface] ?? 'imp_wood_medium';
    const k = Math.min(1, power / 8);
    if (this._play(rec, { gain: 0.6 + k * 0.3, pos, rate: 0.85 })) {
      this._play('imp_wood_medium', { gain: 0.4, pos, rate: 0.75 });
      this._play('metal_pot', { gain: 0.08, pos, rate: 1.8, delay: 0.01 }); // arame chacoalhando
      return;
    }
    this._at(pos, () => { this._tone(140, 0.15, 0.3 * k + 0.1, 'triangle', 0, 0.7); this._burst({ duration: 0.1, freq: 400, gain: 0.4 }); });
  }

  dryFire() {
    if (this._play('metal_click', { gain: 0.55, rate: 1.1 })) return;
    this._tone(2600, 0.04, 0.12, 'square', 0, 0.8, 0, 2600);
    this._burst({ duration: 0.03, freq: 4000, q: 3, gain: 0.15, type: 'bandpass' });
  }

  /** Sacar do coldre / guardar: couro raspando e o clique do metal. */
  holster(draw = true) {
    if (this._play('leather', { gain: 0.45 })) {
      this._play(draw ? 'belt_handle' : 'cloth_belt', { gain: 0.4, delay: draw ? 0.12 : 0.1 });
      this._play('metal_click', { gain: 0.18, rate: 1.3, delay: draw ? 0.3 : 0.22 });
      return;
    }
    this._burst({ duration: 0.22, freq: 1500, q: 1.2, gain: 0.12, type: 'bandpass', attack: 0.04 });
    this._tone(draw ? 3400 : 2900, 0.06, 0.04, 'triangle', draw ? 0.18 : 0.12);
    this._burst({ duration: 0.03, freq: 2500, q: 3, gain: 0.12, type: 'bandpass', delay: draw ? 0.2 : 0.14 });
  }

  cylinderOpen() {
    if (this._play('metal_latch', { gain: 0.5, rate: 1.15 })) return;
    this._burst({ duration: 0.04, freq: 3000, q: 4, gain: 0.2, type: 'bandpass' });
    this._tone(1800, 0.08, 0.05, 'triangle', 0.03, 0.9);
  }

  cylinderClose() {
    if (this._play('metal_click', { gain: 0.6, rate: 0.85 })) { this._play('metal_latch', { gain: 0.3, rate: 1.4, delay: 0.03 }); return; }
    this._burst({ duration: 0.035, freq: 2400, q: 4, gain: 0.3, type: 'bandpass' });
    this._tone(1400, 0.1, 0.08, 'triangle', 0, 0.85);
    this._burst({ duration: 0.02, freq: 5000, q: 3, gain: 0.08, type: 'bandpass', delay: 0.05 });
  }

  ejectShells(count) {
    if (this._play('coins', { gain: 0.3, rate: 1.25 })) return;
    // cápsulas deslizando para fora do tambor
    for (let i = 0; i < count; i++) this._tone(3600 + Math.random() * 1500, 0.07, 0.03, 'triangle', i * 0.012);
    this._burst({ duration: 0.08, freq: 2800, q: 2, gain: 0.08, type: 'bandpass' });
  }

  loadRounds() {
    if (this._play('coins', { gain: 0.4, rate: 0.95 })) { this._play('metal_click', { gain: 0.25, rate: 1.4, delay: 0.12 }); return; }
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
    const rec = { metal: 'imp_metal_medium', wood: 'imp_wood_heavy', concrete: 'imp_mining', sack: 'imp_soft_heavy', water: null }[surface] ?? 'imp_soft_medium';
    if (rec && this._play(rec, { gain: 0.8, pos, ref: 3, rate: surface === 'concrete' ? 1.1 : 1 })) {
      if (ricochet) this._at(pos, () => this._tone(3800 + Math.random() * 1500, 0.35, 0.06, 'sine', 0.01, 0.45), 3);
      return;
    }
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
    if (this._play('leather', { gain: 0.45 })) { this._play('coins', { gain: 0.35, delay: 0.08 }); return; }
    this._burst({ duration: 0.12, freq: 1400, q: 1, gain: 0.12, type: 'bandpass', attack: 0.02 });
    for (let i = 0; i < 4; i++) this._tone(3000 + Math.random() * 1200, 0.05, 0.03, 'triangle', 0.08 + i * 0.03);
  }

  /** Golpe acertando o boneco de estopa: baque abafado, palha e (faca) o pano rasgando. */
  sackHit(pos, knife, power = 4) {
    const k = Math.min(1, power / 8);
    if (this._play(k > 0.6 ? 'imp_soft_heavy' : 'imp_soft_medium', { gain: 0.6 + k * 0.3, pos, rate: 0.9 })) {
      if (knife) this._play('knife_slice', { gain: 0.55, pos });
      this._at(pos, () => this._grains(6 + Math.round(k * 8), 0.12, { fMin: 2500, fMax: 6500, gain: 0.04 })); // palha
      return;
    }
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

  punchHit(pos, heavy = false) {
    if (this._play(heavy ? 'imp_punch_heavy' : 'imp_punch_medium', { gain: 0.7, pos })) return;
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
    this._play('cloth', { gain: 0.25 });
    this._burst({ duration: 0.08, freq: 300, gain: 0.18 });
    this._burst({ duration: 0.18, freq: 1200, q: 0.8, gain: 0.05, type: 'bandpass', attack: 0.03 }); // roupa
    if (Math.random() < 0.5) this.grunt(0.5);
  }

  land(speed, surface = 'grass') {
    const k = Math.min(speed / 12, 1);
    if (this._play(k > 0.5 ? 'imp_soft_heavy' : 'imp_soft_medium', { gain: 0.35 + k * 0.5, rate: 0.85 })) {
      this.step(surface, true, false, 6);
      this._play('cloth', { gain: 0.3, delay: 0.03 });
      if (k > 0.3) this._play('drop_leather', { gain: 0.25 * k, delay: 0.05 });
      if (speed > 8) this.grunt(0.8);
      return;
    }
    this._burst({ duration: 0.16 + k * 0.15, freq: 160 + k * 100, q: 0.7, gain: 0.25 + k * 0.45 }); // corpo
    this.step(surface, true, false, 6);
    this.step(surface, true, false, 6);
    // equipamento chacoalhando
    for (let i = 0; i < 2 + k * 4; i++) this._tone(2800 + Math.random() * 3000, 0.05, 0.012, 'sine', 0.03 + Math.random() * 0.12);
    if (speed > 8) this.grunt(0.8);
  }

  climb(heavy = false) {
    if (this._play('cloth', { gain: 0.35 })) {
      this._play('leather', { gain: 0.25, delay: 0.06 });
      this._play('imp_soft_medium', { gain: 0.2, delay: 0.04, rate: 1.2 }); // mãos na borda
      this.grunt(heavy ? 1 : 0.6);
      return;
    }
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
    const rec = { metal: 'imp_metal_light', wood: 'imp_wood_medium', concrete: 'imp_mining' }[surface] ?? 'imp_soft_medium';
    if (this._play(rec, { gain: 0.6, pos })) {
      if (surface === 'wood') this._play('chop', { gain: 0.35, pos });
      if (surface === 'metal') this._tone(1900 + Math.random() * 300, 0.35, 0.06, 'triangle'); // lâmina vibrando
      return;
    }
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
    const rec = {
      can: 'imp_tin_medium', glass: k > 0.6 ? 'imp_glass_medium' : 'imp_glass_light', hollow: 'imp_plate_light',
      wood: k > 0.6 ? 'imp_wood_medium' : 'imp_wood_light', metal: k > 0.6 ? 'imp_metal_medium' : 'metal_pot',
    }[kind] ?? 'imp_generic_light';
    if (this._play(rec, { gain: 0.25 + k * 0.5, pos, ref: 1.2, rate: kind === 'can' ? 1.1 : 1 })) return;
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
    if (this._play('door_open', { gain: 0.7, pos })) { if (Math.random() < 0.6) this._play('creak', { gain: 0.35, pos, delay: 0.15 }); return; }
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
    if (this._play('door_close', { gain: 0.75, pos })) return;
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
    // ambiente gravado: pássaros e insetos somem dentro de casa e debaixo d'água
    const out = (1 - this.indoor * 0.8) * (underwater ? 0.1 : 1);
    if (this.ambBirds) this.ambBirds.gain.setTargetAtTime(0.16 * out, t, 0.5);
    if (this.ambInsects) this.ambInsects.gain.setTargetAtTime(0.07 * out, t, 0.5);
    if (this.windGain) {
      this.windGain.gain.value = 0.05 * (1 - this.indoor * 0.75) * (underwater ? 0.2 : 1);
      this.windFilter.Q.value = 0.6 + this.indoor * 1.5;
    }
    if (!underwater) {
      this.birdTimer -= dt;
      if (this.birdTimer <= 0) {
        // com o ambiente gravado tocando, só os corvos sintetizados de vez em quando
        if (this.ambBirds) { if (Math.random() < 0.35) this._crow(); } else if (Math.random() < 0.25) this._crow(); else this._bird();
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
