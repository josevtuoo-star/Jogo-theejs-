import * as THREE from 'three';
import { Capsule } from 'three/addons/math/Capsule.js';

// Controlador do personagem em primeira pessoa.
// Física: cápsula colidindo com o Octree do mundo (chão, paredes, rampas, teto).

const GRAVITY = 26;
const RADIUS = 0.35;
export const STAND_HEIGHT = 1.8;
export const CROUCH_HEIGHT = 1.15;
const EYE_BELOW_TOP = 0.14;

const WALK_SPEED = 4.2;
const RUN_SPEED = 7.4;
const CROUCH_SPEED = 2.0;
const BACKWARD_MULT = 0.7;
const JUMP_VELOCITY = 8.6;

const GROUND_ACCEL = 14;
const AIR_ACCEL = 2.2;
const MIN_FLOOR_NORMAL_Y = 0.55;  // ~56° — acima disso é parede
const SUBSTEPS = 5;
const COYOTE_TIME = 0.12;
const JUMP_BUFFER = 0.15;
const SNAP_DISTANCE = 0.35;

const STAMINA_MAX = 100;
const SPRINT_COST = 16;      // por segundo
const JUMP_COST = 9;
const STAMINA_REGEN = 14;
const EXHAUST_RECOVER = 30;  // precisa recuperar até aqui depois de esgotar

const FALL_DAMAGE_SPEED = 13; // m/s de impacto a partir do qual causa dano

const _v = new THREE.Vector3();
const _forward = new THREE.Vector3();
const _right = new THREE.Vector3();
const _wish = new THREE.Vector3();
const _push = new THREE.Vector3();
const _saveStart = new THREE.Vector3();
const _saveEnd = new THREE.Vector3();
const _tris = [];

function damp(a, b, lambda, dt) {
  return a + (b - a) * (1 - Math.exp(-lambda * dt));
}

export class Player {
  constructor(octree, spawn) {
    this.octree = octree;
    this.spawn = spawn.clone();

    this.collider = new Capsule(new THREE.Vector3(), new THREE.Vector3(), RADIUS);
    this._probe = new Capsule(new THREE.Vector3(), new THREE.Vector3(), RADIUS);
    this.velocity = new THREE.Vector3();

    this.yaw = 0;
    this.pitch = 0;

    this.onFloor = false;
    this.timeSinceGround = 0;
    this.jumpBuffer = 0;

    this.height = STAND_HEIGHT;
    this.crouched = false;
    this.crouchToggle = false;

    this.sprinting = false;
    this.stamina = STAMINA_MAX;
    this.staminaDelay = 0;
    this.exhausted = false;

    this.health = 100;

    this.horizontalSpeed = 0;
    this.stepPhase = 0;
    this.moveInput = { x: 0, y: 0 };

    // eventos consumidos por câmera / áudio / animações neste quadro
    this.events = [];

    this.respawn();
  }

  respawn() {
    this.collider.start.set(this.spawn.x, this.spawn.y + RADIUS + 0.05, this.spawn.z);
    this.collider.end.copy(this.collider.start).y += STAND_HEIGHT - 2 * RADIUS;
    this.height = STAND_HEIGHT;
    this.crouched = this.crouchToggle = false;
    this.velocity.set(0, 0, 0);
    this.yaw = 0;
    this.pitch = 0;
    this.health = 100;
    this.stamina = STAMINA_MAX;
  }

  get feetPosition() {
    return _v.set(this.collider.start.x, this.collider.start.y - RADIUS, this.collider.start.z);
  }

  /** Posição dos olhos (sem efeitos de câmera). */
  getEyePosition(target) {
    return target.copy(this.collider.end).setY(this.collider.end.y + RADIUS - EYE_BELOW_TOP);
  }

  /** Há espaço livre acima para ficar de pé? */
  canStand() {
    const p = this._probe;
    p.radius = RADIUS * 0.9;
    p.start.copy(this.collider.end);
    p.end.copy(this.collider.start).y += STAND_HEIGHT - 2 * RADIUS;
    if (p.end.y <= p.start.y + 0.01) return true;
    p.start.y += 0.05;
    return !this.octree.capsuleIntersect(p);
  }

  forwardVector(target) {
    return target.set(-Math.sin(this.yaw), 0, -Math.cos(this.yaw));
  }

