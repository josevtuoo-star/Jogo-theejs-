import * as THREE from 'three';
import { World } from './world.js';
import { Player, STAND_HEIGHT } from './player.js';
import { Input, isTouchDevice } from './input.js';
import { CameraRig } from './cameraRig.js';
import { Character, FP_HIDDEN_LAYER, isFirearm, ITEMS } from './character.js';
import { makeBolt } from './weapons.js';
import { GameAudio } from './audio.js';
import { Effects } from './effects.js';
import { Flashlight } from './flashlight.js';
import { PropSystem } from './physics.js';
import { TrainingDummies } from './dummies.js';
import { loadPlayerModel, loadKnifeModel } from './playerModel.js';
import { buttonHTML } from './icons.js';
import { applyPhotoAssets } from './photoAssets.js';
import { MocapLibrary } from './mocap.js';

// ---------- renderizador ----------
const container = document.getElementById('game');
// antisserrilhado (MSAA): escolhido nas configurações; muda só recriando o contexto (recarrega)
const savedAA = (() => {
  try { return JSON.parse(localStorage.getItem('survival-settings') || '{}').antialias ?? !isTouchDevice; } catch { return !isTouchDevice; }
})();
const renderer = new THREE.WebGLRenderer({ antialias: savedAA, powerPreference: 'high-performance' });
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 0.95;
renderer.autoClear = false;
container.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.04, 600);
camera.rotation.order = 'YXZ';
scene.add(camera);

// ---------- módulos ----------
const quality = isTouchDevice ? 'low' : 'high';
const world = new World(scene, renderer, { quality });
// a sombra do sol também enxerga as partes do corpo escondidas da câmera em 1ª pessoa
world.sun.shadow.camera.layers.enable(FP_HIDDEN_LAYER);
const effects = new Effects(scene, quality);
world.firePositions.forEach((p) => effects.addFire(p));
// cidades queimando no horizonte
effects.addPlume(new THREE.Vector3(260, 10, -230), 1.6);
effects.addPlume(new THREE.Vector3(-300, 0, 180), 2.2);
const input = new Input(renderer.domElement);
// bonecos de treino (estopa e palha) perto do começo e no acampamento: [x, z, giro]
const DUMMY_SPOTS = [[-3.2, 9.5, 0.4], [3.4, 8.6, -0.5], [47.2, -4.6, 2.6]];
const dummies = new TrainingDummies(scene, (x, z) => world.groundHeight(x, z), DUMMY_SPOTS);
const player = new Player(world.octree, world.spawn, world.ladders, {
  waterAt: (x, z) => world.waterAt(x, z),
  doors: [...world.doors, ...dummies.list],
});
// lanterna: a luz sai da lente do modelo na mão do personagem
const flashlight = new Flashlight(scene);
// objetos soltos com física
const props = new PropSystem(scene, world.octree);
props.extraColliders = [...world.doors, ...dummies.list];
for (const p of world.propSpots) props.add(p.type, p.x, p.y, p.z);
const rig = new CameraRig(camera, world.octree);
const character = new Character(scene);
// modelos 3D (personagem e faca); enquanto carregam, fica o corpo procedural
const modelsReady = Promise.allSettled([
  applyPhotoAssets(world, renderer, { quality }),
  new MocapLibrary().load().then((lib) => { character.mocap = lib; }),
  loadPlayerModel(character, 'models/carl.glb'),
  loadKnifeModel('models/faca.glb').then((m) => character.setKnifeModel(m)),
]).then((r) => r.forEach((x) => x.status === 'rejected' && console.warn('modelo não carregou:', x.reason)));
const audio = new GameAudio();
audio.preload(); // sons gravados (decodificados no primeiro toque)
props.onImpact = (kind, strength, pos) => audio.impact(kind, strength, pos);


// ---------- UI ----------
const $ = (id) => document.getElementById(id);
const ui = {
  menu: $('menu'), play: $('play-btn'), loading: $('loading'), hud: $('hud'), touch: $('touch-ui'),
  health: $('health-fill'), state: $('state-label'), fps: $('fps'),
  flash: $('damage-flash'), hurt: $('vignette-hurt'), crosshair: $('crosshair'),
  hint: $('hint'), compass: $('compass-strip'), underwater: $('underwater'), useBtn: $('btn-use'),
  equip: $('equip-label'), attackBtn: $('btn-attack'), swapBtn: $('btn-swap'), aimBtn: $('btn-aim'), reloadBtn: $('btn-reload'),
  ammo: $('ammo'), ammoLoaded: $('ammo-loaded'), ammoReserve: $('ammo-reserve'), ammoKind: $('ammo-kind'), toast: $('toast'), weaponBar: $('weapon-bar'),
  btnSize: $('btn-size'), btnSizeVal: $('btn-size-val'), haptics: $('haptics'),
  death: $('death'), deathReason: $('death-reason'), respawn: $('respawn-btn'),
  sens: $('sens'), sensVal: $('sens-val'), fov: $('fov'), fovVal: $('fov-val'),
  volume: $('volume'), volumeVal: $('volume-val'), quality: $('quality'),
  invert: $('invert-y'), headbob: $('headbob'), showFps: $('show-fps'), antialias: $('antialias'),
};

// ---------- qualidade gráfica ----------
const QUALITY = {
  low:    { maxRatio: 0.9,  shadows: false, shadowSize: 512,  shadowType: THREE.BasicShadowMap, grass: 0.45 },
  medium: { maxRatio: 1.25, shadows: true,  shadowSize: 1024, shadowType: THREE.PCFShadowMap,  grass: 0.75 },
  high:   { maxRatio: 2,    shadows: true,  shadowSize: 2048, shadowType: THREE.PCFSoftShadowMap, grass: 1 },
};
let qualityMode = 'auto';
let activeQuality = null;
let pixelRatio = 1;

function applyQuality(level) {
  const q = QUALITY[level];
  const shadowChanged = activeQuality === null || QUALITY[activeQuality].shadows !== q.shadows ||
    QUALITY[activeQuality].shadowType !== q.shadowType;
  activeQuality = level;
  pixelRatio = Math.min(window.devicePixelRatio || 1, q.maxRatio);
  renderer.setPixelRatio(pixelRatio);
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.shadowMap.enabled = q.shadows;
  renderer.shadowMap.type = q.shadowType;
  world.setShadowMapSize(q.shadowSize);
  world.setGrassDensity(q.grass);
  // sombras (e o anel projetado) da lanterna só em qualidade média/alta
  const flashChanged = flashlight.setShadows(q.shadows);
  if (shadowChanged || flashChanged) {
    // materiais precisam recompilar quando as sombras ligam/desligam
    scene.traverse((o) => {
      if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach((m) => { m.needsUpdate = true; });
    });
  }
}

// modo automático: ajusta a resolução conforme o FPS (essencial em celulares fracos)
const autoRes = { timer: 0, frames: 0, scale: 1, cooldown: 0 };
function updateAutoQuality(dt) {
  if (qualityMode !== 'auto' || !playing) return;
  autoRes.timer += dt;
  autoRes.frames++;
  autoRes.cooldown -= dt;
  if (autoRes.timer < 2) return;
  const fps = autoRes.frames / autoRes.timer;
  autoRes.timer = 0;
  autoRes.frames = 0;
  if (autoRes.cooldown > 0) return;
  const base = Math.min(window.devicePixelRatio || 1, QUALITY[activeQuality].maxRatio);
  if (fps < 40 && autoRes.scale > 0.5) {
    autoRes.scale = Math.max(0.5, autoRes.scale - 0.15);
    if (autoRes.scale <= 0.6 && activeQuality !== 'low') {
      applyQuality(activeQuality === 'high' ? 'medium' : 'low');
      autoRes.scale = 0.85;
    }
  } else if (fps > 57 && autoRes.scale < 1) {
    autoRes.scale = Math.min(1, autoRes.scale + 0.1);
  } else {
    return;
  }
  autoRes.cooldown = 3;
  renderer.setPixelRatio(Math.max(0.5, base * autoRes.scale));
}

