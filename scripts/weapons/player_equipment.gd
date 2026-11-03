class_name PlayerEquipment
extends Node
## Ferramenta na mão do sobrevivente (o que está na casa selecionada da
## mochila, Inventory).
##
## A ferramenta é presa ao osso da mão direita (BoneAttachment3D). A pegada é
## calculada da anatomia da mão do próprio personagem na pose de repouso:
## direção dos dedos, eixo indicador→mínimo e a palma. O cabo fica no
## fechamento da mão, com a cabeça da ferramenta saindo do lado do polegar e o
## lado que golpeia virado para fora da palma, então funciona com qualquer
## personagem do mesmo esqueleto.

signal weapon_changed(weapon: WeaponData)

@export var player: PlayerController
@export var body: BodyAnimator
@export var inventory: Inventory

var weapon: WeaponData = null
var _attachment: BoneAttachment3D
var _model: MeshInstance3D


func has_weapon() -> bool:
	return weapon != null


## Mostra `data` na mão (null = mãos livres). Chamado pela mochila.
func show_weapon(data: WeaponData) -> void:
	if data == weapon:
		return
	weapon = data
	if data != null:
		_ensure_attachment()
		_model.mesh = data.mesh
		_model.visible = true
	elif _model != null:
		_model.visible = false
	if body != null:
		body.guard_clip = &"weapon_idle" if data != null else BodyAnimator.GUARD_CLIP
	_show_drop_button(data != null)
	weapon_changed.emit(weapon)


## Atalho: põe a arma na mochila e a empunha.
func equip(data: WeaponData, _drop_at: Transform3D = Transform3D.IDENTITY) -> void:
	if inventory == null:
		show_weapon(data)
		return
	var item := ItemData.find(data.id)
	var before := inventory.tools.duplicate()
	if inventory.add(item):
		for i in Inventory.TOOL_SLOTS:
			if before[i].is_empty() and not inventory.tools[i].is_empty():
				inventory.equip(i)
				break


## Solta a ferramenta da mão no mundo (corpo físico que pode ser pego de novo).
func drop(where: Transform3D = Transform3D.IDENTITY) -> RigidBody3D:
	if inventory == null or inventory.selected < 0:
		return null
	return inventory.drop_tool(inventory.selected, where)


## O botão SOLTAR dos controles de toque só aparece com uma ferramenta na mão.
func _show_drop_button(holding: bool) -> void:
	if is_inside_tree():
		get_tree().call_group(&"drop_weapon_button", &"set_visible", holding)


func _ensure_attachment() -> void:
	if _attachment != null:
		return
	var skeleton := body.skeleton
	_attachment = BoneAttachment3D.new()
	_attachment.name = "RightHandWeapon"
	_attachment.bone_name = "hand_r"
	skeleton.add_child(_attachment)
	_model = MeshInstance3D.new()
	_model.name = "WeaponModel"
	_model.transform = grip_offset(skeleton)
	# Mesma camada de desenho do corpo (a lanterna de cabeça trata a
	# ferramenta na mão como parte do jogador).
	for mesh: GeometryInstance3D in skeleton.find_children("*", "GeometryInstance3D", true, false):
		_model.layers = mesh.layers
		break
	_attachment.add_child(_model)


## Transformação da arma no espaço do osso da mão, a partir da anatomia.
static func grip_offset(skeleton: Skeleton3D) -> Transform3D:
	var hand := skeleton.get_bone_global_rest(skeleton.find_bone("hand_r"))
	var middle := skeleton.get_bone_global_rest(skeleton.find_bone("middle_01_r")).origin
	var index := skeleton.get_bone_global_rest(skeleton.find_bone("index_01_r")).origin
	var pinky := skeleton.get_bone_global_rest(skeleton.find_bone("pinky_01_r")).origin
	var fingers := (middle - hand.origin).normalized()
	var across := (index - pinky).normalized() # cabo: do mínimo para o indicador
	var palm := fingers.cross(across).normalized()
	var y := (across - fingers * across.dot(fingers)).normalized()
	var z := (palm - y * palm.dot(y)).normalized()
	var x := y.cross(z).normalized()
	# Centro do punho fechado: um pouco além da base dos dedos, junto à palma.
	var grip := hand.origin + fingers * (middle - hand.origin).length() * 0.85 + palm * 0.025
	return hand.affine_inverse() * Transform3D(Basis(x, y, z), grip)
