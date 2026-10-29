import * as THREE from 'three';

// Revólver .357 de cano de 4" (estilo do Colt Python do Carl), feito em código.
// Convenção: origem no centro da empunhadura (onde a mão segura), cano para -Z, +Y para cima.
// Tem tambor que gira a cada tiro e abre para o lado na recarga, cão que arma, gatilho,
// clarão na boca do cano e cápsulas vazias que caem ao recarregar.

export const CAPACITY = 6;
export const SIGHT_Y = 0.083;      // altura da linha de mira acima da empunhadura
const BORE_Y = 0.062;
const MUZZLE_Z = -0.178;

function flashTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d');
  const r = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  r.addColorStop(0, 'rgba(255,250,220,1)');
  r.addColorStop(0.25, 'rgba(255,200,90,0.9)');
  r.addColorStop(0.6, 'rgba(255,120,30,0.35)');
  r.addColorStop(1, 'rgba(255,90,0,0)');
  g.fillStyle = r;
  g.fillRect(0, 0, 64, 64);
  // pontas do clarão
  g.globalCompositeOperation = 'lighter';
  g.fillStyle = 'rgba(255,220,140,0.5)';
  for (let i = 0; i < 6; i++) {
    g.save(); g.translate(32, 32); g.rotate((i / 6) * Math.PI * 2);
    g.beginPath(); g.moveTo(0, -3); g.lineTo(30, 0); g.lineTo(0, 3); g.fill();
    g.restore();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

export class Revolver {
  constructor(scene) {
    this.scene = scene;
    const steel = new THREE.MeshStandardMaterial({ color: 0x2a2d33, metalness: 0.85, roughness: 0.32 });
    const steelDark = new THREE.MeshStandardMaterial({ color: 0x17191c, metalness: 0.8, roughness: 0.45 });
    const wood = new THREE.MeshStandardMaterial({ color: 0x4e2f1a, roughness: 0.62, metalness: 0.05 });
    const brass = new THREE.MeshStandardMaterial({ color: 0xb08a3c, metalness: 0.9, roughness: 0.3 });
    this.brassMat = brass;
    const g = new THREE.Group();
    const add = (geo, mat, x, y, z, parent = g) => {
      const m = new THREE.Mesh(geo, mat);
      m.position.set(x, y, z);
      m.castShadow = true;
      parent.add(m);
      return m;
    };
    // empunhadura de madeira (inclinada para trás) com medalhão
    const grip = add(new THREE.BoxGeometry(0.027, 0.1, 0.036), wood, 0, -0.005, 0.012);
    grip.rotation.x = -0.28;
    add(new THREE.CylinderGeometry(0.006, 0.006, 0.029, 10), brass, 0, 0.01, 0.008).rotation.z = Math.PI / 2;
    add(new THREE.BoxGeometry(0.029, 0.012, 0.03), steel, 0, -0.056, 0.026).rotation.x = -0.28; // base
    // armação
    add(new THREE.BoxGeometry(0.024, 0.04, 0.06), steel, 0, 0.05, -0.025);
    add(new THREE.BoxGeometry(0.024, 0.016, 0.03), steel, 0, 0.068, 0.0); // topo traseiro
    // cano com nervura ventilada e "underlug" cheio até a boca
    const barrel = add(new THREE.CylinderGeometry(0.0085, 0.0085, 0.112, 14), steel, 0, BORE_Y, -0.122);
    barrel.rotation.x = Math.PI / 2;
    add(new THREE.BoxGeometry(0.015, 0.017, 0.106), steel, 0, 0.049, -0.124);
    add(new THREE.BoxGeometry(0.009, 0.007, 0.108), steel, 0, 0.073, -0.122);
    for (let i = 0; i < 5; i++) add(new THREE.BoxGeometry(0.0095, 0.003, 0.008), steelDark, 0, 0.0745, -0.08 - i * 0.02);
    const bore = add(new THREE.CircleGeometry(0.0045, 10), new THREE.MeshBasicMaterial({ color: 0x050505 }), 0, BORE_Y, MUZZLE_Z - 0.001);
    bore.rotation.y = Math.PI;
    // miras: alça (atrás) e massa (na frente), topo na linha de mira
    add(new THREE.BoxGeometry(0.004, 0.013, 0.014), steel, 0, SIGHT_Y - 0.0065, -0.166);
    add(new THREE.BoxGeometry(0.0035, 0.004, 0.004), new THREE.MeshStandardMaterial({ color: 0xc23a1e, roughness: 0.5 }), 0, SIGHT_Y - 0.003, -0.162);
    for (const s of [-1, 1]) add(new THREE.BoxGeometry(0.004, 0.009, 0.008), steel, s * 0.0045, SIGHT_Y - 0.0045, -0.004);
    // guarda-mato e gatilho
    const guard = add(new THREE.TorusGeometry(0.015, 0.0025, 6, 14, Math.PI * 1.15), steel, 0, 0.03, -0.028);
    guard.rotation.set(0, Math.PI / 2, Math.PI * 0.93);
    this.trigger = add(new THREE.BoxGeometry(0.004, 0.017, 0.005), steelDark, 0, 0.026, -0.024);
    this.trigger.geometry.translate(0, -0.006, 0);
    // cão (gira para trás ao armar)
    this.hammer = new THREE.Group();
    this.hammer.position.set(0, 0.066, 0.012);
    g.add(this.hammer);
    add(new THREE.BoxGeometry(0.006, 0.022, 0.01), steelDark, 0, 0.008, 0.002, this.hammer);
    add(new THREE.BoxGeometry(0.008, 0.005, 0.012), steelDark, 0, 0.018, 0.008, this.hammer);
    // tambor: pivô na haste (crane) à esquerda/embaixo, abre girando para a esquerda
    this.crane = new THREE.Group();
    this.crane.position.set(-0.004, 0.036, -0.045);
    g.add(this.crane);
    this.cyl = new THREE.Group();
    this.cyl.position.set(0.004, 0.013, 0); // eixo do tambor (o furo de cima alinha com o cano)
    this.crane.add(this.cyl);
    const cylGeo = new THREE.CylinderGeometry(0.0195, 0.0195, 0.042, 18);
    cylGeo.rotateX(Math.PI / 2);
    add(cylGeo, steel, 0, 0, 0, this.cyl);
    // caneluras e as 6 câmaras com cartuchos
    this.rounds = [];
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2;
      const fl = add(new THREE.BoxGeometry(0.005, 0.003, 0.03), steelDark, Math.sin(a + Math.PI / 6) * 0.019, Math.cos(a + Math.PI / 6) * 0.019, -0.004, this.cyl);
      fl.rotation.z = -(a + Math.PI / 6);
      const r = add(new THREE.CylinderGeometry(0.0048, 0.0048, 0.004, 8), brass, Math.sin(a) * 0.0125, Math.cos(a) * 0.0125, 0.0215, this.cyl);
      r.rotation.x = Math.PI / 2;
      this.rounds.push(r);
    }
    const rod = add(new THREE.CylinderGeometry(0.0025, 0.0025, 0.06, 6), steel, 0, -0.004, -0.045, this.crane);
    rod.rotation.x = Math.PI / 2;
    this.model = g;
    this.muzzleLocal = new THREE.Vector3(0, BORE_Y, MUZZLE_Z - 0.005);

    // clarão + luz do tiro
    this.flash = new THREE.Sprite(new THREE.SpriteMaterial({ map: flashTexture(), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
    this.flash.visible = false;
    this.flash.scale.setScalar(0.22);
    scene.add(this.flash);
    this.light = new THREE.PointLight(0xffb060, 0, 9, 2);
    scene.add(this.light);
    this.flashT = 0;

    // estado
    this.loaded = CAPACITY;
    this.reserve = 12;
    this.cylAngle = 0;
    this.cylTarget = 0;
    this.cock = 0;           // cão armado (0..1)
    this.open = 0;           // tambor aberto (0..1)
    this.shells = [];        // cápsulas caindo
    this.shellGeo = new THREE.CylinderGeometry(0.0048, 0.0048, 0.033, 8);
    this._v = new THREE.Vector3();
    this._q = new THREE.Quaternion();
    this.setLoaded(this.loaded);
  }

  /** Mostra os cartuchos no tambor. */
  setLoaded(n) {
    this.loaded = n;
    this.rounds.forEach((r, i) => { r.visible = i < n; });
  }

  get muzzleWorld() {
    this.model.updateWorldMatrix(true, false);
    return this.model.localToWorld(this._v.copy(this.muzzleLocal));
  }

  /** Tiro: gira o tambor, cão cai, clarão e luz. */
  fire() {
    this.loaded--;
    // a câmara disparada fica vazia (aparece a cápsula); o tambor gira 1/6
    this.cylTarget += Math.PI / 3;
    this.cock = 0;
    this.flashT = 0.06;
    const p = this.muzzleWorld;
    this.flash.position.copy(p);
    this.flash.material.rotation = Math.random() * Math.PI;
    this.flash.scale.setScalar(0.16 + Math.random() * 0.1);
    this.light.position.copy(p);
  }

  /** Cápsulas vazias caem do tambor aberto. */
  ejectShells(count) {
    this.model.updateWorldMatrix(true, true);
    for (let i = 0; i < count; i++) {
      const m = new THREE.Mesh(this.shellGeo, this.brassMat);
      const a = (i / 6) * Math.PI * 2;
      this.cyl.localToWorld(m.position.set(Math.sin(a) * 0.0125, Math.cos(a) * 0.0125, 0.01));
      m.quaternion.setFromRotationMatrix(this.cyl.matrixWorld);
      m.castShadow = true;
      this.scene.add(m);
      this.shells.push({ m, v: new THREE.Vector3((Math.random() - 0.5) * 0.6, -0.4 - Math.random() * 0.6, (Math.random() - 0.5) * 0.6), spin: new THREE.Vector3(Math.random() * 9, Math.random() * 9, 0), life: 2.5, bounced: false });
    }
  }

  update(dt, groundAt, onShellBounce) {
    // tambor gira até a próxima câmara; cão volta a armar devagar (ação dupla)
    this.cylAngle += (this.cylTarget - this.cylAngle) * (1 - Math.exp(-30 * dt));
    this.cyl.rotation.z = -this.cylAngle;
    this.cock = Math.max(0, this.cock - dt * 4);
    this.hammer.rotation.x = this.cock * 0.6;
    this.crane.rotation.z = this.open * 1.25; // abre para a esquerda
    this.trigger.rotation.x = this.cock * 0.5;

    if (this.flashT > 0) {
      this.flashT -= dt;
      const k = Math.max(0, this.flashT / 0.06);
      this.flash.visible = k > 0;
      this.flash.material.opacity = k;
      this.light.intensity = 30 * k;
    } else {
      this.flash.visible = false;
      this.light.intensity = 0;
    }

    for (let i = this.shells.length - 1; i >= 0; i--) {
      const s = this.shells[i];
      s.life -= dt;
      s.v.y -= 9.8 * dt;
      s.m.position.addScaledVector(s.v, dt);
      s.m.rotation.x += s.spin.x * dt;
      s.m.rotation.y += s.spin.y * dt;
      const gy = groundAt(s.m.position.x, s.m.position.z) + 0.006;
      if (s.m.position.y < gy) {
        s.m.position.y = gy;
        if (!s.bounced) onShellBounce?.(s.m.position);
        s.bounced = true;
        s.v.multiplyScalar(0.3);
        s.v.y = Math.abs(s.v.y) * 0.4;
        s.spin.multiplyScalar(0.4);
      }
      if (s.life <= 0) {
        this.scene.remove(s.m);
        this.shells.splice(i, 1);
      }
    }
  }
}
