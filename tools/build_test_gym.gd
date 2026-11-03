extends SceneTree
## Ferramenta de manutenção: gera scenes/test/movement_test_gym.tscn, a área
## de calibração do movimento (não é o mapa do jogo).
## Uso: godot --headless --path . --script res://tools/build_test_gym.gd

const OUTPUT_SCENE := "res://scenes/test/movement_test_gym.tscn"
const GRID_SHADER := "res://resources/materials/dev_grid.gdshader"

const LAYER_WORLD := 1
const LAYER_PROPS := 4
const MASK_PROPS := 1 | 2 | 4

var _root: Node3D
var _materials: Dictionary = {}


func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "MovementTestGym"
	_create_materials()
	_add_environment()
	_add_ground()
	_add_stairs()
	_add_step_blocks()
	_add_ramps()
	_add_crouch_tunnel()
	_add_drop_tower()
	_add_walls()
	_add_rigid_props()
	_add_surface_patches()
	_add_head_beam()
	_add_light_switch()
	_add_barbed_wire()
	_add_training_dummy()
	_add_player_and_ui()

	var packed := PackedScene.new()
	var error := packed.pack(_root)
	if error == OK:
		error = ResourceSaver.save(packed, OUTPUT_SCENE)
	print("Cena de teste gerada: ", error_string(error))
	_root.free()
	quit(0 if error == OK else 1)


func _create_materials() -> void:
	var shader: Shader = load(GRID_SHADER)
	_materials["ground"] = _grid_material(shader, Color(0.33, 0.35, 0.31), Color(0.2, 0.22, 0.19), "ground")
	_materials["concrete"] = _grid_material(shader, Color(0.52, 0.51, 0.48), Color(0.33, 0.32, 0.3), "concrete")
	_materials["ramp"] = _grid_material(shader, Color(0.45, 0.42, 0.36), Color(0.27, 0.25, 0.21), "ramp")
	_materials["steep"] = _grid_material(shader, Color(0.5, 0.3, 0.26), Color(0.3, 0.17, 0.14), "steep")
	_materials["wood"] = _standard_material(Color(0.55, 0.4, 0.25), 0.8, 0.0)
	_materials["metal"] = _standard_material(Color(0.32, 0.36, 0.38), 0.45, 0.8)
	_materials["heavy"] = _standard_material(Color(0.25, 0.27, 0.24), 0.7, 0.2)
	_materials["ice"] = _grid_material(shader, Color(0.72, 0.84, 0.92), Color(0.55, 0.68, 0.78), "ice")
	(_materials["ice"] as ShaderMaterial).set_shader_parameter("roughness_value", 0.15)
	_materials["mud"] = _grid_material(shader, Color(0.3, 0.22, 0.14), Color(0.22, 0.16, 0.1), "mud")


func _grid_material(shader: Shader, base: Color, line: Color, id: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", base)
	material.set_shader_parameter("line_color", line)
	material.resource_name = id
	return material


func _standard_material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _own(node: Node, parent: Node = null) -> Node:
	(parent if parent != null else _root).add_child(node)
	node.owner = _root
	return node


func _add_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.36, 0.45, 0.56)
	sky_material.sky_horizon_color = Color(0.66, 0.63, 0.6)
	sky_material.ground_horizon_color = Color(0.5, 0.48, 0.45)
	sky_material.ground_bottom_color = Color(0.18, 0.17, 0.16)
	sky_material.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.62, 0.62, 0.6)
	environment.fog_density = 0.006
	environment.fog_sky_affect = 0.25

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	_own(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.84)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	_own(sun)