  update(dt, input) {
    this.events.length = 0;

    // ---------- olhar ----------
    const look = input.consumeLook();
    this.yaw -= look.x;
    this.pitch -= look.y;
    const lim = Math.PI / 2 - 0.02;
    this.pitch = Math.max(-lim, Math.min(lim, this.pitch));
    this.lookDelta = look;

    const move = input.getMove();
    this.moveInput = move;
    const moving = Math.hypot(move.x, move.y) > 0.05;

    // ---------- agachar ----------
    if (input.wasPressed('crouchToggle')) this.crouchToggle = !this.crouchToggle;
    const wantSprint = input.sprint && move.y > 0.3;
    if (wantSprint && this.crouchToggle) { this.crouchToggle = false; }
    if (wantSprint) input.clearTouchCrouch();

    const wantCrouch = (input.crouchHeld || this.crouchToggle) && !wantSprint;
    if (wantCrouch) {
      if (!this.crouched) this.events.push({ type: 'crouch' });
      this.crouched = true;
    } else if (this.crouched && this.canStand()) {
      this.crouched = false;
      this.events.push({ type: 'stand' });
    }

    const targetHeight = this.crouched ? CROUCH_HEIGHT : STAND_HEIGHT;
    const newHeight = damp(this.height, targetHeight, 14, dt);
    if (this.onFloor) {
      // no chão: os pés ficam fixos, a cabeça desce/sobe
      this.collider.end.y = this.collider.start.y + newHeight - 2 * RADIUS;
    } else {
      // no ar: encolhe as pernas (pulo agachado alcança lugares mais altos)
      const mid = this.collider.end.y;
      this.collider.start.y = mid - (newHeight - 2 * RADIUS);
      this.collider.end.y = mid;
    }
    this.height = newHeight;

    // ---------- fôlego / corrida ----------
    if (this.stamina <= 0) this.exhausted = true;
    if (this.exhausted && this.stamina >= EXHAUST_RECOVER) this.exhausted = false;
    const canSprint = wantSprint && !this.crouched && !this.exhausted;
    this.sprinting = canSprint && (this.onFloor || this.sprinting);

    if (this.sprinting && this.horizontalSpeed > 1) {
      this.stamina -= SPRINT_COST * dt;
      this.staminaDelay = 1.0;
    } else {
      this.staminaDelay -= dt;
      if (this.staminaDelay <= 0) {
        const mult = moving ? 1 : 1.6;
        this.stamina += STAMINA_REGEN * mult * dt;
      }
    }
    this.stamina = Math.max(0, Math.min(STAMINA_MAX, this.stamina));

    // ---------- velocidade horizontal desejada ----------
    let speed = this.crouched ? CROUCH_SPEED : this.sprinting ? RUN_SPEED : WALK_SPEED;
    if (move.y < 0) speed *= BACKWARD_MULT;
    this.forwardVector(_forward);
    _right.set(-_forward.z, 0, _forward.x);
    _wish.set(0, 0, 0).addScaledVector(_forward, move.y).addScaledVector(_right, move.x);
    if (_wish.lengthSq() > 1) _wish.normalize();
    _wish.multiplyScalar(speed);

    const accel = this.onFloor ? GROUND_ACCEL : AIR_ACCEL;
    this.velocity.x = damp(this.velocity.x, _wish.x, accel, dt);
    this.velocity.z = damp(this.velocity.z, _wish.z, accel, dt);

    // ---------- pulo (com coyote time e buffer) ----------
    this.timeSinceGround = this.onFloor ? 0 : this.timeSinceGround + dt;
    if (input.wasPressed('jump')) this.jumpBuffer = JUMP_BUFFER;
    else this.jumpBuffer -= dt;

    if (this.jumpBuffer > 0 && this.timeSinceGround < COYOTE_TIME && this.stamina >= JUMP_COST * 0.5) {
      if (this.crouched) {
        // pular estando agachado: levanta primeiro, se houver espaço
        if (this.canStand()) {
          this.crouched = this.crouchToggle = false;
          input.clearTouchCrouch();
        }
      }
      if (!this.crouched) {
        this.velocity.y = JUMP_VELOCITY;
        this.stamina = Math.max(0, this.stamina - JUMP_COST);
        this.onFloor = false;
        this.timeSinceGround = COYOTE_TIME;
        this.jumpBuffer = 0;
        this.events.push({ type: 'jump' });
      }
    }

    // ---------- gravidade + integração em sub-passos ----------
    this.velocity.y -= GRAVITY * dt;
    const wasOnFloor = this.onFloor;
    const fallSpeed = -this.velocity.y;
    const jumping = this.velocity.y > 0;

    this.onFloor = false;
    const sdt = dt / SUBSTEPS;
    const startPos = _v.copy(this.collider.start);
    const startX = startPos.x, startZ = startPos.z;
    for (let i = 0; i < SUBSTEPS; i++) {
      this.collider.translate(_wish.copy(this.velocity).multiplyScalar(sdt));
      this._collide();
    }

    if (wasOnFloor && !this.onFloor && !jumping) this._snapToGround();

    if (this.onFloor && this.velocity.y < 0) this.velocity.y = 0;

    // ---------- pouso ----------
    if (!wasOnFloor && this.onFloor) {
      this.events.push({ type: 'land', speed: fallSpeed });
      if (fallSpeed > FALL_DAMAGE_SPEED) {
        const dmg = (fallSpeed - FALL_DAMAGE_SPEED) * 7;
        this.health = Math.max(0, this.health - dmg);
        this.events.push({ type: 'damage', amount: dmg });
      }
    }

    // ---------- passos ----------
    const moved = Math.hypot(this.collider.start.x - startX, this.collider.start.z - startZ);
    this.horizontalSpeed = dt > 0 ? moved / dt : 0;
    if (this.onFloor && this.horizontalSpeed > 0.4) {
      const stride = this.sprinting ? 1.25 : this.crouched ? 0.6 : 0.85;
      const before = Math.floor(this.stepPhase / Math.PI);
      this.stepPhase += (this.horizontalSpeed * dt / stride) * Math.PI;
      if (Math.floor(this.stepPhase / Math.PI) !== before) {
        this.events.push({ type: 'step', run: this.sprinting, crouch: this.crouched });
      }
    }

    // caiu do mapa ou morreu → renasce
    if (this.collider.start.y < -40 || this.health <= 0) {
      this.events.push({ type: 'respawn' });
      this.respawn();
    }
  }

