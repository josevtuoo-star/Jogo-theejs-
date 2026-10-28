import * as THREE from 'three';

// Braços em primeira pessoa (renderizados numa cena separada, por cima do mundo,
// para nunca atravessarem paredes). Todas as animações são procedurais.

const SKIN = 0xc49a7c;
const SLEEVE = 0x3c4430;
const GLOVE = 0x2a2620;

function damp(a, b, lambda, dt) {
  return a + (b - a) * (1 - Math.exp(-lambda * dt));
}

// cápsula deitada ao longo de -Z (antebraço, dedos)
function capsuleZ(radius, length, mat) {
  const g = new THREE.CapsuleGeometry(radius, length, 4, 10);
  g.rotateX(Math.PI / 2);
  return new THREE.Mesh(g, mat);
}

function makeArm(side) {
  const arm = new THREE.Group();
  const sleeveMat = new THREE.MeshStandardMaterial({ color: SLEEVE, roughness: 0.95 });
  const skinMat = new THREE.MeshStandardMaterial({ color: SKIN, roughness: 0.7 });
  const gloveMat = new THREE.MeshStandardMaterial({ color: GLOVE, roughness: 0.8 });

  const forearm = capsuleZ(0.045, 0.36, sleeveMat);
  forearm.position.z = -0.2;
  forearm.scale.set(1, 0.92, 1);
  // dobras da manga arregaçada
  const cuff = capsuleZ(0.05, 0.03, sleeveMat);
  cuff.position.z = -0.37;
  const wrist = capsuleZ(0.036, 0.05, skinMat);
  wrist.position.z = -0.42;

  // mão: palma + dedos fechados + polegar
  const hand = new THREE.Group();
  hand.position.set(0, -0.004, -0.5);
  const palm = new THREE.Mesh(new THREE.BoxGeometry(0.075, 0.035, 0.085), gloveMat);
  palm.position.set(0, 0.0, 0);
  hand.add(palm);
  for (let i = 0; i < 4; i++) {
    const finger = capsuleZ(0.0105, 0.035, gloveMat);
    finger.position.set((i - 1.5) * 0.019, -0.028, -0.035);
    finger.rotation.x = Math.PI / 2.4; // dedos curvados para baixo
    hand.add(finger);
  }
  const thumb = capsuleZ(0.012, 0.035, gloveMat);
  thumb.position.set(-side * 0.04, -0.005, -0.02);
  thumb.rotation.y = side * 0.6;
  hand.add(thumb);

  arm.add(forearm, cuff, wrist, hand);
  arm.userData.hand = hand;
  arm.traverse((o) => { if (o.isMesh) o.castShadow = false; });
  return arm;
}

