extends SkeletonModifier3D
## Ajustes do corpo aplicados depois da animação, a cada quadro:
## - pés no chão (IK de duas articulações): em rampa, escada ou caixa cada pé desce/sobe até
##   o chão de verdade e acompanha a inclinação; o quadril baixa para o pé mais baixo alcançar;
## - inclinação do tronco: para dentro nas curvas e para frente ao acelerar;
## - tronco, pescoço e cabeça viram para onde a câmera olha;
## - em 1ª pessoa a cabeça é encolhida (a câmera fica dentro dela).
## O personagem (player.gd) atualiza os valores abaixo a cada quadro.

var hide_head := false
## 0 = desligado, 1 = pés totalmente presos ao chão (o personagem suaviza)
var ik_weight := 0.0
## x = para frente, y = para o lado direito (radianos)
var lean := Vector2.ZERO
## x = giro em relação ao quadril, y = inclinação para cima/baixo (radianos)
var look := Vector2.ZERO
## o próprio corpo físico (não pode ser "chão" dos raios dos pés)
var exclude: Array[RID] = []

const LEGS := [["thigh_l", "calf_l", "foot_l"], ["thigh_r", "calf_r", "foot_r"]]

var _bones := {}
var _pelvis_off := 0.0
var _foot_off := [0.0, 0.0]
var _foot_n := [Vector3.UP, Vector3.UP]


func _bone(n: String) -> int:
	if not _bones.has(n):
		_bones[n] = get_skeleton().find_bone(n)
	return _bones[n]


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var head := _bone("Head")
	if head >= 0:
		sk.set_bone_pose_scale(head, Vector3.ONE * (0.001 if hide_head else 1.0))
	if ik_weight > 0.001:
		_feet(sk)
	else:
		_pelvis_off = 0.0
	_lean(sk)
	_look(sk)


## Gira um osso em torno de um eixo (no espaço do esqueleto), levando os filhos junto.
func _turn(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 0.0001:
		return
	var g := sk.get_bone_global_pose(bone)
	g.basis = Basis(axis.normalized(), angle) * g.basis
	sk.set_bone_global_pose(bone, g)


func _lean(sk: Skeleton3D) -> void:
	# o modelo olha para +Z; frente = giro em X, lado = giro em Z
	for b in ["spine_01", "spine_02"]:
		_turn(sk, _bone(b), Vector3.RIGHT, lean.x * 0.5)
		_turn(sk, _bone(b), Vector3.BACK, lean.y * 0.5)


func _look(sk: Skeleton3D) -> void:
	if look.length() < 0.001:
		return
	# o giro é dividido pela coluna, pescoço e cabeça (como uma pessoa olhando para o lado)
	_turn(sk, _bone("spine_01"), Vector3.UP, look.x * 0.15)
	_turn(sk, _bone("spine_02"), Vector3.UP, look.x * 0.15)
	_turn(sk, _bone("spine_03"), Vector3.UP, look.x * 0.2)
	_turn(sk, _bone("neck_01"), Vector3.UP, look.x * 0.2)
	_turn(sk, _bone("Head"), Vector3.UP, look.x * 0.3)
	var right := Basis(Vector3.UP, look.x) * Vector3.RIGHT
	_turn(sk, _bone("spine_03"), right, -look.y * 0.25)
	_turn(sk, _bone("neck_01"), right, -look.y * 0.3)
	_turn(sk, _bone("Head"), right, -look.y * 0.45)


func _feet(sk: Skeleton3D) -> void:
	var xf := sk.global_transform
	var inv := xf.affine_inverse()
	var space := sk.get_world_3d().direct_space_state
	var offs := [0.0, 0.0]
	for i in 2:
		var foot := sk.get_bone_global_pose(_bone(LEGS[i][2]))
		var fw := xf * foot.origin
		# onde o chão "estaria" para a animação (altura zero do modelo, embaixo do pé)
		var flat := xf * Vector3(foot.origin.x, 0.0, foot.origin.z)
		var q := PhysicsRayQueryParameters3D.create(fw + Vector3.UP * 0.55, fw + Vector3.DOWN * 0.6, 1 | 2, exclude)
		var hit := space.intersect_ray(q)
		var off := 0.0
		var n := Vector3.UP
		if not hit.is_empty() and hit.normal.y > 0.6:
			off = clampf(hit.position.y - flat.y, -0.45, 0.45)
			n = inv.basis * hit.normal
		_foot_off[i] = lerpf(_foot_off[i], off, 0.35)
		# (lerp + normalizar: o slerp de vetores quase iguais perde precisão)
		_foot_n[i] = _foot_n[i].lerp(n.normalized(), 0.3).normalized()
		offs[i] = _foot_off[i]
	# o quadril desce até o pé mais baixo alcançar o chão
	_pelvis_off = lerpf(_pelvis_off, minf(minf(offs[0], offs[1]), 0.0), 0.3)
	var pelvis := _bone("pelvis")
	var keep := []
	for i in 2:
		keep.append(sk.get_bone_global_pose(_bone(LEGS[i][2])).basis)
	var pg := sk.get_bone_global_pose(pelvis)
	pg.origin.y += _pelvis_off * ik_weight
	sk.set_bone_global_pose(pelvis, pg)
	for i in 2:
		var foot := sk.get_bone_global_pose(_bone(LEGS[i][2]))
		var target: Vector3 = foot.origin + Vector3.UP * (offs[i] - _pelvis_off) * ik_weight
		var tilt := Basis(Quaternion(Vector3.UP, _foot_n[i]).normalized().slerp(Quaternion.IDENTITY, 1.0 - ik_weight))
		_two_bone(sk, _bone(LEGS[i][0]), _bone(LEGS[i][1]), _bone(LEGS[i][2]), target, tilt * keep[i])


## IK analítico de duas articulações (coxa e canela), mantendo o joelho no mesmo plano.
func _two_bone(sk: Skeleton3D, a: int, b: int, c: int, target: Vector3, foot_basis: Basis) -> void:
	var A := sk.get_bone_global_pose(a)
	var B := sk.get_bone_global_pose(b)
	var C := sk.get_bone_global_pose(c)
	var la := A.origin.distance_to(B.origin)
	var lb := B.origin.distance_to(C.origin)
	var at := target - A.origin
	var d := clampf(at.length(), 0.05, la + lb - 0.002)
	var n := (B.origin - A.origin).cross(C.origin - A.origin)
	if n.length() < 0.002:
		# perna quase reta: dobra no plano da coxa
		n = A.basis.x
	n = n.normalized()
	var ang := acos(clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0))
	var knee := A.origin + at.normalized().rotated(n, -ang) * la
	A.basis = Basis(Quaternion((B.origin - A.origin).normalized(), (knee - A.origin).normalized())) * A.basis
	sk.set_bone_global_pose(a, A)
	B = sk.get_bone_global_pose(b)
	C = sk.get_bone_global_pose(c)
	var tdir := target - B.origin
	if tdir.length() > 0.001:
		B.basis = Basis(Quaternion((C.origin - B.origin).normalized(), tdir.normalized())) * B.basis
		sk.set_bone_global_pose(b, B)
	C = sk.get_bone_global_pose(c)
	C.basis = foot_basis
	sk.set_bone_global_pose(c, C)
