class_name DamageZone
extends Area3D
## Área que fere quem está dentro (arame farpado, fogo, vidro quebrado).
##
## Causa dano em pulsos e reduz a velocidade enquanto o corpo estiver dentro.

@export_range(0.0, 200.0, 0.5) var damage_per_second: float = 10.0
@export var damage_kind: StringName = &"arame"
@export_range(0.05, 5.0, 0.05) var tick_interval: float = 0.6
## Multiplicador de velocidade de quem está dentro (arame prende a roupa).
@export_range(0.05, 1.0, 0.01) var speed_multiplier: float = 0.5

var _timers: Dictionary = {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	for body in _timers.keys():
		if not is_instance_valid(body):
			_timers.erase(body)
			continue
		_timers[body] += delta
		if _timers[body] >= tick_interval:
			_timers[body] -= tick_interval
			_hurt(body)


func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController and (body as PlayerController).health != null:
		_timers[body] = 0.0
		(body as PlayerController).external_speed_multiplier = speed_multiplier
		_hurt(body)


func _on_body_exited(body: Node3D) -> void:
	if _timers.has(body):
		_timers.erase(body)
		(body as PlayerController).external_speed_multiplier = 1.0


func _hurt(body: Node3D) -> void:
	var player := body as PlayerController
	var direction := (player.global_position - global_position)
	direction.y = 0.0
	player.health.apply_damage(damage_per_second * tick_interval, damage_kind, -direction.normalized())
