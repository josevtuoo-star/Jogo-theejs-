class_name MeleeCombat
extends Node
## Combate corpo a corpo desarmado, como máquina de estados explícita.
##
##   IDLE ── aperta ATACAR ──> PRESSED ── solta antes do limiar ──> WINDUP (soco rápido)
##                                   └── segura além do limiar ──> CHARGING (gancho)
##   CHARGING ── solta ──> WINDUP
##   WINDUP ── animação chega à janela de impacto ──> ACTIVE
##   ACTIVE ── colisão do braço com algo / fim da janela ──> RECOVERY
##   RECOVERY ── fim da animação de recuperação + intervalo ──> IDLE (ou BLOCKING)
##   IDLE ── toque em DEFESA ──> BLOCKING ── outro toque (ou correr) ──> IDLE
##
## Regras:
## - Só a ação "attack" inicia um golpe, e só na borda de descida (apertar).
##   Apertar de novo durante preparação, impacto ou recuperação é ignorado:
##   nada fica enfileirado, então não há golpes involuntários.
## - Impacto por colisão: durante a janela ativa da animação (em volta do
##   quadro de maior extensão do braço, medido na captura), uma esfera é
##   varrida a partir do ombro do braço que golpeia, na direção da mira, com o
##   comprimento da extensão REAL do braço naquele quadro. Alvo perto é
##   atingido antes; alvo fora do alcance do braço não é atingido.
## - Recuperação: soco rápido termina na própria animação; o gancho volta à
##   guarda com a animação de recuperação. Depois, um intervalo curto.
## - Defesa: um toque em DEFESA ergue a guarda e outro abaixa (não precisa
##   segurar). De guarda anda mais devagar; correr abaixa a guarda. Golpes e
##   mordidas pela frente perdem 75% do dano.
## Alvos com receive_hit(hit) recebem dano; corpos rígidos recebem impulso;
## superfícies rígidas devolvem o golpe (recuo).

signal attack_started(kind: StringName)
signal hit_landed(target: Node, damage: float, kind: StringName)
signal hit_obstacle(point: Vector3)
signal attack_missed(kind: StringName)
signal blocked(amount_prevented: float)
signal state_changed(state: State)
## Guarda ligada/desligada (um toque em DEFESA alterna).
signal guard_toggled(enabled: bool)

enum State { IDLE, PRESSED, CHARGING, WINDUP, ACTIVE, RECOVERY, BLOCKING }

@export var player: PlayerController
## Olhos do personagem (Head/CameraEffects): direção da mira.
@export var view_origin: Node3D
@export var animator: BodyAnimator
@export var stamina: StaminaComponent
## Arma na mão (opcional). Com arma: golpes de arma, dano, impulso e alcance
## da arma; sem arma: socos.
@export var equipment: PlayerEquipment

@export_group("Soco rápido")
@export_range(0.0, 200.0, 0.5) var light_damage: float = 12.0
## Impulso (kg·m/s) aplicado a corpos rígidos.
@export_range(0.0, 200.0, 0.5) var light_impulse: float = 9.0
@export_range(0.0, 100.0, 0.5) var light_stamina_cost: float = 6.0
@export_range(0.5, 3.0, 0.01) var light_speed: float = 1.15
## Intervalo depois do soco antes de outro golpe (s).
@export_range(0.0, 2.0, 0.01) var light_recovery_time: float = 0.12
## Um novo soco pode começar quando o braço já recolheu: este tempo (s, do
## clipe) depois do fim da janela de impacto. Antes disso, apertar é ignorado.
@export_range(0.0, 1.0, 0.01) var combo_ready_after: float = 0.2

@export_group("Golpe carregado")
@export_range(0.0, 300.0, 0.5) var heavy_min_damage: float = 20.0
@export_range(0.0, 300.0, 0.5) var heavy_max_damage: float = 42.0
@export_range(0.0, 300.0, 0.5) var heavy_min_impulse: float = 16.0
@export_range(0.0, 300.0, 0.5) var heavy_max_impulse: float = 34.0
@export_range(0.0, 100.0, 0.5) var heavy_stamina_cost: float = 16.0
## Segurar por mais que isto inicia o golpe carregado (s).
@export_range(0.05, 1.0, 0.01) var charge_threshold: float = 0.22
## Tempo de carga para atingir a força máxima (s).
@export_range(0.1, 5.0, 0.05) var full_charge_time: float = 1.0
@export_range(0.0, 2.0, 0.01) var heavy_recovery_time: float = 0.25
## Velocidade de deslocamento enquanto carrega o golpe.
@export_range(0.1, 1.0, 0.01) var charging_speed_multiplier: float = 0.6

