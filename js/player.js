import * as THREE from 'three';
import { Capsule } from 'three/addons/math/Capsule.js';

// Controlador do personagem em primeira pessoa.
// Física: cápsula colidindo com o Octree do mundo (chão, paredes, rampas, teto).
// Movimentos: andar, correr, pular, agachar, deslizar, escalar obstáculos, subir escadas
// de mão, inclinar (espiar), rolamento ao cair, subir degraus baixos sozinho, andar na água
// rasa, nadar e mergulhar. Portas têm colisão própria (Octree de cada porta).

// valores próximos do real (um pouco mais de gravidade que 9,8 para o corpo não "flutuar")
const GRAVITY = 17;
const RADIUS = 0.35;
export const STAND_HEIGHT = 1.8;
export const CROUCH_HEIGHT = 1.3; // (agachado de verdade: olhos ~1,24 m, igual ao corpo animado)
const EYE_BELOW_TOP = 0.14;

const WALK_SPEED = 1.7;     // andar (modo andar / joystick pouco empurrado)
const JOG_SPEED = 3.6;      // trote, o padrão
const RUN_SPEED = 6.2;      // correr
const CROUCH_SPEED = 1.3;
const CROUCH_RUN_SPEED = 2.4;
const BACKWARD_MULT = 0.6;
const STRAFE_MULT = 0.85;
const JUMP_VELOCITY = 4.8;  // ~0,7 m de altura

const GROUND_ACCEL = 6;     // ganha velocidade aos poucos (inércia do corpo)
const SPRINT_ACCEL = 3.2;
const GROUND_DECEL = 9;
const AIR_ACCEL = 0.7;      // quase nenhum controle no ar
const MIN_FLOOR_NORMAL_Y = 0.55;  // ~56° — acima disso é parede
const SUBSTEPS = 5;
const COYOTE_TIME = 0.12;
const JUMP_BUFFER = 0.15;
const SNAP_DISTANCE = 0.35;

const FALL_DAMAGE_SPEED = 10; // m/s de impacto (~3 m de queda) a partir do qual causa dano
const ROLL_WINDOW = 0.35;     // agachar até esse tempo antes do impacto = rolamento
const ROLL_MIN_SPEED = 7.5;

// deslizar (agachar correndo)
const SLIDE_SPEED = 7;
const SLIDE_FRICTION = 2.2;
const SLIDE_MAX_TIME = 0.9;

// escadas de mão
const LADDER_SPEED = 1.7;
const LADDER_STEP = 0.45;

// degraus baixos (meio-fio, varanda, raízes) são subidos sem pular
const STEP_HEIGHT = 0.42;

// água
const SWIM_ENTER = 1.3;     // profundidade (dos pés à superfície) para começar a nadar
const SWIM_EXIT = 1.1;
const SWIM_SPEED = 2.5;
const SWIM_FAST = 3.6;
const FLOAT_DEPTH = 1.5;    // pés abaixo da superfície ao boiar (olhos logo acima d'água)

