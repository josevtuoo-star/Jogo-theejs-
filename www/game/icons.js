// Gera ícones de inventário renderizando os próprios modelos 3D (um quadro por item).
import { createRenderTarget } from '../engine/gl.js';
import { m4 } from '../engine/math.js';
import { ITEMS } from './items.js';

export function bakeIcons(game) {
  const r = game.r, gl = r.gl, lvl = game.level;
  const out = {};
  const savedEnv = r.env, savedShadow = r.shadowActive, savedCam = { ...r.cam }, savedAspect = r.cam.aspect;
  const env = {
    sunDir: [0.45, 0.78, 0.5], moonDir: [0, -1, 0], sunColor: [3.1, 3.0, 2.8], wetness: 0, zenith: [0.35, 0.45, 0.65], horizon: [0.55, 0.58, 0.62], ground: [0.22, 0.2, 0.16], fog: [0.5, 0.5, 0.5],
    fogDensity: 0, fogFalloff: 0.02, ambientScale: 1.15, cloud: 0, shadowStrength: 0, wind: [0, 0, 0, 0], lights: [null, null, null, null], moon: 0, night: 0, exposure: 1.0,
  };
  const prevPass = r.pass;
  r.pass = 'main';
  for (const [id, d] of Object.entries(ITEMS)) {
    if (!d.model) continue;
    const vis = lvl.itemVisual(id);
    if (!vis) continue;
    const W = Math.max(1, d.w) * 44, H = Math.max(1, d.h) * 44;
    const rt = createRenderTarget(gl, W, H);
    gl.bindFramebuffer(gl.FRAMEBUFFER, rt.fb);
    gl.viewport(0, 0, W, H);
    gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    r.setEnv(env); r.shadowActive = false; r.shadowCascades = r.shadowCascades;
    r.cam.aspect = W / H;
    // câmera olhando para o centro do objeto
    const c = vis.center, s = vis.size;
    const rad = Math.max(s[0], s[1], s[2]) * 0.5;
    // rotaciona o objeto ligeiramente: para objetos longos, mostra de lado
    const yaw = Math.PI / 5;
    const long = Math.max(s[0], s[2]) > s[1] * 1.6;
    const M = m4.create(); m4.rotationY(M, long ? (s[0] > s[2] ? 0 : Math.PI / 2) + 0.3 : yaw);
    const wide = Math.max(s[0], s[2]);
    const fov = 28 * Math.PI / 180;
    const fit = Math.max(long ? wide * 0.62 : rad * 1.15, s[1] * 0.62 * (W / H > 1 ? 1 : 1)) / Math.tan(fov / 2) * (long ? 1.0 : 1.12);
    const center = [c[0], c[1], c[2]];
    const m2 = m4.multiply(m4.create(), m4.translation(m4.create(), 0, 0, 0), M);
    // transforma centro
    const cw = m4.transformPoint([0, 0, 0], M, center);
    const dir = [0.12, 0.34, 1]; const dl = Math.hypot(...dir);
    const pos = [cw[0] + dir[0] / dl * fit, cw[1] + dir[1] / dl * fit, cw[2] + dir[2] / dl * fit];
    const f = [cw[0] - pos[0], cw[1] - pos[1], cw[2] - pos[2]]; const fl = Math.hypot(...f);
    const yawc = Math.atan2(-f[0] / fl, -f[2] / fl), pitch = Math.asin(f[1] / fl);
    r.setCamera(pos, yawc, pitch, fov, 0.02, 20);
    r._uploadScene();
    r._curProg = null; r._boundTex.fill(null);
    r._blend(false); r._depthWrite(true); r._cull(true);
    const tint = d.tint && d.model === 'ammo_box' ? d.tint : null;
    for (const p of vis.parts) {
      let mat = p.material;
      if (tint) mat = lvl._tinted(mat, tint);
      r.draw(p.mesh, mat, { model: M });
    }
    const px = new Uint8Array(W * H * 4);
    gl.readPixels(0, 0, W, H, gl.RGBA, gl.UNSIGNED_BYTE, px);
    const cv = document.createElement('canvas'); cv.width = W; cv.height = H;
    const g2 = cv.getContext('2d'), img = g2.createImageData(W, H);
    for (let y = 0; y < H; y++) img.data.set(px.subarray((H - 1 - y) * W * 4, (H - y) * W * 4), y * W * 4);
    g2.putImageData(img, 0, 0);
    out[id] = cv.toDataURL('image/png');
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.deleteTexture(rt.tex); gl.deleteFramebuffer(rt.fb); gl.deleteRenderbuffer(rt.rb);
  }
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  r.setEnv(savedEnv); r.shadowActive = savedShadow; r.cam.aspect = savedAspect; r.pass = prevPass;
  gl.clearColor(0, 0, 0, 1);
  r._curProg = null; r._boundTex.fill(null);
  return out;
}
