// Entrada unificada: teclado + mouse (PC) e joystick virtual + toque (Android).
import { buttonHTML } from './icons.js';
// O jogador lê apenas estados abstratos (mover, olhar, pular, correr...).

// Notebooks com tela touch continuam no modo PC (ponteiro principal "fino").
export const isTouchDevice =
  matchMedia('(pointer: coarse)').matches ||
  (navigator.maxTouchPoints > 0 && !matchMedia('(pointer: fine)').matches);

const JOY_RADIUS = 55;
const PAD_DEAD = 0.18;
const PAD_LOOK_SPEED = 3.0; // rad/s com o analógico no máximo

// mapeamento "standard" da Gamepad API (Xbox / PlayStation / genéricos no Android)
const PAD = { A: 0, B: 1, X: 2, Y: 3, LB: 4, RB: 5, LT: 6, RT: 7, START: 9, L3: 10, UP: 12, DOWN: 13, LEFT: 14, RIGHT: 15 };

function deadzone(v) {
  const a = Math.abs(v);
  return a < PAD_DEAD ? 0 : Math.sign(v) * (a - PAD_DEAD) / (1 - PAD_DEAD);
}

export class Input {
  constructor(canvas) {
    this.canvas = canvas;
    this.enabled = false;

    this.keys = new Set();
    this.pressed = new Set();   // ações acionadas neste quadro (borda de subida)

    this.lookDX = 0;
    this.lookDY = 0;
    this.mouseSensitivity = 0.0022;
    this.touchSensitivity = 0.0055;
    this.sensitivity = 1;
    this.invertY = false;

    this.mouseDown = false;
    this.mouseRight = false;
    this.gunMode = false;            // com o revólver na mão, o LT do controle mira em vez de correr
    this.touchAim = false;           // botão MIRAR (alternar)
    this.pointerLockFailed = false;
    this.dragLook = false;

    // estado touch
    this.joy = { id: null, ox: 0, oy: 0, x: 0, y: 0 };
    this.look = { id: null, x: 0, y: 0 };
    this.touchHeld = new Set();      // botões segurados (pular)
    this.touchSprint = false;        // botão correr (alternar)
    this.touchCrouch = false;        // botão agachar (alternar)

    // controle (gamepad)
    this.pad = { connected: false, move: { x: 0, y: 0 }, sprintToggle: false, prev: [] };
    this.onGamepadStart = null;

    this.onPauseRequest = null;

    this._bindKeyboardMouse();
    if (isTouchDevice) this._bindTouch();
  }

  // ---------------- PC ----------------
  _bindKeyboardMouse() {
    const actionForKey = {
      Space: 'jump',
      KeyC: 'crouchToggle',
      KeyV: 'view',
      KeyF: 'use',
      KeyL: 'light',
      Digit1: 'equip_hands',
      Digit2: 'equip_pistol',
      KeyR: 'reload',
      KeyX: 'walkToggle',
    };

    window.addEventListener('keydown', (e) => {
      if (!this.enabled) return;
      if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
      if (!e.repeat && actionForKey[e.code]) this.pressed.add(actionForKey[e.code]);
      if (e.code === 'Escape' && this.pointerLockFailed) this.onPauseRequest?.();
      this.keys.add(e.code);
    });
    window.addEventListener('keyup', (e) => this.keys.delete(e.code));
    window.addEventListener('blur', () => { this.keys.clear(); this.mouseDown = false; });

    document.addEventListener('mousemove', (e) => {
      if (!this.enabled || isTouchDevice) return;
      // sem pointer lock (bloqueado pelo navegador): olhar segurando o botão e arrastando
      if (document.pointerLockElement !== this.canvas && !this.dragLook) return;
      // ignora picos absurdos que alguns navegadores geram ao capturar o ponteiro
      if (Math.abs(e.movementX) > 300 || Math.abs(e.movementY) > 300) return;
      this.lookDX += e.movementX * this.mouseSensitivity * this.sensitivity;
      this.lookDY += e.movementY * this.mouseSensitivity * this.sensitivity * (this.invertY ? -1 : 1);
    });

    this.canvas.addEventListener('mousedown', (e) => {
      if (!this.enabled || isTouchDevice) return;
      if (document.pointerLockElement !== this.canvas) {
        if (!this.pointerLockFailed) { this.canvas.requestPointerLock?.(); return; }
        this.dragLook = true;
      }
      if (e.button === 0) { this.mouseDown = true; this.pressed.add('attack'); }
      if (e.button === 2) this.mouseRight = true;
    });
    this.canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    // rodinha do mouse: troca de item (para baixo = próximo, para cima = anterior)
    let wheelCd = 0;
    window.addEventListener('wheel', (e) => {
      if (!this.enabled || isTouchDevice || performance.now() < wheelCd || Math.abs(e.deltaY) < 1) return;
      wheelCd = performance.now() + 180;
      this.pressed.add(e.deltaY > 0 ? 'swapItem' : 'swapPrev');
    }, { passive: true });
    window.addEventListener('mouseup', (e) => {
      if (e.button === 0) this.mouseDown = false;
      if (e.button === 2) this.mouseRight = false;
      this.dragLook = false;
    });
  }

