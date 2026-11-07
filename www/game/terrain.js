// Terreno 2x2 km: heightmap na GPU (R32F), chunks com 5 níveis de LOD, splat de materiais e água.
import { Mesh, texFromData, MeshBuilder } from '../engine/gl.js';
import { Material } from '../engine/renderer.js';
import { m4, clamp } from '../engine/math.js';
import { TERRAIN_FS, terrainVS, WATER_VS, WATER_FS } from '../engine/shaders.js';
import { WORLD } from './worldgen.js';

const CHUNK = 128, CELLS = 64, NCH = WORLD.size / CHUNK; // 16x16 chunks
const LOD_DIST = [140, 330, 650, 1150];

export class Terrain {
  constructor(renderer, world, assets) {
    const gl = this.gl = renderer.gl;
    this.r = renderer; this.world = world; this.assets = assets;
    const hn = WORLD.hn;
    // texturas de dados
    const t = this.heightTex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texStorage2D(gl.TEXTURE_2D, 1, gl.R32F, hn, hn);
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, hn, hn, gl.RED, gl.FLOAT, world.heights);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    const hf = this.heightTexF = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, hf);
    gl.texStorage2D(gl.TEXTURE_2D, 1, gl.R16F, hn, hn);
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, hn, hn, gl.RED, gl.FLOAT, world.heights);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    this.normalTex = texFromData(gl, hn, hn, world.normalMap, { mips: false });
    this.splat0 = texFromData(gl, WORLD.splatN, WORLD.splatN, world.splat0, { mips: true, aniso: 4 });
    this.splat1 = texFromData(gl, WORLD.splatN, WORLD.splatN, world.splat1, { mips: true, aniso: 4 });
    // programas
    this.prog = renderer.prog('terrain', terrainVS(''), TERRAIN_FS);
    this.waterProg = renderer.prog('water', WATER_VS, WATER_FS);
    // malhas de grade por LOD
    this.lods = [];
    for (let k = 0; k < 5; k++) this.lods.push(this._gridMesh(CELLS >> k));
    // alturas mín/máx por chunk
    this.bounds = new Float32Array(NCH * NCH * 2);
    for (let cz = 0; cz < NCH; cz++) for (let cx = 0; cx < NCH; cx++) {
      let mn = 1e9, mx = -1e9;
      const i0 = cx * CELLS, j0 = cz * CELLS;
      for (let j = j0; j <= j0 + CELLS; j += 2) for (let i = i0; i <= i0 + CELLS; i += 2) {
        const h = world.heights[Math.min(j, hn - 1) * hn + Math.min(i, hn - 1)];
        if (h < mn) mn = h; if (h > mx) mx = h;
      }
      this.bounds[(cz * NCH + cx) * 2] = mn - 12; this.bounds[(cz * NCH + cx) * 2 + 1] = mx + 2;
    }
    this._buildWater();
    const TINT = [[0.74, 1.12, 0.5], [0.78, 0.96, 0.62], [1, 0.95, 0.88], [1, 1, 1], [1, 1, 1], [1, 1, 1], [1, 1, 1]];
    this.tint = new Float32Array(TINT.flat());
    this.avg = new Float32Array(21);
    for (let i = 0; i < 21; i++) this.avg[i] = assets.layerAvg[i] * this.tint[i];
  }

  _gridMesh(n) {
    const verts = [], idx = [];
    const w = n + 1;
    for (let j = 0; j <= n; j++) for (let i = 0; i <= n; i++) verts.push(i / n, 0, j / n);
    const base = verts.length / 3;
    const skirt = (list) => { for (const [i, j] of list) verts.push(i / n, 1, j / n); };
    const edges = [];
    for (let i = 0; i <= n; i++) edges.push([i, 0]);        // norte
    for (let i = 0; i <= n; i++) edges.push([i, n]);        // sul
    for (let j = 0; j <= n; j++) edges.push([0, j]);        // oeste
    for (let j = 0; j <= n; j++) edges.push([n, j]);        // leste
    skirt(edges);
    for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) {
      const a = j * w + i, b = a + 1, c = a + w, d = c + 1;
      idx.push(a, c, d, a, d, b);
    }
    const N = n + 1;
    const sk = (off, ids, flip) => {
      for (let k = 0; k < N - 1; k++) {
        const t0 = ids(k), t1 = ids(k + 1), s0 = base + off + k, s1 = base + off + k + 1;
        if (!flip) idx.push(t0, s0, s1, t0, s1, t1); else idx.push(t0, t1, s1, t0, s1, s0);
      }
    };
    sk(0, (k) => k, true);                   // norte (z=0)
    sk(N, (k) => n * w + k, false);          // sul
    sk(2 * N, (k) => k * w, false);          // oeste
    sk(3 * N, (k) => k * w + n, true);       // leste
    const pos = new Float32Array(verts);
    const gl = this.gl;
    const m = new Mesh(gl, { positions: pos, indices: new Uint32Array(idx) });
    m.positions = null; m.indices = null;
    return m;
  }

  _buildWater() {
    const gl = this.gl, w = this.world;
    // lago
    const lk = w.lake, b = new MeshBuilder();
    const ex = lk.rx * 1.7, ez = lk.rz * 1.7, y = WORLD.waterY;
    b.quad4([lk.x - ex, y, lk.z - ez], [lk.x - ex, y, lk.z + ez], [lk.x + ex, y, lk.z + ez], [lk.x + ex, y, lk.z - ez], [0, 1, 0], [0, 0, 0, 1, 1, 1, 1, 0]);
    this.lakeMesh = b.build(gl);
    // rio (faixa)
    const rb = new MeshBuilder();
    const P = w.river.pts, hw = w.river.half + 2.5;
    let acc = 0;
    for (let i = 0; i < P.length; i++) {
      const a = P[Math.max(i - 1, 0)], c = P[Math.min(i + 1, P.length - 1)];
      let dx = c[0] - a[0], dz = c[1] - a[1]; const l = Math.hypot(dx, dz) || 1; dx /= l; dz /= l;
      if (i > 0) acc += Math.hypot(P[i][0] - P[i - 1][0], P[i][1] - P[i - 1][1]);
      const y = P[i][2];
      rb.vert(P[i][0] - dz * hw, y, P[i][1] + dx * hw, 0, 1, 0, 0, acc, 255, 0, 0, 255);
      rb.vert(P[i][0] + dz * hw, y, P[i][1] - dx * hw, 0, 1, 0, 1, acc, 255, 0, 0, 255);
      if (i > 0) { const k = i * 2; rb.quad(k - 2, k, k + 1, k - 1); }
    }
    this.riverMesh = rb.build(gl);
    this.waterModel = m4.create();
  }

  // ---- desenho do terreno
  draw(r, cam, shadowPass) {
    if (shadowPass) return; // terreno não projeta sombras (só recebe)
    const gl = this.gl, p = r.use(this.prog), f = r.frustum, ass = this.assets;
    r.tex(7, this.heightTex); r.tex(8, this.normalTex); r.tex(9, this.splat0); r.tex(10, this.splat1);
    r.tex(11, ass.terrAlb, gl.TEXTURE_2D_ARRAY); r.tex(12, ass.terrNor, gl.TEXTURE_2D_ARRAY);
    p.f2('uHInfo', WORLD.hn, WORLD.spacing);
    p.f4('uTerrInfo', WORLD.size, 1 / WORLD.size, 0, 0);
    const l = p.loc('uLayerAvg[0]'); if (l) gl.uniform3fv(l, this.avg);
    const l2 = p.loc('uLayerTint[0]'); if (l2) gl.uniform3fv(l2, this.tint);
    r._cull(true); r._blend(false); r._depthWrite(true);
    const cx = cam[0], cz = cam[2];
    let drawn = 0;
    gl.bindVertexArray(null);
    for (let z = 0; z < NCH; z++) for (let x = 0; x < NCH; x++) {
      const x0 = x * CHUNK, z0 = z * CHUNK;
      const k = (z * NCH + x) * 2;
      if (!f.aabb(x0, this.bounds[k], z0, x0 + CHUNK, this.bounds[k + 1], z0 + CHUNK)) continue;
      const dx = Math.max(x0 - cx, 0, cx - (x0 + CHUNK)), dz = Math.max(z0 - cz, 0, cz - (z0 + CHUNK));
      const d = Math.hypot(dx, dz);
      let lod = d < LOD_DIST[0] ? 0 : d < LOD_DIST[1] ? 1 : d < LOD_DIST[2] ? 2 : d < LOD_DIST[3] ? 3 : 4;
      if (d > 1500) continue;
      p.f4('uChunk', x0, z0, CHUNK, 1.0 + lod * 2.2);
      const m = this.lods[lod];
      gl.bindVertexArray(m.vao);
      gl.drawElements(gl.TRIANGLES, m.indexCount, m.indexType, 0);
      gl.stats.draws++; gl.stats.tris += m.tris; drawn++;
    }
    this.drawnChunks = drawn;
  }

  drawWater(r) {
    const gl = this.gl, p = r.use(this.waterProg);
    r.tex(13, this.heightTexF);
    p.f4('uTerrInfo', WORLD.size, 1 / WORLD.size, 0, 0);
    p.m4('uModel', this.waterModel);
    r._cull(false); r._blend(true); r._depthWrite(false);
    p.f2('uFlow', 0, 0);
    this.lakeMesh.draw();
    const f = this.world.river.pts;
    p.f2('uFlow', -0.35, 0.45);
    this.riverMesh.draw();
    r._blend(false); r._depthWrite(true);
  }
}
