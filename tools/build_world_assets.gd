extends SceneTree
## Ferramenta de produção: prepara as malhas que o mundo procedural espalha.
##
## Uso: godot --headless --path . --script res://tools/build_world_assets.gd
##
## Saída: resources/models/world/<nome>.res, uma malha por objeto (todas as
## partes do modelo juntas, base em y = 0), prontas para MultiMesh.
##
## - Carcaças: "3D Vehicles Pack" (mehrasaur, CC0), modelos de argila sem UV.
##   Cada um é levado ao tamanho real (escala por eixo: os modelos são
##   estilizados, baixos e curtos), amassado de leve por ruído e dividido em
##   lataria (shader de pintura desbotada e ferrugem, cor por instância),
##   vidros escuros (só carros e utilitários) e borracha dos pneus.
## - Destroços e natureza: modelos da Poly Haven (CC0) juntos numa malha, com
##   níveis de detalhe gerados (a vegetação aparece às centenas).

const OUT := "res://resources/models/world/"
const PH := "res://assets/polyhaven/models/"

## nome: [comprimento, largura, altura (m), tem vidros, faixa da cintura]
const WRECKS := {
	"car_01": [4.0, 1.75, 1.5, true, 0.58],
	"car_02": [4.6, 1.8, 1.45, true, 0.6],
	"car_03": [4.9, 1.95, 2.1, true, 0.55],
	"car_04": [4.0, 1.75, 1.5, true, 0.58],
	"jeep_01": [4.2, 1.85, 1.85, true, 0.58],
	"jeep_02": [4.2, 1.85, 1.85, true, 0.58],
	"pickup": [5.3, 1.9, 1.85, true, 0.6],
	"truck_01": [7.6, 2.4, 3.2, false, 0.0],
	"truck_02": [7.8, 2.5, 3.3, false, 0.0],
	"truck_03": [7.8, 2.5, 3.4, false, 0.0],
	"truck_04": [5.8, 2.2, 2.9, false, 0.0],
	"truck_05": [6.2, 2.3, 2.8, false, 0.0],
	"bus": [10.5, 2.55, 3.1, false, 0.0],
}

## Modelos da Poly Haven usados pelo mundo (base no chão, centrados).
## nome: máximo de triângulos (os scans têm até 100 mil; no celular, às
## dezenas na tela, o detalhe fica na textura e no mapa de normais).
const PROPS := {"covered_car": 6000, "concrete_road_barrier_02": 1500, "old_tyre": 1500,
		"rusted_wheel_rim_01": 1500, "vintage_suitcase": 2000, "trashbag": 1500,
		"plastic_jerrycan": 1200, "metal_jerrycan_green": 1500, "Barrel_02": 1500,
		"can_rusted": 400, "dry_branches_medium_01": 3000, "wooden_military_crate": 2000,
		"fern_02": 3000, "shrub_03": 3000, "boulder_01": 4000, "rock_moss_set_01": 6000,
		"tree_stump_01": 3000, "dead_tree_trunk": 4000,
		# Etapa 9: vegetação dos biomas e ruas das vilas e cidades.
		"shrub_02": 2500, "shrub_04": 2500, "weed_plant_02": 2000,
		"street_lamp_01": 2500, "metal_trash_can": 1500}

## Pacotes com variantes lado a lado: quais nós usar (etapa 9).
const PICK := {"shrub_02": ["shrub_02_b"], "weed_plant_02": ["weed_plant_02_a", "weed_plant_02_b"],
		"metal_trash_can": ["metal_trash_can_rust"]}
## Escala para o tamanho real (os modelos vêm em escala reduzida).
const SCALE := {"weed_plant_02": 5.5, "shrub_04": 3.2}

