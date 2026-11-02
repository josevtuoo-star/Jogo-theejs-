class_name PlayerController
extends CharacterBody3D
## Controlador físico do sobrevivente em primeira pessoa.
##
## Modelo de movimento:
## - A velocidade desejada vem do direcional (andar → trotar → correr), da
##   postura, da carga, da superfície, da inclinação e da recuperação de impactos.
## - A velocidade atual se aproxima da desejada com aceleração dependente da
##   velocidade (arranque forte, ganho gradual perto do máximo), frenagem e
##   atrito lateral em curvas.
## - Toda variação de velocidade no chão é limitada pelo atrito disponível
##   (círculo de atrito μ·g): em asfalto o corpo responde rápido; no gelo ele
##   desliza de verdade. Com o pé plantado, o corpo para sem micro-deslizes.
## - A massa total (corpo + carga) reduz a aceleração, a frenagem e o salto.
## - No ar, gravidade e arrasto aerodinâmico quadrático; o momento é mantido.
## - Acima da inclinação caminhável, o corpo escorrega com atrito cinético.
## - Colisões geram eventos de impacto (piso, paredes, teto) com velocidade real.
##
## A origem do corpo fica na sola dos pés. A cápsula de colisão e a cabeça são
## reposicionadas quando a altura do corpo muda.

signal stance_changed(stance: Stance)
signal movement_state_changed(state: MovementState)
signal jumped(vertical_speed: float)
signal landed(impact_speed: float)
signal fall_damage_taken(amount: float, impact_speed: float)
signal footstep(intensity: float, is_left_foot: bool, surface: SurfaceProfile)
signal stepped_up(height: float)
signal wall_impact(impact_speed: float, normal: Vector3)
signal head_bumped(impact_speed: float)
signal surface_changed(surface: SurfaceProfile)
signal slide_started
signal slide_ended

enum Stance { STANDING, CROUCHING }
enum MovementState { IDLE, WALKING, JOGGING, SPRINTING, CROUCH_IDLE, CROUCH_WALKING, AIRBORNE, SLIDING }

@export var settings: MovementSettings
## Superfície usada quando o piso não define uma.
@export var default_surface: SurfaceProfile
@export var stamina: StaminaComponent
## Vida e lesões. Opcional: sem ele, quedas só emitem o sinal de dano.
@export var health: HealthComponent
## Nó que recebe a arfagem (olhar para cima/baixo). A guinada gira o corpo.
@export var head: Node3D
@export var collision_shape: CollisionShape3D

## Multiplicador externo de velocidade (ferimentos, pernas quebradas, etc.).
var external_speed_multiplier: float = 1.0
## Massa carregada em kg (inventário, mochila, arma). Afeta aceleração,
## frenagem, velocidade máxima, salto, força de empurrar e resistência.
var carried_mass: float = 0.0:
	set(value):
		carried_mass = maxf(value, 0.0)
## Desativa leitura de entrada (menus, inventário aberto, morte).
var input_enabled: bool = true
var look_enabled: bool = true

## Terceira pessoa: o corpo gira para a direção do movimento e a câmera orbita
## livre; primeira pessoa: o corpo fica travado na direção do olhar.
## Controlado pelo sistema de câmera.
var third_person: bool = false
## Velocidade de giro do corpo em terceira pessoa (graus/s).
var body_turn_speed_degrees: float = 540.0
## Desvio máximo entre a frente do corpo e a direção do deslocamento em
## terceira pessoa: o corpo conduz o movimento, então mudanças bruscas de
## direção viram curvas, com perda de velocidade.
var max_travel_offset_degrees: float = 35.0
## Multiplicador de velocidade imposto por ações (defesa, golpe carregado).
## Abaixo de 1 também impede a corrida.
var action_speed_multiplier: float = 1.0

var stance: Stance = Stance.STANDING
var movement_state: MovementState = MovementState.IDLE
var is_sprinting: bool = false
## Modo andar (alternado com a tecla de caminhada): limita ao passo de caminhada.
var is_walk_mode: bool = false
var is_sliding: bool = false
var current_surface: SurfaceProfile
var last_impact_speed: float = 0.0

