extends Node
## Testes automatizados do corpo animado, da câmera em primeira/terceira
## pessoa, do ragdoll e dos sistemas sincronizados com a animação (vida,
## interação, combate e morte).
##   godot --headless --path . --fixed-fps 60 res://tests/animation_test_runner.tscn
## Filtro: ... -- --only=camera

const GYM_SCENE := "res://scenes/test/movement_test_gym.tscn"
const ACTIONS := [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"jump",
		&"crouch_toggle", &"crouch_hold", &"walk_toggle", &"attack", &"interact", &"toggle_camera", &"block", &"drop_weapon",
		&"hotbar_1", &"hotbar_2", &"hotbar_3", &"hotbar_4", &"inventory_toggle"]
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
		_test_feet_on_slope,
		_test_sounds,
		_test_joystick_dead_zone,
		_test_demo_map,
		_test_first_person_running_camera,
		_test_sound_mix,
		_test_wind,
		_test_weapon_pickup_and_drop,
		_test_weapon_strikes,
		_test_world_generator,
		_test_world_caves_and_roads,
		_test_world_streaming,
		_test_world_walk_and_headlamp,
		_test_world_main_scene,
		_test_inventory_pickup,
		_test_inventory_ui_and_touch,
		_test_chop_tree,
		_test_mine_rock,
		_test_zombie_combat,
		_test_bat_breaks,
		_test_cave_exploration,
		_test_cave_geometry,
		_test_headlamp,
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
	_combat.set_guard(false)
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
	for mesh_name in ["Body", "Head"]:
		_check(meshes.has(mesh_name) and (meshes[mesh_name] as MeshInstance3D).skin != null, "malha %s do Sobrevivente.fbx com skin" % mesh_name)
	_check(meshes.has("Head") and String(meshes["Head"].get_meta(&"view")) == "full" and String(meshes["Body"].get_meta(&"view")) == "both",
			"cabeça (gorro, barba) separada do corpo para a 1ª pessoa")
	_check(_player.stamina == null, "resistência desligada")
	# Proporções naturais ("Regular"): ombros e quadris do esqueleto do pacote de roupas.
	var shoulders := _skeleton.get_bone_global_rest(_skeleton.find_bone("upperarm_l")).origin.distance_to(
			_skeleton.get_bone_global_rest(_skeleton.find_bone("upperarm_r")).origin)
	var hips := _skeleton.get_bone_global_rest(_skeleton.find_bone("thigh_l")).origin.distance_to(
			_skeleton.get_bone_global_rest(_skeleton.find_bone("thigh_r")).origin)
	_check(shoulders > 0.25 and shoulders < 0.45 and hips < 0.25, "proporções naturais: ombros %.3f m, quadris %.3f m" % [shoulders, hips])
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
	await _frames(3)
	_android_touch(3, block_button.get_center_global(), false)
	await _frames(20)
	_check(_combat.is_blocking() and _body.get_layer_weights()["guard"] > 0.8 and block_button.is_active,
			"um toque em DEFESA ergue a guarda e fica (botão mostra GUARDA)")
	_android_touch(3, block_button.get_center_global(), true)
	await _frames(3)
	_android_touch(3, block_button.get_center_global(), false)
	await _frames(20)
	_check(not _combat.is_blocking() and not block_button.is_active, "outro toque abaixa a guarda")
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
	await _hold(&"block", 2)
	await _frames(30)
	_check(_combat.is_blocking() and _body.get_layer_weights()["guard"] > 0.9, "um toque ergue a guarda, sem segurar (%.2f)" % _body.get_layer_weights()["guard"])
	_check(_camera.is_position_in_frustum(_bone("hand_l")) and _camera.is_position_in_frustum(_bone("hand_r")),
			"em 1ª pessoa os dois punhos da guarda aparecem diante dos olhos")
	var forward := -_player.get_view_basis().z
	_health.apply_damage(20.0, &"golpe", -forward)
	await _frames(2)
	_check(is_equal_approx(_health.current, 95.0), "golpe pela frente: 20 → %.0f de dano" % (100.0 - _health.current))
	_check(_body.current_animation(BodyAnimator.SLOT_HURT) == &"block_impact", "reação de impacto na guarda")
	await _frames(40)
	_health.apply_damage(20.0, &"golpe", forward)
	await _frames(2)
	_check(is_equal_approx(_health.current, 75.0), "golpe pelas costas: dano inteiro")
	Input.action_press(&"move_forward")
	await _frames(60)
	_check(_combat.is_blocking() and _player.get_horizontal_speed() < _player.settings.jog_speed * _combat.block_speed_multiplier + 0.1,
			"de guarda anda devagar (%.2f m/s)" % _player.get_horizontal_speed())
	Input.action_press(&"sprint")
	await _frames(40)
	_check(not _combat.is_blocking() and _player.is_sprinting, "correr abaixa a guarda e corre")
	_release_all()
	await _frames(30)
	await _hold(&"block", 2)
	await _frames(20)
	await _hold(&"block", 2)
	await _frames(30)
	_check(not _combat.is_blocking() and _body.get_layer_weights()["guard"] < 0.1 and is_equal_approx(_player.action_speed_multiplier, 1.0),
			"segundo toque abaixa a guarda: braços e velocidade de volta")


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

# --- Etapa 6: pés no terreno, sons, controles e mapa ------------------------

func _ground_below(point: Vector3) -> float:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.0, point + Vector3.DOWN * 2.0, 1)
	ray.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(ray)
	return (hit["position"] as Vector3).y if not hit.is_empty() else point.y


func _test_feet_on_slope() -> void:
	_begin("Pés no terreno: de lado numa rampa de 30°, cada pé apoia no chão (IK)")
	# De lado na rampa: um pé fica morro acima, o outro morro abaixo.
	await _reset(Vector3(12.0, 1.47, -3.5), PI * 0.5)
	await _frames(40)
	var gaps: Array[float] = []
	var heights: Array[float] = []
	for side in ["foot_l", "foot_r"]:
		var foot := _bone(side)
		gaps.append(foot.y - _ground_below(foot))
		heights.append(foot.y)
	_check(absf(gaps[0] - _body.ankle_height) < 0.05 and absf(gaps[1] - _body.ankle_height) < 0.05,
			"tornozelos a %.3f e %.3f m do chão sob cada pé (repouso %.2f m)" % [gaps[0], gaps[1], _body.ankle_height])
	_check(absf(heights[0] - heights[1]) > 0.05, "os pés ficam em alturas diferentes (%.2f m)" % absf(heights[0] - heights[1]))
	_check(_body.get_layer_weights()["pelvis_offset"] < -0.02, "a pélvis desce para o pé mais baixo (%.3f m)" % _body.get_layer_weights()["pelvis_offset"])
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	await _frames(20)
	_check(absf(_body.get_layer_weights()["pelvis_offset"]) < 0.01, "no plano não muda nada (%.3f m)" % _body.get_layer_weights()["pelvis_offset"])


func _test_sounds() -> void:
	_begin("Sons: cada ação do jogo toca o som certo, no momento do evento")
	var sounds: PlayerSounds = _player.get_node("Sounds")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var steps := [0]
	var on_step := func(_i: float, _l: bool, _s: SurfaceProfile) -> void: steps[0] += 1
	_player.footstep.connect(on_step)
	var before := sounds.count(&"passo")
	Input.action_press(&"move_forward")
	await _frames(120)
	_release_all()
	_player.footstep.disconnect(on_step)
	_check(steps[0] >= 3 and sounds.count(&"passo") - before == steps[0], "um som de passo por contato do pé (%d passos, %d sons)" % [steps[0], sounds.count(&"passo") - before])
	_check(PlayerSounds.step_set_for(load("res://resources/surfaces/grama.tres")) == "grama"
			and PlayerSounds.step_set_for(load("res://resources/surfaces/gelo.tres")) == "gelo"
			and PlayerSounds.step_set_for(load("res://resources/surfaces/terra.tres")) == "terra", "passo diferente por superfície (terra, grama, gelo)")
	await _reset(Vector3(30.0, 0.0, 10.0), YAW_TOWARD_POSITIVE_Z)
	_player.teleport(Vector3(30.0, 3.0, 10.0))
	var landings := sounds.count(&"aterrissagem")
	await _frames(90)
	_check(sounds.count(&"aterrissagem") == landings + 1, "aterrissagem soa uma vez ao cair de 3 m")
	var dummy := await _face_dummy()
	var swings := sounds.count(&"golpe_ar")
	var punches := sounds.count(&"soco_corpo")
	await _hold(&"attack", 2)
	await _frames(40)
	_check(sounds.count(&"golpe_ar") == swings + 1 and sounds.count(&"soco_corpo") == punches + 1,
			"soco: braço cortando o ar e acerto no corpo")
	var pains := sounds.count(&"dor")
	_health.apply_damage(15.0, &"golpe", Vector3.BACK)
	await _frames(2)
	_check(sounds.count(&"dor") == pains + 1, "dor ao levar um golpe")
	var falls := sounds.count(&"queda_corpo")
	_health.apply_damage(500.0, &"golpe", Vector3.BACK)
	await _frames(60)
	_check(sounds.count(&"morte") >= 1 and sounds.count(&"queda_corpo") == falls + 1, "morte e o corpo caindo")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	_check(ImpactSound.material_of(dummy) == &"corpo", "boneco de treino soa como corpo")
	_check(not SoundSet.load_set("ambience/vento").streams.is_empty() and not SoundSet.load_set("world/fogueira").streams.is_empty(),
			"vento e fogueira carregados")
	_check(not ResourceLoader.exists("res://assets/audio/ambience/floresta.ogg") and not ResourceLoader.exists("res://assets/audio/ambience/passaros.ogg"),
			"sem trilha sonora nem passarinhos")


