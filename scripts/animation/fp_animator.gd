class_name FirstPersonAnimator
extends Node3D
## Animador em camadas dos braços em primeira pessoa.
##
## Lê a biblioteca do AnimationPlayer (editável no editor) e compõe a pose a
## cada quadro, guiada pelo estado físico real do personagem:
##   1. repouso (respiração, tempo real)
##   2. locomoção: andar/trotar/correr misturados pela velocidade medida e
##      posicionados pela FASE DA PASSADA física (não por relógio): o braço
##      direito está à frente exatamente no contato do pé esquerdo
##   3. mancar, pelo grau de lesão nas pernas
##   4. agachado, pela altura real da cápsula de colisão
##   5. ar: impulsão (pelo tempo desde o salto) e queda (pela velocidade vertical)
##   6. guarda de combate (alguns segundos após um ataque)
##   7. camadas sobrepostas: aterrissagem, ferimento, ação e morte, com
##      entrada/saída suaves, eventos de quadro e "segurar" (golpe carregado)
## A avaliação é manual (e não por AnimationTree) para controlar o tempo das
## animações pela física e segurar poses enquanto o jogador carrega um golpe.

signal animation_event(event: StringName, animation: StringName)
signal overlay_finished(slot: StringName, animation: StringName)

const SLOT_LAND := &"land"
const SLOT_HURT := &"hurt"
const SLOT_ACTION := &"action"
const SLOT_DEATH := &"death"
const SLOT_ORDER: Array[StringName] = [&"land", &"hurt", &"action", &"death"]
## Ciclos de marcha: duração normalizada, tempo = fase da passada.
const GAIT_CLIPS: Array[StringName] = [&"walk", &"jog", &"sprint", &"crouch_walk", &"limp_walk"]

@export var player: PlayerController
@export var health: HealthComponent
@export var skeleton: Skeleton3D
@export var animation_player: AnimationPlayer

@export_group("Mistura")
## Velocidade (1/s) com que o peso da locomoção acompanha o movimento.
@export_range(0.5, 30.0, 0.1) var move_blend_speed: float = 9.0
## Velocidade com que os braços entram e saem da pose aérea.
@export_range(0.5, 40.0, 0.1) var air_blend_in: float = 7.0
@export_range(0.5, 40.0, 0.1) var air_blend_out: float = 14.0
@export_range(0.1, 20.0, 0.1) var limp_blend_speed: float = 2.0
@export_range(0.5, 30.0, 0.1) var guard_blend_speed: float = 6.0
## Tempo que a guarda permanece depois de um ataque (s).
@export_range(0.0, 10.0, 0.1) var guard_duration: float = 2.5
## Impacto mínimo (m/s) que dispara a animação de aterrissagem.
@export_range(0.0, 10.0, 0.1) var landing_min_impact: float = 2.2

class Clip:
	var animation: Animation
	var rotation_tracks: Array[Vector2i] = []
	var root_track: int = -1
	var events: Dictionary = {}
	var hold_time: float = -1.0


class Pose:
	var rotations: Array[Quaternion] = []
	var root: Vector3 = Vector3.ZERO

	func _init(bone_count: int) -> void:
		rotations.resize(bone_count)
		rotations.fill(Quaternion.IDENTITY)


class Overlay:
	var slot: StringName
	var name: StringName
	var clip: Clip
	var time: float = 0.0
	var speed: float = 1.0
	var fade_in: float = 0.08
	var fade_out: float = 0.15
	var max_weight: float = 1.0
	var holding: bool = false
	var persistent: bool = false
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
var _root_bone: int = -1
var _pose: Pose
var _layer: Pose
var _scratch: Pose
var _overlays: Dictionary = {}
var _retiring: Array[Overlay] = []

var _idle_time: float = 0.0
var _air_time: float = 0.0
var _move_weight: float = 0.0
var _air_weight: float = 0.0
var _limp_weight: float = 0.0
var _guard_weight: float = 0.0
var _guard_timer: float = 0.0
## Tempo da última atualização, em microssegundos (diagnóstico de desempenho).
var last_update_usec: int = 0


