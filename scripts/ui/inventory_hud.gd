class_name InventoryHud
extends CanvasLayer
## Interface da mochila (no estilo das grades de jogos de sobrevivência):
##
## - barra rápida (9 casas) embaixo, com ícone, quantidade e durabilidade; a
##   casa na mão fica destacada. No toque, as casas são botões do roteador
##   multitoque (HotbarTouchSlot) exatamente sobre estes desenhos;
## - cartão do item em foco sob a mira e o botão USAR vira PEGAR;
## - avisos de coleta, fabricação e quebra;
## - painel MOCHILA (I / Tab / botão MOCHILA):
##   * à esquerda, as casas de armadura (cabeça, tronco, pernas, pés) e o
##     retrato 3D do sobrevivente com o que está vestido;
##   * a BANCADA 2 × 2 com a seta e o resultado;
##   * a mochila (3 × 9) e, embaixo, a barra rápida (9);
##   * à direita, o item escolhido (nome, para que serve, durabilidade e
##     ações) e as RECEITAS, que fabricam com um toque.
##   Toque num item e depois em outra casa para mover/trocar/juntar; numa
##   casa da bancada vai uma unidade por toque; tocar no resultado fabrica.
##   Com o painel aberto o jogador para e os controles de toque somem.

const BOTTOM_MARGIN := 14.0
const CELL := 64.0
const PITCH := 68.0

@export var player: PlayerController
@export var inventory: Inventory
@export var interaction: InteractionComponent

var is_open: bool = false
## Visibilidade de cada camada de toque antes de abrir (restaurada ao fechar).
var _touch_visibility: Dictionary = {}

var _hotbar: Control
var _hud_slots: Array[InventorySlotView] = []
var _toasts: VBoxContainer
var _card: HBoxContainer
var _card_icon: TextureRect
var _card_label: Label
var _panel: Control
var _views: Dictionary = {} # índice da casa -> InventorySlotView do painel
var _result: InventorySlotView
var _held: int = -1
var _info_icon: TextureRect
var _info_name: Label
var _info_text: Label
var _info_bar: ProgressBar
var _info_buttons: HBoxContainer
var _recipes: VBoxContainer
var _preview: CharacterPreview


func _ready() -> void:
	layer = 6
	_build()
	if inventory != null:
		inventory.changed.connect(_refresh)
		inventory.item_added.connect(_on_item_added)
		inventory.crafted.connect(func(item: ItemData, amount: int) -> void:
			_toast(item, "Fabricou %s%s" % [item.display_name, " ×%d" % amount if amount > 1 else ""]))
		inventory.message.connect(func(text: String) -> void: _toast(null, text))
	if interaction != null:
		interaction.focus_changed.connect(_on_focus_changed)
	_refresh()


## Passo e tamanho das casas da barra rápida para a largura da tela (a barra
## cabe entre o direcional e os botões de ação).
static func slot_metrics(screen: Vector2) -> Vector2:
	var pitch := clampf((screen.x - 2.0 * maxf(330.0, screen.x * 0.26)) / Inventory.HOTBAR, 50.0, 70.0)
	return Vector2(pitch, pitch - 6.0)


## Centro de uma casa da barra rápida na tela (os botões de toque usam o mesmo).
static func slot_center(index: int, screen: Vector2) -> Vector2:
	var metrics := slot_metrics(screen)
	var x := screen.x * 0.5 + (index - (Inventory.HOTBAR - 1) * 0.5) * metrics.x
	return Vector2(x, screen.y - BOTTOM_MARGIN - metrics.y * 0.5)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_hotbar = Control.new()
	_hotbar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hotbar)
	for i in Inventory.HOTBAR:
		var slot := InventorySlotView.new(i, inventory, CELL)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not GameInput.uses_touch_controls():
			var key := _label(str(i + 1), 11)
			key.position = Vector2(4.0, 1.0)
			key.modulate = Color(1, 1, 1, 0.7)
			slot.add_child(key)
		_hotbar.add_child(slot)
		_hud_slots.append(slot)
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
	var metrics := slot_metrics(screen)
	for i in _hud_slots.size():
		var slot := _hud_slots[i]
		slot.scale = Vector2.ONE * (metrics.y / CELL)
		slot.position = slot_center(i, screen) - Vector2.ONE * metrics.y * 0.5


