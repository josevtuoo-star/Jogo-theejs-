import * as THREE from 'three';

// Corpo do personagem (visto na câmera em terceira pessoa).
// Esqueleto simples de grupos articulados com animação procedural:
// parado (respiração), andando, correndo, agachado, pulando/caindo, escalando,
// inclinando (Q/E), atacando e morte.

function damp(a, b, lambda, dt) {
  return a + (b - a) * (1 - Math.exp(-lambda * dt));
}

function limb(w, h, d, mat, offsetY) {
  const pivot = new THREE.Group();
  // membros arredondados (cápsula achatada no eixo z quando d < w)
  const r = w / 2;
  const mesh = new THREE.Mesh(new THREE.CapsuleGeometry(r, Math.max(0.01, h - w), 4, 8), mat);
  mesh.scale.z = d / w;
  mesh.position.y = offsetY;
  mesh.castShadow = true;
  pivot.add(mesh);
  return pivot;
}

export class Character {
  constructor(scene) {
    const jacket = new THREE.MeshStandardMaterial({ color: 0x3c4430, roughness: 0.9 });
    const pants = new THREE.MeshStandardMaterial({ color: 0x2e3440, roughness: 0.9 });
    const skin = new THREE.MeshStandardMaterial({ color: 0xc49a7c, roughness: 0.7 });
    const boots = new THREE.MeshStandardMaterial({ color: 0x241c14, roughness: 0.8 });
    const bag = new THREE.MeshStandardMaterial({ color: 0x5a4a32, roughness: 0.9 });
    const hair = new THREE.MeshStandardMaterial({ color: 0x2a2018, roughness: 1 });

    this.root = new THREE.Group();
    this.root.rotation.order = 'YXZ'; // gira (yaw) primeiro, depois tomba no eixo do corpo
    this.hips = new THREE.Group();
    this.hips.position.y = 0.95;
    this.root.add(this.hips);

    this.torso = new THREE.Group();
    this.hips.add(this.torso);
    const chest = new THREE.Mesh(new THREE.BoxGeometry(0.46, 0.6, 0.26), jacket);
    chest.position.y = 0.3;
    chest.castShadow = true;
    const backpack = new THREE.Mesh(new THREE.BoxGeometry(0.36, 0.42, 0.18), bag);
    backpack.position.set(0, 0.32, 0.21);
    backpack.castShadow = true;
    this.torso.add(chest, backpack);

    this.head = new THREE.Group();
    this.head.position.y = 0.62;
    const headMesh = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.27, 0.25), skin);
    headMesh.position.y = 0.14;
    headMesh.castShadow = true;
    const hairMesh = new THREE.Mesh(new THREE.BoxGeometry(0.26, 0.08, 0.27), hair);
    hairMesh.position.y = 0.29;
    this.head.add(headMesh, hairMesh);
    this.torso.add(this.head);

    // braços (pivô no ombro)
    this.armL = limb(0.13, 0.6, 0.13, jacket, -0.28);
    this.armR = limb(0.13, 0.6, 0.13, jacket, -0.28);
    this.armL.position.set(-0.3, 0.56, 0);
    this.armR.position.set(0.3, 0.56, 0);
    for (const a of [this.armL, this.armR]) {
      const hand = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.1, 0.1), skin);
      hand.position.y = -0.62;
      a.add(hand);
    }
    this.torso.add(this.armL, this.armR);

    // pernas (pivô no quadril) com joelho
    const makeLeg = (x) => {
      const thigh = limb(0.17, 0.46, 0.18, pants, -0.23);
      thigh.position.set(x, 0, 0);
      const knee = limb(0.15, 0.46, 0.16, pants, -0.23);
      knee.position.y = -0.46;
      const boot = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.1, 0.26), boots);
      boot.position.set(0, -0.47, -0.04);
      boot.castShadow = true;
      knee.add(boot);
      thigh.add(knee);
      thigh.userData.knee = knee;
      return thigh;
    };
    this.legL = makeLeg(-0.12);
    this.legR = makeLeg(0.12);
    this.hips.add(this.legL, this.legR);

    this.root.visible = false;
    scene.add(this.root);

    this.blendRun = 0;
    this.blendMove = 0;
    this.blendCrouch = 0;
    this.blendAir = 0;
    this.blendClimb = 0;
    this.blendDeath = 0;
    this.lean = 0;
    this.t = 0;
    this.yaw = 0;
  }

  update(dt, player, attacking) {
    this.t += dt;
    const feet = player.feetPosition;
    this.root.position.copy(feet);

    // gira suavemente para a direção da câmera
    let dy = player.yaw - this.yaw;
    dy = Math.atan2(Math.sin(dy), Math.cos(dy));
    this.yaw += dy * (1 - Math.exp(-12 * dt));
    this.root.rotation.y = this.yaw;

    const speed = player.horizontalSpeed;
    this.blendMove = damp(this.blendMove, player.onFloor ? Math.min(speed / 4.2, 1) : 0, 10, dt);
    this.blendRun = damp(this.blendRun, player.sprinting && speed > 1 ? 1 : 0, 8, dt);
    this.blendCrouch = damp(this.blendCrouch, player.crouched ? 1 : 0, 10, dt);
    this.blendAir = damp(this.blendAir, player.onFloor || player.isClimbing ? 0 : 1, 10, dt);
    this.blendClimb = damp(this.blendClimb, player.isClimbing ? 1 : 0, 14, dt);
    this.blendDeath = damp(this.blendDeath, player.dead ? 1 : 0, player.dead ? 3 : 30, dt);
    this.lean = player.lean;

    // direção do movimento relativa ao corpo (andar de costas inverte o passo)
    const back = player.moveInput.y < -0.1 ? -1 : 1;
    const ph = player.stepPhase * back;
    const swing = Math.sin(ph);
    const amp = (0.55 + this.blendRun * 0.45) * this.blendMove;

    // pernas
    const crouchBend = this.blendCrouch * 1.1;
    // (rotação x positiva leva o membro para frente; o joelho dobra para trás)
    this.legL.rotation.x = swing * amp + crouchBend + this.blendAir * 0.6;
    this.legR.rotation.x = -swing * amp + crouchBend - this.blendAir * 0.1;
    this.legL.userData.knee.rotation.x = -(Math.max(0, -Math.cos(ph)) * amp * 1.2 + crouchBend * 1.7 + this.blendAir * 1.0);
    this.legR.userData.knee.rotation.x = -(Math.max(0, Math.cos(ph)) * amp * 1.2 + crouchBend * 1.7 + this.blendAir * 0.4);

    // quadril: desce ao agachar, quica ao andar
    const bounce = Math.abs(Math.cos(ph)) * 0.05 * this.blendMove;
    this.hips.position.y = 0.95 - this.blendCrouch * 0.38 + bounce - this.blendAir * 0.05;

    // tronco inclina para frente correndo/agachado, respira parado
    this.torso.rotation.x = -(this.blendRun * 0.25 + this.blendCrouch * 0.35);
    this.torso.rotation.y = swing * 0.12 * this.blendMove;
    this.torso.scale.y = 1 + Math.sin(this.t * 1.8) * 0.01 * (1 - this.blendMove);

    // cabeça acompanha o olhar vertical
    this.head.rotation.x = player.pitch * 0.6 - this.torso.rotation.x;

    // braços balançam opostos às pernas
    const armAmp = amp * (0.9 + this.blendRun * 0.4);
    this.armL.rotation.x = -swing * armAmp + this.blendRun * 0.3 + this.blendAir * 0.5;
    this.armR.rotation.x = swing * armAmp + this.blendRun * 0.3 + this.blendAir * 0.5;
    this.armL.rotation.z = -0.08 - this.blendAir * 0.4;
    this.armR.rotation.z = 0.08 + this.blendAir * 0.4;

    if (attacking) {
      this.armR.rotation.x = 1.6;
      this.armR.rotation.z = 0.4;
    }

    // escalada: braços para cima/frente apoiando, uma perna sobe primeiro
    const c = this.blendClimb;
    if (c > 0.001) {
      const pr = player.climbProgress;
      const armX = 2.6 - pr * 1.6; // mãos no topo e depois empurrando para baixo
      this.armL.rotation.x = THREE.MathUtils.lerp(this.armL.rotation.x, armX, c);
      this.armR.rotation.x = THREE.MathUtils.lerp(this.armR.rotation.x, armX, c);
      this.legR.rotation.x = THREE.MathUtils.lerp(this.legR.rotation.x, 1.3 * Math.sin(pr * Math.PI), c);
      this.legR.userData.knee.rotation.x = THREE.MathUtils.lerp(this.legR.userData.knee.rotation.x, -1.6 * Math.sin(pr * Math.PI), c);
      this.torso.rotation.x = THREE.MathUtils.lerp(this.torso.rotation.x, -0.45, c);
    }

    // inclinar (espiar)
    this.torso.rotation.z = -this.lean * 0.35;
    this.hips.position.x = this.lean * 0.05;

    // morte: cai de costas
    const d = this.blendDeath;
    this.root.rotation.x = d * 1.45;
    this.root.position.y += d * 0.12;
    if (d > 0.01) {
      this.armL.rotation.z -= d * 0.6;
      this.armR.rotation.z += d * 0.6;
    }
  }
}
