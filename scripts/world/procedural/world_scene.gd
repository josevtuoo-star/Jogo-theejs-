class_name WorldScene
extends Node3D
## Cena principal do mundo procedural: gera os pedaços em volta do ponto de
## partida antes do primeiro quadro (o jogador nasce em chão com colisão) e
## põe o sobrevivente na rodovia. Os outros pedaços chegam em segundo plano.

@export var world: ProceduralWorld
@export var player: PlayerController
## Raio gerado na partida, antes de liberar o jogador.
@export_range(0, 3) var start_radius: int = 1


## Salvamento automático (com permissão), em segundos.
const AUTOSAVE_SECONDS := 60.0

var _autosave: float = 0.0


func _ready() -> void:
	var spawn := world.generator.spawn_point()
	var state: Dictionary = GameSession.world_state if GameSession.active else {}
	var start := spawn
	var yaw := 0.0
	var pitch := -0.05
	if state.has("jogador"):
		var saved: Dictionary = state["jogador"]
		var p: Array = saved.get("posicao", [])
		if p.size() == 3:
			start = Vector3(float(p[0]), float(p[1]), float(p[2])) + Vector3.UP * 0.05
		yaw = float(saved.get("guinada", 0.0))
		pitch = float(saved.get("arfagem", 0.0))
		if player.health != null and saved.has("vida"):
			player.health.current = clampf(float(saved["vida"]), 1.0, player.health.max_health)
	for key: String in state.get("removidos", []):
		world.mark_removed(key)
	for key: String in state.get("pegos", []):
		world.mark_taken(key)
	world.generate_now(start, start_radius)
	player.teleport(start)
	player.set_view_rotation(yaw, pitch)
	var inventory := player.get_node_or_null("Inventory") as Inventory
	if inventory != null and state.has("mochila"):
		inventory.from_data(state["mochila"])
	if not state.get("kit", false):
		_starter_kit(spawn)
	var death := player.get_node_or_null("Death") as PlayerDeath
	if death != null:
		death.spawn_transform = Transform3D(Basis.IDENTITY, spawn)
		# Renascer longe de onde morreu: o chão da partida pode ter sido
		# descarregado; é gerado na hora (antes do próximo passo da física).
		death.respawned.connect(func() -> void: world.generate_now(player.global_position, start_radius))


## Mundo novo: um acampamento abandonado na beira da estrada, com o
## essencial para começar (picareta, machado e tochas para a caverna que
## fica perto da partida).
func _starter_kit(spawn: Vector3) -> void:
	var side := Vector3(-4.2, 0.0, -3.0)
	var at := spawn + side
	at.y = world.generator.surface_height(at.x, at.z)
	var items := [[&"picareta", Vector3(0.0, 0.0, 0.0)], [&"machado", Vector3(0.9, 0.0, 0.6)],
			[&"tocha", Vector3(-0.8, 0.0, 0.5)]]
	for entry: Array in items:
		var item := ItemData.find(entry[0])
		var where := at + (entry[1] as Vector3)
		where.y = world.generator.surface_height(where.x, where.z) + 0.35
		var t := Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, randf() * TAU), where)
		if item.weapon != null and item.tool_type != &"tocha":
			WeaponPickup.spawn(item.weapon, t, self)
		else:
			ItemPickup.spawn(item, t, self, 2)
	_kit_given = true


var _kit_given: bool = false


## Estado do mundo para salvar: jogador, mochila e o que mudou no mundo.
func capture_state() -> Dictionary:
	var p := player.global_position
	var inventory := player.get_node_or_null("Inventory") as Inventory
	return {
		"jogador": {"posicao": [p.x, p.y, p.z], "guinada": player.get_view_yaw(), "arfagem": player.get_pitch(),
				"vida": player.health.current if player.health != null else 100.0},
		"mochila": inventory.to_data() if inventory != null else {},
		"removidos": world.removed_keys(),
		"pegos": world.taken_keys(),
		"kit": _kit_given or GameSession.world_state.get("kit", false),
	}


func save_now() -> bool:
	if player.is_dead():
		return false
	return GameSession.save_world(capture_state())


func _process(delta: float) -> void:
	if not GameSession.active or not GameSession.storage_allowed:
		return
	_autosave += delta
	if _autosave >= AUTOSAVE_SECONDS:
		_autosave = 0.0
		save_now()


func _notification(what: int) -> void:
	# Celular: o jogo vai para segundo plano (ou é fechado) — grava antes.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if GameSession.active and GameSession.storage_allowed and is_inside_tree():
			save_now()


# --- Rede de segurança ---------------------------------------------------------
#
# O terreno é uma casca (a malha visível é a colisão). Se algo jogar o
# jogador para dentro da rocha (um empurrão forte contra a parede, um
# teleporte), não há chão por dentro e ele cairia para fora do mundo. Guarda
# o último ponto seguro (em pé no chão) e volta para ele quando o jogador
# está caindo sob a superfície sem nenhum chão abaixo (raio de 40 m), ou
# abaixo de todas as cavernas.

var _safe_position := Vector3.INF
var _lost_time := 0.0
var _ray := PhysicsRayQueryParameters3D.new()


func _physics_process(delta: float) -> void:
	if player == null or world == null or player.is_dead():
		return
	var p := player.global_position
	if player.is_on_floor():
		_safe_position = p
		_lost_time = 0.0
		return
	var below_everything := p.y < WorldGenerator.CAVE_BAND_LOW - 12.0
	var falling_inside := false
	if player.velocity.y < -1.0 and p.y < world.generator.surface_height(p.x, p.z) - 2.0:
		_ray.from = p + Vector3.UP * 0.5
		_ray.to = p + Vector3.DOWN * 40.0
		_ray.collision_mask = 1
		_ray.exclude = [player.get_rid()]
		falling_inside = get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()
	_lost_time = _lost_time + delta if (falling_inside or below_everything) else 0.0
	if _lost_time > 0.25 and _safe_position != Vector3.INF:
		world.generate_now(_safe_position, 1)
		player.teleport(_safe_position + Vector3.UP * 0.1)
		_lost_time = 0.0