var _noise := FastNoiseLite.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_noise.seed = 404
	_noise.frequency = 1.6
	_procedural()
	if "procedural" in OS.get_cmdline_user_args():
		quit()
		return
	var materials := _wreck_materials()
	for name in WRECKS:
		var mesh := _wreck(name, WRECKS[name], materials)
		_save(name, mesh)
	for name in PROPS:
		var parts := MeshTools.simplified(MeshTools.flatten(PH + "%s/%s_1k.gltf" % [name, name], PICK.get(name, [])), PROPS[name])
		var box := MeshTools.bounds(parts)
		var center := box.get_center()
		var factor: float = SCALE.get(name, 1.0)
		var xform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * factor), Vector3.ZERO) \
				* Transform3D(Basis.IDENTITY, Vector3(-center.x, -box.position.y, -center.z))
		_save(name, MeshTools.build(parts, xform, true))
	quit()


func _save(name: String, mesh: Mesh) -> void:
	var path := OUT + name + ".res"
	var error := ResourceSaver.save(mesh, path)
	var box := mesh.get_aabb()
	var triangles := 0
	for s in mesh.get_surface_count():
		triangles += mesh.surface_get_array_index_len(s) / 3 if mesh.surface_get_array_index_len(s) > 0 else mesh.surface_get_array_len(s) / 3
	print("%-26s %s  %5.2f × %4.2f × %5.2f m  %6d triângulos" % [name, error_string(error), box.size.x, box.size.y, box.size.z, triangles])


func _wreck_materials() -> Array[Material]:
	var body := ShaderMaterial.new()
	body.shader = load("res://resources/materials/wreck.gdshader")
	body.set_shader_parameter("rust_albedo", load("res://assets/polyhaven/textures/rust_coarse_01/rust_coarse_01_albedo_1k.jpg"))
	body.set_shader_parameter("paint_albedo", load("res://assets/polyhaven/textures/rusty_painted_metal/rusty_painted_metal_albedo_1k.jpg"))
	ResourceSaver.save(body, OUT + "wreck_body.tres")
	body = load(OUT + "wreck_body.tres")
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.06, 0.06)
	glass.roughness = 0.25
	glass.metallic = 0.4
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.07, 0.065, 0.06)
	rubber.roughness = 0.95
	return [body, glass, rubber]


func _wreck(name: String, spec: Array, materials: Array[Material]) -> ArrayMesh:
	var parts := MeshTools.flatten("res://assets/vehicles/%s.fbx" % name)
	var box := MeshTools.bounds(parts)
	var center := box.get_center()
	var scale := Vector3(spec[1] / box.size.x, spec[2] / box.size.y, spec[0] / box.size.z)
	var xform := Transform3D(Basis.from_scale(scale), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(-center.x, -box.position.y, -center.z))
	var length: float = spec[0]
	var width: float = spec[1]
	var height: float = spec[2]
	var has_glass: bool = spec[3]
	var belt: float = spec[4] * height
	# Três superfícies: lataria, vidro, borracha.
	var tools: Array[SurfaceTool] = []
	for i in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
	for part in parts:
		var arrays := MeshTools.transformed(part[0], xform)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices := MeshTools.indices_of(arrays)
		for t in indices.size() / 3:
			var ids := [indices[t * 3], indices[t * 3 + 1], indices[t * 3 + 2]]
			var a: Vector3 = vertices[ids[0]]
			var b: Vector3 = vertices[ids[1]]
			var c: Vector3 = vertices[ids[2]]
			var middle := (a + b + c) / 3.0
			var face := (b - a).cross(c - a)
			var n := face.normalized() if face.length_squared() > 1e-12 else Vector3.UP
			var surface := 0
			if has_glass and middle.y > belt and middle.y < height * 0.97 and absf(n.y) < 0.72:
				surface = 1
			elif middle.y < height * 0.34 and absf(n.x) > 0.6 and absf(middle.x) > width * 0.36:
				surface = 2
			for id in ids:
				var v: Vector3 = vertices[id]
				tools[surface].set_normal(normals[id])
				tools[surface].add_vertex(v + _dent(v, length))
	var mesh := ArrayMesh.new()
	for i in 3:
		var arrays := tools[i].commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[i])
	return mesh


