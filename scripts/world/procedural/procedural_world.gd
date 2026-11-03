class_name ProceduralWorld
extends Node3D
## Mundo infinito carregado por pedaços (chunks) em volta do jogador.
##
## Cada pedaço de 32 × 32 m é gerado em segundo plano (WorkerThreadPool) pelo
## WorldGenerator: terreno com cavernas, árvores, vegetação, pedras, carcaças
## na estrada, destroços e armas. O resultado volta para a linha principal,
## que monta os nós com um limite por quadro (sem engasgos). Pedaços que
## ficam longe são descarregados; ao voltar, são gerados iguais (mesma
## semente), menos as armas que o jogador já pegou.

signal chunk_loaded(coord: Vector2i)

@export var world_seed: int = 20261102
## Nó seguido (o jogador). Sem alvo, o mundo fica em volta da origem.
@export var target: Node3D
## Raio de pedaços carregados em volta do alvo (4 = 9 × 9 pedaços, 144 m).
@export_range(1, 8) var view_distance: int = 4
## Tarefas de geração simultâneas em segundo plano.
@export_range(1, 8) var max_tasks: int = 3
## Pedaços montados por quadro (cada um cria malha, colisão e instâncias).
@export_range(1, 8) var applies_per_frame: int = 1

var generator: WorldGenerator

var _chunks: Dictionary = {} # Vector2i -> Node3D
var _tasks: Dictionary = {} # Vector2i -> id da tarefa
var _done: Array[Dictionary] = []
var _mutex := Mutex.new()
var _terrain_material: ShaderMaterial
var _tree_cards: Array[Mesh] = []
var _trunk_mesh: Mesh
var _meshes: Dictionary = {}
var _boxes: Dictionary = {} # nome -> AABB da malha (colisão)
var _weapons: Dictionary = {}
## Armas já pegas (não reaparecem): "x_z_i".
var _taken: Dictionary = {}
## Árvores cortadas e depósitos quebrados (não voltam ao recarregar o pedaço).
var _removed: Dictionary = {}
var _center := Vector2i(1 << 30, 0)
var _generation_usec: Array[int] = []


func _ready() -> void:
	generator = WorldGenerator.new(world_seed)
	# No celular, um anel a menos (a neblina já esconde a borda): ~40% menos
	# pedaços para desenhar e manter na memória.
	if OS.has_feature("mobile") and view_distance > 3:
		view_distance = 3
	_terrain_material = load("res://resources/materials/world_terrain.tres")
	for variant in 3:
		_tree_cards.append(TreeCards.card_mesh(variant))
	_trunk_mesh = TreeCards.trunk_mesh()
	for id in ["taco", "machado", "picareta"]:
		_weapons[id] = load("res://resources/weapons/%s.tres" % id)


func _exit_tree() -> void:
	for coord in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[coord])
	_tasks.clear()


# --- Consultas ---------------------------------------------------------------

static func chunk_of(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / WorldGenerator.CHUNK_SIZE), floori(position.z / WorldGenerator.CHUNK_SIZE))


func is_loaded(coord: Vector2i) -> bool:
	return _chunks.has(coord)


## Todos os pedaços até `radius` em volta da posição já estão montados?
func is_ready_around(position: Vector3, radius: int = 1) -> bool:
	var center := chunk_of(position)
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if not _chunks.has(center + Vector2i(dx, dz)):
				return false
	return true


func loaded_chunks() -> Array:
	return _chunks.keys()


func chunk_node(coord: Vector2i) -> Node3D:
	return _chunks.get(coord)


func mark_removed(key: String) -> void:
	_removed[key] = true


func is_removed(key: String) -> bool:
	return _removed.has(key)


## Árvores e depósitos coletáveis do pedaço (ChunkResources) ou null.
func resources_of(coord: Vector2i) -> ChunkResources:
	var chunk := chunk_node(coord)
	return chunk.get_node_or_null("Recursos") as ChunkResources if chunk != null else null


