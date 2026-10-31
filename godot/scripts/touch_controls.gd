extends Control
## Controles de toque:
## - analógico flutuante no lado esquerdo (aparece onde o dedo encosta); empurrar o dedo
##   além do anel externo = correr;
## - arrastar no lado direito = olhar;
## - botões: SOCO, CHUTE, PULAR, AGACHAR (liga/desliga), CÂMERA (1ª/3ª pessoa) e reiniciar.
##   PULAR e AGACHAR mudam de nome conforme o parkour possível (SUBIR, SALTAR, ESCALAR,
##   DESLIZAR, SOLTAR...).
## Tudo funciona com vários dedos ao mesmo tempo.

const JOY_R := 80.0
const KNOB_R := 34.0
const SPRINT_K := 1.35 # passar deste raio (x JOY_R) = correr
## pos: x negativo = a partir da borda direita; y negativo = a partir de baixo
const BUTTONS := [
	{"action": "punch", "label": "SOCO", "pos": Vector2(-140, -150), "r": 66.0},
	{"action": "jump", "label": "PULAR", "pos": Vector2(-290, -92), "r": 54.0},
	{"action": "crouch", "label": "AGACHAR", "pos": Vector2(-118, -310), "r": 46.0},
	{"action": "kick", "label": "CHUTE", "pos": Vector2(-268, -238), "r": 42.0},
	{"action": "camera", "label": "1ª/3ª", "pos": Vector2(-64, 64), "r": 38.0},
	{"action": "reset", "label": "↺", "pos": Vector2(-152, 64), "r": 30.0},
]

var _joy_finger := -1
var _joy_center := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _sprint := false
var _look_finger := -1
var _btn_finger := {} # dedo -> índice do botão
var _pressed_frame := {} # ação -> quadro da física em que foi apertada
var _pending_release := []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = Inputs.touch_mode


func _default_joy_center() -> Vector2:
	return Vector2(190.0, size.y - 170.0)


func _btn_center(b: Dictionary) -> Vector2:
	var p: Vector2 = b.pos
	return Vector2(size.x + p.x if p.x < 0.0 else p.x, size.y + p.y if p.y < 0.0 else p.y)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not visible:
			visible = true
			Inputs.touch_mode = true
		if event.pressed:
			_down(event.index, event.position)
		else:
			_up(event.index)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position, event.relative)
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_F1:
		visible = not visible


func _down(finger: int, p: Vector2) -> void:
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		if p.distance_to(_btn_center(b)) <= b.r * 1.15:
			_btn_finger[finger] = i
			_press(b.action)
			return
	if p.x < size.x * 0.45 and p.y > size.y * 0.3 and _joy_finger < 0:
		_joy_finger = finger
		# analógico flutuante: se encostou longe da base, a base vem até o dedo
		_joy_center = p if p.distance_to(_default_joy_center()) > JOY_R else _default_joy_center()
		_set_joy(p)
	elif _look_finger < 0:
		_look_finger = finger


func _drag(finger: int, p: Vector2, rel: Vector2) -> void:
	if finger == _joy_finger:
		_set_joy(p)
	elif finger == _look_finger:
		Inputs.look_delta += rel


func _up(finger: int) -> void:
	if finger == _joy_finger:
		_joy_finger = -1
		_joy_vec = Vector2.ZERO
		_apply_joy()
	elif finger == _look_finger:
		_look_finger = -1
	elif _btn_finger.has(finger):
		_release(BUTTONS[_btn_finger[finger]].action)
		_btn_finger.erase(finger)


func _set_joy(p: Vector2) -> void:
	var d := p - _joy_center
	_sprint = d.length() > JOY_R * SPRINT_K
	_joy_vec = d / JOY_R
	if _joy_vec.length() > 1.0:
		_joy_vec = _joy_vec.normalized()
	_apply_joy()


func _apply_joy() -> void:
	var v := _joy_vec
	_axis("move_right", maxf(v.x, 0.0))
	_axis("move_left", maxf(-v.x, 0.0))
	_axis("move_back", maxf(v.y, 0.0))
	_axis("move_forward", maxf(-v.y, 0.0))
	if _sprint and _joy_finger >= 0:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")
		_sprint = false


func _axis(action: String, v: float) -> void:
	if v > 0.0:
		Input.action_press(action, v)
	else:
		Input.action_release(action)


func _press(action: String) -> void:
	Input.action_press(action)
	_pressed_frame[action] = Engine.get_physics_frames()


## Um toque muito rápido (apertar e soltar entre dois passos da física) ainda conta: a ação
## só é solta depois que a física a viu apertada.
func _release(action: String) -> void:
	if _pressed_frame.get(action, -1) >= Engine.get_physics_frames():
		_pending_release.append(action)
	else:
		Input.action_release(action)


func _physics_process(_delta: float) -> void:
	if _pending_release.is_empty():
		return
	var still := []
	for a in _pending_release:
		if _pressed_frame.get(a, -1) < Engine.get_physics_frames():
			Input.action_release(a)
		else:
			still.append(a)
	_pending_release = still


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var c := _joy_center if _joy_finger >= 0 else _default_joy_center()
	var active := _joy_finger >= 0
	draw_circle(c, JOY_R, Color(0, 0, 0, 0.22 if active else 0.14))
	draw_arc(c, JOY_R, 0.0, TAU, 64, Color(1, 1, 1, 0.5 if active else 0.3), 3.0, true)
	draw_arc(c, JOY_R * SPRINT_K, 0.0, TAU, 64, Color(1, 0.8, 0.3, 0.75) if _sprint else Color(1, 1, 1, 0.1), 2.0, true)
	draw_circle(c + _joy_vec * JOY_R, KNOB_R, Color(1, 1, 1, 0.55 if active else 0.35))
	if _sprint:
		draw_string(font, c + Vector2(-40, -JOY_R * SPRINT_K - 10), "CORRENDO", HORIZONTAL_ALIGNMENT_CENTER, 80, 15, Color(1, 0.85, 0.4))
	var held := {}
	for f in _btn_finger:
		held[_btn_finger[f]] = true
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		var bc := _btn_center(b)
		var on: bool = held.has(i) or (b.action == "crouch" and Inputs.crouching) \
			or (b.action == "camera" and Inputs.first_person)
		draw_circle(bc, b.r, Color(1, 0.75, 0.3, 0.45) if on else Color(0, 0, 0, 0.3))
		draw_arc(bc, b.r, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 2.5, true)
		var label: String = b.label
		if b.action == "jump":
			label = Inputs.jump_label
		elif b.action == "crouch":
			label = Inputs.crouch_label
		var fs := 22 if label == "↺" else (17 if b.r > 50.0 else 14)
		var hint: bool = b.action in ["jump", "crouch"] and label != b.label and label != "LEVANTAR"
		draw_string(font, bc + Vector2(-b.r, fs * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, fs, Color(1, 0.85, 0.4) if hint else Color(1, 1, 1, 0.92))
