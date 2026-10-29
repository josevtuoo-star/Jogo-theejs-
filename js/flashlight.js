import * as THREE from 'three';

// Lanterna: modelo 3D (usado na mão em 1ª e em 3ª pessoa) e a luz de verdade, que sai da
// lente e aponta para onde o jogador está mirando. Tem o anel típico de lanterna (textura
// projetada), um feixe levemente visível no ar e, de vez em quando, uma piscada de mau contato.

/** Modelo da lanterna, apontando para -Z. A lente fica em userData.lens. */
export function makeFlashlightModel(scale = 1) {
  const g = new THREE.Group();
  const body = new THREE.MeshStandardMaterial({ color: 0x23262a, roughness: 0.45, metalness: 0.7 });
  const grip = new THREE.MeshStandardMaterial({ color: 0x15171a, roughness: 0.9 });
  const chrome = new THREE.MeshStandardMaterial({ color: 0x9a9ea4, roughness: 0.25, metalness: 0.95 });
  const lensMat = new THREE.MeshBasicMaterial({ color: 0x3a3a34 });

  const add = (geo, mat, z, rx = Math.PI / 2) => {
    const m = new THREE.Mesh(geo, mat);
    m.rotation.x = rx;
    m.position.z = z;
    m.castShadow = false; // a própria lanterna não pode fazer sombra na sua luz
    g.add(m);
    return m;
  };
  add(new THREE.CylinderGeometry(0.017, 0.017, 0.12, 12), body, 0.02);           // corpo
  add(new THREE.CylinderGeometry(0.0185, 0.0185, 0.05, 12), grip, 0.035);        // emborrachado
  add(new THREE.CylinderGeometry(0.026, 0.018, 0.035, 14), body, -0.055);       // cabeça
  add(new THREE.TorusGeometry(0.025, 0.004, 6, 16), chrome, -0.073, 0);          // aro
  add(new THREE.CylinderGeometry(0.016, 0.016, 0.008, 10), chrome, 0.083);       // tampa traseira
  const button = new THREE.Mesh(new THREE.BoxGeometry(0.008, 0.006, 0.014), chrome);
  button.position.set(0, 0.018, 0.0);
  g.add(button);
  const lens = add(new THREE.CircleGeometry(0.022, 16), lensMat, -0.0735, 0);
  lens.rotation.y = Math.PI; // a face do círculo olha para -Z
  g.userData.lens = lens;
  g.userData.lensMat = lensMat;
  g.scale.setScalar(scale);
  return g;
}

