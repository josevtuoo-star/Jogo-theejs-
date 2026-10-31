extends CharacterBody3D
## Personagem jogável.
## - Movimento com peso: acelera, freia, faz curva aberta correndo (inércia), sobe rampas
##   mais devagar e desce mais rápido; corrida, agachar (com teste de teto).
## - Pulo com "tempo de coiote", memória do botão e altura variável (segurar = mais alto).
## - Parkour: sobe em obstáculos (0,45 a 1,45 m), salta por cima de muros finos correndo,
##   agarra bordas altas no ar, fica pendurado e sobe; desliza correndo (agachar), rola ao
##   cair de alto em movimento; queda alta parado = aterrissagem pesada.
## - Soco em combo (jab, direto, gancho) e chute frontal que empurram objetos com física.
## - Câmera em 3ª pessoa (braço que não atravessa paredes) e 1ª pessoa estilo bodycam
##   (na cabeça, balança com o corpo, lente grande-angular olho de peixe).
## - Animações misturadas por uma AnimationTree montada aqui; as de andar/correr são
##   reamostradas para o mesmo ciclo e fase (os pés não "trocam" ao misturar).

enum Mode { NORMAL, MANTLE, HANG, SLIDE, ROLL, ACTION }

# --- velocidades (m/s) e física ---
@export var walk_speed := 1.5
@export var jog_speed := 3.6
@export var sprint_speed := 5.8
@export var crouch_speed := 1.2
## 1ª pessoa: velocidade máxima andando de lado ou para trás
@export var side_speed := 1.7
@export var accel_ground := 14.0
@export var decel_ground := 18.0
@export var accel_air := 3.0
@export var jump_velocity := 4.8
## gravidade subindo com o botão de pulo segurado / caindo ou sem segurar
@export var gravity_up := 9.8
@export var gravity_down := 17.0
@export var coyote_time := 0.12
@export var jump_buffer := 0.15
## força máxima (N) com que o personagem empurra caixas, bolas etc. ao andar contra elas
@export var push_force := 260.0
## atrito do deslizamento (m/s²): quanto maior, menos ele desliza
@export var slide_friction := 3.4
## massa do personagem (kg): o peso dele é aplicado em objetos com física sob os pés
## (gangorra, caixas)
@export var body_mass := 75.0

# --- câmera ---
@export var mouse_sensitivity := 0.0025
@export var touch_sensitivity := 0.0055
@export var pad_sensitivity := 3.0
@export var tp_distance := 3.0
@export var tp_fov := 70.0
## 1ª pessoa (bodycam): campo de visão bem aberto; a lente do pós-processamento curva as bordas
@export var fp_fov := 98.0

const STAND_H := 1.8
const CROUCH_H := 1.15
const SLIDE_H := 0.8
const RADIUS := 0.3
const SKEL := "Scene/Armature_15_M/Skeleton3D:"
## altura das mãos acima dos pés na pose pendurada
const HANG_REACH := 2.07
## andar/correr: direção do movimento (no espaço do modelo) usada para alinhar a fase, e
## quantos metros o corpo anda num ciclo completo (2 passos) de cada animação
const LOCO := {
	"walk": [Vector3(0, 0, 1), 1.85], "jog": [Vector3(0, 0, 1), 3.4], "sprint": [Vector3(0, 0, 1), 3.9],
	"walk_back": [Vector3(0, 0, -1), 0.95], "strafe_left": [Vector3(1, 0, 0), 0.8], "strafe_right": [Vector3(-1, 0, 0), 0.8],
}
const ANIM_CROUCH := 0.75
## velocidade das animações de soco (as originais são lentas)
const PUNCH_TS := 1.5
## combo: animação, instante do impacto e quando já pode emendar o próximo (tempo da
## animação, em s), força (N·s), alcance e altura do golpe
const PUNCHES := [
	{"anim": "punch_jab", "hit": 0.25, "next": 0.45, "end": 1.0, "force": 12.0, "reach": 0.72, "height": 1.45},
	{"anim": "punch_cross", "hit": 0.33, "next": 0.55, "end": 1.15, "force": 18.0, "reach": 0.78, "height": 1.45},
	{"anim": "punch_hook", "hit": 0.33, "next": 0.6, "end": 1.0, "force": 26.0, "reach": 0.75, "height": 1.2},
]
const KICK_TS := 1.5
const KICK := {"hit": 0.72, "end": 1.45, "force": 42.0, "reach": 0.85, "height": 0.8}
## animações que fazem parkour/ações (tocadas por cima de tudo, uma de cada vez)
const PK := ["climb_up", "ledge_hang", "slide_start", "slide", "slide_exit", "roll", "land_hard", "kick"]
const LOOPS := ["idle", "walk", "jog", "sprint", "walk_back", "strafe_left", "strafe_right",
	"crouch_idle", "crouch_walk", "jump_air", "run_jump", "fight_idle", "idle_hurt", "ledge_hang", "slide", "climb_wall"]

const SFX := "res://assets/sfx/"

@onready var col: CollisionShape3D = $Collision
@onready var visual: Node3D = $Visual
@onready var model: Node3D = $Visual/Model
@onready var rig: Node3D = $CamRig
@onready var arm: SpringArm3D = $CamRig/SpringArm3D
@onready var cam: Camera3D = $CamRig/SpringArm3D/Camera3D

var mode := Mode.NORMAL
var cam_yaw := 0.0
var cam_pitch := -0.2
var first_person := false
var cam_blend := 0.0 # 0 = 3ª pessoa, 1 = 1ª pessoa
var crouching := false
var crouch_amt := 0.0
var air_amt := 0.0
var combat := 0.0 # postura de luta depois de socar (vai sumindo)
var model_yaw := 0.0
var sprinting := false
## quantos golpes acertaram alguma coisa (para o HUD)
var hits := 0

var _tree: AnimationTree
var _skel: Skeleton3D
var _head_bone := -1
var _chest_bone := -1
var _head_hider: Node
var _post: CanvasItem
var _capsule: CapsuleShape3D
var _hit_shape := SphereShape3D.new()
var _coyote := 0.0
var _buffer := 0.0
var _air_time := 0.0
var _air_run := 0.0
var _jump_held := false
var _crouch_tap := 0.0
var _mode_t := 0.0
var _grab_cd := 0.0
# soco
var _punch_t := -1.0 # tempo desde o início do soco atual (< 0 = não está socando)
var _punch_idx := 0
var _punch_hit := false
var _punch_queue := 0.0
var _punch_last := -10.0
# parkour
var _m_start := Vector3.ZERO
var _m_end := Vector3.ZERO
var _m_dur := 1.0
var _m_exit := Vector3.ZERO
var _m_vault := false
var _hang_pos := Vector3.ZERO
var _hang_n := Vector3.FORWARD
var _hang_point := Vector3.ZERO
var _hang_top := 0.0
var _slide_dir := Vector3.FORWARD
var _slide_speed := 0.0
var _slide_phase := 0
var _roll_dir := Vector3.FORWARD
var _roll_speed := 0.0
var _act := ""
var _act_dur := 0.0
var _act_hit := false
var _pk_amt := 0.0
var _pk_target := 0.0
var _pk_fade := 0.15
var _pk_stop_at := -1.0
# aterrissagem
var _land_t := -1.0
var _land_cut := 0.0
var _land_slow := 0.0
# câmera e visual
var _step_dist := 0.0
var _shake := 0.0
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _pivot_y := 0.0
var _head_off := Vector3(0, 1.6, 0)
var _chest_off := Vector3(0, 1.4, 0)
var _sway := Vector2.ZERO
var _sway_base := Vector2.ZERO
var _blend_pos := Vector2.ZERO
var _moving_amt := 0.0
var _spawn: Transform3D
var _mouse_look := Vector2.ZERO
var _time := 0.0
var _hitstop := false
var _hint_tick := 0
var _sfx := {}
var _spark: CPUParticles3D
var _dust: CPUParticles3D


