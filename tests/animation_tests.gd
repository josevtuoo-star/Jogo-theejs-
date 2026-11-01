extends Node
## Testes automatizados do sistema de animação em primeira pessoa e dos
## sistemas que ele sincroniza (vida, interação, combate e morte).
##   godot --headless --path . --fixed-fps 60 res://tests/animation_test_runner.tscn
## Filtro: ... -- --only=attack

const GYM_SCENE := "res://scenes/test/movement_test_gym.tscn"
const ACTIONS := [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"jump",
		&"crouch_toggle", &"crouch_hold", &"walk_toggle", &"attack", &"interact"]
const YAW_TOWARD_POSITIVE_Z := PI
const DT := 1.0 / 60.0

var _gym: Node3D
var _player: PlayerController
var _health: HealthComponent
var _animator: FirstPersonAnimator
var _skeleton: Skeleton3D
var _camera: Camera3D
var _combat: MeleeCombat
var _interaction: InteractionComponent
var _death: PlayerDeath
var _viewmodel: ViewmodelMotion
var _right_hand: int
var _failures: Array[String] = []
var _checks: int = 0
var _current_test: String = ""


func _ready() -> void:
	_gym = (load(GYM_SCENE) as PackedScene).instantiate()
	add_child(_gym)
	_player = _gym.get_node("Player")
	_health = _player.health
	_animator = _player.get_node("Head/CameraEffects/Camera3D/ViewModel/FPArms")
	_skeleton = _animator.skeleton
	_camera = _player.get_node("Head/CameraEffects/Camera3D")
	_viewmodel = _player.get_node("Head/CameraEffects/Camera3D/ViewModel")
	_combat = _player.get_node("Combat")
	_interaction = _player.get_node("Interaction")
	_death = _player.get_node("Death")
	_right_hand = _skeleton.find_bone("RightHand")
	await _frames(10)

	var tests: Array[Callable] = [
		_test_rig_and_library,
		_test_ik_pose_precision,
		_test_idle_without_motion,
		_test_gait_phase_sync,
		_test_speed_blend_amplitude,
		_test_crouch_follows_body_height,
		_test_air_and_landing,
		_test_hurt_reactions,
		_test_leg_injury_limp,
		_test_interaction_contact_frame,
		_test_light_attack_hit_frame,
		_test_heavy_attack_charge,
		_test_punch_rigid_body,
		_test_punch_wall_recoil,
		_test_damage_zone,
		_test_death_and_respawn,
		_test_viewmodel_sway,
		_test_touch_attack_button,
		_test_animator_performance,
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


func _reset(position: Vector3, yaw: float, pitch: float = 0.0) -> void:
	_release_all()
	if _player._crouch_toggled:
		await _hold(&"crouch_toggle", 2)
	if _player.is_walk_mode:
		await _hold(&"walk_toggle", 2)
	if _health.is_dead:
		_death.respawn(Transform3D(Basis.IDENTITY, position))
	_health.revive()
	_player.teleport(position + Vector3.UP * 0.02)
	_player.set_view_rotation(yaw, pitch)
	_player.stamina.current = _player.stamina.max_stamina
	_player.stamina.is_exhausted = false
	_player.external_speed_multiplier = 1.0
	_player.carried_mass = 0.0
	await _frames(60)


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)


## Posição do punho direito no espaço do esqueleto (câmera, sem o balanço secundário).
func _hand() -> Vector3:
	return _skeleton.get_bone_global_pose(_right_hand).origin


# --- Rig ---------------------------------------------------------------------

func _test_rig_and_library() -> void:
	_begin("Rig, malha e biblioteca")
	_check(_skeleton.get_bone_count() == 19, "19 ossos (%d)" % _skeleton.get_bone_count())
	var expected := ["idle", "walk", "jog", "sprint", "crouch_idle", "crouch_walk", "limp_walk", "jump", "fall",
			"land_soft", "land_hard", "hurt_light", "hurt_heavy", "interact", "guard", "attack_light",
			"attack_heavy", "impact_recoil", "death"]
	var missing := expected.filter(func(n: String) -> bool: return not _animator.has_animation(n))
	_check(missing.is_empty(), "todas as %d animações presentes %s" % [expected.size(), missing])
	var mesh: MeshInstance3D = _skeleton.get_node("ArmsMesh")
	_check(mesh.skin != null and mesh.skin.get_bind_count() == 19, "malha com skin ligada aos 19 ossos")
	_check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "braços não projetam sombra")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	var hand_world := _skeleton.global_transform * _hand()
	_check(_camera.is_position_in_frustum(hand_world), "mão direita visível na câmera em repouso")


