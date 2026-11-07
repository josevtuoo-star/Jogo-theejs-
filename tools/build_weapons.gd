extends SceneTree
## Ferramenta de produção: monta as armas brancas e ferramentas.
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
## - Etapa 9 (feitas na bancada): machado, picareta e faca de pedra, lança e
##   tocha — cabo de galho com casca (textura pine_bark, Poly Haven, CC0),
##   pedra lascada (malha irregular gerada aqui, textura de rocha projetada) e
##   amarração de corda. Facão (machete) e pé de cabra (crowbar_01) são da
##   Poly Haven (CC0).

const OUT_MESH := "res://resources/models/weapons/"
const OUT_DATA := "res://resources/weapons/"
const PH := "res://assets/polyhaven/"

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 7707
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_MESH))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DATA))
	var results := [_pickaxe(), _fire_axe(), _nail_bat(), _stone_axe(), _stone_pickaxe(), _stone_knife(),
			_spear(), _torch(), _machete(), _crowbar()]
	# Empunhadura e golpe próprios (etapa 10): machados, picaretas e pé de
	# cabra descem de cima para baixo com as duas mãos; a lança é estocada;
	# taco com as duas mãos juntas; faca, facão e tocha numa mão só.
	# [golpe, duas mãos, mão esquerda em relação à direita, direita sobe no cabo]
	var style := {"machado": [&"mine", true, -0.16, 0.2], "picareta": [&"mine", true, -0.16, 0.2],
			"machado_pedra": [&"mine", true, -0.13, 0.15], "picareta_pedra": [&"mine", true, -0.13, 0.15],
			"pe_de_cabra": [&"mine", true, -0.14, 0.16], "taco": [&"weapon_swing_a", true, -0.1, 0.12],
			"lanca": [&"punch_cross", true, -0.42, 0.0]}
	for data: WeaponData in results:
		if style.has(String(data.id)):
			var spec: Array = style[String(data.id)]
			data.light_clip = spec[0]
			data.two_handed = spec[1]
			data.offhand_offset = spec[2]
			data.grip_shift = spec[3]
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


# --- Ferramentas de pedra, lança e tocha (etapa 9) ------------------------------

var _bark_material: StandardMaterial3D
var _rope_material: StandardMaterial3D


func _bark() -> StandardMaterial3D:
	if _bark_material == null:
		_bark_material = StandardMaterial3D.new()
		_bark_material.albedo_texture = load(PH + "textures/pine_bark/pine_bark_albedo_1k.jpg")
		_bark_material.normal_enabled = true
		_bark_material.normal_texture = load(PH + "textures/pine_bark/pine_bark_normal_1k.jpg")
		_bark_material.albedo_color = Color(0.85, 0.78, 0.68)
		_bark_material.uv1_scale = Vector3(0.6, 0.6, 0.6)
		_bark_material.roughness = 0.9
	return _bark_material


func _rope() -> StandardMaterial3D:
	if _rope_material == null:
		_rope_material = StandardMaterial3D.new()
		_rope_material.albedo_color = Color(0.42, 0.33, 0.22)
		_rope_material.roughness = 1.0
	return _rope_material


## Galho reto (cabo) de `bottom` a `top` no eixo Y.
func _stick_part(bottom: float, top: float, radius: float) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_cylinder(st, Vector3(0.0, bottom, 0.0), Vector3.UP, radius, top - bottom, 9)
	_add_cylinder(st, Vector3(0.0, top, 0.0), Vector3.DOWN, radius, top - bottom, 9)
	st.generate_normals()
	return [st.commit_to_arrays(), _bark()]


## Amarração: voltas de corda em torno do cabo.
func _rope_part(y: float, radius: float, height: float) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var turns := 4
	for i in turns:
		var yy := y - height * 0.5 + height * (i + 0.5) / turns
		_add_cylinder(st, Vector3(0.0, yy - height / turns * 0.42, 0.0), Vector3.UP, radius + 0.004, height / turns * 0.84, 10)
		_add_cylinder(st, Vector3(0.0, yy + height / turns * 0.42, 0.0), Vector3.DOWN, radius + 0.004, height / turns * 0.84, 10)
	st.generate_normals()
	return [st.commit_to_arrays(), _rope()]


## Pedra lascada: esfera deformada por ruído, achatada em `size` e afinada
## (`taper_axis`: 1 = afina para +Y, 2 = afina nas duas pontas de Z).
func _rock_part(center: Vector3, size: Vector3, seed_value: int, material: Material, taper_axis: int = 0) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 3.0
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 14
	sphere.rings = 8
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		var v := vertices[index]
		var bump := 1.0 + noise.get_noise_3dv(v * 2.0) * 0.35
		var p := v * 2.0 * bump
		# Faces de lascamento: o ruído é quantizado em facetas.
		p = p.snapped(Vector3.ONE * 0.18)
		if taper_axis == 1 and p.y > 0.0:
			var t := clampf(p.y, 0.0, 1.0)
			p.x *= 1.0 - t * 0.75
			p.z *= 1.0 - t * 0.55
		elif taper_axis == 2:
			var t := clampf(absf(p.z), 0.0, 1.0)
			p.x *= 1.0 - t * 0.7
			p.y *= 1.0 - t * 0.7
		st.add_vertex(center + p * size * 0.5)
	st.generate_normals()
	return [st.commit_to_arrays(), material]


func _stone() -> Material:
	return load("res://resources/models/world/pedra_solta.tres")