func _ready() -> void:
	Inputs.setup()
	_spawn = global_transform
	cam_yaw = rotation.y
	model_yaw = cam_yaw + PI
	rotation = Vector3.ZERO
	_capsule = col.shape as CapsuleShape3D
	_hit_shape.radius = 0.36
	_prev_pos = global_position
	_cur_pos = global_position
	_pivot_y = global_position.y
	arm.add_excluded_object(get_rid())
	_setup_animation()
	_setup_sounds()
	_setup_particles()


# ------------------------------------------------------------------ física / movimento

func _physics_process(delta: float) -> void:
	_prev_pos = global_position
	_time += delta
	_mode_t += delta
	_grab_cd -= delta
	if Input.is_action_just_pressed("reset") or global_position.y < -20.0:
		respawn()
		return
	match mode:
		Mode.NORMAL:
			_move_normal(delta)
		Mode.MANTLE:
			_move_mantle()
		Mode.HANG:
			_move_hang(delta)
		Mode.SLIDE:
			_move_slide(delta)
		Mode.ROLL:
			_move_roll(delta)
		Mode.ACTION:
			_move_action(delta)
	if _pk_stop_at > 0.0 and _time >= _pk_stop_at:
		_pk_stop_at = -1.0
		_pk_stop(0.25)
	_footsteps(delta)
	_hint_tick += 1
	if _hint_tick % 4 == 0:
		_update_hints()
	_cur_pos = global_position


func _read_move() -> Array:
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var mag := minf(inp.length(), 1.0)
	var dir := Vector3(inp.x, 0.0, inp.y).rotated(Vector3.UP, cam_yaw)
	if dir.length() > 0.001:
		dir = dir.normalized()
	return [dir, mag, inp]


func _move_normal(delta: float) -> void:
	var was_on_floor := is_on_floor()
	var r := _read_move()
	var dir: Vector3 = r[0]
	var mag: float = r[1]
	var inp: Vector2 = r[2]
	var hv := Vector3(velocity.x, 0.0, velocity.z)

	if Input.is_action_just_pressed("crouch"):
		if not was_on_floor:
			_crouch_tap = 0.4 # no ar: prepara o rolamento
		elif hv.length() > 4.2 and not crouching and _punch_t < 0.0:
			_start_slide()
			return
		elif crouching:
			_try_stand()
		else:
			_set_crouch(true)
	_crouch_tap -= delta

	if Input.is_action_just_pressed("kick") and was_on_floor and _punch_t < 0.0 and not crouching:
		_start_action("kick")
		return

	# velocidade desejada
	var forwardness := -inp.y / maxf(mag, 0.001) # 1 = para frente da câmera
	sprinting = Input.is_action_pressed("sprint") and mag > 0.5 and not crouching \
		and (not first_person or forwardness > 0.6) and _punch_t < 0.0
	var target_speed: float
	if crouching:
		target_speed = crouch_speed * mag
	elif sprinting:
		target_speed = sprint_speed
	elif mag < 0.6:
		target_speed = walk_speed * mag / 0.6
	else:
		target_speed = lerpf(walk_speed, jog_speed, (mag - 0.6) / 0.4)
	if first_person and forwardness < 0.5:
		target_speed = minf(target_speed, side_speed)
	if was_on_floor:
		# ladeira: subindo cansa (mais devagar), descendo embala um pouco
		var n := get_floor_normal()
		var uphill := -Vector3(n.x, 0.0, n.z).dot(dir)
		target_speed *= clampf(1.0 - uphill * 1.1, 0.55, 1.15)
	if _punch_t >= 0.0:
		target_speed *= 0.2
	if _land_slow > 0.0:
		target_speed *= 0.45
		_land_slow -= delta

	var target := dir * target_speed
	if was_on_floor:
		var cur := hv.length()
		if cur > 1.5 and target.length() > 0.5:
			var ang := hv.signed_angle_to(target, Vector3.UP)
			if absf(ang) > 2.4 and cur > 4.0:
				# meia-volta correndo: primeiro freia
				hv = hv.move_toward(Vector3.ZERO, decel_ground * 1.2 * delta)
			else:
				# inércia: quanto mais rápido, mais aberta a curva
				var k := clampf((cur - walk_speed) / (sprint_speed - walk_speed), 0.0, 1.0)
				var max_turn := lerpf(14.0, 4.0, k) * delta
				var nl := move_toward(cur, target.length(), (accel_ground if target.length() > cur else decel_ground) * delta)
				hv = hv.normalized().rotated(Vector3.UP, clampf(ang, -max_turn, max_turn)) * nl
		else:
			hv = hv.move_toward(target, (accel_ground if target.length() > cur else decel_ground) * delta)
	else:
		hv = hv.move_toward(target, accel_air * delta)
	# no início do soco, um pequeno passo à frente
	if _punch_t >= 0.0 and _punch_t < 0.12 and was_on_floor:
		hv += _facing() * 12.0 * delta * (1.0 - _punch_t / 0.12)
	velocity.x = hv.x
	velocity.z = hv.z

	# pulo: coiote (pular logo depois de sair da borda) e memória (apertou um pouco antes)
	_coyote = coyote_time if was_on_floor else _coyote - delta
	if Input.is_action_just_pressed("jump"):
		_buffer = jump_buffer
	else:
		_buffer -= delta
	if _buffer > 0.0:
		if was_on_floor and _punch_t < 0.0 and _try_parkour(dir if mag > 0.2 else Vector3.ZERO):
			_buffer = 0.0
			return
		if _coyote > 0.0 and (not crouching or _try_stand()):
			velocity.y = jump_velocity
			_coyote = 0.0
			_buffer = 0.0
			_jump_held = true
			_air_run = clampf((hv.length() - 3.0) / 2.0, 0.0, 1.0)
			_on_jump()
	if not Input.is_action_pressed("jump"):
		_jump_held = false
	if not was_on_floor or velocity.y > 0.0:
		var g := gravity_up if (velocity.y > 0.0 and _jump_held) else gravity_down
		velocity.y = maxf(velocity.y - g * delta, -40.0)

	var vy_before := velocity.y
	move_and_slide()
	_push_bodies(delta, target)

	if is_on_floor():
		if not was_on_floor and _air_time > 0.12:
			_on_land(-vy_before, hv.length())
		_air_time = 0.0
	else:
		_air_time += delta
		# no ar, perto de uma borda alta: agarra
		if velocity.y < 2.5 and _grab_cd <= 0.0 and _air_time > 0.08:
			_try_grab()

	_update_punch(delta)


