class_name LightSwitch
extends Interactable
## Interruptor: liga e desliga uma luz e move a alavanca.

@export var light: Light3D
## Nó girado entre as posições ligado/desligado.
@export var lever: Node3D
@export var lever_angle_degrees: float = 35.0
@export var is_on: bool = false

var toggle_count: int = 0


func _ready() -> void:
	interacted.connect(_on_interacted)
	_apply()


func _on_interacted(_by: Node) -> void:
	is_on = not is_on
	toggle_count += 1
	_apply()


func _apply() -> void:
	if light != null:
		light.visible = is_on
	if lever != null:
		lever.rotation.x = deg_to_rad(lever_angle_degrees * (1.0 if is_on else -1.0))
	prompt = "Desligar a luz" if is_on else "Ligar a luz"
