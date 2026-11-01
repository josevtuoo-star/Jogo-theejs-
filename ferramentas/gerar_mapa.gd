extends SceneTree
## Uso: godot --rendering-driver opengl3 -s res://ferramentas/gerar_mapa.gd  (precisa de janela/xvfb:
## no modo headless as MultiMesh da floresta saem vazias)
# Gera o mapa de 1 km x 1 km (v0.03): res://scenes/main.tscn, res://scenes/player.tscn e os
# dados do terreno em res://assets/mapa/.

const SIZE := 1000.0
const RES := 2.5
const N := 401 # vértices por lado (SIZE / RES + 1)
const CHUNKS := 10
const M := "res://assets/modelos/"
const MAPA := "res://assets/mapa/"

var H := PackedFloat32Array()
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var mask: Image
var root_main: Node3D
var world: Node3D
var props: Node3D
var chunk_nodes := {}
var blocked := [] # [centro Vector2, raio] onde não nasce vegetação
var tree_spots: Array[Vector3] = []

# estradas: pontos (x, z)
var ROAD := [Vector2(-520, 70), Vector2(-330, 62), Vector2(-150, 40), Vector2(-40, 26), Vector2(60, 22),
	Vector2(170, 8), Vector2(300, -55), Vector2(420, -80), Vector2(520, -92)]
var DIRT := [Vector2(170, 8), Vector2(190, 70), Vector2(205, 150), Vector2(215, 215)]
var DIRT2 := [Vector2(-40, 26), Vector2(-60, -60), Vector2(-90, -160), Vector2(-95, -255)]
var DIRT3 := [Vector2(60, 22), Vector2(80, 140), Vector2(110, 250), Vector2(125, 325)]
const TOWER := Vector2(220, 245)
const LAKE := Vector2(-185, -150)
const LAKE_R := 42.0
const LAKE_Y := -2.2
var CABINS := [[Vector3(6, 0, -8), 0.0], [Vector3(-262, 0, 92), 170.0], [Vector3(335, 0, -122), 15.0],
	[Vector3(-95, 0, -272), 0.0], [Vector3(128, 0, 342), 200.0], [Vector3(-338, 0, 262), 120.0]]


func _initialize() -> void:
	rng.seed = 2024
	noise.seed = 7
	noise.frequency = 0.004
	noise.fractal_octaves = 4
	noise2.seed = 11
	noise2.frequency = 0.02
	_build_player()
	_heights()
	await _build_main()
	quit()


# ================================================================== terreno