  // ---------------- Android / touch ----------------
  _bindTouch() {
    document.body.classList.add('touch');
    // segurar um botão no Android abria menu, seleção de texto ou arrastava uma "cópia" do botão
    for (const ev of ['contextmenu', 'dragstart', 'selectstart']) {
      document.addEventListener(ev, (e) => { if (!(e.target instanceof Element && e.target.closest('.settings'))) e.preventDefault(); }, { passive: false });
    }
    this.joyBase = document.getElementById('joy-base');
    this.joyKnob = document.getElementById('joy-knob');

    // botões
    document.querySelectorAll('#touch-ui .tbtn').forEach((btn) => {
      const action = btn.dataset.action;
      if (btn.dataset.icon) btn.innerHTML = buttonHTML(btn.dataset.icon, btn.dataset.label);
      // botões de tiro/mirar: arrastar o dedo sobre eles também gira a câmera (atirar e mirar
      // sem soltar o botão, como nos jogos de tiro de celular)
      if (btn.dataset.look) {
        const drag = new Map();
        btn.addEventListener('pointerdown', (e) => drag.set(e.pointerId, { x: e.clientX, y: e.clientY, moved: 0 }));
        btn.addEventListener('pointermove', (e) => {
          const d = drag.get(e.pointerId);
          if (!d || !this.enabled) return;
          const dx = e.clientX - d.x, dy = e.clientY - d.y;
          d.x = e.clientX; d.y = e.clientY;
          d.moved += Math.abs(dx) + Math.abs(dy);
          if (d.moved < 6) return; // um toque com o dedo tremendo não mexe a mira
          this.lookDX += dx * this.touchSensitivity * this.sensitivity;
          this.lookDY += dy * this.touchSensitivity * this.sensitivity * (this.invertY ? -1 : 1);
        });
        const stop = (e) => drag.delete(e.pointerId);
        btn.addEventListener('pointerup', stop);
        btn.addEventListener('pointercancel', stop);
      }
      btn.addEventListener('pointerdown', (e) => {
        e.preventDefault();
        e.stopPropagation();
        if (!this.enabled && action !== 'pause') return;
        btn.setPointerCapture?.(e.pointerId);
        switch (action) {
          case 'sprint':
            this.touchSprint = !this.touchSprint;
            if (this.touchSprint) this.touchCrouch = false;
            break;
          case 'crouch':
            this.touchCrouch = !this.touchCrouch;
            if (this.touchCrouch) this.touchSprint = false;
            break;
          case 'pause':
            this.onPauseRequest?.();
            break;
          case 'aim':
            this.touchAim = !this.touchAim;
            break;
          default:
            this.pressed.add(action);
            this.touchHeld.add(action);
        }
        this._refreshButtons();
      });
      const release = () => { this.touchHeld.delete(action); };
      btn.addEventListener('pointerup', release);
      btn.addEventListener('pointercancel', release);
    });

    const ui = document.getElementById('touch-ui');
    const isOnButton = (e) => e.target instanceof Element && e.target.closest('.tbtn, .wslot');

    window.addEventListener('pointerdown', (e) => {
      if (!this.enabled || e.pointerType === 'mouse' || isOnButton(e)) return;
      if (!ui || ui.classList.contains('hidden')) return;
      if (e.clientX < window.innerWidth * 0.45) {
        if (this.joy.id === null) {
          this.joy.id = e.pointerId;
          this.joy.ox = e.clientX; this.joy.oy = e.clientY;
          this.joy.x = 0; this.joy.y = 0;
          this.joyBase.style.left = e.clientX + 'px';
          this.joyBase.style.top = e.clientY + 'px';
          this.joyBase.classList.add('active');
          this._updateKnob();
        }
      } else if (this.look.id === null) {
        this.look.id = e.pointerId;
        this.look.x = e.clientX; this.look.y = e.clientY;
      }
    }, { passive: false });

    window.addEventListener('pointermove', (e) => {
      if (e.pointerId === this.joy.id) {
        let dx = e.clientX - this.joy.ox;
        let dy = e.clientY - this.joy.oy;
        const len = Math.hypot(dx, dy);
        if (len > JOY_RADIUS) { dx *= JOY_RADIUS / len; dy *= JOY_RADIUS / len; }
        this.joy.x = dx / JOY_RADIUS;
        this.joy.y = dy / JOY_RADIUS;
        this._updateKnob();
      } else if (e.pointerId === this.look.id) {
        const dx = e.clientX - this.look.x;
        const dy = e.clientY - this.look.y;
        this.look.x = e.clientX; this.look.y = e.clientY;
        this.lookDX += dx * this.touchSensitivity * this.sensitivity;
        this.lookDY += dy * this.touchSensitivity * this.sensitivity * (this.invertY ? -1 : 1);
      }
    }, { passive: false });

    const end = (e) => {
      if (e.pointerId === this.joy.id) {
        this.joy.id = null; this.joy.x = 0; this.joy.y = 0;
        this.joyBase.classList.remove('active');
        this.joyBase.style.left = '';
        this.joyBase.style.top = '';
        this._updateKnob();
      } else if (e.pointerId === this.look.id) {
        this.look.id = null;
      }
    };
    window.addEventListener('pointerup', end);
    window.addEventListener('pointercancel', end);
  }

