extends SceneTree
## Ferramenta de produção: monta as três armas brancas.
##
## Uso: godot --headless --path . --script res://tools/build_weapons.gd
##
## Saída: resources/models/weapons/<id>.res (malha) e
## resources/weapons/<id>.tres (WeaponData). Convenção de todas as malhas:
## empunhadura na origem, cabo em +Y (na direção da cabeça da arma) e o lado
## que golpeia em +Z (ver PlayerEquipment.grip_offset).
##
## - Picareta: "Survival Tools" (Gar5546x, OpenGameArt, CC0), texturas PBR
##   reduzidas para 1K com AO, rugosidade e metal juntos numa textura ORM.
## - Machado de bombeiro: wooden_axe_02 (Poly Haven, CC0) no tamanho de um
##   machado de bombeiro (~88 cm), com a cabeça pintada de vermelho gasto e o
##   fio da lâmina em metal nu, como na referência.
## - Taco com pregos: baseball_bat (Poly Haven, CC0) com pregos enferrujados
##   cravados no barril (geometria gerada aqui: haste e cabeça de cada prego).

const OUT_MESH := "res://resources/models/weapons/"
const OUT_DATA := "res://resources/weapons/"
const PH := "res://assets/polyhaven/"

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 7707
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_MESH))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DATA))
	var results := [_pickaxe(), _fire_axe(), _nail_bat()]
	for data: WeaponData in results:
		var mesh_path := OUT_MESH + String(data.id) + ".res"
		ResourceSaver.save(data.mesh, mesh_path)
		data.mesh = load(mesh_path)
		var error := ResourceSaver.save(data, OUT_DATA + String(data.id) + ".tres")
		var box := data.mesh.get_aabb()
		print("%-10s %s  comprimento %.2f m  %s" % [data.id, error_string(error), box.size.y, box])
	quit()


# --- Picareta ----------------------------------------------------------------

func _pickaxe() -> WeaponData:
	var parts := MeshTools.flatten("res://assets/weapons/pickaxe/Pickaxe.fbx")
	var material := ORMMaterial3D.new()
	material.albedo_texture = load("res://assets/weapons/pickaxe/pickaxe_albedo.png")
	material.normal_enabled = true
	material.normal_texture = load("res://assets/weapons/pickaxe/pickaxe_normal.png")
	material.orm_texture = load("res://assets/weapons/pickaxe/pickaxe_orm.png")
	for part in parts:
		part[1] = material
	# Cabo em Y, cabeça cruzada em X: a cabeça passa a cruzar em Z (as pontas
	# golpeiam para a frente) e a pegada fica 12 cm acima do fim do cabo.
	var box := MeshTools.bounds(parts)
	var grip := Vector3(box.get_center().x, box.position.y + 0.12, box.get_center().z)
	var xform := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -grip)
	var data := WeaponData.new()
	data.id = &"picareta"
	data.display_name = "Picareta"
	data.mesh = MeshTools.build(parts, xform)
	data.mass = 2.6
	data.reach = 0.66
	data.hit_radius = 0.14
	data.light_damage = 26.0
	data.light_impulse = 16.0
	data.light_speed = 0.85
	data.light_recovery = 0.25
	data.heavy_min_damage = 38.0
	data.heavy_max_damage = 66.0
	data.heavy_min_impulse = 26.0
	data.heavy_max_impulse = 50.0
	data.heavy_recovery = 0.45
	data.impact_material = &"metal"
	return data


# --- Machado de bombeiro -------------------------------------------------------