// ---------- configurações ----------
function loadSettings() {
  try {
    const s = JSON.parse(localStorage.getItem('survival-settings') || '{}');
    if (s.sens) ui.sens.value = s.sens;
    if (s.fov) ui.fov.value = s.fov;
    if (s.volume !== undefined) ui.volume.value = s.volume;
    if (s.quality) ui.quality.value = s.quality;
    ui.invert.checked = !!s.invert;
    ui.headbob.checked = s.headbob !== false;
    ui.showFps.checked = !!s.showFps;
    if (s.btnSize) ui.btnSize.value = s.btnSize;
    ui.haptics.checked = s.haptics !== false;
  } catch { /* sem armazenamento disponível */ }
  ui.antialias.checked = savedAA;
  applySettings();
}

function applySettings() {
  input.sensitivity = parseFloat(ui.sens.value);
  input.invertY = ui.invert.checked;
  rig.baseFov = parseFloat(ui.fov.value);
  rig.bobEnabled = ui.headbob.checked;
  audio.setVolume(parseFloat(ui.volume.value));
  ui.sensVal.textContent = input.sensitivity.toFixed(1);
  ui.fovVal.textContent = ui.fov.value;
  ui.volumeVal.textContent = Math.round(parseFloat(ui.volume.value) * 100);
  ui.fps.classList.toggle('hidden-fps', !ui.showFps.checked);
  document.documentElement.style.setProperty('--btn-scale', ui.btnSize.value);
  ui.btnSizeVal.textContent = Math.round(parseFloat(ui.btnSize.value) * 100);

  if (ui.quality.value !== qualityMode || activeQuality === null) {
    qualityMode = ui.quality.value;
    autoRes.scale = 1;
    applyQuality(qualityMode === 'auto' ? (isTouchDevice ? 'medium' : 'high') : qualityMode);
  }
  try {
    localStorage.setItem('survival-settings', JSON.stringify({
      sens: ui.sens.value, fov: ui.fov.value, volume: ui.volume.value, quality: ui.quality.value,
      invert: ui.invert.checked, headbob: ui.headbob.checked, showFps: ui.showFps.checked,
      btnSize: ui.btnSize.value, haptics: ui.haptics.checked, antialias: ui.antialias.checked,
    }));
  } catch { /* ignore */ }
}
for (const el of [ui.sens, ui.fov, ui.volume, ui.btnSize]) el.addEventListener('input', applySettings);
for (const el of [ui.quality, ui.invert, ui.headbob, ui.showFps, ui.haptics]) el.addEventListener('change', applySettings);
ui.antialias.addEventListener('change', () => {
  applySettings();
  // só recarrega se a escolha ficou salva (senão voltaria igual)
  let saved = null;
  try { saved = JSON.parse(localStorage.getItem('survival-settings') || '{}').antialias; } catch { /* sem armazenamento */ }
  if (saved === ui.antialias.checked && saved !== savedAA) location.reload();
});

/** Vibração curta no celular (pouso, dano, escalada). */
function haptic(ms) {
  if (isTouchDevice && ui.haptics.checked) navigator.vibrate?.(ms);
}

// ---------- menu / pausa ----------
let playing = false;
let started = false;

function startGame() {
  audio.unlock();
  if (isTouchDevice) {
    const el = document.documentElement;
    try {
      const fs = el.requestFullscreen?.({ navigationUI: 'hide' }) ?? el.webkitRequestFullscreen?.();
      Promise.resolve(fs)
        .then(() => screen.orientation?.lock?.('landscape'))
        .catch(() => { /* navegador não permite: tudo bem */ });
    } catch { /* idem */ }
    resume();
  } else if (input.pointerLockFailed || !renderer.domElement.requestPointerLock) {
    input.pointerLockFailed = true;
    resume();
  } else {
    try {
      const req = renderer.domElement.requestPointerLock();
      req?.catch?.(() => document.dispatchEvent(new Event('pointerlockerror')));
    } catch {
      document.dispatchEvent(new Event('pointerlockerror'));
    }
  }
}

function resume() {
  if (player.dead) return;
  playing = true;
  started = true;
  input.enabled = true;
  input.reset();
  clock.getDelta();
  ui.menu.classList.add('hidden');
  ui.hud.classList.remove('hidden');
  ui.touch.classList.toggle('hidden', !isTouchDevice);
  document.body.classList.add('playing');
  audio.unlock();
}

function pause() {
  if (!playing) return;
  playing = false;
  input.enabled = false;
  input.reset();
  ui.menu.classList.remove('hidden');
  ui.touch.classList.add('hidden');
  ui.play.textContent = 'CONTINUAR';
  document.body.classList.remove('playing');
  audio.suspend();
}

ui.play.addEventListener('click', startGame);
input.onPauseRequest = pause;
input.onGamepadStart = () => {
  // controle não conta como gesto para o pointer lock: entra direto
  if (player.dead) { respawn(); return; }
  if (!playing && !ui.menu.classList.contains('hidden')) { audio.unlock(); resume(); }
};

document.addEventListener('pointerlockchange', () => {
  if (document.pointerLockElement === renderer.domElement) resume();
  else if (!isTouchDevice && !input.pointerLockFailed && !player.dead) pause();
});
document.addEventListener('pointerlockerror', () => {
  // alguns navegadores bloqueiam o pointer lock: joga mesmo assim, olhando com clique e arrastar
  input.pointerLockFailed = true;
  resume();
});
document.addEventListener('visibilitychange', () => { if (document.hidden) pause(); });

// ---------- morte ----------
let deathReason = '';
function showDeath() {
  playing = false;
  input.enabled = false;
  input.reset();
  ui.deathReason.textContent = deathReason || 'Você não resistiu aos ferimentos.';
  ui.touch.classList.add('hidden');
  setTimeout(() => {
    ui.death.classList.remove('hidden');
    if (document.pointerLockElement) document.exitPointerLock();
    ui.respawn.focus();
  }, 1400);
}
function respawn() {
  ui.death.classList.add('hidden');
  player.respawn();
  lastHealth = player.health;
  startGame();
}
ui.respawn.addEventListener('click', respawn);

// ---------- bússola ----------
const COMPASS_PX_PER_DEG = 3;
(function buildCompass() {
  const names = { 0: 'N', 45: 'NE', 90: 'L', 135: 'SE', 180: 'S', 225: 'SO', 270: 'O', 315: 'NO' };
  let html = '';
  // três voltas para poder rolar sem "buraco" nas bordas
  for (let d = -360; d <= 720; d += 15) {
    const deg = ((d % 360) + 360) % 360;
    const label = names[deg] ?? (deg % 30 === 0 ? String(deg) : '·');
    const cls = names[deg] ? (deg === 0 ? 'major north' : 'major') : '';
    html += `<span class="${cls}" style="left:${(d + 360) * COMPASS_PX_PER_DEG}px">${label}</span>`;
  }
  ui.compass.innerHTML = html;
})();
function updateCompass() {
  // norte = -Z; yaw positivo gira para a esquerda
  const heading = ((-THREE.MathUtils.radToDeg(player.yaw) % 360) + 360) % 360;
  const width = ui.compass.parentElement.clientWidth;
  ui.compass.style.transform = `translateX(${width / 2 - (heading + 360) * COMPASS_PX_PER_DEG}px)`;
}

function onResize() {
  const w = window.innerWidth, h = window.innerHeight;
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  renderer.setSize(w, h);
}
window.addEventListener('resize', onResize);
window.addEventListener('orientationchange', () => setTimeout(onResize, 200));

// ---------- loop ----------
const clock = new THREE.Clock();
let elapsed = 0;
let fpsTimer = 0, fpsFrames = 0;
let flashOn = false;
let lastHealth = player.health;
let ambientTimer = 0;
let indoor = 0;
const _eye = new THREE.Vector3();
const _up = new THREE.Ray(new THREE.Vector3(), new THREE.Vector3(0, 1, 0));

