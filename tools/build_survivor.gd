extends SceneTree
## Ferramenta de produção: monta o personagem sobrevivente.
##
## Uso: godot --headless --path . --script res://tools/build_survivor.gd
##
## Entrada (CC0, ver ASSET_LICENSES.md):
##   - corpo, olhos e sobrancelhas: Quaternius Universal Base Characters
##   - cabelo raspado e barba: idem (versões presas ao osso da cabeça)
##   - tecidos PBR: Poly Haven (algodão, jeans, couro)
## Saída:
##   - resources/models/survivor/*.res  malhas (corpo recortado e roupas)
##   - scenes/characters/survivor.tscn   personagem com esqueleto, malhas,
##                                       AnimationPlayer e a biblioteca retargetada
##
## As roupas são geradas a partir da malha do corpo: cada triângulo é
## classificado pela influência dos ossos (tronco/braços → jaqueta, pélvis/
## coxas/canelas → calça, pés → botas), copiado para uma camada própria,
## deslocado para fora pela normal média de cada posição (sem rachaduras nas
## costuras de UV) e suavizado para apagar o relevo muscular. Cada peça avança
## um anel de triângulos sobre a vizinha (a jaqueta cobre a cintura da calça,
## a bota cobre a barra da calça) e a pele totalmente coberta é removida.

const BODY_SCENE := "res://assets/characters/survivor/Superhero_Male_FullBody.gltf"
const HAIR_SCENES := ["res://assets/characters/survivor/hair/Hair_Buzzed.gltf",
		"res://assets/characters/survivor/hair/Hair_Beard.gltf"]
const LIBRARY := "res://resources/animations/survivor_body.res"
const OUT_DIR := "res://resources/models/survivor/"
const OUT_SCENE := "res://scenes/characters/survivor.tscn"
const BODY_ANIMATOR_SCRIPT := "res://scripts/animation/body_animator.gd"

const JACKET_BONES := ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r",
		"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"]
const PANTS_BONES := ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"]
const BOOT_BONES := ["foot_l", "foot_r", "ball_l", "ball_r"]
## Altura (m, na pose de repouso) abaixo da qual a canela vira cano da bota.
const BOOT_TOP := 0.20
## Cor do cabelo, barba e sobrancelhas (a textura do pacote é neutra para tingir).
const HAIR_COLOR := Color(0.30, 0.22, 0.15)

## [nome, camada, deslocamento (m), iterações de suavização, textura, cor, escala UV]
## Ragdoll: [osso, osso-filho que define o comprimento ("" = vertical), raio,
## massa (kg), abertura do cone (graus), torção (graus)]. Soma ≈ 80 kg.
const RAGDOLL := [
	["pelvis", "spine_01", 0.13, 12.0, 0.0, 0.0],
	["spine_01", "spine_03", 0.13, 10.0, 25.0, 20.0],
	["spine_03", "neck_01", 0.15, 14.0, 25.0, 20.0],
	["Head", "", 0.11, 5.0, 40.0, 45.0],
	["upperarm_l", "lowerarm_l", 0.055, 2.5, 75.0, 40.0],
	["upperarm_r", "lowerarm_r", 0.055, 2.5, 75.0, 40.0],
	["lowerarm_l", "hand_l", 0.045, 1.8, 75.0, 10.0],
	["lowerarm_r", "hand_r", 0.045, 1.8, 75.0, 10.0],
	["hand_l", "middle_01_l", 0.04, 0.6, 40.0, 20.0],
	["hand_r", "middle_01_r", 0.04, 0.6, 40.0, 20.0],
	["thigh_l", "calf_l", 0.085, 9.0, 60.0, 20.0],
	["thigh_r", "calf_r", 0.085, 9.0, 60.0, 20.0],
	["calf_l", "foot_l", 0.06, 4.0, 70.0, 5.0],
	["calf_r", "foot_r", 0.06, 4.0, 70.0, 5.0],
	["foot_l", "ball_l", 0.045, 1.2, 30.0, 10.0],
	["foot_r", "ball_r", 0.045, 1.2, 30.0, 10.0],
]
## Camada dos ossos físicos (8 = "ragdoll"): colidem com mundo e objetos, não entre si.
const RAGDOLL_LAYER := 128
const RAGDOLL_MASK := 1 | 4

