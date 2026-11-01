class_name BodyAnimator
extends Node3D
## Animador do corpo inteiro do sobrevivente (o mesmo modelo nas duas câmeras).
##
## Compõe a pose a cada quadro a partir do estado físico do PlayerController:
##   1. repouso (tempo real)
##   2. locomoção andar/trotar/correr pela FASE DA PASSADA física, alinhada ao
##      contato do calcanhar medido em cada animação (metadado left_contact).
##      Como a passada da física é igual à da animação, o pé apoiado não
##      desliza. Para trás, o ciclo é tocado ao contrário.
##   3. agachado, pela altura real da cápsula; mancar (lesão nas pernas)
##   4. ar: impulsão e queda pela velocidade vertical
##   5. camadas: aterrissagem (corpo inteiro), ferimento e ações (só do peito
##      para cima: as pernas continuam a locomoção), com eventos de quadro
##      (hit, contact) e "segurar" (golpe carregado)
## Ajustes procedurais depois das animações:
##   - pélvis gira na direção do movimento lateral e o tronco gira de volta
##   - tronco e pescoço dobram com a inclinação do olhar (os braços seguem a mira)
##   - em terceira pessoa parado, a cabeça acompanha a direção da câmera
##   - em primeira pessoa a cabeça é escondida e a câmera fica nos olhos

signal animation_event(event: StringName, animation: StringName)
signal overlay_finished(slot: StringName, animation: StringName)

const SLOT_LAND := &"land"
const SLOT_HURT := &"hurt"
const SLOT_ACTION := &"action"
const SLOT_DEATH := &"death"
const SLOT_ORDER: Array[StringName] = [&"land", &"hurt", &"action", &"death"]
const GAIT_CLIPS: Array[StringName] = [&"walk", &"jog", &"sprint", &"crouch_walk", &"walk_carry"]
## Primeiro osso da metade superior (máscara das ações).
const UPPER_BODY_ROOT := "spine_02"
## Distribuição da inclinação do olhar pelo tronco (soma = 1).
## O tronco dobra pouco (braços acompanham a mira); pescoço e cabeça fazem o resto.
const PITCH_BONES := {"spine_01": 0.05, "spine_02": 0.10, "spine_03": 0.15, "neck_01": 0.30, "Head": 0.40}
## Contra-rotação do tronco quando a pélvis gira para o lado (soma = 1).
const TWIST_BONES := {"spine_01": 0.3, "spine_02": 0.3, "spine_03": 0.4}
## Olhar da cabeça em terceira pessoa (soma = 1).
const HEAD_LOOK_BONES := {"spine_03": 0.3, "neck_01": 0.3, "Head": 0.4}

@export var player: PlayerController
@export var health: HealthComponent
@export var skeleton: Skeleton3D
@export var animation_player: AnimationPlayer
## Esconde a cabeça (primeira pessoa). Controlado pelo sistema de câmera.
@export var hide_head: bool = false
## Em terceira pessoa, a cabeça acompanha a câmera quando o corpo está parado.
@export var head_follows_view: bool = false

@export_group("Mistura")
@export_range(0.5, 30.0, 0.1) var move_blend_speed: float = 9.0
@export_range(0.5, 40.0, 0.1) var air_blend_in: float = 7.0
@export_range(0.5, 40.0, 0.1) var air_blend_out: float = 12.0
@export_range(0.1, 20.0, 0.1) var limp_blend_speed: float = 2.0
@export_range(0.5, 30.0, 0.1) var direction_blend_speed: float = 8.0
## Giro máximo da pélvis ao andar de lado (graus).
@export_range(0.0, 90.0, 1.0) var max_lower_body_yaw: float = 65.0
## Giro máximo da cabeça seguindo a câmera (graus).
@export_range(0.0, 90.0, 1.0) var max_head_look_yaw: float = 70.0
@export_range(0.0, 10.0, 0.1) var landing_min_impact: float = 3.0
## Deslocamento do olho em relação ao osso da cabeça (espaço do personagem).
@export var eye_offset: Vector3 = Vector3(0.0, 0.075, -0.085)

