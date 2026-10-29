import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

// Modelos 3D do jogador (arquivos .glb em /models):
//  - personagem: veio sem esqueleto de animação, então aqui ele é "costurado" no esqueleto
//    procedural do Character — cada vértice ganha pesos para os ossos mais próximos (quadril,
//    tronco, cabeça, braço, antebraço, mão, coxa, canela, pé) e vira um SkinnedMesh. Assim o
//    MESMO corpo anima em 1ª e 3ª pessoa com todas as animações que já existem;
//  - faca: só é reorientada para a convenção do jogo (lâmina em +Y, fio em -Z, cabo na origem).

const loader = new GLTFLoader();

// Escala e juntas do modelo, medidas no próprio arquivo (unidades originais, Z para cima,
// rosto para -Y). S converte para metros; depois o modelo gira 180° para olhar para -Z.
const S = 0.026;
const J = {
  shoulder: [7.6, 55.0, 1.5],
  elbow: [14.2, 46.2, 1.8],
  wrist: [20.5, 39.5, 0.0],
  fingers: [22.7, 33.9, -0.5],
  hip: [4.0, 33.0, 0.5],
  knee: [4.8, 19.5, 0.6],
  ankle: [5.4, 3.6, 1.8],
  toe: [5.6, 0.8, -7.0],
};
/** Junta do modelo no espaço do personagem (metros, frente -Z); side: +1 direita, -1 esquerda. */
function joint(name, side) {
  const [x, z, y] = J[name];
  // original (x, y, z) com Z para cima → three (x, z, -y) → gira 180° em Y → (-x, z, y)
  // o lado +x do arquivo é o lado esquerdo do personagem
  return new THREE.Vector3(side * x * S, z * S, y * S);
}

/** Partes que pertencem 100% à cabeça (e somem da câmera em 1ª pessoa). */
const HEAD_ONLY = /hat|carl_head|eyeball|hair/;
const FP_HIDE = /hat|carl_head|eyeball|hair|mechanic_head_color/;
const DROP = /holster/; // coldre de revólver: no lugar dele fica a bainha da faca

function closestOnSegment(p, a, b, out) {
  const ab = _ab.subVectors(b, a);
  const t = Math.max(0, Math.min(1, _ap.subVectors(p, a).dot(ab) / Math.max(ab.lengthSq(), 1e-9)));
  return out.copy(a).addScaledVector(ab, t);
}
const _ab = new THREE.Vector3(), _ap = new THREE.Vector3(), _c = new THREE.Vector3(), _v = new THREE.Vector3();

/**
 * Carrega o personagem e o prende no esqueleto do `character`.
 * Retorna true se deu certo (senão o corpo procedural continua).
 */
