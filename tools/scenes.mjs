// Carrega o jogo uma vez e tira várias capturas. Uso: node tools/scenes.mjs cenas.json saida_prefixo [--w=960 --h=540 --q=test]
import { createRequire } from 'node:module';
import fs from 'node:fs';
const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }
const args = process.argv.slice(2);
const scenes = JSON.parse(fs.readFileSync(args[0], 'utf8')), prefix = args[1];
const opt = (k, d) => { const a = args.find((x) => x.startsWith('--' + k + '=')); return a ? a.split('=').slice(1).join('=') : d; };
const W = +opt('w', 960), H = +opt('h', 540), q = opt('q', 'test&manual'), port = opt('port', '8080');
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1, hasTouch: opt('touch', '0') === '1' });
const logs = [];
page.on('console', (m) => { const t = m.text(); if (m.type() !== 'log' || /error|warn/i.test(t)) logs.push(m.type() + ': ' + t.slice(0, 300)); });
page.on('pageerror', (e) => logs.push('PAGEERROR: ' + e.message + '\n' + (e.stack || '').split('\n').slice(0, 4).join('\n')));
await page.goto(`http://localhost:${port}/index.html?${q}`);
await page.waitForFunction('window.game && window.game.started', null, { timeout: 400000, polling: 500 });
for (const s of scenes) {
  try {
    const r = await page.evaluate(s.js);
    if (r !== undefined && r !== null) logs.push(`[${s.name}] -> ${JSON.stringify(r).slice(0, 400)}`);
  } catch (e) { logs.push(`[${s.name}] EVAL ERROR ${e.message}`); }
  if (s.name) await page.screenshot({ path: `${prefix}_${s.name}.png`, timeout: 170000 });
}
console.log(logs.slice(-40).join('\n'));
await browser.close();