var _gravity: float
var _drag_coefficient: float
var _capsule: CapsuleShape3D
var _current_height: float
var _pitch: float = 0.0
## Direção horizontal do olhar (independe do corpo em terceira pessoa).
var _view_yaw: float = 0.0
var _body_locked_to_view: bool = true
var _face_view_timer: float = 0.0
var _move_input: Vector2 = Vector2.ZERO
var _sprint_held: bool = false
var _jump_held: bool = false
var _jump_held_previous: bool = false
var _crouch_toggle_held_previous: bool = false
var _walk_toggle_held_previous: bool = false
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
var _floor_collider: Object = null
var _slide_normal: Vector3 = Vector3.UP
var _uphill_amount: float = 0.0
## Distância horizontal que ainda falta percorrer após subir um degrau antes
## de liberar a descida ativa (o centro do corpo precisa passar da quina).
var _step_up_clearance_remaining: float = 0.0
var _teleport_physics_frame: int = -1
var _collision_layer_backup: int = 0
var _material_surfaces: Dictionary = {}

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
## Metadado que associa um SurfaceProfile a um corpo do cenário.
const SURFACE_META := &"surface_profile"


func _ready() -> void:
	assert(settings != null, "PlayerController precisa de um MovementSettings.")
	assert(head != null and collision_shape != null, "PlayerController precisa de head e collision_shape.")
	if default_surface == null:
		default_surface = SurfaceProfile.new()
	current_surface = default_surface
	_view_yaw = rotation.y
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	_drag_coefficient = _gravity / (settings.terminal_velocity * settings.terminal_velocity)
	floor_max_angle = deg_to_rad(settings.max_floor_angle_degrees)
	floor_snap_length = settings.floor_snap_length
	floor_constant_speed = true
	floor_block_on_wall = true
	floor_stop_on_slope = true
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
	if health != null:
		fall_damage_taken.connect(func(amount: float, _impact: float) -> void: health.apply_fall_damage(amount))
		health.died.connect(_on_died)
		health.revived.connect(_on_revived)


func _process(delta: float) -> void:
	var look := GameInput.consume_look()
	if look_enabled and look != Vector2.ZERO:
		_view_yaw = wrapf(_view_yaw - look.x, -PI, PI)
		var limit := deg_to_rad(settings.max_pitch_degrees)
		_pitch = clampf(_pitch - look.y, -limit, limit)
	head.rotation.x = _pitch
	if is_dead():
		return
	if not third_person or _face_view_timer > 0.0:
		# Primeira pessoa: o corpo acompanha o olhar sem atraso. Logo após sair
		# da terceira pessoa ele gira rápido até alinhar e então trava.
		if _body_locked_to_view and not third_person:
			rotation.y = _view_yaw
		else:
			rotation.y = rotate_toward(rotation.y, _view_yaw, deg_to_rad(900.0) * delta)
			_body_locked_to_view = not third_person and absf(angle_difference(rotation.y, _view_yaw)) < deg_to_rad(1.0)
	else:
		_body_locked_to_view = false


func _physics_process(delta: float) -> void:
	_restore_collision_after_teleport()
	_read_input()
	_jumped_this_frame = false
	var was_grounded := _grounded

	_update_timers(delta, was_grounded)
	_update_body_yaw(delta)
	_update_stance(delta)
	_update_sprint(delta, was_grounded)
	_apply_gravity_and_drag(delta)
	_handle_jump(delta)
	if is_sliding:
		_apply_slide_control(delta)
	elif was_grounded:
		_apply_ground_movement(delta)
	else:
		_apply_air_movement(delta)

	var pre_move_transform := global_transform
	var pre_move_velocity := velocity
	move_and_slide()
	if was_grounded and not _jumped_this_frame and _is_blocked_by_low_obstacle(pre_move_transform, pre_move_velocity):
		if _try_step_up(pre_move_transform, pre_move_velocity, delta):
			# O degrau não deve consumir o momento horizontal.
			velocity.x = pre_move_velocity.x
			velocity.z = pre_move_velocity.z

	_floor_collider = null
	_step_up_clearance_remaining = maxf(_step_up_clearance_remaining \
			- Vector2(global_position.x - pre_move_transform.origin.x, global_position.z - pre_move_transform.origin.z).length(), 0.0)
	if was_grounded and not is_on_floor() and not _jumped_this_frame and pre_move_velocity.y <= 0.0 \
			and _step_up_clearance_remaining <= 0.0:
		_try_step_down()
	# A velocidade anterior ao movimento decide: ao contornar a quina de um
	# degrau, a colisão pode deixar a velocidade levemente para cima.
	_grounded = is_on_floor() or (was_grounded and not _jumped_this_frame \
			and pre_move_velocity.y <= 0.0 and _probe_ground())
	_update_slide(delta)
	_update_surface()
	_handle_collisions(pre_move_velocity, delta)
	_handle_landing(was_grounded, pre_move_velocity)
	_update_stride(delta)
	_update_movement_state()


# --- Entrada -----------------------------------------------------------------