## Tempo médio de geração de um pedaço em segundo plano (ms).
func average_generation_ms() -> float:
	if _generation_usec.is_empty():
		return 0.0
	var total := 0
	for usec in _generation_usec:
		total += usec
	return total / 1000.0 / _generation_usec.size()


# --- Ciclo ---------------------------------------------------------------------

func _process(_delta: float) -> void:
	var focus := target.global_position if target != null and is_instance_valid(target) else Vector3.ZERO
	var center := chunk_of(focus)
	if center != _center:
		_center = center
		_unload_far(center)
	_start_tasks(center)
	_apply_results(center)


func _wanted(center: Vector2i) -> Array[Vector2i]:
	var list: Array[Vector2i] = []
	for dz in range(-view_distance, view_distance + 1):
		for dx in range(-view_distance, view_distance + 1):
			if dx * dx + dz * dz <= (view_distance + 0.5) * (view_distance + 0.5):
				list.append(center + Vector2i(dx, dz))
	list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared())
	return list


func _start_tasks(center: Vector2i) -> void:
	# Tarefas terminadas: libera o registro no pool.
	for coord in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[coord]):
			WorkerThreadPool.wait_for_task_completion(_tasks[coord])
			_tasks.erase(coord)
	if _tasks.size() >= max_tasks:
		return
	for coord in _wanted(center):
		if _chunks.has(coord) or _tasks.has(coord) or _is_done(coord):
			continue
		var seed_value := world_seed
		_tasks[coord] = WorkerThreadPool.add_task(_generate.bind(coord, seed_value), false, "Pedaço %s" % coord)
		if _tasks.size() >= max_tasks:
			return


## Roda em segundo plano: só dados, nenhum nó.
func _generate(coord: Vector2i, seed_value: int) -> void:
	var data := WorldGenerator.new(seed_value).build_chunk(coord)
	data["faces"] = _faces(data["mesh"])
	_mutex.lock()
	_done.append(data)
	_mutex.unlock()


static func _faces(mesh: Dictionary) -> PackedVector3Array:
	var vertices: PackedVector3Array = mesh["vertices"]
	var indices: PackedInt32Array = mesh["indices"]
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in indices.size():
		faces[i] = vertices[indices[i]]
	return faces


func _is_done(coord: Vector2i) -> bool:
	_mutex.lock()
	var found := false
	for data in _done:
		if data["coord"] == coord:
			found = true
			break
	_mutex.unlock()
	return found


func _apply_results(center: Vector2i) -> void:
	_mutex.lock()
	# Mais perto primeiro.
	_done.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["coord"] - center).length_squared() < (b["coord"] - center).length_squared())
	var batch: Array[Dictionary] = []
	while not _done.is_empty() and batch.size() < applies_per_frame:
		batch.append(_done.pop_front())
	_mutex.unlock()
	var limit := (view_distance + 1) * (view_distance + 1)
	for data in batch:
		var coord: Vector2i = data["coord"]
		if _chunks.has(coord) or (coord - center).length_squared() > limit * 2:
			continue
		_generation_usec.append(data["usec"])
		if _generation_usec.size() > 64:
			_generation_usec.pop_front()
		_chunks[coord] = _build_chunk_node(data)
		chunk_loaded.emit(coord)


func _unload_far(center: Vector2i) -> void:
	var limit := float(view_distance) + 1.5
	for coord in _chunks.keys():
		if Vector2(coord - center).length() > limit:
			(_chunks[coord] as Node3D).queue_free()
			_chunks.erase(coord)


## Gera de uma vez (na linha principal) os pedaços em volta de uma posição.
## Para a partida e para testes; o jogo normal usa as tarefas em segundo plano.
func generate_now(position: Vector3, radius: int = 1) -> void:
	var center := chunk_of(position)
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var coord := center + Vector2i(dx, dz)
			if _chunks.has(coord) or _tasks.has(coord):
				continue
			var data := generator.build_chunk(coord)
			data["faces"] = _faces(data["mesh"])
			_chunks[coord] = _build_chunk_node(data)
			chunk_loaded.emit(coord)


# --- Montagem do pedaço --------------------------------------------------------