  /**
   * Resolve a colisão triângulo a triângulo, separando chão de parede.
   * (O capsuleIntersect do Octree soma tudo num vetor só; encostado numa parede
   * isso faria o jogador "perder" o chão.)
   */
  _collide() {
    _tris.length = 0;
    this.octree.getCapsuleTriangles(this.collider, _tris);
    for (let i = 0; i < _tris.length; i++) {
      const r = this.octree.triangleCapsuleIntersect(this.collider, _tris[i]);
      if (!r || r.depth <= 0) continue;
      const n = r.normal;
      if (n.y >= MIN_FLOOR_NORMAL_Y) {
        // chão caminhável: empurra só para cima (não escorrega em rampas)
        this.onFloor = true;
        this.collider.translate(_push.set(0, r.depth / n.y, 0));
        if (this.velocity.y < 0) this.velocity.y = 0;
      } else {
        // parede / teto: empurra para fora e remove a velocidade contra a superfície
        const vn = this.velocity.dot(n);
        if (vn < 0) this.velocity.addScaledVector(n, -vn);
        this.collider.translate(_push.copy(n).multiplyScalar(r.depth));
      }
    }
  }

  /** "Gruda" no chão ao descer rampas/escadas em vez de sair voando. */
  _snapToGround() {
    _saveStart.copy(this.collider.start);
    _saveEnd.copy(this.collider.end);
    const savedVy = this.velocity.y;
    this.collider.translate(_push.set(0, -SNAP_DISTANCE, 0));
    this._collide();
    if (!this.onFloor) {
      this.collider.start.copy(_saveStart);
      this.collider.end.copy(_saveEnd);
      this.velocity.y = savedVy;
    }
  }

  get state() {
    if (!this.onFloor) return this.velocity.y > 0 ? 'PULANDO' : 'CAINDO';
    if (this.crouched) return this.horizontalSpeed > 0.4 ? 'AGACHADO • ANDANDO' : 'AGACHADO';
    if (this.horizontalSpeed < 0.4) return 'PARADO';
    return this.sprinting ? 'CORRENDO' : 'ANDANDO';
  }
}
