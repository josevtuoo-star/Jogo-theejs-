extends Node3D
## Mundo real: Faisqueiro e a PB-394 (Paraíba), 2,6 km x 4,6 km, montado em blocos de 160 m
## conforme o jogador anda (só existe o que está perto — leve no celular):
## - terreno do relevo real (Copernicus 30 m), com a imagem de satélite (Sentinel-2) por baixo;
##   menos detalhe longe (sem buracos: "saia" nas bordas); colisão só nos blocos próximos;
## - estradas reais (asfalto da PB-394 e estradas de terra) e açudes com água para nadar;
## - casas nos lugares das construções reais (reboco pintado, telha ou zinco, portas e janelas
##   abertas, algumas sem telhado), com móveis e coisas para achar dentro;
## - caatinga seca, árvores com folha e roçados conforme o satélite: árvores de perto com o
##   modelo inteiro e de longe como "impostores" (cartões com a foto da árvore);
## - carros abandonados na rodovia, a capela (Espaço São José) e a torre de vigia no morro.

const D := "res://assets/mapa_real/"
const CB := 32 # células por bloco (5 m cada = 160 m)
const M := "res://assets/modelos/"

var gx0: float
var gz0: float
var cell: float
var gw: int
var gh: int
var alt := PackedFloat32Array()
var veg: Image
var dados: Dictionary
var limites := Rect2()
var nbx: int
var nbz: int

var _player: Node3D
var _mat_terra: ShaderMaterial
var _mat_casa: ShaderMaterial
var _blocks := {} # Vector2i -> Dictionary
var _proto := {} # nome -> Dictionary
var _houses_by_block := {} # Vector2i -> Array de índices de casas
var _cars_by_block := {}
var _t := 0.0
var _cfg_ver := -1
var _ponds := []
var spawn := Vector3.ZERO

## distâncias (m), ajustadas pelas configurações
var view_dist := 550.0
var tree_near := 130.0
var grass_dist := 55.0
var col_dist := 210.0

const TREES := ["arvore_seca_4", "arvore_seca_5", "arvore_seca_6", "arvore_seca_7", "arvore_seca_3"]
const GREEN := ["arvore_verde_1"]
const SHRUBS := ["galhos", "arbusto", "toco", "tronco_2"]
const CACTI := ["Cactus_2", "Cactus_3", "Cactus_4", "Cactus_5"]
const GRASS := ["grama_3", "grama_1"]
const ROCKS := ["pedra_1", "pedra_5"]
const LOOT := ["comida", "comida", "garrafa", "garrafa", "fosforos", "municao", "lanterna", "panela", "caneca", "frigideira",
	"chaleira", "kit_medico", "caixa_ferramentas", "galao", "machado", "pa"]
const GUNS := ["escopeta", "rifle_weatherby", "escopeta", "rifle_weatherby", "ak47", "m4a1"]
const FURN := ["cama", "mesa", "armario", "estante", "fogao", "cadeira"]
const COLORS := [Color(0.88, 0.85, 0.77), Color(0.88, 0.75, 0.5), Color(0.68, 0.76, 0.78), Color(0.86, 0.66, 0.62),
	Color(0.72, 0.78, 0.6), Color(0.92, 0.9, 0.86), Color(0.82, 0.6, 0.42), Color(0.9, 0.86, 0.7)]


func _ready() -> void:
	add_to_group("mundo")
	Config.load_cfg()
	_load_data()
	_materials()
	_build_houses()
	_build_roads()
	_build_ponds()
	_build_landmarks()
	_plan_cars()
	_walls()
	_apply_config()


func _load_data() -> void:
	dados = JSON.parse_string(FileAccess.get_file_as_string(D + "dados.json"))
	var g: Dictionary = dados.grade
	gx0 = g.x0
	gz0 = g.z0
	cell = g.celula
	gw = int(g.w)
	gh = int(g.h)
	var img: Image = load(D + "altura.res")
	alt = img.get_data().to_float32_array()
	veg = (load(D + "vegetacao.png") as Texture2D).get_image()
	if veg.is_compressed():
		veg.decompress()
	var lim: Array = dados.limites
	limites = Rect2(lim[0], lim[1], lim[2] - lim[0], lim[3] - lim[1])
	nbx = int(ceil(float(gw - 1) / CB))
	nbz = int(ceil(float(gh - 1) / CB))


func _materials() -> void:
	_mat_terra = ShaderMaterial.new()
	_mat_terra.shader = load("res://shaders/terreno_real.gdshader")
	_mat_terra.set_shader_parameter("satelite", load(D + "satelite.png"))
	_mat_terra.set_shader_parameter("mascara", load(D + "mascara.png"))
	_mat_terra.set_shader_parameter("detalhe", load("res://assets/texturas/detalhe_solo.png"))
	_mat_terra.set_shader_parameter("asfalto", load("res://assets/cenario/Road.png"))
	_mat_terra.set_shader_parameter("area", Vector4(gx0, gz0, (gw - 1) * cell + cell, (gh - 1) * cell + cell))
	_mat_casa = ShaderMaterial.new()
	_mat_casa.shader = load("res://shaders/parede.gdshader")
	_mat_casa.set_shader_parameter("reboco", load("res://assets/texturas/reboco.png"))
	_mat_casa.set_shader_parameter("zinco", load("res://assets/cenario/Rooftile.png"))


# ================================================================== altura

