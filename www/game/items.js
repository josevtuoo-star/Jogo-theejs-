// Banco de itens e inventário em grade (estilo DayZ): slots de equipamento + contêineres das roupas.
export const SLOT = { HEAD: 'head', FACE: 'face', BODY: 'body', VEST: 'vest', LEGS: 'legs', FEET: 'feet', BACK: 'back', PRIMARY: 'primary', SECONDARY: 'secondary', MELEE: 'melee', HANDS: 'hands' };
export const SLOT_NAMES = { head: 'Cabeça', face: 'Rosto', body: 'Torso', vest: 'Colete', legs: 'Pernas', feet: 'Pés', back: 'Costas', primary: 'Arma principal', secondary: 'Pistola', melee: 'Corpo a corpo', hands: 'Mãos' };

// kind: weapon|ammo|food|drink|med|tool|cloth|misc|throw
export const ITEMS = {
  // ---- armas
  mosin: { name: 'Rifle de ferrolho 7,62', kind: 'weapon', slot: 'primary', w: 5, h: 2, weight: 4.0, model: 'bolt_action_rifle_7_62', icon: 'rifle', weapon: 'mosin', desc: 'Ferrolho, 5 tiros, 7,62x54R. Alta precisão e queda de projétil real.' },
  m1911: { name: 'Pistola .45', kind: 'weapon', slot: 'secondary', w: 2, h: 2, weight: 1.1, model: 'service_pistol', weapon: 'pistol', desc: 'Semiautomática, carregador de 7 tiros .45 ACP.' },
  hatchet: { name: 'Machadinha', kind: 'weapon', slot: 'melee', w: 2, h: 3, weight: 1.2, model: 'hatchet', weapon: 'hatchet', desc: 'Corta lenha e inimigos.' },
  machete: { name: 'Facão', kind: 'weapon', slot: 'melee', w: 1, h: 4, weight: 0.8, model: 'machete', weapon: 'machete', desc: 'Lâmina longa e rápida.' },
  crowbar: { name: 'Pé de cabra', kind: 'weapon', slot: 'melee', w: 1, h: 4, weight: 1.6, model: 'crowbar_01', weapon: 'crowbar', desc: 'Pesado e confiável.' },
  grenade: { name: 'Granada de mão', kind: 'throw', w: 1, h: 2, weight: 0.6, model: 'stick_grenade', desc: 'Detona 4 s após ser lançada. Empurra objetos físicos.' },
  // ---- munição (qty = projéteis)
  ammo_762: { name: 'Munição 7,62x54R', kind: 'ammo', ammo: '762', w: 1, h: 1, weight: 0.02, stack: 40, model: 'ammo_box', desc: 'Para o rifle de ferrolho.' },
  ammo_45: { name: 'Munição .45 ACP', kind: 'ammo', ammo: '45', w: 1, h: 1, weight: 0.015, stack: 50, model: 'ammo_box', tint: [0.85, 0.7, 0.4], desc: 'Para a pistola.' },
  // ---- comida e bebida
  fish_can: { name: 'Sardinha em lata', kind: 'food', w: 1, h: 1, weight: 0.3, model: 'russian_food_cans_01', node: 'russian_food_cans_01_can_fish', food: { kcal: 380, water: -10, health: 0 }, desc: 'Calorias seguras.' },
  milk_can: { name: 'Leite condensado', kind: 'food', w: 1, h: 1, weight: 0.4, model: 'russian_food_cans_01', node: 'russian_food_cans_01_can_cond', food: { kcal: 420, water: 40 }, desc: 'Doce e energético.' },
  ration: { name: 'Ração de longa duração', kind: 'food', w: 2, h: 1, weight: 0.5, model: 'long_life_food', food: { kcal: 600, water: 0 }, desc: 'Pacote de ração.' },
  water: { name: 'Garrafa de água (1 L)', kind: 'drink', w: 1, h: 2, weight: 1.0, model: 'plastic_bottle_gallon', drink: { water: 500 }, qtyMax: 4, desc: 'Cada gole mata a sede.' },
  can_empty: { name: 'Lata enferrujada', kind: 'misc', w: 1, h: 1, weight: 0.1, model: 'can_rusted', desc: 'Vazia.' },
  // ---- médicos
  bandage: { name: 'Bandagem', kind: 'med', w: 1, h: 1, weight: 0.1, stack: 5, model: 'medical_tape', med: { stopBleed: true, health: 8 }, desc: 'Estanca sangramento.' },
  medkit: { name: 'Kit de primeiros socorros', kind: 'med', w: 2, h: 2, weight: 1.2, model: 'medical_box', med: { health: 45, stopBleed: true, blood: 600 }, desc: 'Cura ferimentos e repõe sangue.' },
  // ---- ferramentas
  flashlight: { name: 'Lanterna', kind: 'tool', w: 1, h: 2, weight: 0.4, model: 'signal_flashlight', tool: 'flashlight', desc: 'Tecla L liga/desliga.' },
  binoculars: { name: 'Binóculos', kind: 'tool', w: 2, h: 2, weight: 0.6, model: 'binoculars', tool: 'binoculars', desc: 'Zoom 6x (mira).' },
  jerrycan: { name: 'Galão de combustível', kind: 'tool', w: 2, h: 3, weight: 4.5, model: 'metal_jerrycan', tool: 'fuel', desc: 'Abastece veículos.' },
  // ---- roupas (grid = capacidade)
  hoodie: { name: 'Moletom cinza', kind: 'cloth', slot: 'body', w: 3, h: 3, weight: 0.8, grid: [4, 3], tint: [0.45, 0.47, 0.5], icon: '🧥', warmth: 0.25, desc: 'Torso. 4x3 de espaço.' },
  jacket: { name: 'Jaqueta camuflada', kind: 'cloth', slot: 'body', w: 3, h: 3, weight: 1.1, grid: [5, 4], tint: [0.28, 0.33, 0.2], icon: '🧥', warmth: 0.4, desc: 'Torso. 5x4 de espaço.' },
  pants: { name: 'Calça cargo preta', kind: 'cloth', slot: 'legs', w: 2, h: 3, weight: 0.6, grid: [3, 3], tint: [0.12, 0.12, 0.13], icon: '👖', warmth: 0.15, desc: 'Pernas. 3x3 de espaço.' },
  jeans: { name: 'Jeans', kind: 'cloth', slot: 'legs', w: 2, h: 3, weight: 0.6, grid: [3, 2], tint: [0.18, 0.26, 0.42], icon: '👖', warmth: 0.15, desc: 'Pernas. 3x2.' },
  boots: { name: 'Botas de borracha', kind: 'cloth', slot: 'feet', w: 2, h: 2, weight: 0.9, tint: [0.12, 0.1, 0.07], model: 'rubber_boots', warmth: 0.1, desc: 'Pés.' },
  vest: { name: 'Colete tático', kind: 'cloth', slot: 'vest', w: 3, h: 2, weight: 1.4, grid: [4, 2], tint: [0.2, 0.22, 0.16], icon: '🦺', armor: 0.25, desc: 'Colete. 4x2 de espaço e proteção leve.' },
  backpack: { name: 'Mochila pequena', kind: 'cloth', slot: 'back', w: 3, h: 3, weight: 0.6, grid: [5, 5], tint: [0.7, 0.28, 0.1], icon: '🎒', pack: 'small', desc: 'Costas. 5x5 de espaço.' },
  backpack_big: { name: 'Mochila grande militar', kind: 'cloth', slot: 'back', w: 4, h: 4, weight: 1.2, grid: [7, 8], tint: [0.28, 0.32, 0.2], icon: '🎒', pack: 'big', desc: 'Costas. 7x8 de espaço.' },
  hat: { name: 'Chapéu de pescador', kind: 'cloth', slot: 'head', w: 2, h: 2, weight: 0.2, model: 'fishermans_hat', warmth: 0.05, desc: 'Cabeça.' },
  helmet: { name: 'Capacete', kind: 'cloth', slot: 'head', w: 2, h: 2, weight: 1.0, icon: '⛑️', tint: [0.2, 0.25, 0.3], armor: 0.35, desc: 'Cabeça. Reduz dano.' },
  gasmask: { name: 'Máscara de gás', kind: 'cloth', slot: 'face', w: 2, h: 2, weight: 0.5, model: 'old_gas_mask', desc: 'Rosto.' },
};
for (const [id, d] of Object.entries(ITEMS)) { d.id = id; d.stack = d.stack || 1; d.weight = d.weight ?? 0.1; }