const GARMENTS := [
	["Jacket", 1, 0.020, 4, "cotton_jersey", Color(0.42, 0.44, 0.30), 10.0],
	["Pants", 2, 0.011, 3, "denim_fabric", Color(0.80, 0.82, 0.88), 9.0],
	["Boots", 3, 0.016, 2, "brown_leather", Color(0.55, 0.45, 0.38), 6.0],
]


func _initialize() -> void:
	var body_root: Node = (load(BODY_SCENE) as PackedScene).instantiate()
	var source_skeleton: Skeleton3D = body_root.find_children("*", "Skeleton3D", true, false)[0]
	var body_instance: MeshInstance3D = source_skeleton.get_node("SuperHero_Male")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/characters"))

	var root := Node3D.new()
	root.name = "Survivor"
	var armature := Node3D.new()
	armature.name = "Armature"
	# O modelo olha para +Z (glTF); o jogo usa -Z como frente.
	armature.rotation.y = PI
	root.add_child(armature)
	armature.owner = root
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	for bone in source_skeleton.get_bone_count():
		skeleton.add_bone(source_skeleton.get_bone_name(bone))
	for bone in source_skeleton.get_bone_count():
		skeleton.set_bone_parent(bone, source_skeleton.get_bone_parent(bone))
		skeleton.set_bone_rest(bone, source_skeleton.get_bone_rest(bone))
	skeleton.reset_bone_poses()
	armature.add_child(skeleton)
	skeleton.owner = root

	var garments := _split_body(body_instance, source_skeleton)
	_add_mesh(root, skeleton, "Body", garments["Body"], body_instance.skin, 0, false, "full")
	for garment in GARMENTS:
		var view := "full" if garment[0] == "Jacket" else "both"
		_add_mesh(root, skeleton, garment[0], garments[garment[0]], body_instance.skin, garment[1], false, view)
	# Primeira pessoa: corpo e jaqueta sem cabeça e pescoço (a câmera ocupa o
	# lugar deles). As versões completas continuam projetando a sombra.
	for name in ["Body", "Jacket"]:
		var headless := _without_head(garments[name], body_instance.skin, source_skeleton)
		_add_mesh(root, skeleton, name + "FirstPerson", headless, body_instance.skin, 0, false, "first_person")
	for name in ["Eyes", "Eyebrows"]:
		var part: MeshInstance3D = source_skeleton.get_node(name)
		var mesh := part.mesh if name == "Eyes" else _tinted(part.mesh, HAIR_COLOR)
		_add_mesh(root, skeleton, name, mesh, part.skin, 0, true)
	for path in HAIR_SCENES:
		var hair_root: Node = (load(path) as PackedScene).instantiate()
		for part: MeshInstance3D in hair_root.find_children("*", "MeshInstance3D", true, false):
			_add_mesh(root, skeleton, path.get_file().get_basename(), _tinted(part.mesh, HAIR_COLOR), part.skin, 0, true)

	_build_ragdoll(skeleton, root)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", load(LIBRARY))
	root.add_child(player)
	player.owner = root
	if ResourceLoader.exists(BODY_ANIMATOR_SCRIPT):
		root.set_script(load(BODY_ANIMATOR_SCRIPT))
		root.set("skeleton", skeleton)
		root.set("animation_player", player)

	var packed := PackedScene.new()
	var error := packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, OUT_SCENE)
	print("Sobrevivente gerado: %s" % error_string(error))
	quit(0 if error == OK else 1)


func _add_mesh(root: Node, skeleton: Skeleton3D, node_name: String, mesh: Mesh, skin: Skin,
		layer: int, keep_material: bool = false, view: String = "full") -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var path := OUT_DIR + node_name.to_snake_case() + ".res"
	if not keep_material or true:
		ResourceSaver.save(mesh, path)
		mesh = load(path)
	instance.mesh = mesh
	instance.skin = skin
	# Os limites mudam muito com as animações (deitar, rolar).
	instance.custom_aabb = AABB(Vector3(-1.2, -0.2, -1.2), Vector3(2.4, 2.4, 2.4))
	skeleton.add_child(instance)
	instance.owner = root
	instance.skeleton = NodePath("..")
	instance.set_meta(&"garment_layer", layer)
	# "full" = corpo completo (terceira pessoa; sombra em primeira pessoa),
	# "first_person" = sem cabeça (só primeira pessoa), "both" = sempre.
	instance.set_meta(&"view", view)