func _hill(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 9.0 + noise2.get_noise_2d(x, z) * 1.2
	# morro da torre
	var dt := Vector2(x, z).distance_to(TOWER)
	h += 16.0 * exp(-dt * dt / (2.0 * 70.0 * 70.0))
	# morros nas bordas (fecham a vista)
	var edge := maxf(absf(x), absf(z))
	h += smoothstep(380.0, 500.0, edge) * 14.0
	return h


func _dist_poly(p: Vector2, pts: Array) -> Array:
	var best := 1e9
	var t_best := 0.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			t_best = i + t
	return [best, t_best]


func _heights() -> void:
	H.resize(N * N)
	mask = Image.create(N, N, false, Image.FORMAT_RGB8)
	for j in N:
		for i in N:
			var x := -SIZE * 0.5 + i * RES
			var z := -SIZE * 0.5 + j * RES
			H[j * N + i] = _hill(x, z)
	# estradas: altura suavizada ao longo do traçado (média larga) e laterais em rampa
	var roads := [[ROAD, 4.5, 1.0], [DIRT, 2.8, 0.0], [DIRT2, 2.5, 0.0], [DIRT3, 2.5, 0.0]]
	var smooth := H.duplicate()
	for j in N:
		for i in N:
			var acc := 0.0
			var cnt := 0
			for dj in range(-6, 7, 3):
				for di in range(-6, 7, 3):
					var ii := clampi(i + di, 0, N - 1)
					var jj := clampi(j + dj, 0, N - 1)
					acc += H[jj * N + ii]
					cnt += 1
			smooth[j * N + i] = acc / cnt
	for j in N:
		for i in N:
			var x := -SIZE * 0.5 + i * RES
			var z := -SIZE * 0.5 + j * RES
			var p := Vector2(x, z)
			var h: float = H[j * N + i]
			var r := 0.0
			var g := 0.0
			for rd in roads:
				var dd := _dist_poly(p, rd[0])
				var w: float = rd[1]
				var k := 1.0 - smoothstep(w, w + 9.0, dd[0])
				h = lerpf(h, smooth[j * N + i], k)
				var paint := 1.0 - smoothstep(w - 0.5, w + 1.5, dd[0])
				if rd[2] > 0.5:
					r = maxf(r, paint)
				else:
					g = maxf(g, paint)
			# acampamento e cabanas: chão plano e de terra batida
			for c in CABINS:
				var cp := Vector2(c[0].x, c[0].z)
				var dc := p.distance_to(cp)
				var radius := 26.0 if cp.length() < 10.0 else 14.0
				var k := 1.0 - smoothstep(radius, radius + 18.0, dc)
				h = lerpf(h, _hill(cp.x, cp.y) * 0.0 + _flat_y(cp), k)
				g = maxf(g, (1.0 - smoothstep(radius * 0.4, radius, dc)) * 0.8)
			var dtw := p.distance_to(TOWER)
			h = lerpf(h, _hill(TOWER.x, TOWER.y), 1.0 - smoothstep(10.0, 22.0, dtw))
			g = maxf(g, 1.0 - smoothstep(6.0, 14.0, dtw))
			# lago
			var dl := p.distance_to(LAKE)
			var bowl := LAKE_Y - 3.0 * (1.0 - clampf(dl / LAKE_R, 0.0, 1.0))
			h = lerpf(h, minf(h, bowl), 1.0 - smoothstep(LAKE_R, LAKE_R + 14.0, dl))
			H[j * N + i] = h
			mask.set_pixel(i, j, Color(r, g, 0.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAPA))
	ResourceSaver.save(ImageTexture.create_from_image(mask), MAPA + "mascara.res")
	print("alturas prontas")


## Altura plana para construções (usa a altura natural do lugar).
func _flat_y(p: Vector2) -> float:
	return _hill(p.x, p.y) if p.length() > 10.0 else 0.4


func height_at(x: float, z: float) -> float:
	var fx := clampf((x + SIZE * 0.5) / RES, 0.0, N - 1.001)
	var fz := clampf((z + SIZE * 0.5) / RES, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := H[j * N + i]
	var b := H[j * N + i + 1]
	var c := H[(j + 1) * N + i]
	var d := H[(j + 1) * N + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func _mask_at(x: float, z: float) -> Color:
	var i := clampi(int((x + SIZE * 0.5) / RES), 0, N - 1)
	var j := clampi(int((z + SIZE * 0.5) / RES), 0, N - 1)
	return mask.get_pixel(i, j)


func _terrain() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("mask_tex", load(MAPA + "mascara.res"))
	mat.set_shader_parameter("gravel_tex", load("res://assets/cenario/Ground.png"))
	mat.set_shader_parameter("road_tex", load("res://assets/cenario/Road.png"))
	var per := (N - 1) / CHUNKS
	for cz in CHUNKS:
		for cx in CHUNKS:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for j in range(cz * per, cz * per + per + 1):
				for i in range(cx * per, cx * per + per + 1):
					var x := -SIZE * 0.5 + i * RES
					var z := -SIZE * 0.5 + j * RES
					var hl := H[j * N + maxi(i - 1, 0)]
					var hr := H[j * N + mini(i + 1, N - 1)]
					var hd := H[maxi(j - 1, 0) * N + i]
					var hu := H[mini(j + 1, N - 1) * N + i]
					st.set_normal(Vector3(hl - hr, 2.0 * RES, hd - hu).normalized())
					st.add_vertex(Vector3(x, H[j * N + i], z))
			var w := per + 1
			for j in per:
				for i in per:
					var a := j * w + i
					st.add_index(a)
					st.add_index(a + 1)
					st.add_index(a + w)
					st.add_index(a + 1)
					st.add_index(a + w + 1)
					st.add_index(a + w)
			var mesh := st.commit()
			mesh.surface_set_material(0, mat)
			var path := MAPA + "terreno_%d_%d.res" % [cx, cz]
			ResourceSaver.save(mesh, path)
			var mi := MeshInstance3D.new()
			mi.name = "Terreno"
			mi.mesh = load(path)
			mi.visibility_range_end = 560.0
			_chunk(cx, cz).add_child(mi)
			var body := StaticBody3D.new()
			body.name = "Chao"
			body.set_script(load("res://scripts/terreno.gd"))
			body.add_to_group("piso_grama", true)
			mi.add_child(body)


func _chunk(cx: int, cz: int) -> Node3D:
	var key := Vector2i(cx, cz)
	if not chunk_nodes.has(key):
		var n := Node3D.new()
		n.name = "Bloco_%d_%d" % [cx, cz]
		world.add_child(n)
		chunk_nodes[key] = n
	return chunk_nodes[key]


func _chunk_of(x: float, z: float) -> Node3D:
	return _chunk(clampi(int((x + SIZE * 0.5) / (SIZE / CHUNKS)), 0, CHUNKS - 1), clampi(int((z + SIZE * 0.5) / (SIZE / CHUNKS)), 0, CHUNKS - 1))


# ================================================================== objetos

func _place(prefab: String, pos: Vector3, yaw_deg: float, parent: Node = null, sink := 0.05) -> Node3D:
	var n: Node3D = load(M + prefab + ".tscn").instantiate()
	n.position = Vector3(pos.x, height_at(pos.x, pos.z) - sink if is_nan(pos.y) else pos.y, pos.z)
	n.rotation.y = deg_to_rad(yaw_deg)
	(parent if parent else _chunk_of(pos.x, pos.z)).add_child(n)
	return n


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, NAN, z)


func _is_free(p: Vector2, r: float) -> bool:
	for b in blocked:
		if p.distance_to(b[0]) < b[1] + r:
			return false
	var m := _mask_at(p.x, p.y)
	if m.r > 0.05 or m.g > 0.3:
		return false
	if p.distance_to(LAKE) < LAKE_R + 6.0:
		return false
	return true


func _structures() -> void:
	# cabanas (com porta que abre) — a primeira é a do acampamento, onde o jogo começa
	var ci := 0
	for c in CABINS:
		var p: Vector3 = c[0]
		var base := _flat_y(Vector2(p.x, p.z)) - 0.05
		var cab := _place("cabana", Vector3(p.x, base, p.z), c[1])
		cab.name = "Cabana%d" % ci
		var cbody := cab.get_node_or_null("Corpo")
		if cbody:
			cbody.add_to_group("piso_madeira", true)
		var inside := Area3D.new()
		inside.name = "Interior"
		inside.set_script(load("res://scripts/interior.gd"))
		inside.collision_layer = 0
		inside.collision_mask = 4
		var ics := CollisionShape3D.new()
		var ibox := BoxShape3D.new()
		ibox.size = Vector3(7.4, 2.8, 5.0)
		ics.shape = ibox
		ics.position = Vector3(0, 1.8, 0)
		inside.add_child(ics)
		cab.add_child(inside)
		blocked.append([Vector2(p.x, p.z), 9.0])
		# porta: dobradiça na borda da porta original (relativa ao centro da cabana)
		var door := AnimatableBody3D.new()
		door.name = "Porta"
		door.set_script(load("res://scripts/door.gd"))
		door.position = Vector3(-1.9, 0.4, -0.385)
		var dmodel: Node3D = load(M + "porta_cabana.tscn").instantiate()
		dmodel.position = Vector3(0, 0, 0.485)
		var dcol := dmodel.get_node("Corpo")
		# a colisão da porta passa a ser do corpo animado
		var shape: CollisionShape3D = dcol.get_node("Colisao").duplicate()
		dmodel.remove_child(dcol)
		dcol.queue_free()
		door.add_child(dmodel)
		shape.position += dmodel.position
		door.add_child(shape)
		cab.add_child(door)
		_furnish(cab, ci)
		ci += 1
	# torre de vigia no morro
	var ty := _hill(TOWER.x, TOWER.y) - 0.1
	var tower := _place("torre", Vector3(TOWER.x, ty, TOWER.y), 25.0)
	tower.name = "TorreDeVigia"
	var tbody := tower.get_node_or_null("Corpo")
	if tbody:
		tbody.add_to_group("piso_madeira", true)
	blocked.append([TOWER, 12.0])
	# carros abandonados (alguns fora da estrada, tortos)
	var cars := [["picape", Vector2(-4, 10), 35.0], ["viatura", Vector2(16, 12), -70.0], ["picape", Vector2(-150, 46), 95.0],
		["viatura", Vector2(178, 2), 160.0], ["picape", Vector2(305, -48), 72.0], ["viatura", Vector2(-336, 72), -20.0],
		["picape", Vector2(-60, -60), 10.0], ["viatura", Vector2(410, -70), 105.0], ["picape", Vector2(95, 190), -15.0]]
	var k := 0
	for c in cars:
		var cp: Vector2 = c[1]
		var car := _place(c[0], _ground(cp.x, cp.y), c[2], null, 0.12)
		car.name = "Carro%d" % k
		blocked.append([cp, 4.0])
		k += 1


## Móveis dentro das cabanas (posições locais; a cabana tem ~7,9 x 5,5 m, piso a 0,4 m).
func _furnish(cab: Node3D, idx: int) -> void:
	var f := 0.42
	var list := [["cama", Vector3(2.4, f, -1.6), 90.0], ["mesa", Vector3(0.4, f, 1.9), 90.0], ["fogao", Vector3(-2.8, f, 1.9), 180.0],
		["estante", Vector3(3.6, f, 1.2), -90.0], ["armario", Vector3(-1.0, f, -2.2), 0.0]]
	for it in list:
		var n: Node3D = load(M + it[0] + ".tscn").instantiate()
		n.position = it[1]
		n.rotation.y = deg_to_rad(it[2])
		cab.add_child(n)
	# cadeira (dá para sentar)
	var chair := _seat("cadeira", Vector3(0.4, f, 1.15), 0.0)
	cab.add_child(chair)


func _seat(prefab: String, pos: Vector3, yaw: float) -> Node3D:
	var n: Node3D = load(M + prefab + ".tscn").instantiate()
	n.position = pos
	n.rotation.y = deg_to_rad(yaw)
	var body := n.get_node_or_null("Corpo") as StaticBody3D
	if body:
		body.set_script(load("res://scripts/seat.gd"))
		body.add_to_group("usavel", true)
		var s := Node3D.new()
		s.name = "Assento"
		s.position = Vector3(0, 0.46, 0)
		s.rotation.y = PI
		body.add_child(s)
	return n


# ================================================================== vegetação

func _vegetation() -> void:
	var trees := ["arvore_seca_1", "arvore_seca_2", "arvore_seca_3", "arvore_seca_4", "arvore_seca_5", "arvore_seca_6",
		"arvore_seca_7", "pinheiro_seco_1", "pinheiro_seco_2", "arvore_verde_1", "arvore_verde_2", "arvore_verde_3"]
	var tree_w := [3, 3, 2, 3, 2, 2, 2, 4, 4, 0, 0, 0] # as verdes ficam de fora (mundo morto)
	var dens := FastNoiseLite.new()
	dens.seed = 3
	dens.frequency = 0.008
	# árvores: por bloco, uma MultiMesh por tipo (desenho barato) + troncos com colisão
	var placed := {}
	var count := 0
	for attempt in 26000:
		var x := rng.randf_range(-490, 490)
		var z := rng.randf_range(-490, 490)
		var forest := dens.get_noise_2d(x, z) * 0.5 + 0.5
		if rng.randf() > smoothstep(0.42, 0.7, forest) * 0.9:
			continue
		var p := Vector2(x, z)
		if not _is_free(p, 4.0):
			continue
		var tsum := 0
		for w in tree_w:
			tsum += w
		var pick := rng.randi_range(0, tsum - 1)
		var ti := 0
		while pick >= tree_w[ti]:
			pick -= tree_w[ti]
			ti += 1
		var key := [_chunk_of(x, z), trees[ti]]
		if not placed.has(key):
			placed[key] = []
		var s := rng.randf_range(0.75, 1.15)
		placed[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, height_at(x, z) - 0.2, z)))
		if count % 8 == 0:
			tree_spots.append(Vector3(x, height_at(x, z), z))
		count += 1
		if count >= 1400:
			break
	for key in placed:
		_multimesh(key[0], key[1], placed[key], 230.0, true)
	print("árvores ", count)
	# pedras, troncos caídos, arbustos e grama
	var small := [["pedra_1", 120, 0.6, true], ["pedra_2", 60, 0.5, true], ["pedra_4", 40, 0.4, true], ["pedra_5", 60, 0.5, true],
		["pedra_6", 120, 0.8, true], ["pedra_7", 120, 0.8, true], ["pedra_8", 160, 1.0, true], ["pedra_9", 160, 1.0, true],
		["rochedo", 14, 0.5, true], ["tronco_2", 60, 1.0, true], ["tronco_3", 40, 1.0, true], ["toco", 80, 1.0, true],
		["galhos", 120, 1.0, false], ["arbusto", 500, 1.0, false], ["samambaia", 400, 1.0, false]]
	for s in small:
		var by_chunk := {}
		for i in s[1]:
			for tries in 8:
				var x := rng.randf_range(-480, 480)
				var z := rng.randf_range(-480, 480)
				if _is_free(Vector2(x, z), 3.0):
					var c := _chunk_of(x, z)
					if not by_chunk.has(c):
						by_chunk[c] = []
					var sc: float = rng.randf_range(0.7, 1.2) * s[2]
					by_chunk[c].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, height_at(x, z) - 0.15, z)))
					break
		for c in by_chunk:
			_multimesh(c, s[0], by_chunk[c], 160.0 if s[3] else 90.0, s[3])
	# grama alta: muitas touceiras perto de onde se anda (some de longe)
	var grass := ["grama_1", "grama_2", "grama_3"]
	for g in grass:
		var by_chunk := {}
		for i in 2200:
			var x := rng.randf_range(-480, 480)
			var z := rng.randf_range(-480, 480)
			var m := _mask_at(x, z)
			if m.r > 0.1 or Vector2(x, z).distance_to(LAKE) < LAKE_R:
				continue
			var c := _chunk_of(x, z)
			if not by_chunk.has(c):
				by_chunk[c] = []
			by_chunk[c].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.5, 0.9)), Vector3(x, height_at(x, z) - 0.05, z)))
		for c in by_chunk:
			_multimesh(c, g, by_chunk[c], 70.0, false)


