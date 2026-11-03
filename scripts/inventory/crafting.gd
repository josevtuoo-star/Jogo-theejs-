class_name Crafting
extends RefCounted
## Receitas da bancada (grade 2 × 2 da mochila).
##
## Cada casa da grade recebe UMA unidade de um item; a receita vale quando o
## conjunto de itens da grade é exatamente o pedido (a posição não importa,
## então ninguém precisa decorar formatos). Cada combinação é única.
## Também dá para fabricar direto pela lista de receitas (um toque), que tira
## os ingredientes da mochila.

## result: [quantidade, {ingrediente: unidades}]
const RECIPES := {
	"tabua": [4, {"madeira": 1}],
	"graveto": [4, {"tabua": 2}],
	"tocha": [2, {"graveto": 1, "carvao": 1}],
	"faca_pedra": [1, {"pedra": 1, "graveto": 1}],
	"machado_pedra": [1, {"pedra": 2, "graveto": 1}],
	"picareta_pedra": [1, {"pedra": 2, "graveto": 2}],
	"lanca": [1, {"graveto": 3, "pedra": 1}],
	"taco": [1, {"tabua": 2, "ferro": 1}],
	"facao": [1, {"ferro": 2, "tabua": 1}],
	"machado": [1, {"ferro": 2, "graveto": 1}],
	"picareta": [1, {"ferro": 2, "graveto": 2}],
	"pe_de_cabra": [1, {"ferro": 3, "carvao": 1}],
	"capacete": [1, {"ferro": 3}],
	"colete": [1, {"ferro": 4}],
	"joelheiras": [1, {"ferro": 1, "tabua": 1}],
	"botas_reforcadas": [1, {"ferro": 2, "carvao": 1}],
}


## Receita que a grade forma (ids das unidades em cada casa; "" = vazia) ou "".
static func match_grid(cells: Array) -> String:
	var counts := {}
	for id in cells:
		if String(id) != "":
			counts[String(id)] = int(counts.get(String(id), 0)) + 1
	if counts.is_empty():
		return ""
	for result: String in RECIPES:
		var needed: Dictionary = RECIPES[result][1]
		if needed.size() != counts.size():
			continue
		var same := true
		for id: String in needed:
			if int(counts.get(id, 0)) != int(needed[id]):
				same = false
				break
		if same:
			return result
	return ""


static func result_count(result: String) -> int:
	return RECIPES[result][0] if RECIPES.has(result) else 0


static func ingredients(result: String) -> Dictionary:
	return RECIPES[result][1] if RECIPES.has(result) else {}


## A mochila tem os ingredientes?
static func can_craft(inventory: Inventory, result: String) -> bool:
	var needed := ingredients(result)
	if needed.is_empty():
		return false
	for id: String in needed:
		if inventory.count(StringName(id)) < int(needed[id]):
			return false
	return true


## Fabrica pela lista: tira os ingredientes da mochila e guarda o resultado.
## Se o resultado não couber, devolve os ingredientes. Retorna se fabricou.
static func craft_from_inventory(inventory: Inventory, result: String) -> bool:
	if not can_craft(inventory, result):
		return false
	var item := ItemData.find(StringName(result))
	if item == null:
		return false
	var needed := ingredients(result)
	for id: String in needed:
		inventory.remove_item(StringName(id), int(needed[id]))
	if not inventory.add(item, result_count(result)):
		for id: String in needed:
			inventory.add(ItemData.find(StringName(id)), int(needed[id]))
		return false
	inventory.crafted.emit(item, result_count(result))
	return true
