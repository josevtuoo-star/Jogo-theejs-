extends CharacterBody3D
## Personagem jogável.
## - Movimento com aceleração/frenagem, corrida, agachar (com teste de teto para levantar),
##   pulo com "tempo de coiote", memória do botão e altura variável (segurar = pula mais).
## - Empurra objetos com física ao andar contra eles.
## - Soco em combo (jab, direto, gancho) que acerta e empurra objetos com física.
## - Câmera em 3ª pessoa (com braço que não atravessa paredes) e em 1ª pessoa (na cabeça do
##   personagem, vendo o próprio corpo).
## - Animações misturadas por uma AnimationTree montada aqui no código.

# --- velocidades (m/s) e física ---
@export var walk_speed := 1.5
@export var jog_speed := 3.6
@export var sprint_speed := 5.6
@export var crouch_speed := 1.2
## 1ª pessoa: velocidade máxima andando de lado ou para trás
@export var side_speed := 2.0
@export var accel_ground := 16.0
@export var decel_ground := 20.0
@export var accel_air := 4.0
@export var jump_velocity := 4.8
## gravidade subindo com o botão de pulo segurado / caindo ou sem segurar
@export var gravity_up := 9.8
@export var gravity_down := 17.0
@export var coyote_time := 0.12
@export var jump_buffer := 0.15
## força máxima (N) com que o personagem empurra caixas, bolas etc. ao andar contra elas
@export var push_force := 260.0

# --- câmera ---
@export var mouse_sensitivity := 0.0025
@export var touch_sensitivity := 0.0055
@export var pad_sensitivity := 3.0
@export var tp_distance := 3.0
@export var tp_fov := 70.0
@export var fp_fov := 80.0

const STAND_H := 1.8
const CROUCH_H := 1.15
const RADIUS := 0.3
const SKEL := "Scene/Armature_15_M/Skeleton3D:"
## velocidade natural de cada animação de andar (m/s); a animação acelera/desacelera
## para os pés não "patinarem"
const ANIM_WALK := 1.1
const ANIM_JOG := 2.9
const ANIM_SPRINT := 4.7
const ANIM_SIDE := 0.85
const ANIM_CROUCH := 0.75
## velocidade das animações de soco (as originais são lentas)
const PUNCH_TS := 1.5
## combo: animação, instante do impacto e quando já pode emendar o próximo (tempo da
## animação, em s), força (N·s), alcance e altura do golpe
const PUNCHES := [
	{"anim": "punch_jab", "hit": 0.25, "next": 0.45, "end": 1.0, "force": 12.0, "reach": 0.72, "height": 1.45, "side": 0.0},
	{"anim": "punch_cross", "hit": 0.33, "next": 0.55, "end": 1.15, "force": 18.0, "reach": 0.78, "height": 1.45, "side": 0.0},
	{"anim": "punch_hook", "hit": 0.27, "next": 0.45, "end": 0.45, "force": 26.0, "reach": 0.7, "height": 1.3, "side": -0.05},
]
const LOOPS := ["idle", "walk", "jog", "sprint", "walk_back", "strafe_left", "strafe_right",
	"crouch_idle", "crouch_walk", "jump_air", "fight_idle", "idle_hurt"]
const SFX := "res://assets/sfx/"

@onready var col: CollisionShape3D = $Collision
@onready var visual: Node3D = $Visual
@onready var model: Node3D = $Visual/Model
@onready var rig: Node3D = $CamRig
@onready var arm: SpringArm3D = $CamRig/SpringArm3D
@onready var cam: Camera3D = $CamRig/SpringArm3D/Camera3D

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

