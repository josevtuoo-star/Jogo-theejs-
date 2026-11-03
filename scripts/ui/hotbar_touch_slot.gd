class_name HotbarTouchSlot
extends TouchActionButton
## Casa da barra rápida no toque: área de toque (roteada por TouchControls,
## então um dedo aqui nunca vira câmera nem golpe) exatamente sobre o desenho
## da casa feito pelo InventoryHud. Toque = empunhar/guardar a ferramenta.

@export var slot_index: int = 0


func _ready() -> void:
	super._ready()
	mode = Mode.TAP
	action = StringName("hotbar_%d" % (slot_index + 1))
	label = ""
	_follow()
	get_viewport().size_changed.connect(_follow)
	if get_parent() is Control:
		(get_parent() as Control).resized.connect(_follow)


func _follow() -> void:
	var screen := get_viewport().get_visible_rect().size
	var parent_rect := (get_parent() as Control).get_global_rect() if get_parent() is Control else Rect2(Vector2.ZERO, screen)
	var center := InventoryHud.slot_center(slot_index, parent_rect.size)
	radius = InventoryHud.slot_metrics(parent_rect.size).y * 0.5
	size = Vector2.ONE * radius * 2.0
	position = center - size * 0.5


func _draw() -> void:
	# O desenho da casa é do InventoryHud; aqui só o retorno do toque.
	if is_pressed:
		draw_circle(size * 0.5, radius, Color(1, 1, 1, 0.18))