func _add_static_box(node_name: String, size: Vector3, transform: Transform3D, material_id: String, parent: Node = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.transform = transform
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	_own(body, parent)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _materials[material_id]
	_own(mesh_instance, body)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	_own(collision, body)
	return body


func _add_label(text: String, position: Vector3, parent: Node = null) -> void:
	var label := Label3D.new()
	label.name = "Label_" + text.validate_node_name().replace(" ", "_")
	label.text = text
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.font_size = 64
	label.pixel_size = 0.004
	label.outline_size = 12
	label.modulate = Color(1, 1, 1, 0.9)
	_own(label, parent)


func _group(node_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = node_name
	_own(group)
	return group


func _add_ground() -> void:
	_add_static_box("Ground", Vector3(80.0, 1.0, 80.0), Transform3D(Basis.IDENTITY, Vector3(0.0, -0.5, 0.0)), "ground")


## Escada: 8 degraus de 18 cm x 30 cm (padrão residencial) até um patamar.
func _add_stairs() -> void:
	var group := _group("Stairs")
	var step_height := 0.18
	var step_depth := 0.3
	var width := 2.0
	var origin := Vector3(4.0, 0.0, -1.0)
	for i in 8:
		var height := step_height * (i + 1)
		var center := origin + Vector3(0.0, height * 0.5, -step_depth * (i + 0.5))
		_add_static_box("Step%d" % (i + 1), Vector3(width, height, step_depth), Transform3D(Basis.IDENTITY, center), "concrete", group)
	var top := step_height * 8
	var landing_depth := 3.0
	var landing_center := origin + Vector3(0.0, top * 0.5, -step_depth * 8 - landing_depth * 0.5)
	_add_static_box("Landing", Vector3(width + 1.0, top, landing_depth), Transform3D(Basis.IDENTITY, landing_center), "concrete", group)
	_add_label("Escada 18 cm", origin + Vector3(0.0, 1.0, 0.6), group)


## Blocos isolados para testar o limite de subida de degrau (32 cm).
func _add_step_blocks() -> void:
	var group := _group("StepBlocks")
	var heights := [0.1, 0.2, 0.3, 0.45]
	for i in heights.size():
		var h: float = heights[i]
		var center := Vector3(-3.0 - i * 2.2, h * 0.5, -3.0)
		_add_static_box("Block_%dcm" % int(h * 100.0), Vector3(1.6, h, 1.6), Transform3D(Basis.IDENTITY, center), "concrete", group)
		_add_label("%d cm" % int(h * 100.0), center + Vector3(0.0, h * 0.5 + 0.6, 0.9), group)


## Rampas de 15°, 30°, 45° (caminháveis) e 55° (íngreme demais).
func _add_ramps() -> void:
	var group := _group("Ramps")
	var angles := [15.0, 30.0, 45.0, 55.0]
	var length := 6.0
	var thickness := 0.2
	for i in angles.size():
		var angle: float = angles[i]
		var radians := deg_to_rad(angle)
		var x := 9.0 + i * 3.0
		var center_y := sin(radians) * length * 0.5 - cos(radians) * thickness * 0.5
		var center_z := -1.0 - cos(radians) * length * 0.5
		var basis := Basis(Vector3.RIGHT, radians)
		var material := "steep" if angle > 46.0 else "ramp"
		_add_static_box("Ramp_%d" % int(angle), Vector3(2.4, thickness, length), Transform3D(basis, Vector3(x, center_y, center_z)), material, group)
		var top_height := sin(radians) * length
		var top_z := -1.0 - cos(radians) * length
		_add_static_box("RampTop_%d" % int(angle), Vector3(2.4, top_height, 1.5),
				Transform3D(Basis.IDENTITY, Vector3(x, top_height * 0.5 - 0.01, top_z - 0.75)), material, group)
		_add_label("Rampa %d°" % int(angle), Vector3(x, 1.2, 0.0), group)


## Túnel com teto a 1,35 m: só é possível atravessar agachado.
func _add_crouch_tunnel() -> void:
	var group := _group("CrouchTunnel")
	var length := 6.0
	var clear_height := 1.35
	var center_x := -12.0
	var z_center := -6.0
	_add_static_box("Roof", Vector3(2.4, 0.3, length), Transform3D(Basis.IDENTITY, Vector3(center_x, clear_height + 0.15, z_center)), "concrete", group)
	_add_static_box("WallLeft", Vector3(0.3, clear_height, length), Transform3D(Basis.IDENTITY, Vector3(center_x - 1.05, clear_height * 0.5, z_center)), "concrete", group)
	_add_static_box("WallRight", Vector3(0.3, clear_height, length), Transform3D(Basis.IDENTITY, Vector3(center_x + 1.05, clear_height * 0.5, z_center)), "concrete", group)
	_add_label("Túnel 1,35 m (agachar)", Vector3(center_x, 2.2, z_center + length * 0.5 + 0.2), group)


## Torre com rampa de 25° até 6 m e um patamar intermediário a 3 m, para
## testar queda, aterrissagem e dano.
func _add_drop_tower() -> void:
	var group := _group("DropTower")
	var top := 6.0
	var angle := deg_to_rad(25.0)
	var length := top / sin(angle)
	var thickness := 0.3
	var x := -22.0
	var start_z := 4.0
	var center_y := sin(angle) * length * 0.5 - cos(angle) * thickness * 0.5
	var center_z := start_z - cos(angle) * length * 0.5
	_add_static_box("TowerRamp", Vector3(2.4, thickness, length), Transform3D(Basis(Vector3.RIGHT, angle), Vector3(x, center_y, center_z)), "ramp", group)
	var top_z := start_z - cos(angle) * length
	_add_static_box("Platform6m", Vector3(4.0, 0.4, 4.0), Transform3D(Basis.IDENTITY, Vector3(x, top - 0.2, top_z - 2.0)), "concrete", group)
	_add_static_box("Pillar6m", Vector3(1.0, top - 0.4, 1.0), Transform3D(Basis.IDENTITY, Vector3(x, (top - 0.4) * 0.5, top_z - 2.0)), "concrete", group)
	_add_static_box("Platform3m", Vector3(3.0, 0.4, 3.0), Transform3D(Basis.IDENTITY, Vector3(x + 3.5, 2.8, top_z - 2.0)), "concrete", group)
	_add_static_box("Pillar3m", Vector3(0.8, 2.6, 0.8), Transform3D(Basis.IDENTITY, Vector3(x + 3.5, 1.3, top_z - 2.0)), "concrete", group)
	_add_label("Queda 6 m", Vector3(x, top + 1.0, top_z - 2.0), group)
	_add_label("Queda 3 m", Vector3(x + 3.5, 4.0, top_z - 2.0), group)


func _add_walls() -> void:
	var group := _group("Walls")
	_add_static_box("WallNorth", Vector3(30.0, 3.0, 0.4), Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, -20.0)), "concrete", group)
	_add_static_box("WallAngled", Vector3(8.0, 3.0, 0.4), Transform3D(Basis(Vector3.UP, deg_to_rad(35.0)), Vector3(-6.0, 1.5, -15.0)), "concrete", group)
	_add_label("Paredes (deslizar)", Vector3(0.0, 3.6, -19.6), group)


