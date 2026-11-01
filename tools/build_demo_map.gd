extends SceneTree
## Ferramenta de produção: gera a cena de demonstração "posto militar
## abandonado numa clareira de floresta de coníferas".
##
## Uso: godot --headless --path . --script res://tools/build_demo_map.gd
## (os assets da Poly Haven e o atlas das árvores precisam estar importados:
##  python3 tools/download_polyhaven.py; godot --headless --path . --import)
##
## Conteúdo:
## - terreno 160 × 160 m com relevo por ruído, achatado na clareira e ao longo
##   da estrada; pesos de grama/lama/chão de floresta por vértice; colisão
##   com a malha exata do terreno
## - floresta de abetos por impostor (MultiMesh por variante) com troncos
##   reais de casca de pinheiro e colisão cilíndrica por árvore
## - posto militar: barreiras de concreto, caixotes, galões, barris, pneus,
##   latas e ferramentas (objetos soltos são corpos rígidos com massa real e
##   colisão convexa gerada da malha)
## - vegetação baixa, pedras, tocos e troncos caídos
## - fogueira interativa, arame farpado, limites do mapa
## - céu encoberto procedural, sol de manhã com sombras, neblina volumétrica de distância

const OUT := "res://scenes/demo/demo_forest.tscn"
const SIZE := 160.0
const CELL := 2.0
const SEED := 20261101
const PH := "res://assets/polyhaven/"
const TREE_HEIGHTS := [9.0, 7.95, 6.02]
const TREE_COUNT := 900

var _root: Node3D
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _occupied: Array[Vector3] = []


func _initialize() -> void:
	_rng.seed = SEED
	_noise.seed = SEED
	_noise.frequency = 0.010
	_noise.fractal_octaves = 4
	_detail.seed = SEED + 7
	_detail.frequency = 0.08
	_root = Node3D.new()
	_root.name = "DemoForest"
	_environment()
	_terrain()
	_checkpoint()
	_campfire(Vector3(-7.0, 0.0, -11.0))
	_nature_props()
	_forest()
	_boundaries()
	_player_and_ui()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/demo"))
	var packed := PackedScene.new()
	var error := packed.pack(_root)
	if error == OK:
		error = ResourceSaver.save(packed, OUT)
	print("Cena de demonstração gerada: %s" % error_string(error))
	quit(0 if error == OK else 1)


func _own(node: Node, parent: Node = null) -> Node:
	(parent if parent != null else _root).add_child(node)
	node.owner = _root
	return node


# --- Relevo ------------------------------------------------------------------

func _road_x(z: float) -> float:
	return 6.0 * sin(z * 0.025) + 2.0 * sin(z * 0.061)


func height_at(x: float, z: float) -> float:
	var hills := _noise.get_noise_2d(x, z) * 9.0 + _noise.get_noise_2d(x * 0.35 + 300.0, z * 0.35) * 7.0
	var clearing := clampf((Vector2(x, z).length() - 20.0) / 20.0, 0.0, 1.0)
	var road := clampf((absf(x - _road_x(z)) - 3.5) / 7.0, 0.0, 1.0)
	var flat := minf(clearing, road)
	flat = flat * flat * (3.0 - 2.0 * flat)
	return hills * flat + _detail.get_noise_2d(x, z) * 0.035


## Pesos por vértice: R = grama, G = lama (estrada e marcas do acampamento).
func _weights_at(x: float, z: float) -> Color:
	var road := 1.0 - clampf((absf(x - _road_x(z)) - 2.2) / 1.6, 0.0, 1.0)
	var camp := 1.0 - clampf((Vector2(x, z).length() - 9.0) / 5.0, 0.0, 1.0)
	var mud := clampf(maxf(road, camp * 0.6 * (0.5 + 0.5 * _detail.get_noise_2d(x * 2.0, z * 2.0))), 0.0, 1.0)
	var open := 1.0 - clampf((Vector2(x, z).length() - 18.0) / 16.0, 0.0, 1.0)
	var grass := clampf(open * (0.55 + 0.45 * _noise.get_noise_2d(x * 4.0, z * 4.0)) * (1.0 - mud), 0.0, 1.0)
	return Color(grass, mud, 0.0)


