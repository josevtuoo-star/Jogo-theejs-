// Jogador: movimento, câmera 1ª/3ª pessoa, sobrevivência, interação e uso de itens.
import { m4, q4, v3, clamp, lerp, smoothstep, damp, angleDiff } from '../engine/math.js';
import { SURF } from '../engine/physics.js';
import { Inventory, makeItem, ITEMS, SLOT } from './items.js';
import { WORLD } from './worldgen.js';

const RUN = { walk: 1.7, jog: 3.7, sprint: 6.0 };

export class Player {
  constructor(game) {
    this.g = game;
    this.body = { pos: [0, 0, 0], vel: [0, 0, 0], radius: 0.32, height: 1.8, grounded: false, jumpSpeed: 4.6 };
    this.pos = this.body.pos; this.vel = this.body.vel;
    this.yaw = 0; this.pitch = 0; this.recoilPitch = 0; this.recoilYaw = 0;
    this.stance = 0; this.eyeH = 1.65; this.lean = 0;
    this.sprinting = false; this.sprintLatch = false;
    this.camMode = 'fp'; this.camDist = 3.0; this.camFov = 72 * Math.PI / 180;
    this.eye = [0, 0, 0]; this.camPos = [0, 0, 0]; this.camYaw = 0; this.camPitch = 0;
    this.aimYaw = 0; this.aimPitch = 0; this.aimTarget = [0, 0, 0];
    this.noclip = false; this.god = false; this.speedMul = 1;
    this.dead = false; this.inVehicle = null;
    this.action = null;           // {t, dur, label, fn}
    this.flashlight = false;
    this.limp = false;
    this.stepAcc = 0; this.landFlag = 0;
    this.interactTarget = null;
    this.walkMode = false;
    this.statsRate = 6;
    this.hurt = 0; this.bobT = 0;
    this.reset();
  }
  get grounded() { return this.body.grounded; }
  get swimming() { return this.body.swimming; }

  reset() {
    const g = this.g, W = g.world;
    this.dead = false;
    const sp = W.spawn;
    this.pos[0] = sp.x; this.pos[2] = sp.z; this.pos[1] = W.heightAt(sp.x, sp.z) + 0.05;
    this.vel[0] = this.vel[1] = this.vel[2] = 0;
    this.yaw = 1.6; this.pitch = 0;
    this.health = 100; this.blood = 5000; this.food = 3600; this.water = 3200; this.temp = 36.6; this.stamina = 100; this.wet = 0;
    this.bleeding = 0; this.limp = false; this.stance = 0;
    this.inVehicle = null;
    this.inv = g.inv = new Inventory();
    const add = (id, q) => { const it = makeItem(id, q); const ok = id === 'hoodie' || id === 'pants' || id === 'boots' || id === 'backpack' ? this.inv.equip(it) : this.inv.add(it); return it; };
    add('hoodie'); add('pants'); add('boots'); add('backpack');
    for (const [id, q] of [['bandage', 2], ['water'], ['fish_can'], ['ration'], ['flashlight'], ['ammo_45', 14], ['ammo_762', 20]]) { const it = makeItem(id, q); this.inv.add(it); }
    const pistol = makeItem('m1911'); this.inv.equip(pistol, 'secondary');
    const rifle = makeItem('mosin'); this.inv.equip(rifle, 'primary');
    this.inv.quick[0] = rifle; this.inv.quick[1] = pistol;
    this.hands = null;
    this.g.weapons && this.g.weapons.equip(null);
    this.inv.onChange = () => { g.onInventoryChange && g.onInventoryChange(); };
    g.onInventoryChange && g.onInventoryChange();
  }

