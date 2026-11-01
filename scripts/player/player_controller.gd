class_name PlayerController
extends CharacterBody3D
## Controlador físico do sobrevivente em primeira pessoa.
##
## Responsável por: aceleração e inércia, corrida com resistência, salto com
## coyote time e buffer, agachamento com verificação de teto, subida de
## degraus, rampas, queda com cálculo de impacto e dano, recuperação após
## aterrissagens fortes, empurrar e pisar em corpos rígidos e emissão de
## eventos de passada usados pela câmera, áudio e animação.
##
## A origem do corpo fica na sola dos pés. A cápsula de colisão e a cabeça
## são reposicionadas quando a altura do corpo muda.

signal stance_changed(stance: Stance)
signal movement_state_changed(state: MovementState)
signal jumped(vertical_speed: float)
signal landed(impact_speed: float)
signal fall_damage_taken(amount: float, impact_speed: float)
signal footstep(intensity: float, is_left_foot: bool)
signal stepped_up(height: float)

enum Stance { STANDING, CROUCHING }
enum MovementState { IDLE, WALKING, SPRINTING, CROUCH_IDLE, CROUCH_WALKING, AIRBORNE }

@export var settings: MovementSettings
@export var stamina: StaminaComponent
## Nó que recebe a arfagem (olhar para cima/baixo). A guinada gira o corpo.
@export var head: Node3D
@export var collision_shape: CollisionShape3D

## Multiplicador externo de velocidade (peso do inventário, ferimentos, etc.).
var external_speed_multiplier: float = 1.0
## Desativa leitura de entrada (menus, inventário aberto, morte).
var input_enabled: bool = true
var look_enabled: bool = true

var stance: Stance = Stance.STANDING
var movement_state: MovementState = MovementState.IDLE
var is_sprinting: bool = false
var last_impact_speed: float = 0.0

var _gravity: float
var _capsule: CapsuleShape3D
var _current_height: float
var _pitch: float = 0.0
var _move_input: Vector2 = Vector2.ZERO
var _sprint_held: bool = false
var _jump_held: bool = false
var _jump_held_previous: bool = false
var _crouch_toggle_held_previous: bool = false
var _crouch_toggled: bool = false
var _crouch_hold: bool = false
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _jump_cooldown_timer: float = 0.0
var _jumped_this_frame: bool = false
var _airborne_time: float = 0.0
var _stagger_timer: float = 0.0
var _stagger_duration: float = 0.0
var _stride_distance: float = 0.0
var _left_foot_next: bool = true
var _grounded: bool = false
var _teleport_physics_frame: int = -1
var _collision_layer_backup: int = 0

var _motion_params := PhysicsTestMotionParameters3D.new()
var _motion_result := PhysicsTestMotionResult3D.new()
var _stand_query := PhysicsShapeQueryParameters3D.new()
var _stand_shape := CapsuleShape3D.new()

## Altura acima dos pés a partir da qual se verifica espaço para levantar.
## Fica acima de qualquer rampa caminhável tocando a base da cápsula.
const STAND_CHECK_BOTTOM := 0.35
## Folga vertical ao subir um degrau, para a cápsula não raspar na quina.
const STEP_CLEARANCE := 0.005
## Folga extra da sonda de chão além da altura máxima de degrau.
const GROUND_PROBE_EXTRA := 0.08


