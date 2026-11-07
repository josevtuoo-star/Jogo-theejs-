// Partículas (billboards), decalques, chuva e linhas.
import { texFromImage } from './gl.js';
import { mulberry32, clamp } from './math.js';
import { PART_VS, PART_FS, DECAL_VS, LINE_VS, LINE_FS } from './shaders.js';

export const FRAME = { SMOKE: 0, DUST: 1, SPARK: 2, FLASH: 3, RAIN: 4, RING: 5, HOLE: 6, SCORCH: 7, FIRE: 8, DEBRIS: 9, LEAF: 10 };

function makeAtlas(gl) {
  const S = 64, c = document.createElement('canvas'); c.width = c.height = S * 4;
  const g = c.getContext('2d'), rnd = mulberry32(5);
  const cell = (i) => [(i % 4) * S, Math.floor(i / 4) * S];
  const blob = (i, soft, noise) => {
    const [ox, oy] = cell(i);
    for (let k = 0; k < noise; k++) {
      const a = rnd() * 6.28, r = rnd() * S * 0.22, x = ox + S / 2 + Math.cos(a) * r, y = oy + S / 2 + Math.sin(a) * r;
      const rr = S * (0.16 + rnd() * 0.16);
      const gr = g.createRadialGradient(x, y, 0, x, y, rr);
      gr.addColorStop(0, `rgba(255,255,255,${0.35 + 0.2 * rnd()})`); gr.addColorStop(soft, 'rgba(255,255,255,0.12)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = gr; g.fillRect(ox, oy, S, S);
    }
  };
  blob(0, 0.55, 12); blob(1, 0.4, 7);
  // spark
  { const [ox, oy] = cell(2); const gr = g.createRadialGradient(ox + 32, oy + 32, 0, ox + 32, oy + 32, 14); gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.3, 'rgba(255,240,200,0.8)'); gr.addColorStop(1, 'rgba(255,200,100,0)'); g.fillStyle = gr; g.fillRect(ox, oy, S, S); }
  // flash (estrela)
  { const [ox, oy] = cell(3); g.save(); g.translate(ox + 32, oy + 32);
    const gr = g.createRadialGradient(0, 0, 0, 0, 0, 30); gr.addColorStop(0, 'rgba(255,255,230,1)'); gr.addColorStop(0.25, 'rgba(255,220,140,0.8)'); gr.addColorStop(1, 'rgba(255,150,40,0)'); g.fillStyle = gr; g.fillRect(-32, -32, 64, 64);
    g.fillStyle = 'rgba(255,240,190,0.95)';
    for (let k = 0; k < 6; k++) { g.rotate(Math.PI / 3 + 0.2); g.beginPath(); g.moveTo(0, -2); g.lineTo(30, 0); g.lineTo(0, 2); g.fill(); }
    g.restore(); }
  // chuva
  { const [ox, oy] = cell(4); const gr = g.createLinearGradient(ox, oy, ox, oy + S); gr.addColorStop(0, 'rgba(255,255,255,0)'); gr.addColorStop(0.5, 'rgba(255,255,255,0.9)'); gr.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = gr; g.fillRect(ox + 30, oy, 4, S); }
  // anel
  { const [ox, oy] = cell(5); g.strokeStyle = 'rgba(255,255,255,0.9)'; g.lineWidth = 3; g.beginPath(); g.ellipse(ox + 32, oy + 32, 24, 24, 0, 0, 7); g.stroke(); }
  // buraco de bala
  { const [ox, oy] = cell(6); const gr = g.createRadialGradient(ox + 32, oy + 32, 2, ox + 32, oy + 32, 22); gr.addColorStop(0, 'rgba(0,0,0,0.95)'); gr.addColorStop(0.35, 'rgba(10,8,6,0.8)'); gr.addColorStop(1, 'rgba(0,0,0,0)'); g.fillStyle = gr; g.fillRect(ox, oy, S, S);
    g.strokeStyle = 'rgba(0,0,0,0.45)'; g.lineWidth = 1; for (let k = 0; k < 7; k++) { const a = rnd() * 6.28, l = 12 + rnd() * 16; g.beginPath(); g.moveTo(ox + 32, oy + 32); g.lineTo(ox + 32 + Math.cos(a) * l, oy + 32 + Math.sin(a) * l); g.stroke(); } }
  // mancha escura (queimado)
  blob(7, 0.7, 10);
  // fogo
  { const [ox, oy] = cell(8); const gr = g.createRadialGradient(ox + 32, oy + 40, 0, ox + 32, oy + 36, 26); gr.addColorStop(0, 'rgba(255,255,200,1)'); gr.addColorStop(0.4, 'rgba(255,170,40,0.85)'); gr.addColorStop(1, 'rgba(255,60,0,0)'); g.fillStyle = gr; g.fillRect(ox, oy, S, S); }
  // detrito (pedacinho)
  { const [ox, oy] = cell(9); g.fillStyle = '#fff'; g.beginPath(); g.moveTo(ox + 20, oy + 40); g.lineTo(ox + 36, oy + 18); g.lineTo(ox + 46, oy + 40); g.closePath(); g.fill(); }
  // folha
  { const [ox, oy] = cell(10); g.fillStyle = '#fff'; g.beginPath(); g.ellipse(ox + 32, oy + 32, 20, 9, 0.4, 0, 7); g.fill(); }
  return texFromImage(gl, c, { srgb: false, mips: true, aniso: 1, wrap: gl.CLAMP_TO_EDGE });
}

