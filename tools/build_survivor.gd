extends SceneTree
## Ferramenta de produção: monta o personagem sobrevivente.
##
## Uso (duas etapas, por causa da importação das texturas reduzidas):
##   godot --headless --path . --script res://tools/build_survivor.gd
##   godot --headless --path . --import
##   godot --headless --path . --script res://tools/build_survivor.gd
## Na primeira execução as texturas 4K da roupa são reduzidas e gravadas em
## assets/characters/survivor/outfit/; na segunda, o personagem é montado.
##
## Entrada (CC0, ver ASSET_LICENSES.md):
##   - roupa modelada e esqueleto em proporções naturais ("Regular"):
##     Quaternius Modular Character Outfits – Fantasy (versão gratuita), em
##     assets/_source/outfits_fantasy/ (fora do Git): camisa, braços com mãos,
##     calça (Peasant) e botas de couro de cano alto (Ranger)
##   - cabeça, olhos, sobrancelhas, cabelo raspado e barba: Quaternius
##     Universal Base Characters (assets/characters/survivor/)
## Os dois pacotes usam o mesmo esqueleto de 65 ossos (mesma hierarquia e
## alturas; o "Regular" tem ombros e quadris 2 cm mais estreitos que o
## "Superhero"). As peles (Skin) guardam as matrizes de ligação de cada osso
## pelo nome, então a cabeça do pacote de personagens acompanha o osso Head
## do esqueleto novo sem editar vértices.
## Saída:
##   - resources/models/survivor/*.res  malhas
##   - scenes/characters/survivor.tscn   esqueleto, malhas, ragdoll,
##                                       AnimationPlayer com a biblioteca

const OUTFIT_DIR := "res://assets/_source/outfits_fantasy/"
const OUTFIT_SKELETON_SCENE := OUTFIT_DIR + "Male_Peasant.gltf"
const HEAD_SCENE := "res://assets/characters/survivor/Superhero_Male_FullBody.gltf"
const HAIR_SCENES := ["res://assets/characters/survivor/hair/Hair_Buzzed.gltf",
		"res://assets/characters/survivor/hair/Hair_Beard.gltf"]
const TEXTURE_DIR := "res://assets/characters/survivor/outfit/"
const LIBRARY := "res://resources/animations/survivor_body.res"
const OUT_DIR := "res://resources/models/survivor/"
const OUT_SCENE := "res://scenes/characters/survivor.tscn"
const BODY_ANIMATOR_SCRIPT := "res://scripts/animation/body_animator.gd"

## Peças da roupa: [nó, cena de origem, malha na cena, material, tinta]
## A camisa clara é tingida de oliva gasto (sobrevivência, não festa medieval).
const OUTFIT := [
	["Shirt", "Male_Peasant.gltf", "Male_Peasant_Body", "peasant", Color(0.62, 0.62, 0.50)],
	["Arms", "Male_Peasant.gltf", "Male_Peasant_Arms", "peasant", Color(0.62, 0.62, 0.50)],
	["Pants", "Male_Peasant.gltf", "Male_Peasant_Legs", "peasant", Color(0.80, 0.80, 0.80)],
	["Boots", "Male_Ranger.gltf", "Male_Ranger_Feet_Boots", "ranger", Color(0.85, 0.80, 0.75)],
]
## Texturas reduzidas: [arquivo de origem, nome de saída, lado (px)]
const TEXTURES := [
	["T_Peasant_BaseColor.png", "peasant_albedo.png", 2048],
	["T_Peasant_Normal.png", "peasant_normal.png", 2048],
	["T_Peasant_ORM.png", "peasant_orm.png", 2048],
	["T_Ranger_BaseColor.png", "ranger_albedo.png", 1024],
	["T_Ranger_Normal.png", "ranger_normal.png", 1024],
	["T_Ranger_ORM.png", "ranger_orm.png", 1024],
	["T_Regular_Male_Dark_BaseColor.png", "skin_albedo.png", 1024],
	["T_Regular_Male_Normal.png", "skin_normal.png", 1024],
	["T_Regular_Male_Roughness.png", "skin_roughness.png", 1024],
]
## Cor do cabelo, barba e sobrancelhas (a textura do pacote é neutra para tingir).
const HAIR_COLOR := Color(0.30, 0.22, 0.15)
## Influência mínima de Head + neck_01 para um triângulo do corpo-base fazer
## parte da cabeça (o resto do corpo-base é descartado: a roupa o substitui).
const HEAD_WEIGHT := 0.2

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