func _ready() -> void:
	assert(settings != null, "PlayerController precisa de um MovementSettings.")
	assert(head != null and collision_shape != null, "PlayerController precisa de head e collision_shape.")
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	floor_max_angle = deg_to_rad(settings.max_floor_angle_degrees)
	floor_snap_length = settings.floor_snap_length
	floor_constant_speed = true
	floor_block_on_wall = true
	# Só o cenário (camada "mundo") transmite velocidade de plataforma. Objetos
	# soltos podem girar ou ser arremessados e não devem lançar o jogador.
	platform_floor_layers = 1
	# Duplica a forma para que cada instância do jogador tenha sua própria cápsula.
	_capsule = (collision_shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	collision_shape.shape = _capsule
	_capsule.radius = settings.capsule_radius
	_current_height = settings.standing_height
	_apply_body_height(_current_height)

	_stand_shape.radius = settings.capsule_radius - 0.02
	_stand_shape.height = maxf(settings.standing_height + 0.02 - STAND_CHECK_BOTTOM, _stand_shape.radius * 2.0)
	_stand_query.shape = _stand_shape
	_stand_query.exclude = [get_rid()]
	_motion_params.margin = safe_margin


func _process(_delta: float) -> void:
	var look := GameInput.consume_look()
	if not look_enabled:
		return
	if look != Vector2.ZERO:
		rotate_y(-look.x)
		var limit := deg_to_rad(settings.max_pitch_degrees)
		_pitch = clampf(_pitch - look.y, -limit, limit)
		head.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	_restore_collision_after_teleport()
	_read_input()
	_jumped_this_frame = false
	var was_grounded := _grounded

	_update_timers(delta, was_grounded)
	_update_stance(delta)
	_update_sprint(delta, was_grounded)
	_apply_gravity(delta, is_on_floor())
	_handle_jump(delta)
	_apply_horizontal_movement(delta, was_grounded)

	var pre_move_transform := global_transform
	var pre_move_velocity := velocity
	move_and_slide()
	if was_grounded and not _jumped_this_frame and _is_blocked_by_low_obstacle(pre_move_transform, pre_move_velocity):
		if _try_step_up(pre_move_transform, pre_move_velocity, delta):
			# O degrau não deve consumir o momento horizontal.
			velocity.x = pre_move_velocity.x
			velocity.z = pre_move_velocity.z

	_grounded = is_on_floor() or (was_grounded and not _jumped_this_frame \
			and velocity.y <= 0.0 and _probe_ground())
	_interact_with_rigid_bodies(pre_move_velocity, delta)
	_handle_landing(was_grounded, pre_move_velocity)
	_update_stride(delta)
	_update_movement_state()


## Verdadeiro quando o personagem está apoiado: no chão ou descendo um degrau
## (a cápsula contorna a quina e por alguns quadros não toca o piso).
func is_grounded() -> bool:
	return _grounded


func _probe_ground() -> bool:
	var origin := global_position + Vector3.UP * 0.05
	var reach := settings.max_step_height + GROUND_PROBE_EXTRA
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * reach, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and (hit["normal"] as Vector3).angle_to(Vector3.UP) <= floor_max_angle


# --- Entrada -----------------------------------------------------------------

func _read_input() -> void:
	if not input_enabled:
		_move_input = Vector2.ZERO
		_sprint_held = false
		_jump_held = false
		_crouch_hold = false
		return
	_move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_sprint_held = Input.is_action_pressed("sprint")
	_jump_held_previous = _jump_held
	_jump_held = Input.is_action_pressed("jump")
	# A borda de subida é detectada aqui, e não com is_action_just_pressed, para
	# funcionar igualmente com teclado, gamepad e botões de toque pressionados
	# fora do passo de física.
	if _jump_held and not _jump_held_previous:
		_jump_buffer_timer = settings.jump_buffer_time
	var crouch_toggle_held := Input.is_action_pressed("crouch_toggle")
	if crouch_toggle_held and not _crouch_toggle_held_previous:
		_crouch_toggled = not _crouch_toggled
	_crouch_toggle_held_previous = crouch_toggle_held
	_crouch_hold = Input.is_action_pressed("crouch_hold")


# --- Temporizadores ----------------------------------------------------------

func _update_timers(delta: float, on_floor: bool) -> void:
	if on_floor:
		_coyote_timer = settings.coyote_time
		_airborne_time = 0.0
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
		_airborne_time += delta
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_jump_cooldown_timer = maxf(_jump_cooldown_timer - delta, 0.0)
	_stagger_timer = maxf(_stagger_timer - delta, 0.0)


# --- Postura -----------------------------------------------------------------

func _update_stance(delta: float) -> void:
	var wants_crouch := _crouch_toggled or _crouch_hold
	var new_stance := stance
	if wants_crouch:
		new_stance = Stance.CROUCHING
	elif stance == Stance.CROUCHING and can_stand_up():
		new_stance = Stance.STANDING
	if new_stance != stance:
		stance = new_stance
		stance_changed.emit(stance)

	var target_height := settings.standing_height if stance == Stance.STANDING else settings.crouch_height
	if not is_equal_approx(_current_height, target_height):
		_current_height = move_toward(_current_height, target_height, settings.crouch_transition_speed * delta)
		_apply_body_height(_current_height)


## Verifica se há espaço livre acima do corpo para ficar em pé.
func can_stand_up() -> bool:
	_stand_query.collision_mask = collision_mask
	var center_height := STAND_CHECK_BOTTOM + _stand_shape.height * 0.5
	_stand_query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * center_height)
	return get_world_3d().direct_space_state.intersect_shape(_stand_query, 1).is_empty()