func _test_joystick_dead_zone() -> void:
	_begin("Direcional: zona morta (dedo apoiado não anda) e resposta suave")
	var controls: TouchControls = _gym.get_node("TouchControlsLayer/TouchControls")
	var stick: TouchMoveStick = controls.joystick
	stick.begin(Vector2(200.0, 500.0))
	stick.drag(Vector2(200.0, 500.0 - stick.radius * stick.dead_zone * 0.8))
	_check(stick.output.length() < 0.001, "dedo quase parado: nenhum movimento")
	stick.drag(Vector2(200.0, 500.0 - stick.radius * 0.5))
	var half := stick.output.length()
	stick.drag(Vector2(200.0, 500.0 - stick.radius))
	_check(half > 0.3 and half < 0.6 and is_equal_approx(stick.output.length(), 1.0), "meio curso %.2f, curso total 1,00" % half)
	stick.end()
	await _frames(2)


func _test_demo_map() -> void:
	_begin("Mapa ampliado: 400 m, área original intacta, sons do mundo")
	var map: Node3D = (load("res://scenes/demo/demo_forest.tscn") as PackedScene).instantiate()
	var terrain: MeshInstance3D = map.get_node("Terrain/TerrainMesh")
	var size := terrain.mesh.get_aabb().size
	_check(size.x >= 399.0 and size.z >= 399.0, "terreno de %.0f × %.0f m" % [size.x, size.z])
	var trees := 0
	var chunks := 0
	var all_ranged := true
	for child in map.get_node("Forest").get_children():
		if child is ScatterInstances and String(child.name).begins_with("Firs"):
			trees += (child as ScatterInstances).transforms.size()
			chunks += 1
			all_ranged = all_ranged and (child as ScatterInstances).max_distance > 0.0
	_check(trees >= 6000 and chunks > 50 and all_ranged, "%d árvores em %d blocos, todos com distância de desenho" % [trees, chunks])
	var campfires := map.find_children("Campfire", "", true, false).size()
	_check(campfires == 2, "duas fogueiras (clareira e acampamento de caçadores): %d" % campfires)
	for poi in ["Checkpoint", "HunterCamp", "NorthRoadblock", "Lookout"]:
		_check(map.has_node(poi), "%s presente" % poi)
	var rigid_with_sound := 0
	var rigid := 0
	for body in map.find_children("*", "RigidBody3D", true, false):
		rigid += 1
		if body.has_node("ImpactSound"):
			rigid_with_sound += 1
	_check(rigid > 10 and rigid_with_sound == rigid, "todos os %d objetos soltos têm som de batida" % rigid)
	map.free()



func _test_first_person_running_camera() -> void:
	_begin("1ª pessoa correndo: câmera nos olhos (nunca atrás, dentro da gola), FOV de velocidade")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var base_fov := _camera.fov
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(60)
	var worst_gap := 0.0
	var worst_behind := 1.0
	for i in 60:
		await _frames(1)
		var eye := _body.get_eye_position()
		var gap := Vector2(_camera.global_position.x - eye.x, _camera.global_position.z - eye.z).length()
		worst_gap = maxf(worst_gap, gap)
		worst_behind = minf(worst_behind, (_camera.global_position - _bone("Head")).dot(_forward()))
	_check(worst_gap < 0.08, "câmera acompanha os olhos com o tronco inclinado (afastamento máx. %.3f m)" % worst_gap)
	_check(worst_behind > 0.0, "a câmera fica sempre à frente da cabeça (mín. %.3f m)" % worst_behind)
	_check(_camera.fov > base_fov + 3.0, "campo de visão abre na corrida (%.1f° → %.1f°)" % [base_fov, _camera.fov])
	_release_all()
	await _frames(90)
	_check(absf(_camera.fov - base_fov) < 1.0, "e volta ao parar (%.1f°)" % _camera.fov)


func _test_sound_mix() -> void:
	_begin("Sons: camadas do passo, aterrissagem com os dois pés, respiração pelo esforço")
	var sounds: PlayerSounds = _player.get_node("Sounds")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	var steps := sounds.count(&"passo")
	var leaves := sounds.count(&"passo_folhas")
	Input.action_press(&"move_forward")
	await _frames(90)
	_release_all()
	var made := sounds.count(&"passo") - steps
	_check(made >= 2 and sounds.count(&"passo_folhas") - leaves == made, "chão de floresta: calcanhar + folhas em cada passo (%d passos)" % made)
	await _frames(30)
	_player.teleport(_player.global_position + Vector3.UP * 3.0)
	var before := sounds.count(&"passo")
	await _frames(90)
	_check(sounds.count(&"passo") - before >= 2, "aterrissagem: os dois pés batendo no chão")
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	sounds.effort = 0.0
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(60 * 5)
	_check(sounds.effort > 0.5, "correr 5 s cansa (esforço %.2f)" % sounds.effort)
	_release_all()
	# Respirações avulsas num ritmo humano (não ofegante): conta por 10 s.
	var start_breaths := sounds.breaths_played
	await _frames(60 * 10)
	var per_minute := (sounds.breaths_played - start_breaths) * 6.0
	_check(per_minute >= 12.0 and per_minute <= 42.0, "respiração depois da corrida: %.0f por minuto" % per_minute)
	_check(sounds.effort < 0.5, "parado, o fôlego volta aos poucos (esforço %.2f)" % sounds.effort)


func _test_wind() -> void:
	_begin("Vento: um só ambiente, com a intensidade movendo som e árvores")
	var wind: Node = get_node("/root/Wind")
	wind.set("override", 0.05)
	await _frames(240)
	var calm_volume: float = (wind.get("_player") as AudioStreamPlayer).volume_db
	var calm_cutoff: float = (wind.get("_filter") as AudioEffectLowPassFilter).cutoff_hz
	var calm_shader: float = wind.get("intensity")
	wind.set("override", 0.95)
	await _frames(240)
	var strong_volume: float = (wind.get("_player") as AudioStreamPlayer).volume_db
	var strong_cutoff: float = (wind.get("_filter") as AudioEffectLowPassFilter).cutoff_hz
	var strong_shader: float = wind.get("intensity")
	_check(strong_volume > calm_volume + 15.0, "vento forte é mais alto (%.0f dB → %.0f dB)" % [calm_volume, strong_volume])
	_check(strong_cutoff > calm_cutoff * 4.0, "vento fraco é abafado, forte chia (%.0f Hz → %.0f Hz)" % [calm_cutoff, strong_cutoff])
	_check(strong_shader > 0.8 and calm_shader < 0.2, "a copa das árvores segue a mesma intensidade (%.2f → %.2f)" % [calm_shader, strong_shader])
	wind.set("override", -1.0)


# --- Morte e ragdoll ---------------------------------------------------------

# --- Etapa 7: armas brancas ---------------------------------------------------

const WEAPONS := ["res://resources/weapons/taco.tres", "res://resources/weapons/machado.tres", "res://resources/weapons/picareta.tres"]


## Esvazia a mochila e as mãos.
func _clear_inventory() -> void:
	var inventory: Inventory = _player.get_node("Inventory")
	inventory.unequip()
	for i in Inventory.TOOL_SLOTS:
		inventory.tools[i] = {}
	inventory.resources.clear()
	inventory.changed.emit()


## Solta a arma no chão diante do jogador, mira nela e aperta USAR.
func _pick_up_from_ground(data: WeaponData, spot: Vector3) -> RigidBody3D:
	var body := WeaponPickup.spawn(data, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), spot + Vector3.UP * 0.3), _gym)
	await _frames(90)
	# Mira na arma. Ao olhar para baixo a cabeça (e a câmera em 1ª pessoa)
	# avança um pouco, então a mira é corrigida até assentar, como o jogador faz.
	for attempt in 3:
		var eye := _camera.global_position
		var target := body.global_position
		_player.set_view_rotation(_player.get_view_yaw(), atan2(target.y - eye.y, Vector2(target.x - eye.x, target.z - eye.z).length()))
		_rig.snap()
		await _frames(20)
	_check(_interaction.focused is WeaponPickup and (_interaction.focused as WeaponPickup).prompt == "Pegar " + data.display_name.to_lower(),
			"mira na arma mostra \"Pegar %s\"" % data.display_name.to_lower())
	await _hold(&"interact", 2)
	await _frames(90)
	return body


