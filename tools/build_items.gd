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

## id: propriedades do ItemData. "source" = arma (.tres) ou malha (.res).
const W := "res://resources/weapons/"
const M := "res://resources/models/world/"
const T := ItemData.Kind.TOOL
const R := ItemData.Kind.RESOURCE
const A := ItemData.Kind.ARMOR
const LIST := {
	# Ferramentas e armas
	"machado": {"name": "Machado de bombeiro", "kind": T, "source": W + "machado.tres", "mass": 2.8, "durability": 140.0,
		"sound": &"metal", "tool_type": &"machado", "tier": 2, "power": 1.0,
		"text": "Derruba árvores rápido. Arma pesada."},
	"picareta": {"name": "Picareta", "kind": T, "source": W + "picareta.tres", "mass": 2.6, "durability": 140.0,
		"sound": &"metal", "tool_type": &"picareta", "tier": 2, "power": 1.0,
		"text": "Quebra pedra, carvão e minério de ferro."},
	"taco": {"name": "Taco com pregos", "kind": T, "source": W + "taco.tres", "mass": 1.2, "durability": 60.0,
		"sound": &"madeira", "text": "Arma rápida contra zumbis."},
	"machado_pedra": {"name": "Machado de pedra", "kind": T, "source": W + "machado_pedra.tres", "mass": 1.3, "durability": 70.0,
		"sound": &"madeira", "tool_type": &"machado", "tier": 1, "power": 0.7,
		"text": "Corta árvores (mais devagar que o de bombeiro)."},
	"picareta_pedra": {"name": "Picareta de pedra", "kind": T, "source": W + "picareta_pedra.tres", "mass": 1.5, "durability": 70.0,
		"sound": &"madeira", "tool_type": &"picareta", "tier": 1, "power": 0.6,
		"text": "Quebra pedra e carvão. Ferro pede picareta de metal."},
	"faca_pedra": {"name": "Faca de pedra", "kind": T, "source": W + "faca_pedra.tres", "mass": 0.3, "durability": 50.0,
		"sound": &"madeira", "text": "Golpes curtos e muito rápidos."},
	"lanca": {"name": "Lança", "kind": T, "source": W + "lanca.tres", "mass": 1.4, "durability": 60.0,
		"sound": &"madeira", "text": "Alcance longo: mantém o zumbi longe."},
	"tocha": {"name": "Tocha", "kind": T, "source": W + "tocha.tres", "mass": 0.5, "durability": 240.0,
		"sound": &"madeira", "tool_type": &"tocha", "light": 2.4,
		"text": "Ilumina as cavernas. Queima com o tempo na mão."},
	"facao": {"name": "Facão", "kind": T, "source": W + "facao.tres", "mass": 0.7, "durability": 110.0,
		"sound": &"metal", "tool_type": &"facao", "tier": 1, "power": 0.45,
		"text": "Arma rápida; também corta árvores, devagar."},
	"pe_de_cabra": {"name": "Pé de cabra", "kind": T, "source": W + "pe_de_cabra.tres", "mass": 1.6, "durability": 200.0,
		"sound": &"metal", "text": "Arma pesada e quase indestrutível."},
	# Recursos
	"madeira": {"name": "Madeira", "kind": R, "source": M + "tora.res", "mass": 4.0, "sound": &"madeira",
		"text": "Tora. Vira tábuas na bancada."},
	"tabua": {"name": "Tábua", "kind": R, "source": M + "tabua.res", "mass": 1.0, "sound": &"madeira",
		"text": "Para gravetos e construção."},
	"graveto": {"name": "Graveto", "kind": R, "source": M + "graveto.res", "mass": 0.2, "sound": &"madeira",
		"text": "Cabo de ferramentas e tochas."},
	"pedra": {"name": "Pedra", "kind": R, "source": M + "pedaco_pedra.res", "mass": 1.5, "sound": &"generico",
		"text": "Lâminas e cabeças de ferramentas."},
	"carvao": {"name": "Carvão", "kind": R, "source": M + "pedaco_carvao.res", "mass": 0.8, "sound": &"generico",
		"text": "Combustível das tochas."},
	"ferro": {"name": "Minério de ferro", "kind": R, "source": M + "pedaco_ferro.res", "mass": 2.0, "sound": &"metal",
		"text": "Ferramentas de metal e armaduras."},
	# Armaduras
	"capacete": {"name": "Capacete de sucata", "kind": A, "source": M + "armadura_capacete.res", "mass": 1.2, "durability": 80.0,
		"sound": &"metal", "slot": &"cabeca", "armor": 0.15, "text": "Cabeça: absorve 15% do dano."},
	"colete": {"name": "Colete de chapas", "kind": A, "source": M + "armadura_colete.res", "mass": 4.0, "durability": 120.0,
		"sound": &"metal", "slot": &"tronco", "armor": 0.25, "text": "Tronco: absorve 25% do dano."},
	"joelheiras": {"name": "Joelheiras", "kind": A, "source": M + "armadura_joelheira.res", "mass": 0.8, "durability": 70.0,
		"sound": &"metal", "slot": &"pernas", "armor": 0.08, "text": "Pernas: absorvem 8% do dano."},
	"botas_reforcadas": {"name": "Botas reforçadas", "kind": A, "source": M + "armadura_bota.res", "mass": 1.0, "durability": 70.0,
		"sound": &"metal", "slot": &"pes", "armor": 0.06, "text": "Pés: absorvem 6% do dano."},
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
		var spec: Dictionary = LIST[id]
		var item := ItemData.new()
		item.id = StringName(id)
		item.display_name = spec["name"]
		item.kind = spec["kind"]
		item.mass = spec["mass"]
		item.max_durability = maxf(spec.get("durability", 1.0), 1.0)
		item.impact_material = spec["sound"]
		item.description = spec.get("text", "")
		item.stack_size = 64 if item.kind == ItemData.Kind.RESOURCE else 1
		item.tool_type = spec.get("tool_type", &"arma")
		item.tier = spec.get("tier", 0)
		item.work_power = spec.get("power", 0.0)
		item.armor_slot = spec.get("slot", &"")
		item.armor_value = spec.get("armor", 0.0)
		item.light_energy = spec.get("light", 0.0)
		var mesh: Mesh
		if item.kind == ItemData.Kind.TOOL:
			item.weapon = load(spec["source"])
			mesh = item.weapon.mesh
		else:
			mesh = load(spec["source"])
		item.world_mesh = mesh
		var image := await _render(mesh, item.kind == ItemData.Kind.TOOL)
		image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		var icon_path := ICONS + id + ".png"
		image.save_png(icon_path)
		# O ícone fica em resources/icons/<id>.png (importado pelo projeto) e
		# ItemData.get_icon() o carrega por esse caminho.
		var error := ResourceSaver.save(item, ITEMS + id + ".tres")
		print("%-16s %s" % [id, error_string(error)])
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
