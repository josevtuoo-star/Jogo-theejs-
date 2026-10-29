import * as THREE from 'three';
import { World } from './world.js';
import { Player, STAND_HEIGHT } from './player.js';
import { Input, isTouchDevice } from './input.js';
import { CameraRig } from './cameraRig.js';
import { Character, FP_HIDDEN_LAYER } from './character.js';
import { GameAudio } from './audio.js';
import { Effects } from './effects.js';
import { Flashlight } from './flashlight.js';
import { PropSystem } from './physics.js';

// ---------- renderizador ----------
const container = document.getElementById('game');
const renderer = new THREE.WebGLRenderer({ antialias: !isTouchDevice, powerPreference: 'high-performance' });
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
const player = new Player(world.octree, world.spawn, world.ladders, {
  waterAt: (x, z) => world.waterAt(x, z),
  doors: world.doors,
});
// lanterna: a luz sai da lente do modelo na mão do personagem
const flashlight = new Flashlight(scene);
// objetos soltos com física
const props = new PropSystem(scene, world.octree);
props.extraColliders = world.doors;
for (const p of world.propSpots) props.add(p.type, p.x, p.y, p.z);
const rig = new CameraRig(camera, world.octree);
const character = new Character(scene);
const audio = new GameAudio();
props.onImpact = (kind, strength, pos) => audio.impact(kind, strength, pos);


// ---------- UI ----------
const $ = (id) => document.getElementById(id);
const ui = {
  menu: $('menu'), play: $('play-btn'), loading: $('loading'), hud: $('hud'), touch: $('touch-ui'),
  health: $('health-fill'), state: $('state-label'), fps: $('fps'),
  flash: $('damage-flash'), hurt: $('vignette-hurt'), crosshair: $('crosshair'),
  hint: $('hint'), compass: $('compass-strip'), underwater: $('underwater'), useBtn: $('btn-use'),
  equip: $('equip-label'), attackBtn: $('btn-attack'),
  btnSize: $('btn-size'), btnSizeVal: $('btn-size-val'), haptics: $('haptics'),
  death: $('death'), deathReason: $('death-reason'), respawn: $('respawn-btn'),
  sens: $('sens'), sensVal: $('sens-val'), fov: $('fov'), fovVal: $('fov-val'),
  volume: $('volume'), volumeVal: $('volume-val'), quality: $('quality'),
  invert: $('invert-y'), headbob: $('headbob'), showFps: $('show-fps'),
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
      btnSize: ui.btnSize.value, haptics: ui.haptics.checked,
    }));
  } catch { /* ignore */ }
}
for (const el of [ui.sens, ui.fov, ui.volume, ui.btnSize]) el.addEventListener('input', applySettings);
for (const el of [ui.quality, ui.invert, ui.headbob, ui.showFps, ui.haptics]) el.addEventListener('change', applySettings);

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
    const door = useTarget;
    const what = door.toggle(player.feetPosition);
    if (what === 'open') audio.doorOpen(door.center);
    haptic(10);
  }
  // mãos livres / faca
  let wantEquip = null;
  if (input.wasPressed('equipHands')) wantEquip = 'hands';
  if (input.wasPressed('equipKnife')) wantEquip = 'knife';
  if (input.wasPressed('swapItem')) wantEquip = character.equip === 'knife' ? 'hands' : 'knife';
  if (wantEquip && character.setEquip(wantEquip)) {
    if (wantEquip === 'knife') setTimeout(() => audio.unsheath(), 180); else setTimeout(() => audio.sheathe(), 200);
  }
  const busy = player.isClimbing || player.onLadder || player.swimming || player.isHanging || player.sliding;
  if (input.wasPressed('attack') && !busy && character.attack()) {
    hitKind = character.attackKind;
    pendingHit = hitKind === 'knife' ? 0.15 : 0.1; // o golpe chega ao alvo no meio do movimento
    if (hitKind === 'knife') audio.swing(); else audio.punch();
  }
}
let hitKind = 'knife';