var _tree: AnimationTree
var _skel: Skeleton3D
var _head_bone := -1
var _head_hider: Node
var _capsule: CapsuleShape3D
var _hit_shape := SphereShape3D.new()
var _coyote := 0.0
var _buffer := 0.0
var _air_time := 0.0
var _jump_held := false
var _punch_t := -1.0 # tempo desde o início do soco atual (< 0 = não está socando)
var _punch_idx := 0
var _punch_hit := false
var _punch_queue := 0.0
var _punch_last := -10.0
var _land_t := -1.0
var _land_cut := 0.0
var _land_slow := 0.0
var _step_dist := 0.0
var _shake := 0.0
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _pivot_y := 0.0
var _head_off := Vector3(0, 1.6, 0)
var _blend_pos := Vector2.ZERO
var _spawn: Transform3D
var _mouse_look := Vector2.ZERO
var _time := 0.0
var _hitstop := false
var _sfx := {}
var _spark: CPUParticles3D
var _dust: CPUParticles3D

## posição do último golpe que acertou (para o HUD) e quantos acertaram
var hits := 0


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
	var was_on_floor := is_on_floor()

	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var mag := minf(inp.length(), 1.0)
	var dir := Vector3(inp.x, 0.0, inp.y).rotated(Vector3.UP, cam_yaw)
	if dir.length() > 0.001:
		dir = dir.normalized()

	if Input.is_action_just_pressed("crouch"):
		if crouching:
			_try_stand()
		else:
			_set_crouch(true)
	if Input.is_action_just_pressed("reset") or global_position.y < -20.0:
		respawn()
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
	if _punch_t >= 0.0:
		target_speed *= 0.2
	if _land_slow > 0.0:
		target_speed *= 0.45
		_land_slow -= delta

	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var target := dir * target_speed
	var rate: float
	if was_on_floor:
		rate = accel_ground if target.length() > hv.length() else decel_ground
	else:
		rate = accel_air
	hv = hv.move_toward(target, rate * delta)
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
	if _buffer > 0.0 and _coyote > 0.0:
		if not crouching or _try_stand():
			velocity.y = jump_velocity
			_coyote = 0.0
			_buffer = 0.0
			_jump_held = true
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
			_on_land(-vy_before)
		_air_time = 0.0
	else:
		_air_time += delta

	_update_punch(delta)
	_footsteps(delta)
	_cur_pos = global_position


func _facing() -> Vector3:
	return Vector3(sin(model_yaw), 0.0, cos(model_yaw))


func _set_crouch(on: bool) -> void:
	crouching = on
	var h := CROUCH_H if on else STAND_H
	_capsule.height = h
	col.position.y = h * 0.5
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
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider() as RigidBody3D
		if body == null:
			continue
		var n := -c.get_normal()
		n.y = 0.0
		if n.length() < 0.1:
			continue
		n = n.normalized()
		# leva o objeto até a velocidade do personagem, sem passar da força de um empurrão
		# (bola leve sai rolando; pilha pesada de caixas mal se mexe)
		var dv := wanted.dot(n) - body.linear_velocity.dot(n)
		if dv <= 0.0:
			continue
		var j := minf(body.mass * dv * 0.6, push_force * delta)
		body.apply_impulse(n * j, c.get_position() - body.global_position)


func respawn() -> void:
	global_transform = Transform3D(Basis(), _spawn.origin)
	velocity = Vector3.ZERO
	_prev_pos = global_position
	_cur_pos = global_position
	_pivot_y = global_position.y
	if crouching:
		_set_crouch(false)


# ------------------------------------------------------------------ soco

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
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var h := lerpf(p.height, 0.8, crouch_amt)
	var center: Vector3 = global_position + Vector3.UP * h + fwd * p.reach + right * p.side
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
		_do_hitstop(0.04 + p.force * 0.0015)


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


func _on_land(fall_speed: float) -> void:
	var k := clampf((fall_speed - 2.0) / 8.0, 0.0, 1.0)
	_play("step", lerpf(-6.0, 4.0, k))
	if fall_speed > 6.5:
		_play("land", lerpf(-8.0, 2.0, k))
	_shake = maxf(_shake, 0.05 + 0.25 * k)
	_dust.global_position = global_position + Vector3.UP * 0.05
	_dust.amount = int(lerpf(6, 24, k))
	_dust.restart()
	var moving := Vector2(velocity.x, velocity.z).length() > 2.0
	if fall_speed > 4.0 and (not moving or fall_speed > 9.0):
		_tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_land_t = 0.0
		_land_cut = lerpf(0.12, 0.45, k) # queda alta = agacha mais fundo
		_land_slow = lerpf(0.05, 0.4, k)