## Cria o PhysicalBoneSimulator3D com cápsulas no comprimento de cada osso e
## juntas cônicas com limites anatômicos.
func _build_ragdoll(skeleton: Skeleton3D, root: Node) -> void:
	var simulator := PhysicalBoneSimulator3D.new()
	simulator.name = "PhysicalBoneSimulator3D"
	skeleton.add_child(simulator)
	simulator.owner = root
	for spec in RAGDOLL:
		var bone := skeleton.find_bone(spec[0])
		var global_rest := skeleton.get_bone_global_rest(bone)
		var direction: Vector3
		var length: float
		if String(spec[1]).is_empty():
			direction = (global_rest.basis.inverse() * Vector3.UP).normalized()
			length = 0.22
		else:
			var child_local := global_rest.affine_inverse() * skeleton.get_bone_global_rest(skeleton.find_bone(spec[1])).origin
			direction = child_local.normalized()
			length = child_local.length()
		var physical := PhysicalBone3D.new()
		physical.name = "Physical_" + String(spec[0])
		physical.bone_name = spec[0]
		physical.mass = spec[3]
		physical.friction = 0.8
		physical.linear_damp = 0.1
		physical.angular_damp = 0.8
		physical.collision_layer = RAGDOLL_LAYER
		physical.collision_mask = RAGDOLL_MASK
		physical.transform = global_rest
		# Junta na origem do osso, eixo X (torção) ao longo do osso.
		var joint_basis := _basis_with_x(direction)
		physical.joint_offset = Transform3D(joint_basis, Vector3.ZERO)
		if float(spec[4]) > 0.0:
			physical.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			physical.set("joint_constraints/swing_span", spec[4])
			physical.set("joint_constraints/twist_span", spec[5])
		simulator.add_child(physical)
		physical.owner = root
		var capsule := CapsuleShape3D.new()
		capsule.radius = spec[2]
		capsule.height = maxf(length + float(spec[2]) * 0.6, float(spec[2]) * 2.0)
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		shape.shape = capsule
		# A cápsula (eixo Y) fica centrada no segmento do osso.
		shape.transform = Transform3D(_basis_with_y(direction), direction * length * 0.5)
		physical.add_child(shape)
		shape.owner = root


func _basis_with_y(direction: Vector3) -> Basis:
	var y := direction.normalized()
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(reference).normalized()
	return Basis(x, y, x.cross(y).normalized())


func _basis_with_x(direction: Vector3) -> Basis:
	var x := direction.normalized()
	var reference := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var z := x.cross(reference).normalized()
	return Basis(x, z.cross(x).normalized(), z)


## Remove os triângulos com influência da cabeça ou do pescoço.
func _without_head(mesh: ArrayMesh, skin: Skin, skeleton: Skeleton3D) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var influences := bones.size() / vertices.size()
	var head_binds := {}
	for bind in skin.get_bind_count():
		var bone_name := String(skin.get_bind_name(bind))
		if bone_name.is_empty():
			bone_name = skeleton.get_bone_name(skin.get_bind_bone(bind))
		if bone_name in ["Head", "neck_01"]:
			head_binds[bind] = true
	var head_weight := PackedFloat32Array()
	head_weight.resize(vertices.size())
	for v in vertices.size():
		for k in influences:
			if head_binds.has(bones[v * influences + k]):
				head_weight[v] += weights[v * influences + k]
	var kept := PackedInt32Array()
	for t in indices.size() / 3:
		var keep := true
		for k in 3:
			if head_weight[indices[t * 3 + k]] > 0.15:
				keep = false
		if keep:
			kept.append(t)
	var result := _submesh(arrays, kept, PackedVector3Array(), 0.0)
	result.surface_set_material(0, mesh.surface_get_material(0))
	return result


## Copia a malha com os materiais tingidos (multiplicando a textura).
func _tinted(mesh: Mesh, color: Color) -> Mesh:
	var copy := mesh.duplicate() as Mesh
	for surface in copy.get_surface_count():
		var material := copy.surface_get_material(surface)
		if material is BaseMaterial3D:
			var tinted := material.duplicate() as BaseMaterial3D
			tinted.albedo_color = color
			copy.surface_set_material(surface, tinted)
	return copy


