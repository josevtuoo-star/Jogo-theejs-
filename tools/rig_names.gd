extends RefCounted
## Nomes dos ossos: esqueleto do personagem (convenção Mixamo, como exportado
## no Sobrevivente.fbx) → nomes usados pelo jogo e pelas animações (convenção
## Unreal/Quaternius). O jogo inteiro (animador, combate, ragdoll, testes)
## fala nos nomes da direita; trocar de personagem só exige este mapa.

const MIXAMO_TO_GAME := {
	"Hips": "pelvis", "Spine": "spine_01", "Spine1": "spine_02", "Spine2": "spine_03",
	"Neck": "neck_01", "Head": "Head",
	"LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l", "LeftToe_End": "ball_leaf_l",
	"RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r", "RightToe_End": "ball_leaf_r",
}

const SIDES := {"Left": "_l", "Right": "_r"}
const FINGERS := {"Thumb": "thumb", "Index": "index", "Middle": "middle", "Ring": "ring", "Pinky": "pinky"}


## Nome no jogo para um osso do personagem (ou o próprio nome, se não mapeado).
static func game_name(bone_name: String) -> String:
	var clean := bone_name.trim_prefix("mixamorig:")
	if MIXAMO_TO_GAME.has(clean):
		return MIXAMO_TO_GAME[clean]
	for side in SIDES:
		var suffix: String = SIDES[side]
		if clean == side + "Shoulder":
			return "clavicle" + suffix
		if clean == side + "Arm":
			return "upperarm" + suffix
		if clean == side + "ForeArm":
			return "lowerarm" + suffix
		if clean == side + "Hand":
			return "hand" + suffix
		for finger in FINGERS:
			for index in range(1, 5):
				if clean == "%sHand%s%d" % [side, finger, index]:
					if index == 4:
						return "%s_04_leaf%s" % [FINGERS[finger], suffix]
					return "%s_0%d%s" % [FINGERS[finger], index, suffix]
	return clean


## Renomeia os ossos de um esqueleto para os nomes do jogo.
static func rename_skeleton(skeleton: Skeleton3D) -> void:
	for bone in skeleton.get_bone_count():
		skeleton.set_bone_name(bone, game_name(skeleton.get_bone_name(bone)))


## Renomeia as ligações de uma pele (Skin) para os nomes do jogo.
static func rename_skin(skin: Skin) -> Skin:
	var copy := skin.duplicate() as Skin
	for bind in copy.get_bind_count():
		var bind_name := String(copy.get_bind_name(bind))
		if not bind_name.is_empty():
			copy.set_bind_name(bind, game_name(bind_name))
	return copy
