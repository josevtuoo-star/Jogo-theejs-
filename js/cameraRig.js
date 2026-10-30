import * as THREE from 'three';

// Câmera: em 1ª pessoa fica nos olhos do corpo animado (o balanço, o pouso, as escaladas e a
// queda vêm da animação do corpo); em 3ª pessoa fica atrás do ombro, com colisão.
// Também: inclinação ao espiar/andar de lado, FOV maior correndo, tremor com dano e morte.

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
    this.kickP = 0;
    this.kickY = 0;
    this.fov = this.baseFov;
    this.deathBlend = 0;
    this.climbPitch = 0;
    this.slideBlend = 0;
    this.ladderBlend = 0;
  }

  /** Tranco da câmera (golpe dado ou recebido). */
  kick(pitch, yaw = 0) {
    this.kickP += pitch;
    this.kickY += yaw;
  }

  toggleView() {
    this.thirdPerson = !this.thirdPerson;
  }

  /**
   * headEye: posição dos olhos do corpo animado (1ª pessoa). A câmera segue a cabeça de verdade,
   * então o balanço ao andar, o agachar, as escaladas e a queda vêm da própria animação do corpo.
   */
  update(dt, player, headEye) {
    for (const e of player.events) {
      if (e.type === 'damage') this.shake = 0.35;
      if (e.type === 'slide') this.shake = Math.max(this.shake, 0.12);
      if (e.type === 'land' && e.speed > 8) this.shake = Math.max(this.shake, Math.min(0.3, (e.speed - 8) * 0.05));
    }
    this.shake = Math.max(0, this.shake - dt);
    // tranco dos golpes: mola rápida que volta ao centro
    this.kickP = damp(this.kickP, 0, 14, dt);
    this.kickY = damp(this.kickY, 0, 14, dt);
    this.deathBlend = damp(this.deathBlend, player.dead ? 1 : 0, player.dead ? 2.5 : 20, dt);

    player.getEyePosition(_eye);

    // inclinação lateral ao andar de lado + espiar
    const strafeRoll = -player.moveInput.x * 0.015 * (player.onFloor ? 1 : 0.4) * (this.bobEnabled ? 1 : 0.3);
    this.roll = damp(this.roll, strafeRoll - player.lean * 0.2, 8, dt);

    // escalada: olha um pouco para as mãos
    const climbing = player.isClimbing ? Math.sin(player.climbProgress * Math.PI) : 0;
    this.climbPitch = damp(this.climbPitch, climbing * -0.12, 10, dt);

    this.slideBlend = damp(this.slideBlend, player.sliding ? 1 : 0, 10, dt);
    this.ladderBlend = damp(this.ladderBlend, player.onLadder ? 1 : 0, 8, dt);
    const extraRoll = this.slideBlend * 0.07 * (this.bobEnabled ? 1 : 0.4);

    // rolamento: a visão gira para frente e volta
    let rollPitch = 0;
    if (player.rolling) rollPitch = -Math.sin(Math.min(1, player.rollTime / 0.65) * Math.PI) * 1.4;

    // FOV
    const sprintActive = (player.sprinting && player.horizontalSpeed > 4) || player.sliding;
    // mirando com a arma: aproxima (zoom leve, mais forte pela alça e massa em 1ª pessoa)
    const aim = this.aim ?? 0;
    const fovT = this.baseFov + (sprintActive ? SPRINT_FOV_BONUS : 0) + this.slideBlend * 3 - aim * (this.thirdPerson ? 12 : 22);
    this.fov = damp(this.fov, fovT, aim > 0.02 || Math.abs(this.fov - fovT) < 6 ? 12 : 4, dt);
    if (Math.abs(this.camera.fov - this.fov) > 0.01) {
      this.camera.fov = this.fov;
      this.camera.updateProjectionMatrix();
    }

    const shakeX = this.shake > 0 ? (Math.random() - 0.5) * this.shake * 0.08 : 0;
    const shakeY = this.shake > 0 ? (Math.random() - 0.5) * this.shake * 0.08 : 0;
    const pitch = player.pitch + shakeY + this.climbPitch + rollPitch + this.kickP;
    const yaw = player.yaw + shakeX + this.kickY;

    if (!this.thirdPerson) {
      // segue os olhos do corpo, sem sair da cápsula (não atravessa paredes)
      if (!this._fp) this._fp = headEye.clone();
      const cx = player.collider.start.x, cz = player.collider.start.z;
      let ox = headEye.x - cx, oz = headEye.z - cz;
      const maxR = 0.28 + Math.abs(player.leanOffset);
      const r = Math.hypot(ox, oz);
      if (r > maxR) { ox *= maxR / r; oz *= maxR / r; }
      const top = player.collider.end.y + player.collider.radius - 0.06;
      const ty = Math.min(top, Math.max(player.collider.start.y - player.collider.radius + 0.2, headEye.y));
      const lambdaY = this.bobEnabled ? 28 : 7; // sem balanço: filtra o sobe-e-desce dos passos
      this._fp.x = damp(this._fp.x, cx + ox, 35, dt);
      this._fp.z = damp(this._fp.z, cz + oz, 35, dt);
      this._fp.y = damp(this._fp.y, ty, lambdaY, dt);
      if (player.dead || player.rolling) this._fp.copy(headEye);
      this.camera.position.copy(this._fp);
      const d = this.deathBlend;
      _euler.set(pitch * (1 - d) + d * 0.2, yaw, this.roll + extraRoll + d * 1.3);
      this.camera.quaternion.setFromEuler(_euler);
    } else {
      this._fp = null;
      // câmera atrás do ombro, aproximando se bater em parede
      _euler.set(pitch - this.deathBlend * 0.5, yaw, 0);
      this.camera.quaternion.setFromEuler(_euler);
      _dir.set(0, 0, 1).applyQuaternion(this.camera.quaternion);
      // pendurado/escalando: a câmera sobe e se afasta do muro para não entrar nele
      this.wallBlend = damp(this.wallBlend ?? 0, player.isHanging || player.isClimbing ? 1 : 0, 6, dt);
      _shoulder.set(0.45 + player.leanOffset + this.wallBlend * 0.25, 0.1 + this.wallBlend * 0.45, 0).applyQuaternion(this.camera.quaternion);
      _pivot.copy(_eye).add(_shoulder);
      _ray.set(_pivot, _dir);
      const hit = this.octree.rayIntersect(_ray);
      let dist = this.tpDistance * (1 - 0.4 * (this.aim ?? 0)) + this.deathBlend * 1.5 + this.wallBlend * 0.6;
      if (hit && hit.distance < dist + 0.3) dist = Math.max(0.3, hit.distance - 0.3);
      // aproxima rápido, afasta devagar
      this.currentTpDist = dist < this.currentTpDist ? dist : damp(this.currentTpDist, dist, 4, dt);
      this.camera.position.copy(_pivot).addScaledVector(_dir, this.currentTpDist);
    }
  }
}
