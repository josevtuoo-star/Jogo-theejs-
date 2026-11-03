class_name Inventory
extends Node
## Mochila do sobrevivente, em casas (como num jogo de sobrevivência em grade):
##
## - 0–8: barra rápida (a casa selecionada é a que está na mão);
## - 9–35: mochila (27 casas);
## - 36–39: armadura no corpo (cabeça, tronco, pernas, pés);
## - 40–43: bancada 2 × 2 (cada casa guarda uma unidade).
##
## Cada casa guarda {"item": ItemData, "count": int, "durability": float} ou
## {} (vazia). Recursos empilham até ItemData.stack_size; ferramentas e
## armaduras ocupam uma casa cada uma, com a própria durabilidade.
## Tudo o que sai do chão entra aqui (PEGAR); soltar devolve ao mundo como
## corpo físico de verdade, com a durabilidade que tinha.
##
## Controles: 1–9 escolhem a casa da barra (de novo = guardar), setas do
## controle trocam, G / SOLTAR solta a da mão, I / Tab / MOCHILA abre a mochila.

signal changed
signal item_added(item: ItemData, amount: int)
signal tool_broken(item: ItemData)
signal message(text: String)
signal crafted(item: ItemData, amount: int)

const HOTBAR := 9
const BACKPACK := 27
## Casas que guardam itens soltos (barra + mochila).
const STORAGE := HOTBAR + BACKPACK
const ARMOR_START := STORAGE
const ARMOR_SLOTS: Array[StringName] = [&"cabeca", &"tronco", &"pernas", &"pes"]
const ARMOR_NAMES := ["Cabeça", "Tronco", "Pernas", "Pés"]
const CRAFT_START := ARMOR_START + 4
const CRAFT_CELLS := 4
const TOTAL := CRAFT_START + CRAFT_CELLS
## Compatibilidade: casas da barra rápida.
const TOOL_SLOTS := HOTBAR
## A tocha na mão gasta 1 de durabilidade por segundo.
const TORCH_BURN_PER_SECOND := 1.0

@export var player: PlayerController
@export var equipment: PlayerEquipment

var slots: Array[Dictionary] = []
## Casa da barra na mão (-1 = mãos livres).
var selected: int = -1
var _burn: float = 0.0


func _ready() -> void:
	slots.resize(TOTAL)
	for i in TOTAL:
		slots[i] = {}
	if player != null and player.health != null:
		player.health.armor_absorbed.connect(func(_amount: float) -> void: wear_armor(1.0))


# --- Consultas -----------------------------------------------------------------

func tool_at(index: int) -> Dictionary:
	return slots[index] if index >= 0 and index < TOTAL else {}


func item_at(index: int) -> ItemData:
	return tool_at(index).get("item")


func equipped() -> Dictionary:
	return tool_at(selected) if selected >= 0 and selected < HOTBAR else {}


func equipped_item() -> ItemData:
	return equipped().get("item")


## Unidades de um item na barra e na mochila.
func count(item_id: StringName) -> int:
	var total := 0
	for i in STORAGE:
		var entry := slots[i]
		if not entry.is_empty() and (entry["item"] as ItemData).id == item_id:
			total += int(entry["count"])
	return total


## Ferramentas guardadas (barra + mochila).
func tool_count() -> int:
	var n := 0
	for i in STORAGE:
		if not slots[i].is_empty() and (slots[i]["item"] as ItemData).is_tool():
			n += 1
	return n


func has_tool(item_id: StringName) -> bool:
	return find_item(item_id) >= 0


## Primeira casa (barra + mochila) com o item, ou -1.
func find_item(item_id: StringName) -> int:
	for i in STORAGE:
		if not slots[i].is_empty() and (slots[i]["item"] as ItemData).id == item_id:
			return i
	return -1


func armor_item(body_slot: StringName) -> ItemData:
	return item_at(ARMOR_START + ARMOR_SLOTS.find(body_slot))


## Fração do dano absorvida pela armadura vestida.
func armor_value() -> float:
	var total := 0.0
	for k in ARMOR_SLOTS.size():
		var item := item_at(ARMOR_START + k)
		if item != null:
			total += item.armor_value
	return minf(total, 0.8)