func _test_weapon_pickup_and_drop() -> void:
	_begin("Armas: pegar do chão, empunhar, soltar e trocar")
	var equipment: PlayerEquipment = _player.get_node("Equipment")
	_clear_inventory()
	for path in WEAPONS:
		var data: WeaponData = load(path)
		var box := data.mesh.get_aabb()
		_check(box.size.y > 0.75 and box.size.y < 1.0 and data.mesh.get_surface_count() >= 1,
				"%s: malha de %.2f m, empunhadura na origem (de %.2f a %.2f m)" % [data.display_name, box.size.y, box.position.y, box.end.y])
		_check(box.position.y < 0.0 and box.position.y > -0.2, "%s: cabo passa pela mão" % data.display_name)
	var bat: WeaponData = load(WEAPONS[0])
	var axe: WeaponData = load(WEAPONS[1])
	await _reset(Vector3(30.0, 0.0, 10.0), YAW_TOWARD_POSITIVE_Z)
	var ground := _player.global_position + _forward() * 0.9
	var dropped := await _pick_up_from_ground(bat, ground)
	_check(equipment.weapon == bat, "pegou o taco do chão com USAR (%s)" % (equipment.weapon.display_name if equipment.weapon else "nada"))
	_check(not is_instance_valid(dropped), "o taco saiu do chão")
	var model := _skeleton.get_node_or_null("RightHandWeapon/WeaponModel") as MeshInstance3D
	_check(model != null and model.visible and model.mesh == bat.mesh, "taco preso ao osso da mão direita")
	if model != null:
		var hand := _bone("hand_r")
		_check(model.global_position.distance_to(hand) < 0.15, "empunhadura junto da mão (%.2f m)" % model.global_position.distance_to(hand))
	_check(_body.guard_clip == &"weapon_idle", "postura de arma empunhada")
	var drop_buttons := get_tree().get_nodes_in_group(&"drop_weapon_button")
	_check(drop_buttons.is_empty() or (drop_buttons[0] as Control).visible, "botão SOLTAR aparece com arma na mão")
	# Pegar outra: vai para a mochila (a da mão continua na mão) e troca-se
	# pela barra rápida.
	var inventory: Inventory = _player.get_node("Inventory")
	await _pick_up_from_ground(axe, _player.global_position + _forward() * 0.9)
	_check(equipment.weapon == bat and inventory.has_tool(&"machado") and inventory.has_tool(&"taco"),
			"machado guardado na mochila, taco continua na mão")
	await _hold(&"hotbar_2", 2)
	await _frames(5)
	_check(equipment.weapon == axe and inventory.selected == 1, "tecla 2 empunha o machado")
	await _hold(&"hotbar_2", 2)
	await _frames(5)
	_check(equipment.weapon == null and inventory.has_tool(&"machado"), "de novo: guarda (mãos livres, machado na mochila)")
	await _hold(&"hotbar_2", 2)
	await _frames(5)
	# Soltar.
	await _hold(&"drop_weapon", 2)
	await _frames(60)
	_check(equipment.weapon == null and not model.visible and not inventory.has_tool(&"machado"), "soltou o machado (G / direcional baixo)")
	_check(_body.guard_clip == BodyAnimator.GUARD_CLIP, "voltou à guarda de punhos")
	_check(drop_buttons.is_empty() or not (drop_buttons[0] as Control).visible, "botão SOLTAR some sem arma")
	for child in _gym.get_children():
		if child is RigidBody3D and child.has_node("WeaponPickup"):
			_check(child.global_position.y > -1.0 and child.global_position.y < 1.0, "%s parou no chão (y %.2f)" % [child.name, child.global_position.y])
			child.queue_free()
	await _frames(5)


func _test_weapon_strikes() -> void:
	_begin("Armas: golpes com dano, alcance e animação da arma")
	var equipment: PlayerEquipment = _player.get_node("Equipment")
	var dummy: TrainingDummy = _gym.get_node("TrainingDummyStation/TrainingDummy")
	# A 0,45 m além da distância do soco, o punho não chega.
	await _reset(Vector3(-5.0, 0.0, 10.4), 0.0)
	var hits := dummy.hits
	await _hold(&"attack", 2)
	await _frames(60)
	_check(dummy.hits == hits, "sem arma, o soco não alcança a 0,45 m a mais")
	for path in WEAPONS:
		var data: WeaponData = load(path)
		equipment.equip(data)
		await _reset(Vector3(-5.0, 0.0, 10.4), 0.0)
		await _frames(120)
		hits = dummy.hits
		await _hold(&"attack", 2)
		await _frames(3)
		_check(_body.current_animation(BodyAnimator.SLOT_ACTION) == &"weapon_swing_a", "%s: golpe rápido de arma" % data.display_name)
		await _frames(60)
		_check(dummy.hits == hits + 1 and is_equal_approx(dummy.last_damage, data.light_damage),
				"%s: acerta mais longe com dano %.0f (%.0f)" % [data.display_name, data.light_damage, dummy.last_damage])
		await _frames(120)
	# Golpe carregado com o machado.
	var axe: WeaponData = load(WEAPONS[1])
	equipment.equip(axe)
	await _reset(Vector3(-5.0, 0.0, 10.4), 0.0)
	await _frames(150)
	hits = dummy.hits
	Input.action_press(&"attack")
	await _frames(70)
	_check(_body.current_animation(BodyAnimator.SLOT_ACTION) == &"weapon_swing_b" and _body.is_holding(BodyAnimator.SLOT_ACTION),
			"machado: segura a preparação do golpe amplo")
	Input.action_release(&"attack")
	await _frames(50)
	_check(dummy.hits == hits + 1 and dummy.last_damage > axe.light_damage and dummy.last_damage <= axe.heavy_max_damage,
			"machado carregado: dano %.1f (entre %.0f e %.0f)" % [dummy.last_damage, axe.light_damage, axe.heavy_max_damage])
	await _frames(90)
	equipment.drop()
	for child in _gym.get_children():
		if child is RigidBody3D and child.has_node("WeaponPickup"):
			child.queue_free()
	await _frames(5)


# --- Etapa 7: mundo procedural por pedaços ------------------------------------

const WORLD_SEED := 20261102
## Longe do ginásio de testes (que fica em volta da origem).
const FAR := Vector3(6000.0, 0.0, 6000.0)


func _test_world_generator() -> void:
	_begin("Mundo: geração determinística, sem emendas e rápida")
	var a := WorldGenerator.new(WORLD_SEED)
	var b := WorldGenerator.new(WORLD_SEED)
	var other := WorldGenerator.new(WORLD_SEED + 1)
	var coord := Vector2i(3, -7)
	var first := a.build_chunk(coord)
	var again := b.build_chunk(coord)
	var different := other.build_chunk(coord)
	var v1: PackedVector3Array = first["mesh"]["vertices"]
	var v2: PackedVector3Array = again["mesh"]["vertices"]
	var v3: PackedVector3Array = different["mesh"]["vertices"]
	_check(v1 == v2 and first["wrecks"].size() == again["wrecks"].size() and str(first["trees"]) == str(again["trees"]),
			"mesma semente, mesmo pedaço: idêntico (%d vértices)" % v1.size())
	_check(v1 != v3, "outra semente gera outro mundo")
	# Costura: os vértices da faixa de células compartilhada entre dois
	# vizinhos saem iguais nos dois (sem frestas nem degraus na borda).
	var left := a.build_chunk(Vector2i(0, 0))
	var right := a.build_chunk(Vector2i(1, 0))
	var edge := WorldGenerator.CHUNK_SIZE
	var on_left := {}
	for v: Vector3 in left["mesh"]["vertices"]:
		if v.x > edge - WorldGenerator.CELL and v.x < edge:
			on_left[v.snapped(Vector3.ONE * 0.001)] = true
	var on_right := {}
	for v: Vector3 in right["mesh"]["vertices"]:
		if v.x > edge - WorldGenerator.CELL and v.x < edge:
			on_right[v.snapped(Vector3.ONE * 0.001)] = true
	var shared := 0
	for key in on_left:
		if on_right.has(key):
			shared += 1
	_check(on_left.size() > 10 and shared == on_left.size() and on_right.size() == on_left.size(),
			"borda entre pedaços: %d de %d vértices idênticos nos dois lados" % [shared, on_left.size()])
	# Faces da frente para o ar: o triângulo gira no sentido horário visto de
	# fora (o produto vetorial aponta contra a normal da superfície).
	var mesh: Dictionary = first["mesh"]
	var vertices: PackedVector3Array = mesh["vertices"]
	var normals: PackedVector3Array = mesh["normals"]
	var indices: PackedInt32Array = mesh["indices"]
	var outward := 0
	for t in indices.size() / 3:
		var p0 := vertices[indices[t * 3]]
		var cross := (vertices[indices[t * 3 + 1]] - p0).cross(vertices[indices[t * 3 + 2]] - p0)
		if cross.dot(normals[indices[t * 3]] + normals[indices[t * 3 + 1]] + normals[indices[t * 3 + 2]]) < 0.0:
			outward += 1
	_check(outward >= indices.size() / 3 * 0.95, "%d%% das faces viradas para o ar" % (outward * 100 / maxi(indices.size() / 3, 1)))
	var started := Time.get_ticks_usec()
	for i in 4:
		a.build_chunk(Vector2i(20 + i, 11))
	var ms := (Time.get_ticks_usec() - started) / 4000.0
	_check(ms < 250.0, "um pedaço de 32 × 32 m gerado em %.0f ms (em segundo plano)" % ms)