# --- Painel --------------------------------------------------------------------

func _build_panel(root: Control) -> void:
	_panel = ColorRect.new()
	(_panel as ColorRect).color = Color(0.0, 0.0, 0.0, 0.6)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	root.add_child(_panel)
	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	var size := Vector2(1184.0, 654.0)
	frame.position = -size * 0.5
	frame.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.135, 0.125, 0.97)
	style.border_color = Color(0.36, 0.37, 0.33)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(18)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 12
	frame.add_theme_stylebox_override("panel", style)
	_panel.add_child(frame)
	var content := Control.new()
	content.custom_minimum_size = size - Vector2(36.0, 36.0)
	frame.add_child(content)

	# Armadura, retrato e bancada.
	_place(content, _label("MOCHILA", 22), Vector2(0.0, 0.0))
	for k in Inventory.ARMOR_SLOTS.size():
		var view := _slot(Inventory.ARMOR_START + k, content, Vector2(0.0, 44.0 + k * PITCH))
		view.hint = (Inventory.ARMOR_NAMES[k] as String).to_upper()
	_preview = CharacterPreview.new()
	_preview.inventory = inventory
	_preview.position = Vector2(76.0, 40.0)
	_preview.size = Vector2(212.0, 276.0)
	var preview_back := Panel.new()
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(0.05, 0.055, 0.05, 0.9)
	preview_style.set_border_width_all(2)
	preview_style.border_color = Color(0.0, 0.0, 0.0, 0.7)
	preview_back.add_theme_stylebox_override("panel", preview_style)
	preview_back.position = _preview.position
	preview_back.size = _preview.size
	content.add_child(preview_back)
	content.add_child(_preview)
	_place(content, _label("BANCADA", 16), Vector2(312.0, 44.0))
	for k in Inventory.CRAFT_CELLS:
		_slot(Inventory.CRAFT_START + k, content, Vector2(312.0 + (k % 2) * PITCH, 74.0 + (k / 2) * PITCH))
	var arrow := _label("➜", 34)
	_place(content, arrow, Vector2(456.0, 112.0))
	_result = InventorySlotView.new(-1, inventory, CELL)
	_result.position = Vector2(500.0, 108.0)
	_result.pressed.connect(func() -> void:
		inventory.craft_make()
		_refresh())
	content.add_child(_result)
	var tip := _label("Toque num item e depois numa casa da bancada (uma unidade por toque). Toque no resultado para fabricar.", 13)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.modulate = Color(1, 1, 1, 0.7)
	tip.custom_minimum_size = Vector2(300.0, 0.0)
	tip.size = Vector2(300.0, 80.0)
	_place(content, tip, Vector2(312.0, 222.0))

	# Mochila (3 × 9) e barra rápida.
	var top := 332.0
	for r in 3:
		for c in Inventory.HOTBAR:
			_slot(Inventory.HOTBAR + r * Inventory.HOTBAR + c, content, Vector2(c * PITCH, top + r * PITCH))
	for c in Inventory.HOTBAR:
		_slot(c, content, Vector2(c * PITCH, top + 3 * PITCH + 12.0))

	# Item escolhido, ações e receitas.
	var right := 640.0
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_END
	header.add_theme_constant_override("separation", 8)
	header.add_child(_button("ORGANIZAR", func() -> void:
		inventory.sort()
		_held = -1
		_refresh()))
	header.add_child(_button("FECHAR", close))
	header.position = Vector2(right, 0.0)
	header.size = Vector2(508.0, 46.0)
	content.add_child(header)
	_info_icon = TextureRect.new()
	_info_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_info_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_info_icon.position = Vector2(right, 60.0)
	_info_icon.size = Vector2(76.0, 76.0)
	content.add_child(_info_icon)
	_info_name = _label("", 20)
	_place(content, _info_name, Vector2(right + 88.0, 58.0))
	_info_text = _label("", 14)
	_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_text.size = Vector2(420.0, 60.0)
	_info_text.custom_minimum_size = Vector2(420.0, 0.0)
	_place(content, _info_text, Vector2(right + 88.0, 88.0))
	_info_bar = ProgressBar.new()
	_info_bar.position = Vector2(right + 88.0, 146.0)
	_info_bar.size = Vector2(240.0, 14.0)
	_info_bar.show_percentage = false
	content.add_child(_info_bar)
	_info_buttons = HBoxContainer.new()
	_info_buttons.add_theme_constant_override("separation", 8)
	_info_buttons.position = Vector2(right, 176.0)
	_info_buttons.size = Vector2(508.0, 48.0)
	content.add_child(_info_buttons)
	_place(content, _label("RECEITAS", 16), Vector2(right, 238.0))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(right, 266.0)
	scroll.size = Vector2(508.0, 352.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_recipes = VBoxContainer.new()
	_recipes.custom_minimum_size = Vector2(492.0, 0.0)
	_recipes.add_theme_constant_override("separation", 4)
	scroll.add_child(_recipes)


func _slot(index: int, parent: Control, at: Vector2) -> InventorySlotView:
	var view := InventorySlotView.new(index, inventory, CELL)
	view.position = at
	view.pressed.connect(_on_slot_pressed.bind(index))
	parent.add_child(view)
	_views[index] = view
	return view


func _place(parent: Control, node: Control, at: Vector2) -> void:
	node.position = at
	parent.add_child(node)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(110.0, 46.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(action)
	return button


func _icon(item: ItemData, side: float = 44.0) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = item.get_icon() if item != null else null
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# --- Toques no painel ----------------------------------------------------------

## Toque numa casa: escolhe o item; com um item escolhido, move para a casa
## tocada (troca, junta pilhas, veste armadura, põe uma unidade na bancada).
func _on_slot_pressed(index: int) -> void:
	if _held < 0:
		if inventory.tool_at(index).is_empty():
			return
		if index >= Inventory.CRAFT_START:
			# Da bancada volta direto para a mochila.
			inventory.quick_move(index)
		else:
			_held = index
	elif _held == index:
		_held = -1
	else:
		var source := _held
		var moved := inventory.move(source, index)
		if moved and index >= Inventory.CRAFT_START and not inventory.tool_at(source).is_empty():
			_held = source # continua escolhido: mais um toque, mais uma unidade
		elif not moved and not inventory.tool_at(index).is_empty():
			_held = index
		else:
			_held = -1
	_refresh()


func _held_actions(index: int) -> void:
	for child in _info_buttons.get_children():
		child.free()
	if index < 0:
		return
	var entry := inventory.tool_at(index)
	if entry.is_empty():
		return
	var item: ItemData = entry["item"]
	if index < Inventory.HOTBAR and item.is_tool():
		if inventory.selected == index:
			_info_buttons.add_child(_button("GUARDAR", func() -> void: inventory.unequip()))
		else:
			_info_buttons.add_child(_button("NA MÃO", func() -> void: inventory.equip(index)))
	if index >= Inventory.ARMOR_START and index < Inventory.CRAFT_START:
		_info_buttons.add_child(_button("TIRAR", func() -> void:
			if inventory.quick_move(index):
				_held = -1))
	elif item.is_armor():
		_info_buttons.add_child(_button("VESTIR", func() -> void:
			if inventory.move(index, Inventory.ARMOR_START + Inventory.ARMOR_SLOTS.find(item.armor_slot)):
				_held = -1))
	elif index >= Inventory.HOTBAR:
		_info_buttons.add_child(_button("PARA A BARRA", func() -> void:
			if inventory.quick_move(index):
				_held = -1))
	else:
		_info_buttons.add_child(_button("GUARDAR NA MOCHILA", func() -> void:
			if inventory.quick_move(index):
				_held = -1))
	if int(entry["count"]) > 1:
		_info_buttons.add_child(_button("SOLTAR 1", func() -> void: inventory.drop_slot(index, 1)))
	_info_buttons.add_child(_button("SOLTAR", func() -> void:
		_held = -1
		inventory.drop_slot(index)))


# --- Atualização ---------------------------------------------------------------

func _refresh() -> void:
	for i in _hud_slots.size():
		_hud_slots[i].highlight = 2 if inventory != null and inventory.selected == i else 0
		_hud_slots[i].refresh()
	if inventory == null:
		return
	get_tree().call_group(&"drop_weapon_button", &"set_visible", inventory.selected >= 0)
	if not is_open:
		return
	if _held >= 0 and inventory.tool_at(_held).is_empty():
		_held = -1
	for index: int in _views:
		var view: InventorySlotView = _views[index]
		view.highlight = 1 if index == _held else (2 if index == inventory.selected else 0)
		view.refresh()
	var result := inventory.craft_result()
	_result.preview_item = ItemData.find(StringName(result)) if result != "" else null
	_result.preview_count = Crafting.result_count(result) if result != "" else 0
	_result.disabled = result == ""
	_result.refresh()
	_refresh_info()
	_refresh_recipes()


func _refresh_info() -> void:
	var entry := inventory.tool_at(_held) if _held >= 0 else {}
	var item: ItemData = entry.get("item")
	_info_icon.texture = item.get_icon() if item != null else null
	_info_name.text = item.display_name if item != null else "Nenhum item escolhido"
	_info_text.text = item.description if item != null else "Toque num item para ver para que serve e o que fazer com ele."
	_info_bar.visible = item != null and item.has_durability()
	if _info_bar.visible:
		_info_bar.value = inventory.durability_fraction(_held) * 100.0
	_held_actions(_held)


func _refresh_recipes() -> void:
	for child in _recipes.get_children():
		child.free()
	var ready: Array[String] = []
	var missing: Array[String] = []
	for result: String in Crafting.RECIPES:
		(ready if Crafting.can_craft(inventory, result) else missing).append(result)
	for result in ready + missing:
		var item := ItemData.find(StringName(result))
		if item == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var possible := Crafting.can_craft(inventory, result)
		row.modulate = Color(1, 1, 1, 1.0 if possible else 0.5)
		row.add_child(_icon(item, 40.0))
		var amount := Crafting.result_count(result)
		var name := _label("%s%s" % [item.display_name, " ×%d" % amount if amount > 1 else ""], 15)
		name.custom_minimum_size = Vector2(150.0, 0.0)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var needed := Crafting.ingredients(result)
		for id: String in needed:
			row.add_child(_icon(ItemData.find(StringName(id)), 30.0))
			var have := inventory.count(StringName(id))
			var count := _label("%d/%d" % [mini(have, int(needed[id])), int(needed[id])], 13)
			count.add_theme_color_override("font_color", Color(0.75, 0.95, 0.6) if have >= int(needed[id]) else Color(1.0, 0.55, 0.45))
			row.add_child(count)
		var make := _button("FABRICAR", func() -> void:
			Crafting.craft_from_inventory(inventory, result)
			_refresh())
		make.custom_minimum_size = Vector2(104.0, 42.0)
		make.disabled = not possible
		row.add_child(make)
		_recipes.add_child(row)


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
	_hotbar.visible = false
	_toasts.visible = false
	_held = -1
	if player != null:
		player.input_enabled = false
	_touch_visibility.clear()
	for layer_node in get_tree().get_nodes_in_group(&"touch_controls"):
		_touch_visibility[layer_node] = layer_node.get(&"visible")
		layer_node.set(&"visible", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_preview.apply_look(GameSession.look)
	_refresh()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_held = -1
	inventory.craft_clear()
	_panel.visible = false
	_hotbar.visible = true
	_toasts.visible = true
	if player != null:
		player.input_enabled = true
	for layer_node in _touch_visibility:
		if is_instance_valid(layer_node):
			layer_node.set(&"visible", _touch_visibility[layer_node])
	_touch_visibility.clear()
	if not GameInput.uses_touch_controls() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh()
