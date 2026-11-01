extends Node3D
## Ferramenta de produção: gera o atlas de impostor das árvores a partir de um
## modelo realista (Poly Haven "Fir Sapling Medium", CC0, 2,3 milhões de
## polígonos — pesado demais para o celular).
##
## Uso (precisa de renderização; em servidor, use xvfb-run):
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tools/bake_tree_impostors.tscn
##
## Renderiza o modelo com câmera ortográfica e fundo transparente em três
## ângulos (0°, 60°, 120°) para cada uma das três variantes do pacote e grava
## um atlas 3×3 (linhas = variantes, colunas = ângulos). No jogo,
## cada árvore é formada por três planos cruzados com esses quadros
## (ver tools/build_demo_map.gd e resources/materials/tree_card.gdshader).

const SOURCE := "res://assets/_source/fir_sapling_medium/fir_sapling_medium_1k.gltf"
const OUTPUT := "res://resources/textures/trees/fir_cards.png"
const TILE := Vector2i(256, 512)
const ANGLES := [0.0, 60.0, 120.0]


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

	var model: Node3D = (load(SOURCE) as PackedScene).instantiate()
	add_child(model)
	var variants: Array[MeshInstance3D] = []
	for child in model.get_children():
		if child is MeshInstance3D:
			variants.append(child)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.01
	camera.far = 100.0
	add_child(camera)
	camera.current = true

	# Linhas = variantes (a, b, c); colunas = ângulos.
	var atlas := Image.create(TILE.x * ANGLES.size(), TILE.y * variants.size(), false, Image.FORMAT_RGBA8)
	for row in variants.size():
		for other in variants:
			other.visible = other == variants[row]
		var variant := variants[row]
		var bounds := variant.transform * variant.get_aabb()
		var pivot := Vector3(variant.position.x, bounds.position.y + bounds.size.y * 0.5, variant.position.z)
		camera.size = bounds.size.y * 1.02
		for column in ANGLES.size():
			variant.rotation_degrees.y = ANGLES[column]
			camera.global_position = pivot + Vector3(0.0, 0.0, 20.0)
			camera.look_at(pivot)
			for frame in 4:
				await get_tree().process_frame
			var image := get_viewport().get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			image.resize(TILE.x, TILE.y)
			atlas.blit_rect(image, Rect2i(Vector2i.ZERO, TILE), Vector2i(TILE.x * column, TILE.y * row))
		print("Variante %s: altura %.2f m (quadro %.2f m de largura)" % [variant.name, bounds.size.y * 1.02, bounds.size.y * 1.02 * float(TILE.x) / TILE.y])
	atlas.fix_alpha_edges()
	var error := atlas.save_png(OUTPUT)
	print("Atlas salvo em %s: %s" % [OUTPUT, error_string(error)])
	get_tree().quit(0 if error == OK else 1)
