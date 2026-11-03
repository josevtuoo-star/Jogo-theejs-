class_name ChunkResources
extends StaticBody3D
## Árvores e depósitos de minério de um pedaço do mundo, que se coletam com a
## ferramenta certa (inspirado no Minecraft, com física e animação realistas).
##
## Cada árvore e cada depósito é uma forma de colisão deste corpo, com
## resistência própria (pelo tipo e pelo tamanho). O golpe do jogador chega
## por receive_hit (MeleeCombat): com a ferramenta certa (machado na árvore,
## picareta no minério) tira resistência, solta lascas ou pó de pedra, soa e a
## árvore balança; com a errada, o golpe é rebatido e um aviso diz qual usar.
## Esgotada, a árvore tomba de verdade (corpo rígido), deixa um toco e se
## parte em toras; o depósito some e solta pedra, carvão ou ferro. Tudo o que
## cai é coletável (PEGAR) e o que foi colhido não volta ao recarregar.

signal depleted(entry: Dictionary)

const TREE_TOOL := &"machado"
const ROCK_TOOL := &"picareta"
## Resistência por tipo (multiplicada pelo tamanho).
const DEPOSIT_HEALTH := {&"pedra": 70.0, &"carvao": 90.0, &"ferro": 130.0}
const TREE_HEALTH := [78.0, 60.0, 44.0]

var world: ProceduralWorld
var coord: Vector2i
## Forma de colisão -> dados do recurso.
var _entries: Dictionary = {}
var _hint_time: float = -100.0


## Registra uma árvore. `instances` = [[ScatterInstances, índice], ...] (copa e
## tronco), escondidas quando ela cai.
func add_tree(key: String, variant: int, scale: float, height: float, base: Transform3D, radius: float,
		instances: Array) -> void:
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 4.0
	var shape := CollisionShape3D.new()
	shape.shape = cylinder
	shape.position = base.origin + Vector3.UP * 2.0
	add_child(shape)
	var health: float = TREE_HEALTH[variant] * scale * scale
	_entries[shape] = {"kind": &"arvore", "key": key, "variant": variant, "scale": scale, "height": height,
			"base": base, "health": health, "max": health, "tool": TREE_TOOL, "instances": instances,
			"shape": shape, "material": &"madeira"}


## Registra um depósito (pedra, carvão, ferro).
func add_deposit(key: String, type: StringName, t: Transform3D, box: AABB, instances: Array) -> void:
	var scale := t.basis.get_scale()
	var boxshape := BoxShape3D.new()
	boxshape.size = box.size * scale * 0.85
	var shape := CollisionShape3D.new()
	shape.shape = boxshape
	shape.transform = Transform3D(t.basis.orthonormalized(), t * box.get_center())
	add_child(shape)
	var health: float = DEPOSIT_HEALTH.get(type, 80.0) * clampf(scale.x, 0.6, 1.6)
	_entries[shape] = {"kind": &"deposito", "key": key, "type": type, "transform": t, "health": health,
			"max": health, "tool": ROCK_TOOL, "instances": instances, "shape": shape, "material": type}


## Recurso atingido por um golpe (pelo índice da forma) ou {}.
func entry_for_shape(shape_index: int) -> Dictionary:
	if shape_index < 0:
		return {}
	var owner_id := shape_find_owner(shape_index)
	var node: Object = shape_owner_get_owner(owner_id)
	return _entries.get(node, {})


func entries() -> Array:
	return _entries.values()