func _add_rigid_box(node_name: String, size: Vector3, mass: float, position: Vector3, material_id: String, parent: Node) -> void:
	var body := RigidBody3D.new()
	body.name = node_name
	body.mass = mass
	body.position = position
	body.collision_layer = LAYER_PROPS
	body.collision_mask = MASK_PROPS
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.75
	physics_material.bounce = 0.05
	body.physics_material_override = physics_material
	_own(body, parent)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _materials[material_id]
	_own(mesh_instance, body)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	_own(collision, body)


func _add_rigid_barrel(node_name: String, radius: float, height: float, mass: float, position: Vector3, parent: Node) -> void:
	var body := RigidBody3D.new()
	body.name = node_name
	body.mass = mass
	body.position = position
	body.collision_layer = LAYER_PROPS
	body.collision_mask = MASK_PROPS
	_own(body, parent)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _materials["metal"]
	_own(mesh_instance, body)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	_own(collision, body)


## Objetos com massas reais para testar empurrar e pisar.
func _add_rigid_props() -> void:
	var group := _group("PhysicsProps")
	_add_rigid_box("Crate5kg", Vector3(0.45, 0.45, 0.45), 5.0, Vector3(-1.5, 0.225, -9.0), "wood", group)
	_add_rigid_box("Crate20kg", Vector3(0.7, 0.7, 0.7), 20.0, Vector3(0.0, 0.35, -9.0), "wood", group)
	_add_rigid_box("Block300kg", Vector3(1.2, 1.2, 1.2), 300.0, Vector3(2.0, 0.6, -9.0), "heavy", group)
	_add_rigid_barrel("Barrel15kg", 0.29, 0.88, 15.0, Vector3(-3.0, 0.44, -10.5), group)
	_add_label("Objetos físicos (5, 15, 20 e 300 kg)", Vector3(0.0, 1.8, -8.0), group)


