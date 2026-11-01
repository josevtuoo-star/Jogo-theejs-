extends Node
## Testes automatizados do controlador em primeira pessoa.
##
## Executa a cena de calibração real (mesma física, mesmas cenas) e simula
## entrada pelo InputMap e por eventos de toque. Rodar com passo fixo:
##   godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
## O processo termina com código 0 se todos os testes passarem.

const GYM_SCENE := "res://scenes/test/movement_test_gym.tscn"
const ACTIONS := [&"move_forward", &"move_back", &"move_left", &"move_right",
		&"sprint", &"jump", &"crouch_toggle", &"crouch_hold"]
const YAW_TOWARD_POSITIVE_Z := PI

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
		_test_walk_acceleration_and_braking,
		_test_direction_multipliers,
		_test_sprint_and_exhaustion,
		_test_jump_height_and_cooldown,
		_test_crouch_and_ceiling,
		_test_stairs,
		_test_step_height_limit,
		_test_ramps,
		_test_fall_damage,
		_test_push_props,
		_test_touch_controls,
	]
	# Filtro opcional: godot ... res://tests/test_runner.tscn -- --only=stairs
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


## Reposiciona o jogador em pé, parado, com resistência cheia.
func _reset(position: Vector3, yaw: float) -> void:
	_release_all()
	if _player.stance == PlayerController.Stance.CROUCHING:
		if _player._crouch_toggled:
			Input.action_press(&"crouch_toggle")
			await _frames(2)
			Input.action_release(&"crouch_toggle")
	_player.teleport(position + Vector3.UP * 0.02)
	_player.set_view_rotation(yaw, 0.0)
	_player.stamina.current = _player.stamina.max_stamina
	_player.stamina.is_exhausted = false
	_player.external_speed_multiplier = 1.0
	await _frames(45)


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)


# --- Testes ------------------------------------------------------------------

func _test_walk_acceleration_and_braking() -> void:
	_begin("Caminhada: aceleração, velocidade de cruzeiro e frenagem")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward")
	await _frames(6)
	var early_speed := _player.get_horizontal_speed()
	_check(early_speed > 0.3 and early_speed < _settings.walk_speed * 0.6,
			"aceleração gradual: %.2f m/s após 0,1 s" % early_speed)
	await _frames(54)
	var cruise := _player.get_horizontal_speed()
	_check(absf(cruise - _settings.walk_speed) < 0.05, "velocidade de caminhada %.2f m/s (esperado %.2f)" % [cruise, _settings.walk_speed])
	_check(_player.velocity.z > 0.0 and absf(_player.velocity.x) < 0.01, "desloca na direção do olhar")
	_check(_player.movement_state == PlayerController.MovementState.WALKING, "estado WALKING")
	Input.action_release(&"move_forward")
	var stop_start := _player.global_position
	var frames_to_stop := 0
	while _player.get_horizontal_speed() > 0.01 and frames_to_stop < 120:
		await _frames(1)
		frames_to_stop += 1
	var stop_distance := _player.global_position.distance_to(stop_start)
	_check(frames_to_stop > 3 and frames_to_stop <= 18, "frenagem com inércia em %d quadros" % frames_to_stop)
	_check(stop_distance > 0.05 and stop_distance < 0.4, "distância de parada %.2f m" % stop_distance)


func _test_direction_multipliers() -> void:
	_begin("Velocidade por direção (frente, lado, trás)")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_back")
	await _frames(60)
	var backward := _player.get_horizontal_speed()
	Input.action_release(&"move_back")
	_check(absf(backward - _settings.walk_speed * _settings.backward_multiplier) < 0.05, "para trás %.2f m/s" % backward)
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_right")
	await _frames(60)
	var strafe := _player.get_horizontal_speed()
	Input.action_release(&"move_right")
	_check(absf(strafe - _settings.walk_speed * _settings.strafe_multiplier) < 0.05, "de lado %.2f m/s" % strafe)
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward", 0.5)
	await _frames(60)
	var half := _player.get_horizontal_speed()
	Input.action_release(&"move_forward")
	_check(half > 0.5 and half < _settings.walk_speed * 0.6, "entrada analógica parcial %.2f m/s" % half)