  // ---------------------------------------------------------------- equipamento
  wield(item) {
    const g = this.g;
    if (this.hands === item) return;
    this.holster(true);
    if (!item) return;
    // remove de onde estiver
    if (item.container) item.container.remove(item);
    if (item.slot && this.inv.slots[item.slot] === item) { this.inv.slots[item.slot] = null; }
    item._slot = item.def.slot || null;
    this.inv.slots.hands = item; item.slot = 'hands';
    this.hands = item;
    if (ITEMS[item.id].weapon) g.weapons.equip(item); else g.weapons.equip(null);
    g.onInventoryChange && g.onInventoryChange();
  }
  holster(silent) {
    const g = this.g, it = this.hands;
    if (!it) return;
    this.inv.slots.hands = null; it.slot = null;
    const pref = it.def.slot;
    if (pref && !this.inv.slots[pref] && it.def.kind === 'weapon') { this.inv.slots[pref] = it; it.slot = pref; }
    else if (!this.inv.add(it)) { g.level.dropLootAt(it.id, it.qty, this.pos[0] + 0.5, this.pos[2], this.pos[1] + 0.5, { item: it }); }
    this.hands = null; g.weapons.equip(null);
    if (!silent) g.onInventoryChange && g.onInventoryChange();
  }
  useQuick(i) {
    const it = this.inv.quick[i];
    if (!it) return;
    if (this.hands === it) { this.holster(); return; }
    const k = it.def.kind;
    if (k === 'food' || k === 'drink' || k === 'med') this.useItem(it); else this.wield(it);
  }
  cycleWeapon(dir) {
    const list = this.inv.quick.filter((q) => q && (q.def.kind === 'weapon' || q.def.kind === 'tool' || q.def.kind === 'throw'));
    if (!list.length) return;
    let i = list.indexOf(this.hands); i = (i + dir + list.length + (i < 0 ? (dir > 0 ? 0 : 1) : 0)) % list.length;
    this.wield(list[i]);
  }
  startAction(label, dur, fn, sound) {
    if (this.action) return false;
    this.action = { t: 0, dur, label, fn };
    if (sound) this.g.audio[sound] && this.g.audio[sound]();
    return true;
  }
  useItem(it) {
    const g = this.g, d = it.def;
    if (this.action || this.dead) return;
    if (d.kind === 'food') this.startAction('Comendo ' + d.name, 2.4, () => { this.food = Math.min(5000, this.food + d.food.kcal); this.water = clamp(this.water + (d.food.water || 0), 0, 5000); this.inv.consume(it.id, 1); g.ui.toast('+' + d.food.kcal + ' kcal'); }, 'eat');
    else if (d.kind === 'drink') {
      if (it.qty <= 0) { g.ui.toast('Vazio'); return; }
      this.startAction('Bebendo', 1.6, () => { this.water = Math.min(5000, this.water + d.drink.water * 0.5); it.qty--; g.ui.toast('+250 ml'); g.onInventoryChange && g.onInventoryChange(); }, 'drink');
    } else if (d.kind === 'med') this.startAction('Usando ' + d.name, d.id === 'medkit' ? 5 : 3, () => { if (d.med.stopBleed) this.bleeding = 0; this.health = Math.min(100, this.health + d.med.health); if (d.med.blood) this.blood = Math.min(5000, this.blood + d.med.blood); if (d.id === 'medkit') this.limp = false; this.inv.consume(it.id, 1); g.ui.toast('Ferimentos tratados'); }, 'bandage');
    else if (d.kind === 'cloth') { if (!this.inv.slots[d.slot]) { this.inv.equip(it, d.slot); g.audio.ui('ok'); } }
    else if (d.kind === 'weapon' || d.kind === 'tool' || d.kind === 'throw') this.wield(it);
  }
  drop(item) {
    const g = this.g;
    if (!item) return;
    if (this.hands === item) { this.inv.slots.hands = null; item.slot = null; this.hands = null; g.weapons.equip(null); }
    else this.inv.remove(item);
    // equipamento vestido: derruba também seu conteúdo (permanece dentro)
    const dir = this.aimDir();
    const o = [this.pos[0] + dir[0] * 0.8, this.pos[1] + 1.3, this.pos[2] + dir[2] * 0.8];
    g.level.spawnItemBody(item, o, [dir[0] * 2.2 + this.vel[0], 1.2, dir[2] * 2.2 + this.vel[2]]);
    g.onInventoryChange && g.onInventoryChange();
  }
  pickup(e) {
    const g = this.g, it = e.item;
    if (it.def.kind === 'weapon' && !this.inv.slots[it.def.slot] && this.inv.slots[it.def.slot] !== undefined && it.def.slot) { /* vai direto ao slot */ }
    let ok = false;
    if (it.def.kind === 'cloth' && !this.inv.slots[it.def.slot]) ok = this.inv.equip(it, it.def.slot);
    else if (it.def.kind === 'weapon' && it.def.slot && !this.inv.slots[it.def.slot]) ok = this.inv.equip(it, it.def.slot);
    else ok = this.inv.add(it);
    if (!ok) { g.ui.toast('Sem espaço no inventário (vista roupas/mochila)'); return false; }
    g.level.removeLoot(e);
    g.audio.ui('ok');
    // atalhos automáticos
    if (['weapon', 'tool', 'throw'].includes(it.def.kind) && !this.inv.quick.includes(it)) { const i = this.inv.quick.indexOf(null); if (i >= 0) this.inv.quick[i] = it; }
    g.ui.toast('Pegou: ' + it.def.name + (it.def.stack > 1 ? ' x' + it.qty : ''));
    return true;
  }

