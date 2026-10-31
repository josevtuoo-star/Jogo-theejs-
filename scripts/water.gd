extends Area3D
## Volume de água: avisa o personagem quando entra/sai e qual a altura da superfície.

@export var surface_y := 0.0


func _ready() -> void:
	body_entered.connect(func(b: Node3D): if b.has_method("set_water"): b.set_water(self))
	body_exited.connect(func(b: Node3D): if b.has_method("set_water"): b.set_water(null))
