import * as THREE from 'three';

// Efeitos de câmera: balanço da cabeça ao andar, inclinação lateral, espiar (Q/E),
// "tranco" no pouso, FOV maior correndo, escalada, morte e câmera em terceira pessoa.

const SPRINT_FOV_BONUS = 9;

function damp(a, b, lambda, dt) {
  return a + (b - a) * (1 - Math.exp(-lambda * dt));
}

const _eye = new THREE.Vector3();
const _dir = new THREE.Vector3();
const _shoulder = new THREE.Vector3();
const _pivot = new THREE.Vector3();
const _ray = new THREE.Ray();
const _euler = new THREE.Euler(0, 0, 0, 'YXZ');

export class CameraRig {
  constructor(camera, octree) {
    this.camera = camera;
    this.octree = octree;
    this.thirdPerson = false;
    this.tpDistance = 3.2;
    this.currentTpDist = 3.2;

    this.baseFov = 75;
    this.bobEnabled = true;

    this.bobAmount = 0;
    this.roll = 0;
    this.landOffset = 0;
    this.landVel = 0;
    this.shake = 0;
    this.fov = this.baseFov;
    this.deathBlend = 0;
    this.climbPitch = 0;
    this.slideBlend = 0;
    this.ladderBlend = 0;
  }

  toggleView() {
    this.thirdPerson = !this.thirdPerson;
  }

  update(dt, player) {
    for (const e of player.events) {
      if (e.type === 'land') this.landVel -= Math.min(e.speed, 22) * 0.045;
      if (e.type === 'damage') this.shake = 0.35;
      if (e.type === 'climb' || e.type === 'vault') this.landVel -= 0.6;
      if (e.type === 'slide') this.shake = Math.max(this.shake, 0.12);
    }
    // mola amortecida para o pouso
    this.landVel += (-this.landOffset * 160 - this.landVel * 16) * dt;
    this.landOffset += this.landVel * dt;
    this.shake = Math.max(0, this.shake - dt);
    this.deathBlend = damp(this.deathBlend, player.dead ? 1 : 0, player.dead ? 2.5 : 20, dt);

    player.getEyePosition(_eye);

    // balanço da cabeça (head bob)
    const moving = player.onFloor ? Math.min(player.horizontalSpeed / 4.2, 1.8) : 0;
    this.bobAmount = damp(this.bobAmount, this.bobEnabled ? moving : 0, 10, dt);
    const ph = player.stepPhase;
    const intensity = player.sprinting ? 1.4 : player.crouched ? 0.6 : 1;
    const bobY = Math.abs(Math.sin(ph)) * 0.055 * this.bobAmount * intensity - 0.025 * this.bobAmount;
    const bobX = Math.cos(ph) * 0.035 * this.bobAmount * intensity;

    // inclinação lateral ao andar de lado + espiar
    const strafeRoll = -player.moveInput.x * 0.025 * (player.onFloor ? 1 : 0.4) * (this.bobEnabled ? 1 : 0.3);
    this.roll = damp(this.roll, strafeRoll - player.lean * 0.22, 8, dt);

    // escalada: olha um pouco para baixo, para as mãos
    const climbing = player.isClimbing ? Math.sin(player.climbProgress * Math.PI) : 0;
    this.climbPitch = damp(this.climbPitch, climbing * -0.25, 10, dt);

    // deslize: câmera baixa e inclinada; escada: balança no ritmo das mãos
    this.slideBlend = damp(this.slideBlend, player.sliding ? 1 : 0, 10, dt);
    this.ladderBlend = damp(this.ladderBlend, player.onLadder ? 1 : 0, 8, dt);
    const ladderSway = Math.sin(player.ladderPhase) * 0.03 * this.ladderBlend;
    const extraRoll = (this.slideBlend * 0.09 + ladderSway * 0.5) * (this.bobEnabled ? 1 : 0.4);

    // rolamento: a visão gira para frente e volta
    let rollPitch = 0, rollDrop = 0;
    if (player.rolling) {
      const k = Math.min(1, player.rollTime / 0.65);
      rollPitch = -Math.sin(k * Math.PI) * 1.4;
      rollDrop = Math.sin(k * Math.PI) * 0.55;
    }

    // FOV
    const sprintActive = (player.sprinting && player.horizontalSpeed > 1) || player.sliding;
    this.fov = damp(this.fov, this.baseFov + (sprintActive ? SPRINT_FOV_BONUS : 0) + this.slideBlend * 4, 6, dt);
    if (Math.abs(this.camera.fov - this.fov) > 0.01) {
      this.camera.fov = this.fov;
      this.camera.updateProjectionMatrix();
    }

    const shakeX = this.shake > 0 ? (Math.random() - 0.5) * this.shake * 0.08 : 0;
    const shakeY = this.shake > 0 ? (Math.random() - 0.5) * this.shake * 0.08 : 0;

    const pitch = player.pitch + shakeY + this.climbPitch + rollPitch;
    const yaw = player.yaw + shakeX;

    if (!this.thirdPerson) {
      const sin = Math.sin(yaw), cos = Math.cos(yaw);
      const side = bobX + player.leanOffset + ladderSway;
      const d = this.deathBlend;
      this.camera.position.set(
        _eye.x + cos * side,
        _eye.y + bobY + this.landOffset - Math.abs(player.lean) * 0.08 - rollDrop - d * (_eye.y - player.feetPosition.y - 0.25),
        _eye.z - sin * side
      );
      // morto: cabeça cai de lado
      _euler.set(pitch * (1 - d) + d * 0.2, yaw, this.roll + extraRoll + bobX * 0.4 + d * 1.3);
      this.camera.quaternion.setFromEuler(_euler);
    } else {
      // câmera atrás do ombro, aproximando se bater em parede
      _euler.set(pitch - this.deathBlend * 0.5, yaw, 0);
      this.camera.quaternion.setFromEuler(_euler);
      _dir.set(0, 0, 1).applyQuaternion(this.camera.quaternion);
      _shoulder.set(0.45 + player.leanOffset, 0.1, 0).applyQuaternion(this.camera.quaternion);
      _pivot.copy(_eye).add(_shoulder);
      _ray.set(_pivot, _dir);
      const hit = this.octree.rayIntersect(_ray);
      let dist = this.tpDistance + this.deathBlend * 1.5;
      if (hit && hit.distance < dist + 0.3) dist = Math.max(0.3, hit.distance - 0.3);
      // aproxima rápido, afasta devagar
      this.currentTpDist = dist < this.currentTpDist ? dist : damp(this.currentTpDist, dist, 4, dt);
      this.camera.position.copy(_pivot).addScaledVector(_dir, this.currentTpDist);
      this.camera.position.y += this.landOffset * 0.5;
    }
  }
}
