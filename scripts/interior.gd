extends Area3D
## Lugar fechado (garagem): com o personagem aqui dentro, os sons ganham eco.

func _ready() -> void:
	body_entered.connect(func(b: Node3D): if b.has_method("set_water"): Audio.indoor = true)
	body_exited.connect(func(b: Node3D): if b.has_method("set_water"): Audio.indoor = false)
