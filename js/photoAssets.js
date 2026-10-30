import * as THREE from 'three';
import { RGBELoader } from 'three/addons/loaders/RGBELoader.js';

// Texturas fotográficas e céu HDRI (CC0 — ver assets/CREDITS.md). O mundo nasce com as texturas
// desenhadas em canvas; quando as fotos chegam, os materiais são trocados por elas. Se algo
// falhar (rede, celular sem memória), o jogo continua com as texturas procedurais.
//
// Terreno: mistura de três fotos (grama verde, chão seco de outono com folhas e gravetos, rocha
// com musgo) por pesos de cada vértice + altura de cada textura (as pedras "saem" do meio da grama
// em vez de um degradê), em duas escalas giradas para não aparecer repetição, mais terra escura
// nas trilhas. As normais também são misturadas.

const loader = new THREE.TextureLoader();

async function tex(url, { srgb = true, repeat = 1, aniso = 8 } = {}) {
  const t = await loader.loadAsync(url);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
  t.repeat.set(repeat, repeat);
  t.anisotropy = aniso;
  return t;
}

/** Lê .hdr direto ou, onde .hdr não pode ser servido, um .txt com o arquivo em base64. */
async function loadHDR(url) {
  const rgbe = new RGBELoader().setDataType(THREE.FloatType);
  if (!url.endsWith('.txt')) return rgbe.loadAsync(url);
  const b64 = (await (await fetch(url)).text()).trim();
  const raw = atob(b64);
  const bin = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bin[i] = raw.charCodeAt(i);
  const data = rgbe.parse(bin.buffer);
  const t = new THREE.DataTexture(data.data, data.width, data.height, THREE.RGBAFormat, data.type);
  t.colorSpace = THREE.LinearSRGBColorSpace;
  t.minFilter = t.magFilter = THREE.LinearFilter;
  t.generateMipmaps = false;
  t.flipY = true;
  t.needsUpdate = true;
  return t;
}

function terrainMaterial(T, hq) {
  const m = new THREE.MeshStandardMaterial({
    map: T.forest, normalMap: T.grassN, normalScale: new THREE.Vector2(1.1, 1.1), roughness: 0.94, envMapIntensity: 0.4,
  });
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, { tGrass: { value: T.grass }, tRock: { value: T.rock }, tForestN: { value: T.forestN }, tRockN: { value: T.rockN } });
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute vec4 splat;\nattribute float tint;\nvarying vec4 vSplat;\nvarying float vTint;')
      .replace('#include <uv_vertex>', '#include <uv_vertex>\nvSplat = splat;\nvTint = tint;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', `#include <common>
        uniform sampler2D tGrass, tRock, tForestN, tRockN;
        varying vec4 vSplat;
        varying float vTint;`)
      .replace('#include <map_fragment>', `
        vec2 tuvA = vMapUv;
        vec2 tuvB = mat2(0.8, -0.6, 0.6, 0.8) * vMapUv * 0.41 + vec2(0.37, 0.71);
        vec3 cG = texture2D(tGrass, tuvA).rgb;
        vec3 cF = texture2D(map, tuvA).rgb;
        vec3 cR = texture2D(tRock, tuvA * 0.55).rgb;
        ${hq ? `
        cG = mix(cG, texture2D(tGrass, tuvB).rgb, 0.42);
        cF = mix(cF, texture2D(map, tuvB).rgb, 0.42);
        cR = mix(cR, texture2D(tRock, tuvB * 0.55).rgb, 0.35);` : ''}
        // mistura por altura: o mais "alto" (claro) de cada textura aparece primeiro na borda
        vec3 hgt = vec3(dot(cG, vec3(0.3, 0.59, 0.11)), dot(cF, vec3(0.3, 0.59, 0.11)), dot(cR, vec3(0.3, 0.59, 0.11)));
        vec3 tw = max(vSplat.xyz, 0.0) * (hgt * 1.6 + 0.3);
        tw = pow(tw, vec3(2.6));
        tw /= max(1e-4, tw.x + tw.y + tw.z);
        vec3 tcol = cG * tw.x + cF * tw.y + cR * tw.z;
        // terra batida/trilhas: o chão de folhas fica escuro e marrom, sem as folhas claras
        vec3 mud = cF * vec3(0.5, 0.43, 0.35);
        float dirt = clamp(vSplat.w * (1.25 - hgt.y * 0.6), 0.0, 1.0);
        tcol = mix(tcol, mud, dirt);
        // fotos aéreas são claras demais para o clima nublado: escurece e dá o tom outonal
        tcol *= vec3(0.74, 0.7, 0.62) * vTint;
        diffuseColor.rgb *= tcol;
        vec3 tN = (texture2D(normalMap, tuvA).xyz * 2.0 - 1.0) * tw.x
                + (texture2D(tForestN, tuvA).xyz * 2.0 - 1.0) * tw.y
                + (texture2D(tRockN, tuvA * 0.55).xyz * 2.0 - 1.0) * tw.z;
        tN = normalize(mix(tN, vec3(0.0, 0.0, 1.0), dirt * 0.4));`)
      .replace('#include <roughnessmap_fragment>', 'float roughnessFactor = roughness * (1.0 - tw.z * 0.14 - dirt * 0.06);')
      .replace('#include <normal_fragment_maps>', `
        vec3 mapN = tN;
        mapN.xy *= normalScale;
        normal = normalize( tbn * mapN );`);
  };
  m.customProgramCacheKey = () => 'terrain' + (hq ? 'hq' : 'lq');
  return m;
}