func durability_fraction(index: int) -> float:
	var entry := tool_at(index)
	if entry.is_empty() or not (entry["item"] as ItemData).has_durability():
		return 0.0
	return float(entry["durability"]) / (entry["item"] as ItemData).max_durability


# --- Guardar -------------------------------------------------------------------

## Cabe `amount` deste item?
func can_add(item: ItemData, amount: int = 1) -> bool:
	if item == null or amount <= 0:
		return false
	if item.has_durability():
		if item.is_armor() and slots[ARMOR_START + ARMOR_SLOTS.find(item.armor_slot)].is_empty():
			amount -= 1
		var free := 0
		for i in STORAGE:
			if slots[i].is_empty():
				free += 1
		return free >= amount
	var room := 0
	for i in STORAGE:
		var entry := slots[i]
		if entry.is_empty():
			room += item.stack_size
		elif (entry["item"] as ItemData).id == item.id:
			room += item.stack_size - int(entry["count"])
	return room >= amount


## Põe um item na mochila. `durability` < 0 = novo. Retorna falso (e avisa)
## se não couber: nada entra pela metade.
func add(item: ItemData, amount: int = 1, durability: float = -1.0) -> bool:
	if item == null or amount <= 0:
		return false
	if not can_add(item, amount):
		message.emit("Mochila cheia")
		return false
	if item.has_durability():
		for n in amount:
			var entry := {"item": item, "count": 1,
					"durability": item.max_durability if durability < 0.0 else durability}
			# Armadura: veste se a casa do corpo estiver livre.
			if item.is_armor():
				var body := ARMOR_START + ARMOR_SLOTS.find(item.armor_slot)
				if slots[body].is_empty():
					slots[body] = entry
					_armor_changed()
					continue
			# Ferramenta: barra rápida primeiro (e na mão, se estiver livre).
			var index := _first_empty(true)
			slots[index] = entry
			if item.is_tool() and selected < 0 and index < HOTBAR:
				equip(index)
	else:
		var left := amount
		# Completa pilhas existentes, depois casas vazias (mochila primeiro: a
		# barra fica para as ferramentas).
		for i in STORAGE:
			var entry := slots[i]
			if left > 0 and not entry.is_empty() and (entry["item"] as ItemData).id == item.id:
				var put := mini(item.stack_size - int(entry["count"]), left)
				entry["count"] = int(entry["count"]) + put
				left -= put
		while left > 0:
			var index := _first_empty(false)
			var put := mini(item.stack_size, left)
			slots[index] = {"item": item, "count": put, "durability": 0.0}
			left -= put
	item_added.emit(item, amount)
	changed.emit()
	return true


func _first_empty(hotbar_first: bool) -> int:
	var order: Array = range(STORAGE) if hotbar_first else range(HOTBAR, STORAGE) + range(HOTBAR)
	for i: int in order:
		if slots[i].is_empty():
			return i
	return -1


## Tira unidades de um item (para fabricar/gastar). Retorna quantas saíram.
## Pilhas da mochila saem antes das da barra.
func remove_item(item_id: StringName, amount: int) -> int:
	var taken := 0
	var order: Array = range(STORAGE - 1, -1, -1)
	for i: int in order:
		if taken >= amount:
			break
		var entry := slots[i]
		if entry.is_empty() or (entry["item"] as ItemData).id != item_id:
			continue
		var put := mini(int(entry["count"]), amount - taken)
		entry["count"] = int(entry["count"]) - put
		taken += put
		if int(entry["count"]) <= 0:
			_clear(i)
	if taken > 0:
		changed.emit()
	return taken


## Compatibilidade com a mochila antiga.
func remove_resource(item_id: StringName, amount: int) -> int:
	return remove_item(item_id, amount)


func _clear(index: int) -> void:
	slots[index] = {}
	if index == selected:
		selected = -1
		_show()
	elif index >= ARMOR_START and index < CRAFT_START:
		_armor_changed()


# --- Mão -----------------------------------------------------------------------