func _test_ik_pose_precision() -> void:
	_begin("Precisão da IK: o punho chega à posição de autoria")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	_animator.trigger_guard(5.0)
	await _frames(90)
	# Guarda: punho direito em (0,120; -0,172; -0,33) + elevação de 0,05.
	var expected := Vector3(0.120, -0.122, -0.33)
	var error := _hand().distance_to(expected)
	# A guarda tem um balanço respiratório de 6 mm; a IK em si é exata.
	_check(error < 0.008, "erro de posição na guarda: %.1f mm (inclui 6 mm de respiração)" % (error * 1000.0))
	_animator.trigger_guard(0.0)
	await _frames(60)


# --- Locomoção ---------------------------------------------------------------

func _test_idle_without_motion() -> void:
	_begin("Parado: respiração, sem balanço de passada")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	var weights := _animator.get_layer_weights()
	_check(weights["move"] < 0.01, "peso da locomoção parado: %.3f" % weights["move"])
	var low := 1.0
	var high := -1.0
	for i in 200:
		await _frames(1)
		low = minf(low, _hand().y)
		high = maxf(high, _hand().y)
	var breath := (high - low) * 1000.0
	_check(breath > 3.0 and breath < 12.0, "respiração move as mãos %.1f mm" % breath)


## O braço direito deve estar à frente exatamente nos contatos do pé esquerdo
## e atrás nos contatos do pé direito (marcha contralateral), passo a passo.
func _test_gait_phase_sync() -> void:
	_begin("Sincronia braços × passada física")
	for sprinting in [false, true]:
		await _reset(Vector3(30.0, 0.0, -35.0), YAW_TOWARD_POSITIVE_Z)
		var left_contacts: Array[float] = []
		var right_contacts: Array[float] = []
		var on_step := func(_intensity: float, is_left: bool, _surface: SurfaceProfile) -> void:
			(left_contacts if is_left else right_contacts).append(_hand().z)
		Input.action_press(&"move_forward")
		if sprinting:
			Input.action_press(&"sprint")
		await _frames(70)
		_player.footstep.connect(on_step)
		await _frames(150)
		_player.footstep.disconnect(on_step)
		_release_all()
		var label := "correndo" if sprinting else "trotando"
		_check(left_contacts.size() >= 3 and right_contacts.size() >= 3,
				"%s: %d contatos esquerdos e %d direitos" % [label, left_contacts.size(), right_contacts.size()])
		var forward_at_left: float = left_contacts.max() if not left_contacts.is_empty() else 0.0
		var back_at_right: float = right_contacts.min() if not right_contacts.is_empty() else 0.0
		_check(forward_at_left < back_at_right - 0.03,
				"%s: mão direita à frente em todo contato esquerdo (z máx %.3f) e atrás em todo direito (z mín %.3f)" % [label, forward_at_left, back_at_right])


func _test_speed_blend_amplitude() -> void:
	_begin("Amplitude do balanço cresce com a velocidade (andar < trotar < correr)")
	var amplitudes := {}
	for mode in ["andar", "trotar", "correr"]:
		await _reset(Vector3(30.0, 0.0, -35.0), YAW_TOWARD_POSITIVE_Z)
		if mode == "andar":
			await _hold(&"walk_toggle", 2)
		Input.action_press(&"move_forward")
		if mode == "correr":
			Input.action_press(&"sprint")
		await _frames(80)
		var low := 1.0
		var high := -1.0
		for i in 90:
			await _frames(1)
			low = minf(low, _hand().z)
			high = maxf(high, _hand().z)
		amplitudes[mode] = high - low
		_release_all()
	_check(amplitudes["andar"] < amplitudes["trotar"] and amplitudes["trotar"] < amplitudes["correr"],
			"amplitude: andar %.0f mm, trotar %.0f mm, correr %.0f mm" % [amplitudes["andar"] * 1000.0, amplitudes["trotar"] * 1000.0, amplitudes["correr"] * 1000.0])