class Clip:
	var animation: Animation
	var rotation_tracks: Array[Vector2i] = []
	var pelvis_track: int = -1
	var events: Dictionary = {}
	var hold_time: float = -1.0
	var left_contact: float = 0.0


class Pose:
	var rotations: Array[Quaternion] = []
	var pelvis: Vector3 = Vector3.ZERO

	func _init(bone_count: int) -> void:
		rotations.resize(bone_count)
		rotations.fill(Quaternion.IDENTITY)


class Overlay:
	var slot: StringName
	var name: StringName
	var clip: Clip
	var time: float = 0.0
	var speed: float = 1.0
	var fade_in: float = 0.1
	var fade_out: float = 0.2
	var max_weight: float = 1.0
	var holding: bool = false
	var persistent: bool = false
	var upper_body: bool = false
	var retire_weight: float = -1.0

	func weight() -> float:
		var length := clip.animation.length
		var w := max_weight * clampf(time / maxf(fade_in, 0.001), 0.0, 1.0)
		if not persistent:
			w *= clampf((length - time) / maxf(fade_out, 0.001), 0.0, 1.0)
		if retire_weight >= 0.0:
			w = minf(w, retire_weight)
		return w


var _clips: Dictionary = {}
var _bone_count: int = 0
var _pelvis_bone: int = -1
var _head_bone: int = -1
var _full_meshes: Array[MeshInstance3D] = []
var _first_person_meshes: Array[MeshInstance3D] = []
var _view_first_person: bool = false
var _view_applied: bool = false
var _upper_mask := PackedByteArray()
var _rest: Pose
var _pose: Pose
var _layer: Pose
var _scratch: Pose
var _overlays: Dictionary = {}
var _retiring: Array[Overlay] = []

var _idle_time: float = 0.0
var _air_time: float = 0.0
var _air_latched: bool = false
var _move_weight: float = 0.0
var _air_weight: float = 0.0
var _limp_weight: float = 0.0
var _lower_body_yaw: float = 0.0
var _backward_weight: float = 0.0
var _head_look_yaw: float = 0.0
## Tempo da última atualização, em microssegundos (diagnóstico de desempenho).
var last_update_usec: int = 0


func _ready() -> void:
	assert(skeleton != null and animation_player != null, "BodyAnimator precisa do Skeleton3D e do AnimationPlayer.")
	_bone_count = skeleton.get_bone_count()
	_pelvis_bone = skeleton.find_bone("pelvis")
	_head_bone = skeleton.find_bone("Head")
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			match String(child.get_meta(&"view", "both")):
				"full":
					_full_meshes.append(child)
				"first_person":
					_first_person_meshes.append(child)
	_rest = Pose.new(_bone_count)
	for bone in _bone_count:
		_rest.rotations[bone] = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	_rest.pelvis = skeleton.get_bone_rest(_pelvis_bone).origin
	_pose = Pose.new(_bone_count)
	_layer = Pose.new(_bone_count)
	_scratch = Pose.new(_bone_count)
	for pose in [_pose, _layer, _scratch]:
		_reset_to_rest(pose)
	_upper_mask.resize(_bone_count)
	var upper_root := skeleton.find_bone(UPPER_BODY_ROOT)
	for bone in _bone_count:
		var current := bone
		while current >= 0:
			if current == upper_root:
				_upper_mask[bone] = 1
				break
			current = skeleton.get_bone_parent(current)
	for anim_name in animation_player.get_animation_list():
		_clips[StringName(anim_name)] = _build_clip(animation_player.get_animation(anim_name))
	animation_player.active = false
	if player != null:
		player.landed.connect(_on_player_landed)
		player.jumped.connect(func(_speed: float) -> void: _air_time = 0.0)
	if health != null:
		health.damaged.connect(_on_damaged)
		health.revived.connect(reset_state)


