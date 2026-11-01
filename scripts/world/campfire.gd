class_name Campfire
extends Interactable
## Fogueira que o jogador acende e apaga (interação no quadro de contato da
## mão). Acesa: luz quente que tremula de forma irregular, chamas e fumaça.

@export var light: OmniLight3D
@export var flames: GPUParticles3D
@export var smoke: GPUParticles3D
@export var is_lit: bool = false
## Energia média da luz acesa.
@export_range(0.0, 10.0, 0.1) var light_energy: float = 2.4

var _time: float = 0.0


func _ready() -> void:
	interacted.connect(func(_by: Node) -> void: set_lit(not is_lit))
	set_lit(is_lit)


func set_lit(lit: bool) -> void:
	is_lit = lit
	if light != null:
		light.visible = lit
	if flames != null:
		flames.emitting = lit
	if smoke != null:
		smoke.emitting = lit
	prompt = "Apagar a fogueira" if lit else "Acender a fogueira"


func _process(delta: float) -> void:
	if not is_lit or light == null:
		return
	_time += delta
	# Tremulação: soma de senos de frequências não múltiplas (sem padrão visível).
	var flicker := 0.82 + 0.10 * sin(_time * 7.3) + 0.06 * sin(_time * 13.1 + 1.7) + 0.04 * sin(_time * 23.7 + 0.4)
	light.light_energy = light_energy * flicker
