class_name TouchActionButton
extends Control
## Botão circular de toque. O roteamento multitoque (qual dedo pertence a
## qual botão) é feito por TouchControls; o botão só reage a press/release.
##
## Modos:
## - HOLD: pressiona `action` enquanto o dedo estiver no botão (pular,
##   atacar, defender, usar).
## - TOGGLE: cada toque alterna o estado e emite `toggled`; não pressiona a
##   ação sozinho. Quem decide o efeito é o dono da ação (ex.: TouchControls
##   combina o botão de corrida com o direcional).
## - TAP: pressiona `action` por um instante a cada toque (alternar câmera).

signal toggled(active: bool)

enum Mode { HOLD, TOGGLE, TAP }

@export var action: StringName = &"jump"
@export var mode: Mode = Mode.HOLD
@export var label: String = "PULAR"
@export_range(16.0, 200.0, 1.0) var radius: float = 52.0
## Margem extra de acerto (pixels), facilitando o toque sem olhar. Quando as
## margens de dois botões se sobrepõem, vale o botão de centro mais próximo.
@export_range(0.0, 60.0, 1.0) var hit_padding: float = 10.0
@export var idle_color: Color = Color(1, 1, 1, 0.2)
@export var pressed_color: Color = Color(1, 1, 1, 0.45)
@export var font_size: int = 18
## Rótulo e anel destacados quando o estado está ativo (alternância).
@export var active_label: String = ""
@export var active_color: Color = Color(0.95, 0.78, 0.35, 0.9)

var is_pressed: bool = false
var is_active: bool = false
var _feedback: float = 0.0
var _tap_frames: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * radius * 2.0
	set_process(false)


func get_center_global() -> Vector2:
	return get_global_rect().get_center()


func get_hit_radius_global() -> float:
	return (radius + hit_padding) * get_global_transform().get_scale().x


func contains_global_point(point: Vector2) -> bool:
	return point.distance_to(get_center_global()) <= get_hit_radius_global()


## Distância do ponto ao centro em múltiplos do raio de acerto (< 1 = dentro).
func hit_distance(point: Vector2) -> float:
	return point.distance_to(get_center_global()) / get_hit_radius_global()


func press() -> void:
	if is_pressed:
		return
	is_pressed = true
	match mode:
		Mode.HOLD:
			Input.action_press(action)
		Mode.TOGGLE:
			set_active(not is_active)
			toggled.emit(is_active)
		Mode.TAP:
			Input.action_press(action)
			_tap_frames = 2
			set_process(true)
	queue_redraw()


func release() -> void:
	if not is_pressed:
		return
	is_pressed = false
	if mode == Mode.HOLD:
		Input.action_release(action)
	queue_redraw()


## Estado de alternância exibido pelo botão (não pressiona a ação).
func set_active(active: bool) -> void:
	if active == is_active:
		return
	is_active = active
	_feedback = 1.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if _tap_frames > 0:
		# O toque dura dois quadros: tempo para o leitor de borda ver a ação.
		_tap_frames -= 1
		if _tap_frames == 0:
			Input.action_release(action)
	# Pulso curto confirmando a troca de estado.
	_feedback = maxf(_feedback - delta * 3.0, 0.0)
	queue_redraw()
	if _feedback <= 0.0 and _tap_frames == 0:
		set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release()
	elif what == NOTIFICATION_EXIT_TREE:
		release()
		if _tap_frames > 0:
			Input.action_release(action)


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