## Amassado: deslocamento por um campo de ruído (o mesmo ponto sempre se
## move igual, então arestas com vértices duplicados não abrem frestas).
func _dent(v: Vector3, length: float) -> Vector3:
	var p := v * (4.0 / length)
	return Vector3(_noise.get_noise_3dv(p), _noise.get_noise_3dv(p + Vector3(31.0, 0.0, 0.0)) * 1.4,
			_noise.get_noise_3dv(p + Vector3(0.0, 0.0, 57.0))) * 0.035


# --- Malhas procedurais das cavernas e dos recursos (etapa 8) ------------------

const CAVE_ROCK := "res://assets/polyhaven/textures/cliff_side/cliff_side_albedo_1k.jpg"


func _rock_material(file: String, tint: Color, fleck: Color, amount: float, metallic: float, roughness: float, wet: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://resources/materials/cave_rock.gdshader")
	material.set_shader_parameter("rock_albedo", load(CAVE_ROCK))
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("fleck_color", fleck)
	material.set_shader_parameter("fleck_amount", amount)
	material.set_shader_parameter("fleck_metallic", metallic)
	material.set_shader_parameter("fleck_roughness", roughness)
	material.set_shader_parameter("wetness", wet)
	ResourceSaver.save(material, OUT + file)
	return load(OUT + file)


func _procedural() -> void:
	var formation := _rock_material("rocha_caverna.tres", Color(0.95, 0.9, 0.84), Color.BLACK, 0.0, 0.0, 0.8, 0.45)
	var coal := _rock_material("minerio_carvao.tres", Color(0.5, 0.48, 0.46), Color(0.03, 0.03, 0.035), 0.7, 0.15, 0.3, 0.2)
	var iron := _rock_material("minerio_ferro.tres", Color(0.55, 0.5, 0.46), Color(0.34, 0.14, 0.06), 0.62, 0.1, 0.7, 0.2)
	var stone := _rock_material("pedra_solta.tres", Color(1.0, 0.97, 0.92), Color.BLACK, 0.0, 0.0, 0.85, 0.1)
	_save("estalagmite", _spire(1.7, 0.42, 1.0, 11, formation))
	_save("estalactite", _spire(1.4, 0.3, -1.0, 12, formation))
	_save("minerio_carvao", _lump(0.75, Vector3(1.0, 0.95, 0.9), 0.15, 21, coal, 3))
	_save("minerio_ferro", _lump(0.75, Vector3(1.0, 0.95, 0.85), 0.15, 22, iron, 3))
	# Pedaços coletáveis (cabem na mão).
	_save("pedaco_pedra", _lump(0.11, Vector3(1.0, 0.75, 0.9), 0.3, 31, stone))
	# Pedaços já separados da rocha: quase só mineral.
	var coal_piece := _rock_material("carvao_pedaco.tres", Color(0.12, 0.12, 0.13), Color(0.02, 0.02, 0.025), 0.75, 0.2, 0.25, 0.0)
	var iron_piece := _rock_material("ferro_pedaco.tres", Color(0.62, 0.36, 0.26), Color(0.32, 0.14, 0.07), 0.7, 0.15, 0.7, 0.0)
	_save("pedaco_carvao", _lump(0.09, Vector3(1.0, 0.8, 0.85), 0.3, 32, coal_piece))
	_save("pedaco_ferro", _lump(0.1, Vector3(1.0, 0.8, 0.9), 0.3, 33, iron_piece))
	_save("tora", _log(0.85, 0.13))
	# Rochedos da superfície (substituem o scan "rock_face_01", uma fatia de
	# penhasco com laterais cortadas retas que, nas encostas, ficava
	# flutuando): blocos arredondados e irregulares, textura projetada nos
	# três eixos (sem esticar), musgo no topo. Base plana em y = 0.
	var boulder := _rock_material("rocha_superficie.tres", Color(0.8, 0.79, 0.75), Color.BLACK, 0.0, 0.0, 0.85, 0.05)
	boulder.set_shader_parameter("moss_amount", 0.55)
	boulder.set_shader_parameter("desaturate", 0.7)
	boulder.set_shader_parameter("tile", 1.8)
	ResourceSaver.save(boulder, OUT + "rocha_superficie.tres")
	_save("rochedo_0", _lump(1.2, Vector3(1.35, 0.8, 1.0), 0.24, 41, boulder, 3))
	_save("rochedo_1", _lump(1.1, Vector3(1.0, 1.0, 0.9), 0.3, 42, boulder, 3))
	_save("rochedo_2", _lump(1.3, Vector3(1.6, 0.6, 1.1), 0.2, 43, boulder, 3))
	_items_and_armor()
	_town_material()


## Material das fachadas das vilas e cidades (resources/materials/building.gdshader).
func _town_material() -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://resources/materials/building.gdshader")
	var textures := {"brick_albedo": "brick_wall_02", "plaster_albedo": "worn_plaster_wall", "concrete_albedo": "concrete_wall_004",
			"planks_albedo": "weathered_planks", "roof_albedo": "grey_roof_01", "tin_albedo": "rusty_corrugated_iron"}
	for parameter: String in textures:
		var folder: String = textures[parameter]
		material.set_shader_parameter(parameter, load("res://assets/polyhaven/textures/%s/%s_albedo_1k.jpg" % [folder, folder]))
	ResourceSaver.save(material, "res://resources/materials/building.tres")


# --- Itens feitos na bancada e armaduras (etapa 9) -------------------------------

func _pbr(folder: String, scale: float = 1.0) -> ORMMaterial3D:
	var base := "res://assets/polyhaven/textures/%s/%s_" % [folder, folder]
	var material := ORMMaterial3D.new()
	material.albedo_texture = load(base + "albedo_1k.jpg")
	material.normal_enabled = true
	material.normal_texture = load(base + "normal_1k.jpg")
	material.orm_texture = load(base + "arm_1k.jpg")
	material.uv1_scale = Vector3.ONE * scale
	return material


func _box_arrays(size: Vector3, at: Vector3 = Vector3.ZERO, rotation: Basis = Basis.IDENTITY) -> Array:
	var box := BoxMesh.new()
	box.size = size
	return MeshTools.transformed(box.get_mesh_arrays(), Transform3D(rotation, at))


func _items_and_armor() -> void:
	var planks := _pbr("weathered_planks", 0.5)
	ResourceSaver.save(planks, OUT + "tabua_material.tres")
	planks = load(OUT + "tabua_material.tres")
	# Tábua serrada (60 × 11 × 2,5 cm), base em y = 0.
	_save("tabua", MeshTools.build([[_box_arrays(Vector3(0.11, 0.025, 0.6), Vector3(0.0, 0.0125, 0.0)), planks]]))
	# Graveto: galho fino com casca.
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = load("res://assets/polyhaven/textures/pine_bark/pine_bark_albedo_1k.jpg")
	bark.albedo_color = Color(0.85, 0.78, 0.68)
	bark.roughness = 0.9
	var stick := CylinderMesh.new()
	stick.top_radius = 0.011
	stick.bottom_radius = 0.014
	stick.height = 0.5
	stick.radial_segments = 7
	stick.rings = 1
	_save("graveto", MeshTools.build([[MeshTools.transformed(stick.get_mesh_arrays(),
			Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.014, 0.0))), bark]]))
	# Armaduras de sucata: chapa pintada e enferrujada presa por tiras de
	# couro. Malhas no espaço do esqueleto (metros, personagem olhando para
	# +Z), centradas na origem; ArmorVisuals as prende aos ossos.
	var plate := _pbr("rusty_painted_metal", 0.6)
	plate.metallic_specular = 0.6
	# Chapa pintada de verde-oliva, gasta (a foto é de tinta descascada).
	plate.albedo_color = Color(0.5, 0.56, 0.46)
	ResourceSaver.save(plate, OUT + "armadura_material.tres")
	plate = load(OUT + "armadura_material.tres")
	var strap := StandardMaterial3D.new()
	strap.albedo_color = Color(0.2, 0.15, 0.1)
	strap.roughness = 0.85
	var dome := SphereMesh.new()
	dome.radius = 0.14
	dome.height = 0.14
	dome.is_hemisphere = true
	dome.radial_segments = 20
	dome.rings = 8
	var brim := CylinderMesh.new()
	brim.top_radius = 0.15
	brim.bottom_radius = 0.165
	brim.height = 0.014
	brim.radial_segments = 20
	brim.rings = 1
	_save("armadura_capacete", MeshTools.build([
		[MeshTools.transformed(dome.get_mesh_arrays(), Transform3D(Basis.from_scale(Vector3(1.0, 0.95, 1.12)), Vector3.ZERO)), plate],
		[MeshTools.transformed(brim.get_mesh_arrays(), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.12)), Vector3(0.0, 0.004, 0.0))), plate],
		[_box_arrays(Vector3(0.012, 0.11, 0.02), Vector3(0.128, -0.05, 0.02)), strap],
		[_box_arrays(Vector3(0.012, 0.11, 0.02), Vector3(-0.128, -0.05, 0.02)), strap],
	]))
	_save("armadura_colete", MeshTools.build([
		[_box_arrays(Vector3(0.34, 0.36, 0.028), Vector3(0.0, 0.0, 0.135), Basis(Vector3.RIGHT, -0.12)), plate],
		[_box_arrays(Vector3(0.34, 0.38, 0.028), Vector3(0.0, 0.0, -0.125), Basis(Vector3.RIGHT, 0.08)), plate],
		[_box_arrays(Vector3(0.06, 0.02, 0.28), Vector3(0.11, 0.2, 0.0)), strap],
		[_box_arrays(Vector3(0.06, 0.02, 0.28), Vector3(-0.11, 0.2, 0.0)), strap],
		[_box_arrays(Vector3(0.025, 0.05, 0.26), Vector3(0.19, -0.1, 0.0)), strap],
		[_box_arrays(Vector3(0.025, 0.05, 0.26), Vector3(-0.19, -0.1, 0.0)), strap],
	]))
	_save("armadura_joelheira", MeshTools.build([
		[_box_arrays(Vector3(0.1, 0.13, 0.03), Vector3(0.0, 0.0, 0.0), Basis(Vector3.RIGHT, 0.1)), plate],
		[_box_arrays(Vector3(0.13, 0.025, 0.12), Vector3(0.0, -0.035, -0.04)), strap],
	]))
	_save("armadura_bota", MeshTools.build([
		[_box_arrays(Vector3(0.105, 0.06, 0.1), Vector3(0.0, 0.0, 0.0), Basis(Vector3.RIGHT, -0.25)), plate],
		[_box_arrays(Vector3(0.12, 0.03, 0.05), Vector3(0.0, 0.03, -0.06)), strap],
	]))


