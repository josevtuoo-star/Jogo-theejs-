// Interface: HUD, inventário (arrastar e soltar), menu de testes, controles de toque.
import { ITEMS, SLOT_NAMES, makeItem } from './items.js';
import { clamp } from '../engine/math.js';
import { WEATHER } from '../engine/atmosphere.js';

const $ = (h) => { const t = document.createElement('template'); t.innerHTML = h.trim(); return t.content.firstChild; };
const CELL = () => (innerHeight < 520 ? 34 : 40);
const DOLL = ['head', 'face', 'back', 'body', 'vest', 'melee', 'legs', 'feet', 'hands'];
const CAT = { food: 'Comida', drink: 'Bebida', med: 'Médico', tool: 'Ferramentas', cloth: 'Roupas', misc: 'Recursos e outros' };
const svg = (d, w = 1.8) => `<svg viewBox="0 0 24 24" width="100%" height="100%" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const ICON = {
  bag: svg('<path d="M7 8V6a5 5 0 0 1 10 0v2"/><rect x="4" y="8" width="16" height="13" rx="3"/><path d="M9 14h6"/>'),
  eye: svg('<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'),
  menu: svg('<path d="M4 7h16M4 12h16M4 17h16"/>'),
  hand: svg('<path d="M8 12V5.5a1.5 1.5 0 0 1 3 0V11m0-1.5V4.5a1.5 1.5 0 0 1 3 0V11m0-4a1.5 1.5 0 0 1 3 0v6c0 4-2.5 7-6 7-2.7 0-4.2-1.4-5.7-3.6L4 13.5a1.6 1.6 0 0 1 2.6-1.8L8 13"/>'),
  axe: svg('<path d="M5 20 15 10"/><path d="M13 4c3 0 6 1 8 3l-3 3 -2 2 -3 -3 -2 -2z"/>'),
  pick: svg('<path d="M6 20 16 9"/><path d="M3 11c3-5 9-7 15-5 2 .7 3 1.5 3 1.5s-1 .8-3 1c-3 .3-4 1-5 2"/>'),
  car: svg('<path d="M5 16V11l2-5h10l2 5v5"/><path d="M3 16h18v3H3z"/><circle cx="7.5" cy="19" r="1.2"/><circle cx="16.5" cy="19" r="1.2"/>'),
  up: svg('<path d="M6 14l6-6 6 6"/><path d="M6 19l6-6 6 6" opacity=".5"/>'),
  down: svg('<path d="M7 7l5 5 5-5"/><path d="M5 18h14"/>'),
  light: svg('<path d="M9 3h6l1 5H8z"/><path d="M8 8l1 12h6l1-12"/>'),
  food: svg('<path d="M7 3v7a2 2 0 0 0 4 0V3M9 3v18M17 3c-2 2-3 5-3 8h3v10"/>'),
  water: svg('<path d="M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z"/>'),
  temp: svg('<path d="M10 14V5a2 2 0 0 1 4 0v9a4 4 0 1 1-4 0z"/>'),
  blood: svg('<path d="M12 3s6 6 6 10.5A6 6 0 0 1 6 13.5C6 9 12 3 12 3z" fill="currentColor"/>'),
  heart: svg('<path d="M12 20s-7-4.6-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.4-7 10-7 10z"/>'),
  leg: svg('<path d="M9 3v8l-3 3 2 6M15 3v8l-1 4"/><path d="M5 12l4 3" />'),
  swing: svg('<path d="M6 19 17 8"/><path d="M15 4c3 0 5 1 6 3l-3 3-3-3z"/>'),
};
export class UI {
  constructor(game) {
    this.g = game;
    this.root = document.getElementById('ui');
    if (game.input.touchMode) document.body.classList.add('touch');
    this.menuOpen = false; this.invOpen = false; this.sel = null; this.icons = {};
    this.toasts = [];
    this.fpsAcc = 0; this.fpsN = 0; this.fps = 0; this.ms = 0;
    this.buildHUD();
    this.buildInventory();
    this.buildMenu();
    if (game.input.touchMode) this.buildTouch();
    addEventListener('resize', () => this.relayout());
  }

  // ---------------------------------------------------------------- carregamento
  loading(text, p) { const f = document.getElementById('lfill'), t = document.getElementById('ltext'); if (f) f.style.width = Math.round(p * 100) + '%'; if (t) t.textContent = text; }
  loadDone() { const l = document.getElementById('loading'); l.classList.add('hide'); setTimeout(() => (l.style.display = 'none'), 700); }
  loadError(e) { document.getElementById('lerr').textContent = 'Erro: ' + (e && e.message ? e.message : e) + '\n' + (e && e.stack ? e.stack.split('\n').slice(0, 3).join('\n') : ''); }

  // ---------------------------------------------------------------- HUD (limpo: só o essencial)
  buildHUD() {
    const R = this.root;
    R.append($('<div id="vig" class="hud"></div>'));
    R.append($('<div id="bino" class="hud"></div>'));
    R.append($('<div id="cross" class="hud"><i></i><b></b></div>'));
    R.append($('<div id="info" class="hud glass"></div>'));
    R.append($('<div id="dbg" class="hud"></div>'));
    const st = $('<div id="status" class="hud"></div>');
    this.sts = {};
    for (const [k, ic, t] of [['food', 'food', 'Fome'], ['water', 'water', 'Sede'], ['temp', 'temp', 'Temperatura'], ['blood', 'blood', 'Sangue'], ['health', 'heart', 'Saúde'], ['leg', 'leg', 'Perna quebrada']]) {
      const el = $(`<div class="st" title="${t}" data-k="${k}"><div class="ico">${ICON[ic]}</div><small></small></div>`); st.append(el); this.sts[k] = el;
    }
    R.append(st);
    R.append($('<div id="hint" class="hud glass"></div>'));
    R.append($('<div id="prompt" class="hud glass"></div>'));
    R.append($('<div id="actbar" class="hud glass"><span></span><div class="bar"><i></i></div></div>'));
    R.append($('<div id="stam" class="hud"><i></i></div>'));
    const q = $('<div id="quick" class="hud"></div>');
    this.qslots = [];
    for (let i = 0; i < 8; i++) { const s = $(`<div class="qs"><b>${i + 1}</b></div>`); s.addEventListener('pointerdown', (e) => { e.preventDefault(); this.g.audio.unlock(); this.g.player.useQuick(i); this.renderQuick(); }); q.append(s); this.qslots.push(s); }
    R.append(q);
    // botões superiores (iguais no PC e no celular)
    const top = $('<div id="topbtns" class="hud"></div>');
    const mkTop = (ic, fn, id) => { const b = $(`<div class="ibtn" id="${id || ''}">${ICON[ic]}</div>`); b.addEventListener('pointerdown', (e) => { e.preventDefault(); this.g.audio.unlock(); fn(); }); top.append(b); return b; };
    this.btnFlash = mkTop('light', () => this.g.input.press('flashlight'), 'bflash'); this.btnFlash.style.display = 'none';
    mkTop('eye', () => this.g.input.press('camera')); mkTop('bag', () => this.g.input.press('inventory')); mkTop('menu', () => this.g.input.press('menu'));
    R.append(top);
    const d = $('<div id="death" class="hud"><h1>VOCÊ MORREU</h1><div id="dcause"></div><div class="pill" id="drespawn">Renascer</div></div>');
    d.querySelector('#drespawn').addEventListener('click', () => { d.style.display = 'none'; this.g.respawn(); });
    R.append(d);
  }
  // mensagem curta e discreta (substitui a pilha de avisos)
  hint(msg) {
    const h = this.root.querySelector('#hint'); h.textContent = msg; h.classList.add('on');
    clearTimeout(this._ht); this._ht = setTimeout(() => h.classList.remove('on'), 2300);
  }
  toast(msg) { this.hint(msg); }
  hitInfo() {}
  flashMuzzle() {}
  onDeath(cause) { const d = this.root.querySelector('#death'); d.style.display = 'flex'; d.querySelector('#dcause').textContent = 'Causa: ' + (cause || 'ferimentos'); this.closeInv(); this.closeMenu(); this.g.input.exitLock(); }

  iconHTML(item) {
    const d = item.def, src = this.icons[item.id];
    if (src) return `<img src="${src}" draggable="false">`;
    const t = d.tint ? `style="color:rgb(${d.tint.map((c) => Math.min(255, c * 360)).join(',')})"` : '';
    return `<div class="emo" ${t}>${d.icon || '📦'}</div>`;
  }
  renderQuick() {
    const P = this.g.player, inv = this.g.inv; let any = false;
    this.qslots.forEach((el, i) => {
      const it = inv.quick[i];
      el.querySelectorAll('img,.emo,em').forEach((n) => n.remove());
      el.classList.toggle('act', !!it && P.hands === it);
      el.style.display = it ? 'flex' : 'none';
      if (it) { any = true; el.insertAdjacentHTML('beforeend', this.iconHTML(it)); if (it.def.stack > 1) el.insertAdjacentHTML('beforeend', `<em>${it.qty}</em>`); }
    });
    this.root.querySelector('#quick').style.display = any ? 'flex' : 'none';
  }

  update(dt, g) {
    const P = g.player, T = g.tools, atm = g.atm, root = this.root;
    this.fpsAcc += dt; this.fpsN++;
    if (this.fpsAcc > 0.5) { this.fps = this.fpsN / this.fpsAcc; this.ms = this.fpsAcc / this.fpsN * 1000; this.fpsAcc = 0; this.fpsN = 0; }
    // indicadores: só os que precisam de atenção
    const lvl = { food: P.food / 5000, water: P.water / 5000, temp: 1 - Math.abs(P.temp - 36.6) / 3, blood: P.blood / 5000, health: P.health / 100 };
    const warnAt = { food: 0.4, water: 0.4, temp: 0.62, blood: 0.7, health: 0.7 };
    let anyShown = false;
    for (const k of Object.keys(lvl)) {
      const el = this.sts[k], v = clamp(lvl[k], 0, 1), show = v < warnAt[k] || this.invOpen || this.menuOpen;
      el.classList.toggle('show', show); anyShown = anyShown || show;
      if (show) { el.style.setProperty('--p', v); const crit = v < warnAt[k] * 0.5; el.classList.toggle('crit', crit); el.classList.toggle('cold', k === 'temp' && P.temp < 36); el.classList.toggle('hot', k === 'temp' && P.temp > 37.5); if (k === 'temp') el.querySelector('small').textContent = P.temp.toFixed(1) + '°'; }
    }
    this.sts.leg.classList.toggle('show', P.limp); this.sts.leg.classList.toggle('crit', P.limp);
    root.querySelector('#stam').style.opacity = P.stamina < 99 ? 1 : 0; root.querySelector('#stam i').style.width = P.stamina + '%';
    root.querySelector('#stam i').style.background = P.stamina < 20 ? '#e5534b' : '#dfe6c0';
    root.querySelector('#vig').style.opacity = clamp(P.hurt * 1.2 + (P.health < 30 ? (30 - P.health) / 60 : 0) + (P.bleeding ? 0.1 : 0), 0, 1);
    root.querySelector('#bino').style.display = P.zoomBino ? 'block' : 'none';
    // mira: ponto discreto; anel quando há algo para interagir
    const cross = root.querySelector('#cross'), tgt = P.interactTarget || P.resourceTarget;
    cross.classList.toggle('on', !!tgt && !P.inVehicle); cross.style.display = P.inVehicle || (P.camMode === 'tp' && false) ? 'none' : 'block';
    // relógio e temperatura
    const fps = g.settings.showFps ? ` · ${Math.round(this.fps)} fps` : '';
    root.querySelector('#info').textContent = `${atm.hourText} · ${P.airT !== undefined ? P.airT.toFixed(0) + '°C' : ''}${fps}`;
    // prompt contextual
    const pr = root.querySelector('#prompt'), mob = g.input.touchMode;
    let txt = '', mode = 'hand';
    if (P.inVehicle) { txt = `${mob ? '' : '<b>F</b> '}Sair · ${Math.abs(P.inVehicle.speed * 3.6).toFixed(0)} km/h · ${P.inVehicle.fuel.toFixed(0)} L`; mode = 'car'; }
    else if (!this.invOpen && !this.menuOpen) {
      const R = P.resourceTarget, it = P.interactTarget;
      if (R && T.active) { txt = (R.kind === 'tree' ? 'Cortar árvore' : 'Quebrar rocha'); mode = T.def.id === 'axe' ? 'axe' : 'pick'; if ((R.kind === 'tree') !== (T.def.id === 'axe')) txt += R.kind === 'tree' ? ' (precisa do machado)' : ' (precisa da picareta)'; txt = (mob ? '' : '<b>Botão esq.</b> ') + txt; }
      else if (it && it.type === 'loot') { txt = `${mob ? '' : '<b>F</b> '}Pegar ${it.e.item.def.name}${it.e.item.def.stack > 1 ? ' ×' + it.e.item.qty : ''}`; mode = 'hand'; }
      else if (it && it.type === 'vehicle') { txt = `${mob ? '' : '<b>F</b> '}Entrar no veículo`; mode = 'car'; }
      else if (R) { txt = R.kind === 'tree' ? 'Árvore — use o machado' : 'Rocha — use a picareta'; mode = R.kind === 'tree' ? 'axe' : 'pick'; }
      else if (T.active) mode = T.def.id === 'axe' ? 'axe' : 'pick';
    }
    pr.classList.toggle('on', !!txt); pr.classList.toggle('low', !!P.inVehicle); if (txt && pr._t !== txt) { pr.innerHTML = txt; pr._t = txt; }
    // botão de ação (celular)
    if (this.actBtn) {
      if (this._am !== mode) { this._am = mode; this.actBtn.innerHTML = ICON[mode === 'hand' ? 'hand' : mode]; }
      this.actBtn.classList.toggle('ready', !!txt || T.active);
    }
    if (this.btnFlash) this.btnFlash.style.display = (g.inv.all().some((i) => i.def.tool === 'flashlight') && (g.env.night > 0.25 || P.flashlight)) ? 'flex' : 'none';
    this.btnFlash && this.btnFlash.classList.toggle('on', P.flashlight);
    // barra de ação (comer/beber/curar)
    const ab = root.querySelector('#actbar');
    if (P.action && P.action.label) { ab.classList.add('on'); ab.querySelector('span').textContent = P.action.label; ab.querySelector('i').style.width = (P.action.t / P.action.dur * 100) + '%'; } else ab.classList.remove('on');
    // depuração
    const dbg = root.querySelector('#dbg');
    if (g.settings.debug) {
      dbg.style.display = 'block';
      const gl = g.r.gl, s = gl.stats;
      dbg.textContent = `FPS ${this.fps.toFixed(0)} (${this.ms.toFixed(1)} ms)  ${g.r.width}x${g.r.height}\nDraws ${s.draws}  Tris ${(s.tris / 1000).toFixed(0)}k\nÁrvores ${g.veg.stats.trees}  Cobertura ${g.veg.stats.cover}  Chunks ${g.terrain.drawnChunks}\nCorpos ${g.phys.bodies.filter((b) => !b.dead && !b.asleep).length}/${g.phys.bodies.length}  Part ${g.particles.n}\nPos ${P.pos.map((v) => v.toFixed(0)).join(', ')}  v=${(P.lastSpeed || 0).toFixed(1)} m/s\nÁudio: ${g.audio.ctx ? g.audio.ctx.state : 'sem'}  amostras ${Object.keys(g.audio.buffers).length}\n${gl.caps.renderer || ''}`;
    } else dbg.style.display = 'none';
    if (this.menuOpen && this.statsEl) this.refreshStats();
  }
  refreshStats() { const g = this.g, s = g.r.gl.stats; this.statsEl.textContent = `FPS: ${this.fps.toFixed(0)} (${this.ms.toFixed(1)} ms)\nResolução: ${g.r.width} x ${g.r.height} (escala ${g.settings.renderScale})\nDraw calls: ${s.draws}\nTriângulos: ${(s.tris / 1000).toFixed(0)}k\nÁrvores visíveis: ${g.veg.stats.trees} / ${g.veg.treeCount}\nChunks de terreno: ${g.terrain.drawnChunks}\nCorpos rígidos: ${g.phys.bodies.length}\nPartículas: ${g.particles.n}\nÁudio: ${g.audio.ctx ? g.audio.ctx.state : 'sem'}\nGPU: ${g.r.gl.caps.renderer}`; }

  relayout() { if (this.invOpen) this.renderInv(); }

  // ---------------------------------------------------------------- inventário
  buildInventory() {
    const inv = $(`<div id="inv"><div class="top"><div style="font-size:18px;letter-spacing:3px">INVENTÁRIO</div><div id="iw" style="color:var(--dim)"></div><div class="pill" id="iclose">Fechar ✕</div></div>
      <div class="cols"><div class="col"><h3><span>Chão</span><span id="gcount"></span></h3><div class="scroll ground" id="ground" data-drop="ground"></div></div>
      <div class="col" style="flex:1.1"><h3><span>Jogador</span></h3><div class="scroll"><div class="doll" id="doll"></div><div id="ibar"><div id="iinfo">Toque num item para ver ações. Arraste para mover.</div><div id="iact" style="display:flex;gap:6px;flex-wrap:wrap"></div></div></div></div>
      <div class="col" style="flex:1.5"><h3><span>Mochilas e bolsos</span></h3><div class="scroll" id="grids"></div></div></div></div>`);
    this.root.parentNode.append(inv); this.inv = inv;
    inv.querySelector('#iclose').addEventListener('click', () => this.closeInv());
    this.g.onInventoryChange = () => { if (this.invOpen) this.renderInv(); this.renderQuick(); this.g.syncEquipment && this.g.syncEquipment(); };
  }
  openInv() { if (this.g.player.dead) return; this.invOpen = true; this.inv.style.display = 'block'; this.g.input.exitLock(); this.renderInv(); }
  closeInv() { this.invOpen = false; this.inv.style.display = 'none'; this.sel = null; if (!this.g.input.touchMode && !this.menuOpen) this.g.input.requestLock(); }
  toggleInv() { this.invOpen ? this.closeInv() : this.openInv(); }

  renderInv() {
    const g = this.g, inv = g.inv, c = CELL();
    // chão
    const gr = this.inv.querySelector('#ground'); gr.innerHTML = '';
    const near = g.level.loot.filter((e) => { const x = e.body ? e.body.pos[0] : e.x, z = e.body ? e.body.pos[2] : e.z; return Math.hypot(x - g.player.pos[0], z - g.player.pos[2]) < 3.2; });
    this.inv.querySelector('#gcount').textContent = near.length;
    near.forEach((e) => {
      const t = $(`<div class="tile ${e.item === this.sel ? 'sel' : ''}">${this.iconHTML(e.item)}<span>${e.item.def.name}${e.item.def.stack > 1 ? ' ×' + e.item.qty : ''}</span></div>`);
      t.addEventListener('pointerdown', (ev) => this.beginDrag(ev, e.item, t, { ground: e }));
      gr.append(t);
    });
    // boneco
    const doll = this.inv.querySelector('#doll'); doll.innerHTML = '';
    for (const s of DOLL) {
      const it = inv.slots[s];
      const el = $(`<div class="slot ${it ? 'full' : ''}" data-slot="${s}"><span class="nm">${SLOT_NAMES[s]}</span>${it ? this.iconHTML(it) : ''}</div>`);
      if (it) el.addEventListener('pointerdown', (ev) => this.beginDrag(ev, it, el, { slot: s }));
      doll.append(el);
    }
    // grades
    const gd = this.inv.querySelector('#grids'); gd.innerHTML = '';
    for (const gi of inv.grids()) {
      const grid = gi.grid;
      gd.append($(`<div class="ghd"><span>${gi.owner.def.name}</span><span>${grid.w}×${grid.h}</span></div>`));
      const el = $(`<div class="grid" data-gid="${gi.slot}" style="width:${grid.w * c}px;height:${grid.h * c}px;background-size:${c}px ${c}px"></div>`);
      el._grid = grid;
      for (const it of grid.items) {
        const t = $(`<div class="tile ${it === this.sel ? 'sel' : ''}" style="left:${it.gx * c}px;top:${it.gy * c}px;width:${it.def.w * c}px;height:${it.def.h * c}px">${this.iconHTML(it)}${it.def.stack > 1 ? `<em>${it.qty}</em>` : it.def.kind === 'drink' ? `<em>${it.qty}/4</em>` : it.mag !== undefined ? `<em>${it.mag}</em>` : ''}</div>`);
        t.addEventListener('pointerdown', (ev) => this.beginDrag(ev, it, t, { grid }));
        el.append(t);
      }
      gd.append(el);
    }
    this.inv.querySelector('#iw').textContent = `Peso: ${inv.weight().toFixed(1)} kg`;
    this.renderActions();
  }
  renderActions() {
    const it = this.sel, g = this.g, bar = this.inv.querySelector('#iact'), info = this.inv.querySelector('#iinfo');
    bar.innerHTML = '';
    if (!it) { info.textContent = 'Toque num item para ver ações. Arraste para mover.'; return; }
    const d = it.def;
    info.innerHTML = `<b style="color:var(--fg)">${d.name}</b> · ${(d.weight * (d.stack > 1 ? it.qty : 1)).toFixed(2)} kg<br>${d.desc || ''}${it.mag !== undefined ? '<br>Munição no carregador: ' + it.mag : ''}`;
    const add = (label, fn) => { const b = $(`<div class="pill">${label}</div>`); b.addEventListener('click', () => { fn(); this.g.audio.ui(); }); bar.append(b); };
    const onGround = !!it.container === false && !it.slot && g.level.loot.some((e) => e.item === it);
    if (onGround) add('Pegar', () => { const e = g.level.loot.find((e) => e.item === it); if (e) g.player.pickup(e); this.sel = null; this.renderInv(); });
    else {
      if (d.kind === 'food') add('Comer', () => { g.player.useItem(it); this.closeInv(); });
      if (d.kind === 'drink') add('Beber', () => { g.player.useItem(it); this.closeInv(); });
      if (d.kind === 'med') add('Usar', () => { g.player.useItem(it); this.closeInv(); });
      if (d.kind === 'cloth') add(it.slot ? 'Tirar' : 'Vestir', () => { if (it.slot) { const s = it.slot; g.inv.unequip(s); if (!g.inv.add(it)) g.player.drop(it); } else if (!g.inv.slots[d.slot]) g.inv.equip(it, d.slot); this.renderInv(); });
      if (d.kind === 'tool') add(g.player.hands === it ? 'Guardar' : 'Segurar', () => { g.player.hands === it ? g.player.holster() : g.player.wield(it); this.renderInv(); });
      if (d.stack > 1 && it.qty > 1) add('Dividir', () => { const h = Math.floor(it.qty / 2); const c = makeItem(it.id, h); it.qty -= h; if (!g.inv.add(c)) it.qty += h; this.renderInv(); });
      add('Atalho ' + ((g.inv.quick.indexOf(it) >= 0) ? g.inv.quick.indexOf(it) + 1 : '—'), () => { const i = g.inv.quick.indexOf(it); g.inv.quick = g.inv.quick.map((q) => (q === it ? null : q)); const n = (i + 1) % 9; if (n < 8) g.inv.quick[n] = it; this.renderQuick(); this.renderInv(); });
      add('Largar', () => { g.player.drop(it); this.sel = null; this.renderInv(); });
    }
  }
  beginDrag(ev, item, el, src) {
    ev.preventDefault();
    const g = this.g, c = CELL();
    const r = el.getBoundingClientRect();
    const ghost = $(`<div class="ghost" style="width:${item.def.w * c}px;height:${item.def.h * c}px">${this.iconHTML(item)}</div>`);
    document.body.append(ghost);
    const move = (x, y) => { ghost.style.left = x - item.def.w * c / 2 + 'px'; ghost.style.top = y - item.def.h * c / 2 + 'px'; };
    move(ev.clientX, ev.clientY);
    let moved = false; const sx = ev.clientX, sy = ev.clientY;
    const onMove = (e) => { if (Math.hypot(e.clientX - sx, e.clientY - sy) > 6) moved = true; move(e.clientX, e.clientY); document.querySelectorAll('.slot.drop').forEach((s) => s.classList.remove('drop')); const s = this.slotAt(e.clientX, e.clientY); if (s) s.classList.add('drop'); };
    const onUp = (e) => {
      removeEventListener('pointermove', onMove); removeEventListener('pointerup', onUp); removeEventListener('pointercancel', onUp);
      ghost.remove(); document.querySelectorAll('.slot.drop').forEach((s) => s.classList.remove('drop'));
      if (!moved) { // toque: seleciona / duplo toque: ação primária
        const now = performance.now();
        if (this._lastTap && this._lastTap.item === item && now - this._lastTap.t < 380) { this.primary(item, src); this._lastTap = null; }
        else { this._lastTap = { item, t: now }; this.sel = item; this.renderInv(); }
        return;
      }
      this.dropAt(item, src, e.clientX, e.clientY);
    };
    addEventListener('pointermove', onMove); addEventListener('pointerup', onUp); addEventListener('pointercancel', onUp);
  }
  slotAt(x, y) { for (const s of this.inv.querySelectorAll('.slot')) { const r = s.getBoundingClientRect(); if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) return s; } return null; }
  primary(item, src) {
    const g = this.g, d = item.def;
    if (src.ground) { g.player.pickup(src.ground); this.sel = null; this.renderInv(); return; }
    if (d.kind === 'cloth') { if (item.slot) { g.inv.unequip(item.slot); if (!g.inv.add(item)) g.player.drop(item); } else g.inv.equip(item, d.slot); this.renderInv(); return; }
    if (['food', 'drink', 'med'].includes(d.kind)) { g.player.useItem(item); this.closeInv(); return; }
    g.player.wield(item); this.renderInv();
  }
  dropAt(item, src, x, y) {
    const g = this.g, inv = g.inv, c = CELL();
    const wasGround = src.ground;
    // slot do boneco
    const s = this.slotAt(x, y);
    if (s) {
      const slot = s.dataset.slot;
      if (slot === 'hands') { g.player.wield(item); this.renderInv(); return; }
      if (item.def.slot === slot && !inv.slots[slot]) { if (wasGround) { if (!g.player.pickup(src.ground)) return; if (item.container) item.container.remove(item); } if (item.slot) inv.unequip(item.slot); inv.equip(item, slot); this.renderInv(); return; }
      g.ui.toast('Não cabe nesse espaço'); this.renderInv(); return;
    }
    // grades
    for (const el of this.inv.querySelectorAll('.grid')) {
      const r = el.getBoundingClientRect();
      if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) {
        const grid = el._grid;
        const gx = Math.floor((x - r.left - item.def.w * c / 2 + c / 2) / c), gy = Math.floor((y - r.top - item.def.h * c / 2 + c / 2) / c);
        if (wasGround) { g.level.removeLoot(wasGround); if (item.container) item.container.remove(item); }
        if (item.slot && inv.slots[item.slot] === item) { inv.slots[item.slot] = null; item.slot = null; if (g.player.hands === item) g.player.hands = null; }
        if (grid.fits(item, gx, gy, item) || (item.container === grid && grid.fits(item, gx, gy, item))) { inv.moveTo(item, grid, gx, gy); }
        else if (item.container !== grid && grid.fits(item, gx, gy)) inv.moveTo(item, grid, gx, gy);
        else if (!inv.add(item)) g.player.drop(item);
        this.renderInv(); return;
      }
    }
    // soltar no chão
    const gr = this.inv.querySelector('#ground').getBoundingClientRect();
    if (x >= gr.left && x <= gr.right && y >= gr.top && y <= gr.bottom) { if (!wasGround) g.player.drop(item); this.sel = null; this.renderInv(); return; }
    this.renderInv();
  }

  // ---------------------------------------------------------------- toque
  buildTouch() {
    const g = this.g, R = this.root, inp = g.input;
    R.parentNode.append($('<div id="joy"><i></i></div>'));
    const joy = document.getElementById('joy'), jk = joy.querySelector('i');
    inp.onJoy = (j, on) => { joy.style.display = on ? 'block' : 'none'; if (on) { joy.style.left = j.ox + 'px'; joy.style.top = j.oy + 'px'; jk.style.transform = `translate(${j.px || 0}px,${j.py || 0}px)`; joy.classList.toggle('fast', Math.hypot(j.x, j.y) > 0.93); } };
    const mk = (cls, icon, style, onDown, onUp) => {
      const b = $(`<div class="tbtn ${cls}" style="${style}">${icon}</div>`);
      const down = (e) => { e.preventDefault(); g.audio.unlock(); b.classList.add('on'); onDown && onDown(); };
      const up = (e) => { e.preventDefault(); b.classList.remove('on'); onUp && onUp(); };
      b.addEventListener('pointerdown', down); b.addEventListener('pointerup', up); b.addEventListener('pointercancel', up); b.addEventListener('pointerleave', up);
      R.append(b); return b;
    };
    const rb = 'calc(var(--safe-r) + ', bb = 'calc(var(--safe-b) + ';
    this.actBtn = mk('act', ICON.hand, `right:${rb}26px);bottom:${bb}28px)`, () => inp.press('action'));
    mk('sm', ICON.up, `right:${rb}140px);bottom:${bb}34px)`, () => { inp.press('jump'); inp.setButton('jump', true); }, () => inp.setButton('jump', false));
    mk('sm', ICON.down, `right:${rb}36px);bottom:${bb}132px)`, () => inp.press('crouch'));
  }

  // ---------------------------------------------------------------- menu
  buildMenu() {
    const g = this.g;
    const m = $(`<div id="menu"><div class="tabs"></div><div class="body"></div><div class="foot"><span id="mver">Laboratório v1 · motor próprio WebGL2</span><div class="pill" id="mclose">Continuar ▶</div></div></div>`);
    this.root.parentNode.append(m); this.menu = m;
    m.querySelector('#mclose').addEventListener('click', () => this.closeMenu());
    this.tabs = {};
    const tabs = m.querySelector('.tabs'), body = m.querySelector('.body');
    const addTab = (id, label, fn) => { const t = $(`<div class="tab">${label}</div>`); t.addEventListener('click', () => this.showTab(id)); tabs.append(t); this.tabs[id] = { el: t, fn }; };
    addTab('game', 'Jogo', (b) => this.tabGame(b)); addTab('gfx', 'Gráficos', (b) => this.tabGfx(b)); addTab('world', 'Mundo', (b) => this.tabWorld(b));
    addTab('player', 'Jogador', (b) => this.tabPlayer(b)); addTab('items', 'Itens', (b) => this.tabItems(b)); addTab('stats', 'Desempenho', (b) => this.tabStats(b)); addTab('help', 'Ajuda', (b) => this.tabHelp(b));
    this.menuBody = body; this.curTab = 'game';
  }
  showTab(id) { this.curTab = id; for (const [k, t] of Object.entries(this.tabs)) t.el.classList.toggle('on', k === id); const b = this.menuBody; b.innerHTML = ''; this.statsEl = null; this.tabs[id].fn(b); }
  openMenu() { this.menuOpen = true; this.menu.style.display = 'flex'; this.g.input.exitLock(); this.showTab(this.curTab); }
  closeMenu() { this.menuOpen = false; this.menu.style.display = 'none'; this.g.saveSettings(); if (!this.g.input.touchMode && !this.invOpen) this.g.input.requestLock(); }
  toggleMenu() { this.menuOpen ? this.closeMenu() : this.openMenu(); }

  // helpers de controle
  slider(p, label, min, max, step, get, set, fmt = (v) => v) {
    const r = $(`<div class="row"><label>${label}</label><input type="range" min="${min}" max="${max}" step="${step}"><span class="v"></span></div>`);
    const i = r.querySelector('input'), v = r.querySelector('.v');
    i.value = get(); v.textContent = fmt(+i.value);
    i.addEventListener('input', () => { set(+i.value); v.textContent = fmt(+i.value); });
    p.append(r); return i;
  }
  toggle(p, label, get, set) {
    const r = $(`<div class="row"><label>${label}</label><div class="pill"></div></div>`), b = r.querySelector('.pill');
    const upd = () => { b.textContent = get() ? 'Ligado' : 'Desligado'; b.classList.toggle('on', !!get()); };
    b.addEventListener('click', () => { set(!get()); upd(); }); upd(); p.append(r);
  }
  select(p, label, opts, get, set) {
    const r = $(`<div class="row"><label>${label}</label><select></select></div>`), s = r.querySelector('select');
    opts.forEach(([v, t]) => s.append($(`<option value="${v}">${t}</option>`)));
    s.value = get(); s.addEventListener('change', () => set(isNaN(+s.value) ? s.value : +s.value)); p.append(r);
  }
  buttons(p, list) { const d = $('<div class="btns"></div>'); for (const [t, fn] of list) { const b = $(`<div class="pill">${t}</div>`); b.addEventListener('click', () => { fn(b); this.g.audio.ui(); }); d.append(b); } p.append(d); return d; }

  tabGame(b) {
    const g = this.g, S = g.settings;
    b.append($('<h4>Controles</h4>'));
    this.slider(b, 'Sensibilidade', 0.3, 3, 0.05, () => S.sens, (v) => { S.sens = v; g.input.sens = v; }, (v) => v.toFixed(2));
    this.slider(b, 'Campo de visão (FOV)', 60, 105, 1, () => S.fov, (v) => (S.fov = v), (v) => v + '°');
    this.toggle(b, 'Inverter eixo Y', () => S.invertY, (v) => { S.invertY = v; });
    this.toggle(b, 'Câmera em 3ª pessoa', () => g.player.camMode === 'tp', (v) => { g.player.camMode = v ? 'tp' : 'fp'; });
    this.toggle(b, 'Andar devagar (caminhada)', () => g.player.walkMode, (v) => (g.player.walkMode = v));
    b.append($('<h4>Áudio e informações</h4>'));
    this.slider(b, 'Volume geral', 0, 1, 0.05, () => S.volume, (v) => { S.volume = v; g.audio.setVolume(v); }, (v) => Math.round(v * 100) + '%');
    this.toggle(b, 'Mostrar FPS', () => S.showFps, (v) => (S.showFps = v));
    this.toggle(b, 'Painel de depuração (F3)', () => S.debug, (v) => (S.debug = v));
    b.append($('<h4>Sobrevivência</h4>'));
    this.slider(b, 'Velocidade de fome/sede', 1, 120, 1, () => g.player.statsRate, (v) => (g.player.statsRate = v), (v) => '×' + v);
    this.buttons(b, [['Renascer (novo personagem)', () => { this.closeMenu(); g.respawn(); }], ['Curar tudo', () => { const P = g.player; P.health = 100; P.blood = 5000; P.food = 5000; P.water = 5000; P.temp = 36.6; P.bleeding = 0; P.limp = false; P.wet = 0; this.toast('Curado'); }]]);
  }
  tabGfx(b) {
    const g = this.g, S = g.settings;
    b.append($('<h4>Qualidade</h4>'));
    this.select(b, 'Predefinição', [['low', 'Baixa'], ['medium', 'Média'], ['high', 'Alta'], ['ultra', 'Ultra']], () => S.quality, (v) => { g.applyPreset(v); this.showTab('gfx'); });
    this.slider(b, 'Resolução de renderização', 0.35, 1.25, 0.05, () => S.renderScale, (v) => { S.renderScale = v; S.renderScaleBase = v; g.r.settings.renderScale = v; g.r.resize(); }, (v) => Math.round(v * 100) + '%');
    this.select(b, 'Sombras', [[0, 'Desligadas'], [1, '1 cascata'], [2, '2 cascatas'], [3, '3 cascatas']], () => S.shadows, (v) => { S.shadows = v; g.r.setShadowQuality(v, S.shadowSize); });
    this.select(b, 'Resolução das sombras', [[1024, '1024'], [2048, '2048'], [3072, '3072']], () => S.shadowSize, (v) => { S.shadowSize = v; g.r.setShadowQuality(S.shadows, v); });
    this.select(b, 'Grama', [[0, 'Desligada'], [1, 'Baixa'], [2, 'Média'], [3, 'Alta']], () => S.grass, (v) => { S.grass = v; g.veg.setGrassQuality(v); });
    this.slider(b, 'Distância da vegetação', 0.4, 1.5, 0.05, () => S.vegDist, (v) => { S.vegDist = v; g.veg.distScale = v; }, (v) => '×' + v.toFixed(2));
    this.slider(b, 'Alcance de visão', 400, 2400, 50, () => S.far, (v) => { S.far = v; }, (v) => v + ' m');
    this.slider(b, 'Exposição', 0.5, 1.8, 0.05, () => S.exposure, (v) => { S.exposure = v; }, (v) => v.toFixed(2));
    this.slider(b, 'Anisotropia de textura', 1, 16, 1, () => S.aniso, (v) => { S.aniso = v; }, (v) => v + 'x');
    this.toggle(b, 'Limitar a 60 FPS', () => S.cap60, (v) => (S.cap60 = v));
    this.toggle(b, 'Resolução dinâmica (auto)', () => S.autoRes, (v) => { S.autoRes = v; S.renderScaleBase = S.renderScale; });
    this.toggle(b, 'Suavização MSAA (reinicia)', () => S.msaa, (v) => { S.msaa = v; g.saveSettings(); if (confirm('Recarregar para aplicar?')) location.reload(); });
    b.append($('<div class="help">Dica: no celular a resolução de renderização é o ajuste que mais impacta o desempenho.</div>'));
  }
  tabWorld(b) {
    const g = this.g, a = g.atm;
    b.append($('<h4>Tempo e clima</h4>'));
    const hs = this.slider(b, 'Hora do dia', 0, 24, 0.1, () => a.hour, (v) => { a.hour = v; }, (v) => a.hourText);
    this.select(b, 'Velocidade do tempo', [[0, 'Parado'], [1, 'Tempo real'], [30, '×30 (dia = 48 min)'], [120, '×120'], [600, '×600']], () => a.paused ? 0 : a.timeScale, (v) => { a.paused = v === 0; if (v) a.timeScale = v; });
    this.buttons(b, [['Amanhecer', () => (a.hour = 5.8)], ['Meio-dia', () => (a.hour = 12)], ['Entardecer', () => (a.hour = 18.4)], ['Noite', () => (a.hour = 1)]]);
    b.append($('<div style="height:6px"></div>'));
    this.buttons(b, Object.keys(WEATHER).map((k) => [{ clear: '☀️ Limpo', cloudy: '⛅ Nublado', overcast: '☁️ Encoberto', rain: '🌧️ Chuva', storm: '⛈️ Tempestade', fog: '🌫️ Neblina' }[k], () => a.setWeather(k)]));
    b.append($('<h4>Teleportar</h4>'));
    const tp = (n, x, z) => [n, () => { g.teleport(x, z); this.closeMenu(); }];
    this.buttons(b, [tp('Início / área de testes', g.world.spawn.x, g.world.spawn.z), ...g.world.towns.map((t) => tp(t.name, t.x, t.z + 30)), tp('Depósito', 1280, 1790), tp('Lago', 640, 1560), tp('Montanha', 1750, 300), tp('Floresta densa', 1476, 388)]);
    b.append($('<h4>Física</h4>'));
    this.buttons(b, [['Derrubar pilha de caixas', () => { for (const dp of g.level.dynProps) if (!dp.body.dead) g.phys.applyImpulse(dp.body, [Math.random() * 40 - 20, 30, Math.random() * 40 - 20], dp.body.pos); }]]);
  }
  tabPlayer(b) {
    const g = this.g, P = g.player;
    b.append($('<h4>Modos de teste</h4>'));
    this.toggle(b, 'Invencível', () => P.god, (v) => (P.god = v));
    this.toggle(b, 'Voar / atravessar (N)', () => P.noclip, (v) => (P.noclip = v));
    this.slider(b, 'Multiplicador de velocidade', 0.5, 6, 0.1, () => P.speedMul, (v) => (P.speedMul = v), (v) => '×' + v.toFixed(1));
    b.append($('<h4>Estados</h4>'));
    this.slider(b, 'Saúde', 1, 100, 1, () => P.health, (v) => (P.health = v));
    this.slider(b, 'Comida (kcal)', 0, 5000, 50, () => P.food, (v) => (P.food = v));
    this.slider(b, 'Água (ml)', 0, 5000, 50, () => P.water, (v) => (P.water = v));
    this.slider(b, 'Temperatura corporal', 32, 40, 0.1, () => P.temp, (v) => (P.temp = v), (v) => v.toFixed(1) + '°');
    this.buttons(b, [['Sangrar', () => (P.bleeding = 2)], ['Quebrar perna', () => (P.limp = true)], ['Dano 30', () => P.damage(30, 'teste')], ['Subir 80 m', () => (P.pos[1] += 80)]]);
    b.append($('<h4>Veículos</h4>'));
    this.buttons(b, [['Criar carro à frente', () => g.spawnVehicle()], ['Reabastecer', () => g.vehicles.forEach((v) => (v.fuel = 40))]]);
  }
  tabItems(b) {
    const g = this.g;
    b.append($('<div class="help">Toque num item para adicioná-lo ao inventário (ou ao chão, se não couber).</div>'));
    const cats = {};
    for (const [id, d] of Object.entries(ITEMS)) (cats[d.kind] = cats[d.kind] || []).push([id, d]);
    for (const [k, list] of Object.entries(cats)) {
      b.append($(`<h4>${CAT[k] || k}</h4>`));
      this.buttons(b, list.map(([id, d]) => [d.name, () => { const it = makeItem(id); if (d.kind === 'cloth' && !g.inv.slots[d.slot]) g.inv.equip(it, d.slot); else if (!g.inv.add(it)) { const dir = g.player.aimDir(); g.level.spawnItemBody(it, [g.player.pos[0] + dir[0], g.player.pos[1] + 1.4, g.player.pos[2] + dir[2]], [dir[0] * 2, 2, dir[2] * 2]); } this.toast('+ ' + d.name); }]));
    }
  }
  tabStats(b) { const p = $('<div class="help" style="white-space:pre;font:12px/1.5 ui-monospace,Menlo,monospace"></div>'); b.append(p); this.statsEl = p; this.refreshStats(); b.append($('<div class="help" style="margin-top:8px">Meta de desempenho: 60 FPS no POCO X7 Pro com a predefinição Alta (resolução 75%). Ajuste resolução, sombras e grama para encontrar o equilíbrio.</div>')); }
  tabHelp(b) {
    b.append($(`<div class="help"><b>PC:</b> <kbd>W A S D</kbd> mover · mouse olhar · <kbd>Shift</kbd> correr · <kbd>C</kbd> agachar · <kbd>Espaço</kbd> pular · botão esquerdo: cortar/quebrar/pegar · <kbd>F</kbd> interagir · <kbd>Tab</kbd> inventário · <kbd>1</kbd>–<kbd>8</kbd> atalhos · <kbd>V</kbd> 1ª/3ª pessoa · <kbd>L</kbd> lanterna · <kbd>G</kbd> largar · <kbd>H</kbd> guardar · <kbd>N</kbd> voar · <kbd>F3</kbd> depuração · <kbd>Esc</kbd> menu.<br><br>
<b>Celular:</b> arraste à esquerda para mover (empurre até a borda para correr), arraste à direita para olhar. <b>Toque direto</b> num item para pegar, num carro para entrar, numa árvore ou rocha para golpear (equipa a ferramenta certa sozinho). O botão grande faz a ação do momento; ⤒ pula; ⤓ agacha.<br><br>
<b>Recursos:</b> o <b>machado</b> derruba árvores (madeira); a <b>picareta</b> quebra rochas (pedra). Ambos estão no seu inventário.<br><br>
<b>Créditos:</b> personagem e animações Quaternius (CC0); machado, picareta e props do Poly Haven (CC0); carros e sons da Kenney (CC0); sons do OpenGameArt (CC0). Veja CREDITS.md.</div>`));
  }
}
