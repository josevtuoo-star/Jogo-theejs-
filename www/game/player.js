// Jogador: movimento, câmera 1ª/3ª pessoa, sobrevivência, interação por toque e ferramentas.
import { m4, v3, clamp, lerp, damp, angleDiff } from '../engine/math.js';
import { SURF } from '../engine/physics.js';
import { Inventory, makeItem, ITEMS } from './items.js';

const RUN = { walk: 1.7, jog: 3.7, sprint: 6.0 };

export class Player {
  constructor(game) {
    this.g = game;
    this.body = { pos: [0, 0, 0], vel: [0, 0, 0], radius: 0.32, height: 1.8, grounded: false, jumpSpeed: 4.6 };
    this.pos = this.body.pos; this.vel = this.body.vel;
    this.yaw = 0; this.pitch = 0;
    this.stance = 0; this.eyeH = 1.65;
    this.sprinting = false;
    this.camMode = 'fp'; this.camDist = 3.0;
    this.eye = [0, 0, 0]; this.camPos = [0, 0, 0]; this.camYaw = 0; this.camPitch = 0; this.camRoll = 0;
    this.aimYaw = 0; this.aimPitch = 0; this.headPos = [0, 0, 0];
    this.noclip = false; this.god = false; this.speedMul = 1;
    this.dead = false; this.inVehicle = null;
    this.action = null;
    this.flashlight = false; this.limp = false;
    this.stepAcc = 0; this.interactTarget = null; this.resourceTarget = null;
    this.walkMode = false; this.statsRate = 6; this.hurt = 0; this.bobT = 0; this.lastSpeed = 0;
    this.lookIdle = 0; this.zoomBino = false; this.landBump = 0;
    this.reset();
  }
  get grounded() { return this.body.grounded; }
  get swimming() { return this.body.swimming; }

  reset() {
    const g = this.g, W = g.world, sp = W.spawn;
    this.dead = false;
    this.pos[0] = sp.x; this.pos[2] = sp.z; this.pos[1] = W.heightAt(sp.x, sp.z) + 0.05;
    this.vel[0] = this.vel[1] = this.vel[2] = 0;
    this.yaw = 1.6; this.pitch = 0;
    this.health = 100; this.blood = 5000; this.food = 3600; this.water = 3200; this.temp = 36.6; this.stamina = 100; this.wet = 0;
    this.bleeding = 0; this.limp = false; this.stance = 0; this.inVehicle = null; this.camMode = 'fp';
    this.inv = g.inv = new Inventory();
    for (const id of ['hoodie', 'pants', 'boots', 'backpack']) this.inv.equip(makeItem(id));
    for (const [id, q] of [['bandage', 2], ['water'], ['fish_can'], ['ration'], ['flashlight']]) this.inv.add(makeItem(id, q));
    const axe = makeItem('axe'), pick = makeItem('pickaxe');
    this.inv.equip(axe, 'melee'); this.inv.add(pick);
    this.inv.quick[0] = axe; this.inv.quick[1] = pick;
    const fl = this.inv.all().find((i) => i.id === 'flashlight'); if (fl) this.inv.quick[2] = fl;
    this.hands = null; this.action = null;
    g.tools && g.tools.equip(null);
    this.inv.onChange = () => { g.onInventoryChange && g.onInventoryChange(); };
    g.onInventoryChange && g.onInventoryChange();
  }

