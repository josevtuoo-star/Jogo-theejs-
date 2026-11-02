class_name PlayerSounds
extends SoundEmitter
## Sons do sobrevivente, todos disparados pelos eventos reais do jogo:
## - passos: no contato físico do pé (sinal footstep), pelo tipo de chão,
##   com volume pela intensidade (andar baixo, correr alto, agachado quase
##   mudo) e roupa farfalhando na corrida;
## - salto (esforço), aterrissagem (pelo impacto), dor (pelo dano), morte e o
##   corpo caindo;
## - combate: braço cortando o ar no golpe, acerto no corpo, na madeira, no
##   metal ou na parede, impacto na guarda;
## - interação e agachar/levantar.

@export var player: PlayerController
@export var health: HealthComponent
@export var combat: MeleeCombat
@export var interaction: InteractionComponent

var _steps: Dictionary = {}
var _sets: Dictionary = {}
var _last_pain: float = -10.0
var _clock: float = 0.0
var _step_count: int = 0


func _ready() -> void:
	super._ready()
	for surface in ["terra", "grama", "gelo", "pedra"]:
		_steps[surface] = SoundSet.load_set("footsteps/" + surface)
	for key in ["body/aterrissagem", "body/queda_corpo", "body/roupa", "voice/esforco", "voice/dor",
			"voice/morte", "combat/golpe_ar", "combat/soco_corpo", "combat/impacto_madeira",
			"combat/impacto_metal", "combat/impacto_generico", "combat/parede", "combat/defesa",
			"interact/interruptor", "interact/couro"]:
		_sets[key] = SoundSet.load_set(key)
	if player != null:
		player.footstep.connect(_on_footstep)
		player.jumped.connect(_on_jumped)
		player.landed.connect(_on_landed)
		player.stance_changed.connect(func(_stance: int) -> void: _play_body(&"roupa", "body/roupa", -6.0))
		player.wall_impact.connect(_on_wall_impact)
	if health != null:
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)
	if combat != null:
		combat.state_changed.connect(_on_combat_state)
		combat.hit_landed.connect(_on_hit_landed)
		combat.hit_obstacle.connect(func(point: Vector3) -> void: play(&"parede", _sets["combat/parede"], 0.0, 1.0, 0.06, point))
		combat.blocked.connect(func(_amount: float) -> void: _play_body(&"defesa", "combat/defesa", 0.0, 1.5))
		combat.guard_toggled.connect(func(_on: bool) -> void: _play_body(&"roupa", "body/roupa", -8.0))
	if interaction != null:
		interaction.interaction_completed.connect(_on_interaction_completed)


func _process(delta: float) -> void:
	_clock += delta


func _play_body(category: StringName, key: String, volume_db: float = 0.0, height: float = 1.0) -> void:
	play(category, _sets[key], volume_db, 1.0, 0.06, player.global_position + Vector3.UP * height)


## Superfície física → conjunto de passos.
static func step_set_for(surface: SurfaceProfile) -> String:
	if surface == null:
		return "terra"
	match surface.id:
		&"grama":
			return "grama"
		&"gelo":
			return "gelo"
		&"concreto", &"pedra", &"metal", &"madeira":
			return "pedra"
	return "terra"


func _on_footstep(intensity: float, _is_left: bool, surface: SurfaceProfile) -> void:
	var key := step_set_for(surface)
	# Intensidade 0,3 (andar agachado) .. 1 (correr): de -16 dB a 0 dB.
	var volume := lerpf(-16.0, 0.0, clampf(intensity, 0.0, 1.0))
	var pitch := 1.0
	if surface != null and surface.id == &"lama":
		pitch = 0.82 # lama: passo mais grave e abafado
		volume -= 2.0
	play(&"passo", _steps[key], volume, pitch, 0.07, player.global_position + Vector3.UP * 0.05)
	_step_count += 1
	if player.is_sprinting and _step_count % 2 == 0:
		_play_body(&"roupa", "body/roupa", -12.0)


func _on_jumped(_speed: float) -> void:
	_play_body(&"roupa", "body/roupa", -6.0)
	if randf() < 0.5:
		_play_body(&"esforco", "voice/esforco", -8.0, 1.6)


func _on_landed(impact_speed: float) -> void:
	if impact_speed < 1.5:
		return
	var volume := lerpf(-10.0, 2.0, clampf((impact_speed - 1.5) / 7.0, 0.0, 1.0))
	play(&"aterrissagem", _sets["body/aterrissagem"], volume, 1.0, 0.06, player.global_position)


func _on_wall_impact(impact_speed: float, _normal: Vector3) -> void:
	_play_body(&"impacto", "combat/impacto_generico", lerpf(-10.0, 0.0, clampf(impact_speed / 6.0, 0.0, 1.0)))


func _on_damaged(amount: float, kind: StringName, _direction: Vector3) -> void:
	if health.is_dead:
		return
	# Dor: no máximo uma vez a cada 0,6 s (arame dá dano contínuo).
	if _clock - _last_pain < 0.6 or amount < 3.0:
		return
	_last_pain = _clock
	_play_body(&"dor", "voice/dor", lerpf(-8.0, 0.0, clampf(amount / 30.0, 0.0, 1.0)), 1.6)
	if kind == &"golpe" or kind == &"mordida":
		_play_body(&"soco_corpo", "combat/soco_corpo", -4.0, 1.3)


func _on_died() -> void:
	_play_body(&"morte", "voice/morte", 0.0, 1.6)
	# O corpo chega ao chão um instante depois (ragdoll).
	get_tree().create_timer(0.55).timeout.connect(func() -> void:
		play(&"queda_corpo", _sets["body/queda_corpo"], -2.0, 0.9, 0.05, player.global_position))


func _on_combat_state(state: int) -> void:
	if state == MeleeCombat.State.WINDUP:
		# O braço corta o ar quando o golpe sai (soco rápido ou gancho solto).
		var heavy := combat.charge > 0.0
		_play_body(&"golpe_ar", "combat/golpe_ar", -4.0 if heavy else -8.0, 1.4)


func _on_hit_landed(target: Node, _damage: float, _kind: StringName) -> void:
	var point: Vector3 = combat.last_hit.get("point", player.global_position + Vector3.UP * 1.4)
	var material := ImpactSound.material_of(target)
	match material:
		&"corpo":
			play(&"soco_corpo", _sets["combat/soco_corpo"], 0.0, 1.0, 0.08, point)
		&"madeira":
			play(&"impacto_madeira", _sets["combat/impacto_madeira"], 0.0, 1.0, 0.08, point)
		&"metal":
			play(&"impacto_metal", _sets["combat/impacto_metal"], -2.0, 1.0, 0.08, point)
		_:
			play(&"impacto_generico", _sets["combat/impacto_generico"], 0.0, 1.0, 0.08, point)


func _on_interaction_completed(target: Interactable) -> void:
	if target is Campfire:
		return # a fogueira tem o próprio som
	var key := "interact/interruptor" if target is LightSwitch else "interact/couro"
	var node: Node = target
	while node != null and not node is Node3D:
		node = node.get_parent()
	var position := (node as Node3D).global_position if node != null else global_position
	play(&"interacao", _sets[key], -4.0, 1.0, 0.04, position)