func _test_crouch_follows_body_height() -> void:
	_begin("Agachar: peso da animação acompanha a altura real da cápsula")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	var standing_y := _hand().y
	await _hold(&"crouch_toggle", 2)
	await _frames(5)
	var settings := _player.settings
	var expected := (settings.standing_height - _player.get_current_height()) / (settings.standing_height - settings.crouch_height)
	var weight: float = _animator.get_layer_weights()["crouch"]
	_check(absf(weight - expected) < 0.001 and weight > 0.05 and weight < 0.95,
			"no meio da transição: peso %.3f = altura do corpo %.3f" % [weight, expected])
	await _frames(40)
	_check(is_equal_approx(_animator.get_layer_weights()["crouch"], 1.0), "agachado: peso 1")
	_check(_hand().y < standing_y - 0.01, "mãos mais baixas agachado (%.3f → %.3f)" % [standing_y, _hand().y])
	await _hold(&"crouch_toggle", 2)
	await _frames(40)


# --- Ar e impactos -----------------------------------------------------------

func _test_air_and_landing() -> void:
	_begin("Salto, queda e aterrissagem")
	await _reset(Vector3(30.0, 0.0, 10.0), YAW_TOWARD_POSITIVE_Z)
	await _hold(&"jump", 3)
	await _frames(15)
	_check(_animator.get_layer_weights()["air"] > 0.5, "peso aéreo no salto: %.2f" % _animator.get_layer_weights()["air"])
	await _frames(60)
	_check(not _animator.is_playing(FirstPersonAnimator.SLOT_LAND) or _animator.current_animation(FirstPersonAnimator.SLOT_LAND) == &"land_soft",
			"salto comum: no máximo aterrissagem suave")
	await _reset(Vector3(30.0, 0.0, 10.0), YAW_TOWARD_POSITIVE_Z)
	_player.teleport(Vector3(30.0, 6.0, 10.0))
	var saw_fall := false
	var landed := [false]
	var on_land := func(_impact: float) -> void: landed[0] = true
	_player.landed.connect(on_land)
	while not landed[0]:
		await _frames(1)
		saw_fall = saw_fall or (_animator.get_layer_weights()["air"] > 0.8 and _player.velocity.y < -5.0)
	_player.landed.disconnect(on_land)
	await _frames(2)
	_check(saw_fall, "queda de 6 m usa a pose de queda")
	_check(_animator.current_animation(FirstPersonAnimator.SLOT_LAND) == &"land_hard", "queda de 6 m dispara aterrissagem forte")
	_check(not _animator.is_playing(FirstPersonAnimator.SLOT_HURT), "dano de queda não duplica com reação de ferimento")
	await _frames(60)


func _test_hurt_reactions() -> void:
	_begin("Ferimentos: reação proporcional ao dano")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	_health.apply_damage(6.0, &"golpe", Vector3.FORWARD)
	await _frames(2)
	_check(_animator.current_animation(FirstPersonAnimator.SLOT_HURT) == &"hurt_light", "dano 6 → reação leve")
	await _frames(40)
	_health.apply_damage(25.0, &"golpe", Vector3.LEFT)
	await _frames(2)
	_check(_animator.current_animation(FirstPersonAnimator.SLOT_HURT) == &"hurt_heavy", "dano 25 → reação forte")
	var kick := _viewmodel.get_rotation_offset().length()
	_check(kick > deg_to_rad(0.5), "braços levam tranco do impacto (%.1f°)" % rad_to_deg(kick))
	_check(is_equal_approx(_health.current, 69.0), "vida %.0f/100" % _health.current)


func _test_leg_injury_limp() -> void:
	_begin("Lesão nas pernas: mancar, mais lento, sem correr")
	await _reset(Vector3(30.0, 0.0, -35.0), YAW_TOWARD_POSITIVE_Z)
	_health.apply_fall_damage(36.0)
	_check(is_equal_approx(_health.leg_injury, 0.6), "lesão de %.0f%%" % (_health.leg_injury * 100.0))
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(120)
	var expected := _player.settings.jog_speed * (1.0 - 0.45 * _health.leg_injury)
	_check(not _player.is_sprinting, "não consegue correr com a perna ferida")
	_check(absf(_player.get_horizontal_speed() - expected) < 0.1, "velocidade %.2f m/s (esperado %.2f)" % [_player.get_horizontal_speed(), expected])
	_check(_animator.get_layer_weights()["limp"] > 0.4, "animação de mancar com peso %.2f" % _animator.get_layer_weights()["limp"])
	_release_all()