func _stone_axe() -> WeaponData:
	var parts := [_stick_part(-0.08, 0.56, 0.017), _rock_part(Vector3(0.0, 0.47, 0.06), Vector3(0.05, 0.11, 0.17), 51, _stone()),
			_rope_part(0.47, 0.017, 0.07)]
	var data := _numbers(&"machado_pedra", "Machado de pedra", MeshTools.build(parts), 1.3, 0.55, 0.12,
			[18.0, 12.0, 0.95, 0.24], [26.0, 44.0, 18.0, 36.0, 0.42], &"madeira")
	return data


func _stone_pickaxe() -> WeaponData:
	var parts := [_stick_part(-0.08, 0.58, 0.017), _rock_part(Vector3(0.0, 0.5, 0.0), Vector3(0.05, 0.07, 0.38), 52, _stone(), 2),
			_rope_part(0.5, 0.017, 0.06)]
	return _numbers(&"picareta_pedra", "Picareta de pedra", MeshTools.build(parts), 1.5, 0.58, 0.12,
			[18.0, 12.0, 0.9, 0.26], [26.0, 46.0, 18.0, 38.0, 0.45], &"madeira")


func _stone_knife() -> WeaponData:
	var parts := [_stick_part(-0.03, 0.09, 0.015), _rope_part(0.04, 0.015, 0.1),
			_rock_part(Vector3(0.0, 0.17, 0.004), Vector3(0.014, 0.17, 0.05), 53, _stone(), 1)]
	return _numbers(&"faca_pedra", "Faca de pedra", MeshTools.build(parts), 0.3, 0.2, 0.1,
			[14.0, 7.0, 1.35, 0.1], [20.0, 30.0, 10.0, 18.0, 0.22], &"madeira")


func _spear() -> WeaponData:
	var parts := [_stick_part(-0.55, 1.06, 0.017), _rope_part(1.04, 0.017, 0.07),
			_rock_part(Vector3(0.0, 1.13, 0.0), Vector3(0.022, 0.15, 0.055), 54, _stone(), 1)]
	return _numbers(&"lanca", "Lança", MeshTools.build(parts), 1.4, 1.2, 0.1,
			[24.0, 16.0, 0.95, 0.25], [34.0, 56.0, 22.0, 40.0, 0.45], &"madeira")


func _torch() -> WeaponData:
	var coal: Material = load("res://resources/models/world/carvao_pedaco.tres")
	var parts := [_stick_part(-0.08, 0.42, 0.019), _rope_part(0.38, 0.019, 0.05),
			_rock_part(Vector3(0.0, 0.45, 0.0), Vector3(0.075, 0.11, 0.075), 55, coal)]
	return _numbers(&"tocha", "Tocha", MeshTools.build(parts), 0.5, 0.42, 0.1,
			[8.0, 6.0, 1.1, 0.18], [12.0, 18.0, 8.0, 14.0, 0.3], &"madeira")


func _machete() -> WeaponData:
	var parts := MeshTools.flatten(PH + "models/machete/machete_1k.gltf")
	var box := MeshTools.bounds(parts)
	var blade_up := _wide_end_is_top(parts, box, 2)
	var bottom := box.position.y if blade_up else box.end.y
	var direction := 1.0 if blade_up else -1.0
	var grip := Vector3(box.get_center().x, bottom + direction * 0.07, box.get_center().z)
	var flip := Basis.IDENTITY if blade_up else Basis(Vector3.RIGHT, PI)
	var xform := Transform3D(flip, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -grip)
	return _numbers(&"facao", "Facão", MeshTools.build(parts, xform), 0.7, 0.62, 0.1,
			[26.0, 13.0, 1.15, 0.16], [34.0, 56.0, 18.0, 34.0, 0.3], &"metal")


func _crowbar() -> WeaponData:
	var parts := MeshTools.flatten(PH + "models/crowbar_01/crowbar_01_1k.gltf")
	var box := MeshTools.bounds(parts)
	var hook_up := _wide_end_is_top(parts, box, 2)
	var bottom := box.position.y if hook_up else box.end.y
	var direction := 1.0 if hook_up else -1.0
	var grip := Vector3(box.get_center().x, bottom + direction * 0.06, box.get_center().z)
	var flip := Basis.IDENTITY if hook_up else Basis(Vector3.RIGHT, PI)
	var xform := Transform3D(flip.scaled(Vector3.ONE * 1.3), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -grip)
	return _numbers(&"pe_de_cabra", "Pé de cabra", MeshTools.build(parts, xform), 1.6, 0.62, 0.12,
			[25.0, 16.0, 0.9, 0.24], [38.0, 64.0, 26.0, 48.0, 0.45], &"metal")


## light = [dano, impulso, velocidade, recuperação];
## heavy = [dano mín, dano máx, impulso mín, impulso máx, recuperação].
func _numbers(id: StringName, display: String, mesh: Mesh, mass: float, reach: float, radius: float,
		light: Array, heavy: Array, sound: StringName) -> WeaponData:
	var data := WeaponData.new()
	data.id = id
	data.display_name = display
	data.mesh = mesh
	data.mass = mass
	data.reach = reach
	data.hit_radius = radius
	data.light_damage = light[0]
	data.light_impulse = light[1]
	data.light_speed = light[2]
	data.light_recovery = light[3]
	data.heavy_min_damage = heavy[0]
	data.heavy_max_damage = heavy[1]
	data.heavy_min_impulse = heavy[2]
	data.heavy_max_impulse = heavy[3]
	data.heavy_recovery = heavy[4]
	data.impact_material = sound
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
