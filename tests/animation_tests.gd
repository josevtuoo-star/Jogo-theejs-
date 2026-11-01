extends Node
## Testes automatizados do corpo animado, da câmera em primeira/terceira
## pessoa, do ragdoll e dos sistemas sincronizados com a animação (vida,
## interação, combate e morte).
##   godot --headless --path . --fixed-fps 60 res://tests/animation_test_runner.tscn
## Filtro: ... -- --only=camera

const GYM_SCENE := "res://scenes/test/movement_test_gym.tscn"
const ACTIONS := [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"jump",
		&"crouch_toggle", &"crouch_hold", &"walk_toggle", &"attack", &"interact", &"toggle_camera", &"block"]
const YAW_TOWARD_POSITIVE_Z := PI
const DT := 1.0 / 60.0
## Área aberta do ginásio para corridas longas.
const OPEN_LANE := Vector3(30.0, 0.0, -35.0)

var _gym: Node3D
var _player: PlayerController
var _health: HealthComponent
var _body: BodyAnimator
var _skeleton: Skeleton3D
var _rig: PlayerCameraRig
var _camera: Camera3D
var _combat: MeleeCombat
var _interaction: InteractionComponent
var _death: PlayerDeath
var _bones: Dictionary = {}
var _failures: Array[String] = []
var _checks: int = 0
var _current_test: String = ""


func _ready() -> void:
	_gym = (load(GYM_SCENE) as PackedScene).instantiate()
	add_child(_gym)
	_player = _gym.get_node("Player")
	_health = _player.health
	_body = _player.get_node("Survivor")
	_skeleton = _body.skeleton
	_rig = _player.get_node("CameraRig")
	_camera = _rig.camera
	_combat = _player.get_node("Combat")
	_interaction = _player.get_node("Interaction")
	_death = _player.get_node("Death")
	for bone_name in ["root", "pelvis", "Head", "foot_l", "foot_r", "hand_l", "hand_r", "spine_03"]:
		_bones[bone_name] = _skeleton.find_bone(bone_name)
	await _frames(10)

	var tests: Array[Callable] = [
		_test_character_and_library,
		_test_idle_pose,
		_test_locomotion_upright,
		_test_gait_phase_sync,
		_test_stride_matches_animation,
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
		_test_camera_first_person_view,
		_test_camera_toggle_standing,
		_test_camera_toggle_walking,
		_test_camera_toggle_running,
		_test_camera_toggle_crouched,
		_test_camera_toggle_in_combat,
		_test_camera_walls,
		_test_camera_rotate_during_transition,
		_test_camera_animation_sync,
		_test_camera_touch_button,
		_test_touch_camera_never_attacks,
		_test_touch_move_and_look_together,
		_test_touch_attack_only_button,
		_test_touch_layout_and_sprint,
		_test_run_direction_change,
		_test_stop_deceleration,
		_test_crouch_and_stand,
		_test_obstacle_collision,
		_test_planted_feet,
		_test_defense,
		_test_attack_no_queue,
		_test_arm_reach,
		_test_ragdoll_death_and_respawn,
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


func _reset(position: Vector3, yaw: float, pitch: float = 0.0, third_person: bool = false) -> void:
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
	_rig.set_third_person(third_person)
	_rig.snap()
	await _frames(60)


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)


## Posição de um osso no mundo.
func _bone(bone_name: String) -> Vector3:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_bones[bone_name]).origin


## Altura de um osso acima dos pés do jogador.
func _bone_height(bone_name: String) -> float:
	return _bone(bone_name).y - _player.global_position.y


func _forward() -> Vector3:
	return -_player.global_basis.z


## Grava a câmera quadro a quadro: maior salto de posição (m), maior mudança
## de salto (aceleração por quadro, m) e maior giro por quadro (graus).
class CameraTrace:
	var positions: Array[Vector3] = []
	var bases: Array[Basis] = []

	func add(camera: Camera3D) -> void:
		positions.append(camera.global_position)
		bases.append(camera.global_basis.orthonormalized())

	func max_step() -> float:
		var result := 0.0
		for i in range(1, positions.size()):
			result = maxf(result, positions[i].distance_to(positions[i - 1]))
		return result

	func max_step_change() -> float:
		var result := 0.0
		for i in range(2, positions.size()):
			var a := positions[i - 1] - positions[i - 2]
			var b := positions[i] - positions[i - 1]
			result = maxf(result, (b - a).length())
		return result

	func max_turn_degrees() -> float:
		var result := 0.0
		for i in range(1, bases.size()):
			var q0 := bases[i - 1].get_rotation_quaternion()
			var q1 := bases[i].get_rotation_quaternion()
			result = maxf(result, rad_to_deg(q0.angle_to(q1)))
		return result


## Alterna a câmera e grava a transição inteira (mais alguns quadros).
func _toggle_and_trace(frames: int = 45) -> CameraTrace:
	var trace := CameraTrace.new()
	trace.add(_camera)
	_rig.toggle()
	for i in frames:
		await _frames(1)
		trace.add(_camera)
	return trace


## Câmera na terceira pessoa: atrás do jogador, acima e olhando na direção da vista.
func _camera_offset_local() -> Vector3:
	var view := _player.get_view_basis()
	return view.inverse() * (_camera.global_position - _player.global_position)


# --- Personagem --------------------------------------------------------------

func _test_character_and_library() -> void:
	_begin("Personagem, roupas, biblioteca e ragdoll")
	_check(_skeleton.get_bone_count() == 65, "esqueleto humano de 65 ossos (%d)" % _skeleton.get_bone_count())
	var expected := ["idle", "walk", "jog", "sprint", "crouch_idle", "crouch_walk", "jump_start", "fall", "land",
			"punch_jab", "punch_cross", "punch_hook", "hit_chest", "hit_head", "hit_knockback", "interact",
			"pickup", "push", "death", "get_up", "consume", "open_container", "walk_carry",
			"punch_hook_recover", "block_impact"]
	var missing := expected.filter(func(n: String) -> bool: return not _body.has_animation(n))
	_check(missing.is_empty(), "todas as %d animações presentes %s" % [expected.size(), missing])
	var meshes := {}
	for child in _skeleton.get_children():
		if child is MeshInstance3D:
			meshes[String(child.name)] = child
	for mesh_name in ["Shirt", "Arms", "Pants", "Boots", "Head", "Hair_Beard", "Hair_Buzzed", "Eyes"]:
		_check(meshes.has(mesh_name) and (meshes[mesh_name] as MeshInstance3D).skin != null, "malha %s com skin" % mesh_name)
	# Proporções naturais ("Regular"): ombros e quadris do esqueleto do pacote de roupas.
	var shoulders := _skeleton.get_bone_global_rest(_skeleton.find_bone("upperarm_l")).origin.distance_to(
			_skeleton.get_bone_global_rest(_skeleton.find_bone("upperarm_r")).origin)
	var hips := _skeleton.get_bone_global_rest(_skeleton.find_bone("thigh_l")).origin.distance_to(
			_skeleton.get_bone_global_rest(_skeleton.find_bone("thigh_r")).origin)
	_check(shoulders < 0.40 and hips < 0.20, "proporções naturais: ombros %.3f m, quadris %.3f m" % [shoulders, hips])
	var simulator := _skeleton.get_node_or_null("PhysicalBoneSimulator3D") as PhysicalBoneSimulator3D
	_check(simulator != null and simulator.get_child_count() == 16, "ragdoll com 16 ossos físicos")
	var mass := 0.0
	if simulator != null:
		for bone: PhysicalBone3D in simulator.get_children():
			mass += bone.mass
	_check(mass > 70.0 and mass < 90.0, "massa do ragdoll %.1f kg" % mass)
	_check(simulator != null and not simulator.active, "simulador desligado em vida (não interfere na pose)")
	for gait in ["walk", "jog", "sprint"]:
		var animation: Animation = _body.animation_player.get_animation(gait)
		_check(animation.has_meta(&"stride") and animation.has_meta(&"left_contact"), "%s com passada e contato medidos" % gait)