## Golpe do jogador. Retorna falso se o golpe não serve (ferramenta errada,
## sem ferramenta): o combate trata como superfície rígida (rebate).
func receive_hit(hit: Dictionary) -> bool:
	var entry := entry_for_shape(hit.get("shape", -1))
	if entry.is_empty() or entry["health"] <= 0.0:
		return false
	var point: Vector3 = hit.get("point", global_position)
	var direction: Vector3 = hit.get("direction", Vector3.FORWARD)
	if hit.get("weapon", &"") != entry["tool"]:
		ImpactEffects.sound(self, point, "combat/impacto_madeira" if entry["kind"] == &"arvore" else "world/pedra_golpe", -8.0)
		_hint(hit.get("attacker"), entry)
		return false
	entry["health"] = float(entry["health"]) - float(hit.get("damage", 0.0))
	if entry["kind"] == &"arvore":
		ImpactEffects.burst(self, point, -direction, &"madeira", 12, 0.035, 3.0)
		ImpactEffects.sound(self, point, "combat/impacto_madeira", 0.0, 0.9)
		_wobble(entry, direction)
	else:
		ImpactEffects.burst(self, point, -direction, entry["type"], 16, 0.05, 3.5)
		ImpactEffects.burst(self, point, -direction, &"pedra", 8, 0.03, 2.0)
		ImpactEffects.sound(self, point, "world/pedra_golpe", 0.0)
	if entry["health"] <= 0.0:
		if entry["kind"] == &"arvore":
			_fell_tree(entry, direction)
		else:
			_break_deposit(entry, point)
	return true


func _hint(attacker: Variant, entry: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _hint_time < 4.0 or not (attacker is Node):
		return
	_hint_time = now
	var inventory := (attacker as Node).get_node_or_null("Inventory") as Inventory
	if inventory != null:
		inventory.message.emit("Precisa de um machado para cortar árvores" if entry["kind"] == &"arvore"
				else "Precisa de uma picareta para quebrar rocha")


## A árvore balança com o golpe (a copa e o tronco giram de leve e voltam).
func _wobble(entry: Dictionary, direction: Vector3) -> void:
	var base: Transform3D = entry["base"]
	var axis := Vector3.UP.cross(Vector3(direction.x, 0.0, direction.z)).normalized()
	if axis.length_squared() < 0.5:
		return
	var tween := create_tween()
	var steps := [0.035, -0.02, 0.01, 0.0]
	var previous := 0.0
	for angle: float in steps:
		tween.tween_method(func(a: float) -> void: _set_tilt(entry, axis, a), previous, angle, 0.09)
		previous = angle


func _set_tilt(entry: Dictionary, axis: Vector3, angle: float) -> void:
	if entry["health"] <= 0.0:
		return
	var base: Transform3D = entry["base"]
	for pair in entry["instances"]:
		var scatter: ScatterInstances = pair[0]
		var original: Transform3D = scatter.transforms[pair[1]]
		var t := Transform3D(Basis.IDENTITY, base.origin) * Transform3D(Basis(axis, angle), Vector3.ZERO) \
				* Transform3D(Basis.IDENTITY, -base.origin) * original
		scatter.multimesh.set_instance_transform(pair[1], t)


func _hide(entry: Dictionary) -> void:
	for pair in entry["instances"]:
		var scatter: ScatterInstances = pair[0]
		var original: Transform3D = scatter.transforms[pair[1]]
		scatter.multimesh.set_instance_transform(pair[1], Transform3D(Basis().scaled(Vector3.ONE * 0.0001), original.origin))
	(entry["shape"] as CollisionShape3D).disabled = true


# --- Árvore caindo -------------------------------------------------------------

func _fell_tree(entry: Dictionary, direction: Vector3) -> void:
	_hide(entry)
	if world != null:
		world.mark_removed(entry["key"])
	var base: Transform3D = entry["base"]
	var scale: float = entry["scale"]
	var height: float = entry["height"]
	ImpactEffects.sound(self, base.origin + Vector3.UP * 2.0, "world/arvore_racha", 2.0)
	# Toco no lugar (fica).
	_stump(base.origin, scale)
	# O tronco cai: corpo rígido com a copa e o tronco, empurrado no alto para
	# o lado oposto ao golpe; tomba girando sobre a base.
	var tree := RigidBody3D.new()
	tree.name = "ArvoreCaindo"
	tree.mass = 120.0 * scale * scale
	tree.collision_layer = 4
	tree.collision_mask = 1 | 4
	tree.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	tree.center_of_mass = Vector3(0.0, height * 0.35, 0.0)
	for pair in entry["instances"]:
		var scatter: ScatterInstances = pair[0]
		var model := MeshInstance3D.new()
		model.mesh = scatter.mesh
		model.transform = Transform3D(Basis.IDENTITY, -base.origin) * scatter.transforms[pair[1]]
		tree.add_child(model)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25 * scale
	capsule.height = height * 0.85
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position = Vector3(0.0, height * 0.45 + 0.5, 0.0)
	tree.add_child(shape)
	get_parent().add_child(tree)
	tree.global_position = base.origin + Vector3.UP * 0.6
	var push := Vector3(direction.x, 0.0, direction.z).normalized()
	tree.apply_impulse(push * tree.mass * 1.6, Vector3(0.0, height * 0.8, 0.0))
	var wood := clampi(roundi(2.0 + height / 3.0), 3, 7)
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if is_instance_valid(tree):
			_split_logs(tree, height, wood))
	depleted.emit(entry)


