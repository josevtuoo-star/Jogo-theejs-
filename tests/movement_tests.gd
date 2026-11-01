extends Node
## Testes automatizados da física do personagem em primeira pessoa.
##
## Executa a cena de calibração real (mesma física, mesmas cenas) e simula
## entrada pelo InputMap e por eventos de toque. Rodar com passo fixo:
##   godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
## Filtro opcional por nome de teste:
##   godot ... res://tests/test_runner.tscn -- --only=slope
## O processo termina com código 0 se todos os testes passarem.

const GYM_SCENE := "res://scenes/test/movement_test_gym.tscn"
const ACTIONS := [&"move_forward", &"move_back", &"move_left", &"move_right",
		&"sprint", &"jump", &"crouch_toggle", &"crouch_hold", &"walk_toggle"]
const YAW_TOWARD_POSITIVE_Z := PI
const YAW_TOWARD_POSITIVE_X := -PI * 0.5
const DT := 1.0 / 60.0
const G := 9.81

var _gym: Node3D
var _player: PlayerController
var _settings: MovementSettings
var _failures: Array[String] = []
var _checks: int = 0
var _current_test: String = ""


func _ready() -> void:
	_gym = (load(GYM_SCENE) as PackedScene).instantiate()
	add_child(_gym)
	_player = _gym.get_node("Player")
	_settings = _player.settings
	await _frames(10)

	var tests: Array[Callable] = [
		_test_jog_acceleration_and_braking,
		_test_speed_tiers_and_analog,
		_test_direction_multipliers,
		_test_sprint_acceleration_curve_and_stop,
		_test_sprint_turn_inertia,
		_test_sprint_and_exhaustion,
		_test_jump_height_and_cooldown,
		_test_crouch_and_ceiling,
		_test_stairs,
		_test_step_height_limit,
		_test_slope_uphill,
		_test_slope_downhill,
		_test_slope_idle_no_drift,
		_test_slope_steep_slide,
		_test_uphill_sprint_stamina,
		_test_surface_ice,
		_test_surface_mud,
		_test_carried_load,
		_test_air_drag_terminal_velocity,
		_test_fall_damage,
		_test_wall_impact,
		_test_head_bump,
		_test_push_props,
		_test_touch_controls,
	]
	var only := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")
	for test in tests:
		if only.is_empty() or test.get_method().contains(only):
			await test.call()

	print("")
	if _failures.is_empty():
		print("RESULTADO: %d verificações, todas passaram." % _checks)
		get_tree().quit(0)
	else:
		print("RESULTADO: %d de %d verificações falharam:" % [_failures.size(), _checks])
		for failure in _failures:
			print("  - " + failure)
		get_tree().quit(1)


# --- Utilidades --------------------------------------------------------------

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _begin(test_name: String) -> void:
	_current_test = test_name
	print("\n== " + test_name)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   " + description)
	else:
		print("  FALHA " + description)
		_failures.append("%s: %s" % [_current_test, description])


func _release_all() -> void:
	for action in ACTIONS:
		Input.action_release(action)


## Reposiciona o jogador em pé, parado, sem carga e com resistência cheia.
func _reset(position: Vector3, yaw: float) -> void:
	_release_all()
	if _player._crouch_toggled:
		await _hold(&"crouch_toggle", 2)
	if _player.is_walk_mode:
		await _hold(&"walk_toggle", 2)
	_player.teleport(position + Vector3.UP * 0.02)
	_player.set_view_rotation(yaw, 0.0)
	_player.stamina.current = _player.stamina.max_stamina
	_player.stamina.is_exhausted = false
	_player.external_speed_multiplier = 1.0
	_player.carried_mass = 0.0
	await _frames(45)


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)


## Quadros até a velocidade horizontal atingir o limiar (ou o limite).
func _frames_until_speed(threshold: float, limit: int) -> int:
	var count := 0
	while _player.get_horizontal_speed() < threshold and count < limit:
		await _frames(1)
		count += 1
	return count


## Solta o movimento e mede quadros e distância até parar por completo.
func _measure_stop(limit: int) -> Vector2:
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	var start := _player.global_position
	var count := 0
	while _player.get_horizontal_speed() > 0.0 and count < limit:
		await _frames(1)
		count += 1
	var distance := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	return Vector2(count, distance)


## Velocidade de impacto após cair h metros com arrasto quadrático:
## v² = vt²·(1 − e^(−2kh)), k = g/vt².
func _impact_with_drag(height: float) -> float:
	var vt := _settings.terminal_velocity
	var k := G / (vt * vt)
	return sqrt(vt * vt * (1.0 - exp(-2.0 * k * height)))


# --- Velocidade, aceleração e frenagem ---------------------------------------