func _terrain() -> void:
	var count := int(SIZE / CELL) + 1
	var half := SIZE * 0.5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for iz in count:
		for ix in count:
			var x := -half + ix * CELL
			var z := -half + iz * CELL
			var h := height_at(x, z)
			vertices.append(Vector3(x, h, z))
			var dx := height_at(x + 0.5, z) - height_at(x - 0.5, z)
			var dz := height_at(x, z + 0.5) - height_at(x, z - 0.5)
			normals.append(Vector3(-dx, 1.0, -dz).normalized())
			colors.append(_weights_at(x, z))
	for iz in count - 1:
		for ix in count - 1:
			var a := iz * count + ix
			var b := a + 1
			var c := a + count
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = load("res://resources/materials/terrain.gdshader")
	for layer in [["floor", "forest_floor"], ["grass", "leafy_grass"], ["mud", "brown_mud_leaves_01"]]:
		var folder := PH + "textures/%s/%s_" % [layer[1], layer[1]]
		material.set_shader_parameter(layer[0] + "_albedo", load(folder + "albedo_1k.jpg"))
		material.set_shader_parameter(layer[0] + "_normal", load(folder + "normal_1k.jpg"))
		material.set_shader_parameter(layer[0] + "_arm", load(folder + "arm_1k.jpg"))
	mesh.surface_set_material(0, material)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/models/demo"))
	ResourceSaver.save(mesh, "res://resources/models/demo/terrain.res")
	mesh = load("res://resources/models/demo/terrain.res")

	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"surface_profile", load("res://resources/surfaces/terra.tres"))
	_own(body)
	var instance := MeshInstance3D.new()
	instance.name = "TerrainMesh"
	instance.mesh = mesh
	_own(instance, body)
	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var concave := mesh.create_trimesh_shape()
	ResourceSaver.save(concave, "res://resources/models/demo/terrain_collision.res")
	shape.shape = load("res://resources/models/demo/terrain_collision.res")
	_own(shape, body)


# --- Ambiente ----------------------------------------------------------------