# --- Interação ---------------------------------------------------------------

func _test_interaction_contact_frame() -> void:
	_begin("Interação: o efeito acontece no quadro de contato da mão")
	var switch: LightSwitch = _gym.get_node("LightSwitchStation/SwitchPanel/Switch")
	var lamp: OmniLight3D = _gym.get_node("LightSwitchStation/Lamp")
	await _reset(Vector3(-3.0, 0.0, 3.2), 0.0, atan2(1.30 - 1.68, 1.2))
	_check(_interaction.focused == switch, "interruptor em foco a 1,2 m")
	var was_on := switch.is_on
	var toggled_frame := -1
	Input.action_press(&"interact")
	for frame in 50:
		await _frames(1)
		if frame == 2:
			Input.action_release(&"interact")
		if toggled_frame < 0 and switch.is_on != was_on:
			toggled_frame = frame
	_check(toggled_frame >= 22 and toggled_frame <= 28, "acendeu no quadro %d (contato da animação em 0,42 s ≈ quadro 25)" % toggled_frame)
	_check(lamp.visible == switch.is_on, "lâmpada acompanha o interruptor")
	await _reset(Vector3(-3.0, 0.0, 5.0), 0.0, atan2(1.30 - 1.68, 3.0))
	_check(_interaction.focused == null, "a 3 m está fora de alcance")
	var before := switch.toggle_count
	await _hold(&"interact", 3)
	await _frames(40)
	_check(switch.toggle_count == before, "fora de alcance nada acontece")


# --- Combate -----------------------------------------------------------------

func _face_dummy() -> TrainingDummy:
	var dummy: TrainingDummy = _gym.get_node("TrainingDummyStation/TrainingDummy")
	await _reset(Vector3(-5.0, 0.0, 9.95), 0.0)
	return dummy


func _test_light_attack_hit_frame() -> void:
	_begin("Soco rápido: dano no quadro de impacto da animação")
	var dummy := await _face_dummy()
	var hits_before := dummy.hits
	var stamina_before := _player.stamina.current
	var hit_frame := -1
	Input.action_press(&"attack")
	await _frames(2)
	Input.action_release(&"attack")
	for frame in 40:
		await _frames(1)
		if hit_frame < 0 and dummy.hits > hits_before:
			hit_frame = frame
		if frame == 4:
			await _hold(&"attack", 2)
	_check(dummy.hits == hits_before + 1, "um acerto, mesmo apertando de novo durante o golpe (%d)" % (dummy.hits - hits_before))
	_check(hit_frame >= 4 and hit_frame <= 10, "acerto no quadro %d (evento em 0,12 s)" % hit_frame)
	_check(is_equal_approx(dummy.last_damage, _combat.light_damage), "dano %.0f" % dummy.last_damage)
	_check(stamina_before - _player.stamina.current >= _combat.light_stamina_cost - 0.01, "consome resistência")
	_check(dummy.get_sway_angle() > 0.0, "boneco balança com o golpe")
	_check(_animator.get_layer_weights()["guard"] > 0.3, "braços em guarda após o ataque")


func _test_heavy_attack_charge() -> void:
	_begin("Golpe carregado: segura a preparação e bate mais forte")
	var dummy := await _face_dummy()
	await _frames(150)
	var hits_before := dummy.hits
	Input.action_press(&"attack")
	await _frames(70)
	_check(_animator.current_animation(FirstPersonAnimator.SLOT_ACTION) == &"attack_heavy", "animação de golpe carregado")
	_check(_animator.is_holding(FirstPersonAnimator.SLOT_ACTION), "preparação mantida enquanto segura")
	_check(dummy.hits == hits_before, "nenhum dano durante a carga")
	Input.action_release(&"attack")
	await _frames(25)
	var expected := lerpf(_combat.heavy_min_damage, _combat.heavy_max_damage, (70.0 * DT - _combat.charge_threshold) / _combat.full_charge_time)
	_check(dummy.hits == hits_before + 1, "acerta ao soltar")
	_check(absf(dummy.last_damage - expected) < 1.5 and dummy.last_damage > _combat.light_damage,
			"dano %.1f (esperado ~%.1f, maior que o soco rápido)" % [dummy.last_damage, expected])
	await _frames(60)


