extends SceneTree
# Separa o FBX do pacote (e as armas) em objetos prontos: res://assets/modelos/<nome>.tscn
# (malhas em .res, materiais corrigidos, colisão) — o jogo não precisa importar o FBX inteiro.

const FBX := "res://assets/cenario/Vegetation.fbx"
const OUT := "res://assets/modelos/"
var src: Node3D
var xf := {} # nome do nó -> transformação global no FBX

# nome: [partes], colisão, opções
# colisões: "trimesh" (formato exato, estático), "convex", "box", "trunk" (tronco de árvore), "none"
var PREFABS := {
	# construções
	"torre": [["Cube", "Cube_009", "Cube_016", "Cube_046", "Cube_022", "Cube_034", "Cube_035", "Cube_036",
		"Windows", "Windows_001", "Windows_002", "Windows_003", "Windows_004", "Windows_005", "Windows_006", "Windows_007",
		"Windows_008", "Windows_009", "Windows_010", "Windows_011", "Windows_012", "Windows_013", "Windows_014",
		"Windows_015", "Windows_016", "Windows_017", "Windows_018", "Windows_019", "Door",
		"Bed", "Kitchen_table_001", "Stove", "oven", "shelve_001", "Table_001", "Cube_003", "Cylinder_015", "drawer_001",
		"drawer_d_001", "drawer_01_001", "Archivist_001", "Archivist_002", "Archivist_003", "Archivist_004", "Archivist_005",
		"Photos_003", "Photos_004", "Photos_005", "firewood_013", "firewood_01_001"], "trimesh"],
	"cabana": [["hut", "Cube_018", "Cube_024", "Cube_025", "Cube_029", "Cube_030", "Windows_040", "Windows_041",
		"Windows_C", "Windows_C_001", "Windows_C_002", "Windows_C_003"], "trimesh"],
	"porta_cabana": [["Door_002"], "box"],
	"picape": [["Car", "Seating", "Car_Door", "Car_Door_001", "Glove_box", "Cube_237", "Pedal", "Pedal_01", "Pedal_02",
		"Steering", "Tire", "Tire_001", "Tire_002", "Tire_003"], "convex"],
	"viatura": [["Car_sheriff", "Car_sheriff_D", "Car_sheriff_D_001", "Car_sheriff_D_002", "Car_sheriff_D_003",
		"Car_sheriff_In_002", "Cube_238", "Cube_239", "Cube_242", "Cube_243", "Steering_001", "Tire_004", "Tire_005",
		"Tire_006", "Tire_007"], "convex"],
	# móveis
	"cama": [["Bed_003"], "box"], "mesa": [["Table"], "box"], "mesa_cozinha": [["Kitchen_table_001"], "box"],
	"cadeira": [["Cube_001"], "box"], "cadeira2": [["Cylinder_014"], "box"], "armario": [["drawer_01"], "box"],
	"gaveteiro": [["drawer"], "box"], "estante": [["shelve"], "box"], "fogao": [["Stove"], "box"],
	"forno": [["oven_002"], "box"], "arquivo": [["Archivist"], "box"], "lenha": [["firewood"], "box"],
	# vegetação e pedras
	"arvore_seca_1": [["Tree"], "trunk"], "arvore_seca_2": [["Tree_01"], "trunk"], "arvore_seca_3": [["Tree_02"], "trunk"],
	"arvore_seca_4": [["Tree_03"], "trunk"], "arvore_seca_5": [["Tree_04"], "trunk"], "arvore_seca_6": [["Tree_05"], "trunk"],
	"arvore_seca_7": [["Tree_06"], "trunk"], "pinheiro_seco_1": [["Tree_07"], "trunk"], "pinheiro_seco_2": [["Tree_08"], "trunk"],
	"arvore_verde_1": [["Tree_V"], "trunk"], "arvore_verde_2": [["Tree_01_V"], "trunk"], "arvore_verde_3": [["Tree_05_V"], "trunk"],
	"arbusto": [["Tree_B"], "none"], "samambaia": [["Plane_016"], "none"], "samambaia2": [["Plane_014"], "none"],
	"grama_1": [["Grass_P_007"], "none"], "grama_2": [["Grass_P_014"], "none"], "grama_3": [["Grass_P_005"], "none"],
	"galhos": [["Branch_C"], "none"],
	"tronco_1": [["Trunk"], "box"], "tronco_2": [["Trunk_01"], "box"], "tronco_3": [["Trunk_02"], "box"], "toco": [["Trunk_001"], "box"],
	"pedra_1": [["Rock"], "convex"], "pedra_2": [["Rock_01"], "convex"], "pedra_3": [["Rock_02"], "convex"],
	"pedra_4": [["Rock_03"], "convex"], "pedra_5": [["Rock_04"], "convex"], "pedra_6": [["Rock_05"], "convex"],
	"pedra_7": [["Rock_06"], "convex"], "pedra_8": [["Rock_07"], "convex"], "pedra_9": [["Rock_08"], "convex"],
	"pedra_10": [["Rock_10"], "convex"], "rochedo": [["Rock_09"], "convex"],
	# equipamento e itens
	"mochila": [["Backpack"], "none"], "mochila2": [["Backpack_01"], "box"],
	"rifle_weatherby": [["Weatherby_Orion_I", "Weatherby_Orion_I_001"], "box"],
	"municao": [["Ammunition"], "box"], "lanterna": [["flashlight"], "box"], "garrafa": [["Water_bottle"], "box"],
	"comida": [["Food"], "box"], "machado": [["Axe"], "box"], "pa": [["Shovel"], "box"], "panela": [["pot"], "box"],
	"frigideira": [["frying_pan"], "box"], "chaleira": [["teapot"], "box"], "caneca": [["Cup"], "box"],
	"fosforos": [["Matches"], "box"], "caixa_ferramentas": [["toolbox"], "box"], "galao": [["fuel_tank"], "box"],
	"kit_medico": [["kit"], "box"], "caixa": [["Box"], "box"], "livro": [["Book_006"], "box"],
}