  // ---------------------------------------------------------------- equipamento nas mãos
  wield(item) {
    const g = this.g;
    if (this.hands === item) return;
    this.holster(true);
    if (!item) return;
    if (item.container) item.container.remove(item);
    if (item.slot && this.inv.slots[item.slot] === item) this.inv.slots[item.slot] = null;
    this.inv.slots.hands = item; item.slot = 'hands';
    this.hands = item;
    g.tools.equip(item);
    if (!['axe', 'pickaxe'].includes(item.def.tool)) g.audio.play('click', { vol: 0.5 });
    g.onInventoryChange && g.onInventoryChange();
  }
  holster(silent) {
    const g = this.g, it = this.hands;
    if (!it) return;
    this.inv.slots.hands = null; it.slot = null;
    const pref = it.def.slot;
    if (pref && !this.inv.slots[pref]) { this.inv.slots[pref] = it; it.slot = pref; }
    else if (!this.inv.add(it)) g.level.spawnItemBody(it, [this.pos[0], this.pos[1] + 1.2, this.pos[2]], [0, 1, 0]);
    this.hands = null; this.zoomBino = false; g.tools.equip(null);
    if (!silent) g.onInventoryChange && g.onInventoryChange();
  }
  useQuick(i) {
    const it = this.inv.quick[i];
    if (!it) return;
    if (this.hands === it) { this.holster(); return; }
    const k = it.def.kind;
    if (k === 'food' || k === 'drink' || k === 'med') this.useItem(it); else if (k === 'tool') this.wield(it);
  }
  cycleWeapon(dir) {
    const list = this.inv.quick.filter((q) => q && q.def.kind === 'tool');
    if (!list.length) return;
    let i = list.indexOf(this.hands); i = (i + dir + list.length + (i < 0 ? (dir > 0 ? 0 : 1) : 0)) % list.length;
    this.wield(list[i]);
  }
  startAction(label, dur, fn, clip, snd) {
    if (this.action) return false;
    this.action = { t: 0, dur, label, fn, clip };
    if (snd) this.g.audio[snd] && this.g.audio[snd]();
    return true;
  }
  useItem(it) {
    const g = this.g, d = it.def;
    if (this.action || this.dead) return;
    if (d.kind === 'food') this.startAction('Comendo', 2.6, () => { this.food = Math.min(5000, this.food + d.food.kcal); this.water = clamp(this.water + (d.food.water || 0), 0, 5000); this.inv.consume(it.id, 1); g.ui.hint('+' + d.food.kcal + ' kcal'); }, 'Consume', 'eat');
    else if (d.kind === 'drink') {
      if (it.qty <= 0) { g.ui.hint('Vazio'); return; }
      this.startAction('Bebendo', 2.2, () => { this.water = Math.min(5000, this.water + d.drink.water * 0.5); it.qty--; g.ui.hint('+250 ml'); g.onInventoryChange && g.onInventoryChange(); }, 'Consume', 'drink');
    } else if (d.kind === 'med') this.startAction('Tratando ferimentos', d.id === 'medkit' ? 5 : 3, () => { if (d.med.stopBleed) this.bleeding = 0; this.health = Math.min(100, this.health + d.med.health); if (d.med.blood) this.blood = Math.min(5000, this.blood + d.med.blood); if (d.id === 'medkit') this.limp = false; this.inv.consume(it.id, 1); g.ui.hint('Ferimentos tratados'); }, 'Interact', 'bandage');
    else if (d.kind === 'cloth') { if (!this.inv.slots[d.slot]) { this.inv.equip(it, d.slot); g.audio.ui('ok'); } }
    else if (d.kind === 'tool') this.wield(it);
  }
  drop(item) {
    const g = this.g;
    if (!item) return;
    if (this.hands === item) { this.inv.slots.hands = null; item.slot = null; this.hands = null; g.tools.equip(null); }
    else this.inv.remove(item);
    const dir = this.aimDir();
    g.level.spawnItemBody(item, [this.pos[0] + dir[0] * 0.8, this.pos[1] + 1.3, this.pos[2] + dir[2] * 0.8], [dir[0] * 2.2 + this.vel[0], 1.2, dir[2] * 2.2 + this.vel[2]]);
    g.onInventoryChange && g.onInventoryChange();
  }
  pickup(e) {
    const g = this.g, it = e.item;
    let ok = false;
    if (it.def.kind === 'cloth' && !this.inv.slots[it.def.slot]) ok = this.inv.equip(it, it.def.slot);
    else ok = this.inv.add(it);
    if (!ok) { g.ui.hint('Sem espaço no inventário'); return false; }
    g.level.removeLoot(e);
    g.audio.pickup();
    this.startAction('', 0.9, null, 'PickUp_Table');
    if (it.def.kind === 'tool' && !this.inv.quick.includes(it)) { const i = this.inv.quick.indexOf(null); if (i >= 0) this.inv.quick[i] = it; }
    g.ui.hint(it.def.name + (it.def.stack > 1 ? ' ×' + it.qty : ''));
    return true;
  }