func _test_idle_pose() -> void:
	_begin("Parado: corpo em pé, pés no chão, cabeça acima da pélvis")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var head := _bone_height("Head")
	var pelvis := _bone_height("pelvis")
	_check(head > 1.45 and head < 1.80, "cabeça a %.2f m" % head)
	_check(pelvis > 0.80 and pelvis < 1.05, "pélvis a %.2f m" % pelvis)
	_check(absf(_bone_height("foot_l")) < 0.2 and absf(_bone_height("foot_r")) < 0.2,
			"pés no chão (%.2f / %.2f m)" % [_bone_height("foot_l"), _bone_height("foot_r")])
	_check(_body.get_layer_weights()["move"] < 0.01, "peso da locomoção parado: %.3f" % _body.get_layer_weights()["move"])


## Regressão: ossos sem trilha (root) eram misturados para a identidade e o
## corpo tombava 90° ao andar.
func _test_locomotion_upright() -> void:
	_begin("Locomoção: corpo em pé em todas as velocidades, nas duas câmeras")
	for third in [false, true]:
		for mode in ["andar", "trotar", "correr"]:
			await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z, 0.0, third)
			if mode == "andar":
				await _hold(&"walk_toggle", 2)
			Input.action_press(&"move_forward")
			if mode == "correr":
				Input.action_press(&"sprint")
			await _frames(60)
			var lowest_head := 10.0
			var lowest_pelvis := 10.0
			var farthest := 0.0
			for i in 60:
				await _frames(1)
				lowest_head = minf(lowest_head, _bone_height("Head"))
				lowest_pelvis = minf(lowest_pelvis, _bone_height("pelvis"))
				var flat := _bone("pelvis") - _player.global_position
				farthest = maxf(farthest, Vector2(flat.x, flat.z).length())
			_release_all()
			var label := "%s %s" % ["3ª" if third else "1ª", mode]
			_check(lowest_head > 1.3 and lowest_pelvis > 0.75,
					"%s: cabeça ≥ %.2f m, pélvis ≥ %.2f m" % [label, lowest_head, lowest_pelvis])
			_check(farthest < 0.3, "%s: corpo sobre a cápsula (pélvis a %.2f m do centro)" % [label, farthest])


## Contralateral: no contato do pé esquerdo (evento físico de passo), o pé
## esquerdo está à frente do direito; no contato direito, o contrário.
func _test_gait_phase_sync() -> void:
	_begin("Sincronia pés × passada física")
	for sprinting in [false, true]:
		await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z, 0.0, true)
		var left_leads: Array[float] = []
		var right_leads: Array[float] = []
		var on_step := func(_intensity: float, is_left: bool, _surface: SurfaceProfile) -> void:
			var lead := (_bone("foot_l") - _bone("foot_r")).dot(_forward())
			(left_leads if is_left else right_leads).append(lead)
		Input.action_press(&"move_forward")
		if sprinting:
			Input.action_press(&"sprint")
		await _frames(70)
		_player.footstep.connect(on_step)
		await _frames(150)
		_player.footstep.disconnect(on_step)
		_release_all()
		var label := "correndo" if sprinting else "trotando"
		_check(left_leads.size() >= 3 and right_leads.size() >= 3,
				"%s: %d contatos esquerdos e %d direitos" % [label, left_leads.size(), right_leads.size()])
		var worst_left: float = left_leads.min() if not left_leads.is_empty() else 0.0
		var worst_right: float = right_leads.max() if not right_leads.is_empty() else 0.0
		_check(worst_left > 0.15 and worst_right < -0.15,
				"%s: pé que pisa está à frente (esq. ≥ %.2f m, dir. ≤ %.2f m)" % [label, worst_left, worst_right])


func _test_stride_matches_animation() -> void:
	_begin("Passada da física = passada medida da animação (pé não desliza)")
	var settings := _player.settings
	var pairs := {"walk": settings.walk_stride, "jog": settings.jog_stride, "sprint": settings.sprint_stride,
			"crouch_walk": settings.crouch_stride}
	for clip_name in pairs:
		var animation: Animation = _body.animation_player.get_animation(clip_name)
		var measured: float = animation.get_meta(&"stride", 0.0)
		_check(absf(measured - pairs[clip_name]) / pairs[clip_name] < 0.05,
				"%s: animação %.2f m, física %.2f m" % [clip_name, measured, pairs[clip_name]])


func _test_crouch_follows_body_height() -> void:
	_begin("Agachar: peso da animação acompanha a altura real da cápsula")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var standing := _bone_height("pelvis")
	await _hold(&"crouch_toggle", 2)
	await _frames(5)
	var settings := _player.settings
	var expected := (settings.standing_height - _player.get_current_height()) / (settings.standing_height - settings.crouch_height)
	var weight: float = _body.get_layer_weights()["crouch"]
	_check(absf(weight - expected) < 0.001 and weight > 0.05 and weight < 0.95,
			"no meio da transição: peso %.3f = altura do corpo %.3f" % [weight, expected])
	await _frames(40)
	_check(is_equal_approx(_body.get_layer_weights()["crouch"], 1.0), "agachado: peso 1")
	_check(_bone_height("pelvis") < standing - 0.2, "pélvis baixa agachado (%.2f → %.2f m)" % [standing, _bone_height("pelvis")])
	await _hold(&"crouch_toggle", 2)
	await _frames(40)


# --- Ar e impactos -----------------------------------------------------------

func _test_air_and_landing() -> void:
	_begin("Salto, queda e aterrissagem")
	await _reset(Vector3(30.0, 0.0, 10.0), YAW_TOWARD_POSITIVE_Z)
	await _hold(&"jump", 3)
	await _frames(15)
	_check(_body.get_layer_weights()["air"] > 0.5, "peso aéreo no salto: %.2f" % _body.get_layer_weights()["air"])
	await _frames(60)
	await _reset(Vector3(30.0, 0.0, 10.0), YAW_TOWARD_POSITIVE_Z)
	_player.teleport(Vector3(30.0, 6.0, 10.0))
	var saw_fall := false
	var landed := [false]
	var on_land := func(_impact: float) -> void: landed[0] = true
	_player.landed.connect(on_land)
	while not landed[0]:
		await _frames(1)
		saw_fall = saw_fall or (_body.get_layer_weights()["air"] > 0.8 and _player.velocity.y < -5.0)
	_player.landed.disconnect(on_land)
	await _frames(2)
	_check(saw_fall, "queda de 6 m usa a pose de queda")
	_check(_body.current_animation(BodyAnimator.SLOT_LAND) == &"land", "queda de 6 m dispara a aterrissagem")
	_check(_body.get_overlay_weight(BodyAnimator.SLOT_LAND) > 0.5 or _body.get_overlay_time(BodyAnimator.SLOT_LAND) < 0.2,
			"aterrissagem com peso total do corpo")
	_check(not _body.is_playing(BodyAnimator.SLOT_HURT), "dano de queda não duplica com reação de ferimento")
	await _frames(60)


func _test_hurt_reactions() -> void:
	_begin("Ferimentos: reação proporcional ao dano")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	_health.apply_damage(6.0, &"golpe", Vector3.FORWARD)
	await _frames(2)
	_check(_body.current_animation(BodyAnimator.SLOT_HURT) == &"hit_chest", "dano 6 → reação no peito")
	await _frames(50)
	_health.apply_damage(18.0, &"golpe", Vector3.LEFT)
	await _frames(2)
	_check(_body.current_animation(BodyAnimator.SLOT_HURT) == &"hit_head", "dano 18 → reação na cabeça")
	await _frames(60)
	_health.apply_damage(32.0, &"golpe", Vector3.BACK)
	await _frames(2)
	_check(_body.current_animation(BodyAnimator.SLOT_HURT) == &"hit_knockback", "dano 32 → recuo do corpo inteiro")
	_check(is_equal_approx(_health.current, 44.0), "vida %.0f/100" % _health.current)
	await _frames(90)