# ------------------------------------------------------------------ passos e sons

func _footsteps(delta: float) -> void:
	var spd := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or spd < 0.4:
		_step_dist = minf(_step_dist, 0.3)
		return
	_step_dist += spd * delta
	var stride := 0.55 if crouching else (0.72 if spd < 2.0 else (1.1 if spd < 4.5 else 1.45))
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
		pl.position = Vector3.UP * (0.1 if key in ["step", "land"] else 1.3)
		add_child(pl)
		_sfx[key] = pl


func _play(key: String, db := 0.0) -> void:
	var pl: AudioStreamPlayer3D = _sfx.get(key)
	if pl:
		pl.volume_db = db
		pl.play()


func _setup_particles() -> void:
	_spark = _make_particles(Color(1.0, 0.85, 0.5), 14, 0.22, 3.5, 0.025)
	_dust = _make_particles(Color(0.62, 0.6, 0.56, 0.7), 16, 0.6, 1.4, 0.06)
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
	visual.global_position = pos

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

	# câmera: 3ª pessoa acima do ombro; 1ª pessoa presa à cabeça animada
	_pivot_y = lerpf(_pivot_y, pos.y, 1.0 - exp(-14.0 * delta))
	if absf(_pivot_y - pos.y) > 1.0:
		_pivot_y = pos.y
	var tp_pivot := Vector3(pos.x, _pivot_y + lerpf(1.55, 1.05, crouch_amt), pos.z)
	if _head_bone >= 0:
		var head := _skel.global_transform * _skel.get_bone_global_pose(_head_bone).origin
		_head_off = _head_off.lerp(head - pos, 1.0 - exp(-18.0 * delta))
	var cam_fwd := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var fp_pivot := pos + _head_off + Vector3.UP * 0.08 + cam_fwd * (0.12 + 0.16 * clampf(-cam_pitch, 0.0, 1.2))
	rig.global_position = tp_pivot.lerp(fp_pivot, e)
	rig.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	arm.spring_length = lerpf(tp_distance, 0.0, e)
	arm.position = Vector3(lerpf(0.35, 0.0, e), 0.0, 0.0)
	if _head_hider:
		_head_hider.hide_head = cam_blend > 0.5
	var fov := lerpf(tp_fov, fp_fov, e)
	if sprinting:
		fov += 6.0
	cam.fov = lerpf(cam.fov, fov, 1.0 - exp(-6.0 * delta))
	# tremida (impactos e quedas)
	_shake = maxf(_shake - delta * 1.5, 0.0)
	var s := _shake * _shake
	cam.h_offset = (randf() - 0.5) * s * 0.6
	cam.v_offset = (randf() - 0.5) * s * 0.6


# ------------------------------------------------------------------ animação

