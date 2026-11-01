class_name ViewmodelMotion
extends Node3D
## Movimento secundário dos braços em primeira pessoa, por cima das animações.
##
## Os braços têm massa: atrasam quando a visão gira (inércia rotacional),
## ficam para trás quando o corpo acelera, respiram mais forte e mais rápido
## com a resistência baixa e levam um tranco na direção de onde veio o dano.
## Tudo é integrado por molas amortecidas, sem curvas fixas.

@export var player: PlayerController
@export var stamina: StaminaComponent
@export var health: HealthComponent

@export_group("Atraso da visão")
## Graus de atraso por rad/s de rotação da visão.
@export_range(0.0, 10.0, 0.05) var look_lag_degrees_per_rad_s: float = 1.6
@export_range(0.0, 15.0, 0.1) var max_look_lag_degrees: float = 4.0

@export_group("Inércia do corpo")
## Deslocamento (m) por m/s² de aceleração do corpo.
@export_range(0.0, 0.01, 0.0001) var inertia_per_acceleration: float = 0.0018
@export_range(0.0, 0.1, 0.001) var max_inertia_offset: float = 0.022

@export_group("Respiração")
@export_range(0.0, 0.02, 0.0001) var calm_breath_amplitude: float = 0.0012
@export_range(0.0, 0.03, 0.0001) var exhausted_breath_amplitude: float = 0.0065
@export_range(0.05, 2.0, 0.01) var calm_breath_rate: float = 0.25
@export_range(0.1, 3.0, 0.01) var exhausted_breath_rate: float = 0.75

@export_group("Molas")
@export_range(10.0, 800.0, 1.0) var stiffness: float = 140.0
@export_range(1.0, 60.0, 0.5) var damping: float = 17.0
## Tranco (graus/s) por ponto de dano recebido.
@export_range(0.0, 50.0, 0.5) var damage_kick_per_point: float = 6.0

var _rotation_offset: Vector3 = Vector3.ZERO
var _rotation_velocity: Vector3 = Vector3.ZERO
var _position_offset: Vector3 = Vector3.ZERO
var _position_velocity: Vector3 = Vector3.ZERO
var _rotation_target: Vector3 = Vector3.ZERO
var _position_target: Vector3 = Vector3.ZERO
var _previous_yaw: float = 0.0
var _previous_pitch: float = 0.0
var _previous_local_velocity: Vector3 = Vector3.ZERO
var _breath_phase: float = 0.0
var _has_previous: bool = false


func _ready() -> void:
	if health != null:
		health.damaged.connect(_on_damaged)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	# Aceleração do corpo no espaço local: os braços ficam para trás dela.
	var local_velocity := player.get_local_horizontal_velocity()
	var acceleration := (local_velocity - _previous_local_velocity) / delta
	_previous_local_velocity = local_velocity
	var offset := -acceleration * inertia_per_acceleration
	offset.y = -player.velocity.y * 0.002
	_position_target = offset.limit_length(max_inertia_offset)


func _process(delta: float) -> void:
	if player == null:
		return
	delta = minf(delta, 1.0 / 20.0)
	var yaw := player.rotation.y
	var pitch := player.get_pitch()
	if _has_previous and delta > 0.0:
		var yaw_rate := wrapf(yaw - _previous_yaw, -PI, PI) / delta
		var pitch_rate := (pitch - _previous_pitch) / delta
		var limit := deg_to_rad(max_look_lag_degrees)
		var factor := deg_to_rad(look_lag_degrees_per_rad_s)
		# Os braços tentam manter a orientação anterior: giram contra a visão.
		_rotation_target = Vector3(
				clampf(-pitch_rate * factor, -limit, limit),
				clampf(-yaw_rate * factor, -limit, limit),
				clampf(yaw_rate * factor * 0.5, -limit, limit))
	_previous_yaw = yaw
	_previous_pitch = pitch
	_has_previous = true

	var fatigue := 1.0 - (stamina.get_ratio() if stamina != null else 1.0)
	_breath_phase += TAU * lerpf(calm_breath_rate, exhausted_breath_rate, fatigue) * delta
	var breath := sin(_breath_phase) * lerpf(calm_breath_amplitude, exhausted_breath_amplitude, fatigue)

	var rotation_acceleration := (_rotation_target - _rotation_offset) * stiffness - _rotation_velocity * damping
	_rotation_velocity += rotation_acceleration * delta
	_rotation_offset += _rotation_velocity * delta
	var position_acceleration := (_position_target - _position_offset) * stiffness - _position_velocity * damping
	_position_velocity += position_acceleration * delta
	_position_offset += _position_velocity * delta

	position = _position_offset + Vector3(0.0, breath, 0.0)
	rotation = _rotation_offset + Vector3(breath * 1.5, 0.0, 0.0)


func get_rotation_offset() -> Vector3:
	return _rotation_offset


func _on_damaged(amount: float, _kind: StringName, direction: Vector3) -> void:
	var kick := deg_to_rad(damage_kick_per_point) * amount
	var local := Vector3.ZERO
	if direction != Vector3.ZERO and player != null:
		local = player.global_basis.inverse() * direction
	# O impacto empurra os braços para longe da origem do golpe e para cima.
	_rotation_velocity += Vector3(kick, -local.x * kick, local.x * kick * 0.5)
	_position_velocity += Vector3(-local.x, 0.0, -local.z).normalized() * kick * 0.02 if local != Vector3.ZERO else Vector3.ZERO
