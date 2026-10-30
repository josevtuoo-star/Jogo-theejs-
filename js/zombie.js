import * as THREE from 'three';
import { loadModelFile } from './modelLoader.js';

// Zumbi de teste: anda de lá para cá entre dois pontos com a animação de andar do próprio
// modelo (o deslocamento da animação foi tirado; quem anda é o código, na mesma velocidade da
// passada). Nas pontas ele vira devagar e volta.

const damp = (a, b, l, dt) => a + (b - a) * (1 - Math.exp(-l * dt));

export class PatrolZombie {
  constructor(scene, groundHeight) {
    this.scene = scene;
    this.groundHeight = groundHeight;
    this.root = new THREE.Group();
    this.ready = false;
  }

  async load(url, a, b) {
    const g = await loadModelFile(url);
    let meta = null;
    g.scene.traverse((o) => {
      if (!meta && o.userData?.meta) meta = o.userData.meta;
      if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; o.frustumCulled = false; o.material.envMapIntensity = 0.5; o.material.side = THREE.FrontSide; }
    });
    this.speed = meta?.speed ?? 0.33;
    this.root.add(g.scene);
    this.scene.add(this.root);
    this.mixer = new THREE.AnimationMixer(g.scene);
    this.walk = this.mixer.clipAction(g.animations[0]);
    this.walk.play();
    this.a = a.clone(); this.b = b.clone();
    this.target = this.b;
    this.root.position.copy(this.a);
    this.yaw = Math.atan2(b.x - a.x, b.z - a.z); // o modelo olha para +Z
    this.ready = true;
  }

  update(dt) {
    if (!this.ready) return;
    const p = this.root.position;
    const dx = this.target.x - p.x, dz = this.target.z - p.z;
    if (Math.hypot(dx, dz) < 0.4) this.target = this.target === this.b ? this.a : this.b;
    let d = Math.atan2(dx, dz) - this.yaw;
    d = Math.atan2(Math.sin(d), Math.cos(d));
    this.yaw += Math.sign(d) * Math.min(Math.abs(d), 1.1 * dt); // vira devagar
    // virando: anda mais devagar (a passada acompanha)
    const k = Math.max(0.25, Math.cos(Math.min(Math.abs(d), Math.PI / 2)));
    this.walk.timeScale = damp(this.walk.timeScale, k, 4, dt);
    const v = this.speed * this.walk.timeScale;
    p.x += Math.sin(this.yaw) * v * dt;
    p.z += Math.cos(this.yaw) * v * dt;
    p.y = this.groundHeight(p.x, p.z);
    this.root.rotation.y = this.yaw;
    this.mixer.update(dt);
  }
}