  _updateKnob() {
    this.joyKnob.style.transform = `translate(${this.joy.x * JOY_RADIUS}px, ${this.joy.y * JOY_RADIUS}px)`;
  }

  _refreshButtons() {
    document.getElementById('btn-sprint')?.classList.toggle('on', this.touchSprint);
    document.getElementById('btn-crouch')?.classList.toggle('on', this.touchCrouch);
    document.getElementById('btn-aim')?.classList.toggle('on', this.touchAim);
  }

  // ---------------- API usada pelo jogo ----------------

  /** Vetor de movimento: x = lateral (+direita), y = frente (+frente). */
  getMove() {
    let x = 0, y = 0;
    const k = this.keys;
    if (k.has('KeyW') || k.has('ArrowUp')) y += 1;
    if (k.has('KeyS') || k.has('ArrowDown')) y -= 1;
    if (k.has('KeyD') || k.has('ArrowRight')) x += 1;
    if (k.has('KeyA') || k.has('ArrowLeft')) x -= 1;

    if (this.pad.connected) {
      x += this.pad.move.x;
      y += this.pad.move.y;
    }

    if (this.joy.id !== null) {
      const dead = 0.12;
      const jx = Math.abs(this.joy.x) > dead ? this.joy.x : 0;
      const jy = Math.abs(this.joy.y) > dead ? this.joy.y : 0;
      x += jx;
      y -= jy;
    }
    const len = Math.hypot(x, y);
    if (len > 1) { x /= len; y /= len; }
    return { x, y };
  }

  get sprint() {
    const joyFull = this.joy.id !== null && Math.hypot(this.joy.x, this.joy.y) > 0.95 && this.joy.y < -0.5;
    return this.keys.has('ShiftLeft') || this.keys.has('ShiftRight') || this.touchSprint || joyFull ||
      this.pad.sprintToggle || (!this.gunMode && this._padHeld(PAD.LT));
  }

