import * as THREE from 'three';
import { World } from './world.js';
import { Player, STAND_HEIGHT } from './player.js';
import { Input, isTouchDevice } from './input.js';
import { CameraRig } from './cameraRig.js';
import { ViewModel } from './viewmodel.js';
import { Character } from './character.js';
import { GameAudio } from './audio.js';

// ---------- renderizador ----------
const container = document.getElementById('game');
const renderer = new THREE.WebGLRenderer({ antialias: !isTouchDevice, powerPreference: 'high-performance' });
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
renderer.autoClear = false;
container.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.05, 600);
camera.rotation.order = 'YXZ';
scene.add(camera);

// lanterna presa à câmera
const flashlight = new THREE.SpotLight(0xfff2d8, 0, 40, Math.PI / 7, 0.45, 1.5);
flashlight.position.set(0.25, -0.2, 0);
flashlight.target.position.set(0, 0, -1);
camera.add(flashlight, flashlight.target);

// ---------- módulos ----------
const world = new World(scene, { quality: isTouchDevice ? 'low' : 'high' });
const input = new Input(renderer.domElement);
const player = new Player(world.octree, world.spawn);
const rig = new CameraRig(camera, world.octree);
const viewModel = new ViewModel();
const character = new Character(scene);
const audio = new GameAudio();

viewModel.setAspect(camera.aspect);

// ---------- UI ----------
const $ = (id) => document.getElementById(id);
const ui = {
  menu: $('menu'), play: $('play-btn'), loading: $('loading'), hud: $('hud'), touch: $('touch-ui'),
  health: $('health-fill'), stamina: $('stamina-fill'), state: $('state-label'), fps: $('fps'),
  flash: $('damage-flash'), exhaust: $('vignette-exhaust'), hurt: $('vignette-hurt'),
  hint: $('hint'), compass: $('compass-strip'),
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
  world.grass.count = Math.floor(world.grass.instanceMatrix.count * q.grass);
  if (shadowChanged) {
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

  if (ui.quality.value !== qualityMode || activeQuality === null) {
    qualityMode = ui.quality.value;
    autoRes.scale = 1;
    applyQuality(qualityMode === 'auto' ? (isTouchDevice ? 'medium' : 'high') : qualityMode);
  }
  try {
    localStorage.setItem('survival-settings', JSON.stringify({
      sens: ui.sens.value, fov: ui.fov.value, volume: ui.volume.value, quality: ui.quality.value,
      invert: ui.invert.checked, headbob: ui.headbob.checked, showFps: ui.showFps.checked,
    }));
  } catch { /* ignore */ }
}
for (const el of [ui.sens, ui.fov, ui.volume]) el.addEventListener('input', applySettings);
for (const el of [ui.quality, ui.invert, ui.headbob, ui.showFps]) el.addEventListener('change', applySettings);

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
  viewModel.setAspect(w / h);
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
let breathTimer = 0;

function handleActions() {
  if (input.wasPressed('view')) {
    rig.toggleView();
    audio.click();
  }
  if (input.wasPressed('light')) {
    flashOn = !flashOn;
    flashlight.intensity = flashOn ? 60 : 0;
    viewModel.setFlashlight(flashOn);
    $('btn-light')?.classList.toggle('on', flashOn);
    audio.click();
  }
  if (input.wasPressed('attack') && !player.sprinting && !player.isClimbing) {
    viewModel.attack();
    audio.swing();
  }
}

function handleEvents(dt) {
  for (const e of player.events) {
    switch (e.type) {
      case 'step': audio.step(world.surfaceAt(player.feetPosition), e.run, e.crouch); break;
      case 'jump': audio.jump(); break;
      case 'land': if (e.speed > 3) audio.land(e.speed, world.surfaceAt(player.feetPosition)); break;
      case 'climb': case 'vault': audio.climb(); break;
      case 'damage': audio.hurt(); deathReason = 'A queda foi alta demais.'; break;
      case 'death': showDeath(); break;
    }
  }
  // respiração ofegante quando o fôlego está baixo
  breathTimer -= dt;
  if (player.stamina < 35 && breathTimer <= 0) {
    audio.breath(player.exhausted ? 1 : 0.5);
    breathTimer = player.exhausted ? 0.55 : 0.8;
  }
}

function updateHud(dt) {
  ui.health.style.width = player.health + '%';
  ui.stamina.style.width = player.stamina + '%';
  ui.stamina.classList.toggle('exhausted', player.exhausted);
  ui.state.textContent = player.state;
  if (player.health < lastHealth) {
    ui.flash.style.transition = 'none';
    ui.flash.style.opacity = '1';
    requestAnimationFrame(() => { ui.flash.style.transition = 'opacity 0.6s'; ui.flash.style.opacity = '0'; });
  }
  lastHealth = player.health;

  ui.exhaust.style.opacity = Math.max(0, (35 - player.stamina) / 35).toFixed(2);
  const hurt = player.health < 40 ? (1 - player.health / 40) * (0.75 + Math.sin(elapsed * 4) * 0.25) : 0;
  ui.hurt.style.opacity = hurt.toFixed(2);

  const ledge = player.ledgeAhead;
  if (ledge && !player.isClimbing) {
    const key = input.pad.connected ? 'A' : isTouchDevice ? 'PULAR' : 'ESPAÇO';
    ui.hint.textContent = `${key} — ${ledge.kind === 'vault' ? 'PULAR OBSTÁCULO' : 'ESCALAR'}`;
    ui.hint.classList.remove('hidden');
  } else {
    ui.hint.classList.add('hidden');
  }
  updateCompass();
}

function frame() {
  requestAnimationFrame(frame);
  const dt = Math.min(clock.getDelta(), 0.05);
  elapsed += dt;

  input.pollGamepad(dt);
  if (playing) {
    handleActions();
    player.update(dt, input);
    handleEvents(dt);
    input.endFrame();
    updateHud(dt);
  } else if (!started) {
    // tela inicial: câmera girando lentamente
    player.yaw += dt * 0.1;
    player.events.length = 0;
  } else {
    player.events.length = 0;
  }

  rig.update(dt, player);
  viewModel.update(dt, player);
  character.update(dt, player, viewModel.isAttacking);
  world.update(player.feetPosition, elapsed);

  character.root.visible = rig.thirdPerson;
  viewModel.visible = !rig.thirdPerson;

  renderer.clear();
  renderer.render(scene, camera);
  viewModel.render(renderer, camera);

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
window.game = { player, world, rig, input, STAND_HEIGHT };