func _test_jog_acceleration_and_braking() -> void:
	_begin("Trote: aceleração, velocidade de cruzeiro e frenagem sem deslizar")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward")
	await _frames(6)
	var early_speed := _player.get_horizontal_speed()
	_check(early_speed > 0.6 and early_speed < 1.3, "arranque responsivo e gradual: %.2f m/s após 0,1 s" % early_speed)
	await _frames(84)
	var cruise := _player.get_horizontal_speed()
	_check(absf(cruise - _settings.jog_speed) < 0.05, "trote %.2f m/s (esperado %.2f)" % [cruise, _settings.jog_speed])
	_check(_player.velocity.z > 0.0 and absf(_player.velocity.x) < 0.01, "desloca na direção do olhar")
	_check(_player.movement_state == PlayerController.MovementState.JOGGING, "estado JOGGING")
	var stop := await _measure_stop(120)
	_check(stop.x >= 10 and stop.x <= 22, "frenagem com inércia em %d quadros" % int(stop.x))
	_check(stop.y > 0.3 and stop.y < 0.8, "distância de parada %.2f m (cerca de meio passo)" % stop.y)
	var rest := _player.global_position
	await _frames(30)
	_check(rest.distance_to(_player.global_position) < 0.001, "parado não desliza (pé plantado)")


func _test_speed_tiers_and_analog() -> void:
	_begin("Perfis de velocidade: andar, trote analógico e modo andar")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward", 0.5)
	await _frames(60)
	var strength := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back").length()
	var expected := _settings.walk_speed * strength / _settings.analog_walk_threshold
	var analog := _player.get_horizontal_speed()
	_check(absf(analog - expected) < 0.05, "direcional parcial (%.2f) → %.2f m/s (esperado %.2f)" % [strength, analog, expected])
	_check(_player.movement_state == PlayerController.MovementState.WALKING, "estado WALKING")
	Input.action_press(&"move_forward", 0.85)
	await _frames(60)
	strength = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back").length()
	var t := (strength - _settings.analog_walk_threshold) / (1.0 - _settings.analog_walk_threshold)
	expected = lerpf(_settings.walk_speed, _settings.jog_speed, t)
	var mid := _player.get_horizontal_speed()
	_check(absf(mid - expected) < 0.05, "direcional %.2f → %.2f m/s entre andar e trote (esperado %.2f)" % [strength, mid, expected])
	Input.action_release(&"move_forward")
	await _hold(&"walk_toggle", 2)
	_check(_player.is_walk_mode, "tecla de caminhada ativa o modo andar")
	Input.action_press(&"move_forward")
	await _frames(60)
	var walk := _player.get_horizontal_speed()
	_check(absf(walk - _settings.walk_speed) < 0.05, "modo andar limita a %.2f m/s" % walk)
	Input.action_release(&"move_forward")
	await _hold(&"walk_toggle", 2)
	_check(not _player.is_walk_mode, "segundo toque volta ao trote")


func _test_direction_multipliers() -> void:
	_begin("Velocidade por direção (lado, trás)")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_back")
	await _frames(70)
	var backward := _player.get_horizontal_speed()
	Input.action_release(&"move_back")
	_check(absf(backward - _settings.jog_speed * _settings.backward_multiplier) < 0.05, "para trás %.2f m/s" % backward)
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_right")
	await _frames(70)
	var strafe := _player.get_horizontal_speed()
	Input.action_release(&"move_right")
	_check(absf(strafe - _settings.jog_speed * _settings.strafe_multiplier) < 0.05, "de lado %.2f m/s" % strafe)


