extends SkeletonModifier3D
## Ajustes do corpo aplicados depois da animação, a cada quadro:
## - pés no chão (IK de duas articulações): em rampa, escada ou caixa cada pé desce/sobe até
##   o chão de verdade e acompanha a inclinação; o quadril baixa para o pé mais baixo alcançar;
## - inclinação do tronco: para dentro nas curvas e para frente ao acelerar;
## - tronco, pescoço e cabeça viram para onde a câmera olha;
## - em 1ª pessoa a cabeça é encolhida (a câmera fica dentro dela);
## - braços por IK (ombro-cotovelo-mão, com o cotovelo apontando para baixo/fora): a mão vai até
##   um alvo no mundo (pegar item, segurar a arma com as duas mãos, levar até as costas);
## - tronco inclinado para frente ao abaixar para pegar algo;
## - extras por cima de cada animação: respiração (peito e ombros sobem, mais rápido cansado),
##   braços abrindo para equilibrar no ar, cabeça para fora d'água nadando, cabeça baixa e
##   tronco à frente fazendo força ao empurrar, giro do tronco acompanhando o soco.
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
## duração do quadro (o personagem atualiza): as suavizações não dependem do FPS
var dt := 1.0 / 60.0
## braços: peso do IK e alvo no mundo (posição do pulso e orientação do osso da mão)
## índice 0 = esquerdo, 1 = direito
var hand_w := [0.0, 0.0]
var hand_xf := [Transform3D(), Transform3D()]
## quanto do giro para a câmera vai para a coluna (o resto fica no pescoço/cabeça)
var twist_share := 1.0
## abaixar o tronco para frente (0..1)
var bend := 0.0
## agachar mais (metros que o quadril desce; os pés ficam no chão pelo IK das pernas)
var squat := 0.0
## extras (o personagem atualiza)
var breath := 0.0 # intensidade da respiração (0 nada, 1 normal, 2 ofegante)
var breath_rate := 0.25 # respirações por segundo
var air_arms := 0.0
var head_up := 0.0
var strain := 0.0
var twist := 0.0 # giro extra do tronco (rad, + = para a esquerda)
var _bt := 0.0
## (testes) onde a mão ficou depois do IK
var debug_hand := [Vector3.ZERO, Vector3.ZERO]

const ARMS := [["upperarm_l", "lowerarm_l", "hand_l"], ["upperarm_r", "lowerarm_r", "hand_r"]]

const LEGS := [["thigh_l", "calf_l", "foot_l"], ["thigh_r", "calf_r", "foot_r"]]

var _bones := {}
var _pelvis_off := 0.0
var _foot_off := [0.0, 0.0]
var _foot_n := [Vector3.UP, Vector3.UP]


func _bone(n: String) -> int:
	if not _bones.has(n):
		_bones[n] = get_skeleton().find_bone(n)
	return _bones[n]


## Godot 4.5+: recebe o tempo do quadro.
func _process_modification_with_delta(delta: float) -> void:
	dt = delta
	_process_modification()


## Godot 4.3/4.4.
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
	_bend(sk)
	_extras(sk)
	_look(sk)
	for i in 2:
		if hand_w[i] > 0.001:
			_arm(sk, i)


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
	var sp := twist_share
	var rest := (1.0 - sp) * 0.5
	_turn(sk, _bone("spine_01"), Vector3.UP, look.x * 0.15 * sp)
	_turn(sk, _bone("spine_02"), Vector3.UP, look.x * 0.15 * sp)
	_turn(sk, _bone("spine_03"), Vector3.UP, look.x * 0.2 * sp)
	_turn(sk, _bone("neck_01"), Vector3.UP, look.x * (0.2 + rest * 0.4))
	_turn(sk, _bone("Head"), Vector3.UP, look.x * (0.3 + rest * 0.6))
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
		_foot_off[i] = lerpf(_foot_off[i], off, 1.0 - exp(-24.0 * dt))
		# (lerp + normalizar: o slerp de vetores quase iguais perde precisão)
		_foot_n[i] = _foot_n[i].lerp(n.normalized(), 1.0 - exp(-18.0 * dt)).normalized()
		offs[i] = _foot_off[i]
	# o quadril desce até o pé mais baixo alcançar o chão
	_pelvis_off = lerpf(_pelvis_off, minf(minf(offs[0], offs[1]), 0.0), 1.0 - exp(-14.0 * dt))
	var pelvis := _bone("pelvis")
	var keep := []
	for i in 2:
		keep.append(sk.get_bone_global_pose(_bone(LEGS[i][2])).basis)
	var pg := sk.get_bone_global_pose(pelvis)
	pg.origin.y += (_pelvis_off - squat) * ik_weight
	sk.set_bone_global_pose(pelvis, pg)
	for i in 2:
		var foot := sk.get_bone_global_pose(_bone(LEGS[i][2]))
		var target: Vector3 = foot.origin + Vector3.UP * (offs[i] - _pelvis_off + squat) * ik_weight
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