func _read_input() -> void:
	if not input_enabled or is_dead():
		_move_input = Vector2.ZERO
		_sprint_held = false
		_jump_held = false
		_crouch_hold = false
		return
	_move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_sprint_held = Input.is_action_pressed("sprint")
	_jump_held_previous = _jump_held
	_jump_held = Input.is_action_pressed("jump")
	# As bordas de subida são detectadas aqui, e não com is_action_just_pressed,
	# para funcionar igualmente com teclado, gamepad e botões de toque
	# pressionados fora do passo de física.
	if _jump_held and not _jump_held_previous:
		_jump_buffer_timer = settings.jump_buffer_time
	var crouch_toggle_held := Input.is_action_pressed("crouch_toggle")
	if crouch_toggle_held and not _crouch_toggle_held_previous:
		_crouch_toggled = not _crouch_toggled
	_crouch_toggle_held_previous = crouch_toggle_held
	var walk_toggle_held := Input.is_action_pressed("walk_toggle")
	if walk_toggle_held and not _walk_toggle_held_previous:
		is_walk_mode = not is_walk_mode
	_walk_toggle_held_previous = walk_toggle_held
	_crouch_hold = Input.is_action_pressed("crouch_hold")


# --- Temporizadores ----------------------------------------------------------

func _update_timers(delta: float, grounded: bool) -> void:
	if grounded:
		_coyote_timer = settings.coyote_time
		_airborne_time = 0.0
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
		_airborne_time += delta
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_face_view_timer = maxf(_face_view_timer - delta, 0.0)
	_jump_cooldown_timer = maxf(_jump_cooldown_timer - delta, 0.0)
	_stagger_timer = maxf(_stagger_timer - delta, 0.0)


# --- Direção do corpo --------------------------------------------------------

## Em terceira pessoa o corpo gira, com velocidade limitada, para a direção em
## que está andando (relativa à câmera). Parado, mantém a direção.
func _update_body_yaw(delta: float) -> void:
	if not third_person or _face_view_timer > 0.0 or is_dead():
		return
	var wish := _get_wish_direction()
	if wish == Vector3.ZERO:
		return
	var target := atan2(-wish.x, -wish.z)
	# Correndo, o corpo vira mais devagar (momento): a curva fica aberta.
	var rate := deg_to_rad(body_turn_speed_degrees) * (0.45 if is_sprinting else 1.0)
	rotation.y = rotate_toward(rotation.y, target, rate * delta)


## Faz o corpo encarar a direção do olhar por `duration` segundos (ataques e
## interações em terceira pessoa).
func face_view_for(duration: float) -> void:
	_face_view_timer = maxf(_face_view_timer, duration)


func get_view_yaw() -> float:
	return _view_yaw


## Base horizontal do olhar (frente = -Z).
func get_view_basis() -> Basis:
	return Basis(Vector3.UP, _view_yaw)


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


# --- Corrida e resistência ---------------------------------------------------

func _update_sprint(delta: float, grounded: bool) -> void:
	# Em terceira pessoa o corpo encara o movimento: corre em qualquer direção.
	var moving_forward := _move_input.y < -0.5 or (third_person and _move_input.length() > 0.5)
	var allowed := _sprint_held and moving_forward and stance == Stance.STANDING and not is_sliding \
			and _stagger_timer <= 0.0 and (stamina == null or stamina.can_sprint()) \
			and get_leg_injury() < 0.5 and action_speed_multiplier >= 0.99
	if grounded:
		is_sprinting = allowed
	elif not allowed:
		# No ar mantém o estado de corrida (o momento já existe), mas permite cancelar.
		is_sprinting = false
	if is_sprinting and grounded and stamina != null:
		var drain := settings.sprint_stamina_drain * get_load_factor() * current_surface.stamina_multiplier \
				* (1.0 + settings.uphill_stamina_factor * _uphill_amount)
		if not stamina.drain(drain, delta):
			is_sprinting = false
	if stamina != null:
		stamina.is_moving = get_horizontal_speed() > 0.3


# --- Gravidade, arrasto e salto ----------------------------------------------

func _apply_gravity_and_drag(delta: float) -> void:
	if is_on_floor() and velocity.y <= 0.0:
		return
	velocity.y -= _gravity * delta
	# Arrasto aerodinâmico quadrático (F = ½ρCdA·v²), calibrado para que a
	# velocidade terminal seja a configurada: a = k·v², com k = g / vt².
	var speed := velocity.length()
	if speed > 0.0:
		var drag := minf(_drag_coefficient * speed * speed * delta, speed)
		velocity -= velocity / speed * drag


