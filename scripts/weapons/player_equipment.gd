class_name PlayerEquipment
extends Node
## Arma na mão do sobrevivente.
##
## A arma é presa ao osso da mão direita (BoneAttachment3D). A pegada é
## calculada da anatomia da mão do próprio personagem na pose de repouso:
## direção dos dedos, eixo indicador→mínimo e a palma. O cabo fica no
## fechamento da mão, com a cabeça da arma saindo do lado do polegar e o lado
## que golpeia virado para fora da palma, então funciona com qualquer
## personagem do mesmo esqueleto.

signal weapon_changed(weapon: WeaponData)

@export var player: PlayerController
@export var body: BodyAnimator

var weapon: WeaponData = null
var _attachment: BoneAttachment3D
var _model: MeshInstance3D


func has_weapon() -> bool:
	return weapon != null


## Empunha `data`. Se já havia uma arma, ela cai em `drop_at` (onde estava a
## nova) ou na frente do jogador.
func equip(data: WeaponData, drop_at: Transform3D = Transform3D.IDENTITY) -> void:
	if weapon != null:
		drop(drop_at if drop_at != Transform3D.IDENTITY else _drop_transform())
	weapon = data
	_ensure_attachment()
	_model.mesh = data.mesh
	_model.visible = true
	if body != null:
		body.guard_clip = &"weapon_idle"
	_show_drop_button(true)
	weapon_changed.emit(weapon)


## Solta a arma no mundo (corpo físico que pode ser pego de novo).
func drop(where: Transform3D = Transform3D.IDENTITY) -> RigidBody3D:
	if weapon == null:
		return null
	var data := weapon
	weapon = null
	if _model != null:
		_model.visible = false
	if body != null:
		body.guard_clip = BodyAnimator.GUARD_CLIP
	var spot := where if where != Transform3D.IDENTITY else _drop_transform()
	var dropped := WeaponPickup.spawn(data, spot, player.get_parent())
	_show_drop_button(false)
	weapon_changed.emit(null)
	return dropped


## O botão SOLTAR dos controles de toque só aparece com uma arma na mão.
func _show_drop_button(holding: bool) -> void:
	if is_inside_tree():
		get_tree().call_group(&"drop_weapon_button", &"set_visible", holding)


func _drop_transform() -> Transform3D:
	var forward := -player.get_view_basis().z
	var spot := player.global_position + forward * 0.7 + Vector3.UP * 0.6
	return Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, player.get_view_yaw()), spot)


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("drop_weapon") and weapon != null and player.input_enabled and not player.is_dead():
		drop()


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
