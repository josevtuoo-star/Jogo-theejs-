extends Node3D
## Ferramenta de produção: atlas de impostor das árvores dos outros biomas
## (etapa 9), como o dos abetos (tools/bake_tree_impostors.gd):
##   linha 0: árvore de folhas largas (Poly Haven "Tree Small 02", CC0);
##   linha 1: a mesma árvore seca, sem folhas (cerrado seco e neve);
##   linha 2: árvore-aljava (Poly Haven "Quiver Tree 01", CC0), terra seca.
## Os modelos (milhões de polígonos) ficam em assets/_source, fora do jogo.
##
## Uso (precisa de renderização; em servidor, use xvfb-run):
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tools/bake_broadleaf_impostors.tscn

const OUTPUT := "res://resources/textures/trees/broadleaf_cards.png"
const TILE := Vector2i(384, 384)
const ANGLES := [0.0, 60.0, 120.0]
## [modelo, superfícies escondidas]
const ROWS := [
	["res://assets/_source/tree_small_02/tree_small_02_1k.gltf", []],
	["res://assets/_source/tree_small_02/tree_small_02_1k.gltf", [1]],
	["res://assets/_source/quiver_tree_01/quiver_tree_01_1k.gltf", []],
]


func _ready() -> void:
	get_viewport().transparent_bg = true
	get_window().size = TILE
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.88, 0.85)
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, 20.0, 0.0)
	key.light_energy = 0.9
	add_child(key)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.01
	camera.far = 100.0
	add_child(camera)
	camera.current = true
	var atlas := Image.create(TILE.x * ANGLES.size(), TILE.y * ROWS.size(), false, Image.FORMAT_RGBA8)
	var hidden := StandardMaterial3D.new()
	hidden.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hidden.albedo_color = Color(0, 0, 0, 0)
	for row in ROWS.size():
		var model: Node3D = (load(ROWS[row][0]) as PackedScene).instantiate()
		add_child(model)
		var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
		for s: int in ROWS[row][1]:
			mesh.set_surface_override_material(s, hidden)
		var bounds := mesh.global_transform * mesh.get_aabb()
		var side := maxf(bounds.size.y, maxf(bounds.size.x, bounds.size.z)) * 1.02
		var pivot := Vector3(mesh.global_position.x, bounds.position.y + side * 0.5, mesh.global_position.z)
		camera.size = side
		for column in ANGLES.size():
			model.rotation_degrees.y = ANGLES[column]
			camera.global_position = pivot + Vector3(0.0, 0.0, 20.0)
			camera.look_at(pivot)
			for frame in 6:
				await get_tree().process_frame
			var image := get_viewport().get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			image.resize(TILE.x, TILE.y)
			atlas.blit_rect(image, Rect2i(Vector2i.ZERO, TILE), Vector2i(TILE.x * column, TILE.y * row))
		print("Linha %d: quadro de %.2f m (altura do modelo %.2f m)" % [row, side, bounds.size.y])
		model.queue_free()
		await get_tree().process_frame
	atlas.fix_alpha_edges()
	var error := atlas.save_png(OUTPUT)
	print("Atlas salvo em %s: %s" % [OUTPUT, error_string(error)])
	get_tree().quit(0 if error == OK else 1)