func _initialize() -> void:
	if not _prepare_textures():
		print("Texturas reduzidas gravadas em %s. Rode --import e esta ferramenta de novo." % TEXTURE_DIR)
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/characters"))
	var outfit_root: Node = (load(OUTFIT_SKELETON_SCENE) as PackedScene).instantiate()
	var source_skeleton: Skeleton3D = outfit_root.find_children("*", "Skeleton3D", true, false)[0]

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

	# Roupa modelada (corpo inteiro coberto, mãos e antebraços com pele).
	var materials := _materials()
	for piece in OUTFIT:
		var scene_root: Node = (load(OUTFIT_DIR + piece[1]) as PackedScene).instantiate()
		var part := scene_root.find_child(piece[2], true, false) as MeshInstance3D
		assert(part != null, "Peça %s não encontrada em %s" % [piece[2], piece[1]])
		var mesh := _with_materials(part.mesh, materials, piece[3], piece[4])
		_add_mesh(root, skeleton, piece[0], mesh, part.skin, "both")

	# Cabeça e pescoço do corpo-base (o resto do corpo-base fica de fora).
	var head_root: Node = (load(HEAD_SCENE) as PackedScene).instantiate()
	var head_skeleton: Skeleton3D = head_root.find_children("*", "Skeleton3D", true, false)[0]
	var base: MeshInstance3D = head_skeleton.get_node("SuperHero_Male")
	var head := _only_bones(base.mesh, base.skin, head_skeleton, ["Head", "neck_01"], HEAD_WEIGHT)
	_add_mesh(root, skeleton, "Head", head, base.skin, "full")
	for name in ["Eyes", "Eyebrows"]:
		var part: MeshInstance3D = head_skeleton.get_node(name)
		var mesh := part.mesh if name == "Eyes" else _tinted(part.mesh, HAIR_COLOR)
		_add_mesh(root, skeleton, name, mesh, part.skin, "full")
	for path in HAIR_SCENES:
		var hair_root: Node = (load(path) as PackedScene).instantiate()
		for part: MeshInstance3D in hair_root.find_children("*", "MeshInstance3D", true, false):
			_add_mesh(root, skeleton, path.get_file().get_basename(), _tinted(part.mesh, HAIR_COLOR), part.skin, "full")

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


## Reduz as texturas 4K do pacote (memória de vídeo no celular). Retorna
## verdadeiro se todas já existem importadas.
func _prepare_textures() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEXTURE_DIR))
	var ready := true
	for entry in TEXTURES:
		var target: String = TEXTURE_DIR + entry[1]
		if ResourceLoader.exists(target):
			continue
		ready = false
		var image := Image.load_from_file(ProjectSettings.globalize_path(OUTFIT_DIR + entry[0]))
		var side: int = entry[2]
		image.resize(side, side, Image.INTERPOLATE_LANCZOS)
		image.save_png(ProjectSettings.globalize_path(target))
	return ready


func _materials() -> Dictionary:
	var result := {}
	for set_name in ["peasant", "ranger"]:
		var material := ORMMaterial3D.new()
		material.albedo_texture = load(TEXTURE_DIR + set_name + "_albedo.png")
		material.normal_enabled = true
		material.normal_texture = load(TEXTURE_DIR + set_name + "_normal.png")
		material.orm_texture = load(TEXTURE_DIR + set_name + "_orm.png")
		result[set_name] = material
	var skin := StandardMaterial3D.new()
	skin.albedo_texture = load(TEXTURE_DIR + "skin_albedo.png")
	skin.normal_enabled = true
	skin.normal_texture = load(TEXTURE_DIR + "skin_normal.png")
	skin.roughness_texture = load(TEXTURE_DIR + "skin_roughness.png")
	skin.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	result["skin"] = skin
	return result