func _bend(sk: Skeleton3D) -> void:
	if bend < 0.001:
		return
	_turn(sk, _bone("spine_01"), Vector3.RIGHT, bend * 0.35)
	_turn(sk, _bone("spine_02"), Vector3.RIGHT, bend * 0.3)
	_turn(sk, _bone("spine_03"), Vector3.RIGHT, bend * 0.15)
	_turn(sk, _bone("neck_01"), Vector3.RIGHT, -bend * 0.25)


## IK do braço com vetor de polo (cotovelo para baixo, para fora e um pouco para trás).
func _arm(sk: Skeleton3D, i: int) -> void:
	var a := _bone(ARMS[i][0])
	var b := _bone(ARMS[i][1])
	var c := _bone(ARMS[i][2])
	if a < 0 or b < 0 or c < 0:
		return
	var w: float = clampf(hand_w[i], 0.0, 1.0)
	var t: Transform3D = sk.global_transform.affine_inverse() * (hand_xf[i] as Transform3D)
	var A := sk.get_bone_global_pose(a)
	var B := sk.get_bone_global_pose(b)
	var C := sk.get_bone_global_pose(c)
	var tp := C.origin.lerp(t.origin, w)
	var tq := C.basis.get_rotation_quaternion().slerp(t.basis.orthonormalized().get_rotation_quaternion(), w)
	var la := A.origin.distance_to(B.origin)
	var lb := B.origin.distance_to(C.origin)
	var at := tp - A.origin
	var dist := clampf(at.length(), 0.05, la + lb - 0.002)
	var dirn := at.normalized()
	var side := 1.0 if i == 0 else -1.0
	var pole := Vector3(side * 0.45, -0.75, -0.35)
	# braço levantado à frente: o cotovelo vai mais para fora e para baixo
	var pv := pole - dirn * pole.dot(dirn)
	if pv.length() < 0.01:
		pv = Vector3(side, 0.0, 0.0) - dirn * dirn.x * side
	var n := dirn.cross(pv.normalized()).normalized()
	var ang := acos(clampf((la * la + dist * dist - lb * lb) / (2.0 * la * dist), -1.0, 1.0))
	var elbow := A.origin + dirn.rotated(n, ang) * la
	A.basis = Basis(Quaternion((B.origin - A.origin).normalized(), (elbow - A.origin).normalized())) * A.basis
	sk.set_bone_global_pose(a, A)
	B = sk.get_bone_global_pose(b)
	C = sk.get_bone_global_pose(c)
	var tdir := tp - B.origin
	if tdir.length() > 0.001:
		B.basis = Basis(Quaternion((C.origin - B.origin).normalized(), tdir.normalized())) * B.basis
		sk.set_bone_global_pose(b, B)
	C = sk.get_bone_global_pose(c)
	C.basis = Basis(tq)
	sk.set_bone_global_pose(c, C)
	debug_hand[i] = sk.global_transform * sk.get_bone_global_pose(c).origin


func _extras(sk: Skeleton3D) -> void:
	_bt += dt * breath_rate * TAU
	if breath > 0.001:
		# inspira: o peito abre (coluna de cima para trás) e os ombros sobem
		var b := (sin(_bt) * 0.5 + 0.5) * breath
		_turn(sk, _bone("spine_02"), Vector3.RIGHT, -0.012 * b)
		_turn(sk, _bone("spine_03"), Vector3.RIGHT, -0.018 * b)
		_turn(sk, _bone("clavicle_l"), Vector3.BACK, 0.035 * b)
		_turn(sk, _bone("clavicle_r"), Vector3.BACK, -0.035 * b)
		_turn(sk, _bone("neck_01"), Vector3.RIGHT, 0.02 * b)
	if air_arms > 0.001:
		# no ar: braços abrem para os lados e um pouco para frente (equilíbrio)
		_turn(sk, _bone("upperarm_l"), Vector3.BACK, 0.55 * air_arms)
		_turn(sk, _bone("upperarm_r"), Vector3.BACK, -0.55 * air_arms)
		_turn(sk, _bone("lowerarm_l"), Vector3.UP, -0.3 * air_arms)
		_turn(sk, _bone("lowerarm_r"), Vector3.UP, 0.3 * air_arms)
	if head_up > 0.001:
		_turn(sk, _bone("neck_01"), Vector3.RIGHT, -0.35 * head_up)
		_turn(sk, _bone("Head"), Vector3.RIGHT, -0.25 * head_up)
	if strain > 0.001:
		_turn(sk, _bone("spine_02"), Vector3.RIGHT, 0.12 * strain)
		_turn(sk, _bone("neck_01"), Vector3.RIGHT, 0.12 * strain)
		_turn(sk, _bone("Head"), Vector3.RIGHT, 0.1 * strain)
	if absf(twist) > 0.001:
		_turn(sk, _bone("spine_01"), Vector3.UP, twist * 0.3)
		_turn(sk, _bone("spine_02"), Vector3.UP, twist * 0.3)
		_turn(sk, _bone("spine_03"), Vector3.UP, twist * 0.4)
		# a cabeça segura o olhar no alvo
		_turn(sk, _bone("neck_01"), Vector3.UP, -twist * 0.5)
		_turn(sk, _bone("Head"), Vector3.UP, -twist * 0.4)