export async function loadPlayerModel(character, url) {
  const gltf = await loader.loadAsync(url);
  const ch = character;

  // ---------- ossos: um por grupo do esqueleto procedural ----------
  // bind = onde a junta está no modelo; rest = direção do osso no esqueleto em repouso (para baixo)
  const down = new THREE.Vector3(0, -1, 0);
  const bones = [];
  const bindInv = [];
  const segs = []; // segmento de influência de cada osso (espaço do modelo) + raio
  const addBone = (group, origin, dirTo, a, b, radius, side = 0) => {
    const bone = new THREE.Bone();
    group.add(bone);
    const q = new THREE.Quaternion();
    if (dirTo) q.setFromUnitVectors(down, _v.subVectors(dirTo, origin).normalize());
    const m = new THREE.Matrix4().compose(origin, q, new THREE.Vector3(1, 1, 1));
    bones.push(bone);
    bindInv.push(m.invert());
    segs.push({ a, b, r: radius, side });
    return bones.length - 1;
  };
  // tronco: as juntas do modelo coincidem com o esqueleto em repouso (sem rotação)
  const v3 = (x, y, z) => new THREE.Vector3(x, y, z);
  const hipsY = ch.hips.position.y, torsoY = hipsY + ch.torso.position.y, headY = torsoY + ch.head.position.y;
  const iHips = addBone(ch.hips, v3(0, hipsY, 0), null, v3(0, 0.84, 0.01), v3(0, 1.0, 0.01), 0.15);
  addBone(ch.torso, v3(0, torsoY, 0), null, v3(0, 1.0, 0), v3(0, 1.42, 0.02), 0.15);
  const iHead = addBone(ch.head, v3(0, headY, 0), null, v3(0, 1.52, 0), v3(0, 1.74, -0.02), 0.1);
  for (const [arm, leg] of [[ch.armL, ch.legL], [ch.armR, ch.legR]]) {
    const s = arm.side;
    const sh = joint('shoulder', s), el = joint('elbow', s), wr = joint('wrist', s), fi = joint('fingers', s);
    addBone(arm.upper, sh, el, sh, el, 0.05, s);
    addBone(arm.elbow, el, wr, el, wr, 0.042, s);
    // mão até os nós dos dedos + dedos (osso próprio para fechar o punho)
    const kn1 = new THREE.Vector3().lerpVectors(wr, fi, 0.5), kn2 = new THREE.Vector3().lerpVectors(wr, fi, 0.74);
    addBone(arm.hand, wr, fi, wr, kn1, 0.036, s);
    addBone(arm.fingers, kn1, fi, kn1, kn2, 0.024, s);
    addBone(arm.fingers2, kn2, fi, kn2, fi, 0.022, s);
    const hp = joint('hip', s), kn = joint('knee', s), an = joint('ankle', s), to = joint('toe', s);
    addBone(leg.thigh, hp, kn, hp, kn, 0.075, s);
    addBone(leg.knee, kn, an, kn, an, 0.055, s);
    addBone(leg.ankle, an, null, an, to, 0.05, s);
  }
  const skeleton = new THREE.Skeleton(bones, bindInv);

  // ---------- malhas: geometria para o espaço do personagem + pesos ----------
  const toChar = new THREE.Matrix4().makeRotationY(Math.PI).multiply(new THREE.Matrix4().makeScale(S, S, S));
  gltf.scene.updateMatrixWorld(true);
  const meshes = [];
  gltf.scene.traverse((o) => { if (o.isMesh) meshes.push(o); });
  const out = [];
  const p = new THREE.Vector3();
  for (const src of meshes) {
    const name = src.material.name || src.name;
    if (DROP.test(name)) continue;
    const geo = src.geometry.clone();
    geo.applyMatrix4(new THREE.Matrix4().multiplyMatrices(toChar, src.matrixWorld));
    const pos = geo.attributes.position;
    const n = pos.count;
    const idx = new Uint16Array(n * 4), wts = new Float32Array(n * 4);
    const headOnly = HEAD_ONLY.test(name);
    const cand = [];
    for (let i = 0; i < n; i++) {
      if (headOnly) { idx[i * 4] = iHead; wts[i * 4] = 1; continue; }
      p.fromBufferAttribute(pos, i);
      const side = p.x > 0.015 ? 1 : p.x < -0.015 ? -1 : 0;
      cand.length = 0;
      for (let b = 0; b < segs.length; b++) {
        const sg = segs[b];
        if (sg.side && side && sg.side !== side) continue; // braço/perna só do próprio lado
        const d = closestOnSegment(p, sg.a, sg.b, _c).distanceTo(p) / sg.r;
        cand.push([b, 1 / (Math.pow(d, 5) + 1e-5)]);
      }
      cand.sort((x, y) => y[1] - x[1]);
      let sum = 0;
      for (let k = 0; k < 4; k++) sum += cand[k][1];
      for (let k = 0; k < 4; k++) {
        const w = cand[k][1] / sum;
        idx[i * 4 + k] = cand[k][0];
        wts[i * 4 + k] = w < 0.02 ? 0 : w;
      }
      // renormaliza depois de descartar pesos muito pequenos
      let s2 = 0;
      for (let k = 0; k < 4; k++) s2 += wts[i * 4 + k];
      for (let k = 0; k < 4; k++) wts[i * 4 + k] /= s2;
    }
    geo.setAttribute('skinIndex', new THREE.Uint16BufferAttribute(idx, 4));
    geo.setAttribute('skinWeight', new THREE.Float32BufferAttribute(wts, 4));
    const mat = src.material;
    mat.envMapIntensity = 0.6;
    const mesh = new THREE.SkinnedMesh(geo, mat);
    mesh.bind(skeleton, new THREE.Matrix4());
    mesh.frustumCulled = false;
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    mesh.userData.fpHide = FP_HIDE.test(name);
    out.push(mesh);
  }
  ch.useModel(out, iHips);
  return true;
}

/** Faca do arquivo, reorientada: cabo no centro, lâmina para +Y, fio para -Z. */
export async function loadKnifeModel(url, length = 0.26) {
  const gltf = await loader.loadAsync(url);
  const m = gltf.scene;
  m.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(m);
  const size = box.max.x - box.min.x; // ao longo de X: ponta em -X, pomo em +X
  const k = length / size;
  // centro do cabo: ~25% do comprimento a partir do pomo
  const gripX = box.max.x - size * 0.25;
  const fix = new THREE.Matrix4().makeBasis(
    new THREE.Vector3(0, -1, 0), // +X (pomo) → -Y
    new THREE.Vector3(0, 0, 1),  // +Y (costas) → +Z, então o fio (-Y) fica em -Z
    new THREE.Vector3(-1, 0, 0),
  ).multiply(new THREE.Matrix4().makeScale(k, k, k))
    .multiply(new THREE.Matrix4().makeTranslation(-gripX, -(box.min.y + box.max.y) / 2, -(box.min.z + box.max.z) / 2));
  const g = new THREE.Group();
  m.traverse((o) => {
    if (!o.isMesh) return;
    const geo = o.geometry.clone();
    geo.applyMatrix4(new THREE.Matrix4().multiplyMatrices(fix, o.matrixWorld));
    const mesh = new THREE.Mesh(geo, o.material);
    o.material.side = THREE.FrontSide;
    mesh.castShadow = true;
    g.add(mesh);
  });
  return g;
}
