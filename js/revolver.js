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

/** Textura da empunhadura: madeira de nogueira com quadriculado. */
function woodGripTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  g.fillStyle = '#5a341b';
  g.fillRect(0, 0, 128, 128);
  for (let i = 0; i < 40; i++) {
    g.strokeStyle = `rgba(${30 + Math.random() * 30},${15 + Math.random() * 15},5,0.35)`;
    g.lineWidth = 1 + Math.random() * 2;
    g.beginPath();
    const y = Math.random() * 128;
    g.moveTo(0, y);
    g.bezierCurveTo(40, y + Math.random() * 10 - 5, 80, y + Math.random() * 10 - 5, 128, y + Math.random() * 6 - 3);
    g.stroke();
  }
  // quadriculado de pegada no meio
  g.strokeStyle = 'rgba(20,10,4,0.35)';
  g.lineWidth = 1;
  for (let i = -128; i < 256; i += 5) {
    g.beginPath(); g.moveTo(i, 30); g.lineTo(i + 70, 100); g.stroke();
    g.beginPath(); g.moveTo(i + 70, 30); g.lineTo(i, 100); g.stroke();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(18, 18); // UV do ExtrudeGeometry está em metros
  return t;
}

/** Ponto da empunhadura onde a palma da mão direita encosta (espaço da arma). */
export const GRIP = new THREE.Vector3(0, -0.012, 0.016);