func _test_sprint_acceleration_curve_and_stop() -> void:
	_begin("Corrida: curva de aceleração e parada com momento")
	await _reset(Vector3(30.0, 0.0, -35.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	var to_jog := await _frames_until_speed(_settings.jog_speed * 0.95, 200)
	var to_sprint := to_jog + await _frames_until_speed(_settings.sprint_speed * 0.95, 200)
	_check(to_jog < to_sprint - 10, "ganho de velocidade diminui perto do máximo (trote em %.2f s, corrida em %.2f s)" % [to_jog * DT, to_sprint * DT])
	_check(to_sprint * DT > 0.6 and to_sprint * DT < 1.3, "atinge 95%% da corrida em %.2f s" % (to_sprint * DT))
	await _frames(40)
	var sprint_speed := _player.get_horizontal_speed()
	_check(absf(sprint_speed - _settings.sprint_speed) < 0.05, "velocidade de corrida %.2f m/s" % sprint_speed)
	_check(_player.movement_state == PlayerController.MovementState.SPRINTING, "estado SPRINTING")
	var camera_effects: PlayerCameraEffects = _player.get_node("Head/CameraEffects")
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	await _frames(12)
	var braking_pitch := camera_effects.rotation.x
	await _frames(60)
	_check(braking_pitch > deg_to_rad(0.3), "ao frear, a cabeça é jogada para trás (%.2f°)" % rad_to_deg(braking_pitch))

	await _reset(Vector3(30.0, 0.0, -35.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(12)
	var accel_pitch := camera_effects.rotation.x
	_check(accel_pitch < -deg_to_rad(0.3), "ao arrancar, o tronco inclina para frente (%.2f°)" % rad_to_deg(accel_pitch))
	await _frames(90)
	var stop := await _measure_stop(180)
	_check(stop.y > 1.0 and stop.y < 2.0, "parada da corrida em %.2f m (%.2f s)" % [stop.y, stop.x * DT])


func _test_sprint_turn_inertia() -> void:
	_begin("Curva de 90° correndo vs trotando (inércia)")
	var results := {}
	for sprinting in [true, false]:
		await _reset(Vector3(30.0, 0.0, -35.0), YAW_TOWARD_POSITIVE_Z)
		Input.action_press(&"move_forward")
		if sprinting:
			Input.action_press(&"sprint")
		await _frames(110)
		var start := _player.global_position
		_player.set_view_rotation(YAW_TOWARD_POSITIVE_X, 0.0)
		var frames := 0
		while frames < 120:
			await _frames(1)
			frames += 1
			var v := Vector2(_player.velocity.x, _player.velocity.z)
			if v.length() > 0.5 and absf(v.angle_to(Vector2(1.0, 0.0))) < deg_to_rad(10.0):
				break
		var overshoot := _player.global_position.z - start.z
		results[sprinting] = Vector2(frames * DT, overshoot)
		_release_all()
	_check(results[true].x > 0.35 and results[true].x < 1.0, "correndo, alinha em %.2f s" % results[true].x)
	_check(results[false].x < results[true].x, "trotando, alinha mais rápido (%.2f s)" % results[false].x)
	_check(results[true].y > results[false].y + 0.3, "correndo, o momento leva o corpo mais longe na direção antiga (%.2f m vs %.2f m)" % [results[true].y, results[false].y])


func _test_sprint_and_exhaustion() -> void:
	_begin("Corrida, consumo de resistência e exaustão")
	await _reset(Vector3(30.0, 0.0, -35.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(90)
	_check(_player.stamina.current < _player.stamina.max_stamina - 10.0, "resistência consumida (%.1f)" % _player.stamina.current)
	_player.stamina.current = 5.0
	await _frames(40)
	_check(_player.stamina.is_exhausted, "entra em exaustão ao zerar")
	_check(not _player.is_sprinting, "corrida interrompida pela exaustão")
	await _frames(60)
	var tired_speed := _player.get_horizontal_speed()
	_check(absf(tired_speed - _settings.jog_speed) < 0.1, "volta ao trote (%.2f m/s)" % tired_speed)
	_release_all()
	await _frames(60 * 4)
	_check(not _player.stamina.is_exhausted, "recupera da exaustão em repouso (%.1f)" % _player.stamina.current)


# --- Salto e postura ---------------------------------------------------------

func _test_jump_height_and_cooldown() -> void:
	_begin("Salto: altura física, aterrissagem e intervalo entre saltos")
	await _reset(Vector3(30.0, 0.0, 10.0), YAW_TOWARD_POSITIVE_Z)
	var base_y := _player.global_position.y
	var max_y := base_y
	var landed_impacts: Array[float] = []
	var on_landed := func(impact: float) -> void: landed_impacts.append(impact)
	_player.landed.connect(on_landed)
	await _hold(&"jump", 3)
	for i in 90:
		await _frames(1)
		max_y = maxf(max_y, _player.global_position.y)
	var height := max_y - base_y
	_check(absf(height - _settings.jump_height) < 0.03, "altura do salto %.3f m (esperado %.2f)" % [height, _settings.jump_height])
	_check(landed_impacts.size() == 1, "um evento de aterrissagem")
	var expected_impact := sqrt(2.0 * G * _settings.jump_height)
	if landed_impacts.size() > 0:
		_check(absf(landed_impacts[0] - expected_impact) < 0.25, "impacto %.2f m/s (esperado %.2f)" % [landed_impacts[0], expected_impact])
	_check(_player.stamina.current < _player.stamina.max_stamina, "salto consome resistência")

	landed_impacts.clear()
	await _hold(&"jump", 3)
	var guard := 0
	while landed_impacts.is_empty() and guard < 120:
		await _frames(1)
		guard += 1
	await _hold(&"jump", 2)
	await _frames(2)
	_check(_player.is_on_floor() and _player.velocity.y <= 0.0, "salto bloqueado logo após aterrissar")
	await _frames(30)
	await _hold(&"jump", 2)
	await _frames(3)
	_check(_player.velocity.y > 1.0, "salto aceito após o intervalo")
	await _frames(90)
	_player.landed.disconnect(on_landed)


func _test_crouch_and_ceiling() -> void:
	_begin("Agachar, teto baixo e levantar automaticamente")
	await _reset(Vector3(-12.0, 0.0, -1.0), 0.0)
	Input.action_press(&"move_forward")
	await _frames(120)
	Input.action_release(&"move_forward")
	_check(_player.global_position.z > -3.0, "em pé não entra no túnel (z = %.2f)" % _player.global_position.z)

	await _reset(Vector3(-12.0, 0.0, -1.0), 0.0)
	await _hold(&"crouch_toggle", 2)
	await _frames(30)
	_check(_player.stance == PlayerController.Stance.CROUCHING, "postura agachada")
	_check(absf(_player.get_current_height() - _settings.crouch_height) < 0.01, "altura do corpo %.2f m" % _player.get_current_height())
	_check(absf(_player.head.position.y - (_settings.crouch_height - _settings.eye_offset_from_top)) < 0.01, "câmera acompanha a altura")
	Input.action_press(&"move_forward")
	await _frames(60)
	var crouch_speed := _player.get_horizontal_speed()
	_check(absf(crouch_speed - _settings.crouch_speed) < 0.05, "velocidade agachado %.2f m/s" % crouch_speed)
	while _player.global_position.z > -5.5:
		await _frames(1)
	Input.action_release(&"move_forward")
	await _hold(&"crouch_toggle", 2)
	await _frames(30)
	_check(_player.stance == PlayerController.Stance.CROUCHING, "não levanta sob o teto")
	_check(_player.get_current_height() < _settings.crouch_height + 0.01, "corpo não atravessa o teto")
	await _hold(&"jump", 2)
	await _frames(10)
	_check(_player.global_position.y < 0.05, "não salta sob o teto")
	Input.action_press(&"move_forward")
	var guard := 0
	while _player.global_position.z > -10.0 and guard < 600:
		await _frames(1)
		guard += 1
	await _frames(40)
	Input.action_release(&"move_forward")
	_check(_player.stance == PlayerController.Stance.STANDING, "levanta sozinho ao sair do túnel")
	_check(absf(_player.get_current_height() - _settings.standing_height) < 0.01, "altura em pé restaurada")


# --- Degraus e rampas --------------------------------------------------------

func _test_stairs() -> void:
	_begin("Escada de 18 cm")
	await _reset(Vector3(4.0, 0.0, 1.0), 0.0)
	var stepped := [0]
	var on_step := func(_height: float) -> void: stepped[0] += 1
	_player.stepped_up.connect(on_step)
	Input.action_press(&"move_forward")
	var guard := 0
	while _player.global_position.z > -4.5 and guard < 400:
		await _frames(1)
		guard += 1
	Input.action_release(&"move_forward")
	await _frames(30)
	_player.stepped_up.disconnect(on_step)
	_check(absf(_player.global_position.y - 1.44) < 0.03, "chega ao patamar (y = %.2f m)" % _player.global_position.y)
	_check(stepped[0] >= 6, "subiu degraus sem saltar (%d subidas)" % stepped[0])
	_check(guard < 400, "subida concluída em %.1f s" % (guard * DT))
	await _reset(Vector3(4.0, 1.44, -4.0), YAW_TOWARD_POSITIVE_Z)
	var airborne_frames := 0
	Input.action_press(&"move_forward")
	guard = 0
	while _player.global_position.z < 1.0 and guard < 400:
		await _frames(1)
		guard += 1
		if not _player.is_grounded():
			airborne_frames += 1
	Input.action_release(&"move_forward")
	_check(_player.global_position.y < 0.05, "desce até o chão")
	_check(airborne_frames <= 6, "desce colado aos degraus (%d quadros no ar)" % airborne_frames)

	# Sair pela lateral do patamar (1,44 m) é uma queda real, não um degrau.
	await _reset(Vector3(4.0, 1.44, -4.9), YAW_TOWARD_POSITIVE_X)
	var record := {"impact": -1.0, "speed": 0.0, "airborne": false}
	var on_landed := func(impact: float) -> void:
		record["impact"] = impact
		record["speed"] = _player.get_horizontal_speed()
	_player.landed.connect(on_landed)
	Input.action_press(&"move_forward")
	guard = 0
	while record["impact"] < 0.0 and guard < 240:
		await _frames(1)
		guard += 1
		if _player.movement_state == PlayerController.MovementState.AIRBORNE:
			record["airborne"] = true
	Input.action_release(&"move_forward")
	_player.landed.disconnect(on_landed)
	var expected := _impact_with_drag(1.44)
	_check(record["airborne"], "borda de 1,44 m vira queda (estado AIRBORNE)")
	_check(absf(record["impact"] - expected) < 0.4, "impacto %.2f m/s (esperado %.2f)" % [record["impact"], expected])


func _test_step_height_limit() -> void:
	_begin("Limite de altura de degrau")
	var cases := [[-3.0, 0.1, true], [-5.2, 0.2, true], [-7.4, 0.3, true], [-9.6, 0.45, false]]
	for case in cases:
		await _reset(Vector3(case[0], 0.0, 0.0), 0.0)
		Input.action_press(&"move_forward")
		# Anda até o centro do corpo ficar sobre o bloco (que vai de z -2,2 a -3,8).
		var guard := 0
		while _player.global_position.z > -3.0 and guard < 150:
			await _frames(1)
			guard += 1
		Input.action_release(&"move_forward")
		await _frames(30)
		var y := _player.global_position.y
		if case[2]:
			_check(absf(y - case[1]) < 0.03, "sobe bloco de %d cm (y = %.2f)" % [int(case[1] * 100.0), y])
		else:
			_check(y < 0.05, "não sobe bloco de %d cm sem saltar (y = %.2f)" % [int(case[1] * 100.0), y])


func _test_slope_uphill() -> void:
	_begin("Rampas em subida e inclinação máxima")
	var cases := [[9.0, 15.0], [12.0, 30.0], [15.0, 45.0], [18.0, 55.0]]
	for case in cases:
		await _reset(Vector3(case[0], 0.0, 1.0), 0.0)
		var top := sin(deg_to_rad(case[1])) * 6.0
		var max_y := 0.0
		var speeds: Array[float] = []
		Input.action_press(&"move_forward")
		for i in 360:
			await _frames(1)
			max_y = maxf(max_y, _player.global_position.y)
			if _player.global_position.y > top * 0.3 and _player.global_position.y < top * 0.7 and _player.is_on_floor():
				speeds.append(_player.velocity.length())
			if max_y > top - 0.02:
				break
		Input.action_release(&"move_forward")
		if case[1] < 46.0:
			_check(max_y > top - 0.05, "sobe rampa de %d° (altura %.2f de %.2f)" % [int(case[1]), max_y, top])
			var average := _average(speeds)
			var expected := _settings.jog_speed * (1.0 - sin(deg_to_rad(case[1])) * _settings.uphill_penalty)
			_check(absf(average - expected) < 0.12, "subida mais lenta em %d°: %.2f m/s (esperado %.2f)" % [int(case[1]), average, expected])
		else:
			_check(max_y < 0.6, "não escala rampa de %d° (altura %.2f)" % [int(case[1]), max_y])


func _test_slope_downhill() -> void:
	_begin("Rampas em descida: ganho em rampa suave, contenção em rampa íngreme")
	var cases := [[9.0, 15.0], [15.0, 45.0]]
	for case in cases:
		var angle: float = case[1]
		var top := sin(deg_to_rad(angle)) * 6.0
		var top_z := -1.0 - cos(deg_to_rad(angle)) * 6.0
		await _reset(Vector3(case[0], top, top_z - 0.7), YAW_TOWARD_POSITIVE_Z)
		var speeds: Array[float] = []
		var airborne := 0
		Input.action_press(&"move_forward")
		for i in 300:
			await _frames(1)
			var y := _player.global_position.y
			if y < top * 0.7 and y > top * 0.3:
				speeds.append(_player.velocity.length())
				if not _player.is_grounded():
					airborne += 1
			if y < 0.05 and _player.global_position.z > -0.5:
				break
		Input.action_release(&"move_forward")
		var along := sin(deg_to_rad(angle))
		var expected := _settings.jog_speed * (1.0 + _settings.downhill_bonus * along - _settings.downhill_penalty * along * along)
		var average := _average(speeds)
		_check(absf(average - expected) < 0.15, "descida de %d°: %.2f m/s (esperado %.2f)" % [int(angle), average, expected])
		_check(airborne == 0, "desce colado à rampa de %d° (%d quadros no ar)" % [int(angle), airborne])
		if angle < 20.0:
			_check(average > _settings.jog_speed, "rampa suave acelera a descida")
		else:
			_check(average < _settings.jog_speed, "rampa íngreme contém a descida")


func _test_slope_idle_no_drift() -> void:
	_begin("Parado em rampa de 30° e de 45° não escorrega")
	for case in [[12.0, 30.0], [15.0, 45.0]]:
		var angle: float = case[1]
		var z := -3.0
		var y := (-1.0 - z) * tan(deg_to_rad(angle))
		await _reset(Vector3(case[0], y + 0.05, z), 0.0)
		await _frames(30)
		var rest := _player.global_position
		await _frames(120)
		var drift := rest.distance_to(_player.global_position)
		_check(drift < 0.01 and _player.is_on_floor(), "deriva em 2 s na rampa de %d°: %.4f m" % [int(angle), drift])


func _test_slope_steep_slide() -> void:
	_begin("Encosta de 55°: escorrega com atrito, sem poder subir")
	var angle := deg_to_rad(55.0)
	var z := -3.0
	var surface_y := (-1.0 - z) * tan(angle)
	await _reset(Vector3(30.0, 0.0, 20.0), 0.0)
	var slid := [false]
	var on_slide := func() -> void: slid[0] = true
	_player.slide_started.connect(on_slide)
	_player.teleport(Vector3(18.0, surface_y + 0.7, z))
	Input.action_press(&"move_forward")
	var max_speed := 0.0
	var frames := 0
	var saw_state := false
	while frames < 240:
		await _frames(1)
		frames += 1
		if _player.is_sliding:
			max_speed = maxf(max_speed, _player.velocity.length())
			saw_state = saw_state or _player.movement_state == PlayerController.MovementState.SLIDING
		if _player.is_on_floor() and _player.global_position.y < 0.05:
			break
	Input.action_release(&"move_forward")
	_player.slide_started.disconnect(on_slide)
	_check(slid[0] and saw_state, "entra no estado SLIDING")
	_check(_player.global_position.y < 0.05 and _player.global_position.z > -1.2, "escorrega até a base mesmo tentando subir (z = %.2f)" % _player.global_position.z)
	# Aceleração ao longo da encosta: g·(senθ − μ·k·cosθ).
	var mu := _player.default_surface.traction * _settings.slide_friction_factor
	var acceleration := G * (sin(angle) - mu * cos(angle))
	var distance := surface_y / sin(angle)
	var expected_speed := minf(sqrt(2.0 * acceleration * distance), _settings.max_slide_speed)
	_check(max_speed > expected_speed * 0.75 and max_speed < expected_speed * 1.15,
			"velocidade ao escorregar %.2f m/s (modelo com atrito: %.2f; sem atrito seria %.2f)" % [max_speed, expected_speed, sqrt(2.0 * G * surface_y)])


func _test_uphill_sprint_stamina() -> void:
	_begin("Correr em subida gasta mais resistência")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(60)
	var flat_start := _player.stamina.current
	await _frames(30)
	var flat_rate := (flat_start - _player.stamina.current) / (30.0 * DT)
	_release_all()

	await _reset(Vector3(12.0, 0.0, 1.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	var top := sin(deg_to_rad(30.0)) * 6.0
	var samples := 0
	var used := 0.0
	var previous := _player.stamina.current
	for i in 240:
		await _frames(1)
		var y := _player.global_position.y
		if y > top * 0.2 and y < top * 0.8 and _player.is_on_floor():
			used += previous - _player.stamina.current
			samples += 1
		previous = _player.stamina.current
		if y > top - 0.05:
			break
	_release_all()
	var uphill_rate := used / (maxi(samples, 1) * DT)
	var expected_ratio := 1.0 + _settings.uphill_stamina_factor * sin(deg_to_rad(30.0))
	_check(absf(flat_rate - _settings.sprint_stamina_drain) < 0.5, "plano: %.1f/s" % flat_rate)
	_check(absf(uphill_rate / flat_rate - expected_ratio) < 0.15, "subida de 30°: %.1f/s (%.2fx; esperado %.2fx)" % [uphill_rate, uphill_rate / flat_rate, expected_ratio])


# --- Superfícies e carga -----------------------------------------------------

func _test_surface_ice() -> void:
	_begin("Gelo: aderência baixa limita arranque, frenagem e curvas")
	await _reset(Vector3(-32.0, 0.02, 3.0), YAW_TOWARD_POSITIVE_Z)
	_check(_player.current_surface.id == &"gelo", "superfície detectada: %s" % _player.current_surface.id)
	var traction_limit := _player.current_surface.traction * G * _settings.traction_grip
	Input.action_press(&"move_forward")
	await _frames(60)
	var after_one_second := _player.get_horizontal_speed()
	_check(absf(after_one_second - traction_limit) < 0.1, "após 1 s: %.2f m/s (limite de atrito %.2f m/s²)" % [after_one_second, traction_limit])
	await _frames(90)
	var speed := _player.get_horizontal_speed()
	var stop := await _measure_stop(600)
	var expected := speed * speed / (2.0 * traction_limit)
	_check(absf(stop.y - expected) < 0.25, "desliza %.2f m até parar a %.2f m/s (esperado %.2f)" % [stop.y, speed, expected])
	await _frames(10)


func _test_surface_mud() -> void:
	_begin("Lama: passada mais curta e mais esforço")
	await _reset(Vector3(20.0, 0.02, 15.0), YAW_TOWARD_POSITIVE_Z)
	_check(_player.current_surface.id == &"lama", "superfície detectada: %s" % _player.current_surface.id)
	Input.action_press(&"move_forward")
	await _frames(70)
	var speed := _player.get_horizontal_speed()
	var expected := _settings.jog_speed * _player.current_surface.speed_multiplier
	_check(absf(speed - expected) < 0.05, "trote na lama %.2f m/s (esperado %.2f)" % [speed, expected])
	Input.action_press(&"sprint")
	await _frames(40)
	var start := _player.stamina.current
	await _frames(30)
	var rate := (start - _player.stamina.current) / (30.0 * DT)
	_release_all()
	var expected_rate := _settings.sprint_stamina_drain * _player.current_surface.stamina_multiplier
	_check(absf(rate - expected_rate) < 0.6, "corrida na lama gasta %.1f/s (esperado %.1f)" % [rate, expected_rate])


func _test_carried_load() -> void:
	_begin("Carga de 40 kg: aceleração, velocidade e salto")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward")
	await _frames(9)
	var unloaded := _player.get_horizontal_speed()
	_release_all()
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	_player.carried_mass = 40.0
	var load_multiplier := _player.get_load_speed_multiplier()
	Input.action_press(&"move_forward")
	await _frames(9)
	var loaded := _player.get_horizontal_speed()
	await _frames(90)
	var speed := _player.get_horizontal_speed()
	_release_all()
	_check(absf(speed - _settings.jog_speed * load_multiplier) < 0.05, "trote carregado %.2f m/s (multiplicador %.2f)" % [speed, load_multiplier])
	# Mesma força das pernas sobre massa maior: a = F/m.
	var ratio := loaded / unloaded
	_check(absf(ratio - _player.get_mass_factor()) < 0.05, "arranque após 0,15 s: %.2f contra %.2f m/s (razão %.2f; m_corpo/m_total = %.2f)" % [loaded, unloaded, ratio, _player.get_mass_factor()])
	await _frames(40)
	var base_y := _player.global_position.y
	var max_y := base_y
	await _hold(&"jump", 3)
	for i in 70:
		await _frames(1)
		max_y = maxf(max_y, _player.global_position.y)
	var expected := _settings.jump_height * pow(_player.get_mass_factor(), _settings.load_jump_exponent)
	_check(absf((max_y - base_y) - expected) < 0.03, "salto carregado %.2f m (esperado %.2f)" % [max_y - base_y, expected])


# --- Ar, queda e impactos ----------------------------------------------------

func _test_air_drag_terminal_velocity() -> void:
	_begin("Queda longa: arrasto do ar e velocidade terminal")
	await _reset(Vector3(30.0, 0.0, 20.0), 0.0)
	_player.teleport(Vector3(30.0, 400.0, 20.0))
	await _frames(1)
	var start_frame := Engine.get_physics_frames()
	await _frames(360)
	var elapsed := (Engine.get_physics_frames() - start_frame + 1) * DT
	var vt := _settings.terminal_velocity
	var expected := vt * tanh(G * elapsed / vt)
	var speed := -_player.velocity.y
	_check(absf(speed - expected) < 1.0, "após %.1f s: %.1f m/s (modelo %.1f; sem arrasto seria %.1f)" % [elapsed, speed, expected, G * elapsed])
	_check(speed < vt, "abaixo da velocidade terminal (%.0f m/s)" % vt)
	_player.teleport(Vector3(30.0, 0.0, 20.0))
	await _frames(30)


func _test_fall_damage() -> void:
	_begin("Queda livre, impacto e dano")
	var cases := [[1.0, false], [3.0, false], [6.0, true], [12.0, true], [18.0, true]]
	var results := {}
	for case in cases:
		var height: float = case[0]
		await _reset(Vector3(30.0, 0.0, 20.0), 0.0)
		var record := {"impact": -1.0, "damage": 0.0}
		var on_landed := func(impact: float) -> void: record["impact"] = impact
		var on_damage := func(amount: float, _impact: float) -> void: record["damage"] = amount
		_player.landed.connect(on_landed)
		_player.fall_damage_taken.connect(on_damage)
		_player.teleport(Vector3(30.0, height, 20.0))
		var guard := 0
		while record["impact"] < 0.0 and guard < 400:
			await _frames(1)
			guard += 1
		_player.landed.disconnect(on_landed)
		_player.fall_damage_taken.disconnect(on_damage)
		var expected := _impact_with_drag(height)
		_check(absf(record["impact"] - expected) < 0.3, "queda de %.0f m: impacto %.2f m/s (esperado %.2f)" % [height, record["impact"], expected])
		if case[1]:
			_check(record["damage"] > 0.0, "queda de %.0f m causa dano (%.1f)" % [height, record["damage"]])
			_check(_player.is_recovering_from_impact(), "aterrissagem forte reduz a mobilidade")
		else:
			_check(record["damage"] == 0.0, "queda de %.0f m não causa dano" % height)
		results[height] = record["damage"]
	_check(results[18.0] >= _settings.lethal_fall_damage, "queda de 18 m é letal (%.1f)" % results[18.0])
	_check(results[12.0] > results[6.0], "dano cresce com a altura")


func _test_wall_impact() -> void:
	_begin("Impacto contra parede")
	var impacts: Array[float] = []
	var on_impact := func(speed: float, _normal: Vector3) -> void: impacts.append(speed)
	_player.wall_impact.connect(on_impact)
	await _reset(Vector3(10.0, 0.0, -13.0), 0.0)
	Input.action_press(&"move_forward")
	await _frames(240)
	_release_all()
	_check(impacts.size() == 1, "trotando contra a parede: %d impacto registrado" % impacts.size())
	_check(not _player.is_recovering_from_impact(), "trote não faz cambalear")
	impacts.clear()
	await _reset(Vector3(10.0, 0.0, -11.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	var guard := 0
	while impacts.is_empty() and guard < 300:
		await _frames(1)
		guard += 1
	var recovering := _player.is_recovering_from_impact()
	await _frames(30)
	_release_all()
	_player.wall_impact.disconnect(on_impact)
	_check(impacts.size() >= 1 and absf(impacts[0] - _settings.sprint_speed) < 0.3, "correndo: impacto de %.2f m/s" % (impacts[0] if impacts.size() > 0 else 0.0))
	_check(recovering, "impacto em corrida faz cambalear")
	_check(_player.global_position.z > -19.8 + _settings.capsule_radius - 0.01, "a parede bloqueia o corpo (z = %.2f)" % _player.global_position.z)


func _test_head_bump() -> void:
	_begin("Cabeça bate na viga ao saltar")
	await _reset(Vector3(0.0, 0.0, 14.0), 0.0)
	var bumps: Array[float] = []
	var on_bump := func(speed: float) -> void: bumps.append(speed)
	_player.head_bumped.connect(on_bump)
	var max_y := 0.0
	await _hold(&"jump", 3)
	for i in 80:
		await _frames(1)
		max_y = maxf(max_y, _player.global_position.y)
	_player.head_bumped.disconnect(on_bump)
	var limit := 2.15 - _settings.standing_height
	_check(bumps.size() == 1, "batida de cabeça registrada (%s m/s)" % (str(snappedf(bumps[0], 0.01)) if bumps.size() > 0 else "-"))
	_check(max_y < limit + 0.02, "o salto é interrompido pela viga (pés a %.2f m, limite %.2f m)" % [max_y, limit])


# --- Objetos físicos e toque -------------------------------------------------

func _test_push_props() -> void:
	_begin("Empurrar objetos físicos conforme a massa")
	var crate: RigidBody3D = _gym.get_node("PhysicsProps/Crate5kg")
	var heavy: RigidBody3D = _gym.get_node("PhysicsProps/Block300kg")
	var crate_start := crate.global_position
	var heavy_start := heavy.global_position
	await _reset(Vector3(crate_start.x, 0.0, crate_start.z + 2.5), 0.0)
	Input.action_press(&"move_forward")
	await _frames(150)
	Input.action_release(&"move_forward")
	await _frames(30)
	var crate_moved := crate_start.distance_to(crate.global_position)
	_check(crate_moved > 1.0, "caixa de 5 kg é empurrada (%.2f m)" % crate_moved)

	await _reset(Vector3(heavy_start.x, 0.0, heavy_start.z + 2.5), 0.0)
	Input.action_press(&"move_forward")
	await _frames(150)
	Input.action_release(&"move_forward")
	await _frames(30)
	var heavy_moved := heavy_start.distance_to(heavy.global_position)
	_check(heavy_moved < 0.1, "bloco de 300 kg não se move (%.3f m)" % heavy_moved)
	_check(_player.global_position.z > heavy_start.z + 0.6, "jogador é bloqueado pelo bloco pesado")

	await _reset(Vector3(heavy_start.x, 1.3, heavy.global_position.z), 0.0)
	await _frames(60)
	_check(_player.is_on_floor() and _player.global_position.y > 1.1, "fica de pé sobre o bloco (y = %.2f)" % _player.global_position.y)


func _test_touch_controls() -> void:
	_begin("Controles de toque: direcional, visão e botões")
	var controls: TouchControls = _gym.get_node("TouchControlsLayer/TouchControls")
	controls.visible = true
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	var screen := controls.get_global_rect().size

	var start := Vector2(screen.x * 0.15, screen.y * 0.7)
	var stick_radius := (controls.get_node("Joystick") as TouchMoveStick).radius
	_send_touch(0, start, true)
	_send_drag(0, start + Vector2(0.0, -stick_radius * 0.4), Vector2(0.0, -stick_radius * 0.4))
	await _frames(60)
	_check(_player.get_horizontal_speed() > 0.3 and _player.get_horizontal_speed() < _settings.walk_speed + 0.05,
			"direcional pouco inclinado caminha (%.2f m/s)" % _player.get_horizontal_speed())
	_send_drag(0, start + Vector2(0.0, -stick_radius), Vector2(0.0, -stick_radius * 0.6))
	await _frames(70)
	_check(Input.get_action_strength(&"move_forward") > 0.95, "direcional todo inclinado pressiona move_forward")
	_check(absf(_player.get_horizontal_speed() - _settings.jog_speed) < 0.1, "direcional todo inclinado trota (%.2f m/s)" % _player.get_horizontal_speed())
	_send_drag(0, start + Vector2(0.0, -stick_radius * 1.6), Vector2(0.0, -stick_radius * 0.6))
	await _frames(60)
	_check(_player.is_sprinting, "zona de corrida do direcional ativa sprint")

	var look_start := Vector2(screen.x * 0.7, screen.y * 0.4)
	var yaw_before := _player.rotation.y
	_send_touch(1, look_start, true)
	_send_drag(1, look_start + Vector2(100.0, 0.0), Vector2(100.0, 0.0))
	await _frames(3)
	var yaw_delta := wrapf(yaw_before - _player.rotation.y, -PI, PI)
	_check(absf(yaw_delta - 100.0 * GameInput.touch_sensitivity) < 0.01, "arrasto à direita gira a visão (%.3f rad)" % yaw_delta)
	_send_touch(1, look_start + Vector2(100.0, 0.0), false)

	var jump_button: TouchActionButton = controls.get_node("JumpButton")
	_send_touch(2, jump_button.get_center_global(), true)
	await _frames(3)
	_send_touch(2, jump_button.get_center_global(), false)
	await _frames(3)
	_check(_player.velocity.y > 0.5, "botão PULAR faz saltar com o direcional ativo")

	_send_touch(0, start, false)
	await _frames(90)
	_check(Input.get_action_strength(&"move_forward") == 0.0 and not Input.is_action_pressed(&"sprint"), "soltar o direcional libera as ações")
	await _frames(60)

	var crouch_button: TouchActionButton = controls.get_node("CrouchButton")
	_send_touch(3, crouch_button.get_center_global(), true)
	await _frames(2)
	_send_touch(3, crouch_button.get_center_global(), false)
	await _frames(30)
	_check(_player.stance == PlayerController.Stance.CROUCHING, "botão AGACHAR alterna a postura")
	_send_touch(3, crouch_button.get_center_global(), true)
	await _frames(2)
	_send_touch(3, crouch_button.get_center_global(), false)
	await _frames(30)
	_check(_player.stance == PlayerController.Stance.STANDING, "segundo toque levanta")
	controls.visible = false


## Os eventos são injetados em coordenadas de janela, como chegam do sistema;
## a viewport aplica a transformação de escala (resolução física -> base 1280x720).
func _send_touch(index: int, viewport_position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * viewport_position
	event.pressed = pressed
	get_viewport().push_input(event)


func _send_drag(index: int, viewport_position: Vector2, viewport_relative: Vector2) -> void:
	var to_window := get_viewport().get_final_transform()
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = to_window * viewport_position
	event.relative = to_window.basis_xform(viewport_relative)
	get_viewport().push_input(event)


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()
