class_name WeaponPickup
extends Interactable
## Ferramenta no chão: um corpo físico de verdade (cai, rola, soa ao bater)
## que o jogador pega com PEGAR. Ela entra na mochila (barra rápida), com a
## durabilidade que tinha; com as mãos livres, já vai para a mão. O
## Interactable é desligado ao pegar: não dá para pegar duas vezes.

@export var weapon: WeaponData
## Durabilidade restante (< 0 = nova).
@export var durability: float = -1.0


func _ready() -> void:
	if weapon != null:
		prompt = "Pegar " + weapon.display_name.to_lower()
	interacted.connect(_on_interacted)


func _on_interacted(by: Node) -> void:
	var inventory := by.get_node_or_null("Inventory") as Inventory
	if inventory == null or weapon == null or not enabled:
		return
	if inventory.add(ItemData.find(weapon.id), 1, durability):
		enabled = false
		var body := get_parent() as Node3D
		if body != null:
			body.queue_free()


## Cria o corpo físico de uma arma solta no mundo.
static func spawn(data: WeaponData, where: Transform3D, parent: Node, wear: float = -1.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Arma_" + String(data.id)
	body.mass = data.mass
	body.collision_layer = 4
	body.collision_mask = 1 | 2 | 4
	var material := PhysicsMaterial.new()
	material.friction = 0.9
	material.bounce = 0.1
	body.physics_material_override = material
	var model := MeshInstance3D.new()
	model.name = "Model"
	model.mesh = data.mesh
	body.add_child(model)
	var shape := CollisionShape3D.new()
	shape.shape = data.mesh.create_convex_shape(true, true)
	body.add_child(shape)
	var sound := ImpactSound.new()
	sound.name = "ImpactSound"
	sound.material = data.impact_material
	body.add_child(sound)
	var pickup := WeaponPickup.new()
	pickup.name = "WeaponPickup"
	pickup.weapon = data
	pickup.durability = wear
	body.add_child(pickup)
	parent.add_child(body)
	body.global_transform = where
	return body

# Rede de segurança: o terreno é uma casca; se o corpo atravessar o chão
# (nasceu dentro de um morro, foi empurrado contra a parede), volta ao último
# lugar onde estava parado.
var _rest_position := Vector3.INF


func _physics_process(_delta: float) -> void:
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	if body.linear_velocity.length_squared() < 0.04:
		_rest_position = body.global_position
	elif _rest_position == Vector3.INF:
		_rest_position = body.global_position + Vector3.UP * 0.5
	if body.global_position.y < _rest_position.y - 25.0:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.global_position = _rest_position + Vector3.UP * 0.6