function makeKnife() {
  const knife = new THREE.Group();
  const handleMat = new THREE.MeshStandardMaterial({ color: 0x1a1612, roughness: 0.7 });
  const handle = new THREE.Mesh(new THREE.CylinderGeometry(0.014, 0.016, 0.11, 8), handleMat);
  handle.rotation.x = Math.PI / 2;
  const guard = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.012, 0.012),
    new THREE.MeshStandardMaterial({ color: 0x555555, metalness: 0.8, roughness: 0.4 }));
  guard.position.z = -0.06;
  // lâmina com ponta: forma desenhada e extrudada
  const shape = new THREE.Shape();
  shape.moveTo(0, -0.016);
  shape.lineTo(0.17, -0.012);
  shape.lineTo(0.205, 0.012);
  shape.lineTo(0, 0.018);
  shape.lineTo(0, -0.016);
  const bladeGeo = new THREE.ExtrudeGeometry(shape, { depth: 0.006, bevelEnabled: false });
  bladeGeo.translate(0, 0, -0.003);
  bladeGeo.rotateY(Math.PI / 2);
  const blade = new THREE.Mesh(bladeGeo,
    new THREE.MeshStandardMaterial({ color: 0xc4c8cc, metalness: 0.9, roughness: 0.22 }));
  blade.position.set(0, 0.002, -0.066);
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
    // lanterna também ilumina os braços
    this.flashFill = new THREE.PointLight(0xfff2d8, 0, 1.5);
    this.flashFill.position.set(0.1, -0.1, -0.2);
    this.scene.add(this.flashFill);

    this.root = new THREE.Group();   // balanço geral
    this.scene.add(this.root);

    this.right = makeArm(1);
    this.left = makeArm(-1);
    this.rightBase = new THREE.Vector3(0.24, -0.26, -0.1);
    this.leftBase = new THREE.Vector3(-0.27, -0.29, -0.08);
    this.right.position.copy(this.rightBase);
    this.left.position.copy(this.leftBase);
    this.root.add(this.right, this.left);

    this.knife = makeKnife();
    this.knife.position.set(0, -0.012, -0.03);
    this.knife.rotation.set(0.35, 0, 0);
    this.right.userData.hand.add(this.knife);

    this.t = 0;
    this.sway = new THREE.Vector2();
    this.sprintBlend = 0;
    this.crouchBlend = 0;
    this.climbBlend = 0;
    this.ladderBlend = 0;
    this.slideBlend = 0;
    this.airOffset = 0;
    this.landKick = 0;
    this.landVel = 0;
    this.attackTime = -1;
    this.attackSide = 1;
    this.hidden = 0;   // 1 = abaixado/fora da tela (morte)
    this.visible = true;
  }

  setAspect(aspect) {
    this.camera.aspect = aspect;
    this.camera.updateProjectionMatrix();
  }

  setFlashlight(on) {
    this.flashFill.intensity = on ? 1.2 : 0;
  }

  attack() {
    if (this.attackTime < 0 || this.attackTime > 0.42) {
      this.attackTime = 0;
      this.attackSide = -this.attackSide; // alterna golpe da direita/esquerda
    }
  }

  get isAttacking() { return this.attackTime >= 0 && this.attackTime < 0.5; }

  update(dt, player) {
    this.t += dt;
    const speed = player.horizontalSpeed;
    const moveAmt = player.onFloor ? Math.min(speed / 4.2, 1.8) : 0;

    this.sprintBlend = damp(this.sprintBlend, player.sprinting && speed > 1 ? 1 : 0, 8, dt);
    this.crouchBlend = damp(this.crouchBlend, player.crouched ? 1 : 0, 8, dt);
    this.climbBlend = damp(this.climbBlend, player.isClimbing ? 1 : 0, player.isClimbing ? 18 : 6, dt);
    this.hidden = damp(this.hidden, player.dead ? 1 : player.rolling ? 0.7 : 0, player.rolling ? 14 : 5, dt);
    this.ladderBlend = damp(this.ladderBlend, player.onLadder ? 1 : 0, 10, dt);
    this.slideBlend = damp(this.slideBlend, player.sliding ? 1 : 0, 10, dt);

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
    this.airOffset = damp(this.airOffset, player.onFloor || player.isClimbing ? 0 : (player.velocity.y > 0 ? -0.02 : 0.025), 6, dt);

    // passo
    const ph = player.stepPhase;
    const bobX = Math.cos(ph) * 0.012 * moveAmt;
    const bobY = -Math.abs(Math.sin(ph)) * 0.014 * moveAmt;
    const breath = Math.sin(this.t * 1.7) * 0.004 * (1 - Math.min(moveAmt, 1) * 0.7);

    this.root.position.set(
      bobX - this.sway.x * 0.3 + player.lean * 0.02,
      bobY + breath + this.sway.y * 0.25 + this.landKick + this.airOffset - this.crouchBlend * 0.015 - this.hidden * 0.5,
      0
    );
    this.root.rotation.set(
      this.sway.y * 0.6,
      this.sway.x * 0.8,
      bobX * 1.5 - this.sway.x * 0.4 + player.lean * 0.15
    );

    // pose base + corrida: braços abaixam e giram
    const s = this.sprintBlend;
    this.right.position.set(this.rightBase.x + s * 0.04, this.rightBase.y - s * 0.06, this.rightBase.z + s * 0.05);
    this.left.position.set(this.leftBase.x - s * 0.02, this.leftBase.y - s * 0.08 + Math.sin(ph) * 0.03 * s, this.leftBase.z + s * 0.06);
    this.right.rotation.set(0.1 - s * 0.5, 0.12 + s * 0.5, -s * 0.3);
    this.left.rotation.set(0.05 - s * 0.4 + Math.cos(ph) * 0.15 * s, -0.15 - s * 0.2, s * 0.2);

    // escalada: as duas mãos se apoiam à frente, empurrando o corpo
    const c = this.climbBlend;
    if (c > 0.001) {
      const push = player.isClimbing ? player.climbProgress : 1;
      const reach = Math.sin(Math.min(push, 1) * Math.PI); // estende e depois recolhe
      for (const [arm, side] of [[this.right, 1], [this.left, -1]]) {
        arm.position.x = THREE.MathUtils.lerp(arm.position.x, side * 0.22, c);
        arm.position.y = THREE.MathUtils.lerp(arm.position.y, -0.17 + reach * 0.04 - push * 0.05, c);
        arm.position.z = THREE.MathUtils.lerp(arm.position.z, -0.02 - reach * 0.06, c);
        arm.rotation.x = THREE.MathUtils.lerp(arm.rotation.x, -0.15 - reach * 0.25, c);
        arm.rotation.y = THREE.MathUtils.lerp(arm.rotation.y, side * -0.2, c);
        arm.rotation.z = THREE.MathUtils.lerp(arm.rotation.z, 0, c);
      }
    }

    // escada de mão: as mãos sobem alternadas, agarrando os degraus
    const L = this.ladderBlend;
    if (L > 0.001) {
      for (const [arm, side] of [[this.right, 1], [this.left, -1]]) {
        const alt = Math.sin(player.ladderPhase + (side > 0 ? 0 : Math.PI));
        arm.position.x = THREE.MathUtils.lerp(arm.position.x, side * 0.19, L);
        arm.position.y = THREE.MathUtils.lerp(arm.position.y, -0.12 + alt * 0.09, L);
        arm.position.z = THREE.MathUtils.lerp(arm.position.z, -0.12 - Math.max(0, alt) * 0.04, L);
        arm.rotation.x = THREE.MathUtils.lerp(arm.rotation.x, 0.55 + alt * 0.15, L);
        arm.rotation.y = THREE.MathUtils.lerp(arm.rotation.y, side * -0.1, L);
        arm.rotation.z = THREE.MathUtils.lerp(arm.rotation.z, 0, L);
      }
    }

    // deslize: braços abertos para equilibrar
    const S = this.slideBlend;
    if (S > 0.001) {
      for (const [arm, side] of [[this.right, 1], [this.left, -1]]) {
        arm.position.x += side * 0.08 * S;
        arm.position.y -= 0.05 * S;
        arm.rotation.z += -side * 0.5 * S;
        arm.rotation.y += side * 0.3 * S;
      }
    }

    // ataque com a faca (golpes alternados)
    if (this.attackTime >= 0) {
      this.attackTime += dt;
      const a = this.attackTime;
      let k;
      if (a < 0.08) k = -(a / 0.08) * 0.4;                      // prepara
      else if (a < 0.2) k = -0.4 + ((a - 0.08) / 0.12) * 1.6;   // golpe
      else if (a < 0.5) k = 1.2 * (1 - (a - 0.2) / 0.3);        // volta
      else { k = 0; this.attackTime = -1; }
      const side = this.attackSide;
      this.right.position.x -= Math.max(0, k) * 0.12 * (side > 0 ? 1 : 0.4);
      this.right.position.z -= Math.max(0, k) * 0.1;
      this.right.position.y += k * 0.04 * side;
      this.right.rotation.y += k * 0.9 * (side > 0 ? 1 : 0.5);
      this.right.rotation.x -= k * 0.25 * side;
      this.right.rotation.z += k * 0.6 * side;
    }
  }

  render(renderer, mainCamera) {
    if (!this.visible || this.hidden > 0.98) return;
    this.camera.fov = mainCamera.fov * 0.85;
    this.camera.updateProjectionMatrix();
    renderer.clearDepth();
    renderer.render(this.scene, this.camera);
  }
}