@export_group("Impacto")
@export_range(0.02, 0.5, 0.01) var hit_radius: float = 0.11
## Janela ativa em volta do quadro de maior extensão (s, tempo do clipe).
@export_range(0.0, 0.3, 0.005) var active_before: float = 0.08
@export_range(0.0, 0.3, 0.005) var active_after: float = 0.06
## Folga além da extensão medida do braço (raio do punho, m).
@export_range(0.0, 0.5, 0.01) var fist_margin: float = 0.12
## Camadas atingíveis: mundo, objetos físicos, zumbis e hitboxes.
@export_flags_3d_physics var hit_mask: int = 1 | 4 | 8 | 32

@export_group("Defesa")
## Fração do dano que passa pela guarda.
@export_range(0.0, 1.0, 0.01) var block_damage_factor: float = 0.25
@export_range(0.0, 100.0, 0.5) var block_stamina_cost: float = 10.0
@export_range(0.1, 1.0, 0.01) var block_speed_multiplier: float = 0.55
## Cosseno do ângulo máximo, a partir da frente, que a guarda cobre.
@export_range(-1.0, 1.0, 0.01) var block_cone: float = 0.3

var state: State = State.IDLE
var charge: float = 0.0
var last_hit: Dictionary = {}
var _held_time: float = 0.0
var _pressed_previous: bool = false
var _block_previous: bool = false
## Guarda alternada: um toque em DEFESA ergue, outro abaixa.
var guard_enabled: bool = false
var _active_kind: StringName = &""
var _recovery_clip: StringName = &""
var _recovery_timer: float = 0.0
var _tired: bool = false
var _next_light: StringName = &"punch_jab"
var _last_light_end: float = -10.0
## Relógio do jogo (s): independe do tempo real, da taxa de quadros e de pausas.
var _clock: float = 0.0
var _chaining: bool = false
var _query := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_sphere.radius = hit_radius
	_query.shape = _sphere
	_query.collision_mask = hit_mask
	_ray.collision_mask = hit_mask
	if player.health != null:
		player.health.damage_filter = _filter_damage


func can_attack() -> bool:
	if player.is_dead():
		return false
	if state == State.RECOVERY:
		return _combo_ready()
	return (state == State.IDLE or state == State.BLOCKING) and not animator.is_playing(BodyAnimator.SLOT_ACTION)


## Soco rápido já recolhido: o próximo pode começar (cancelando o fim da
## animação), sem fila de comandos.
func _combo_ready() -> bool:
	if not _recovery_clip in [&"punch_jab", &"punch_cross", &"weapon_swing_a", &"chop", &"mine"]:
		return false
	if animator.current_animation(BodyAnimator.SLOT_ACTION) != _recovery_clip:
		return false
	var ready_at := animator.get_event_time(_recovery_clip, &"hit") + active_after + combo_ready_after
	return animator.get_overlay_time(BodyAnimator.SLOT_ACTION) >= ready_at


func is_blocking() -> bool:
	return state == State.BLOCKING


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)


