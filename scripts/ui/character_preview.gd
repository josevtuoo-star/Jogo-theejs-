class_name CharacterPreview
extends SubViewportContainer
## Retrato 3D do sobrevivente (mochila e menu PERSONAGEM): o próprio modelo do
## jogo, parado na animação de respiração, com a aparência escolhida e a
## armadura vestida, girando devagar. Arrastar com o dedo/mouse gira à mão.
## Só desenha enquanto está visível (no celular, o retrato não pesa no jogo).

@export var inventory: Inventory
@export var turn_speed: float = 0.35

var survivor: Node3D
var _viewport: SubViewport
var _pivot: Node3D
var _armor: ArmorVisuals
var _dragging: bool = false


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.52, 0.55)
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25.0, 30.0, 0.0)
	key.light_energy = 1.2
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10.0, 160.0, 0.0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.8, 0.85, 1.0)
	_viewport.add_child(rim)
	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0.0, 1.0, 4.1)
	_viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.92, 0.0))
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	survivor = (load("res://scenes/characters/survivor.tscn") as PackedScene).instantiate()
	_pivot.add_child(survivor)
	var physical := survivor.find_child("PhysicalBoneSimulator3D", true, false)
	if physical != null:
		physical.queue_free()
	if inventory != null:
		_armor = ArmorVisuals.new()
		_armor.body = survivor as BodyAnimator
		_armor.inventory = inventory
		survivor.add_child(_armor)
		inventory.changed.connect(_armor.refresh)
	apply_look(GameSession.look)
	visibility_changed.connect(_on_visibility)
	_on_visibility()


func apply_look(look: Dictionary) -> void:
	CharacterLook.apply(survivor, look)


func _on_visibility() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	if not _dragging and is_visible_in_tree():
		_pivot.rotation.y += turn_speed * delta


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _dragging:
		_pivot.rotation.y += (event as InputEventMouseMotion).relative.x * 0.012
