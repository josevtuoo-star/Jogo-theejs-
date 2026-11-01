class_name PlayerDeath
extends Node
## Morte (ragdoll) e renascimento do jogador.
##
## Ao morrer, o corpo vira ragdoll: os ossos físicos herdam a velocidade do
## personagem e o tronco recebe o impulso do golpe que matou, na direção de
## onde ele veio. A câmera passa a seguir a cabeça física (primeira pessoa) ou
## a orbitar o corpo (terceira pessoa). respawn() para a simulação, devolve a
## pose animada, vida, câmera e controles e leva o jogador ao ponto inicial.

signal died
signal respawned

@export var player: PlayerController
@export var health: HealthComponent
@export var camera_rig: PlayerCameraRig
@export var body: BodyAnimator
## Tempo mínimo antes de permitir renascer (s).
@export_range(0.0, 10.0, 0.1) var respawn_delay: float = 2.0
## Impulso no tronco por ponto de dano do golpe final (kg·m/s).
@export_range(0.0, 10.0, 0.05) var impulse_per_damage: float = 0.8
@export_range(0.0, 200.0, 1.0) var max_death_impulse: float = 80.0

var spawn_transform: Transform3D
var time_since_death: float = 0.0
var simulator: PhysicalBoneSimulator3D
var _last_damage: float = 0.0
var _last_direction: Vector3 = Vector3.ZERO
var _player_layer: int
var _player_mask: int


func _ready() -> void:
	spawn_transform = player.global_transform
	simulator = body.skeleton.get_node_or_null("PhysicalBoneSimulator3D")
	# O simulador é um modificador do esqueleto: ativo, ele sobrescreve a pose
	# animada com a dos ossos físicos. Só liga na morte.
	if simulator != null:
		simulator.active = false
	health.damaged.connect(func(amount: float, _kind: StringName, direction: Vector3) -> void:
		_last_damage = amount
		_last_direction = direction)
	health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if health.is_dead:
		time_since_death += delta


func can_respawn() -> bool:
	return health.is_dead and time_since_death >= respawn_delay


func is_ragdoll_active() -> bool:
	return simulator != null and simulator.is_simulating_physics()


## Osso físico da cabeça (seguido pela câmera).
func get_physical_bone(bone_name: String) -> PhysicalBone3D:
	if simulator == null:
		return null
	return simulator.get_node_or_null("Physical_" + bone_name) as PhysicalBone3D


func _on_died() -> void:
	time_since_death = 0.0
	# A cápsula deixa de bloquear: o corpo agora é o ragdoll.
	_player_layer = player.collision_layer
	_player_mask = player.collision_mask
	player.collision_layer = 0
	player.velocity = Vector3.ZERO
	if simulator != null:
		simulator.active = true
		simulator.physical_bones_start_simulation()
		var carried := player.get_real_velocity()
		for bone: PhysicalBone3D in simulator.get_children():
			bone.linear_velocity = carried
		var torso := get_physical_bone("spine_03")
		if torso != null:
			var direction := _last_direction if _last_direction != Vector3.ZERO else player.global_basis.z
			var strength := minf(_last_damage * impulse_per_damage, max_death_impulse)
			torso.apply_central_impulse(direction.normalized() * strength)
		camera_rig.follow(get_physical_bone("Head"))
	else:
		body.play(BodyAnimator.SLOT_DEATH, &"death", 1.0, 0.1)
	died.emit()


## Renasce no ponto inicial ou em `at` (transformação nos pés).
func respawn(at: Variant = null) -> void:
	if simulator != null:
		simulator.physical_bones_stop_simulation()
		simulator.active = false
	camera_rig.follow(null)
	var target: Transform3D = at if at is Transform3D else spawn_transform
	health.revive()
	player.collision_layer = _player_layer if _player_layer != 0 else 2
	player.teleport(target.origin)
	player.set_view_rotation(target.basis.get_euler().y, 0.0)
	if player.stamina != null:
		player.stamina.restore(player.stamina.max_stamina)
	camera_rig.snap()
	time_since_death = 0.0
	respawned.emit()