function handleActions() {
  if (input.wasPressed('view')) {
    rig.toggleView();
    character.setFirstPerson(!rig.thirdPerson);
    audio.click();
  }
  if (input.wasPressed('light')) {
    flashOn = flashlight.toggle();
    $('btn-light')?.classList.toggle('on', flashOn);
    audio.click();
  }
  if (input.wasPressed('use') && useTarget) {
    if (useTarget.isPickup) {
      pickUp(useTarget);
    } else {
      const door = useTarget;
      const what = door.toggle(player.feetPosition);
      if (what === 'open') audio.doorOpen(door.center);
    }
    haptic(10);
  }
  // mãos livres / faca / revólver / espingarda / besta / taco (teclas 1–6, rodinha ou botão de trocar)
  let wantEquip = null;
  for (const it of ITEMS) if (input.wasPressed('equip_' + it)) wantEquip = it;
  const cur = ITEMS.indexOf(character.equip);
  if (input.wasPressed('swapItem')) wantEquip = ITEMS[(cur + 1) % ITEMS.length];
  if (input.wasPressed('swapPrev')) wantEquip = ITEMS[(cur + ITEMS.length - 1) % ITEMS.length];
  const from = character.equip;
  if (wantEquip && character.setEquip(wantEquip)) equipSounds(from, wantEquip);
  // armas de fogo: mirar, atirar, recarregar
  const gunOut = isFirearm(character.swap >= 0 ? character.swapTo : character.equip);
  input.gunMode = gunOut;
  character.aiming = gunOut && input.aimHeld && !player.sprinting;
  player.aiming = gunOut && character.b.aim > 0.4;
  if (gunOut) {
    attackHold = -1;
    const busy = player.isClimbing || player.onLadder || player.swimming || player.isHanging || player.sliding || player.rolling || player.dead;
    if (input.wasPressed('reload') && !busy) character.reload();
    if (input.wasPressed('attack') && !busy) shoot();
    return;
  }
  handleCombat();
}

/** Sons de guardar o item atual e sacar o novo (no ritmo da animação). */
function equipSounds(from, to) {
  const long = (it) => it === 'shotgun' || it === 'crossbow';
  const T = 0.5 * Math.max({ hands: 0.45, knife: 0.8, gun: 0.95, bat: 0.9, shotgun: 1.15, crossbow: 1.2 }[from], { hands: 0.45, knife: 0.8, gun: 0.95, bat: 0.9, shotgun: 1.15, crossbow: 1.2 }[to]) * 1000;
  const put = (it, at) => setTimeout(() => {
    if (it === 'knife') audio.sheathe(); else if (it === 'gun') audio.holster(false); else if (long(it)) audio.sling(false); else if (it === 'bat') audio.sling(false);
  }, at);
  const take = (it, at) => setTimeout(() => {
    if (it === 'knife') audio.unsheath(); else if (it === 'gun') audio.holster(true); else if (long(it) || it === 'bat') audio.sling(true);
  }, at);
  if (from !== 'hands') put(from, T * 0.55);
  if (to !== 'hands') take(to, T * (from === 'hands' ? 0.45 : 0.95));
  if (!isFirearm(to)) input.clearTouchAim();
}

// ---------- armas de fogo ----------
const _shotDir = new THREE.Vector3(), _hitN = new THREE.Vector3(), _tmp = new THREE.Vector3();
const holes = [];
let holeIdx = 0;
const holeGeo = new THREE.CircleGeometry(0.012, 8);
const holeMat = new THREE.MeshBasicMaterial({ color: 0x0c0a08, transparent: true, opacity: 0.9, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -3 });
/** Furo de bala numa superfície (os 50 mais recentes ficam). */
function bulletHole(point, normal) {
  let m = holes[holeIdx];
  if (!m) { m = new THREE.Mesh(holeGeo, holeMat); holes.push(m); scene.add(m); }
  holeIdx = (holeIdx + 1) % 50;
  m.position.copy(point).addScaledVector(normal, 0.006);
  m.lookAt(_tmp.copy(m.position).add(normal));
  m.scale.setScalar(0.7 + Math.random() * 0.6);
}
let hitMarkerT = 0;
function hitMarker() {
  hitMarkerT = 0.18;
  ui.crosshair.classList.add('hit');
}

function shoot() {
  const kind = character.equip;
  const r = character.fireGun();
  if (r === 'dry') {
    audio.dryFire();
    // vazia: recarrega sozinha se tiver munição
    if (character.gun.reserve > 0) character.reload();
    return;
  }
  if (r !== 'fired') return;
  const aim = character.b.aim;
  // lanterna na outra mão (só no revólver): atira com uma mão só, recuo maior e bem menos precisão
  const oneHand = character._heldFlash && kind === 'gun' ? 1 : 0;
  // dispersão: precisa mirar para acertar longe
  const spread = lerp(kind === 'gun' ? 0.045 : 0.035, 0.0035, aim) * (1 + oneHand * 2.2) + oneHand * 0.012 +
    Math.min(player.horizontalSpeed, 6) * 0.006 * (1 - aim * 0.6) + (player.onFloor ? 0 : 0.05);
  const aimDir = (extra) => {
    camera.getWorldDirection(_shotDir);
    const u = Math.random() * Math.PI * 2, rr = Math.sqrt(Math.random()) * extra;
    _tmp.set(Math.cos(u) * rr, Math.sin(u) * rr, 0).applyQuaternion(camera.quaternion);
    return _shotDir.add(_tmp).normalize();
  };
  if (kind === 'crossbow') {
    audio.crossbowShot();
    haptic(20);
    rig.kick(0.012, (Math.random() - 0.5) * 0.006);
    launchBolt(aimDir(spread * 0.6));
    return;
  }
  const shotgun = kind === 'shotgun';
  audio.gunshot(indoor, shotgun);
  haptic(shotgun ? 70 : 45);
  rig.kick(((shotgun ? 0.1 : 0.05) + Math.random() * 0.02 - aim * 0.015) * (1 + oneHand * 0.5), (Math.random() - 0.5) * 0.02 * (1 + oneHand));
  rig.shake = Math.max(rig.shake, shotgun ? 0.28 : 0.12);
  player.pitch = Math.min(1.45, player.pitch + (shotgun ? 0.03 : 0.012) + Math.random() * 0.008); // o cano sobe um pouco
  // fumaça na boca do cano
  const mz = character.gun.muzzleWorld;
  for (let i = 0; i < (shotgun ? 9 : 4); i++) {
    effects.dust.emit(mz.x, mz.y, mz.z, (Math.random() - 0.5) * 0.3, 0.2 + Math.random() * 0.3, (Math.random() - 0.5) * 0.3,
      { life: shotgun ? 1.8 : 1.2, size: shotgun ? 0.07 : 0.05, grow: 0.35, color: [0.75, 0.74, 0.72], alpha: 0.25, drag: 2.5, gravity: -0.3 });
  }
  if (!shotgun) { bulletImpact(camera.position, aimDir(spread)); return; }
  // calibre 12: nove bagos de chumbo grosso num cone (mirar fecha um pouco o cone)
  const base = aimDir(spread * 0.5).clone();
  const cone = lerp(0.06, 0.042, aim);
  for (let i = 0; i < 9; i++) {
    const u = (i / 9) * Math.PI * 2 + Math.random() * 0.6, rr = (i === 0 ? 0 : 0.35 + Math.random() * 0.65) * cone;
    _tmp.set(Math.cos(u) * rr, Math.sin(u) * rr, 0).applyQuaternion(camera.quaternion);
    bulletImpact(camera.position, _pellet.copy(base).add(_tmp).normalize(), { power: 2.6, quiet: i > 1, range: 70 });
  }
}
const _pellet = new THREE.Vector3();