export function makeItem(id, qty) {
  const d = ITEMS[id];
  if (!d) throw new Error('item desconhecido ' + id);
  const it = { id, def: d, qty: qty ?? (d.stack > 1 ? d.stack : 1), uid: ++makeItem.n, cond: 1 };
  if (d.kind === 'drink') it.qty = d.qtyMax || 1;
  if (d.weapon === 'mosin') { it.mag = 5; it.chamber = true; }
  if (d.weapon === 'pistol') { it.mag = 7; it.chamber = true; }
  if (d.grid) it.grid = new Grid(d.grid[0], d.grid[1]);
  return it;
}
makeItem.n = 0;

export class Grid {
  constructor(w, h) { this.w = w; this.h = h; this.cells = new Array(w * h).fill(null); this.items = []; }
  fits(item, x, y, ignore) {
    const { w, h } = item.def;
    if (x < 0 || y < 0 || x + w > this.w || y + h > this.h) return false;
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) { const c = this.cells[(y + j) * this.w + x + i]; if (c && c !== ignore) return false; }
    return true;
  }
  place(item, x, y) {
    const { w, h } = item.def;
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.cells[(y + j) * this.w + x + i] = item;
    item.gx = x; item.gy = y; item.container = this; this.items.push(item);
  }
  remove(item) {
    const { w, h } = item.def;
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) { const k = (item.gy + j) * this.w + item.gx + i; if (this.cells[k] === item) this.cells[k] = null; }
    const i = this.items.indexOf(item); if (i >= 0) this.items.splice(i, 1);
    item.container = null;
  }
  findSpace(item) {
    for (let y = 0; y <= this.h - item.def.h; y++) for (let x = 0; x <= this.w - item.def.w; x++) if (this.fits(item, x, y)) return [x, y];
    return null;
  }
}

