extends StaticBody3D
## Painel com botão: USAR aperta (animação de interagir) e abre/fecha o portão.

@export var gate: Node3D


func use_label() -> String:
	return "FECHAR PORTÃO" if gate and gate.is_open else "ABRIR PORTÃO"


func interact(player: Node) -> void:
	player.press(self)


## Chamado pelo personagem no instante em que a mão encosta no botão.
func activate() -> void:
	if gate:
		gate.toggle()
	var lamp := get_node_or_null("Luz") as MeshInstance3D
	if lamp:
		var m := lamp.get_active_material(0) as StandardMaterial3D
		if m:
			m.emission = Color(0.2, 1.0, 0.3) if gate.is_open else Color(1.0, 0.25, 0.15)
