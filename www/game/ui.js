// Interface: HUD, inventário (arrastar e soltar), menu de testes, controles de toque.
import { ITEMS, SLOT_NAMES, makeItem } from './items.js';
import { clamp } from '../engine/math.js';
import { WEATHER } from '../engine/atmosphere.js';

const $ = (h) => { const t = document.createElement('template'); t.innerHTML = h.trim(); return t.content.firstChild; };
const CELL = () => (innerHeight < 520 ? 34 : 40);
const DOLL = ['head', 'face', 'back', 'body', 'vest', 'melee', 'legs', 'feet', 'hands', 'primary', 'secondary'];
const CAT = { weapon: 'Armas', ammo: 'Munição', food: 'Comida', drink: 'Bebida', med: 'Médico', tool: 'Ferramentas', cloth: 'Roupas', misc: 'Outros', throw: 'Explosivos' };
const DIRS = ['N', 'NE', 'L', 'SE', 'S', 'SO', 'O', 'NO'];

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

  // ---------------------------------------------------------------- HUD
  buildHUD() {
    const R = this.root;
    R.append($('<div id="cross" class="hud"><i></i><div class="ring"></div></div>'));
    R.append($('<div id="hitm"></div>'));
    R.append($('<div id="vig" class="hud"></div>'));
    R.append($('<div id="flash" class="hud"></div>'));
    R.append($('<div id="bino" class="hud"></div>'));
    R.append($('<div id="compass" class="hud">N</div>'));
    R.append($('<div id="info" class="hud"></div>'));
    R.append($('<div id="dbg" class="hud"></div>'));
    R.append($('<div id="hitinfo" class="hud"></div>'));
    R.append($('<div id="toasts" class="hud"></div>'));
    R.append($('<div id="prompt" class="hud"></div>'));
    R.append($('<div id="actbar" class="hud"><div class="t"></div><div class="bar"><i></i></div></div>'));
    R.append($('<div id="ammo" class="hud"><div class="a"></div><div class="w"></div></div>'));
    R.append($('<div id="stam" class="hud"><div class="t">RESISTÊNCIA</div><div class="bar"><i></i></div></div>'));
    const st = $('<div id="status" class="hud"></div>');
    this.sts = {};
    for (const [k, e, t] of [['food', '🍖', 'Fome'], ['water', '💧', 'Sede'], ['temp', '🌡️', 'Temp.'], ['blood', '🩸', 'Sangue'], ['health', '❤️', 'Saúde']]) { const el = $(`<div class="st" title="${t}"><span>${e}</span><small></small></div>`); st.append(el); this.sts[k] = el; }
    R.append(st);
    const q = $('<div id="quick" class="hud"></div>');
    this.qslots = [];
    for (let i = 0; i < 8; i++) { const s = $(`<div class="qs"><b>${i + 1}</b></div>`); s.addEventListener('pointerdown', (e) => { e.preventDefault(); this.g.audio.resume(); this.g.player.useQuick(i); this.renderQuick(); }); q.append(s); this.qslots.push(s); }
    R.append(q);
    const d = $('<div id="death" class="hud"><h1>VOCÊ MORREU</h1><div id="dcause" style="color:#ddd"></div><div class="pill" id="drespawn">Renascer</div></div>');
    d.querySelector('#drespawn').addEventListener('click', () => { d.style.display = 'none'; this.g.respawn(); });
    R.append(d);
  }
  toast(msg) {
    const t = $(`<div class="toast">${msg}</div>`);
    const box = this.root.querySelector('#toasts');
    box.append(t); setTimeout(() => t.remove(), 3100);
    while (box.children.length > 4) box.firstChild.remove();
  }
  flashMuzzle() { const f = this.root.querySelector('#flash'); f.style.transition = 'none'; f.style.opacity = '0.8'; requestAnimationFrame(() => { f.style.transition = 'opacity .09s'; f.style.opacity = '0'; }); }
  hitInfo(dist, data, other) { const h = this.root.querySelector('#hitinfo'); h.textContent = `${dist.toFixed(0)} m` + (other ? '' : ' · alvo'); h.style.opacity = 1; clearTimeout(this._hi); this._hi = setTimeout(() => (h.style.opacity = 0), 1500); }
  onDeath(cause) { const d = this.root.querySelector('#death'); d.style.display = 'flex'; d.querySelector('#dcause').textContent = 'Causa: ' + (cause || 'ferimentos'); this.closeInv(); this.closeMenu(); this.g.input.exitLock(); }

  iconHTML(item, cls = '') {
    const d = item.def, src = this.icons[item.id];
    if (src) return `<img src="${src}" draggable="false">`;
    const t = d.tint ? `style="background:rgb(${d.tint.map((c) => Math.min(255, c * 330)).join(',')})"` : '';
    return `<div class="emo" ${t}>${d.icon || '📦'}</div>`;
  }

  renderQuick() {
    const P = this.g.player, inv = this.g.inv;
    this.qslots.forEach((el, i) => {
      const it = inv.quick[i];
      el.classList.toggle('act', !!it && P.hands === it);
      el.querySelector('img,.emo,em')?.remove();
      el.querySelectorAll('img,.emo,em').forEach((n) => n.remove());
      if (it) { el.insertAdjacentHTML('beforeend', this.iconHTML(it)); if (it.def.stack > 1) el.insertAdjacentHTML('beforeend', `<em>${it.qty}</em>`); }
    });
  }

  update(dt, g) {
    const P = g.player, W = g.weapons, atm = g.atm, root = this.root;
    this.fpsAcc += dt; this.fpsN++;
    if (this.fpsAcc > 0.5) { this.fps = this.fpsN / this.fpsAcc; this.ms = this.fpsAcc / this.fpsN * 1000; this.fpsAcc = 0; this.fpsN = 0; }
    // status
    const set = (k, v, txt) => { const el = this.sts[k]; el.style.setProperty('--p', clamp(v, 0, 1)); const c = v < 0.18 ? '#e5534b' : v < 0.35 ? '#e0b34a' : '#e8e6df'; el.style.setProperty('--c', c); if (txt !== undefined) el.querySelector('small').textContent = txt; };
    set('food', P.food / 5000); set('water', P.water / 5000);
    const tv = clamp((P.temp - 33) / 5, 0, 1); set('temp', tv, P.temp.toFixed(1) + '°');
    if (P.temp < 35.5) this.sts.temp.style.setProperty('--c', '#6fb3e0'); else if (P.temp > 38) this.sts.temp.style.setProperty('--c', '#e5834b');
    set('blood', P.blood / 5000); set('health', P.health / 100);
    // stamina
    root.querySelector('#stam .bar i').style.width = P.stamina + '%';
    root.querySelector('#stam .bar i').style.background = P.stamina < 20 ? '#d9534f' : '#cfd8a0';
    root.querySelector('#stam .t').textContent = ['EM PÉ', 'AGACHADO', 'DEITADO'][P.stance] + (P.sprinting ? ' · CORRENDO' : P.swimming ? ' · NADANDO' : '') + (P.limp ? ' · PERNA QUEBRADA' : '');
    // mira
    const ring = root.querySelector('#cross .ring');
    const hasGun = W.isGun;
    const spread = hasGun ? 4 + (1 - W.adsT) * 26 + Math.min(1, P.lastSpeed / 4) * 18 + W.kick * 14 : 0;
    ring.style.width = ring.style.height = spread * 2 + 'px'; ring.style.opacity = hasGun ? 1 - W.adsT : 0;
    root.querySelector('#cross i').style.opacity = W.adsT > 0.6 ? 0.25 : 0.9;
    root.querySelector('#hitm').style.opacity = W.hitMarker;
    root.querySelector('#bino').style.display = P.zoomBino ? 'block' : 'none';
    root.querySelector('#vig').style.opacity = clamp(P.hurt * 1.2 + (P.health < 30 ? (30 - P.health) / 60 : 0) + (P.bleeding ? 0.12 : 0), 0, 1);
    // munição
    const am = root.querySelector('#ammo');
    if (W.item && hasGun) { am.style.display = 'block'; am.querySelector('.a').innerHTML = `${W.item.mag}<small> / ${W.ammoAvailable()}</small>`; am.querySelector('.w').textContent = W.item.def.name + (W.state === 'reload' ? ' · recarregando' : ''); }
    else if (P.hands) { am.style.display = 'block'; am.querySelector('.a').innerHTML = P.hands.id === 'grenade' ? `${g.inv.count('grenade')}` : ''; am.querySelector('.w').textContent = P.hands.def.name; }
    else am.style.display = 'none';
    // bússola
    const yaw = ((-P.camYaw % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2);
    const deg = Math.round(yaw * 180 / Math.PI);
    root.querySelector('#compass').textContent = `${DIRS[Math.round(yaw / (Math.PI / 4)) % 8]}  ${String(deg).padStart(3, '0')}°`;
    // info
    const wn = { clear: 'Limpo ☀️', cloudy: 'Nublado ⛅', overcast: 'Encoberto ☁️', rain: 'Chuva 🌧️', storm: 'Tempestade ⛈️', fog: 'Neblina 🌫️' }[atm.weatherName];
    root.querySelector('#info').textContent = `${atm.hourText} · ${wn} · ${P.airT !== undefined ? P.airT.toFixed(0) + '°C' : ''} · ${g.settings.showFps ? Math.round(this.fps) + ' fps' : ''}`;
    // prompt de interação
    const pr = root.querySelector('#prompt'), t = P.interactTarget;
    if (t && !this.invOpen && !this.menuOpen && !P.inVehicle) { pr.style.display = 'block'; pr.innerHTML = t.type === 'loot' ? `<b>[F]</b> Pegar ${t.e.item.def.name}${t.e.item.def.stack > 1 ? ' ×' + t.e.item.qty : ''}` : `<b>[F]</b> Entrar no veículo`; }
    else if (P.inVehicle) { pr.style.display = 'block'; pr.innerHTML = `<b>[F]</b> Sair · ${Math.abs(P.inVehicle.speed * 3.6).toFixed(0)} km/h · combustível ${P.inVehicle.fuel.toFixed(0)} L`; }
    else pr.style.display = 'none';
    this.touchInteract && (this.touchInteract.style.display = (t || P.inVehicle) ? 'flex' : 'none');
    // barra de ação
    const ab = root.querySelector('#actbar');
    if (P.action) { ab.style.display = 'block'; ab.querySelector('.t').textContent = P.action.label; ab.querySelector('.bar i').style.width = (P.action.t / P.action.dur * 100) + '%'; } else ab.style.display = 'none';
    // debug
    const dbg = root.querySelector('#dbg');
    if (g.settings.debug) {
      dbg.style.display = 'block';
      const gl = g.r.gl, s = gl.stats;
      const mem = performance.memory ? (performance.memory.usedJSHeapSize / 1048576).toFixed(0) + ' MB' : 'n/d';
      dbg.textContent = `FPS ${this.fps.toFixed(0)}  (${this.ms.toFixed(1)} ms)  ${g.r.width}x${g.r.height}\nDraws ${s.draws}  Tris ${(s.tris / 1000).toFixed(0)}k  Prog ${s.programs}\nÁrvores ${g.veg.stats.trees}  Cobertura ${g.veg.stats.cover}  Chunks ${g.terrain.drawnChunks}\nCorpos ${g.phys.bodies.filter((b) => !b.dead && !b.asleep).length}/${g.phys.bodies.length}  Proj ${g.phys.projectiles.length}  Part ${g.particles.n}\nPos ${P.pos.map((v) => v.toFixed(0)).join(', ')}  v=${(P.lastSpeed || 0).toFixed(1)} m/s  alt ${(P.pos[1] - g.world.heightAt(P.pos[0], P.pos[2])).toFixed(1)}\nJS heap ${mem}\n${gl.caps.renderer || ''}`;
    } else dbg.style.display = 'none';
    // menu stats
    if (this.menuOpen && this.statsEl) this.refreshStats();
  }
  refreshStats() { const g = this.g, s = g.r.gl.stats; this.statsEl.textContent = `FPS: ${this.fps.toFixed(0)} (${this.ms.toFixed(1)} ms)\nResolução: ${g.r.width} x ${g.r.height} (escala ${g.settings.renderScale})\nDraw calls: ${s.draws}\nTriângulos: ${(s.tris / 1000).toFixed(0)}k\nÁrvores visíveis: ${g.veg.stats.trees} / ${g.veg.treeCount}\nChunks de terreno: ${g.terrain.drawnChunks}\nCorpos rígidos: ${g.phys.bodies.length}\nProjéteis: ${g.phys.projectiles.length}\nPartículas: ${g.particles.n}\nGPU: ${g.r.gl.caps.renderer}\nWebGL2 aniso máx: ${g.r.gl.caps.aniso}x`; }

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
      if (['weapon', 'tool', 'throw'].includes(d.kind)) add(g.player.hands === it ? 'Guardar' : 'Segurar', () => { g.player.hands === it ? g.player.holster() : g.player.wield(it); this.renderInv(); });
      if (d.weapon && WDEF(d.weapon) && it.mag !== undefined) add('Descarregar', () => { const n = it.mag; if (n > 0) { it.mag = 0; const am = makeItem('ammo_' + (d.weapon === 'mosin' ? '762' : '45'), n); if (!g.inv.add(am)) g.level.spawnItemBody(am, [g.player.pos[0], g.player.pos[1] + 1, g.player.pos[2]], [0, 1, 0]); } this.renderInv(); });
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
    inp.onJoy = (j, on) => { joy.style.display = on ? 'block' : 'none'; if (on) { joy.style.left = j.ox + 'px'; joy.style.top = j.oy + 'px'; jk.style.transform = `translate(${j.px || 0}px,${j.py || 0}px)`; } };
    const mk = (name, label, cls, style, hold = true, fn) => {
      const b = $(`<div class="tbtn ${cls || ''}" style="${style}">${label}</div>`);
      const down = (e) => { e.preventDefault(); g.audio.resume(); if (fn) fn(true); else inp.setButton(name, true); b.classList.add('on'); };
      const up = (e) => { e.preventDefault(); if (fn) fn(false); else if (hold) inp.setButton(name, false); b.classList.remove('on'); };
      b.addEventListener('pointerdown', down); b.addEventListener('pointerup', up); b.addEventListener('pointercancel', up); b.addEventListener('pointerleave', up);
      R.append(b); return b;
    };
    const rb = `calc(var(--safe-r) + `, bb = `calc(var(--safe-b) + `;
    mk('fire', '🔥', '', `right:${rb}30px);bottom:${bb}34px);width:92px;height:92px;font-size:34px`, true);
    mk('aim', '🎯', '', `right:${rb}134px);bottom:${bb}44px);width:68px;height:68px`, true);
    mk('jump', '⤒', '', `right:${rb}34px);bottom:${bb}140px);width:62px;height:62px`, false, (d) => d && inp.press('jump'));
    mk('reload', '⟳', '', `right:${rb}110px);bottom:${bb}122px);width:54px;height:54px;font-size:22px`, false, (d) => d && inp.press('reload'));
    this.touchInteract = mk('interact', 'F', '', `right:${rb}170px);bottom:${bb}60px);width:60px;height:60px;display:none;font-weight:700`, false, (d) => d && inp.press('interact'));
    mk('crouch', '⤓', '', `left:calc(var(--safe-l) + 18px);bottom:${bb}175px);width:54px;height:54px`, false, (d) => d && inp.press('crouch'));
    mk('prone', '▭', '', `left:calc(var(--safe-l) + 80px);bottom:${bb}175px);width:44px;height:44px;font-size:18px`, false, (d) => d && inp.press('prone'));
    mk('sprint', '»', '', `left:calc(var(--safe-l) + 18px);bottom:${bb}235px);width:54px;height:54px;font-size:28px`, false, (d) => { if (d) { g.player.sprintLatch = !g.player.sprintLatch; } });
    const top = (label, st, name) => mk(name, label, '', `right:calc(var(--safe-r) + ${st}px);top:calc(var(--safe-t) + 8px);width:44px;height:44px;font-size:20px`, false, (d) => d && inp.press(name));
    top('☰', 8, 'menu'); top('🎒', 58, 'inventory'); top('👁', 108, 'camera'); top('🔦', 158, 'flashlight');
    top('✋', 208, 'holster');
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
    this.buttons(b, [tp('Spawn / Polígono', g.world.spawn.x, g.world.spawn.z), ...g.world.towns.map((t) => tp(t.name, t.x, t.z + 30)), tp('Base Militar', 1280, 1790), tp('Lago', 640, 1560), tp('Montanha', 1750, 300), tp('Polígono 300 m', g.world.spawn.x + 340, g.world.spawn.z)]);
    b.append($('<h4>Física</h4>'));
    this.buttons(b, [['Derrubar pilha de caixas', () => { for (const dp of g.level.dynProps) if (!dp.body.dead) g.phys.applyImpulse(dp.body, [Math.random() * 40 - 20, 30, Math.random() * 40 - 20], dp.body.pos); }], ['Explosão à frente', () => { const d = g.player.aimDir(); const p = [g.player.eye[0] + d[0] * 12, g.world.heightAt(g.player.eye[0] + d[0] * 12, g.player.eye[2] + d[2] * 12) + 0.3, g.player.eye[2] + d[2] * 12]; g.weapons.explodeAt(p); }]]);
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
    b.append($(`<div class="help"><b>PC:</b> <kbd>W A S D</kbd> mover · mouse olhar · <kbd>Shift</kbd> correr · <kbd>C</kbd> agachar · <kbd>Z</kbd> deitar · <kbd>Espaço</kbd> pular · <kbd>Q</kbd>/<kbd>E</kbd> inclinar · botão esq. atirar · botão dir. mirar (<kbd>Shift</kbd> segura a respiração) · <kbd>R</kbd> recarregar · <kbd>F</kbd> interagir/pegar · <kbd>Tab</kbd>/<kbd>I</kbd> inventário · <kbd>1</kbd>–<kbd>8</kbd> atalhos · <kbd>V</kbd> 1ª/3ª pessoa · <kbd>L</kbd> lanterna · <kbd>G</kbd> largar · <kbd>H</kbd> guardar · <kbd>N</kbd> voar · <kbd>F3</kbd> depuração · <kbd>Esc</kbd> menu.<br><br>
<b>Celular:</b> arraste à esquerda para mover (empurre até o fim para correr), arraste à direita para olhar, 🔥 atira, 🎯 mira, ⤒ pula, ⟳ recarrega, » alterna corrida, ⤓ agacha, ▭ deita, 🎒 inventário, 👁 câmera, 🔦 lanterna.<br><br>
<b>Mecânicas para testar:</b> física de caixas e barris no polígono, balística com queda e vento (alvos a 25–300 m), penetração em madeira, granadas, carros com suspensão real, fome/sede/temperatura/sangramento, ciclo dia/noite, clima, loot nas casas, inventário em grade, quedas e dano.<br><br>
<b>Créditos:</b> modelos e texturas CC0 do Poly Haven; personagem Soldier (three.js/Mixamo). Veja CREDITS.md.</div>`));
  }
}
function WDEF(k) { return true; }
