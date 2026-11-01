class_name TouchControls
extends Control
## Roteador multitoque dos controles de tela.
##
## Cada dedo é identificado pelo índice do toque e associado, no momento em
## que encosta na tela, a UM destino: um botão, o direcional (lado esquerdo)
## ou a área de câmera (lado direito, fora dos botões). Ele fica com esse
## destino até ser levantado (ou cancelado pelo sistema), não importa por
## onde passe. Assim:
## - arrastar para girar a câmera nunca pressiona botões nem ataca, mesmo
##   passando por cima deles;
## - direcional, câmera e botões funcionam ao mesmo tempo com dedos
##   diferentes;
## - o clique de mouse que o Godot emula a partir do toque (necessário para
##   os botões da interface) não aciona ações de jogo: os botões do mouse no
##   InputMap valem só para o mouse físico (dispositivo 0) e o GameInput
##   ignora eventos emulados. Ataque só sai do botão ATACAR.
## A ação de correr tem um único dono, este nó: corre quando o botão CORRER
## está ligado ou o direcional está na zona de corrida, e só enquanto o
## direcional estiver em uso.

@export var joystick: TouchMoveStick
@export var buttons: Array[TouchActionButton] = []
## Botão de corrida (modo alternância). Pode ficar vazio.
@export var sprint_button: TouchActionButton
@export var sprint_action: StringName = &"sprint"
## Fração da largura da tela que pertence ao direcional (o resto é câmera).
@export_range(0.1, 0.9, 0.01) var joystick_zone_ratio: float = 0.42
## Exibir mesmo sem touchscreen (para testes no PC com emulação de toque).
@export var always_visible: bool = false

var _joystick_touch: int = -1
var _look_touch: int = -1
var _button_touches: Dictionary = {}
var _sprint_pressed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = always_visible or GameInput.uses_touch_controls()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and not touch.canceled:
			_on_touch_down(touch.index, touch.position)
		else:
			_on_touch_up(touch.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_on_touch_drag(drag.index, drag.position, drag.relative)
		get_viewport().set_input_as_handled()


## Qual destino um toque nesta posição receberia (para testes e depuração).
func get_target_at(screen_position: Vector2) -> StringName:
	var button := _button_at(screen_position)
	if button != null:
		return StringName("button:" + String(button.name))
	var local := get_global_transform().affine_inverse() * screen_position
	return &"joystick" if local.x < size.x * joystick_zone_ratio else &"look"


func is_finger_on_look(index: int) -> bool:
	return index == _look_touch


func _button_at(screen_position: Vector2) -> TouchActionButton:
	var best: TouchActionButton = null
	var best_distance := 1.0
	for button in buttons:
		if not button.is_visible_in_tree():
			continue
		var distance := button.hit_distance(screen_position)
		if distance <= best_distance:
			best = button
			best_distance = distance
	return best


func _on_touch_down(index: int, screen_position: Vector2) -> void:
	_on_touch_up(index)
	var button := _button_at(screen_position)
	if button != null:
		_button_touches[index] = button
		button.press()
		return
	var local := get_global_transform().affine_inverse() * screen_position
	if local.x < size.x * joystick_zone_ratio:
		if _joystick_touch == -1 and joystick != null:
			_joystick_touch = index
			joystick.begin(joystick.get_global_transform().affine_inverse() * screen_position)
	elif _look_touch == -1:
		_look_touch = index


func _on_touch_drag(index: int, screen_position: Vector2, relative: Vector2) -> void:
	if index == _joystick_touch:
		joystick.drag(joystick.get_global_transform().affine_inverse() * screen_position)
	elif index == _look_touch:
		GameInput.add_touch_look(relative)
	elif _button_touches.has(index):
		# Arrastar o dedo para fora do botão o solta, como em botões físicos.
		var button: TouchActionButton = _button_touches[index]
		if not button.contains_global_point(screen_position):
			button.release()
			_button_touches.erase(index)


func _on_touch_up(index: int) -> void:
	if index == _joystick_touch:
		_joystick_touch = -1
		joystick.end()
		# Soltar o direcional para a corrida, como num jogo de celular.
		if sprint_button != null:
			sprint_button.set_active(false)
	elif index == _look_touch:
		_look_touch = -1
	elif _button_touches.has(index):
		(_button_touches[index] as TouchActionButton).release()
		_button_touches.erase(index)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var moving := joystick != null and joystick.is_active and joystick.output.length() > 0.2
	var wants_sprint := moving and ((sprint_button != null and sprint_button.is_active) or joystick.is_sprint_zone)
	if wants_sprint != _sprint_pressed:
		_sprint_pressed = wants_sprint
		if wants_sprint:
			Input.action_press(sprint_action)
		else:
			Input.action_release(sprint_action)


## Solta todos os toques ativos (ex.: ao abrir um menu ou perder o foco).
func release_all() -> void:
	if joystick != null and _joystick_touch != -1:
		joystick.end()
	_joystick_touch = -1
	_look_touch = -1
	for button: TouchActionButton in _button_touches.values():
		button.release()
	_button_touches.clear()
	if sprint_button != null:
		sprint_button.set_active(false)
	if _sprint_pressed:
		_sprint_pressed = false
		Input.action_release(sprint_action)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release_all()
