extends CharacterBody3D
## Personagem jogável (manequim da Universal Animation Library).
## - Movimento com peso: acelera, freia, curva mais aberta quanto mais rápido, ladeiras.
## - Andar / trotar / correr pelo analógico, agachar (com teste de teto), pular (tempo de
##   coiote, memória do botão, altura variável), rolar (correndo + agachar ou queda alta).
## - Nadar na água funda; na água rasa anda mais devagar.
## - Empurrar caixas pesadas (animação de empurrar), socos em combo (jab e direto) que
##   empurram objetos com física, peso do corpo sobre o que estiver embaixo.
## - USAR: pegar suprimentos, sentar no banco, apertar o botão do portão.
## - Câmeras em 3ª pessoa (por cima do ombro) e 1ª pessoa (nos olhos, corpo visível) com
##   impulsos dos passos, queda e pulo, respiração quando cansado, leve inclinação ao andar de
##   lado; mergulho com visão e som abafados debaixo d'água.
## - Sons: passos no ritmo dos pés da animação (grama, concreto ou água), respiração ofegante
##   depois de correr/nadar, roupa, golpes e água.
## - Animações misturadas por uma AnimationTree montada aqui e, por cima, camadas procedurais
##   (procedural_body.gd): pés no chão, cabeça/tronco olhando para a câmera, inclinação.

enum Mode { NORMAL, ACTION, SIT, SWIM }

# --- movimento (m/s) ---
@export var walk_speed := 1.4
@export var jog_speed := 3.4
@export var sprint_speed := 5.6
@export var crouch_speed := 1.2
@export var swim_speed := 1.4
@export var swim_fast_speed := 2.3
@export var push_speed := 1.0
@export var accel_ground := 14.0
@export var decel_ground := 18.0
@export var accel_air := 3.0
@export var jump_velocity := 4.8
## gravidade subindo com o botão de pulo segurado / caindo ou sem segurar
@export var gravity_up := 9.8
@export var gravity_down := 17.0
@export var coyote_time := 0.12
@export var jump_buffer := 0.15
## força máxima (N) para empurrar objetos com física
@export var push_force := 480.0
## massa do personagem (kg): o peso é aplicado no que está sob os pés
@export var body_mass := 75.0

# --- câmera ---
@export var mouse_sensitivity := 0.0025
@export var touch_sensitivity := 0.0055
@export var pad_sensitivity := 3.0
@export var tp_distance := 2.6
@export var tp_fov := 65.0
@export var fp_fov := 78.0

const STAND_H := 1.8
const CROUCH_H := 1.15
const RADIUS := 0.3
## andar/trotar/correr: metros que o corpo anda num ciclo completo (2 passos) da animação
const LOCO := {"Walk": 1.8, "Jog_Fwd": 3.0, "Sprint": 3.7}
const CROUCH_CYCLE := 2.0
const SWIM_CYCLE := 1.9
## objetos a partir desta massa (kg) são "pesados": o personagem empurra com as duas mãos
const HEAVY := 25.0
## socos: animação, impacto e quando pode emendar (tempo da animação, s), força (N·s)
const PUNCH_TS := 1.35
const PUNCHES := [
	{"anim": "Punch_Jab", "hit": 0.24, "next": 0.4, "end": 0.8, "force": 12.0, "reach": 0.72, "height": 1.4},
	{"anim": "Punch_Cross", "hit": 0.3, "next": 0.5, "end": 0.95, "force": 18.0, "reach": 0.75, "height": 1.4},
]
## ações que prendem o corpo enquanto tocam (uma por vez)
const ACTIONS := ["Roll", "Jump_Land", "PickUp_Table", "Interact", "Sitting_Enter", "Sitting_Idle", "Sitting_Exit"]

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
var cam_blend := 0.0
var crouching := false
var sprinting := false
var pushing := false
var model_yaw := 0.0
## suprimentos coletados (HUD)
var supplies := 0
## cansaço (0 a 1): sobe correndo/nadando, desce parado. Só muda a respiração (som e câmera).
var fatigue := 0.0
var diving := false
## passos dados (som/câmera) — usado pelos testes
var steps := 0

var _tree: AnimationTree
var _skel: Skeleton3D
var _body: Node # procedural_body.gd
var _head_bone := -1
var _capsule: CapsuleShape3D
var _hit_shape := SphereShape3D.new()
var _spawn: Transform3D
# pulo e queda
var _coyote := 0.0
var _buffer := 0.0
var _air_time := 0.0
var _jump_held := false
var _land_t := -1.0
var _land_cut := 0.0
var _land_slow := 0.0
# animação
var _blend := 0.0 # marcha suavizada (0 parado, 1 andar, 2 trotar, 3 correr)
var _moving := 0.0
var _crouch_amt := 0.0
var _air_amt := 0.0
var _swim_amt := 0.0
var _push_amt := 0.0
var _act_amt := 0.0
var _act_target := 0.0
var _act_fade := 0.15
var _backward := false
# ações
var _act := ""
var _act_t := 0.0
var _act_dur := 0.0
var _act_fired := false
var _act_target_node: Node
var _roll_dir := Vector3.ZERO
var _roll_speed := 0.0
var _sit_xform: Transform3D
var _push_hold := 0.0
var _act_goto := Vector3.INF # aproxima o corpo do objeto no começo da ação
# soco
var _punch_t := -1.0
var _punch_idx := 0
var _punch_hit := false
var _punch_queue := 0.0
var _punch_last := -10.0
# água
var _water: Node3D
var _water_y := 0.0
# câmera
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _pivot_y := 0.0
var _head_off := Vector3(0, 1.55, 0)
var _eye_y := 0.0
var _shake := 0.0
var _mouse_look := Vector2.ZERO
var _last_yaw := 0.0
var _last_speed := 0.0
var _time := 0.0
var _hitstop := false
var _step_dist := 0.0
var _use_target: Node
var _sfx := {}
var _spark: CPUParticles3D
var _splash: CPUParticles3D
# suavização e câmera imersiva
var _yaw_vel := 0.0
var _phase := 0.0
var _hz := 1.0
var _floor_hard := false
var _bob := Vector2.ZERO
var _bob_vel := Vector2.ZERO
var _roll := 0.0
var _breath_t := 0.0
var _breath_in := true
var _breath_clock := 0.0
var _look_pending := Vector2.ZERO
var _under := 0.0
var _bubble_t := 0.0
var _post: CanvasItem