## Instâncias de um objeto num bloco do mapa: uma MultiMesh por parte da malha (desenho único)
## e, se tiver colisão, um corpo estático com uma forma por instância.
func _multimesh(chunk: Node3D, prefab: String, xforms: Array, vis: float, collide: bool) -> void:
	var proto: Node3D = load(M + prefab + ".tscn").instantiate()
	for part in proto.get_children():
		if not part is MeshInstance3D:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = (part as MeshInstance3D).mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i] * (part as MeshInstance3D).transform)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%s" % [prefab, part.name]
		mmi.multimesh = mm
		mmi.visibility_range_end = vis
		mmi.visibility_range_end_margin = 20.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if vis < 100.0:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(mmi)
	if collide:
		var body := proto.get_node_or_null("Corpo") as StaticBody3D
		if body:
			var shape_node := body.get_node("Colisao") as CollisionShape3D
			var sb := StaticBody3D.new()
			sb.name = "Colisao_" + prefab
			for i in xforms.size():
				var cs := CollisionShape3D.new()
				cs.shape = shape_node.shape
				var t: Transform3D = xforms[i]
				var sc := t.basis.get_scale().x
				# forma escalada uniformemente junto com a instância
				cs.transform = Transform3D(t.basis.orthonormalized(), t.origin) * Transform3D(Basis().scaled(Vector3.ONE * sc), shape_node.position * sc)
				sb.add_child(cs)
			chunk.add_child(sb)
	proto.free()


