// Editor de HUD: cada botão do celular e cada elemento do HUD pode ser arrastado para outro
// lugar, aumentado/diminuído e ficar mais ou menos transparente. O layout fica salvo no
// aparelho (localStorage) e é aplicado ao abrir o jogo.

const KEY = 'survival-hud-layout';

// [id, nome mostrado, só no celular?]
const ITEMS = [
  ['btn-attack', 'ATIRAR', true], ['btn-aim', 'MIRAR', true], ['btn-reload', 'RECARREGAR', true], ['btn-melee', 'GOLPE', true],
  ['btn-jump', 'PULAR', true], ['btn-crouch', 'AGACHAR', true], ['btn-sprint', 'CORRER', true], ['btn-use', 'USAR', true],
  ['btn-view', 'CÂMERA', true], ['btn-pause', 'PAUSA', true], ['joy-base', 'JOYSTICK', true],
  ['bars', 'BARRA DE VIDA', false], ['compass', 'BÚSSOLA', false], ['clock', 'RELÓGIO', false], ['weapon-bar', 'ITENS', false],
  ['ammo', 'MUNIÇÃO', false], ['equip-label', 'ARMA', false], ['state-label', 'ESTADO', false],
];

function load() {
  try { return JSON.parse(localStorage.getItem(KEY) || '{}'); } catch { return {}; }
}

export class HudEditor {
  constructor({ isTouch, onClose }) {
    this.isTouch = isTouch;
    this.onClose = onClose;
    this.layout = load();
    this.el = document.getElementById('hud-editor');
    this.sel = null;
    this.items = ITEMS.filter(([, , touch]) => !touch || isTouch).map(([id, name]) => ({ id, name, el: document.getElementById(id) })).filter((i) => i.el);
    const $ = (id) => document.getElementById(id);
    this.ui = { name: $('he-name'), size: $('he-size'), sizeVal: $('he-size-val'), op: $('he-opacity'), opVal: $('he-opacity-val') };
    this.ui.size.addEventListener('input', () => this._edit({ s: parseFloat(this.ui.size.value) }));
    this.ui.op.addEventListener('input', () => this._edit({ o: parseFloat(this.ui.op.value) }));
    $('he-reset-one').addEventListener('click', () => { if (this.sel) { delete this.work[this.sel.id]; this._applyOne(this.sel, this.work); this._select(this.sel); } });
    $('he-reset-all').addEventListener('click', () => { this.work = {}; this._applyAll(this.work); if (this.sel) this._select(this.sel); });
    $('he-cancel').addEventListener('click', () => this.close(false));
    $('he-save').addEventListener('click', () => this.close(true));
    // arrastar: captura antes dos botões (eles não disparam a ação durante a edição)
    this._down = (e) => {
      if (!this.open_) return;
      const item = this.items.find((i) => i.el.contains(e.target));
      if (!item) return;
      e.preventDefault(); e.stopPropagation();
      this._select(item);
      const r = item.el.getBoundingClientRect();
      this.drag = { id: e.pointerId, item, dx: e.clientX - (r.left + r.width / 2), dy: e.clientY - (r.top + r.height / 2) };
    };
    this._move = (e) => {
      const d = this.drag;
      if (!d || e.pointerId !== d.id) return;
      e.preventDefault(); e.stopPropagation();
      const x = (e.clientX - d.dx) / window.innerWidth * 100, y = (e.clientY - d.dy) / window.innerHeight * 100;
      this._edit({ x: Math.max(2, Math.min(98, x)), y: Math.max(2, Math.min(98, y)) });
    };
    this._up = (e) => { if (this.drag && e.pointerId === this.drag.id) { this.drag = null; e.stopPropagation(); } };
    for (const [ev, fn] of [['pointerdown', this._down], ['pointermove', this._move], ['pointerup', this._up], ['pointercancel', this._up]]) document.addEventListener(ev, fn, { capture: true, passive: false });
    this.apply();
  }

  /** Escala geral dos botões (configuração "Tamanho dos botões"). */
  set btnScale(v) { this._btnScale = v; this.apply(); }

  apply() { this._applyAll(this.layout); }

  _applyAll(L) { for (const it of this.items) this._applyOne(it, L); }

  _applyOne(it, L) {
    const v = L[it.id], st = it.el.style;
    const isBtn = it.el.classList.contains('tbtn');
    if (!v) {
      for (const k of ['left', 'top', 'right', 'bottom', 'transform', 'opacity', 'margin', 'transformOrigin']) st[k] = '';
      return;
    }
    if (v.x !== undefined) {
      st.left = v.x + '%'; st.top = v.y + '%'; st.right = 'auto'; st.bottom = 'auto'; st.margin = '0';
    }
    const s = (v.s ?? 1) * (isBtn ? (this._btnScale ?? 1) : 1);
    st.transformOrigin = '50% 50%';
    st.transform = v.x !== undefined ? `translate(-50%, -50%) scale(${s})` : `scale(${s})`;
    st.opacity = v.o ?? '';
  }

  _select(it) {
    for (const i of this.items) i.el.classList.toggle('he-sel', i === it);
    this.sel = it;
    const v = this.work[it.id] ?? {};
    this.ui.name.textContent = it.name;
    this.ui.size.value = v.s ?? 1; this.ui.op.value = v.o ?? 1;
    this.ui.sizeVal.textContent = Math.round((v.s ?? 1) * 100) + '%';
    this.ui.opVal.textContent = Math.round((v.o ?? 1) * 100) + '%';
  }

  _edit(patch) {
    const it = this.sel;
    if (!it) return;
    const cur = this.work[it.id] ?? {};
    // ao mexer pela primeira vez, guarda a posição atual (centro do elemento) como ponto de partida
    if (cur.x === undefined) {
      const r = it.el.getBoundingClientRect();
      cur.x = (r.left + r.width / 2) / window.innerWidth * 100; cur.y = (r.top + r.height / 2) / window.innerHeight * 100;
    }
    Object.assign(cur, patch);
    this.work[it.id] = cur;
    this._applyOne(it, this.work);
    this.ui.sizeVal.textContent = Math.round((cur.s ?? 1) * 100) + '%';
    this.ui.opVal.textContent = Math.round((cur.o ?? 1) * 100) + '%';
  }

  open() {
    this.work = JSON.parse(JSON.stringify(this.layout));
    this.open_ = true;
    this.hiddenBefore = this.items.filter((i) => i.el.classList.contains('hidden')).map((i) => i.el);
    for (const el of this.hiddenBefore) el.classList.remove('hidden');
    for (const i of this.items) i.el.classList.add('he-item');
    document.body.classList.add('hud-edit');
    this.el.classList.remove('hidden');
    this.sel = null;
    this.ui.name.textContent = 'TOQUE NUM ELEMENTO';
  }

  close(save) {
    if (save) { this.layout = this.work; try { localStorage.setItem(KEY, JSON.stringify(this.layout)); } catch { /* sem armazenamento */ } }
    this.open_ = false;
    for (const i of this.items) i.el.classList.remove('he-item', 'he-sel');
    for (const el of this.hiddenBefore ?? []) el.classList.add('hidden');
    document.body.classList.remove('hud-edit');
    this.el.classList.add('hidden');
    this.apply();
    this.onClose?.(save);
  }

  reset() {
    this.layout = {};
    try { localStorage.removeItem(KEY); } catch { /* ignore */ }
    this.apply();
  }
}
