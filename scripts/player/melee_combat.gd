class_name MeleeCombat
extends Node
## Combate corpo a corpo desarmado.
##
## Toque rápido em "attack": soco rápido; toques seguidos alternam jab
## (esquerda) e cruzado (direita). Segurar: o gancho para na preparação
## enquanto o botão estiver apertado; ao soltar, sai com força proporcional ao
## tempo carregado. As animações afetam só o tronco: as pernas continuam a
## locomoção. O acerto é calculado no quadro de impacto da animação (evento
## "hit", medido na própria animação), com uma esfera varrida a partir dos
## olhos na direção do olhar — igual em primeira e terceira pessoa. Alvos com
## receive_hit(hit) recebem dano; corpos rígidos recebem impulso; superfícies
## rígidas devolvem o golpe.

signal attack_started(kind: StringName)
signal hit_landed(target: Node, damage: float, kind: StringName)
signal hit_obstacle(point: Vector3)
signal attack_missed(kind: StringName)

@export var player: PlayerController
## Olhos do personagem (Head/CameraEffects): origem e direção dos golpes.
@export var view_origin: Node3D
@export var animator: BodyAnimator
@export var stamina: StaminaComponent

@export_group("Soco rápido")
@export_range(0.0, 200.0, 0.5) var light_damage: float = 12.0
## Impulso (kg·m/s) aplicado a corpos rígidos.
@export_range(0.0, 200.0, 0.5) var light_impulse: float = 9.0
@export_range(0.2, 3.0, 0.01) var light_reach: float = 0.85
@export_range(0.0, 100.0, 0.5) var light_stamina_cost: float = 6.0

@export_group("Golpe carregado")
@export_range(0.0, 300.0, 0.5) var heavy_min_damage: float = 20.0
@export_range(0.0, 300.0, 0.5) var heavy_max_damage: float = 42.0
@export_range(0.0, 300.0, 0.5) var heavy_min_impulse: float = 16.0
@export_range(0.0, 300.0, 0.5) var heavy_max_impulse: float = 34.0
@export_range(0.2, 3.0, 0.01) var heavy_reach: float = 1.0
@export_range(0.0, 100.0, 0.5) var heavy_stamina_cost: float = 16.0
## Segurar por mais que isto inicia o golpe carregado (s).
@export_range(0.05, 1.0, 0.01) var charge_threshold: float = 0.22
## Tempo de carga para atingir a força máxima (s).
@export_range(0.1, 5.0, 0.05) var full_charge_time: float = 1.0

@export_group("Varredura")
@export_range(0.02, 0.5, 0.01) var hit_radius: float = 0.12
## Camadas atingíveis: mundo, objetos físicos, zumbis e hitboxes.
@export_flags_3d_physics var hit_mask: int = 1 | 4 | 8 | 32

enum State { IDLE, PRESSED, CHARGING, STRIKING }

var state: State = State.IDLE
var charge: float = 0.0
var last_hit: Dictionary = {}
var _held_time: float = 0.0
var _pressed_previous: bool = false
var _active_kind: StringName = &""
var _tired: bool = false
var _next_light: StringName = &"punch_jab"
var _last_light_end: float = -10.0
var _query := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()


func _ready() -> void:
	_sphere.radius = hit_radius
	_query.shape = _sphere
	_query.collision_mask = hit_mask
	animator.animation_event.connect(_on_animation_event)
	animator.overlay_finished.connect(_on_overlay_finished)


func _physics_process(delta: float) -> void:
	var pressed := Input.is_action_pressed("attack") and player.input_enabled and not player.is_dead()
	match state:
		State.IDLE:
			if pressed and not _pressed_previous and can_attack():
				state = State.PRESSED
				_held_time = 0.0
		State.PRESSED:
			_held_time += delta
			if not pressed:
				_start_light()
			elif _held_time >= charge_threshold:
				_start_heavy()
		State.CHARGING:
			_held_time += delta
			charge = clampf((_held_time - charge_threshold) / full_charge_time, 0.0, 1.0)
			player.face_view_for(0.3)
			if not pressed:
				state = State.STRIKING
				animator.release_hold(BodyAnimator.SLOT_ACTION)
		State.STRIKING:
			if animator.current_animation(BodyAnimator.SLOT_ACTION) != _active_kind:
				_last_light_end = Time.get_ticks_msec() / 1000.0
				state = State.IDLE
	if player.is_dead() and state != State.IDLE:
		state = State.IDLE
	_pressed_previous = pressed