func _fire_axe() -> WeaponData:
	var parts := MeshTools.flatten(PH + "models/wooden_axe_02/wooden_axe_02_1k.gltf")
	var scale := 1.25
	var box := MeshTools.bounds(parts)
	# A cabeça é a ponta do cabo onde a peça é larga em Z (a lâmina).
	var head_up := _wide_end_is_top(parts, box, 2)
	var bottom := box.position.y if head_up else box.end.y
	var direction := 1.0 if head_up else -1.0
	var grip := Vector3(box.get_center().x, bottom + direction * 0.07, 0.0)
	var flip := Basis.IDENTITY if head_up else Basis(Vector3.RIGHT, PI)
	var xform := Transform3D(flip.scaled(Vector3.ONE * scale), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -grip)
	# Pintura: a cabeça (acima do começo da lâmina) fica vermelha, exceto o fio.
	var max_z := _max_z(parts, xform)
	var head_start := _head_start(parts, xform, max_z * 0.45)
	var edge_z := max_z - 0.045 * scale
	var original: Material = parts[0][1]
	var paint := (original as BaseMaterial3D).duplicate() as BaseMaterial3D
	paint.albedo_color = Color(0.78, 0.06, 0.04)
	paint.roughness = 0.55
	paint.metallic = 0.25
	var split := _split_paint(parts, xform, head_start, edge_z, paint)
	var data := WeaponData.new()
	data.id = &"machado"
	data.display_name = "Machado de bombeiro"
	data.mesh = MeshTools.build(split, xform)
	data.mass = 2.8
	data.reach = 0.68
	data.hit_radius = 0.13
	data.light_damage = 30.0
	data.light_impulse = 18.0
	data.light_speed = 0.82
	data.light_recovery = 0.28
	data.heavy_min_damage = 44.0
	data.heavy_max_damage = 75.0
	data.heavy_min_impulse = 28.0
	data.heavy_max_impulse = 52.0
	data.heavy_recovery = 0.5
	data.impact_material = &"metal"
	return data


# --- Taco com pregos -----------------------------------------------------------

func _nail_bat() -> WeaponData:
	var parts := MeshTools.flatten(PH + "models/baseball_bat/baseball_bat_1k.gltf")
	var box := MeshTools.bounds(parts)
	var barrel_up := _wide_end_is_top(parts, box, -1)
	var bottom := box.position.y if barrel_up else box.end.y
	var direction := 1.0 if barrel_up else -1.0
	var grip := Vector3(box.get_center().x, bottom + direction * 0.09, box.get_center().z)
	var flip := Basis.IDENTITY if barrel_up else Basis(Vector3.RIGHT, PI)
	var xform := Transform3D(flip, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -grip)
	# Pregos: 16, cravados 3 cm no terço superior do barril, saindo 7-9 cm,
	# um pouco tortos (marteladas à mão).
	var nail_material := StandardMaterial3D.new()
	nail_material.albedo_texture = load(PH + "textures/rust_coarse_01/rust_coarse_01_albedo_1k.jpg")
	nail_material.uv1_scale = Vector3(0.15, 0.15, 0.15)
	nail_material.metallic = 0.55
	nail_material.roughness = 0.7
	var length := box.size.y
	var nails := SurfaceTool.new()
	nails.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 16:
		var height := length * _rng.randf_range(0.62, 0.95) - 0.09
		var radius := _radius_at(parts, xform, height)
		var angle := TAU * (i / 16.0) + _rng.randf_range(-0.25, 0.25)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var tilt := Basis(out.cross(Vector3.UP).normalized(), _rng.randf_range(-0.3, 0.3))
		var axis := (tilt * out).normalized()
		var protrude := _rng.randf_range(0.07, 0.09)
		var base := Vector3(0.0, height, 0.0) + out * (radius - 0.03)
		_add_cylinder(nails, base, axis, 0.0032, protrude + 0.03, 6)
		_add_cylinder(nails, base + out * 0.028, axis, 0.0085, 0.003, 8)
	nails.generate_normals()
	var nail_arrays := nails.commit_to_arrays()
	var data := WeaponData.new()
	data.id = &"taco"
	data.display_name = "Taco com pregos"
	var mesh := MeshTools.build(parts, xform)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, nail_arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, nail_material)
	data.mesh = mesh
	data.mass = 1.2
	data.reach = 0.72
	data.hit_radius = 0.15
	data.light_damage = 22.0
	data.light_impulse = 14.0
	data.light_speed = 1.05
	data.light_recovery = 0.16
	data.heavy_min_damage = 32.0
	data.heavy_max_damage = 54.0
	data.heavy_min_impulse = 22.0
	data.heavy_max_impulse = 42.0
	data.heavy_recovery = 0.32
	data.impact_material = &"madeira"
	return data