# ================================================================== itens

func _item(id: String, pos: Vector3, yaw := 0.0) -> RigidBody3D:
	# apoia na superfície embaixo (mesa, chão, piso da torre)
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.6, pos + Vector3.DOWN * 3.0, 1 | 2)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		pos.y = hit.position.y
	else:
		print("sem apoio: ", id, " ", pos)
	var rb := Itens.make_body(id)
	var real: Vector3 = rb.get_node("Modelo").get_meta("tamanho_real")
	if Itens.is_gun(id):
		# arma deitada de lado
		rb.rotation = Vector3(0.0, deg_to_rad(yaw), PI * 0.5)
		rb.position = pos + Vector3.UP * (maxf(real.x, 0.08) * 0.5 + 0.03)
	else:
		rb.rotation.y = deg_to_rad(yaw)
		rb.position = pos + Vector3.UP * (maxf(real.y, 0.08) * 0.5 + 0.03)
	rb.name = "Item_%s_%d" % [id, props.get_child_count()]
	props.add_child(rb)
	return rb


func _items() -> void:
	var c0: Node3D = world.find_child("Cabana0", true, false)
	var base := c0.global_transform if c0 else Transform3D()
	var fy := base.origin.y + 0.42
	# na mesa da cabana do acampamento
	_item("garrafa", base * Vector3(0.15, 0.0, 1.9) + Vector3(0, 1.08, 0))
	_item("comida", base * Vector3(0.45, 0.0, 1.95) + Vector3(0, 1.05, 0))
	_item("lanterna", base * Vector3(0.7, 0.0, 1.85) + Vector3(0, 1.05, 0), 30.0)
	_item("municao", base * Vector3(3.4, 0.0, 1.2) + Vector3(0, fy - base.origin.y + 1.0, 0))
	# no acampamento, perto da fogueira
	var camp := Vector3(-2.0, 0, 16.0)
	_item("rifle_weatherby", Vector3(camp.x - 2.0, height_at(camp.x - 2.0, camp.z + 2.6) + 0.15, camp.z + 2.6), 20.0)
	_item("machado", Vector3(camp.x - 1.2, height_at(camp.x - 1.2, camp.z + 1) + 0.1, camp.z + 1.0), 60.0)
	_item("panela", Vector3(camp.x, height_at(camp.x, camp.z) + 0.3, camp.z - 0.2))
	_item("caneca", Vector3(camp.x + 0.6, height_at(camp.x + 0.6, camp.z - 1) + 0.1, camp.z - 1.0))
	_item("comida", Vector3(camp.x - 0.5, height_at(camp.x - 0.5, camp.z - 1.2) + 0.1, camp.z - 1.2))
	# armas pelo mapa
	_item("escopeta", Vector3(19.0, height_at(19, 15) + 0.15, 15.0), 70.0)
	var tower := world.find_child("TorreDeVigia", true, false) as Node3D
	if tower:
		_item("ak47", tower.global_transform * Vector3(-0.9, 18.75, -2.6), 40.0)
		_item("kit_medico", tower.global_transform * Vector3(0.6, 18.7, -2.4))
	var c1 := world.find_child("Cabana1", true, false) as Node3D
	if c1:
		_item("m4a1", c1.global_transform * Vector3(0.4, 1.5, 1.9), 0.0)
		_item("pa", c1.global_transform * Vector3(-2.5, 0.6, -1.5), 0.0)
	var c2 := world.find_child("Cabana2", true, false) as Node3D
	if c2:
		_item("caixa_ferramentas", c2.global_transform * Vector3(0.4, 1.5, 1.9))
		_item("galao", c2.global_transform * Vector3(-2.0, 0.8, 0.5))
	# coisas jogadas perto dos carros
	_item("galao", Vector3(-6.0, height_at(-6, 13) + 0.3, 13.0))
	_item("frigideira", Vector3(-148.0, height_at(-148, 50) + 0.1, 50.0))
	_item("fosforos", Vector3(0.9, base.origin.y + 1.6, base.origin.z + 1.95))