func _build_clip(animation: Animation) -> Clip:
	var clip := Clip.new()
	clip.animation = animation
	for track in animation.get_track_count():
		var bone := skeleton.find_bone(animation.track_get_path(track).get_concatenated_subnames())
		if bone < 0:
			continue
		match animation.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				clip.rotation_tracks.append(Vector2i(bone, track))
			Animation.TYPE_POSITION_3D:
				if bone == _pelvis_bone:
					clip.pelvis_track = track
	if animation.has_meta(&"events"):
		clip.events = animation.get_meta(&"events")
	if animation.has_meta(&"hold_time"):
		clip.hold_time = animation.get_meta(&"hold_time")
	if animation.has_meta(&"left_contact"):
		clip.left_contact = animation.get_meta(&"left_contact")
	return clip


func has_animation(anim_name: StringName) -> bool:
	return _clips.has(anim_name)


func get_animation_length(anim_name: StringName) -> float:
	return (_clips[anim_name] as Clip).animation.length if _clips.has(anim_name) else 0.0


## Tempo (s) do evento numa animação, ou -1.
func get_event_time(anim_name: StringName, event: StringName) -> float:
	if not _clips.has(anim_name):
		return -1.0
	return float((_clips[anim_name] as Clip).events.get(String(event), -1.0))


# --- API de camadas ----------------------------------------------------------

## Toca uma animação numa camada. `upper_body` restringe ao tronco, braços e
## cabeça. `hold` pausa no hold_time da animação até release_hold().
func play(slot: StringName, anim_name: StringName, speed: float = 1.0, fade_in: float = 0.1,
		fade_out: float = 0.2, max_weight: float = 1.0, hold: bool = false, upper_body: bool = false) -> bool:
	if not _clips.has(anim_name):
		push_error("Animação inexistente: %s" % anim_name)
		return false
	if _overlays.has(SLOT_DEATH) and slot != SLOT_DEATH:
		return false
	_retire(slot)
	var overlay := Overlay.new()
	overlay.slot = slot
	overlay.name = anim_name
	overlay.clip = _clips[anim_name]
	overlay.speed = speed
	overlay.fade_in = fade_in
	overlay.fade_out = fade_out
	overlay.max_weight = max_weight
	overlay.holding = hold and overlay.clip.hold_time >= 0.0
	overlay.persistent = slot == SLOT_DEATH
	overlay.upper_body = upper_body
	_overlays[slot] = overlay
	return true


func release_hold(slot: StringName) -> void:
	if _overlays.has(slot):
		(_overlays[slot] as Overlay).holding = false


func is_holding(slot: StringName) -> bool:
	if not _overlays.has(slot):
		return false
	var overlay: Overlay = _overlays[slot]
	return overlay.holding and overlay.time >= overlay.clip.hold_time


func is_playing(slot: StringName) -> bool:
	return _overlays.has(slot)


func current_animation(slot: StringName) -> StringName:
	return (_overlays[slot] as Overlay).name if _overlays.has(slot) else &""


func get_overlay_time(slot: StringName) -> float:
	return (_overlays[slot] as Overlay).time if _overlays.has(slot) else -1.0


func get_overlay_weight(slot: StringName) -> float:
	return (_overlays[slot] as Overlay).weight() if _overlays.has(slot) else 0.0


func stop(slot: StringName) -> void:
	_retire(slot)


func get_layer_weights() -> Dictionary:
	return {"move": _move_weight, "air": _air_weight, "limp": _limp_weight, "crouch": _crouch_weight(),
			"backward": _backward_weight, "lower_body_yaw": _lower_body_yaw}


func reset_state() -> void:
	_overlays.clear()
	_retiring.clear()
	_air_weight = 0.0
	_air_time = 0.0
	_air_latched = false


func _retire(slot: StringName) -> void:
	if not _overlays.has(slot):
		return
	var old: Overlay = _overlays[slot]
	old.retire_weight = old.weight()
	old.holding = true
	_retiring.append(old)
	_overlays.erase(slot)


## Posição dos olhos no mundo (osso da cabeça + deslocamento no espaço do corpo).
func get_eye_position() -> Vector3:
	var head := skeleton.get_bone_global_pose(_head_bone).origin
	return skeleton.global_transform * head + global_basis * eye_offset


