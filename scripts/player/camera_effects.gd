class_name PlayerCameraEffects
extends Node3D
## Movimento natural da câmera em primeira pessoa.
##
## Fica entre a cabeça (que recebe a arfagem) e a Camera3D. Aplica apenas
## deslocamentos pequenos, derivados do estado físico real do personagem:
## balanço sincronizado com a passada, inclinação lateral ao andar de lado,
## amortecimento por mola na aterrissagem, suavização ao subir degraus e um
## leve aumento do campo de visão ao correr.

@export var player: PlayerController
@export var camera: Camera3D

@export_group("Balanço da passada")
@export var bob_enabled: bool = true
## Amplitude vertical por passo (m), andando e correndo.
@export_range(0.0, 0.1, 0.001) var walk_bob_vertical: float = 0.012
@export_range(0.0, 0.1, 0.001) var sprint_bob_vertical: float = 0.026
@export_range(0.0, 0.1, 0.001) var crouch_bob_vertical: float = 0.008
## Amplitude lateral por ciclo de dois passos (m).
@export_range(0.0, 0.1, 0.001) var walk_bob_lateral: float = 0.008
@export_range(0.0, 0.1, 0.001) var sprint_bob_lateral: float = 0.016
## Rolagem da câmera acompanhando o apoio de cada pé (graus).
@export_range(0.0, 3.0, 0.01) var bob_roll_degrees: float = 0.35

@export_group("Inclinação ao andar de lado")
@export_range(0.0, 5.0, 0.01) var strafe_roll_degrees: float = 1.2
@export_range(0.1, 30.0, 0.1) var roll_smoothing: float = 7.0

@export_group("Aterrissagem")
## Impacto mínimo (m/s) que movimenta a câmera.
@export_range(0.0, 10.0, 0.1) var landing_min_impact: float = 1.5
## Velocidade inicial da mola por m/s de impacto.
@export_range(0.0, 0.2, 0.001) var landing_impulse_per_speed: float = 0.05
@export_range(0.0, 0.5, 0.005) var landing_max_dip: float = 0.16
@export_range(10.0, 600.0, 1.0) var spring_stiffness: float = 160.0
@export_range(1.0, 60.0, 0.5) var spring_damping: float = 19.0
## Inclinação para baixo (graus) por metro de afundamento.
@export_range(0.0, 60.0, 0.5) var landing_pitch_per_meter: float = 18.0

@export_group("Degraus")
## Velocidade de recuperação do deslocamento vertical ao subir degraus.
@export_range(1.0, 40.0, 0.5) var step_smoothing: float = 14.0

@export_group("Campo de visão")
@export_range(40.0, 110.0, 0.5) var base_fov: float = 75.0
@export_range(0.0, 20.0, 0.1) var sprint_fov_bonus: float = 4.0
@export_range(0.1, 30.0, 0.1) var fov_smoothing: float = 5.0

var _bob_weight: float = 0.0
var _landing_offset: float = 0.0
var _landing_velocity: float = 0.0
var _step_offset: float = 0.0
var _roll: float = 0.0


func _ready() -> void:
	assert(player != null and camera != null, "PlayerCameraEffects precisa de player e camera.")
	player.landed.connect(_on_player_landed)
	player.stepped_up.connect(_on_player_stepped_up)
	camera.fov = base_fov


func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 20.0)
	var settings := player.settings
	var speed := player.get_horizontal_speed()
	var on_floor := player.is_grounded()

	# Peso do balanço: proporcional à velocidade, zero no ar.
	var target_weight := 0.0
	if bob_enabled and on_floor:
		target_weight = clampf(speed / settings.walk_speed, 0.0, 1.0)
	_bob_weight = lerpf(_bob_weight, target_weight, 1.0 - exp(-10.0 * delta))

	var sprint_blend := clampf(inverse_lerp(settings.walk_speed, settings.sprint_speed, speed), 0.0, 1.0)
	var crouching := player.stance == PlayerController.Stance.CROUCHING
	var vertical_amplitude := crouch_bob_vertical if crouching else lerpf(walk_bob_vertical, sprint_bob_vertical, sprint_blend)
	var lateral_amplitude := lerpf(walk_bob_lateral, sprint_bob_lateral, sprint_blend)

	var phase := player.get_stride_phase()
	# Um ciclo vertical por passo (mais baixo no apoio) e um ciclo lateral a cada dois passos.
	var side := 1.0 if player.is_left_foot_next() else -1.0
	var bob_vertical := -vertical_amplitude * 0.5 * (1.0 - cos(phase * TAU)) * _bob_weight
	var bob_lateral := lateral_amplitude * sin(phase * PI) * side * _bob_weight
	var bob_roll := deg_to_rad(bob_roll_degrees) * sin(phase * PI) * side * _bob_weight

	# Mola criticamente amortecida para a aterrissagem (integração semi-implícita).
	var spring_acceleration := -spring_stiffness * _landing_offset - spring_damping * _landing_velocity
	_landing_velocity += spring_acceleration * delta
	_landing_offset += _landing_velocity * delta
	_landing_offset = clampf(_landing_offset, -landing_max_dip, landing_max_dip * 0.5)

	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-step_smoothing * delta))

	var local_velocity := player.get_local_horizontal_velocity()
	var strafe_ratio := clampf(local_velocity.x / settings.sprint_speed, -1.0, 1.0) if on_floor else 0.0
	var target_roll := -strafe_ratio * deg_to_rad(strafe_roll_degrees)
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-roll_smoothing * delta))

	position = Vector3(bob_lateral, bob_vertical + _landing_offset + _step_offset, 0.0)
	rotation = Vector3(deg_to_rad(landing_pitch_per_meter) * _landing_offset, 0.0, _roll + bob_roll)

	var target_fov := base_fov + (sprint_fov_bonus * sprint_blend if player.is_sprinting else 0.0)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-fov_smoothing * delta))


func _on_player_landed(impact_speed: float) -> void:
	if impact_speed < landing_min_impact:
		return
	_landing_velocity -= (impact_speed - landing_min_impact * 0.5) * landing_impulse_per_speed * 10.0


func _on_player_stepped_up(height: float) -> void:
	# O corpo subiu instantaneamente; a câmera acompanha de forma suave.
	_step_offset = maxf(_step_offset - height, -player.settings.max_step_height * 1.5)