func _test_leg_injury_limp() -> void:
	_begin("Lesão nas pernas: mancar, mais lento, sem correr")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	_health.apply_fall_damage(36.0)
	_check(is_equal_approx(_health.leg_injury, 0.6), "lesão de %.0f%%" % (_health.leg_injury * 100.0))
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(120)
	var expected := _player.settings.jog_speed * (1.0 - 0.45 * _health.leg_injury)
	_check(not _player.is_sprinting, "não consegue correr com a perna ferida")
	_check(absf(_player.get_horizontal_speed() - expected) < 0.1, "velocidade %.2f m/s (esperado %.2f)" % [_player.get_horizontal_speed(), expected])
	_check(_body.get_layer_weights()["limp"] > 0.4, "animação de mancar com peso %.2f" % _body.get_layer_weights()["limp"])
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
	var contact := _body.get_event_time(&"interact", &"contact") / InteractionComponent.INTERACT_SPEED
	var expected_frame := roundi(contact / DT)
	Input.action_press(&"interact")
	for frame in 70:
		await _frames(1)
		if frame == 2:
			Input.action_release(&"interact")
		if toggled_frame < 0 and switch.is_on != was_on:
			toggled_frame = frame
	_check(absi(toggled_frame - expected_frame) <= 3,
			"acendeu no quadro %d (contato da mão em %.2f s ≈ quadro %d)" % [toggled_frame, contact, expected_frame])
	_check(lamp.visible == switch.is_on, "lâmpada acompanha o interruptor")
	await _reset(Vector3(-3.0, 0.0, 5.0), 0.0, atan2(1.30 - 1.68, 3.0))
	_check(_interaction.focused == null, "a 3 m está fora de alcance")
	var before := switch.toggle_count
	await _hold(&"interact", 3)
	await _frames(60)
	_check(switch.toggle_count == before, "fora de alcance nada acontece")


# --- Combate -----------------------------------------------------------------

func _face_dummy(third_person: bool = false) -> TrainingDummy:
	var dummy: TrainingDummy = _gym.get_node("TrainingDummyStation/TrainingDummy")
	await _reset(Vector3(-5.0, 0.0, 9.95), 0.0, 0.0, third_person)
	await _frames(60)
	return dummy


func _test_light_attack_hit_frame() -> void:
	_begin("Soco rápido: dano no quadro de impacto da animação")
	var dummy := await _face_dummy()
	var hits_before := dummy.hits
	var stamina_before := _player.stamina.current
	var hit_frame := -1
	var expected := _body.get_event_time(&"punch_jab", &"hit") / 1.15
	Input.action_press(&"attack")
	await _frames(2)
	Input.action_release(&"attack")
	for frame in 50:
		await _frames(1)
		if hit_frame < 0 and dummy.hits > hits_before:
			hit_frame = frame
		if frame == 4:
			await _hold(&"attack", 2)
	_check(dummy.hits == hits_before + 1, "um acerto, mesmo apertando de novo durante o golpe (%d)" % (dummy.hits - hits_before))
	# O braço atinge o alvo dentro da janela ativa (em volta da extensão máxima);
	# alvo perto é atingido assim que o punho chega até ele.
	var window_start := (_body.get_event_time(&"punch_jab", &"hit") - _combat.active_before) / _combat.light_speed
	var window_end := (_body.get_event_time(&"punch_jab", &"hit") + _combat.active_after) / _combat.light_speed
	_check(hit_frame >= floori(window_start / DT) - 1 and hit_frame <= ceili(window_end / DT) + 1,
			"acerto no quadro %d, dentro da janela ativa (%.2f–%.2f s; extensão máxima em %.2f s)" % [hit_frame, window_start, window_end, expected])
	_check(is_equal_approx(dummy.last_damage, _combat.light_damage), "dano %.0f" % dummy.last_damage)
	_check(stamina_before - _player.stamina.current >= _combat.light_stamina_cost - 0.01, "consome resistência")
	_check(dummy.get_sway_angle() > 0.0, "boneco balança com o golpe")
	await _frames(60)
	# Um-dois: o segundo soco rápido sai com a outra mão.
	await _hold(&"attack", 2)
	await _frames(3)
	var first := _body.current_animation(BodyAnimator.SLOT_ACTION)
	# O segundo soco só é aceito depois que o braço recolheu (sem fila).
	await _frames(26)
	await _hold(&"attack", 2)
	await _frames(3)
	var second := _body.current_animation(BodyAnimator.SLOT_ACTION)
	_check(first != second and first in [&"punch_jab", &"punch_cross"] and second in [&"punch_jab", &"punch_cross"],
			"sequência um-dois alterna as mãos (%s → %s)" % [first, second])
	await _frames(60)


func _test_heavy_attack_charge() -> void:
	_begin("Golpe carregado: segura a preparação e bate mais forte")
	var dummy := await _face_dummy()
	await _frames(150)
	var hits_before := dummy.hits
	Input.action_press(&"attack")
	await _frames(70)
	_check(_body.current_animation(BodyAnimator.SLOT_ACTION) == &"punch_hook", "animação de golpe carregado")
	_check(_body.is_holding(BodyAnimator.SLOT_ACTION), "preparação mantida enquanto segura")
	_check(dummy.hits == hits_before, "nenhum dano durante a carga")
	Input.action_release(&"attack")
	await _frames(40)
	var expected := lerpf(_combat.heavy_min_damage, _combat.heavy_max_damage, (70.0 * DT - _combat.charge_threshold) / _combat.full_charge_time)
	_check(dummy.hits == hits_before + 1, "acerta ao soltar")
	_check(absf(dummy.last_damage - expected) < 2.0 and dummy.last_damage > _combat.light_damage,
			"dano %.1f (esperado ~%.1f, maior que o soco rápido)" % [dummy.last_damage, expected])
	await _frames(60)


func _test_punch_rigid_body() -> void:
	_begin("Soco derruba caixa de cima de um bloco (impulso físico)")
	var crate: RigidBody3D = _gym.get_node("PhysicsProps/Crate5kg")
	var block: RigidBody3D = _gym.get_node("PhysicsProps/Block300kg")
	var top := block.global_position + Vector3(0.0, 0.6 + 0.226, 0.0)
	crate.global_transform = Transform3D(Basis.IDENTITY, top)
	crate.linear_velocity = Vector3.ZERO
	crate.angular_velocity = Vector3.ZERO
	await _reset(Vector3(top.x, 0.0, top.z + 0.9), 0.0)
	var eye := (_player.get_node("Head/CameraEffects") as Node3D).global_position
	_player.set_view_rotation(0.0, -atan2(eye.y - top.y, 0.9))
	await _frames(10)
	var start := crate.global_position
	await _hold(&"attack", 2)
	await _frames(60)
	var moved := crate.global_position.distance_to(start)
	_check(not _combat.last_hit.is_empty() and _combat.last_hit["target"] == crate, "o alvo atingido foi a caixa")
	var direction: Vector3 = _combat.last_hit.get("direction", Vector3.FORWARD)
	var horizontal := Vector2(direction.x, direction.z).length() * _combat.light_impulse
	var vertical := -direction.y * _combat.light_impulse
	var speed := (horizontal - 0.75 * vertical) / crate.mass
	var expected := speed * speed / (2.0 * 0.75 * 9.81)
	# A estimativa ignora o tombo: o punho acerta acima do centro de massa e a
	# caixa gira, então o deslocamento pode passar dela.
	var travel := crate.global_position - start
	_check(moved > expected * 0.5 and moved < expected * 3.0 and Vector2(travel.x, travel.z).normalized().dot(Vector2(direction.x, direction.z).normalized()) > 0.7,
			"caixa de 5 kg deslocada %.2f m na direção do golpe (estimativa física sem tombo %.2f m)" % [moved, expected])


