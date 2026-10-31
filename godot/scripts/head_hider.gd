extends SkeletonModifier3D
## Em 1ª pessoa, encolhe a cabeça do personagem (depois da animação) para a câmera não ver
## o rosto por dentro. O resto do corpo continua visível: olhando para baixo você vê braços,
## tronco e pernas.

var hide_head := false
var _bone := -1


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _bone < 0:
		_bone = sk.find_bone("head")
		if _bone < 0:
			return
	sk.set_bone_pose_scale(_bone, Vector3.ONE * (0.001 if hide_head else 1.0))
