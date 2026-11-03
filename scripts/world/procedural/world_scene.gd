class_name WorldScene
extends Node3D
## Cena principal do mundo procedural: gera os pedaços em volta do ponto de
## partida antes do primeiro quadro (o jogador nasce em chão com colisão) e
## põe o sobrevivente na rodovia. Os outros pedaços chegam em segundo plano.

@export var world: ProceduralWorld
@export var player: PlayerController
## Raio gerado na partida, antes de liberar o jogador.
@export_range(0, 3) var start_radius: int = 1


func _ready() -> void:
	var spawn := world.generator.spawn_point()
	world.generate_now(spawn, start_radius)
	player.teleport(spawn)
	# Olhando ao longo da rodovia, para o norte.
	player.set_view_rotation(0.0, -0.05)
	var death := player.get_node_or_null("Death") as PlayerDeath
	if death != null:
		death.spawn_transform = Transform3D(Basis.IDENTITY, spawn)
		# Renascer longe de onde morreu: o chão da partida pode ter sido
		# descarregado; é gerado na hora (antes do próximo passo da física).
		death.respawned.connect(func() -> void: world.generate_now(player.global_position, start_radius))


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