export class Inventory {
  constructor() {
    this.slots = {}; for (const s of Object.values(SLOT)) this.slots[s] = null;
    this.pockets = new Grid(2, 2); this.pockets.owner = { def: { name: 'Bolsos' } };
    this.quick = new Array(8).fill(null); // atalhos 1..8 (referências a itens)
    this.onChange = null;
  }
  grids() {
    const out = [];
    for (const s of ['body', 'vest', 'legs', 'back']) { const it = this.slots[s]; if (it && it.grid) out.push({ owner: it, grid: it.grid, slot: s }); }
    if (!out.some((g) => g.slot === 'legs')) out.push({ owner: this.pockets.owner, grid: this.pockets, slot: 'pockets' });
    return out;
  }
  _changed() { this.onChange && this.onChange(); }
  // adiciona (empilha se possível). retorna true se coube
  add(item) {
    const d = item.def;
    if (d.stack > 1) {
      for (const g of this.grids()) for (const o of g.grid.items) if (o.id === item.id && o.qty < d.stack) {
        const mv = Math.min(d.stack - o.qty, item.qty); o.qty += mv; item.qty -= mv; if (item.qty <= 0) { this._changed(); return true; }
      }
    }
    for (const g of this.grids()) { const sp = g.grid.findSpace(item); if (sp) { g.grid.place(item, sp[0], sp[1]); this._changed(); return true; } }
    return false;
  }
  equip(item, slot) {
    slot = slot || item.def.slot;
    if (!slot || this.slots[slot]) return false;
    if (item.container) item.container.remove(item);
    this.slots[slot] = item; item.slot = slot; this._changed(); return true;
  }
  unequip(slot) { const it = this.slots[slot]; if (!it) return null; this.slots[slot] = null; it.slot = null; this._changed(); return it; }
  remove(item) {
    if (item.container) item.container.remove(item);
    if (item.slot && this.slots[item.slot] === item) this.slots[item.slot] = null;
    item.slot = null;
    this.quick = this.quick.map((q) => (q === item ? null : q));
    this._changed();
  }
  all() {
    const out = [];
    for (const s of Object.values(SLOT)) if (this.slots[s]) { out.push(this.slots[s]); if (this.slots[s].grid) out.push(...this.slots[s].grid.items); }
    out.push(...this.pockets.items);
    return out;
  }
  count(id) { return this.all().filter((i) => i.id === id).reduce((a, i) => a + (i.def.stack > 1 ? i.qty : 1), 0); }
  consume(id, n) {
    for (const it of this.all().filter((i) => i.id === id)) {
      if (n <= 0) break;
      if (it.def.stack > 1) { const t = Math.min(n, it.qty); it.qty -= t; n -= t; if (it.qty <= 0) this.remove(it); } else { this.remove(it); n--; }
    }
    this._changed(); return n <= 0;
  }
  weight() { return this.all().reduce((a, i) => a + i.def.weight * (i.def.stack > 1 ? i.qty : 1) + (i.def.kind === 'drink' ? i.qty * 0.5 : 0), 0); }
  moveTo(item, grid, x, y) {
    if (item.container === grid && grid.fits(item, x, y, item)) { grid.remove(item); grid.place(item, x, y); this._changed(); return true; }
    if (!grid.fits(item, x, y)) return false;
    if (item.container) item.container.remove(item);
    if (item.slot && this.slots[item.slot] === item) { this.slots[item.slot] = null; item.slot = null; }
    grid.place(item, x, y); this._changed(); return true;
  }
  // equipamentos que possuem arma
  weaponInSlot(s) { return this.slots[s]; }
}

