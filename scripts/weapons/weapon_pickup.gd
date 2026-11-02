class_name WeaponPickup
extends Interactable
## Arma no chão: um corpo físico de verdade (cai, rola, soa ao bater) que o
## jogador pega com USAR. Quem pega é o PlayerEquipment do jogador; se ele já
## segurava outra arma, a outra cai no lugar desta.

@export var weapon: WeaponData


func _ready() -> void:
	if weapon != null:
		prompt = "Pegar " + weapon.display_name.to_lower()
	interacted.connect(_on_interacted)


func _on_interacted(by: Node) -> void:
	var equipment := by.get_node_or_null("Equipment") as PlayerEquipment
	if equipment == null or weapon == null:
		return
	var body := get_parent() as Node3D
	equipment.equip(weapon, body.global_transform if body != null else Transform3D.IDENTITY)
	if body != null:
		body.queue_free()


## Cria o corpo físico de uma arma solta no mundo.
static func spawn(data: WeaponData, where: Transform3D, parent: Node) -> RigidBody3D:
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
	body.add_child(pickup)
	parent.add_child(body)
	body.global_transform = where
	return body