## O tronco caído vira toras soltas ao longo dele (cada uma é madeira).
func _split_logs(tree: RigidBody3D, height: float, count: int) -> void:
	var item := ItemData.find(&"madeira")
	var along := tree.global_basis.y.normalized()
	var start := tree.global_transform * Vector3(0.0, 0.6, 0.0)
	ImpactEffects.sound(self, start + along * height * 0.4, "props/madeira_cai", -2.0)
	for i in count:
		var spot := start + along * (1.0 + i * (height * 0.7) / count) + Vector3.UP * 0.35
		var t := Transform3D(Basis(Vector3.UP, atan2(along.x, along.z) + PI * 0.5), spot)
		ItemPickup.spawn(item, t, get_parent())
	ImpactEffects.burst(get_parent(), start + along * height * 0.4, Vector3.UP, &"casca", 20, 0.05, 2.5)
	tree.queue_free()


func _stump(at: Vector3, scale: float) -> void:
	var stump := MeshInstance3D.new()
	stump.name = "Toco"
	stump.mesh = load("res://resources/models/world/tree_stump_01.res")
	add_child(stump)
	stump.global_transform = Transform3D(Basis().scaled(Vector3.ONE * scale * 0.32), at - Vector3.UP * 0.05)


# --- Depósito quebrando --------------------------------------------------------

## Rendimento de cada tipo: [item, mínimo, máximo] (a pedra em volta também).
const DEPOSIT_YIELD := {
	&"pedra": [[&"pedra", 3, 4]],
	&"carvao": [[&"carvao", 2, 3], [&"pedra", 1, 1]],
	&"ferro": [[&"ferro", 2, 3], [&"pedra", 1, 1]],
}


func _break_deposit(entry: Dictionary, point: Vector3) -> void:
	_hide(entry)
	if world != null:
		world.mark_removed(entry["key"])
	var t: Transform3D = entry["transform"]
	var center := t.origin + Vector3.UP * 0.4
	ImpactEffects.sound(self, center, "world/pedra_quebra", 2.0)
	ImpactEffects.burst(self, center, Vector3.UP, entry["type"], 26, 0.07, 3.5)
	ImpactEffects.burst(self, center, Vector3.UP, &"pedra", 18, 0.05, 2.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(entry["key"])
	for spec in DEPOSIT_YIELD.get(entry["type"], []):
		var item := ItemData.find(spec[0])
		for i in rng.randi_range(spec[1], spec[2]):
			var spot := center + Vector3(rng.randf_range(-0.5, 0.5), 0.3 + i * 0.12, rng.randf_range(-0.5, 0.5))
			ItemPickup.spawn(item, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), spot), get_parent())
	ImpactEffects.sound(self, center, "world/pedra_cai", -4.0)
	depleted.emit(entry)
