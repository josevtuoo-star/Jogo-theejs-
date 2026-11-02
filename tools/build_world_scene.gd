extends SceneTree
## Ferramenta de produção: monta a cena principal do mundo procedural.
##
## Uso: godot --headless --path . --script res://tools/build_world_scene.gd
##
## A cena só tem o que não é gerado: céu, neblina e luz (manhã nublada de
## floresta de coníferas, como nas fotos de referência), o gerador de mundo
## por pedaços, a luz das cavernas, o jogador e a interface. Todo o terreno,
## floresta, cavernas, estradas e carcaças nascem em tempo de jogo.

const OUT := "res://scenes/world/mundo.tscn"

var _root: Node3D


func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "Mundo"
	_root.set_script(load("res://scripts/world/procedural/world_scene.gd"))
	var environment := _environment()
	var sun := _sun()
	var world := Node3D.new()
	world.name = "ProceduralWorld"
	world.set_script(load("res://scripts/world/procedural/procedural_world.gd"))
	_own(world)
	var player := _player_and_ui()
	world.set("target", player)
	var caves := Node.new()
	caves.name = "CaveAtmosphere"
	caves.set_script(load("res://scripts/world/procedural/cave_atmosphere.gd"))
	_own(caves)
	caves.set("world", world)
	caves.set("camera", player.get_node("CameraRig/Camera3D"))
	caves.set("eyes", player.get_node("Head/CameraEffects"))
	caves.set("environment", environment)
	caves.set("sun", sun)
	_root.set("world", world)
	_root.set("player", player)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/world"))
	var packed := PackedScene.new()
	var error := packed.pack(_root)
	if error == OK:
		error = ResourceSaver.save(packed, OUT)
	print("Cena do mundo gerada: %s" % error_string(error))
	quit(0 if error == OK else 1)


func _own(node: Node, parent: Node = null) -> Node:
	(parent if parent != null else _root).add_child(node)
	node.owner = _root
	return node


## Manhã encoberta com névoa entre as árvores: céu cinza-azulado, luz difusa
## forte (sob a copa é o que ilumina), neblina densa que esconde o limite dos
## pedaços carregados (~140 m) e dá profundidade à mata.
func _environment() -> WorldEnvironment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.46, 0.52, 0.57)
	sky_material.sky_horizon_color = Color(0.66, 0.69, 0.69)
	sky_material.sky_curve = 0.1
	sky_material.ground_bottom_color = Color(0.10, 0.11, 0.09)
	sky_material.ground_horizon_color = Color(0.5, 0.53, 0.52)
	sky_material.sun_angle_max = 25.0
	sky_material.sun_curve = 0.06
	sky_material.energy_multiplier = 0.8
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.1
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.95
	environment.tonemap_white = 6.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.52, 0.56, 0.57)
	environment.fog_light_energy = 1.0
	environment.fog_density = 0.019
	environment.fog_sky_affect = 0.55
	environment.fog_aerial_perspective = 0.35
	environment.glow_enabled = true
	environment.glow_intensity = 0.3
	environment.glow_bloom = 0.04
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.8
	environment.adjustment_contrast = 1.05
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = environment
	_own(world)
	return world


func _sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, -125.0, 0.0)
	sun.light_color = Color(0.96, 0.95, 0.9)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 50.0
	sun.directional_shadow_split_1 = 0.25
	_own(sun)
	return sun


func _player_and_ui() -> Node3D:
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	player.name = "Player"
	player.position = Vector3(0.0, 30.0, 0.0) # trocado pelo ponto de partida ao abrir
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
	return player
