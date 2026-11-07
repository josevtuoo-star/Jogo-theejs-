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


## Mostra `data` na mão (null = mãos livres). Chamado pela mochila. `item`
## traz o que não é de combate (a tocha acende uma luz na ponta).
func show_weapon(data: WeaponData, item: ItemData = null) -> void:
	var light := item.light_energy if item != null else 0.0
	if data == weapon and light == _light_energy:
		return
	weapon = data
	if data != null:
		_ensure_attachment()
		_model.mesh = data.mesh
		# Ferramenta de duas mãos: a direita fica mais acima no cabo.
		_model.transform = grip_offset(body.skeleton) * Transform3D(Basis.IDENTITY, Vector3(0.0, -data.grip_shift, 0.0))
		_model.visible = true
	elif _model != null:
		_model.visible = false
	_set_flame(light, data)
	if body != null:
		body.two_hand_weapon = data if data != null and data.two_handed else null
		body.held_weapon = data
		body.guard_clip = &"weapon_idle" if data != null else BodyAnimator.GUARD_CLIP
	_show_drop_button(data != null)
	weapon_changed.emit(weapon)


## Atalho: põe a arma na mochila e a empunha.
func equip(data: WeaponData, _drop_at: Transform3D = Transform3D.IDENTITY) -> void:
	if inventory == null:
		show_weapon(data)
		return
	var item := ItemData.find(data.id)
	if inventory.add(item):
		# A unidade nova é a última casa com o item (barra primeiro).
		for i in Inventory.HOTBAR:
			if inventory.item_at(i) == item:
				inventory.equip(i)


# --- Tocha ---------------------------------------------------------------------

var _light_energy: float = 0.0
var _flame: Node3D
var _flame_light: OmniLight3D
var _flicker: float = 0.0


## Chama na ponta da tocha: luz quente que tremula e partículas de fogo.
func _set_flame(energy: float, data: WeaponData) -> void:
	_light_energy = energy
	if energy <= 0.0 or data == null:
		if _flame != null:
			_flame.queue_free()
			_flame = null
			_flame_light = null
		return
	if _flame != null:
		return
	_flame = Node3D.new()
	_flame.name = "Chama"
	_flame.position = Vector3(0.0, data.mesh.get_aabb().end.y - 0.03, 0.0)
	_model.add_child(_flame)
	_flame_light = OmniLight3D.new()
	_flame_light.light_color = Color(1.0, 0.62, 0.3)
	_flame_light.light_energy = energy
	_flame_light.omni_range = 9.0
	_flame_light.omni_attenuation = 1.2
	_flame_light.shadow_enabled = true
	_flame_light.position = Vector3(0.0, 0.12, 0.0)
	# Não ilumina nem sombreia o próprio corpo de dentro dele.
	_flame_light.light_cull_mask = ~CaveAtmosphere.PLAYER_RENDER_LAYER
	_flame.add_child(_flame_light)
	var fire := CPUParticles3D.new()
	fire.amount = 24
	fire.lifetime = 0.45
	fire.local_coords = false
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 0.035
	fire.direction = Vector3.UP
	fire.spread = 12.0
	fire.gravity = Vector3(0.0, 1.6, 0.0)
	fire.initial_velocity_min = 0.15
	fire.initial_velocity_max = 0.4
	fire.scale_amount_min = 0.5
	fire.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	fire.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	ramp.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	fire.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.12)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	glow.vertex_color_use_as_albedo = true
	glow.albedo_texture = _soft_dot()
	quad.material = glow
	fire.mesh = quad
	_flame.add_child(fire)


static func _soft_dot() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 32
	texture.height = 32
	return texture


func _process(delta: float) -> void:
	if _flame_light != null:
		_flicker += delta * 13.0
		_flame_light.light_energy = _light_energy * (0.85 + 0.1 * sin(_flicker) + 0.06 * sin(_flicker * 2.7 + 1.3))


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
	# O lado que golpeia aponta para onde apontam os nós dos dedos (a frente
	# do punho fechado), como ao segurar um martelo: a lâmina do machado e a
	# ponta da picareta vão para a frente, não para o lado da palma.
	var z := (fingers - y * fingers.dot(y)).normalized()
	var x := y.cross(z).normalized()
	# Centro do punho fechado: um pouco além da base dos dedos, junto à palma.
	var grip := hand.origin + fingers * (middle - hand.origin).length() * 0.85 + palm * 0.025
	return hand.affine_inverse() * Transform3D(Basis(x, y, z), grip)