// ---------- virotes da besta: voam com gravidade, cravam e podem ser recolhidos ----------
const bolts = [];
const BOLT_SPEED = 85, BOLT_TIP = 0.23;
const _bv = new THREE.Vector3(), _bq = new THREE.Vector3(0, 0, -1);
function launchBolt(dir) {
  // sai da besta e vai para onde a mira (centro da tela) aponta
  const start = character.gun.muzzleWorld.clone();
  _ray.set(camera.position, dir);
  const wall = world.octree.rayIntersect(_ray);
  const target = camera.position.clone().addScaledVector(dir, Math.max(3, Math.min(wall ? wall.distance : 200, 200)));
  const v = target.sub(start).normalize().multiplyScalar(BOLT_SPEED);
  const m = makeBolt();
  m.position.copy(start);
  m.quaternion.setFromUnitVectors(_bq, _bv.copy(v).normalize());
  scene.add(m);
  bolts.push({ m, v, life: 8, falling: false });
}
function updateBolts(dt) {
  for (let i = bolts.length - 1; i >= 0; i--) {
    const b = bolts[i];
    b.life -= dt;
    const step = b.v.length() * dt;
    _bv.copy(b.v).normalize();
    raycaster.set(b.m.position, _bv);
    raycaster.far = step + BOLT_TIP;
    _ray.set(b.m.position, _bv);
    const wall = world.octree.rayIntersect(_ray);
    let best = wall && wall.distance <= raycaster.far ? { kind: 'world', d: wall.distance, point: wall.position } : null;
    const dm = b.falling ? null : dummies.raycast(raycaster);
    if (dm && (!best || dm.distance < best.d)) best = { kind: 'dummy', d: dm.distance, point: dm.point };
    const ph = raycaster.intersectObjects(props.meshes, true)[0];
    if (ph && (!best || ph.distance < best.d)) best = { kind: 'prop', d: ph.distance, point: ph.point };
    const dh = raycaster.intersectObjects(doorSlabs, false)[0];
    if (dh && (!best || dh.distance < best.d)) best = { kind: 'door', d: dh.distance, point: dh.point, obj: dh.object };
    if (best) {
      boltHit(b, best, wall, dm);
      if (b.stuck) bolts.splice(i, 1);
      continue;
    }
    b.m.position.addScaledVector(b.v, dt);
    b.v.y -= 9.8 * dt;
    if (b.falling) b.m.rotateX(dt * 9);
    else b.m.quaternion.setFromUnitVectors(_bq, _bv.copy(b.v).normalize());
    if (b.life <= 0 || b.m.position.y < -40) { b.m.removeFromParent(); bolts.splice(i, 1); }
  }
}
function boltHit(b, hit, wall, dm) {
  const dir = _bv;
  if (b.falling) {
    // caiu: fica deitado onde parou
    b.m.position.copy(hit.point);
    b.m.position.y += 0.012;
    b.m.rotation.set(0, Math.random() * Math.PI * 2, 0);
    makeBoltPickup(b.m);
    b.stuck = true;
    return;
  }
  let surface = 'grass', stick = true, depth = 0.08;
  if (hit.kind === 'dummy') {
    dummies.hit(dm, dir, 9, { bullet: true });
    surface = 'sack'; depth = 0.12;
    hitMarker();
    for (let k = 0; k < 8; k++) {
      effects.dust.emit(dm.point.x, dm.point.y, dm.point.z, dir.x * 1.5 + (Math.random() - 0.5) * 1.5, Math.random() * 1.2, dir.z * 1.5 + (Math.random() - 0.5) * 1.5,
        { life: 0.9, size: 0.022, grow: 0, color: STRAW, alpha: 0.95, drag: 1.5, gravity: 5 });
    }
  } else if (hit.kind === 'prop') {
    raycaster.far = 2;
    const res = props.hit(raycaster, 8);
    if (res) { audio.impact(res.body.type.sound, 0.8, res.point); hitMarker(); }
    stick = false;
  } else if (hit.kind === 'door') {
    surface = 'wood'; depth = 0.1;
  } else {
    const surfHit = raycaster.intersectObjects(world.surfaceMeshes, false)[0];
    surface = surfHit && surfHit.distance < wall.distance + 0.05 ? surfHit.object.userData.surface : 'grass';
    if (surface === 'metal' || surface === 'concrete') stick = false;
    if (surface === 'grass') depth = 0.14;
  }
  audio.boltHit(surface, hit.point);
  if (!stick) {
    // ricocheteia e cai
    effects.puff(hit.point, 2, 0.3, DUST[surface] ?? DUST.grass);
    if (surface === 'metal') for (let k = 0; k < 6; k++) effects.glow.emit(hit.point.x, hit.point.y, hit.point.z, (Math.random() - 0.5) * 3, Math.random() * 2, (Math.random() - 0.5) * 3, { life: 0.3, size: 0.025, grow: -0.05, color: SPARK, alpha: 1, drag: 1, gravity: 9 });
    b.m.position.copy(hit.point).addScaledVector(dir, -0.25);
    b.v.multiplyScalar(-0.12).add(_tmp.set((Math.random() - 0.5) * 2, 1.5, (Math.random() - 0.5) * 2));
    b.falling = true;
    return;
  }
  // crava: a ponta entra um pouco e a haste fica para fora, tremendo
  b.m.position.copy(hit.point).addScaledVector(dir, depth - BOLT_TIP);
  b.m.quaternion.setFromUnitVectors(_bq, dir);
  if (hit.kind === 'dummy') (dm.part === 'head' ? dm.dummy.head : dm.dummy.sack).attach(b.m);
  else if (hit.kind === 'door') hit.obj.attach(b.m);
  if (surface !== 'sack') effects.puff(hit.point, 3, 0.35, DUST[surface] ?? DUST.grass);
  b.m.userData.wobble = 0.35;
  wobbling.push(b.m);
  makeBoltPickup(b.m);
  b.stuck = true;
}
const wobbling = [];
function updateWobble(dt) {
  for (let i = wobbling.length - 1; i >= 0; i--) {
    const m = wobbling[i];
    const w = (m.userData.wobble -= dt);
    if (w <= 0 || !m.parent) { wobbling.splice(i, 1); continue; }
    m.rotateX(Math.sin(w * 90) * w * 0.03);
  }
}
const boltHitGeo = new THREE.BoxGeometry(0.12, 0.12, 0.5);
const hitboxMat = new THREE.MeshBasicMaterial({ visible: false });
function makeBoltPickup(m) {
  const box = new THREE.Mesh(boltHitGeo, hitboxMat);
  m.add(box);
  box.userData.pickup = { isPickup: true, kind: 'bolt', amount: 1, mesh: box, root: m, center: m.position, label: 'RECOLHER O VIROTE' };
  pickups.push(box);
  // os mais antigos somem (no máximo 30 espalhados)
  const stuck = pickups.filter((p) => p.userData.pickup.kind === 'bolt');
  if (stuck.length > 30) { const old = stuck[0]; old.userData.pickup.root.removeFromParent(); pickups.splice(pickups.indexOf(old), 1); }
}

/** A bala acerta o que estiver primeiro no caminho: boneco, objeto, porta ou o mundo. */
function bulletImpact(origin, dir, { power = 7, quiet = false, range = 160 } = {}) {
  const RANGE = range;
  raycaster.set(origin, dir);
  raycaster.far = RANGE;
  // em 3ª pessoa a câmera fica atrás: ignora o que estiver entre ela e o personagem
  const skip = rig.thirdPerson ? rig.currentTpDist * 0.9 : 0;
  _ray.set(origin, dir);
  const wall = world.octree.rayIntersect(_ray);
  let best = wall && wall.distance < RANGE && wall.distance > skip ? { kind: 'world', d: wall.distance } : null;
  const dm = dummies.raycast(raycaster);
  if (dm && dm.distance > skip && (!best || dm.distance < best.d)) best = { kind: 'dummy', d: dm.distance };
  const ph = raycaster.intersectObjects(props.meshes, true)[0];
  if (ph && ph.distance > skip && (!best || ph.distance < best.d)) best = { kind: 'prop', d: ph.distance };
  const dh = raycaster.intersectObjects(doorSlabs, false)[0];
  if (dh && dh.distance > skip && (!best || dh.distance < best.d)) best = { kind: 'door', d: dh.distance };
  if (!best) return;
  if (best.kind === 'dummy') {
    dummies.hit(dm, dir, power, { bullet: true });
    if (!quiet) audio.bulletHit('sack', dm.point);
    for (let i = 0; i < 10; i++) {
      effects.dust.emit(dm.point.x, dm.point.y, dm.point.z, dir.x * 2 + (Math.random() - 0.5) * 2, Math.random() * 1.5, dir.z * 2 + (Math.random() - 0.5) * 2,
        { life: 0.9, size: 0.022, grow: 0, color: STRAW, alpha: 0.95, drag: 1.5, gravity: 5 });
    }
    hitMarker();
  } else if (best.kind === 'prop') {
    const res = props.hit(raycaster, power * 1.3);
    if (res) {
      if (!quiet) audio.impact(res.body.type.sound, 1, res.point);
      effects.puff(res.point, 3, 0.4, [0.5, 0.48, 0.44]);
      hitMarker();
    }
  } else if (best.kind === 'door') {
    _hitN.copy(dh.face.normal).transformDirection(dh.object.matrixWorld);
    if (_hitN.dot(dir) > 0) _hitN.negate();
    bulletHole(dh.point, _hitN);
    if (!quiet) audio.bulletHit('wood', dh.point);
    effects.puff(dh.point, 4, 0.5, DUST.wood);
  } else {
    wall.triangle.getNormal(_hitN);
    if (_hitN.dot(dir) > 0) _hitN.negate();
    const surfHit = raycaster.intersectObjects(world.surfaceMeshes, false)[0];
    const surface = surfHit && surfHit.distance < wall.distance + 0.05 ? surfHit.object.userData.surface : 'grass';
    const p = wall.position;
    if (surface !== 'grass') bulletHole(p, _hitN);
    const ric = (surface === 'metal' || surface === 'concrete') && Math.random() < 0.35;
    if (!quiet) audio.bulletHit(surface, p, ric);
    if (surface === 'metal') {
      for (let i = 0; i < 10; i++) {
        effects.glow.emit(p.x, p.y, p.z, _hitN.x * 2 + (Math.random() - 0.5) * 4, _hitN.y * 2 + Math.random() * 3, _hitN.z * 2 + (Math.random() - 0.5) * 4,
          { life: 0.3, size: 0.025, grow: -0.05, color: SPARK, alpha: 1, drag: 1, gravity: 9 });
      }
    } else {
      // poeira/terra espirrando para fora da superfície
      for (let i = 0; i < 6; i++) {
        effects.dust.emit(p.x, p.y, p.z, _hitN.x * 1.5 + (Math.random() - 0.5), _hitN.y * 1.5 + Math.random(), _hitN.z * 1.5 + (Math.random() - 0.5),
          { life: 0.8, size: 0.06, grow: 0.3, color: DUST[surface] ?? DUST.grass, alpha: 0.5, drag: 3, gravity: 1.5 });
      }
    }
  }
}