func _test_punch_wall_recoil() -> void:
	_begin("Soco na parede: o tronco é rebatido")
	await _reset(Vector3(0.0, 0.0, -19.3), 0.0)
	var obstacle := [false]
	var on_obstacle := func(_point: Vector3) -> void: obstacle[0] = true
	_combat.hit_obstacle.connect(on_obstacle)
	await _hold(&"attack", 2)
	await _frames(16)
	_combat.hit_obstacle.disconnect(on_obstacle)
	_check(obstacle[0], "impacto em superfície rígida detectado")
	_check(_body.current_animation(BodyAnimator.SLOT_ACTION) == &"hit_head", "animação de recuo")
	await _frames(60)


# --- Perigos -----------------------------------------------------------------

func _test_damage_zone() -> void:
	_begin("Arame farpado: dano contínuo, lentidão e reação")
	await _reset(Vector3(8.0, 0.0, 5.5), YAW_TOWARD_POSITIVE_Z)
	var hurt_seen := false
	Input.action_press(&"move_forward")
	for i in 90:
		await _frames(1)
		hurt_seen = hurt_seen or _body.is_playing(BodyAnimator.SLOT_HURT)
		if _player.global_position.z > 8.0:
			Input.action_release(&"move_forward")
	_check(_health.current < 100.0, "perdeu vida no arame (%.0f)" % _health.current)
	_check(is_equal_approx(_player.external_speed_multiplier, 0.5), "preso no arame: velocidade pela metade")
	_check(hurt_seen, "reação de ferimento ao tocar o arame")
	Input.action_press(&"move_forward")
	await _frames(150)
	Input.action_release(&"move_forward")
	_check(is_equal_approx(_player.external_speed_multiplier, 1.0), "fora do arame: velocidade normal")


# --- Câmera ------------------------------------------------------------------

func _test_camera_first_person_view() -> void:
	_begin("Câmera 1ª pessoa: nos olhos, cabeça escondida, corpo visível ao olhar para baixo")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var eye_height := _camera.global_position.y - _player.global_position.y
	_check(eye_height > 1.55 and eye_height < 1.80, "olhos a %.2f m do chão" % eye_height)
	var head := _bone("Head")
	_check(_camera.global_position.distance_to(head) < 0.25, "câmera junto à cabeça animada (%.2f m)" % _camera.global_position.distance_to(head))
	_check(_body.hide_head, "cabeça escondida em 1ª pessoa")
	var full_shadow_only := true
	var first_person_visible := true
	for child in _skeleton.get_children():
		if child is MeshInstance3D:
			var view := String(child.get_meta(&"view", "both"))
			if view == "full":
				full_shadow_only = full_shadow_only and (child as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			elif view == "both":
				first_person_visible = first_person_visible and child.visible \
						and (child as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_check(full_shadow_only, "cabeça, cabelo e olhos só projetam sombra (a sombra continua inteira)")
	_check(first_person_visible, "roupa, braços e mãos visíveis em 1ª pessoa (um corpo só, sem duplicar)")
	_player.set_view_rotation(YAW_TOWARD_POSITIVE_Z, -1.3)
	await _frames(30)
	var foot := _bone("foot_l")
	_check(_camera.is_position_in_frustum(foot), "olhando para baixo, os pés aparecem")


func _test_camera_toggle_standing() -> void:
	_begin("Câmera [1] alternar parado: transição suave, sem teleporte, mesma direção")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var start_position := _player.global_position
	var view_forward := -_player.get_view_basis().z
	var trace := await _toggle_and_trace()
	_check(_player.global_position.distance_to(start_position) < 0.01, "o personagem não se move (%.3f m)" % _player.global_position.distance_to(start_position))
	_check(not _rig.is_transitioning() and _rig.third_person, "transição concluída em %.2f s" % _rig.transition_time)
	_check(trace.max_step() < 0.2, "maior salto por quadro %.3f m (sem teleporte)" % trace.max_step())
	_check(trace.max_step_change() < 0.03, "aceleração suave (variação máx. %.4f m/quadro)" % trace.max_step_change())
	_check(trace.max_turn_degrees() < 3.0, "giro máximo por quadro %.2f°" % trace.max_turn_degrees())
	var offset := _camera_offset_local()
	_check(offset.z > _rig.distance * 0.8 and offset.y > 1.2 and offset.x > 0.1,
			"atrás, acima e sobre o ombro (%.2f, %.2f, %.2f)" % [offset.x, offset.y, offset.z])
	_check((-_camera.global_basis.z).dot(view_forward) > 0.99, "a câmera continua olhando para onde o jogador olhava")
	_check(not _body.hide_head, "corpo inteiro visível em 3ª pessoa")
	var back := await _toggle_and_trace()
	_check(back.max_step() < 0.2 and back.max_step_change() < 0.03, "volta suave à 1ª pessoa (salto máx. %.3f m)" % back.max_step())
	_check(_camera.global_position.distance_to(_bone("Head")) < 0.25 and _body.hide_head, "de volta aos olhos")


func _test_camera_toggle_walking() -> void:
	_begin("Câmera [2] alternar andando: velocidade e passada não mudam")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	await _hold(&"walk_toggle", 2)
	Input.action_press(&"move_forward")
	await _frames(60)
	var speed := _player.get_horizontal_speed()
	var trace := await _toggle_and_trace()
	_check(absf(_player.get_horizontal_speed() - speed) < 0.05, "velocidade %.2f → %.2f m/s" % [speed, _player.get_horizontal_speed()])
	# Andando a 1,5 m/s o jogador avança 0,025 m por quadro além da transição.
	_check(trace.max_step() < 0.22 and trace.max_step_change() < 0.035, "sem trancos (salto máx. %.3f m)" % trace.max_step())
	_check(_body.get_layer_weights()["move"] > 0.95, "locomoção continua tocando (peso %.2f)" % _body.get_layer_weights()["move"])
	_release_all()
	await _frames(20)


func _test_camera_toggle_running() -> void:
	_begin("Câmera [3] alternar correndo")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(80)
	var speed := _player.get_horizontal_speed()
	var trace := await _toggle_and_trace()
	_check(_player.is_sprinting and absf(_player.get_horizontal_speed() - speed) < 0.1,
			"continua correndo a %.2f m/s" % _player.get_horizontal_speed())
	# Correndo a 5,8 m/s o jogador avança ~0,1 m por quadro.
	_check(trace.max_step() < 0.3 and trace.max_step_change() < 0.04, "sem trancos (salto máx. %.3f m, variação %.4f)" % [trace.max_step(), trace.max_step_change()])
	await _frames(30)
	var offset := _camera_offset_local()
	_check(offset.z > _rig.distance, "a câmera se afasta um pouco na corrida (%.2f m)" % offset.z)
	_release_all()
	await _frames(30)


func _test_camera_toggle_crouched() -> void:
	_begin("Câmera [4] alternar agachado: pivô mais baixo, sem levantar")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z, 0.0, true)
	await _frames(20)
	var standing := _camera_offset_local().y
	await _hold(&"crouch_toggle", 2)
	await _frames(60)
	var crouched := _camera_offset_local().y
	_check(crouched < standing - 0.35, "câmera desce com o agachar (%.2f → %.2f m)" % [standing, crouched])
	var trace := await _toggle_and_trace()
	_check(_player._crouch_toggled and _player.get_current_height() < _player.settings.standing_height - 0.3,
			"continua agachado depois de alternar")
	_check(trace.max_step() < 0.2, "transição sem saltos (%.3f m)" % trace.max_step())
	var eye := _camera.global_position.y - _player.global_position.y
	_check(eye < 1.35, "1ª pessoa agachada na altura dos olhos agachados (%.2f m)" % eye)
	await _hold(&"crouch_toggle", 2)
	await _frames(40)


func _test_camera_toggle_in_combat() -> void:
	_begin("Câmera [5] alternar durante o combate: golpe continua e acerta")
	var dummy := await _face_dummy()
	var hits_before := dummy.hits
	Input.action_press(&"attack")
	await _frames(2)
	Input.action_release(&"attack")
	await _frames(2)
	_rig.toggle()
	await _frames(40)
	_check(dummy.hits == hits_before + 1, "o soco iniciado em 1ª pessoa acertou durante a transição")
	await _frames(40)
	hits_before = dummy.hits
	await _hold(&"attack", 2)
	await _frames(30)
	_check(dummy.hits == hits_before + 1, "em 3ª pessoa o golpe sai na direção da mira")
	_check(_rig.third_person and not _rig.is_transitioning(), "câmera em 3ª pessoa")
	await _frames(40)


func _test_camera_walls() -> void:
	_begin("Câmera [6] perto de paredes: não atravessa e volta suavemente")
	# Parede do ginásio em z ≈ -20; o jogador de costas para ela.
	await _reset(Vector3(0.0, 0.0, -18.9), YAW_TOWARD_POSITIVE_Z)
	var ray := PhysicsRayQueryParameters3D.create(_player.global_position + Vector3.UP * 1.5,
			_player.global_position + Vector3(0.0, 1.5, -5.0), 1)
	ray.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not hit.is_empty(), "parede atrás do jogador encontrada")
	if hit.is_empty():
		return
	var normal: Vector3 = hit["normal"]
	var deepest := 10.0
	var trace := CameraTrace.new()
	_rig.toggle()
	for i in 45:
		await _frames(1)
		trace.add(_camera)
		deepest = minf(deepest, (_camera.global_position - hit["position"]).dot(normal))
	_check(deepest > 0.1, "a câmera nunca passa da parede (folga mínima %.2f m)" % deepest)
	_check(_camera.global_position.distance_to(_player.global_position + Vector3.UP * 1.5) < _rig.distance,
			"o braço encurtou contra a parede")
	# Jogador se afasta da parede: a câmera volta suavemente à distância.
	Input.action_press(&"move_forward")
	await _frames(60)
	Input.action_release(&"move_forward")
	var recovering := CameraTrace.new()
	for i in 60:
		await _frames(1)
		recovering.add(_camera)
	var offset := _camera_offset_local()
	_check(offset.z > _rig.distance * 0.85, "longe da parede a distância é restaurada (%.2f m)" % offset.z)
	_check(recovering.max_step() < 0.15, "recuperação sem saltos (%.3f m)" % recovering.max_step())
	# Primeira pessoa encostada na parede: o olho não atravessa.
	await _reset(Vector3(0.0, 0.0, -19.3), 0.0, -0.6)
	Input.action_press(&"move_forward")
	await _frames(40)
	Input.action_release(&"move_forward")
	var front := PhysicsRayQueryParameters3D.create(_player.global_position + Vector3.UP * 1.5,
			_player.global_position + Vector3(0.0, 1.5, -3.0), 1)
	front.exclude = [_player.get_rid()]
	var front_hit := _player.get_world_3d().direct_space_state.intersect_ray(front)
	var gap: float = 1.0 if front_hit.is_empty() else (_camera.global_position - front_hit["position"]).dot(front_hit["normal"])
	_check(gap > 0.03, "1ª pessoa encostada: olho do lado de cá da parede (%.2f m)" % gap)


