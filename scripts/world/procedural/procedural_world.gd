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
## Usa a semente do mundo aberto no menu (GameSession), se houver.
@export var use_session_seed: bool = false
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
var _hulls: Dictionary = {} # nome -> pontos do casco convexo (rochedos)
var _building_material: Material
var _weapons: Dictionary = {}
## Armas já pegas (não reaparecem): "x_z_i".
var _taken: Dictionary = {}
## Árvores cortadas e depósitos quebrados (não voltam ao recarregar o pedaço).
var _removed: Dictionary = {}
var _center := Vector2i(1 << 30, 0)
var _generation_usec: Array[int] = []


func _ready() -> void:
	# Mundo aberto pelo menu: a semente é a dele.
	if use_session_seed and GameSession.active:
		world_seed = GameSession.world_seed
	generator = WorldGenerator.new(world_seed)
	# No celular, um anel a menos (a neblina já esconde a borda): ~40% menos
	# pedaços para desenhar e manter na memória.
	if use_session_seed:
		# Mundo do jogo: distância de visão das configurações.
		view_distance = clampi(int(GameSession.settings.get("distancia", 3)), 2, 6)
		GameSession.settings_changed.connect(func() -> void:
			view_distance = clampi(int(GameSession.settings.get("distancia", 3)), 2, 6)
			_center = Vector2i(1 << 30, 0))
	elif OS.has_feature("mobile") and view_distance > 3:
		view_distance = 3
	_terrain_material = load("res://resources/materials/world_terrain.tres")
	_building_material = load("res://resources/materials/building.tres")
	for variant in 3:
		_tree_cards.append(TreeCards.card_mesh(variant))
	# Variantes 3–5: folhosa, árvore seca e árvore-aljava (outros biomas).
	for row in 3:
		_tree_cards.append(TreeCards.broadleaf_mesh(row))
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


# --- Escavação (etapa 10: o terreno também quebra) ---------------------------------

## A malha do terreno tem 2 m de resolução: o buraco precisa alcançar uma
## amostra (um "bloco" de ~3 m de largura).
const DIG_RADIUS := 1.6
## Dano acumulado num ponto até abrir o buraco.
const DIG_HEALTH := 34.0

## Pedaço -> escavações que o alcançam (Vector4: centro e raio).
var _digs: Dictionary = {}
## Todas as escavações, sem repetir (para salvar).
var _dig_list: Array[Vector4] = []
var _dig_damage: Dictionary = {}
var _dirty: Dictionary = {}


func digs_of(coord: Vector2i) -> Array[Vector4]:
	var list: Array[Vector4] = []
	list.assign(_digs.get(coord, []))
	return list


func dig_list() -> Array:
	var out := []
	for dig in _dig_list:
		out.append([dig.x, dig.y, dig.z, dig.w])
	return out


func load_digs(list: Array) -> void:
	for entry: Array in list:
		if entry.size() == 4:
			add_dig(Vector4(entry[0], entry[1], entry[2], entry[3]), false)


## Golpe no terreno: acumula até ceder e abrir um buraco do tamanho de um
## bloco. Retorna se o golpe valeu (fundo do mundo não cava).
func dig_hit(point: Vector3, normal: Vector3, damage: float) -> bool:
	if point.y < WorldGenerator.FLOOR_Y + 3.0 or damage <= 0.0:
		return false
	var cell := Vector3i(floori(point.x / 0.7), floori(point.y / 0.7), floori(point.z / 0.7))
	var total := float(_dig_damage.get(cell, 0.0)) + damage
	var depth := generator.surface_height(point.x, point.z) - point.y
	var rock := depth > 1.5 or normal.y < 0.5
	ImpactEffects.burst(self, point, normal, &"pedra" if rock else &"casca", 12, 0.04, 2.5)
	ImpactEffects.sound(self, point, "world/pedra_golpe" if rock else "combat/impacto_generico", -3.0)
	if total < DIG_HEALTH:
		_dig_damage[cell] = total
		return true
	_dig_damage.erase(cell)
	var center := point - normal.normalized() * 0.35
	add_dig(Vector4(center.x, center.y, center.z, DIG_RADIUS), true)
	ImpactEffects.burst(self, point, normal, &"pedra" if rock else &"casca", 26, 0.06, 3.0)
	var chunk := chunk_node(chunk_of(point))
	if rock and chunk != null and randf() < 0.6:
		ItemPickup.spawn(ItemData.find(&"pedra"), Transform3D(Basis.IDENTITY, point + normal * 0.4), chunk)
	return true


