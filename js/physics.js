import * as THREE from 'three';

// Física simples para objetos soltos pelo mapa: latas, garrafas, baldes, galões, panelas
// e caixinhas. Eles caem, quicam, rolam, batem uns nos outros, são chutados quando o
// jogador passa por eles e voam com o golpe da faca. Cada impacto avisa o som.
//
// Latas e garrafas começam em pé (paradas) e tombam ao serem tocadas, rolando deitadas.
// Os outros objetos ficam sempre de pé (colisão por esfera) e deslizam/giram no chão.

const GRAVITY = 16;
const _sphere = new THREE.Sphere();
const _v = new THREE.Vector3();
const _n = new THREE.Vector3();
const _seg = new THREE.Line3();
const _closest = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _qRoll = new THREE.Quaternion();
const Y_UP = new THREE.Vector3(0, 1, 0);

function makeTypes() {
  const metal = (color, rough = 0.4) => new THREE.MeshStandardMaterial({ color, roughness: rough, metalness: 0.75 });
  const paint = (color) => new THREE.MeshStandardMaterial({ color, roughness: 0.6, metalness: 0.2 });

  // lata: corpo com rótulo colorido + tampas metálicas
  const canGroup = (labelColor) => {
    const g = new THREE.Group();
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.033, 0.033, 0.1, 14), paint(labelColor));
    const lid = new THREE.Mesh(new THREE.CylinderGeometry(0.031, 0.033, 0.012, 14), metal(0xb0b0aa, 0.3));
    lid.position.y = 0.056;
    const bottom = lid.clone();
    bottom.position.y = -0.056;
    g.add(body, lid, bottom);
    return g;
  };
  // garrafa de vidro (perfil torneado)
  const bottleGeo = new THREE.LatheGeometry([
    [0, -0.13], [0.034, -0.13], [0.036, -0.12], [0.036, 0.02], [0.03, 0.06], [0.013, 0.09], [0.012, 0.135], [0.014, 0.14], [0, 0.14],
  ].map(([x, y]) => new THREE.Vector2(x, y)), 14);
  const glass = (color) => new THREE.MeshStandardMaterial({ color, roughness: 0.08, metalness: 0.1, transparent: true, opacity: 0.72 });
  const bottle = (color) => new THREE.Mesh(bottleGeo, glass(color));

  const bucket = () => {
    const g = new THREE.Group();
    const m = metal(0x6f7570, 0.55);
    m.side = THREE.DoubleSide;
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.115, 0.26, 16, 1, true), m);
    const base = new THREE.Mesh(new THREE.CircleGeometry(0.115, 16), m);
    base.rotation.x = -Math.PI / 2;
    base.position.y = -0.125;
    const handle = new THREE.Mesh(new THREE.TorusGeometry(0.15, 0.006, 4, 16, Math.PI), metal(0x555a55));
    handle.position.y = 0.13;
    handle.rotation.y = Math.PI / 2;
    g.add(body, base, handle);
    return g;
  };
  const jerrycan = () => {
    const g = new THREE.Group();
    const red = paint(0x8a2a1c);
    const body = new THREE.Mesh(new THREE.BoxGeometry(0.17, 0.34, 0.3), red);
    const handle = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.04, 0.16), red);
    handle.position.set(0, 0.19, 0.03);
    const spout = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.022, 0.05, 8), metal(0x2a2a2a));
    spout.position.set(0, 0.19, -0.11);
    g.add(body, handle, spout);
    return g;
  };
  const pot = () => {
    const g = new THREE.Group();
    const m = metal(0x3a3c3e, 0.5);
    m.side = THREE.DoubleSide;
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.11, 0.13, 16, 1, true), m);
    const base = new THREE.Mesh(new THREE.CircleGeometry(0.11, 16), m);
    base.rotation.x = -Math.PI / 2;
    base.position.y = -0.065;
    const handle = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.015, 0.025), m);
    handle.position.set(0.18, 0.05, 0);
    g.add(body, base, handle);
    return g;
  };
  const smallCrate = () => {
    const tex = new THREE.MeshStandardMaterial({ color: 0x8a6a44, roughness: 0.9 });
    const g = new THREE.Group();
    g.add(new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.36, 0.32), tex));
    for (const y of [-0.12, 0.12]) {
      const slat = new THREE.Mesh(new THREE.BoxGeometry(0.44, 0.04, 0.34), new THREE.MeshStandardMaterial({ color: 0x5a4430, roughness: 1 }));
      slat.position.y = y;
      g.add(slat);
    }
    return g;
  };

  const cans = [0xa0302a, 0x2a5a8a, 0xc8a03a, 0x3a6a3a];
  const bottles = [0x2f5a2a, 0x5a3a1a, 0x8aa0a0];
  return {
    can: { make: (i) => canGroup(cans[i % cans.length]), tip: true, height: 0.124, rad: 0.033, mass: 0.3, sound: 'can' },
    bottle: { make: (i) => bottle(bottles[i % bottles.length]), tip: true, height: 0.27, rad: 0.036, mass: 0.5, sound: 'glass' },
    bucket: { make: bucket, tip: false, height: 0.26, rad: 0.13, mass: 1.2, sound: 'metal' },
    jerrycan: { make: jerrycan, tip: false, height: 0.34, rad: 0.17, mass: 2.5, sound: 'hollow' },
    pot: { make: pot, tip: false, height: 0.13, rad: 0.065, mass: 0.9, sound: 'metal' },
    crate: { make: smallCrate, tip: false, height: 0.36, rad: 0.18, mass: 3, sound: 'wood' },
  };
}