  // ---------------------------------------------------------------- mira / dano
  aimDir() {
    const cy = Math.cos(this.aimPitch), sy = Math.sin(this.aimYaw);
    return [-sy * cy, Math.sin(this.aimPitch), -Math.cos(this.aimYaw) * cy];
  }
  damage(a, cause = '') {
    if (this.god || this.dead || a <= 0) return;
    this.health -= a; this.hurt = Math.min(1, this.hurt + a / 40);
    this.g.audio.hurt();
    if (a > 12 && cause !== 'fall') this.bleeding = Math.max(this.bleeding, a > 30 ? 2 : 1);
    if (this.health <= 0) this.die(cause);
  }
  die(cause) {
    if (this.dead) return;
    this.dead = true; this.health = 0;
    this.holster(true); if (this.inVehicle) this.exitVehicle();
    this.camMode = 'tp';
    this.g.ui.onDeath(cause);
  }

  // árvore/rocha ao alcance: cone horizontal à frente (robusto em encostas, onde o terreno esconderia um raio)
  findResource(reach = 2.9) {
    const g = this.g, p = this.pos, fx = -Math.sin(this.yaw), fz = -Math.cos(this.yaw);
    let best = null, bs = 1e9;
    for (const c of g.phys.near(p[0], p[2], reach + 3, this._rl || (this._rl = []))) {
      if (c.dead || !(c.tree || c.rock)) continue;
      if ((c.rock && c.rock.gone) || (c.tree && c.tree.felled)) continue;
      const dx = c.cx - p[0], dz = c.cz - p[2], hd = Math.hypot(dx, dz) || 1e-3, dist = hd - c.r;
      if (dist > reach || c.y1 < p[1] - 0.3 || c.y0 > p[1] + 2.2) continue;
      const cosA = dist < 0.4 ? 1 : (dx * fx + dz * fz) / hd;
      if (cosA < 0.78) continue;
      const score = dist * (2 - cosA);
      if (score < bs) { bs = score; best = { kind: c.tree ? 'tree' : 'rock', col: c, dist, point: [c.cx - dx / hd * c.r, clamp(p[1] + 1.1, c.y0 + 0.15, Math.max(c.y0 + 0.2, c.y1 - 0.15)), c.cz - dz / hd * c.r] }; }
    }
    return best;
  }

