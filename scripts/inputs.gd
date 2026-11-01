class_name Inputs
extends Object
## Ações de controle (teclado, mouse e controle) criadas ao abrir o jogo e o estado
## compartilhado entre o personagem e os botões de toque.

## Quanto o dedo arrastou no lado direito da tela desde o último quadro.
static var look_delta := Vector2.ZERO
## Celular/tablet: mostra os controles de toque.
static var touch_mode := false
static var crouching := false
static var first_person := false
## Texto do botão USAR ("" = nada por perto) e do botão PULAR/AGACHAR conforme o contexto.
static var use_label := ""
static var jump_label := "PULAR"
static var crouch_label := "AGACHAR"
## Mensagem curta no centro da tela (ex.: "Sem espaço") e por quanto tempo ainda aparece.
static var toast := ""
static var toast_t := 0.0
## Painel da mochila aberto (os controles de toque param de mover/olhar).
static var menu_open := false

const KEYS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE], "crouch": [KEY_C, KEY_CTRL], "sprint": [KEY_SHIFT],
	"punch": [KEY_F], "use": [KEY_E], "camera": [KEY_V], "reset": [KEY_R],
	"weapon": [KEY_Q], "inventory": [KEY_TAB, KEY_I],
}
const PAD_BUTTONS := {
	"jump": JOY_BUTTON_A, "crouch": JOY_BUTTON_B, "punch": JOY_BUTTON_X, "use": JOY_BUTTON_Y,
	"camera": JOY_BUTTON_RIGHT_STICK, "sprint": JOY_BUTTON_LEFT_STICK, "reset": JOY_BUTTON_BACK,
	"weapon": JOY_BUTTON_RIGHT_SHOULDER, "inventory": JOY_BUTTON_START,
}
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0],
}

static var _done := false


## Cria as ações (uma vez só).
static func setup() -> void:
	if _done:
		return
	_done = true
	for action in KEYS:
		_add(action)
		for key in KEYS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = key
			InputMap.action_add_event(action, e)
	for action in PAD_BUTTONS:
		var e := InputEventJoypadButton.new()
		e.button_index = PAD_BUTTONS[action]
		InputMap.action_add_event(action, e)
	for action in PAD_AXES:
		_add(action)
		var e := InputEventJoypadMotion.new()
		e.axis = PAD_AXES[action][0]
		e.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, e)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("punch", click)
	touch_mode = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


static func _add(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.15)


## Devolve e zera o arrasto acumulado do toque.
static func take_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d