export class PropSystem {
  constructor(scene, octree) {
    this.scene = scene;
    this.octree = octree;
    this.types = makeTypes();
    this.bodies = [];
    this.meshes = [];         // para raycast (golpe de faca)
    this.extraColliders = []; // portas (cada uma com .octree)
    this.onImpact = null;     // (som, força, posição)
    this._count = 0;
  }

  /** (x, z) = posição; baseY = altura da superfície onde o objeto está apoiado. */
  add(type, x, baseY, z, yaw = Math.random() * Math.PI * 2) {
    const t = this.types[type];
    const mesh = t.make(this._count++);
    mesh.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    if (mesh.isMesh) { mesh.castShadow = true; mesh.receiveShadow = true; }
    this.scene.add(mesh);
    const body = {
      type: t, mesh,
      pos: new THREE.Vector3(x, baseY + t.height / 2, z),
      vel: new THREE.Vector3(),
      // em pé: a colisão é a metade da altura; deitada (latas/garrafas): o raio do cilindro
      r: t.height / 2,
      standing: true, lying: false,
      yaw, axisYaw: yaw, roll: 0, spin: 0,
      asleep: true, sleepTimer: 0, grounded: true, soundCooldown: 0,
    };
    mesh.userData.body = body;
    mesh.traverse((o) => { o.userData.body = body; });
    this.bodies.push(body);
    this.meshes.push(mesh);
    this._sync(body);
    return body;
  }

  _wake(b) {
    b.asleep = false;
    b.sleepTimer = 0;
    if (b.type.tip && b.standing) {
      // tomba: passa a ser um cilindro deitado
      b.standing = false;
      b.lying = true;
      b.pos.y += b.type.rad - b.type.height / 2 + 0.01;
      b.r = b.type.rad;
    }
  }

  /** Aplica um empurrão (m/s) no objeto. */
  push(b, impulse) {
    this._wake(b);
    b.vel.addScaledVector(impulse, 1 / Math.max(0.4, b.type.mass * 0.6));
    b.spin += (Math.random() - 0.5) * impulse.length() * 4;
  }

  /** Golpe ao longo de um raio; retorna { body, point } ou null. */
  hit(raycaster, strength = 4.5) {
    const hit = raycaster.intersectObjects(this.meshes, true)[0];
    if (!hit) return null;
    const b = hit.object.userData.body;
    _v.copy(raycaster.ray.direction).multiplyScalar(strength).add(_n.set(0, strength * 0.35, 0));
    this.push(b, _v);
    return { body: b, point: hit.point };
  }

  _collideOctree(b, octree) {
    _sphere.set(b.pos, b.r);
    const res = octree.sphereIntersect(_sphere);
    if (!res) return;
    b.pos.addScaledVector(res.normal, res.depth);
    const vn = b.vel.dot(res.normal);
    if (vn < 0) {
      const impact = -vn;
      const bounce = b.type.sound === 'glass' || b.type.sound === 'can' ? 0.35 : 0.2;
      b.vel.addScaledVector(res.normal, -(1 + bounce) * vn);
      if (impact > 1.1 && b.soundCooldown <= 0) {
        this.onImpact?.(b.type.sound, Math.min(1, impact / 6), b.pos);
        b.soundCooldown = 0.08;
      }
    }
    if (res.normal.y > 0.5) b.grounded = true;
  }

