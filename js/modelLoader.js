import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const loader = new GLTFLoader();

/**
 * Carrega um modelo 3D (.glb). Também aceita glTF em .json cuja geometria está num arquivo de
 * texto base64 (.txt) — usado onde a página não pode buscar .glb nem endereços data: (artifact).
 * A geometria é decodificada aqui e montada num GLB em memória; as texturas continuam .jpg.
 */
export async function loadModelFile(url) {
  if (!url.endsWith('.json')) return loader.loadAsync(url);
  const base = url.slice(0, url.lastIndexOf('/') + 1);
  const json = await (await fetch(url)).json();
  const b64 = (await (await fetch(base + json.buffers[0].uri)).text()).trim();
  const raw = atob(b64);
  const bin = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bin[i] = raw.charCodeAt(i);
  delete json.buffers[0].uri;
  json.buffers[0].byteLength = bin.length;
  const js = new TextEncoder().encode(JSON.stringify(json));
  const pad = (n) => (4 - (n % 4)) % 4;
  const jsLen = js.length + pad(js.length), binLen = bin.length + pad(bin.length);
  const glb = new Uint8Array(12 + 8 + jsLen + 8 + binLen);
  const dv = new DataView(glb.buffer);
  dv.setUint32(0, 0x46546c67, true); dv.setUint32(4, 2, true); dv.setUint32(8, glb.length, true);
  dv.setUint32(12, jsLen, true); dv.setUint32(16, 0x4e4f534a, true);
  glb.fill(0x20, 20, 20 + jsLen); glb.set(js, 20);
  dv.setUint32(20 + jsLen, binLen, true); dv.setUint32(24 + jsLen, 0x004e4942, true);
  glb.set(bin, 28 + jsLen);
  return loader.parseAsync(glb.buffer, base);
}

/** Nome "limpo" de osso Mixamo (o Sketchfab acrescenta um número): mixamorigLeftArm_00 → LeftArm. */
export const boneName = (n) => n.replace(/^mixamorig:?/, '').replace(/_\d+$/, '');

/** Ossos do esqueleto por nome limpo. */
export function bonesByName(root) {
  const B = {};
  root.traverse((o) => { if (o.isBone) B[boneName(o.name)] = o; });
  return B;
}