  // ---------------------------------------------------------------- mira
  aimDir() {
    const cy = Math.cos(this.aimPitch), sy = Math.sin(this.aimYaw);
    return [-sy * cy, Math.sin(this.aimPitch), -Math.cos(this.aimYaw) * cy];
  }
  addRecoil(p, y) { this.recoilPitch += p; this.recoilYaw += y; this.pitch += p * 0.55; this.yaw += y; }

  damage(a, cause = '') {
    if (this.god || this.dead || a <= 0) return;
    this.health -= a; this.hurt = Math.min(1, this.hurt + a / 40);
    this.g.audio.hurt();
    if (a > 8 && cause !== 'fall') this.bleeding = Math.max(this.bleeding, a > 30 ? 2 : 1);
    if (this.health <= 0) this.die(cause);
  }
  die(cause) {
    if (this.dead) return;
    this.dead = true; this.health = 0;
    this.holster(true);
    this.g.ui.onDeath(cause);
  }

  // ---------------------------------------------------------------- atualização
  update(dt, inp) {
    const g = this.g, b = this.body;
    if (this.dead) { this.updateCamera(dt); return; }
    // olhar
    const [ly, lp] = inp.consumeLook();
    if (!g.ui.menuOpen && !g.ui.invOpen) {
      const z = g.weapons.adsT > 0.3 ? lerp(1, 0.55, g.weapons.adsT) : 1;
      this.yaw += ly * z; this.pitch = clamp(this.pitch + lp * z, -1.45, 1.45);
      g.weapons.lookDelta(ly, lp);
    }
    // recuo se recupera
    this.recoilPitch = damp(this.recoilPitch, 0, 6, dt); this.recoilYaw = damp(this.recoilYaw, 0, 6, dt);
    this.pitch -= 0; // o recuo sobe a mira; a recuperação desce lentamente
    if (this.recoilPitch > 0.0005) this.pitch -= this.recoilPitch * dt * 2.2;

    if (this.inVehicle) { this.updateVehicle(dt, inp); this.updateCamera(dt); this.updateStats(dt, 0.2); return; }

    // estâncias
    if (inp.pressed('crouch') && !g.ui.menuOpen) { this.stance = this.stance === 1 ? 0 : 1; }
    if (inp.pressed('prone') && !g.ui.menuOpen) { this.stance = this.stance === 2 ? 0 : 2; }
    if (inp.pressed('camera')) { this.camMode = this.camMode === 'fp' ? 'tp' : 'fp'; g.ui.toast(this.camMode === 'fp' ? 'Primeira pessoa' : 'Terceira pessoa'); }
    if (inp.pressed('flashlight')) this.toggleFlashlight();
    if (inp.pressed('leanL')) this.leanTarget = this.leanTarget === -1 ? 0 : -1;
    if (inp.pressed('leanR')) this.leanTarget = this.leanTarget === 1 ? 0 : 1;
    this.leanTarget = this.leanTarget || 0;
    this.lean = damp(this.lean, this.leanTarget, 8, dt);
    for (let i = 1; i <= 8; i++) if (inp.pressed('slot' + i)) this.useQuick(i - 1);
    if (inp.pressed('nextWeapon')) this.cycleWeapon(1);
    if (inp.pressed('prevWeapon')) this.cycleWeapon(-1);
    if (inp.pressed('holster')) this.holster();
    if (inp.pressed('drop') && this.hands) this.drop(this.hands);
    if (inp.pressed('reload')) g.weapons.startReload();
    if (inp.pressed('firemode')) { /* sem rajada nas armas atuais */ }
    // ADS
    const W = g.weapons;
    if (inp.touchMode) { if (inp.pressed('aim')) W.aiming = !W.aiming; }
    else W.aiming = inp.isHeld('aim');
    if (this.hands && this.hands.def.tool === 'binoculars') this.zoomBino = W.aiming; else this.zoomBino = false;
    if (this.hands && this.hands.id === 'grenade' && inp.pressed('fire') && !g.ui.menuOpen) W.throwGrenade();
    // movimento
    const spd = this.handleMovement(dt, inp);
    this.updateCamera(dt);
    this.updateInteraction(dt, inp);
    this.updateAction(dt);
    this.updateStats(dt, spd);
    // lanterna
    this.updateFlashlight();
  }