func _physics_process(delta: float) -> void:
	_clock += delta
	var alive := not player.is_dead() and player.input_enabled
	var pressed := Input.is_action_pressed("attack") and alive
	var block_pressed := Input.is_action_pressed("block") and alive
	if block_pressed and not _block_previous:
		set_guard(not guard_enabled)
	_block_previous = block_pressed
	# Correr baixa a guarda (não dá para correr de guarda erguida).
	if guard_enabled and Input.is_action_pressed("sprint") and player.get_horizontal_speed() > 0.5:
		set_guard(false)
	var block_held := guard_enabled
	var just_pressed := pressed and not _pressed_previous
	_pressed_previous = pressed
	if not alive:
		_cancel()
		return
	match state:
		State.IDLE, State.BLOCKING:
			if just_pressed and can_attack():
				_set_state(State.PRESSED)
				_held_time = 0.0
			elif block_held:
				_set_state(State.BLOCKING)
			else:
				_set_state(State.IDLE)
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
				_set_state(State.WINDUP)
				animator.release_hold(BodyAnimator.SLOT_ACTION)
		State.WINDUP, State.ACTIVE:
			_update_strike()
		State.RECOVERY:
			if just_pressed and _combo_ready():
				_chaining = true
				_set_state(State.PRESSED)
				_held_time = 0.0
			elif not animator.is_playing(BodyAnimator.SLOT_ACTION) or animator.current_animation(BodyAnimator.SLOT_ACTION) != _recovery_clip:
				_recovery_timer -= delta
				if _recovery_timer <= 0.0:
					_last_light_end = _clock
					_set_state(State.BLOCKING if block_held else State.IDLE)
	var guarding := state == State.BLOCKING or (block_held and state == State.RECOVERY)
	animator.set_guard(guarding)
	if state == State.BLOCKING:
		player.action_speed_multiplier = block_speed_multiplier
	elif state == State.CHARGING:
		player.action_speed_multiplier = charging_speed_multiplier
	else:
		player.action_speed_multiplier = 1.0


func _weapon() -> WeaponData:
	return equipment.weapon if equipment != null else null


func _start_light() -> void:
	var weapon := _weapon()
	if weapon != null:
		_chaining = false
		# Diante de uma árvore com o machado ou de rocha com a picareta, o
		# golpe é o de trabalho (corte de lenhador, picareta de cima para
		# baixo); senão, o golpe de arma.
		_active_kind = _work_clip(weapon)
		charge = 0.0
		player.face_view_for(0.7)
		var speed := weapon.light_speed if _active_kind == &"weapon_swing_a" else 1.05
		animator.play(BodyAnimator.SLOT_ACTION, _active_kind, speed, 0.08, 0.2, 1.0, false, true)
		_recovery_clip = _active_kind
		_recovery_timer = weapon.light_recovery
		_set_state(State.WINDUP)
		attack_started.emit(&"attack_light")
		return
	# Um-dois: um segundo soco logo depois do primeiro sai com a outra mão.
	# Encadeado (ainda na recuperação) ou logo depois do anterior: alterna.
	if not _chaining and _clock - _last_light_end > 0.8:
		_next_light = &"punch_jab"
	_chaining = false
	_active_kind = _next_light
	_next_light = &"punch_cross" if _next_light == &"punch_jab" else &"punch_jab"
	_tired = stamina != null and not stamina.try_consume(light_stamina_cost)
	charge = 0.0
	player.face_view_for(0.6)
	animator.play(BodyAnimator.SLOT_ACTION, _active_kind, light_speed, 0.06, 0.15, 1.0, false, true)
	_recovery_clip = _active_kind
	_recovery_timer = light_recovery_time
	_set_state(State.WINDUP)
	attack_started.emit(&"attack_light")


func _start_heavy() -> void:
	var weapon := _weapon()
	if weapon != null and _work_clip(weapon) != &"weapon_swing_a":
		# Trabalho (cortar, minerar) não carrega: segurar dá golpes seguidos.
		_start_light()
		return
	if weapon != null:
		# Golpe amplo de arma: segura na preparação enquanto carrega.
		_active_kind = &"weapon_swing_b"
		charge = 0.0
		player.face_view_for(1.5)
		animator.play(BodyAnimator.SLOT_ACTION, _active_kind, 1.0, 0.08, 0.2, 1.0, true, true)
		_recovery_clip = _active_kind
		_recovery_timer = weapon.heavy_recovery
		_set_state(State.CHARGING)
		attack_started.emit(&"attack_heavy")
		return
	_active_kind = &"punch_hook"
	charge = 0.0
	player.face_view_for(1.5)
	animator.play(BodyAnimator.SLOT_ACTION, &"punch_hook", 1.0, 0.08, 0.1, 1.0, true, true)
	_recovery_clip = &"punch_hook_recover"
	_recovery_timer = heavy_recovery_time
	_set_state(State.CHARGING)
	attack_started.emit(&"attack_heavy")


