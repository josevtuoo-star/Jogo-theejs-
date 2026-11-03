class_name ZombiePosture
extends SkeletonModifier3D
## Postura própria de cada zumbi, aplicada por cima da animação: cabeça caída
## para um lado, tronco curvado e um braço pendurado (como quem foi mordido
## ali). Some quando ele vira ragdoll (o simulador assume os ossos).

var head_tilt: float = 0.0
var hunch: float = 0.0
var limp_arm: float = 0.0
var arm_side: String = "_l"


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if absf(hunch) > 0.001:
		for bone_name: String in ["spine_01", "spine_02", "spine_03"]:
			_rotate(skeleton, bone_name, Vector3.LEFT, -hunch / 3.0)
	if absf(head_tilt) > 0.001:
		_rotate(skeleton, "neck_01", Vector3.BACK, head_tilt * 0.4)
		_rotate(skeleton, "Head", Vector3.BACK, head_tilt * 0.6)
	if limp_arm > 0.001:
		# Braço junto ao corpo, mole: gira o ombro para baixo.
		var side := 1.0 if arm_side == "_l" else -1.0
		_rotate(skeleton, "upperarm" + arm_side, Vector3.BACK, -side * limp_arm)
		_rotate(skeleton, "lowerarm" + arm_side, Vector3.LEFT, limp_arm * 0.3)


static func _rotate(skeleton: Skeleton3D, bone_name: String, axis: Vector3, angle: float) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var global_rotation := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	var delta := global_rotation.inverse() * Quaternion(axis, angle) * global_rotation
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * delta)
