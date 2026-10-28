import * as THREE from 'three';

// Braços em primeira pessoa (renderizados numa cena separada, por cima do mundo,
// para nunca atravessarem paredes). Todas as animações são procedurais.

const SKIN = 0xc49a7c;
const SLEEVE = 0x3c4430;
const GLOVE = 0x2a2620;

function damp(a, b, lambda, dt) {
  return a + (b - a) * (1 - Math.exp(-lambda * dt));
}

function makeArm(side) {
  const arm = new THREE.Group();
  const sleeveMat = new THREE.MeshStandardMaterial({ color: SLEEVE, roughness: 0.9 });
  const skinMat = new THREE.MeshStandardMaterial({ color: SKIN, roughness: 0.7 });
  const gloveMat = new THREE.MeshStandardMaterial({ color: GLOVE, roughness: 0.8 });

  const forearm = new THREE.Mesh(new THREE.BoxGeometry(0.085, 0.085, 0.42), sleeveMat);
  forearm.position.z = -0.21;
  const cuff = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.09, 0.05), skinMat);
  cuff.position.z = -0.44;
  const hand = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.1, 0.11), gloveMat);
  hand.position.set(0, -0.005, -0.52);
  const thumb = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.03, 0.06), gloveMat);
  thumb.position.set(-side * 0.045, 0.03, -0.5);
  arm.add(forearm, cuff, hand, thumb);
  arm.userData.hand = hand;
  return arm;
}

function makeKnife() {
  const knife = new THREE.Group();
  const handle = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.03, 0.12),
    new THREE.MeshStandardMaterial({ color: 0x1a1a1a, roughness: 0.6 }));
  const guard = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.012, 0.012),
    new THREE.MeshStandardMaterial({ color: 0x555555, metalness: 0.8, roughness: 0.4 }));
  guard.position.z = -0.065;
  const blade = new THREE.Mesh(new THREE.BoxGeometry(0.008, 0.035, 0.2),
    new THREE.MeshStandardMaterial({ color: 0xb8bcc0, metalness: 0.9, roughness: 0.25 }));
  blade.position.set(0, 0.004, -0.17);
  knife.add(handle, guard, blade);
  return knife;
}

export class ViewModel {
  constructor() {
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(60, 1, 0.01, 10);
    this.scene.add(new THREE.HemisphereLight(0xc8d0d4, 0x403a30, 1.3));
    const key = new THREE.DirectionalLight(0xfff0dd, 1.2);
    key.position.set(1, 2, 1);
    this.scene.add(key);

    this.root = new THREE.Group();   // balanço geral
    this.scene.add(this.root);

    this.right = makeArm(1);
    this.left = makeArm(-1);
    this.rightBase = new THREE.Vector3(0.24, -0.27, -0.12);
    this.leftBase = new THREE.Vector3(-0.27, -0.3, -0.1);
    this.right.position.copy(this.rightBase);
    this.left.position.copy(this.leftBase);
    this.right.rotation.set(0.1, 0.12, 0);
    this.left.rotation.set(0.05, -0.15, 0);
    this.root.add(this.right, this.left);

    this.knife = makeKnife();
    this.knife.position.set(0, 0.02, -0.52);
    this.knife.rotation.set(0.25, 0, 0);
    this.right.add(this.knife);

    this.t = 0;
    this.sway = new THREE.Vector2();
    this.sprintBlend = 0;
    this.crouchBlend = 0;
    this.airOffset = 0;
    this.landKick = 0;
    this.landVel = 0;
    this.attackTime = -1;
    this.visible = true;
  }

  setAspect(aspect) {
    this.camera.aspect = aspect;
    this.camera.updateProjectionMatrix();
  }

  attack() {
    if (this.attackTime < 0 || this.attackTime > 0.45) this.attackTime = 0;
  }

  get isAttacking() { return this.attackTime >= 0 && this.attackTime < 0.5; }

