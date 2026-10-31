extends RigidBody3D
## Caixa de suprimentos: o personagem pega com o botão USAR (animação de pegar do chão).

func use_label() -> String:
	return "PEGAR"


func interact(player: Node) -> void:
	player.pickup(self)