func _environment() -> void:
	# Céu encoberto procedural: a floresta é geometria de verdade, então o céu
	# não pode trazer árvores pintadas (um HDRI de mata mostraria troncos
	# "pendurados" acima das copas). Também é mais leve no celular.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.42, 0.50, 0.58)
	sky_material.sky_horizon_color = Color(0.70, 0.72, 0.72)
	sky_material.sky_curve = 0.12
	sky_material.ground_bottom_color = Color(0.10, 0.11, 0.09)
	sky_material.ground_horizon_color = Color(0.45, 0.47, 0.45)
	sky_material.sun_angle_max = 20.0
	sky_material.sun_curve = 0.08
	sky_material.energy_multiplier = 0.85
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.7
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.95
	environment.tonemap_white = 6.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.38, 0.42, 0.42)
	environment.fog_density = 0.0085
	environment.fog_sky_affect = 0.2
	environment.fog_aerial_perspective = 0.25
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.04
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.88
	environment.adjustment_contrast = 1.06
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = environment
	_own(world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38.0, -125.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 55.0
	sun.directional_shadow_split_1 = 0.25
	_own(sun)


# --- Props -------------------------------------------------------------------

## Instancia um modelo da Poly Haven apoiado no chão. Corpo rígido (massa > 0)
## ou estático, com colisão convexa gerada dos vértices do modelo.
func _prop(asset: String, position: Vector3, yaw_degrees: float, mass: float = 0.0,
		scale: float = 1.0, on_ground: bool = true, parent: Node = null) -> Node3D:
	var scene: PackedScene = load(PH + "models/%s/%s_1k.gltf" % [asset, asset])
	var model: Node3D = scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var bounds := _bounds(model)
	var points := _hull_points(model)
	var body: CollisionObject3D
	if mass > 0.0:
		var rigid := RigidBody3D.new()
		rigid.mass = mass
		rigid.collision_layer = 4
		rigid.collision_mask = 1 | 2 | 4 | 128
		var material := PhysicsMaterial.new()
		material.friction = 0.8
		material.bounce = 0.05
		rigid.physics_material_override = material
		body = rigid
	else:
		var static_body := StaticBody3D.new()
		static_body.collision_layer = 1
		static_body.collision_mask = 0
		body = static_body
	body.name = asset.to_pascal_case() + "_%d" % _rng.randi_range(100, 999)
	var ground := height_at(position.x, position.z) if on_ground else position.y
	body.position = Vector3(position.x, ground - bounds.position.y * scale + 0.01, position.z)
	body.rotation_degrees.y = yaw_degrees
	_own(body, parent)
	model.name = "Model"
	model.scale = Vector3.ONE * scale
	_own(model, body)
	var shape := ConvexPolygonShape3D.new()
	var scaled := PackedVector3Array()
	for p in points:
		scaled.append(p * scale)
	shape.points = scaled
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	_own(collision, body)
	_occupied.append(Vector3(position.x, 0.0, position.z))
	return body


func _bounds(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box := _relative_transform(model, mesh) * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


## Até ~150 pontos da superfície (amostragem uniforme) para o casco convexo.
func _hull_points(model: Node3D) -> PackedVector3Array:
	var all := PackedVector3Array()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var xform := _relative_transform(model, mesh)
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for v in vertices:
				all.append(xform * v)
	var step := maxi(all.size() / 150, 1)
	var points := PackedVector3Array()
	for i in range(0, all.size(), step):
		points.append(all[i])
	return points


func _checkpoint() -> void:
	var group := Node3D.new()
	group.name = "Checkpoint"
	_own(group)
	var road_center := _road_x(-6.0)
	# Bloqueio da estrada com barreiras de concreto.
	for i in 3:
		_prop("concrete_road_barrier_02", Vector3(road_center - 3.3 + i * 3.1, 0.0, -6.0 + (i % 2) * 0.6), 90.0 + _rng.randf_range(-8.0, 8.0), 0.0, 1.0, true, group)
	# Caixotes e suprimentos.
	_prop("wooden_military_crate", Vector3(6.0, 0.0, -2.5), 15.0, 30.0, 1.0, true, group)
	_prop("old_military_crate", Vector3(7.4, 0.0, -0.8), -20.0, 18.0, 1.0, true, group)
	_prop("metal_jerrycan_green", Vector3(5.2, 0.0, -0.6), 40.0, 8.0, 1.0, true, group)
	_prop("utility_box_01", Vector3(-4.5, 0.0, -7.5), 180.0, 0.0, 1.0, true, group)
	for i in 3:
		_prop("Barrel_02", Vector3(-6.0 + i * 0.75, 0.0, 2.5 + (i % 2) * 0.6), _rng.randf_range(0.0, 360.0), 25.0, 1.0, true, group)
	_prop("wooden_barrels_01", Vector3(-10.0, 0.0, 5.0), 30.0, 0.0, 1.0, true, group)
	_prop("old_tyre", Vector3(4.0, 0.0, 3.5), 70.0, 10.0, 1.0, true, group)
	_prop("old_tyre", Vector3(-3.0, 0.0, -9.5), 10.0, 10.0, 1.0, true, group)
	# Latas e ferramentas sobre o caixote (corpos rígidos leves).
	var crate_top := height_at(6.0, -2.5) + 0.53
	_prop("russian_food_cans_01", Vector3(5.85, crate_top, -2.6), 0.0, 0.5, 1.0, false, group)
	_prop("can_rusted", Vector3(6.25, crate_top, -2.35), 0.0, 0.4, 1.0, false, group)
	_prop("machete", Vector3(5.9, 0.0, 1.6), 30.0, 0.7, 1.0, true, group)
	_prop("wooden_axe", Vector3(-8.6, 0.0, 3.6), -50.0, 1.4, 1.0, true, group)
	_prop("crowbar_01", Vector3(-3.6, 0.0, -8.4), 75.0, 2.0, 1.0, true, group)
	_barbed_wire(Vector3(road_center + 6.5, 0.0, -6.4), group)


func _barbed_wire(center: Vector3, parent: Node) -> void:
	var area := Area3D.new()
	area.name = "BarbedWire"
	area.position = Vector3(center.x, height_at(center.x, center.z) + 0.5, center.z)
	area.collision_layer = 0
	area.collision_mask = 2
	area.set_script(load("res://scripts/world/damage_zone.gd"))
	_own(area, parent)
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 1.0, 1.4)
	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	shape.shape = box
	_own(shape, area)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.31, 0.29)
	steel.metallic = 0.85
	steel.roughness = 0.55
	# Rolo de concertina: espiral de arame ao longo do eixo X.
	var curve := Curve3D.new()
	for i in 220:
		var t := float(i) / 219.0
		var angle := t * TAU * 22.0
		curve.add_point(Vector3(-2.0 + 4.0 * t, sin(angle) * 0.42, cos(angle) * 0.42))
	var path := Path3D.new()
	path.name = "Coil"
	path.curve = curve
	_own(path, area)
	var wire := CSGPolygon3D.new()
	wire.name = "Wire"
	wire.mode = CSGPolygon3D.MODE_PATH
	wire.path_node = NodePath("..")
	wire.polygon = PackedVector2Array([Vector2(-0.006, -0.006), Vector2(0.006, -0.006), Vector2(0.006, 0.006), Vector2(-0.006, 0.006)])
	wire.path_interval = 0.08
	wire.material = steel
	_own(wire, path)
	for x in [-2.0, 2.0]:
		var post := CSGCylinder3D.new()
		post.name = "Post%d" % int(x)
		post.radius = 0.03
		post.height = 1.1
		post.position = Vector3(x, 0.05, 0.0)
		post.material = steel
		_own(post, area)


