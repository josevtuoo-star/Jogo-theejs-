class_name Zombie
extends CharacterBody3D
## Zumbi: o mesmo corpo do sobrevivente (esqueleto, ragdoll) com pele e roupa
## tingidas e as animações de zumbi (Quaternius UAL2, CC0) retargetadas.
##
## Comportamento simples e legível:
## - VAGA devagar quando não percebe ninguém;
## - percebe o jogador pela visão (até 22 m, à frente) ou pelo barulho (perto,
##   ou correndo) e PERSEGUE no passo arrastado;
## - perto, ATACA com o arranhão; o dano sai no quadro em que a mão passa à
##   frente (evento da animação), só se o jogador ainda estiver ao alcance;
## - ao apanhar: perde vida, recua pelo impulso do golpe e cambaleia
##   (animação de impacto), solta sangue; golpe forte derruba o passo;
## - morre como ragdoll, empurrado na direção do golpe final.
## Recebe golpes por receive_hit (MeleeCombat), como o boneco de treino.

signal died

enum State { WANDER, CHASE, ATTACK, STAGGER, DEAD }

const BODY_SCENE := "res://scenes/characters/survivor.tscn"

@export_range(1.0, 500.0, 1.0) var max_health: float = 90.0
@export_range(0.1, 5.0, 0.05) var walk_speed: float = 1.15
@export_range(1.0, 60.0, 0.5) var sight_range: float = 22.0
@export_range(0.5, 20.0, 0.5) var hearing_range: float = 7.0
@export_range(0.5, 3.0, 0.05) var attack_range: float = 1.35
@export_range(0.0, 100.0, 0.5) var attack_damage: float = 12.0
@export var target: Node3D
## Roupa (ZombieLook.OUTFITS); -1 = sorteada.
@export var variant: int = -1

var health: float
var state: State = State.WANDER
var hits_taken: int = 0
var last_damage: float = 0.0

var _body: Node3D
var _skeleton: Skeleton3D
var _animation: AnimationPlayer
var _simulator: PhysicalBoneSimulator3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _knockback := Vector3.ZERO
var _stagger_time := 0.0
var _attack_time := -1.0
var _attack_dealt := false
var _wander_heading := 0.0
var _wander_timer := 0.0
var _groan_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _voice: AudioStreamPlayer3D
var _voices: Dictionary = {}


func _ready() -> void:
	health = max_health
	# Camada 4 (zumbis, valor 8): colide com mundo, jogador, objetos e outros
	# zumbis; o golpe do jogador procura nela.
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8
	_rng.randomize()
	_wander_heading = _rng.randf() * TAU
	_groan_timer = _rng.randf_range(2.0, 7.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.75
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.875, 0.0)
	add_child(shape)
	_body = (load(BODY_SCENE) as PackedScene).instantiate()
	# Sem o animador do jogador (ele depende do controle): animação direta.
	_body.set_script(null)
	add_child(_body)
	# O corpo olha para -Z; o zumbi anda para +Z (a frente deste nó).
	_body.rotation.y = PI
	_skeleton = _body.find_child("Skeleton3D") as Skeleton3D
	_animation = _body.find_child("AnimationPlayer") as AnimationPlayer
	_simulator = _skeleton.get_node_or_null("PhysicalBoneSimulator3D")
	if _simulator != null:
		_simulator.active = false
	_dress()
	_animation.play(&"zombie_walk", 0.2)
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = &"Efeitos"
	_voice.unit_size = 5.0
	_voice.max_distance = 40.0
	_voice.position = Vector3(0.0, 1.6, 0.0)
	add_child(_voice)


## Quem ele era: roupa, pele em decomposição, sangue, altura, magreza,
## postura e o próprio passo (cada zumbi anda diferente).
func _dress() -> void:
	var outfit := ZombieLook.dress(_body, variant if variant >= 0 else _rng.randi(), _rng)
	var height := _rng.randf_range(0.93, 1.07)
	var thin: bool = outfit.get("magro", false)
	_body.scale = Vector3(height * (0.88 if thin else 1.0), height, height * (0.9 if thin else 1.0))
	walk_speed *= _rng.randf_range(0.8, 1.25)
	var posture := ZombiePosture.new()
	posture.name = "Postura"
	posture.hunch = _rng.randf_range(0.1, 0.45)
	posture.head_tilt = _rng.randf_range(0.1, 0.45) * (1.0 if _rng.randf() < 0.5 else -1.0)
	posture.limp_arm = _rng.randf_range(0.4, 0.9) if _rng.randf() < 0.4 else 0.0
	posture.arm_side = "_l" if _rng.randf() < 0.5 else "_r"
	_skeleton.add_child(posture)
	_posture = posture


var _posture: ZombiePosture


func is_dead() -> bool:
	return state == State.DEAD