## texturas que faltaram no pacote: usa a parecida
const TEX_FIX := {"Branch_T2_01": "Branch_T2.png", "Branch_T2_N": "Branch_T2.png", "Branch_T3_01": "Branch_T.png",
	"Branch_T4": "Branch.png", "Branch_T4_01": "Branch.png", "canteen": "Water_bottle.png", "camp_bed": "Backpack_01.png"}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	src = load(FBX).instantiate()
	_collect(src, Transform3D())
	var n := 0
	for name in PREFABS:
		if _prefab(name, PREFABS[name][0], PREFABS[name][1]):
			n += 1
	_guns()
	print("prefabs: ", n)
	src.free()
	quit()


func _collect(node: Node, parent: Transform3D) -> void:
	var t := parent
	if node is Node3D:
		t = parent * (node as Node3D).transform
	if node is MeshInstance3D:
		xf[node.name] = [t, node]
	for c in node.get_children():
		_collect(c, t)


func _fix_material(m: Material) -> Material:
	if not m is StandardMaterial3D:
		var s := StandardMaterial3D.new()
		s.albedo_color = Color(0.5, 0.5, 0.5)
		return s
	var mat := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
	if mat.albedo_texture == null:
		var fix: String = TEX_FIX.get(String(mat.resource_name), String(mat.resource_name) + ".png")
		var p := "res://assets/cenario/" + fix
		if ResourceLoader.exists(p):
			mat.albedo_texture = load(p)
	if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		# folhas e grama: recorte (rápido no celular), dos dois lados
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.45
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif String(mat.resource_name) == "Glass" or String(mat.resource_name).begins_with("Cube_0"):
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.55, 0.6, 0.62, 0.35)
		mat.roughness = 0.1
	mat.metallic = minf(mat.metallic, 0.2)
	mat.roughness = maxf(mat.roughness, 0.7)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


func _prefab(name: String, parts: Array, col: String) -> bool:
	var ab := AABB()
	var first := true
	for p in parts:
		if not xf.has(p):
			print("  falta parte ", p, " em ", name)
			continue
		var mi: MeshInstance3D = xf[p][1]
		var box: AABB = xf[p][0] * mi.get_aabb()
		ab = box if first else ab.merge(box)
		first = false
	if first:
		return false
	# pivô: centro da base
	var pivot := Vector3(ab.position.x + ab.size.x * 0.5, ab.position.y, ab.position.z + ab.size.z * 0.5)
	var root := Node3D.new()
	root.name = name
	var faces := PackedVector3Array()
	for p in parts:
		if not xf.has(p):
			continue
		var t: Transform3D = xf[p][0]
		var mi0: MeshInstance3D = xf[p][1]
		var mesh := mi0.mesh.duplicate() as ArrayMesh
		for i in mesh.get_surface_count():
			mesh.surface_set_material(i, _fix_material(mesh.surface_get_material(i)))
		var mpath := OUT + "malhas/%s__%s.res" % [name, p]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "malhas"))
		ResourceSaver.save(mesh, mpath)
		var mi := MeshInstance3D.new()
		mi.name = p
		mi.mesh = load(mpath)
		mi.transform = Transform3D(t.basis, t.origin - pivot)
		root.add_child(mi)
		if col == "trimesh" or col == "convex":
			var f := mesh.get_faces()
			for v in f:
				faces.append(mi.transform * v)
	var size := ab.size
	if col != "none":
		var body := StaticBody3D.new()
		body.name = "Corpo"
		root.add_child(body)
		var cs := CollisionShape3D.new()
		cs.name = "Colisao"
		match col:
			"trimesh":
				var sh := ConcavePolygonShape3D.new()
				sh.set_faces(faces)
				cs.shape = sh
			"convex":
				var sh := ConvexPolygonShape3D.new()
				var pts := PackedVector3Array()
				# reduz os pontos (casco convexo não precisa de todos)
				var step := maxi(1, faces.size() / 600)
				for i in range(0, faces.size(), step):
					pts.append(faces[i])
				sh.points = pts
				cs.shape = sh
			"box":
				var sh := BoxShape3D.new()
				sh.size = size
				cs.shape = sh
				cs.position.y = size.y * 0.5
			"trunk":
				var sh := CylinderShape3D.new()
				sh.radius = clampf(minf(size.x, size.z) * 0.03, 0.15, 0.45)
				sh.height = 3.0
				cs.shape = sh
				cs.position.y = 1.5
		body.add_child(cs)
	root.set_meta("tamanho", size)
	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, OUT + name + ".tscn")
	root.free()
	return true


