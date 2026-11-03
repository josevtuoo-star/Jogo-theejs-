class_name InventorySlotView
extends Button
## Uma casa da mochila na tela: fundo, moldura, ícone, quantidade e barra de
## durabilidade. É um botão (toque e clique funcionam igual); o InventoryHud
## decide o que o toque faz (selecionar, mover, vestir, fabricar).

## Casa da mochila mostrada (-1 = resultado da bancada).
var index: int = -1
var inventory: Inventory
## Destaque: 0 nenhum, 1 selecionada para mover, 2 na mão.
var highlight: int = 0
## Texto de fundo da casa vazia (ex.: "CABEÇA").
var hint: String = ""
## Item mostrado quando a casa não é da mochila (resultado da bancada).
var preview_item: ItemData
var preview_count: int = 0
var size_px: float = 64.0

var _icon: TextureRect
var _count: Label
var _hint: Label
var _bar: Control


func _init(slot_index: int = -1, owner_inventory: Inventory = null, pixels: float = 64.0) -> void:
	index = slot_index
	inventory = owner_inventory
	size_px = pixels
	custom_minimum_size = Vector2.ONE * pixels
	size = Vector2.ONE * pixels
	flat = true
	focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, empty)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.28))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.position = Vector2.ONE * pixels * 0.09
	_icon.size = Vector2.ONE * pixels * 0.82
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_icon)
	_count = Label.new()
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.position = Vector2(0.0, pixels - 22.0)
	_count.size = Vector2(pixels - 5.0, 20.0)
	_count.add_theme_font_size_override("font_size", 14)
	_count.add_theme_color_override("font_outline_color", Color.BLACK)
	_count.add_theme_constant_override("outline_size", 4)
	add_child(_count)
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.size = Vector2.ONE * pixels
	_bar.draw.connect(_draw_bar)
	add_child(_bar)


func refresh() -> void:
	var item: ItemData = preview_item
	var amount := preview_count
	if index >= 0 and inventory != null:
		var entry := inventory.tool_at(index)
		item = entry.get("item")
		amount = int(entry.get("count", 0))
	_icon.texture = item.get_icon() if item != null else null
	_count.text = str(amount) if item != null and amount > 1 else ""
	_hint.text = hint if item == null else ""
	queue_redraw()
	_bar.queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var back := Color(0.07, 0.075, 0.07, 0.82)
	if is_hovered() and not disabled:
		back = Color(0.13, 0.14, 0.12, 0.9)
	draw_rect(rect, back)
	# Bisel: claro em cima/esquerda, escuro embaixo/direita (casa afundada).
	draw_line(Vector2(0, 0), Vector2(size.x, 0), Color(0, 0, 0, 0.6), 2.0)
	draw_line(Vector2(0, 0), Vector2(0, size.y), Color(0, 0, 0, 0.6), 2.0)
	draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(1, 1, 1, 0.12), 2.0)
	draw_line(Vector2(size.x - 1, 0), Vector2(size.x - 1, size.y), Color(1, 1, 1, 0.12), 2.0)
	if highlight == 2:
		draw_rect(rect.grow(-1.5), Color(0.95, 0.78, 0.35, 0.95), false, 3.0)
	elif highlight == 1:
		draw_rect(rect, Color(0.95, 0.78, 0.35, 0.18))
		draw_rect(rect.grow(-1.5), Color(1.0, 0.93, 0.7, 0.95), false, 3.0)


func _draw_bar() -> void:
	if index < 0 or inventory == null:
		return
	var entry := inventory.tool_at(index)
	if entry.is_empty() or not (entry["item"] as ItemData).has_durability():
		return
	var fraction := inventory.durability_fraction(index)
	if fraction >= 0.999:
		return
	var back := Rect2(size_px * 0.1, size_px - 8.0, size_px * 0.8, 4.0)
	_bar.draw_rect(back, Color(0, 0, 0, 0.7))
	var color := Color(0.4, 0.85, 0.35).lerp(Color(0.9, 0.2, 0.15), 1.0 - fraction)
	_bar.draw_rect(Rect2(back.position, Vector2(back.size.x * fraction, back.size.y)), color)