  /** -1 inclina para a esquerda, 1 para a direita (Q/E, LB/RB). */
  get lean() {
    let l = 0;
    if (this.keys.has('KeyQ') || this._padHeld(PAD.LB)) l -= 1;
    if (this.keys.has('KeyE') || this._padHeld(PAD.RB)) l += 1;
    return l;
  }

  /** Mirar (botão direito, MIRAR no celular, LT no controle com a arma). */
  get aimHeld() {
    return this.mouseRight || this.touchAim || (this.gunMode && this._padHeld(PAD.LT));
  }

  /** Desliga o MIRAR do celular (ao guardar a arma). */
  clearTouchAim() {
    if (this.touchAim) { this.touchAim = false; this._refreshButtons(); }
  }

  /** Botão de golpe segurado (carrega o golpe forte). */
  get attackHeld() {
    return this.mouseDown || this.touchHeld.has('attack') || this._padHeld(PAD.RT);
  }

  /** Pulo segurado (subir à superfície nadando). */
  get jumpHeld() {
    return this.keys.has('Space') || this.touchHeld.has('jump') || this._padHeld(PAD.A);
  }

  get crouchHeld() {
    return this.keys.has('ControlLeft') || this.keys.has('ControlRight') || this.touchCrouch;
  }

  /** Chamado pelo jogador quando ele mesmo cancela o agachar (ex.: ao pular/correr). */
  clearTouchCrouch() {
    if (this.touchCrouch) { this.touchCrouch = false; this._refreshButtons(); }
  }

  wasPressed(action) { return this.pressed.has(action); }

  consumeLook() {
    const d = { x: this.lookDX, y: this.lookDY };
    this.lookDX = 0; this.lookDY = 0;
    return d;
  }

  endFrame() { this.pressed.clear(); }

  // ---------------- controle (gamepad) ----------------
  _padHeld(i) {
    return !!this.pad.prev[i];
  }

  /** Lê o controle uma vez por quadro (a Gamepad API não usa eventos para botões). */
  pollGamepad(dt) {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    let gp = null;
    for (const p of pads) if (p && p.connected) { gp = p; break; }
    this.pad.connected = !!gp;
    if (!gp) { this.pad.move.x = this.pad.move.y = 0; this.pad.prev.length = 0; return; }

    const held = gp.buttons.map((b) => b.pressed || b.value > 0.5);
    const down = (i) => held[i] && !this.pad.prev[i];

    if (!this.enabled) {
      if (down(PAD.A) || down(PAD.START)) this.onGamepadStart?.();
      this.pad.prev = held;
      return;
    }

    const lx = deadzone(gp.axes[0] || 0), ly = deadzone(gp.axes[1] || 0);
    const rx = deadzone(gp.axes[2] || 0), ry = deadzone(gp.axes[3] || 0);
    this.pad.move.x = lx;
    this.pad.move.y = -ly;
    // curva quadrática: precisão perto do centro, rapidez no limite
    this.lookDX += Math.sign(rx) * rx * rx * PAD_LOOK_SPEED * this.sensitivity * dt;
    this.lookDY += Math.sign(ry) * ry * ry * PAD_LOOK_SPEED * this.sensitivity * dt * (this.invertY ? -1 : 1);

    if (down(PAD.L3)) this.pad.sprintToggle = !this.pad.sprintToggle;
    if (Math.hypot(lx, ly) < 0.2) this.pad.sprintToggle = false;

    if (down(PAD.A)) this.pressed.add('jump');
    if (down(PAD.B)) this.pressed.add('crouchToggle');
    if (down(PAD.X)) this.pressed.add('use');
    if (down(PAD.UP)) this.pressed.add('light');
    if (down(PAD.LEFT)) this.pressed.add('swapItem');
    if (down(PAD.RIGHT)) this.pressed.add('walkToggle');
    if (down(PAD.DOWN)) this.pressed.add('reload');
    if (down(PAD.Y)) this.pressed.add('view');
    if (down(PAD.RT)) this.pressed.add('attack');
    if (down(PAD.START)) this.onPauseRequest?.();

    this.pad.prev = held;
  }

  reset() {
    this.keys.clear();
    this.pressed.clear();
    this.lookDX = this.lookDY = 0;
    this.mouseDown = false;
    this.mouseRight = false;
  }
}