func _campfire(position: Vector3) -> void:
	var pit := _prop("stone_fire_pit", position, 0.0)
	pit.collision_layer = 1 | 16
	var top := 0.35
	var light := OmniLight3D.new()
	light.name = "FireLight"
	light.position = Vector3(0.0, top + 0.4, 0.0)
	light.light_color = Color(1.0, 0.62, 0.30)
	light.omni_range = 9.0
	light.shadow_enabled = false
	_own(light, pit)
	var flames := _fire_particles("Flames", Color(1.0, 0.55, 0.15), 0.9, 0.35, 40, true)
	flames.position = Vector3(0.0, top, 0.0)
	_own(flames, pit)
	var smoke := _fire_particles("Smoke", Color(0.35, 0.34, 0.33, 0.35), 3.5, 0.9, 24, false)
	smoke.position = Vector3(0.0, top + 0.6, 0.0)
	_own(smoke, pit)
	var fire := Node.new()
	fire.name = "Campfire"
	fire.set_script(load("res://scripts/world/campfire.gd"))
	_own(fire, pit)
	fire.set("light", light)
	fire.set("flames", flames)
	fire.set("smoke", smoke)
	# Troncos caídos servem de bancos.
	_prop("dead_tree_trunk", position + Vector3(2.4, 0.0, 0.6), 80.0, 0.0, 0.55)
	_prop("tree_stump_01", position + Vector3(-1.8, 0.0, 1.6), 0.0, 0.0, 0.6)