func _own(n: Node, r: Node) -> void:
	if n != r:
		n.owner = r
	for c in n.get_children():
		_own(c, r)


## Armas: malha inteira, materiais PBR das texturas do pacote e pontos de mão/cano.
func _guns() -> void:
	var guns := {"ak47": ["res://assets/armas/AK-47/AK47.fbx", "res://assets/armas/AK-47/AK47"],
		"m4a1": ["res://assets/armas/M4A1/M4A1.fbx", "res://assets/armas/M4A1/M4A1"],
		"escopeta": ["res://assets/armas/Shotgun/Shotgun.fbx", "res://assets/armas/Shotgun/Shotgun"]}
	for gname in guns:
		var g: Node3D = load(guns[gname][0]).instantiate()
		var base: String = guns[gname][1]
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(base + "_Base_Color.png")
		mat.metallic = 1.0
		mat.metallic_texture = load(base + "_Metallic.png")
		mat.roughness = 1.0
		mat.roughness_texture = load(base + "_Roughness.png")
		var nrm := base + ("_Normal_DirectX.png" if ResourceLoader.exists(base + "_Normal_DirectX.png") else "_Normal.png")
		mat.normal_enabled = true
		mat.normal_texture = load(nrm)
		var parts := []
		_gun_parts(g, Transform3D(), parts)
		var ab := AABB()
		for i in parts.size():
			var b: AABB = parts[i][0] * parts[i][1].get_aabb()
			ab = b if i == 0 else ab.merge(b)
		var root := Node3D.new()
		root.name = gname
		var center := ab.position + ab.size * 0.5
		for p in parts:
			var mesh := (p[1].mesh as ArrayMesh).duplicate() as ArrayMesh
			for i in mesh.get_surface_count():
				mesh.surface_set_material(i, mat)
			var mpath := OUT + "malhas/%s__%s.res" % [gname, p[1].name]
			ResourceSaver.save(mesh, mpath)
			var mi := MeshInstance3D.new()
			mi.name = p[1].name
			mi.mesh = load(mpath)
			var t: Transform3D = p[0]
			mi.transform = Transform3D(t.basis, t.origin - center)
			root.add_child(mi)
		# cano em -Z; empunhadura (mão direita) a ~72% para trás, guarda-mão (mão esquerda) a ~35%
		var L := ab.size.z
		_marker(root, "Cano", Vector3(0, 0.02, -L * 0.5))
		_marker(root, "Empunhadura", Vector3(0, -ab.size.y * 0.32, L * 0.16))
		_marker(root, "Guarda", Vector3(0, -ab.size.y * 0.12, -L * 0.2))
		root.set_meta("tamanho", ab.size)
		_own(root, root)
		var ps := PackedScene.new()
		ps.pack(root)
		ResourceSaver.save(ps, OUT + gname + ".tscn")
		print("arma ", gname, " tamanho ", ab.size)
		root.free()
		g.free()


func _gun_parts(n: Node, parent: Transform3D, out: Array) -> void:
	var t := parent
	if n is Node3D:
		t = parent * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append([t, n])
	for c in n.get_children():
		_gun_parts(c, t, out)


func _marker(root: Node3D, n: String, p: Vector3) -> void:
	var m := Marker3D.new()
	m.name = n
	m.position = p
	root.add_child(m)
