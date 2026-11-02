class_name PlayerSounds
extends SoundEmitter
## Sons do sobrevivente, todos disparados pelos eventos reais do jogo.
## Mistura com proporções reais: passos bem abaixo de um soco (andando quase
## não se ouve), ambiente presente, nada no mesmo volume. Passo no chão de
## floresta em duas camadas sorteadas (calcanhar abafado + folhas secas).
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
## Esforço acumulado da corrida (0..1): a respiração aparece depois de
## alguns segundos correndo e some aos poucos depois de parar.
var effort: float = 0.0
## Respirações avulsas, com intervalo pelo esforço (não um laço ofegante).
var _breaths: SoundSet
var _next_breath: float = 0.0
var breaths_played: int = 0


func _ready() -> void:
	super._ready()
	for surface in ["calcanhar", "folhas", "grama", "gelo", "pedra"]:
		_steps[surface] = SoundSet.load_set("footsteps/" + surface)
	_breaths = SoundSet.load_set("voice/respiracao")
	for key in ["body/aterrissagem", "body/queda_corpo", "body/roupa", "voice/esforco", "voice/dor",
			"voice/morte", "combat/golpe_ar", "combat/soco_corpo", "combat/impacto_madeira",
			"combat/impacto_metal", "combat/impacto_generico", "combat/parede", "combat/defesa",
			"interact/interruptor", "interact/couro"]:
		_sets[key] = SoundSet.load_set(key)
	if player != null:
		player.footstep.connect(_on_footstep)
		player.jumped.connect(_on_jumped)
		player.landed.connect(_on_landed)
		player.stance_changed.connect(func(_stance: int) -> void: _play_body(&"roupa", "body/roupa", -14.0))
		player.wall_impact.connect(_on_wall_impact)
	if health != null:
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)
	if combat != null:
		combat.state_changed.connect(_on_combat_state)
		combat.hit_landed.connect(_on_hit_landed)
		combat.hit_obstacle.connect(func(point: Vector3) -> void: play(&"parede", _sets["combat/parede"], 0.0, 1.0, 0.06, point))
		combat.blocked.connect(func(_amount: float) -> void: _play_body(&"defesa", "combat/defesa", 0.0, 1.5))
		combat.guard_toggled.connect(func(_on: bool) -> void: _play_body(&"roupa", "body/roupa", -16.0))
	if interaction != null:
		interaction.interaction_completed.connect(_on_interaction_completed)


func _process(delta: float) -> void:
	_clock += delta
	if player == null:
		return
	# Esforço: sobe correndo (cheio em ~8 s) e desce devagar (~25 s), como
	# o fôlego de quem correu e está se recuperando.
	var sprinting := player.is_sprinting and player.get_horizontal_speed() > player.settings.jog_speed
	effort = clampf(effort + (delta / 8.0 if sprinting else -delta / 25.0), 0.0, 1.0)
	# Uma respiração por vez: cansado, a cada ~1,6 s (≈37 por minuto, ritmo
	# de quem correu muito); recuperando, o intervalo cresce até ~3,2 s
	# (≈19/min) e some. Intervalo e volume variam um pouco a cada respiração.
	if effort > 0.3 and not player.is_dead():
		_next_breath -= delta
		if _next_breath <= 0.0:
			var heavy := smoothstep(0.3, 1.0, effort)
			play(&"respiracao", _breaths, lerpf(-26.0, -14.0, heavy), lerpf(0.94, 1.0, heavy), 0.04,
					player.global_position + Vector3.UP * 1.6, 1.5)
			breaths_played += 1
			_next_breath = lerpf(3.2, 1.6, heavy) * randf_range(0.88, 1.12)
	else:
		_next_breath = minf(_next_breath, 0.8)


func _play_body(category: StringName, key: String, volume_db: float = 0.0, height: float = 1.0) -> void:
	play(category, _sets[key], volume_db, 1.0, 0.06, player.global_position + Vector3.UP * height)


## Superfície física → conjunto de passos ("terra" = calcanhar + folhas).
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


## Toca um passo: chão de floresta em duas camadas, os outros em uma.
func _play_step(key: String, volume: float, pitch: float, at: Vector3) -> void:
	if key == "terra":
		play(&"passo", _steps["calcanhar"], volume - 2.0, pitch * 0.95, 0.08, at)
		# Folhas: às vezes mais, às vezes menos (o chão não é uniforme).
		play(&"passo_folhas", _steps["folhas"], volume - randf_range(4.0, 9.0), pitch, 0.1, at, 3.0)
	elif key == "grama":
		play(&"passo", _steps["grama"], volume - 3.0, pitch, 0.07, at)
		play(&"passo_folhas", _steps["folhas"], volume - randf_range(10.0, 14.0), pitch * 1.1, 0.1, at, 3.0)
	else:
		play(&"passo", _steps[key], volume, pitch, 0.07, at)