func _test_world_caves_and_roads() -> void:
	_begin("Mundo: cavernas com bocas, estradas planas e engarrafamentos")
	var g := WorldGenerator.new(WORLD_SEED)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var air := 0
	var samples := 6000
	for i in samples:
		var x := rng.randf_range(-400.0, 400.0)
		var z := rng.randf_range(-400.0, 400.0)
		var y := rng.randf_range(WorldGenerator.FLOOR_Y + 5.0, g.surface_height(x, z) - 4.0)
		if g.density(x, y, z) < 0.0:
			air += 1
	_check(air > samples * 0.02, "%.1f%% do subsolo é caverna" % (air * 100.0 / samples))
	# Bocas: as únicas aberturas são as rampas de entrada (os poços verticais
	# da etapa 7 foram eliminados na etapa 8). Cada uma tem a boca aberta
	# na superfície e o túnel desobstruído até a galeria.
	var ramps := g.entrances_near(Vector3.ZERO, 800.0)
	var open := 0
	for ramp in ramps:
		var top: Vector3 = ramp["top"]
		var bottom: Vector3 = ramp["bottom"]
		var middle := top.lerp(bottom, 0.5)
		var middle_floor := lerpf(top.y, bottom.y, 0.5 / 0.8)
		if g.density(top.x, top.y + 1.0, top.z) < 0.0 and g.density(middle.x, middle_floor + 1.5, middle.z) < 0.0:
			open += 1
	_check(ramps.size() >= 8 and open == ramps.size(), "%d entradas de caverna em rampa, todas com boca e túnel abertos" % open)
	_check(g.density(0.0, WorldGenerator.FLOOR_Y + 1.0, 0.0) > 0.0, "leito de rocha no fundo")
	# Estrada: plana de lado a lado e sem buracos de caverna sob o asfalto.
	var worst := 0.0
	var holes := 0
	for i in 60:
		var z := rng.randf_range(-1500.0, 1500.0)
		var cx := g.highway_center_x(0.0, z)
		worst = maxf(worst, absf(g.surface_height(cx - 3.0, z) - g.surface_height(cx + 3.0, z)))
		var s := g.surface_height(cx, z)
		for depth in [0.5, 3.0, 8.0]:
			if g.density(cx, s - depth, z) < 0.0:
				holes += 1
	_check(worst < 0.6, "rodovia nivelada de lado a lado (desnível máximo %.2f m em 6 m)" % worst)
	_check(holes == 0, "nenhuma caverna abre sob o asfalto (%d)" % holes)
	# Engarrafamentos: carcaças na rodovia, todas sobre a pista ou no barranco.
	var wrecks := 0
	var off_road := 0
	var weapons := 0
	var z := -640.0
	while z < 640.0:
		var cx := g.highway_center_x(0.0, z)
		var data := g.build_chunk(ProceduralWorld.chunk_of(Vector3(cx, 0.0, z)))
		for entry in data["wrecks"]:
			var t: Transform3D = entry[1]
			var r := g.road_distances(t.origin.x, t.origin.z)
			wrecks += 1
			if minf(r.x, r.y) > WorldGenerator.HIGHWAY_HALF_WIDTH + 5.0:
				off_road += 1
		weapons += (data["weapons"] as Array).size()
		z += WorldGenerator.CHUNK_SIZE
	_check(wrecks >= 20 and off_road == 0, "%d carcaças ao longo de 1,3 km de rodovia, todas na estrada ou no acostamento" % wrecks)
	_check(weapons >= 1, "armas largadas pelo caminho (%d)" % weapons)


func _world_node(view: int) -> ProceduralWorld:
	var world := ProceduralWorld.new()
	world.world_seed = WORLD_SEED
	world.view_distance = view
	world.max_tasks = 4
	world.applies_per_frame = 4
	return world


func _test_world_streaming() -> void:
	_begin("Mundo: pedaços carregam em volta do jogador e descarregam atrás")
	var marker := Node3D.new()
	add_child(marker)
	marker.global_position = FAR
	var world := _world_node(2)
	world.target = marker
	add_child(world)
	# Tempo real (com --fixed-fps os quadros não esperam o relógio, mas as
	# tarefas em segundo plano levam o tempo delas).
	var started := Time.get_ticks_msec()
	while world.loaded_chunks().size() < 21 and Time.get_ticks_msec() - started < 30000:
		await _frames(1)
	var count := world.loaded_chunks().size()
	_check(count == 21, "21 pedaços num raio de 2 (%d em %.2f s)" % [count, (Time.get_ticks_msec() - started) / 1000.0])
	_check(world.is_ready_around(FAR, 1), "pedaços em volta prontos")
	var first := ProceduralWorld.chunk_of(FAR)
	var chunk := world.chunk_node(first)
	_check(chunk != null and chunk.has_node("Terreno") and chunk.has_node("Chao"), "pedaço tem malha e colisão")
	_check(world.average_generation_ms() > 0.0, "geração em segundo plano: %.0f ms por pedaço" % world.average_generation_ms())
	# Anda 6 pedaços para leste.
	marker.global_position = FAR + Vector3(6.0 * WorldGenerator.CHUNK_SIZE, 0.0, 0.0)
	started = Time.get_ticks_msec()
	while world.chunk_node(ProceduralWorld.chunk_of(marker.global_position) + Vector2i(2, 0)) == null and Time.get_ticks_msec() - started < 30000:
		await _frames(1)
	await _frames(5)
	_check(world.is_ready_around(marker.global_position, 1), "novo lugar carregado em %.2f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	_check(not world.is_loaded(first), "pedaço que ficou para trás foi descarregado")
	_check(world.loaded_chunks().size() <= 30, "memória limitada: %d pedaços carregados" % world.loaded_chunks().size())
	world.queue_free()
	marker.queue_free()
	await _frames(5)


func _test_world_walk_and_headlamp() -> void:
	_begin("Mundo: andar no chão gerado, armas no mundo e lanterna na caverna")
	var world := _world_node(1)
	world.target = _player
	add_child(world)
	await _frames(1)
	var g := world.generator
	# Um ponto plano fora da estrada.
	var spot := FAR
	for i in 200:
		var x := FAR.x + i * 7.0
		if g.slope_at(x, FAR.z) < 0.15 and g.road_distances(x, FAR.z).x > 12.0:
			spot = Vector3(x, g.surface_height(x, FAR.z), FAR.z)
			break
	world.generate_now(spot, 1)
	await _reset(spot + Vector3.UP * 0.1, 0.0)
	_check(_player.is_on_floor() and absf(_player.global_position.y - spot.y) < 0.5,
			"jogador em pé no terreno gerado (y %.2f, chão %.2f)" % [_player.global_position.y, spot.y])
	var start := _player.global_position
	Input.action_press(&"move_forward")
	await _frames(150)
	Input.action_release(&"move_forward")
	await _frames(30)
	var moved := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	var ground := g.surface_height(_player.global_position.x, _player.global_position.z)
	_check(moved > 3.0 and _player.global_position.y > ground - 0.6,
			"andou %.1f m sobre a colisão do terreno (y %.2f, chão %.2f)" % [moved, _player.global_position.y, ground])
	# Armas: o pedaço que tem uma arma a mostra como corpo físico pegável.
	var loot := Vector2i.ZERO
	var found := false
	for i in 400:
		var coord := Vector2i(190 + i % 20, 190 + i / 20)
		var data := g.build_chunk(coord)
		if not (data["weapons"] as Array).is_empty():
			loot = coord
			found = true
			break
	if found:
		var center := Vector3((loot.x + 0.5) * WorldGenerator.CHUNK_SIZE, 0.0, (loot.y + 0.5) * WorldGenerator.CHUNK_SIZE)
		world.generate_now(center, 0)
		var pickups := world.chunk_node(loot).find_children("WeaponPickup", "WeaponPickup", true, false)
		_check(pickups.size() >= 1, "arma do pedaço %s apareceu no chão (%d)" % [loot, pickups.size()])
	else:
		_check(false, "nenhum pedaço com arma encontrado")
	# Lanterna: câmera numa caverna acende; na superfície, apaga.
	var cave := Vector3.INF
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 100000:
		var x := FAR.x + rng.randf_range(-150.0, 150.0)
		var z := FAR.z + rng.randf_range(-150.0, 150.0)
		var s := g.surface_height(x, z)
		var y := rng.randf_range(WorldGenerator.FLOOR_Y + 6.0, s - 10.0)
		if g.density(x, y, z) < 0.0 and g.density(x, y - 1.0, z) > 0.0 and g.density(x, y + 2.5, z) < 0.0:
			cave = Vector3(x, y, z)
			break
	_check(cave != Vector3.INF, "caverna encontrada para o teste da lanterna")
	if cave != Vector3.INF:
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.ambient_light_energy = 1.0
		add_child(environment)
		var camera := Camera3D.new()
		add_child(camera)
		var atmosphere := CaveAtmosphere.new()
		atmosphere.world = world
		atmosphere.camera = camera
		atmosphere.environment = environment
		atmosphere.adapt_time = 0.3
		add_child(atmosphere)
		camera.global_position = cave + Vector3.UP * 1.6
		await _frames(60)
		_check(atmosphere.underground > 0.9 and atmosphere.headlamp.visible and atmosphere.headlamp.light_energy > 1.0,
				"dentro da caverna: lanterna acesa (%.1f), luz do céu %.2f" % [atmosphere.headlamp.light_energy, environment.environment.ambient_light_energy])
		var surface := Vector3(cave.x, g.surface_height(cave.x, cave.z) + 1.6, cave.z)
		camera.global_position = surface
		await _frames(60)
		_check(atmosphere.underground < 0.05 and not atmosphere.headlamp.visible and environment.environment.ambient_light_energy > 0.95,
				"de volta à superfície: lanterna apagada e céu de volta")
		atmosphere.queue_free()
		camera.queue_free()
		environment.queue_free()
	world.queue_free()
	await _frames(5)


func _test_world_main_scene() -> void:
	_begin("Mundo: cena principal começa na rodovia, em chão firme")
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/world/mundo.tscn", "mundo procedural é a cena principal")
	var scene: Node3D = (load("res://scenes/world/mundo.tscn") as PackedScene).instantiate()
	add_child(scene)
	var world: ProceduralWorld = scene.get_node("ProceduralWorld")
	var player: PlayerController = scene.get_node("Player")
	await _frames(40)
	var spawn := world.generator.spawn_point()
	var roads := world.generator.road_distances(player.global_position.x, player.global_position.z)
	_check(player.is_on_floor() and absf(player.global_position.y - spawn.y) < 0.6,
			"jogador em pé no ponto de partida (y %.2f, chão %.2f)" % [player.global_position.y, spawn.y])
	_check(roads.x < WorldGenerator.HIGHWAY_HALF_WIDTH, "começa sobre a rodovia (%.1f m do eixo)" % roads.x)
	_check(world.loaded_chunks().size() >= 9, "%d pedaços prontos logo na partida" % world.loaded_chunks().size())
	var caves: CaveAtmosphere = scene.get_node("CaveAtmosphere")
	_check(caves.underground < 0.01 and not caves.headlamp.visible, "na superfície a lanterna fica apagada")
	scene.queue_free()
	await _frames(5)
	_camera.make_current()


# --- Etapa 8: mochila, coleta, zumbis e cavernas --------------------------------

## Mira num corpo (corrigindo enquanto a cabeça assenta) e aperta PEGAR.
func _aim_and_take(body: Node3D) -> void:
	for attempt in 3:
		var eye := _camera.global_position
		var target := body.global_position
		var flat := Vector2(target.x - eye.x, target.z - eye.z)
		_player.set_view_rotation(atan2(-flat.x, -flat.y), atan2(target.y - eye.y, flat.length()))
		_rig.snap()
		await _frames(20)
	await _hold(&"interact", 2)
	await _frames(90)


## Olha para um ponto (yaw e pitch a partir dos olhos).
func _look_at_point(target: Vector3) -> void:
	var eye := _camera.global_position
	var flat := Vector2(target.x - eye.x, target.z - eye.z)
	_player.set_view_rotation(atan2(-flat.x, -flat.y), atan2(target.y - eye.y, flat.length()))
	_rig.snap()


func _test_inventory_pickup() -> void:
	_begin("Mochila: PEGAR coloca na mochila (com nome e ícone), sem pegar duas vezes")
	var inventory: Inventory = _player.get_node("Inventory")
	var hud: InventoryHud = _gym.get_node("InventoryHud")
	_clear_inventory()
	await _reset(Vector3(30.0, 0.0, 10.0), YAW_TOWARD_POSITIVE_Z)
	for id in [&"machado", &"picareta", &"taco", &"madeira", &"pedra", &"carvao", &"ferro"]:
		var item := ItemData.find(id)
		_check(item != null and item.get_icon() != null and item.display_name != "", "%s: item com nome e ícone" % id)
	var added := []
	var on_added := func(item: ItemData, amount: int) -> void: added.append([item.id, amount])
	inventory.item_added.connect(on_added)
	# Machado no chão: o cartão mostra o ícone, o toque vira PEGAR.
	var axe := WeaponPickup.spawn(load(WEAPONS[1]), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), _player.global_position + _forward() * 0.9 + Vector3.UP * 0.3), _gym)
	await _frames(90)
	for attempt in 3:
		_look_at_point(axe.global_position)
		await _frames(20)
	var interact_button: TouchActionButton = _gym.get_node("TouchControlsLayer/TouchControls/InteractButton")
	_check(_interaction.focused is WeaponPickup and interact_button.label == "PEGAR" and hud._card.visible,
			"mirando: botão PEGAR e cartão com o ícone do machado")
	await _hold(&"interact", 2)
	await _frames(90)
	_check(inventory.has_tool(&"machado") and not is_instance_valid(axe), "pegou: machado na mochila, sumiu do chão")
	_check(inventory.equipped_item() != null and inventory.equipped_item().id == &"machado", "mãos livres: já empunha o machado")
	_check(added.size() == 1 and added[0][0] == &"machado", "aviso de coleta com o nome do item (%s)" % str(added))
	# Não dá para pegar duas vezes o mesmo objeto: dois toques no mesmo
	# quadro (antes de o corpo sumir) contam uma vez só.
	var twice := ItemPickup.spawn(ItemData.find(&"carvao"), Transform3D(Basis.IDENTITY, _player.global_position + Vector3(2.0, 0.3, 0.0)), _gym)
	var twice_pickup: ItemPickup = twice.get_node("ItemPickup")
	twice_pickup.interact(_player)
	twice_pickup.interact(_player)
	await _frames(5)
	_check(inventory.count(&"carvao") == 1, "o mesmo objeto não entra duas vezes (%d carvão)" % inventory.count(&"carvao"))
	# Recursos empilham.
	var stones := ItemPickup.spawn(ItemData.find(&"pedra"), Transform3D(Basis.IDENTITY, _player.global_position + _forward() * 1.0 + Vector3.UP * 0.3), _gym, 3)
	await _frames(60)
	await _aim_and_take(stones)
	_check(inventory.count(&"pedra") == 3 and not is_instance_valid(stones), "pegou 3 pedras de uma vez (%d)" % inventory.count(&"pedra"))
	# Guardar e soltar.
	await _hold(&"hotbar_1", 2)
	await _frames(5)
	_check(inventory.selected == -1 and inventory.has_tool(&"machado") and (_player.get_node("Equipment") as PlayerEquipment).weapon == null,
			"guardar: tecla 1 de novo, machado na mochila e mãos livres")
	inventory.drop_resource(&"pedra", 1)
	await _frames(60)
	var loose := 0
	for child in _gym.get_children():
		if child.has_node("ItemPickup"):
			loose += 1
	_check(inventory.count(&"pedra") == 2 and loose == 1, "soltar 1 pedra: vira objeto no chão (%d na mochila)" % inventory.count(&"pedra"))
	inventory.item_added.disconnect(on_added)
	for child in _gym.get_children():
		if child.has_node("ItemPickup") or child.has_node("WeaponPickup"):
			child.queue_free()
	_clear_inventory()
	await _frames(5)


