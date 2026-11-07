// Gera o mundo (determinístico) e grava os dados prontos em www/assets/world/ (embarcados no APK).
// Uso: node tools/bake_world.mjs [semente]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { generateWorld, bakeWorld } from '../www/game/worldgen.js';
const out = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'www', 'assets', 'world');
fs.mkdirSync(out, { recursive: true });
const seed = +process.argv[2] || 1337;
const t0 = Date.now();
const W = await generateWorld(seed, (n, p) => { if (Math.round(p * 100) % 20 === 0) process.stdout.write(`\r${n} ${Math.round(p * 100)}%   `); });
const b = bakeWorld(W);
fs.writeFileSync(path.join(out, 'meta.json'), JSON.stringify(b.meta));
fs.writeFileSync(path.join(out, 'height.i16'), Buffer.from(b.height.buffer));
fs.writeFileSync(path.join(out, 'splat0.bin'), Buffer.from(b.splat0.buffer));
fs.writeFileSync(path.join(out, 'splat1.bin'), Buffer.from(b.splat1.buffer));
console.log(`\nMundo ${seed} gerado em ${((Date.now() - t0) / 1000).toFixed(1)} s -> ${out}`);