func _facing() -> Vector3:
	return Vector3(sin(model_yaw), 0.0, cos(model_yaw))


func _yaw_of(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)


func _set_height(h: float) -> void:
	_capsule.height = h
	col.position.y = h * 0.5


func _set_crouch(on: bool) -> void:
	crouching = on
	_set_height(CROUCH_H if on else STAND_H)
	Inputs.crouching = on


## Levanta se houver espaço acima da cabeça. Devolve se conseguiu.
func _try_stand() -> bool:
	if not crouching:
		return true
	if test_move(global_transform, Vector3.UP * (STAND_H - CROUCH_H + 0.05)):
		return false
	_set_crouch(false)
	return true


## O corpo (cápsula de altura h) cabe com os pés em `pos`?
func _fits(pos: Vector3, h: float) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS - 0.03
	shape.height = h
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), pos + Vector3.UP * (h * 0.5 + 0.04))
	q.collision_mask = 1 | 2
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _push_bodies(delta: float, wanted: Vector3) -> void:
	var weighed := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider() as RigidBody3D
		if body == null:
			continue
		if c.get_normal().y > 0.6:
			# em pé em cima: o peso do corpo (o Godot não faz isso sozinho)
			if not weighed:
				weighed = true
				body.apply_impulse(Vector3.DOWN * body_mass * 9.8 * delta, c.get_position() - body.global_position)
			continue
		var n := -c.get_normal()
		n.y = 0.0
		if n.length() < 0.1:
			continue
		n = n.normalized()
		# leva o objeto até a velocidade do personagem, sem passar da força de um empurrão
		# (bola leve sai rolando; pilha pesada de caixas anda devagar)
		var dv := wanted.dot(n) - body.linear_velocity.dot(n)
		if dv <= 0.0:
			continue
		var j := minf(body.mass * dv * 0.6, push_force * delta)
		body.apply_impulse(n * j, c.get_position() - body.global_position)


func respawn() -> void:
	mode = Mode.NORMAL
	_pk_stop(0.1)
	global_transform = Transform3D(Basis(), _spawn.origin)
	velocity = Vector3.ZERO
	_prev_pos = global_position
	_cur_pos = global_position
	_pivot_y = global_position.y
	_set_crouch(false)


# ------------------------------------------------------------------ parkour

## Procura um obstáculo à frente: parede (normal), ponto na face, altura do topo.
func _ledge_probe(fwd: Vector3) -> Dictionary:
	if fwd.length() < 0.1:
		return {}
	var space := get_world_3d().direct_space_state
	var base := global_position
	for h in [0.35, 0.8, 1.3]:
		var from: Vector3 = base + Vector3.UP * h
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 0.95, 1, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty() or absf(hit.normal.y) > 0.35:
			continue
		var n := Vector3(hit.normal.x, 0.0, hit.normal.z).normalized()
		var p: Vector3 = hit.position
		var inside := p - n * 0.2
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(inside.x, base.y + 3.4, inside.z), Vector3(inside.x, base.y + 0.2, inside.z), 1, [get_rid()])
		var top := space.intersect_ray(q2)
		if top.is_empty() or top.normal.y < 0.75:
			return {}
		return {"n": n, "point": p, "top": top.position.y, "h": top.position.y - base.y,
			"dist": (p - base).dot(-n) - 0.0}
	return {}


## Profundidade do topo do obstáculo a partir da face (99 = grosso demais para saltar por cima).
func _obstacle_depth(L: Dictionary) -> float:
	var space := get_world_3d().direct_space_state
	for d in [0.35, 0.55, 0.75, 0.95, 1.15]:
		var p: Vector3 = L.point - L.n * d
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, L.top + 0.3, p.z), Vector3(p.x, L.top - 0.3, p.z), 1, [get_rid()])
		if space.intersect_ray(q).is_empty():
			return d - 0.1
	return 99.0


## Pulo perto de um obstáculo baixo/médio: sobe nele ou salta por cima.
func _try_parkour(move_dir: Vector3) -> bool:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var fwd := move_dir if move_dir.length() > 0.1 else Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var L := _ledge_probe(fwd)
	if L.is_empty() or fwd.dot(-L.n) < 0.55 or L.dist > 0.85:
		return false
	var h: float = L.h
	if h < 0.45 or h > 1.45:
		return false
	var spd := hv.length()
	if h <= 1.25 and spd > 2.2:
		var depth := _obstacle_depth(L)
		if depth < 1.0:
			var land: Vector3 = L.point - L.n * (depth + 0.5)
			land.y = L.top + 0.08
			if _fits(land, CROUCH_H):
				_start_mantle(L, land, true, spd)
				return true
	var on_top: Vector3 = L.point - L.n * 0.42
	on_top.y = L.top + 0.02
	if _fits(on_top, STAND_H):
		_start_mantle(L, on_top, false, 0.0)
		return true
	if _fits(on_top, CROUCH_H):
		_set_crouch(true)
		_start_mantle(L, on_top, false, 0.0)
		return true
	return false


func _start_mantle(L: Dictionary, end: Vector3, vault: bool, spd: float) -> void:
	mode = Mode.MANTLE
	_mode_t = 0.0
	_m_start = global_position
	_m_end = end
	_m_vault = vault
	_m_exit = -L.n * maxf(spd, 3.6) if vault else Vector3.ZERO
	var h := end.y - _m_start.y
	_m_dur = (0.42 + 0.12 * h) if vault else (0.5 + 0.24 * h)
	model_yaw = _yaw_of(-L.n)
	velocity = Vector3.ZERO
	_punch_t = -1.0
	_pk_play("climb_up", 0.667 / _m_dur, 0.08)
	_play("cloth", -4.0)
	_play("grab", -10.0)


func _move_mantle() -> void:
	var u := clampf(_mode_t / _m_dur, 0.0, 1.0)
	# primeiro sobe (o corpo passa por cima da quina), depois avança
	var rise := 1.0 - pow(1.0 - minf(u / (0.55 if _m_vault else 0.65), 1.0), 2.0)
	var adv := u * u
	var p := _m_start.lerp(Vector3(_m_end.x, _m_start.y, _m_end.z), adv)
	p.y = lerpf(_m_start.y, _m_end.y, rise)
	global_position = p
	if u >= 1.0:
		mode = Mode.NORMAL
		velocity = _m_exit
		_air_time = 0.0
		_pk_stop(0.18 if _m_vault else 0.25)
		if not _m_vault:
			_play("step", -4.0)