func height_at(x: float, z: float) -> float:
	var fx := clampf((x - gx0) / cell, 0.0, gw - 1.001)
	var fz := clampf((z - gz0) / cell, 0.0, gh - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := alt[j * gw + i]
	var b := alt[j * gw + i + 1]
	var c := alt[(j + 1) * gw + i]
	var d := alt[(j + 1) * gw + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func _h(i: int, j: int) -> float:
	return alt[clampi(j, 0, gh - 1) * gw + clampi(i, 0, gw - 1)]


func veg_at(x: float, z: float) -> Color:
	var i := clampi(int((x - gx0) / cell), 0, gw - 1)
	var j := clampi(int((z - gz0) / cell), 0, gh - 1)
	return veg.get_pixel(i, j)


func block_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int((x - gx0) / (cell * CB)), 0, nbx - 1), clampi(int((z - gz0) / (cell * CB)), 0, nbz - 1))


func block_center(b: Vector2i) -> Vector3:
	var x := gx0 + (b.x + 0.5) * CB * cell
	var z := gz0 + (b.y + 0.5) * CB * cell
	return Vector3(x, height_at(x, z), z)


# ================================================================== blocos

func _apply_config() -> void:
	_cfg_ver = Config.version
	view_dist = Config.v.distancia
	tree_near = clampf(view_dist * 0.12, 60.0, 140.0)
	grass_dist = 55.0 if Config.v.grama else 0.0
	_mat_terra.set_shader_parameter("detalhe_dist", 70.0 if Config.v.qualidade == "Baixa" else 110.0)
	# vegetação refeita com a nova densidade
	for b in _blocks:
		_clear_veg(_blocks[b])
		(_blocks[b] as Dictionary).erase("inst")


func _process(delta: float) -> void:
	if _cfg_ver != Config.version:
		_apply_config()
	if _player == null:
		_player = get_tree().get_first_node_in_group("jogador") as Node3D
		if _player == null:
			return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.1
	_update_blocks(_player.global_position, 3)


## Cria/atualiza o que estiver perto (`budget` operações caras por chamada) e solta o que ficou longe.
func _update_blocks(p: Vector3, budget: int) -> void:
	var want := []
	var r := int(ceil(view_dist / (CB * cell))) + 1
	var pb := block_of(p.x, p.z)
	for bz in range(pb.y - r, pb.y + r + 1):
		for bx in range(pb.x - r, pb.x + r + 1):
			if bx < 0 or bz < 0 or bx >= nbx or bz >= nbz:
				continue
			var key := Vector2i(bx, bz)
			var d := _block_dist(key, p)
			if d <= view_dist:
				want.append([d, key])
	want.sort_custom(func(a, b): return a[0] < b[0])
	var keep := {}
	for w in want:
		var key: Vector2i = w[1]
		var d: float = w[0]
		keep[key] = true
		if not _blocks.has(key):
			_blocks[key] = {"lod": -1}
		var blk: Dictionary = _blocks[key]
		# terreno: detalhe conforme a distância
		var lod := 1 if d < 260.0 else (2 if d < 620.0 else 4)
		if blk.lod != lod and budget > 0:
			_terrain(key, blk, lod)
			budget -= 1
		# colisão
		if d < col_dist and not blk.has("col") and budget > 0:
			_collision(key, blk)
			budget -= 1
		# vegetação
		var vlevel := 2 if d < tree_near else 1
		if d < 60.0 and grass_dist > 0.0:
			vlevel = 3
		if blk.get("veg_level", 0) != vlevel and budget > 0:
			_vegetation(key, blk, vlevel)
			budget -= 1
		# coisas das casas e carros (uma vez só; ficam)
		if d < 140.0 and not blk.get("props", false):
			_spawn_props(key)
			blk.props = true
	for key in _blocks.keys():
		if keep.has(key):
			continue
		var blk: Dictionary = _blocks[key]
		if _block_dist(key, p) > view_dist + 120.0:
			_free_block(blk)
			_blocks.erase(key)
	# colisão e grama que ficaram longe saem (economia)
	for key in _blocks:
		var blk: Dictionary = _blocks[key]
		var d := _block_dist(key, p)
		if blk.has("col") and d > col_dist + 80.0:
			(blk.col as Node).queue_free()
			blk.erase("col")


func _block_dist(key: Vector2i, p: Vector3) -> float:
	var x0 := gx0 + key.x * CB * cell
	var z0 := gz0 + key.y * CB * cell
	var dx := maxf(maxf(x0 - p.x, 0.0), p.x - (x0 + CB * cell))
	var dz := maxf(maxf(z0 - p.z, 0.0), p.z - (z0 + CB * cell))
	return sqrt(dx * dx + dz * dz)


func _free_block(blk: Dictionary) -> void:
	for k in ["terra", "col"]:
		if blk.has(k):
			(blk[k] as Node).queue_free()
	_clear_veg(blk)


func _clear_veg(blk: Dictionary) -> void:
	if blk.has("veg"):
		(blk.veg as Node).queue_free()
		blk.erase("veg")
	blk.veg_level = 0