func _ready() -> void:
	assert(skeleton != null and animation_player != null, "FirstPersonAnimator precisa do Skeleton3D e do AnimationPlayer.")
	_bone_count = skeleton.get_bone_count()
	_root_bone = skeleton.find_bone("Root")
	_pose = Pose.new(_bone_count)
	_layer = Pose.new(_bone_count)
	_scratch = Pose.new(_bone_count)
	for bone in _bone_count:
		_pose.rotations[bone] = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	for anim_name in animation_player.get_animation_list():
		_clips[StringName(anim_name)] = _build_clip(animation_player.get_animation(anim_name))
	# O AnimationPlayer guarda a biblioteca; quem aplica as poses é este nó.
	animation_player.active = false
	if player != null:
		player.landed.connect(_on_player_landed)
		player.jumped.connect(func(_speed: float) -> void: _air_time = 0.0)
	if health != null:
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)
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
				if bone == _root_bone:
					clip.root_track = track
	if animation.has_meta(&"events"):
		clip.events = animation.get_meta(&"events")
	if animation.has_meta(&"hold_time"):
		clip.hold_time = animation.get_meta(&"hold_time")
	return clip


func has_animation(anim_name: StringName) -> bool:
	return _clips.has(anim_name)


# --- API de camadas ----------------------------------------------------------

## Toca uma animação numa camada. `hold` pausa no hold_time da animação até
## release_hold(). Retorna false se a animação não existir ou se a camada de
## morte estiver ativa.
func play(slot: StringName, anim_name: StringName, speed: float = 1.0, fade_in: float = 0.08,
		fade_out: float = 0.15, max_weight: float = 1.0, hold: bool = false) -> bool:
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


## Mantém os braços em guarda por `duration` segundos.
func trigger_guard(duration: float = -1.0) -> void:
	_guard_timer = guard_duration if duration < 0.0 else duration


func get_layer_weights() -> Dictionary:
	return {"move": _move_weight, "air": _air_weight, "limp": _limp_weight, "guard": _guard_weight,
			"crouch": _crouch_weight()}


## Volta ao estado inicial (renascer).
func reset_state() -> void:
	_overlays.clear()
	_retiring.clear()
	_guard_timer = 0.0
	_guard_weight = 0.0
	_air_weight = 0.0
	_air_time = 0.0


func _retire(slot: StringName) -> void:
	if not _overlays.has(slot):
		return
	var old: Overlay = _overlays[slot]
	old.retire_weight = old.weight()
	old.holding = true
	_retiring.append(old)
	_overlays.erase(slot)


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
	_guard_timer = maxf(_guard_timer - delta, 0.0)
	if player == null:
		return
	var grounded := player.is_grounded()
	var speed := player.get_horizontal_speed()
	var airborne := player.movement_state == PlayerController.MovementState.AIRBORNE \
			or player.movement_state == PlayerController.MovementState.SLIDING
	var move_target := clampf(speed / 0.9, 0.0, 1.0) if grounded else _move_weight
	_move_weight = _approach(_move_weight, move_target, move_blend_speed, delta)
	var air_rate := air_blend_in if airborne else air_blend_out
	_air_weight = _approach(_air_weight, 1.0 if airborne else 0.0, air_rate, delta)
	if airborne:
		_air_time += delta
	var injury := health.leg_injury if health != null else 0.0
	_limp_weight = _approach(_limp_weight, injury, limp_blend_speed, delta)
	_guard_weight = _approach(_guard_weight, 1.0 if _guard_timer > 0.0 else 0.0, guard_blend_speed, delta)


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
		old.retire_weight -= delta / 0.12
		if old.retire_weight <= 0.0:
			_retiring.remove_at(i)


func _compose() -> void:
	# 1. Repouso.
	_sample(&"idle", _idle_time, _pose)
	if player != null:
		# 2-3. Locomoção em pé, pela fase da passada e pela velocidade medida.
		if _move_weight > 0.001:
			var phase := player.get_gait_phase()
			_sample_locomotion(phase, _layer)
			if _limp_weight > 0.001:
				_sample(&"limp_walk", phase, _scratch)
				_mix(_layer, _scratch, _limp_weight)
			_mix(_pose, _layer, _move_weight)
		# 4. Agachado.
		var crouch := _crouch_weight()
		if crouch > 0.001:
			_sample(&"crouch_idle", _idle_time, _layer)
			if _move_weight > 0.001:
				_sample(&"crouch_walk", player.get_gait_phase(), _scratch)
				_mix(_layer, _scratch, _move_weight)
			_mix(_pose, _layer, crouch)
		# 5. Ar.
		if _air_weight > 0.001:
			_sample(&"jump", _air_time, _layer)
			var fall_amount := clampf(inverse_lerp(1.5, -3.0, player.velocity.y), 0.0, 1.0)
			if fall_amount > 0.001:
				_sample(&"fall", _idle_time, _scratch)
				_mix(_layer, _scratch, fall_amount)
			_mix(_pose, _layer, _air_weight)
	# 6. Guarda.
	if _guard_weight > 0.001:
		_sample(&"guard", _idle_time, _layer)
		_mix(_pose, _layer, _guard_weight)
	# 7. Camadas sobrepostas (somente os ossos que cada animação controla).
	for old in _retiring:
		_sample_clip(old.clip, old.time, _layer)
		_mix_clip(_pose, _layer, old.clip, old.weight())
	for slot in SLOT_ORDER:
		if _overlays.has(slot):
			var overlay: Overlay = _overlays[slot]
			_sample_clip(overlay.clip, overlay.time, _layer)
			_mix_clip(_pose, _layer, overlay.clip, overlay.weight())