## No ar, de frente para uma borda que as mãos alcançam: agarra e fica pendurado.
func _try_grab() -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var fwd := hv.normalized() if hv.length() > 0.6 else _facing()
	if first_person:
		fwd = Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var L := _ledge_probe(fwd)
	if L.is_empty() or L.dist > 0.7 or fwd.dot(-L.n) < 0.5:
		return
	var reach: float = L.top - global_position.y
	if reach > 2.3 or reach < 0.4:
		return
	if reach < 1.5:
		# borda na altura do peito: sobe direto, sem ficar pendurado
		var on_top: Vector3 = L.point - L.n * 0.42
		on_top.y = L.top + 0.02
		if _fits(on_top, STAND_H):
			_start_mantle(L, on_top, false, 0.0)
		elif _fits(on_top, CROUCH_H):
			_set_crouch(true)
			_start_mantle(L, on_top, false, 0.0)
		return
	mode = Mode.HANG
	_mode_t = 0.0
	_hang_n = L.n
	_hang_point = L.point
	_hang_top = L.top
	_hang_pos = L.point + L.n * (RADIUS + 0.05)
	_hang_pos.y = L.top - HANG_REACH
	velocity = Vector3.ZERO
	model_yaw = _yaw_of(-L.n)
	_set_crouch(false)
	_pk_play("ledge_hang", 1.0, 0.1)
	_play("grab", -2.0)
	if first_person:
		cam_pitch = maxf(cam_pitch, 0.6) # olha para as mãos na borda
	_shake = maxf(_shake, 0.12)


func _move_hang(delta: float) -> void:
	global_position = global_position.lerp(_hang_pos, minf(1.0, delta * 18.0))
	if _mode_t < 0.25:
		return
	var r := _read_move()
	var dir: Vector3 = r[0]
	var toward := dir.dot(-_hang_n) if r[1] > 0.5 else 0.0
	if Input.is_action_just_pressed("jump") or toward > 0.7:
		var on_top := _hang_point - _hang_n * 0.42
		on_top.y = _hang_top + 0.02
		var L := {"n": _hang_n, "point": _hang_point, "top": _hang_top}
		if _fits(on_top, STAND_H):
			_start_mantle(L, on_top, false, 0.0)
		elif _fits(on_top, CROUCH_H):
			_set_crouch(true)
			_start_mantle(L, on_top, false, 0.0)
	elif Input.is_action_just_pressed("crouch") or toward < -0.7:
		mode = Mode.NORMAL
		velocity = _hang_n * 1.2
		_grab_cd = 0.6
		_air_time = 0.2
		_pk_stop(0.2)


func _start_slide() -> void:
	mode = Mode.SLIDE
	_mode_t = 0.0
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	_slide_dir = hv.normalized()
	_slide_speed = hv.length() + 0.8
	_slide_phase = 0
	model_yaw = _yaw_of(_slide_dir)
	_set_height(SLIDE_H)
	_pk_play("slide_start", 1.7, 0.08)
	_tree.set("parameters/pk_seek/seek_request", 0.1)
	_play("cloth", -2.0)
	_play("slide", -6.0)


func _move_slide(delta: float) -> void:
	var on_floor := is_on_floor()
	var n := get_floor_normal() if on_floor else Vector3.UP
	# ladeira abaixo embala, atrito freia
	_slide_speed += Vector3(n.x, 0.0, n.z).dot(_slide_dir) * 9.8 * delta
	_slide_speed = move_toward(_slide_speed, 0.0, slide_friction * delta)
	var r := _read_move()
	if r[1] > 0.3:
		var ang := _slide_dir.signed_angle_to(r[0], Vector3.UP)
		_slide_dir = _slide_dir.rotated(Vector3.UP, clampf(ang, -1.2 * delta, 1.2 * delta))
	model_yaw = _yaw_of(_slide_dir)
	velocity.x = _slide_dir.x * _slide_speed
	velocity.z = _slide_dir.z * _slide_speed
	if not on_floor:
		velocity.y = maxf(velocity.y - gravity_down * delta, -40.0)
	move_and_slide()
	_push_bodies(delta, velocity)
	if _slide_phase == 0 and _mode_t > 0.42:
		_slide_phase = 1
		_pk_switch("slide")
	var jump := Input.is_action_just_pressed("jump")
	var blocked := is_on_wall() and Vector3(velocity.x, 0.0, velocity.z).length() < 0.5
	if _slide_speed < 1.8 or jump or blocked or Input.is_action_just_pressed("crouch") and _mode_t > 0.3:
		if _fits(global_position, STAND_H):
			mode = Mode.NORMAL
			_set_crouch(false)
			if jump:
				velocity.y = jump_velocity
				_jump_held = true
				_air_run = 1.0
				_pk_stop(0.15)
				_on_jump()
			else:
				_pk_switch("slide_exit")
				_tree.set("parameters/pk_ts/scale", 1.4)
				_pk_stop_at = _time + 0.3
		elif _fits(global_position, CROUCH_H):
			mode = Mode.NORMAL
			_set_crouch(true)
			_pk_stop(0.3)
		else:
			# ainda embaixo de alguma coisa: continua arrastando
			_slide_speed = maxf(_slide_speed, 1.6)


func _start_roll(speed: float) -> void:
	mode = Mode.ROLL
	_mode_t = 0.0
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	_roll_dir = hv.normalized() if hv.length() > 0.5 else _facing()
	_roll_speed = clampf(speed, 2.8, 5.0)
	model_yaw = _yaw_of(_roll_dir)
	_set_height(CROUCH_H)
	_pk_play("roll", 1.6, 0.06)
	_play("land", -6.0)
	_play("cloth", -4.0)


func _move_roll(delta: float) -> void:
	_roll_speed = move_toward(_roll_speed, 2.0, 2.5 * delta)
	velocity.x = _roll_dir.x * _roll_speed
	velocity.z = _roll_dir.z * _roll_speed
	velocity.y = 0.0 if is_on_floor() else maxf(velocity.y - gravity_down * delta, -40.0)
	move_and_slide()
	_push_bodies(delta, velocity)
	if _mode_t > 0.95:
		mode = Mode.NORMAL
		if _fits(global_position, STAND_H):
			_set_crouch(false)
		else:
			_set_crouch(true)
		_pk_stop(0.2)


## Ações que prendem o corpo: chute e aterrissagem pesada.
func _start_action(kind: String) -> void:
	mode = Mode.ACTION
	_mode_t = 0.0
	_act = kind
	_act_hit = false
	if kind == "kick":
		model_yaw = cam_yaw + PI
		_act_dur = KICK.end / KICK_TS
		combat = 1.0
		_pk_play("kick", KICK_TS, 0.1)
		_play("swing", -6.0)
	else:
		_act_dur = 0.8
		_pk_play("land_hard", 1.25, 0.04)
		_tree.set("parameters/pk_seek/seek_request", 0.1)


