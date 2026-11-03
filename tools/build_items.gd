extends SceneTree
## Ferramenta de produção: itens da mochila e seus ícones.
##
## Uso (precisa de renderização, não roda com --headless):
##   xvfb-run godot --rendering-driver opengl3 --path . --script res://tools/build_items.gd
##
## Saída: resources/items/<id>.tres (ItemData) e resources/icons/<id>.png
## (128 × 128, fundo transparente), desenhados a partir do próprio modelo 3D
## do item, com a mesma luz para todos.

const ICONS := "res://resources/icons/"
const ITEMS := "res://resources/items/"

## id: [nome, tipo, malha ou arma, massa, durabilidade, material do som]
const LIST := {
	"machado": ["Machado de bombeiro", ItemData.Kind.TOOL, "res://resources/weapons/machado.tres", 2.8, 140.0, &"metal"],
	"picareta": ["Picareta", ItemData.Kind.TOOL, "res://resources/weapons/picareta.tres", 2.6, 140.0, &"metal"],
	"taco": ["Taco com pregos", ItemData.Kind.TOOL, "res://resources/weapons/taco.tres", 1.2, 60.0, &"madeira"],
	"madeira": ["Madeira", ItemData.Kind.RESOURCE, "res://resources/models/world/tora.res", 4.0, 0.0, &"madeira"],
	"pedra": ["Pedra", ItemData.Kind.RESOURCE, "res://resources/models/world/pedaco_pedra.res", 1.5, 0.0, &"generico"],
	"carvao": ["Carvão", ItemData.Kind.RESOURCE, "res://resources/models/world/pedaco_carvao.res", 0.8, 0.0, &"generico"],
	"ferro": ["Minério de ferro", ItemData.Kind.RESOURCE, "res://resources/models/world/pedaco_ferro.res", 2.0, 0.0, &"metal"],
}

var _viewport: SubViewport
var _camera: Camera3D
var _holder: Node3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ICONS))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ITEMS))
	_stage()
	_build.call_deferred()


func _stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(256, 256)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.1
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	key.light_energy = 1.3
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	rim.light_energy = 0.6
	_viewport.add_child(rim)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	_holder = Node3D.new()
	_viewport.add_child(_holder)


func _build() -> void:
	for id: String in LIST:
		var spec: Array = LIST[id]
		var item := ItemData.new()
		item.id = StringName(id)
		item.display_name = spec[0]
		item.kind = spec[1]
		item.mass = spec[3]
		item.max_durability = maxf(spec[4], 1.0)
		item.impact_material = spec[5]
		var mesh: Mesh
		if item.kind == ItemData.Kind.TOOL:
			item.weapon = load(spec[2])
			mesh = item.weapon.mesh
		else:
			mesh = load(spec[2])
		item.world_mesh = mesh
		var image := await _render(mesh, item.kind == ItemData.Kind.TOOL)
		image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		var icon_path := ICONS + id + ".png"
		image.save_png(icon_path)
		# O ícone fica em resources/icons/<id>.png (importado pelo projeto) e
		# ItemData.get_icon() o carrega por esse caminho.
		var error := ResourceSaver.save(item, ITEMS + id + ".tres")
		print("%-9s %s" % [id, error_string(error)])
	quit()


## Desenha o item centrado, num ângulo de três quartos. Ferramentas ficam na
## diagonal da moldura (o cabo de um canto ao outro).
func _render(mesh: Mesh, diagonal: bool) -> Image:
	for child in _holder.get_children():
		child.free()
	var model := MeshInstance3D.new()
	model.mesh = mesh
	_holder.add_child(model)
	var box := mesh.get_aabb()
	if diagonal:
		# Cabo de um canto ao outro da moldura, lado que golpeia para a frente.
		model.basis = Basis(Vector3.BACK, deg_to_rad(-45.0)) * Basis(Vector3.UP, PI * 0.5)
	else:
		model.basis = Basis(Vector3.RIGHT, deg_to_rad(20.0)) * Basis(Vector3.UP, deg_to_rad(-30.0))
	model.position = -(model.basis * box.get_center())
	var radius := box.size.length() * 0.5
	_camera.size = radius * (1.55 if diagonal else 1.9)
	_camera.position = Vector3(0.0, 0.0, radius * 4.0)
	_camera.look_at(Vector3.ZERO)
	for i in 4:
		await process_frame
	return _viewport.get_texture().get_image()
