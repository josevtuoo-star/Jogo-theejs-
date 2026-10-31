extends StaticBody3D
## Banco: USAR senta (entrar, sentado, levantar). O ponto "Assento" diz onde o quadril fica e
## para onde o personagem olha.

func use_label() -> String:
	return "SENTAR"


func interact(player: Node) -> void:
	player.sit(($Assento as Node3D).global_transform)
