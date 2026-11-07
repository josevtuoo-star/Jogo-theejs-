class_name MainMenu
extends Node3D
## Menu inicial: o próprio mundo ao fundo (uma câmera passando devagar pela
## rodovia abandonada, na neblina), o título e:
##
## - CONTINUAR: o último mundo jogado;
## - NOVO MUNDO: nome e semente (vazia = sorteada; a mesma semente gera sempre
##   o mesmo mundo, como no Minecraft);
## - CARREGAR MUNDO: os mundos salvos, com JOGAR e APAGAR;
## - PERSONAGEM: cores da jaqueta, calça, botas, gorro, pele e cabelo, com o
##   sobrevivente em 3D girando;
## - SAIR.
##
## Na primeira vez o jogo pede permissão para gravar os mundos na memória
## interna do aparelho; sem ela dá para jogar, mas nada é salvo.

const WORLD_SCENE := "res://scenes/world/mundo.tscn"
## Mundo de fundo do menu (fixo: sempre a mesma paisagem).
const BACKDROP_SEED := 20261102

var _world: ProceduralWorld
var _camera: Camera3D
var _camera_target: Node3D
var _path_z: float = 0.0
var _ui: Control
var _side: Control
var _panels: Dictionary = {}
var _continue_button: Button
var _load_button: Button
var _storage_note: Label
var _permission: Control
var _worlds_list: VBoxContainer
var _name_field: LineEdit
var _seed_field: LineEdit
var _preview: CharacterPreview
var _look: Dictionary = {}
var _loading: Control


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_backdrop()
	_build_ui()
	_refresh_buttons()
	if not GameSession.storage_asked:
		_permission.visible = true


# --- Fundo ---------------------------------------------------------------------

func _build_backdrop() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.36, 0.41, 0.46)
	sky_material.sky_horizon_color = Color(0.62, 0.6, 0.55)
	sky_material.ground_bottom_color = Color(0.08, 0.09, 0.08)
	sky_material.ground_horizon_color = Color(0.5, 0.5, 0.47)
	sky_material.sun_angle_max = 20.0
	sky_material.energy_multiplier = 0.8
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.95
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.58, 0.58, 0.55)
	environment.fog_density = 0.026
	environment.fog_sky_affect = 0.6
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-18.0, -140.0, 0.0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	_camera_target = Node3D.new()
	add_child(_camera_target)
	_world = ProceduralWorld.new()
	_world.world_seed = BACKDROP_SEED
	_world.view_distance = 2
	_world.max_tasks = 2
	_world.target = _camera_target
	add_child(_world)
	var start := _world.generator.spawn_point()
	_camera_target.global_position = start
	_world.generate_now(start, 1)
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.far = 400.0
	add_child(_camera)
	_camera.current = true
	_path_z = start.z


func _process(delta: float) -> void:
	# A câmera segue a rodovia para o norte, devagar, a 2,4 m do chão.
	_path_z -= delta * 1.6
	var g := _world.generator
	var x := g.highway_center_x(0.0, _path_z) - 1.2
	var ground := g.surface_height(x, _path_z)
	var eye := Vector3(x, ground + 2.4, _path_z)
	_camera.global_position = _camera.global_position.lerp(eye, 1.0 - exp(-3.0 * delta)) if _camera.global_position != Vector3.ZERO else eye
	var ahead_z := _path_z - 18.0
	var look := Vector3(g.highway_center_x(0.0, ahead_z) + 2.0, g.surface_height(g.highway_center_x(0.0, ahead_z), ahead_z) + 1.6, ahead_z)
	_camera.look_at(look)
	_camera_target.global_position = eye


# --- Interface -----------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	# Faixa escura à esquerda (leitura do texto sobre a paisagem).
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.82))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 4
	shade.texture = texture
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.custom_minimum_size = Vector2(760.0, 0.0)
	shade.size = Vector2(760.0, 720.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)

	_side = VBoxContainer.new()
	_side.position = Vector2(64.0, 56.0)
	_side.custom_minimum_size = Vector2(380.0, 0.0)
	_side.add_theme_constant_override("separation", 12)
	_ui.add_child(_side)
	var title := MenuStyle.title("ÚLTIMO\nAMANHECER", 58)
	_side.add_child(title)
	var subtitle := MenuStyle.label("Sobreviva. Explore. Construa.", 17)
	subtitle.modulate = Color(1, 1, 1, 0.75)
	_side.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 14.0)
	_side.add_child(gap)
	_continue_button = MenuStyle.button("CONTINUAR", _continue)
	_side.add_child(_continue_button)
	_side.add_child(MenuStyle.button("NOVO MUNDO", func() -> void: _show_panel("novo")))
	_load_button = MenuStyle.button("CARREGAR MUNDO", func() -> void: _show_panel("carregar"))
	_side.add_child(_load_button)
	_side.add_child(MenuStyle.button("PERSONAGEM", func() -> void: _show_panel("personagem")))
	_side.add_child(MenuStyle.button("CONFIGURAÇÕES", func() -> void: _show_panel("configuracoes")))
	_side.add_child(MenuStyle.button("SAIR", func() -> void: get_tree().quit()))
	_storage_note = MenuStyle.label("", 13)
	_storage_note.modulate = Color(1, 0.85, 0.6, 0.9)
	_side.add_child(_storage_note)

	_build_new_world_panel()
	_build_load_panel()
	_build_character_panel()
	_panel("configuracoes", "CONFIGURAÇÕES", 640.0).add_child(SettingsPanel.new())
	_build_permission()
	_build_loading()