# =============================================================================
# Recorte do corpo e geração das roupas
# =============================================================================

func _split_body(body: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var source: ArrayMesh = body.mesh
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var influences := bones.size() / vertices.size()
	var skin := body.skin

	# Grupo de cada vínculo da skin.
	var bind_group: Array[int] = []
	for bind in skin.get_bind_count():
		var bone_name := String(skin.get_bind_name(bind))
		if bone_name.is_empty():
			bone_name = skeleton.get_bone_name(skin.get_bind_bone(bind))
		if bone_name in JACKET_BONES:
			bind_group.append(1)
		elif bone_name in PANTS_BONES:
			bind_group.append(2)
		elif bone_name in BOOT_BONES:
			bind_group.append(3)
		else:
			bind_group.append(0)

	# Classe de cada vértice: grupo de maior peso, com o cano da bota por altura
	# e o pulso (influência da mão) como pele.
	var vertex_class := PackedInt32Array()
	vertex_class.resize(vertices.size())
	for v in vertices.size():
		var sums := [0.0, 0.0, 0.0, 0.0]
		for k in influences:
			sums[bind_group[bones[v * influences + k]]] += weights[v * influences + k]
		var best := 0
		for g in 4:
			if sums[g] > sums[best]:
				best = g
		if best == 2 and vertices[v].y < BOOT_TOP:
			best = 3
		if best == 1 and sums[0] > 0.25:
			best = 0 # pulso e pescoço ficam de pele
		vertex_class[v] = best

	# Triângulo pertence à peça da maioria dos vértices.
	var triangle_count := indices.size() / 3
	var triangle_class := PackedInt32Array()
	triangle_class.resize(triangle_count)
	for t in triangle_count:
		var counts := [0, 0, 0, 0]
		for k in 3:
			counts[vertex_class[indices[t * 3 + k]]] += 1
		var best := 0
		for g in 4:
			if counts[g] > counts[best]:
				best = g
		triangle_class[t] = best

	# Normal média por posição (evita rachaduras nas costuras de UV).
	var position_key := {}
	var averaged := PackedVector3Array()
	averaged.resize(vertices.size())
	for v in vertices.size():
		var key := vertices[v].snapped(Vector3.ONE * 0.0001)
		position_key[key] = (position_key.get(key, Vector3.ZERO) as Vector3) + normals[v]
	for v in vertices.size():
		averaged[v] = (position_key[vertices[v].snapped(Vector3.ONE * 0.0001)] as Vector3).normalized()

	var result := {}
	var covered := PackedByteArray()
	covered.resize(triangle_count)
	for garment in GARMENTS:
		var layer: int = garment[1]
		# Peça + um anel de triângulos vizinhos (sobreposição nas bordas).
		var member := PackedByteArray()
		member.resize(vertices.size())
		for t in triangle_count:
			if triangle_class[t] == layer:
				for k in 3:
					member[indices[t * 3 + k]] = 1
		var selected := PackedInt32Array()
		for t in triangle_count:
			var inside := triangle_class[t] == layer
			var touches := false
			for k in 3:
				touches = touches or member[indices[t * 3 + k]] == 1
			if inside or (touches and _grows_into(layer, triangle_class[t])):
				selected.append(t)
				if inside:
					covered[t] = 1
		result[garment[0]] = _build_shell(arrays, selected, averaged, garment)
	# Corpo: só os triângulos que nenhuma peça cobre por inteiro.
	var body_triangles := PackedInt32Array()
	for t in triangle_count:
		if covered[t] == 0:
			body_triangles.append(t)
	var body_mesh := _submesh(arrays, body_triangles, PackedVector3Array(), 0.0)
	body_mesh.surface_set_material(0, source.surface_get_material(0))
	result["Body"] = body_mesh
	return result


## A jaqueta avança sobre a calça e a pele; a bota sobre a calça; a calça
## sobre a pele (cintura).
func _grows_into(layer: int, other: int) -> bool:
	match layer:
		1:
			return other == 2 or other == 0
		3:
			return other == 2
		2:
			return other == 0
	return false


func _build_shell(arrays: Array, triangles: PackedInt32Array, averaged: PackedVector3Array, garment: Array) -> ArrayMesh:
	var offset: float = garment[2]
	var mesh := _submesh(arrays, triangles, averaged, offset, garment[3])
	var material := ORMMaterial3D.new()
	var folder := "res://assets/polyhaven/textures/%s/%s_" % [garment[4], garment[4]]
	material.albedo_texture = load(folder + "albedo_1k.jpg")
	material.albedo_color = garment[5]
	material.normal_enabled = true
	material.normal_texture = load(folder + "normal_1k.jpg")
	material.orm_texture = load(folder + "arm_1k.jpg")
	material.uv1_scale = Vector3.ONE * float(garment[6])
	# A borda interna da peça aparece nos punhos e na cintura.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


## Copia os triângulos escolhidos para uma malha nova, reindexada, com os
## vértices deslocados pela normal média e suavizados (Laplaciano).
func _submesh(arrays: Array, triangles: PackedInt32Array, averaged: PackedVector3Array,
		offset: float, smooth_iterations: int = 0) -> ArrayMesh:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var remap := {}
	var order := PackedInt32Array()
	var new_indices := PackedInt32Array()
	for t in triangles:
		for k in 3:
			var v := indices[t * 3 + k]
			if not remap.has(v):
				remap[v] = order.size()
				order.append(v)
			new_indices.append(remap[v])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TANGENT,
			Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		var data = arrays[channel]
		if data == null:
			continue
		var width := 1
		if channel == Mesh.ARRAY_TANGENT:
			width = 4
		elif channel == Mesh.ARRAY_BONES or channel == Mesh.ARRAY_WEIGHTS:
			width = data.size() / vertices.size()
		var copy = data.duplicate()
		copy.resize(order.size() * width)
		for i in order.size():
			for k in width:
				copy[i * width + k] = data[order[i] * width + k]
		out[channel] = copy
	out[Mesh.ARRAY_INDEX] = new_indices
	if offset > 0.0:
		var positions: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
		for i in order.size():
			positions[i] += averaged[order[i]] * offset
		positions = _smooth(positions, new_indices, smooth_iterations)
		out[Mesh.ARRAY_VERTEX] = positions
	var mesh := ArrayMesh.new()
	var format := Mesh.ARRAY_FORMAT_VERTEX
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if (out[Mesh.ARRAY_BONES] as PackedInt32Array).size() / order.size() == 8 else 0)
	return mesh