## Malha do terreno de um bloco (passo = 1, 2 ou 4 células) com saia nas bordas.
func _terrain_mesh(key: Vector2i, step: int) -> ArrayMesh:
	var i0 := key.x * CB
	var j0 := key.y * CB
	var n := CB / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for a in n:
		for b in n:
			var i := i0 + b * step
			var j := j0 + a * step
			var h := _h(i, j)
			verts[a * n + b] = Vector3(gx0 + i * cell, h, gz0 + j * cell)
			var hl := _h(i - 1, j)
			var hr := _h(i + 1, j)
			var hu := _h(i, j - 1)
			var hd := _h(i, j + 1)
			norms[a * n + b] = Vector3(hl - hr, 2.0 * cell, hu - hd).normalized()
	for a in n - 1:
		for b in n - 1:
			var v := a * n + b
			idx.append_array([v, v + 1, v + n, v + 1, v + n + 1, v + n])
	# saia: uma faixa descendo em volta (esconde frestas entre blocos com detalhes diferentes)
	var edges := []
	for b in n:
		edges.append(b)
	for a in range(1, n):
		edges.append(a * n + n - 1)
	for b in range(n - 2, -1, -1):
		edges.append((n - 1) * n + b)
	for a in range(n - 2, -1, -1):
		edges.append(a * n)
	var base := verts.size()
	for e in edges:
		verts.append(verts[e] + Vector3.DOWN * (2.0 + step))
		norms.append(norms[e])
	for k in edges.size() - 1:
		var top0: int = edges[k]
		var top1: int = edges[k + 1]
		idx.append_array([top0, base + k, top1, top1, base + k, base + k + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, _mat_terra)
	return m


func _terrain(key: Vector2i, blk: Dictionary, lod: int) -> void:
	var mi: MeshInstance3D = blk.get("terra")
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Terra_%d_%d" % [key.x, key.y]
		add_child(mi)
		blk.terra = mi
	mi.mesh = _terrain_mesh(key, lod)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blk.lod = lod


func _collision(key: Vector2i, blk: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "Chao_%d_%d" % [key.x, key.y]
	body.add_to_group("piso_grama")
	var cs := CollisionShape3D.new()
	cs.shape = _terrain_mesh(key, 1).create_trimesh_shape()
	body.add_child(cs)
	add_child(body)
	blk.col = body


# ================================================================== vegetação

func _proto_of(name: String) -> Dictionary:
	if _proto.has(name):
		return _proto[name]
	var path := M + name + ".tscn"
	if not ResourceLoader.exists(path):
		path = "res://assets/natureza/%s.glb" % name
	var src: Node3D = load(path).instantiate()
	var parts := []
	var aabb := AABB()
	var first := true
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var xf := _rel_xform(src, mi as Node3D)
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if name.begins_with("Cactus"):
			mesh = _cactus_mesh(mesh)
		parts.append([mesh, xf])
		var box := xf * mesh.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	src.free()
	var p := {"parts": parts, "aabb": aabb, "impostor": null}
	var imp := "res://assets/natureza/impostor_%s.png" % name
	if ResourceLoader.exists(imp):
		p.impostor = _impostor_mesh(load(imp), aabb)
	_proto[name] = p
	return p


func _rel_xform(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != root and cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Cacto do pacote low-poly com cor de mandacaru seco (verde-acinzentado, fosco).
func _cactus_mesh(mesh: Mesh) -> Mesh:
	var m := mesh.duplicate() as Mesh
	for s in m.get_surface_count():
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.38, 0.27) if s == 0 else Color(0.75, 0.62, 0.4)
		mat.roughness = 0.85
		m.surface_set_material(s, mat)
	return m


## Dois cartões cruzados com a foto da árvore (feita pelo gerador do mapa).
func _impostor_mesh(tex: Texture2D, aabb: AABB) -> Mesh:
	# a foto foi tirada de lado com câmera ortogonal: alta = meia altura de largura; larga = quadrada
	var wsz := maxf(aabb.size.x, aabb.size.z)
	var w := aabb.size.y * 0.5
	var h := aabb.size.y
	var y0 := aabb.position.y
	if aabb.size.y <= wsz:
		w = maxf(aabb.size.y, wsz)
		h = w
		y0 = aabb.get_center().y - h * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var dir := Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)
		var cxz := Vector3(aabb.get_center().x, 0.0, aabb.get_center().z)
		var a := cxz - dir * w * 0.5
		var b := cxz + dir * w * 0.5
		var n := dir.cross(Vector3.UP)
		for q in [[a, 0.0, 1.0], [b, 1.0, 1.0], [b + Vector3.UP * h, 1.0, 0.0], [a, 0.0, 1.0], [b + Vector3.UP * h, 1.0, 0.0], [a + Vector3.UP * h, 0.0, 0.0]]:
			st.set_normal(Vector3.UP.lerp(n, 0.3).normalized())
			st.set_uv(Vector2(q[1], q[2]))
			st.add_vertex((q[0] as Vector3) + Vector3.UP * y0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


## Lista de plantas do bloco (sempre igual para o mesmo bloco).
func _veg_instances(key: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + 99
	var out := {} # nome -> [Transform3D]
	var dens: float = Config.v.vegetacao
	var x0 := gx0 + key.x * CB * cell
	var z0 := gz0 + key.y * CB * cell
	var tries := int(900 * dens)
	for t in tries:
		var x := x0 + rng.randf() * CB * cell
		var z := z0 + rng.randf() * CB * cell
		if not limites.grow(150.0).has_point(Vector2(x, z)):
			continue
		var c := veg_at(x, z)
		var r := rng.randf()
		var name := ""
		var sc := 1.0
		# caatinga fechada: muita moita seca, arvoretas tortas, cactos; roçado: capim e um ou outro
		# pé de pau; verde: árvores com folha (perto de água e das casas)
		if r < c.r * 0.12 + c.b * 0.008:
			name = TREES[rng.randi() % TREES.size()]
			sc = rng.randf_range(0.18, 0.32)
		elif r < c.r * 0.55 + c.b * 0.03:
			name = "arbusto" if rng.randf() < 0.9 else ("toco" if rng.randf() < 0.5 else "galhos")
			sc = rng.randf_range(0.35, 0.75)
		elif r < c.r * 0.6 + c.b * 0.04:
			name = CACTI[rng.randi() % CACTI.size()]
			sc = rng.randf_range(0.8, 1.5)
		elif c.g > 0.25 and rng.randf() < c.g * 0.25:
			name = GREEN[rng.randi() % GREEN.size()]
			sc = rng.randf_range(0.25, 0.4)
		elif rng.randf() < c.b * 0.35:
			name = GRASS[rng.randi() % GRASS.size()]
			sc = rng.randf_range(0.35, 0.7)
		elif rng.randf() < 0.01:
			name = ROCKS[rng.randi() % ROCKS.size()]
			sc = rng.randf_range(0.12, 0.3)
		else:
			continue
		if not out.has(name):
			out[name] = []
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, height_at(x, z) - 0.08, z))
		# um pouco tortas (vento, chão inclinado)
		xf.basis = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.08)) * xf.basis
		out[name].append(xf)
	return out