func _test_inventory_ui_and_touch() -> void:
	_begin("Mochila: painel (I / MOCHILA) e barra rápida no toque, sem golpes acidentais")
	var inventory: Inventory = _player.get_node("Inventory")
	var hud: InventoryHud = _gym.get_node("InventoryHud")
	_clear_inventory()
	await _reset(OPEN_LANE, YAW_TOWARD_POSITIVE_Z)
	inventory.add(ItemData.find(&"taco"))
	inventory.add(ItemData.find(&"picareta"))
	inventory.add(ItemData.find(&"madeira"), 4)
	inventory.unequip()
	await _hold(&"inventory_toggle", 2)
	await _frames(5)
	_check(hud.is_open and not _player.input_enabled, "I abre a mochila e o personagem para")
	_check(hud._tool_list.get_child_count() == 2 and hud._resource_list.get_child_count() == 1, "lista 2 ferramentas e 1 recurso")
	var start := _player.global_position
	await _hold(&"move_forward", 30)
	_check(_player.global_position.distance_to(start) < 0.05, "com a mochila aberta não anda")
	hud.close()
	await _frames(5)
	_check(not hud.is_open and _player.input_enabled, "fecha e volta a controlar")
	# Organizar: picareta antes de taco.
	inventory.sort()
	_check((inventory.tool_at(0)["item"] as ItemData).id == &"picareta", "ORGANIZAR ordena as ferramentas")
	# Toque: tocar na casa 2 da barra empunha o taco; não ataca.
	var controls := _touch_setup()
	var attacks := [0]
	var on_attack := func(_kind: StringName) -> void: attacks[0] += 1
	_combat.attack_started.connect(on_attack)
	await _frames(5)
	var slot := InventoryHud.slot_center(1, _screen())
	_check(controls.get_target_at(slot) == &"button:HotbarSlot2", "casa 2 da barra é um botão do toque (%s)" % controls.get_target_at(slot))
	_android_touch(0, slot, true)
	await _frames(3)
	_android_touch(0, slot, false)
	await _frames(10)
	_check(inventory.selected == 1 and (inventory.equipped_item() as ItemData).id == &"taco", "toque na casa 2 empunha o taco")
	_check(attacks[0] == 0, "tocar na barra não golpeia")
	var bag := (controls.get_node("InventoryButton") as Control).get_global_rect().get_center()
	_android_touch(0, bag, true)
	await _frames(3)
	_android_touch(0, bag, false)
	await _frames(10)
	_check(hud.is_open, "botão MOCHILA abre o painel no toque")
	hud.close()
	_combat.attack_started.disconnect(on_attack)
	await _touch_teardown(controls)
	_clear_inventory()


## Procura no mundo, perto de FAR, uma árvore com chão plano em volta.
func _find_tree(world: ProceduralWorld) -> Array:
	var g := world.generator
	var center := ProceduralWorld.chunk_of(FAR)
	for r in 6:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var coord := center + Vector2i(dx, dz)
				var data := g.build_chunk(coord)
				var trees: Array = data["tree_list"]
				for i in trees.size():
					var base: Vector3 = (trees[i][2] as Transform3D).origin
					var stand := base + Vector3(1.25, 0.0, 0.0)
					if g.slope_at(stand.x, stand.z) < 0.2 and g.slope_at(base.x, base.z) < 0.2:
						var crowded := false
						for j in trees.size():
							if j != i and ((trees[j][2] as Transform3D).origin - stand).length() < 1.6:
								crowded = true
						if not crowded:
							return [coord, i, base]
	return []