## Janela ativa: varre o braço enquanto ele se estende.
func _update_strike() -> void:
	if animator.current_animation(BodyAnimator.SLOT_ACTION) != _active_kind:
		# Animação interrompida (ferimento forte, morte): golpe perdido.
		_enter_recovery(false)
		return
	var hit_time := animator.get_event_time(_active_kind, &"hit")
	var time := animator.get_overlay_time(BodyAnimator.SLOT_ACTION)
	if time < hit_time - active_before:
		return
	_set_state(State.ACTIVE)
	if _sweep_arm():
		_enter_recovery(true)
	elif time > hit_time + active_after:
		last_hit = {}
		attack_missed.emit(_active_kind)
		_enter_recovery(false)


func _enter_recovery(_landed: bool) -> void:
	if _active_kind == &"punch_hook" and animator.current_animation(BodyAnimator.SLOT_ACTION) == &"punch_hook":
		# O gancho volta à guarda com a recuperação capturada.
		animator.play(BodyAnimator.SLOT_ACTION, &"punch_hook_recover", 1.0, 0.08, 0.2, 1.0, false, true)
	_set_state(State.RECOVERY)


## Ombro e punho do braço que golpeia, no mundo.
func _arm_points() -> Array[Vector3]:
	var skeleton := animator.skeleton
	var hand_name := String(animator.animation_player.get_animation(_active_kind).get_meta(&"hand", "hand_r"))
	var side := hand_name.substr(hand_name.length() - 2)
	var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("upperarm" + side)).origin
	var fist := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(hand_name)).origin
	return [shoulder, fist]


## Ponto para onde o jogador olha (o que está sob a mira, até 2 m).
func _aim_point(space: PhysicsDirectSpaceState3D) -> Vector3:
	var eye := view_origin.global_position
	var forward := -view_origin.global_basis.z
	_ray.from = eye
	_ray.to = eye + forward * 2.0
	_ray.exclude = [player.get_rid()]
	var hit := space.intersect_ray(_ray)
	return hit["position"] if not hit.is_empty() else eye + forward * 1.2


## Varre a esfera do ombro em direção ao ponto mirado, pela extensão atual do
## braço (o punho converge para o que está sob a mira, sem paralaxe entre
## olho e ombro). Retorna verdadeiro se acertou algo (e aplica o golpe).
func _sweep_arm() -> bool:
	var points := _arm_points()
	var shoulder := points[0]
	var weapon := _weapon()
	# Com arma, o alcance é o braço mais o comprimento útil da arma.
	var extension := shoulder.distance_to(points[1]) + (weapon.reach if weapon != null else fist_margin)
	_sphere.radius = weapon.hit_radius if weapon != null else hit_radius
	var space := view_origin.get_world_3d().direct_space_state
	var aim := (_aim_point(space) - shoulder).normalized()
	_query.transform = Transform3D(Basis.IDENTITY, shoulder)
	_query.motion = aim * extension
	_query.exclude = [player.get_rid()]
	var fractions := space.cast_motion(_query)
	if fractions.is_empty() or fractions[1] >= 1.0:
		return false
	_query.transform = Transform3D(Basis.IDENTITY, shoulder + aim * extension * fractions[1])
	_query.motion = Vector3.ZERO
	var rest := space.get_rest_info(_query)
	if rest.is_empty():
		return false
	_apply_hit(instance_from_id(rest["collider_id"]) as Node, rest["point"], aim, rest.get("shape", -1))
	return true