func _vegetation(key: Vector2i, blk: Dictionary, level: int) -> void:
	_clear_veg(blk)
	if not blk.has("inst"):
		blk.inst = _veg_instances(key)
	var node := Node3D.new()
	node.name = "Veg_%d_%d" % [key.x, key.y]
	add_child(node)
	blk.veg = node
	blk.veg_level = level
	var inst: Dictionary = blk.inst
	var shadows: bool = Config.v.sombras >= 2
	for name in inst:
		var xfs: Array = inst[name]
		var is_grass: bool = name in GRASS
		if is_grass and level < 3:
			continue
		var p := _proto_of(name)
		var tree: bool = name in TREES or name in GREEN
		if level == 1:
			# de longe: só árvores e cactos grandes, como cartões
			if not tree or p.impostor == null:
				continue
			_mm(node, p.impostor, xfs, Transform3D(), false)
			continue
		for part in p.parts:
			_mm(node, part[0], xfs, part[1], shadows and tree)
	# colisão de troncos e cactos (só perto)
	if level >= 2:
		var sb := StaticBody3D.new()
		for name in inst:
			var r := 0.0
			if name in TREES or name in GREEN:
				r = 0.18
			elif name in CACTI:
				r = 0.25
			elif name == "tronco_2" or name in ROCKS:
				r = 0.35
			if r <= 0.0:
				continue
			for xf in inst[name]:
				var cs := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				var s: float = (xf as Transform3D).basis.get_scale().x
				cyl.radius = r * clampf(s * (3.0 if name in TREES or name in GREEN else 1.0), 0.6, 2.0)
				cyl.height = 2.2
				cs.shape = cyl
				cs.position = (xf as Transform3D).origin + Vector3.UP * 1.0
				sb.add_child(cs)
		if sb.get_child_count() > 0:
			node.add_child(sb)
		else:
			sb.free()


func _mm(parent: Node3D, mesh: Mesh, xfs: Array, local: Transform3D, shadow: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, (xfs[i] as Transform3D) * local)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


# ================================================================== casas

func _build_houses() -> void:
	var houses: Array = dados.casas
	var by_block := {}
	for i in houses.size():
		var hs: Dictionary = houses[i]
		var b := block_of(hs.x, hs.z)
		if not by_block.has(b):
			by_block[b] = []
		by_block[b].append(i)
	_houses_by_block = by_block
	for b in by_block:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var body := StaticBody3D.new()
		body.name = "Casas_%d_%d" % [b.x, b.y]
		body.add_to_group("piso_duro")
		for i in by_block[b]:
			_house(st, body, houses[i], i)
		var mi := MeshInstance3D.new()
		mi.name = "CasasMalha_%d_%d" % [b.x, b.y]
		st.generate_normals()
		mi.mesh = st.commit()
		mi.material_override = _mat_casa
		add_child(mi)
		add_child(body)