func _setup_animation() -> void:
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	_head_bone = _skel.find_bone("head")
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

	_head_hider = load("res://scripts/head_hider.gd").new()
	_skel.add_child(_head_hider)

	var bt := AnimationNodeBlendTree.new()
	# andar em pé: posição = direção em relação ao corpo x "marcha" (1 andar, 2 trote, 3 correr)
	var move := AnimationNodeBlendSpace2D.new()
	move.min_space = Vector2(-1.5, -1.5)
	move.max_space = Vector2(1.5, 3.0)
	move.add_blend_point(_anim("idle"), Vector2(0, 0))
	move.add_blend_point(_anim("walk"), Vector2(0, 1))
	move.add_blend_point(_anim("jog"), Vector2(0, 2))
	move.add_blend_point(_anim("sprint"), Vector2(0, 3))
	move.add_blend_point(_anim("walk_back"), Vector2(0, -1))
	move.add_blend_point(_anim("strafe_left"), Vector2(-1, 0))
	move.add_blend_point(_anim("strafe_right"), Vector2(1, 0))
	bt.add_node("move", move)
	bt.add_node("move_ts", AnimationNodeTimeScale.new())
	bt.connect_node("move_ts", 0, "move")
	bt.add_node("fight", _anim("fight_idle"))
	bt.add_node("stance", AnimationNodeBlend2.new())
	bt.connect_node("stance", 0, "move_ts")
	bt.connect_node("stance", 1, "fight")
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
	bt.connect_node("crouch", 0, "stance")
	bt.connect_node("crouch", 1, "crouch_ts")
	# no ar
	bt.add_node("air_anim", _anim("jump_air"))
	bt.add_node("air", AnimationNodeBlend2.new())
	bt.connect_node("air", 0, "crouch")
	bt.connect_node("air", 1, "air_anim")
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
	bt.connect_node("punch", 0, "land")
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


func _anim(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a


## "Marcha" para a mistura: 0 parado, 1 andando, 2 trotando, 3 correndo.
func _gait(v: float) -> float:
	if v <= walk_speed:
		return v / walk_speed
	if v <= jog_speed:
		return 1.0 + (v - walk_speed) / (jog_speed - walk_speed)
	return 2.0 + clampf((v - jog_speed) / (sprint_speed - jog_speed), 0.0, 1.0)


func _update_animation(delta: float, hv: Vector3) -> void:
	var spd := hv.length()
	var fwd := _facing()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var target := Vector2.ZERO
	var ts := 1.0
	if spd > 0.05:
		var d := Vector2(hv.dot(right), hv.dot(fwd)) / spd
		var g := _gait(spd)
		target = d * g
		var nominal := ANIM_SIDE
		if d.y > 0.7:
			nominal = ANIM_WALK if g <= 1.0 else (lerpf(ANIM_WALK, ANIM_JOG, g - 1.0) if g <= 2.0 else lerpf(ANIM_JOG, ANIM_SPRINT, g - 2.0))
		ts = clampf(spd / nominal, 0.6, 1.8) if spd > 0.3 else 1.0
	_blend_pos = _blend_pos.lerp(target, 1.0 - exp(-10.0 * delta))
	var k := 1.0 - exp(-8.0 * delta)
	crouch_amt = lerpf(crouch_amt, 1.0 if crouching else 0.0, k)
	var in_air := not is_on_floor() and _air_time > 0.1
	air_amt = lerpf(air_amt, 1.0 if in_air else 0.0, 1.0 - exp(-12.0 * delta))
	if _punch_t < 0.0:
		combat = maxf(combat - delta / 3.0, 0.0)

	_tree.set("parameters/move/blend_position", _blend_pos)
	_tree.set("parameters/move_ts/scale", ts)
	_tree.set("parameters/stance/blend_amount", combat * clampf(1.0 - spd, 0.0, 1.0))
	_tree.set("parameters/crouch_bs/blend_position", clampf(spd / crouch_speed, 0.0, 1.0))
	_tree.set("parameters/crouch_ts/scale", clampf(spd / ANIM_CROUCH, 0.7, 1.8) if spd > 0.2 else 1.0)
	_tree.set("parameters/crouch/blend_amount", crouch_amt)
	_tree.set("parameters/air/blend_amount", air_amt)
	# aterrissagem: queda pequena só "dobra" os joelhos; queda alta agacha fundo
	if _land_t >= 0.0:
		_land_t += delta
		if _land_t >= _land_cut:
			_land_t = -1.0
			_tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## Texto de estado para o HUD.
func state_text() -> String:
	var s := "No ar" if not is_on_floor() else ("Agachado" if crouching else ("Correndo" if sprinting else "Em pé"))
	if _punch_t >= 0.0:
		s += " · " + ["Jab", "Direto", "Gancho"][_punch_idx]
	return s
