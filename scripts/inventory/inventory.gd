class_name Inventory
extends Node
## Mochila do sobrevivente.
##
## - Ferramentas (machado, picareta, taco) ocupam as 4 casas da barra rápida,
##   cada uma com a própria durabilidade. A casa selecionada é a que está na
##   mão (PlayerEquipment mostra o modelo e o combate usa os dados da arma).
## - Recursos (madeira, pedra, carvão, ferro) empilham por tipo.
## - Tudo o que sai do chão entra aqui (PEGAR); soltar devolve ao mundo como
##   corpo físico de verdade, com a durabilidade que tinha.
##
## Controles: 1–4 escolhem a ferramenta (de novo = guardar), setas do controle
## trocam, G / SOLTAR solta a da mão, I / Tab / MOCHILA abre a mochila.

signal changed
signal item_added(item: ItemData, amount: int)
signal tool_broken(item: ItemData)
signal message(text: String)

const TOOL_SLOTS := 4

@export var player: PlayerController
@export var equipment: PlayerEquipment

## Casas da barra rápida: {"item": ItemData, "durability": float} ou {} (vazia).
var tools: Array[Dictionary] = []
## Recursos: id -> quantidade.
var resources: Dictionary = {}
## Casa na mão (-1 = mãos livres).
var selected: int = -1


func _ready() -> void:
	tools.resize(TOOL_SLOTS)
	for i in TOOL_SLOTS:
		tools[i] = {}


# --- Consultas -----------------------------------------------------------------

func tool_at(slot: int) -> Dictionary:
	return tools[slot] if slot >= 0 and slot < TOOL_SLOTS else {}


func equipped() -> Dictionary:
	return tool_at(selected)


func equipped_item() -> ItemData:
	var entry := equipped()
	return entry.get("item")


func count(item_id: StringName) -> int:
	return resources.get(item_id, 0)


func tool_count() -> int:
	var n := 0
	for entry in tools:
		if not entry.is_empty():
			n += 1
	return n


func has_tool(item_id: StringName) -> bool:
	for entry in tools:
		if not entry.is_empty() and (entry["item"] as ItemData).id == item_id:
			return true
	return false


# --- Guardar -------------------------------------------------------------------

## Põe um item na mochila. Ferramentas: `durability` < 0 = nova. Retorna
## falso se não couber (barra de ferramentas cheia).
func add(item: ItemData, amount: int = 1, durability: float = -1.0) -> bool:
	if item == null or amount <= 0:
		return false
	if item.is_tool():
		var slot := tools.find({})
		if slot < 0:
			message.emit("Mochila cheia: solte uma ferramenta antes")
			return false
		tools[slot] = {"item": item, "durability": item.max_durability if durability < 0.0 else durability}
		# Mãos livres: já empunha o que pegou.
		if selected < 0:
			equip(slot)
	else:
		resources[item.id] = count(item.id) + amount
	item_added.emit(item, amount)
	changed.emit()
	return true


## Tira recursos (para construir/gastar). Retorna quantos saíram.
func remove_resource(item_id: StringName, amount: int) -> int:
	var taken := mini(count(item_id), amount)
	if taken <= 0:
		return 0
	resources[item_id] = count(item_id) - taken
	if resources[item_id] <= 0:
		resources.erase(item_id)
	changed.emit()
	return taken


# --- Mão -----------------------------------------------------------------------

func equip(slot: int) -> void:
	if tool_at(slot).is_empty():
		return
	selected = slot
	_show()


## Guarda a ferramenta da mão na mochila (mãos livres).
func unequip() -> void:
	selected = -1
	_show()


## Tocar na casa da ferramenta da mão a guarda; em outra, troca.
func toggle(slot: int) -> void:
	if slot == selected:
		unequip()
	else:
		equip(slot)


func cycle(step: int) -> void:
	for i in range(1, TOOL_SLOTS + 1):
		var slot := posmod(maxi(selected, 0) + step * i, TOOL_SLOTS)
		if not tool_at(slot).is_empty():
			equip(slot)
			return


func _show() -> void:
	var item := equipped_item()
	if equipment != null:
		equipment.show_weapon(item.weapon if item != null else null)
	changed.emit()


# --- Desgaste ------------------------------------------------------------------

## Gasta a ferramenta da mão (um golpe útil). Quebra ao chegar a zero.
func wear_equipped(amount: float = 1.0) -> void:
	var entry := equipped()
	if entry.is_empty():
		return
	entry["durability"] = maxf(float(entry["durability"]) - amount, 0.0)
	if entry["durability"] <= 0.0:
		var item: ItemData = entry["item"]
		tools[selected] = {}
		selected = -1
		_show()
		message.emit("%s quebrou" % item.display_name)
		tool_broken.emit(item)
	changed.emit()


func durability_fraction(slot: int) -> float:
	var entry := tool_at(slot)
	if entry.is_empty():
		return 0.0
	return float(entry["durability"]) / (entry["item"] as ItemData).max_durability


# --- Soltar --------------------------------------------------------------------

## Solta a ferramenta da casa no chão, à frente do jogador.
func drop_tool(slot: int, where: Transform3D = Transform3D.IDENTITY) -> RigidBody3D:
	var entry := tool_at(slot)
	if entry.is_empty():
		return null
	tools[slot] = {}
	if slot == selected:
		selected = -1
		_show()
	var item: ItemData = entry["item"]
	var body := WeaponPickup.spawn(item.weapon, where if where != Transform3D.IDENTITY else _drop_transform(),
			player.get_parent(), entry["durability"])
	changed.emit()
	return body


## Solta recursos no chão (um corpo físico com a quantidade).
func drop_resource(item_id: StringName, amount: int = 1) -> RigidBody3D:
	var taken := remove_resource(item_id, amount)
	if taken <= 0:
		return null
	return ItemPickup.spawn(ItemData.find(item_id), _drop_transform(), player.get_parent(), taken)


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

## Junta as ferramentas no começo da barra (por nome) mantendo a da mão.
func sort() -> void:
	var held := equipped()
	var list: Array[Dictionary] = []
	for entry in tools:
		if not entry.is_empty():
			list.append(entry)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["item"] as ItemData).display_name < (b["item"] as ItemData).display_name)
	for i in TOOL_SLOTS:
		tools[i] = list[i] if i < list.size() else {}
	selected = tools.find(held) if not held.is_empty() else -1
	_show()


# --- Entrada -------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if player == null or not player.input_enabled or player.is_dead():
		return
	for i in TOOL_SLOTS:
		if Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
			toggle(i)
	if Input.is_action_just_pressed("hotbar_next"):
		cycle(1)
	if Input.is_action_just_pressed("hotbar_prev"):
		cycle(-1)
	if Input.is_action_just_pressed("drop_weapon") and selected >= 0:
		drop_tool(selected)
