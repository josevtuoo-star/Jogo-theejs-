class_name InventoryHud
extends CanvasLayer
## Interface da mochila:
## - barra rápida (4 ferramentas) embaixo, com ícone, tecla e durabilidade; a
##   casa na mão fica destacada. No toque, as casas são botões do roteador
##   multitoque (HotbarTouchSlot) exatamente sobre estes desenhos;
## - cartão do item em foco (ícone e nome) sob a mira, e o botão de toque
##   USAR vira PEGAR;
## - avisos de coleta ("+3 Madeira" com ícone) e de quebra;
## - painel MOCHILA (I / Tab / botão MOCHILA): ferramentas com durabilidade
##   (empunhar, guardar, soltar), recursos com quantidade (soltar) e
##   ORGANIZAR. Com o painel aberto, o jogador para e os controles de toque
##   somem (um toque no painel nunca vira câmera nem golpe).

const SLOT_SIZE := 72.0
const SLOT_GAP := 10.0
const BOTTOM_MARGIN := 16.0

@export var player: PlayerController
@export var inventory: Inventory
@export var interaction: InteractionComponent

var is_open: bool = false
## Visibilidade de cada camada de toque antes de abrir (restaurada ao fechar).
var _touch_visibility: Dictionary = {}

var _hotbar: Control
var _slots: Array[Control] = []
var _toasts: VBoxContainer
var _card: HBoxContainer
var _card_icon: TextureRect
var _card_label: Label
var _panel: Control
var _tool_list: VBoxContainer
var _resource_list: VBoxContainer


func _ready() -> void:
	layer = 6
	_build()
	if inventory != null:
		inventory.changed.connect(_refresh)
		inventory.item_added.connect(_on_item_added)
		inventory.message.connect(func(text: String) -> void: _toast(null, text))
	if interaction != null:
		interaction.focus_changed.connect(_on_focus_changed)
	_refresh()


## Centro de uma casa da barra rápida na tela (os botões de toque usam o mesmo).
static func slot_center(index: int, screen: Vector2) -> Vector2:
	var x := screen.x * 0.5 + (index - (Inventory.TOOL_SLOTS - 1) * 0.5) * (SLOT_SIZE + SLOT_GAP)
	return Vector2(x, screen.y - BOTTOM_MARGIN - SLOT_SIZE * 0.5)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_hotbar = Control.new()
	_hotbar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hotbar)
	for i in Inventory.TOOL_SLOTS:
		# Casa: fundo e moldura desenhados; ícone, número e durabilidade em
		# nós próprios (desenhar texto e textura na mesma chamada saía com o
		# ícone branco no renderizador de compatibilidade).
		var slot := Control.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.size = Vector2.ONE * SLOT_SIZE
		slot.draw.connect(_draw_slot.bind(slot, i))
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2.ONE * 6.0
		icon.size = Vector2.ONE * (SLOT_SIZE - 12.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.add_child(icon)
		var key := Label.new()
		key.name = "Key"
		key.text = str(i + 1)
		key.position = Vector2(5.0, 1.0)
		key.add_theme_font_size_override("font_size", 12)
		key.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		key.add_theme_color_override("font_outline_color", Color.BLACK)
		key.add_theme_constant_override("outline_size", 3)
		key.visible = not GameInput.uses_touch_controls()
		slot.add_child(key)
		var bar := Control.new()
		bar.name = "Durability"
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size = slot.size
		bar.draw.connect(_draw_durability.bind(bar, i))
		slot.add_child(bar)
		_hotbar.add_child(slot)
		_slots.append(slot)
	_hotbar.resized.connect(_place_slots)
	_place_slots()

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toasts.position = Vector2(-330.0, 122.0)
	_toasts.custom_minimum_size = Vector2(300.0, 0.0)
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)

	_card = HBoxContainer.new()
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.position = Vector2(-130.0, 58.0)
	_card.custom_minimum_size = Vector2(260.0, 48.0)
	_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	root.add_child(_card)
	_card_icon = TextureRect.new()
	_card_icon.custom_minimum_size = Vector2(48.0, 48.0)
	_card_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card.add_child(_card_icon)
	_card_label = _label("", 16)
	_card.add_child(_card_label)

	_build_panel(root)


func _place_slots() -> void:
	var screen := _hotbar.size
	for i in _slots.size():
		_slots[i].position = slot_center(i, screen) - Vector2.ONE * SLOT_SIZE * 0.5


func _draw_slot(slot: Control, index: int) -> void:
	var rect := Rect2(Vector2.ZERO, slot.size)
	var held := inventory != null and inventory.selected == index
	slot.draw_rect(rect, Color(0.05, 0.06, 0.06, 0.55))
	slot.draw_rect(rect, Color(0.95, 0.78, 0.35, 0.95) if held else Color(1, 1, 1, 0.3), false, 3.0 if held else 1.5)


func _draw_durability(bar: Control, index: int) -> void:
	if inventory == null or inventory.tool_at(index).is_empty():
		return
	var fraction := inventory.durability_fraction(index)
	var back := Rect2(6.0, bar.size.y - 9.0, bar.size.x - 12.0, 4.0)
	bar.draw_rect(back, Color(0, 0, 0, 0.6))
	var color := Color(0.4, 0.85, 0.35).lerp(Color(0.9, 0.2, 0.15), 1.0 - fraction)
	bar.draw_rect(Rect2(back.position, Vector2(back.size.x * fraction, back.size.y)), color)