## Uma casa: paredes com porta/janelas (vãos), piso de cimento, telhado de duas águas.
func _house(st: SurfaceTool, body: StaticBody3D, hs: Dictionary, idx: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = idx * 7919 + 13
	var L: float = clampf(hs.comp, 4.0, 22.0)
	var Wd: float = clampf(hs.larg, 3.5, 12.0)
	var a: float = hs.ang
	var u := Vector3(cos(a), 0.0, sin(a))
	var v := Vector3(-sin(a), 0.0, cos(a))
	var y0: float = hs.y + 0.12
	var c := Vector3(hs.x, y0, hs.z)
	var Hh := rng.randf_range(2.7, 3.2)
	var col: Color = hs.get("cor", COLORS[rng.randi() % COLORS.size()])
	col = col.lerp(Color(0.7, 0.62, 0.52), rng.randf_range(0.1, 0.5)) # desbotada
	hs["_cor"] = col
	# lado da porta: o que dá para a estrada mais perto
	var door_side := 1.0
	var road_dir := _nearest_road_dir(Vector2(hs.x, hs.z))
	if road_dir != Vector2.ZERO and Vector2(v.x, v.z).dot(road_dir) < 0.0:
		door_side = -1.0
	hs["_porta"] = door_side
	var t := 0.15
	# paredes longas (com porta de um lado e janela do outro)
	var door_at := rng.randf_range(-L * 0.25, L * 0.25)
	for side: float in [1.0, -1.0]:
		var p0 := c + v * side * (Wd * 0.5) - u * (L * 0.5)
		var holes := []
		if side == door_side:
			holes.append([L * 0.5 + door_at - 0.5, L * 0.5 + door_at + 0.5, 0.0, 2.1])
			if L > 7.0:
				var wx := L * 0.5 + door_at + (2.2 if door_at < 0.0 else -2.2)
				holes.append([wx - 0.5, wx + 0.5, 1.0, 2.0])
		else:
			holes.append([L * 0.5 - 0.55, L * 0.5 + 0.55, 1.0, 2.0])
		_wall(st, body, p0, u, L, Hh, t, holes, col, v * side)
	# paredes curtas (janela se for larga)
	for side: float in [1.0, -1.0]:
		var p0 := c + u * side * (L * 0.5) - v * (Wd * 0.5)
		var holes := []
		if Wd > 4.5 and rng.randf() < 0.7:
			holes.append([Wd * 0.5 - 0.5, Wd * 0.5 + 0.5, 1.0, 2.0])
		_wall(st, body, p0, v, Wd, Hh, t, holes, col, u * side)
	# piso
	_quad(st, c - u * L * 0.5 - v * Wd * 0.5, c + u * L * 0.5 - v * Wd * 0.5, c + u * L * 0.5 + v * Wd * 0.5, c - u * L * 0.5 + v * Wd * 0.5, Color.WHITE, 3.0, Vector2(L, Wd))
	var floor_cs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(L, 0.3, Wd)
	floor_cs.shape = fb
	floor_cs.transform = Transform3D(Basis(u, Vector3.UP, u.cross(Vector3.UP)).orthonormalized(), c + Vector3.DOWN * 0.15)
	body.add_child(floor_cs)
	# telhado (algumas casas abandonadas sem ou com meio telhado)
	var roof := rng.randf()
	if roof < 0.12:
		return
	var kind := 1.0 if rng.randf() < 0.7 else 2.0
	var ov := 0.35
	var rise := rng.randf_range(0.9, 1.4)
	var top := c + Vector3.UP * Hh
	var r0 := top - u * (L * 0.5 + ov)
	var r1 := top + u * (L * 0.5 + ov)
	var ridge0 := r0 + Vector3.UP * rise
	var ridge1 := r1 + Vector3.UP * rise
	for side: float in [1.0, -1.0]:
		if roof < 0.22 and side < 0.0:
			continue # meio telhado caído
		var e0 := r0 + v * side * (Wd * 0.5 + ov) + Vector3.DOWN * 0.15
		var e1 := r1 + v * side * (Wd * 0.5 + ov) + Vector3.DOWN * 0.15
		var slope := (ridge0 - e0).length()
		_quad(st, e0, e1, ridge1, ridge0, Color.WHITE, kind, Vector2(L + ov * 2.0, slope))
		_quad(st, ridge0, ridge1, e1, e0, Color.WHITE, kind, Vector2(L + ov * 2.0, slope))
	# oitões (triângulos das paredes curtas)
	for side: float in [1.0, -1.0]:
		var b0 := top + u * side * (L * 0.5) - v * (Wd * 0.5)
		var b1 := top + u * side * (L * 0.5) + v * (Wd * 0.5)
		var apex := top + u * side * (L * 0.5) + Vector3.UP * rise
		for q in [[b0, b1, apex], [b1, b0, apex]]:
			st.set_color(col)
			st.set_uv2(Vector2(0, 0))
			for k in 3:
				var pt: Vector3 = q[k]
				st.set_uv(Vector2((pt - b0).dot(v), Hh + (pt.y - top.y)))
				st.add_vertex(pt)


func _nearest_road_dir(p: Vector2) -> Vector2:
	var best := 1e9
	var dir := Vector2.ZERO
	for r in dados.estradas:
		var pts: Array = r.pts
		for k in pts.size() - 1:
			var a := Vector2(pts[k][0], pts[k][1])
			var b := Vector2(pts[k + 1][0], pts[k + 1][1])
			var q := Geometry2D.get_closest_point_to_segment(p, a, b)
			var d := p.distance_to(q)
			if d < best:
				best = d
				dir = (q - p).normalized()
	return dir if best < 80.0 else Vector2.ZERO


## Parede com vãos: holes = [[início, fim, base, topo]] ao longo da parede (m).
func _wall(st: SurfaceTool, body: StaticBody3D, p0: Vector3, dir: Vector3, length: float, h: float, t: float, holes: Array,
		col: Color, outward: Vector3) -> void:
	holes.sort_custom(func(a, b): return a[0] < b[0])
	var x := 0.0
	var pieces := [] # [x0, x1, y0, y1]
	for ho in holes:
		var hx0: float = clampf(ho[0], 0.3, length - 0.3)
		var hx1: float = clampf(ho[1], 0.3, length - 0.3)
		if hx0 > x:
			pieces.append([x, hx0, 0.0, h])
		if ho[2] > 0.0:
			pieces.append([hx0, hx1, 0.0, ho[2]])
		pieces.append([hx0, hx1, ho[3], h])
		x = hx1
	if x < length:
		pieces.append([x, length, 0.0, h])
	var n := outward.normalized()
	for pc in pieces:
		var a0: float = pc[0]
		var a1: float = pc[1]
		var b0: float = pc[2]
		var b1: float = pc[3]
		if a1 - a0 < 0.01 or b1 - b0 < 0.01:
			continue
		var q0 := p0 + dir * a0 + Vector3.UP * b0
		var q1 := p0 + dir * a1 + Vector3.UP * b0
		var q2 := p0 + dir * a1 + Vector3.UP * b1
		var q3 := p0 + dir * a0 + Vector3.UP * b1
		# face de fora e de dentro
		_quad_uv(st, q0 + n * t * 0.5, q1 + n * t * 0.5, q2 + n * t * 0.5, q3 + n * t * 0.5, col, Vector2(a0, b0), Vector2(a1, b1), n)
		_quad_uv(st, q1 - n * t * 0.5, q0 - n * t * 0.5, q3 - n * t * 0.5, q2 - n * t * 0.5, col.lerp(Color(0.8, 0.78, 0.72), 0.5), Vector2(a1, b0), Vector2(a0, b1), -n)
		# espessura nas bordas dos vãos
		_quad_uv(st, q0 - n * t * 0.5, q0 + n * t * 0.5, q3 + n * t * 0.5, q3 - n * t * 0.5, col, Vector2(0, b0), Vector2(t, b1), -dir)
		_quad_uv(st, q1 + n * t * 0.5, q1 - n * t * 0.5, q2 - n * t * 0.5, q2 + n * t * 0.5, col, Vector2(0, b0), Vector2(t, b1), dir)
		_quad_uv(st, q3 + n * t * 0.5, q2 + n * t * 0.5, q2 - n * t * 0.5, q3 - n * t * 0.5, col, Vector2(a0, 0), Vector2(a1, t), Vector3.UP)
		if b0 > 0.0:
			_quad_uv(st, q1 + n * t * 0.5, q0 + n * t * 0.5, q0 - n * t * 0.5, q1 - n * t * 0.5, col, Vector2(a0, 0), Vector2(a1, t), Vector3.DOWN)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(a1 - a0, b1 - b0, t)
		cs.shape = bs
		var zb := dir.cross(Vector3.UP).normalized()
		cs.transform = Transform3D(Basis(dir, Vector3.UP, -zb).orthonormalized(), p0 + dir * (a0 + a1) * 0.5 + Vector3.UP * (b0 + b1) * 0.5)
		body.add_child(cs)


func _quad_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uv0: Vector2, uv1: Vector2, _n: Vector3) -> void:
	var uvs := [Vector2(uv0.x, uv0.y), Vector2(uv1.x, uv0.y), Vector2(uv1.x, uv1.y), Vector2(uv0.x, uv1.y)]
	var ps := [a, b, c, d]
	for k in [0, 2, 1, 0, 3, 2]:
		st.set_color(col)
		st.set_uv(uvs[k])
		st.set_uv2(Vector2(0, 0))
		st.add_vertex(ps[k])


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, kind: float, size: Vector2) -> void:
	var uvs := [Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)]
	var ps := [a, b, c, d]
	for k in [0, 2, 1, 0, 3, 2]:
		st.set_color(col)
		st.set_uv(uvs[k])
		st.set_uv2(Vector2(kind, 0))
		st.add_vertex(ps[k])


