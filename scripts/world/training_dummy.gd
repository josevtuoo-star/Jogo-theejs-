class_name TrainingDummy
extends StaticBody3D
## Boneco de treino: recebe golpes (receive_hit), balança na direção do
## impacto com uma mola amortecida e mostra o dano do último golpe.

signal hit_received(damage: float, kind: StringName)

## Nó que balança (o tronco do boneco).
@export var pivot: Node3D
@export var label: Label3D
## Graus/s de balanço por kg·m/s de impulso.
@export_range(0.0, 50.0, 0.5) var sway_per_impulse: float = 6.0
@export_range(10.0, 500.0, 1.0) var stiffness: float = 60.0
@export_range(0.5, 30.0, 0.5) var damping: float = 5.0

var hits: int = 0
var total_damage: float = 0.0
var last_damage: float = 0.0
var _angle: Vector2 = Vector2.ZERO
var _angular_velocity: Vector2 = Vector2.ZERO


func receive_hit(hit: Dictionary) -> void:
	var damage: float = hit.get("damage", 0.0)
	var impulse: float = hit.get("impulse", 0.0)
	var direction: Vector3 = hit.get("direction", Vector3.ZERO)
	hits += 1
	last_damage = damage
	total_damage += damage
	var local := global_basis.inverse() * direction
	# O golpe empurra o topo do boneco na direção do soco.
	_angular_velocity += Vector2(local.z, -local.x) * deg_to_rad(sway_per_impulse) * impulse
	if label != null:
		label.text = "%.0f" % damage
	hit_received.emit(damage, hit.get("kind", &""))


func _physics_process(delta: float) -> void:
	var acceleration := -_angle * stiffness - _angular_velocity * damping
	_angular_velocity += acceleration * delta
	_angle += _angular_velocity * delta
	if pivot != null:
		pivot.rotation = Vector3(_angle.x, 0.0, _angle.y)


func get_sway_angle() -> float:
	return _angle.length()
