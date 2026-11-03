class_name ItemData
extends Resource
## Um tipo de item: ferramenta (vai para a barra rápida, tem durabilidade e
## uma arma associada) ou recurso (empilha na mochila, ex.: madeira, pedra).

enum Kind { TOOL, RESOURCE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.RESOURCE
@export var icon: Texture2D
## Malha do item solto no chão (ferramentas usam a malha da arma).
@export var world_mesh: Mesh
@export_range(0.01, 50.0, 0.01) var mass: float = 1.0
## Ferramenta: dados de combate e golpes.
@export var weapon: WeaponData
## Ferramenta: golpes úteis até quebrar.
@export_range(1.0, 1000.0, 1.0) var max_durability: float = 100.0
## Material do som quando o item cai ("madeira", "metal", "pedra"…).
@export var impact_material: StringName = &"generico"


static func find(item_id: StringName) -> ItemData:
	var path := "res://resources/items/%s.tres" % item_id
	return load(path) if ResourceLoader.exists(path) else null


## Ícone do item: o definido no recurso ou o desenhado pela ferramenta
## (resources/icons/<id>.png).
func get_icon() -> Texture2D:
	if icon != null:
		return icon
	var path := "res://resources/icons/%s.png" % id
	return load(path) if ResourceLoader.exists(path) else null


func is_tool() -> bool:
	return kind == Kind.TOOL