func _panel(key: String, title: String, width: float) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", MenuStyle.panel())
	frame.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	frame.custom_minimum_size = Vector2(width, 0.0)
	frame.position = Vector2(-width - 56.0, -300.0)
	frame.visible = false
	_ui.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	frame.add_child(column)
	var header := HBoxContainer.new()
	var label := MenuStyle.title(title, 28)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var close := MenuStyle.button("✕", func() -> void: frame.visible = false, 58.0)
	header.add_child(close)
	column.add_child(header)
	_panels[key] = frame
	return column


func _show_panel(key: String) -> void:
	for other: String in _panels:
		(_panels[other] as Control).visible = other == key
	if key == "carregar":
		_refresh_worlds()
	if key == "novo":
		_name_field.text = ""
		_seed_field.text = ""
	if key == "personagem":
		_look = GameSession.look.duplicate()
		_preview.apply_look(_look)


func _build_new_world_panel() -> void:
	var column := _panel("novo", "NOVO MUNDO", 560.0)
	column.add_child(MenuStyle.label("Nome do mundo", 15))
	_name_field = MenuStyle.field("Mundo %d" % (GameSession.list_worlds().size() + 1))
	column.add_child(_name_field)
	column.add_child(MenuStyle.label("Semente (número ou palavra; vazio = aleatória)", 15))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_seed_field = MenuStyle.field("aleatória")
	_seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_seed_field)
	row.add_child(MenuStyle.button("SORTEAR", func() -> void: _seed_field.text = str(GameSession.random_seed()), 140.0))
	column.add_child(row)
	var info := MenuStyle.label("A mesma semente gera sempre o mesmo mundo: relevo, florestas, cavernas, estradas e cidades. Passe a semente para um amigo jogar o mesmo lugar.", 14)
	info.modulate = Color(1, 1, 1, 0.7)
	column.add_child(info)
	column.add_child(MenuStyle.button("CRIAR MUNDO", func() -> void:
		var seed_value := GameSession.seed_from_text(_seed_field.text)
		GameSession.new_world(_name_field.text if _name_field.text != "" else _name_field.placeholder_text, seed_value)
		_start_game()))


func _build_load_panel() -> void:
	var column := _panel("carregar", "MUNDOS SALVOS", 600.0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 420.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_worlds_list = VBoxContainer.new()
	_worlds_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_worlds_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_worlds_list)


func _refresh_worlds() -> void:
	for child in _worlds_list.get_children():
		child.free()
	var worlds := GameSession.list_worlds()
	if worlds.is_empty():
		_worlds_list.add_child(MenuStyle.label("Nenhum mundo salvo ainda.", 16))
		return
	for data in worlds:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(MenuStyle.label(String(data.get("nome", "?")), 19))
		var when := Time.get_datetime_string_from_unix_time(int(data.get("jogado", 0)), true)
		var details := MenuStyle.label("semente %d · %s" % [int(data.get("semente", 0)), when], 13)
		details.modulate = Color(1, 1, 1, 0.65)
		text.add_child(details)
		row.add_child(text)
		var id: String = data["id"]
		var play := func() -> void:
			if GameSession.load_world(id):
				_start_game()
		row.add_child(MenuStyle.button("JOGAR", play, 120.0))
		var delete := MenuStyle.button("APAGAR", Callable(), 120.0)
		delete.pressed.connect(func() -> void:
			if delete.text == "APAGAR":
				delete.text = "CONFIRMAR"
			else:
				GameSession.delete_world(id)
				_refresh_worlds()
				_refresh_buttons())
		row.add_child(delete)
		_worlds_list.add_child(row)