func equip(index: int) -> void:
	if index < 0 or index >= HOTBAR or slots[index].is_empty():
		return
	selected = index
	_show()


## Guarda a ferramenta da mão (mãos livres).
func unequip() -> void:
	selected = -1
	_show()


## Tocar na casa da mão a guarda; em outra, troca.
func toggle(index: int) -> void:
	if index == selected:
		unequip()
	else:
		equip(index)


func cycle(step: int) -> void:
	for i in range(1, HOTBAR + 1):
		var index := posmod(maxi(selected, 0) + step * i, HOTBAR)
		if not slots[index].is_empty():
			equip(index)
			return


func _show() -> void:
	var item := equipped_item()
	if equipment != null:
		equipment.show_weapon(item.weapon if item != null and item.is_tool() else null, item)
	changed.emit()


# --- Desgaste ------------------------------------------------------------------

## Gasta a ferramenta da mão (um golpe útil). Quebra ao chegar a zero.
func wear_equipped(amount: float = 1.0) -> void:
	var entry := equipped()
	if entry.is_empty() or not (entry["item"] as ItemData).has_durability():
		return
	entry["durability"] = maxf(float(entry["durability"]) - amount, 0.0)
	if entry["durability"] <= 0.0:
		var item: ItemData = entry["item"]
		slots[selected] = {}
		selected = -1
		_show()
		message.emit(("%s apagou" if item.tool_type == &"tocha" else "%s quebrou") % item.display_name)
		tool_broken.emit(item)
	changed.emit()


## A armadura absorveu um golpe: cada peça vestida se gasta.
func wear_armor(amount: float = 1.0) -> void:
	for k in ARMOR_SLOTS.size():
		var index := ARMOR_START + k
		var entry := slots[index]
		if entry.is_empty():
			continue
		entry["durability"] = maxf(float(entry["durability"]) - amount, 0.0)
		if entry["durability"] <= 0.0:
			var item: ItemData = entry["item"]
			slots[index] = {}
			message.emit("%s quebrou" % item.display_name)
			tool_broken.emit(item)
			_armor_changed()
	changed.emit()


func _armor_changed() -> void:
	if player != null and player.health != null:
		player.health.armor = armor_value()
	var visuals := get_parent().get_node_or_null("ArmorVisuals") if get_parent() != null else null
	if visuals != null:
		visuals.call(&"refresh")


# --- Mover (interface da mochila) -----------------------------------------------

## A casa aceita o item? (armadura só na sua casa do corpo; bancada só uma unidade)
func accepts(index: int, item: ItemData) -> bool:
	if item == null:
		return true
	if index >= ARMOR_START and index < CRAFT_START:
		return item.is_armor() and ARMOR_SLOTS[index - ARMOR_START] == item.armor_slot
	return index >= 0 and index < TOTAL


## Move o conteúdo de uma casa para outra: junta pilhas iguais, troca as
## diferentes. Para a bancada vai só uma unidade.
func move(from: int, to: int) -> bool:
	if from == to or from < 0 or to < 0 or from >= TOTAL or to >= TOTAL or slots[from].is_empty():
		return false
	var source := slots[from]
	var target := slots[to]
	var item: ItemData = source["item"]
	if not accepts(to, item):
		return false
	if to >= CRAFT_START:
		if not target.is_empty():
			return false
		slots[to] = {"item": item, "count": 1, "durability": source["durability"]}
		source["count"] = int(source["count"]) - 1
		if int(source["count"]) <= 0:
			_clear(from)
	elif not target.is_empty() and (target["item"] as ItemData).id == item.id and not item.has_durability():
		var put := mini(item.stack_size - int(target["count"]), int(source["count"]))
		if put <= 0:
			return false
		target["count"] = int(target["count"]) + put
		source["count"] = int(source["count"]) - put
		if int(source["count"]) <= 0:
			_clear(from)
	else:
		if not target.is_empty() and not accepts(from, target["item"]):
			return false
		slots[to] = source
		slots[from] = target
	if from == selected or to == selected:
		if slots[selected].is_empty():
			selected = -1
		_show()
	if _is_armor_index(from) or _is_armor_index(to):
		_armor_changed()
	changed.emit()
	return true


