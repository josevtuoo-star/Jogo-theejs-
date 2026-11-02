class_name PlayerCameraRig
extends Node3D
## Sistema de câmera em primeira e terceira pessoa, com transição suave.
##
## Um único Camera3D é posicionado a cada quadro pela mistura de duas poses:
## - Primeira pessoa: nos olhos. A posição combina o ponto estável da física
##   (cabeça do controlador, com os efeitos de passada e aterrissagem) com os
##   olhos do osso da cabeça animado; um raio impede o olho de passar de
##   paredes quando o tronco se inclina.
## - Terceira pessoa: órbita sobre o ombro, com distância, altura e ombro
##   ajustáveis; a altura acompanha o agachar e a distância cresce na corrida.
## A transição interpola posição, altura, distância e orientação com uma curva
## suave (smootherstep), mantendo a direção do olhar. O "braço" da câmera é
## varrido com uma esfera contra o cenário em todo quadro (inclusive durante a
## transição): ela encosta em paredes e volta suavemente quando há espaço.
## O corpo é o mesmo nas duas câmeras: a cabeça só é escondida quando a câmera
## está perto dela, então nada some nem duplica na troca.

signal mode_changed(third_person: bool)
signal transition_finished(third_person: bool)

@export var player: PlayerController
@export var body: BodyAnimator
## Ponto de vista estável da primeira pessoa (Head/CameraEffects).
@export var first_person_anchor: Node3D
@export var camera: Camera3D

@export_group("Primeira pessoa")
## Quanto a câmera segue a cabeça animada (0 = só o ponto da física), na
## vertical e na horizontal. A captura balança a cabeça bastante na corrida;
## seguir pouco na horizontal deixa a mira estável (como em DayZ) e ainda
## transmite o peso do corpo no sobe-e-desce.
@export_range(0.0, 1.0, 0.01) var head_bone_follow: float = 0.35
@export_range(0.0, 1.0, 0.01) var head_bone_follow_horizontal: float = 0.12
@export_range(1.0, 60.0, 0.5) var head_smoothing: float = 22.0
@export_range(0.01, 0.3, 0.01) var eye_wall_margin: float = 0.08
## Avanço da câmera ao olhar totalmente para baixo (m): mostra o peito e as
## pernas em vez do interior do pescoço, como nos jogos com corpo verdadeiro.
@export_range(0.0, 0.5, 0.01) var look_down_forward: float = 0.22

@export_group("Terceira pessoa")
@export_range(0.8, 6.0, 0.05) var distance: float = 2.4
@export_range(0.5, 3.0, 0.05) var min_distance: float = 1.3
@export_range(1.0, 8.0, 0.05) var max_distance: float = 4.0
## Altura do pivô acima dos pés, em pé e agachado.
@export_range(0.5, 2.5, 0.01) var pivot_height: float = 1.55
@export_range(0.3, 2.0, 0.01) var crouch_pivot_height: float = 1.0
## Deslocamento lateral (positivo = ombro direito).
@export_range(-1.0, 1.0, 0.01) var shoulder_offset: float = 0.38
@export_range(0.0, 2.0, 0.01) var sprint_distance_bonus: float = 0.35
@export_range(0.05, 0.5, 0.01) var collision_radius: float = 0.18
@export_range(0.5, 20.0, 0.1) var distance_recovery_speed: float = 5.0
## Camadas que bloqueiam a câmera: mundo e objetos físicos.
@export_flags_3d_physics var collision_mask: int = 1 | 4

@export_group("Transição")
@export_range(0.05, 2.0, 0.01) var transition_time: float = 0.5
## Fração da transição abaixo da qual a cabeça fica escondida.
@export_range(0.0, 1.0, 0.01) var hide_head_below: float = 0.35

var third_person: bool = false
## 0 = primeira pessoa, 1 = terceira (com curva suave aplicada).
var blend: float = 0.0
var _progress: float = 0.0
var _arm_length: float = 0.0
var _eye_smoothed: Vector3
var _has_eye: bool = false
var _toggle_previous: bool = false
var _sprint_blend: float = 0.0
var _crouch_blend: float = 0.0
var _query := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()
var _ray := PhysicsRayQueryParameters3D.new()
## Corpo físico seguido depois da morte (cabeça do ragdoll), se houver.
var follow_target: Node3D = null
var _follow_offset: Transform3D


func _ready() -> void:
	top_level = true
	_sphere.radius = collision_radius
	_query.shape = _sphere
	_query.collision_mask = collision_mask
	_ray.collision_mask = collision_mask
	camera.current = true


func toggle() -> void:
	set_third_person(not third_person)


func set_third_person(enabled: bool) -> void:
	if enabled == third_person:
		return
	third_person = enabled
	player.third_person = enabled
	mode_changed.emit(enabled)


## Termina a transição imediatamente (spawn, cutscene).
func snap() -> void:
	_progress = 1.0 if third_person else 0.0
	blend = _progress
	_has_eye = false


func is_transitioning() -> bool:
	return (third_person and _progress < 1.0) or (not third_person and _progress > 0.0)