func _test_camera_rotate_during_transition() -> void:
	_begin("Câmera [7] girar a câmera durante a transição")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var body_yaw := _player.rotation.y
	var trace := CameraTrace.new()
	_rig.toggle()
	for i in 45:
		GameInput.add_look_radians(Vector2(0.02, 0.0))
		await _frames(1)
		trace.add(_camera)
	await _frames(2)
	_check(trace.max_step() < 0.25 and trace.max_step_change() < 0.05,
			"sem saltos girando (salto %.3f m, variação %.4f)" % [trace.max_step(), trace.max_step_change()])
	_check(trace.max_turn_degrees() < 4.0, "giro por quadro limitado (%.2f°)" % trace.max_turn_degrees())
	var forward := -_camera.global_basis.z
	_check(forward.dot(-_player.get_view_basis().z) > 0.99, "ao fim, a câmera olha na direção da vista")
	var offset := _camera_offset_local()
	_check(offset.z > _rig.distance * 0.8, "órbita centrada atrás da nova direção (%.2f m)" % offset.z)
	_check(absf(angle_difference(_player.rotation.y, body_yaw)) < deg_to_rad(1.0),
			"parado em 3ª pessoa, girar a câmera não gira o corpo (órbita livre)")
	# Ao andar, o corpo vira para a direção do movimento.
	Input.action_press(&"move_forward")
	await _frames(60)
	Input.action_release(&"move_forward")
	_check(absf(angle_difference(_player.rotation.y, _player.get_view_yaw())) < deg_to_rad(5.0),
			"andando, o corpo vira para a direção da câmera")
	await _frames(30)