# --- Utilidades de malha -------------------------------------------------------

## A ponta larga (cabeça) está no alto do eixo Y? `axis` = 2 mede a largura
## em Z (lâmina); -1 mede o raio no plano XZ (barril do taco).
func _wide_end_is_top(parts: Array, box: AABB, axis: int) -> bool:
	var top := 0.0
	var bottom := 0.0
	var center := box.get_center()
	for part in parts:
		for v: Vector3 in part[0][Mesh.ARRAY_VERTEX]:
			var width := absf(v.z - center.z) if axis == 2 else Vector2(v.x - center.x, v.z - center.z).length()
			if v.y > box.end.y - box.size.y * 0.15:
				top = maxf(top, width)
			elif v.y < box.position.y + box.size.y * 0.15:
				bottom = maxf(bottom, width)
	return top >= bottom


## Altura (no espaço final) onde a cabeça começa: o vértice mais baixo que
## avança mais de `min_z` em Z (o cabo é curvo, então a medida é pela
## profundidade da lâmina, não pela distância ao eixo).
func _head_start(parts: Array, xform: Transform3D, min_z: float) -> float:
	var start := INF
	for part in parts:
		for v: Vector3 in part[0][Mesh.ARRAY_VERTEX]:
			var p := xform * v
			if p.z > min_z:
				start = minf(start, p.y)
	return start - 0.01


func _max_z(parts: Array, xform: Transform3D) -> float:
	var result := -INF
	for part in parts:
		for v: Vector3 in part[0][Mesh.ARRAY_VERTEX]:
			result = maxf(result, (xform * v).z)
	return result


## Divide em [madeira e fio, cabeça pintada] pela posição dos triângulos.
func _split_paint(parts: Array, xform: Transform3D, head_start: float, edge_z: float, paint: Material) -> Array:
	var result := []
	for part in parts:
		var arrays: Array = part[0]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		var painted := PackedInt32Array()
		for t in indices.size() / 3:
			var c := (xform * vertices[indices[t * 3]] + xform * vertices[indices[t * 3 + 1]] + xform * vertices[indices[t * 3 + 2]]) / 3.0
			if c.y > head_start and c.z < edge_z:
				painted.append_array([indices[t * 3], indices[t * 3 + 1], indices[t * 3 + 2]])
			else:
				keep.append_array([indices[t * 3], indices[t * 3 + 1], indices[t * 3 + 2]])
		for pair in [[keep, part[1]], [painted, paint]]:
			if (pair[0] as PackedInt32Array).is_empty():
				continue
			var copy := arrays.duplicate()
			copy[Mesh.ARRAY_INDEX] = pair[0]
			result.append([copy, pair[1]])
	return result


## Raio do taco numa altura (espaço final), pela maior distância ao eixo.
func _radius_at(parts: Array, xform: Transform3D, height: float) -> float:
	var radius := 0.0
	for part in parts:
		for v: Vector3 in part[0][Mesh.ARRAY_VERTEX]:
			var p := xform * v
			if absf(p.y - height) < 0.02:
				radius = maxf(radius, Vector2(p.x, p.z).length())
	return radius


func _add_cylinder(st: SurfaceTool, base: Vector3, axis: Vector3, radius: float, length: float, sides: int) -> void:
	var side_a := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var side_b := axis.cross(side_a).normalized()
	var top := base + axis * length
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := (side_a * cos(a0) + side_b * sin(a0)) * radius
		var p1 := (side_a * cos(a1) + side_b * sin(a1)) * radius
		for v in [base + p0, top + p0, top + p1, base + p0, top + p1, base + p1, top, top + p1, top + p0]:
			st.set_uv(Vector2(v.x + v.z, v.y) * 4.0)
			st.add_vertex(v)
