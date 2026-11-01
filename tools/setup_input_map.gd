extends SceneTree
## Ferramenta de manutenção: grava o mapa de entrada padrão em project.godot.
## Uso: godot --headless --path . --script res://tools/setup_input_map.gd


func _init() -> void:
	_add_action("move_forward", 0.2, [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add_action("move_back", 0.2, [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add_action("move_left", 0.2, [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_add_action("move_right", 0.2, [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_add_action("look_left", 0.15, [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_add_action("look_right", 0.15, [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_add_action("look_up", 0.15, [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_add_action("look_down", 0.15, [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_add_action("sprint", 0.5, [_key(KEY_SHIFT), _button(JOY_BUTTON_LEFT_STICK)])
	_add_action("jump", 0.5, [_key(KEY_SPACE), _button(JOY_BUTTON_A)])
	_add_action("crouch_toggle", 0.5, [_key(KEY_C), _button(JOY_BUTTON_B)])
	_add_action("crouch_hold", 0.5, [_key(KEY_CTRL)])
	_add_action("walk_toggle", 0.5, [_key(KEY_ALT), _button(JOY_BUTTON_RIGHT_STICK)])
	_add_action("attack", 0.5, [_mouse(MOUSE_BUTTON_LEFT), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_add_action("interact", 0.5, [_key(KEY_E), _button(JOY_BUTTON_X)])
	_add_action("toggle_mouse_capture", 0.5, [_key(KEY_ESCAPE)])
	_add_action("debug_toggle", 0.5, [_key(KEY_F3)])
	_add_action("debug_cycle_load", 0.5, [_key(KEY_F4)])
	var error := ProjectSettings.save()
	print("Mapa de entrada salvo: ", error_string(error))
	quit(0 if error == OK else 1)


func _add_action(action_name: String, deadzone: float, events: Array) -> void:
	ProjectSettings.set_setting("input/" + action_name, {"deadzone": deadzone, "events": events})


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.device = -1
	event.physical_keycode = keycode
	return event


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.device = -1
	event.button_index = button
	return event


func _button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	return event


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis
	event.axis_value = value
	return event