  handleMovement(dt, inp) {
    const g = this.g, b = this.body, W = g.weapons;
    if (g.ui.invOpen && false) return 0;
    const inputOn = !g.ui.menuOpen;
    let mx = inputOn ? inp.moveX : 0, my = inputOn ? inp.moveY : 0;
    const mag = Math.hypot(mx, my);
    const sy = Math.sin(this.yaw), cy = Math.cos(this.yaw);
    // direção de mundo
    let wx = (-sy * -my + cy * mx), wz = (-cy * -my + -sy * mx);
    const wantSprint = inputOn && (inp.isHeld('sprint') || this.sprintLatch) && my < 0.1 && mag > 0.3;
    this.sprinting = wantSprint && this.stance === 0 && this.stamina > 6 && !b.swimming && !W.aiming && !this.limp && this.grounded;
    if (!wantSprint) this.sprintLatch = false;
    if (this.sprinting && my > -0.2 && Math.abs(mx) > 0.8) this.sprinting = false;
    // velocidade alvo
    let base = this.walkMode || mag < 0.55 ? RUN.walk : RUN.jog;
    if (this.sprinting) base = RUN.sprint;
    if (this.stance === 1) base *= 0.58; else if (this.stance === 2) base *= 0.28;
    if (W.adsT > 0.5) base *= 0.6;
    if (b.swimming) base = 1.8;
    if (this.limp) base *= 0.55;
    const wgt = clamp((this.inv.weight() - 18) / 30, 0, 0.35); base *= 1 - wgt;
    if (this.stamina < 15) base *= 0.75;
    base *= this.speedMul;
    const mmag = Math.min(1, mag);
    const sp = base * (mag > 0.05 ? mmag > 0.55 ? 1 : mmag / 0.55 : 0);
    const l = Math.hypot(wx, wz) || 1;
    let tx = wx / l * sp, tz = wz / l * sp;
    if (mag < 0.05) { tx = 0; tz = 0; }
    // estâncias alteram altura da cápsula
    b.height = this.stance === 0 ? 1.8 : this.stance === 1 ? 1.3 : 0.55;
    // impede levantar se há teto
    this.eyeH = damp(this.eyeH, this.stance === 0 ? 1.65 : this.stance === 1 ? 1.2 : 0.42, 10, dt);
    const jump = inputOn && inp.pressed('jump') && this.stamina > 12 && !this.limp;
    if (jump && this.stance !== 0) { this.stance = 0; }
    else if (jump) { this.stamina -= 10; g.audio.jump(this.pos); }
    const wasGround = b.grounded, vyBefore = b.vel[1];
    if (this.noclip) {
      const f = this.aimDir(); const s2 = this.speedMul * (inp.isHeld('sprint') ? 40 : 14);
      const upd = (inp.isHeld('jump') ? 1 : 0) - (inp.isHeld('crouch') ? 1 : 0);
      b.pos[0] += (wx / l * mmag * s2) * dt * (mag > 0.05 ? 1 : 0) + f[0] * -my * s2 * dt * 0; b.pos[2] += (wz / l * mmag * s2) * dt * (mag > 0.05 ? 1 : 0);
      b.pos[1] += (f[1] * -my * s2 + upd * s2 * 0.5) * dt;
      b.vel[1] = 0; b.grounded = false;
    } else {
      g.phys.moveCharacter(b, dt, tx, tz, jump);
    }
    // aterrissagem / dano de queda
    if (b.grounded && !wasGround && vyBefore < -3) {
      const sp = -vyBefore;
      g.audio.land(sp, g.phys.surfaceAt(this.pos[0], this.pos[2]));
      if (sp > 7.5 && !this.noclip) { const dmg = (sp - 7.5) * 10; this.damage(dmg, 'fall'); if (sp > 13) { this.limp = true; g.ui.toast('Perna quebrada! Use um kit médico.'); } }
      this.landBump = Math.min(0.12, sp * 0.012);
    }
    this.landBump = damp(this.landBump || 0, 0, 10, dt);
    // stamina
    const moving = Math.hypot(b.vel[0], b.vel[2]);
    if (this.sprinting) this.stamina = Math.max(0, this.stamina - dt * 14);
    else if (b.swimming) this.stamina = Math.max(0, this.stamina - dt * 4);
    else this.stamina = Math.min(100, this.stamina + dt * (moving < 0.5 ? 18 : 9) * (this.food > 600 ? 1 : 0.4));
    // passos
    if (b.grounded && moving > 0.6 && !this.noclip) {
      const stride = this.sprinting ? 2.0 : this.stance === 1 ? 1.1 : 1.45;
      this.stepAcc += moving * dt;
      if (this.stepAcc > stride) {
        this.stepAcc = 0;
        const surf = b.wading ? SURF.WATER : g.phys.surfaceAt(this.pos[0], this.pos[2]);
        g.audio.step(surf, this.stance === 1 ? 0.5 : this.sprinting ? 1.4 : 1, null);
        if (surf === SURF.WATER) g.particles.splash(this.pos[0], g.phys.waterY, this.pos[2], 3);
      }
    }
    this.bobT += dt * moving * 1.9;
    this.lastSpeed = moving;
    return moving;
  }