func _camp() -> void:
	# fogueira apagada: lenha, pedras e troncos para sentar
	var camp := Vector3(-2.0, 0, 16.0)
	_place("lenha", _ground(camp.x, camp.z), 0.0)
	for i in 7:
		var a := i * TAU / 7.0
		_place("pedra_9", _ground(camp.x + cos(a) * 0.8, camp.z + sin(a) * 0.8), i * 40.0).scale = Vector3.ONE * 0.18
	var log1 := _place("tronco_1", _ground(camp.x + 2.6, camp.z + 0.4), 80.0)
	var log2 := _place("tronco_1", _ground(camp.x - 2.4, camp.z - 0.6), 100.0)
	blocked.append([Vector2(camp.x, camp.z), 7.0])


# ================================================================== cena

func _build_main() -> void:
	root_main = Node3D.new()
	root_main.name = "Main"
	root_main.set_script(load("res://scripts/main.gd"))
	world = Node3D.new()
	world.name = "Mundo"
	root_main.add_child(world)
	props = Node3D.new()
	props.name = "Objetos"
	root_main.add_child(props)
	_environment()
	_terrain()
	_structures()
	_camp()
	_vegetation()
	_lake()
	# no ar da cena para poder lançar raios (itens apoiados nas superfícies de verdade)
	root_main.remove_child(world)
	root.add_child(world)
	for i in 3:
		await physics_frame
	var sp := world.get_world_3d().direct_space_state
	for pt in [Vector2(0, 0), Vector2(19, 15), Vector2(-148, 50), Vector2(100, -300), Vector2(220, 245), Vector2(-1.4, 15)]:
		var r := sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(pt.x, 100, pt.y), Vector3(pt.x, -100, pt.y), 1))
		print("chão ", pt, " visual ", height_at(pt.x, pt.y), " colisão ", r.get("position", Vector3.INF).y, " ", r.get("collider"))
	_items()
	root.remove_child(world)
	root_main.add_child(world)
	root_main.move_child(world, 0)
	var amb := Node3D.new()
	amb.name = "Ambiente"
	amb.set_script(load("res://scripts/ambience.gd"))
	amb.lake_center = Vector3(LAKE.x, LAKE_Y, LAKE.y)
	amb.bird_spots = tree_spots
	root_main.add_child(amb)
	var player: Node3D = load("res://scenes/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector3(2.0, height_at(2.0, 20.0) + 0.1, 20.0)
	root_main.add_child(player)
	_hud()
	_own(root_main, root_main)
	var ps := PackedScene.new()
	assert(ps.pack(root_main) == OK)
	print("main ", ResourceSaver.save(ps, "res://scenes/main.scn", ResourceSaver.FLAG_COMPRESS))
	root_main.free()


func _lake() -> void:
	var lake := Node3D.new()
	lake.name = "Lago"
	lake.position = Vector3(LAKE.x, 0, LAKE.y)
	world.add_child(lake)
	var water := MeshInstance3D.new()
	water.name = "Agua"
	var pm := PlaneMesh.new()
	pm.size = Vector2(LAKE_R * 2.6, LAKE_R * 2.6)
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	wm.set_shader_parameter("shallow", Color(0.2, 0.28, 0.22))
	wm.set_shader_parameter("deep", Color(0.05, 0.09, 0.07))
	pm.material = wm
	water.mesh = pm
	water.position.y = LAKE_Y
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lake.add_child(water)
	var area := Area3D.new()
	area.name = "VolumeAgua"
	area.set_script(load("res://scripts/water.gd"))
	area.surface_y = LAKE_Y
	area.collision_layer = 0
	area.collision_mask = 4 | 2
	area.position = Vector3(0, LAKE_Y - 1.5, 0)
	var cs := CollisionShape3D.new()
	cs.name = "Colisao"
	var cyl := CylinderShape3D.new()
	cyl.radius = LAKE_R + 2.0
	cyl.height = 6.0
	cs.shape = cyl
	area.add_child(cs)
	lake.add_child(area)


func _environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	# céu nublado, sem cor (fim do mundo)
	sm.sky_top_color = Color(0.42, 0.45, 0.48)
	sm.sky_horizon_color = Color(0.62, 0.63, 0.62)
	sm.sky_curve = 0.2
	sm.ground_bottom_color = Color(0.2, 0.2, 0.19)
	sm.ground_horizon_color = Color(0.55, 0.56, 0.54)
	sm.sun_angle_max = 40.0
	sm.sun_curve = 0.3
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.58, 0.6, 0.6)
	env.fog_density = 0.0075
	env.fog_sky_affect = 0.6
	we.environment = env
	root_main.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sol"
	sun.rotation_degrees = Vector3(-48, -40, 0)
	sun.light_color = Color(0.92, 0.9, 0.86)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	root_main.add_child(sun)