func _test_punch_rigid_body() -> void:
	_begin("Soco derruba caixa de cima de um bloco (impulso físico)")
	# Golpe quase horizontal numa caixa de 5 kg sobre o bloco de 300 kg (1,2 m).
	# Um soco de cima para baixo numa caixa no chão apenas a prende contra o piso
	# (o atrito anula a componente horizontal), como na realidade.
	var crate: RigidBody3D = _gym.get_node("PhysicsProps/Crate5kg")
	var block: RigidBody3D = _gym.get_node("PhysicsProps/Block300kg")
	var top := block.global_position + Vector3(0.0, 0.6 + 0.226, 0.0)
	crate.global_transform = Transform3D(Basis.IDENTITY, top)
	crate.linear_velocity = Vector3.ZERO
	crate.angular_velocity = Vector3.ZERO
	await _reset(Vector3(top.x, 0.0, top.z + 0.9), 0.0)
	_player.set_view_rotation(0.0, -atan2(_camera.global_position.y - top.y, 0.9))
	await _frames(10)
	var start := crate.global_position
	await _hold(&"attack", 2)
	await _frames(60)
	var moved := crate.global_position.distance_to(start)
	_check(not _combat.last_hit.is_empty() and _combat.last_hit["target"] == crate, "o alvo atingido foi a caixa")
	# Estimativa: impulso horizontal menos o atrito gerado pela componente
	# vertical do golpe, depois deslizamento com desaceleração μ·g (μ = 0,75).
	var direction: Vector3 = _combat.last_hit.get("direction", Vector3.FORWARD)
	var horizontal := Vector2(direction.x, direction.z).length() * _combat.light_impulse
	var vertical := -direction.y * _combat.light_impulse
	var speed := (horizontal - 0.75 * vertical) / crate.mass
	var expected := speed * speed / (2.0 * 0.75 * 9.81)
	_check(moved > expected * 0.5 and moved < expected * 2.0,
			"caixa de 5 kg deslocada %.2f m (estimativa física %.2f m)" % [moved, expected])


func _test_punch_wall_recoil() -> void:
	_begin("Soco na parede: a mão é rebatida")
	await _reset(Vector3(0.0, 0.0, -19.3), 0.0)
	var obstacle := [false]
	var on_obstacle := func(_point: Vector3) -> void: obstacle[0] = true
	_combat.hit_obstacle.connect(on_obstacle)
	await _hold(&"attack", 2)
	await _frames(12)
	_combat.hit_obstacle.disconnect(on_obstacle)
	_check(obstacle[0], "impacto em superfície rígida detectado")
	_check(_animator.current_animation(FirstPersonAnimator.SLOT_ACTION) == &"impact_recoil", "animação de recuo da mão")
	await _frames(40)


# --- Perigos, morte e renascer -----------------------------------------------

func _test_damage_zone() -> void:
	_begin("Arame farpado: dano contínuo, lentidão e reação")
	await _reset(Vector3(8.0, 0.0, 5.5), YAW_TOWARD_POSITIVE_Z)
	var hurt_seen := false
	Input.action_press(&"move_forward")
	for i in 90:
		await _frames(1)
		hurt_seen = hurt_seen or _animator.is_playing(FirstPersonAnimator.SLOT_HURT)
		if _player.global_position.z > 8.0:
			Input.action_release(&"move_forward")
	_check(_health.current < 100.0, "perdeu vida no arame (%.0f)" % _health.current)
	_check(is_equal_approx(_player.external_speed_multiplier, 0.5), "preso no arame: velocidade pela metade")
	_check(hurt_seen, "reação de ferimento ao tocar o arame")
	Input.action_press(&"move_forward")
	await _frames(150)
	Input.action_release(&"move_forward")
	_check(is_equal_approx(_player.external_speed_multiplier, 1.0), "fora do arame: velocidade normal")


