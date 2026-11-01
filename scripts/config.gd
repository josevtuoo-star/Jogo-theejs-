class_name Config
extends Object
## Configurações do jogo (gráficos, controles), salvas em user://config.cfg e aplicadas na hora.

const PATH := "user://config.cfg"
const PRESETS := {
	"Baixa": {"sombras": 0, "escala": 0.7, "msaa": 0, "distancia": 350.0, "vegetacao": 0.45, "grama": false, "neblina": true, "pos": false, "sombra_dist": 25.0},
	"Média": {"sombras": 1, "escala": 0.85, "msaa": 0, "distancia": 550.0, "vegetacao": 0.7, "grama": true, "neblina": true, "pos": true, "sombra_dist": 35.0},
	"Alta": {"sombras": 2, "escala": 1.0, "msaa": 1, "distancia": 800.0, "vegetacao": 1.0, "grama": true, "neblina": true, "pos": true, "sombra_dist": 50.0},
	"Ultra": {"sombras": 3, "escala": 1.0, "msaa": 2, "distancia": 1200.0, "vegetacao": 1.35, "grama": true, "neblina": true, "pos": true, "sombra_dist": 80.0},
}

## valores atuais
static var v := {
	"qualidade": "Média",
	"sombras": 1, # 0 desligadas, 1 baixa, 2 média, 3 alta
	"sombra_dist": 35.0,
	"escala": 0.85, # resolução 3D (0,5 a 1,0)
	"msaa": 0, # 0 desligado, 1 = 2x, 2 = 4x
	"distancia": 550.0, # metros que dá para ver (terreno e árvores)
	"vegetacao": 0.7, # densidade da caatinga
	"grama": true,
	"neblina": true,
	"pos": true, # cor final (gradação)
	"fps": 60, # 0 = sem limite
	"brilho": 1.0,
	"fov": 78.0,
	"sensibilidade": 1.0,
	"mostrar_fps": true,
}
static var _loaded := false
## avisos para quem depende (mundo, câmera...)
static var version := 0


static func load_cfg() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in v:
			v[k] = cf.get_value("jogo", k, v[k])
	else:
		# primeira vez: celular começa em Média; PC em Alta
		set_preset("Média" if OS.has_feature("mobile") else "Alta", false)


static func save_cfg() -> void:
	var cf := ConfigFile.new()
	for k in v:
		cf.set_value("jogo", k, v[k])
	cf.save(PATH)


static func set_preset(name: String, save := true) -> void:
	v.qualidade = name
	for k in PRESETS[name]:
		v[k] = PRESETS[name][k]
	if save:
		save_cfg()
	version += 1


static func set_value(k: String, val: Variant) -> void:
	v[k] = val
	if k in ["sombras", "escala", "msaa", "distancia", "vegetacao", "grama", "neblina", "pos", "sombra_dist"]:
		v.qualidade = "Personalizada"
	save_cfg()
	version += 1


## Aplica o que é da janela/renderização (o mundo e a câmera leem o resto).
static func apply(tree: SceneTree) -> void:
	var vp := tree.root
	vp.scaling_3d_scale = clampf(v.escala, 0.5, 1.0)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(v.msaa, 0, 2)]
	Engine.max_fps = int(v.fps)
	var sun := tree.get_first_node_in_group("sol") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = v.sombras > 0
		sun.directional_shadow_max_distance = v.sombra_dist
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if v.sombras <= 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		RenderingServer.directional_shadow_atlas_set_size([1024, 1024, 2048, 4096][clampi(v.sombras, 0, 3)], true)
		RenderingServer.directional_soft_shadow_filter_set_quality(
			[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][clampi(v.sombras, 0, 3)])
	var we := tree.get_first_node_in_group("ambiente_mundo") as WorldEnvironment
	if we:
		var env := we.environment
		env.fog_enabled = v.neblina
		env.tonemap_exposure = 1.0 * v.brilho
		# sem neblina a vista vai até a distância escolhida; com neblina ela esconde o fim
		env.fog_density = clampf(2.2 / maxf(v.distancia, 100.0), 0.0015, 0.02)
	for n in tree.get_nodes_in_group("pos_processamento"):
		(n as CanvasItem).visible = v.pos
	var cam := vp.get_camera_3d()
	if cam:
		cam.far = v.distancia + 150.0