func _ready() -> void:
	Inputs.setup()
	_spawn = global_transform
	cam_yaw = rotation.y
	model_yaw = cam_yaw + PI
	rotation = Vector3.ZERO
	_capsule = col.shape as CapsuleShape3D
	_hit_shape.radius = 0.35
	_prev_pos = global_position
	_cur_pos = global_position
	_pivot_y = global_position.y
	_eye_y = global_position.y + 1.6
	arm.add_excluded_object(get_rid())
	_setup_animation()
	_setup_sounds()
	_setup_particles()


# ================================================================== física / movimento

func _physics_process(delta: float) -> void:
	_prev_pos = global_position
	_time += delta
	if Input.is_action_just_pressed("reset") or global_position.y < -25.0:
		respawn()
		return
	match mode:
		Mode.NORMAL:
			_move_normal(delta)
		Mode.ACTION:
			_move_action(delta)
		Mode.SIT:
			_move_sit()
		Mode.SWIM:
			_move_swim(delta)
	_footsteps(delta)
	_update_use_target()
	var gain := 0.0
	if mode == Mode.NORMAL and sprinting and is_on_floor():
		gain = 0.1
	elif mode == Mode.SWIM:
		gain = 0.06 if sprinting else 0.03
	fatigue = clampf(fatigue + (gain if gain > 0.0 else -0.06) * delta, 0.0, 1.0)
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
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var depth := _water_depth()

	if Input.is_action_just_pressed("crouch"):
		if was_on_floor and hv.length() > 4.0 and not crouching:
			_start_roll(hv.length())
			return
		elif crouching:
			_try_stand()
		else:
			_set_crouch(true)
	if Input.is_action_just_pressed("use") and _use_target and was_on_floor and _punch_t < 0.0:
		_use_target.interact(self)
		if mode != Mode.NORMAL:
			return

	# velocidade desejada
	sprinting = Input.is_action_pressed("sprint") and mag > 0.5 and not crouching and _punch_t < 0.0 and depth < 0.6
	var target_speed: float
	if crouching:
		target_speed = crouch_speed * mag
	elif sprinting:
		target_speed = sprint_speed
	elif mag < 0.6:
		target_speed = walk_speed * mag / 0.6
	else:
		target_speed = lerpf(walk_speed, jog_speed, (mag - 0.6) / 0.4)
	if first_person and _is_backward(dir):
		target_speed = minf(target_speed, walk_speed * 1.2)
	if was_on_floor:
		# ladeira: subindo cansa, descendo embala um pouco
		var n := get_floor_normal()
		target_speed *= clampf(1.0 + Vector3(n.x, 0.0, n.z).dot(dir) * 1.1, 0.55, 1.15)
	if depth > 0.3:
		target_speed *= clampf(1.0 - (depth - 0.3) * 0.5, 0.45, 1.0) # água: arrasta as pernas
	if pushing:
		target_speed = minf(target_speed, push_speed)
	if _punch_t >= 0.0:
		target_speed *= 0.2
	if _land_slow > 0.0:
		target_speed *= 0.45
		_land_slow -= delta

	var target := dir * target_speed
	if was_on_floor:
		var cur := hv.length()
		var rate := accel_ground if target.length() > cur else decel_ground
		if cur > 1.5 and target.length() > 0.5 and not first_person:
			# inércia: quanto mais rápido, mais aberta a curva; meia-volta correndo freia antes
			var ang := hv.signed_angle_to(target, Vector3.UP)
			if absf(ang) > 2.4 and cur > 4.0:
				hv = hv.move_toward(Vector3.ZERO, decel_ground * 1.2 * delta)
			else:
				var k := clampf((cur - walk_speed) / (sprint_speed - walk_speed), 0.0, 1.0)
				var max_turn := lerpf(14.0, 4.0, k) * delta
				hv = hv.normalized().rotated(Vector3.UP, clampf(ang, -max_turn, max_turn)) * move_toward(cur, target.length(), rate * delta)
		else:
			hv = hv.move_toward(target, rate * delta)
	else:
		hv = hv.move_toward(target, accel_air * delta)
	if _punch_t >= 0.0 and _punch_t < 0.12 and was_on_floor:
		hv += _facing() * 12.0 * delta * (1.0 - _punch_t / 0.12)
	velocity.x = hv.x
	velocity.z = hv.z

	# pulo: coiote (pular logo depois de sair da borda) e memória (apertou um pouco antes)
	_coyote = coyote_time if was_on_floor else _coyote - delta
	_buffer = jump_buffer if Input.is_action_just_pressed("jump") else _buffer - delta
	if _buffer > 0.0 and _coyote > 0.0 and _punch_t < 0.0 and not pushing:
		if not crouching or _try_stand():
			velocity.y = jump_velocity * (0.8 if depth > 0.6 else 1.0)
			_coyote = 0.0
			_buffer = 0.0
			_jump_held = true
			_play("cloth", -6.0)
			_bob_vel.y += 0.35
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
	if _water_depth() > 1.3 and mode == Mode.NORMAL:
		_start_swim()
		return
	_update_punch(delta)


func _facing() -> Vector3:
	return Vector3(sin(model_yaw), 0.0, cos(model_yaw))


## Em 1ª pessoa: andando para trás (as pernas não viram de costas para a câmera).
func _is_backward(dir: Vector3) -> bool:
	return dir.length() > 0.1 and dir.dot(Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))) < -0.45


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