func _test_chop_tree() -> void:
	_begin("Machado: corta a árvore (resistência por golpe), ela tomba e vira madeira coletável")
	var inventory: Inventory = _player.get_node("Inventory")
	var equipment: PlayerEquipment = _player.get_node("Equipment")
	var world := _world_node(1)
	world.target = _player
	add_child(world)
	await _frames(1)
	var found := _find_tree(world)
	_check(not found.is_empty(), "árvore achada para o teste")
	if found.is_empty():
		world.queue_free()
		return
	var base: Vector3 = found[2]
	world.generate_now(base, 1)
	var g := world.generator
	var stand := base + Vector3(1.25, 0.0, 0.0)
	stand.y = g.surface_height(stand.x, stand.z)
	await _reset(stand + Vector3.UP * 0.1, 0.0)
	var resources := world.resources_of(found[0])
	var entry: Dictionary = {}
	for e in resources.entries():
		if e["key"] == "a_%d_%d_%d" % [found[0].x, found[0].y, found[1]]:
			entry = e
	_check(not entry.is_empty() and entry["health"] > 0.0, "árvore com resistência própria (%.0f)" % entry.get("health", 0.0))
	var trunk_point := Vector3(base.x, stand.y + 1.15, base.z)
	# Sem machado (taco): não corta, avisa.
	_clear_inventory()
	equipment.equip(load(WEAPONS[0]))
	var messages := []
	var on_message := func(text: String) -> void: messages.append(text)
	inventory.message.connect(on_message)
	_look_at_point(trunk_point)
	await _frames(30)
	var before: float = entry["health"]
	await _hold(&"attack", 2)
	await _frames(70)
	_check(is_equal_approx(entry["health"], before) and messages.size() > 0 and messages[0].contains("machado"),
			"com o taco não corta e avisa (\"%s\")" % (messages[0] if messages.size() > 0 else ""))
	# Com o machado.
	_clear_inventory()
	equipment.equip(load(WEAPONS[1]))
	_look_at_point(trunk_point)
	await _frames(40)
	var durability: float = inventory.equipped()["durability"]
	await _hold(&"attack", 2)
	await _frames(4)
	_check(_body.current_animation(BodyAnimator.SLOT_ACTION) == &"chop", "diante da árvore o golpe é o corte de lenhador")
	await _frames(80)
	_check(entry["health"] < before, "um golpe tira resistência (%.0f → %.0f)" % [before, entry["health"]])
	_check(inventory.equipped()["durability"] < durability, "o machado se desgasta (%.0f → %.0f)" % [durability, inventory.equipped()["durability"]])
	var swings := 1
	while entry["health"] > 0.0 and swings < 25:
		_look_at_point(trunk_point)
		await _hold(&"attack", 2)
		await _frames(75)
		swings += 1
	_check(entry["health"] <= 0.0, "a árvore cede depois de %d golpes" % swings)
	_check((entry["shape"] as CollisionShape3D).disabled and world.is_removed(entry["key"]), "tronco sai do lugar (fica o toco) e não volta ao recarregar")
	var chunk := world.chunk_node(found[0])
	var falling := chunk.find_children("ArvoreCaindo", "RigidBody3D", true, false)
	_check(falling.size() == 1, "a árvore tomba como corpo físico")
	var start_tilt := 0.0
	if falling.size() == 1:
		await _frames(90)
		start_tilt = rad_to_deg((falling[0] as Node3D).global_basis.y.angle_to(Vector3.UP))
		_check(start_tilt > 30.0, "caiu de lado (%.0f° da vertical)" % start_tilt)
	await _frames(240)
	var logs: Array = []
	for node in chunk.find_children("*", "ItemPickup", true, false):
		if (node as ItemPickup).item.id == &"madeira":
			logs.append(node.get_parent())
	_check(logs.size() >= 3, "o tronco virou %d toras de madeira" % logs.size())
	# Coleta: anda até as toras e pega com PEGAR.
	var collected := 0
	for candidate: Variant in logs.slice(0, 2):
		if not is_instance_valid(candidate):
			continue
		var log_body := candidate as Node3D
		var near := log_body.global_position + Vector3(0.9, 0.0, 0.0)
		near.y = g.surface_height(near.x, near.z)
		_player.teleport(near + Vector3.UP * 0.1)
		await _frames(30)
		await _aim_and_take(log_body)
		if not is_instance_valid(log_body):
			collected += 1
	_check(collected == 2 and inventory.count(&"madeira") == 2, "coletou madeira com PEGAR (%d na mochila)" % inventory.count(&"madeira"))
	inventory.message.disconnect(on_message)
	_clear_inventory()
	world.queue_free()
	await _frames(5)


func _find_deposit(world: ProceduralWorld, type: StringName, near: Vector3, radius: int) -> Array:
	var g := world.generator
	var center := ProceduralWorld.chunk_of(near)
	for r in radius:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var coord := center + Vector2i(dx, dz)
				var deposits: Array = g.build_chunk(coord)["deposits"]
				for i in deposits.size():
					if deposits[i][0] == type:
						return [coord, i, (deposits[i][1] as Transform3D).origin]
	return []


## Fica ao lado de um depósito e o quebra com a picareta; retorna o que caiu.
func _mine(world: ProceduralWorld, found: Array, stand: Vector3) -> Dictionary:
	var resources := world.resources_of(found[0])
	var entry: Dictionary = {}
	for e in resources.entries():
		if e["key"] == "d_%d_%d_%d" % [found[0].x, found[0].y, found[1]]:
			entry = e
	if entry.is_empty():
		return {}
	var target := (found[2] as Vector3) + Vector3.UP * 0.45
	await _reset(stand + Vector3.UP * 0.1, 0.0)
	_look_at_point(target)
	await _frames(30)
	var first := true
	var swings := 0
	while entry["health"] > 0.0 and swings < 20:
		_look_at_point(target)
		await _hold(&"attack", 2)
		if first:
			await _frames(4)
			entry["first_clip"] = _body.current_animation(BodyAnimator.SLOT_ACTION)
			first = false
		await _frames(95)
		swings += 1
	entry["swings"] = swings
	return entry


func _test_mine_rock() -> void:
	_begin("Picareta: pega do chão, minera a rocha e coleta as pedras")
	var inventory: Inventory = _player.get_node("Inventory")
	var world := _world_node(1)
	world.target = _player
	add_child(world)
	await _frames(1)
	var g := world.generator
	var found := _find_deposit(world, &"pedra", FAR, 8)
	_check(not found.is_empty(), "rocha de pedra achada")
	if found.is_empty():
		world.queue_free()
		return
	var rock: Vector3 = found[2]
	world.generate_now(rock, 1)
	var stand := rock + Vector3(1.6, 0.0, 0.0)
	stand.y = g.surface_height(stand.x, stand.z)
	# A picareta está no chão: PEGAR.
	_clear_inventory()
	await _reset(stand + Vector3.UP * 0.1, 0.0)
	var tool_spot := stand + Vector3(0.0, 0.0, 0.9)
	tool_spot.y = g.surface_height(tool_spot.x, tool_spot.z) + 0.4
	var tool := WeaponPickup.spawn(load(WEAPONS[2]), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), tool_spot), world)
	await _frames(60)
	await _aim_and_take(tool)
	_check(inventory.has_tool(&"picareta") and inventory.equipped_item().id == &"picareta", "pegou a picareta e empunhou")
	var entry := await _mine(world, found, stand)
	_check(entry.get("first_clip", &"") == &"mine", "diante da rocha o golpe é o da picareta de cima para baixo (%s)" % entry.get("first_clip", &""))
	_check(entry.get("health", 1.0) <= 0.0, "rocha quebrada em %d golpes" % entry.get("swings", 0))
	await _frames(60)
	var chunk := world.chunk_node(found[0])
	var pieces: Array = []
	for node in chunk.find_children("*", "ItemPickup", true, false):
		if (node as ItemPickup).item.id == &"pedra":
			pieces.append(node.get_parent())
	_check(pieces.size() >= 3, "soltou %d pedras" % pieces.size())
	# As pedras rolam encosta abaixo: espera assentarem. Pegar uma pode
	# recolher a vizinha que estiver sob a mira, então a cada tentativa usa a
	# primeira que ainda está no chão.
	for attempt in 6:
		if inventory.count(&"pedra") >= 2:
			break
		var piece: RigidBody3D = null
		for candidate: Variant in pieces:
			if is_instance_valid(candidate):
				piece = candidate as RigidBody3D
				break
		if piece == null:
			break
		for wait in 12:
			if piece.linear_velocity.length() < 0.05:
				break
			await _frames(10)
		var near := piece.global_position + Vector3(0.7, 0.0, 0.2)
		near.y = g.surface_height(near.x, near.z)
		_player.teleport(near + Vector3.UP * 0.1)
		await _frames(30)
		await _aim_and_take(piece)
	_check(inventory.count(&"pedra") >= 2, "coletou pedras (%d na mochila)" % inventory.count(&"pedra"))
	_clear_inventory()
	world.queue_free()
	await _frames(5)


