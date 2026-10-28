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

// escalar / pular obstáculos (estilo DayZ)
const LEDGE_MIN = 0.45;       // abaixo disso é só pular
const LEDGE_MAX = 2.3;        // altura máxima que dá para escalar
const VAULT_OVER_MAX = 1.45;  // obstáculos finos até essa altura são pulados por cima
const CLIMB_COST = 10;

const LEAN_DISTANCE = 0.45;

const _v = new THREE.Vector3();
const _forward = new THREE.Vector3();
const _right = new THREE.Vector3();
const _wish = new THREE.Vector3();
const _push = new THREE.Vector3();
const _saveStart = new THREE.Vector3();
const _saveEnd = new THREE.Vector3();
const _tris = [];
const _ray = new THREE.Ray();
const _lf = new THREE.Vector3();
const _n = new THREE.Vector3();
const _p = new THREE.Vector3();

function smooth(t) { return t * t * (3 - 2 * t); }

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
    this.dead = false;

    this.climb = null;        // animação de escalada em andamento
    this.ledgeAhead = null;   // obstáculo escalável à frente (para a dica na tela)
    this._ledgeTimer = 0;

    this.lean = 0;            // -1 esquerda … 1 direita (Q/E)

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
    this.dead = false;
    this.climb = null;
    this.lean = 0;
    this.stamina = STAMINA_MAX;
  }

  get isClimbing() { return this.climb !== null; }

  /** 0..1 durante a escalada (usado pelas animações). */
  get climbProgress() {
    if (!this.climb) return 0;
    return Math.min(1, this.climb.elapsed / this.climb.total);
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
    if (this.dead) { input.consumeLook(); this.horizontalSpeed = 0; return; }

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

    if (this.climb) { this._updateClimb(dt); this._updateLean(dt, 0); return; }

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

    // escalar tem prioridade sobre o pulo quando há um obstáculo na frente
    if (this.jumpBuffer > 0 && this.timeSinceGround < 0.6 && this.stamina >= CLIMB_COST * 0.5) {
      const ledge = this.findLedge(this.onFloor ? LEDGE_MIN : 0.1);
      if (ledge) {
        this._startClimb(ledge, input);
        return;
      }
    }

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

    // inclinar (espiar) só parado/andando no chão
    const leanInput = (this.onFloor && !this.sprinting) ? input.lean : 0;
    this._updateLean(dt, leanInput);

    // dica de escalada (não precisa ser testada todo quadro)
    this._ledgeTimer -= dt;
    if (this._ledgeTimer <= 0) {
      this._ledgeTimer = 0.12;
      this.ledgeAhead = this.onFloor && move.y > -0.1 ? this.findLedge(LEDGE_MIN) : null;
    }

    if (this.health <= 0) {
      this.dead = true;
      this.lean = 0;
      this.events.push({ type: 'death' });
    } else if (this.collider.start.y < -40) {
      // caiu para fora do mapa
      this.events.push({ type: 'respawn' });
      this.respawn();
    }
  }

  // ---------- inclinar (Q/E) ----------
  _updateLean(dt, target) {
    if (target !== 0) {
      // não deixa a cabeça atravessar paredes
      this.getEyePosition(_ray.origin);
      this.forwardVector(_lf);
      _ray.direction.set(-_lf.z * Math.sign(target), 0, _lf.x * Math.sign(target));
      const hit = this.octree.rayIntersect(_ray);
      if (hit) {
        const room = Math.max(0, Math.min(1, (hit.distance - 0.25) / LEAN_DISTANCE));
        target *= room;
      }
    }
    this.lean = damp(this.lean, target, 10, dt);
    if (Math.abs(this.lean) < 0.001) this.lean = 0;
  }

  /** Deslocamento lateral dos olhos causado pela inclinação (em metros). */
  get leanOffset() { return this.lean * LEAN_DISTANCE; }

  // ---------- escalar / pular obstáculos ----------
  _rayHit(ox, oy, oz, dx, dy, dz) {
    _ray.origin.set(ox, oy, oz);
    _ray.direction.set(dx, dy, dz);
    return this.octree.rayIntersect(_ray) || null;
  }

  /** Cápsula de pé (ou agachada) cabe com os pés em (x, y, z)? */
  _fits(x, y, z, height) {
    const p = this._probe;
    p.radius = RADIUS * 0.95;
    p.start.set(x, y + RADIUS + 0.04, z);
    p.end.set(x, y + height - RADIUS, z);
    return !this.octree.capsuleIntersect(p);
  }

  /**
   * Procura um obstáculo escalável logo à frente.
   * Retorna { kind: 'climb' | 'vault', height, path: [pontos dos pés] } ou null.
   */
  findLedge(minHeight) {
    const feet = this.collider.start.y - RADIUS;
    const x = this.collider.start.x, z = this.collider.start.z;
    const f = this.forwardVector(_lf);

    // 1) tem parede na frente? (joelho, cintura, peito)
    let wall = Infinity;
    for (const h of [0.35, 0.9, 1.5]) {
      const hit = this._rayHit(x, feet + h, z, f.x, 0, f.z);
      if (hit && hit.distance < wall) wall = hit.distance;
    }
    if (wall > RADIUS + 0.55) return null;

    // 2) topo do obstáculo: raio de cima para baixo, logo depois da face da parede
    // (bem perto da face, para acertar também cercas e muretas finas)
    const reach = wall + 0.08;
    const top = this._rayHit(x + f.x * reach, feet + LEDGE_MAX + 0.3, z + f.z * reach, 0, -1, 0);
    if (!top) return null;
    const topY = top.position.y;
    const height = topY - feet;
    if (height < minHeight || height > LEDGE_MAX) return null;
    top.triangle.getNormal(_n);
    if (_n.y < 0.7) return null;

    // espaço livre acima da cabeça durante o movimento
    const headY = this.collider.end.y + RADIUS;
    const ceil = this._rayHit(x, headY, z, 0, 1, 0);
    if (ceil && ceil.distance < Math.max(0, topY + 0.2 + CROUCH_HEIGHT - headY) + 0.05) return null;

    const start = new THREE.Vector3(x, feet, z);

    // 3) obstáculo fino (cerca, mureta, caixote)? pula por cima
    const far = reach + 0.75;
    const beyond = this._rayHit(x + f.x * far, topY + 0.3, z + f.z * far, 0, -1, 0);
    const thin = !beyond || beyond.position.y < topY - 0.4;
    // (não salta por cima se do outro lado houver uma queda alta, ex.: mureta do terraço)
    const safeDrop = !beyond || beyond.position.y > feet - 0.6;
    if (thin && height <= VAULT_OVER_MAX && safeDrop) {
      const lx = x + f.x * (far + 0.15), lz = z + f.z * (far + 0.15);
      const groundY = beyond ? beyond.position.y : topY - 1;
      if (this._fits(lx, Math.max(groundY, topY - 1.2), lz, STAND_HEIGHT) &&
          this._fits(x + f.x * reach, topY + 0.15, z + f.z * reach, CROUCH_HEIGHT)) {
        return {
          kind: 'vault', height, crouch: false,
          path: [
            start,
            new THREE.Vector3(x + f.x * Math.max(0, wall - RADIUS - 0.05), topY + 0.15, z + f.z * Math.max(0, wall - RADIUS - 0.05)),
            new THREE.Vector3(x + f.x * reach, topY + 0.18, z + f.z * reach),
            new THREE.Vector3(lx, Math.max(groundY, topY - 1.2) + 0.02, lz),
          ],
          durations: [0.16 + height * 0.06, 0.16, 0.18],
        };
      }
    }

    // 4) subir em cima (de pé, ou agachado se o teto for baixo)
    // em cima de algo largo, o corpo inteiro vai para cima; em algo fino (muro), fica no meio dele
    let ahead = wall + RADIUS + 0.1;
    const ground = this._rayHit(x + f.x * ahead, topY + 0.3, z + f.z * ahead, 0, -1, 0);
    if (!ground || Math.abs(ground.position.y - topY) > 0.15) ahead = reach + 0.05;
    const dx = x + f.x * ahead, dz = z + f.z * ahead;
    let crouch = false;
    if (!this._fits(dx, topY, dz, STAND_HEIGHT)) {
      if (!this._fits(dx, topY, dz, CROUCH_HEIGHT)) return null;
      crouch = true;
    }
    return {
      kind: 'climb', height, crouch,
      path: [
        start,
        new THREE.Vector3(x, topY + 0.08, z),
        new THREE.Vector3(dx, topY + 0.02, dz),
      ],
      durations: [0.22 + height * 0.2, 0.2],
    };
  }

  _startClimb(ledge, input) {
    this.climb = { ...ledge, seg: 0, t: 0, elapsed: 0, total: ledge.durations.reduce((a, b) => a + b, 0) };
    if (ledge.crouch) { this.crouched = true; this.crouchToggle = true; }
    this.jumpBuffer = 0;
    this.stamina = Math.max(0, this.stamina - CLIMB_COST * (ledge.kind === 'vault' ? 0.6 : 1));
    this.velocity.set(0, 0, 0);
    this.sprinting = false;
    this.events.push({ type: ledge.kind, height: ledge.height });
    if (!ledge.crouch) input.clearTouchCrouch?.();
  }

  _updateClimb(dt) {
    const c = this.climb;
    c.t += dt;
    c.elapsed += dt;
    while (c.seg < c.durations.length && c.t >= c.durations[c.seg]) {
      c.t -= c.durations[c.seg];
      c.seg++;
    }
    let feet;
    if (c.seg >= c.durations.length) {
      feet = c.path[c.path.length - 1];
    } else {
      const k = smooth(c.t / c.durations[c.seg]);
      feet = _p.copy(c.path[c.seg]).lerp(c.path[c.seg + 1], k);
    }
    const h = this.height;
    this.collider.start.set(feet.x, feet.y + RADIUS, feet.z);
    this.collider.end.set(feet.x, feet.y + h - RADIUS, feet.z);
    this.height = damp(this.height, this.crouched ? CROUCH_HEIGHT : STAND_HEIGHT, 14, dt);
    this.horizontalSpeed = 0;
    this.onFloor = false;

    if (c.seg >= c.durations.length) {
      // terminou: mantém um pouco de impulso para frente
      this.forwardVector(_lf);
      const keep = c.kind === 'vault' ? 3.5 : 1;
      this.velocity.set(_lf.x * keep, 0, _lf.z * keep);
      this.climb = null;
      this.onFloor = true;
      this._collide();
      this.events.push({ type: 'land', speed: c.kind === 'vault' ? 4 : 2 });
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
    if (this.dead) return 'MORTO';
    if (this.climb) return this.climb.kind === 'vault' ? 'PULANDO OBSTÁCULO' : 'ESCALANDO';
    if (!this.onFloor) return this.velocity.y > 0 ? 'PULANDO' : 'CAINDO';
    if (this.crouched) return this.horizontalSpeed > 0.4 ? 'AGACHADO • ANDANDO' : 'AGACHADO';
    if (this.horizontalSpeed < 0.4) return 'PARADO';
    return this.sprinting ? 'CORRENDO' : 'ANDANDO';
  }
}
