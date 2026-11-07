// Entrada unificada: teclado + mouse (pointer lock), toque (joystick virtual + área de olhar + botões) e gamepad.
import { clamp } from './math.js';

export class Input {
  constructor(canvas) {
    this.canvas = canvas;
    this.keys = new Set();
    this.held = {};           // ações seguradas (fire, aim, sprint...)
    this.pressedQ = new Set(); // ações disparadas neste frame
    this.look = [0, 0];       // acumulado de olhar (rad)
    this.moveX = 0; this.moveY = 0;
    this.sens = 1;
    this.locked = false;
    this.enabled = true;
    this.touchMode = matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window;
    this.joy = { id: -1, ox: 0, oy: 0, x: 0, y: 0, active: false };
    this.lookTouch = { id: -1, lx: 0, ly: 0 };
    this.map = {
      KeyW: 'fwd', KeyS: 'back', KeyA: 'left', KeyD: 'right', Space: 'jump', ShiftLeft: 'sprint', ShiftRight: 'sprint',
      KeyC: 'crouch', KeyZ: 'prone', KeyR: 'reload', KeyF: 'interact', KeyE: 'leanR', Tab: 'inventory', KeyI: 'inventory', KeyV: 'camera',
      KeyL: 'flashlight', KeyG: 'drop', KeyQ: 'leanL', KeyB: 'firemode', Escape: 'menu', KeyP: 'menu', F3: 'debug', KeyN: 'noclip',
      KeyT: 'time', KeyX: 'holster', KeyH: 'holster', KeyM: 'map', KeyU: 'use', KeyK: 'vehicle', KeyJ: 'vehicle',
      Digit1: 'slot1', Digit2: 'slot2', Digit3: 'slot3', Digit4: 'slot4', Digit5: 'slot5', Digit6: 'slot6', Digit7: 'slot7', Digit8: 'slot8',
    };
    const down = (e) => {
      if (!this.enabled) return;
      if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT')) return;
      const a = this.map[e.code];
      if (a) {
        if (e.code === 'Tab' || e.code === 'F3' || e.code === 'Space') e.preventDefault();
        if (!e.repeat) { this.pressedQ.add(a); }
        this.keys.add(e.code); this.held[a] = true;
      }
    };
    const up = (e) => { const a = this.map[e.code]; this.keys.delete(e.code); if (a) { let any = false; for (const [c, v] of Object.entries(this.map)) if (v === a && this.keys.has(c)) any = true; this.held[a] = any; } };
    addEventListener('keydown', down); addEventListener('keyup', up);
    addEventListener('blur', () => { this.keys.clear(); this.held = {}; });
    // mouse
    canvas.addEventListener('mousedown', (e) => {
      if (this.touchMode) return;
      if (!this.locked && this.enabled && document.pointerLockElement !== canvas && this.wantLock) { canvas.requestPointerLock?.(); return; }
      if (e.button === 0) { this.held.fire = true; this.pressedQ.add('fire'); }
      if (e.button === 2) { this.held.aim = true; this.pressedQ.add('aim'); }
    });
    addEventListener('mouseup', (e) => { if (e.button === 0) this.held.fire = false; if (e.button === 2) this.held.aim = false; });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    addEventListener('mousemove', (e) => {
      if (!this.locked || !this.enabled) return;
      this.look[0] -= (e.movementX || 0) * 0.0022 * this.sens; this.look[1] -= (e.movementY || 0) * 0.0022 * this.sens;
    });
    addEventListener('wheel', (e) => { if (this.enabled && this.locked) this.pressedQ.add(e.deltaY > 0 ? 'nextWeapon' : 'prevWeapon'); }, { passive: true });
    document.addEventListener('pointerlockchange', () => { this.locked = document.pointerLockElement === canvas; if (!this.locked) { this.held.fire = false; this.held.aim = false; } this.onLockChange && this.onLockChange(this.locked); });
    // toque na tela do jogo
    canvas.style.touchAction = 'none';
    canvas.addEventListener('pointerdown', (e) => this._tdown(e));
    canvas.addEventListener('pointermove', (e) => this._tmove(e));
    const end = (e) => this._tup(e);
    canvas.addEventListener('pointerup', end); canvas.addEventListener('pointercancel', end);
    this.pads = [];
  }
  _tdown(e) {
    if (e.pointerType === 'mouse' || !this.enabled) return;
    const w = innerWidth;
    if (e.clientX < w * 0.42 && this.joy.id < 0) {
      this.joy = { id: e.pointerId, ox: e.clientX, oy: e.clientY, x: 0, y: 0, active: true };
      this.onJoy && this.onJoy(this.joy, true);
    } else if (this.lookTouch.id < 0) {
      this.lookTouch = { id: e.pointerId, lx: e.clientX, ly: e.clientY, t: performance.now(), moved: 0 };
    }
    try { this.canvas.setPointerCapture(e.pointerId); } catch {}
  }
  _tmove(e) {
    if (e.pointerType === 'mouse') return;
    if (e.pointerId === this.joy.id) {
      const R = 62, dx = e.clientX - this.joy.ox, dy = e.clientY - this.joy.oy, d = Math.hypot(dx, dy);
      const k = d > R ? R / d : 1;
      this.joy.x = dx * k / R; this.joy.y = dy * k / R;
      this.joy.px = dx * k; this.joy.py = dy * k;
      this.onJoy && this.onJoy(this.joy, true);
    } else if (e.pointerId === this.lookTouch.id) {
      const dx = e.clientX - this.lookTouch.lx, dy = e.clientY - this.lookTouch.ly;
      this.lookTouch.lx = e.clientX; this.lookTouch.ly = e.clientY; this.lookTouch.moved += Math.abs(dx) + Math.abs(dy);
      const s = 0.0042 * this.sens * (this.held.aim ? 0.6 : 1);
      this.look[0] -= dx * s; this.look[1] -= dy * s;
    }
  }
  _tup(e) {
    if (e.pointerId === this.joy.id) { this.joy = { id: -1, ox: 0, oy: 0, x: 0, y: 0, active: false }; this.onJoy && this.onJoy(this.joy, false); }
    if (e.pointerId === this.lookTouch.id) { this.lookTouch = { id: -1, lx: 0, ly: 0 }; }
  }
  // botões de interface virtual
  setButton(name, down) { if (down && !this.held[name]) this.pressedQ.add(name); this.held[name] = down; }
  press(name) { this.pressedQ.add(name); }
  pressed(name) { return this.pressedQ.has(name); }
  isHeld(name) { return !!this.held[name]; }
  requestLock() { if (!this.touchMode) this.canvas.requestPointerLock?.(); }
  exitLock() { if (document.pointerLockElement) document.exitPointerLock(); }