## Estalagmite (direction 1, base em y = 0, ponta para cima) ou estalactite
## (direction -1, presa no teto em y = 0, ponta para baixo): cone irregular
## com anéis de crescimento.
func _spire(height: float, radius: float, direction: float, seed_value: int, material: Material) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 2.2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 12
	var rings := 10
	var points := []
	for r in rings + 1:
		var t := float(r) / rings
		var ring := []
		var profile := radius * pow(1.0 - t, 0.85) + 0.015
		# Anéis de crescimento: o raio pulsa ao longo da altura.
		profile *= 1.0 + 0.08 * sin(t * 23.0)
		for k in sides:
			var angle := TAU * k / sides
			var dir := Vector3(cos(angle), 0.0, sin(angle))
			var y := t * height * direction
			var bump := 1.0 + noise.get_noise_3d(dir.x * 2.0, y * 1.5, dir.z * 2.0) * 0.28
			ring.append(dir * profile * bump + Vector3(0.0, y, 0.0) + Vector3(0.04, 0.0, 0.03) * t * t * direction)
		points.append(ring)
	var tip := Vector3(0.0, height * direction * 1.04, 0.0)
	for r in rings:
		for k in sides:
			var a: Vector3 = points[r][k]
			var b: Vector3 = points[r][(k + 1) % sides]
			var c: Vector3 = points[r + 1][(k + 1) % sides]
			var d: Vector3 = points[r + 1][k]
			_quad_faces(st, a, b, c, d, direction > 0.0)
	for k in sides:
		var a: Vector3 = points[rings][k]
		var b: Vector3 = points[rings][(k + 1) % sides]
		if direction > 0.0:
			st.add_vertex(a); st.add_vertex(tip); st.add_vertex(b)
		else:
			st.add_vertex(a); st.add_vertex(b); st.add_vertex(tip)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, material)
	return mesh