## Placas rentes ao chão (2 cm) com perfis de superfície: gelo e lama.
func _add_surface_patches() -> void:
	var group := _group("SurfacePatches")
	var ice := _add_static_box("Ice", Vector3(7.0, 0.02, 20.0), Transform3D(Basis.IDENTITY, Vector3(-32.0, 0.01, 12.0)), "ice", group)
	ice.set_meta(&"surface_profile", load("res://resources/surfaces/gelo.tres"))
	_add_label("Gelo (μ 0,08)", Vector3(-32.0, 1.6, 1.6), group)
	var mud := _add_static_box("Mud", Vector3(8.0, 0.02, 16.0), Transform3D(Basis.IDENTITY, Vector3(20.0, 0.01, 22.0)), "mud", group)
	mud.set_meta(&"surface_profile", load("res://resources/surfaces/lama.tres"))
	_add_label("Lama (μ 0,5, passo 75%)", Vector3(20.0, 1.6, 13.6), group)


## Viga com face inferior a 2,15 m: a cabeça bate nela ao saltar embaixo.
func _add_head_beam() -> void:
	var group := _group("HeadBeam")
	_add_static_box("Beam", Vector3(3.0, 0.2, 0.4), Transform3D(Basis.IDENTITY, Vector3(0.0, 2.25, 14.0)), "concrete", group)
	_add_static_box("PostLeft", Vector3(0.2, 2.35, 0.2), Transform3D(Basis.IDENTITY, Vector3(-1.6, 1.175, 14.0)), "concrete", group)
	_add_static_box("PostRight", Vector3(0.2, 2.35, 0.2), Transform3D(Basis.IDENTITY, Vector3(1.6, 1.175, 14.0)), "concrete", group)
	_add_label("Viga 2,15 m (saltar)", Vector3(0.0, 2.9, 14.0), group)


## Interruptor num poste com lâmpada: testa interação sincronizada com a mão.
func _add_light_switch() -> void:
	var group := _group("LightSwitchStation")
	_add_static_box("Post", Vector3(0.12, 2.8, 0.12), Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.4, 1.9)), "concrete", group)
	var panel := _add_static_box("SwitchPanel", Vector3(0.22, 0.30, 0.06), Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.30, 1.99)), "metal", group)
	panel.collision_layer = 1 | 16
	var lever_pivot := Node3D.new()
	lever_pivot.name = "LeverPivot"
	lever_pivot.position = Vector3(0.0, 0.0, 0.04)
	_own(lever_pivot, panel)
	var lever_mesh := BoxMesh.new()
	lever_mesh.size = Vector3(0.035, 0.11, 0.03)
	var lever := MeshInstance3D.new()
	lever.name = "Lever"
	lever.mesh = lever_mesh
	lever.position = Vector3(0.0, 0.045, 0.0)
	lever.material_override = _standard_material(Color(0.75, 0.12, 0.08), 0.5, 0.2)
	_own(lever, lever_pivot)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(-3.0, 2.75, 2.25)
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 3.0
	lamp.omni_range = 7.0
	_own(lamp, group)
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.07
	bulb_mesh.height = 0.14
	var bulb_material := StandardMaterial3D.new()
	bulb_material.albedo_color = Color(1.0, 0.9, 0.7)
	bulb_material.emission_enabled = true
	bulb_material.emission = Color(1.0, 0.8, 0.5)
	var bulb := MeshInstance3D.new()
	bulb.name = "Bulb"
	bulb.mesh = bulb_mesh
	bulb.material_override = bulb_material
	_own(bulb, lamp)
	var switch := Node.new()
	switch.name = "Switch"
	switch.set_script(load("res://scripts/interaction/light_switch.gd"))
	_own(switch, panel)
	switch.set("light", lamp)
	switch.set("lever", lever_pivot)
	_add_label("Interruptor (USAR)", Vector3(-3.0, 3.1, 2.0), group)


