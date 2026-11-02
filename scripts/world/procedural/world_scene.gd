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
