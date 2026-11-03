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
	_add_action("block", 0.5, [_key(KEY_Q), _mouse(MOUSE_BUTTON_RIGHT), _button(JOY_BUTTON_LEFT_SHOULDER)])
	_add_action("jump", 0.5, [_key(KEY_SPACE), _button(JOY_BUTTON_A)])
	_add_action("crouch_toggle", 0.5, [_key(KEY_C), _button(JOY_BUTTON_B)])
	_add_action("crouch_hold", 0.5, [_key(KEY_CTRL)])
	_add_action("walk_toggle", 0.5, [_key(KEY_ALT), _button(JOY_BUTTON_RIGHT_STICK)])
	_add_action("attack", 0.5, [_mouse(MOUSE_BUTTON_LEFT), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_add_action("interact", 0.5, [_key(KEY_E), _button(JOY_BUTTON_X)])
	_add_action("drop_weapon", 0.5, [_key(KEY_G), _button(JOY_BUTTON_DPAD_DOWN)])
	_add_action("toggle_camera", 0.5, [_key(KEY_V), _button(JOY_BUTTON_BACK)])
	# Barra rápida de ferramentas e mochila (etapa 8).
	_add_action("hotbar_1", 0.5, [_key(KEY_1)])
	_add_action("hotbar_2", 0.5, [_key(KEY_2)])
	_add_action("hotbar_3", 0.5, [_key(KEY_3)])
	_add_action("hotbar_4", 0.5, [_key(KEY_4)])
	# Etapa 9: barra de 9 casas, menu de pausa.
	_add_action("hotbar_5", 0.5, [_key(KEY_5)])
	_add_action("hotbar_6", 0.5, [_key(KEY_6)])
	_add_action("hotbar_7", 0.5, [_key(KEY_7)])
	_add_action("hotbar_8", 0.5, [_key(KEY_8)])
	_add_action("hotbar_9", 0.5, [_key(KEY_9)])
	_add_action("pause_menu", 0.5, [_key(KEY_P), _button(JOY_BUTTON_START)])
	_add_action("hotbar_next", 0.5, [_button(JOY_BUTTON_DPAD_RIGHT)])
	_add_action("hotbar_prev", 0.5, [_button(JOY_BUTTON_DPAD_LEFT)])
	_add_action("inventory_toggle", 0.5, [_key(KEY_I), _key(KEY_TAB), _button(JOY_BUTTON_Y)])
	_add_action("camera_zoom_in", 0.5, [_mouse(MOUSE_BUTTON_WHEEL_UP)])
	_add_action("camera_zoom_out", 0.5, [_mouse(MOUSE_BUTTON_WHEEL_DOWN)])
	_add_action("toggle_mouse_capture", 0.5, [_key(KEY_ESCAPE)])
	_add_action("debug_toggle", 0.5, [_key(KEY_F3)])
	_add_action("debug_cycle_load", 0.5, [_key(KEY_F4)])
	# A emulação de mouse a partir do toque continua ligada: é por ela que os
	# botões da interface (Button, menus) recebem toques no Android. O que
	# impede um arrasto de virar ataque é a regra de _mouse(): as ações de jogo
	# só aceitam o mouse físico (dispositivo 0), nunca o emulado (-1).
	ProjectSettings.set_setting("input_devices/pointing/emulate_mouse_from_touch", true)
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


## Botões do mouse valem só para o mouse físico (dispositivo 0). Eventos de
## mouse emulados a partir do toque usam InputEvent.DEVICE_ID_EMULATION (-1)
## e não acionam ações: um arrasto na tela jamais vira ataque, mesmo que a
## emulação seja ligada.
func _mouse(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.device = 0
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