# ================================================================== estradas, açudes, marcos

## Faixa de asfalto da PB-394 (malha própria um pouco acima do chão, com faixa amarela gasta).
func _build_roads() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/cenario/Road.png")
	mat.albedo_color = Color(0.33, 0.33, 0.32)
	mat.roughness = 0.85
	mat.uv1_scale = Vector3(1, 1, 1)
	for r in dados.estradas:
		if not r.asfalto:
			continue
		var pts: Array = r.pts
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var w: float = r.largura * 0.5
		var dist := 0.0
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_d := 0.0
		var dense := []
		for k in pts.size() - 1:
			var a := Vector2(pts[k][0], pts[k][1])
			var b := Vector2(pts[k + 1][0], pts[k + 1][1])
			var n := int(ceil(a.distance_to(b) / 4.0))
			for s in n:
				dense.append(a.lerp(b, float(s) / n))
		dense.append(Vector2(pts[-1][0], pts[-1][1]))
		for k in dense.size():
			var p: Vector2 = dense[k]
			var dir: Vector2 = ((dense[mini(k + 1, dense.size() - 1)] as Vector2) - (dense[maxi(k - 1, 0)] as Vector2)).normalized()
			var side := Vector2(-dir.y, dir.x)
			var l2 := p + side * w
			var r2 := p - side * w
			var l := Vector3(l2.x, height_at(l2.x, l2.y) + 0.06, l2.y)
			var rr := Vector3(r2.x, height_at(r2.x, r2.y) + 0.06, r2.y)
			if k > 0:
				dist += p.distance_to(dense[k - 1])
				for q in [[prev_l, 0.0, prev_d], [rr, 1.0, dist], [prev_r, 1.0, prev_d], [prev_l, 0.0, prev_d], [l, 0.0, dist], [rr, 1.0, dist]]:
					st.set_normal(Vector3.UP)
					st.set_uv(Vector2(q[1], q[2] / 8.0))
					st.add_vertex(q[0])
			prev_l = l
			prev_r = rr
			prev_d = dist
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _build_ponds() -> void:
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	wm.set_shader_parameter("shallow", Color(0.36, 0.33, 0.22))
	wm.set_shader_parameter("deep", Color(0.12, 0.13, 0.08))
	# açude: água barrenta, pouco reflexo
	wm.set_shader_parameter("rugosidade", 0.6)
	wm.set_shader_parameter("brilho", 0.12)
	wm.set_shader_parameter("opacidade", 0.93)
	for p in dados.acudes:
		var cx: float = (p.x0 + p.x1) * 0.5
		var cz: float = (p.z0 + p.z1) * 0.5
		var sx: float = p.x1 - p.x0
		var sz: float = p.z1 - p.z0
		var y: float = p.nivel
		var water := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(sx, sz)
		pm.subdivide_width = 8
		pm.subdivide_depth = 8
		pm.material = wm
		water.mesh = pm
		water.position = Vector3(cx, y, cz)
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)
		var area := Area3D.new()
		area.set_script(load("res://scripts/water.gd"))
		area.set("surface_y", y)
		area.collision_layer = 0
		area.collision_mask = 4 | 2
		# o volume passa 2 m acima da superfície (boiando, o corpo continua "na água")
		area.position = Vector3(cx, y - 2.0, cz)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(sx, 8.0, sz)
		cs.shape = bs
		area.add_child(cs)
		add_child(area)
		_ponds.append(Vector3(cx, y, cz))