func _apply_hit(target: Node, point: Vector3, direction: Vector3, shape: int = -1) -> void:
	var heavy := _active_kind == &"punch_hook" or _active_kind == &"weapon_swing_b"
	var damage := lerpf(heavy_min_damage, heavy_max_damage, charge) if heavy else light_damage
	var impulse := lerpf(heavy_min_impulse, heavy_max_impulse, charge) if heavy else light_impulse
	var weapon := _weapon()
	if weapon != null:
		damage = lerpf(weapon.heavy_min_damage, weapon.heavy_max_damage, charge) if heavy else weapon.light_damage
		impulse = lerpf(weapon.heavy_min_impulse, weapon.heavy_max_impulse, charge) if heavy else weapon.light_impulse
	if heavy:
		_tired = stamina != null and not stamina.try_consume(heavy_stamina_cost)
	if _tired:
		# Exausto: o golpe sai fraco.
		damage *= 0.5
		impulse *= 0.5
	var hit := {
		"damage": damage, "impulse": impulse, "direction": direction, "point": point,
		"kind": _active_kind, "attacker": player,
		"weapon": weapon.id if weapon != null else &"",
		"shape": shape,
	}
	last_hit = hit.duplicate()
	last_hit["target"] = target
	var receiver := _find_receiver(target)
	# O alvo pode recusar o golpe (ferramenta errada numa árvore ou rocha):
	# aí é superfície rígida, o golpe rebate.
	var accepted: Variant = receiver.call(&"receive_hit", hit) if receiver != null else false
	if receiver != null and accepted != false:
		hit_landed.emit(receiver, damage, _active_kind)
		_wear()
	elif target is RigidBody3D:
		var body := target as RigidBody3D
		body.apply_impulse(direction * impulse, point - body.global_position)
		hit_landed.emit(body, 0.0, _active_kind)
	else:
		# Superfície rígida: o golpe é rebatido e o tronco recua (com arma, o
		# impacto volta pelo cabo da mesma forma).
		animator.play(BodyAnimator.SLOT_ACTION, &"hit_head", 1.4, 0.03, 0.15, 1.0, false, true)
		_recovery_clip = &"hit_head"
		hit_obstacle.emit(point)


## Um golpe útil gasta a ferramenta da mão (pode quebrar).
func _wear() -> void:
	if equipment != null and equipment.inventory != null and _weapon() != null:
		equipment.inventory.wear_equipped(1.0)


## Golpe de trabalho conforme o que está na mira, ao alcance da ferramenta.
func _work_clip(weapon: WeaponData) -> StringName:
	var space := view_origin.get_world_3d().direct_space_state
	var eye := view_origin.global_position
	_ray.from = eye
	_ray.to = eye - view_origin.global_basis.z * 2.6
	_ray.exclude = [player.get_rid()]
	var hit := space.intersect_ray(_ray)
	if hit.is_empty() or not (hit["collider"] is ChunkResources):
		return &"weapon_swing_a"
	var entry := (hit["collider"] as ChunkResources).entry_for_shape(hit.get("shape", -1))
	if entry.is_empty() or entry["tool"] != weapon.id:
		return &"weapon_swing_a"
	return &"chop" if entry["kind"] == &"arvore" else &"mine"


func _find_receiver(node: Node) -> Node:
	var current := node
	for i in 3:
		if current == null:
			return null
		if current.has_method(&"receive_hit"):
			return current
		current = current.get_parent()
	return null


## Defesa: golpes e mordidas vindos da frente perdem a maior parte do dano.
func _filter_damage(amount: float, kind: StringName, direction: Vector3) -> float:
	if state != State.BLOCKING or animator.get_layer_weights()["guard"] < 0.6:
		return amount
	if kind != &"golpe" and kind != &"mordida":
		return amount
	var facing := -player.get_view_basis().z
	var incoming := Vector3(direction.x, 0.0, direction.z)
	# `direction` é para onde o golpe empurra: vindo da frente, aponta para trás.
	if incoming.length_squared() > 0.0001 and incoming.normalized().dot(facing) > -block_cone:
		return amount
	if stamina != null and not stamina.try_consume(block_stamina_cost):
		return amount # sem fôlego, a guarda cede
	var reduced := amount * block_damage_factor
	# Impacto na guarda: o tronco recua, braços continuam na defesa.
	animator.play(BodyAnimator.SLOT_HURT, &"block_impact", 1.6, 0.03, 0.2, 0.7, false, true)
	blocked.emit(amount - reduced)
	return reduced


## Ergue ou abaixa a guarda (alternância). Morrer também abaixa.
func set_guard(enabled: bool) -> void:
	if enabled == guard_enabled:
		return
	guard_enabled = enabled
	guard_toggled.emit(enabled)


func _cancel() -> void:
	set_guard(false)
	if state != State.IDLE:
		_set_state(State.IDLE)
	animator.set_guard(false)
	player.action_speed_multiplier = 1.0