## Copia a malha trocando os materiais do pacote pelos das texturas reduzidas.
## Superfícies de pele (MI_Regular_Male) recebem o material de pele.
func _with_materials(mesh: Mesh, materials: Dictionary, set_name: String, tint: Color) -> Mesh:
	var copy := mesh.duplicate() as ArrayMesh
	for surface in copy.get_surface_count():
		var original := copy.surface_get_material(surface)
		var is_skin := original != null and String(original.resource_name).contains("Regular")
		if is_skin:
			copy.surface_set_material(surface, materials["skin"])
		else:
			var material := (materials[set_name] as BaseMaterial3D).duplicate() as BaseMaterial3D
			material.albedo_color = tint
			copy.surface_set_material(surface, material)
	return copy


func _add_mesh(root: Node, skeleton: Skeleton3D, node_name: String, mesh: Mesh, skin: Skin,
		view: String) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var path := OUT_DIR + node_name.to_snake_case() + ".res"
	ResourceSaver.save(mesh, path)
	instance.mesh = load(path)
	instance.skin = skin
	# Os limites mudam muito com as animações (deitar, rolar).
	instance.custom_aabb = AABB(Vector3(-1.2, -0.2, -1.2), Vector3(2.4, 2.4, 2.4))
	skeleton.add_child(instance)
	instance.owner = root
	instance.skeleton = NodePath("..")
	# "full" = só em terceira pessoa (em primeira pessoa vira só sombra: a
	# câmera ocupa o lugar da cabeça); "both" = sempre visível.
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
		physical.joint_offset = Transform3D(_basis_with_x(direction), Vector3.ZERO)
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


## Só os triângulos em que todos os vértices têm influência dos ossos dados
## acima do limiar (ex.: cabeça e pescoço do corpo-base).
func _only_bones(mesh: ArrayMesh, skin: Skin, skeleton: Skeleton3D, bone_names: Array, threshold: float) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var influences := bones.size() / vertices.size()
	var selected_binds := {}
	for bind in skin.get_bind_count():
		var bone_name := String(skin.get_bind_name(bind))
		if bone_name.is_empty():
			bone_name = skeleton.get_bone_name(skin.get_bind_bone(bind))
		if bone_name in bone_names:
			selected_binds[bind] = true
	var amount := PackedFloat32Array()
	amount.resize(vertices.size())
	for v in vertices.size():
		for k in influences:
			if selected_binds.has(bones[v * influences + k]):
				amount[v] += weights[v * influences + k]
	var kept := PackedInt32Array()
	for t in indices.size() / 3:
		if amount[indices[t * 3]] > threshold and amount[indices[t * 3 + 1]] > threshold and amount[indices[t * 3 + 2]] > threshold:
			kept.append(t)
	var result := _extract(arrays, kept)
	result.surface_set_material(0, mesh.surface_get_material(0))
	return result


## Nova malha com os triângulos dados (vértices não usados são descartados).
func _extract(arrays: Array, triangles: PackedInt32Array) -> ArrayMesh:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertex_count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var remap := PackedInt32Array()
	remap.resize(vertex_count)
	remap.fill(-1)
	var order := PackedInt32Array()
	var new_indices := PackedInt32Array()
	for t in triangles:
		for k in 3:
			var old := indices[t * 3 + k]
			if remap[old] < 0:
				remap[old] = order.size()
				order.append(old)
			new_indices.append(remap[old])
	var result_arrays := []
	result_arrays.resize(Mesh.ARRAY_MAX)
	for channel in Mesh.ARRAY_MAX:
		var data = arrays[channel]
		if data == null or channel == Mesh.ARRAY_INDEX:
			continue
		var per_vertex: int = data.size() / vertex_count
		var copy = data.duplicate()
		copy.resize(order.size() * per_vertex)
		for i in order.size():
			for k in per_vertex:
				copy[i * per_vertex + k] = data[order[i] * per_vertex + k]
		result_arrays[channel] = copy
	result_arrays[Mesh.ARRAY_INDEX] = new_indices
	var mesh := ArrayMesh.new()
	var flags := 0
	if result_arrays[Mesh.ARRAY_BONES] != null and (result_arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() == order.size() * 8:
		flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result_arrays, [], {}, flags)
	return mesh


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