  update(dt, player) {
    // jogador chutando objetos ao passar
    _seg.set(player.collider.start, player.collider.end);
    const pr = player.collider.radius;
    const pv = player.velocity;
    for (const b of this.bodies) {
      _seg.closestPointToPoint(b.pos, true, _closest);
      const d = _closest.distanceTo(b.pos);
      if (d < pr + b.r) {
        _n.subVectors(b.pos, _closest).setY(0);
        if (_n.lengthSq() < 1e-6) _n.set(1, 0, 0);
        _n.normalize();
        b.pos.addScaledVector(_n, pr + b.r - d);
        const speed = Math.hypot(pv.x, pv.z);
        _v.copy(_n).multiplyScalar(0.6 + speed * 0.5);
        _v.x += pv.x * 0.7;
        _v.z += pv.z * 0.7;
        _v.y = speed > 2 ? 1 + speed * 0.15 : 0.3;
        this._wake(b);
        b.vel.copy(_v).multiplyScalar(1 / Math.max(0.6, b.type.mass * 0.5));
        if (b.soundCooldown <= 0) { this.onImpact?.(b.type.sound, Math.min(1, speed / 7 + 0.2), b.pos); b.soundCooldown = 0.25; }
      }
    }

    const steps = 2, h = dt / steps;
    for (const b of this.bodies) {
      b.soundCooldown -= dt;
      if (b.asleep) continue;
      for (let s = 0; s < steps; s++) {
        b.vel.y -= GRAVITY * h;
        b.pos.addScaledVector(b.vel, h);
        b.grounded = false;
        this._collideOctree(b, this.octree);
        for (const o of this.extraColliders) this._collideOctree(b, o.octree);
      }
      if (b.grounded) {
        // atrito no chão (rolando perde menos velocidade)
        const k = Math.exp(-(b.lying ? 1.6 : 5) * dt);
        b.vel.x *= k;
        b.vel.z *= k;
      }
      b.spin *= Math.exp(-2.5 * dt);
      b.yaw += b.spin * dt;
      const hs = Math.hypot(b.vel.x, b.vel.z);
      if (b.lying && hs > 0.05) {
        // o eixo do cilindro fica perpendicular ao movimento e ele rola
        const target = Math.atan2(b.vel.x, b.vel.z) + Math.PI / 2;
        let da = target - b.axisYaw;
        da = Math.atan2(Math.sin(da * 2), Math.cos(da * 2)) / 2; // o cilindro é simétrico
        b.axisYaw += da * Math.min(1, dt * 6);
        if (b.grounded) b.roll += (hs / b.r) * dt;
      }
      // dorme quando para
      if (b.grounded && b.vel.lengthSq() < 0.01 && Math.abs(b.spin) < 0.1) {
        b.sleepTimer += dt;
        if (b.sleepTimer > 0.5) { b.asleep = true; b.vel.set(0, 0, 0); }
      } else b.sleepTimer = 0;
      if (b.pos.y < -50) { b.asleep = true; b.mesh.visible = false; }
    }

    // objetos batendo uns nos outros
    for (let i = 0; i < this.bodies.length; i++) {
      const a = this.bodies[i];
      for (let j = i + 1; j < this.bodies.length; j++) {
        const b = this.bodies[j];
        if (a.asleep && b.asleep) continue;
        const min = a.r + b.r;
        _n.subVectors(b.pos, a.pos);
        const d2 = _n.lengthSq();
        if (d2 >= min * min || d2 < 1e-8) continue;
        const d = Math.sqrt(d2);
        _n.multiplyScalar(1 / d);
        const ma = a.type.mass, mb = b.type.mass, tot = ma + mb;
        a.pos.addScaledVector(_n, -(min - d) * mb / tot);
        b.pos.addScaledVector(_n, (min - d) * ma / tot);
        const rel = _v.subVectors(b.vel, a.vel).dot(_n);
        if (rel < 0) {
          const j2 = -1.4 * rel / tot;
          a.vel.addScaledVector(_n, -j2 * mb);
          b.vel.addScaledVector(_n, j2 * ma);
          if (-rel > 0.8) this.onImpact?.(a.type.sound, Math.min(1, -rel / 5), a.pos);
        }
        if (a.asleep) this._wake(a);
        if (b.asleep) this._wake(b);
      }
    }

    for (const b of this.bodies) if (!b.asleep || b._dirty !== false) { this._sync(b); b._dirty = !b.asleep; }
  }

  _sync(b) {
    const m = b.mesh;
    m.position.copy(b.pos);
    if (b.lying) {
      // eixo Y do modelo deitado na direção axisYaw, girando (rolando) em torno dele
      const axis = _v.set(Math.sin(b.axisYaw), 0, Math.cos(b.axisYaw));
      _q.setFromUnitVectors(Y_UP, axis);
      _qRoll.setFromAxisAngle(axis, b.roll);
      m.quaternion.multiplyQuaternions(_qRoll, _q);
    } else {
      m.quaternion.setFromAxisAngle(Y_UP, b.yaw);
    }
  }
}
