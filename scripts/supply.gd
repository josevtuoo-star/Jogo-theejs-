extends "res://scripts/prop.gd"
## Caixa de suprimentos: o personagem pega com o botão USAR (animação de pegar). Como os
## outros objetos, faz barulho ao cair e boia na água.

func use_label() -> String:
	return "PEGAR"


func interact(player: Node) -> void:
	player.pickup(self)