func _handle_jump(delta: float) -> void:
	if _jump_buffer_timer <= 0.0:
		return
	if stance == Stance.CROUCHING:
		# Saltar agachado faz o personagem se levantar, se houver espaço.
		_jump_buffer_timer = 0.0
		if can_stand_up():
			_crouch_toggled = false
		return
	if is_sliding or _coyote_timer <= 0.0 or _jump_cooldown_timer > 0.0 \
			or _current_height < settings.standing_height - 0.05:
		return
	var height_factor := pow(get_mass_factor(), settings.load_jump_exponent) * (1.0 - 0.6 * get_leg_injury())
	if stamina != null:
		var cost := settings.jump_stamina_cost * get_load_factor()
		if not stamina.try_consume(cost):
			var obtained := stamina.consume_partial(cost)
			height_factor *= lerpf(settings.exhausted_jump_factor, 1.0, obtained)
	var jump_speed := sqrt(2.0 * _gravity * settings.jump_height * height_factor)
	# Meio passo de gravidade compensa a integração discreta: a altura atingida
	# fica igual à altura física configurada.
	velocity.y = jump_speed - 0.5 * _gravity * delta
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_jumped_this_frame = true
	jumped.emit(jump_speed)


# --- Deslocamento no chão ----------------------------------------------------

