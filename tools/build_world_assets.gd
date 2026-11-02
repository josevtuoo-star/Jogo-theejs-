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
		"tree_stump_01": 3000, "dead_tree_trunk": 4000, "rock_face_01": 6000}

var _noise := FastNoiseLite.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_noise.seed = 404
	_noise.frequency = 1.6
	var materials := _wreck_materials()
	for name in WRECKS:
		var mesh := _wreck(name, WRECKS[name], materials)
		_save(name, mesh)
	for name in PROPS:
		var parts := MeshTools.simplified(MeshTools.flatten(PH + "%s/%s_1k.gltf" % [name, name]), PROPS[name])
		var box := MeshTools.bounds(parts)
		var center := box.get_center()
		var xform := Transform3D(Basis.IDENTITY, Vector3(-center.x, -box.position.y, -center.z))
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