func _test_camera_animation_sync() -> void:
	_begin("Câmera [8] animações continuam sincronizadas após alternar")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward")
	await _frames(40)
	_rig.toggle()
	await _frames(20)
	_rig.toggle()
	await _frames(20)
	_rig.toggle()
	await _frames(40)
	var left_leads: Array[float] = []
	var right_leads: Array[float] = []
	var on_step := func(_intensity: float, is_left: bool, _surface: SurfaceProfile) -> void:
		var lead := (_bone("foot_l") - _bone("foot_r")).dot(_forward())
		(left_leads if is_left else right_leads).append(lead)
	_player.footstep.connect(on_step)
	await _frames(120)
	_player.footstep.disconnect(on_step)
	_release_all()
	_check(left_leads.size() >= 2 and right_leads.size() >= 2 and left_leads.min() > 0.15 and right_leads.max() < -0.15,
			"pés em fase com os passos físicos depois de 3 trocas")
	_check(_rig.third_person and not _body.hide_head and _body.head_follows_view, "3ª pessoa: cabeça visível e acompanhando a vista")
	var head_visible := true
	for child in _skeleton.get_children():
		if child is MeshInstance3D and String(child.get_meta(&"view", "both")) == "full":
			head_visible = head_visible and (child as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_check(head_visible, "cabeça visível em 3ª pessoa (corpo completo, nada duplicado)")
	await _frames(20)


func _test_camera_touch_button() -> void:
	_begin("Botão de câmera na tela (lado direito, com retorno visual)")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var controls: TouchControls = _gym.get_node("TouchControlsLayer/TouchControls")
	controls.visible = true
	var button: TouchActionButton = controls.get_node("CameraButton")
	_check(button.get_center_global().x > get_viewport().get_visible_rect().size.x * 0.5, "botão no lado direito")
	_send_touch(7, button.get_center_global(), true)
	await _frames(2)
	_send_touch(7, button.get_center_global(), false)
	await _frames(5)
	_check(_rig.third_person, "toque alterna para 3ª pessoa")
	_check(button.is_active, "botão mostra o modo ativo (3ª P)")
	# Pode ser usado andando: o dedo do direcional continua controlando.
	var stick_touch := Vector2(get_viewport().get_visible_rect().size.x * 0.15, get_viewport().get_visible_rect().size.y * 0.75)
	_send_touch(8, stick_touch, true)
	_send_drag(8, stick_touch + Vector2(0.0, -60.0))
	await _frames(30)
	_send_touch(9, button.get_center_global(), true)
	await _frames(2)
	_send_touch(9, button.get_center_global(), false)
	await _frames(20)
	_check(not _rig.third_person and not button.is_active, "segundo toque volta à 1ª pessoa")
	_check(_player.get_horizontal_speed() > 0.5, "continua andando com o direcional (%.2f m/s)" % _player.get_horizontal_speed())
	_send_touch(8, stick_touch + Vector2(0.0, -60.0), false)
	controls.visible = false
	await _frames(30)



# --- Controles de toque como no Android --------------------------------------
# Os eventos entram por Input.parse_input_event (o mesmo caminho do sistema
# operacional) com a emulação de mouse LIGADA: cada dedo também gera cliques
# de mouse emulados, que eram a origem do soco ao girar a câmera.

func _touch_setup() -> TouchControls:
	var controls: TouchControls = _gym.get_node("TouchControlsLayer/TouchControls")
	controls.visible = true
	Input.emulate_mouse_from_touch = true
	return controls


func _touch_teardown(controls: TouchControls) -> void:
	controls.release_all()
	controls.visible = false
	await _frames(5)


func _android_touch(index: int, viewport_position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * viewport_position
	event.pressed = pressed
	Input.parse_input_event(event)


func _android_drag(index: int, viewport_position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * viewport_position
	# Em coordenadas da janela, como o sistema entrega (o Godot converte para
	# a viewport; sem tela, a janela de teste tem outra escala).
	event.relative = get_viewport().get_final_transform().basis_xform(relative)
	Input.parse_input_event(event)


## Arrasta um dedo de `from` por `total` pixels em `frames` quadros.
func _swipe(index: int, from: Vector2, total: Vector2, frames: int) -> void:
	_android_touch(index, from, true)
	await _frames(1)
	var step := total / frames
	for i in frames:
		_android_drag(index, from + step * (i + 1), step)
		await _frames(1)
	_android_touch(index, from + total, false)
	await _frames(2)


func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


func _test_touch_camera_never_attacks() -> void:
	_begin("[T1/T2] Girar a câmera pela tela nunca ataca (eventos reais de toque, mouse emulado ligado)")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var controls := _touch_setup()
	var attacks := [0]
	var on_attack := func(_kind: StringName) -> void: attacks[0] += 1
	_combat.attack_started.connect(on_attack)
	var center := _screen() * Vector2(0.66, 0.42)
	_check(controls.get_target_at(center) == &"look", "o centro-direita da tela é a área da câmera")
	var yaw := _player.get_view_yaw()
	await _swipe(0, center, Vector2(320.0, 0.0), 12)
	_check(absf(angle_difference(yaw, _player.get_view_yaw())) > 0.5, "arrastar para a direita gira a câmera (%.0f°)" % rad_to_deg(angle_difference(yaw, _player.get_view_yaw())))
	yaw = _player.get_view_yaw()
	await _swipe(0, center, Vector2(-320.0, 0.0), 12)
	_check(absf(angle_difference(yaw, _player.get_view_yaw())) > 0.5, "arrastar para a esquerda gira de volta")
	var pitch := _player.get_pitch()
	await _swipe(0, center, Vector2(0.0, 160.0), 10)
	_check(_player.get_pitch() < pitch - 0.2, "arrastar para baixo inclina a câmera para baixo")
	pitch = _player.get_pitch()
	await _swipe(0, center, Vector2(0.0, -160.0), 10)
	_check(_player.get_pitch() > pitch + 0.2, "arrastar para cima inclina para cima")
	# Toques curtos (o que viraria "clique") e um arrasto que passa por cima
	# do botão ATACAR depois de começar na área da câmera.
	for i in 3:
		_android_touch(0, center, true)
		await _frames(3)
		_android_touch(0, center, false)
		await _frames(3)
	var attack_button: TouchActionButton = controls.get_node("AttackButton")
	var start := attack_button.get_center_global() - Vector2(260.0, 0.0)
	await _swipe(0, start, Vector2(260.0, 0.0), 10)
	await _frames(40)
	_combat.attack_started.disconnect(on_attack)
	_check(attacks[0] == 0, "nenhum ataque em giros, toques na área da câmera e arrasto sobre o botão (%d)" % attacks[0])
	_check(_combat.state == MeleeCombat.State.IDLE and not Input.is_action_pressed(&"attack"), "ação de ataque nunca foi pressionada")
	await _touch_teardown(controls)


func _test_touch_move_and_look_together() -> void:
	_begin("[T3] Direcional e câmera ao mesmo tempo (dedos identificados pelo índice)")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var controls := _touch_setup()
	var attacks := [0]
	var on_attack := func(_kind: StringName) -> void: attacks[0] += 1
	_combat.attack_started.connect(on_attack)
	var stick := _screen() * Vector2(0.15, 0.72)
	_android_touch(1, stick, true)
	_android_drag(1, stick + Vector2(0.0, -70.0), Vector2(0.0, -70.0))
	await _frames(20)
	var yaw := _player.get_view_yaw()
	var look := _screen() * Vector2(0.64, 0.40)
	_android_touch(2, look, true)
	for i in 20:
		_android_drag(2, look + Vector2(10.0 * (i + 1), 0.0), Vector2(10.0, 0.0))
		await _frames(1)
	_check(_player.get_horizontal_speed() > 1.0, "andando com o direcional (%.2f m/s)" % _player.get_horizontal_speed())
	_check(absf(angle_difference(yaw, _player.get_view_yaw())) > 0.4, "e girando a câmera com o outro dedo")
	# Terceiro dedo no ATACAR enquanto os outros dois continuam na tela.
	var attack_button: TouchActionButton = controls.get_node("AttackButton")
	_android_touch(3, attack_button.get_center_global(), true)
	await _frames(3)
	_android_touch(3, attack_button.get_center_global(), false)
	await _frames(30)
	_check(attacks[0] == 1, "ATACAR com o terceiro dedo dá exatamente um soco (%d)" % attacks[0])
	_check(_player.get_horizontal_speed() > 1.0, "o direcional continua funcionando durante o soco")
	_android_touch(2, look, false)
	_android_touch(1, stick, false)
	await _frames(30)
	_check(_player.get_horizontal_speed() < 0.5, "soltar o direcional para o personagem")
	_combat.attack_started.disconnect(on_attack)
	await _touch_teardown(controls)


func _test_touch_attack_only_button() -> void:
	_begin("[T4] Apertar ATACAR sem mexer a câmera")
	var dummy := await _face_dummy()
	var controls := _touch_setup()
	var yaw := _player.get_view_yaw()
	var pitch := _player.get_pitch()
	var hits := dummy.hits
	var button: TouchActionButton = controls.get_node("AttackButton")
	_android_touch(4, button.get_center_global(), true)
	await _frames(3)
	_android_touch(4, button.get_center_global(), false)
	await _frames(40)
	_check(dummy.hits == hits + 1, "um soco acerta o boneco")
	_check(absf(angle_difference(yaw, _player.get_view_yaw())) < 0.0001 and absf(pitch - _player.get_pitch()) < 0.0001,
			"o toque no botão não gira a câmera")
	await _touch_teardown(controls)


func _test_touch_layout_and_sprint() -> void:
	_begin("[T12] Layout de toque: áreas exclusivas, CORRER e DEFESA")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var controls := _touch_setup()
	var names := ["AttackButton", "JumpButton", "CrouchButton", "SprintButton", "BlockButton", "InteractButton", "CameraButton"]
	var all_exclusive := true
	var all_right := true
	for name in names:
		var button: TouchActionButton = controls.get_node(name)
		all_exclusive = all_exclusive and controls.get_target_at(button.get_center_global()) == StringName("button:" + name)
		all_right = all_right and button.get_center_global().x > _screen().x * 0.5
		for other_name in names:
			if other_name == name:
				continue
			var other: TouchActionButton = controls.get_node(other_name)
			if button.get_center_global().distance_to(other.get_center_global()) < (button.radius + other.radius) * button.get_global_transform().get_scale().x:
				all_exclusive = false
	_check(all_exclusive, "cada botão tem a própria área, sem sobreposição")
	_check(all_right, "botões do lado direito")
	_check(controls.get_target_at(_screen() * Vector2(0.15, 0.7)) == &"joystick", "lado esquerdo é o direcional")
	# CORRER: alterna a corrida enquanto o direcional anda.
	var stick := _screen() * Vector2(0.15, 0.72)
	_android_touch(1, stick, true)
	_android_drag(1, stick + Vector2(0.0, -80.0), Vector2(0.0, -80.0))
	await _frames(10)
	var sprint_button: TouchActionButton = controls.get_node("SprintButton")
	_android_touch(2, sprint_button.get_center_global(), true)
	await _frames(2)
	_android_touch(2, sprint_button.get_center_global(), false)
	await _frames(60)
	_check(_player.is_sprinting and _player.get_horizontal_speed() > _player.settings.jog_speed + 0.5,
			"CORRER liga a corrida (%.2f m/s)" % _player.get_horizontal_speed())
	_android_touch(1, stick, false)
	await _frames(10)
	_check(not sprint_button.is_active and not Input.is_action_pressed(&"sprint"), "soltar o direcional desliga a corrida")
	var block_button: TouchActionButton = controls.get_node("BlockButton")
	_android_touch(3, block_button.get_center_global(), true)
	await _frames(20)
	_check(_combat.is_blocking() and _body.get_layer_weights()["guard"] > 0.8, "DEFESA segurado: guarda erguida")
	_android_touch(3, block_button.get_center_global(), false)
	await _frames(20)
	_check(not _combat.is_blocking(), "soltar DEFESA baixa a guarda")
	await _touch_teardown(controls)


# --- Movimento e física -------------------------------------------------------

func _test_run_direction_change() -> void:
	_begin("[T5] Correr e trocar de direção: curva com peso, sem virar instantâneo")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z, 0.0, true)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(80)
	var start_speed := _player.get_horizontal_speed()
	var old_direction := Vector3(_player.velocity.x, 0.0, _player.velocity.z).normalized()
	Input.action_release(&"move_forward")
	Input.action_press(&"move_right")
	var max_turn_rate := 0.0
	var max_velocity_turn := 0.0
	var min_speed := 100.0
	var last_yaw := _player.rotation.y
	var last_direction := old_direction
	for i in 60:
		await _frames(1)
		max_turn_rate = maxf(max_turn_rate, absf(angle_difference(last_yaw, _player.rotation.y)) / DT)
		last_yaw = _player.rotation.y
		var direction := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
		if direction.length() > 0.3:
			direction = direction.normalized()
			max_velocity_turn = maxf(max_velocity_turn, rad_to_deg(last_direction.angle_to(direction)))
			last_direction = direction
		min_speed = minf(min_speed, _player.get_horizontal_speed())
	var wanted := -_player.get_view_basis().z.rotated(Vector3.UP, -PI * 0.5)
	_check(max_turn_rate <= deg_to_rad(_player.body_turn_speed_degrees) + 0.05, "corpo gira no máximo %.0f°/s (%.0f°/s)" % [_player.body_turn_speed_degrees, rad_to_deg(max_turn_rate)])
	_check(max_velocity_turn < 12.0, "a direção do deslocamento muda aos poucos (máx. %.1f° por quadro)" % max_velocity_turn)
	_check(min_speed < start_speed * 0.9, "a curva fechada custa velocidade (%.2f → mín. %.2f m/s)" % [start_speed, min_speed])
	_check(last_direction.dot(wanted) > 0.9, "termina correndo na nova direção")
	_release_all()
	await _frames(40)
	# Parado em 3ª pessoa, inverter a direção gira o corpo no lugar antes de andar.
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z, 0.0, true)
	var position := _player.global_position
	Input.action_press(&"move_back")
	await _frames(8)
	var drift := Vector2(_player.global_position.x - position.x, _player.global_position.z - position.z)
	_check(drift.dot(Vector2(_forward().x, _forward().z)) < 0.05, "parado e virando para trás: gira no lugar, não sai andando de costas nem para a frente")
	await _frames(50)
	_check(-_player.global_basis.z.dot(-_player.get_view_basis().z) < -0.9 and _player.get_horizontal_speed() > 1.0, "depois do giro, anda para trás da câmera")
	_release_all()
	await _frames(30)


func _test_stop_deceleration() -> void:
	_begin("[T6] Arrancar e parar de correr: aceleração e frenagem com peso")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	var max_start_lean := 0.0
	var start_lean_forward := false
	for i in 20:
		await _frames(1)
		if _body.get_lean_degrees() > max_start_lean:
			max_start_lean = _body.get_lean_degrees()
			start_lean_forward = _body.get_body_acceleration().dot(_forward()) > 0.0
	_check(max_start_lean > 2.0 and start_lean_forward, "arrancada inclina o tronco para a frente (%.1f°)" % max_start_lean)
	await _frames(60)
	var speeds: Array[float] = []
	var top := _player.get_horizontal_speed()
	_release_all()
	var max_brake_lean := 0.0
	var brake_backward := false
	for i in 90:
		await _frames(1)
		speeds.append(_player.get_horizontal_speed())
		if _body.get_lean_degrees() > max_brake_lean:
			max_brake_lean = _body.get_lean_degrees()
			brake_backward = _body.get_body_acceleration().dot(_forward()) < 0.0
	var monotonic := true
	for i in range(1, speeds.size()):
		monotonic = monotonic and speeds[i] <= speeds[i - 1] + 0.01
	var stop_frame := speeds.find(speeds.filter(func(v: float) -> bool: return v < 0.05).front() if speeds.any(func(v: float) -> bool: return v < 0.05) else -1.0)
	_check(speeds[0] > top * 0.8, "não para na hora (%.2f → %.2f m/s no 1º quadro)" % [top, speeds[0]])
	_check(monotonic, "desaceleração contínua, sem trancos")
	_check(stop_frame >= 9 and stop_frame <= 75, "para em %.2f s" % (stop_frame * DT))
	_check(max_brake_lean > 2.0 and brake_backward, "frenagem joga o tronco para trás (%.1f°)" % max_brake_lean)
	await _frames(30)
	_check(_body.get_layer_weights()["move"] < 0.05 and _body.get_lean_degrees() < 1.0, "parado: sem locomoção nem inclinação")


func _test_crouch_and_stand() -> void:
	_begin("[T8] Agachar e levantar")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var standing := _bone_height("Head")
	await _hold(&"crouch_toggle", 2)
	await _frames(50)
	var crouched := _bone_height("Head")
	_check(crouched < standing - 0.3, "agachado: cabeça desce (%.2f → %.2f m)" % [standing, crouched])
	Input.action_press(&"move_forward")
	await _frames(60)
	_check(_player.get_horizontal_speed() > 0.5 and _player.get_horizontal_speed() <= _player.settings.crouch_speed + 0.05 and _bone_height("Head") < standing - 0.3,
			"anda agachado (%.2f m/s)" % _player.get_horizontal_speed())
	_release_all()
	await _hold(&"crouch_toggle", 2)
	await _frames(50)
	_check(absf(_bone_height("Head") - standing) < 0.05 and _body.get_layer_weights()["crouch"] < 0.01, "levanta de volta (%.2f m)" % _bone_height("Head"))


func _test_obstacle_collision() -> void:
	_begin("[T10] Colisão com obstáculos: correr contra a parede")
	await _reset(Vector3(0.0, 0.0, -15.0), 0.0)
	var ray := PhysicsRayQueryParameters3D.create(_player.global_position + Vector3.UP, _player.global_position + Vector3(0.0, 1.0, -10.0), 1)
	ray.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not hit.is_empty(), "parede à frente")
	if hit.is_empty():
		return
	var wall: Vector3 = hit["position"]
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	var deepest := 10.0
	for i in 120:
		await _frames(1)
		deepest = minf(deepest, _player.global_position.z - wall.z)
	_release_all()
	var radius: float = (_player.get_node("CollisionShape3D") as CollisionShape3D).shape.get("radius")
	_check(deepest > radius - 0.02, "a cápsula não entra na parede (folga %.3f m, raio %.2f m)" % [deepest, radius])
	_check(_player.get_horizontal_speed() < 0.3, "parado contra a parede")
	_check(_bone_height("Head") > 1.3, "corpo em pé depois do choque")
	await _frames(40)


