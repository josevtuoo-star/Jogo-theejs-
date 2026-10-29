import * as THREE from 'three';

// Efeitos de partículas: poeira (pouso, deslize, escalada), fumaça e brasas da fogueira
// e folhas caindo ao redor do jogador.

/** Pool de partículas renderizadas como pontos macios (um único draw call). */
class ParticlePool {
  constructor(scene, max, { additive = false } = {}) {
    this.max = max;
    this.next = 0;
    this.pos = new Float32Array(max * 3);
    this.vel = new Float32Array(max * 3);
    this.color = new Float32Array(max * 3);
    this.alpha = new Float32Array(max);
    this.size = new Float32Array(max);
    this.life = new Float32Array(max);
    this.maxLife = new Float32Array(max);
    this.grow = new Float32Array(max);
    this.drag = new Float32Array(max);
    this.gravity = new Float32Array(max);
    this.baseAlpha = new Float32Array(max);

    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('color', new THREE.BufferAttribute(this.color, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('alpha', new THREE.BufferAttribute(this.alpha, 1).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('size', new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage));
    this.geometry = g;

    const mat = new THREE.ShaderMaterial({
      transparent: true,
      depthWrite: false,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
      uniforms: { uScale: { value: 400 } },
      vertexShader: `
        attribute float alpha; attribute float size; attribute vec3 color;
        varying float vAlpha; varying vec3 vColor;
        uniform float uScale;
        void main() {
          vAlpha = alpha; vColor = color;
          vec4 mv = modelViewMatrix * vec4(position, 1.0);
          gl_PointSize = size * uScale / max(-mv.z, 0.1);
          gl_Position = projectionMatrix * mv;
        }`,
      fragmentShader: `
        varying float vAlpha; varying vec3 vColor;
        void main() {
          vec2 c = gl_PointCoord - 0.5;
          float d = dot(c, c) * 4.0;
          if (d > 1.0) discard;
          gl_FragColor = vec4(vColor, vAlpha * (1.0 - d));
          #include <colorspace_fragment>
        }`,
    });
    this.material = mat;
    this.points = new THREE.Points(g, mat);
    this.points.frustumCulled = false;
    scene.add(this.points);
  }

  emit(x, y, z, vx, vy, vz, { life = 1, size = 0.3, grow = 0.5, color = [0.6, 0.55, 0.45], alpha = 0.5, drag = 2, gravity = 0 } = {}) {
    const i = this.next;
    this.next = (this.next + 1) % this.max;
    this.pos.set([x, y, z], i * 3);
    this.vel.set([vx, vy, vz], i * 3);
    this.color.set(color, i * 3);
    this.life[i] = life;
    this.maxLife[i] = life;
    this.size[i] = size;
    this.grow[i] = grow;
    this.drag[i] = drag;
    this.gravity[i] = gravity;
    this.baseAlpha[i] = alpha;
  }

  update(dt, viewportHeight) {
    this.material.uniforms.uScale.value = viewportHeight * 0.6;
    for (let i = 0; i < this.max; i++) {
      if (this.life[i] <= 0) { this.alpha[i] = 0; continue; }
      this.life[i] -= dt;
      const k = Math.exp(-this.drag[i] * dt);
      const o = i * 3;
      this.vel[o] *= k; this.vel[o + 2] *= k;
      this.vel[o + 1] = this.vel[o + 1] * k - this.gravity[i] * dt;
      this.pos[o] += this.vel[o] * dt;
      this.pos[o + 1] += this.vel[o + 1] * dt;
      this.pos[o + 2] += this.vel[o + 2] * dt;
      this.size[i] += this.grow[i] * dt;
      const t = this.life[i] / this.maxLife[i];
      // aparece rápido e some devagar
      this.alpha[i] = this.baseAlpha[i] * Math.min(1, (1 - t) * 8) * t;
    }
    const a = this.geometry.attributes;
    a.position.needsUpdate = a.alpha.needsUpdate = a.size.needsUpdate = a.color.needsUpdate = true;
  }
}

export class Effects {
  constructor(scene, quality) {
    this.scene = scene;
    this.dust = new ParticlePool(scene, quality === 'low' ? 120 : 260);
    this.glow = new ParticlePool(scene, 80, { additive: true });
    this.smoke = new ParticlePool(scene, 140);
    this.smoke.points.material.fog = false;
    this.plumes = [];
    this.fires = [];
    this._buildLeaves(quality === 'low' ? 70 : 160);
    this.t = 0;
  }

  /** Nuvem de poeira no chão (pouso, deslize, escalada). */
  puff(pos, amount = 8, strength = 1, color = [0.55, 0.5, 0.4]) {
    for (let i = 0; i < amount; i++) {
      const a = Math.random() * Math.PI * 2;
      const s = (0.6 + Math.random()) * strength;
      this.dust.emit(
        pos.x + Math.cos(a) * 0.2, pos.y + 0.05, pos.z + Math.sin(a) * 0.2,
        Math.cos(a) * s, 0.3 + Math.random() * 0.5 * strength, Math.sin(a) * s,
        { life: 0.7 + Math.random() * 0.6, size: 0.25 + Math.random() * 0.2, grow: 0.9, color, alpha: 0.35, drag: 3 }
      );
    }
  }

  // ---------- fogueira ----------
  addFire(pos) {
    const light = new THREE.PointLight(0xff8a3a, 6, 14, 1.6);
    light.position.set(pos.x, pos.y + 0.6, pos.z);
    this.scene.add(light);

    // chamas: cones emissivos que tremulam
    const flameMat = new THREE.MeshBasicMaterial({ color: 0xffa040, transparent: true, opacity: 0.85, depthWrite: false, blending: THREE.AdditiveBlending });
    const flames = [];
    for (let i = 0; i < 4; i++) {
      const f = new THREE.Mesh(new THREE.ConeGeometry(0.16 - i * 0.02, 0.6 - i * 0.08, 6, 1, true), flameMat);
      const a = (i / 4) * Math.PI * 2;
      f.position.set(pos.x + Math.cos(a) * 0.1 * (i ? 1 : 0), pos.y + 0.35, pos.z + Math.sin(a) * 0.1 * (i ? 1 : 0));
      this.scene.add(f);
      flames.push(f);
    }
    const core = new THREE.Mesh(new THREE.SphereGeometry(0.16, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffd080 }));
    core.position.set(pos.x, pos.y + 0.12, pos.z);
    core.scale.y = 0.5;
    this.scene.add(core);
    this.fires.push({ pos: pos.clone(), light, flames, smokeTimer: 0, emberTimer: 0 });
  }

  /** Coluna de fumaça escura bem longe (cidade queimando no horizonte). */
  addPlume(pos, scale = 1) {
    this.plumes.push({ pos: pos.clone(), scale, timer: 0 });
    // já começa com a coluna formada
    for (let i = 0; i < 40; i++) this._emitPlume(this.plumes[this.plumes.length - 1], Math.random() * 30);
  }

  _emitPlume(p, age = 0) {
    const s = p.scale;
    const life = 32;
    this.smoke.emit(p.pos.x + (Math.random() - 0.5) * 6 * s, p.pos.y + age * 2.2 * s, p.pos.z + (Math.random() - 0.5) * 6 * s,
      0.9 * s, 2.2 * s, 0.3 * s,
      { life: life - age, size: (6 + age * 0.9) * s, grow: 0.9 * s, color: [0.16, 0.15, 0.14], alpha: 0.35, drag: 0.02 });
  }

  _updateFires(dt) {
    for (const p of this.plumes) {
      p.timer -= dt;
      if (p.timer <= 0) { p.timer = 0.75; this._emitPlume(p); }
    }
    for (const f of this.fires) {
      const flick = Math.sin(this.t * 13) * 0.3 + Math.sin(this.t * 7.3 + 1) * 0.4 + Math.random() * 0.4;
      f.light.intensity = 5 + flick * 1.6;
      f.flames.forEach((m, i) => {
        m.scale.set(1 + Math.sin(this.t * 9 + i) * 0.15, 0.8 + Math.abs(Math.sin(this.t * (6 + i * 1.7) + i * 2)) * 0.6, 1);
        m.rotation.y += dt * (1 + i);
      });
      f.smokeTimer -= dt;
      if (f.smokeTimer <= 0) {
        f.smokeTimer = 0.12;
        this.dust.emit(f.pos.x + (Math.random() - 0.5) * 0.2, f.pos.y + 0.7, f.pos.z + (Math.random() - 0.5) * 0.2,
          0.15 + Math.random() * 0.1, 0.8 + Math.random() * 0.4, (Math.random() - 0.5) * 0.15,
          { life: 3.5, size: 0.35, grow: 0.7, color: [0.35, 0.34, 0.33], alpha: 0.25, drag: 0.3 });
      }
      f.emberTimer -= dt;
      if (f.emberTimer <= 0) {
        f.emberTimer = 0.07 + Math.random() * 0.1;
        this.glow.emit(f.pos.x + (Math.random() - 0.5) * 0.3, f.pos.y + 0.3, f.pos.z + (Math.random() - 0.5) * 0.3,
          (Math.random() - 0.5) * 0.6, 1.2 + Math.random() * 1.5, (Math.random() - 0.5) * 0.6,
          { life: 1.2 + Math.random(), size: 0.05, grow: -0.02, color: [1, 0.55, 0.15], alpha: 1, drag: 0.8 });
      }
    }
  }

  // ---------- folhas caindo ----------
  _buildLeaves(count) {
    const geo = new THREE.PlaneGeometry(0.11, 0.08);
    // sem iluminação: contra o céu, o lado de trás de uma folha iluminada ficaria preto
    const mat = new THREE.MeshBasicMaterial({ side: THREE.DoubleSide });
    this.leaves = new THREE.InstancedMesh(geo, mat, count);
    this.leaves.frustumCulled = false;
    this.leafData = [];
    const palette = [0x9a5426, 0x83401f, 0xa88232, 0x6a5c26, 0x74321a];
    const c = new THREE.Color();
    for (let i = 0; i < count; i++) {
      this.leafData.push({ p: new THREE.Vector3(0, -100, 0), spin: new THREE.Vector3(), rot: new THREE.Euler(), phase: Math.random() * 10, fall: 0.5 + Math.random() * 0.5 });
      c.setHex(palette[i % palette.length]);
      this.leaves.setColorAt(i, c);
    }
    this.scene.add(this.leaves);
    this._m = new THREE.Matrix4();
    this._q = new THREE.Quaternion();
    this._s = new THREE.Vector3(1, 1, 1);
  }

  _updateLeaves(dt, center, groundAt) {
    for (let i = 0; i < this.leafData.length; i++) {
      const L = this.leafData[i];
      const ground = groundAt(L.p.x, L.p.z);
      if (L.p.y < ground + 0.02 || L.p.distanceToSquared(center) > 900) {
        // renasce acima, em volta do jogador
        const a = Math.random() * Math.PI * 2, r = 2 + Math.random() * 26;
        L.p.set(center.x + Math.cos(a) * r, center.y + 4 + Math.random() * 9, center.z + Math.sin(a) * r);
        L.spin.set(Math.random() * 3, Math.random() * 3, Math.random() * 3);
      }
      L.phase += dt;
      L.p.x += (Math.sin(L.phase * 1.3) * 0.6 + 0.4) * dt;
      L.p.z += Math.cos(L.phase * 0.9) * 0.4 * dt;
      L.p.y -= L.fall * dt;
      L.rot.x += L.spin.x * dt; L.rot.y += L.spin.y * dt; L.rot.z += L.spin.z * dt;
      this._q.setFromEuler(L.rot);
      this._m.compose(L.p, this._q, this._s);
      this.leaves.setMatrixAt(i, this._m);
    }
    this.leaves.instanceMatrix.needsUpdate = true;
  }

  update(dt, playerPos, groundAt, viewportHeight) {
    this.t += dt;
    this._updateFires(dt);
    this._updateLeaves(dt, playerPos, groundAt);
    this.dust.update(dt, viewportHeight);
    this.glow.update(dt, viewportHeight);
    this.smoke.update(dt, viewportHeight);
  }
}