func _move_action(delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, decel_ground * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = 0.0 if is_on_floor() else maxf(velocity.y - gravity_down * delta, -40.0)
	move_and_slide()
	if _act == "kick" and not _act_hit and _mode_t * KICK_TS >= KICK.hit:
		_act_hit = true
		_do_hit(KICK)
	if _mode_t >= _act_dur:
		mode = Mode.NORMAL
		_pk_stop(0.3)


## Texto dos botões de toque conforme o que dá para fazer agora.
func _update_hints() -> void:
	var jump := "PULAR"
	var crouch := "LEVANTAR" if crouching else "AGACHAR"
	match mode:
		Mode.HANG:
			jump = "SUBIR"
			crouch = "SOLTAR"
		Mode.SLIDE:
			crouch = "LEVANTAR"
		Mode.NORMAL:
			var hv := Vector3(velocity.x, 0.0, velocity.z)
			if is_on_floor():
				if hv.length() > 4.2 and not crouching:
					crouch = "DESLIZAR"
				var r := _read_move()
				var fwd: Vector3 = r[0] if r[1] > 0.2 else Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
				var L := _ledge_probe(fwd)
				if not L.is_empty() and L.dist < 0.85 and fwd.dot(-L.n) > 0.55:
					if L.h >= 0.45 and L.h <= 1.45:
						jump = "SALTAR" if (L.h <= 1.25 and hv.length() > 2.2 and _obstacle_depth(L) < 1.0) else "SUBIR"
					elif L.h > 1.45 and L.h < 3.4:
						jump = "ESCALAR"
	Inputs.jump_label = jump
	Inputs.crouch_label = crouch


# ------------------------------------------------------------------ soco e chute

func _update_punch(delta: float) -> void:
	if Input.is_action_just_pressed("punch"):
		_punch_queue = 0.3
	else:
		_punch_queue -= delta
	if _punch_t >= 0.0:
		_punch_t += delta
		var p: Dictionary = PUNCHES[_punch_idx]
		var at := _punch_t * PUNCH_TS
		if not _punch_hit and at >= p.hit:
			_punch_hit = true
			_do_hit(p)
		if at >= p.next and _punch_queue > 0.0:
			_start_punch((_punch_idx + 1) % PUNCHES.size())
		elif at >= p.end or (at >= p.next and Vector2(velocity.x, velocity.z).length() > 1.0):
			_punch_t = -1.0
			_punch_last = _time
			_tree.set("parameters/punch/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	elif _punch_queue > 0.0:
		var nxt := (_punch_idx + 1) % PUNCHES.size() if _time - _punch_last < 0.5 else 0
		_start_punch(nxt)


func _start_punch(idx: int) -> void:
	_punch_idx = idx
	_punch_t = 0.0
	_punch_hit = false
	_punch_queue = 0.0
	combat = 1.0
	var p: Dictionary = PUNCHES[idx]
	_tree.set("parameters/punch_sel/transition_request", p.anim)
	if not _tree.get("parameters/punch/active"):
		_tree.set("parameters/punch/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	# sempre soca para onde a câmera olha
	model_yaw = cam_yaw + PI
	_play("swing", -8.0)


func _do_hit(p: Dictionary) -> void:
	var fwd := _facing()
	var h := lerpf(p.height, 0.8, crouch_amt)
	var center: Vector3 = global_position + Vector3.UP * h + fwd * p.reach
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _hit_shape
	q.transform = Transform3D(Basis(), center)
	q.exclude = [get_rid()]
	q.collision_mask = 1 | 2
	var res := get_world_3d().direct_space_state.intersect_shape(q, 8)
	var hit_soft := false
	var hit_hard := false
	for r in res:
		var c: Object = r.collider
		if c is RigidBody3D:
			var b := c as RigidBody3D
			var point: Vector3 = center - fwd * 0.2
			b.apply_impulse(fwd * p.force + Vector3.UP * p.force * 0.12, point - b.global_position)
			if b.has_method("on_punch"):
				b.on_punch(p.force, point)
			hit_soft = true
		else:
			hit_hard = true
	if hit_soft or hit_hard:
		hits += 1
		_spark.global_position = center - fwd * 0.25
		_spark.restart()
		_shake = 0.12 + p.force * 0.004
		_play("punch_heavy" if p.force > 20.0 else "punch", 0.0 if hit_soft else -4.0)
		if hit_hard and not hit_soft:
			_play("wall", -2.0)
		_do_hitstop(0.04 + p.force * 0.0012)


func _do_hitstop(t: float) -> void:
	if _hitstop:
		return
	_hitstop = true
	Engine.time_scale = 0.08
	await get_tree().create_timer(t, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop = false


# ------------------------------------------------------------------ pulo / queda

func _on_jump() -> void:
	_tree.set("parameters/jump/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_play("cloth", -6.0)


func _on_land(fall_speed: float, hspeed: float) -> void:
	var k := clampf((fall_speed - 2.0) / 10.0, 0.0, 1.0)
	_play("step", lerpf(-6.0, 4.0, k))
	_shake = maxf(_shake, 0.05 + 0.3 * k)
	_dust.global_position = global_position + Vector3.UP * 0.05
	_dust.amount = int(lerpf(6, 28, k))
	_dust.restart()
	_air_run = 0.0
	if fall_speed > 10.5:
		# queda de mais de ~3 m: rolando se estiver em movimento (ou apertou agachar antes)
		if hspeed > 2.0 or _crouch_tap > 0.0:
			_start_roll(hspeed)
		else:
			_play("land", 2.0)
			_start_action("land_hard")
			_land_slow = 0.4
		return
	if fall_speed > 6.5:
		_play("land", lerpf(-8.0, 2.0, k))
	if fall_speed > 4.0 and (hspeed < 2.0 or fall_speed > 8.0):
		_tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_land_t = 0.0
		_land_cut = lerpf(0.12, 0.4, k) # queda alta = agacha mais fundo
		_land_slow = lerpf(0.05, 0.35, k)


# ------------------------------------------------------------------ passos e sons

func _footsteps(delta: float) -> void:
	if mode != Mode.NORMAL:
		_step_dist = 0.0
		return
	var spd := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or spd < 0.4:
		_step_dist = minf(_step_dist, 0.3)
		return
	_step_dist += spd * delta
	var stride := 0.55 if crouching else (0.85 if spd < 2.0 else (1.55 if spd < 4.5 else 1.95))
	if _step_dist >= stride:
		_step_dist = 0.0
		var vol := -14.0 if crouching else lerpf(-10.0, 0.0, clampf(spd / sprint_speed, 0.0, 1.0))
		_play("step", vol)
		if spd > 4.5:
			_play("cloth", -16.0)


func _setup_sounds() -> void:
	var sets := {
		"step": ["step_concrete_0", "step_concrete_1", "step_concrete_2", "step_concrete_3", "step_concrete_4"],
		"punch": ["imp_punch_medium_0", "imp_punch_medium_1"],
		"punch_heavy": ["imp_punch_heavy_0", "imp_punch_heavy_1"],
		"swing": ["cloth_0", "cloth_1", "cloth_2"],
		"cloth": ["cloth_0", "cloth_1", "cloth_2"],
		"wall": ["imp_wood_medium_0", "imp_wood_medium_1"],
		"land": ["imp_soft_heavy_0"],
		"grab": ["imp_wood_medium_0", "imp_soft_heavy_0"],
		"slide": ["imp_soft_heavy_0"],
	}
	for key in sets:
		var r := AudioStreamRandomizer.new()
		for f in sets[key]:
			r.add_stream(-1, load(SFX + f + ".mp3"))
		r.random_pitch = 1.12
		r.random_volume_offset_db = 2.0
		var pl := AudioStreamPlayer3D.new()
		pl.stream = r
		pl.max_polyphony = 3
		pl.unit_size = 6.0
		pl.position = Vector3.UP * (0.1 if key in ["step", "land", "slide"] else 1.3)
		add_child(pl)
		_sfx[key] = pl


func _play(key: String, db := 0.0) -> void:
	var pl: AudioStreamPlayer3D = _sfx.get(key)
	if pl:
		pl.volume_db = db
		pl.play()


func _setup_particles() -> void:
	_spark = _make_particles(Color(1.0, 0.85, 0.5), 14, 0.22, 3.5, 0.025)
	_dust = _make_particles(Color(0.55, 0.5, 0.42, 0.7), 16, 0.7, 1.4, 0.06)
	_dust.direction = Vector3.UP
	_dust.spread = 80.0
	_dust.gravity = Vector3(0, 0.5, 0)
	_dust.scale_amount_max = 2.5


func _make_particles(c: Color, amount: int, life: float, speed: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	if c.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	p.mesh = m
	p.top_level = true
	add_child(p)
	return p


# ------------------------------------------------------------------ câmera e visual

func _unhandled_input(event: InputEvent) -> void:
	if Inputs.touch_mode:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_look += event.relative
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	# posição suavizada entre dois passos da física (sem "tremido" em telas de 90/120 Hz)
	var f := Engine.get_physics_interpolation_fraction()
	var pos := _prev_pos.lerp(_cur_pos, f)
	# pendurado, o modelo encosta na parede (as mãos ficam na quina)
	visual.global_position = pos - _hang_n * 0.14 * _pk_amt if mode == Mode.HANG else pos

	# olhar
	var look := Inputs.take_look() * touch_sensitivity + _mouse_look * mouse_sensitivity
	_mouse_look = Vector2.ZERO
	var pad := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	look += pad * pad_sensitivity * delta
	cam_yaw = wrapf(cam_yaw - look.x, -PI, PI)
	var min_p := -1.35 if first_person else -1.2
	var max_p := 1.3 if first_person else 0.75
	cam_pitch = clampf(cam_pitch - look.y, min_p, max_p)

	if Input.is_action_just_pressed("camera"):
		first_person = not first_person
		Inputs.first_person = first_person
	cam_blend = move_toward(cam_blend, 1.0 if first_person else 0.0, delta * 4.0)
	var e := smoothstep(0.0, 1.0, cam_blend)

	# para onde o corpo olha: em 1ª pessoa e socando, para a câmera; senão, para onde anda
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if mode == Mode.NORMAL:
		var target_yaw := model_yaw
		var turn := 10.0
		if first_person or _punch_t >= 0.0:
			target_yaw = cam_yaw + PI
			turn = 25.0
		elif hv.length() > 0.3:
			target_yaw = atan2(hv.x, hv.z)
			turn = 12.0 if is_on_floor() else 4.0
		model_yaw = lerp_angle(model_yaw, target_yaw, 1.0 - exp(-turn * delta))
	visual.rotation = Vector3(0.0, model_yaw, 0.0)

	_update_animation(delta, hv)

	# 3ª pessoa: acima do ombro
	_pivot_y = lerpf(_pivot_y, pos.y, 1.0 - exp(-14.0 * delta))
	if absf(_pivot_y - pos.y) > 1.0 or mode == Mode.MANTLE:
		_pivot_y = pos.y
	var low := maxf(crouch_amt, _pk_amt if mode in [Mode.SLIDE, Mode.ROLL] else 0.0)
	var tp_pivot := Vector3(pos.x, _pivot_y + lerpf(1.55, 1.0, low), pos.z)
	# 1ª pessoa (bodycam): presa à cabeça; o balanço do tronco inclina a imagem
	var cam_fwd := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var cam_right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	if _chest_bone >= 0:
		var chest_pose := _skel.get_bone_global_pose(_chest_bone)
		var chest := _skel.global_transform * chest_pose.origin
		_chest_off = _chest_off.lerp(chest - visual.global_position, 1.0 - exp(-30.0 * delta))
		var head := _skel.global_transform * _skel.get_bone_global_pose(_head_bone).origin
		_head_off = _head_off.lerp(head - visual.global_position, 1.0 - exp(-25.0 * delta))
		var up_b := (_skel.global_transform.basis * chest_pose.basis).orthonormalized().y
		var raw := Vector2(up_b.dot(cam_fwd), -up_b.dot(cam_right))
		_sway_base = _sway_base.lerp(raw, 1.0 - exp(-1.5 * delta))
		_sway = _sway.lerp((raw - _sway_base).clamp(Vector2(-0.25, -0.25), Vector2(0.25, 0.25)), 1.0 - exp(-12.0 * delta))
	var model_fwd := _facing()
	var fp_pivot := visual.global_position + _head_off + Vector3.UP * 0.07 + model_fwd * 0.1 \
		+ cam_fwd * 0.1 * clampf(-cam_pitch, 0.0, 1.2)
	if e > 0.01:
		# a câmera do peito nunca entra na parede (pendurado, encostado num muro...)
		var from := global_position + Vector3.UP * minf(_head_off.y, _capsule.height - 0.15)
		var q := PhysicsRayQueryParameters3D.create(from, fp_pivot, 1 | 2, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			fp_pivot = from + (fp_pivot - from).normalized() * maxf(from.distance_to(hit.position) - 0.12, 0.0)
	rig.global_position = tp_pivot.lerp(fp_pivot, e)
	rig.rotation = Vector3(cam_pitch - _sway.x * 0.5 * e, cam_yaw, _sway.y * 0.6 * e)
	arm.spring_length = lerpf(tp_distance, 0.0, e)
	arm.position = Vector3(lerpf(0.35, 0.0, e), 0.0, 0.0)
	if _head_hider:
		_head_hider.hide_head = cam_blend > 0.5
	var fov := lerpf(tp_fov, fp_fov, e)
	if sprinting or mode == Mode.SLIDE:
		fov += 6.0
	cam.fov = lerpf(cam.fov, fov, 1.0 - exp(-6.0 * delta))
	if _post == null:
		_post = get_tree().get_first_node_in_group("pos_processamento") as CanvasItem
	if _post:
		(_post.material as ShaderMaterial).set_shader_parameter("bodycam", e)
	# tremida (impactos e quedas)
	_shake = maxf(_shake - delta * 1.5, 0.0)
	var s := _shake * _shake
	cam.h_offset = (randf() - 0.5) * s * 0.6
	cam.v_offset = (randf() - 0.5) * s * 0.6


# ------------------------------------------------------------------ animação

func _setup_animation() -> void:
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	_head_bone = _skel.find_bone("head")
	_chest_bone = _skel.find_bone("spine_03")
	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	for n in LOOPS:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	# no pulo o quadril não sobe além do normal (quem sobe é o corpo físico)
	for n in ["jump_start", "jump_air"]:
		var an := ap.get_animation(n)
		var t := an.find_track(NodePath(SKEL + "pelvis"), Animation.TYPE_POSITION_3D)
		if t >= 0:
			for k in an.track_get_key_count(t):
				var v: Vector3 = an.track_get_key_value(t, k)
				v.z = minf(v.z, 0.92)
				an.track_set_key_value(t, k, v)
	# andar/correr com o mesmo ciclo e a mesma fase (pé esquerdo à frente no início)
	var lib := AnimationLibrary.new()
	for n in LOCO:
		lib.add_animation(n, _normalize_cycle(ap, n, LOCO[n][0]))
	ap.add_animation_library("loco", lib)

	_head_hider = load("res://scripts/head_hider.gd").new()
	_skel.add_child(_head_hider)

	var bt := AnimationNodeBlendTree.new()
	# parado (normal ou postura de luta)
	bt.add_node("idle", _anim("idle"))
	bt.add_node("fight", _anim("fight_idle"))
	bt.add_node("stance", AnimationNodeBlend2.new())
	bt.connect_node("stance", 0, "idle")
	bt.connect_node("stance", 1, "fight")
	# andando: direção em relação ao corpo x "marcha" (1 andar, 2 trote, 3 correr)
	var move := AnimationNodeBlendSpace2D.new()
	move.min_space = Vector2(-1.5, -1.5)
	move.max_space = Vector2(1.5, 3.0)
	move.sync = true
	move.add_blend_point(_anim("loco/walk"), Vector2(0, 1))
	move.add_blend_point(_anim("loco/jog"), Vector2(0, 2))
	move.add_blend_point(_anim("loco/sprint"), Vector2(0, 3))
	move.add_blend_point(_anim("loco/walk_back"), Vector2(0, -1))
	move.add_blend_point(_anim("loco/strafe_left"), Vector2(-1, 0))
	move.add_blend_point(_anim("loco/strafe_right"), Vector2(1, 0))
	bt.add_node("move", move)
	bt.add_node("move_ts", AnimationNodeTimeScale.new())
	bt.connect_node("move_ts", 0, "move")
	bt.add_node("moving", AnimationNodeBlend2.new())
	bt.connect_node("moving", 0, "stance")
	bt.connect_node("moving", 1, "move_ts")
	# agachado
	var cmove := AnimationNodeBlendSpace1D.new()
	cmove.min_space = 0.0
	cmove.max_space = 1.0
	cmove.add_blend_point(_anim("crouch_idle"), 0.0)
	cmove.add_blend_point(_anim("crouch_walk"), 1.0)
	bt.add_node("crouch_bs", cmove)
	bt.add_node("crouch_ts", AnimationNodeTimeScale.new())
	bt.connect_node("crouch_ts", 0, "crouch_bs")
	bt.add_node("crouch", AnimationNodeBlend2.new())
	bt.connect_node("crouch", 0, "moving")
	bt.connect_node("crouch", 1, "crouch_ts")
	# no ar (pulo parado ou correndo)
	bt.add_node("air_anim", _anim("jump_air"))
	bt.add_node("run_jump", _anim("run_jump"))
	bt.add_node("air_pose", AnimationNodeBlend2.new())
	bt.connect_node("air_pose", 0, "air_anim")
	bt.connect_node("air_pose", 1, "run_jump")
	bt.add_node("air", AnimationNodeBlend2.new())
	bt.connect_node("air", 0, "crouch")
	bt.connect_node("air", 1, "air_pose")
	# impulso do pulo e aterrissagem
	bt.add_node("jump_anim", _anim("jump_start"))
	bt.add_node("jump_ts", AnimationNodeTimeScale.new())
	bt.connect_node("jump_ts", 0, "jump_anim")
	var jump := AnimationNodeOneShot.new()
	jump.fadein_time = 0.05
	jump.fadeout_time = 0.35
	bt.add_node("jump", jump)
	bt.connect_node("jump", 0, "air")
	bt.connect_node("jump", 1, "jump_ts")
	bt.add_node("land_anim", _anim("jump_land"))
	bt.add_node("land_ts", AnimationNodeTimeScale.new())
	bt.connect_node("land_ts", 0, "land_anim")
	var land := AnimationNodeOneShot.new()
	land.fadein_time = 0.04
	land.fadeout_time = 0.3
	bt.add_node("land", land)
	bt.connect_node("land", 0, "jump")
	bt.connect_node("land", 1, "land_ts")
	# parkour e ações (uma por vez, por cima de tudo)
	var pk_sel := AnimationNodeTransition.new()
	pk_sel.xfade_time = 0.12
	for i in PK.size():
		pk_sel.add_input(PK[i])
		bt.add_node("pk_" + PK[i], _anim(PK[i]))
	bt.add_node("pk_sel", pk_sel)
	for i in PK.size():
		bt.connect_node("pk_sel", i, "pk_" + PK[i])
	bt.add_node("pk_seek", AnimationNodeTimeSeek.new())
	bt.connect_node("pk_seek", 0, "pk_sel")
	bt.add_node("pk_ts", AnimationNodeTimeScale.new())
	bt.connect_node("pk_ts", 0, "pk_seek")
	bt.add_node("pk", AnimationNodeBlend2.new())
	bt.connect_node("pk", 0, "land")
	bt.connect_node("pk", 1, "pk_ts")
	# socos: o corpo inteiro (base firme, quadril girando junto com o golpe)
	var sel := AnimationNodeTransition.new()
	sel.xfade_time = 0.08
	for p in PUNCHES:
		sel.add_input(p.anim)
	bt.add_node("punch_sel", sel)
	for i in PUNCHES.size():
		bt.add_node(PUNCHES[i].anim, _anim(PUNCHES[i].anim))
		bt.connect_node("punch_sel", i, PUNCHES[i].anim)
	bt.add_node("punch_ts", AnimationNodeTimeScale.new())
	bt.connect_node("punch_ts", 0, "punch_sel")
	var punch := AnimationNodeOneShot.new()
	punch.fadein_time = 0.06
	punch.fadeout_time = 0.25
	bt.add_node("punch", punch)
	bt.connect_node("punch", 0, "pk")
	bt.connect_node("punch", 1, "punch_ts")
	bt.connect_node("output", 0, "punch")

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(ap)
	_tree.tree_root = bt
	_tree.active = true
	_tree.set("parameters/punch_ts/scale", PUNCH_TS)
	_tree.set("parameters/jump_ts/scale", 1.25)
	_tree.set("parameters/land_ts/scale", 1.4)
	_tree.set("parameters/pk_ts/scale", 1.0)


## Copia a animação de andar/correr para um ciclo de 1 s que começa com o pé esquerdo mais à
## frente (no sentido do movimento). Com todas assim e "sync" ligado, a mistura entre andar,
## trotar e correr nunca troca de pé.
func _normalize_cycle(ap: AnimationPlayer, name: String, dir: Vector3) -> Animation:
	var src := ap.get_animation(name)
	var L := src.length
	var bl := _skel.find_bone("ball_l")
	var br := _skel.find_bone("ball_r")
	var best := 0.0
	var best_lead := -INF
	ap.play(name)
	for i in 48:
		var t := L * i / 48.0
		ap.seek(t, true)
		_skel.force_update_all_bone_transforms()
		var lead := (_skel.get_bone_global_pose(bl).origin - _skel.get_bone_global_pose(br).origin).dot(dir)
		if lead > best_lead:
			best_lead = lead
			best = t
	ap.stop()
	var out := Animation.new()
	out.length = 1.0
	out.loop_mode = Animation.LOOP_LINEAR
	const N := 40
	for tr in src.get_track_count():
		var type := src.track_get_type(tr)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D:
			continue
		var nt := out.add_track(type)
		out.track_set_path(nt, src.track_get_path(tr))
		for i in N:
			var u := float(i) / N
			var t := fposmod(best + u * L, L)
			if type == Animation.TYPE_POSITION_3D:
				out.position_track_insert_key(nt, u, src.position_track_interpolate(tr, t))
			else:
				out.rotation_track_insert_key(nt, u, src.rotation_track_interpolate(tr, t))
	return out


func _anim(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a


## Toca uma animação de parkour/ação por cima de tudo (ts = velocidade).
func _pk_play(name: String, ts: float, fade: float) -> void:
	var cur: String = _tree.get("parameters/pk_sel/current_state")
	_tree.set("parameters/pk_sel/transition_request", name)
	if cur == name or _pk_amt < 0.05:
		_tree.set("parameters/pk_seek/seek_request", 0.0)
	_tree.set("parameters/pk_ts/scale", ts)
	_pk_target = 1.0
	_pk_fade = fade
	_pk_stop_at = -1.0
	if _punch_t >= 0.0 or _tree.get("parameters/punch/active"):
		_punch_t = -1.0
		_tree.set("parameters/punch/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


func _pk_switch(name: String) -> void:
	_tree.set("parameters/pk_sel/transition_request", name)


func _pk_stop(fade: float) -> void:
	_pk_target = 0.0
	_pk_fade = fade


## "Marcha" para a mistura: 1 andando, 2 trotando, 3 correndo.
func _gait(v: float) -> float:
	if v <= walk_speed:
		return 1.0
	if v <= jog_speed:
		return 1.0 + (v - walk_speed) / (jog_speed - walk_speed)
	return 2.0 + clampf((v - jog_speed) / (sprint_speed - jog_speed), 0.0, 1.0)


func _update_animation(delta: float, hv: Vector3) -> void:
	var spd := hv.length()
	var fwd := _facing()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var target := _blend_pos
	var hz := 1.0
	if spd > 0.05:
		var d := Vector2(hv.dot(right), hv.dot(fwd)) / spd
		var g := _gait(spd)
		target = d * g
		# cadência (ciclos por segundo) = velocidade / metros por ciclo da mistura atual
		var cyc_fwd: float = LOCO.walk[1]
		if g > 2.0:
			cyc_fwd = lerpf(LOCO.jog[1], LOCO.sprint[1], g - 2.0)
		elif g > 1.0:
			cyc_fwd = lerpf(LOCO.walk[1], LOCO.jog[1], g - 1.0)
		var cyc_other: float = LOCO.walk_back[1] if d.y < 0.0 else LOCO.strafe_left[1]
		var w := maxf(d.y, 0.0)
		hz = clampf(spd / lerpf(cyc_other, cyc_fwd, w * w), 0.35, 3.0)
	_blend_pos = _blend_pos.lerp(target, 1.0 - exp(-10.0 * delta))
	_moving_amt = lerpf(_moving_amt, clampf(spd / 0.7, 0.0, 1.0), 1.0 - exp(-12.0 * delta))
	var k := 1.0 - exp(-8.0 * delta)
	crouch_amt = lerpf(crouch_amt, 1.0 if crouching else 0.0, k)
	var in_air := mode == Mode.NORMAL and not is_on_floor() and _air_time > 0.1
	air_amt = lerpf(air_amt, 1.0 if in_air else 0.0, 1.0 - exp(-12.0 * delta))
	if _punch_t < 0.0 and mode != Mode.ACTION:
		combat = maxf(combat - delta / 3.0, 0.0)
	_pk_amt = move_toward(_pk_amt, _pk_target, delta / maxf(_pk_fade, 0.01))

	_tree.set("parameters/move/blend_position", _blend_pos)
	_tree.set("parameters/move_ts/scale", hz)
	_tree.set("parameters/moving/blend_amount", _moving_amt)
	_tree.set("parameters/stance/blend_amount", combat)
	_tree.set("parameters/crouch_bs/blend_position", clampf(spd / crouch_speed, 0.0, 1.0))
	_tree.set("parameters/crouch_ts/scale", clampf(spd / ANIM_CROUCH, 0.7, 1.8) if spd > 0.2 else 1.0)
	_tree.set("parameters/crouch/blend_amount", crouch_amt)
	_tree.set("parameters/air_pose/blend_amount", _air_run)
	_tree.set("parameters/air/blend_amount", air_amt)
	_tree.set("parameters/pk/blend_amount", smoothstep(0.0, 1.0, _pk_amt))
	# aterrissagem: queda pequena só "dobra" os joelhos; queda alta agacha fundo
	if _land_t >= 0.0:
		_land_t += delta
		if _land_t >= _land_cut:
			_land_t = -1.0
			_tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## Texto de estado para o HUD.
func state_text() -> String:
	match mode:
		Mode.MANTLE:
			return "Saltando obstáculo" if _m_vault else "Subindo"
		Mode.HANG:
			return "Pendurado"
		Mode.SLIDE:
			return "Deslizando"
		Mode.ROLL:
			return "Rolando"
		Mode.ACTION:
			return "Chute" if _act == "kick" else "Aterrissagem pesada"
	var s := "No ar" if not is_on_floor() else ("Agachado" if crouching else ("Correndo" if sprinting else "Em pé"))
	if _punch_t >= 0.0:
		s += " · " + ["Jab", "Direto", "Gancho"][_punch_idx]
	return s