/**
 * Carrega e aplica. Devolve uma promessa que nunca falha (só avisa no console).
 * base: pasta dos assets; hdrUrl: céu HDRI (ou .txt base64).
 */
export async function applyPhotoAssets(world, renderer, { quality = 'high', base = 'assets/', hdr = 'env/forest_slope_1k.hdr' } = {}) {
  const hq = quality !== 'low';
  const aniso = Math.min(16, renderer.capabilities.getMaxAnisotropy());
  const jobs = [];
  // terreno
  jobs.push((async () => {
    const [grass, forest, rock, grassN, forestN, rockN] = await Promise.all([
      tex(base + 'tex/ground_grass_color.jpg', { aniso }), tex(base + 'tex/ground_forest_color.jpg', { aniso }), tex(base + 'tex/ground_dry_color.jpg', { aniso }),
      tex(base + 'tex/ground_grass_normal.jpg', { srgb: false, aniso }), tex(base + 'tex/ground_forest_normal.jpg', { srgb: false, aniso }), tex(base + 'tex/ground_dry_normal.jpg', { srgb: false, aniso }),
    ]);
    if (world.terrainMesh) world.terrainMesh.material = terrainMaterial({ grass, forest, rock, grassN, forestN, rockN }, hq);
  })());
  // tijolo de verdade (com relevo e rugosidade) — a foto cobre ~1,7 m; as paredes usam 2 m por repetição
  jobs.push((async () => {
    const [c, bump, rough] = await Promise.all([
      tex(base + 'tex/brick_color.jpg', { repeat: 1.18, aniso }), tex(base + 'tex/brick_bump.jpg', { srgb: false, repeat: 1.18, aniso }),
      tex(base + 'tex/brick_rough.jpg', { srgb: false, repeat: 1.18, aniso }),
    ]);
    Object.assign(world.mat.brick, { map: c, bumpMap: bump, bumpScale: 2.2, roughnessMap: rough, roughness: 1, color: new THREE.Color(0xd8ccc0) });
    world.mat.brick.needsUpdate = true;
  })());
  // asfalto velho: relevo de pedrinhas (normal da rocha em escala pequena) e mais escuro
  jobs.push((async () => {
    const n = await tex(base + 'tex/ground_dry_normal.jpg', { srgb: false, repeat: 2.5, aniso });
    Object.assign(world.mat.asphalt, { normalMap: n, normalScale: new THREE.Vector2(0.7, 0.7), color: new THREE.Color(0x9a978f) });
    world.mat.asphalt.needsUpdate = true;
  })());
  // tábuas velhas (janelas pregadas, píer, caixotes, porta)
  jobs.push((async () => {
    const [c, bump] = await Promise.all([tex(base + 'tex/planks_color.jpg', { repeat: 0.5, aniso }), tex(base + 'tex/planks_bump.jpg', { srgb: false, repeat: 0.5, aniso })]);
    for (const m of [world.mat.plank, world.mat.door]) {
      if (!m) continue;
      Object.assign(m, { map: c, bumpMap: bump, bumpScale: 1.6 });
      m.needsUpdate = true;
    }
  })());
  // céu HDRI só para a iluminação/reflexos (o céu visível continua o procedural, com nuvens animadas)
  jobs.push((async () => {
    const t = await loadHDR(base + hdr);
    // o HDRI é de um dia de céu azul: para o clima nublado de outono, tira boa parte da cor
    // (luz mais cinza) e esquenta um pouco
    const d = t.image.data;
    for (let i = 0; i < d.length; i += 4) {
      const l = d[i] * 0.3 + d[i + 1] * 0.59 + d[i + 2] * 0.11;
      d[i] = (l + (d[i] - l) * 0.3) * 1.06;
      d[i + 1] = (l + (d[i + 1] - l) * 0.3) * 1.0;
      d[i + 2] = (l + (d[i + 2] - l) * 0.3) * 0.88;
    }
    t.needsUpdate = true;
    t.mapping = THREE.EquirectangularReflectionMapping;
    const pmrem = new THREE.PMREMGenerator(renderer);
    const env = pmrem.fromEquirectangular(t).texture;
    pmrem.dispose();
    t.dispose();
    world.scene.environment = env;
    for (const m of Object.values(world.mat)) if (m.envMapIntensity !== undefined) m.envMapIntensity = Math.min(m.envMapIntensity, 0.5);
  })());
  const res = await Promise.allSettled(jobs);
  for (const r of res) if (r.status === 'rejected') console.warn('textura/céu fotográfico não carregou:', r.reason);
}