func _apply_body_height(height: float) -> void:
	_capsule.height = maxf(height, _capsule.radius * 2.0)
	collision_shape.position = Vector3(0.0, height * 0.5, 0.0)
	head.position.y = height - settings.eye_offset_from_top


# --- Corrida -----------------------------------------------------------------

func _update_sprint(delta: float, on_floor: bool) -> void:
	var moving_forward := _move_input.y < -0.5
	var allowed := _sprint_held and moving_forward and stance == Stance.STANDING \
			and _stagger_timer <= 0.0 and (stamina == null or stamina.can_sprint())
	if on_floor:
		is_sprinting = allowed
	elif not allowed:
		# No ar mantém o estado de corrida (o momento já existe), mas permite cancelar.
		is_sprinting = false
	if is_sprinting and on_floor and stamina != null:
		if not stamina.drain(settings.sprint_stamina_drain, delta):
			is_sprinting = false
	if stamina != null:
		stamina.is_moving = get_horizontal_speed() > 0.3


# --- Gravidade e salto -------------------------------------------------------

func _apply_gravity(delta: float, on_floor: bool) -> void:
	if on_floor and velocity.y <= 0.0:
		return
	velocity.y = maxf(velocity.y - _gravity * delta, -settings.terminal_velocity)


func _handle_jump(delta: float) -> void:
	if _jump_buffer_timer <= 0.0:
		return
	if stance == Stance.CROUCHING:
		# Saltar agachado faz o personagem se levantar, se houver espaço.
		_jump_buffer_timer = 0.0
		if can_stand_up():
			_crouch_toggled = false
		return
	if _coyote_timer <= 0.0 or _jump_cooldown_timer > 0.0 or _current_height < settings.standing_height - 0.05:
		return
	var height_factor := 1.0
	if stamina != null:
		if not stamina.try_consume(settings.jump_stamina_cost):
			var obtained := stamina.consume_partial(settings.jump_stamina_cost)
			height_factor = lerpf(settings.exhausted_jump_factor, 1.0, obtained)
	var jump_speed := sqrt(2.0 * _gravity * settings.jump_height * height_factor)
	# Meio passo de gravidade compensa a integração discreta: a altura atingida
	# fica igual à altura física configurada.
	velocity.y = jump_speed - 0.5 * _gravity * delta
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_jumped_this_frame = true
	jumped.emit(jump_speed)


# --- Deslocamento horizontal -------------------------------------------------

