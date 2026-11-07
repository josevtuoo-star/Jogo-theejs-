// Captura de tela com Chromium headless (WebGL por software).
// node tools/shot.mjs <url> <saida.png> [--wait=ms] [--w=1280] [--h=720] [--eval="js"] [--logs]
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }
const args = process.argv.slice(2);
const url = args[0], out = args[1];
const opt = (k, d) => { const a = args.find((x) => x.startsWith('--' + k + '=')); return a ? a.split('=').slice(1).join('=') : d; };
const wait = +opt('wait', 8000), W = +opt('w', 1280), H = +opt('h', 720);
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl', '--no-sandbox', '--enable-features=Vulkan'] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
const logs = [];
page.on('console', (m) => logs.push(m.type() + ': ' + m.text()));
page.on('pageerror', (e) => logs.push('PAGEERROR: ' + e.message + '\n' + (e.stack || '')));
await page.goto(url);
const ev = opt('eval', '');
const steps = ev ? ev.split(';;') : [];
await page.waitForTimeout(wait);
for (const s of steps) { const r = await page.evaluate(s); if (r !== undefined) logs.push('eval -> ' + JSON.stringify(r)); await page.waitForTimeout(+opt('after', 1500)); }
await page.screenshot({ path: out });
if (args.includes('--logs') || logs.some((l) => /error/i.test(l))) console.log(logs.slice(-40).join('\n'));
await browser.close();