func add_dig(dig: Vector4, rebuild: bool) -> void:
	_dig_list.append(dig)
	var reach := dig.w + WorldGenerator.CELL * 1.5
	var a := chunk_of(Vector3(dig.x - reach, 0.0, dig.z - reach))
	var b := chunk_of(Vector3(dig.x + reach, 0.0, dig.z + reach))
	for cz in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			var coord := Vector2i(cx, cz)
			if not _digs.has(coord):
				_digs[coord] = []
			(_digs[coord] as Array).append(dig)
			if rebuild and _chunks.has(coord):
				_rebuild(coord)


## Refaz o pedaço com as escavações (em segundo plano); troca quando pronto.
func _rebuild(coord: Vector2i) -> void:
	if _tasks.has(coord):
		_dirty[coord] = true
		return
	_tasks[coord] = WorkerThreadPool.add_task(_generate.bind(coord, world_seed, digs_of(coord), true), false, "Escavação %s" % coord)


func _swap_chunk(coord: Vector2i, data: Dictionary) -> void:
	var old: Node3D = _chunks[coord]
	var fresh := _build_chunk_node(data)
	# O que está solto no pedaço (itens, ferramentas, árvores caindo, zumbis)
	# continua onde está.
	for child in old.get_children():
		if child is RigidBody3D or child is CharacterBody3D:
			child.reparent(fresh)
	old.queue_free()
	_chunks[coord] = fresh
	if _dirty.has(coord):
		_dirty.erase(coord)
		_rebuild(coord)


func mark_removed(key: String) -> void:
	_removed[key] = true


## Arma largada no mundo que o jogador já pegou (não reaparece).
func mark_taken(key: String) -> void:
	_taken[key] = true


func removed_keys() -> Array:
	return _removed.keys()


func taken_keys() -> Array:
	return _taken.keys()


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
		_tasks[coord] = WorkerThreadPool.add_task(_generate.bind(coord, seed_value, digs_of(coord)), false, "Pedaço %s" % coord)
		if _tasks.size() >= max_tasks:
			return