func pond_centers() -> Array:
	return _ponds


func _build_landmarks() -> void:
	# capela (Espaço São José) e placa da vila
	for pl in dados.lugares:
		if pl.tipo == "capela":
			_chapel(Vector2(pl.x, pl.z), pl.nome)
	_sign(Vector3(18.0, 0.0, -60.0), "FAISQUEIRO\nPB-394", 0.4)
	# torre de vigia no morro mais alto perto da vila
	var best := Vector3(0, -1e9, 0)
	for k in 900:
		var a := k * 2.399963
		var r := sqrt(k / 900.0) * 1000.0
		var x := cos(a) * r
		var z := sin(a) * r + 300.0
		if not limites.grow(-60.0).has_point(Vector2(x, z)):
			continue
		var y := height_at(x, z)
		if y > best.y and veg_at(x, z).r > 0.2:
			best = Vector3(x, y, z)
	var tower: Node3D = load(M + "torre.tscn").instantiate()
	tower.name = "TorreDeVigia"
	tower.position = best + Vector3.DOWN * 0.4
	tower.rotation.y = 0.4
	add_child(tower)
	var tb := tower.get_node_or_null("Corpo")
	if tb:
		tb.add_to_group("piso_madeira")
	_extra_loot.append(["ak47", tower.global_transform * Vector3(-0.9, 18.75, -2.6)])
	_extra_loot.append(["kit_medico", tower.global_transform * Vector3(0.6, 18.7, -2.4)])


var _extra_loot := []


func _sign(p: Vector3, text: String, yaw: float) -> void:
	var y := height_at(p.x, p.z)
	var root := Node3D.new()
	root.position = Vector3(p.x, y, p.z)
	root.rotation.y = yaw
	add_child(root)
	var post := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.08, 2.4, 0.08)
	post.mesh = cm
	post.position.y = 1.2
	root.add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.8, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.35, 0.2)
	bm.material = mat
	board.mesh = bm
	board.position.y = 2.2
	root.add_child(board)
	var lb := Label3D.new()
	lb.text = text
	lb.pixel_size = 0.004
	lb.font_size = 48
	lb.position = Vector3(0, 2.2, 0.03)
	lb.modulate = Color(0.92, 0.92, 0.88)
	root.add_child(lb)


func _chapel(p: Vector2, nome: String) -> void:
	var y := height_at(p.x, p.y)
	var hs := {"x": p.x, "z": p.y, "comp": 13.0, "larg": 7.0, "ang": 0.0, "y": y, "cor": Color(0.93, 0.92, 0.88)}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	_house(st, body, hs, 4242)
	var mi := MeshInstance3D.new()
	st.generate_normals()
	mi.mesh = st.commit()
	mi.material_override = _mat_casa
	add_child(mi)
	add_child(body)
	# cruz na frente
	var cross := Node3D.new()
	cross.position = Vector3(p.x + 6.8, y + 4.6, p.y)
	add_child(cross)
	for s in [Vector3(0.12, 1.6, 0.12), Vector3(0.12, 0.12, 0.9)]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s
		b.mesh = bm
		b.position.y = 0.3 if s.y < 1.0 else 0.0
		cross.add_child(b)
	_sign(Vector3(p.x + 9.0, 0, p.y + 4.0), nome.to_upper(), PI * 0.5)
	_extra_loot.append(["escopeta", Vector3(p.x, y + 0.5, p.y + 1.0)])
	_extra_loot.append(["kit_medico", Vector3(p.x - 3.0, y + 0.5, p.y - 1.5)])