func _test_zombie_combat() -> void:
	_begin("Zumbi: persegue, ataca, apanha do taco (dano, recuo, cambaleio) e morre em ragdoll")
	var equipment: PlayerEquipment = _player.get_node("Equipment")
	var inventory: Inventory = _player.get_node("Inventory")
	_clear_inventory()
	await _reset(Vector3(30.0, 0.0, 10.0), YAW_TOWARD_POSITIVE_Z)
	equipment.equip(load(WEAPONS[0]))
	_check(equipment.weapon != null and equipment.weapon.id == &"taco", "taco empunhado")
	var zombie := Zombie.new()
	zombie.target = _player
	_gym.add_child(zombie)
	zombie.global_position = _player.global_position + _forward() * 6.0
	zombie.rotation.y = PI # de costas: percebe pelo barulho/visão ao virar
	await _frames(10)
	var start_distance := zombie.global_position.distance_to(_player.global_position)
	await _frames(150)
	_check(zombie.state in [Zombie.State.CHASE, Zombie.State.ATTACK], "percebeu o jogador e persegue")
	_check(zombie.global_position.distance_to(_player.global_position) < start_distance - 0.5,
			"vem andando (%.1f → %.1f m)" % [start_distance, zombie.global_position.distance_to(_player.global_position)])
	# Deixa o zumbi chegar e atacar.
	var health_before := _health.current
	var frames := 0
	while _health.current >= health_before and frames < 600:
		await _frames(1)
		frames += 1
	_check(_health.current < health_before, "o arranhão fere o jogador (%.0f → %.0f)" % [health_before, _health.current])
	# Revida com o taco.
	var zombie_health := zombie.health
	var durability: float = inventory.equipped()["durability"]
	var before := zombie.global_position
	_look_at_point(zombie.global_position + Vector3.UP * 1.3)
	await _frames(2)
	await _hold(&"attack", 2)
	await _frames(40)
	_check(zombie.health < zombie_health, "o taco fere o zumbi (%.0f → %.0f)" % [zombie_health, zombie.health])
	_check(zombie.state == Zombie.State.STAGGER or zombie.hits_taken > 0, "cambaleia com o golpe")
	var pushed := Vector2(zombie.global_position.x - before.x, zombie.global_position.z - before.z)
	var away := Vector2(before.x - _player.global_position.x, before.z - _player.global_position.z).normalized()
	_check(pushed.dot(away) > 0.15, "recua na direção do golpe (%.2f m)" % pushed.dot(away))
	_check(inventory.equipped()["durability"] < durability, "o taco se desgasta (%.0f → %.0f)" % [durability, inventory.equipped()["durability"]])
	var hits := 1
	while not zombie.is_dead() and hits < 15:
		await _frames(20)
		_look_at_point(zombie.global_position + Vector3.UP * 1.2)
		await _hold(&"attack", 2)
		await _frames(30)
		hits += 1
	_check(zombie.is_dead(), "morreu depois de %d golpes" % hits)
	var simulator := zombie.find_child("PhysicalBoneSimulator3D", true, false) as PhysicalBoneSimulator3D
	_check(simulator != null and simulator.active, "corpo vira ragdoll")
	await _frames(60)
	zombie.queue_free()
	_health.revive()
	_clear_inventory()
	await _frames(5)


func _test_bat_breaks() -> void:
	_begin("Durabilidade: o taco gasto quebra no golpe")
	var inventory: Inventory = _player.get_node("Inventory")
	var equipment: PlayerEquipment = _player.get_node("Equipment")
	var dummy := await _face_dummy()
	_clear_inventory()
	equipment.equip(load(WEAPONS[0]))
	inventory.equipped()["durability"] = 1.0
	var broken := []
	var on_broken := func(item: ItemData) -> void: broken.append(item.id)
	inventory.tool_broken.connect(on_broken)
	await _frames(60)
	var hits := dummy.hits
	await _hold(&"attack", 2)
	await _frames(60)
	_check(dummy.hits == hits + 1, "último golpe ainda acerta")
	_check(broken == [&"taco"] and not inventory.has_tool(&"taco") and equipment.weapon == null, "o taco quebrou: some da mochila e da mão")
	inventory.tool_broken.disconnect(on_broken)
	_clear_inventory()


func _test_cave_exploration() -> void:
	_begin("Cavernas: entrar pela boca, andar e correr nas galerias, minerar e sair")
	var inventory: Inventory = _player.get_node("Inventory")
	var world := _world_node(2)
	world.target = _player
	add_child(world)
	await _frames(1)
	var g := world.generator
	var spawn := g.spawn_point()
	var entrances := g.entrances_near(spawn, 330.0)
	_check(entrances.size() >= 3, "%d entradas de caverna perto do ponto de partida" % entrances.size())
	var nearest := INF
	for e in entrances:
		nearest = minf(nearest, Vector2((e["top"] as Vector3).x - spawn.x, (e["top"] as Vector3).z - spawn.z).length())
	_check(nearest < 120.0, "uma entrada a %.0f m da partida" % nearest)
	var mined := false
	for e in entrances.slice(0, 2):
		var top: Vector3 = e["top"]
		var bottom: Vector3 = e["bottom"]
		var down := Vector3(bottom.x - top.x, 0.0, bottom.z - top.z).normalized()
		var start := top - down * 6.0
		start.y = g.surface_height(start.x, start.z)
		world.generate_now(start, 2)
		await _reset(start + Vector3.UP * 0.1, 0.0)
		var path := []
		for i in range(1, 11):
			path.append(top.lerp(bottom, i / 10.0))
		path.append(bottom + down * 3.0)
		var went_in := await _walk_path(path, false)
		var depth := g.surface_height(_player.global_position.x, _player.global_position.z) - _player.global_position.y
		_check(went_in and depth > 8.0, "desceu a rampa até a galeria (%.0f m sob a superfície)" % depth)
		# Galeria: corre seguindo o eixo e agacha.
		var here := bottom + down * 3.0
		var heading := down
		var gallery := []
		for step in 4:
			# A galeria pode cruzar a rampa de lado: procura até ±150°.
			var turns := [0]
			for k in range(1, 16):
				turns.append_array([-k, k])
			for k in turns:
				var d: Vector3 = heading.rotated(Vector3.UP, k * deg_to_rad(10.0))
				var q: Vector3 = here + d * 3.0
				var ga := g.gallery_at(q.x, q.z, g.surface_height(q.x, q.z))
				if ga.x < ga.y * 0.5:
					here = q
					heading = d
					gallery.append(q)
					break
		var ran := await _walk_path(gallery, true)
		_check(ran and gallery.size() >= 3, "correu %d m pela galeria" % (gallery.size() * 3))
		await _hold(&"crouch_toggle", 2)
		await _frames(30)
		_check(_player._crouch_toggled and _player.is_on_floor(), "agacha dentro da caverna")
		await _hold(&"crouch_toggle", 2)
		await _frames(30)
		# Minerar dentro: o minério mais perto ao alcance da galeria.
		if not mined:
			var ore := _nearest_ore(world, _player.global_position, 28.0)
			if not ore.is_empty():
				_clear_inventory()
				(_player.get_node("Equipment") as PlayerEquipment).equip(load(WEAPONS[2]))
				var deposit: Vector3 = ore[2]
				var stand := deposit + Vector3((_player.global_position - deposit).x, 0.0, (_player.global_position - deposit).z).normalized() * 1.7
				var fy := deposit.y + 2.0
				while g.density(stand.x, fy - 0.1, stand.z) < 0.0 and fy > deposit.y - 3.0:
					fy -= 0.1
				stand.y = fy
				var entry := await _mine(world, ore, stand)
				_check(entry.get("health", 1.0) <= 0.0, "quebrou o %s dentro da caverna em %d golpes" % [ore[3], entry.get("swings", 0)])
				await _frames(60)
				for node in world.chunk_node(ore[0]).find_children("*", "ItemPickup", true, false):
					var id := (node as ItemPickup).item.id
					if (id == &"carvao" or id == &"ferro") and inventory.count(&"carvao") + inventory.count(&"ferro") == 0:
						var piece := node.get_parent() as Node3D
						var near := piece.global_position + (_player.global_position - piece.global_position).normalized() * 0.7
						near.y = piece.global_position.y + 0.1
						_player.teleport(near)
						await _frames(30)
						await _aim_and_take(piece)
				mined = (inventory.count(&"carvao") + inventory.count(&"ferro")) > 0
				_check(mined, "coletou o minério (%d carvão, %d ferro)" % [inventory.count(&"carvao"), inventory.count(&"ferro")])
				_clear_inventory()
				_player.teleport(bottom + Vector3.UP * 0.3)
				await _frames(30)
		# Volta: sobe a rampa e sai.
		var back := []
		for i in range(9, -1, -1):
			back.append(top.lerp(bottom, i / 10.0))
		back.append(start)
		var out := await _walk_path(back, false)
		var sky := g.sky_visibility(_player.global_position + Vector3.UP)
		_check(out and sky > 0.9, "saiu da caverna e voltou ao ar livre (céu %.2f)" % sky)
	world.queue_free()
	await _frames(5)


func _nearest_ore(world: ProceduralWorld, near: Vector3, radius: float) -> Array:
	var best := []
	var best_distance := radius
	for coord in world.loaded_chunks():
		var resources := world.resources_of(coord)
		if resources == null:
			continue
		for e in resources.entries():
			if e["kind"] != &"deposito" or e["health"] <= 0.0 or e["type"] == &"pedra":
				continue
			var t: Transform3D = e["transform"]
			var d := t.origin.distance_to(near)
			if d < best_distance:
				best_distance = d
				var key: String = e["key"]
				var parts := key.split("_")
				best = [Vector2i(int(parts[1]), int(parts[2])), int(parts[3]), t.origin, e["type"]]
	return best


## Anda (ou corre) por uma lista de pontos, mirando em cada um. Falso se
## travar (sem avançar por 3 s) ou demorar demais.
func _walk_path(points: Array, run: bool) -> bool:
	if run:
		Input.action_press(&"sprint")
	for target: Vector3 in points:
		var frames := 0
		var last := _player.global_position
		var stuck := 0
		Input.action_press(&"move_forward")
		while Vector2(_player.global_position.x - target.x, _player.global_position.z - target.z).length() > 1.5:
			var d := target - _player.global_position
			_player.set_view_rotation(atan2(-d.x, -d.z), 0.0)
			await _frames(1)
			frames += 1
			if frames % 60 == 0:
				if _player.global_position.distance_to(last) < 0.5:
					stuck += 1
				last = _player.global_position
			if stuck >= 3 or frames > 900:
				_release_all()
				return false
	_release_all()
	return true