func _test_death_and_respawn() -> void:
	_begin("Morte: animação, câmera física e renascer")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	_health.apply_damage(500.0, &"golpe", Vector3.FORWARD)
	await _frames(2)
	_check(_health.is_dead, "personagem morto")
	_check(_animator.current_animation(FirstPersonAnimator.SLOT_DEATH) == &"death", "animação de morte")
	_check(_camera.top_level and _death.head_body != null, "câmera presa ao corpo físico da cabeça")
	Input.action_press(&"move_forward")
	await _frames(150)
	Input.action_release(&"move_forward")
	_check(_player.get_horizontal_speed() < 0.05, "sem controle depois de morto")
	_check(_camera.global_position.y < 0.4, "a visão caiu até o chão (%.2f m)" % _camera.global_position.y)
	_check(_death.can_respawn(), "renascer liberado após %.1f s" % _death.respawn_delay)
	var hud: PlayerHud = _gym.get_node("PlayerHud")
	_check(hud._death_panel.visible and hud._death_cause.text.contains("golpe"), "tela de morte com a causa: %s" % hud._death_cause.text)
	await _hold(&"interact", 3)
	await _frames(5)
	_check(not _health.is_dead and is_equal_approx(_health.current, 100.0), "renasceu com vida cheia")
	_check(not _camera.top_level and _camera.transform.is_equal_approx(Transform3D.IDENTITY), "câmera de volta à cabeça")
	_check(not _animator.is_playing(FirstPersonAnimator.SLOT_DEATH), "animação de morte encerrada")
	_check(not hud._death_panel.visible, "tela de morte fechada")
	Input.action_press(&"move_forward")
	await _frames(40)
	Input.action_release(&"move_forward")
	_check(_player.get_horizontal_speed() > 1.0, "controle restaurado")


# --- Movimento secundário, toque e desempenho --------------------------------

func _test_viewmodel_sway() -> void:
	_begin("Braços atrasam ao girar a visão e voltam")
	await _reset(Vector3(30.0, 0.0, -20.0), YAW_TOWARD_POSITIVE_Z)
	for i in 10:
		GameInput.add_look_radians(Vector2(0.05, 0.0))
		await _frames(1)
	var lag := _viewmodel.get_rotation_offset().y
	_check(lag > deg_to_rad(0.5), "girando para a direita, os braços ficam para trás (%.2f°)" % rad_to_deg(lag))
	await _frames(60)
	_check(absf(_viewmodel.get_rotation_offset().y) < deg_to_rad(0.1), "voltam ao centro ao parar (%.3f°)" % rad_to_deg(_viewmodel.get_rotation_offset().y))


func _test_touch_attack_button() -> void:
	_begin("Botões de toque ATACAR e USAR")
	var controls: TouchControls = _gym.get_node("TouchControlsLayer/TouchControls")
	controls.visible = true
	var dummy := await _face_dummy()
	await _frames(120)
	var hits_before := dummy.hits
	var button: TouchActionButton = controls.get_node("AttackButton")
	_send_touch(5, button.get_center_global(), true)
	await _frames(3)
	_send_touch(5, button.get_center_global(), false)
	await _frames(30)
	_check(dummy.hits == hits_before + 1, "toque rápido em ATACAR dá um soco")
	var use_button: TouchActionButton = controls.get_node("InteractButton")
	_send_touch(6, use_button.get_center_global(), true)
	await _frames(2)
	_check(Input.is_action_pressed(&"interact"), "USAR pressiona a ação de interagir")
	_send_touch(6, use_button.get_center_global(), false)
	controls.visible = false
	await _frames(30)


func _test_animator_performance() -> void:
	_begin("Desempenho do animador")
	await _reset(Vector3(30.0, 0.0, -35.0), YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	_animator.trigger_guard(10.0)
	_health.apply_fall_damage(12.0)
	var total := 0
	for i in 120:
		await _frames(1)
		total += _animator.last_update_usec
	_release_all()
	var average := total / 120.0
	print("  (média de %.0f µs por quadro com locomoção, mancar e guarda ativos)" % average)
	_check(average < 2000.0, "atualização média abaixo de 2 ms (%.0f µs)" % average)


func _send_touch(index: int, viewport_position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * viewport_position
	event.pressed = pressed
	get_viewport().push_input(event)