# --- Comportamento --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = maxf(velocity.y, -0.5)
	var wish := Vector3.ZERO
	var to_target := Vector3.ZERO
	var distance := INF
	if target != null and is_instance_valid(target) and not _target_dead():
		to_target = target.global_position - global_position
		to_target.y = 0.0
		distance = to_target.length()
	match state:
		State.WANDER:
			_wander_timer -= delta
			if _wander_timer <= 0.0:
				_wander_heading += _rng.randf_range(-1.2, 1.2)
				_wander_timer = _rng.randf_range(3.0, 7.0)
			wish = Vector3(sin(_wander_heading), 0.0, cos(_wander_heading)) * 0.45
			if _perceives(to_target, distance):
				state = State.CHASE
				_say("voice/zumbi_geme", 0.0)
		State.CHASE:
			if distance > sight_range * 1.6:
				state = State.WANDER
			elif distance <= attack_range:
				_start_attack()
			else:
				wish = to_target / distance
		State.ATTACK:
			_attack_time += delta
			if not _attack_dealt and _attack_time >= _event_time(&"zombie_attack"):
				_attack_dealt = true
				_deal_damage()
			if _attack_time >= _animation.get_animation(&"zombie_attack").length * 0.85:
				state = State.CHASE
				_animation.play(&"zombie_walk", 0.25)
			if distance < INF:
				_face(to_target, delta * 4.0)
		State.STAGGER:
			_stagger_time -= delta
			if _stagger_time <= 0.0:
				state = State.CHASE
				_animation.play(&"zombie_walk", 0.3)
	# Andar: velocidade na direção desejada + empurrão do golpe (amortecido).
	var horizontal := wish * walk_speed
	if wish.length_squared() > 0.001:
		_face(wish, delta * 3.0)
	_knockback = _knockback.move_toward(Vector3.ZERO, 6.0 * delta)
	velocity.x = horizontal.x + _knockback.x
	velocity.z = horizontal.z + _knockback.z
	move_and_slide()
	# A passada acompanha a velocidade (pé não escorrega).
	if _animation.current_animation == &"zombie_walk":
		_animation.speed_scale = clampf(horizontal.length() / 0.97, 0.35, 1.6)
	else:
		_animation.speed_scale = 1.0
	_groan_timer -= delta
	if _groan_timer <= 0.0:
		_groan_timer = _rng.randf_range(4.0, 9.0)
		_say("voice/zumbi_geme", -4.0)


func _target_dead() -> bool:
	return target.has_method(&"is_dead") and bool(target.call(&"is_dead"))


func _perceives(to_target: Vector3, distance: float) -> bool:
	if distance > sight_range:
		return false
	if distance < hearing_range:
		return true
	var running := target is PlayerController and (target as PlayerController).velocity.length() > 4.0
	if running and distance < hearing_range * 2.2:
		return true
	# Visão: à frente (cone de 120°) e sem rocha no caminho.
	var forward := global_basis.z
	if forward.dot(to_target / distance) < 0.5:
		return false
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.6, target.global_position + Vector3.UP * 1.4, 1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _face(direction: Vector3, weight: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(weight, 0.0, 1.0))


func _start_attack() -> void:
	state = State.ATTACK
	_attack_time = 0.0
	_attack_dealt = false
	_animation.play(&"zombie_attack", 0.15)
	_say("voice/zumbi_ataque", 0.0)


func _deal_damage() -> void:
	if target == null or not is_instance_valid(target):
		return
	var offset := target.global_position - global_position
	offset.y = 0.0
	if offset.length() > attack_range + 0.45 or global_basis.z.dot(offset.normalized()) < 0.3:
		return
	var health_node := target.get_node_or_null("Health") as HealthComponent
	if health_node == null and target.get("health") is HealthComponent:
		health_node = target.get("health")
	if health_node != null:
		health_node.apply_damage(attack_damage, &"mordida", -offset.normalized())


func _event_time(clip: StringName) -> float:
	var events: Dictionary = _animation.get_animation(clip).get_meta(&"events", {})
	return events.get(&"hit", 0.6)


# --- Golpes recebidos ---------------------------------------------------------

func receive_hit(hit: Dictionary) -> bool:
	if state == State.DEAD:
		return false
	var damage: float = hit.get("damage", 0.0)
	var impulse: float = hit.get("impulse", 0.0)
	var direction: Vector3 = hit.get("direction", -global_basis.z)
	var point: Vector3 = hit.get("point", global_position + Vector3.UP * 1.4)
	health -= damage
	last_damage = damage
	hits_taken += 1
	ImpactEffects.burst(get_parent(), point, -direction, &"sangue", 12, 0.03, 2.5)
	ImpactEffects.sound(get_parent(), point, "combat/soco_corpo", 0.0)
	# Empurrão: impulso do golpe sobre ~70 kg (no plano).
	var push := Vector3(direction.x, 0.0, direction.z).normalized() * impulse / 70.0 * 11.0
	_knockback += push
	if health <= 0.0:
		_die(direction, impulse)
		return true
	# Cambaleia: golpe forte = recuo grande.
	state = State.STAGGER
	_stagger_time = 0.75 if impulse > 25.0 else 0.45
	_animation.play(&"hit_knockback" if impulse > 25.0 else &"hit_chest", 0.06)
	_say("voice/zumbi_geme", 2.0)
	# Quem bate é notado.
	if target == null:
		target = hit.get("attacker")
	return true


func _die(direction: Vector3, impulse: float) -> void:
	state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	_say("voice/zumbi_morte", 2.0)
	if _simulator != null:
		_animation.stop()
		if _posture != null:
			_posture.active = false
		_simulator.active = true
		_simulator.physical_bones_start_simulation()
		var carried := velocity + _knockback
		for bone in _simulator.get_children():
			if bone is PhysicalBone3D:
				(bone as PhysicalBone3D).linear_velocity = carried
				(bone as PhysicalBone3D).collision_mask = 1 | 4
		var torso := _simulator.get_node_or_null("Physical_spine_03") as PhysicalBone3D
		if torso != null:
			torso.apply_central_impulse(direction.normalized() * clampf(impulse * 1.6, 20.0, 90.0))
	else:
		_animation.play(&"death", 0.1)
	died.emit()
	# O corpo fica um tempo e some.
	get_tree().create_timer(40.0).timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free())


func _say(key: String, volume_db: float) -> void:
	if not _voices.has(key):
		_voices[key] = SoundSet.load_set(key)
	var sounds: SoundSet = _voices[key]
	if sounds == null or _voice == null:
		return
	_voice.stream = sounds.pick()
	_voice.volume_db = volume_db
	_voice.pitch_scale = _rng.randf_range(0.9, 1.05)
	_voice.play()