  // ---------------------------------------------------------------- ação contextual (botão de ação / clique)
  doAction() {
    const g = this.g;
    if (this.dead || this.action || g.ui.menuOpen || g.ui.invOpen) return;
    if (this.inVehicle) { return; }
    const T = g.tools, tool = T.active, R = this.resourceTarget;
    if (tool && R) { T.startSwing(); return; }
    const it = this.interactTarget;
    if (it) { if (it.type === 'loot') this.pickup(it.e); else if (it.type === 'vehicle') this.enterVehicle(it.v); return; }
    if (!tool && R) { this.autoTool(R); return; }
    if (tool) { T.startSwing(); return; }
    const h = this.hands;
    if (h && h.def.tool === 'flashlight') this.toggleFlashlight();
    else if (h && h.def.tool === 'binoculars') this.zoomBino = !this.zoomBino;
  }
  // equipa a ferramenta certa para o recurso à frente (se o jogador tiver) e golpeia
  autoTool(R) {
    const g = this.g, need = R.kind === 'tree' ? 'axe' : 'pickaxe';
    const it = this.inv.all().find((i) => i.def.tool === need);
    if (!it) { g.ui.hint(need === 'axe' ? 'Você precisa de um machado' : 'Você precisa de uma picareta'); return; }
    this.wield(it);
    g.tools.startSwing();
  }
  faceTowards(p) {
    const e = this.eye, dx = p[0] - e[0], dy = p[1] - e[1], dz = p[2] - e[2], L = Math.hypot(dx, dy, dz) || 1;
    this.yaw = Math.atan2(-dx, -dz); this.pitch = clamp(Math.asin(dy / L), -1.2, 1.2);
  }
  // toque direto num objeto da tela: pega itens, entra em carros, golpeia árvores/rochas
  tapInteract(sx, sy) {
    const g = this.g, r = g.r;
    if (this.dead || this.inVehicle || g.ui.menuOpen || g.ui.invOpen) return false;
    const nx = sx / innerWidth * 2 - 1, ny = 1 - sy / innerHeight * 2;
    const unp = (z) => { const m = r.invVP, x = nx, y = ny, w = m[3] * x + m[7] * y + m[11] * z + m[15]; return [(m[0] * x + m[4] * y + m[8] * z + m[12]) / w, (m[1] * x + m[5] * y + m[9] * z + m[13]) / w, (m[2] * x + m[6] * y + m[10] * z + m[14]) / w]; };
    const a = unp(-1), b = unp(1), d = v3.normalize([0, 0, 0], [b[0] - a[0], b[1] - a[1], b[2] - a[2]]);
    const o = this.camPos;
    // itens no chão: esfera de seleção generosa para o dedo
    let best = null, bt = 1e9;
    const hit = (c, rad) => { const oc = [c[0] - o[0], c[1] - o[1], c[2] - o[2]], t = v3.dot(oc, d); if (t < 0 || t > 14) return null; const px = o[0] + d[0] * t - c[0], py = o[1] + d[1] * t - c[1], pz = o[2] + d[2] * t - c[2]; return Math.hypot(px, py, pz) < rad ? t : null; };
    for (const e of g.level.loot) {
      const c = e.body ? e.body.pos : [e.x, e.y + 0.15, e.z];
      const t = hit(c, 0.55 + (e.visual ? Math.max(...e.visual.size) * 0.3 : 0)); if (t === null) continue;
      if (Math.hypot(c[0] - this.pos[0], c[2] - this.pos[2]) > 3.6) { if (t < bt) { bt = t; best = { far: true }; } continue; }
      if (t < bt) { bt = t; best = { type: 'loot', e }; }
    }
    for (const v of g.vehicles) { const t = hit([v.pos[0], v.pos[1], v.pos[2]], 2.4); if (t !== null && t < bt) { bt = t; best = Math.hypot(v.pos[0] - this.pos[0], v.pos[2] - this.pos[2]) < 5 ? { type: 'vehicle', v } : { far: true }; } }
    // árvores/rochas: raio contra os cilindros (ignora o terreno, que em encostas esconderia o alvo)
    for (const c of g.phys.near(this.pos[0], this.pos[2], 9, [])) {
      if (c.dead || !(c.tree || c.rock) || (c.rock && c.rock.gone) || (c.tree && c.tree.felled)) continue;
      const hh = g.phys._rayCol(o, d, { ...c, r: c.r + 0.35 }, 30);
      if (!hh || hh.t >= bt) continue;
      const dist = Math.hypot(c.cx - this.pos[0], c.cz - this.pos[2]) - c.r;
      if (dist < 3.2) { best = { type: 'res', kind: c.tree ? 'tree' : 'rock', point: [hh.point[0], hh.point[1], hh.point[2]] }; bt = hh.t; } else { best = { far: true }; bt = hh.t; }
    }
    if (!best) return false;
    if (best.far) { g.ui.hint('Chegue mais perto'); return true; }
    if (best.type === 'loot') { this.pickup(best.e); return true; }
    if (best.type === 'vehicle') { this.enterVehicle(best.v); return true; }
    if (best.type === 'res') {
      const need = best.kind === 'tree' ? 'axe' : 'pickaxe';
      this.faceTowards(best.point);
      if (this.hands && this.hands.def.tool === need) g.tools.startSwing();
      else this.autoTool({ kind: best.kind });
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- atualização
  update(dt, inp) {
    const g = this.g;
    if (this.dead) { this.updateCamera(dt); return; }
    const [ly, lp] = inp.consumeLook();
    if (!g.ui.menuOpen && !g.ui.invOpen) {
      this.yaw += ly; this.pitch = clamp(this.pitch + lp, -1.45, 1.45);
      g.tools.lookDelta(ly, lp);
      if (Math.abs(ly) + Math.abs(lp) > 1e-4) this.lookIdle = 0;
    }
    this.lookIdle += dt;
    // toques na tela -> interação direta
    for (const t of inp.takeTaps()) this.tapInteract(t.x, t.y);

    if (this.inVehicle) { this.updateVehicle(dt, inp); this.updateCamera(dt); this.updateStats(dt, 0.2); return; }

    if (inp.pressed('crouch') && !g.ui.menuOpen) this.stance = this.stance === 1 ? 0 : 1;
    if (inp.pressed('camera')) { this.camMode = this.camMode === 'fp' ? 'tp' : 'fp'; g.ui.hint(this.camMode === 'fp' ? 'Primeira pessoa' : 'Terceira pessoa'); }
    if (inp.pressed('flashlight')) this.toggleFlashlight();
    for (let i = 1; i <= 8; i++) if (inp.pressed('slot' + i)) this.useQuick(i - 1);
    if (inp.pressed('nextWeapon')) this.cycleWeapon(1);
    if (inp.pressed('prevWeapon')) this.cycleWeapon(-1);
    if (inp.pressed('holster')) this.holster();
    if (inp.pressed('drop') && this.hands) this.drop(this.hands);
    if (inp.pressed('fire') || inp.pressed('action')) this.doAction();
    if (inp.isHeld('fire') && this.g.tools.active && !this.action && !g.ui.menuOpen) this.g.tools.startSwing();
    if (this.hands && this.hands.def.tool === 'binoculars' && !inp.touchMode) this.zoomBino = inp.isHeld('aim');
    const spd = this.handleMovement(dt, inp);
    this.updateCamera(dt);
    this.updateInteraction(dt, inp);
    this.updateAction(dt);
    this.updateStats(dt, spd);
    this.updateFlashlight();
  }

  handleMovement(dt, inp) {
    const g = this.g, b = this.body;
    const inputOn = !g.ui.menuOpen;
    const mx = inputOn ? inp.moveX : 0, my = inputOn ? inp.moveY : 0, mag = Math.hypot(mx, my);
    const sy = Math.sin(this.yaw), cy = Math.cos(this.yaw);
    const wx = (-sy * -my + cy * mx), wz = (-cy * -my + -sy * mx);
    // correr: Shift no PC; no celular, empurrar o analógico até a borda
    const wantSprint = inputOn && (inp.isHeld('sprint') || (inp.joy.active && mag > 0.93)) && my < -0.15;
    this.sprinting = wantSprint && this.stance === 0 && this.stamina > 6 && !b.swimming && !this.limp && this.grounded && !g.tools.swinging;
    let base = this.walkMode || mag < 0.55 ? RUN.walk : RUN.jog;
    if (this.sprinting) base = RUN.sprint;
    if (this.stance === 1) base *= 0.58;
    if (g.tools.swinging) base *= 0.45;
    if (b.swimming) base = 1.8;
    if (this.limp) base *= 0.55;
    base *= 1 - clamp((this.inv.weight() - 18) / 30, 0, 0.35);
    if (this.stamina < 15) base *= 0.75;
    base *= this.speedMul;
    const sp = base * (mag > 0.05 ? (Math.min(1, mag) > 0.55 ? 1 : Math.min(1, mag) / 0.55) : 0);
    const l = Math.hypot(wx, wz) || 1;
    const tx = mag < 0.05 ? 0 : wx / l * sp, tz = mag < 0.05 ? 0 : wz / l * sp;
    b.height = this.stance === 0 ? 1.8 : 1.3;
    this.eyeH = damp(this.eyeH, this.stance === 0 ? 1.65 : 1.2, 10, dt);
    const jump = inputOn && inp.pressed('jump') && this.stamina > 12 && !this.limp;
    if (jump && this.stance !== 0) this.stance = 0;
    else if (jump) { this.stamina -= 10; g.audio.jump(); }
    const wasGround = b.grounded, vyBefore = b.vel[1];
    if (this.noclip) {
      const f = this.aimDir(), s2 = this.speedMul * (inp.isHeld('sprint') ? 40 : 14), upd = (inp.isHeld('jump') ? 1 : 0) - (inp.isHeld('crouch') ? 1 : 0);
      if (mag > 0.05) { b.pos[0] += wx / l * Math.min(1, mag) * s2 * dt; b.pos[2] += wz / l * Math.min(1, mag) * s2 * dt; }
      b.pos[1] += (f[1] * -my * s2 + upd * s2 * 0.5) * dt; b.vel[1] = 0; b.grounded = false;
    } else g.phys.moveCharacter(b, dt, tx, tz, jump);
    if (b.grounded && !wasGround && vyBefore < -3) {
      const v = -vyBefore;
      g.audio.land(v, g.phys.surfaceAt(this.pos[0], this.pos[2]));
      if (v > 7.5 && !this.noclip) { this.damage((v - 7.5) * 10, 'fall'); if (v > 13) { this.limp = true; g.ui.hint('Perna quebrada! Use um kit médico'); } }
      this.landBump = Math.min(0.12, v * 0.012);
    }
    this.landBump = damp(this.landBump, 0, 10, dt);
    const moving = Math.hypot(b.vel[0], b.vel[2]);
    if (this.sprinting) this.stamina = Math.max(0, this.stamina - dt * 14);
    else if (b.swimming) this.stamina = Math.max(0, this.stamina - dt * 4);
    else this.stamina = Math.min(100, this.stamina + dt * (moving < 0.5 ? 18 : 9) * (this.food > 600 ? 1 : 0.4));
    // passos
    if (b.grounded && moving > 0.6 && !this.noclip) {
      this.stepAcc += moving * dt;
      if (this.stepAcc > (this.sprinting ? 2.1 : this.stance === 1 ? 1.2 : 1.5)) {
        this.stepAcc = 0;
        const surf = b.wading ? SURF.WATER : g.phys.surfaceAt(this.pos[0], this.pos[2]);
        g.audio.step(surf, this.sprinting ? 1.25 : 1, this.stance === 1);
        if (surf === SURF.WATER) g.particles.splash(this.pos[0], g.phys.waterY, this.pos[2], 3);
      }
    }
    this.bobT += dt * moving * 1.9;
    this.lastSpeed = moving;
    return moving;
  }

  updateCamera(dt) {
    const g = this.g, p = this.pos, v = this.inVehicle;
    let yaw = this.yaw, pitch = this.pitch;
    if (g.shake > 0.001) { yaw += (Math.random() - 0.5) * g.shake * 0.04; pitch += (Math.random() - 0.5) * g.shake * 0.04; g.shake = damp(g.shake, 0, 6, dt); }
    if (v) {
      // chase cam: acompanha a direção do carro quando o jogador não está olhando em volta
      if (this.lookIdle > 1.2) { this.yaw += angleDiff(this.yaw, v.yaw + Math.PI) * Math.min(1, dt * 2.5); this.pitch += (-0.12 - this.pitch) * Math.min(1, dt * 2); }
      yaw = this.yaw; pitch = this.pitch;
      const seat = v.seat();
      this.headPos = [seat[0], seat[1] + 0.78, seat[2]];
      {
        const f = [-Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), -Math.cos(yaw) * Math.cos(pitch)];
        const piv = [v.pos[0], v.pos[1] + 0.9, v.pos[2]];
        const h = g.phys.raycast(piv, [-f[0], -f[1], -f[2]], 8, { noBodies: true });
        const d = h ? Math.max(1.5, h.t - 0.3) : 7.5;
        this.camPos = [piv[0] - f[0] * d, Math.max(piv[1] - f[1] * d, g.world.heightAt(piv[0] - f[0] * d, piv[2] - f[2] * d) + 0.4), piv[2] - f[2] * d];
        this.eye = piv;
      }
      this.camYaw = yaw; this.camPitch = pitch; this.camRoll = 0; this.aimYaw = yaw; this.aimPitch = pitch;
      return;
    }
    const ex = p[0], ey = p[1] + this.eyeH - this.landBump + Math.sin(this.bobT) * 0.012 * Math.min(1, this.lastSpeed / 3), ez = p[2];
    this.headPos = [ex, ey, ez];
    this.camRoll = 0;
    if (this.camMode === 'fp') {
      const f = [-Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), -Math.cos(yaw) * Math.cos(pitch)];
      this.camPos = [ex + f[0] * 0.1, ey + f[1] * 0.1 - 0.02, ez + f[2] * 0.1];
      this.camYaw = yaw; this.camPitch = pitch; this.eye = [ex, ey, ez]; this.aimYaw = yaw; this.aimPitch = pitch;
    } else {
      const right = [Math.cos(yaw), 0, -Math.sin(yaw)];
      const dist = this.dead ? 3.8 : this.camDist, shoulder = this.dead ? 0 : 0.5;
      const piv = [ex + right[0] * shoulder, ey + 0.15, ez + right[2] * shoulder];
      const f = [-Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), -Math.cos(yaw) * Math.cos(pitch)];
      const back = [-f[0], -f[1], -f[2]];
      const h = g.phys.raycast(piv, back, dist + 0.3, { noBodies: true });
      const d = h ? Math.max(0.35, h.t - 0.25) : dist;
      this.camPos = [piv[0] + back[0] * d, Math.max(piv[1] + back[1] * d, g.world.heightAt(piv[0] + back[0] * d, piv[2] + back[2] * d) + 0.25), piv[2] + back[2] * d];
      this.camYaw = yaw; this.camPitch = pitch; this.eye = [ex, ey, ez];
      const hit = g.phys.raycast(this.camPos, f, 300, {});
      const T = hit ? hit.point : [this.camPos[0] + f[0] * 100, this.camPos[1] + f[1] * 100, this.camPos[2] + f[2] * 100];
      const dx = T[0] - ex, dy = T[1] - ey, dz = T[2] - ez, L = Math.hypot(dx, dy, dz) || 1;
      this.aimYaw = L < 1.5 ? yaw : Math.atan2(-dx, -dz); this.aimPitch = L < 1.5 ? pitch : Math.asin(clamp(dy / L, -1, 1));
    }
  }

  updateInteraction(dt, inp) {
    const g = this.g, L = g.level;
    this.interactTarget = null; this.resourceTarget = null;
    if (g.ui.menuOpen || g.ui.invOpen) return;
    const dir = [-Math.sin(this.yaw) * Math.cos(this.pitch), Math.sin(this.pitch), -Math.cos(this.yaw) * Math.cos(this.pitch)], o = this.eye;
    let best = null, bd = 1e9;
    for (const e of L.loot) {
      const ex = e.body ? e.body.pos[0] : e.x, ey = e.body ? e.body.pos[1] : e.y + 0.1, ez = e.body ? e.body.pos[2] : e.z;
      const dx = ex - o[0], dy = ey - o[1], dz = ez - o[2], d = Math.hypot(dx, dy, dz);
      if (d > 2.6) continue;
      const cosA = (dx * dir[0] + dy * dir[1] + dz * dir[2]) / (d || 1);
      if (cosA < 0.72 && d > 1.0) continue;
      const score = d * (2 - cosA); if (score < bd) { bd = score; best = { type: 'loot', e, d }; }
    }
    for (const v of g.vehicles) { const d = Math.hypot(v.pos[0] - this.pos[0], v.pos[2] - this.pos[2]); if (d < 3.6 && (!best || best.type !== 'loot')) best = { type: 'vehicle', v, d }; }
    this.interactTarget = best;
    // recurso à frente (árvore/rocha)
    if (((g.frameNo || 0) & 1) === 0) this._res = this.findResource(3.0);
    this.resourceTarget = this._res;
    if (inp.pressed('interact') && best) {
      if (best.type === 'loot') this.pickup(best.e); else if (best.type === 'vehicle') this.enterVehicle(best.v);
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
    if (!this.inv.all().some((i) => i.def.tool === 'flashlight')) { g.ui.hint('Você não tem lanterna'); return; }
    this.flashlight = !this.flashlight; g.audio.play('click', { vol: 0.5, rate: 1.4 });
  }
  updateFlashlight() {
    const e = this.g.env;
    if (this.flashlight && this.inv.all().some((i) => i.def.tool === 'flashlight')) {
      const d = this.camMode === 'fp' ? this.camPos : this.eye, f = [-Math.sin(this.camYaw) * Math.cos(this.camPitch), Math.sin(this.camPitch), -Math.cos(this.camYaw) * Math.cos(this.camPitch)];
      e.lights[0] = { pos: [d[0] + f[0] * 0.3, d[1] + f[1] * 0.3 - 0.05, d[2] + f[2] * 0.3], dir: f, radius: 38, color: [1, 0.96, 0.85], intensity: 10, spot: true, cosOuter: Math.cos(0.5), cosInner: Math.cos(0.18) };
    } else e.lights[0] = null;
  }

  // ---------------------------------------------------------------- veículos
  enterVehicle(v) {
    if (v.driver || this.dead) return;
    v.driver = this; this.inVehicle = v; this.holster(true); this.stance = 0; this.flashlight = false;
    this.lookIdle = 5;
    this.g.ui.hint('W/S acelera · A/D direção · Espaço freio de mão · F sai');
  }
  exitVehicle() {
    const v = this.inVehicle; if (!v) return;
    v.driver = null; this.inVehicle = null;
    const c = Math.cos(v.yaw), s = Math.sin(v.yaw);
    this.pos[0] = v.pos[0] - c * 2.2; this.pos[2] = v.pos[2] + s * 2.2;
    this.pos[1] = this.g.world.heightAt(this.pos[0], this.pos[2]) + 0.1;
    this.vel[0] = v.vel[0] * 0.3; this.vel[2] = v.vel[2] * 0.3; this.vel[1] = 0;
    v.input.throttle = v.input.brake = v.input.steer = 0;
  }
  updateVehicle(dt, inp) {
    const v = this.inVehicle;
    const jy = inp.joy.active ? inp.joy.y : 0, jx = inp.joy.active ? inp.joy.x : 0;
    v.input.throttle = (inp.held.fwd ? 1 : 0) + Math.max(0, -jy);
    v.input.brake = (inp.held.back ? 1 : 0) + Math.max(0, jy);
    v.input.steer = (inp.held.right ? 1 : 0) - (inp.held.left ? 1 : 0) + jx;
    v.input.handbrake = !!inp.held.jump;
    this.pos[0] = v.pos[0]; this.pos[1] = v.pos[1]; this.pos[2] = v.pos[2];
    if (inp.pressed('interact') || inp.pressed('action')) this.exitVehicle();
    if (inp.pressed('flashlight')) v.lights = !v.lights;
  }

  // ---------------------------------------------------------------- sobrevivência
  updateStats(dt, speed) {
    const g = this.g, atm = g.atm, rate = this.statsRate, st = dt * rate;
    const act = clamp(speed / 5, 0, 1) + (this.sprinting ? 0.6 : 0) + (g.tools.swinging ? 0.5 : 0);
    this.food = Math.max(0, this.food - (0.7 + act * 2.0) * st);
    const air = this.airTemp();
    this.water = Math.max(0, this.water - (1.1 + act * 2.4 + Math.max(0, air - 22) * 0.12) * st);
    if (this.swimming) this.wet = Math.min(1, this.wet + dt * 0.5);
    else if (this.body.wading) this.wet = Math.min(0.5, this.wet + dt * 0.1);
    else if (atm.rainAmount > 0.2) this.wet = Math.min(1, this.wet + dt * 0.012 * atm.rainAmount * 3);
    else this.wet = Math.max(0, this.wet - dt * 0.004 * (1 + Math.max(0, air - 10) * 0.05));
    const warmth = Object.values(this.inv.slots).reduce((a, i) => a + (i && i.def.warmth ? i.def.warmth : 0), 0);
    const target = 36.6 + clamp((air + warmth * 14 + act * 6 - this.wet * 10 - atm.env.wind[2] * 3 - 16) * 0.12, -4.5, 2.4);
    this.temp += (target - this.temp) * Math.min(1, dt * 0.004 * rate);
    this.airT = air;
    let dmg = 0;
    if (this.food <= 0) dmg += 0.25; if (this.water <= 0) dmg += 0.45;
    if (this.temp < 34.5) dmg += (34.5 - this.temp) * 0.4; if (this.temp > 39.5) dmg += (this.temp - 39.5) * 0.4;
    if (this.bleeding > 0) this.blood -= this.bleeding * 12 * dt * Math.max(1, rate * 0.4);
    if (this.blood <= 0) dmg += 3;
    if (dmg > 0 && !this.god) { this.health -= dmg * dt * Math.max(1, rate * 0.3); if (this.health <= 0) this.die(this.food <= 0 ? 'fome' : this.water <= 0 ? 'sede' : this.blood <= 0 ? 'sangramento' : 'frio'); }
    if (!dmg && this.food > 1800 && this.water > 2200 && this.blood > 3500 && this.temp > 35.5 && this.temp < 38) {
      this.health = Math.min(100, this.health + 0.05 * st);
      this.blood = Math.min(5000, this.blood + 1.2 * st * (this.bleeding ? 0 : 1));
    }
    const warn = (key, cond, msg) => { if (cond && !this['_w' + key]) { this['_w' + key] = 1; g.ui.hint(msg); } else if (!cond) this['_w' + key] = 0; };
    warn('food', this.food < 1000, 'Estou com fome'); warn('water', this.water < 1000, 'Estou com sede'); warn('cold', this.temp < 35.8, 'Estou com frio'); warn('hot', this.temp > 38.2, 'Estou com calor'); warn('bleed', this.bleeding > 0, 'Estou sangrando — use uma bandagem');
    this.hurt = damp(this.hurt, 0, 2.5, dt);
  }
  airTemp() {
    const atm = this.g.atm;
    const day = Math.sin((atm.hour - 9) / 24 * Math.PI * 2) * 0.5 + 0.5;
    return 5 + day * 15 - atm.cur.rain * 4 - atm.cur.fog * 2 - Math.max(0, this.pos[1] - 40) * 0.05;
  }
}