func _build_character_panel() -> void:
	var column := _panel("personagem", "PERSONAGEM", 720.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)
	_preview = CharacterPreview.new()
	_preview.custom_minimum_size = Vector2(240.0, 400.0)
	row.add_child(_preview)
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 6)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(options)
	for part: String in CharacterLook.ORDER:
		options.add_child(MenuStyle.label(CharacterLook.PART_NAMES[part], 15))
		var swatches := HBoxContainer.new()
		swatches.add_theme_constant_override("separation", 6)
		options.add_child(swatches)
		for option in (CharacterLook.COLORS[part] as Array).size():
			var button := Button.new()
			button.custom_minimum_size = Vector2(46.0, 40.0)
			button.focus_mode = Control.FOCUS_NONE
			button.toggle_mode = true
			var color := CharacterLook.swatch(part, option, _preview.survivor)
			var box := StyleBoxFlat.new()
			box.bg_color = color
			box.set_corner_radius_all(3)
			box.set_border_width_all(2)
			box.border_color = Color(0, 0, 0, 0.6)
			var chosen := box.duplicate() as StyleBoxFlat
			chosen.border_color = MenuStyle.ACCENT
			chosen.set_border_width_all(4)
			button.add_theme_stylebox_override("normal", box)
			button.add_theme_stylebox_override("hover", box)
			button.add_theme_stylebox_override("pressed", chosen)
			button.add_theme_stylebox_override("hover_pressed", chosen)
			button.button_pressed = int(GameSession.look.get(part, 0)) == option
			button.set_meta(&"part", part)
			button.pressed.connect(func() -> void:
				_look[part] = option
				for sibling: Button in swatches.get_children():
					sibling.set_pressed_no_signal(sibling == button)
				_preview.apply_look(_look))
			swatches.add_child(button)
	column.add_child(MenuStyle.button("SALVAR APARÊNCIA", func() -> void:
		GameSession.look = _look.duplicate()
		GameSession.save_settings()
		(_panels["personagem"] as Control).visible = false))


func _build_permission() -> void:
	_permission = ColorRect.new()
	(_permission as ColorRect).color = Color(0, 0, 0, 0.7)
	_permission.set_anchors_preset(Control.PRESET_FULL_RECT)
	_permission.visible = false
	_ui.add_child(_permission)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", MenuStyle.panel(Color(0.1, 0.105, 0.1, 0.98)))
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.custom_minimum_size = Vector2(620.0, 0.0)
	frame.position = Vector2(-310.0, -170.0)
	_permission.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	frame.add_child(column)
	column.add_child(MenuStyle.title("Salvar seus mundos?", 28))
	column.add_child(MenuStyle.label("O Último Amanhecer quer guardar os mundos que você criar (posição, mochila, árvores cortadas, minério colhido) na memória interna do celular, numa pasta privada do jogo. Cada mundo ocupa poucos KB.\n\nSem permissão você joga normalmente, mas o mundo não fica salvo ao sair.", 16))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var allow := MenuStyle.button("PERMITIR", func() -> void:
		GameSession.set_storage_permission(true)
		_permission.visible = false
		_refresh_buttons())
	allow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(allow)
	var deny := MenuStyle.button("AGORA NÃO", func() -> void:
		GameSession.set_storage_permission(false)
		_permission.visible = false
		_refresh_buttons())
	deny.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(deny)


func _build_loading() -> void:
	_loading = ColorRect.new()
	(_loading as ColorRect).color = Color(0.03, 0.035, 0.03, 0.92)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.visible = false
	_ui.add_child(_loading)
	var label := MenuStyle.title("Gerando o mundo...", 30)
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(-160.0, -20.0)
	_loading.add_child(label)


func _refresh_buttons() -> void:
	var worlds: Array = GameSession.list_worlds() if GameSession.storage_allowed else []
	_continue_button.disabled = worlds.is_empty()
	_continue_button.text = "CONTINUAR  ·  %s" % worlds[0].get("nome", "") if not worlds.is_empty() else "CONTINUAR"
	_load_button.disabled = not GameSession.storage_allowed
	_storage_note.text = "" if GameSession.storage_allowed else "Sem permissão para salvar: os mundos não ficam guardados."
	if not GameSession.storage_allowed and GameSession.storage_asked:
		if not _storage_note.has_meta(&"button"):
			var ask := MenuStyle.button("PERMITIR SALVAR", func() -> void: _permission.visible = true)
			_storage_note.set_meta(&"button", ask)
			_side.add_child(ask)
	elif _storage_note.has_meta(&"button"):
		(_storage_note.get_meta(&"button") as Node).queue_free()
		_storage_note.remove_meta(&"button")


func _continue() -> void:
	var worlds := GameSession.list_worlds()
	if not worlds.is_empty() and GameSession.load_world(worlds[0]["id"]):
		_start_game()


func _start_game() -> void:
	_loading.visible = true
	# Um quadro para a tela de carregamento aparecer antes da geração.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(WORLD_SCENE)