// parkour
const LEDGE_MIN = 0.42;       // abaixo disso o degrau é subido andando
const LEDGE_MAX = 2.15;       // altura máxima que dá para escalar partindo do chão
const VAULT_OVER_MAX = 1.25;  // obstáculos finos até essa altura são pulados por cima
const MANTLE_MAX = 1.35;      // até aqui: apoia as mãos e sobe; acima: escalada completa
const HANG_MAX = 2.75;        // no ar, agarra bordas até essa altura acima dos pés
const HANG_DROP = 1.95;       // pés abaixo da borda quando pendurado (braços esticados)

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
  constructor(octree, spawn, ladders = [], { waterAt = () => -Infinity, doors = [] } = {}) {
    this.octree = octree;
    this.ladders = ladders;
    this.waterAt = waterAt;
    this.doors = doors;
    this._octrees = [octree];
    this.swimming = false;
    this.waterY = -Infinity;
    this.waterDepth = 0;
    this.swimPhase = 0;
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
    this.walkMode = false;    // andar devagar (tecla X)
    this.aiming = false;      // mirando com a arma: anda devagar e não corre
    this.exertion = 0;        // cansaço (só som e respiração; não limita a corrida)
    this.stumble = 0;         // recuperação depois de um pouso forte
    this.floorNormal = new THREE.Vector3(0, 1, 0);
    this.hang = null;         // pendurado numa borda
    this.speedTarget = 0;
    this.slide = null;        // deslize em andamento
    this.ladder = null;       // escada de mão em uso
    this.ladderAhead = null;  // escada perto (para a dica na tela)
    this.ladderPhase = 0;
    this.rollTime = -1;       // >= 0 durante o rolamento
    this._crouchPressedAt = -10;
    this._prevCrouchHeld = false;
    this._clock = 0;

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
    this.slide = null;
    this.ladder = null;
    this.hang = null;
    this.rollTime = -1;
    this.lean = 0;
    this.swimming = false;
    this.stumble = 0;
    this.exertion = 0;
  }

  get isHanging() { return this.hang !== null; }

  get sliding() { return this.slide !== null; }
  get onLadder() { return this.ladder !== null; }
  get rolling() { return this.rollTime >= 0; }

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
  /**
   * Câmera de 1ª pessoa: os olhos do corpo, sem sair da cápsula (não atravessa paredes).
   * A câmera e as armas na mão usam o mesmo ponto (antes a arma ficava fora do lugar agachado).
   */
  clampView(v) {
    const cx = this.collider.start.x, cz = this.collider.start.z;
    let ox = v.x - cx, oz = v.z - cz;
    const maxR = 0.28 + Math.abs(this.leanOffset ?? 0);
    const r = Math.hypot(ox, oz);
    if (r > maxR) { ox *= maxR / r; oz *= maxR / r; }
    const top = this.collider.end.y + this.collider.radius - 0.06;
    return v.set(cx + ox, Math.min(top, Math.max(this.collider.start.y - this.collider.radius + 0.2, v.y)), cz + oz);
  }

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

    this._clock += dt;
    if (this.rollTime >= 0) { this.rollTime += dt; if (this.rollTime > 0.65) this.rollTime = -1; }

    if (this.climb) { this._updateClimb(dt); this._updateLean(dt, 0); return; }
    if (this.hang) { this._updateHang(dt, input, move); this._updateLean(dt, 0); return; }
    if (this.ladder) { this._updateLadder(dt, input, move); this._updateLean(dt, 0); return; }

    // portas próximas também colidem
    this._octrees.length = 1;
    for (const d of this.doors) {
      if (d.center.distanceToSquared(this.collider.start) < 16) this._octrees.push(d.octree);
    }

    // ---------- água ----------
    const feetY = this.collider.start.y - RADIUS;
    this.waterY = this.waterAt(this.collider.start.x, this.collider.start.z);
    this.waterDepth = this.waterY - feetY;
    if (!this.swimming && this.waterDepth > SWIM_ENTER) {
      this.swimming = true;
      this.events.push({ type: 'splash', speed: Math.abs(this.velocity.y) });
      this.velocity.y *= 0.25; // a água freia a queda
      this.slide = null;
    } else if (this.swimming && this.waterDepth < SWIM_EXIT) {
      this.swimming = false;
    }
    if (this.swimming) { this._updateSwim(dt, input, move); this._updateLean(dt, 0); return; }
    this.underwater = false;

    // entrar numa escada de mão
    const ladder = this._findLadder(move, false);
    if (ladder) { this._enterLadder(ladder); return; }

    // ---------- agachar / deslizar ----------
    const crouchPressed = input.wasPressed('crouchToggle') || (input.crouchHeld && !this._prevCrouchHeld);
    this._prevCrouchHeld = input.crouchHeld;
    if (crouchPressed) this._crouchPressedAt = this._clock;

    if (crouchPressed && !this.slide && this.sprinting && this.onFloor && this.horizontalSpeed > 5) {
      this._startSlide(input);
    } else if (input.wasPressed('crouchToggle')) {
      this.crouchToggle = !this.crouchToggle;
    }
    const wantSprint = input.sprint && move.y > 0.3 && !this.aiming;
    if (input.wasPressed('walkToggle')) this.walkMode = !this.walkMode;

    if (this.slide) {
      this.crouched = true;
    } else {
      if (wantSprint && this.crouchToggle) { this.crouchToggle = false; }
      if (wantSprint && !input.crouchHeld) input.clearTouchCrouch();
      const wantCrouch = (input.crouchHeld || this.crouchToggle) && !wantSprint;
      if (wantCrouch) {
        if (!this.crouched) this.events.push({ type: 'crouch' });
        this.crouched = true;
      } else if (this.crouched && this.canStand()) {
        this.crouched = false;
        this.events.push({ type: 'stand' });
      }
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

    // ---------- corrida (sem limite de fôlego) ----------
    const canSprint = wantSprint && !this.crouched && this.stumble <= 0;
    this.sprinting = canSprint && (this.onFloor || this.sprinting);

    // ---------- velocidade horizontal desejada ----------
    // joystick: pouco empurrado = andar, mais = trotar; teclado: trotar (ou andar no modo andar)
    const mag = Math.min(1, Math.hypot(move.x, move.y));
    let speed;
    if (this.crouched) speed = (input.sprint ? CROUCH_RUN_SPEED : CROUCH_SPEED) * Math.min(1, mag / 0.6);
    else if (this.sprinting) speed = RUN_SPEED;
    else if (this.walkMode) speed = WALK_SPEED * Math.min(1, mag / 0.6);
    else speed = mag < 0.65 ? WALK_SPEED * (mag / 0.65) : WALK_SPEED + (JOG_SPEED - WALK_SPEED) * ((mag - 0.65) / 0.35);
    if (this.aiming) speed = Math.min(speed, WALK_SPEED * 1.05);
    if (move.y < -0.1) speed *= BACKWARD_MULT;
    else if (Math.abs(move.x) > Math.abs(move.y)) speed *= STRAFE_MULT;
    // andando na água rasa fica mais lento
    if (this.waterDepth > 0.3) speed *= Math.max(0.45, 1 - this.waterDepth * 0.45);
    // depois de um pouso forte o corpo demora a se recuperar
    if (this.stumble > 0) { speed *= 0.35; this.stumble -= dt; }
    this.forwardVector(_forward);
    _right.set(-_forward.z, 0, _forward.x);
    _wish.set(0, 0, 0).addScaledVector(_forward, move.y).addScaledVector(_right, move.x);
    if (_wish.lengthSq() > 1e-6) _wish.normalize();
    // ladeira: subir é mais lento, descer um pouco mais rápido
    if (this.onFloor && this.floorNormal.y < 0.995) {
      const grade = -(this.floorNormal.x * _wish.x + this.floorNormal.z * _wish.z) / this.floorNormal.y;
      speed *= Math.max(0.5, Math.min(1.12, 1 - grade * 0.9));
    }
    _wish.multiplyScalar(speed);
    this.speedTarget = speed;

    // cansaço só para a respiração ficar ofegante (não há barra de fôlego)
    this.exertion = Math.max(0, Math.min(1, this.exertion + (this.sprinting && this.horizontalSpeed > 4 ? 0.07 : -0.05) * dt));

    if (this.slide) {
      // deslizando: perde velocidade aos poucos, dá para mirar um pouco com o movimento lateral
      this.slide.t += dt;
      const k = Math.exp(-SLIDE_FRICTION * dt);
      this.velocity.x = this.velocity.x * k + _right.x * move.x * 3 * dt;
      this.velocity.z = this.velocity.z * k + _right.z * move.x * 3 * dt;
      const hs = Math.hypot(this.velocity.x, this.velocity.z);
      if (hs < 2.6 || this.slide.t > SLIDE_MAX_TIME) this.slide = null;
    } else {
      // inércia: acelera devagar, freia mais rápido, no ar quase não muda de direção
      const cur = Math.hypot(this.velocity.x, this.velocity.z);
      const accel = !this.onFloor ? AIR_ACCEL : speed > cur + 0.05 ? (this.sprinting ? SPRINT_ACCEL : GROUND_ACCEL) : GROUND_DECEL;
      this.velocity.x = damp(this.velocity.x, _wish.x, accel, dt);
      this.velocity.z = damp(this.velocity.z, _wish.z, accel, dt);
    }

    // ---------- pulo (com coyote time e buffer) ----------
    this.timeSinceGround = this.onFloor ? 0 : this.timeSinceGround + dt;
    if (input.wasPressed('jump')) this.jumpBuffer = JUMP_BUFFER;
    else this.jumpBuffer -= dt;

    // escalar tem prioridade sobre o pulo quando há um obstáculo na frente
    if (this.jumpBuffer > 0 && this.timeSinceGround < 0.6 && !this.slide && this.stumble <= 0) {
      const ledge = this.findLedge(this.onFloor ? LEDGE_MIN : 0.1);
      if (ledge) {
        this._startClimb(ledge, input);
        return;
      }
    }
    // no ar, indo para frente contra uma borda alta: agarra e fica pendurado
    if (!this.onFloor && this.timeSinceGround > 0.08 && move.y > 0.3 && this.velocity.y < 2.5) {
      const grab = this.findLedge(1.0, HANG_MAX);
      if (grab && grab.height > 1.55 && this._startHang(grab)) return;
      if (grab && this.jumpBuffer > 0) { this._startClimb(grab, input); return; }
    }

    if (this.jumpBuffer > 0 && this.timeSinceGround < COYOTE_TIME && this.stumble <= 0) {
      if (this.slide) this.slide = null; // pulo no fim do deslize mantém o embalo
      if (this.crouched) {
        // pular estando agachado: levanta primeiro, se houver espaço
        if (this.canStand()) {
          this.crouched = this.crouchToggle = false;
          input.clearTouchCrouch();
        }
      }
      if (!this.crouched) {
        this.velocity.y = JUMP_VELOCITY;
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
    const wantX = this.velocity.x * dt, wantZ = this.velocity.z * dt;
    for (let i = 0; i < SUBSTEPS; i++) {
      this.collider.translate(_wish.copy(this.velocity).multiplyScalar(sdt));
      this._collide();
    }

    // travou num degrau baixo? tenta subir nele
    if (wasOnFloor && !jumping && !this.slide) {
      const want = Math.hypot(wantX, wantZ);
      const got = Math.hypot(this.collider.start.x - startX, this.collider.start.z - startZ);
      if (want > 0.004 && got < want * 0.6) this._tryStepUp(wantX - (this.collider.start.x - startX), wantZ - (this.collider.start.z - startZ), wantX / dt, wantZ / dt);
    }

    if (wasOnFloor && !this.onFloor && !jumping) this._snapToGround();

    if (this.onFloor && this.velocity.y < 0) this.velocity.y = 0;

    // ---------- pouso ----------
    if (!wasOnFloor && this.onFloor) {
      // rolamento: agachar logo antes de tocar o chão reduz o dano da queda
      const roll = fallSpeed > ROLL_MIN_SPEED && (this._clock - this._crouchPressedAt < ROLL_WINDOW) && this.horizontalSpeed > 0.5;
      this.events.push({ type: 'land', speed: fallSpeed, roll });
      // pouso pesado: o corpo amortece e perde velocidade por um instante
      if (!roll && fallSpeed > 6.5 && this.waterDepth < 0.5) {
        this.stumble = Math.min(0.9, (fallSpeed - 6) * 0.12);
        this.velocity.x *= 0.4;
        this.velocity.z *= 0.4;
      }
      if (roll) {
        this.rollTime = 0;
        this.forwardVector(_lf);
        this.velocity.x = _lf.x * 5.5;
        this.velocity.z = _lf.z * 5.5;
        this.crouched = true;
        this.crouchToggle = false;
        this.events.push({ type: 'roll' });
      }
      if (fallSpeed > FALL_DAMAGE_SPEED) {
        const dmg = (fallSpeed - FALL_DAMAGE_SPEED) * 9 * (roll ? 0.3 : 1) * (this.waterDepth > 0.5 ? 0.3 : 1);
        this.health = Math.max(0, this.health - dmg);
        this.events.push({ type: 'damage', amount: dmg });
      }
    }

    // ---------- passos ----------
    const moved = Math.hypot(this.collider.start.x - startX, this.collider.start.z - startZ);
    this.horizontalSpeed = dt > 0 ? moved / dt : 0;
    if (this.onFloor && this.horizontalSpeed > 0.4) {
      // passada cresce com a velocidade (como de verdade): ~0,75 m andando, ~1,5 m correndo
      const stride = this.crouched ? 0.5 : 0.45 + this.horizontalSpeed * 0.17 + Math.max(0, this.horizontalSpeed - 4) * 0.12;
      const before = Math.floor(this.stepPhase / Math.PI);
      this.stepPhase += (this.horizontalSpeed * dt / stride) * Math.PI;
      if (Math.floor(this.stepPhase / Math.PI) !== before) {
        this.events.push({ type: 'step', run: this.sprinting, crouch: this.crouched, speed: this.horizontalSpeed });
      }
    }

    // inclinar (espiar) só parado/andando no chão
    const leanInput = (this.onFloor && !this.sprinting) ? input.lean : 0;
    this._updateLean(dt, leanInput);

    // dica de escalada / escada (não precisa ser testada todo quadro)
    this._ledgeTimer -= dt;
    if (this._ledgeTimer <= 0) {
      this._ledgeTimer = 0.12;
      this.ladderAhead = this._findLadder(move, true);
      this.ledgeAhead = !this.ladderAhead && this.onFloor && !this.slide && move.y > -0.1 ? this.findLedge(LEDGE_MIN) : null;
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
   * Retorna { kind, height, path (pontos dos pés), durations, edge (borda), normal, topY } ou null.
   * kind: 'stepover' (passa por cima), 'speedvault' (salto rápido correndo), 'mantle' (apoia as
   * mãos e sobe), 'climb' (escalada alta, com impulso).
   */
  findLedge(minHeight, maxHeight = LEDGE_MAX) {
    const feet = this.collider.start.y - RADIUS;
    const x = this.collider.start.x, z = this.collider.start.z;
    const f = this.forwardVector(_lf);

    // 1) tem parede na frente? (do joelho até a altura máxima)
    let wall = Infinity;
    for (const h of [0.35, 0.9, 1.5, 1.8, 2.1, 2.5]) {
      if (h > maxHeight + 0.1) break;
      const hit = this._rayHit(x, feet + h, z, f.x, 0, f.z);
      if (hit && hit.distance < wall) wall = hit.distance;
    }
    if (wall > RADIUS + 0.55) return null;

    // 2) topo do obstáculo: raio de cima para baixo, logo depois da face da parede
    // (bem perto da face, para acertar também cercas e muretas finas)
    const reach = wall + 0.08;
    const top = this._rayHit(x + f.x * reach, feet + maxHeight + 0.3, z + f.z * reach, 0, -1, 0);
    if (!top) return null;
    const topY = top.position.y;
    const height = topY - feet;
    if (height < minHeight || height > maxHeight) return null;
    top.triangle.getNormal(_n);
    if (_n.y < 0.7) return null;

    // espaço livre acima da cabeça durante o movimento
    const headY = this.collider.end.y + RADIUS;
    const ceil = this._rayHit(x, headY, z, 0, 1, 0);
    if (ceil && ceil.distance < Math.max(0, topY + 0.2 + CROUCH_HEIGHT - headY) + 0.05) return null;

    const start = new THREE.Vector3(x, feet, z);
    const edge = new THREE.Vector3(x + f.x * wall, topY, z + f.z * wall);
    const info = { height, edge, normal: f.clone(), topY };

    // 3) obstáculo fino (cerca, mureta, caixote)? passa por cima
    const far = reach + 0.75;
    const beyond = this._rayHit(x + f.x * far, topY + 0.3, z + f.z * far, 0, -1, 0);
    const thin = !beyond || beyond.position.y < topY - 0.4;
    // (não salta por cima se do outro lado houver uma queda alta, ex.: mureta do terraço)
    const safeDrop = !beyond || beyond.position.y > feet - 0.6;
    if (thin && height <= VAULT_OVER_MAX && safeDrop && this.onFloor) {
      const lx = x + f.x * (far + 0.15), lz = z + f.z * (far + 0.15);
      const groundY = beyond ? beyond.position.y : topY - 1;
      if (this._fits(lx, Math.max(groundY, topY - 1.2), lz, STAND_HEIGHT) &&
          this._fits(x + f.x * reach, topY + 0.15, z + f.z * reach, CROUCH_HEIGHT)) {
        const fast = this.sprinting && this.horizontalSpeed > 4;
        return {
          ...info, kind: fast ? 'speedvault' : 'stepover', crouch: false,
          path: [
            start,
            new THREE.Vector3(x + f.x * Math.max(0, wall - RADIUS - 0.05), topY + 0.15, z + f.z * Math.max(0, wall - RADIUS - 0.05)),
            new THREE.Vector3(x + f.x * reach, topY + 0.2, z + f.z * reach),
            new THREE.Vector3(lx, Math.max(groundY, topY - 1.2) + 0.02, lz),
          ],
          // correndo: um salto rápido com uma mão; andando: passa a perna com calma
          durations: fast ? [0.13, 0.14, 0.22] : [0.28 + height * 0.12, 0.3, 0.32],
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
    if (height <= MANTLE_MAX) {
      // apoia as mãos na borda, empurra o corpo para cima e passa um joelho
      return {
        ...info, kind: 'mantle', crouch,
        path: [start, new THREE.Vector3(x, topY + 0.08, z), new THREE.Vector3(dx, topY + 0.02, dz)],
        durations: [0.3 + height * 0.22, 0.34],
      };
    }
    // escalada alta: impulso, mãos na borda, puxa o peito acima dela, sobe o joelho e levanta
    return {
      ...info, kind: 'climb', crouch,
      path: [
        start,
        new THREE.Vector3(x, feet + 0.3, z),
        new THREE.Vector3(x, topY - 0.55, z),
        new THREE.Vector3(x, topY + 0.08, z),
        new THREE.Vector3(dx, topY + 0.02, dz),
      ],
      durations: [0.16, 0.3 + height * 0.18, 0.32, 0.38],
    };
  }

  // ---------- pendurado na borda ----------
  _startHang(ledge) {
    const f = ledge.normal;
    const x = ledge.edge.x - f.x * (RADIUS + 0.06), z = ledge.edge.z - f.z * (RADIUS + 0.06);
    const feet = ledge.topY - HANG_DROP;
    if (!this._fits(x, feet, z, STAND_HEIGHT)) return false;
    this.hang = { edge: ledge.edge.clone(), normal: f.clone(), topY: ledge.topY, t: 0, x, z, feet };
    this.velocity.set(0, 0, 0);
    this.height = STAND_HEIGHT;
    this.crouched = false;
    this.sprinting = false;
    this.slide = null;
    this.events.push({ type: 'grab' });
    return true;
  }

  _updateHang(dt, input, move) {
    const h = this.hang;
    h.t += dt;
    // desliza de lado ao longo da borda (se ela continuar)
    if (Math.abs(move.x) > 0.3) {
      const rx = -h.normal.z, rz = h.normal.x;
      const step = move.x * 0.7 * dt;
      const ex = h.edge.x + rx * step, ez = h.edge.z + rz * step;
      const top = this._rayHit(ex + h.normal.x * 0.1, h.topY + 0.3, ez + h.normal.z * 0.1, 0, -1, 0);
      if (top && Math.abs(top.position.y - h.topY) < 0.12 && this._fits(h.x + rx * step, h.feet, h.z + rz * step, STAND_HEIGHT)) {
        h.edge.x = ex; h.edge.z = ez; h.x += rx * step; h.z += rz * step;
        h.shimmy = (h.shimmy || 0) + Math.abs(step) * 6;
      }
    }
    this.collider.start.set(h.x, h.feet + RADIUS, h.z);
    this.collider.end.set(h.x, h.feet + STAND_HEIGHT - RADIUS, h.z);
    this.horizontalSpeed = 0;
    this.onFloor = false;

    if ((input.wasPressed('jump') || move.y > 0.5) && h.t > 0.3) {
      // puxa o corpo para cima da borda
      const f = h.normal;
      const dx = h.edge.x + f.x * (RADIUS + 0.12), dz = h.edge.z + f.z * (RADIUS + 0.12);
      let crouch = false;
      if (!this._fits(dx, h.topY, dz, STAND_HEIGHT)) {
        if (!this._fits(dx, h.topY, dz, CROUCH_HEIGHT)) return;
        crouch = true;
      }
      this.hang = null;
      this._startClimb({
        kind: 'pullup', height: HANG_DROP, crouch, edge: h.edge, normal: f, topY: h.topY,
        path: [new THREE.Vector3(h.x, h.feet, h.z), new THREE.Vector3(h.x, h.topY - 0.55, h.z),
          new THREE.Vector3(h.x, h.topY + 0.08, h.z), new THREE.Vector3(dx, h.topY + 0.02, dz)],
        durations: [0.6, 0.35, 0.4],
      }, input);
    } else if ((move.y < -0.5 || input.crouchHeld || input.wasPressed('crouchToggle')) && h.t > 0.2) {
      // solta
      this.hang = null;
      this.velocity.set(-h.normal.x * 0.8, 0, -h.normal.z * 0.8);
      this.timeSinceGround = 1;
      this.events.push({ type: 'drop' });
    }
  }

  _startClimb(ledge, input) {
    this.climb = { ...ledge, seg: 0, t: 0, elapsed: 0, total: ledge.durations.reduce((a, b) => a + b, 0) };
    if (ledge.crouch) { this.crouched = true; this.crouchToggle = true; }
    this.jumpBuffer = 0;
    this.slide = null;
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

    if (c.seg >= c.durations.length && c.toLadder) {
      // terminou de passar da plataforma para a escada
      this.climb = null;
      this.velocity.set(0, 0, 0);
    } else if (c.seg >= c.durations.length) {
      // terminou: mantém um pouco de impulso para frente
      this.forwardVector(_lf);
      const keep = c.kind === 'speedvault' ? 4.5 : c.kind === 'stepover' ? 1.6 : 0.6;
      this.velocity.set(_lf.x * keep, 0, _lf.z * keep);
      this.climb = null;
      this.onFloor = true;
      this._collide();
      this.events.push({ type: 'land', speed: c.kind === 'speedvault' ? 4 : 2 });
    }
  }

  /**
   * Resolve a colisão triângulo a triângulo, separando chão de parede.
   * (O capsuleIntersect do Octree soma tudo num vetor só; encostado numa parede
   * isso faria o jogador "perder" o chão.)
   */
  _collide() {
    for (const oct of this._octrees) this._collideWith(oct);
  }

  _collideWith(octree) {
    _tris.length = 0;
    octree.getCapsuleTriangles(this.collider, _tris);
    for (let i = 0; i < _tris.length; i++) {
      const r = octree.triangleCapsuleIntersect(this.collider, _tris[i]);
      if (!r || r.depth <= 0) continue;
      const n = r.normal;
      if (n.y >= MIN_FLOOR_NORMAL_Y) {
        // chão caminhável: empurra só para cima (não escorrega em rampas)
        this.onFloor = true;
        this.floorNormal.copy(n);
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

  // ---------- deslizar ----------
  _startSlide(input) {
    this.forwardVector(_lf);
    const hs = Math.max(Math.hypot(this.velocity.x, this.velocity.z), SLIDE_SPEED);
    this.velocity.x = _lf.x * hs;
    this.velocity.z = _lf.z * hs;
    this.slide = { t: 0 };
    this.crouched = true;
    this.crouchToggle = false;
    input.clearTouchCrouch();
    this.events.push({ type: 'slide' });
  }

  // ---------- escadas de mão ----------
  /**
   * Procura uma escada para entrar. Com `hintOnly`, ignora o movimento (só para a dica).
   * Retorna { ladder, fromTop } ou null.
   */
  _findLadder(move, hintOnly) {
    if (!this.ladders.length || this.climb) return null;
    const feet = this.collider.start.y - RADIUS;
    const px = this.collider.start.x, pz = this.collider.start.z;
    const f = this.forwardVector(_lf);
    for (const l of this.ladders) {
      const rx = px - l.x, rz = pz - l.z;
      const out = rx * l.nx + rz * l.nz;        // distância para fora da escada
      const side = rx * l.tx + rz * l.tz;       // deslocamento lateral
      if (Math.abs(side) > l.width / 2 + 0.25) continue;
      const facing = -(f.x * l.nx + f.z * l.nz); // > 0 olhando para a escada
      const pushing = hintOnly || move.y > 0.3;
      if (feet > l.bottom - 0.4 && feet < l.top - 0.6 && out > 0 && out < RADIUS + 0.5 && facing > 0.35 && pushing) {
        return { ladder: l, fromTop: false };
      }
      if (Math.abs(feet - l.top) < 0.4 && out < 0.3 && out > -1.1 && facing < -0.35 && pushing && this.onFloor) {
        return { ladder: l, fromTop: true };
      }
    }
    return null;
  }

  _enterLadder({ ladder: l, fromTop }) {
    const px = this.collider.start.x, pz = this.collider.start.z;
    const side = Math.max(-0.15, Math.min(0.15, (px - l.x) * l.tx + (pz - l.z) * l.tz));
    const feet = fromTop ? l.top - 1.2 : Math.max(this.collider.start.y - RADIUS, l.bottom);
    const off = RADIUS + 0.08;
    const x = l.x + l.nx * off + l.tx * side, z = l.z + l.nz * off + l.tz * side;
    this.ladder = { l, x, z };
    this.slide = null;
    this.crouched = false;
    this.crouchToggle = false;
    this.velocity.set(0, 0, 0);
    this.lean = 0;
    if (fromTop) {
      // desce pela borda: pequena animação até a posição na escada
      this.climb = {
        kind: 'climb', crouch: false, seg: 0, t: 0, elapsed: 0, total: 0.45, toLadder: true,
        path: [this.feetPosition.clone(), new THREE.Vector3(x, l.top - 0.4, z), new THREE.Vector3(x, feet, z)],
        durations: [0.25, 0.2],
      };
    } else {
      this.collider.start.set(this.collider.start.x, feet + RADIUS, this.collider.start.z);
      this.collider.end.set(this.collider.start.x, feet + this.height - RADIUS, this.collider.start.z);
    }
    this.events.push({ type: 'ladder' });
  }

  _updateLadder(dt, input, move) {
    const { l } = this.ladder;
    this.forwardVector(_lf);
    // olhando para a escada, "frente" sobe; de costas para ela, "frente" desce
    const facing = -(_lf.x * l.nx + _lf.z * l.nz) >= -0.2 ? 1 : -1;
    const vy = move.y * facing * LADDER_SPEED;
    this.ladderVy = vy;
    const feet = this.collider.start.y - RADIUS;
    this.height = damp(this.height, STAND_HEIGHT, 14, dt);

    // gruda na escada
    const nx = damp(this.collider.start.x, this.ladder.x, 12, dt);
    const nz = damp(this.collider.start.z, this.ladder.z, 12, dt);
    const ny = feet + vy * dt;
    this.collider.start.set(nx, ny + RADIUS, nz);
    this.collider.end.set(nx, ny + this.height - RADIUS, nz);
    this.velocity.set(0, 0, 0);
    this.horizontalSpeed = 0;
    this.onFloor = false;

    const before = Math.floor(this.ladderPhase / Math.PI);
    this.ladderPhase += Math.abs(vy) * dt / LADDER_STEP * Math.PI;
    if (Math.floor(this.ladderPhase / Math.PI) !== before) this.events.push({ type: 'ladderStep' });

    if (input.wasPressed('jump')) {
      // solta da escada, pulando para trás
      this.ladder = null;
      this.velocity.set(l.nx * 3.5, 3, l.nz * 3.5);
      this.events.push({ type: 'jump' });
      return;
    }
    if (ny >= l.top - 0.02 && vy > 0) {
      // chegou no topo: sobe para a plataforma
      this.ladder = null;
      const x = this.collider.start.x, z = this.collider.start.z;
      this._startClimb({
        kind: 'climb', crouch: false, height: 1,
        path: [new THREE.Vector3(x, ny, z), new THREE.Vector3(x, l.top + 0.1, z),
          new THREE.Vector3(l.x - l.nx * 0.75, l.top + 0.03, l.z - l.nz * 0.75)],
        durations: [0.25, 0.3],
      }, input);
      return;
    }
    if (vy < 0) {
      // desceu até o chão
      this._collide();
      if (this.onFloor || ny <= l.bottom) {
        this.ladder = null;
        this.onFloor = true;
        this.events.push({ type: 'land', speed: 1 });
      }
    }
  }

  // ---------- subir degraus baixos ----------
  _tryStepUp(dx, dz, vx, vz) {
    _saveStart.copy(this.collider.start);
    _saveEnd.copy(this.collider.end);
    const savedVel = _lf.copy(this.velocity);
    const feet0 = this.collider.start.y;
    // sobe, verifica espaço, avança e desce de novo
    this.collider.translate(_push.set(0, STEP_HEIGHT, 0));
    let blocked = false;
    for (const oct of this._octrees) if (oct.capsuleIntersect(this.collider)) { blocked = true; break; }
    if (!blocked) {
      // avança pelo menos um pouco: obstáculos arredondados (troncos) precisam disso
      const len = Math.hypot(dx, dz);
      const adv = Math.max(len, 0.28) / Math.max(len, 1e-6);
      this.collider.translate(_push.set(dx * adv, 0, dz * adv));
      this.velocity.set(vx, 0, vz);
      this._collide();
      this.onFloor = false;
      this.collider.translate(_push.set(0, -STEP_HEIGHT - 0.06, 0));
      this._collide();
      const rise = this.collider.start.y - feet0;
      const moved = Math.hypot(this.collider.start.x - _saveStart.x, this.collider.start.z - _saveStart.z);
      if (this.onFloor && rise > 0.03 && rise < STEP_HEIGHT + 0.03 && moved > Math.hypot(dx, dz) * 0.5) {
        this.velocity.set(savedVel.x, 0, savedVel.z);
        this.events.push({ type: 'stepUp', rise });
        return;
      }
    }
    this.collider.start.copy(_saveStart);
    this.collider.end.copy(_saveEnd);
    this.velocity.copy(savedVel);
    this.onFloor = true;
  }

  // ---------- nadar e mergulhar ----------
  _updateSwim(dt, input, move) {
    this.crouched = false;
    this.crouchToggle = false;
    this.sprinting = false;
    this.height = damp(this.height, STAND_HEIGHT, 10, dt);
    this.timeSinceGround = 1;

    const fast = input.sprint;
    this.forwardVector(_forward);
    _right.set(-_forward.z, 0, _forward.x);
    _wish.set(0, 0, 0).addScaledVector(_forward, move.y).addScaledVector(_right, move.x);
    if (_wish.lengthSq() > 1) _wish.normalize();
    _wish.multiplyScalar(fast ? SWIM_FAST : SWIM_SPEED);
    this.velocity.x = damp(this.velocity.x, _wish.x, 3, dt);
    this.velocity.z = damp(this.velocity.z, _wish.z, 3, dt);

    const feet = this.collider.start.y - RADIUS;
    const floatFeet = this.waterY - FLOAT_DEPTH;
    const submerged = feet < floatFeet - 0.35;
    let vyTarget;
    if (input.crouchHeld) vyTarget = -2.2;                 // mergulhar
    else if (input.jumpHeld && submerged) vyTarget = 2.4;  // voltar para a superfície
    else vyTarget = Math.max(-1.5, Math.min(1.5, (floatFeet - feet) * 2.5)); // boiar
    // debaixo d'água, nadar para frente segue o olhar (para cima ou para baixo)
    if (submerged || (move.y > 0 && this.pitch < -0.4)) vyTarget += move.y * Math.sin(this.pitch) * (fast ? SWIM_FAST : SWIM_SPEED);
    this.velocity.y = damp(this.velocity.y, vyTarget, 3, dt);

    // sair da água subindo no píer / margem
    if (input.wasPressed('jump') && !submerged) {
      const ledge = this.findLedge(0.1);
      if (ledge) { this.swimming = false; this._startClimb(ledge, input); return; }
    }

    const startX = this.collider.start.x, startZ = this.collider.start.z;
    const sdt = dt / SUBSTEPS;
    this.onFloor = false;
    for (let i = 0; i < SUBSTEPS; i++) {
      this.collider.translate(_push.copy(this.velocity).multiplyScalar(sdt));
      this._collide();
    }
    this.horizontalSpeed = Math.hypot(this.collider.start.x - startX, this.collider.start.z - startZ) / Math.max(dt, 1e-4);

    const before = Math.floor(this.swimPhase / Math.PI);
    this.swimPhase += dt * (1.6 + this.horizontalSpeed * 0.9);
    if (Math.floor(this.swimPhase / Math.PI) !== before && this.horizontalSpeed > 0.4) {
      this.events.push({ type: 'swimStroke', under: submerged });
    }
    this.underwater = submerged;
  }

  get state() {
    if (this.dead) return 'MORTO';
    if (this.swimming) return this.underwater ? 'MERGULHANDO' : 'NADANDO';
    if (this.ladder || this.climb?.toLadder) return 'NA ESCADA';
    if (this.slide) return 'DESLIZANDO';
    if (this.rollTime >= 0) return 'ROLANDO';
    if (this.hang) return 'PENDURADO';
    if (this.climb) return { speedvault: 'SALTANDO OBSTÁCULO', stepover: 'PASSANDO POR CIMA', mantle: 'SUBINDO', climb: 'ESCALANDO', pullup: 'SUBINDO NA BORDA' }[this.climb.kind] ?? 'ESCALANDO';
    if (!this.onFloor) return this.velocity.y > 0 ? 'PULANDO' : 'CAINDO';
    if (this.crouched) return this.horizontalSpeed > 0.4 ? 'AGACHADO • ANDANDO' : 'AGACHADO';
    if (this.horizontalSpeed < 0.4) return 'PARADO';
    if (this.sprinting) return 'CORRENDO';
    return this.horizontalSpeed > 2.4 ? 'TROTANDO' : 'ANDANDO';
  }
}