## Andar, trotar e correr ficam sincronizados porque todos têm duração 1 e o
## mesmo contato de pé em t = 0; a mistura segue a velocidade física.
func _sample_locomotion(phase: float, out: Pose) -> void:
	var settings := player.settings
	var speed := player.get_horizontal_speed()
	if speed <= settings.walk_speed:
		_sample(&"walk", phase, out)
	elif speed <= settings.jog_speed:
		_sample(&"walk", phase, out)
		_sample(&"jog", phase, _scratch)
		_mix(out, _scratch, inverse_lerp(settings.walk_speed, settings.jog_speed, speed))
	else:
		_sample(&"jog", phase, out)
		_sample(&"sprint", phase, _scratch)
		_mix(out, _scratch, clampf(inverse_lerp(settings.jog_speed, settings.sprint_speed, speed), 0.0, 1.0))


func _sample(anim_name: StringName, time: float, out: Pose) -> void:
	var clip: Clip = _clips[anim_name]
	var length := clip.animation.length
	if clip.animation.loop_mode != Animation.LOOP_NONE:
		time = fposmod(time * length if anim_name in GAIT_CLIPS else time, length)
	else:
		time = clampf(time, 0.0, length)
	_sample_clip(clip, time, out)


func _sample_clip(clip: Clip, time: float, out: Pose) -> void:
	var animation := clip.animation
	for entry in clip.rotation_tracks:
		out.rotations[entry.x] = animation.rotation_track_interpolate(entry.y, time)
	if clip.root_track >= 0:
		out.root = animation.position_track_interpolate(clip.root_track, time)


func _mix(target: Pose, source: Pose, weight: float) -> void:
	if weight <= 0.0:
		return
	weight = minf(weight, 1.0)
	for bone in _bone_count:
		target.rotations[bone] = target.rotations[bone].slerp(source.rotations[bone], weight)
	target.root = target.root.lerp(source.root, weight)


func _mix_clip(target: Pose, source: Pose, clip: Clip, weight: float) -> void:
	if weight <= 0.0:
		return
	weight = minf(weight, 1.0)
	for entry in clip.rotation_tracks:
		target.rotations[entry.x] = target.rotations[entry.x].slerp(source.rotations[entry.x], weight)
	if clip.root_track >= 0:
		target.root = target.root.lerp(source.root, weight)


func _apply() -> void:
	for bone in _bone_count:
		skeleton.set_bone_pose_rotation(bone, _pose.rotations[bone])
	if _root_bone >= 0:
		skeleton.set_bone_pose_position(_root_bone, _pose.root)


# --- Reações a eventos físicos -----------------------------------------------

func _on_player_landed(impact_speed: float) -> void:
	if impact_speed < landing_min_impact:
		return
	var hard := impact_speed > player.settings.stagger_impact_speed
	var weight := clampf(impact_speed / 5.0, 0.45, 1.0)
	play(SLOT_LAND, &"land_hard" if hard else &"land_soft", 1.0, 0.04, 0.2, weight)


func _on_damaged(amount: float, kind: StringName, _direction: Vector3) -> void:
	# A queda já tem a própria animação de aterrissagem.
	if kind == &"queda" or health.is_dead:
		return
	if amount >= 15.0:
		play(SLOT_HURT, &"hurt_heavy", 1.0, 0.04, 0.25)
	else:
		play(SLOT_HURT, &"hurt_light", 1.0, 0.04, 0.15, clampf(0.5 + amount / 20.0, 0.5, 1.0))


func _on_died() -> void:
	for slot in [SLOT_LAND, SLOT_HURT, SLOT_ACTION]:
		_retire(slot)
	_guard_timer = 0.0
	play(SLOT_DEATH, &"death", 1.0, 0.06)