## Primeira pessoa: malhas sem cabeça visíveis e o corpo completo só projeta
## sombra. Terceira pessoa: corpo completo normal.
func _apply_view_mode() -> void:
	if _view_applied and _view_first_person == hide_head:
		return
	_view_first_person = hide_head
	_view_applied = true
	for mesh in _full_meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if hide_head else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for mesh in _first_person_meshes:
		mesh.visible = hide_head
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Atualização -------------------------------------------------------------

func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_update_weights(delta)
	_update_overlays(delta)
	_compose()
	_apply()
	last_update_usec = Time.get_ticks_usec() - start


func _update_weights(delta: float) -> void:
	_idle_time += delta
	if player == null:
		return
	var grounded := player.is_grounded()
	var speed := player.get_horizontal_speed()
	# Saliências do terreno não viram pose de salto: só voo de verdade
	# (tempo no ar ou velocidade vertical) ou escorregar em encosta.
	# Contato real com o chão (o estado AIRBORNE só muda após a tolerância de
	# borda, tarde demais para a impulsão do salto).
	var in_air := not grounded
	if in_air:
		_air_time += delta
	elif grounded:
		_air_time = 0.0
		_air_latched = false
	# Uma vez reconhecido como voo, vale até tocar o chão (no topo de um salto
	# a velocidade vertical passa por zero).
	if in_air and (_air_time > 0.18 or absf(player.velocity.y) > 2.5):
		_air_latched = true
	var airborne := (in_air and _air_latched) or player.movement_state == PlayerController.MovementState.SLIDING
	var move_target := clampf(speed / 0.9, 0.0, 1.0) if grounded else _move_weight
	_move_weight = _approach(_move_weight, move_target, move_blend_speed, delta)
	_air_weight = _approach(_air_weight, 1.0 if airborne else 0.0, air_blend_in if airborne else air_blend_out, delta)
	var injury := health.leg_injury if health != null else 0.0
	_limp_weight = _approach(_limp_weight, injury, limp_blend_speed, delta)
	# Direção do movimento em relação à frente do corpo.
	var local := player.get_local_horizontal_velocity()
	var yaw_target := 0.0
	var backward_target := 0.0
	if speed > 0.3:
		var angle := atan2(-local.x, -local.z) # positivo = para a esquerda
		if absf(angle) > deg_to_rad(110.0):
			backward_target = 1.0
			angle = angle - signf(angle) * PI
		yaw_target = clampf(angle, -deg_to_rad(max_lower_body_yaw), deg_to_rad(max_lower_body_yaw))
	_lower_body_yaw = _approach(_lower_body_yaw, yaw_target, direction_blend_speed, delta)
	_backward_weight = _approach(_backward_weight, backward_target, direction_blend_speed, delta)
	var look_target := 0.0
	if head_follows_view:
		look_target = clampf(wrapf(player.get_view_yaw() - player.rotation.y, -PI, PI),
				-deg_to_rad(max_head_look_yaw), deg_to_rad(max_head_look_yaw))
	_head_look_yaw = _approach(_head_look_yaw, look_target, 6.0, delta)


func _approach(current: float, target: float, rate: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * delta))


func _crouch_weight() -> float:
	if player == null:
		return 0.0
	var settings := player.settings
	return clampf((settings.standing_height - player.get_current_height())
			/ (settings.standing_height - settings.crouch_height), 0.0, 1.0)


func _update_overlays(delta: float) -> void:
	for slot in SLOT_ORDER:
		if not _overlays.has(slot):
			continue
		var overlay: Overlay = _overlays[slot]
		var previous := overlay.time
		var length := overlay.clip.animation.length
		overlay.time += delta * overlay.speed
		if overlay.holding and overlay.clip.hold_time >= 0.0:
			overlay.time = minf(overlay.time, overlay.clip.hold_time)
		if overlay.persistent:
			overlay.time = minf(overlay.time, length)
		for event_name in overlay.clip.events:
			var event_time: float = overlay.clip.events[event_name]
			if previous < event_time and overlay.time >= event_time:
				animation_event.emit(StringName(event_name), overlay.name)
		if overlay.time >= length and not overlay.persistent:
			_overlays.erase(slot)
			overlay_finished.emit(slot, overlay.name)
	for i in range(_retiring.size() - 1, -1, -1):
		var old := _retiring[i]
		old.retire_weight -= delta / 0.15
		if old.retire_weight <= 0.0:
			_retiring.remove_at(i)