func _push_bodies(delta: float, wanted: Vector3) -> void:
	var weighed := false
	var heavy := false
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
		if body.mass >= HEAVY and wanted.length() > 0.3 and wanted.normalized().dot(n) > 0.6:
			heavy = true
		# leva o objeto até a velocidade do personagem, sem passar da força de um empurrão
		var dv := wanted.dot(n) - body.linear_velocity.dot(n)
		if dv <= 0.0:
			continue
		var j := minf(body.mass * dv * 0.6, push_force * delta)
		body.apply_impulse(n * j, c.get_position() - body.global_position)
	# segura o estado um instante (o contato com a caixa oscila entre quadros)
	_push_hold = 0.25 if (heavy and is_on_floor() and not crouching) else _push_hold - delta
	pushing = _push_hold > 0.0 and wanted.length() > 0.3


func respawn() -> void:
	mode = Mode.NORMAL
	_act_target = 0.0
	_act_amt = 0.0
	global_transform = Transform3D(Basis(), _spawn.origin)
	velocity = Vector3.ZERO
	_prev_pos = global_position
	_cur_pos = global_position
	_pivot_y = global_position.y
	_set_crouch(false)


# ================================================================== ações

## Toca uma ação que prende o corpo (rolar, aterrissagem pesada, pegar, interagir, sentar).
func _start_action(clip: String, dur: float, ts := 1.0, fade := 0.12) -> void:
	mode = Mode.ACTION
	_act = clip
	_act_t = 0.0
	_act_dur = dur
	_act_fired = false
	_play_action(clip, ts, fade)


func _play_action(clip: String, ts: float, fade: float) -> void:
	_tree.set("parameters/act_sel/transition_request", clip)
	_tree.set("parameters/act_seek/seek_request", 0.0)
	_tree.set("parameters/act_ts/scale", ts)
	_act_target = 1.0
	_act_fade = fade
	if _punch_t >= 0.0:
		_punch_t = -1.0
		_tree.set("parameters/punch/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


func _end_action(fade := 0.25) -> void:
	mode = Mode.NORMAL
	_act_goto = Vector3.INF
	_act = ""
	_act_target = 0.0
	_act_fade = fade


func _move_action(delta: float) -> void:
	_act_t += delta
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if _act == "Roll":
		_roll_speed = move_toward(_roll_speed, 2.0, 2.5 * delta)
		hv = _roll_dir * _roll_speed
	else:
		hv = hv.move_toward(Vector3.ZERO, decel_ground * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = -0.5 if is_on_floor() else maxf(velocity.y - gravity_down * delta, -40.0)
	if _act_goto != Vector3.INF and _act_t < 0.3:
		# um passo curto até a distância de alcance da mão
		global_position = global_position.lerp(_act_goto, minf(1.0, delta * 12.0))
		velocity = Vector3.ZERO
	else:
		move_and_slide()
	# o instante em que a mão alcança o objeto
	if not _act_fired:
		if _act == "PickUp_Table" and _act_t >= 0.32:
			_act_fired = true
			if is_instance_valid(_act_target_node):
				_act_target_node.queue_free()
				supplies += 1
				_play("pickup", -2.0)
		elif _act == "Interact" and _act_t >= 0.55:
			_act_fired = true
			if is_instance_valid(_act_target_node):
				_act_target_node.activate()
				_play("click", -4.0)
	if _act_t >= _act_dur:
		if _act == "Roll":
			_set_crouch(not _fits(STAND_H))
		elif _act == "Sitting_Enter":
			mode = Mode.SIT
			_act = "Sitting_Idle"
			_play_action("Sitting_Idle", 1.0, 0.2)
			return
		_end_action()


func _start_roll(speed: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	_roll_dir = hv.normalized() if hv.length() > 0.5 else _facing()
	_roll_speed = clampf(speed, 3.0, 5.2)
	model_yaw = atan2(_roll_dir.x, _roll_dir.z)
	_yaw_vel = 0.0
	_set_height(CROUCH_H)
	crouching = false
	_start_action("Roll", 1.0, 1.4, 0.06)
	_play("land", -8.0)
	_play("cloth", -4.0)


## Chamado por uma caixa de suprimentos (USAR).
func pickup(item: Node3D) -> void:
	_act_target_node = item
	_face(item.global_position)
	_act_goto = _reach_point(item.global_position, 0.5)
	_start_action("PickUp_Table", 0.62, 1.3)


## Chamado pelo painel do portão (USAR).
func press(button: Node3D) -> void:
	_act_target_node = button
	_face(button.global_position)
	_act_goto = _reach_point(button.global_position, 0.55)
	_start_action("Interact", 1.15, 1.6)


## Chamado pelo banco (USAR): vai até o assento, de costas para ele, e senta.
func sit(seat: Transform3D) -> void:
	_sit_xform = seat
	var fwd := -seat.basis.z
	model_yaw = atan2(fwd.x, fwd.z)
	_yaw_vel = 0.0
	global_position = seat.origin + fwd * 0.3 + Vector3.DOWN * seat.origin.y + Vector3.UP * global_position.y
	velocity = Vector3.ZERO
	_start_action("Sitting_Enter", 1.25, 1.0, 0.2)


func _move_sit() -> void:
	velocity = Vector3.ZERO
	var r := _read_move()
	if Input.is_action_just_pressed("use") or Input.is_action_just_pressed("jump") or r[1] > 0.5:
		_start_action("Sitting_Exit", 0.95, 1.0, 0.15)


## Ponto no chão a `dist` metros do objeto, do lado em que o personagem está.
func _reach_point(p: Vector3, dist: float) -> Vector3:
	var d := global_position - p
	d.y = 0.0
	if d.length() < 0.01:
		d = -_facing()
	var g := p + d.normalized() * dist
	g.y = global_position.y
	return g


func _face(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.05:
		model_yaw = atan2(d.x, d.z)
		_yaw_vel = 0.0


## Procura o objeto de USAR mais perto, à frente do personagem.
func _update_use_target() -> void:
	_use_target = null
	var label := ""
	if mode == Mode.NORMAL and is_on_floor():
		var best := 1.7
		var fwd := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw)) if first_person else _facing()
		for n in get_tree().get_nodes_in_group("usavel"):
			var p: Vector3 = n.global_position - global_position
			p.y = 0.0
			var d := p.length()
			if d < best and (d < 0.7 or p.normalized().dot(fwd) > 0.2):
				best = d
				_use_target = n
		if _use_target:
			label = _use_target.use_label()
	elif mode == Mode.SIT:
		label = "LEVANTAR"
	Inputs.use_label = label
	Inputs.jump_label = "NADAR" if mode == Mode.SWIM else "PULAR"
	Inputs.crouch_label = "MERGULHAR" if mode == Mode.SWIM else "ROLAR" if (mode == Mode.NORMAL and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 4.0 and not crouching) \
		else ("LEVANTAR" if crouching else "AGACHAR")


## O corpo (cápsula de altura h) cabe aqui?
func _fits(h: float) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS - 0.03
	shape.height = h
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * (h * 0.5 + 0.04))
	q.collision_mask = 1 | 2
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# ================================================================== água

func set_water(area: Node3D) -> void:
	_water = area
	if area:
		_water_y = area.surface_y
		if velocity.y < -2.5:
			area.splash(global_position, clampf(-velocity.y / 9.0, 0.3, 1.0))


## Quanto de água há acima dos pés (0 = fora da água).
func _water_depth() -> float:
	if _water == null:
		return 0.0
	return maxf(_water_y - global_position.y, 0.0)


func _start_swim() -> void:
	mode = Mode.SWIM
	_set_crouch(false)
	_set_height(CROUCH_H)
	if velocity.y > -2.5 and _water:
		_water.splash(global_position, 0.3)


func _move_swim(delta: float) -> void:
	var r := _read_move()
	var dir: Vector3 = r[0]
	var fast := Input.is_action_pressed("sprint") or Input.is_action_pressed("jump")
	var target: Vector3 = dir * (swim_fast_speed if fast else swim_speed) * r[1]
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, 2.5 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	# flutua com a cabeça para fora (a raiz do corpo fica na linha d'água); segurando AGACHAR,
	# mergulha (sem passar do fundo)
	diving = Input.is_action_pressed("crouch")
	var float_y := _water_y - (1.3 if diving else 0.05)
	if diving:
		var q0 := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position + Vector3.DOWN * 2.5, 1, [get_rid()])
		var fl := get_world_3d().direct_space_state.intersect_ray(q0)
		if not fl.is_empty():
			float_y = maxf(float_y, fl.position.y + 0.35)
	velocity.y = lerpf(velocity.y, (float_y - global_position.y) * 4.0, 1.0 - exp(-6.0 * delta))
	move_and_slide()
	_push_bodies(delta, target)
	sprinting = fast and r[1] > 0.3
	# sai nadando quando o fundo fica raso (dá pé: menos de 1,15 m de água) ou a água acaba
	var surf := Vector3(global_position.x, _water_y, global_position.z)
	var q := PhysicsRayQueryParameters3D.create(surf, surf + Vector3.DOWN * 1.15, 1, [get_rid()])
	var shallow := not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	if _water == null or (shallow and not diving):
		mode = Mode.NORMAL
		diving = false
		_set_height(STAND_H)
		velocity.y = 0.0


