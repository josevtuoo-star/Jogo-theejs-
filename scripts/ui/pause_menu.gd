class_name PauseMenu
extends CanvasLayer
## Menu de pausa (P / Start / botão MENU): CONTINUAR, SALVAR e SAIR PARA O
## MENU (grava antes de sair, se o jogador permitiu salvar). Mostra o nome e
## a semente do mundo (para jogar o mesmo mundo de novo ou passar a alguém).
## O jogo fica parado enquanto o menu está aberto.

const MENU_SCENE := "res://scenes/menu/menu_principal.tscn"

@export var world_scene: WorldScene
@export var player: PlayerController

var is_open: bool = false
var _panel: Control
var _status: Label
var _save_button: Button
var _settings: SettingsPanel
var _info: Label
var _touch_visibility: Dictionary = {}


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = ColorRect.new()
	(_panel as ColorRect).color = Color(0, 0, 0, 0.62)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560.0, 0.0)
	box.position = Vector2(-280.0, -320.0)
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	var title := MenuStyle.title("PAUSA", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_info = MenuStyle.label("", 15)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_info)
	box.add_child(MenuStyle.button("CONTINUAR", close))
	_save_button = MenuStyle.button("SALVAR", func() -> void:
		var ok := world_scene != null and world_scene.save_now()
		_status.text = "Mundo salvo." if ok else "Não foi possível salvar.")
	box.add_child(_save_button)
	_settings = SettingsPanel.new()
	_settings.visible = false
	box.add_child(MenuStyle.button("CONFIGURAÇÕES", func() -> void: _settings.visible = not _settings.visible))
	box.add_child(_settings)
	box.add_child(MenuStyle.button("SAIR PARA O MENU", _quit_to_menu))
	_status = MenuStyle.label("", 14)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause_menu"):
		if is_open:
			close()
		elif player == null or not player.is_dead():
			open()


func open() -> void:
	if is_open:
		return
	is_open = true
	_panel.visible = true
	var world_text: String = "%s · semente %d" % [GameSession.world_name, GameSession.world_seed] if GameSession.active else "Mundo de teste (sem salvar)"
	var cycle: SkyCycle = world_scene.sky_cycle if world_scene != null else null
	_info.text = world_text + ("\n%s · %s" % [cycle.clock(), cycle.weather_name()] if cycle != null else "")
	var can_save := GameSession.active and GameSession.storage_allowed
	_save_button.disabled = not can_save
	_status.text = "" if can_save else ("Sem permissão para salvar (menu inicial)." if GameSession.active else "")
	_touch_visibility.clear()
	for layer_node in get_tree().get_nodes_in_group(&"touch_controls"):
		_touch_visibility[layer_node] = layer_node.get(&"visible")
		layer_node.set(&"visible", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func close() -> void:
	if not is_open:
		return
	is_open = false
	_panel.visible = false
	get_tree().paused = false
	for layer_node in _touch_visibility:
		if is_instance_valid(layer_node):
			layer_node.set(&"visible", _touch_visibility[layer_node])
	_touch_visibility.clear()
	if not GameInput.uses_touch_controls() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _quit_to_menu() -> void:
	if world_scene != null and GameSession.active and GameSession.storage_allowed:
		world_scene.save_now()
	get_tree().paused = false
	GameSession.active = false
	get_tree().change_scene_to_file(MENU_SCENE)