func _hud() -> void:
	var pp := CanvasLayer.new()
	pp.name = "PosProcessamento"
	pp.layer = 0
	root_main.add_child(pp)
	var rect := ColorRect.new()
	rect.name = "Imagem"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/post.gdshader")
	pm.set_shader_parameter("saturation", 0.72)
	pm.set_shader_parameter("tint", Color(0.97, 1.0, 0.96))
	pm.set_shader_parameter("contrast", 0.18)
	rect.material = pm
	rect.add_to_group("pos_processamento", true)
	pp.add_child(rect)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	root_main.add_child(hud)
	var ls := LabelSettings.new()
	ls.font_size = 18
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.8)
	var info := Label.new()
	info.name = "Info"
	info.label_settings = ls
	info.position = Vector2(14, 10)
	hud.add_child(info)
	var help := Label.new()
	help.name = "Help"
	var ls2 := ls.duplicate()
	ls2.font_size = 15
	help.label_settings = ls2
	help.text = "WASD mover · Shift correr · Espaço pular · C agachar · E usar/pegar · Q arma · Tab mochila · Clique/F soco · V câmera · R recomeçar"
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_bottom = -10
	hud.add_child(help)
	var dica := Label.new()
	dica.name = "Dica"
	var ls3 := ls.duplicate()
	ls3.font_size = 24
	ls3.font_color = Color(1, 0.87, 0.45)
	dica.label_settings = ls3
	dica.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dica.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dica.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dica.offset_top = 90
	hud.add_child(dica)
	var inv := Control.new()
	inv.name = "Inventario"
	inv.set_script(load("res://scripts/inventory_ui.gd"))
	inv.set_anchors_preset(Control.PRESET_FULL_RECT)
	inv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(inv)
	var touch := Control.new()
	touch.name = "Toque"
	touch.set_script(load("res://scripts/touch_controls.gd"))
	touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(touch)


