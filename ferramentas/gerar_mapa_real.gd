extends SceneTree
## Uso: godot --rendering-driver opengl3 -s res://ferramentas/gerar_mapa_real.gd  (precisa de janela/xvfb)
## Gera res://scenes/main.scn (mapa real de Faisqueiro/PB-394), res://scenes/player.tscn,
## res://assets/mapa_real/altura.res (a partir de altura.bin, feito pelo processador em Python)
## e as fotos das árvores para os impostores (res://assets/natureza/impostor_*.png).

const D := "res://assets/mapa_real/"
var root_main: Node3D


func _initialize() -> void:
	_altura()
	await _impostores()
	_build_player()
	_build_main()
	quit()


func _altura() -> void:
	var dados: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(D + "dados.json"))
	var bin := ProjectSettings.globalize_path(D + "altura.bin")
	if not FileAccess.file_exists(bin):
		print("altura.bin não encontrado (mantendo altura.res)")
		return
	var bytes := FileAccess.get_file_as_bytes(bin)
	var img := Image.create_from_data(int(dados.grade.w), int(dados.grade.h), false, Image.FORMAT_RF, bytes)
	print("altura ", ResourceSaver.save(img, D + "altura.res", ResourceSaver.FLAG_COMPRESS))


## Fotografa cada árvore de lado (fundo transparente) para os cartões de longe.
func _impostores() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 512)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var w := Node3D.new()
	vp.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.72, 0.66)
	env.environment.ambient_light_energy = 0.9
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 0.9
	w.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	w.add_child(cam)
	await process_frame
	for name in ["arvore_seca_3", "arvore_seca_4", "arvore_seca_5", "arvore_seca_6", "arvore_seca_7", "arvore_verde_1", "arvore_verde_3"]:
		var p: Node3D = load("res://assets/modelos/%s.tscn" % name).instantiate()
		w.add_child(p)
		var aabb := AABB()
		var first := true
		for mi in p.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).mesh.get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
		# mesmo enquadramento que o mundo usa para montar o cartão (mundo_real.gd/_impostor_mesh)
		var wsz := maxf(aabb.size.x, aabb.size.z)
		vp.size = Vector2i(256, 512) if aabb.size.y > wsz else Vector2i(512, 512)
		cam.size = aabb.size.y if aabb.size.y > wsz else maxf(aabb.size.y, wsz)
		var c := aabb.get_center()
		cam.position = Vector3(c.x, c.y, c.z + 60.0)
		cam.rotation = Vector3.ZERO
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		# o cartão vai do chão (aabb.position.y) até o topo, largura = maior lado
		img.save_png("res://assets/natureza/impostor_%s.png" % name)
		print("impostor ", name, " ", img.get_size(), " ", aabb.size)
		p.free()
	vp.queue_free()


func _build_main() -> void:
	root_main = Node3D.new()
	root_main.name = "Main"
	root_main.set_script(load("res://scripts/main.gd"))
	_environment()
	var mundo := Node3D.new()
	mundo.name = "Mundo"
	mundo.set_script(load("res://scripts/mundo_real.gd"))
	root_main.add_child(mundo)
	var props := Node3D.new()
	props.name = "Objetos"
	root_main.add_child(props)
	var amb := Node3D.new()
	amb.name = "Ambiente"
	amb.set_script(load("res://scripts/ambience.gd"))
	root_main.add_child(amb)
	var player: Node3D = load("res://scenes/player.tscn").instantiate()
	player.name = "Player"
	root_main.add_child(player)
	_hud()
	_own(root_main, root_main)
	var ps := PackedScene.new()
	assert(ps.pack(root_main) == OK)
	print("main ", ResourceSaver.save(ps, "res://scenes/main.scn", ResourceSaver.FLAG_COMPRESS))
	root_main.free()


func _environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.add_to_group("ambiente_mundo", true)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	# céu do sertão: claro, esbranquiçado de poeira e fumaça (mundo acabado)
	sm.sky_top_color = Color(0.42, 0.47, 0.52)
	sm.sky_horizon_color = Color(0.7, 0.66, 0.6)
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color(0.3, 0.25, 0.2)
	sm.ground_horizon_color = Color(0.72, 0.66, 0.58)
	sm.sun_angle_max = 30.0
	sm.sun_curve = 0.15
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.62, 0.56)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.45
	we.environment = env
	root_main.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sol"
	sun.add_to_group("sol", true)
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 40.0
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
	help.text = "WASD mover · Shift correr · Espaço pular · C agachar · E usar/pegar · Q arma · Tab mochila · Clique/F soco · V câmera · Esc/O configurações · R recomeçar"
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
	var cfg := Control.new()
	cfg.name = "Configuracoes"
	cfg.set_script(load("res://scripts/settings_ui.gd"))
	cfg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cfg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(cfg)
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