func _quad_faces(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: bool) -> void:
	if outward:
		for v in [a, c, b, a, d, c]:
			st.add_vertex(v)
	else:
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)


## Bloco de rocha irregular: icosaedro subdividido, achatado e deformado por
## ruído; base achatada para assentar no chão.
func _lump(radius: float, squash: Vector3, roughness: float, seed_value: int, material: Material, subdivisions: int = 2) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.4
	noise.fractal_octaves = 3
	var sphere := _icosphere(subdivisions)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var moved := {}
	for v: Vector3 in sphere[0]:
		var bump := 1.0 + noise.get_noise_3dv(v * 1.3) * roughness * 2.0
		var p := v * bump * radius * squash
		p.y = maxf(p.y, -radius * squash.y * 0.55)
		moved[v] = p + Vector3(0.0, radius * squash.y * 0.55, 0.0)
	var indices: PackedInt32Array = sphere[1]
	var vertices: PackedVector3Array = sphere[0]
	for i in indices.size():
		st.add_vertex(moved[vertices[indices[i]]])
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, material)
	return mesh


## Icosaedro subdividido (vértices unitários e índices).
func _icosphere(subdivisions: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var vertices := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in vertices.size():
		vertices[i] = vertices[i].normalized()
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
		[11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for level in subdivisions:
		var cache := {}
		var next := []
		for f in faces:
			var m := []
			for e in [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]]:
				var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				if not cache.has(key):
					cache[key] = vertices.size()
					vertices.append(((vertices[e[0]] + vertices[e[1]]) * 0.5).normalized())
				m.append(cache[key])
			next.append_array([[f[0], m[0], m[2]], [f[1], m[1], m[0]], [f[2], m[2], m[1]], [m[0], m[1], m[2]]])
		faces = next
	var indices := PackedInt32Array()
	for f in faces:
		# Ordem invertida: frente horária no Godot, vista de fora.
		indices.append_array([f[0], f[2], f[1]])
	return [vertices, indices]


## Tora de madeira: cilindro de casca de pinheiro com os topos claros.
func _log(length: float, radius: float) -> ArrayMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius * 1.05
	cylinder.height = length
	cylinder.radial_segments = 10
	cylinder.rings = 1
	var arrays := cylinder.get_mesh_arrays()
	# Deitada ao longo de X, apoiada no chão.
	var xform := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, radius, 0.0))
	arrays = MeshTools.transformed(arrays, xform)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var bark := ORMMaterial3D.new()
	var folder := "res://assets/polyhaven/textures/pine_bark/pine_bark_"
	bark.albedo_texture = load(folder + "albedo_1k.jpg")
	bark.normal_enabled = true
	bark.normal_texture = load(folder + "normal_1k.jpg")
	bark.orm_texture = load(folder + "arm_1k.jpg")
	bark.uv1_scale = Vector3(1.0, 1.5, 1.0)
	mesh.surface_set_material(0, bark)
	return mesh

