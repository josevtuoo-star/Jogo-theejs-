class_name ItemData
extends Resource
## Um tipo de item da mochila:
## - ferramenta (machado, picareta, faca, lança, tocha…): ocupa uma casa
##   sozinha, tem durabilidade e uma arma associada (golpes e alcance);
## - recurso (madeira, tábua, graveto, pedra, carvão, ferro): empilha;
## - armadura (capacete, colete, joelheiras, botas): vai nas casas do corpo,
##   reduz o dano recebido e se gasta ao absorver golpes.

enum Kind { TOOL, RESOURCE, ARMOR }

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.RESOURCE
@export var icon: Texture2D
## Malha do item solto no chão (ferramentas usam a malha da arma).
@export var world_mesh: Mesh
@export_range(0.01, 50.0, 0.01) var mass: float = 1.0
## Ferramenta: dados de combate e golpes.
@export var weapon: WeaponData
## Ferramenta e armadura: usos até quebrar.
@export_range(1.0, 1000.0, 1.0) var max_durability: float = 100.0
## Material do som quando o item cai ("madeira", "metal", "pedra"…).
@export var impact_material: StringName = &"generico"
## Quantos cabem numa casa (ferramentas e armaduras: 1).
@export_range(1, 999, 1) var stack_size: int = 64
## Ferramenta: para que serve ("machado", "picareta", "arma", "tocha").
@export var tool_type: StringName = &"arma"
## Ferramenta: nível (1 = pedra, 2 = metal). Minério de ferro pede nível 2.
@export_range(0, 3, 1) var tier: int = 0
## Ferramenta de trabalho: rendimento por golpe (1 = machado de bombeiro).
@export_range(0.0, 2.0, 0.01) var work_power: float = 0.0
## Armadura: casa do corpo ("cabeca", "tronco", "pernas", "pes") e fração
## do dano que absorve.
@export var armor_slot: StringName = &""
@export_range(0.0, 0.9, 0.01) var armor_value: float = 0.0
## Tocha: luz na mão (energia da OmniLight; 0 = sem luz).
@export_range(0.0, 10.0, 0.1) var light_energy: float = 0.0
## Texto curto na mochila (para que serve).
@export_multiline var description: String = ""


static var _cache: Dictionary = {}


static func find(item_id: StringName) -> ItemData:
	if _cache.has(item_id):
		return _cache[item_id]
	var path := "res://resources/items/%s.tres" % item_id
	var item: ItemData = load(path) if ResourceLoader.exists(path) else null
	_cache[item_id] = item
	return item


## Ícone do item: o definido no recurso ou o desenhado pela ferramenta
## (resources/icons/<id>.png).
func get_icon() -> Texture2D:
	if icon != null:
		return icon
	var path := "res://resources/icons/%s.png" % id
	return load(path) if ResourceLoader.exists(path) else null


func is_tool() -> bool:
	return kind == Kind.TOOL


func is_armor() -> bool:
	return kind == Kind.ARMOR


## Tem durabilidade (ferramenta ou armadura): não empilha.
func has_durability() -> bool:
	return kind != Kind.RESOURCE
