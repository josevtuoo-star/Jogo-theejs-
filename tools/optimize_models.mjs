// Simplifica (meshoptimizer) os modelos pesados do Poly Haven para o orçamento de triângulos do celular.
// Uso: node tools/optimize_models.mjs   (depois de tools/fetch_assets.py)
import { NodeIO } from '@gltf-transform/core';
import { weld, simplify } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'www', 'assets', 'models');
// proporção de triângulos mantidos por modelo (por malha)
const RATIO = {
  dead_tree_trunk: 0.016, boulder_01: 0.04, stone_01: 0.016, tree_stump_01: 0.025, rock_07: 0.07, rock_09: 0.07,
  street_lamp_01: 0.05, fire_hydrant: 0.07, cardboard_box_01: 0.06, metal_trash_can: 0.22, binoculars: 0.25,
  metal_jerrycan: 0.1, plastic_bottle_gallon: 0.15, old_gas_mask: 0.15, rubber_boots: 0.1, fishermans_hat: 0.2,
  wooden_picnic_table: 0.2, propane_tank: 0.3, utility_box_01: 0.4, old_military_crate: 0.5, shrub_02: 0.28, shrub_04: 0.12,
  nettle_plant: 0.2, signal_flashlight: 0.35, service_pistol: 0.6,
};
await MeshoptSimplifier.ready;
const io = new NodeIO();
for (const [name, ratio] of Object.entries(RATIO)) {
  const f = path.join(dir, name + '.glb');
  if (!fs.existsSync(f)) continue;
  const before = fs.statSync(f).size;
  const doc = await io.read(f);
  // idempotente: marca o arquivo como já otimizado para não simplificar duas vezes
  const root = doc.getRoot();
  if (root.getExtras().s2x2opt) { console.log(name.padEnd(26), 'já otimizado'); continue; }
  await doc.transform(weld({ tolerance: 0.0001 }), simplify({ simplifier: MeshoptSimplifier, ratio, error: 0.02, lockBorder: false }));
  doc.getRoot().setExtras({ ...doc.getRoot().getExtras(), s2x2opt: true });
  await io.write(f, doc);
  console.log(name.padEnd(26), 'ratio', ratio, (before / 1024) | 0, 'KB ->', (fs.statSync(f).size / 1024) | 0, 'KB');
}
