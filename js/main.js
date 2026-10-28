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
const lowQuality = isTouchDevice;
const renderer = new THREE.WebGLRenderer({ antialias: !lowQuality, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, lowQuality ? 1.25 : 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = lowQuality ? THREE.PCFShadowMap : THREE.PCFSoftShadowMap;
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
const world = new World(scene, { quality: lowQuality ? 'low' : 'high' });
const input = new Input(renderer.domElement);
const player = new Player(world.octree, world.spawn);
const rig = new CameraRig(camera, world.octree);
const viewModel = new ViewModel();
const character = new Character(scene);
const audio = new GameAudio();

viewModel.setAspect(camera.aspect);

// ---------- UI ----------
const ui = {
  menu: document.getElementById('menu'),
  play: document.getElementById('play-btn'),
  loading: document.getElementById('loading'),
  hud: document.getElementById('hud'),
  touch: document.getElementById('touch-ui'),
  health: document.getElementById('health-fill'),
  stamina: document.getElementById('stamina-fill'),
  state: document.getElementById('state-label'),
  fps: document.getElementById('fps'),
  flash: document.getElementById('damage-flash'),
  sens: document.getElementById('sens'),
  sensVal: document.getElementById('sens-val'),
  invert: document.getElementById('invert-y'),
};

function loadSettings() {
  try {
    const s = JSON.parse(localStorage.getItem('survival-settings') || '{}');
    if (s.sens) ui.sens.value = s.sens;
    ui.invert.checked = !!s.invert;
  } catch { /* sem armazenamento disponível */ }
  applySettings();
}
function applySettings() {
  input.sensitivity = parseFloat(ui.sens.value);
  input.invertY = ui.invert.checked;
  ui.sensVal.textContent = input.sensitivity.toFixed(1);
  try {
    localStorage.setItem('survival-settings', JSON.stringify({ sens: ui.sens.value, invert: ui.invert.checked }));
  } catch { /* ignore */ }
}
ui.sens.addEventListener('input', applySettings);
ui.invert.addEventListener('change', applySettings);
loadSettings();

let playing = false;
let started = false;

function startGame() {
  audio.unlock();
  if (isTouchDevice) {
    const el = document.documentElement;
    const fs = el.requestFullscreen?.({ navigationUI: 'hide' }) ?? el.webkitRequestFullscreen?.();
    Promise.resolve(fs)
      .then(() => screen.orientation?.lock?.('landscape'))
      .catch(() => { /* navegador não permite: tudo bem */ });
    resume();
  } else if (input.pointerLockFailed || !renderer.domElement.requestPointerLock) {
    input.pointerLockFailed = true;
    resume();
  } else {
    const req = renderer.domElement.requestPointerLock();
    req?.catch?.(() => document.dispatchEvent(new Event('pointerlockerror')));
  }
}

function resume() {
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

document.addEventListener('pointerlockchange', () => {
  if (document.pointerLockElement === renderer.domElement) resume();
  else if (!isTouchDevice && !input.pointerLockFailed) pause();
});
document.addEventListener('pointerlockerror', () => {
  // alguns navegadores bloqueiam o pointer lock: joga mesmo assim, olhando com clique e arrastar
  input.pointerLockFailed = true;
  resume();
});
document.addEventListener('visibilitychange', () => { if (document.hidden) pause(); });

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
let fpsTimer = 0, fpsFrames = 0;
let flashOn = false;
let lastHealth = player.health;

function handleActions() {
  if (input.wasPressed('view')) {
    rig.toggleView();
    audio.click();
  }
  if (input.wasPressed('light')) {
    flashOn = !flashOn;
    flashlight.intensity = flashOn ? 60 : 0;
    document.getElementById('btn-light')?.classList.toggle('on', flashOn);
    audio.click();
  }
  if (input.wasPressed('attack') && !player.sprinting) {
    viewModel.attack();
    audio.swing();
  }
}

function handleEvents() {
  for (const e of player.events) {
    if (e.type === 'step') audio.step(e.run, e.crouch);
    else if (e.type === 'jump') audio.jump();
    else if (e.type === 'land' && e.speed > 3) audio.land(e.speed);
  }
}

function updateHud() {
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
}

function frame() {
  requestAnimationFrame(frame);
  const dt = Math.min(clock.getDelta(), 0.05);

  if (playing) {
    handleActions();
    player.update(dt, input);
    handleEvents();
    input.endFrame();
    updateHud();
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
  world.update(player.feetPosition);

  character.root.visible = rig.thirdPerson;
  viewModel.visible = !rig.thirdPerson;

  renderer.clear();
  renderer.render(scene, camera);
  viewModel.render(renderer, camera);

  fpsFrames++;
  fpsTimer += dt;
  if (fpsTimer >= 0.5) {
    ui.fps.textContent = Math.round(fpsFrames / fpsTimer) + ' FPS';
    fpsFrames = 0;
    fpsTimer = 0;
  }
}

// pronto
ui.loading.classList.add('hidden');
ui.play.classList.remove('hidden');
frame();

// para depuração no console
window.game = { player, world, rig, input, STAND_HEIGHT };
