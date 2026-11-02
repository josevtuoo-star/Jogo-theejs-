extends SceneTree
## Ferramenta de produção: monta o personagem sobrevivente.
##
## Uso: godot --headless --path . --script res://tools/build_survivor.gd
##
## Entrada: assets/characters/survivor/Sobrevivente.fbx, o modelo do
## sobrevivente enviado pelo dono do projeto (malha única com 23 materiais de
## cor, esqueleto de 65 ossos na convenção Mixamo, em T).
## Saída:
##   - resources/models/survivor/*.res  malhas
##   - scenes/characters/survivor.tscn   esqueleto, malhas, ragdoll,
##                                       AnimationPlayer com a biblioteca
##
## - Os ossos são renomeados para os nomes do jogo (tools/rig_names.gd), e a
##   pele (Skin) também: animador, combate, ragdoll e testes não mudam.
## - A malha é dividida em duas: cabeça (rosto, gorro, cabelo, barba, olhos;
##   triângulos presos à cabeça e ao pescoço) e corpo. Em primeira pessoa a
##   cabeça vira só sombra: a câmera ocupa o lugar dela.
## - Os materiais de cor do modelo viram materiais PBR com rugosidade e metal
##   de cada tipo de superfície (tecido, couro, metal, pele).

const SOURCE := "res://assets/characters/survivor/Sobrevivente.fbx"
const LIBRARY := "res://resources/animations/survivor_body.res"
const OUT_DIR := "res://resources/models/survivor/"
const OUT_SCENE := "res://scenes/characters/survivor.tscn"
const BODY_ANIMATOR_SCRIPT := "res://scripts/animation/body_animator.gd"
const RigNames := preload("res://tools/rig_names.gd")

## Influência mínima de Head + neck_01 para um triângulo ser da cabeça.
const HEAD_WEIGHT := 0.5
## Superfície do material → [rugosidade, metal]. Os nomes vêm do modelo.
const SURFACES := {
	"Pele": [0.62, 0.0], "PeleSombra": [0.66, 0.0], "Labio": [0.5, 0.0],
	"Barba": [0.95, 0.0], "Cabelo": [0.95, 0.0],
	"Esclera": [0.25, 0.0], "Iris": [0.2, 0.0], "Pupila": [0.15, 0.0],
	"Gorro": [0.97, 0.0], "GorroDobra": [0.97, 0.0],
	"Jaqueta": [0.88, 0.0], "JaquetaEscura": [0.9, 0.0], "Cordao": [0.9, 0.0],
	"Ziper": [0.4, 0.75], "Metal": [0.35, 0.85],
	"Calca": [0.92, 0.0], "CalcaEscura": [0.92, 0.0],
	"Bota": [0.6, 0.0], "BotaEscura": [0.62, 0.0], "Sola": [0.85, 0.0], "Cadarco": [0.9, 0.0],
	"Luva": [0.75, 0.0], "Sujeira": [1.0, 0.0],
}
## As cores do modelo são de pintura plana; para a luz física do jogo (sol e
## céu) elas são escurecidas um pouco, como um albedo real de tecido.
const ALBEDO_SCALE := 0.82

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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/characters"))
	var source_root: Node = (load(SOURCE) as PackedScene).instantiate()
	var source_skeleton: Skeleton3D = source_root.find_children("*", "Skeleton3D", true, false)[0]
	RigNames.rename_skeleton(source_skeleton)
	var source_mesh: MeshInstance3D = source_root.find_children("*", "MeshInstance3D", true, false)[0]

	var root := Node3D.new()
	root.name = "Survivor"
	var armature := Node3D.new()
	armature.name = "Armature"
	# O modelo olha para +Z; o jogo usa -Z como frente.
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

	var skin := RigNames.rename_skin(source_mesh.skin)
	var mesh := _with_materials(source_mesh.mesh)
	var parts := _split_by_bones(mesh, skin, skeleton, ["Head", "neck_01"], HEAD_WEIGHT)
	_add_mesh(root, skeleton, "Body", parts[1], skin, "both")
	_add_mesh(root, skeleton, "Head", parts[0], skin, "full")

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
	print("Sobrevivente gerado: %s (corpo %d, cabeça %d superfícies)" % [error_string(error), parts[1].get_surface_count(), parts[0].get_surface_count()])
	quit(0 if error == OK else 1)


## Copia a malha com materiais PBR por tipo de superfície.
func _with_materials(mesh: Mesh) -> ArrayMesh:
	var copy := mesh.duplicate() as ArrayMesh
	for surface in copy.get_surface_count():
		var original := copy.surface_get_material(surface) as BaseMaterial3D
		var material := StandardMaterial3D.new()
		var surface_name := String(original.resource_name) if original != null else ""
		material.resource_name = surface_name
		var color := original.albedo_color if original != null else Color(0.5, 0.5, 0.5)
		material.albedo_color = Color(color.r * ALBEDO_SCALE, color.g * ALBEDO_SCALE, color.b * ALBEDO_SCALE)
		var params: Array = SURFACES.get(surface_name, [0.85, 0.0])
		material.roughness = params[0]
		material.metallic = params[1]
		if surface_name.begins_with("Pele") or surface_name == "Labio":
			# Pele: luz atravessando de leve (orelhas, contra o sol).
			material.rim_enabled = true
			material.rim = 0.15
			material.rim_tint = 0.6
		copy.surface_set_material(surface, material)
	return copy


func _add_mesh(root: Node, skeleton: Skeleton3D, node_name: String, mesh: Mesh, skin: Skin, view: String) -> void:
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


## Divide a malha (todas as superfícies) em [triângulos presos aos ossos
## dados, resto], mantendo os materiais.
func _split_by_bones(mesh: ArrayMesh, skin: Skin, skeleton: Skeleton3D, bone_names: Array, threshold: float) -> Array[ArrayMesh]:
	var selected_binds := {}
	for bind in skin.get_bind_count():
		var bone_name := String(skin.get_bind_name(bind))
		if bone_name.is_empty():
			bone_name = skeleton.get_bone_name(skin.get_bind_bone(bind))
		if bone_name in bone_names:
			selected_binds[bind] = true
	var inside := ArrayMesh.new()
	var outside := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var influences := bones.size() / vertices.size()
		var amount := PackedFloat32Array()
		amount.resize(vertices.size())
		for v in vertices.size():
			for k in influences:
				if selected_binds.has(bones[v * influences + k]):
					amount[v] += weights[v * influences + k]
		var kept_in := PackedInt32Array()
		var kept_out := PackedInt32Array()
		for t in indices.size() / 3:
			var a := amount[indices[t * 3]] + amount[indices[t * 3 + 1]] + amount[indices[t * 3 + 2]]
			if a / 3.0 > threshold:
				kept_in.append(t)
			else:
				kept_out.append(t)
		for pair in [[inside, kept_in], [outside, kept_out]]:
			if (pair[1] as PackedInt32Array).is_empty():
				continue
			var part := _extract(arrays, pair[1])
			var target: ArrayMesh = pair[0]
			target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part.surface_get_arrays(0), [], {},
					Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if influences == 8 else 0)
			target.surface_set_material(target.get_surface_count() - 1, mesh.surface_get_material(surface))
	return [inside, outside]


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
