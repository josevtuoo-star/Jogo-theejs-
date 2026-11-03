class_name ArmorVisuals
extends Node
## Armadura vestida aparece no corpo: capacete na cabeça, chapas no peito e
## nas costas, joelheiras e biqueiras nas botas. Cada peça é presa a um osso
## (BoneAttachment3D) na posição medida na pose de repouso do esqueleto
## (metros, personagem olhando para +Z), então acompanha a animação.
## Em primeira pessoa o capacete só projeta sombra (não tapa a câmera).

## casa do corpo: [[malha, osso, posição no esqueleto], ...]
const PIECES := {
	&"cabeca": [["armadura_capacete", "Head", Vector3(0.0, 1.69, 0.005)]],
	&"tronco": [["armadura_colete", "spine_03", Vector3(0.0, 1.29, 0.0)]],
	&"pernas": [["armadura_joelheira", "calf_l", Vector3(0.095, 0.5, 0.075)],
			["armadura_joelheira", "calf_r", Vector3(-0.095, 0.5, 0.075)]],
	&"pes": [["armadura_bota", "foot_l", Vector3(0.097, 0.065, 0.1)],
			["armadura_bota", "foot_r", Vector3(-0.097, 0.065, 0.1)]],
}

@export var body: BodyAnimator
@export var inventory: Inventory

## casa do corpo -> [MeshInstance3D]
var _shown: Dictionary = {}
var _first_person: bool = false


func _ready() -> void:
	# A aparência escolhida no menu (PERSONAGEM) vale para o corpo do jogador.
	if body != null:
		CharacterLook.apply(body, GameSession.look)
	refresh()


## Mostra exatamente o que está vestido.
func refresh() -> void:
	if body == null or inventory == null or body.skeleton == null:
		return
	for body_slot: StringName in PIECES:
		var worn := inventory.armor_item(body_slot) != null
		if worn and not _shown.has(body_slot):
			_shown[body_slot] = _attach(body_slot)
		elif not worn and _shown.has(body_slot):
			for mesh: Node in _shown[body_slot]:
				mesh.get_parent().queue_free()
			_shown.erase(body_slot)
	_apply_view()


func _attach(body_slot: StringName) -> Array:
	var skeleton := body.skeleton
	var layers := 1
	for mesh: GeometryInstance3D in skeleton.find_children("*", "GeometryInstance3D", true, false):
		layers = mesh.layers
		break
	var list := []
	for piece: Array in PIECES[body_slot]:
		var bone := skeleton.find_bone(piece[1])
		if bone < 0:
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "Armadura_%s_%s" % [body_slot, piece[1]]
		attachment.bone_name = piece[1]
		skeleton.add_child(attachment)
		var mesh := MeshInstance3D.new()
		mesh.mesh = load("res://resources/models/world/%s.res" % piece[0])
		mesh.layers = layers
		mesh.transform = skeleton.get_bone_global_rest(bone).affine_inverse() * Transform3D(Basis.IDENTITY, piece[2])
		attachment.add_child(mesh)
		list.append(mesh)
	return list


func _process(_delta: float) -> void:
	if body != null and body.hide_head != _first_person:
		_apply_view()


func _apply_view() -> void:
	_first_person = body.hide_head if body != null else false
	for mesh: MeshInstance3D in _shown.get(&"cabeca", []):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _first_person \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