func _compose() -> void:
	_sample(&"idle", _idle_time, _pose)
	if player != null:
		if _move_weight > 0.001:
			var phase := player.get_gait_phase()
			_sample_locomotion(phase, _layer)
			if _limp_weight > 0.001:
				# Mancar: o passo da perna ferida é encurtado no tempo (fase deformada).
				var warped := phase + 0.08 * sin(TAU * phase) * _limp_weight
				_sample_locomotion(warped, _scratch)
				_mix(_layer, _scratch, _limp_weight)
			_mix(_pose, _layer, _move_weight)
		var crouch := _crouch_weight()
		if crouch > 0.001:
			_sample(&"crouch_idle", _idle_time, _layer)
			if _move_weight > 0.001:
				_sample_gait(&"crouch_walk", player.get_gait_phase(), _scratch)
				_mix(_layer, _scratch, _move_weight)
			_mix(_pose, _layer, crouch)
		if _air_weight > 0.001:
			# Impulsão a partir da decolagem (0,35 s do clipe), depois queda.
			_sample(&"jump_start", 0.35 + _air_time, _layer)
			var fall_amount := clampf(inverse_lerp(1.5, -3.0, player.velocity.y), 0.0, 1.0)
			if fall_amount > 0.001:
				_sample(&"fall", _idle_time, _scratch)
				_mix(_layer, _scratch, fall_amount)
			_mix(_pose, _layer, _air_weight)
	for old in _retiring:
		_sample_clip(old.clip, old.time, _layer)
		_mix_clip(_pose, _layer, old.clip, old.weight(), old.upper_body)
	for slot in SLOT_ORDER:
		if _overlays.has(slot):
			var overlay: Overlay = _overlays[slot]
			_sample_clip(overlay.clip, overlay.time, _layer)
			_mix_clip(_pose, _layer, overlay.clip, overlay.weight(), overlay.upper_body)


func _sample_locomotion(phase: float, out: Pose) -> void:
	var settings := player.settings
	var speed := player.get_horizontal_speed()
	if speed <= settings.walk_speed:
		_sample_gait(&"walk", phase, out)
	elif speed <= settings.jog_speed:
		_sample_gait(&"walk", phase, out)
		_sample_gait(&"jog", phase, _scratch)
		_mix(out, _scratch, inverse_lerp(settings.walk_speed, settings.jog_speed, speed))
	else:
		_sample_gait(&"jog", phase, out)
		_sample_gait(&"sprint", phase, _scratch)
		_mix(out, _scratch, clampf(inverse_lerp(settings.jog_speed, settings.sprint_speed, speed), 0.0, 1.0))


## Ciclo de marcha na fase física: fase 0 = contato do calcanhar esquerdo.
## Andando para trás, o ciclo é percorrido ao contrário.
func _sample_gait(anim_name: StringName, phase: float, out: Pose) -> void:
	var clip: Clip = _clips[anim_name]
	var direction := -1.0 if _backward_weight > 0.5 else 1.0
	var t := fposmod(clip.left_contact + phase * direction, 1.0) * clip.animation.length
	_sample_clip(clip, t, out)


func _sample(anim_name: StringName, time: float, out: Pose) -> void:
	var clip: Clip = _clips[anim_name]
	var length := clip.animation.length
	if clip.animation.loop_mode != Animation.LOOP_NONE:
		time = fposmod(time, length)
	else:
		time = clampf(time, 0.0, length)
	_sample_clip(clip, time, out)


func _sample_clip(clip: Clip, time: float, out: Pose) -> void:
	var animation := clip.animation
	# Ossos sem trilha no clipe (ex.: root, girado -90° no repouso) ficam no
	# repouso; sem isso, a mistura os puxaria para a identidade e tombaria o corpo.
	_reset_to_rest(out)
	for entry in clip.rotation_tracks:
		out.rotations[entry.x] = animation.rotation_track_interpolate(entry.y, time)
	if clip.pelvis_track >= 0:
		out.pelvis = animation.position_track_interpolate(clip.pelvis_track, time)