## Faixa de arame farpado: dano contínuo e lentidão (ferimentos e morte).
func _add_barbed_wire() -> void:
	var group := _group("BarbedWire")
	var area := Area3D.new()
	area.name = "WireZone"
	area.position = Vector3(8.0, 0.5, 8.0)
	area.collision_layer = 0
	area.collision_mask = 2
	area.set_script(load("res://scripts/world/damage_zone.gd"))
	_own(area, group)
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 1.0, 2.0)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	_own(collision, area)
	var wire_material := _standard_material(Color(0.35, 0.33, 0.30), 0.4, 0.9)
	for i in 5:
		var strand := CylinderMesh.new()
		strand.top_radius = 0.006
		strand.bottom_radius = 0.006
		strand.height = 3.0
		strand.radial_segments = 6
		var mesh := MeshInstance3D.new()
		mesh.name = "Strand%d" % i
		mesh.mesh = strand
		mesh.material_override = wire_material
		mesh.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		mesh.position = Vector3(0.0, -0.35 + 0.17 * i, -0.8 + 0.4 * i)
		_own(mesh, area)
	_add_label("Arame farpado (fere)", Vector3(8.0, 1.6, 9.2), group)


## Boneco de treino: alvo dos golpes (recebe dano e balança).
func _add_training_dummy() -> void:
	var group := _group("TrainingDummyStation")
	var dummy := StaticBody3D.new()
	dummy.name = "TrainingDummy"
	dummy.position = Vector3(-5.0, 0.0, 9.0)
	dummy.collision_layer = 1
	dummy.set_script(load("res://scripts/world/training_dummy.gd"))
	_own(dummy, group)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 1.8, 0.5)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	collision.position = Vector3(0.0, 0.9, 0.0)
	_own(collision, dummy)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0.0, 0.25, 0.0)
	_own(pivot, dummy)
	var cloth := _standard_material(Color(0.55, 0.45, 0.30), 0.9, 0.0)
	var torso_mesh := CylinderMesh.new()
	torso_mesh.top_radius = 0.2
	torso_mesh.bottom_radius = 0.17
	torso_mesh.height = 1.1
	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	torso.mesh = torso_mesh
	torso.position = Vector3(0.0, 0.85, 0.0)
	torso.material_override = cloth
	_own(torso, pivot)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.13
	head_mesh.height = 0.26
	var head := MeshInstance3D.new()
	head.name = "Head"
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.55, 0.0)
	head.material_override = cloth
	_own(head, pivot)
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.04
	post_mesh.bottom_radius = 0.06
	post_mesh.height = 0.3
	var post := MeshInstance3D.new()
	post.name = "Post"
	post.mesh = post_mesh
	post.position = Vector3(0.0, 0.15, 0.0)
	post.material_override = _materials["metal"]
	_own(post, dummy)
	var label := Label3D.new()
	label.name = "DamageLabel"
	label.position = Vector3(0.0, 2.15, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 72
	label.pixel_size = 0.004
	label.outline_size = 12
	label.text = "-"
	_own(label, dummy)
	dummy.set("pivot", pivot)
	dummy.set("label", label)
	_add_label("Boneco de treino (ATACAR)", Vector3(-5.0, 2.5, 9.0), group)


func _add_player_and_ui() -> void:
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	player.name = "Player"
	player.position = Vector3(0.0, 0.0, 4.0)
	_own(player)

	var touch_controls: Node = (load("res://scenes/ui/touch_controls.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	touch_controls.name = "TouchControlsLayer"
	_own(touch_controls)

	var debug_layer := CanvasLayer.new()
	debug_layer.name = "DebugLayer"
	debug_layer.layer = 20
	_own(debug_layer)
	var hud := Label.new()
	hud.name = "MovementDebugHud"
	hud.set_script(load("res://scripts/debug/movement_debug_hud.gd"))
	hud.position = Vector2(16.0, 12.0)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 4)
	_own(hud, debug_layer)
	hud.set("player", player)

	var player_hud := CanvasLayer.new()
	player_hud.name = "PlayerHud"
	player_hud.set_script(load("res://scripts/ui/player_hud.gd"))
	_own(player_hud)
	player_hud.set("player", player)
	player_hud.set("interaction", player.get_node("Interaction"))
	player_hud.set("death", player.get_node("Death"))
	var inventory_hud := CanvasLayer.new()
	inventory_hud.name = "InventoryHud"
	inventory_hud.set_script(load("res://scripts/ui/inventory_hud.gd"))
	_own(inventory_hud)
	inventory_hud.set("player", player)
	inventory_hud.set("inventory", player.get_node("Inventory"))
	inventory_hud.set("interaction", player.get_node("Interaction"))