func _test_sprint_and_exhaustion() -> void:
	_begin("Corrida, consumo de resistência e exaustão")
	await _reset(Vector3(30.0, 0.0, -35.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(90)
	var sprint_speed := _player.get_horizontal_speed()
	_check(absf(sprint_speed - _settings.sprint_speed) < 0.08, "velocidade de corrida %.2f m/s" % sprint_speed)
	_check(_player.movement_state == PlayerController.MovementState.SPRINTING, "estado SPRINTING")
	_check(_player.stamina.current < _player.stamina.max_stamina - 10.0, "resistência consumida (%.1f)" % _player.stamina.current)
	_player.stamina.current = 5.0
	await _frames(40)
	_check(_player.stamina.is_exhausted, "entra em exaustão ao zerar")
	_check(not _player.is_sprinting, "corrida interrompida pela exaustão")
	await _frames(60)
	var tired_speed := _player.get_horizontal_speed()
	_check(absf(tired_speed - _settings.walk_speed) < 0.1, "volta a caminhar (%.2f m/s)" % tired_speed)
	_release_all()
	await _frames(60 * 4)
	_check(not _player.stamina.is_exhausted, "recupera da exaustão em repouso (%.1f)" % _player.stamina.current)


func _test_jump_height_and_cooldown() -> void:
	_begin("Salto: altura física, aterrissagem e intervalo entre saltos")
	await _reset(Vector3(30.0, 0.0, 10.0), YAW_TOWARD_POSITIVE_Z)
	var base_y := _player.global_position.y
	var max_y := base_y
	var landed_impacts: Array[float] = []
	var on_landed := func(impact: float) -> void: landed_impacts.append(impact)
	_player.landed.connect(on_landed)
	Input.action_press(&"jump")
	await _frames(3)
	Input.action_release(&"jump")
	for i in 90:
		await _frames(1)
		max_y = maxf(max_y, _player.global_position.y)
	var height := max_y - base_y
	_check(absf(height - _settings.jump_height) < 0.03, "altura do salto %.3f m (esperado %.2f)" % [height, _settings.jump_height])
	_check(landed_impacts.size() == 1, "um evento de aterrissagem")
	var expected_impact := sqrt(2.0 * 9.81 * _settings.jump_height)
	if landed_impacts.size() > 0:
		_check(absf(landed_impacts[0] - expected_impact) < 0.25, "impacto %.2f m/s (esperado %.2f)" % [landed_impacts[0], expected_impact])
	_check(_player.stamina.current < _player.stamina.max_stamina, "salto consome resistência")

	# Salto imediato após aterrissar deve ser bloqueado pelo intervalo mínimo.
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
	# Em pé, o teto de 1,35 m bloqueia a passagem.
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
	_check(guard < 400, "subida concluída em %.1f s" % (guard / 60.0))
	# Descer: o personagem deve se manter colado aos degraus, sem "voar".
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


func _test_step_height_limit() -> void:
	_begin("Limite de altura de degrau")
	var cases := [[-3.0, 0.1, true], [-5.2, 0.2, true], [-7.4, 0.3, true], [-9.6, 0.45, false]]
	for case in cases:
		await _reset(Vector3(case[0], 0.0, 0.0), 0.0)
		Input.action_press(&"move_forward")
		await _frames(90)
		Input.action_release(&"move_forward")
		await _frames(10)
		var y := _player.global_position.y
		if case[2]:
			_check(absf(y - case[1]) < 0.03, "sobe bloco de %d cm (y = %.2f)" % [int(case[1] * 100.0), y])
		else:
			_check(y < 0.05, "não sobe bloco de %d cm sem saltar (y = %.2f)" % [int(case[1] * 100.0), y])


func _test_ramps() -> void:
	_begin("Rampas e inclinação máxima")
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
			if not speeds.is_empty():
				var average := 0.0
				for s in speeds:
					average += s
				average /= speeds.size()
				var expected := _settings.walk_speed * (1.0 - sin(deg_to_rad(case[1])) * _settings.uphill_penalty)
				_check(absf(average - expected) < 0.12, "subida mais lenta em %d°: %.2f m/s (esperado %.2f)" % [int(case[1]), average, expected])
		else:
			_check(max_y < 0.6, "não escala rampa de %d° (altura %.2f)" % [int(case[1]), max_y])


func _test_fall_damage() -> void:
	_begin("Queda livre, impacto e dano")
	var cases := [[1.0, false], [3.0, false], [6.0, true], [12.0, true], [16.0, true]]
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
		var expected := sqrt(2.0 * 9.81 * height)
		_check(absf(record["impact"] - expected) < 0.3, "queda de %.0f m: impacto %.2f m/s (esperado %.2f)" % [height, record["impact"], expected])
		if case[1]:
			_check(record["damage"] > 0.0, "queda de %.0f m causa dano (%.1f)" % [height, record["damage"]])
		else:
			_check(record["damage"] == 0.0, "queda de %.0f m não causa dano" % height)
		results[height] = record["damage"]
		if height >= 6.0:
			_check(_player.is_recovering_from_landing(), "aterrissagem forte reduz a mobilidade")
	_check(results[16.0] >= _settings.lethal_fall_damage, "queda de 16 m é letal (%.1f)" % results[16.0])
	_check(results[12.0] > results[6.0], "dano cresce com a altura")


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

	# Pisar sobre o bloco pesado: deve sustentar o jogador.
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
	_send_touch(0, start, true)
	_send_drag(0, start + Vector2(0.0, -90.0), Vector2(0.0, -90.0))
	await _frames(60)
	_check(Input.get_action_strength(&"move_forward") > 0.95, "direcional pressiona move_forward")
	_check(absf(_player.get_horizontal_speed() - _settings.walk_speed) < 0.1, "direcional move o jogador (%.2f m/s)" % _player.get_horizontal_speed())
	_send_drag(0, start + Vector2(0.0, -140.0), Vector2(0.0, -50.0))
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
	await _frames(60)
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
