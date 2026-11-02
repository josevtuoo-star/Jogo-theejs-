class_name TouchMoveStick
extends Control
## Direcional analógico flutuante para touchscreen.
##
## O toque é roteado por TouchControls. A base aparece onde o dedo tocou;
## a saída pressiona as ações de movimento do InputMap com intensidade
## analógica. Empurrar o direcional além da borda, para frente, entra na
## zona de corrida (`is_sprint_zone`). O direcional NÃO pressiona a ação de
## correr: TouchControls é o único dono dela e combina a zona com o botão.

@export var action_left: StringName = &"move_left"
@export var action_right: StringName = &"move_right"
@export var action_forward: StringName = &"move_forward"
@export var action_back: StringName = &"move_back"

## Raio de deslocamento máximo do manche (pixels da viewport base).
@export_range(20.0, 300.0, 1.0) var radius: float = 90.0
## Fração do raio sem efeito (o dedo encostado não anda).
@export_range(0.0, 0.5, 0.01) var dead_zone: float = 0.12
## Posição de repouso como fração do tamanho do controle.
@export var rest_position_ratio: Vector2 = Vector2(0.16, 0.74)
## Distância, em múltiplos do raio, a partir da qual a corrida é ativada.
@export_range(1.0, 3.0, 0.01) var sprint_distance_ratio: float = 1.4
## Quão frontal precisa ser a direção para ativar a corrida (componente y).
@export_range(0.0, 1.0, 0.01) var sprint_min_forward: float = 0.8

@export var base_color: Color = Color(1, 1, 1, 0.18)
@export var knob_color: Color = Color(1, 1, 1, 0.45)
@export var sprint_color: Color = Color(1.0, 0.75, 0.3, 0.55)

var is_active: bool = false
var output: Vector2 = Vector2.ZERO
var is_sprint_zone: bool = false

var _center: Vector2
var _knob: Vector2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_reset_visual)
	_reset_visual()


func begin(local_position: Vector2) -> void:
	is_active = true
	_center = local_position
	_knob = local_position
	_update_output(local_position)


func drag(local_position: Vector2) -> void:
	if not is_active:
		return
	_update_output(local_position)


func end() -> void:
	is_active = false
	output = Vector2.ZERO
	is_sprint_zone = false
	_release_actions()
	_reset_visual()


func _update_output(local_position: Vector2) -> void:
	var offset := local_position - _center
	var distance := offset.length()
	var direction := offset / distance if distance > 0.0 else Vector2.ZERO
	# Zona morta (dedo apoiado não anda sozinho) e resposta suave: os
	# primeiros milímetros dão passos lentos e precisos.
	var amount := clampf((distance / radius - dead_zone) / (1.0 - dead_zone), 0.0, 1.0)
	output = direction * amount
	is_sprint_zone = distance >= radius * sprint_distance_ratio and -direction.y >= sprint_min_forward
	_knob = _center + direction * minf(distance, radius)
	_press_actions()
	queue_redraw()


func _press_actions() -> void:
	_set_action(action_left, maxf(-output.x, 0.0))
	_set_action(action_right, maxf(output.x, 0.0))
	_set_action(action_forward, maxf(-output.y, 0.0))
	_set_action(action_back, maxf(output.y, 0.0))


func _release_actions() -> void:
	for action in [action_left, action_right, action_forward, action_back]:
		Input.action_release(action)


func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _reset_visual() -> void:
	_center = size * rest_position_ratio
	_knob = _center
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and is_active:
		end()
	elif what == NOTIFICATION_EXIT_TREE and is_active:
		end()


func _draw() -> void:
	var alpha_scale := 1.0 if is_active else 0.6
	var ring := base_color
	ring.a *= alpha_scale
	draw_circle(_center, radius, ring)
	draw_arc(_center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.3 * alpha_scale), 2.0, true)
	if is_active:
		var sprint_ring := sprint_color if is_sprint_zone else Color(1, 1, 1, 0.08)
		draw_arc(_center, radius * sprint_distance_ratio, -PI * 0.5 - 0.6, -PI * 0.5 + 0.6, 24, sprint_ring, 4.0, true)
	var knob := knob_color
	knob.a *= alpha_scale
	draw_circle(_knob, radius * 0.42, knob)