func _on_footstep(intensity: float, _is_left: bool, surface: SurfaceProfile) -> void:
	var key := step_set_for(surface)
	# Intensidade 0,3 (agachado) .. 1 (correndo): de -26 dB a -10 dB. Um passo
	# é bem mais baixo que um soco; andando, quase só se ouve de perto.
	var volume := lerpf(-26.0, -10.0, clampf(intensity, 0.0, 1.0))
	var pitch := 1.0
	if surface != null and surface.id == &"lama":
		pitch = 0.82 # lama: passo mais grave e abafado
		volume -= 2.0
	_play_step(key, volume, pitch, player.global_position + Vector3.UP * 0.05)
	_step_count += 1
	if player.is_sprinting and _step_count % 3 == 0:
		_play_body(&"roupa", "body/roupa", -20.0)


func _on_jumped(_speed: float) -> void:
	# Impulso: o pé empurrando o chão e a roupa (sem gemido a cada salto).
	_play_step(step_set_for(player.current_surface), -14.0, 1.05, player.global_position)
	_play_body(&"roupa", "body/roupa", -16.0)


func _on_landed(impact_speed: float) -> void:
	if impact_speed < 1.5:
		return
	# Aterrissar = os dois pés batendo no chão (40 ms de diferença) e, em
	# quedas maiores, o corpo absorvendo o impacto.
	var strength := clampf((impact_speed - 1.5) / 7.0, 0.0, 1.0)
	var key := step_set_for(player.current_surface)
	_play_step(key, lerpf(-14.0, -4.0, strength), 0.92, player.global_position)
	get_tree().create_timer(0.04).timeout.connect(func() -> void:
		_play_step(key, lerpf(-16.0, -6.0, strength), 0.88, player.global_position))
	play(&"aterrissagem", _sets["body/aterrissagem"], lerpf(-22.0, -4.0, strength), 1.0, 0.06, player.global_position)
	if impact_speed > 7.0:
		_play_body(&"esforco", "voice/esforco", -10.0, 1.6)


func _on_wall_impact(impact_speed: float, _normal: Vector3) -> void:
	_play_body(&"impacto", "combat/impacto_generico", lerpf(-10.0, 0.0, clampf(impact_speed / 6.0, 0.0, 1.0)))


func _on_damaged(amount: float, kind: StringName, _direction: Vector3) -> void:
	if health.is_dead:
		return
	# Dor: só em ferimentos de verdade e no máximo a cada 1,2 s (arame dá
	# dano contínuo; ninguém grita a cada arranhão).
	if _clock - _last_pain < 1.2 or amount < 8.0:
		return
	_last_pain = _clock
	_play_body(&"dor", "voice/dor", lerpf(-12.0, -2.0, clampf(amount / 40.0, 0.0, 1.0)), 1.6)
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
		var weapon := _weapon()
		if weapon == null:
			_play_body(&"golpe_ar", "combat/golpe_ar", -10.0 if heavy else -15.0, 1.4)
			return
		# Arma: deslocamento de ar mais grave e mais forte quanto mais pesada.
		var weight := clampf((weapon.mass - 1.0) / 2.0, 0.0, 1.0)
		play(&"golpe_ar", _sets["combat/golpe_ar"], (-6.0 if heavy else -9.0) + weight * 2.0,
				lerpf(0.9, 0.68, weight), 0.06, player.global_position + Vector3.UP * 1.4)


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
	# Com arma, soa também o material dela (madeira do taco, aço do machado e
	# da picareta), mais baixo no corpo, que abafa.
	var weapon := _weapon()
	if weapon != null and weapon.impact_material != material:
		var key := "combat/impacto_metal" if weapon.impact_material == &"metal" else "combat/impacto_madeira"
		play(&"impacto_arma", _sets[key], -9.0 if material == &"corpo" else -4.0, 1.0, 0.08, point)


func _weapon() -> WeaponData:
	var equipment := player.get_node_or_null("Equipment") as PlayerEquipment
	return equipment.weapon if equipment != null else null


func _on_interaction_completed(target: Interactable) -> void:
	if target is Campfire:
		return # a fogueira tem o próprio som
	var key := "interact/interruptor" if target is LightSwitch else "interact/couro"
	var node: Node = target
	while node != null and not node is Node3D:
		node = node.get_parent()
	var position := (node as Node3D).global_position if node != null else global_position
	play(&"interacao", _sets[key], -4.0, 1.0, 0.04, position)