func _apply_ground_movement(delta: float) -> void:
	var wish_direction := _get_wish_direction()
	var target_speed := 0.0
	_uphill_amount = 0.0
	if wish_direction != Vector3.ZERO:
		var turn_factor := 1.0
		if third_person and _face_view_timer <= 0.0:
			var steered := _steer_toward_facing(wish_direction)
			turn_factor = steered.w
			wish_direction = Vector3(steered.x, steered.y, steered.z)
		target_speed = get_target_speed() * _get_slope_multiplier(wish_direction) * turn_factor
	var target := wish_direction * target_speed

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var mass_factor := get_mass_factor()
	var speed_ratio := clampf(horizontal.length() / settings.sprint_speed, 0.0, 1.0)
	var acceleration := settings.ground_acceleration * mass_factor * lerpf(1.0, settings.acceleration_falloff, speed_ratio)
	var desired := _accelerate(horizontal, target, acceleration,
			settings.ground_deceleration * mass_factor, settings.ground_turn_friction * mass_factor, delta)

	# Círculo de atrito: a variação total de velocidade horizontal não pode
	# exceder o que o atrito entre calçado e piso permite neste passo.
	var change := desired - horizontal
	var max_change := current_surface.traction * _gravity * settings.traction_grip * delta
	if change.length() > max_change:
		change = change.normalized() * max_change
	horizontal += change

	# Pé plantado: sem comando e quase parado, o corpo para por completo.
	if target_speed <= 0.0:
		var snap := settings.stop_snap_speed * minf(current_surface.traction * current_surface.traction, 1.0)
		if horizontal.length() < snap:
			horizontal = Vector3.ZERO
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Terceira pessoa: o deslocamento segue a frente do corpo (que gira com
## velocidade limitada) e não a entrada crua. Retorna a direção (xyz) e o
## fator de velocidade da curva (w): curvas fechadas perdem velocidade e,
## quase parado, uma inversão de sentido gira o corpo no lugar antes de andar.
func _steer_toward_facing(wish_direction: Vector3) -> Vector4:
	var facing := -global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var angle := facing.signed_angle_to(wish_direction, Vector3.UP)
	var limit := deg_to_rad(max_travel_offset_degrees)
	var direction := facing.rotated(Vector3.UP, clampf(angle, -limit, limit))
	var factor := lerpf(1.0, 0.35, clampf((absf(angle) - deg_to_rad(30.0)) / deg_to_rad(120.0), 0.0, 1.0))
	if get_horizontal_speed() < 1.0 and absf(angle) > deg_to_rad(100.0):
		factor = 0.0
	return Vector4(direction.x, direction.y, direction.z, factor)


## Muda a velocidade em direção ao alvo como um corpo com peso:
## - mudança de direção até 100°: a velocidade CURVA (força centrípeta),
##   girando no máximo o que `turn_friction` (m/s² laterais) permite, e o
##   módulo acelera/freia separadamente. Correr e virar a câmera não "freia"
##   o corpo: só o que excede a aderência (círculo de atrito, depois) se perde;
## - inversão (> 100°): freia na direção antiga e acelera na nova.
func _accelerate(current: Vector3, target: Vector3, acceleration: float,
		deceleration: float, turn_friction: float, delta: float) -> Vector3:
	if target.length_squared() < 0.0001:
		return current.move_toward(Vector3.ZERO, deceleration * delta)
	var target_speed := target.length()
	var direction := target / target_speed
	var speed := current.length()
	if speed < 0.05:
		return direction * move_toward(speed, target_speed, acceleration * delta)
	var current_direction := current / speed
	var angle := current_direction.angle_to(direction)
	if angle > deg_to_rad(100.0):
		var along := current.dot(direction)
		var lateral := current - direction * along
		lateral = lateral.move_toward(Vector3.ZERO, turn_friction * delta)
		along = move_toward(along, target_speed, deceleration * delta)
		return direction * along + lateral
	var max_turn := turn_friction * delta / speed
	var turned := current_direction.slerp(direction, minf(1.0, max_turn / maxf(angle, 0.0001))).normalized()
	var rate := acceleration if speed < target_speed else deceleration
	return turned * move_toward(speed, target_speed, rate * delta)


## Velocidade desejada (m/s) para a entrada atual, antes do efeito da inclinação.
func get_target_speed() -> float:
	var strength := minf(_move_input.length(), 1.0)
	if strength <= 0.0:
		return 0.0
	var base: float
	var crouched := stance == Stance.CROUCHING or _current_height < settings.standing_height - 0.05
	if crouched:
		base = settings.crouch_speed * strength
	elif is_sprinting:
		base = settings.sprint_speed
	elif strength <= settings.analog_walk_threshold:
		base = settings.walk_speed * strength / settings.analog_walk_threshold
	elif is_walk_mode:
		base = settings.walk_speed
	else:
		var t := (strength - settings.analog_walk_threshold) / (1.0 - settings.analog_walk_threshold)
		base = lerpf(settings.walk_speed, settings.jog_speed, t)
	if is_walk_mode and not crouched:
		base = minf(base, settings.walk_speed)
	return base * _get_direction_multiplier() * external_speed_multiplier * action_speed_multiplier * _get_stagger_multiplier() \
			* get_load_speed_multiplier() * current_surface.speed_multiplier * (1.0 - 0.45 * get_leg_injury())


## Direção desejada no mundo, relativa ao olhar (não ao corpo).
func _get_wish_direction() -> Vector3:
	if _move_input == Vector2.ZERO:
		return Vector3.ZERO
	var view := get_view_basis()
	return (view.x * _move_input.x + view.z * _move_input.y).normalized()


func _get_direction_multiplier() -> float:
	if third_person:
		return 1.0 # o corpo sempre encara o movimento
	var input := _move_input.normalized()
	var total := absf(input.x) + absf(input.y)
	if total <= 0.0:
		return 1.0
	var forward_part := maxf(-input.y, 0.0)
	var backward_part := maxf(input.y, 0.0) * settings.backward_multiplier
	var side_part := absf(input.x) * settings.strafe_multiplier
	return (forward_part + backward_part + side_part) / total


## Subida: perda proporcional ao seno da inclinação na direção do movimento.
## Descida: leve ganho em rampas suaves e contenção em rampas íngremes.
## Atravessar a encosta na horizontal não altera a velocidade.
func _get_slope_multiplier(wish_direction: Vector3) -> float:
	var floor_normal := get_floor_normal() if is_on_floor() else Vector3.UP
	var downhill := Vector3(floor_normal.x, 0.0, floor_normal.z)
	# downhill tem módulo igual ao seno da inclinação e aponta morro abaixo.
	var along := wish_direction.dot(downhill)
	if along < 0.0:
		_uphill_amount = -along
		return 1.0 - _uphill_amount * settings.uphill_penalty
	return 1.0 + settings.downhill_bonus * along - settings.downhill_penalty * along * along


func _get_stagger_multiplier() -> float:
	if _stagger_timer <= 0.0 or _stagger_duration <= 0.0:
		return 1.0
	var t := _stagger_timer / _stagger_duration
	return lerpf(1.0, settings.stagger_min_speed_multiplier, t)


# --- Ar e encostas -----------------------------------------------------------

## No ar o corpo conserva o momento. O controle permite pequenas correções,
## sem superar a velocidade que já existia nem a de trote.
func _apply_air_movement(delta: float) -> void:
	var wish_direction := _get_wish_direction()
	if wish_direction == Vector3.ZERO:
		return
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed_cap := maxf(horizontal.length(), settings.jog_speed)
	var desired := horizontal + wish_direction * settings.air_acceleration * delta
	if desired.length() > speed_cap:
		desired = desired.normalized() * speed_cap
	velocity.x = desired.x
	velocity.z = desired.z


## Escorregando, o jogador só consegue se desviar de lado ou acompanhar a
## descida; a componente morro acima do comando é descartada.
func _apply_slide_control(delta: float) -> void:
	var wish_direction := _get_wish_direction()
	if wish_direction == Vector3.ZERO:
		return
	var downhill := Vector3(_slide_normal.x, 0.0, _slide_normal.z).normalized()
	var uphill_part := wish_direction.dot(-downhill)
	if uphill_part > 0.0:
		wish_direction += downhill * uphill_part
	velocity += wish_direction * settings.slide_control_acceleration * delta


## Detecta contato com encosta acima da inclinação caminhável e aplica atrito
## cinético: a aceleração resultante é g·(senθ − μ·cosθ), como num plano real.
func _update_slide(delta: float) -> void:
	var was_sliding := is_sliding
	is_sliding = false
	if not _grounded:
		var max_slide_angle := deg_to_rad(settings.max_slide_angle_degrees)
		for i in get_slide_collision_count():
			var collision := get_slide_collision(i)
			var normal := collision.get_normal()
			var angle := normal.angle_to(Vector3.UP)
			if angle > floor_max_angle and angle < max_slide_angle:
				is_sliding = true
				_slide_normal = normal
				_floor_collider = collision.get_collider()
				break
	if is_sliding:
		var surface := _resolve_surface(_floor_collider)
		var tangent := velocity - _slide_normal * velocity.dot(_slide_normal)
		var friction := surface.traction * settings.slide_friction_factor * _gravity * _slide_normal.y * delta
		tangent = tangent.move_toward(Vector3.ZERO, friction)
		if tangent.length() > settings.max_slide_speed:
			tangent = tangent.normalized() * settings.max_slide_speed
		velocity = tangent
	if is_sliding != was_sliding:
		if is_sliding:
			slide_started.emit()
		else:
			slide_ended.emit()


# --- Superfície --------------------------------------------------------------

func _update_surface() -> void:
	if _floor_collider == null and is_on_floor():
		for i in get_slide_collision_count():
			var collision := get_slide_collision(i)
			if collision.get_normal().angle_to(Vector3.UP) <= floor_max_angle:
				_floor_collider = collision.get_collider()
				break
	if _floor_collider == null:
		return # No ar mantém a última superfície (aterrissagem e salto seguinte).
	var surface := _resolve_surface(_floor_collider)
	if surface != current_surface:
		current_surface = surface
		surface_changed.emit(surface)


func _resolve_surface(collider: Object) -> SurfaceProfile:
	if collider == null:
		return default_surface
	if collider.has_meta(SURFACE_META):
		var profile := collider.get_meta(SURFACE_META) as SurfaceProfile
		if profile != null:
			return profile
	var material: PhysicsMaterial = null
	if collider is StaticBody3D:
		material = (collider as StaticBody3D).physics_material_override
	elif collider is RigidBody3D:
		material = (collider as RigidBody3D).physics_material_override
	if material == null:
		return default_surface
	var key := material.get_instance_id()
	if not _material_surfaces.has(key):
		_material_surfaces[key] = default_surface.with_traction(material.friction)
	return _material_surfaces[key]


# --- Sonda de chão -----------------------------------------------------------

## Verdadeiro quando o personagem está apoiado: no chão ou descendo um degrau
## (a cápsula contorna a quina e por alguns quadros não toca o piso).
func is_grounded() -> bool:
	return _grounded


func _probe_ground() -> bool:
	var origin := global_position + Vector3.UP * 0.05
	var reach := settings.max_step_height + GROUND_PROBE_EXTRA
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * reach, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or (hit["normal"] as Vector3).angle_to(Vector3.UP) > floor_max_angle:
		return false
	_floor_collider = hit["collider"]
	return true


# --- Degraus -----------------------------------------------------------------

## Descida ativa de degrau: ao perder o piso andando (sem saltar), procura um
## piso caminhável até max_step_height abaixo do centro e assenta o corpo nele,
## como a perna que procura o degrau de baixo. Sem isso, em velocidade de trote
## o corpo "voa" sobre cada degrau de uma escada.
func _try_step_down() -> void:
	var origin := global_position + Vector3.UP * 0.05
	var reach := settings.max_step_height + 0.05
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * reach, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or (hit["normal"] as Vector3).angle_to(Vector3.UP) > floor_max_angle:
		return
	var drop := global_position.y - (hit["position"] as Vector3).y
	if drop <= 0.005:
		return
	# A cápsula desce até tocar algo: o piso de baixo ou, se o centro ainda não
	# passou da quina, a própria quina (o próximo quadro completa a descida).
	_motion_params.from = global_transform
	_motion_params.motion = Vector3.DOWN * drop
	if PhysicsServer3D.body_test_motion(get_rid(), _motion_params, _motion_result):
		global_position += _motion_result.get_travel()
	else:
		global_position += _motion_params.motion
	velocity.y = minf(velocity.y, 0.0)
	apply_floor_snap()


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
	_step_up_clearance_remaining = settings.capsule_radius + 0.05
	stepped_up.emit(step_height)
	return true


# --- Colisões ----------------------------------------------------------------

func _handle_collisions(pre_move_velocity: Vector3, delta: float) -> void:
	var strongest_wall_impact := 0.0
	var wall_normal := Vector3.ZERO
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if body != null:
			_interact_with_rigid_body(collision, body, pre_move_velocity, delta)
			continue
		var normal := collision.get_normal()
		# Paredes: superfícies quase verticais do cenário.
		if absf(normal.y) < 0.35:
			var flat_normal := Vector3(normal.x, 0.0, normal.z).normalized()
			var impact := -Vector3(pre_move_velocity.x, 0.0, pre_move_velocity.z).dot(flat_normal)
			if impact > strongest_wall_impact:
				strongest_wall_impact = impact
				wall_normal = flat_normal
	if strongest_wall_impact >= settings.wall_impact_min_speed:
		wall_impact.emit(strongest_wall_impact, wall_normal)
		if strongest_wall_impact >= settings.wall_stagger_speed:
			var severity := clampf(inverse_lerp(settings.wall_stagger_speed, settings.sprint_speed * 1.5, strongest_wall_impact), 0.0, 1.0)
			_start_stagger(lerpf(0.3, settings.stagger_max_duration, severity))
	if is_on_ceiling() and pre_move_velocity.y >= settings.head_bump_min_speed:
		velocity.y = minf(velocity.y, 0.0)
		head_bumped.emit(pre_move_velocity.y)


## Empurra objetos com força limitada (pela força das pernas e pelo atrito
## disponível: no gelo não se empurra nada pesado) e aplica o peso do corpo
## sobre aquilo em que o personagem está pisando.
func _interact_with_rigid_body(collision: KinematicCollision3D, body: RigidBody3D,
		pre_move_velocity: Vector3, delta: float) -> void:
	if body.freeze:
		return
	var normal := collision.get_normal()
	var contact_offset := collision.get_position() - body.global_position
	if normal.y > 0.7:
		body.apply_force(Vector3.DOWN * get_total_mass() * _gravity, contact_offset)
		return
	var push_direction := Vector3(-normal.x, 0.0, -normal.z)
	if push_direction.length_squared() < 0.0001:
		return
	push_direction = push_direction.normalized()
	# As pernas empurram pela intenção (direção e velocidade desejadas), não só
	# pela velocidade do instante: encostado na caixa o corpo quase para a cada
	# choque, mas continua fazendo força nela, como uma pessoa empurrando.
	var push_speed := Vector3(pre_move_velocity.x, 0.0, pre_move_velocity.z).dot(push_direction)
	var wish := _get_wish_direction()
	if wish != Vector3.ZERO:
		push_speed = maxf(push_speed, get_target_speed() * maxf(wish.dot(push_direction), 0.0))
	if push_speed <= 0.05:
		return
	var body_speed := body.linear_velocity.dot(push_direction)
	if body_speed >= push_speed:
		return
	var max_force := minf(settings.max_push_force, current_surface.traction * get_total_mass() * _gravity)
	var effort := clampf(push_speed / settings.jog_speed, 0.25, 1.0)
	var impulse := max_force * effort * delta
	impulse = minf(impulse, (push_speed - body_speed) * body.mass)
	body.apply_impulse(push_direction * impulse, contact_offset)


# --- Aterrissagem ------------------------------------------------------------

func _handle_landing(was_grounded: bool, pre_move_velocity: Vector3) -> void:
	if was_grounded or not _grounded:
		return
	# O impacto é a componente da velocidade normal ao piso: cair numa rampa
	# ou chegar ao fim de uma encosta escorregando dói menos que bater de frente.
	var floor_normal := get_floor_normal() if is_on_floor() else Vector3.UP
	var impact := maxf(-pre_move_velocity.dot(floor_normal), 0.0)
	last_impact_speed = impact
	_jump_cooldown_timer = settings.jump_cooldown
	landed.emit(impact)

	if impact > settings.stagger_impact_speed:
		var severity := clampf(inverse_lerp(settings.stagger_impact_speed, settings.lethal_impact_speed, impact), 0.0, 1.0)
		_start_stagger(lerpf(0.25, settings.stagger_max_duration, severity))
		# Parte da velocidade horizontal é absorvida pelas pernas.
		velocity.x *= lerpf(0.7, 0.2, severity)
		velocity.z *= lerpf(0.7, 0.2, severity)

	var damage := calculate_fall_damage(impact)
	if damage > 0.0:
		fall_damage_taken.emit(damage, impact)


func _start_stagger(duration: float) -> void:
	if duration > _stagger_timer:
		_stagger_duration = duration
		_stagger_timer = duration


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
		footstep.emit(clampf(speed / settings.sprint_speed, 0.1, 1.0), _left_foot_next, current_surface)
		_left_foot_next = not _left_foot_next


## Comprimento do passo para a velocidade atual: a cadência e a amplitude da
## passada crescem juntas, como na marcha humana.
func get_stride_length() -> float:
	if stance == Stance.CROUCHING:
		return settings.crouch_stride
	var speed := get_horizontal_speed()
	if speed <= settings.jog_speed:
		var t := clampf(inverse_lerp(settings.walk_speed, settings.jog_speed, speed), 0.0, 1.0)
		return lerpf(settings.walk_stride, settings.jog_stride, t)
	var t := clampf(inverse_lerp(settings.jog_speed, settings.sprint_speed, speed), 0.0, 1.0)
	return lerpf(settings.jog_stride, settings.sprint_stride, t)


# --- Estado ------------------------------------------------------------------

func _update_movement_state() -> void:
	var new_state: MovementState
	var speed := get_horizontal_speed()
	var moving := speed > 0.2
	if is_sliding:
		new_state = MovementState.SLIDING
	elif not _grounded and _airborne_time > 0.08:
		new_state = MovementState.AIRBORNE
	elif stance == Stance.CROUCHING:
		new_state = MovementState.CROUCH_WALKING if moving else MovementState.CROUCH_IDLE
	elif not moving:
		new_state = MovementState.IDLE
	elif is_sprinting:
		new_state = MovementState.SPRINTING
	elif speed > settings.walk_speed + 0.25:
		new_state = MovementState.JOGGING
	else:
		new_state = MovementState.WALKING
	if new_state != movement_state:
		movement_state = new_state
		movement_state_changed.emit(movement_state)


func get_total_mass() -> float:
	return settings.body_mass + carried_mass


## Razão massa do corpo / massa total: com força das pernas constante, a
## aceleração disponível cai na mesma proporção em que a massa sobe.
func get_mass_factor() -> float:
	return settings.body_mass / get_total_mass()


## Inverso do fator de massa (≥ 1): multiplica custos de resistência.
func get_load_factor() -> float:
	return get_total_mass() / settings.body_mass


func get_load_speed_multiplier() -> float:
	var t := clampf(inverse_lerp(settings.load_free_mass, settings.load_max_mass, carried_mass), 0.0, 1.0)
	return lerpf(1.0, settings.load_max_speed_multiplier, t)


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


## Fase do ciclo de marcha completo (dois passos), de 0 a 1: 0 = contato do pé
## esquerdo, 0,5 = contato do pé direito. Sincroniza as animações de locomoção.
func get_gait_phase() -> float:
	return (0.5 if _left_foot_next else 0.0) + 0.5 * get_stride_phase()


func get_leg_injury() -> float:
	return health.leg_injury if health != null else 0.0


func is_dead() -> bool:
	return health != null and health.is_dead


func _on_died() -> void:
	is_sprinting = false
	look_enabled = false


func _on_revived() -> void:
	look_enabled = true


func is_left_foot_next() -> bool:
	return _left_foot_next


func get_current_height() -> float:
	return _current_height


func get_pitch() -> float:
	return _pitch


func get_slide_normal() -> Vector3:
	return _slide_normal


func is_recovering_from_impact() -> bool:
	return _stagger_timer > 0.0


## Define a orientação da visão (radianos). Útil para spawn e cutscenes.
func set_view_rotation(yaw: float, pitch: float) -> void:
	_view_yaw = wrapf(yaw, -PI, PI)
	rotation.y = _view_yaw
	_body_locked_to_view = true
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
	is_sliding = false
	_step_up_clearance_remaining = 0.0
	reset_physics_interpolation()


func _restore_collision_after_teleport() -> void:
	if _teleport_physics_frame >= 0 and Engine.get_physics_frames() >= _teleport_physics_frame + 2:
		collision_layer = _collision_layer_backup
		_teleport_physics_frame = -1
