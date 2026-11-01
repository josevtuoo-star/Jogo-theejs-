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

var is_pressed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * radius * 2.0


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
	draw_arc(center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
	var font := get_theme_default_font()
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var baseline := center + Vector2(-text_size.x * 0.5, font.get_ascent(font_size) * 0.5 - 2.0)
	draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.85))