export class Particles {
  constructor(renderer, max = 3000) {
    const gl = this.gl = renderer.gl; this.r = renderer;
    this.max = max; this.n = 0;
    this.px = new Float32Array(max * 4); this.pc = new Float32Array(max * 4); this.pr = new Float32Array(max * 4);
    this.vel = new Float32Array(max * 3); this.life = new Float32Array(max); this.maxLife = new Float32Array(max);
    this.s0 = new Float32Array(max); this.s1 = new Float32Array(max); this.c0 = new Float32Array(max * 4); this.c1 = new Float32Array(max * 4);
    this.grav = new Float32Array(max); this.drag = new Float32Array(max); this.spin = new Float32Array(max); this.collide = new Uint8Array(max);
    this.atlas = makeAtlas(gl);
    this.prog = renderer.prog('particles', PART_VS, PART_FS);
    this.decalProg = renderer.prog('decals', DECAL_VS, PART_FS);
    this.lineProg = renderer.prog('lines', LINE_VS, LINE_FS);
    // quad
    this.quad = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, this.quad);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, 1, 1, -1, 1]), gl.STATIC_DRAW);
    this.idx = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.idx); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array([0, 1, 2, 0, 2, 3]), gl.STATIC_DRAW);
    const mk = (cap) => { const b = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, b); gl.bufferData(gl.ARRAY_BUFFER, cap * 4 * 4, gl.DYNAMIC_DRAW); return b; };
    this.bP = mk(max); this.bC = mk(max); this.bR = mk(max);
    const vao = (b1, b2, b3) => {
      const v = gl.createVertexArray(); gl.bindVertexArray(v);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.quad); gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
      [[1, b1], [2, b2], [3, b3]].forEach(([l, b]) => { gl.bindBuffer(gl.ARRAY_BUFFER, b); gl.enableVertexAttribArray(l); gl.vertexAttribPointer(l, 4, gl.FLOAT, false, 0, 0); gl.vertexAttribDivisor(l, 1); });
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.idx);
      gl.bindVertexArray(null); return v;
    };
    this.vao = vao(this.bP, this.bC, this.bR);
    // decalques
    this.dMax = 300; this.dN = 0; this.dHead = 0;
    this.dP = new Float32Array(this.dMax * 4); this.dN4 = new Float32Array(this.dMax * 4); this.dC = new Float32Array(this.dMax * 4); this.dLife = new Float32Array(this.dMax);
    this.bdP = mk(this.dMax); this.bdN = mk(this.dMax); this.bdC = mk(this.dMax);
    this.dvao = vao(this.bdP, this.bdN, this.bdC);
    // chuva
    this.rainN = 0; this.rainMax = 2200;
    this.rP = new Float32Array(this.rainMax * 4); this.rC = new Float32Array(this.rainMax * 4); this.rR = new Float32Array(this.rainMax * 4);
    this.brP = mk(this.rainMax); this.brC = mk(this.rainMax); this.brR = mk(this.rainMax);
    this.rvao = vao(this.brP, this.brC, this.brR);
    this.rain = { drops: new Float32Array(this.rainMax * 3), init: false, seed: mulberry32(11) };
    // linhas dinâmicas
    this.lineMax = 4096;
    this.lineBuf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, this.lineBuf); gl.bufferData(gl.ARRAY_BUFFER, this.lineMax * 7 * 4, gl.DYNAMIC_DRAW);
    this.lineData = new Float32Array(this.lineMax * 7); this.lineN = 0;
    this.lvao = gl.createVertexArray(); gl.bindVertexArray(this.lvao);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.lineBuf);
    gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 28, 0);
    gl.enableVertexAttribArray(3); gl.vertexAttribPointer(3, 4, gl.FLOAT, false, 28, 12);
    gl.bindVertexArray(null);
    this.rnd = mulberry32(1234);
    this.groundFn = null; // (x,z)=>y para colidir com o chão
  }

  emit(o) {
    if (this.n >= this.max) return;
    const i = this.n++;
    const r = this.rnd;
    this.px[i * 4] = o.x; this.px[i * 4 + 1] = o.y; this.px[i * 4 + 2] = o.z; this.px[i * 4 + 3] = o.s0 ?? 0.3;
    this.vel[i * 3] = o.vx || 0; this.vel[i * 3 + 1] = o.vy || 0; this.vel[i * 3 + 2] = o.vz || 0;
    this.life[i] = 0; this.maxLife[i] = o.life ?? 1;
    this.s0[i] = o.s0 ?? 0.3; this.s1[i] = o.s1 ?? o.s0 ?? 0.3;
    const c0 = o.c0 || [1, 1, 1, 1], c1 = o.c1 || [c0[0], c0[1], c0[2], 0];
    for (let k = 0; k < 4; k++) { this.c0[i * 4 + k] = c0[k]; this.c1[i * 4 + k] = c1[k]; }
    this.pr[i * 4] = o.rot ?? r() * 6.28; this.pr[i * 4 + 1] = o.frame ?? 0; this.pr[i * 4 + 2] = o.stretch || 0; this.pr[i * 4 + 3] = o.lit ?? 1;
    this.grav[i] = o.grav ?? 0; this.drag[i] = o.drag ?? 0; this.spin[i] = o.spin ?? 0; this.collide[i] = o.collide ? 1 : 0;
  }
  burst(n, f) { for (let i = 0; i < n; i++) this.emit(f(i, this.rnd)); }

  // preset: nuvem de fumaça
  smoke(x, y, z, n = 6, size = 0.6, up = 0.6, col = [0.7, 0.7, 0.7, 0.5], life = 2) {
    for (let i = 0; i < n; i++) { const r = this.rnd; this.emit({ x, y, z, vx: (r() - 0.5) * 0.6, vy: up * (0.4 + r() * 0.6), vz: (r() - 0.5) * 0.6, s0: size * 0.5, s1: size * (1.5 + r()), life: life * (0.7 + 0.6 * r()), c0: col, c1: [col[0], col[1], col[2], 0], frame: FRAME.SMOKE, drag: 0.8, grav: -0.02, spin: (r() - 0.5) * 0.8 }); }
  }
  dust(x, y, z, n = 8, col = [0.55, 0.45, 0.33, 0.6], speed = 1.6, normal = [0, 1, 0]) {
    for (let i = 0; i < n; i++) { const r = this.rnd; this.emit({ x, y, z, vx: normal[0] * speed * 0.6 + (r() - 0.5) * speed, vy: normal[1] * speed * 0.6 + r() * speed * 0.6, vz: normal[2] * speed * 0.6 + (r() - 0.5) * speed, s0: 0.1, s1: 0.35 + r() * 0.3, life: 0.5 + r() * 0.6, c0: col, c1: [col[0], col[1], col[2], 0], frame: FRAME.DUST, drag: 3.0, grav: 0.3, spin: (r() - 0.5) * 2 }); }
  }
  sparks(x, y, z, n = 6, normal = [0, 1, 0]) {
    for (let i = 0; i < n; i++) { const r = this.rnd; this.emit({ x, y, z, vx: normal[0] * 3 + (r() - 0.5) * 4, vy: normal[1] * 3 + r() * 3, vz: normal[2] * 3 + (r() - 0.5) * 4, s0: 0.05, s1: 0.02, life: 0.25 + r() * 0.3, c0: [1.5, 1.1, 0.5, 1], c1: [1, 0.4, 0.1, 0], frame: FRAME.SPARK, grav: 9, lit: 0 }); }
  }
  debris(x, y, z, n, col, normal = [0, 1, 0], speed = 4) {
    for (let i = 0; i < n; i++) { const r = this.rnd; this.emit({ x, y, z, vx: normal[0] * speed * 0.5 + (r() - 0.5) * speed, vy: normal[1] * speed * 0.5 + r() * speed * 0.8, vz: normal[2] * speed * 0.5 + (r() - 0.5) * speed, s0: 0.04 + r() * 0.04, s1: 0.03, life: 0.6 + r() * 0.5, c0: col, c1: [col[0], col[1], col[2], 0.6], frame: FRAME.DEBRIS, grav: 9.8, spin: (r() - 0.5) * 12, collide: true }); }
  }
  splash(x, y, z, n = 8) {
    for (let i = 0; i < n; i++) { const r = this.rnd; this.emit({ x, y, z, vx: (r() - 0.5) * 2.2, vy: 2 + r() * 2.2, vz: (r() - 0.5) * 2.2, s0: 0.1, s1: 0.2, life: 0.7, c0: [0.8, 0.9, 1, 0.6], c1: [0.8, 0.9, 1, 0], frame: FRAME.DUST, grav: 9.8, drag: 0.5 }); }
    this.emit({ x, y: y + 0.02, z, s0: 0.1, s1: 1.4, life: 0.7, c0: [1, 1, 1, 0.8], c1: [1, 1, 1, 0], frame: FRAME.RING, rot: 0, lit: 1 });
  }
  muzzleFlash(x, y, z, size = 0.5, dir) {
    this.emit({ x, y, z, s0: size, s1: size * 1.3, life: 0.045, c0: [3, 2.4, 1.4, 1], c1: [2, 1, 0.4, 0], frame: FRAME.FLASH, lit: 0 });
  }
  explosion(x, y, z) {
    this.emit({ x, y: y + 0.5, z, s0: 2, s1: 7, life: 0.25, c0: [4, 2.6, 1.2, 1], c1: [2, 0.6, 0.1, 0], frame: FRAME.FIRE, lit: 0 });
    this.smoke(x, y + 0.5, z, 18, 3.0, 2.5, [0.18, 0.17, 0.16, 0.8], 5);
    this.dust(x, y + 0.2, z, 22, [0.4, 0.33, 0.25, 0.7], 8);
    this.sparks(x, y + 0.4, z, 24);
    for (let i = 0; i < 12; i++) { const r = this.rnd; this.emit({ x, y: y + 0.6, z, vx: (r() - 0.5) * 12, vy: 4 + r() * 8, vz: (r() - 0.5) * 12, s0: 0.5, s1: 1.6, life: 1.6, c0: [2, 1, 0.3, 0.9], c1: [0.2, 0.1, 0.05, 0], frame: FRAME.SMOKE, grav: 2, drag: 0.5, lit: 0 }); }
  }

  decal(x, y, z, nx, ny, nz, size, frame, col = [1, 1, 1, 0.9], life = 60) {
    const i = this.dHead; this.dHead = (this.dHead + 1) % this.dMax; this.dN = Math.min(this.dN + 1, this.dMax);
    this.dP[i * 4] = x; this.dP[i * 4 + 1] = y; this.dP[i * 4 + 2] = z; this.dP[i * 4 + 3] = size;
    this.dN4[i * 4] = nx; this.dN4[i * 4 + 1] = ny; this.dN4[i * 4 + 2] = nz; this.dN4[i * 4 + 3] = this.rnd() * 6 + frame * 10;
    for (let k = 0; k < 4; k++) this.dC[i * 4 + k] = col[k];
    this.dLife[i] = life;
  }

  update(dt) {
    const g = this.groundFn;
    for (let i = 0; i < this.n; i++) {
      this.life[i] += dt;
      if (this.life[i] >= this.maxLife[i]) { // remove (swap)
        const l = --this.n;
        if (i !== l) {
          for (let k = 0; k < 4; k++) { this.px[i * 4 + k] = this.px[l * 4 + k]; this.pr[i * 4 + k] = this.pr[l * 4 + k]; this.c0[i * 4 + k] = this.c0[l * 4 + k]; this.c1[i * 4 + k] = this.c1[l * 4 + k]; }
          for (let k = 0; k < 3; k++) this.vel[i * 3 + k] = this.vel[l * 3 + k];
          this.life[i] = this.life[l]; this.maxLife[i] = this.maxLife[l]; this.s0[i] = this.s0[l]; this.s1[i] = this.s1[l]; this.grav[i] = this.grav[l]; this.drag[i] = this.drag[l]; this.spin[i] = this.spin[l]; this.collide[i] = this.collide[l];
        }
        i--; continue;
      }
      const t = this.life[i] / this.maxLife[i];
      const dr = Math.max(0, 1 - this.drag[i] * dt);
      this.vel[i * 3] *= dr; this.vel[i * 3 + 1] = this.vel[i * 3 + 1] * dr - this.grav[i] * dt; this.vel[i * 3 + 2] *= dr;
      this.px[i * 4] += this.vel[i * 3] * dt; this.px[i * 4 + 1] += this.vel[i * 3 + 1] * dt; this.px[i * 4 + 2] += this.vel[i * 3 + 2] * dt;
      if (this.collide[i] && g) { const h = g(this.px[i * 4], this.px[i * 4 + 2]); if (this.px[i * 4 + 1] < h) { this.px[i * 4 + 1] = h; this.vel[i * 3 + 1] *= -0.3; this.vel[i * 3] *= 0.6; this.vel[i * 3 + 2] *= 0.6; } }
      this.px[i * 4 + 3] = this.s0[i] + (this.s1[i] - this.s0[i]) * t;
      for (let k = 0; k < 4; k++) this.pc[i * 4 + k] = this.c0[i * 4 + k] + (this.c1[i * 4 + k] - this.c0[i * 4 + k]) * t;
      this.pr[i * 4] += this.spin[i] * dt;
    }
    for (let i = 0; i < this.dMax; i++) if (this.dLife[i] > 0) { this.dLife[i] -= dt; if (this.dLife[i] < 5) this.dC[i * 4 + 3] = Math.max(0, this.dLife[i] / 5) * 0.9; }
  }

  // lineas: [x,y,z,r,g,b,a]*2 por segmento
  line(a, b, col = [1, 1, 1, 1], col2) {
    if (this.lineN + 2 > this.lineMax) return;
    const d = this.lineData, o = this.lineN * 7, c2 = col2 || col;
    d[o] = a[0]; d[o + 1] = a[1]; d[o + 2] = a[2]; d[o + 3] = col[0]; d[o + 4] = col[1]; d[o + 5] = col[2]; d[o + 6] = col[3];
    d[o + 7] = b[0]; d[o + 8] = b[1]; d[o + 9] = b[2]; d[o + 10] = c2[0]; d[o + 11] = c2[1]; d[o + 12] = c2[2]; d[o + 13] = c2[3];
    this.lineN += 2;
  }

  // chuva ao redor da câmera
  updateRain(cam, amount, dt, wind) {
    const R = this.rain, N = Math.floor(this.rainMax * clamp(amount, 0, 1));
    const rnd = R.seed;
    if (!R.init) { for (let i = 0; i < this.rainMax; i++) { R.drops[i * 3] = (rnd() - 0.5) * 36; R.drops[i * 3 + 1] = rnd() * 18; R.drops[i * 3 + 2] = (rnd() - 0.5) * 36; } R.init = true; }
    this.rainN = N;
    const vx = wind[0] * 3, vz = wind[1] * 3, vy = -13;
    for (let i = 0; i < N; i++) {
      let x = R.drops[i * 3] + vx * dt, y = R.drops[i * 3 + 1] + vy * dt, z = R.drops[i * 3 + 2] + vz * dt;
      if (y < -2) { y += 20; x = (rnd() - 0.5) * 36; z = (rnd() - 0.5) * 36; }
      R.drops[i * 3] = x; R.drops[i * 3 + 1] = y; R.drops[i * 3 + 2] = z;
      this.rP[i * 4] = cam[0] + x; this.rP[i * 4 + 1] = cam[1] + y - 1; this.rP[i * 4 + 2] = cam[2] + z; this.rP[i * 4 + 3] = 0.012;
      this.rC[i * 4] = 0.75; this.rC[i * 4 + 1] = 0.8; this.rC[i * 4 + 2] = 0.9; this.rC[i * 4 + 3] = 0.28;
      this.rR[i * 4] = 0; this.rR[i * 4 + 1] = FRAME.RAIN; this.rR[i * 4 + 2] = 0.55; this.rR[i * 4 + 3] = 0;
    }
  }

  draw(r) {
    const gl = this.gl;
    // decalques
    if (this.dN > 0) {
      const p = r.use(this.decalProg);
      r.tex(14, this.atlas); p.f1('uAdd', 0);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.bdP); gl.bufferSubData(gl.ARRAY_BUFFER, 0, this.dP);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.bdN); gl.bufferSubData(gl.ARRAY_BUFFER, 0, this.dN4);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.bdC); gl.bufferSubData(gl.ARRAY_BUFFER, 0, this.dC);
      r._cull(false); r._blend(true); r._depthWrite(false);
      gl.enable(gl.POLYGON_OFFSET_FILL); gl.polygonOffset(-2, -2);
      gl.bindVertexArray(this.dvao);
      gl.drawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, 0, this.dMax);
      gl.disable(gl.POLYGON_OFFSET_FILL);
    }
    // partículas
    const p = r.use(this.prog);
    r.tex(14, this.atlas);
    r._cull(false); r._blend(true); r._depthWrite(false);
    if (this.n > 0) {
      p.f1('uAdd', 0);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.bP); gl.bufferSubData(gl.ARRAY_BUFFER, 0, this.px, 0, this.n * 4);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.bC); gl.bufferSubData(gl.ARRAY_BUFFER, 0, this.pc, 0, this.n * 4);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.bR); gl.bufferSubData(gl.ARRAY_BUFFER, 0, this.pr, 0, this.n * 4);
      gl.bindVertexArray(this.vao);
      gl.drawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, 0, this.n);
      gl.stats.draws++;
    }
    if (this.rainN > 0) {
      p.f1('uAdd', 0);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.brP); gl.bufferSubData(gl.ARRAY_BUFFER, 0, this.rP, 0, this.rainN * 4);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.brC); gl.bufferSubData(gl.ARRAY_BUFFER, 0, this.rC, 0, this.rainN * 4);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.brR); gl.bufferSubData(gl.ARRAY_BUFFER, 0, this.rR, 0, this.rainN * 4);
      gl.bindVertexArray(this.rvao);
      gl.drawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, 0, this.rainN);
      gl.stats.draws++;
    }
    // linhas
    if (this.lineN > 0) {
      const lp = r.use(this.lineProg);
      lp.f1('uUnlit', 1);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.lineBuf); gl.bufferSubData(gl.ARRAY_BUFFER, 0, this.lineData, 0, this.lineN * 7);
      r._cull(false); r._blend(true); r._depthWrite(false);
      gl.bindVertexArray(this.lvao);
      gl.drawArrays(gl.LINES, 0, this.lineN);
      this.lineN = 0;
    }
    r._blend(false); r._depthWrite(true);
  }
}