## Suavização Laplaciana por posição (vértices coincidentes andam juntos);
## vértices de borda ficam fixos para manter o encaixe com a vizinha.
func _smooth(positions: PackedVector3Array, indices: PackedInt32Array, iterations: int) -> PackedVector3Array:
	if iterations <= 0:
		return positions
	var key_of := PackedInt32Array()
	key_of.resize(positions.size())
	var keys := {}
	for i in positions.size():
		var key := positions[i].snapped(Vector3.ONE * 0.0001)
		if not keys.has(key):
			keys[key] = keys.size()
		key_of[i] = keys[key]
	var count := keys.size()
	var neighbors: Array[Dictionary] = []
	neighbors.resize(count)
	for i in count:
		neighbors[i] = {}
	var edge_uses := {}
	for t in indices.size() / 3:
		for k in 3:
			var a := key_of[indices[t * 3 + k]]
			var b := key_of[indices[t * 3 + (k + 1) % 3]]
			neighbors[a][b] = true
			neighbors[b][a] = true
			var edge := Vector2i(mini(a, b), maxi(a, b))
			edge_uses[edge] = int(edge_uses.get(edge, 0)) + 1
	var boundary := PackedByteArray()
	boundary.resize(count)
	for edge: Vector2i in edge_uses:
		if edge_uses[edge] == 1:
			boundary[edge.x] = 1
			boundary[edge.y] = 1
	var current := PackedVector3Array()
	current.resize(count)
	for i in positions.size():
		current[key_of[i]] = positions[i]
	for iteration in iterations:
		var next := current.duplicate()
		for i in count:
			if boundary[i] == 1 or neighbors[i].is_empty():
				continue
			var mean := Vector3.ZERO
			for n in neighbors[i]:
				mean += current[n]
			mean /= neighbors[i].size()
			next[i] = current[i].lerp(mean, 0.5)
		current = next
	for i in positions.size():
		positions[i] = current[key_of[i]]
	return positions