func _build_chunk_node(data: Dictionary) -> Node3D:
	var coord: Vector2i = data["coord"]
	var chunk := Node3D.new()
	chunk.name = "Pedaco_%d_%d" % [coord.x, coord.y]
	add_child(chunk)
	var mesh_data: Dictionary = data["mesh"]
	if not (mesh_data["indices"] as PackedInt32Array).is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = mesh_data["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = mesh_data["normals"]
		arrays[Mesh.ARRAY_COLOR] = mesh_data["colors"]
		arrays[Mesh.ARRAY_TEX_UV] = mesh_data["uvs"]
		arrays[Mesh.ARRAY_TEX_UV2] = mesh_data["uv2s"]
		arrays[Mesh.ARRAY_INDEX] = mesh_data["indices"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _terrain_material)
		var terrain := MeshInstance3D.new()
		terrain.name = "Terreno"
		terrain.mesh = mesh
		chunk.add_child(terrain)
		var body := StaticBody3D.new()
		body.name = "Chao"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(data["faces"])
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		chunk.add_child(body)
	var solids := StaticBody3D.new()
	solids.name = "Obstaculos"
	solids.collision_layer = 1
	solids.collision_mask = 0
	chunk.add_child(solids)
	# Árvores e depósitos coletáveis (cada um com colisão e resistência
	# próprias, em ChunkResources). Os já colhidos não voltam (fica o toco).
	var resources := ChunkResources.new()
	resources.name = "Recursos"
	resources.collision_layer = 1
	resources.collision_mask = 0
	resources.world = self
	resources.coord = coord
	chunk.add_child(resources)
	var cards: Array = [[], [], []]
	var trunks: Array = []
	var standing: Array = [] # [chave, dados da árvore, índice na copa, índice no tronco]
	var tree_list: Array = data.get("tree_list", [])
	for i in tree_list.size():
		var tree: Array = tree_list[i]
		var key := "a_%d_%d_%d" % [coord.x, coord.y, i]
		if is_removed(key):
			resources._stump((tree[2] as Transform3D).origin, tree[1])
			continue
		standing.append([key, tree, (cards[tree[0]] as Array).size(), trunks.size()])
		(cards[tree[0]] as Array).append(tree[2])
		trunks.append(tree[3])
	var card_scatters: Array = []
	for variant in 3:
		card_scatters.append(_scatter(chunk, "Arvores%d" % variant, _tree_cards[variant], cards[variant], 170.0, true))
	var trunk_scatter := _scatter(chunk, "Troncos", _trunk_mesh, trunks, 70.0, true)
	for entry in standing:
		var tree: Array = entry[1]
		var base: Transform3D = tree[2]
		resources.add_tree(entry[0], tree[0], tree[1], tree[4], Transform3D(Basis.IDENTITY, base.origin), 0.16 * tree[1],
				[[card_scatters[tree[0]], entry[2]], [trunk_scatter, entry[3]]])
	var deposits: Array = data.get("deposits", [])
	var deposit_lists := {}
	var deposit_entries: Array = []
	for i in deposits.size():
		var deposit: Array = deposits[i]
		var key := "d_%d_%d_%d" % [coord.x, coord.y, i]
		if is_removed(key):
			continue
		var mesh_kind: String = deposit[2]
		if not deposit_lists.has(mesh_kind):
			deposit_lists[mesh_kind] = []
		deposit_entries.append([key, deposit, mesh_kind, (deposit_lists[mesh_kind] as Array).size()])
		(deposit_lists[mesh_kind] as Array).append(deposit[1])
	var deposit_scatters := {}
	for mesh_kind in deposit_lists:
		deposit_scatters[mesh_kind] = _scatter(chunk, "Deposito_" + mesh_kind, _mesh(mesh_kind), deposit_lists[mesh_kind], 90.0, true)
	for entry in deposit_entries:
		var deposit: Array = entry[1]
		resources.add_deposit(entry[0], StringName(deposit[0]), deposit[1], _boxes[entry[2]],
				[[deposit_scatters[entry[2]], entry[3]]])
	# Objetos espalhados (uma instância múltipla por tipo).
	var props: Dictionary = data["props"]
	for kind in props:
		var small: bool = kind in ["can_rusted", "plastic_jerrycan", "rusted_wheel_rim_01", "trashbag", "fern_02", "shrub_03", "dry_branches_medium_01"]
		_scatter(chunk, kind, _mesh(kind), props[kind], 45.0 if small else 110.0, not small)
	for entry in data["colliders"]:
		_box_collider(solids, entry[0], entry[1])
	# Carcaças: agrupadas por modelo, com a cor de cada uma.
	var by_kind := {}
	for entry in data["wrecks"]:
		if not by_kind.has(entry[0]):
			by_kind[entry[0]] = [[], []]
		(by_kind[entry[0]][0] as Array).append(entry[1])
		(by_kind[entry[0]][1] as Array).append(entry[2])
		_box_collider(solids, entry[0], entry[1])
	for kind in by_kind:
		# (PackedColorArray é cópia por valor: monta no fim, de uma vez.)
		_scatter(chunk, "Carcacas_" + kind, _mesh(kind), by_kind[kind][0], 160.0, true, PackedColorArray(by_kind[kind][1]))
	# Zumbis (os mortos não voltam).
	var zombies: Array = data.get("zombies", [])
	for i in zombies.size():
		var key := "z_%d_%d_%d" % [coord.x, coord.y, i]
		if is_removed(key):
			continue
		var zombie := Zombie.new()
		zombie.name = "Zumbi%d" % i
		zombie.target = target
		chunk.add_child(zombie)
		zombie.global_position = zombies[i]
		zombie.rotation.y = hash(key) % 628 / 100.0
		zombie.died.connect(func() -> void: mark_removed(key))
	# Armas largadas (corpos físicos de verdade).
	var weapons: Array = data["weapons"]
	for i in weapons.size():
		var key := "%d_%d_%d" % [coord.x, coord.y, i]
		if _taken.has(key):
			continue
		var body := WeaponPickup.spawn(_weapons[weapons[i][0]], weapons[i][1], chunk)
		var pickup: WeaponPickup = body.get_node("WeaponPickup")
		pickup.interacted.connect(func(_by: Node) -> void: _taken[key] = true)
	return chunk


func _scatter(parent: Node3D, node_name: String, mesh: Mesh, list: Array, distance: float, shadows: bool,
		custom := PackedColorArray()) -> ScatterInstances:
	var scatter := ScatterInstances.new()
	scatter.custom_data = custom
	scatter.name = node_name
	scatter.mesh = mesh
	scatter.max_distance = distance
	scatter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var typed: Array[Transform3D] = []
	typed.assign(list)
	scatter.transforms = typed
	if not typed.is_empty():
		parent.add_child(scatter)
	return scatter


func _mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		var mesh: Mesh = load("res://resources/models/world/%s.res" % kind)
		_meshes[kind] = mesh
		_boxes[kind] = mesh.get_aabb()
	return _meshes[kind]


## Caixa de colisão do objeto (a caixa da malha, um pouco menor). Formações
## pontudas usam um cilindro fino no tronco.
func _box_collider(body: StaticBody3D, kind: String, t: Transform3D) -> void:
	_mesh(kind)
	var box: AABB = _boxes[kind]
	if kind == "estalagmite":
		var scale := t.basis.get_scale()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = box.size.x * scale.x * 0.28
		cylinder.height = box.size.y * scale.y * 0.7
		var spire := CollisionShape3D.new()
		spire.shape = cylinder
		spire.transform = Transform3D(Basis.IDENTITY, t.origin + Vector3.UP * cylinder.height * 0.5)
		body.add_child(spire)
		return
	# A física não aceita forma escalada: a escala vai para o tamanho da caixa.
	var scale := t.basis.get_scale()
	var shape := BoxShape3D.new()
	shape.size = box.size * scale * 0.9
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = Transform3D(t.basis.orthonormalized(), t * box.get_center())
	body.add_child(collision)