func _own(n: Node, r: Node) -> void:
	# nós criados aqui (inclusive dentro de cenas instanciadas, como a porta e os móveis da
	# cabana) passam a pertencer à cena; os nós internos das instâncias ficam como estão
	if n != r and n.owner == null:
		n.owner = r
	if n != r and n.scene_file_path != "":
		r.set_editable_instance(n, true)
	for c in n.get_children():
		_own(c, r)


# ================================================================== jogador

func _build_player() -> void:
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.set_script(load("res://scripts/player.gd"))
	p.collision_layer = 4
	p.collision_mask = 1 | 2
	p.floor_max_angle = deg_to_rad(46.0)
	p.floor_snap_length = 0.45
	p.floor_constant_speed = true
	p.safe_margin = 0.02
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	p.add_child(col)
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.top_level = true
	p.add_child(visual)
	var model: Node3D = load("res://assets/ual/UAL1_Standard.glb").instantiate()
	model.name = "Model"
	visual.add_child(model)
	var rig := Node3D.new()
	rig.name = "CamRig"
	rig.top_level = true
	p.add_child(rig)
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	arm.spring_length = 2.6
	arm.margin = 0.12
	arm.collision_mask = 1
	var sph := SphereShape3D.new()
	sph.radius = 0.15
	arm.shape = sph
	rig.add_child(arm)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.fov = 65.0
	cam.near = 0.05
	cam.far = 600.0
	arm.add_child(cam)
	_own(p, p)
	var ps := PackedScene.new()
	ps.pack(p)
	print("player ", ResourceSaver.save(ps, "res://scenes/player.tscn"))
	p.free()