  // chamar uma vez por frame: calcula movimento e gamepad
  poll() {
    let mx = 0, my = 0;
    if (this.held.fwd) my -= 1; if (this.held.back) my += 1; if (this.held.left) mx -= 1; if (this.held.right) mx += 1;
    if (this.joy.active) { mx += this.joy.x; my += this.joy.y; }
    // gamepad
    const gps = navigator.getGamepads ? navigator.getGamepads() : [];
    for (const gp of gps) {
      if (!gp || !gp.connected) continue;
      const dz = (v) => (Math.abs(v) < 0.14 ? 0 : v);
      mx += dz(gp.axes[0]); my += dz(gp.axes[1]);
      this.look[0] -= dz(gp.axes[2]) * 0.045 * this.sens; this.look[1] -= dz(gp.axes[3]) * 0.035 * this.sens;
      const b = (i) => gp.buttons[i] && gp.buttons[i].pressed;
      const edge = (name, i) => { const k = name + gp.index; const p = b(i); if (p && !this['_g' + k]) this.pressedQ.add(name); this['_g' + k] = p; };
      this.held.fire = this.held.fire || b(7) || false; if (!b(7) && gp._f) this.held.fire = false; gp._f = b(7);
      this.held.aim = this.held.aim || b(6) || false; if (!b(6) && gp._a) this.held.aim = false; gp._a = b(6);
      edge('jump', 0); edge('crouch', 1); edge('reload', 2); edge('interact', 3); edge('prevWeapon', 4); edge('nextWeapon', 5); edge('inventory', 8); edge('menu', 9); edge('camera', 11); edge('flashlight', 12);
      this.held.sprint = this.held.sprint || b(10);
    }
    const l = Math.hypot(mx, my);
    if (l > 1) { mx /= l; my /= l; }
    this.moveX = mx; this.moveY = my;
  }
  consumeLook() { const l = [this.look[0], this.look[1]]; this.look[0] = 0; this.look[1] = 0; return l; }
  endFrame() { this.pressedQ.clear(); }
}
