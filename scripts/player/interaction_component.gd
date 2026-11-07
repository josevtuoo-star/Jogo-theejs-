class_name InteractionComponent
extends Node
## Interação do jogador com o cenário.
##
## Um raio parte do centro da câmera e encontra o Interactable em foco. Ao
## apertar "interact", a animação de alcance começa e o efeito acontece no
## quadro de contato da animação (evento "contact"), quando a mão chega ao
## objeto. Se o objeto sair de alcance antes disso, nada acontece.

signal focus_changed(interactable: Interactable)
signal interaction_started(interactable: Interactable)
signal interaction_completed(interactable: Interactable)

@export var player: PlayerController
@export var camera: Camera3D
## Olhos do personagem: o alcance é medido a partir deles (vale também em
## terceira pessoa, com a câmera atrás do corpo).
@export var view_origin: Node3D
@export var animator: BodyAnimator
## Alcance do braço (m) a partir dos olhos.
@export_range(0.5, 5.0, 0.05) var reach: float = 2.3
## Camadas consultadas: mundo (1) e interagíveis (5).
@export_flags_3d_physics var collision_mask: int = 1 | 4 | 16

## Velocidade da animação de interação (a original é lenta para um gesto rápido).
const INTERACT_SPEED := 1.6

var focused: Interactable = null
var _focused_id: int = 0
var _pending: Interactable = null
var _pressed_previous: bool = false
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_ray.collide_with_areas = true
	_ray.collision_mask = collision_mask
	if animator != null:
		animator.animation_event.connect(_on_animation_event)
		animator.overlay_finished.connect(_on_overlay_finished)


func _physics_process(_delta: float) -> void:
	# A animação foi interrompida (morte, outro gesto): a interação é cancelada.
	if _pending != null and animator.current_animation(BodyAnimator.SLOT_ACTION) != &"interact":
		_pending = null
	_update_focus()
	var pressed := Input.is_action_pressed("interact") and player.input_enabled and not player.is_dead()
	if pressed and not _pressed_previous:
		try_interact()
	_pressed_previous = pressed


func _update_focus() -> void:
	var found: Interactable = null
	if not player.is_dead():
		# O raio sai da câmera pela mira; o objeto precisa estar ao alcance do braço.
		var origin := camera.global_position
		var eye := view_origin.global_position
		_ray.from = origin
		_ray.to = origin - camera.global_basis.z * (reach + origin.distance_to(eye))
		_ray.exclude = [player.get_rid()]
		var space := camera.get_world_3d().direct_space_state
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(eye) <= reach:
			found = Interactable.find_on(hit["collider"])
			if found != null and not found.enabled:
				found = null
			if found == null:
				# Mira passou raspando num objeto pequeno (pedra, tora, ferramenta
				# no chão): procura itens soltos numa esfera em volta do ponto.
				found = _nearby_pickup(space, hit["position"], eye)
	# Objeto já liberado (pego, quebrado) conta como nada em foco. (Um objeto
	# liberado é igual a null nas comparações: por isso vale o id guardado.)
	if _focused_id != 0 and not is_instance_id_valid(_focused_id):
		focused = null
		_focused_id = 0
		focus_changed.emit(null)
	if found != focused:
		focused = found
		_focused_id = found.get_instance_id() if found != null else 0
		focus_changed.emit(focused)


var _sphere_query := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()


func _nearby_pickup(space: PhysicsDirectSpaceState3D, point: Vector3, eye: Vector3) -> Interactable:
	_sphere.radius = 0.35
	_sphere_query.shape = _sphere
	_sphere_query.transform = Transform3D(Basis.IDENTITY, point)
	_sphere_query.collision_mask = 4 | 16
	_sphere_query.exclude = [player.get_rid()]
	var best: Interactable = null
	var best_distance := INF
	for result in space.intersect_shape(_sphere_query, 8):
		var candidate := Interactable.find_on(result["collider"])
		if candidate == null or not candidate.enabled or not (candidate is ItemPickup or candidate is WeaponPickup):
			continue
		var body := result["collider"] as Node3D
		var distance := body.global_position.distance_to(point)
		if distance < best_distance and body.global_position.distance_to(eye) <= reach + 0.3:
			best = candidate
			best_distance = distance
	return best


## Começa a interação com o objeto em foco. Retorna false se não houver
## objeto, se as mãos estiverem ocupadas ou se o personagem estiver morto.
func try_interact() -> bool:
	if focused == null or _pending != null or player.is_dead():
		return false
	if animator.is_playing(BodyAnimator.SLOT_ACTION):
		return false
	_pending = focused
	player.face_view_for(1.0)
	animator.play(BodyAnimator.SLOT_ACTION, &"interact", INTERACT_SPEED, 0.12, 0.2, 1.0, false, true)
	interaction_started.emit(_pending)
	return true


func is_busy() -> bool:
	return _pending != null


func _on_animation_event(event: StringName, animation: StringName) -> void:
	if event != &"contact" or animation != &"interact" or _pending == null:
		return
	var target := _pending
	_pending = null
	# A mão chegou: o objeto ainda precisa existir e estar ao alcance do braço.
	# (Não exige a mira exata: durante o gesto a cabeça se move e o raio da
	# câmera pode escapar de um objeto fino, como um cabo no chão.)
	if is_instance_valid(target) and target.enabled and _distance_to(target) <= reach + 0.25:
		target.interact(player)
		interaction_completed.emit(target)


func _distance_to(target: Interactable) -> float:
	var body := (target as Node) as Node3D
	if body == null:
		body = target.get_parent() as Node3D
	return body.global_position.distance_to(view_origin.global_position) if body != null else 0.0


func _on_overlay_finished(slot: StringName, animation: StringName) -> void:
	if slot == BodyAnimator.SLOT_ACTION and animation == &"interact":
		_pending = null