## Move uma casa para o primeiro lugar livre do outro lado (barra ↔ mochila;
## bancada e armadura voltam para a mochila).
func quick_move(index: int) -> bool:
	var entry := tool_at(index)
	if entry.is_empty():
		return false
	var item: ItemData = entry["item"]
	if index >= HOTBAR and index < STORAGE and item.is_armor():
		var body := ARMOR_START + ARMOR_SLOTS.find(item.armor_slot)
		if slots[body].is_empty():
			return move(index, body)
	var range_to: Array = range(HOTBAR) if index >= HOTBAR and index < STORAGE else range(HOTBAR, STORAGE) + range(HOTBAR)
	for i: int in range_to:
		if i == index:
			continue
		var target := slots[i]
		if not target.is_empty() and (target["item"] as ItemData).id == item.id and not item.has_durability() \
				and int(target["count"]) < item.stack_size:
			return move(index, i)
	for i: int in range_to:
		if i != index and slots[i].is_empty():
			return move(index, i)
	message.emit("Sem espaço")
	return false


func _is_armor_index(index: int) -> bool:
	return index >= ARMOR_START and index < CRAFT_START


# --- Bancada ---------------------------------------------------------------------

func craft_cells() -> Array:
	var ids := []
	for k in CRAFT_CELLS:
		var item := item_at(CRAFT_START + k)
		ids.append(String(item.id) if item != null else "")
	return ids


## Receita formada na bancada ("" = nenhuma).
func craft_result() -> String:
	return Crafting.match_grid(craft_cells())


## Fabrica o que a bancada forma: consome uma unidade de cada casa.
func craft_make() -> bool:
	var result := craft_result()
	if result == "":
		return false
	var item := ItemData.find(StringName(result))
	var amount := Crafting.result_count(result)
	var saved: Array[Dictionary] = []
	for k in CRAFT_CELLS:
		saved.append(slots[CRAFT_START + k])
		slots[CRAFT_START + k] = {}
	if not add(item, amount):
		for k in CRAFT_CELLS:
			slots[CRAFT_START + k] = saved[k]
		changed.emit()
		return false
	crafted.emit(item, amount)
	changed.emit()
	return true


## Devolve à mochila o que ficou na bancada (ao fechar). O que não couber cai
## no chão.
func craft_clear() -> void:
	for k in CRAFT_CELLS:
		var index := CRAFT_START + k
		var entry := slots[index]
		if entry.is_empty():
			continue
		slots[index] = {}
		var item: ItemData = entry["item"]
		if not add(item, 1, float(entry["durability"]) if item.has_durability() else -1.0):
			_spawn(item, 1, float(entry["durability"]))
	changed.emit()


# --- Soltar --------------------------------------------------------------------

## Solta a casa no chão, à frente do jogador (`amount` < 0 = a pilha toda).
func drop_slot(index: int, amount: int = -1, where: Transform3D = Transform3D.IDENTITY) -> RigidBody3D:
	var entry := tool_at(index)
	if entry.is_empty():
		return null
	var item: ItemData = entry["item"]
	var take := int(entry["count"]) if amount < 0 else mini(amount, int(entry["count"]))
	entry["count"] = int(entry["count"]) - take
	var durability := float(entry["durability"])
	if int(entry["count"]) <= 0:
		_clear(index)
	changed.emit()
	return _spawn(item, take, durability, where)


## Compatibilidade: solta a ferramenta da casa.
func drop_tool(index: int, where: Transform3D = Transform3D.IDENTITY) -> RigidBody3D:
	return drop_slot(index, -1, where)


## Solta recursos no chão (um corpo físico com a quantidade).
func drop_resource(item_id: StringName, amount: int = 1) -> RigidBody3D:
	var taken := remove_item(item_id, amount)
	if taken <= 0:
		return null
	return _spawn(ItemData.find(item_id), taken, 0.0)


