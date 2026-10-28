import * as THREE from 'three';

// Efeitos de câmera: balanço da cabeça ao andar, inclinação lateral, "tranco" no pouso,
// FOV maior correndo e câmera em terceira pessoa com colisão.

const BASE_FOV = 75;
const SPRINT_FOV = 84;

function damp(a, b, lambda, dt) {
  return a + (b - a) * (1 - Math.exp(-lambda * dt));
}

const _eye = new THREE.Vector3();
const _dir = new THREE.Vector3();
const _ray = new THREE.Ray();
const _euler = new THREE.Euler(0, 0, 0, 'YXZ');

export class CameraRig {
  constructor(camera, octree) {
    this.camera = camera;
    this.octree = octree;
    this.thirdPerson = false;
    this.tpDistance = 3.2;
    this.currentTpDist = 3.2;

    this.bobAmount = 0;
    this.roll = 0;
    this.landOffset = 0;
    this.landVel = 0;
    this.shake = 0;
    this.fov = BASE_FOV;
  }

  toggleView() {
    this.thirdPerson = !this.thirdPerson;
  }

  update(dt, player) {
    for (const e of player.events) {
      if (e.type === 'land') this.landVel -= Math.min(e.speed, 22) * 0.045;
      if (e.type === 'damage') this.shake = 0.35;
    }
    // mola amortecida para o pouso
    this.landVel += (-this.landOffset * 160 - this.landVel * 16) * dt;
    this.landOffset += this.landVel * dt;
    this.shake = Math.max(0, this.shake - dt);

    player.getEyePosition(_eye);

    // balanço da cabeça (head bob)
    const moving = player.onFloor ? Math.min(player.horizontalSpeed / 4.2, 1.8) : 0;
    this.bobAmount = damp(this.bobAmount, moving, 10, dt);
    const ph = player.stepPhase;
    const intensity = player.sprinting ? 1.4 : player.crouched ? 0.6 : 1;
    const bobY = Math.abs(Math.sin(ph)) * 0.055 * this.bobAmount * intensity - 0.025 * this.bobAmount;
    const bobX = Math.cos(ph) * 0.035 * this.bobAmount * intensity;

    // inclinação lateral ao andar de lado
    const targetRoll = -player.moveInput.x * 0.025 * (player.onFloor ? 1 : 0.4);
    this.roll = damp(this.roll, targetRoll, 6, dt);

    // FOV
    const sprintActive = player.sprinting && player.horizontalSpeed > 1;
    this.fov = damp(this.fov, sprintActive ? SPRINT_FOV : BASE_FOV, 6, dt);
    if (Math.abs(this.camera.fov - this.fov) > 0.01) {
      this.camera.fov = this.fov;
      this.camera.updateProjectionMatrix();
    }

    const shakeX = this.shake > 0 ? (Math.random() - 0.5) * this.shake * 0.08 : 0;
    const shakeY = this.shake > 0 ? (Math.random() - 0.5) * this.shake * 0.08 : 0;

    _euler.set(player.pitch + shakeY, player.yaw + shakeX, 0);
    this.camera.quaternion.setFromEuler(_euler);

    if (!this.thirdPerson) {
      // desloca o bob no eixo lateral da câmera
      const sin = Math.sin(player.yaw), cos = Math.cos(player.yaw);
      this.camera.position.set(
        _eye.x + cos * bobX,
        _eye.y + bobY + this.landOffset,
        _eye.z - sin * bobX
      );
      _euler.set(player.pitch + shakeY, player.yaw + shakeX, this.roll + bobX * 0.4);
      this.camera.quaternion.setFromEuler(_euler);
    } else {
      // câmera atrás do ombro, aproximando se bater em parede
      _dir.set(0, 0, 1).applyQuaternion(this.camera.quaternion);
      const shoulder = new THREE.Vector3(0.45, 0.1, 0).applyQuaternion(this.camera.quaternion);
      const pivot = _eye.clone().add(shoulder);
      _ray.set(pivot, _dir);
      const hit = this.octree.rayIntersect(_ray);
      let dist = this.tpDistance;
      if (hit && hit.distance < dist + 0.3) dist = Math.max(0.3, hit.distance - 0.3);
      // aproxima rápido, afasta devagar
      this.currentTpDist = dist < this.currentTpDist ? dist : damp(this.currentTpDist, dist, 4, dt);
      this.camera.position.copy(pivot).addScaledVector(_dir, this.currentTpDist);
      this.camera.position.y += this.landOffset * 0.5;
    }
  }
}