func _apply_horizontal_movement(delta: float, on_floor: bool) -> void:
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := global_basis.x
	right.y = 0.0
	right = right.normalized()

	var input_strength := minf(_move_input.length(), 1.0)
	var wish_direction := Vector3.ZERO
	if input_strength > 0.0:
		wish_direction = (right * _move_input.x - forward * _move_input.y).normalized()

	var target_speed := _get_base_speed() * input_strength * _get_direction_multiplier() \
			* external_speed_multiplier * _get_stagger_multiplier()
	if on_floor and target_speed > 0.0:
		target_speed *= _get_slope_multiplier(wish_direction)
	var target := wish_direction * target_speed

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if on_floor:
		horizontal = _accelerate(horizontal, target, settings.ground_acceleration,
				settings.ground_deceleration, settings.ground_turn_friction, delta)
	else:
		horizontal = _accelerate_air(horizontal, target, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Acelera ao longo da direção desejada e freia a componente lateral
## separadamente: curvas fechadas perdem velocidade como um corpo real.
func _accelerate(current: Vector3, target: Vector3, acceleration: float,
		deceleration: float, turn_friction: float, delta: float) -> Vector3:
	if target.length_squared() < 0.0001:
		return current.move_toward(Vector3.ZERO, deceleration * delta)
	var target_speed := target.length()
	var direction := target / target_speed
	var along := current.dot(direction)
	var lateral := current - direction * along
	lateral = lateral.move_toward(Vector3.ZERO, turn_friction * delta)
	if along < 0.0:
		along = move_toward(along, target_speed, deceleration * delta)
	elif along < target_speed:
		along = move_toward(along, target_speed, acceleration * delta)
	else:
		along = move_toward(along, target_speed, deceleration * delta)
	return direction * along + lateral


## No ar o corpo conserva o momento. O controle permite pequenas correções,
## sem superar a velocidade que já existia nem a de caminhada.
func _accelerate_air(current: Vector3, target: Vector3, delta: float) -> Vector3:
	var result := current * maxf(1.0 - settings.air_drag * delta, 0.0)
	if target.length_squared() < 0.0001:
		return result
	var speed_cap := maxf(current.length(), settings.walk_speed)
	var desired := result + target.normalized() * settings.air_acceleration * delta
	if desired.length() > speed_cap:
		desired = desired.normalized() * speed_cap
	return desired


func _get_base_speed() -> float:
	if stance == Stance.CROUCHING or _current_height < settings.standing_height - 0.05:
		return settings.crouch_speed
	if is_sprinting:
		return settings.sprint_speed
	return settings.walk_speed


func _get_direction_multiplier() -> float:
	var input := _move_input.normalized()
	var total := absf(input.x) + absf(input.y)
	if total <= 0.0:
		return 1.0
	var forward_part := maxf(-input.y, 0.0)
	var backward_part := maxf(input.y, 0.0) * settings.backward_multiplier
	var side_part := absf(input.x) * settings.strafe_multiplier
	return (forward_part + backward_part + side_part) / total


func _get_slope_multiplier(wish_direction: Vector3) -> float:
	var floor_normal := get_floor_normal()
	var downhill := Vector3(floor_normal.x, 0.0, floor_normal.z)
	# downhill tem módulo igual ao seno da inclinação e aponta morro abaixo.
	var uphill_amount := clampf(-wish_direction.dot(downhill), 0.0, 1.0)
	return 1.0 - uphill_amount * settings.uphill_penalty


func _get_stagger_multiplier() -> float:
	if _stagger_timer <= 0.0 or _stagger_duration <= 0.0:
		return 1.0
	var t := _stagger_timer / _stagger_duration
	return lerpf(1.0, settings.stagger_min_speed_multiplier, t)


# --- Degraus -----------------------------------------------------------------

## Verdadeiro se move_and_slide parou o corpo contra uma face vertical baixa
## (classificada pelo próprio motor como parede) na direção do movimento.
func _is_blocked_by_low_obstacle(start: Transform3D, intended_velocity: Vector3) -> bool:
	var horizontal := Vector3(intended_velocity.x, 0.0, intended_velocity.z)
	if horizontal.length_squared() < 0.01 or settings.max_step_height <= 0.0:
		return false
	var direction := horizontal.normalized()
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()
		if normal.angle_to(Vector3.UP) <= floor_max_angle or normal.y < -0.1:
			continue
		var flat_normal := Vector3(normal.x, 0.0, normal.z).normalized()
		if direction.dot(flat_normal) > -0.3:
			continue
		if collision.get_position().y - start.origin.y <= settings.max_step_height + 0.02:
			return true
	return false


## Sobe obstáculos verticais até max_step_height: a partir da posição anterior
## ao movimento, testa elevar e avançar a cápsula e mede o topo com um raio;
## só aplica a elevação se houver piso caminhável na altura permitida.
func _try_step_up(start: Transform3D, intended_velocity: Vector3, delta: float) -> bool:
	var horizontal := Vector3(intended_velocity.x, 0.0, intended_velocity.z)
	var motion := horizontal * delta
	var rid := get_rid()

	var raised := start
	_motion_params.from = start
	_motion_params.motion = Vector3.UP * settings.max_step_height
	if PhysicsServer3D.body_test_motion(rid, _motion_params, _motion_result):
		raised.origin += _motion_result.get_travel()
	else:
		raised.origin += _motion_params.motion
	if raised.origin.y - start.origin.y < 0.02:
		return false

	# O avanço de teste usa ao menos o raio da cápsula: a base arredondada só
	# assenta no topo do degrau quando o centro passa da quina. O corpo real
	# não avança aqui; ele só é elevado, e move_and_slide faz o deslocamento.
	var direction := horizontal.normalized()
	var probe_motion := direction * maxf(motion.length(), settings.capsule_radius + 0.05)
	var advanced := raised
	_motion_params.from = raised
	_motion_params.motion = probe_motion
	if PhysicsServer3D.body_test_motion(rid, _motion_params, _motion_result):
		# Recuo de 2 cm da face encontrada (ex.: o espelho do próximo degrau),
		# para que o raio de apoio não caia rente à face.
		var usable := _motion_result.get_travel().length() - 0.02
		if usable < settings.capsule_radius * 0.25:
			return false # Também bloqueado na altura elevada: é uma parede.
		advanced.origin += direction * usable
	else:
		advanced.origin += probe_motion

	# A altura de apoio é medida por um raio no centro da cápsula avançada: é
	# ali que o peso do corpo vai assentar. Quinas de degraus seguintes não
	# interferem, e a superfície precisa ser caminhável.
	var ray_from := Vector3(advanced.origin.x, raised.origin.y + 0.01, advanced.origin.z)
	var ray_to := Vector3(advanced.origin.x, start.origin.y - 0.01, advanced.origin.z)
	var ray := PhysicsRayQueryParameters3D.create(ray_from, ray_to, collision_mask, [rid])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return false
	if (hit["normal"] as Vector3).angle_to(Vector3.UP) > floor_max_angle:
		return false
	var landing_height: float = (hit["position"] as Vector3).y
	var step_height := landing_height - start.origin.y
	if step_height < 0.01 or step_height > settings.max_step_height + 0.01:
		return false

	global_position = Vector3(start.origin.x, landing_height + STEP_CLEARANCE, start.origin.z)
	stepped_up.emit(step_height)
	return true


# --- Corpos rígidos ----------------------------------------------------------

## Empurra objetos com força limitada (objetos pesados mal se movem) e aplica
## o peso do corpo sobre aquilo em que o personagem está pisando.
func _interact_with_rigid_bodies(pre_move_velocity: Vector3, delta: float) -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if body == null or body.freeze:
			continue
		var normal := collision.get_normal()
		var contact_offset := collision.get_position() - body.global_position
		if normal.y > 0.7:
			body.apply_force(Vector3.DOWN * settings.body_mass * _gravity, contact_offset)
			continue
		var push_direction := Vector3(-normal.x, 0.0, -normal.z)
		if push_direction.length_squared() < 0.0001:
			continue
		push_direction = push_direction.normalized()
		var push_speed := Vector3(pre_move_velocity.x, 0.0, pre_move_velocity.z).dot(push_direction)
		if push_speed <= 0.05:
			continue
		var body_speed := body.linear_velocity.dot(push_direction)
		if body_speed >= push_speed:
			continue
		# Força proporcional à velocidade de impulso, limitada pela força máxima
		# do corpo humano, e nunca maior que a necessária para igualar velocidades.
		var effort := clampf(push_speed / settings.walk_speed, 0.25, 1.0)
		var impulse := settings.max_push_force * effort * delta
		impulse = minf(impulse, (push_speed - body_speed) * body.mass)
		body.apply_impulse(push_direction * impulse, contact_offset)


# --- Aterrissagem ------------------------------------------------------------

func _handle_landing(was_grounded: bool, pre_move_velocity: Vector3) -> void:
	if was_grounded or not _grounded:
		return
	var impact := maxf(-pre_move_velocity.y, 0.0)
	last_impact_speed = impact
	_jump_cooldown_timer = settings.jump_cooldown
	landed.emit(impact)

	if impact > settings.stagger_impact_speed:
		var severity := clampf(inverse_lerp(settings.stagger_impact_speed, settings.lethal_impact_speed, impact), 0.0, 1.0)
		_stagger_duration = lerpf(0.25, settings.stagger_max_duration, severity)
		_stagger_timer = _stagger_duration
		# Parte da velocidade horizontal é absorvida pelas pernas.
		velocity.x *= lerpf(0.7, 0.2, severity)
		velocity.z *= lerpf(0.7, 0.2, severity)

	var damage := calculate_fall_damage(impact)
	if damage > 0.0:
		fall_damage_taken.emit(damage, impact)


## Dano de queda: zero até o impacto seguro e cresce de forma quadrática (a
## energia do impacto é proporcional ao quadrado da velocidade) até o letal.
func calculate_fall_damage(impact_speed: float) -> float:
	if impact_speed <= settings.safe_impact_speed:
		return 0.0
	var safe_energy := settings.safe_impact_speed * settings.safe_impact_speed
	var lethal_energy := settings.lethal_impact_speed * settings.lethal_impact_speed
	var t := (impact_speed * impact_speed - safe_energy) / (lethal_energy - safe_energy)
	return settings.lethal_fall_damage * clampf(t, 0.0, 10.0)


# --- Passada -----------------------------------------------------------------

func _update_stride(delta: float) -> void:
	var speed := get_horizontal_speed()
	if not _grounded or speed < 0.25:
		# Ao parar, o próximo passo começa do zero.
		if _grounded:
			_stride_distance = move_toward(_stride_distance, 0.0, delta * 2.0)
		return
	_stride_distance += speed * delta
	var stride := get_stride_length()
	if _stride_distance >= stride:
		_stride_distance -= stride
		footstep.emit(clampf(speed / settings.sprint_speed, 0.1, 1.0), _left_foot_next)
		_left_foot_next = not _left_foot_next


func get_stride_length() -> float:
	if stance == Stance.CROUCHING:
		return settings.crouch_stride
	var t := clampf(inverse_lerp(settings.walk_speed, settings.sprint_speed, get_horizontal_speed()), 0.0, 1.0)
	return lerpf(settings.walk_stride, settings.sprint_stride, t)


# --- Estado ------------------------------------------------------------------

func _update_movement_state() -> void:
	var new_state: MovementState
	var moving := get_horizontal_speed() > 0.2
	if not _grounded and _airborne_time > 0.08:
		new_state = MovementState.AIRBORNE
	elif stance == Stance.CROUCHING:
		new_state = MovementState.CROUCH_WALKING if moving else MovementState.CROUCH_IDLE
	elif is_sprinting and moving:
		new_state = MovementState.SPRINTING
	elif moving:
		new_state = MovementState.WALKING
	else:
		new_state = MovementState.IDLE
	if new_state != movement_state:
		movement_state = new_state
		movement_state_changed.emit(movement_state)


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Velocidade horizontal no espaço local (x = direita, z = para trás).
func get_local_horizontal_velocity() -> Vector3:
	var local := global_basis.inverse() * velocity
	local.y = 0.0
	return local


## Fase do passo atual, de 0 a 1.
func get_stride_phase() -> float:
	return clampf(_stride_distance / get_stride_length(), 0.0, 1.0)


func is_left_foot_next() -> bool:
	return _left_foot_next


func get_current_height() -> float:
	return _current_height


func get_pitch() -> float:
	return _pitch


func is_recovering_from_landing() -> bool:
	return _stagger_timer > 0.0


## Define a orientação da visão (radianos). Útil para spawn e cutscenes.
func set_view_rotation(yaw: float, pitch: float) -> void:
	rotation.y = yaw
	var limit := deg_to_rad(settings.max_pitch_degrees)
	_pitch = clampf(pitch, -limit, limit)
	head.rotation.x = _pitch


## Posiciona o personagem, zerando velocidade e estado aéreo.
##
## No Jolt, mover um corpo cinemático alterando sua transformação gera uma
## velocidade implícita (distância / passo) que arremessaria objetos tocados
## no destino. Por isso a camada de colisão do jogador fica desligada durante
## o passo de física do teletransporte e é restaurada em seguida.
func teleport(position_on_feet: Vector3) -> void:
	if _teleport_physics_frame < 0:
		_collision_layer_backup = collision_layer
	collision_layer = 0
	_teleport_physics_frame = Engine.get_physics_frames()
	global_position = position_on_feet
	velocity = Vector3.ZERO
	_airborne_time = 0.0
	_stagger_timer = 0.0
	_grounded = false
	reset_physics_interpolation()


func _restore_collision_after_teleport() -> void:
	if _teleport_physics_frame >= 0 and Engine.get_physics_frames() >= _teleport_physics_frame + 2:
		collision_layer = _collision_layer_backup
		_teleport_physics_frame = -1