func _spawn(item: ItemData, amount: int, durability: float, where: Transform3D = Transform3D.IDENTITY) -> RigidBody3D:
	var at := where if where != Transform3D.IDENTITY else _drop_transform()
	if item.is_tool() and item.weapon != null:
		return WeaponPickup.spawn(item.weapon, at, player.get_parent(), durability)
	return ItemPickup.spawn(item, at, player.get_parent(), amount, durability if item.has_durability() else -1.0)


func _drop_transform() -> Transform3D:
	var forward := -player.get_view_basis().z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var chest := player.global_position + Vector3.UP * 1.0
	var spot := chest + forward * 0.7
	# À frente bloqueada (parede, encosta): cai junto aos pés. Senão, assenta
	# sobre o chão achado por um raio (nunca nasce dentro do terreno).
	var space := player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(chest, spot, 1 | 4, [player.get_rid()])
	if not space.intersect_ray(ray).is_empty():
		spot = chest
	ray = PhysicsRayQueryParameters3D.create(spot, spot + Vector3.DOWN * 3.0, 1, [player.get_rid()])
	var ground := space.intersect_ray(ray)
	if not ground.is_empty():
		spot.y = (ground["position"] as Vector3).y + 0.35
	return Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, player.get_view_yaw()), spot)


# --- Organizar -----------------------------------------------------------------

## Junta pilhas iguais e ordena a mochila (ferramentas, armaduras e recursos
## por nome). A barra rápida fica como está.
func sort() -> void:
	var entries: Array[Dictionary] = []
	for i in range(HOTBAR, STORAGE):
		if not slots[i].is_empty():
			entries.append(slots[i])
		slots[i] = {}
	var merged: Array[Dictionary] = []
	for entry in entries:
		var item: ItemData = entry["item"]
		var joined := false
		if not item.has_durability():
			for other in merged:
				if (other["item"] as ItemData).id == item.id and int(other["count"]) < item.stack_size:
					var put := mini(item.stack_size - int(other["count"]), int(entry["count"]))
					other["count"] = int(other["count"]) + put
					entry["count"] = int(entry["count"]) - put
					joined = int(entry["count"]) <= 0
					break
		if not joined:
			merged.append(entry)
	merged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ia: ItemData = a["item"]
		var ib: ItemData = b["item"]
		if ia.kind != ib.kind:
			return ia.kind < ib.kind
		return ia.display_name < ib.display_name)
	for k in merged.size():
		slots[HOTBAR + k] = merged[k]
	changed.emit()


# --- Salvar ----------------------------------------------------------------------

func to_data() -> Dictionary:
	var list := []
	for i in TOTAL:
		var entry := slots[i]
		list.append([] if entry.is_empty() else [String((entry["item"] as ItemData).id), int(entry["count"]),
				float(entry["durability"])])
	return {"slots": list, "selected": selected}


func from_data(data: Dictionary) -> void:
	var list: Array = data.get("slots", [])
	for i in TOTAL:
		slots[i] = {}
		if i < list.size() and (list[i] as Array).size() == 3:
			var item := ItemData.find(StringName(list[i][0]))
			if item != null:
				slots[i] = {"item": item, "count": int(list[i][1]), "durability": float(list[i][2])}
	selected = int(data.get("selected", -1))
	if selected >= 0 and (selected >= HOTBAR or slots[selected].is_empty()):
		selected = -1
	_armor_changed()
	_show()


# --- Entrada -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if player == null or player.is_dead():
		return
	# Tocha acesa na mão queima com o tempo.
	var held := equipped_item()
	if held != null and held.tool_type == &"tocha":
		_burn += delta * TORCH_BURN_PER_SECOND
		if _burn >= 1.0:
			_burn -= 1.0
			wear_equipped(1.0)
	if not player.input_enabled:
		return
	for i in HOTBAR:
		if InputMap.has_action("hotbar_%d" % (i + 1)) and Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
			toggle(i)
	if Input.is_action_just_pressed("hotbar_next"):
		cycle(1)
	if Input.is_action_just_pressed("hotbar_prev"):
		cycle(-1)
	if Input.is_action_just_pressed("drop_weapon") and selected >= 0:
		drop_slot(selected)