## Passa a seguir um corpo físico (morte). Mantém a câmera onde está.
func follow(target: Node3D) -> void:
	follow_target = target
	if target != null:
		_follow_offset = target.global_transform.affine_inverse() * camera.global_transform


func set_distance(value: float) -> void:
	distance = clampf(value, min_distance, max_distance)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		set_distance(distance - 0.25)
	elif event.is_action_pressed("camera_zoom_out"):
		set_distance(distance + 0.25)


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	var toggle_pressed := Input.is_action_pressed("toggle_camera")
	if toggle_pressed and not _toggle_previous:
		toggle()
	_toggle_previous = toggle_pressed

	var previous_progress := _progress
	var target := 1.0 if third_person else 0.0
	_progress = move_toward(_progress, target, delta / transition_time)
	blend = _smootherstep(_progress)
	if previous_progress != _progress and _progress == target:
		transition_finished.emit(third_person)

	if follow_target != null and is_instance_valid(follow_target):
		_update_follow(delta)
		return
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	# --- Primeira pessoa: olhos ---
	var anchor := first_person_anchor.global_transform
	var eye := anchor.origin
	if body != null and head_bone_follow > 0.0:
		var head_eye := body.get_eye_position()
		if not _has_eye:
			_eye_smoothed = head_eye
			_has_eye = true
		_eye_smoothed = _eye_smoothed.lerp(head_eye, 1.0 - exp(-head_smoothing * delta))
		var follow := _eye_smoothed - eye
		eye += Vector3(follow.x * head_bone_follow_horizontal, follow.y * head_bone_follow, follow.z * head_bone_follow_horizontal)
	var look_down := clampf(-player.get_pitch() / deg_to_rad(80.0), 0.0, 1.0)
	eye += -player.get_view_basis().z * look_down_forward * look_down * look_down
	eye = _clamp_eye(eye)

	# --- Terceira pessoa: órbita ---
	var settings := player.settings
	_crouch_blend = lerpf(_crouch_blend, clampf((settings.standing_height - player.get_current_height())
			/ (settings.standing_height - settings.crouch_height), 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	var sprinting := 1.0 if player.is_sprinting and player.get_horizontal_speed() > settings.jog_speed else 0.0
	_sprint_blend = lerpf(_sprint_blend, sprinting, 1.0 - exp(-3.0 * delta))
	var view := Basis.from_euler(Vector3(player.get_pitch(), player.get_view_yaw(), 0.0))
	var pivot := player.global_position + Vector3.UP * lerpf(pivot_height, crouch_pivot_height, _crouch_blend)
	pivot += view.x * shoulder_offset

	# --- Mistura ---
	var orientation := anchor.basis.orthonormalized().slerp(view, blend)
	var arm_origin := eye.lerp(pivot, blend)
	var arm_target := (distance + sprint_distance_bonus * _sprint_blend) * blend
	var arm_direction := orientation.z
	# O braço parte dos olhos (dentro da cápsula): a varredura nunca começa
	# dentro de uma parede.
	var start := eye
	var desired := arm_origin + arm_direction * arm_target
	var allowed := _sweep(start, desired)
	var full := start.distance_to(desired)
	if is_transitioning() or allowed < _arm_length:
		# Transição: segue a curva exatamente. Obstáculo: encurta na hora.
		_arm_length = allowed
	else:
		# Espaço liberado: volta suavemente à distância desejada.
		_arm_length = minf(lerpf(_arm_length, allowed, 1.0 - exp(-distance_recovery_speed * delta)), allowed)
	var position := start if full < 0.0001 else start + (desired - start) / full * _arm_length
	camera.global_transform = Transform3D(orientation, position)

	if body != null:
		body.hide_head = blend < hide_head_below
		body.head_follows_view = blend > 0.5


## Distância livre de `from` até `to` para a esfera da câmera.
func _sweep(from: Vector3, to: Vector3) -> float:
	var length := from.distance_to(to)
	if length < 0.0001:
		return 0.0
	_query.transform = Transform3D(Basis.IDENTITY, from)
	_query.motion = to - from
	_query.exclude = [player.get_rid()]
	var fractions := get_world_3d().direct_space_state.cast_motion(_query)
	if fractions.is_empty():
		return length
	return length * float(fractions[0])


## O olho não pode passar da parede quando o tronco se inclina: um raio do
## centro da cápsula, na altura do olho, limita a posição.
func _clamp_eye(eye: Vector3) -> Vector3:
	var center := Vector3(player.global_position.x, eye.y, player.global_position.z)
	_ray.from = center
	_ray.to = eye
	_ray.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return eye
	var point: Vector3 = hit["position"]
	return point - (eye - center).normalized() * eye_wall_margin


func _update_follow(_delta: float) -> void:
	if not third_person:
		camera.global_transform = follow_target.global_transform * _follow_offset
		return
	var view := Basis.from_euler(Vector3(player.get_pitch(), player.get_view_yaw(), 0.0))
	var pivot := follow_target.global_position + Vector3.UP * 0.4
	var desired := pivot + view.z * distance
	var allowed := _sweep(pivot, desired)
	camera.global_transform = Transform3D(view, pivot + view.z * allowed)


static func _smootherstep(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