// tabelas de loot por tipo de lugar [id, peso, qtdMin, qtdMax]
export const LOOT = {
  house: [['water', 8], ['fish_can', 9], ['milk_can', 6], ['ration', 4], ['bandage', 8, 1, 3], ['hoodie', 4], ['pants', 4], ['jeans', 4], ['boots', 3], ['flashlight', 4], ['backpack', 2], ['hat', 3], ['can_empty', 5], ['ammo_45', 3, 7, 21], ['m1911', 0.8], ['hatchet', 1.5], ['machete', 1], ['jerrycan', 1]],
  apartment: [['water', 8], ['fish_can', 8], ['bandage', 8, 1, 3], ['jeans', 5], ['hoodie', 5], ['ration', 4], ['flashlight', 5], ['ammo_45', 3, 7, 21], ['medkit', 1.2], ['can_empty', 4]],
  barn: [['hatchet', 4], ['crowbar', 3], ['machete', 2], ['jerrycan', 4], ['pants', 3], ['boots', 3], ['water', 4], ['ration', 3], ['backpack', 2], ['hat', 2]],
  shed: [['crowbar', 3], ['hatchet', 3], ['jerrycan', 4], ['can_empty', 4], ['flashlight', 4], ['boots', 3], ['bandage', 2]],
  shop: [['water', 10], ['fish_can', 10], ['milk_can', 8], ['ration', 8], ['bandage', 6, 1, 3], ['flashlight', 4], ['binoculars', 1.2], ['backpack', 3], ['medkit', 2], ['hoodie', 3], ['hat', 2]],
  church: [['bandage', 4], ['water', 4], ['can_empty', 2], ['medkit', 1]],
  warehouse: [['crowbar', 3], ['jerrycan', 4], ['ammo_762', 4, 10, 30], ['ammo_45', 3, 7, 21], ['backpack_big', 1.5], ['vest', 2], ['helmet', 1.5], ['jacket', 2], ['medkit', 2], ['binoculars', 1], ['grenade', 2], ['mosin', 1.2]],
  military: [['mosin', 5], ['m1911', 4], ['ammo_762', 8, 10, 30], ['ammo_45', 6, 7, 21], ['vest', 4], ['helmet', 4], ['jacket', 4], ['backpack_big', 3], ['grenade', 3], ['medkit', 3], ['gasmask', 2], ['binoculars', 2], ['ration', 4]],
  outside: [['can_empty', 6], ['water', 2], ['fish_can', 2], ['bandage', 1]],
};
export function rollLoot(table, rnd) {
  const total = table.reduce((a, r) => a + r[1], 0);
  let x = rnd() * total;
  for (const r of table) { x -= r[1]; if (x <= 0) { const qty = r[2] ? Math.round(r[2] + rnd() * (r[3] - r[2])) : undefined; return [r[0], qty]; } }
  return [table[0][0]];
}
