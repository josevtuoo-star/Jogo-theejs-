extends Node
## Autoload "GameInput": unifica a entrada de visão (mouse, touchscreen e
## gamepad) em um único acumulador em radianos, consumido pelo jogador.
##
## A entrada de movimento usa as ações do InputMap diretamente; os controles
## de toque pressionam essas mesmas ações com intensidade analógica, então o
## controlador do jogador não precisa saber de onde veio o comando.

## Radianos por pixel de movimento do mouse.
var mouse_sensitivity: float = 0.0022
## Radianos por pixel de arrasto na tela (coordenadas da viewport base 1280x720).
var touch_sensitivity: float = 0.0052
## Velocidade máxima de giro com o analógico direito (rad/s).
var gamepad_look_speed: float = 3.2
var invert_y: bool = false

var _look_delta: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not uses_touch_controls() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_look_delta += (event as InputEventMouseMotion).screen_relative * mouse_sensitivity
	elif event.is_action_pressed("toggle_mouse_capture"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not uses_touch_controls():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick != Vector2.ZERO:
		# Curva quadrática: precisão em pequenos desvios, giro rápido no limite.
		_look_delta += stick * stick.length() * gamepad_look_speed * delta


## Adiciona arrasto de toque (em pixels da viewport) ao acumulador de visão.
func add_touch_look(relative_pixels: Vector2) -> void:
	_look_delta += relative_pixels * touch_sensitivity


## Adiciona rotação diretamente em radianos (x = guinada, y = arfagem).
func add_look_radians(radians: Vector2) -> void:
	_look_delta += radians


## Retorna e zera a rotação acumulada desde a última chamada.
func consume_look() -> Vector2:
	var result := _look_delta
	_look_delta = Vector2.ZERO
	if invert_y:
		result.y = -result.y
	return result


## Verdadeiro em celulares/tablets ou quando forçado nas configurações do projeto.
func uses_touch_controls() -> bool:
	if ProjectSettings.get_setting("ultimo_amanhecer/input/force_touch_controls", false):
		return true
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
