class_name PlayerCameraEffects
extends Node3D
## Movimento natural da câmera em primeira pessoa.
##
## Fica entre a cabeça (que recebe a arfagem) e a Camera3D. Aplica apenas
## deslocamentos pequenos, derivados do estado físico real do personagem:
## - balanço sincronizado com a passada (um passo por distância percorrida);
## - inércia da cabeça: o tronco inclina para frente ao acelerar e para trás
##   ao frear, e lateralmente nas curvas, na proporção da aceleração real;
## - inclinação ao andar de lado e ao escorregar em encostas;
## - mola amortecida na aterrissagem, no impacto contra paredes e no teto;
## - suavização ao subir degraus e leve aumento do campo de visão ao correr.

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

@export_group("Inércia da cabeça")
## Inclinação para frente (graus) por m/s² de aceleração para frente.
@export_range(0.0, 1.0, 0.005) var lean_pitch_per_acceleration: float = 0.12
## Rolagem (graus) por m/s² de aceleração lateral.
@export_range(0.0, 1.0, 0.005) var lean_roll_per_acceleration: float = 0.08
## Limite da inclinação por aceleração (graus).
@export_range(0.0, 10.0, 0.1) var max_lean_degrees: float = 2.5
@export_range(0.5, 30.0, 0.1) var lean_smoothing: float = 6.0

@export_group("Inclinação lateral")
@export_range(0.0, 5.0, 0.01) var strafe_roll_degrees: float = 1.2
## Rolagem máxima ao escorregar numa encosta (graus).
@export_range(0.0, 10.0, 0.1) var slide_roll_degrees: float = 3.0
@export_range(0.1, 30.0, 0.1) var roll_smoothing: float = 7.0

@export_group("Impactos")
## Impacto mínimo (m/s) que movimenta a câmera na aterrissagem.
@export_range(0.0, 10.0, 0.1) var landing_min_impact: float = 1.5
## Velocidade inicial da mola por m/s de impacto.
@export_range(0.0, 0.2, 0.001) var landing_impulse_per_speed: float = 0.05
@export_range(0.0, 0.5, 0.005) var landing_max_dip: float = 0.16
@export_range(10.0, 600.0, 1.0) var spring_stiffness: float = 160.0
@export_range(1.0, 60.0, 0.5) var spring_damping: float = 19.0
## Inclinação para baixo (graus) por metro de afundamento.
@export_range(0.0, 60.0, 0.5) var landing_pitch_per_meter: float = 18.0
## Tranco angular (graus/s) por m/s de impacto contra paredes e teto.
@export_range(0.0, 60.0, 0.5) var impact_kick_per_speed: float = 9.0
@export_range(10.0, 600.0, 1.0) var kick_stiffness: float = 220.0
@export_range(1.0, 60.0, 0.5) var kick_damping: float = 22.0

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
var _kick_angle: float = 0.0
var _kick_velocity: float = 0.0
var _step_offset: float = 0.0
var _roll: float = 0.0
var _lean_pitch: float = 0.0
var _lean_roll: float = 0.0
var _lean_target: Vector2 = Vector2.ZERO
var _previous_local_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	assert(player != null and camera != null, "PlayerCameraEffects precisa de player e camera.")
	player.landed.connect(_on_player_landed)
	player.stepped_up.connect(_on_player_stepped_up)
	player.wall_impact.connect(_on_player_wall_impact)
	player.head_bumped.connect(_on_player_head_bumped)
	camera.fov = base_fov


## A aceleração é medida no passo de física, onde a velocidade realmente muda.
func _physics_process(delta: float) -> void:
	var local_velocity := player.get_local_horizontal_velocity()
	var acceleration := (local_velocity - _previous_local_velocity) / delta
	_previous_local_velocity = local_velocity
	if not player.is_grounded():
		_lean_target = Vector2.ZERO
		return
	var limit := deg_to_rad(max_lean_degrees)
	# z local aponta para trás: aceleração para frente = -acceleration.z.
	_lean_target.x = clampf(acceleration.z * deg_to_rad(lean_pitch_per_acceleration), -limit, limit)
	_lean_target.y = clampf(-acceleration.x * deg_to_rad(lean_roll_per_acceleration), -limit, limit)


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

	# Molas amortecidas (integração semi-implícita): afundamento vertical e tranco angular.
	var spring_acceleration := -spring_stiffness * _landing_offset - spring_damping * _landing_velocity
	_landing_velocity += spring_acceleration * delta
	_landing_offset += _landing_velocity * delta
	_landing_offset = clampf(_landing_offset, -landing_max_dip, landing_max_dip * 0.5)
	var kick_acceleration := -kick_stiffness * _kick_angle - kick_damping * _kick_velocity
	_kick_velocity += kick_acceleration * delta
	_kick_angle += _kick_velocity * delta

	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-step_smoothing * delta))

	var lean_weight := 1.0 - exp(-lean_smoothing * delta)
	_lean_pitch = lerpf(_lean_pitch, _lean_target.x, lean_weight)
	_lean_roll = lerpf(_lean_roll, _lean_target.y, lean_weight)

	var target_roll := 0.0
	if player.is_sliding:
		# Inclina para o lado em que a encosta cai, em relação ao olhar.
		var downhill := player.get_slide_normal()
		var local_downhill := player.global_basis.inverse() * Vector3(downhill.x, 0.0, downhill.z)
		target_roll = -clampf(local_downhill.x * 2.0, -1.0, 1.0) * deg_to_rad(slide_roll_degrees)
	elif on_floor:
		var local_velocity := player.get_local_horizontal_velocity()
		var strafe_ratio := clampf(local_velocity.x / settings.sprint_speed, -1.0, 1.0)
		target_roll = -strafe_ratio * deg_to_rad(strafe_roll_degrees)
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-roll_smoothing * delta))

	position = Vector3(bob_lateral, bob_vertical + _landing_offset + _step_offset, 0.0)
	rotation = Vector3(deg_to_rad(landing_pitch_per_meter) * _landing_offset + _lean_pitch + _kick_angle,
			0.0, _roll + bob_roll + _lean_roll)

	var target_fov := base_fov + (sprint_fov_bonus * sprint_blend if player.is_sprinting else 0.0)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-fov_smoothing * delta))


func _on_player_landed(impact_speed: float) -> void:
	if impact_speed < landing_min_impact:
		return
	_landing_velocity -= (impact_speed - landing_min_impact * 0.5) * landing_impulse_per_speed * 10.0


func _on_player_stepped_up(height: float) -> void:
	# O corpo subiu instantaneamente; a câmera acompanha de forma suave.
	_step_offset = maxf(_step_offset - height, -player.settings.max_step_height * 1.5)


func _on_player_wall_impact(impact_speed: float, _normal: Vector3) -> void:
	# A cabeça é jogada para trás (olhar sobe) e o corpo afunda um pouco.
	_kick_velocity += deg_to_rad(impact_kick_per_speed) * impact_speed
	_landing_velocity -= impact_speed * landing_impulse_per_speed * 3.0


func _on_player_head_bumped(impact_speed: float) -> void:
	# A batida no teto empurra a cabeça para baixo.
	_kick_velocity -= deg_to_rad(impact_kick_per_speed) * impact_speed * 1.5
	_landing_velocity -= impact_speed * landing_impulse_per_speed * 4.0