func can_attack() -> bool:
	return not player.is_dead() and not animator.is_playing(BodyAnimator.SLOT_ACTION)


func _start_light() -> void:
	# Um-dois: um segundo soco logo depois do primeiro sai com a outra mão.
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_light_end > 0.8:
		_next_light = &"punch_jab"
	_active_kind = _next_light
	_next_light = &"punch_cross" if _next_light == &"punch_jab" else &"punch_jab"
	_tired = stamina != null and not stamina.try_consume(light_stamina_cost)
	charge = 0.0
	player.face_view_for(0.6)
	animator.play(BodyAnimator.SLOT_ACTION, _active_kind, 1.15, 0.06, 0.15, 1.0, false, true)
	state = State.STRIKING
	attack_started.emit(&"attack_light")


func _start_heavy() -> void:
	_active_kind = &"punch_hook"
	charge = 0.0
	player.face_view_for(1.5)
	animator.play(BodyAnimator.SLOT_ACTION, &"punch_hook", 1.0, 0.08, 0.15, 1.0, true, true)
	state = State.CHARGING
	attack_started.emit(&"attack_heavy")


func _on_animation_event(event: StringName, animation: StringName) -> void:
	if event != &"hit" or animation != _active_kind:
		return
	var heavy := animation == &"punch_hook"
	var damage := lerpf(heavy_min_damage, heavy_max_damage, charge) if heavy else light_damage
	var impulse := lerpf(heavy_min_impulse, heavy_max_impulse, charge) if heavy else light_impulse
	var reach := heavy_reach if heavy else light_reach
	if heavy:
		_tired = stamina != null and not stamina.try_consume(heavy_stamina_cost)
	if _tired:
		# Exausto: o golpe sai fraco.
		damage *= 0.5
		impulse *= 0.5
	_resolve_hit(animation, damage, impulse, reach)


## Varre uma esfera dos olhos até o alcance e aplica o golpe no primeiro
## corpo encontrado.
func _resolve_hit(kind: StringName, damage: float, impulse: float, reach: float) -> void:
	var space := view_origin.get_world_3d().direct_space_state
	var forward := -view_origin.global_basis.z
	var start := view_origin.global_position + forward * 0.1
	_query.transform = Transform3D(Basis.IDENTITY, start)
	_query.motion = forward * reach
	_query.exclude = [player.get_rid()]
	var fractions := space.cast_motion(_query)
	if fractions.is_empty() or fractions[1] >= 1.0:
		last_hit = {}
		attack_missed.emit(kind)
		return
	_query.transform = Transform3D(Basis.IDENTITY, start + forward * reach * fractions[1])
	_query.motion = Vector3.ZERO
	var rest := space.get_rest_info(_query)
	if rest.is_empty():
		last_hit = {}
		attack_missed.emit(kind)
		return
	var target := instance_from_id(rest["collider_id"]) as Node
	var point: Vector3 = rest["point"]
	var hit := {
		"damage": damage, "impulse": impulse, "direction": forward, "point": point,
		"kind": kind, "attacker": player,
	}
	last_hit = hit.duplicate()
	last_hit["target"] = target
	var receiver := _find_receiver(target)
	if receiver != null:
		receiver.call(&"receive_hit", hit)
		hit_landed.emit(receiver, damage, kind)
	elif target is RigidBody3D:
		var body := target as RigidBody3D
		body.apply_impulse(forward * impulse, point - body.global_position)
		hit_landed.emit(body, 0.0, kind)
	else:
		# Superfície rígida: o golpe é rebatido e o tronco recua.
		animator.play(BodyAnimator.SLOT_ACTION, &"hit_head", 1.4, 0.03, 0.15, 1.0, false, true)
		_active_kind = &"hit_head"
		hit_obstacle.emit(point)


func _find_receiver(node: Node) -> Node:
	var current := node
	for i in 3:
		if current == null:
			return null
		if current.has_method(&"receive_hit"):
			return current
		current = current.get_parent()
	return null


func _on_overlay_finished(slot: StringName, animation: StringName) -> void:
	if slot == BodyAnimator.SLOT_ACTION and animation == _active_kind:
		_last_light_end = Time.get_ticks_msec() / 1000.0
		state = State.IDLE
