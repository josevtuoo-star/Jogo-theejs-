class_name TouchActionButton
extends Control
## Botão circular de toque que pressiona uma ação do InputMap enquanto o
## dedo estiver sobre ele. O roteamento multitoque é feito por TouchControls.

@export var action: StringName = &"jump"
@export var label: String = "PULAR"
@export_range(16.0, 200.0, 1.0) var radius: float = 52.0
## Margem extra de acerto (pixels), facilitando o toque sem olhar.
@export_range(0.0, 60.0, 1.0) var hit_padding: float = 14.0
@export var idle_color: Color = Color(1, 1, 1, 0.2)
@export var pressed_color: Color = Color(1, 1, 1, 0.45)
@export var font_size: int = 18
## Botões de alternância (ex.: câmera) mostram o estado: anel destacado e
## rótulo próprio quando ativos.
@export var active_label: String = ""
@export var active_color: Color = Color(0.95, 0.78, 0.35, 0.9)

var is_pressed: bool = false
var is_active: bool = false
var _feedback: float = 0.0


## Estado de alternância exibido pelo botão (não pressiona a ação).
func set_active(active: bool) -> void:
	is_active = active
	_feedback = 1.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	# Pulso curto confirmando a troca de estado.
	_feedback = maxf(_feedback - delta * 3.0, 0.0)
	queue_redraw()
	if _feedback <= 0.0:
		set_process(false)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * radius * 2.0
	set_process(false)


func get_center_global() -> Vector2:
	return get_global_rect().get_center()


func contains_global_point(point: Vector2) -> bool:
	var scale_factor := get_global_transform().get_scale().x
	return point.distance_to(get_center_global()) <= (radius + hit_padding) * scale_factor


func press() -> void:
	if is_pressed:
		return
	is_pressed = true
	Input.action_press(action)
	queue_redraw()


func release() -> void:
	if not is_pressed:
		return
	is_pressed = false
	Input.action_release(action)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release()
	elif what == NOTIFICATION_EXIT_TREE:
		release()


func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius, pressed_color if is_pressed else idle_color)
	if _feedback > 0.0:
		draw_circle(center, radius * (1.0 + 0.25 * (1.0 - _feedback)), Color(active_color, 0.35 * _feedback))
	var ring := active_color if is_active else Color(1, 1, 1, 0.35)
	draw_arc(center, radius, 0.0, TAU, 48, ring, 3.0 if is_active else 2.0, true)
	var text := active_label if is_active and active_label != "" else label
	var font := get_theme_default_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var baseline := center + Vector2(-text_size.x * 0.5, font.get_ascent(font_size) * 0.5 - 2.0)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.85))