func _build_panel(root: Control) -> void:
	_panel = ColorRect.new()
	(_panel as ColorRect).color = Color(0.0, 0.0, 0.0, 0.55)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	root.add_child(_panel)
	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.custom_minimum_size = Vector2(620.0, 430.0)
	frame.position = Vector2(-310.0, -215.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.09, 0.96)
	style.border_color = Color(0.95, 0.78, 0.35, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	frame.add_theme_stylebox_override("panel", style)
	_panel.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("MOCHILA", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("ORGANIZAR", func() -> void: inventory.sort()))
	header.add_child(_button("FECHAR", close))
	column.add_child(_label("Ferramentas", 16))
	_tool_list = VBoxContainer.new()
	column.add_child(_tool_list)
	column.add_child(_label("Recursos", 16))
	_resource_list = VBoxContainer.new()
	column.add_child(_resource_list)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(118.0, 46.0)
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(action)
	return button


func _icon(item: ItemData) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = item.get_icon()
	rect.custom_minimum_size = Vector2(44.0, 44.0)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return rect


# --- Atualização ---------------------------------------------------------------

func _refresh() -> void:
	for i in _slots.size():
		var slot := _slots[i]
		var entry := inventory.tool_at(i) if inventory != null else {}
		(slot.get_node("Icon") as TextureRect).texture = (entry["item"] as ItemData).get_icon() if not entry.is_empty() else null
		slot.queue_redraw()
		(slot.get_node("Durability") as Control).queue_redraw()
	if inventory == null:
		return
	get_tree().call_group(&"drop_weapon_button", &"set_visible", inventory.selected >= 0)
	if not is_open:
		return
	for child in _tool_list.get_children():
		child.free()
	for child in _resource_list.get_children():
		child.free()
	for i in Inventory.TOOL_SLOTS:
		var entry := inventory.tool_at(i)
		if entry.is_empty():
			continue
		var item: ItemData = entry["item"]
		var row := HBoxContainer.new()
		row.add_child(_icon(item))
		var name := _label("%d  %s" % [i + 1, item.display_name], 16)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(110.0, 14.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.value = inventory.durability_fraction(i) * 100.0
		bar.tooltip_text = "Durabilidade"
		row.add_child(bar)
		var slot := i
		if inventory.selected == i:
			row.add_child(_button("GUARDAR", func() -> void: inventory.unequip()))
		else:
			row.add_child(_button("EMPUNHAR", func() -> void: inventory.equip(slot)))
		row.add_child(_button("SOLTAR", func() -> void: inventory.drop_tool(slot)))
		_tool_list.add_child(row)
	if inventory.tool_count() == 0:
		_tool_list.add_child(_label("(nenhuma)", 14))
	var ids := inventory.resources.keys()
	ids.sort()
	for id in ids:
		var item := ItemData.find(id)
		var row := HBoxContainer.new()
		row.add_child(_icon(item))
		var name := _label("%s  ×%d" % [item.display_name, inventory.count(id)], 16)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var item_id: StringName = id
		row.add_child(_button("SOLTAR 1", func() -> void: inventory.drop_resource(item_id, 1)))
		_resource_list.add_child(row)
	if ids.is_empty():
		_resource_list.add_child(_label("(vazio)", 14))


func _on_item_added(item: ItemData, amount: int) -> void:
	_toast(item, "+%d %s" % [amount, item.display_name])


func _toast(item: ItemData, text: String) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item != null:
		row.add_child(_icon(item))
	row.add_child(_label(text, 17))
	_toasts.add_child(row)
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).free()
	var tween := create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(row, "modulate:a", 0.0, 0.6)
	tween.tween_callback(row.queue_free)


func _on_focus_changed(target: Interactable) -> void:
	var item: ItemData = null
	if target is ItemPickup:
		item = (target as ItemPickup).item
	elif target is WeaponPickup and (target as WeaponPickup).weapon != null:
		item = ItemData.find((target as WeaponPickup).weapon.id)
	_card.visible = item != null
	if item != null:
		_card_icon.texture = item.get_icon()
		_card_label.text = item.display_name
	# O botão de toque USAR vira PEGAR diante de um item.
	for button in get_tree().get_nodes_in_group(&"interact_button"):
		(button as TouchActionButton).label = "PEGAR" if item != null else "USAR"
		(button as TouchActionButton).queue_redraw()


# --- Abrir e fechar -----------------------------------------------------------

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("inventory_toggle"):
		if is_open:
			close()
		elif player != null and not player.is_dead():
			open()


func open() -> void:
	if is_open:
		return
	is_open = true
	_panel.visible = true
	if player != null:
		player.input_enabled = false
	_touch_visibility.clear()
	for layer_node in get_tree().get_nodes_in_group(&"touch_controls"):
		_touch_visibility[layer_node] = layer_node.get(&"visible")
		layer_node.set(&"visible", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_panel.visible = false
	if player != null:
		player.input_enabled = true
	for layer_node in _touch_visibility:
		if is_instance_valid(layer_node):
			layer_node.set(&"visible", _touch_visibility[layer_node])
	_touch_visibility.clear()
	if not GameInput.uses_touch_controls() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh()
