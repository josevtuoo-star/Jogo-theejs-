class_name PlayerDeath
extends Node
## Morte e renascimento do jogador.
##
## Ao morrer, a câmera passa a seguir um corpo rígido do tamanho da cabeça,
## lançado com a velocidade que o personagem tinha: a visão cai, bate no chão
## e rola de forma física, enquanto os braços tocam a animação de morte.
## renascer() devolve vida, câmera e controles e leva o jogador ao ponto
## inicial (ou a outro ponto informado).

signal died
signal respawned

@export var player: PlayerController
@export var health: HealthComponent
@export var camera: Camera3D
## Tempo mínimo antes de permitir renascer (s).
@export_range(0.0, 10.0, 0.1) var respawn_delay: float = 2.0
@export_range(0.5, 20.0, 0.1) var head_mass: float = 4.5
@export_range(0.05, 0.3, 0.01) var head_radius: float = 0.11

var spawn_transform: Transform3D
var time_since_death: float = 0.0
var head_body: RigidBody3D = null
var _camera_offset: Transform3D
var _camera_local: Transform3D


func _ready() -> void:
	spawn_transform = player.global_transform
	_camera_local = camera.transform
	health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if health.is_dead:
		time_since_death += delta


func _process(_delta: float) -> void:
	if head_body != null:
		camera.global_transform = head_body.global_transform * _camera_offset


func can_respawn() -> bool:
	return health.is_dead and time_since_death >= respawn_delay


func _on_died() -> void:
	time_since_death = 0.0
	var start := camera.global_transform
	head_body = RigidBody3D.new()
	head_body.name = "DeathHead"
	head_body.mass = head_mass
	head_body.collision_layer = 0
	# Colide com o cenário e com objetos, nunca com a cápsula do próprio corpo.
	head_body.collision_mask = 1 | 4
	head_body.linear_damp = 0.4
	head_body.angular_damp = 2.5
	var material := PhysicsMaterial.new()
	material.friction = 1.0
	material.bounce = 0.1
	head_body.physics_material_override = material
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = head_radius
	shape.shape = sphere
	head_body.add_child(shape)
	player.get_parent().add_child(head_body)
	head_body.global_transform = Transform3D(Basis.IDENTITY, start.origin)
	# A cabeça cai para o lado de onde o corpo estava indo, ou para trás.
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var fall_direction := horizontal.normalized() if horizontal.length() > 0.5 else player.global_basis.z
	head_body.linear_velocity = player.velocity + fall_direction * 0.8
	head_body.angular_velocity = fall_direction.cross(Vector3.UP) * -3.0
	_camera_offset = head_body.global_transform.affine_inverse() * start
	camera.top_level = true
	camera.global_transform = start
	died.emit()


## Renasce no ponto inicial ou em `at` (transformação nos pés).
func respawn(at: Variant = null) -> void:
	if head_body != null:
		head_body.queue_free()
		head_body = null
	camera.top_level = false
	camera.transform = _camera_local
	var target: Transform3D = at if at is Transform3D else spawn_transform
	health.revive()
	player.teleport(target.origin)
	player.set_view_rotation(target.basis.get_euler().y, 0.0)
	if player.stamina != null:
		player.stamina.restore(player.stamina.max_stamina)
	time_since_death = 0.0
	respawned.emit()