  update(dt, player) {
    this.t += dt;
    const speed = player.horizontalSpeed;
    const moveAmt = player.onFloor ? Math.min(speed / 4.2, 1.8) : 0;

    this.sprintBlend = damp(this.sprintBlend, player.sprinting && speed > 1 ? 1 : 0, 8, dt);
    this.crouchBlend = damp(this.crouchBlend, player.crouched ? 1 : 0, 8, dt);

    // balanço ao olhar (os braços "atrasam" em relação à câmera)
    const ld = player.lookDelta || { x: 0, y: 0 };
    this.sway.x = damp(this.sway.x, Math.max(-0.08, Math.min(0.08, ld.x * 1.2)), 10, dt);
    this.sway.y = damp(this.sway.y, Math.max(-0.08, Math.min(0.08, ld.y * 1.2)), 10, dt);

    // pulo / pouso
    for (const e of player.events) {
      if (e.type === 'land') this.landVel -= Math.min(e.speed, 20) * 0.025;
      if (e.type === 'jump') this.landVel += 0.12;
    }
    // mola simples para o "tranco" do pouso
    this.landVel += (-this.landKick * 120 - this.landVel * 14) * dt;
    this.landKick += this.landVel * dt;
    this.airOffset = damp(this.airOffset, player.onFloor ? 0 : (player.velocity.y > 0 ? -0.02 : 0.025), 6, dt);

    // passo
    const ph = player.stepPhase;
    const bobX = Math.cos(ph) * 0.012 * moveAmt;
    const bobY = -Math.abs(Math.sin(ph)) * 0.014 * moveAmt;
    const breath = Math.sin(this.t * 1.7) * 0.004 * (1 - Math.min(moveAmt, 1));

    this.root.position.set(
      bobX - this.sway.x * 0.3,
      bobY + breath + this.sway.y * 0.25 + this.landKick + this.airOffset - this.crouchBlend * 0.015,
      0
    );
    this.root.rotation.set(
      this.sway.y * 0.6,
      this.sway.x * 0.8,
      bobX * 1.5 - this.sway.x * 0.4
    );

    // pose de corrida: braços abaixam e giram
    const s = this.sprintBlend;
    this.right.position.set(this.rightBase.x + s * 0.04, this.rightBase.y - s * 0.06, this.rightBase.z + s * 0.05);
    this.left.position.set(this.leftBase.x - s * 0.02, this.leftBase.y - s * 0.08 + Math.sin(ph) * 0.03 * s, this.leftBase.z + s * 0.06);
    this.right.rotation.set(0.1 - s * 0.5, 0.12 + s * 0.5, -s * 0.3);
    this.left.rotation.set(0.05 - s * 0.4 + Math.cos(ph) * 0.15 * s, -0.15 - s * 0.2, s * 0.2);

    // ataque com a faca
    if (this.attackTime >= 0) {
      this.attackTime += dt;
      const a = this.attackTime;
      let k;
      if (a < 0.08) k = -(a / 0.08) * 0.4;                      // prepara
      else if (a < 0.2) k = -0.4 + ((a - 0.08) / 0.12) * 1.6;   // golpe
      else if (a < 0.5) k = 1.2 * (1 - (a - 0.2) / 0.3);        // volta
      else { k = 0; this.attackTime = -1; }
      this.right.position.x -= Math.max(0, k) * 0.12;
      this.right.position.z -= Math.max(0, k) * 0.08;
      this.right.position.y += k * 0.04;
      this.right.rotation.y += k * 0.9;
      this.right.rotation.x -= k * 0.25;
      this.right.rotation.z += k * 0.6;
    }
  }

  render(renderer, mainCamera) {
    if (!this.visible) return;
    this.camera.fov = mainCamera.fov * 0.85;
    this.camera.updateProjectionMatrix();
    renderer.clearDepth();
    renderer.render(this.scene, this.camera);
  }
}