## Roda em segundo plano: só dados, nenhum nó.
func _generate(coord: Vector2i, seed_value: int, chunk_digs: Array[Vector4] = [], rebuild: bool = false) -> void:
	var generator_copy := WorldGenerator.new(seed_value)
	generator_copy.digs = chunk_digs
	var data := generator_copy.build_chunk(coord)
	data["rebuild"] = rebuild
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
		if data.get("rebuild", false) and _chunks.has(coord):
			_swap_chunk(coord, data)
			continue
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
			generator.digs = digs_of(coord)
			var data := generator.build_chunk(coord)
			generator.digs = []
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
		var flags := 0
		if mesh_data.has("customs"):
			# Pesos dos biomas (CUSTOM0 no shader do terreno).
			arrays[Mesh.ARRAY_CUSTOM0] = mesh_data["customs"]
			flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		mesh.surface_set_material(0, _terrain_material)
		var terrain := MeshInstance3D.new()
		terrain.name = "Terreno"
		terrain.mesh = mesh
		chunk.add_child(terrain)
		var body := StaticBody3D.new()
		body.name = "Chao"
		body.collision_layer = 1
		body.collision_mask = 0
		# O combate reconhece o terreno (cavar com a picareta).
		body.set_meta(&"world", self)
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
	var cards: Array = [[], [], [], [], [], []]
	var trunks: Array = []
	var standing: Array = [] # [chave, dados da árvore, índice na copa, índice no tronco]
	var tree_list: Array = data.get("tree_list", [])
	for i in tree_list.size():
		var tree: Array = tree_list[i]
		var key := "a_%d_%d_%d" % [coord.x, coord.y, i]
		if is_removed(key):
			resources._stump((tree[2] as Transform3D).origin, tree[1])
			continue
		# Só os abetos têm tronco à parte (as outras árvores já o trazem no quadro).
		var has_trunk: bool = tree[3] != null
		standing.append([key, tree, (cards[tree[0]] as Array).size(), trunks.size() if has_trunk else -1])
		(cards[tree[0]] as Array).append(tree[2])
		if has_trunk:
			trunks.append(tree[3])
	var card_scatters: Array = []
	for variant in cards.size():
		card_scatters.append(_scatter(chunk, "Arvores%d" % variant, _tree_cards[variant], cards[variant], 170.0, true))
	var trunk_scatter := _scatter(chunk, "Troncos", _trunk_mesh, trunks, 70.0, true)
	for entry in standing:
		var tree: Array = entry[1]
		var base: Transform3D = tree[2]
		var parts := [[card_scatters[tree[0]], entry[2]]]
		if entry[3] >= 0:
			parts.append([trunk_scatter, entry[3]])
		var radius: float = tree[5] if tree.size() > 5 else 0.16 * tree[1]
		resources.add_tree(entry[0], tree[0], tree[1], tree[4], Transform3D(Basis.IDENTITY, base.origin), radius, parts)
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
	# Objetos espalhados (uma instância múltipla por tipo). Tudo o que tem
	# regra em ChunkResources.PROP_RULES quebra (rocha, madeira, metal, mato);
	# o mato só recebe golpes (camada de alvos), não trava o caminho.
	var soft := ChunkResources.new()
	soft.name = "Mato"
	soft.collision_layer = 32
	soft.collision_mask = 0
	soft.world = self
	soft.coord = coord
	chunk.add_child(soft)
	var solid_props := {}
	for entry in data["colliders"]:
		var marker := _prop_marker(entry[0], entry[1])
		solid_props[marker] = int(solid_props.get(marker, 0)) + 1
	var props: Dictionary = data["props"]
	for kind: String in props:
		var small: bool = kind in ["can_rusted", "plastic_jerrycan", "rusted_wheel_rim_01", "trashbag", "fern_02", "shrub_03",
				"dry_branches_medium_01", "shrub_02", "shrub_04", "weed_plant_02"]
		var list: Array = props[kind]
		var shown: Array = []
		var kept: Array = [] # [chave, transformação]
		for i in list.size():
			var key := "p_%d_%d_%s_%d" % [coord.x, coord.y, kind, i]
			var t: Transform3D = list[i]
			if is_removed(key):
				# Quebrado antes: não volta (nem a colisão).
				var gone := _prop_marker(kind, t)
				if solid_props.has(gone):
					solid_props[gone] = int(solid_props[gone]) - 1
				continue
			shown.append(t)
			kept.append([key, t])
		var scatter := _scatter(chunk, kind, _mesh(kind), shown, 45.0 if small else 110.0, not small)
		var breakable := not ChunkResources.prop_rule(kind).is_empty()
		for j in kept.size():
			var t: Transform3D = kept[j][1]
			var marker := _prop_marker(kind, t)
			var solid := int(solid_props.get(marker, 0)) > 0
			if solid:
				solid_props[marker] = int(solid_props[marker]) - 1
			if not breakable:
				if solid:
					_box_collider(solids, kind, t)
				continue
			if solid:
				resources.add_prop(kept[j][0], kind, t, _box_collider(resources, kind, t), [[scatter, j]])
			else:
				soft.add_prop(kept[j][0], kind, t, _soft_shape(soft, kind, t), [[scatter, j]])
	# Colisões sem objeto visível correspondente (segurança).
	for entry in data["colliders"]:
		var marker := _prop_marker(entry[0], entry[1])
		if int(solid_props.get(marker, 0)) > 0:
			solid_props[marker] = int(solid_props[marker]) - 1
			_box_collider(solids, entry[0], entry[1])
	# Prédios e casas das vilas e cidades: uma malha por pedaço e uma caixa
	# de colisão por prédio (do chão afundado até o teto).
	var building_mesh: Dictionary = data.get("building_mesh", {})
	if not building_mesh.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = building_mesh["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = building_mesh["normals"]
		arrays[Mesh.ARRAY_TEX_UV] = building_mesh["uvs"]
		arrays[Mesh.ARRAY_COLOR] = building_mesh["colors"]
		arrays[Mesh.ARRAY_INDEX] = building_mesh["indices"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _building_material)
		var buildings := MeshInstance3D.new()
		buildings.name = "Predios"
		buildings.mesh = mesh
		buildings.visibility_range_end = 260.0
		chunk.add_child(buildings)
		# Uma caixa por pedaço de parede, piso, teto e rampa da escada (dá
		# para entrar pelas portas e subir a escada).
		for entry: Array in building_mesh.get("boxes", []):
			var box := BoxShape3D.new()
			box.size = entry[1]
			var shape := CollisionShape3D.new()
			shape.shape = box
			shape.transform = entry[0]
			solids.add_child(shape)
	# Carcaças: agrupadas por modelo, com a cor de cada uma.
	var by_kind := {}
	var wrecks: Array = data["wrecks"]
	var wreck_entries: Array = [] # [chave, tipo, transformação, índice na instância]
	for i in wrecks.size():
		var entry: Array = wrecks[i]
		var key := "c_%d_%d_%d" % [coord.x, coord.y, i]
		if is_removed(key):
			continue
		if not by_kind.has(entry[0]):
			by_kind[entry[0]] = [[], []]
		wreck_entries.append([key, entry[0], entry[1], (by_kind[entry[0]][0] as Array).size()])
		(by_kind[entry[0]][0] as Array).append(entry[1])
		(by_kind[entry[0]][1] as Array).append(entry[2])
	var wreck_scatters := {}
	for kind in by_kind:
		# (PackedColorArray é cópia por valor: monta no fim, de uma vez.)
		wreck_scatters[kind] = _scatter(chunk, "Carcacas_" + kind, _mesh(kind), by_kind[kind][0], 160.0, true, PackedColorArray(by_kind[kind][1]))
	for entry: Array in wreck_entries:
		# Carcaça: sucata de ferro (picareta, pé de cabra ou machado).
		resources.add_prop(entry[0], "carcaca", entry[2], _box_collider(resources, entry[1], entry[2]), [[wreck_scatters[entry[1]], entry[3]]])
	# Zumbis (os mortos não voltam). Pedaço refeito por escavação: os zumbis,
	# as armas e os itens que já estavam soltos passam para o novo nó.
	var rebuilt: bool = data.get("rebuild", false)
	var zombies: Array = data.get("zombies", []) if not rebuilt else []
	for i in zombies.size():
		var key := "z_%d_%d_%d" % [coord.x, coord.y, i]
		if is_removed(key):
			continue
		var zombie := Zombie.new()
		zombie.name = "Zumbi%d" % i
		zombie.target = target
		# A roupa sai da chave: o mesmo zumbi volta igual ao recarregar.
		zombie.variant = absi(hash(key + "roupa")) % ZombieLook.OUTFITS.size()
		chunk.add_child(zombie)
		zombie.global_position = zombies[i]
		zombie.rotation.y = hash(key) % 628 / 100.0
		zombie.died.connect(func() -> void: mark_removed(key))
	# Armas largadas (corpos físicos de verdade).
	var weapons: Array = data["weapons"] if not rebuilt else []
	for i in weapons.size():
		var key := "%d_%d_%d" % [coord.x, coord.y, i]
		if _taken.has(key):
			continue
		var body := WeaponPickup.spawn(_weapons[weapons[i][0]], weapons[i][1], chunk)
		var pickup: WeaponPickup = body.get_node("WeaponPickup")
		pickup.interacted.connect(func(_by: Node) -> void: _taken[key] = true)
	# Recursos soltos (sucata de ferro, tábuas) nas vilas e cidades.
	var items: Array = data.get("items", []) if not rebuilt else []
	for i in items.size():
		var key := "i_%d_%d_%d" % [coord.x, coord.y, i]
		var item := ItemData.find(StringName(items[i][0]))
		if _taken.has(key) or item == null:
			continue
		var body := ItemPickup.spawn(item, items[i][1], chunk, items[i][2])
		var pickup: ItemPickup = body.get_node("ItemPickup")
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


func _prop_marker(kind: String, t: Transform3D) -> String:
	return "%s|%.2f|%.2f|%.2f" % [kind, t.origin.x, t.origin.y, t.origin.z]


## Alvo de golpe do mato (arbustos, samambaias, galhos): uma caixa menor que
## a planta, só na camada de alvos (o jogador passa por dentro).
func _soft_shape(body: StaticBody3D, kind: String, t: Transform3D) -> CollisionShape3D:
	_mesh(kind)
	var box: AABB = _boxes[kind]
	var scale := t.basis.get_scale()
	var shape := BoxShape3D.new()
	shape.size = (box.size * scale * 0.6).max(Vector3(0.3, 0.3, 0.3))
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = Transform3D(t.basis.orthonormalized(), t * box.get_center())
	body.add_child(collision)
	return collision


## Caixa de colisão do objeto (a caixa da malha, um pouco menor). Formações
## pontudas usam um cilindro fino no tronco.
func _box_collider(body: StaticBody3D, kind: String, t: Transform3D) -> CollisionShape3D:
	_mesh(kind)
	var box: AABB = _boxes[kind]
	if kind == "street_lamp_01":
		# Poste: só a coluna (o braço da luminária fica no alto, fora do alcance).
		var scale := t.basis.get_scale()
		var pole := CylinderShape3D.new()
		pole.radius = 0.14
		pole.height = box.size.y * scale.y
		var column := CollisionShape3D.new()
		column.shape = pole
		column.transform = Transform3D(Basis.IDENTITY, t.origin + Vector3.UP * pole.height * 0.5)
		body.add_child(column)
		return column
	if kind == "estalagmite":
		var scale := t.basis.get_scale()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = box.size.x * scale.x * 0.28
		cylinder.height = box.size.y * scale.y * 0.7
		var spire := CollisionShape3D.new()
		spire.shape = cylinder
		spire.transform = Transform3D(Basis.IDENTITY, t.origin + Vector3.UP * cylinder.height * 0.5)
		body.add_child(spire)
		return spire
	if kind.begins_with("rochedo"):
		# Rochedo: casco convexo da própria malha (uma caixa deixaria quinas
		# invisíveis), com a escala aplicada aos pontos.
		if not _hulls.has(kind):
			_hulls[kind] = (_mesh(kind).create_convex_shape(true, true) as ConvexPolygonShape3D).points
		var points: PackedVector3Array = (_hulls[kind] as PackedVector3Array).duplicate()
		var scale_basis := Basis.from_scale(t.basis.get_scale())
		for i in points.size():
			points[i] = scale_basis * points[i]
		var hull := ConvexPolygonShape3D.new()
		hull.points = points
		var rock := CollisionShape3D.new()
		rock.shape = hull
		rock.transform = Transform3D(t.basis.orthonormalized(), t.origin)
		body.add_child(rock)
		return rock
	# A física não aceita forma escalada: a escala vai para o tamanho da caixa.
	var scale := t.basis.get_scale()
	var shape := BoxShape3D.new()
	shape.size = box.size * scale * 0.9
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = Transform3D(t.basis.orthonormalized(), t * box.get_center())
	body.add_child(collision)
	return collision