// ---------- munição pelo mapa ----------
const pickups = [];
function ammoBoxTexture(bg = '#6e1f15', band = '#d9c38a', text = '.357 MAG') {
  const c = document.createElement('canvas');
  c.width = 128; c.height = 64;
  const g = c.getContext('2d');
  g.fillStyle = bg; g.fillRect(0, 0, 128, 64);
  g.fillStyle = band; g.fillRect(0, 18, 128, 26);
  g.fillStyle = '#2a1a10'; g.font = 'bold 20px sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
  g.fillText(text, 64, 32);
  g.fillStyle = 'rgba(0,0,0,0.25)';
  for (let i = 0; i < 30; i++) g.fillRect(Math.random() * 128, Math.random() * 64, 2 + Math.random() * 6, 1 + Math.random() * 2);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
const AMMO = {
  ammo357: { gun: 'gun', amount: 12, label: 'MUNIÇÃO .357', toast: 'BALAS .357', size: [0.11, 0.045, 0.075], tex: ['#6e1f15', '#d9c38a', '.357 MAG'] },
  shells: { gun: 'shotgun', amount: 6, label: 'CARTUCHOS CAL. 12', toast: 'CARTUCHOS CAL. 12', size: [0.13, 0.07, 0.07], tex: ['#1f4a26', '#e0c070', '12 GA'] },
  bolts: { gun: 'crossbow', amount: 4, label: 'VIROTES', toast: 'VIROTES', bundle: true },
};
{
  const mats = {};
  for (const [k, a] of Object.entries(AMMO)) {
    if (a.bundle) continue;
    mats[k] = [new THREE.MeshStandardMaterial({ map: ammoBoxTexture(...a.tex), roughness: 0.8 }), new THREE.MeshStandardMaterial({ color: a.tex[0], roughness: 0.85 })];
  }
  // espalhadas em alguns lugares onde já há objetos (mesas, prateleiras, chão das casas)
  const spots = world.propSpots.filter((_, i) => i % 3 === 1).slice(0, 12);
  const kinds = ['ammo357', 'shells', 'bolts'];
  spots.push({ x: 1.6, y: world.groundHeight(1.6, 11.2), z: 11.2, kind: 'ammo357' }); // perto do começo, uma de cada
  spots.push({ x: 2.3, y: world.groundHeight(2.3, 11.6), z: 11.6, kind: 'shells' });
  spots.push({ x: 0.9, y: world.groundHeight(0.9, 11.7), z: 11.7, kind: 'bolts' });
  spots.forEach((sp, i) => {
    const kind = sp.kind ?? kinds[i % 3], a = AMMO[kind];
    let m;
    if (a.bundle) {
      // feixe de virotes amarrado
      m = new THREE.Group();
      for (let j = 0; j < 4; j++) { const b = makeBolt(); b.rotation.y = Math.PI / 2; b.position.set(0, 0.006 + (j % 2) * 0.009, (j - 1.5) * 0.009); m.add(b); }
      const box = new THREE.Mesh(new THREE.BoxGeometry(0.46, 0.06, 0.08), hitboxMat);
      m.add(box);
      box.userData.pickup = { isPickup: true, kind, amount: a.amount, mesh: box, root: m, center: m.position, label: `PEGAR ${a.label} (+${a.amount})` };
      pickups.push(box);
      m.position.set(sp.x + 0.25, sp.y + 0.005, sp.z + 0.1);
    } else {
      const [mat, side] = mats[kind];
      m = new THREE.Mesh(new THREE.BoxGeometry(...a.size), [side, side, mat, side, mat, mat]);
      m.position.set(sp.x + 0.28, sp.y + a.size[1] / 2 + 0.002, sp.z + 0.12);
      m.castShadow = true;
      m.userData.pickup = { isPickup: true, kind, amount: a.amount, mesh: m, center: m.position, label: `PEGAR ${a.label} (+${a.amount})` };
      pickups.push(m);
    }
    m.rotation.y = Math.random() * Math.PI;
    scene.add(m);
  });
}
function pickUp(p) {
  const a = AMMO[p.kind] ?? AMMO.bolts;
  character.guns[a.gun].reserve += p.amount;
  (p.root ?? p.mesh).removeFromParent();
  pickups.splice(pickups.indexOf(p.mesh), 1);
  audio.pickup();
  showToast(p.kind === 'bolt' ? '+1 VIROTE' : `+${p.amount} ${a.toast}`);
}
let toastT = 0;
function showToast(text) {
  ui.toast.textContent = text;
  ui.toast.classList.add('show');
  toastT = 1.8;
}

// ---------- combate ----------
// toque rápido = golpe leve (emenda combo); segurar = carrega o golpe forte, soltar = desfere
const CHARGE_DELAY = 0.22, CHARGE_TIME = 0.55;
let attackHold = -1;
let hitStop = 0;
function handleCombat() {
  const busy = player.isClimbing || player.onLadder || player.swimming || player.isHanging || player.sliding || player.rolling || player.dead;
  if (busy) { attackHold = -1; character.setCharge(0); return; }
  if (input.wasPressed('attack')) attackHold = 0;
  if (attackHold < 0) return;
  if (input.attackHeld) {
    attackHold += frameDt;
    if (attackHold > CHARGE_DELAY) character.setCharge(Math.min(1, (attackHold - CHARGE_DELAY) / CHARGE_TIME));
    return;
  }
  if (attackHold > CHARGE_DELAY && character.charge > 0.3) character.attack(true);
  else character.attack(false);
  character.setCharge(0);
  attackHold = -1;
}

/** Golpe começou: som, passo à frente e tranco da câmera. */
function onSwing(m, name) {
  const knife = m.kind === 'knife';
  if (m.kind === 'bat') audio.batSwing(!!m.heavy);
  else if (knife) audio.swing(!!m.heavy, name === 'stab'); else audio.punch(!!m.heavy);
  if (player.onFloor && m.lunge) {
    camera.getWorldDirection(_fwd);
    const h = Math.hypot(_fwd.x, _fwd.z) || 1;
    player.velocity.x += (_fwd.x / h) * m.lunge;
    player.velocity.z += (_fwd.z / h) * m.lunge;
  }
  const side = name === 'backslash' || name === 'hook' || name === 'batBack' ? -1 : 1;
  rig.kick(m.heavy ? -0.03 : -0.008, (m.heavy ? 0.02 : 0.012) * side * (name === 'stab' || name === 'jab' || name === 'cross' || name === 'batJab' ? 0 : 1));
  haptic(m.heavy ? 12 : 6);
}

// ---------- interação e golpes ----------
const raycaster = new THREE.Raycaster();
const _fwd = new THREE.Vector3();
const _camUp = new THREE.Vector3();
const _lens = new THREE.Vector3();
const _aim = new THREE.Vector3();
const _head = new THREE.Vector3();
const _ray = new THREE.Ray();
let useTarget = null;
const doorSlabs = world.doors.map((d) => d.slab);

function cameraRay(far) {
  camera.getWorldDirection(_fwd);
  raycaster.set(camera.position, _fwd);
  raycaster.far = far;
  return raycaster;
}

/** Porta (ou outro objeto usável) na mira, a até 2,4 m. */
function updateUseTarget() {
  useTarget = null;
  if (rig.thirdPerson && !player.onFloor) return;
  const hit = cameraRay(rig.thirdPerson ? 2.4 + rig.currentTpDist : 2.4).intersectObjects(doorSlabs, false)[0];
  if (hit) useTarget = hit.object.userData.door;
  const pk = raycaster.intersectObjects(pickups, false)[0];
  if (pk && (!hit || pk.distance < hit.distance)) useTarget = pk.object.userData.pickup;
}

const SPARK = [1, 0.7, 0.3];
const STRAW = [0.78, 0.68, 0.42];
const _org = new THREE.Vector3();
/** O golpe chegou: acerta boneco, objeto, porta ou parede/chão à frente. */
function strikeHit(m, name) {
  const knife = m.kind === 'knife';
  const bat = m.kind === 'bat';
  const heavy = !!m.heavy;
  camera.getWorldDirection(_fwd);
  // bonecos: alcance a partir dos olhos do corpo, num cone à frente (golpe corpo a corpo é "largo")
  character.getEyeWorldPosition(_org);
  const target = dummies.find(_org, _fwd, m.reach, name === 'stab' || name === 'jab' || name === 'cross' || name === 'batJab' ? 0.45 : bat ? 0.8 : 0.7);
  if (target) {
    const slashAngle = name === 'slash' ? 0.5 : name === 'backslash' ? -0.5 : name === 'overhead' ? 1.4 : 0;
    // o arame farpado também rasga a lona
    dummies.hit(target, _fwd, m.power, { knife: knife || (bat && name !== 'batJab'), slashAngle: bat ? (name === 'batSmash' ? 1.4 : name === 'batBack' ? -0.2 : 0.2) : slashAngle });
    if (bat) audio.batHit('sack', target.point, m.power); else audio.sackHit(target.point, knife, m.power);
    const n = 6 + m.power * 2;
    for (let i = 0; i < n; i++) {
      effects.dust.emit(target.point.x, target.point.y, target.point.z,
        target.normal.x * 1.5 + (Math.random() - 0.5) * 2.5, Math.random() * 2.2, target.normal.z * 1.5 + (Math.random() - 0.5) * 2.5,
        { life: 0.9 + Math.random() * 0.6, size: 0.025, grow: 0, color: STRAW, alpha: 0.95, drag: 1.5, gravity: 5 });
    }
    effects.puff(target.point, 3, 0.35, [0.5, 0.45, 0.35]);
    hitStop = heavy ? 0.11 : 0.055;
    rig.kick(heavy ? 0.035 : 0.012, (Math.random() - 0.5) * 0.015);
    rig.shake = Math.max(rig.shake, heavy ? 0.16 : 0.06);
    character.recoil = heavy ? 0.5 : 0.25;
    haptic(heavy ? 40 : 22);
    return;
  }
  const reach = m.reach + (rig.thirdPerson ? rig.currentTpDist : 0);
  const rc = cameraRay(reach);
  const prop = props.hit(rc, m.power * (knife ? 1.1 : bat ? 1.4 : 1));
  if (prop) {
    audio.impact(prop.body.type.sound, Math.min(1.2, 0.5 + m.power * 0.1), prop.point);
    if (bat) audio.batHit('wood', prop.point, m.power); else if (!knife) audio.punchHit(prop.point);
    effects.puff(prop.point, 3, 0.4, [0.5, 0.48, 0.44]);
    hitStop = 0.04;
    character.recoil = 0.4;
    haptic(15);
    return;
  }
  const door = rc.intersectObjects(doorSlabs, false)[0];
  _ray.set(camera.position, _fwd);
  const wall = world.octree.rayIntersect(_ray);
  if (bat) {
    // taco em parede/porta/chão: pancada que volta pelo cabo
    const onDoor = door && (!wall || door.distance < wall.distance);
    const p = onDoor ? door.point : wall && wall.distance < reach ? wall.position : null;
    if (!p) return;
    const surfHit = onDoor ? null : rc.intersectObjects(world.surfaceMeshes, false)[0];
    const surface = onDoor ? 'wood' : surfHit && surfHit.distance < wall.distance + 0.05 ? surfHit.object.userData.surface : 'grass';
    audio.batHit(surface, p, m.power);
    effects.puff(p, 5, 0.5, DUST[surface] ?? DUST.grass);
    if (surface === 'metal' || surface === 'concrete') {
      for (let i = 0; i < 6; i++) effects.glow.emit(p.x, p.y, p.z, (Math.random() - 0.5) * 3 - _fwd.x * 2, Math.random() * 2, (Math.random() - 0.5) * 3 - _fwd.z * 2, { life: 0.3, size: 0.02, grow: -0.05, color: SPARK, alpha: 1, drag: 1, gravity: 9 });
    }
    character.hitRecoil(1);
    hitStop = heavy ? 0.08 : 0.05;
    rig.shake = Math.max(rig.shake, heavy ? 0.16 : 0.1);
    rig.kick(0.02, 0);
    haptic(30);
    return;
  }
  if (!knife) {
    // soco em parede/porta: baque seco e a mão volta
    const p = door && (!wall || door.distance < wall.distance) ? door.point : wall && wall.distance < reach ? wall.position : null;
    if (!p) return;
    audio.punchHit(p, heavy);
    character.hitRecoil(1);
    hitStop = 0.05;
    rig.shake = Math.max(rig.shake, 0.1);
    rig.kick(0.02, 0);
    haptic(25);
    if (heavy) player.health = Math.max(1, player.health - 2); // socar parede com força dói
    return;
  }
  if (door && (!wall || door.distance < wall.distance)) {
    audio.knifeHit('wood', door.point);
    effects.puff(door.point, 4, 0.5, DUST.wood);
  } else if (wall && wall.distance < reach) {
    const surfHit = rc.intersectObjects(world.surfaceMeshes, false)[0];
    const surface = surfHit && surfHit.distance < wall.distance + 0.05 ? surfHit.object.userData.surface : 'grass';
    audio.knifeHit(surface, wall.position);
    if (surface === 'metal') {
      for (let i = 0; i < 8; i++) {
        effects.glow.emit(wall.position.x, wall.position.y, wall.position.z,
          (Math.random() - 0.5) * 4 - _fwd.x * 2, Math.random() * 3, (Math.random() - 0.5) * 4 - _fwd.z * 2,
          { life: 0.35, size: 0.03, grow: -0.05, color: SPARK, alpha: 1, drag: 1, gravity: 9 });
      }
    } else {
      effects.puff(wall.position, 5, 0.5, DUST[surface] ?? DUST.grass);
    }
  } else {
    return; // golpe no ar
  }
  character.hitRecoil(1);
  hitStop = 0.045;
  rig.shake = Math.max(rig.shake, 0.08);
  rig.kick(0.015, 0);
  haptic(15);
}

let breathTimer = 0, breathInhale = false;
const lerpN = (a, b, t) => a + (b - a) * t;
const lerp = THREE.MathUtils.lerp;
const DUST = { grass: [0.45, 0.42, 0.3], concrete: [0.55, 0.53, 0.5], wood: [0.5, 0.42, 0.32], metal: [0.5, 0.48, 0.45], water: [0.8, 0.86, 0.88] };

function footSurface() {
  return player.waterDepth > 0.12 ? 'water' : world.surfaceAt(player.feetPosition);
}

/** Respingos na superfície da água. */
function splashAt(x, z, amount, strength) {
  const y = world.waterAt(x, z);
  if (y === -Infinity) return;
  for (let i = 0; i < amount; i++) {
    const a = Math.random() * Math.PI * 2, s = (0.5 + Math.random()) * strength;
    effects.dust.emit(x + Math.cos(a) * 0.3, y + 0.05, z + Math.sin(a) * 0.3,
      Math.cos(a) * s, 1 + Math.random() * 2.5 * strength, Math.sin(a) * s,
      { life: 0.6 + Math.random() * 0.4, size: 0.12, grow: 0.3, color: DUST.water, alpha: 0.6, drag: 1.5, gravity: 7 });
  }
}

function handleEvents(dt) {
  const feet = player.feetPosition;
  for (const e of player.events) {
    switch (e.type) {
      case 'step': {
        const surface = footSurface();
        audio.step(surface, e.run, e.crouch, e.speed);
        if (surface === 'water') splashAt(feet.x, feet.z, 3, 0.4);
        else if (e.run) effects.puff(feet, 2, 0.5, DUST[surface]);
        break;
      }
      case 'splash':
        audio.splash(Math.min(1, 0.3 + e.speed / 12));
        splashAt(feet.x, feet.z, 10 + Math.min(20, e.speed * 2), Math.min(1.5, 0.5 + e.speed / 10));
        haptic(30);
        break;
      case 'swimStroke':
        audio.swimStroke(e.under);
        if (!e.under) splashAt(feet.x, feet.z, 3, 0.3);
        break;
      case 'stepUp': audio.step(footSurface(), false, true); break;
      case 'jump': audio.jump(); break;
      case 'land': {
        const surface = footSurface();
        if (e.speed > 3) audio.land(e.speed, surface);
        if (e.speed > 6) { effects.puff(feet, Math.min(16, Math.round(e.speed)), Math.min(2, e.speed / 8), DUST[surface]); haptic(25); }
        break;
      }
      case 'stepover': case 'speedvault': case 'mantle': audio.climb(false); effects.puff(feet, 4, 0.5); haptic(12); break;
      case 'climb': case 'pullup': audio.climb(true); effects.puff(feet, 5, 0.6); haptic(15); break;
      case 'grab': audio.grab(); haptic(25); break;
      case 'drop': audio.step(footSurface(), false, true); break;
      case 'slide': audio.slide(); effects.puff(feet, 10, 1.2, DUST[world.surfaceAt(feet)]); haptic(20); break;
      case 'roll': audio.roll(); effects.puff(feet, 8, 1); break;
      case 'ladder': audio.ladderStep(); break;
      case 'ladderStep': audio.ladderStep(); break;
      case 'damage': audio.hurt(); haptic(80); deathReason = 'A queda foi alta demais.'; break;
      case 'death': showDeath(); haptic(250); break;
    }
  }
  // respiração ofegante depois de correr bastante (só som; não há barra de fôlego)
  breathTimer -= dt;
  if (player.exertion > 0.2 && breathTimer <= 0 && !player.underwater) {
    breathInhale = !breathInhale;
    audio.breathEffort(player.exertion, breathInhale);
    breathTimer = lerpN(0.95, 0.36, player.exertion) * (breathInhale ? 0.8 : 1.2);
  }
  // poeira contínua enquanto desliza
  if (player.sliding && Math.random() < 0.5) effects.puff(feet, 1, 0.6, DUST[world.surfaceAt(feet)]);
}

/** Ambiente sonoro: dentro de casa (vento abafado) e perto da fogueira (crepitar). */
function updateAmbience(dt) {
  ambientTimer -= dt;
  if (ambientTimer <= 0) {
    ambientTimer = 0.3;
    player.getEyePosition(_eye);
    _up.origin.copy(_eye);
    const roof = world.octree.rayIntersect(_up);
    indoor = roof && roof.distance < 5 ? 1 : 0;
  }
  let fireDist = Infinity;
  for (const f of world.firePositions) fireDist = Math.min(fireDist, player.feetPosition.distanceTo(f));
  audio.update(dt, { indoor, fires: world.firePositions, firePlayerDist: fireDist, underwater, health: player.health });
}

// ---------- debaixo d'água ----------
let underwater = false;
const fogNormal = { color: scene.fog.color.clone(), near: scene.fog.near, far: scene.fog.far };
const fogWater = new THREE.Color(0x1d3a38);
const skyBackground = scene.background;
function updateUnderwater() {
  const wy = world.waterAt(camera.position.x, camera.position.z);
  const now = camera.position.y < wy - 0.02;
  if (now !== underwater) {
    underwater = now;
    ui.underwater.classList.toggle('hidden', !underwater);
    // debaixo d'água: neblina esverdeada curta e sem céu (só a superfície vista de baixo)
    world.sky.visible = !underwater;
    if (underwater) { scene.fog.color.copy(fogWater); scene.fog.near = 0.5; scene.fog.far = 16; scene.background = fogWater; }
    else { scene.fog.color.copy(fogNormal.color); scene.fog.near = fogNormal.near; scene.fog.far = fogNormal.far; scene.background = skyBackground; }
  }
}

// granulado de filme: um canvas de ruído gerado uma vez, esticado e tremendo via CSS
{
  const grain = document.getElementById('grain');
  if (grain) {
    const c = document.createElement('canvas');
    c.width = 480; c.height = 300;
    const g = c.getContext('2d'), img = g.createImageData(c.width, c.height);
    for (let i = 0; i < img.data.length; i += 4) { const v = Math.random() * 255; img.data[i] = img.data[i + 1] = img.data[i + 2] = v; img.data[i + 3] = 255; }
    g.putImageData(img, 0, 0);
    grain.appendChild(c);
  }
}
let lastEquipIcon = '';
const ITEM_NAMES = { hands: 'MÃOS LIVRES', knife: 'FACA', gun: 'REVÓLVER .357', shotgun: 'ESPINGARDA CANO DUPLO', crossbow: 'BESTA', bat: 'TACO COM ARAME FARPADO' };
const ITEM_ICONS = { hands: 'fist', knife: 'knife', gun: 'gun', shotgun: 'shotgun', crossbow: 'crossbow', bat: 'bat' };
// barra de armas: 1–6 no teclado, toque no celular
ui.weaponBar.innerHTML = ITEMS.map((it, i) => `<button class="wslot" data-item="${it}" aria-label="${ITEM_NAMES[it]}"><span class="k">${i + 1}</span>${buttonHTML(ITEM_ICONS[it])}<span class="n"></span></button>`).join('');
ui.weaponBar.addEventListener('pointerdown', (e) => {
  const b = e.target instanceof Element && e.target.closest('.wslot');
  if (!b) return;
  e.preventDefault();
  e.stopPropagation();
  input.pressed.add('equip_' + b.dataset.item);
});
const wbCounts = [...ui.weaponBar.querySelectorAll('.n')];
function updateWeaponBar() {
  ITEMS.forEach((it, i) => {
    const G = character.guns[it];
    const txt = G ? `${G.loaded}/${G.reserve}` : '';
    if (wbCounts[i].textContent !== txt) wbCounts[i].textContent = txt;
  });
}
function updateHud() {
  ui.health.style.width = player.health + '%';
  ui.state.textContent = player.state;
  if (player.health < lastHealth) {
    ui.flash.style.transition = 'none';
    ui.flash.style.opacity = '1';
    requestAnimationFrame(() => { ui.flash.style.transition = 'opacity 0.6s'; ui.flash.style.opacity = '0'; });
  }
  lastHealth = player.health;

  const hurt = player.health < 40 ? (1 - player.health / 40) * (0.75 + Math.sin(elapsed * 4) * 0.25) : 0;
  ui.hurt.style.opacity = hurt.toFixed(2);

  const ledge = player.ledgeAhead, ladder = player.ladderAhead;
  let hint = '';
  if (player.isHanging) {
    hint = isTouchDevice ? 'JOYSTICK ↑ / PULAR — SUBIR · ↓ / AGACHAR — SOLTAR' : 'W / ESPAÇO — SUBIR · A D — DE LADO · S / CTRL — SOLTAR';
  } else if (player.onLadder) {
    hint = `${input.pad.connected ? 'ANALÓGICO' : isTouchDevice ? 'JOYSTICK' : 'W / S'} — SUBIR/DESCER · ${input.pad.connected ? 'A' : isTouchDevice ? 'PULAR' : 'ESPAÇO'} — SOLTAR`;
  } else if (ladder && !player.isClimbing) {
    const key = input.pad.connected ? 'ANALÓGICO ↑' : isTouchDevice ? 'JOYSTICK ↑' : 'W';
    hint = `${key} — ${ladder.fromTop ? 'DESCER A ESCADA' : 'SUBIR A ESCADA'}`;
  } else if (ledge && !player.isClimbing) {
    const key = input.pad.connected ? 'A' : isTouchDevice ? 'PULAR' : 'ESPAÇO';
    const what = { stepover: 'PASSAR POR CIMA', speedvault: 'SALTAR POR CIMA', mantle: 'SUBIR', climb: 'ESCALAR' }[ledge.kind] ?? 'ESCALAR';
    hint = `${key} — ${what}`;
  }
  if (!hint && useTarget) {
    const key = input.pad.connected ? 'X' : isTouchDevice ? 'USAR' : 'F';
    hint = `${key} — ${useTarget.isPickup ? useTarget.label : useTarget.isOpen ? 'FECHAR A PORTA' : 'ABRIR A PORTA'}`;
  } else if (!hint && player.swimming) {
    hint = isTouchDevice ? 'AGACHAR — MERGULHAR · PULAR — SUBIR' : 'CTRL — MERGULHAR · ESPAÇO — SUBIR';
  }
  ui.hint.textContent = hint;
  ui.hint.classList.toggle('hidden', !hint);
  ui.useBtn?.classList.toggle('hidden', !useTarget);
  const eq = character.swap >= 0 ? character.swapTo : character.equip;
  const gunOut = isFirearm(eq);
  ui.equip.textContent = ITEM_NAMES[eq] + (character.reloading ? ' · RECARREGANDO' : '') + (player.walkMode ? ' · ANDANDO DEVAGAR' : '');
  if (eq !== lastEquipIcon) {
    // ícone do botão de ataque = item na mão; o de troca mostra o próximo item
    lastEquipIcon = eq;
    ui.attackBtn.innerHTML = buttonHTML(ITEM_ICONS[eq], gunOut ? 'ATIRAR' : '');
    ui.swapBtn.innerHTML = buttonHTML(ITEM_ICONS[ITEMS[(ITEMS.indexOf(eq) + 1) % ITEMS.length]], 'TROCAR');
    ui.ammoKind.textContent = { gun: '.357', shotgun: 'CAL. 12', crossbow: 'VIROTES' }[eq] ?? '';
    for (const el of ui.weaponBar.children) el.classList.toggle('sel', el.dataset.item === eq);
  }
  updateWeaponBar();
  ui.aimBtn?.classList.toggle('hidden', !gunOut);
  ui.reloadBtn?.classList.toggle('hidden', !gunOut);
  ui.ammo.classList.toggle('hidden', !gunOut);
  if (gunOut) {
    const g = character.guns[eq]; // (durante a troca já mostra a arma que está vindo)
    ui.ammoLoaded.textContent = g.loaded;
    ui.ammoReserve.textContent = g.reserve;
    ui.ammo.classList.toggle('empty', g.loaded === 0);
    if (g.loaded === 0 && g.reserve === 0 && !hint) hint = { gun: 'SEM MUNIÇÃO — PROCURE CAIXAS .357', shotgun: 'SEM CARTUCHOS — PROCURE CAIXAS CAL. 12', crossbow: 'SEM VIROTES — RECOLHA OS QUE ATIROU' }[eq];
    else if (g.loaded === 0 && !character.reloading && !hint) hint = (input.pad.connected ? '↓' : isTouchDevice ? '🔄' : 'R') + ' — RECARREGAR';
    ui.hint.textContent = hint;
    ui.hint.classList.toggle('hidden', !hint);
  }

  // mira se abre com o movimento e no ar (e fecha quando mira com a arma)
  const aim = character.b.aim;
  let spread = 4 + Math.min(player.horizontalSpeed, 8) * 1.3 + (player.onFloor ? 0 : 8);
  if (gunOut) spread = lerp(spread + 6, 2, aim) + (character._heldFlash && eq === 'gun' ? 7 : 0) + (eq === 'shotgun' ? 10 - aim * 4 : 0);
  spread += character.charge * 9; // carregando o golpe forte: a mira abre
  ui.crosshair.style.setProperty('--gap', spread.toFixed(1) + 'px');
  // mirando em 1ª pessoa usa a alça e massa do revólver (sem cruz)
  ui.crosshair.classList.toggle('hide', player.onLadder || player.isClimbing || player.rolling || player.dead || (gunOut && aim > 0.6 && !rig.thirdPerson));
  if (hitMarkerT > 0) { hitMarkerT -= frameDt; if (hitMarkerT <= 0) ui.crosshair.classList.remove('hit'); }
  if (toastT > 0) { toastT -= frameDt; if (toastT <= 0) ui.toast.classList.remove('show'); }
  updateCompass();
}

let frameDt = 0.016;
function frame() {
  requestAnimationFrame(frame);
  let dt = Math.min(clock.getDelta(), 0.05);
  // "hit stop": o mundo quase congela por um instante quando um golpe acerta
  if (hitStop > 0) { hitStop -= dt; dt *= 0.12; }
  frameDt = dt;
  elapsed += dt;

  input.pollGamepad(dt);
  if (playing) {
    updateUseTarget();
    handleActions();
    player.update(dt, input);
    handleEvents(dt);
    input.endFrame();
    updateHud();
    updateAmbience(dt);
  } else if (!started) {
    // tela inicial: câmera girando lentamente
    player.yaw += dt * 0.1;
    player.events.length = 0;
  } else {
    player.events.length = 0;
  }

  for (const d of world.doors) if (d.update(dt, player.collider)) audio.doorClose(d.center);
  props.update(dt, player);

  // braços recolhem perto de paredes (mira do quadro anterior)
  camera.getWorldDirection(_fwd);
  _ray.set(camera.position, _fwd);
  let wallAhead = world.octree.rayIntersect(_ray);
  character.setObstruction(wallAhead && !rig.thirdPerson ? wallAhead.distance : 99);
  // o corpo anima primeiro; a câmera de 1ª pessoa vai nos olhos dele
  character.update(dt, player);
  for (const e of character.events) {
    if (e.type === 'swing') onSwing(e.move, e.name);
    else if (e.type === 'hit' && playing) strikeHit(e.move, e.name);
    else if (e.type === 'cylOpen') audio.cylinderOpen();
    else if (e.type === 'eject') { if (e.weapon === 'shotgun') audio.shellsEject(); else audio.ejectShells(e.count); }
    else if (e.type === 'cylClose') audio.cylinderClose();
    else if (e.type === 'brkOpen') audio.breakOpen();
    else if (e.type === 'brkClose') audio.breakClose();
    else if (e.type === 'stringPull') audio.crossbowCock();
    else if (e.type === 'loadRounds') {
      // speedloader / dois cartuchos / um virote: completa com o que tiver
      const g = character.guns[e.weapon], n = Math.min(g.capacity - g.loaded, g.reserve);
      g.reserve -= n;
      g.setLoaded(g.loaded + n);
      if (e.weapon === 'shotgun') { audio.shellIn(); if (n > 1) audio.shellIn(0.22); } else if (e.weapon === 'crossbow') audio.boltLoad(); else audio.loadRounds();
    }
  }
  for (const G of Object.values(character.guns)) G.update(dt, (x, z) => world.groundHeight(x, z), (p) => audio.shellClink(p));
  updateBolts(dt);
  updateWobble(dt);
  rig.aim = character.b.aim;
  character.events.length = 0;
  dummies.update(dt);
  character.getCameraWorldPosition(_head, _fwd);
  rig.update(dt, player, _head);
  camera.updateMatrixWorld();
  camera.getWorldDirection(_fwd);
  _ray.set(camera.position, _fwd);
  wallAhead = world.octree.rayIntersect(_ray);

  // lanterna: a luz sai da lente da lanterna na mão do corpo e mira no centro da tela
  character.getLensWorldPosition(_lens);
  _aim.copy(camera.position).addScaledVector(_fwd, wallAhead ? Math.max(1.5, Math.min(25, wallAhead.distance)) : 25);
  const lightK = flashlight.update(dt, _lens, _aim, { thirdPerson: rig.thirdPerson });
  character.setFlashlight(flashOn, lightK);

  world.update(player.feetPosition, elapsed);
  effects.update(dt, player.feetPosition, (x, z) => world.groundHeight(x, z), renderer.domElement.height);
  updateUnderwater();
  _camUp.set(0, 1, 0).applyQuaternion(camera.quaternion);
  audio.setListener(camera.position, _fwd, _camUp);


  renderer.clear();
  renderer.render(scene, camera);

  updateAutoQuality(dt);
  fpsFrames++;
  fpsTimer += dt;
  if (fpsTimer >= 0.5) {
    ui.fps.textContent = Math.round(fpsFrames / fpsTimer) + ' FPS';
    fpsFrames = 0;
    fpsTimer = 0;
  }
}

// pronto (espera os modelos 3D)
await modelsReady;
loadSettings();
ui.loading.classList.add('hidden');
ui.play.classList.remove('hidden');
frame();

// para depuração no console
window.game = { player, world, rig, input, character, effects, props, flashlight, renderer, scene, camera, dummies, audio, STAND_HEIGHT };
