class_name CaveCompass
extends CanvasLayer
## Indicação discreta, no alto da tela, da boca de caverna mais próxima
## (até 250 m): seta na direção relativa à câmera e a distância. Some dentro
## da caverna e quando não há nenhuma por perto.

const RADIUS := 250.0

@export var world: ProceduralWorld
@export var camera: Camera3D

var _label: Label
var _arrow: Control
var _angle: float = 0.0
var _timer: float = 0.0


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_arrow = Control.new()
	_arrow.size = Vector2(28.0, 28.0)
	_arrow.position = Vector2(-110.0, 14.0)
	_arrow.pivot_offset = _arrow.size * 0.5
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(func() -> void:
		var c := _arrow.size * 0.5
		_arrow.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -12), c + Vector2(9, 9), c + Vector2(0, 4), c + Vector2(-9, 9)]),
				Color(0.95, 0.85, 0.6, 0.9)))
	root.add_child(_arrow)
	_label = Label.new()
	_label.position = Vector2(-78.0, 14.0)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	root.add_child(_label)


func _process(delta: float) -> void:
	if world == null or camera == null or world.generator == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.5
		_update()
	_arrow.rotation = lerp_angle(_arrow.rotation, _angle, 1.0 - exp(-10.0 * delta))


func _update() -> void:
	var p := camera.global_position
	var g := world.generator
	var underground := p.y < g.surface_height(p.x, p.z) - 3.0
	var best := Vector3.INF
	var best_distance := RADIUS
	if not underground:
		for e: Dictionary in g.entrances_near(p, RADIUS):
			var top: Vector3 = e["top"]
			var d := Vector2(top.x - p.x, top.z - p.z).length()
			if d < best_distance:
				best_distance = d
				best = top
	var visible_now := best != Vector3.INF and best_distance > 6.0
	_label.visible = visible_now
	_arrow.visible = visible_now
	if not visible_now:
		return
	_label.text = "Caverna  %d m" % roundi(best_distance)
	var forward := -camera.global_basis.z
	var heading := atan2(forward.x, -forward.z)
	var target := atan2(best.x - p.x, -(best.z - p.z))
	_angle = wrapf(target - heading, -PI, PI)
