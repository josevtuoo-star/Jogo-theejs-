import * as THREE from 'three';

// Corpo do personagem. Em terceira pessoa aparece inteiro; em primeira pessoa o tronco, a
// cabeça e os braços ficam numa camada invisível para a câmera (mas ainda projetam sombra),
// então dá para ver as próprias pernas ao olhar para baixo sem o corpo atravessar a visão.
// Animação procedural: parado, andar, correr, agachar, pular, escalar, escada de mão,
// deslizar, rolar, inclinar (Q/E), atacar e morrer.

export const FP_HIDDEN_LAYER = 1;

function damp(a, b, lambda, dt) {
  return a + (b - a) * (1 - Math.exp(-lambda * dt));
}
const lerp = THREE.MathUtils.lerp;

/** Membro arredondado pendurado num pivô (ombro, cotovelo, quadril, joelho). */
function limb(w, h, d, mat, offsetY) {
  const pivot = new THREE.Group();
  const mesh = new THREE.Mesh(new THREE.CapsuleGeometry(w / 2, Math.max(0.01, h - w), 4, 10), mat);
  mesh.scale.z = d / w;
  mesh.position.y = offsetY;
  pivot.add(mesh);
  return pivot;
}

function part(geo, mat, x, y, z) {
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x, y, z);
  return m;
}