func _test_cave_geometry() -> void:
	_begin("Cavernas: chão caminhável, altura livre, rampas e nenhum buraco fora das entradas")
	var g := WorldGenerator.new(WORLD_SEED)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var floors := 0
	var steep := 0
	var low := 0
	var tries := 0
	while floors < 300 and tries < 30000:
		tries += 1
		var x := rng.randf_range(-700.0, 700.0)
		var z := rng.randf_range(-700.0, 700.0)
		var s := g.surface_height(x, z)
		var ga := g.gallery_at(x, z, s)
		if ga.x > ga.y * 0.75:
			continue
		var fy := ga.w + 2.0
		if g.density(x, fy, z) >= 0.0:
			continue
		while g.density(x, fy - 0.1, z) < 0.0 and fy > ga.w - 4.0:
			fy -= 0.1
		floors += 1
		var e := 0.3
		var normal := -Vector3(g.density(x + e, fy - 0.1, z) - g.density(x - e, fy - 0.1, z),
				g.density(x, fy - 0.1 + e, z) - g.density(x, fy - 0.1 - e, z),
				g.density(x, fy - 0.1, z + e) - g.density(x, fy - 0.1, z - e)).normalized()
		if normal.y < cos(deg_to_rad(40.0)):
			steep += 1
		var h := 0.0
		while h < 4.0 and g.density(x, fy + h + 0.1, z) < 0.0:
			h += 0.1
		if h < 2.1:
			low += 1
	_check(floors >= 200, "%d pontos de chão de galeria medidos" % floors)
	_check(steep <= floors * 0.03, "chão com mais de 40°: %.1f%%" % (steep * 100.0 / maxi(floors, 1)))
	_check(low <= floors * 0.03, "altura livre abaixo de 2,1 m: %.1f%%" % (low * 100.0 / maxi(floors, 1)))
	# Rampas: inclinação média caminhável e nunca um degrau impossível.
	var worst := 0.0
	var ramps := g.entrances_near(Vector3.ZERO, 500.0)
	for ramp in ramps:
		var top: Vector3 = ramp["top"]
		var bottom: Vector3 = ramp["bottom"]
		var step := Vector2(top.x - bottom.x, top.z - bottom.z).length() / 40.0
		var previous := top.y
		var smoothed := []
		for i in range(0, 41):
			var p := top.lerp(bottom, i / 40.0)
			var fy := lerpf(top.y, bottom.y, minf(i / 40.0 / 0.8, 1.0)) + 1.5
			while g.density(p.x, fy - 0.1, p.z) < 0.0 and fy > -40.0:
				fy -= 0.1
			smoothed.append(fy)
		for i in range(4, 41, 4):
			worst = maxf(worst, rad_to_deg(atan2(absf(smoothed[i] - smoothed[i - 4]), step * 4.0)))
	_check(ramps.size() >= 5 and worst < 32.0, "%d rampas de entrada; trecho mais íngreme %.0f° (limite do personagem 46°)" % [ramps.size(), worst])
	# Buracos: chão que se abre fora das rampas (antes eram poços).
	var holes := 0
	for i in 4000:
		var x := rng.randf_range(-900.0, 900.0)
		var z := rng.randf_range(-900.0, 900.0)
		var s := g.surface_height(x, z)
		if g.density(x, s - 1.5, z) < 0.0:
			var in_ramp := false
			for ramp in g.entrances_near(Vector3(x, 0.0, z), 200.0):
				var a := Vector2((ramp["top"] as Vector3).x, (ramp["top"] as Vector3).z)
				var b := Vector2((ramp["bottom"] as Vector3).x, (ramp["bottom"] as Vector3).z)
				if Geometry2D.get_closest_point_to_segment(Vector2(x, z), a, b).distance_to(Vector2(x, z)) < 10.0:
					in_ramp = true
			if not in_ramp:
				holes += 1
	_check(holes == 0, "nenhum buraco na superfície fora das rampas (%d)" % holes)


func _test_headlamp() -> void:
	_begin("Lanterna: na testa, sem sombra do próprio corpo, segue a mira; acende na caverna")
	var world := _world_node(1)
	world.target = _player
	add_child(world)
	await _frames(1)
	var g := world.generator
	var ramp: Dictionary = g.entrances_near(FAR, 400.0)[0]
	var top: Vector3 = ramp["top"]
	var bottom: Vector3 = ramp["bottom"]
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_energy = 1.0
	add_child(environment)
	var atmosphere := CaveAtmosphere.new()
	atmosphere.world = world
	atmosphere.camera = _camera
	atmosphere.eyes = _player.get_node("Head/CameraEffects")
	atmosphere.body = _body
	atmosphere.environment = environment
	atmosphere.adapt_time = 0.3
	add_child(atmosphere)
	var player_layer := CaveAtmosphere.PLAYER_RENDER_LAYER
	var meshes := _body.find_children("*", "GeometryInstance3D", true, false)
	var on_layer := 0
	for mesh: GeometryInstance3D in meshes:
		if mesh.layers == player_layer:
			on_layer += 1
	_check(on_layer == meshes.size(), "corpo do sobrevivente na camada do jogador (%d de %d malhas)" % [on_layer, meshes.size()])
	var lamp := atmosphere.headlamp
	_check(lamp.shadow_enabled and (lamp.shadow_caster_mask & player_layer) == 0 and (lamp.light_cull_mask & player_layer) == 0,
			"foco com sombra, mas o corpo não projeta sombra nele nem fica estourado por ele")
	_check(not atmosphere.spill.shadow_enabled and not atmosphere.body_fill.shadow_enabled and (atmosphere.body_fill.light_cull_mask == player_layer),
			"um único mapa de sombras (halo e luz do corpo sem sombra; celular)")
	# Ar livre.
	var outside := top - Vector3(bottom.x - top.x, 0.0, bottom.z - top.z).normalized() * 10.0
	outside.y = g.surface_height(outside.x, outside.z)
	world.generate_now(outside, 1)
	await _reset(outside + Vector3.UP * 0.1, 0.0)
	await _frames(60)
	_check(atmosphere.underground < 0.05 and not lamp.visible, "ao ar livre a lanterna fica apagada (dia)")
	# Boca da rampa: transição.
	var mouth := top.lerp(bottom, 0.15)
	mouth.y = lerpf(top.y, bottom.y, 0.15 / 0.8) + 0.2
	world.generate_now(mouth, 1)
	_player.teleport(mouth)
	await _frames(90)
	var at_mouth := atmosphere.underground
	# Fundo da galeria.
	var deep := bottom + Vector3.UP * 0.3
	world.generate_now(deep, 1)
	_player.teleport(deep)
	_player.set_view_rotation(0.0, 0.0)
	_rig.set_third_person(false)
	_rig.snap()
	await _frames(90)
	_check(at_mouth > 0.05 and at_mouth < atmosphere.underground, "escurece aos poucos: boca %.2f, fundo %.2f" % [at_mouth, atmosphere.underground])
	_check(atmosphere.underground > 0.9 and lamp.visible and lamp.light_energy > 3.0, "dentro da caverna acende (%.1f)" % lamp.light_energy)
	var eyes: Vector3 = atmosphere.eyes.global_position
	var offset := lamp.global_position - eyes
	_check(offset.y > 0.03 and offset.length() < 0.2, "na testa: %.0f cm acima e %.0f cm dos olhos" % [offset.y * 100.0, offset.length() * 100.0])
	var level := lamp.global_position
	for pitch in [-1.2, 1.0]:
		_player.set_view_rotation(0.0, pitch)
		_rig.snap()
		await _frames(10)
		var aim := -_camera.global_basis.z
		var moved := lamp.global_position.distance_to(atmosphere.forehead())
		_check((-lamp.global_basis.z).dot(aim) > 0.99 and moved < 0.01,
				"olhando para %s: foco segue a mira e a lanterna fica na testa" % ("o chão" if pitch < 0.0 else "o teto"))
	_check(level.distance_to(atmosphere.forehead()) < 0.15, "olhar para cima/baixo não leva a lanterna para dentro do peito ou do gorro")
	# Colado na parede: a lanterna não entra na rocha.
	_player.set_view_rotation(0.0, 0.0)
	var side := Vector3(1.0, 0.0, 0.0)
	var p := deep
	while g.density(p.x + side.x * 1.0, p.y + 1.6, p.z + side.z * 1.0) < 0.0 and p.distance_to(deep) < 10.0:
		p += side * 0.25
	_player.teleport(p)
	_player.set_view_rotation(-PI * 0.5, 0.0)
	_rig.snap()
	await _frames(30)
	_check(g.density(lamp.global_position.x, lamp.global_position.y, lamp.global_position.z) < 0.0,
			"de cara para a parede a lanterna continua no ar, fora da rocha")
	# Câmera em movimento e 3ª pessoa.
	for i in 30:
		_player.set_view_rotation(i * 0.1, sin(i * 0.3) * 0.5)
		await _frames(1)
	_check((-lamp.global_basis.z).dot(-_camera.global_basis.z) > 0.99, "girando a câmera, o foco acompanha")
	_rig.set_third_person(true)
	_rig.snap()
	await _frames(30)
	_check(lamp.global_position.distance_to(atmosphere.eyes.global_position) < 0.2 and lamp.global_position.distance_to(_camera.global_position) > 1.0,
			"em 3ª pessoa a luz sai da testa do personagem, não da câmera")
	_rig.set_third_person(false)
	atmosphere.queue_free()
	environment.queue_free()
	world.queue_free()
	for mesh: GeometryInstance3D in meshes:
		mesh.layers = 1
	await _frames(5)


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