func _test_planted_feet() -> void:
	_begin("Girar parado: pés plantados e passo de ajuste")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	await _frames(30)
	var foot := _bone("foot_l")
	for i in 10:
		GameInput.add_look_radians(Vector2(deg_to_rad(3.0), 0.0))
		await _frames(1)
	var offset := rad_to_deg(_body.get_layer_weights()["turn_offset"])
	_check(absf(offset) > 25.0 and absf(offset) < 35.0, "girando 30°, as pernas ficam (torção %.1f°)" % offset)
	_check(_bone("foot_l").distance_to(foot) < 0.06, "o pé esquerdo não desliza (%.3f m)" % _bone("foot_l").distance_to(foot))
	var stepped := false
	for i in roundi((_body.settle_delay + _body.turn_step_time + 0.4) / DT):
		await _frames(1)
		stepped = stepped or _body.get_layer_weights()["turn_step"] >= 0.0
	_check(stepped and absf(rad_to_deg(_body.get_layer_weights()["turn_offset"])) < 3.0, "depois de uma pausa, um passo realinha as pernas")
	var largest := 0.0
	stepped = false
	for i in 18:
		GameInput.add_look_radians(Vector2(deg_to_rad(5.0), 0.0))
		await _frames(1)
		largest = maxf(largest, absf(_body.get_layer_weights()["turn_offset"]))
		stepped = stepped or _body.get_layer_weights()["turn_step"] >= 0.0
	_check(stepped, "giro de 90°: passo assim que passa do limite")
	_check(rad_to_deg(largest) <= _body.max_planted_twist * 1.3 + 0.5, "torção nunca passa de %.0f° (%.1f°)" % [_body.max_planted_twist * 1.3, rad_to_deg(largest)])
	await _frames(60)