export class Character {
  constructor(scene) {
    const M = {
      jacket: new THREE.MeshStandardMaterial({ color: 0x46503a, roughness: 0.9 }),
      jacketDark: new THREE.MeshStandardMaterial({ color: 0x343c2c, roughness: 0.9 }),
      pants: new THREE.MeshStandardMaterial({ color: 0x30394a, roughness: 0.9 }),
      skin: new THREE.MeshStandardMaterial({ color: 0xc69a7a, roughness: 0.65 }),
      boots: new THREE.MeshStandardMaterial({ color: 0x2a2018, roughness: 0.8 }),
      sole: new THREE.MeshStandardMaterial({ color: 0x141210, roughness: 0.9 }),
      bag: new THREE.MeshStandardMaterial({ color: 0x5e4e34, roughness: 0.9 }),
      leather: new THREE.MeshStandardMaterial({ color: 0x3a2a1c, roughness: 0.7 }),
      buckle: new THREE.MeshStandardMaterial({ color: 0x8a8a80, roughness: 0.4, metalness: 0.8 }),
      beanie: new THREE.MeshStandardMaterial({ color: 0x6a2e24, roughness: 1 }),
      eye: new THREE.MeshStandardMaterial({ color: 0x1a1612, roughness: 0.3 }),
      beard: new THREE.MeshStandardMaterial({ color: 0x3a2c22, roughness: 1 }),
      glove: new THREE.MeshStandardMaterial({ color: 0x2a2620, roughness: 0.8 }),
    };
    this.fpHidden = [];

    this.root = new THREE.Group();
    this.root.rotation.order = 'YXZ'; // gira (yaw) primeiro, depois tomba no eixo do corpo
    this.body = new THREE.Group();     // deslocado para trás em 1ª pessoa
    this.root.add(this.body);
    this.hips = new THREE.Group();
    this.hips.position.y = 0.95;
    this.body.add(this.hips);

    // quadril e cinto
    this.hips.add(part(new THREE.BoxGeometry(0.36, 0.2, 0.22), M.pants, 0, -0.02, 0));
    this.hips.add(part(new THREE.BoxGeometry(0.38, 0.05, 0.24), M.leather, 0, 0.08, 0));
    this.hips.add(part(new THREE.BoxGeometry(0.06, 0.05, 0.02), M.buckle, 0, 0.08, -0.125));

    // tronco
    this.torso = new THREE.Group();
    this.hips.add(this.torso);
    const chest = part(new THREE.CapsuleGeometry(0.2, 0.28, 4, 12), M.jacket, 0, 0.32, 0);
    chest.scale.set(1.12, 1, 0.66);
    this.torso.add(chest);
    this.torso.add(part(new THREE.BoxGeometry(0.012, 0.42, 0.01), M.jacketDark, 0, 0.3, -0.135)); // zíper
    for (const s of [-1, 1]) { // bolsos
      this.torso.add(part(new THREE.BoxGeometry(0.11, 0.1, 0.02), M.jacketDark, s * 0.11, 0.2, -0.128));
    }
    const collar = part(new THREE.TorusGeometry(0.1, 0.035, 6, 12), M.jacketDark, 0, 0.6, 0);
    collar.rotation.x = Math.PI / 2;
    this.torso.add(collar);
    // mochila com saco de dormir e alças
    this.torso.add(part(new THREE.BoxGeometry(0.34, 0.42, 0.17), M.bag, 0, 0.33, 0.2));
    this.torso.add(part(new THREE.BoxGeometry(0.28, 0.14, 0.04), M.leather, 0, 0.22, 0.29));
    const roll = part(new THREE.CylinderGeometry(0.08, 0.08, 0.38, 10), M.jacketDark, 0, 0.6, 0.2);
    roll.rotation.z = Math.PI / 2;
    this.torso.add(roll);
    for (const s of [-1, 1]) {
      const strap = part(new THREE.BoxGeometry(0.05, 0.36, 0.015), M.leather, s * 0.1, 0.38, -0.13);
      strap.rotation.z = s * 0.08;
      this.torso.add(strap);
    }

    // pescoço e cabeça
    const neck = part(new THREE.CylinderGeometry(0.055, 0.065, 0.1, 8), M.skin, 0, 0.62, 0);
    this.torso.add(neck);
    this.head = new THREE.Group();
    this.head.position.y = 0.66;
    const skull = part(new THREE.SphereGeometry(0.125, 14, 12), M.skin, 0, 0.13, 0);
    skull.scale.set(0.95, 1.12, 1.02);
    const beanie = part(new THREE.SphereGeometry(0.133, 14, 8, 0, Math.PI * 2, 0, Math.PI / 2), M.beanie, 0, 0.16, 0.005);
    beanie.scale.set(1, 1.15, 1.05);
    const fold = part(new THREE.CylinderGeometry(0.135, 0.135, 0.04, 14), M.beanie, 0, 0.165, 0.005);
    const beard = part(new THREE.SphereGeometry(0.1, 10, 8, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), M.beard, 0, 0.1, -0.03);
    beard.scale.set(1.05, 0.8, 1.05);
    const nose = part(new THREE.BoxGeometry(0.03, 0.045, 0.04), M.skin, 0, 0.12, -0.13);
    this.head.add(skull, beanie, fold, beard, nose);
    for (const s of [-1, 1]) {
      this.head.add(part(new THREE.BoxGeometry(0.03, 0.018, 0.01), M.eye, s * 0.045, 0.15, -0.118));
      this.head.add(part(new THREE.SphereGeometry(0.025, 6, 6), M.skin, s * 0.125, 0.12, 0)); // orelhas
    }
    this.torso.add(this.head);
    this.fpHidden.push(neck, collar);
    this.head.traverse((o) => { if (o.isMesh) this.fpHidden.push(o); });

    // braços: ombro → cotovelo → mão
    const makeArm = (s) => {
      const shoulder = new THREE.Group();
      shoulder.position.set(s * 0.25, 0.52, 0);
      shoulder.add(part(new THREE.SphereGeometry(0.075, 10, 8), M.jacket, 0, 0, 0));
      const upper = limb(0.12, 0.32, 0.12, M.jacket, -0.15);
      shoulder.add(upper);
      const elbow = limb(0.105, 0.3, 0.105, M.jacket, -0.14);
      elbow.position.y = -0.3;
      upper.add(elbow);
      elbow.add(part(new THREE.BoxGeometry(0.08, 0.1, 0.09), M.glove, 0, -0.32, -0.005));
      shoulder.userData = { upper, elbow };
      shoulder.traverse((o) => { if (o.isMesh) this.fpHidden.push(o); });
      return shoulder;
    };
    this.armL = makeArm(-1);
    this.armR = makeArm(1);
    this.torso.add(this.armL, this.armR);

    // pernas: quadril → joelho → bota
    const makeLeg = (x) => {
      const thigh = limb(0.17, 0.46, 0.18, M.pants, -0.23);
      thigh.position.set(x, -0.04, 0);
      const knee = limb(0.15, 0.46, 0.16, M.pants, -0.23);
      knee.position.y = -0.44;
      const boot = part(new THREE.BoxGeometry(0.15, 0.13, 0.27), M.boots, 0, -0.45, -0.045);
      boot.add(part(new THREE.BoxGeometry(0.16, 0.035, 0.29), M.sole, 0, -0.07, 0));
      knee.add(boot);
      thigh.add(knee);
      thigh.userData.knee = knee;
      return thigh;
    };
    this.legL = makeLeg(-0.1);
    this.legR = makeLeg(0.1);
    this.hips.add(this.legL, this.legR);

    this.torso.traverse((o) => { if (o.isMesh && !this.fpHidden.includes(o)) this.fpHidden.push(o); });
    this.root.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    scene.add(this.root);

    this.blend = { run: 0, move: 0, crouch: 0, air: 0, climb: 0, death: 0, ladder: 0, slide: 0 };
    this.lean = 0;
    this.t = 0;
    this.yaw = 0;
    this.firstPerson = true;
    this.setFirstPerson(true);
  }

