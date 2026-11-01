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
@export var animator: FirstPersonAnimator
## Alcance do braço (m) a partir dos olhos.
@export_range(0.5, 5.0, 0.05) var reach: float = 2.0
## Camadas consultadas: mundo (1) e interagíveis (5).
@export_flags_3d_physics var collision_mask: int = 1 | 16

var focused: Interactable = null
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
	if _pending != null and animator.current_animation(FirstPersonAnimator.SLOT_ACTION) != &"interact":
		_pending = null
	_update_focus()
	var pressed := Input.is_action_pressed("interact") and player.input_enabled and not player.is_dead()
	if pressed and not _pressed_previous:
		try_interact()
	_pressed_previous = pressed


func _update_focus() -> void:
	var found: Interactable = null
	if not player.is_dead():
		var origin := camera.global_position
		_ray.from = origin
		_ray.to = origin - camera.global_basis.z * reach
		_ray.exclude = [player.get_rid()]
		var hit := camera.get_world_3d().direct_space_state.intersect_ray(_ray)
		if not hit.is_empty():
			found = Interactable.find_on(hit["collider"])
			if found != null and not found.enabled:
				found = null
	if found != focused:
		focused = found
		focus_changed.emit(focused)


## Começa a interação com o objeto em foco. Retorna false se não houver
## objeto, se as mãos estiverem ocupadas ou se o personagem estiver morto.
func try_interact() -> bool:
	if focused == null or _pending != null or player.is_dead():
		return false
	if animator.is_playing(FirstPersonAnimator.SLOT_ACTION):
		return false
	_pending = focused
	animator.play(FirstPersonAnimator.SLOT_ACTION, &"interact", 1.0, 0.1, 0.18)
	interaction_started.emit(_pending)
	return true


func is_busy() -> bool:
	return _pending != null


func _on_animation_event(event: StringName, animation: StringName) -> void:
	if event != &"contact" or animation != &"interact" or _pending == null:
		return
	var target := _pending
	_pending = null
	# A mão chegou: o objeto ainda precisa estar em foco e ao alcance.
	_update_focus()
	if focused == target:
		target.interact(player)
		interaction_completed.emit(target)


func _on_overlay_finished(slot: StringName, animation: StringName) -> void:
	if slot == FirstPersonAnimator.SLOT_ACTION and animation == &"interact":
		_pending = null
