extends StaticBody3D
## Assento (cadeira, banco, cama): USAR senta. O ponto "Assento" diz onde o quadril fica e
## para onde a pessoa sentada olha (-Z).

func use_label() -> String:
	return "SENTAR"


func interact(player: Node) -> void:
	player.sit(($Assento as Node3D).global_transform)