func _reset_to_rest(pose: Pose) -> void:
	pose.rotations.assign(_rest.rotations)
	pose.pelvis = _rest.pelvis


func _mix(target: Pose, source: Pose, weight: float) -> void:
	if weight <= 0.0:
		return
	weight = minf(weight, 1.0)
	for bone in _bone_count:
		target.rotations[bone] = target.rotations[bone].slerp(source.rotations[bone], weight)
	target.pelvis = target.pelvis.lerp(source.pelvis, weight)


func _mix_clip(target: Pose, source: Pose, clip: Clip, weight: float, upper_body: bool) -> void:
	if weight <= 0.0:
		return
	weight = minf(weight, 1.0)
	for entry in clip.rotation_tracks:
		if upper_body and _upper_mask[entry.x] == 0:
			continue
		target.rotations[entry.x] = target.rotations[entry.x].slerp(source.rotations[entry.x], weight)
	if clip.pelvis_track >= 0 and not upper_body:
		target.pelvis = target.pelvis.lerp(source.pelvis, weight)


func _apply() -> void:
	for bone in _bone_count:
		skeleton.set_bone_pose_rotation(bone, _pose.rotations[bone])
	skeleton.set_bone_pose_position(_pelvis_bone, _pose.pelvis)
	if player != null and not _overlays.has(SLOT_DEATH):
		# Pélvis gira para o lado do movimento; o tronco gira de volta.
		if absf(_lower_body_yaw) > 0.001:
			_rotate_global(_pelvis_bone, Vector3.UP, _lower_body_yaw)
			for bone_name in TWIST_BONES:
				_rotate_global(skeleton.find_bone(bone_name), Vector3.UP, -_lower_body_yaw * TWIST_BONES[bone_name])
		# Cabeça acompanha a câmera (terceira pessoa).
		if absf(_head_look_yaw) > 0.001:
			for bone_name in HEAD_LOOK_BONES:
				_rotate_global(skeleton.find_bone(bone_name), Vector3.UP, _head_look_yaw * HEAD_LOOK_BONES[bone_name])
		# Tronco e pescoço dobram com o olhar. O personagem olha para +Z no
		# espaço do esqueleto, então o eixo "direita" do corpo é -X.
		var pitch := player.get_pitch()
		if absf(pitch) > 0.001:
			for bone_name in PITCH_BONES:
				_rotate_global(skeleton.find_bone(bone_name), Vector3.LEFT, pitch * PITCH_BONES[bone_name])
	_apply_view_mode()


## Gira um osso em torno de um eixo do espaço do esqueleto, mantendo a origem.
func _rotate_global(bone: int, axis: Vector3, angle: float) -> void:
	var global_rotation := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	var delta := global_rotation.inverse() * Quaternion(axis, angle) * global_rotation
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * delta)


# --- Reações a eventos físicos -----------------------------------------------

func _on_player_landed(impact_speed: float) -> void:
	if impact_speed < landing_min_impact:
		return
	var weight := clampf(impact_speed / 6.0, 0.35, 1.0)
	var speed := 1.6 if impact_speed < player.settings.stagger_impact_speed else 1.0
	play(SLOT_LAND, &"land", speed, 0.05, 0.25, weight)


func _on_damaged(amount: float, kind: StringName, _direction: Vector3) -> void:
	if kind == &"queda" or health.is_dead:
		return
	if amount >= 30.0:
		play(SLOT_HURT, &"hit_knockback", 1.0, 0.05, 0.25)
	elif amount >= 15.0:
		play(SLOT_HURT, &"hit_head", 1.0, 0.04, 0.2, 1.0, false, true)
	else:
		play(SLOT_HURT, &"hit_chest", 1.0, 0.04, 0.15, clampf(0.5 + amount / 20.0, 0.5, 1.0), false, true)
