// Carregamento de texturas (arrays) e modelos.
import { texArray, setLayer, finishArray, loadImage } from '../engine/gl.js';
import { loadGLB } from '../engine/gltf.js';

export const MAT = { plaster: 0, plasterY: 1, planks: 2, brick: 3, concrete: 4, roof: 5, iron: 6, bark: 7, floor: 8, darkwood: 9, metal: 10, roofGrey: 11, asphalt: 12 };
const MAT_FILES = ['m_plaster', 'm_plaster_y', 'm_planks', 'm_brick', 'm_concrete', 'm_roof', 'm_iron', 'm_bark', 'm_floor', 'm_darkwood', 'm_metal', 'm_roof_grey', 't_asphalt'];
const TERR_FILES = ['t_grass', 't_forest', 't_dirt', 't_rock', 't_sand', 't_gravel', 't_asphalt'];

export const MODEL_NAMES = [
  'wooden_axe', 'picke_dirty_01', 'life_jacket', 'cement_bag', 'compost_bag_02', 'trashbag', 'dry_branches_medium_01', 'stone_01', 'signal_flashlight',
  'russian_food_cans_01', 'long_life_food', 'medical_box', 'metal_jerrycan', 'plastic_bottle_gallon',
  'old_gas_mask', 'medical_tape', 'can_rusted', 'rubber_boots', 'fishermans_hat', 'binoculars',
  'wooden_crate_01', 'old_military_crate', 'barrel_03', 'metal_trash_can', 'cardboard_box_01', 'old_tyre', 'fire_hydrant', 'utility_box_01',
  'street_lamp_01', 'tree_stump_01', 'dead_tree_trunk', 'rock_07', 'rock_09', 'shrub_02', 'fern_02',
  'wooden_picnic_table', 'painted_wooden_bench', 'propane_tank',
  'vehicle_green', 'vehicle_red', 'vehicle_yellow', 'vehicle_purple',
];

export class Assets {
  constructor(gl, base = 'assets/') { this.gl = gl; this.base = base; this.models = {}; this.terrAlb = null; this.terrNor = null; this.matAlb = null; this.matNor = null; this.layerAvg = new Float32Array(21); }

  async loadTextures(progress = () => {}) {
    const gl = this.gl;
    const mk = async (files, size, nsize) => {
      const alb = texArray(gl, size, size, files.length, { srgb: true }), nor = texArray(gl, nsize, nsize, files.length, { srgb: false });
      const avgs = [];
      const jobs = files.map(async (f, i) => {
        const [d, n] = await Promise.all([loadImage(`${this.base}tex/${f}_d.jpg`), loadImage(`${this.base}tex/${f}_n.jpg`)]);
        setLayer(gl, alb, i, d); setLayer(gl, nor, i, n);
        // cor média (linear)
        const c = document.createElement('canvas'); c.width = c.height = 8;
        const g = c.getContext('2d'); g.drawImage(d, 0, 0, 8, 8);
        const px = g.getImageData(0, 0, 8, 8).data; let r = 0, gg = 0, b = 0;
        for (let k = 0; k < 64; k++) { r += px[k * 4]; gg += px[k * 4 + 1]; b += px[k * 4 + 2]; }
        const lin = (v) => Math.pow(v / 64 / 255, 2.2);
        avgs[i] = [lin(r), lin(gg), lin(b)];
        progress();
      });
      await Promise.all(jobs);
      finishArray(gl, alb); finishArray(gl, nor);
      return { alb, nor, avgs };
    };
    const t = await mk(TERR_FILES, 1024, 512);
    this.terrAlb = t.alb; this.terrNor = t.nor;
    t.avgs.forEach((a, i) => this.layerAvg.set(a, i * 3));
    const m = await mk(MAT_FILES, 512, 512);
    this.matAlb = m.alb; this.matNor = m.nor;
  }

  async loadModels(names, progress = () => {}, concurrency = 4) {
    const queue = names.slice();
    const worker = async () => {
      while (queue.length) {
        const n = queue.shift();
        try {
          const foliage = /shrub|fern|grass|nettle/.test(n);
          this.models[n] = await loadGLB(`${this.base}models/${n}.glb`, this.gl, { foliage });
        } catch (e) { console.warn('modelo falhou', n, e); }
        progress();
      }
    };
    await Promise.all(Array.from({ length: concurrency }, worker));
  }
  async loadCharacter(onPrimitive) {
    this.models.survivor = await loadGLB(`${this.base}char/survivor.glb`, this.gl, { onPrimitive });
    return this.models.survivor;
  }
}