// ---------- interação e golpes ----------
const raycaster = new THREE.Raycaster();
const _fwd = new THREE.Vector3();
const _camUp = new THREE.Vector3();
const _lens = new THREE.Vector3();
const _aim = new THREE.Vector3();
const _head = new THREE.Vector3();
const _ray = new THREE.Ray();
let useTarget = null;
let pendingHit = -1;
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
}

const SPARK = [1, 0.7, 0.3];
/** Golpe (faca ou soco) acerta o que estiver na frente: objetos, portas ou paredes/chão. */
function knifeHit() {
  const knife = hitKind === 'knife';
  const reach = (knife ? 1.8 : 1.3) + (rig.thirdPerson ? rig.currentTpDist : 0);
  const rc = cameraRay(reach);
  const prop = props.hit(rc, knife ? 4.5 : 3);
  if (prop) {
    audio.impact(prop.body.type.sound, 0.9, prop.point);
    if (!knife) audio.punchHit(prop.point);
    effects.puff(prop.point, 3, 0.4, [0.5, 0.48, 0.44]);
    character.hitRecoil();
    haptic(15);
    return;
  }
  const door = rc.intersectObjects(doorSlabs, false)[0];
  _ray.set(camera.position, _fwd);
  const wall = world.octree.rayIntersect(_ray);
  if (!knife) {
    // soco: só um baque seco na parede/porta
    const p = door && (!wall || door.distance < wall.distance) ? door.point : wall && wall.distance < reach ? wall.position : null;
    if (!p) return;
    audio.punchHit(p);
    character.hitRecoil();
    rig.shake = Math.max(rig.shake, 0.1);
    haptic(20);
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
  character.hitRecoil();
  rig.shake = Math.max(rig.shake, 0.08);
  haptic(15);
}

let breathTimer = 0, breathInhale = false;
const lerpN = (a, b, t) => a + (b - a) * t;
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
    hint = `${key} — ${useTarget.isOpen ? 'FECHAR A PORTA' : 'ABRIR A PORTA'}`;
  } else if (!hint && player.swimming) {
    hint = isTouchDevice ? 'AGACHAR — MERGULHAR · PULAR — SUBIR' : 'CTRL — MERGULHAR · ESPAÇO — SUBIR';
  }
  ui.hint.textContent = hint;
  ui.hint.classList.toggle('hidden', !hint);
  ui.useBtn?.classList.toggle('hidden', !useTarget);
  const eq = character.swap >= 0 ? character.swapTo : character.equip;
  ui.equip.textContent = (eq === 'knife' ? 'FACA' : 'MÃOS LIVRES') + (player.walkMode ? ' · ANDANDO DEVAGAR' : '');
  if (ui.attackBtn) ui.attackBtn.textContent = eq === 'knife' ? '🔪' : '👊';

  // mira se abre com o movimento e no ar
  const spread = 4 + Math.min(player.horizontalSpeed, 8) * 1.3 + (player.onFloor ? 0 : 8);
  ui.crosshair.style.setProperty('--gap', spread.toFixed(1) + 'px');
  ui.crosshair.classList.toggle('hide', player.onLadder || player.isClimbing || player.rolling || player.dead);
  updateCompass();
}

function frame() {
  requestAnimationFrame(frame);
  const dt = Math.min(clock.getDelta(), 0.05);
  elapsed += dt;

  input.pollGamepad(dt);
  if (playing) {
    updateUseTarget();
    handleActions();
    player.update(dt, input);
    handleEvents(dt);
    input.endFrame();
    if (pendingHit >= 0) { pendingHit -= dt; if (pendingHit < 0) knifeHit(); }
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
  character.getEyeWorldPosition(_head);
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

// pronto
loadSettings();
ui.loading.classList.add('hidden');
ui.play.classList.remove('hidden');
frame();

// para depuração no console
window.game = { player, world, rig, input, character, effects, props, flashlight, renderer, scene, camera, STAND_HEIGHT };