  updateCamera(dt) {
    const g = this.g, W = g.weapons;
    const p = this.pos, lean = this.lean;
    const right = [Math.cos(this.yaw), 0, -Math.sin(this.yaw)];
    let ex = p[0] + right[0] * lean * 0.38, ey = p[1] + this.eyeH + (this.landBump ? -this.landBump : 0) + Math.sin(this.bobT) * 0.012 * Math.min(1, (this.lastSpeed || 0) / 3) * (1 - W.adsT), ez = p[2] + right[2] * lean * 0.38;
    if (this.stance === 2) { const f = [-Math.sin(this.yaw), -Math.cos(this.yaw)]; ex += f[0] * 0.75; ez += f[1] * 0.75; ey = p[1] + 0.5 + 0.0; }
    this.headPos = [ex, ey, ez];
    let yaw = this.yaw, pitch = this.pitch;
    // balanço da câmera (explosões)
    if (g.shake > 0.001) { yaw += (Math.random() - 0.5) * g.shake * 0.04; pitch += (Math.random() - 0.5) * g.shake * 0.04; g.shake = damp(g.shake, 0, 6, dt); }
    const roll = -lean * 0.14;
    if (this.camMode === 'fp' || this.inVehicle && this.inVehicle.fpCam) {
      this.camPos = [ex, ey, ez]; this.camYaw = yaw; this.camPitch = pitch; this.camRoll = roll;
      this.eye = [ex, ey, ez];
      this.aimYaw = yaw; this.aimPitch = pitch;
      // FP: a câmera fica ligeiramente à frente da cabeça (cabeça oculta)
      const f = [-Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), -Math.cos(yaw) * Math.cos(pitch)];
      this.camPos = [ex + f[0] * 0.1, ey + f[1] * 0.1 - 0.02, ez + f[2] * 0.1];
    } else {
      // terceira pessoa: câmera de ombro
      const ads = W.adsT;
      const dist = lerp(this.camDist, 1.5, ads), shoulder = lerp(0.55, 0.38, ads);
      const piv = [ex + right[0] * shoulder, ey + 0.15, ez + right[2] * shoulder];
      const f = [-Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), -Math.cos(yaw) * Math.cos(pitch)];
      let d = dist;
      const back = [-f[0], -f[1], -f[2]];
      const h = g.phys.raycast(piv, back, dist + 0.3, { noBodies: true });
      if (h) d = Math.max(0.35, h.t - 0.25);
      this.camPos = [piv[0] + back[0] * d, Math.max(piv[1] + back[1] * d, g.world.heightAt(piv[0] + back[0] * d, piv[2] + back[2] * d) + 0.25), piv[2] + back[2] * d];
      this.camYaw = yaw; this.camPitch = pitch; this.camRoll = roll * 0.5;
      this.eye = [ex, ey, ez];
      // ponto mirado pela câmera -> direção do cano
      const hit = g.phys.raycast(this.camPos, f, 600, { noBodies: false });
      const T = hit ? hit.point : [this.camPos[0] + f[0] * 300, this.camPos[1] + f[1] * 300, this.camPos[2] + f[2] * 300];
      this.aimTarget = T;
      const dx = T[0] - ex, dy = T[1] - ey, dz = T[2] - ez, L = Math.hypot(dx, dy, dz) || 1;
      this.aimYaw = Math.atan2(-dx, -dz); this.aimPitch = Math.asin(clamp(dy / L, -1, 1));
      if (L < 1.5) { this.aimYaw = yaw; this.aimPitch = pitch; }
    }
  }

  updateInteraction(dt, inp) {
    const g = this.g, L = g.level;
    this.interactTarget = null;
    if (g.ui.menuOpen || g.ui.invOpen) return;
    const dir = [-Math.sin(this.yaw) * Math.cos(this.pitch), Math.sin(this.pitch), -Math.cos(this.yaw) * Math.cos(this.pitch)];
    const o = this.eye;
    let best = null, bd = 1e9;
    for (const e of L.loot) {
      const ex = e.body ? e.body.pos[0] : e.x, ey = e.body ? e.body.pos[1] : e.y + 0.1, ez = e.body ? e.body.pos[2] : e.z;
      const dx = ex - o[0], dy = ey - o[1], dz = ez - o[2], d = Math.hypot(dx, dy, dz);
      if (d > 2.6) continue;
      const cosA = (dx * dir[0] + dy * dir[1] + dz * dir[2]) / (d || 1);
      const score = d * (2 - cosA);
      if (cosA < 0.72 && d > 1.0) continue;
      if (score < bd) { bd = score; best = { type: 'loot', e, d }; }
    }
    for (const v of g.vehicles) { const d = Math.hypot(v.pos[0] - this.pos[0], v.pos[2] - this.pos[2]); if (d < 3.4 && (!best || best.type !== 'loot')) best = { type: 'vehicle', v, d }; }
    this.interactTarget = best;
    if (inp.pressed('interact') && best) {
      if (best.type === 'loot') this.pickup(best.e);
      else if (best.type === 'vehicle') this.enterVehicle(best.v);
    }
  }
  updateAction(dt) {
    const a = this.action; if (!a) return;
    if (Math.hypot(this.vel[0], this.vel[2]) > 3.5 || this.sprinting) { this.action = null; return; }
    a.t += dt;
    if (a.t >= a.dur) { const fn = a.fn; this.action = null; fn && fn(); }
  }

  toggleFlashlight() {
    const g = this.g;
    if (!this.inv.all().some((i) => i.def.tool === 'flashlight')) { g.ui.toast('Você não tem lanterna'); return; }
    this.flashlight = !this.flashlight; g.audio.click(null, 0.4, 1500);
  }
  updateFlashlight() {
    const g = this.g, e = g.env;
    if (this.flashlight && this.inv.all().some((i) => i.def.tool === 'flashlight')) {
      const d = this.camMode === 'fp' ? this.camPos : this.eye;
      const f = [-Math.sin(this.camYaw) * Math.cos(this.camPitch), Math.sin(this.camPitch), -Math.cos(this.camYaw) * Math.cos(this.camPitch)];
      e.lights[0] = { pos: [d[0] + f[0] * 0.3, d[1] + f[1] * 0.3 - 0.05, d[2] + f[2] * 0.3], dir: f, radius: 38, color: [1, 0.96, 0.85], intensity: 10, spot: true, cosOuter: Math.cos(0.5), cosInner: Math.cos(0.18) };
    } else e.lights[0] = null;
  }

  // ---------------------------------------------------------------- veículos
  enterVehicle(v) {
    if (v.driver) return;
    v.driver = this; this.inVehicle = v; this.holster(true);
    this.g.ui.toast('W/S acelera, A/D direção, Espaço freio de mão, F sai');
    this.stance = 0;
  }
  exitVehicle() {
    const v = this.inVehicle; if (!v) return;
    v.driver = null; this.inVehicle = null;
    const c = Math.cos(v.yaw), s = Math.sin(v.yaw);
    const side = -1; // sai pela esquerda
    this.pos[0] = v.pos[0] + (c * 2.0 * side); this.pos[2] = v.pos[2] + (-s * 2.0 * side);
    this.pos[1] = this.g.world.heightAt(this.pos[0], this.pos[2]) + 0.1;
    this.vel[0] = v.vel[0] * 0.3; this.vel[2] = v.vel[2] * 0.3; this.vel[1] = 0;
  }
  updateVehicle(dt, inp) {
    const v = this.inVehicle, g = this.g;
    v.input.throttle = (inp.held.fwd ? 1 : 0) + (inp.joy.active ? Math.max(0, -inp.joy.y) : 0);
    v.input.brake = (inp.held.back ? 1 : 0) + (inp.joy.active ? Math.max(0, inp.joy.y) : 0);
    v.input.steer = (inp.held.right ? 1 : 0) - (inp.held.left ? 1 : 0) + (inp.joy.active ? inp.joy.x : 0);
    v.input.handbrake = inp.held.jump;
    this.pos[0] = v.pos[0]; this.pos[1] = v.pos[1]; this.pos[2] = v.pos[2];
    if (inp.pressed('interact')) this.exitVehicle();
    if (inp.pressed('flashlight')) v.lights = !v.lights;
  }

  // ---------------------------------------------------------------- sobrevivência
  updateStats(dt, speed) {
    const g = this.g, atm = g.atm, rate = this.statsRate, st = dt * rate;
    const act = clamp(speed / 5, 0, 1) + (this.sprinting ? 0.6 : 0);
    this.food = Math.max(0, this.food - (0.7 + act * 2.0) * st);
    const air = this.airTemp();
    this.water = Math.max(0, this.water - (1.1 + act * 2.4 + Math.max(0, air - 22) * 0.12) * st);
    // molhado
    const raining = atm.rainAmount > 0.2 && !this.sheltered;
    if (this.swimming) this.wet = Math.min(1, this.wet + dt * 0.5);
    else if (this.wading) this.wet = Math.min(0.5, this.wet + dt * 0.1);
    else if (raining) this.wet = Math.min(1, this.wet + dt * 0.012 * atm.rainAmount * 3);
    else this.wet = Math.max(0, this.wet - dt * 0.004 * (1 + Math.max(0, air - 10) * 0.05));
    // temperatura corporal
    const warmth = Object.values(this.inv.slots).reduce((a, i) => a + (i && i.def.warmth ? i.def.warmth : 0), 0);
    const target = 36.6 + clamp((air + warmth * 14 + act * 6 - this.wet * 10 - (atm.env.wind[2] * 3) - 16) * 0.12, -4.5, 2.4);
    this.temp += (target - this.temp) * Math.min(1, dt * 0.004 * rate);
    this.airT = air;
    // danos
    let dmg = 0;
    if (this.food <= 0) dmg += 0.25; if (this.water <= 0) dmg += 0.45;
    if (this.temp < 34.5) dmg += (34.5 - this.temp) * 0.4; if (this.temp > 39.5) dmg += (this.temp - 39.5) * 0.4;
    if (this.bleeding > 0) { this.blood -= this.bleeding * 12 * dt * Math.max(1, rate * 0.4); if (Math.random() < dt * 0.4) g.particles.dust(this.pos[0], this.pos[1] + 0.05, this.pos[2], 1, [0.5, 0.02, 0.02, 0.8], 0.1); }
    if (this.blood <= 0) dmg += 3;
    if (dmg > 0 && !this.god) { this.health -= dmg * dt * Math.max(1, rate * 0.3); if (this.health <= 0) this.die(this.food <= 0 ? 'fome' : this.water <= 0 ? 'sede' : this.blood <= 0 ? 'sangramento' : 'frio'); }
    // regeneração
    if (!dmg && this.food > 1800 && this.water > 2200 && this.blood > 3500 && this.temp > 35.5 && this.temp < 38) {
      this.health = Math.min(100, this.health + 0.05 * st);
      this.blood = Math.min(5000, this.blood + 1.2 * st * (this.bleeding ? 0 : 1));
    }
    // avisos
    const warn = (key, cond, msg) => { if (cond && !this['_w' + key]) { this['_w' + key] = 1; g.ui.toast(msg); } else if (!cond) this['_w' + key] = 0; };
    warn('food', this.food < 1000, 'Estou com fome.'); warn('water', this.water < 1000, 'Estou com sede.'); warn('cold', this.temp < 35.8, 'Estou com frio.'); warn('hot', this.temp > 38.2, 'Estou com calor.'); warn('bleed', this.bleeding > 0, 'Estou sangrando! Use uma bandagem.');
    this.hurt = damp(this.hurt, 0, 2.5, dt);
  }
  airTemp() {
    const h = this.g.atm.hour, atm = this.g.atm;
    const day = Math.sin((h - 9) / 24 * Math.PI * 2) * 0.5 + 0.5;
    return 5 + day * 15 - atm.cur.rain * 4 - atm.cur.fog * 2 - Math.max(0, this.pos[1] - 40) * 0.05;
  }
}
