class_name MeshTools
extends RefCounted
## Utilidades das ferramentas de produção: juntar as malhas de um modelo
## importado numa só, aplicar transformações (inclusive escala não uniforme)
## e gerar níveis de detalhe.


## Todas as superfícies do modelo, com as transformações dos nós aplicadas:
## [[arrays, material], ...].
## `only`: só os nós cujo nome contém algum destes textos (pacotes com várias
## variantes lado a lado: escolhe uma).
static func flatten(path: String, only: Array = []) -> Array:
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var result := []
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not only.is_empty() and not only.any(func(text: String) -> bool: return String(mi.name).contains(text)):
			continue
		var xform := Transform3D.IDENTITY
		var node: Node = mi
		while node != null and node != root:
			xform = (node as Node3D).transform * xform
			node = node.get_parent()
		for s in mi.mesh.get_surface_count():
			var arrays := transformed(mi.mesh.surface_get_arrays(s), xform)
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
			result.append([arrays, mi.get_active_material(s)])
	root.free()
	return result


static func transformed(arrays: Array, xform: Transform3D) -> Array:
	var copy := arrays.duplicate()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var moved := PackedVector3Array()
	moved.resize(vertices.size())
	for i in vertices.size():
		moved[i] = xform * vertices[i]
	copy[Mesh.ARRAY_VERTEX] = moved
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var turned := PackedVector3Array()
		turned.resize(normals.size())
		var basis := xform.basis.inverse().transposed()
		for i in normals.size():
			turned[i] = (basis * normals[i]).normalized()
		copy[Mesh.ARRAY_NORMAL] = turned
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var out := tangents.duplicate()
		for i in tangents.size() / 4:
			var t := (xform.basis * Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])).normalized()
			out[i * 4] = t.x
			out[i * 4 + 1] = t.y
			out[i * 4 + 2] = t.z
		copy[Mesh.ARRAY_TANGENT] = out
	return copy


## Junta as partes numa malha. Com `lods`, gera níveis de detalhe (o motor
## troca para versões mais leves de longe; essencial para vegetação).
static func build(parts: Array, xform: Transform3D = Transform3D.IDENTITY, lods: bool = false) -> ArrayMesh:
	if lods:
		var importer := ImporterMesh.new()
		for part in parts:
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, transformed(part[0], xform), [], {}, part[1])
		importer.generate_lods(25.0, 60.0, [])
		return importer.get_mesh()
	var mesh := ArrayMesh.new()
	for part in parts:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, transformed(part[0], xform))
		mesh.surface_set_material(mesh.get_surface_count() - 1, part[1])
	return mesh


static func bounds(parts: Array, xform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var box := AABB()
	var first := true
	for part in parts:
		for v: Vector3 in part[0][Mesh.ARRAY_VERTEX]:
			var p := xform * v
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box


## Índices dos triângulos (gera a sequência quando a superfície não é indexada).
static func indices_of(arrays: Array) -> PackedInt32Array:
	if arrays[Mesh.ARRAY_INDEX] != null:
		return arrays[Mesh.ARRAY_INDEX]
	var result := PackedInt32Array()
	result.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	for i in result.size():
		result[i] = i
	return result


## Reduz as partes para no máximo `max_triangles` (no total), usando a
## simplificação do próprio motor (a mesma dos níveis de detalhe) e
## descartando os vértices que sobraram sem uso.
static func simplified(parts: Array, max_triangles: int) -> Array:
	var total := 0
	for part in parts:
		total += indices_of(part[0]).size() / 3
	if total <= max_triangles:
		return parts
	var ratio := float(max_triangles) / total
	var result := []
	for part in parts:
		var arrays: Array = part[0]
		var indices := indices_of(arrays)
		var target := int(indices.size() / 3 * ratio)
		var importer := ImporterMesh.new()
		var source := arrays.duplicate()
		source[Mesh.ARRAY_INDEX] = indices
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, source)
		importer.generate_lods(25.0, 60.0, [])
		# A geração pode dividir vértices (normais): os índices dos níveis se
		# referem aos vértices do próprio importador, não aos originais.
		var generated := importer.get_surface_arrays(0)
		var best: PackedInt32Array = generated[Mesh.ARRAY_INDEX]
		for lod in importer.get_surface_lod_count(0):
			var candidate := importer.get_surface_lod_indices(0, lod)
			best = candidate
			if candidate.size() / 3 <= target:
				break
		result.append([_compacted(generated, best), part[1]])
	return result


static func _compacted(arrays: Array, indices: PackedInt32Array) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var new_indices := PackedInt32Array()
	new_indices.resize(indices.size())
	for i in indices.size():
		var old := indices[i]
		if not remap.has(old):
			remap[old] = order.size()
			order.append(old)
		new_indices[i] = remap[old]
	var copy := arrays.duplicate()
	for slot in Mesh.ARRAY_MAX:
		var data: Variant = arrays[slot]
		if data == null or slot == Mesh.ARRAY_INDEX:
			continue
		var width := 1
		if slot == Mesh.ARRAY_TANGENT:
			width = 4
		var picked: Variant = data.duplicate()
		picked.resize(order.size() * width)
		for i in order.size():
			for k in width:
				picked[i * width + k] = data[order[i] * width + k]
		copy[slot] = picked
	copy[Mesh.ARRAY_INDEX] = new_indices
	return copy