## Carros abandonados: no acostamento da PB-394 (alguns atravessados) e nas ruas da vila.
func _plan_cars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 394
	for r in dados.estradas:
		var pts: Array = r.pts
		var acc := 0.0
		for k in pts.size() - 1:
			var a := Vector2(pts[k][0], pts[k][1])
			var b := Vector2(pts[k + 1][0], pts[k + 1][1])
			acc += a.distance_to(b)
			var gap := 260.0 if r.asfalto else 520.0
			if acc < gap:
				continue
			acc = 0.0
			if rng.randf() > 0.6:
				continue
			var dir := (b - a).normalized()
			var side := Vector2(-dir.y, dir.x) * (rng.randf_range(3.5, 5.0) * (1.0 if rng.randf() < 0.5 else -1.0))
			var q := b + side
			if not limites.has_point(q):
				continue
			var yaw := atan2(dir.x, dir.y) + (0.0 if rng.randf() < 0.5 else PI) + rng.randf_range(-0.5, 0.5)
			var key := block_of(q.x, q.y)
			if not _cars_by_block.has(key):
				_cars_by_block[key] = []
			_cars_by_block[key].append([q, yaw, "picape" if rng.randf() < 0.6 else "viatura"])


## Móveis e coisas nas casas, carros e itens especiais de um bloco (só quando o jogador chega perto).
func _spawn_props(key: Vector2i) -> void:
	var objs := get_parent().get_node_or_null("Objetos")
	if objs == null:
		objs = self
	for c in _cars_by_block.get(key, []):
		var q: Vector2 = c[0]
		var car: Node3D = load(M + c[2] + ".tscn").instantiate()
		car.position = Vector3(q.x, height_at(q.x, q.y) - 0.12, q.y)
		car.rotation.y = c[1]
		add_child(car)
	for i in _houses_by_block.get(key, []):
		_furnish(dados.casas[i], i, objs)
	for e in _extra_loot.duplicate():
		var pos: Vector3 = e[1]
		if block_of(pos.x, pos.z) == key:
			var rb := Itens.make_body(e[0])
			objs.add_child(rb)
			rb.global_position = pos + Vector3.UP * 0.3
			_extra_loot.erase(e)


func _furnish(hs: Dictionary, idx: int, objs: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = idx * 31 + 7
	var L: float = clampf(hs.comp, 4.0, 22.0)
	var Wd: float = clampf(hs.larg, 3.5, 12.0)
	var a: float = hs.ang
	var u := Vector3(cos(a), 0.0, sin(a))
	var v := Vector3(-sin(a), 0.0, cos(a))
	var c := Vector3(hs.x, hs.y + 0.12, hs.z)
	var door: float = hs.get("_porta", 1.0)
	# móveis encostados na parede dos fundos (lado sem porta)
	var n := rng.randi_range(1, 3) if L * Wd > 18.0 else 1
	for k in n:
		var f: String = FURN[rng.randi() % FURN.size()]
		var t := (k + 0.5) / n - 0.5
		var pos := c + u * t * (L - 1.6) - v * door * (Wd * 0.5 - 0.6)
		var obj: Node3D = load(M + f + ".tscn").instantiate()
		obj.position = pos
		obj.rotation.y = atan2(v.x * door, v.z * door) + (PI * 0.5 if f in ["cama", "mesa", "estante", "armario"] else 0.0)
		add_child(obj)
		if f == "cadeira":
			var b := obj.get_node_or_null("Corpo") as StaticBody3D
			if b:
				b.set_script(load("res://scripts/seat.gd"))
				b.add_to_group("usavel")
				var s := Node3D.new()
				s.name = "Assento"
				s.position = Vector3(0, 0.46, 0)
				s.rotation.y = PI
				b.add_child(s)
	# coisas para achar
	var loot_n := 0
	if rng.randf() < 0.65:
		loot_n = rng.randi_range(1, 2)
	for k in loot_n:
		var id: String = LOOT[rng.randi() % LOOT.size()]
		if rng.randf() < 0.07:
			id = GUNS[rng.randi() % GUNS.size()]
		var pos := c + u * rng.randf_range(-L * 0.3, L * 0.3) + v * rng.randf_range(-Wd * 0.2, Wd * 0.2) + Vector3.UP * 0.35
		var rb := Itens.make_body(id)
		if Itens.is_gun(id):
			rb.rotation = Vector3(0.0, rng.randf() * TAU, PI * 0.5)
		objs.add_child(rb)
		rb.global_position = pos


## Paredes invisíveis no fim do mapa.
func _walls() -> void:
	var body := StaticBody3D.new()
	body.name = "LimiteDoMapa"
	var r := limites
	for w in [[Vector3(r.position.x, 0, r.get_center().y), Vector3(1, 400, r.size.y)], [Vector3(r.end.x, 0, r.get_center().y), Vector3(1, 400, r.size.y)],
			[Vector3(r.get_center().x, 0, r.position.y), Vector3(r.size.x, 400, 1)], [Vector3(r.get_center().x, 0, r.end.y), Vector3(r.size.x, 400, 1)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = w[1]
		cs.shape = bs
		cs.position = w[0]
		body.add_child(cs)
	add_child(body)


## Ponto para o jogador começar: no acostamento da PB-394, na entrada da vila (o alfinete).
func spawn_point() -> Vector3:
	var x := 9.0
	var z := 6.0
	return Vector3(x, height_at(x, z) + 0.3, z)


## Prepara tudo em volta de um ponto de uma vez (ao começar e ao recomeçar).
func preload_around(p: Vector3) -> void:
	for i in 40:
		_update_blocks(p, 1000)
