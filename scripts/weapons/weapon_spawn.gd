class_name WeaponSpawn
extends Marker3D
## Ponto onde uma arma aparece no mundo ao carregar (mapa feito à mão ou
## pedaço do mundo procedural). Vira um corpo físico de verdade (WeaponPickup)
## e o marcador some.

@export var weapon: WeaponData


func _ready() -> void:
	if weapon == null:
		queue_free()
		return
	_spawn.call_deferred()


func _spawn() -> void:
	var parent := get_parent()
	var where := global_transform
	queue_free()
	WeaponPickup.spawn(weapon, where, parent)