# ================================================================== soco

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
	elif _punch_queue > 0.0 and not pushing and _water_depth() < 0.8:
		_start_punch((_punch_idx + 1) % PUNCHES.size() if _time - _punch_last < 0.5 else 0)


func _start_punch(idx: int) -> void:
	_punch_idx = idx
	_punch_t = 0.0
	_punch_hit = false
	_punch_queue = 0.0
	var p: Dictionary = PUNCHES[idx]
	_tree.set("parameters/punch_sel/transition_request", p.anim)
	if not _tree.get("parameters/punch/active"):
		_tree.set("parameters/punch/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	model_yaw = cam_yaw + PI # soca para onde a câmera olha
	_yaw_vel = 0.0
	_play("swish", -6.0)


func _do_hit(p: Dictionary) -> void:
	var fwd := _facing()
	var h: float = lerpf(p.height, 0.8, _crouch_amt)
	var center: Vector3 = global_position + Vector3.UP * h + fwd * p.reach
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _hit_shape
	q.transform = Transform3D(Basis(), center)
	q.exclude = [get_rid()]
	q.collision_mask = 1 | 2
	var res := get_world_3d().direct_space_state.intersect_shape(q, 8)
	var soft := false
	var hard := false
	for r in res:
		var c: Object = r.collider
		if c is RigidBody3D:
			var b := c as RigidBody3D
			var point: Vector3 = center - fwd * 0.2
			b.apply_impulse(fwd * p.force + Vector3.UP * p.force * 0.12, point - b.global_position)
			if b.has_method("on_punch"):
				b.on_punch(p.force, point)
			soft = true
		else:
			hard = true
	if soft or hard:
		_spark.global_position = center - fwd * 0.25
		_spark.restart()
		_shake = 0.12 + p.force * 0.004
		_play("punch", 0.0 if soft else -3.0)
		if hard and not soft:
			_play("knock", -4.0)
		_do_hitstop(0.04 + p.force * 0.0012)


func _do_hitstop(t: float) -> void:
	if _hitstop:
		return
	_hitstop = true
	Engine.time_scale = 0.08
	await get_tree().create_timer(t, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop = false


# ================================================================== queda

func _on_land(fall_speed: float, hspeed: float) -> void:
	var k := clampf((fall_speed - 2.0) / 10.0, 0.0, 1.0)
	_play("land", lerpf(-16.0, 1.0, k))
	_play("step_hard" if _floor_hard else "step_grass", lerpf(-8.0, 0.0, k))
	_shake = maxf(_shake, 0.03 + 0.25 * k)
	# a queda chega na câmera: os joelhos dobram e a vista desce e volta
	_bob_vel.y -= lerpf(0.4, 1.6, k)
	if _water_depth() > 0.3:
		return
	if fall_speed > 10.5:
		# queda de mais de ~3 m: rola se estiver em movimento; parado, amortece agachando
		if hspeed > 2.0:
			_start_roll(hspeed)
		else:
			_start_action("Jump_Land", 0.75, 1.1, 0.04)
			_land_slow = 0.4
		return
	if fall_speed > 4.0 and (hspeed < 2.0 or fall_speed > 8.0):
		_tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_land_t = 0.0
		_land_cut = lerpf(0.1, 0.32, k) # queda pequena só dobra os joelhos
		_land_slow = lerpf(0.05, 0.3, k)


# ================================================================== sons e efeitos

## Nado e agachado: som por distância percorrida. (Em pé, os passos vêm da animação.)
func _footsteps(delta: float) -> void:
	var spd := Vector2(velocity.x, velocity.z).length()
	var fc := get_last_slide_collision()
	if is_on_floor() and fc != null:
		var c := fc.get_collider() as Node
		_floor_hard = c != null and c.is_in_group("piso_duro")
	if mode == Mode.SWIM:
		_step_dist += spd * delta
		if _step_dist > 1.3:
			_step_dist = 0.0
			_play("stroke", -8.0 if not diving else -14.0)
		return
	if mode != Mode.NORMAL or not is_on_floor() or spd < 0.3 or not crouching:
		return
	_step_dist += spd * delta
	if _step_dist >= 0.55:
		_step_dist = 0.0
		_step_sound(spd, 0.4)


## Em pé: o pé toca o chão em fases fixas do ciclo (as animações de andar/trotar/correr foram
## alinhadas para começar com o pé esquerdo à frente): esquerdo em ~0,03 e direito em ~0,53.
func _anim_footsteps(delta: float) -> void:
	if mode != Mode.NORMAL or not is_on_floor() or crouching or _moving < 0.15:
		return
	var prev := _phase
	_phase = fposmod(_phase + _hz * delta, 1.0)
	for contact in [0.03, 0.53]:
		var hit: bool = (prev < contact and _phase >= contact) if _hz >= 0.0 else (prev > contact and _phase <= contact)
		if hit or (_hz >= 0.0 and prev > _phase and contact < _phase):
			_step_sound(Vector2(velocity.x, velocity.z).length(), _moving)
			break


func _step_sound(spd: float, weight: float) -> void:
	steps += 1
	var k := clampf(spd / sprint_speed, 0.0, 1.0)
	var vol := lerpf(-16.0, -1.0, k) - (6.0 if crouching else 0.0) - (1.0 - weight) * 10.0
	if _water_depth() > 0.1:
		_play("step_water", vol + 2.0)
	else:
		_play("step_hard" if _floor_hard else "step_grass", vol)
	if spd > 4.5:
		_play("cloth", -18.0)
	# o passo chega na câmera (1ª pessoa): uma descida curta
	_bob_vel.y -= lerpf(0.05, 0.16, k)
	_bob_vel.x += (0.02 if _phase < 0.5 else -0.02) * (0.5 + k)


func _setup_sounds() -> void:
	for key in ["step_grass", "step_hard", "step_water", "land", "punch", "knock", "swish", "splash_small",
			"stroke", "bubbles", "click", "cloth", "pickup", "breath_in", "breath_out"]:
		var pl := AudioStreamPlayer3D.new()
		pl.stream = Sfx.get_stream(key)
		pl.max_polyphony = 3
		pl.unit_size = 6.0
		pl.bus = "Mundo"
		pl.position = Vector3.UP * (0.1 if key.begins_with("step") or key == "land" else 1.55)
		add_child(pl)
		_sfx[key] = pl


func _play(key: String, db := 0.0) -> void:
	var pl: AudioStreamPlayer3D = _sfx.get(key)
	if pl and Sfx.ready:
		pl.volume_db = db
		pl.pitch_scale = randf_range(0.94, 1.06)
		pl.play()


func _setup_particles() -> void:
	_spark = _make_particles(Color(1.0, 0.85, 0.5), 14, 0.22, 3.5, 0.025)
	_splash = _make_particles(Color(0.85, 0.93, 1.0, 0.8), 30, 0.8, 3.0, 0.05)
	_splash.direction = Vector3.UP
	_splash.spread = 35.0
	_splash.gravity = Vector3(0, -9.8, 0)


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


# ================================================================== câmera e corpo

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
	# posição suavizada entre dois passos da física (sem tremido em telas de 90/120 Hz)
	var pos := _prev_pos.lerp(_cur_pos, Engine.get_physics_interpolation_fraction())
	# empurrando, o corpo recua para as mãos encostarem no objeto
	visual.global_position = pos - _facing() * 0.24 * _push_amt

	# olhar: o movimento do dedo/mouse é aplicado em ~30 ms (sem "degraus" em telas rápidas)
	_look_pending += Inputs.take_look() * touch_sensitivity + _mouse_look * mouse_sensitivity
	_mouse_look = Vector2.ZERO
	var look := _look_pending * (1.0 - exp(-35.0 * delta))
	_look_pending -= look
	look += Input.get_vector("look_left", "look_right", "look_up", "look_down") * pad_sensitivity * delta
	cam_yaw = wrapf(cam_yaw - look.x, -PI, PI)
	cam_pitch = clampf(cam_pitch - look.y, -1.3 if first_person else -1.2, 1.25 if first_person else 0.75)
	if Input.is_action_just_pressed("camera"):
		first_person = not first_person
		Inputs.first_person = first_person
	cam_blend = move_toward(cam_blend, 1.0 if first_person else 0.0, delta * 4.0)
	var e := smoothstep(0.0, 1.0, cam_blend)

	# para onde o corpo olha
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var spd := hv.length()
	var view_yaw := cam_yaw + PI # o modelo olha para +Z
	_backward = false
	if mode == Mode.NORMAL or mode == Mode.SWIM:
		var target_yaw := model_yaw
		var turn := 10.0
		if _punch_t >= 0.0:
			target_yaw = view_yaw
			turn = 25.0
		elif first_person and spd > 0.3:
			# 1ª pessoa: as pernas seguem a direção do passo (até de lado); para trás, o corpo
			# fica de frente e a animação anda de ré. Tronco e cabeça continuam na câmera.
			var move_yaw := atan2(hv.x, hv.z)
			var rel := wrapf(move_yaw - view_yaw, -PI, PI)
			if absf(rel) > 1.95:
				_backward = mode == Mode.NORMAL
				target_yaw = move_yaw + PI if _backward else move_yaw
			else:
				target_yaw = move_yaw
			turn = 12.0
		elif first_person:
			# parado: a cabeça vira primeiro; passando de ~60° o corpo acompanha
			if absf(wrapf(view_yaw - model_yaw, -PI, PI)) > 1.05:
				target_yaw = view_yaw
				turn = 5.0
		elif spd > 0.3:
			target_yaw = atan2(hv.x, hv.z)
			turn = 12.0 if is_on_floor() or mode == Mode.SWIM else 4.0
		_turn_to(target_yaw, turn, delta)
	visual.rotation = Vector3(0.0, model_yaw, 0.0)

	_update_animation(delta, hv)
	_update_body(delta, hv, view_yaw)

	# 3ª pessoa: por cima do ombro direito
	_pivot_y = lerpf(_pivot_y, pos.y, 1.0 - exp(-14.0 * delta))
	if absf(_pivot_y - pos.y) > 1.0:
		_pivot_y = pos.y
	var pivot_h := lerpf(1.6, 1.05, _crouch_amt)
	if mode == Mode.SWIM:
		pivot_h = 0.4
	elif mode == Mode.SIT or _act == "Sitting_Exit":
		pivot_h = 1.2
	var tp_pivot := Vector3(pos.x, _pivot_y + pivot_h, pos.z)
	# 1ª pessoa: nos olhos; o balanço vem da cabeça animada, estabilizado pela metade
	var cam_fwd := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	if _head_bone >= 0:
		var head := _skel.global_transform * _skel.get_bone_global_pose(_head_bone).origin
		_head_off = _head_off.lerp(head - visual.global_position, 1.0 - exp(-25.0 * delta))
	var fp_pivot := visual.global_position + _head_off + Vector3.UP * 0.1 + cam_fwd * 0.12
	if mode == Mode.NORMAL and is_on_floor():
		_eye_y = lerpf(_eye_y, pos.y + lerpf(1.68, 1.1, _crouch_amt), 1.0 - exp(-10.0 * delta))
		fp_pivot.y = lerpf(fp_pivot.y, _eye_y, 0.5)
	else:
		_eye_y = fp_pivot.y
	if e > 0.01:
		# a câmera nunca entra na parede
		var from := global_position + Vector3.UP * clampf(_head_off.y, 0.3, _capsule.height - 0.1)
		var q := PhysicsRayQueryParameters3D.create(from, fp_pivot, 1 | 2, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			fp_pivot = from + (fp_pivot - from).normalized() * maxf(from.distance_to(hit.position) - 0.12, 0.0)
	rig.global_position = tp_pivot.lerp(fp_pivot, e)
	# 1ª pessoa: molas dos passos/queda, respiração e leve inclinação andando de lado
	var k_spring := 170.0
	var c_spring := 2.0 * sqrt(k_spring) * 0.55
	_bob_vel += (-k_spring * _bob - c_spring * _bob_vel) * minf(delta, 0.05)
	_bob += _bob_vel * minf(delta, 0.05)
	_breath_clock += delta * lerpf(0.35, 1.25, fatigue) * TAU
	var breath := (0.004 + 0.016 * fatigue) * e
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	_roll = lerpf(_roll, -hv.dot(right) * 0.008 - _body.lean.y * 0.2, 1.0 - exp(-5.0 * delta))
	rig.rotation = Vector3(cam_pitch + sin(_breath_clock) * breath, cam_yaw + sin(_breath_clock * 0.5) * breath * 0.4, _roll * e)
	_breathing(delta)
	_underwater(delta)
	arm.spring_length = lerpf(tp_distance, 0.0, e)
	arm.position = Vector3(lerpf(0.45, 0.0, e), 0.0, 0.0)
	_body.hide_head = cam_blend > 0.5
	var fov := lerpf(tp_fov, fp_fov, e) + (5.0 if sprinting and mode == Mode.NORMAL else 0.0)
	cam.fov = lerpf(cam.fov, fov, 1.0 - exp(-6.0 * delta))
	_shake = maxf(_shake - delta * 1.5, 0.0)
	var s := _shake * _shake
	cam.h_offset = (randf() - 0.5) * s * 0.6 + _bob.x * e
	cam.v_offset = (randf() - 0.5) * s * 0.6 + _bob.y * e


## Respiração ofegante depois de correr/nadar (inspira e expira alternando, mais rápido e
## mais alto quanto mais cansado).
func _breathing(delta: float) -> void:
	if fatigue < 0.12 or _under > 0.5:
		_breath_t = 0.0
		return
	_breath_t -= delta
	if _breath_t <= 0.0:
		var period := lerpf(1.7, 0.75, fatigue)
		_play("breath_in" if _breath_in else "breath_out", lerpf(-26.0, -7.0, fatigue))
		_breath_t = period * (0.42 if _breath_in else 0.58)
		_breath_in = not _breath_in


## Debaixo d'água: cor e som abafados, bolhas.
func _underwater(delta: float) -> void:
	var under := _water != null and cam.global_position.y < _water_y - 0.03
	_under = move_toward(_under, 1.0 if under else 0.0, delta * 5.0)
	Audio.underwater = under
	if _post == null:
		_post = get_tree().get_first_node_in_group("pos_processamento") as CanvasItem
	if _post:
		var m := _post.material as ShaderMaterial
		m.set_shader_parameter("underwater", _under)
		m.set_shader_parameter("fatigue", fatigue)
	if under:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble_t = randf_range(0.8, 2.0)
			_play("bubbles", -10.0)


## Giro do corpo com mola criticamente amortecida: acelera e desacelera a rotação (não estala).
func _turn_to(target: float, omega: float, delta: float) -> void:
	var d := wrapf(target - model_yaw, -PI, PI)
	var dt := minf(delta, 0.05)
	_yaw_vel += (omega * omega * d - 2.0 * omega * _yaw_vel) * dt
	model_yaw = wrapf(model_yaw + _yaw_vel * dt, -PI, PI)


## Camadas procedurais: pés no chão, inclinação, tronco/cabeça olhando para a câmera.
func _update_body(delta: float, hv: Vector3, view_yaw: float) -> void:
	_body.dt = delta
	var spd := hv.length()
	var yaw_rate := wrapf(model_yaw - _last_yaw, -PI, PI) / maxf(delta, 0.001)
	_last_yaw = model_yaw
	var accel := (spd - _last_speed) / maxf(delta, 0.001)
	_last_speed = spd
	var free := mode == Mode.NORMAL and is_on_floor() and _water_depth() < 0.5
	_body.ik_weight = move_toward(_body.ik_weight, 1.0 if (free and spd < 2.6 and not pushing) else 0.0, delta * 4.0)
	var lean := Vector2.ZERO
	if free:
		lean = Vector2(clampf(accel * 0.012, -0.08, 0.12) + clampf(spd / sprint_speed, 0.0, 1.0) * 0.05,
			clampf(-yaw_rate * spd * 0.03, -0.28, 0.28))
	_body.lean = _body.lean.lerp(lean, 1.0 - exp(-6.0 * delta))
	var lk := Vector2.ZERO
	if (mode == Mode.NORMAL or mode == Mode.SWIM or mode == Mode.SIT) and _punch_t < 0.0 and not pushing:
		var diff := wrapf(view_yaw - model_yaw, -PI, PI)
		var fade := 1.0 - smoothstep(1.6, 2.2, absf(diff))
		if first_person:
			fade = 1.0
		lk = Vector2(clampf(diff, -1.6, 1.6) * fade,
			clampf(cam_pitch + (0.0 if first_person else 0.2), -0.7, 0.6) * (1.0 if first_person else 0.6))
	_body.look = _body.look.lerp(lk, 1.0 - exp(-8.0 * delta))


# ================================================================== animação

func _setup_animation() -> void:
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	_head_bone = _skel.find_bone("Head")
	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# andar/trotar/correr com o mesmo ciclo e a mesma fase (pé esquerdo à frente no início):
	# misturando, os pés nunca "trocam" de lado
	var lib := AnimationLibrary.new()
	for n in LOCO:
		lib.add_animation(n, _normalize_cycle(ap, n))
	ap.add_animation_library("loco", lib)

	_body = load("res://scripts/procedural_body.gd").new()
	_body.exclude.append(get_rid())
	_skel.add_child(_body)

	var bt := AnimationNodeBlendTree.new()
	# em pé: parado ↔ andando (andar/trotar/correr no mesmo ritmo)
	var move := AnimationNodeBlendSpace1D.new()
	move.min_space = 1.0
	move.max_space = 3.0
	move.sync = true
	_add_point(move, "loco/Walk", 1.0)
	_add_point(move, "loco/Jog_Fwd", 2.0)
	_add_point(move, "loco/Sprint", 3.0)
	bt.add_node("move", move)
	_ts(bt, "move_ts", "move")
	bt.add_node("idle", _anim("Idle"))
	_blend2(bt, "moving", "idle", "move_ts")
	# agachado
	var cm := AnimationNodeBlendSpace1D.new()
	_add_point(cm, "Crouch_Idle", 0.0)
	_add_point(cm, "Crouch_Fwd", 1.0)
	bt.add_node("crouch_bs", cm)
	_ts(bt, "crouch_ts", "crouch_bs")
	_blend2(bt, "crouch", "moving", "crouch_ts")
	# empurrando
	bt.add_node("push_anim", _anim("Push"))
	_ts(bt, "push_ts", "push_anim")
	_blend2(bt, "push", "crouch", "push_ts")
	# nadando
	var sw := AnimationNodeBlendSpace1D.new()
	_add_point(sw, "Swim_Idle", 0.0)
	_add_point(sw, "Swim_Fwd", 1.0)
	bt.add_node("swim_bs", sw)
	_ts(bt, "swim_ts", "swim_bs")
	_blend2(bt, "swim", "push", "swim_ts")
	# no ar
	bt.add_node("air_anim", _anim("Jump"))
	_blend2(bt, "air", "swim", "air_anim")
	# aterrissagem leve
	bt.add_node("land_anim", _anim("Jump_Land"))
	_ts(bt, "land_ts", "land_anim")
	var land := AnimationNodeOneShot.new()
	land.fadein_time = 0.04
	land.fadeout_time = 0.3
	bt.add_node("land", land)
	bt.connect_node("land", 0, "air")
	bt.connect_node("land", 1, "land_ts")
	# ações (uma por vez, por cima de tudo)
	var act_sel := AnimationNodeTransition.new()
	act_sel.xfade_time = 0.22
	for i in ACTIONS.size():
		act_sel.add_input(ACTIONS[i])
		bt.add_node("a_" + ACTIONS[i], _anim(ACTIONS[i]))
	bt.add_node("act_sel", act_sel)
	for i in ACTIONS.size():
		bt.connect_node("act_sel", i, "a_" + ACTIONS[i])
	bt.add_node("act_seek", AnimationNodeTimeSeek.new())
	bt.connect_node("act_seek", 0, "act_sel")
	_ts(bt, "act_ts", "act_seek")
	_blend2(bt, "act", "land", "act_ts")
	# socos
	var sel := AnimationNodeTransition.new()
	sel.xfade_time = 0.08
	for p in PUNCHES:
		sel.add_input(p.anim)
		bt.add_node(p.anim, _anim(p.anim))
	bt.add_node("punch_sel", sel)
	for i in PUNCHES.size():
		bt.connect_node("punch_sel", i, PUNCHES[i].anim)
	_ts(bt, "punch_ts", "punch_sel")
	var punch := AnimationNodeOneShot.new()
	punch.fadein_time = 0.08
	punch.fadeout_time = 0.3
	bt.add_node("punch", punch)
	bt.connect_node("punch", 0, "act")
	bt.connect_node("punch", 1, "punch_ts")
	bt.connect_node("output", 0, "punch")

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(ap)
	_tree.tree_root = bt
	_tree.active = true
	_tree.set("parameters/punch_ts/scale", PUNCH_TS)
	_tree.set("parameters/land_ts/scale", 1.3)


## Ponto de mistura com nome (o Godot 4.6+ pede um nome; no 4.3 o método não aceita).
static var _named_points := -1


func _add_point(bs: AnimationRootNode, clip: String, pos: Variant) -> void:
	if _named_points < 0:
		_named_points = 0
		for m in ClassDB.class_get_method_list("AnimationNodeBlendSpace1D", true):
			if m.name == "add_blend_point" and m.args.size() >= 4:
				_named_points = 1
	if _named_points == 1:
		bs.call("add_blend_point", _anim(clip), pos, -1, StringName(clip.get_file()))
	else:
		bs.call("add_blend_point", _anim(clip), pos)


func _anim(clip: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = clip
	return a


func _ts(bt: AnimationNodeBlendTree, clip: String, input: String) -> void:
	bt.add_node(clip, AnimationNodeTimeScale.new())
	bt.connect_node(clip, 0, input)


func _blend2(bt: AnimationNodeBlendTree, clip: String, a: String, b: String) -> void:
	bt.add_node(clip, AnimationNodeBlend2.new())
	bt.connect_node(clip, 0, a)
	bt.connect_node(clip, 1, b)


## Copia a animação para um ciclo de 1 s que começa com o pé esquerdo mais à frente.
func _normalize_cycle(ap: AnimationPlayer, clip: String) -> Animation:
	var src := ap.get_animation(clip)
	var L := src.length
	var bl := _skel.find_bone("ball_l")
	var br := _skel.find_bone("ball_r")
	var best := 0.0
	var best_lead := -INF
	ap.play(clip)
	for i in 48:
		var t := L * i / 48.0
		ap.seek(t, true)
		_skel.force_update_all_bone_transforms()
		var lead := _skel.get_bone_global_pose(bl).origin.z - _skel.get_bone_global_pose(br).origin.z
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


## "Marcha": 1 andando, 2 trotando, 3 correndo.
func _gait(v: float) -> float:
	if v <= walk_speed:
		return 1.0
	if v <= jog_speed:
		return 1.0 + (v - walk_speed) / (jog_speed - walk_speed)
	return 2.0 + clampf((v - jog_speed) / (sprint_speed - jog_speed), 0.0, 1.0)


func _update_animation(delta: float, hv: Vector3) -> void:
	var spd := hv.length()
	var g := _gait(spd)
	_blend = lerpf(_blend, g, 1.0 - exp(-5.0 * delta))
	var cyc: float = LOCO.Walk
	if _blend > 2.0:
		cyc = lerpf(LOCO.Jog_Fwd, LOCO.Sprint, _blend - 2.0)
	elif _blend > 1.0:
		cyc = lerpf(LOCO.Walk, LOCO.Jog_Fwd, _blend - 1.0)
	var dirsign := -1.0 if _backward else 1.0
	var turning := first_person and spd < 0.3 and absf(wrapf(cam_yaw + PI - model_yaw, -PI, PI)) > 0.15 and mode == Mode.NORMAL \
		and absf(wrapf(model_yaw - _last_yaw, -PI, PI)) > 0.002
	var moving := clampf(spd / 0.7, 0.0, 1.0)
	var hz := clampf(spd / cyc, 0.35, 3.0)
	if turning:
		moving = maxf(moving, 0.45) # girando parado: passinhos no lugar
		hz = 0.9
	_moving = lerpf(_moving, moving, 1.0 - exp(-8.0 * delta))
	var k := 1.0 - exp(-6.0 * delta)
	_crouch_amt = lerpf(_crouch_amt, 1.0 if crouching else 0.0, k)
	var in_air := mode == Mode.NORMAL and not is_on_floor() and _air_time > 0.12
	_air_amt = lerpf(_air_amt, 1.0 if in_air else 0.0, 1.0 - exp(-10.0 * delta))
	_swim_amt = lerpf(_swim_amt, 1.0 if mode == Mode.SWIM else 0.0, k)
	_push_amt = lerpf(_push_amt, 1.0 if pushing else 0.0, k)
	_act_amt = move_toward(_act_amt, _act_target, delta / maxf(_act_fade, 0.01))

	_tree.set("parameters/move/blend_position", _blend)
	_tree.set("parameters/move_ts/scale", hz * dirsign)
	_hz = hz * dirsign
	_anim_footsteps(delta)
	_tree.set("parameters/moving/blend_amount", _moving)
	_tree.set("parameters/crouch_bs/blend_position", clampf(spd / crouch_speed, 0.0, 1.0))
	_tree.set("parameters/crouch_ts/scale", (clampf(spd * 2.0 / CROUCH_CYCLE, 0.6, 2.0) if spd > 0.2 else 1.0) * dirsign)
	_tree.set("parameters/crouch/blend_amount", _crouch_amt)
	_tree.set("parameters/push_ts/scale", clampf(spd / 0.6, 0.0, 1.6))
	_tree.set("parameters/push/blend_amount", _push_amt)
	_tree.set("parameters/swim_bs/blend_position", clampf(spd / swim_speed, 0.0, 1.0))
	_tree.set("parameters/swim_ts/scale", clampf(spd * 1.33 / SWIM_CYCLE, 0.6, 1.8) if spd > 0.2 else 1.0)
	_tree.set("parameters/swim/blend_amount", _swim_amt)
	_tree.set("parameters/air/blend_amount", _air_amt)
	_tree.set("parameters/act/blend_amount", smoothstep(0.0, 1.0, _act_amt))
	if _land_t >= 0.0:
		_land_t += delta
		if _land_t >= _land_cut:
			_land_t = -1.0
			_tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## Texto de estado para o HUD.
func state_text() -> String:
	match mode:
		Mode.SWIM:
			return "Nadando"
		Mode.SIT:
			return "Sentado"
		Mode.ACTION:
			return {"Roll": "Rolando", "Jump_Land": "Aterrissagem pesada", "PickUp_Table": "Pegando",
				"Interact": "Apertando botão", "Sitting_Enter": "Sentando", "Sitting_Exit": "Levantando"}.get(_act, _act)
	if not is_on_floor():
		return "No ar"
	var s := "Empurrando" if pushing else ("Agachado" if crouching else ("Correndo" if sprinting else "Em pé"))
	if _water_depth() > 0.3:
		s += " (na água)"
	if _punch_t >= 0.0:
		s += " · " + ["Jab", "Direto"][_punch_idx]
	return s