func _fire_particles(node_name: String, color: Color, lifetime: float, size: float, amount: int, additive: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emitting = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.18
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 0.4 if additive else 0.3
	process.initial_velocity_max = 0.9 if additive else 0.6
	process.gravity = Vector3(0.15, 0.6 if additive else 0.25, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(color, color.a))
	fade.set_color(1, Color(color.r * 0.5, color.g * 0.3, color.b * 0.2, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = soft
	var material := StandardMaterial3D.new()
	material.albedo_texture = dot
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = material
	particles.draw_pass_1 = quad
	return particles


func _nature_props() -> void:
	var group := Node3D.new()
	group.name = "Nature"
	_own(group)
	_prop("boulder_01", Vector3(19.0, 0.0, -14.0), 40.0, 0.0, 1.0, true, group)
	for spot in [Vector3(-17.0, 0, 11.0), Vector3(22.0, 0, 9.0), Vector3(-21.0, 0, -18.0)]:
		_prop("rock_moss_set_01", spot, _rng.randf_range(0.0, 360.0), 0.0, 0.6, true, group)
	for spot in [Vector3(13.0, 0, 15.0), Vector3(-15.0, 0, -4.0), Vector3(17.0, 0, -3.0), Vector3(-12.0, 0, 19.0)]:
		_prop("tree_stump_01", spot, _rng.randf_range(0.0, 360.0), 0.0, 0.8, true, group)
	_prop("dead_tree_trunk", Vector3(24.0, 0.0, 2.0), 20.0, 0.0, 1.0, true, group)
	var placed := 0
	while placed < 28:
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(16.0, 30.0)
		var spot := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if absf(spot.x - _road_x(spot.z)) < 4.5:
			continue
		var asset := "fern_02" if placed % 3 != 0 else "shrub_03"
		var plant := _prop(asset, spot, _rng.randf_range(0.0, 360.0), 0.0, _rng.randf_range(0.8, 1.3), true, group)
		# Plantas não bloqueiam a passagem.
		plant.collision_layer = 0
		placed += 1


# --- Floresta ----------------------------------------------------------------

func _forest() -> void:
	var group := Node3D.new()
	group.name = "Forest"
	_own(group)
	var atlas: Texture2D = load("res://resources/textures/trees/fir_cards.png")
	var transforms: Array = [[], [], []]
	var trunk_transforms := []
	var colliders := StaticBody3D.new()
	colliders.name = "TreeTrunkColliders"
	colliders.collision_layer = 1
	_own(colliders, group)
	var tries := 0
	var placed: Array[Vector3] = []
	while placed.size() < TREE_COUNT and tries < 40000:
		tries += 1
		# Mata fechada em todo o mapa, a partir da borda da clareira.
		var limit := SIZE * 0.5 - 3.5
		var spot := Vector3(_rng.randf_range(-limit, limit), 0.0, _rng.randf_range(-limit, limit))
		if Vector2(spot.x, spot.z).length() < 23.0:
			continue
		if absf(spot.x - _road_x(spot.z)) < 6.0:
			continue
		var crowded := false
		for other in placed:
			if other.distance_to(spot) < 2.7:
				crowded = true
				break
		for other in _occupied:
			if other.distance_to(spot) < 3.0:
				crowded = true
				break
		if crowded:
			continue
		placed.append(spot)
		var variant := _rng.randi_range(0, 2)
		var scale := _rng.randf_range(1.35, 2.1)
		var ground := height_at(spot.x, spot.z) - 0.2
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scale)
		transforms[variant].append(Transform3D(basis, Vector3(spot.x, ground, spot.z)))
		var tree_height: float = TREE_HEIGHTS[variant] * scale
		var trunk_scale := Vector3(scale * 0.9, tree_height * 0.42, scale * 0.9)
		trunk_transforms.append(Transform3D(Basis.IDENTITY.scaled(trunk_scale), Vector3(spot.x, ground + trunk_scale.y * 0.5, spot.z)))
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.16 * scale
		cylinder.height = 4.0
		var shape := CollisionShape3D.new()
		shape.name = "Trunk%d" % placed.size()
		shape.shape = cylinder
		shape.position = Vector3(spot.x, ground + 2.0, spot.z)
		_own(shape, colliders)
	for variant in 3:
		_own(_scatter("Firs%d" % variant, _card_mesh(variant, atlas), transforms[variant]), group)
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.05
	trunk_mesh.bottom_radius = 0.17
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 8
	trunk_mesh.rings = 1
	var bark := ORMMaterial3D.new()
	var folder := PH + "textures/pine_bark/pine_bark_"
	bark.albedo_texture = load(folder + "albedo_1k.jpg")
	bark.normal_enabled = true
	bark.normal_texture = load(folder + "normal_1k.jpg")
	bark.orm_texture = load(folder + "arm_1k.jpg")
	bark.uv1_scale = Vector3(2.0, 4.0, 1.0)
	trunk_mesh.material = bark
	_own(_scatter("Trunks", trunk_mesh, trunk_transforms), group)
	print("Árvores: %d (variantes %d/%d/%d)" % [placed.size(), transforms[0].size(), transforms[1].size(), transforms[2].size()])


func _scatter(node_name: String, mesh: Mesh, list: Array) -> ScatterInstances:
	var scatter := ScatterInstances.new()
	scatter.name = node_name
	scatter.mesh = mesh
	var typed: Array[Transform3D] = []
	typed.assign(list)
	scatter.transforms = typed
	return scatter


## Três planos cruzados (0°, 60°, 120°) com os quadros da variante no atlas.
func _card_mesh(variant: int, atlas: Texture2D) -> ArrayMesh:
	var height: float = TREE_HEIGHTS[variant]
	var width := height * 0.5
	var bottom := -height * 0.01
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for column in 3:
		var basis := Basis(Vector3.UP, deg_to_rad(column * 60.0))
		var u0 := column / 3.0
		var u1 := (column + 1) / 3.0
		var v0 := variant / 3.0
		var v1 := (variant + 1) / 3.0
		var base := vertices.size()
		vertices.append(basis * Vector3(-width * 0.5, bottom, 0.0))
		vertices.append(basis * Vector3(width * 0.5, bottom, 0.0))
		vertices.append(basis * Vector3(width * 0.5, bottom + height, 0.0))
		vertices.append(basis * Vector3(-width * 0.5, bottom + height, 0.0))
		uvs.append_array([Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)])
		indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = load("res://resources/materials/tree_card.gdshader")
	material.set_shader_parameter("atlas", atlas)
	material.set_shader_parameter("card_height", height)
	mesh.surface_set_material(0, material)
	mesh.custom_aabb = AABB(Vector3(-width, bottom, -width), Vector3(width * 2.0, height, width * 2.0))
	return mesh


func _boundaries() -> void:
	var walls := StaticBody3D.new()
	walls.name = "MapBoundary"
	walls.collision_layer = 1
	_own(walls)
	var limit := SIZE * 0.5 - 3.0
	for side in [Vector3(limit, 0, 0), Vector3(-limit, 0, 0), Vector3(0, 0, limit), Vector3(0, 0, -limit)]:
		var box := BoxShape3D.new()
		box.size = Vector3(0.5 if side.x != 0.0 else SIZE, 40.0, 0.5 if side.z != 0.0 else SIZE)
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = side + Vector3(0.0, 10.0, 0.0)
		_own(shape, walls)


# --- Jogador e interface -----------------------------------------------------

func _player_and_ui() -> void:
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	player.name = "Player"
	var spawn_z := 16.0
	player.position = Vector3(_road_x(spawn_z), height_at(_road_x(spawn_z), spawn_z) + 0.05, spawn_z)
	_own(player)
	var touch: Node = (load("res://scenes/ui/touch_controls.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	touch.name = "TouchControlsLayer"
	_own(touch)
	var hud := CanvasLayer.new()
	hud.name = "PlayerHud"
	hud.set_script(load("res://scripts/ui/player_hud.gd"))
	_own(hud)
	hud.set("player", player)
	hud.set("interaction", player.get_node("Interaction"))
	hud.set("death", player.get_node("Death"))
	hud.set("camera_rig", player.get_node("CameraRig"))
	var debug_layer := CanvasLayer.new()
	debug_layer.name = "DebugLayer"
	debug_layer.layer = 20
	_own(debug_layer)
	var debug := Label.new()
	debug.name = "MovementDebugHud"
	debug.set_script(load("res://scripts/debug/movement_debug_hud.gd"))
	debug.position = Vector2(16.0, 60.0)
	debug.add_theme_font_size_override("font_size", 14)
	debug.add_theme_color_override("font_outline_color", Color.BLACK)
	debug.add_theme_constant_override("outline_size", 4)
	_own(debug, debug_layer)
	debug.set("player", player)