export class Revolver {
  constructor(scene) {
    this.scene = scene;
    const steel = new THREE.MeshStandardMaterial({ color: 0x3b4048, metalness: 0.92, roughness: 0.26 });
    const steelDark = new THREE.MeshStandardMaterial({ color: 0x1c1f23, metalness: 0.85, roughness: 0.4 });
    const wood = new THREE.MeshStandardMaterial({ map: woodGripTexture(), roughness: 0.55, metalness: 0.05 });
    const brass = new THREE.MeshStandardMaterial({ color: 0xc09643, metalness: 0.9, roughness: 0.28 });
    this.brassMat = brass;
    const g = new THREE.Group();
    const add = (geo, mat, x, y, z, parent = g) => {
      const m = new THREE.Mesh(geo, mat);
      m.position.set(x, y, z);
      m.castShadow = true;
      parent.add(m);
      return m;
    };
    // perfil lateral (u = para frente, v = para cima) extrudado com borda arredondada; vira -Z
    const profile = (pts, depth, bevel, mat) => {
      const sh = new THREE.Shape();
      sh.moveTo(pts[0][0], pts[0][1]);
      for (let i = 1; i < pts.length; i++) {
        const p = pts[i];
        if (p.length === 4) sh.quadraticCurveTo(p[0], p[1], p[2], p[3]); else sh.lineTo(p[0], p[1]);
      }
      const geo = new THREE.ExtrudeGeometry(sh, { depth: depth - bevel * 2, bevelEnabled: true, bevelThickness: bevel, bevelSize: bevel, bevelSegments: 2, curveSegments: 6 });
      geo.translate(0, 0, -(depth - bevel * 2) / 2);
      geo.rotateY(Math.PI / 2); // u → -Z, espessura → X
      return add(geo, mat, 0, 0, 0);
    };
    // armação: recoil shield, top strap sobre o tambor e a parte de baixo até o guarda-mato
    profile([[-0.02, 0.064], [-0.008, 0.075, 0.004, 0.077], [0.074, 0.077], [0.074, 0.044], [0.064, 0.039], [0.03, 0.034],
      [0.016, 0.027], [0.0, 0.026], [-0.012, 0.031], [-0.024, 0.045, -0.022, 0.056]], 0.023, 0.0025, steel);
    // empunhadura de madeira (curva, com o "dedo" de baixo arredondado)
    profile([[-0.002, 0.03], [0.004, 0.0, 0.0, -0.02], [-0.004, -0.05, -0.012, -0.062], [-0.03, -0.066, -0.038, -0.058],
      [-0.036, -0.02], [-0.028, 0.03, -0.022, 0.05], [-0.01, 0.04]], 0.031, 0.005, wood);
    add(new THREE.CylinderGeometry(0.006, 0.006, 0.033, 12), brass, 0, -0.012, 0.018).rotation.z = Math.PI / 2; // medalhão
    // cano: tubo + "underlug" cheio + nervura ventilada (perfil do Python)
    const barrel = add(new THREE.CylinderGeometry(0.0088, 0.0088, 0.105, 18), steel, 0, BORE_Y, -0.1255);
    barrel.rotation.x = Math.PI / 2;
    profile([[0.074, 0.043], [0.178, 0.043], [0.178, 0.058], [0.074, 0.058]], 0.016, 0.003, steel);   // underlug
    profile([[0.07, 0.066], [0.176, 0.066], [0.176, 0.075], [0.07, 0.077]], 0.0095, 0.0015, steel);  // nervura
    for (let i = 0; i < 6; i++) add(new THREE.BoxGeometry(0.0105, 0.0035, 0.007), steelDark, 0, 0.0745, -0.083 - i * 0.016);
    const bore = add(new THREE.CircleGeometry(0.0046, 12), new THREE.MeshBasicMaterial({ color: 0x030303 }), 0, BORE_Y, MUZZLE_Z - 0.0005);
    bore.rotation.y = Math.PI;
    // miras: massa em rampa com ponto vermelho e alça com entalhe
    profile([[0.15, 0.076], [0.17, 0.076], [0.17, SIGHT_Y], [0.162, SIGHT_Y]], 0.0035, 0.0006, steel);
    add(new THREE.BoxGeometry(0.0038, 0.0035, 0.004), new THREE.MeshStandardMaterial({ color: 0xd8341a, roughness: 0.4, emissive: 0x3a0800 }), 0, SIGHT_Y - 0.0028, -0.165);
    for (const sx of [-1, 1]) add(new THREE.BoxGeometry(0.0045, 0.008, 0.007), steel, sx * 0.0048, SIGHT_Y - 0.004, -0.002);
    // guarda-mato e gatilho
    const guard = add(new THREE.TorusGeometry(0.0145, 0.0022, 6, 16, Math.PI * 1.1), steel, 0, 0.028, -0.026);
    guard.rotation.set(0, Math.PI / 2, Math.PI * 0.95);
    this.trigger = add(new THREE.BoxGeometry(0.004, 0.017, 0.005), steelDark, 0, 0.026, -0.022);
    this.trigger.geometry.translate(0, -0.006, 0);
    // cão (gira para trás ao armar)
    this.hammer = new THREE.Group();
    this.hammer.position.set(0, 0.066, 0.014);
    g.add(this.hammer);
    add(new THREE.BoxGeometry(0.006, 0.022, 0.009), steelDark, 0, 0.008, 0.002, this.hammer);
    add(new THREE.BoxGeometry(0.009, 0.004, 0.012), steelDark, 0, 0.018, 0.009, this.hammer);
    // tambor: pivô na haste (crane) à esquerda/embaixo, abre girando para a esquerda
    this.crane = new THREE.Group();
    this.crane.position.set(-0.004, 0.036, -0.045);
    g.add(this.crane);
    this.cyl = new THREE.Group();
    this.cyl.position.set(0.004, 0.013, 0);
    this.crane.add(this.cyl);
    const cylGeo = new THREE.CylinderGeometry(0.0198, 0.0198, 0.04, 24);
    cylGeo.rotateX(Math.PI / 2);
    add(cylGeo, steel, 0, 0, 0, this.cyl);
    const front = new THREE.CylinderGeometry(0.0172, 0.0198, 0.003, 24);
    front.rotateX(Math.PI / 2);
    add(front, steel, 0, 0, -0.0215, this.cyl);
    // caneluras e as 6 câmaras com cartuchos
    this.rounds = [];
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2;
      const fl = add(new THREE.CylinderGeometry(0.0042, 0.0042, 0.026, 8), steelDark, Math.sin(a + Math.PI / 6) * 0.0185, Math.cos(a + Math.PI / 6) * 0.0185, -0.004, this.cyl);
      fl.rotation.x = Math.PI / 2;
      const r = add(new THREE.CylinderGeometry(0.0048, 0.0048, 0.003, 10), brass, Math.sin(a) * 0.0122, Math.cos(a) * 0.0122, 0.0205, this.cyl);
      r.rotation.x = Math.PI / 2;
      this.rounds.push(r);
      const pr = add(new THREE.CircleGeometry(0.0016, 8), steelDark, Math.sin(a) * 0.0122, Math.cos(a) * 0.0122, 0.0222, this.cyl); // espoleta
      pr.userData.primer = true;
    }
    const rod = add(new THREE.CylinderGeometry(0.0026, 0.0026, 0.058, 8), steel, 0, -0.004, -0.05, this.crane);
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
    this.kind = 'revolver';
    this.capacity = CAPACITY;
    this.sightY = SIGHT_Y;
    this.longGun = false;
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