/** Textura do "anel" de lanterna: centro forte, anel e borda suave. */
function cookieTexture() {
  const s = 128;
  const c = document.createElement('canvas');
  c.width = c.height = s;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
  grad.addColorStop(0, 'rgb(255,255,255)');
  grad.addColorStop(0.18, 'rgb(250,248,240)');
  grad.addColorStop(0.3, 'rgb(170,165,155)');
  grad.addColorStop(0.42, 'rgb(205,200,190)'); // anel do refletor
  grad.addColorStop(0.55, 'rgb(110,106,100)');
  grad.addColorStop(1, 'rgb(0,0,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, s, s);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

export class Flashlight {
  constructor(scene) {
    this.on = false;
    this.light = new THREE.SpotLight(0xfff1d6, 0, 45, Math.PI / 7.5, 0.55, 1.25);
    this.light.shadow.mapSize.set(512, 512);
    this.light.shadow.camera.near = 0.1;
    this.light.shadow.bias = -0.0008;
    this.light.shadow.normalBias = 0.02;
    this.cookie = cookieTexture();
    scene.add(this.light, this.light.target);

    // feixe visível: cone aditivo bem fraco que some na ponta e nas bordas
    const len = 7;
    const radius = Math.tan(Math.PI / 7.5) * len;
    const geo = new THREE.ConeGeometry(radius, len, 24, 1, true);
    geo.translate(0, -len / 2, 0);
    geo.rotateX(Math.PI / 2); // ponta na origem, abre para -Z
    this.beamMat = new THREE.ShaderMaterial({
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
      blending: THREE.AdditiveBlending,
      uniforms: { uOpacity: { value: 0 }, uLen: { value: len } },
      vertexShader: `
        varying float vAlong; varying vec3 vN; varying vec3 vView;
        uniform float uLen;
        void main() {
          vAlong = clamp(-position.z / uLen, 0.0, 1.0);
          vec4 mv = modelViewMatrix * vec4(position, 1.0);
          vN = normalize(normalMatrix * normal);
          vView = normalize(-mv.xyz);
          gl_Position = projectionMatrix * mv;
        }`,
      fragmentShader: `
        varying float vAlong; varying vec3 vN; varying vec3 vView;
        uniform float uOpacity;
        void main() {
          float edge = pow(abs(dot(vN, vView)), 1.5);
          float a = uOpacity * (1.0 - vAlong) * (1.0 - vAlong) * edge * smoothstep(0.0, 0.08, vAlong);
          gl_FragColor = vec4(vec3(1.0, 0.93, 0.8) * a, 1.0);
        }`,
    });
    this.beam = new THREE.Mesh(geo, this.beamMat);
    this.beam.frustumCulled = false;
    this.beam.renderOrder = 5;
    scene.add(this.beam);

    // brilho da lente (visto principalmente em 3ª pessoa)
    const gc = document.createElement('canvas');
    gc.width = gc.height = 64;
    const gg = gc.getContext('2d');
    const rg = gg.createRadialGradient(32, 32, 0, 32, 32, 32);
    rg.addColorStop(0, 'rgba(255,245,220,1)');
    rg.addColorStop(0.3, 'rgba(255,230,180,0.5)');
    rg.addColorStop(1, 'rgba(255,220,160,0)');
    gg.fillStyle = rg;
    gg.fillRect(0, 0, 64, 64);
    this.glow = new THREE.Sprite(new THREE.SpriteMaterial({
      map: new THREE.CanvasTexture(gc), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true,
    }));
    this.glow.scale.setScalar(0.35);
    scene.add(this.glow);

    this.flicker = 1;
    this.flickerTimer = 25 + Math.random() * 30;
    this.flickerT = -1;
    this._q = new THREE.Quaternion();
    this._up = new THREE.Vector3(0, 0, -1);
  }

  /** Sombras da lanterna (só em qualidade média/alta). Retorna true se mudou. */
  setShadows(enabled) {
    if (this.light.castShadow === enabled) return false;
    this.light.castShadow = enabled;
    // a textura do anel exige mapa de sombra
    this.light.map = enabled ? this.cookie : null;
    return true;
  }

  toggle() {
    this.on = !this.on;
    return this.on;
  }

  /**
   * origin: posição da lente no mundo; aim: ponto para onde a luz aponta.
   * showBeamGlow: em 1ª pessoa o brilho da lente fica no modelo dos braços.
   */
  update(dt, origin, aim, { thirdPerson = false } = {}) {
    // mau contato ocasional: algumas piscadas rápidas
    this.flickerTimer -= dt;
    if (this.on && this.flickerTimer <= 0 && this.flickerT < 0) {
      this.flickerT = 0;
      this.flickerTimer = 30 + Math.random() * 50;
    }
    if (this.flickerT >= 0) {
      this.flickerT += dt;
      const t = this.flickerT;
      this.flicker = t < 0.5 ? (Math.sin(t * 70) > 0.2 ? 1 : 0.15) : 1;
      if (t > 0.5) this.flickerT = -1;
    } else {
      this.flicker = 1;
    }

    const k = this.on ? this.flicker : 0;
    this.light.intensity = 42 * k;
    // desligada: não redesenha o mapa de sombra (economiza uma renderização inteira da cena)
    this.light.shadow.autoUpdate = this.on;
    this.light.position.copy(origin);
    this.light.target.position.copy(aim);
    this.light.target.updateMatrixWorld();

    this.beam.visible = k > 0;
    this.beam.position.copy(origin);
    this.beam.lookAt(aim);
    this.beam.rotateY(Math.PI); // lookAt aponta +Z; o cone abre para -Z
    this.beamMat.uniforms.uOpacity.value = (thirdPerson ? 0.07 : 0.035) * k;

    this.glow.visible = thirdPerson && k > 0;
    this.glow.position.copy(origin);
    this.glow.material.opacity = k;
    return k;
  }
}
