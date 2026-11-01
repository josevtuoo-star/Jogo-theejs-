class_name TouchControls
extends Control
## Roteador multitoque dos controles de tela.
##
## Cada dedo é associado, no momento do toque, a um único destino (botão,
## direcional ou área de visão) e permanece com ele até ser levantado.
## Prioridade: botões > direcional (lado esquerdo) > visão (lado direito).

@export var joystick: TouchMoveStick
@export var buttons: Array[TouchActionButton] = []
## Fração da largura da tela que pertence ao direcional (o resto é visão).
@export_range(0.1, 0.9, 0.01) var joystick_zone_ratio: float = 0.42
## Exibir mesmo sem touchscreen (para testes no PC com emulação de toque).
@export var always_visible: bool = false

var _joystick_touch: int = -1
var _look_touch: int = -1
var _button_touches: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = always_visible or GameInput.uses_touch_controls()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_on_touch_down(touch.index, touch.position)
		else:
			_on_touch_up(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_on_touch_drag(drag.index, drag.position, drag.relative)


func _on_touch_down(index: int, screen_position: Vector2) -> void:
	_on_touch_up(index)
	for button in buttons:
		if button.is_visible_in_tree() and button.contains_global_point(screen_position):
			_button_touches[index] = button
			button.press()
			get_viewport().set_input_as_handled()
			return
	var local := get_global_transform().affine_inverse() * screen_position
	if local.x < size.x * joystick_zone_ratio:
		if _joystick_touch == -1 and joystick != null:
			_joystick_touch = index
			joystick.begin(joystick.get_global_transform().affine_inverse() * screen_position)
			get_viewport().set_input_as_handled()
	elif _look_touch == -1:
		_look_touch = index
		get_viewport().set_input_as_handled()


func _on_touch_drag(index: int, screen_position: Vector2, relative: Vector2) -> void:
	if index == _joystick_touch:
		joystick.drag(joystick.get_global_transform().affine_inverse() * screen_position)
		get_viewport().set_input_as_handled()
	elif index == _look_touch:
		GameInput.add_touch_look(relative)
		get_viewport().set_input_as_handled()
	elif _button_touches.has(index):
		# Arrastar o dedo para fora do botão o solta, como em botões físicos.
		var button: TouchActionButton = _button_touches[index]
		if not button.contains_global_point(screen_position):
			button.release()
			_button_touches.erase(index)
		get_viewport().set_input_as_handled()


func _on_touch_up(index: int) -> void:
	if index == _joystick_touch:
		_joystick_touch = -1
		joystick.end()
	elif index == _look_touch:
		_look_touch = -1
	elif _button_touches.has(index):
		(_button_touches[index] as TouchActionButton).release()
		_button_touches.erase(index)


## Solta todos os toques ativos (ex.: ao abrir um menu ou perder o foco).
func release_all() -> void:
	if joystick != null and _joystick_touch != -1:
		joystick.end()
	_joystick_touch = -1
	_look_touch = -1
	for button: TouchActionButton in _button_touches.values():
		button.release()
	_button_touches.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release_all()