  /** Em 1ª pessoa, tronco, cabeça e braços somem da câmera mas continuam projetando sombra. */
  setFirstPerson(fp) {
    this.firstPerson = fp;
    for (const m of this.fpHidden) m.layers.set(fp ? FP_HIDDEN_LAYER : 0);
  }

  update(dt, player, attacking) {
    this.t += dt;
    const b = this.blend;
    this.root.position.copy(player.feetPosition);

    // gira suavemente para a direção da câmera (na escada, de frente para ela)
    let targetYaw = player.yaw;
    if (player.onLadder) targetYaw = Math.atan2(player.ladder.l.nx, player.ladder.l.nz);
    let dy = targetYaw - this.yaw;
    dy = Math.atan2(Math.sin(dy), Math.cos(dy));
    this.yaw += dy * (1 - Math.exp(-14 * dt));
    this.root.rotation.y = this.yaw;

    const speed = player.horizontalSpeed;
    b.move = damp(b.move, player.onFloor && !player.sliding ? Math.min(speed / 4.2, 1) : 0, 10, dt);
    b.run = damp(b.run, player.sprinting && speed > 1 ? 1 : 0, 8, dt);
    b.crouch = damp(b.crouch, player.crouched && !player.sliding ? 1 : 0, 10, dt);
    b.air = damp(b.air, player.onFloor || player.isClimbing || player.onLadder ? 0 : 1, 10, dt);
    b.climb = damp(b.climb, player.isClimbing && !player.climb?.toLadder ? 1 : 0, 14, dt);
    b.ladder = damp(b.ladder, player.onLadder || player.climb?.toLadder ? 1 : 0, 10, dt);
    b.slide = damp(b.slide, player.sliding ? 1 : 0, 12, dt);
    b.death = damp(b.death, player.dead ? 1 : 0, player.dead ? 3 : 30, dt);
    this.lean = player.lean;

    // em 1ª pessoa o corpo fica um pouco atrás da câmera (sem atravessar a visão)
    this.body.position.z = this.firstPerson ? 0.1 + b.crouch * 0.1 + b.slide * 0.2 : 0;

    // direção do movimento relativa ao corpo (andar de costas inverte o passo)
    const backwards = player.moveInput.y < -0.1 ? -1 : 1;
    const ph = player.stepPhase * backwards;
    const swing = Math.sin(ph);
    const amp = (0.55 + b.run * 0.45) * b.move;
    const kneeL = this.legL.userData.knee, kneeR = this.legR.userData.knee;

    // ---------- pernas ----------
    // (rotação x positiva leva o membro para frente; o joelho dobra para trás)
    const crouchBend = b.crouch * 1.1;
    this.legL.rotation.x = swing * amp + crouchBend + b.air * 0.6;
    this.legR.rotation.x = -swing * amp + crouchBend - b.air * 0.1;
    kneeL.rotation.x = -(Math.max(0, -Math.cos(ph)) * amp * 1.3 + crouchBend * 1.7 + b.air * 1.0);
    kneeR.rotation.x = -(Math.max(0, Math.cos(ph)) * amp * 1.3 + crouchBend * 1.7 + b.air * 0.4);

    // quadril: desce ao agachar, quica ao andar
    const bounce = Math.abs(Math.cos(ph)) * 0.05 * b.move;
    this.hips.position.y = 0.95 - b.crouch * 0.38 + bounce - b.air * 0.05;
    this.hips.position.x = this.lean * 0.05;
    this.hips.rotation.x = 0;

    // ---------- tronco e cabeça ----------
    const fpLean = this.firstPerson ? 0.5 : 1;
    this.torso.rotation.x = -(b.run * 0.22 + b.crouch * 0.35) * fpLean;
    this.torso.rotation.y = swing * 0.12 * b.move;
    this.torso.rotation.z = -this.lean * 0.35;
    this.torso.scale.y = 1 + Math.sin(this.t * 1.8) * 0.01 * (1 - b.move);
    this.head.rotation.x = player.pitch * 0.6 - this.torso.rotation.x;

    // ---------- braços ----------
    const armAmp = amp * (0.9 + b.run * 0.4);
    const { upper: uL, elbow: eL } = this.armL.userData;
    const { upper: uR, elbow: eR } = this.armR.userData;
    uL.rotation.set(-swing * armAmp + b.run * 0.25 + b.air * 0.5, 0, -0.1 - b.air * 0.4);
    uR.rotation.set(swing * armAmp + b.run * 0.25 + b.air * 0.5, 0, 0.1 + b.air * 0.4);
    // cotovelos dobram mais correndo
    eL.rotation.x = 0.25 + b.run * 1.1 + Math.max(0, -swing) * 0.3 * b.move;
    eR.rotation.x = 0.25 + b.run * 1.1 + Math.max(0, swing) * 0.3 * b.move;

    if (attacking) {
      uR.rotation.x = 1.5;
      uR.rotation.z = 0.35;
      eR.rotation.x = 0.4;
    }

    // ---------- escalada ----------
    const c = b.climb;
    if (c > 0.001) {
      const pr = player.climbProgress;
      const armX = 2.7 - pr * 1.7; // mãos no topo e depois empurrando para baixo
      uL.rotation.x = lerp(uL.rotation.x, armX, c);
      uR.rotation.x = lerp(uR.rotation.x, armX, c);
      eL.rotation.x = lerp(eL.rotation.x, 0.2 + pr * 0.8, c);
      eR.rotation.x = lerp(eR.rotation.x, 0.2 + pr * 0.8, c);
      this.legR.rotation.x = lerp(this.legR.rotation.x, 1.3 * Math.sin(pr * Math.PI), c);
      kneeR.rotation.x = lerp(kneeR.rotation.x, -1.6 * Math.sin(pr * Math.PI), c);
      this.torso.rotation.x = lerp(this.torso.rotation.x, -0.45, c);
    }

    // ---------- escada de mão: mãos e pés alternados ----------
    const L = b.ladder;
    if (L > 0.001) {
      const lp = player.ladderPhase;
      const altL = Math.sin(lp), altR = Math.sin(lp + Math.PI);
      uL.rotation.x = lerp(uL.rotation.x, 2.7 + altL * 0.3, L);
      uR.rotation.x = lerp(uR.rotation.x, 2.7 + altR * 0.3, L);
      eL.rotation.x = lerp(eL.rotation.x, 0.5 + altL * 0.3, L);
      eR.rotation.x = lerp(eR.rotation.x, 0.5 + altR * 0.3, L);
      uL.rotation.z = lerp(uL.rotation.z, -0.15, L);
      uR.rotation.z = lerp(uR.rotation.z, 0.15, L);
      this.legL.rotation.x = lerp(this.legL.rotation.x, 0.5 + altR * 0.4, L);
      this.legR.rotation.x = lerp(this.legR.rotation.x, 0.5 + altL * 0.4, L);
      kneeL.rotation.x = lerp(kneeL.rotation.x, -0.9 - altR * 0.4, L);
      kneeR.rotation.x = lerp(kneeR.rotation.x, -0.9 - altL * 0.4, L);
      this.torso.rotation.x = lerp(this.torso.rotation.x, 0.05, L);
    }

    // ---------- deslize: pernas para frente, corpo para trás ----------
    const S = b.slide;
    if (S > 0.001) {
      this.legL.rotation.x = lerp(this.legL.rotation.x, 1.45, S);
      kneeL.rotation.x = lerp(kneeL.rotation.x, -0.15, S);
      this.legR.rotation.x = lerp(this.legR.rotation.x, 0.9, S);
      kneeR.rotation.x = lerp(kneeR.rotation.x, -1.6, S);
      this.hips.position.y = lerp(this.hips.position.y, 0.32, S);
      this.torso.rotation.x = lerp(this.torso.rotation.x, 0.45, S);
      uL.rotation.z = lerp(uL.rotation.z, -1.0, S);
      uR.rotation.z = lerp(uR.rotation.z, 0.6, S);
    }

    // ---------- rolamento: o corpo encolhido gira para frente ----------
    if (player.rolling) {
      const k = Math.min(1, player.rollTime / 0.65);
      const tuck = Math.sin(k * Math.PI);
      this.hips.rotation.x = -k * Math.PI * 2;
      this.hips.position.y = lerp(this.hips.position.y, 0.45, tuck);
      this.legL.rotation.x = this.legR.rotation.x = lerp(this.legL.rotation.x, 1.6, tuck);
      kneeL.rotation.x = kneeR.rotation.x = lerp(kneeL.rotation.x, -2.2, tuck);
      this.torso.rotation.x = lerp(this.torso.rotation.x, -0.9, tuck);
    }

    // ---------- morte: cai de costas ----------
    const d = b.death;
    this.root.rotation.x = d * 1.45;
    this.root.position.y += d * 0.12;
    if (d > 0.01) {
      uL.rotation.z -= d * 0.6;
      uR.rotation.z += d * 0.6;
    }
  }
}