func _test_defense() -> void:
	_begin("Defesa: guarda, dano reduzido pela frente, não pelas costas")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	Input.action_press(&"block")
	await _frames(30)
	_check(_combat.is_blocking() and _body.get_layer_weights()["guard"] > 0.9, "guarda erguida (%.2f)" % _body.get_layer_weights()["guard"])
	_check(_camera.is_position_in_frustum(_bone("hand_l")) and _camera.is_position_in_frustum(_bone("hand_r")),
			"em 1ª pessoa os dois punhos da guarda aparecem diante dos olhos")
	var forward := -_player.get_view_basis().z
	var stamina := _player.stamina.current
	_health.apply_damage(20.0, &"golpe", -forward)
	await _frames(2)
	_check(is_equal_approx(_health.current, 95.0), "golpe pela frente: 20 → %.0f de dano" % (100.0 - _health.current))
	_check(_body.current_animation(BodyAnimator.SLOT_HURT) == &"block_impact", "reação de impacto na guarda")
	_check(_player.stamina.current < stamina - 5.0, "aparar custa fôlego")
	await _frames(40)
	_health.apply_damage(20.0, &"golpe", forward)
	await _frames(2)
	_check(is_equal_approx(_health.current, 75.0), "golpe pelas costas: dano inteiro")
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(60)
	_check(not _player.is_sprinting and _player.get_horizontal_speed() < _player.settings.jog_speed * _combat.block_speed_multiplier + 0.1,
			"de guarda anda devagar e não corre (%.2f m/s)" % _player.get_horizontal_speed())
	_release_all()
	await _frames(30)
	_check(not _combat.is_blocking() and _body.get_layer_weights()["guard"] < 0.1 and is_equal_approx(_player.action_speed_multiplier, 1.0),
			"soltar a defesa devolve braços e velocidade")


func _test_attack_no_queue() -> void:
	_begin("Golpes involuntários: apertar durante o golpe não enfileira outro")
	var dummy := await _face_dummy()
	await _frames(60)
	var started := [0]
	var on_attack := func(_kind: StringName) -> void: started[0] += 1
	_combat.attack_started.connect(on_attack)
	var hits := dummy.hits
	await _hold(&"attack", 2)
	for i in 3:
		await _frames(3)
		await _hold(&"attack", 2)
	await _frames(70)
	_combat.attack_started.disconnect(on_attack)
	_check(started[0] == 1 and dummy.hits == hits + 1, "quatro toques rápidos: um golpe, um acerto (%d / %d)" % [started[0], dummy.hits - hits])
	_check(_combat.state == MeleeCombat.State.IDLE, "volta ao repouso depois da recuperação")


func _test_arm_reach() -> void:
	_begin("Alcance real do braço: alvo longe demais não é atingido")
	var dummy: TrainingDummy = _gym.get_node("TrainingDummyStation/TrainingDummy")
	await _reset(Vector3(-5.0, 0.0, 10.85), 0.0)
	await _frames(60)
	var hits := dummy.hits
	var missed := [false]
	var on_miss := func(_kind: StringName) -> void: missed[0] = true
	_combat.attack_missed.connect(on_miss)
	await _hold(&"attack", 2)
	await _frames(50)
	_combat.attack_missed.disconnect(on_miss)
	_check(dummy.hits == hits and missed[0], "a 0,9 m a mais o soco não alcança")
	await _frames(40)

# --- Morte e ragdoll ---------------------------------------------------------

func _test_ragdoll_death_and_respawn() -> void:
	_begin("Morte: ragdoll físico, câmera segue o corpo, renascer")
	for third in [false, true]:
		await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z, 0.0, third)
		var torso := _death.get_physical_bone("spine_03")
		var start := _player.global_position
		_health.apply_damage(500.0, &"golpe", Vector3.BACK)
		await _frames(2)
		var label := "3ª" if third else "1ª"
		_check(_health.is_dead and _death.is_ragdoll_active(), "%s: morto e ragdoll ativo" % label)
		_check(_rig.follow_target == _death.get_physical_bone("Head"), "%s: câmera segue a cabeça física" % label)
		Input.action_press(&"move_forward")
		await _frames(150)
		Input.action_release(&"move_forward")
		_check(_player.get_horizontal_speed() < 0.05, "%s: sem controle depois de morto" % label)
		var head := _death.get_physical_bone("Head").global_position
		_check(head.y - start.y < 0.5, "%s: o corpo caiu até o chão (cabeça a %.2f m)" % [label, head.y - start.y])
		var pushed := (torso.global_position - start).dot(Vector3.BACK)
		_check(pushed > 0.1, "%s: o golpe empurrou o corpo na direção dele (%.2f m)" % [label, pushed])
		_check(_camera.global_position.distance_to(head) < 5.0, "%s: câmera acompanhou o corpo" % label)
		_check(_death.can_respawn(), "%s: renascer liberado após %.1f s" % [label, _death.respawn_delay])
		var hud: PlayerHud = _gym.get_node("PlayerHud")
		_check(hud._death_panel.visible and hud._death_cause.text.contains("golpe"), "%s: tela de morte com a causa" % label)
		await _hold(&"interact", 3)
		await _frames(10)
		_check(not _health.is_dead and is_equal_approx(_health.current, 100.0), "%s: renasceu com vida cheia" % label)
		_check(not _death.is_ragdoll_active() and not _death.simulator.active, "%s: ragdoll desligado" % label)
		_check(_rig.follow_target == null, "%s: câmera de volta ao jogador" % label)
		_check(_bone_height("Head") > 1.4, "%s: corpo animado em pé de novo (cabeça a %.2f m)" % [label, _bone_height("Head")])
		_check(not hud._death_panel.visible, "%s: tela de morte fechada" % label)
		Input.action_press(&"move_forward")
		await _frames(40)
		Input.action_release(&"move_forward")
		_check(_player.get_horizontal_speed() > 1.0, "%s: controle restaurado" % label)


# --- Toque e desempenho ------------------------------------------------------

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
	_begin("Desempenho do animador do corpo")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z, 0.0, true)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	_health.apply_fall_damage(12.0)
	await _frames(20)
	_body.play(BodyAnimator.SLOT_ACTION, &"punch_hook", 1.0, 0.08, 0.15, 1.0, true, true)
	var total := 0
	for i in 120:
		await _frames(1)
		total += _body.last_update_usec
	_release_all()
	_body.release_hold(BodyAnimator.SLOT_ACTION)
	var average := total / 120.0
	print("  (média de %.0f µs por quadro: 65 ossos, locomoção, mancar e golpe ativos)" % average)
	_check(average < 2500.0, "atualização média abaixo de 2,5 ms (%.0f µs)" % average)


func _send_touch(index: int, viewport_position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * viewport_position
	event.pressed = pressed
	get_viewport().push_input(event)


func _send_drag(index: int, viewport_position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * viewport_position
	event.relative = Vector2(0.0, -60.0)
	get_viewport().push_input(event)
