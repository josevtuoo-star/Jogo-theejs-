extends SceneTree
## Ferramenta de produção: gera o rig de braços em primeira pessoa e a sua
## biblioteca de animações autorais.
##
## Uso: godot --headless --path . --script res://tools/build_fp_arms.gd
##
## Saídas:
## - resources/models/fp_arms_mesh.res        malha com skin (mangas + mãos)
## - resources/animations/fp_arms_library.res animações (AnimationLibrary)
## - scenes/player/fp_arms.tscn               cena do rig (Skeleton3D + malha + AnimationPlayer)
##
## As animações são escritas como intenção física (posição e orientação das
## mãos e quanto os dedos estão fechados) e convertidas em rotações de osso
## por cinemática inversa analítica de dois ossos, amostrada a 30 quadros/s.
## Os nomes dos ossos seguem o SkeletonProfileHumanoid do Godot.

const SCENE_PATH := "res://scenes/player/fp_arms.tscn"
const LIBRARY_PATH := "res://resources/animations/fp_arms_library.res"
const MESH_PATH := "res://resources/models/fp_arms_mesh.res"
const SHADER_PATH := "res://resources/materials/viewmodel.gdshader"
const ANIMATOR_SCRIPT := "res://scripts/animation/fp_animator.gd"
const BAKE_FPS := 30.0

# --- Proporções (metros, espaço da câmera: x direita, y cima, -z frente) ----
const SHOULDER := Vector3(0.18, -0.25, 0.06)
## Elevação aplicada a todas as poses de mão: mantém mãos e antebraços dentro
## do quadro (a 32 cm da câmera, a borda inferior visível fica em y ≈ -0,245).
const HAND_LIFT := Vector3(0.0, 0.05, 0.0)
const UPPER_LEN := 0.30
const FORE_LEN := 0.28
const HAND_LEN := 0.085
const FINGER_PROX := 0.044
const FINGER_INTER := 0.038
const THUMB_PROX := 0.040
const THUMB_DIST := 0.032
## Direção para onde o cotovelo aponta (para fora e para baixo).
const ELBOW_POLE := Vector3(0.55, -1.0, 0.25)

const SIDES := {"Right": 1.0, "Left": -1.0}
const SIDE_BONES := ["UpperArm", "LowerArm", "Hand", "ThumbProximal", "ThumbDistal",
		"IndexProximal", "IndexIntermediate", "MiddleProximal", "MiddleIntermediate"]
const BONE_PARENTS := {
	"UpperArm": "", "LowerArm": "UpperArm", "Hand": "LowerArm",
	"ThumbProximal": "Hand", "ThumbDistal": "ThumbProximal",
	"IndexProximal": "Hand", "IndexIntermediate": "IndexProximal",
	"MiddleProximal": "Hand", "MiddleIntermediate": "MiddleProximal",
}

var _unreachable_warnings: Array[String] = []
var _current_animation: String = ""


func _initialize() -> void:
	var library := _build_library()
	var skeleton := _build_skeleton()
	var mesh := _build_mesh(skeleton)
	var errors := []
	errors.append(ResourceSaver.save(mesh, MESH_PATH))
	errors.append(ResourceSaver.save(library, LIBRARY_PATH))
	errors.append(_build_scene(skeleton, load(MESH_PATH), load(LIBRARY_PATH)))
	for warning in _unreachable_warnings:
		push_warning(warning)
	var ok := errors.all(func(e: int) -> bool: return e == OK)
	print("Rig e animações gerados: %s (%d animações, %d avisos de alcance)" % [
		"OK" if ok else str(errors), library.get_animation_list().size(), _unreachable_warnings.size()])
	quit(0 if ok else 1)


# =============================================================================
# Autoria: poses de mão
# =============================================================================

## Pose de mão: posição do punho (espaço da câmera), orientação em graus
## (arfagem, guinada, rolagem; dedos apontam para -Z, dorso para +Y) e
## fechamento dos dedos (0 aberta, 1 punho).
func _hand(position: Vector3, euler_degrees: Vector3, grip: float) -> Dictionary:
	return {"p": position + HAND_LIFT, "e": euler_degrees, "g": grip}


## Espelha uma pose da mão direita para a esquerda (plano YZ).
func _mirror(hand: Dictionary) -> Dictionary:
	var p: Vector3 = hand["p"]
	var e: Vector3 = hand["e"]
	return {"p": Vector3(-p.x, p.y, p.z), "e": Vector3(e.x, -e.y, -e.z), "g": hand["g"]}


func _offset(hand: Dictionary, dp: Vector3, de: Vector3 = Vector3.ZERO, dg: float = 0.0) -> Dictionary:
	return {"p": hand["p"] + dp, "e": hand["e"] + de, "g": clampf(hand["g"] + dg, 0.0, 1.0)}


## Quadro-chave. `left` nulo = espelho de `right`.
func _key(t: float, right: Dictionary, left: Variant = null, root: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"t": t, "Right": right, "Left": left if left != null else _mirror(right), "root": root}


## Ciclo de marcha normalizado (duração 1 = dois passos). t = 0: contato do pé
## esquerdo com o braço direito à frente; t = 0,5: contato do pé direito.
## swing_p/swing_e: deslocamento da mão direita no extremo dianteiro (o
## traseiro é o oposto); arc eleva a mão nos dois extremos (arco pendular);
## bounce: atraso vertical das mãos em relação ao corpo nos contatos.
func _gait_cycle(base: Dictionary, swing_p: Vector3, swing_e: Vector3, arc: float,
		bounce: float, grip_swing: float, samples: int = 8) -> Array:
	var keys := []
	for i in samples:
		var t := float(i) / samples
		var swing := cos(TAU * t)
		var contact := cos(2.0 * TAU * t) # +1 nos contatos
		var lift := Vector3(0.0, arc * swing * swing + bounce * contact, 0.0)
		var right := _offset(base, swing_p * swing + lift, swing_e * swing, grip_swing * swing)
		var left := _mirror(_offset(base, swing_p * -swing + lift, swing_e * -swing, grip_swing * -swing))
		keys.append(_key(t, right, left))
	return keys


# =============================================================================
# Autoria: animações
# =============================================================================

func _build_library() -> AnimationLibrary:
	var library := AnimationLibrary.new()

	var ready := _hand(Vector3(0.165, -0.262, -0.32), Vector3(-18.0, 10.0, -28.0), 0.35)
	var jog := _hand(Vector3(0.158, -0.236, -0.29), Vector3(-2.0, 14.0, -62.0), 0.72)
	var sprint := _hand(Vector3(0.172, -0.244, -0.26), Vector3(2.0, 16.0, -72.0), 0.92)
	var crouch := _hand(Vector3(0.150, -0.285, -0.34), Vector3(-26.0, 12.0, -32.0), 0.40)
	var guard_r := _hand(Vector3(0.120, -0.172, -0.33), Vector3(8.0, 18.0, -78.0), 1.0)
	var guard_l := _mirror(_hand(Vector3(0.140, -0.162, -0.29), Vector3(10.0, 20.0, -75.0), 1.0))
	var air := _hand(Vector3(0.210, -0.200, -0.29), Vector3(-8.0, 22.0, -20.0), 0.25)
	var fall := _hand(Vector3(0.245, -0.165, -0.26), Vector3(-5.0, 30.0, -15.0), 0.10)
	var flinch := _hand(Vector3(0.100, -0.150, -0.24), Vector3(10.0, 25.0, -60.0), 0.65)
	var jab := _hand(Vector3(0.050, -0.130, -0.47), Vector3(2.0, -4.0, -88.0), 1.0)

	# Repouso: respiração lenta (3,2 s), as mãos sobem na inspiração.
	_add(library, "idle", 3.2, true, [
		_key(0.0, ready),
		_key(1.6, _offset(ready, Vector3(0.0, 0.007, -0.004), Vector3(2.0, 0.0, 0.0), 0.05)),
	])
	# Locomoção (sincronizada com a passada real pelo animador).
	_add(library, "walk", 1.0, true, _gait_cycle(_offset(ready, Vector3(0.0, -0.004, 0.0)),
			Vector3(0.006, 0.012, -0.035), Vector3(4.0, 0.0, 0.0), 0.004, 0.003, 0.05))
	_add(library, "jog", 1.0, true, _gait_cycle(jog,
			Vector3(0.012, 0.034, -0.075), Vector3(-10.0, 0.0, 0.0), 0.010, 0.006, 0.08))
	_add(library, "sprint", 1.0, true, _gait_cycle(sprint,
			Vector3(0.020, 0.068, -0.13), Vector3(-18.0, 0.0, 4.0), 0.025, 0.010, 0.05))
	_add(library, "crouch_idle", 3.6, true, [
		_key(0.0, crouch),
		_key(1.8, _offset(crouch, Vector3(0.0, 0.006, -0.003), Vector3(2.0, 0.0, 0.0), 0.05)),
	])
	_add(library, "crouch_walk", 1.0, true, _gait_cycle(crouch,
			Vector3(0.004, 0.010, -0.030), Vector3(3.0, 0.0, 0.0), 0.003, 0.002, 0.03))
	# Mancando: o braço direito apoia o quadril machucado (fora da tela) e o
	# esquerdo equilibra; o tranco acontece no apoio da perna ferida (t = 0,5).
	var brace := _hand(Vector3(0.205, -0.360, -0.20), Vector3(-40.0, 20.0, -30.0), 0.80)
	var balance := _mirror(_offset(ready, Vector3(0.025, 0.0, 0.0), Vector3(0.0, 8.0, 10.0), -0.1))
	_add(library, "limp_walk", 1.0, true, [
		_key(0.00, brace, _offset(balance, Vector3(0.0, 0.004, 0.025))),
		_key(0.25, _offset(brace, Vector3(0.0, 0.006, 0.0)), _offset(balance, Vector3(0.0, 0.010, 0.0))),
		_key(0.50, _offset(brace, Vector3(0.010, -0.030, 0.010), Vector3(-6.0, 0.0, 0.0), 0.15),
				_offset(balance, Vector3(-0.030, -0.028, -0.030), Vector3(0.0, -10.0, -12.0))),
		_key(0.62, _offset(brace, Vector3(0.006, -0.018, 0.006), Vector3(-3.0, 0.0, 0.0), 0.1),
				_offset(balance, Vector3(-0.020, -0.012, -0.020))),
		_key(0.80, brace, _offset(balance, Vector3(0.0, 0.006, 0.0))),
	])
	# Ar: impulsão (pose atingida em 0,35 s) e queda (braços abertos para equilíbrio).
	_add(library, "jump", 0.35, false, [_key(0.0, ready), _key(0.35, air)])
	_add(library, "fall", 1.4, true, [
		_key(0.0, fall),
		_key(0.7, _offset(fall, Vector3(0.010, 0.015, 0.010), Vector3(5.0, 4.0, 6.0), -0.05)),
	])
	# Aterrissagens: as mãos descem com o corpo e voltam; na forte, apoiam-se.
	_add(library, "land_soft", 0.35, false, [
		_key(0.0, ready),
		_key(0.07, _offset(ready, Vector3(0.010, -0.055, 0.030), Vector3(-10.0, 0.0, 0.0), 0.15)),
		_key(0.35, ready),
	])
	var brace_land := _hand(Vector3(0.240, -0.360, -0.26), Vector3(-35.0, 25.0, -10.0), 0.90)
	_add(library, "land_hard", 0.75, false, [
		_key(0.0, ready),
		_key(0.06, brace_land),
		_key(0.32, _offset(brace_land, Vector3(0.0, 0.020, 0.0))),
		_key(0.75, ready),
	])
	# Ferimentos.
	_add(library, "hurt_light", 0.45, false, [
		_key(0.0, ready), _key(0.06, flinch), _key(0.45, ready),
	])
	var thrown := _hand(Vector3(0.220, -0.100, -0.20), Vector3(25.0, 35.0, -30.0), 0.30)
	var clutch := _hand(Vector3(0.050, -0.300, -0.17), Vector3(-30.0, 40.0, -70.0), 0.90)
	var brace_out := _mirror(_hand(Vector3(0.240, -0.260, -0.28), Vector3(-10.0, 25.0, -20.0), 0.50))
	_add(library, "hurt_heavy", 0.9, false, [
		_key(0.0, ready), _key(0.07, thrown), _key(0.30, clutch, brace_out), _key(0.9, ready),
	])
	# Interação: a mão direita alcança e pressiona (evento "contact" em 0,42 s).
	var reach := _hand(Vector3(0.070, -0.130, -0.46), Vector3(4.0, -6.0, -82.0), 0.15)
	_add(library, "interact", 0.85, false, [
		_key(0.0, ready), _key(0.32, reach), _key(0.42, _offset(reach, Vector3(0.0, 0.0, -0.015))),
		_key(0.55, reach), _key(0.85, ready),
	], {"contact": 0.42}, -1.0, "Right")
	# Guarda de combate (mantida alguns segundos depois de um ataque).
	_add(library, "guard", 2.4, true, [
		_key(0.0, guard_r, guard_l),
		_key(1.2, _offset(guard_r, Vector3(0.0, 0.006, 0.0)), _offset(guard_l, Vector3(0.0, 0.006, 0.0))),
	])
	# Soco rápido (jab): extensão em 0,13 s, golpe no evento "hit".
	_add(library, "attack_light", 0.55, false, [
		_key(0.0, guard_r, guard_l),
		_key(0.05, _offset(guard_r, Vector3(0.0, 0.005, 0.025)), guard_l),
		_key(0.13, jab, _offset(guard_l, Vector3(0.0, 0.0, 0.030))),
		_key(0.20, _offset(jab, Vector3(0.0, 0.0, 0.030)), _offset(guard_l, Vector3(0.0, 0.0, 0.025))),
		_key(0.45, guard_r, guard_l),
	], {"hit": 0.12})
	# Golpe carregado: preparação até 0,30 s (mantida enquanto o botão é
	# segurado), gancho com golpe em 0,43 s e acompanhamento.
	var windup := _hand(Vector3(0.260, -0.150, -0.12), Vector3(15.0, 70.0, -55.0), 1.0)
	var hook := _hand(Vector3(0.020, -0.120, -0.44), Vector3(0.0, -45.0, -90.0), 1.0)
	var follow := _hand(Vector3(-0.130, -0.160, -0.38), Vector3(-5.0, -70.0, -95.0), 1.0)
	_add(library, "attack_heavy", 1.15, false, [
		_key(0.0, guard_r, guard_l),
		_key(0.30, windup, _offset(guard_l, Vector3(0.030, 0.0, -0.06))),
		_key(0.44, hook, _offset(guard_l, Vector3(0.020, -0.030, 0.05))),
		_key(0.56, follow, _offset(guard_l, Vector3(0.010, -0.020, 0.04))),
		_key(1.15, guard_r, guard_l),
	], {"hit": 0.43}, 0.30)
	# Recuo da mão ao acertar algo rígido (parede).
	_add(library, "impact_recoil", 0.45, false, [
		_key(0.0, jab),
		_key(0.07, _hand(Vector3(0.110, -0.150, -0.30), Vector3(20.0, 10.0, -70.0), 0.9)),
		_key(0.16, _hand(Vector3(0.120, -0.170, -0.32), Vector3(10.0, 14.0, -76.0), 1.0)),
		_key(0.45, guard_r),
	], {}, -1.0, "Right")
	# Morte: espasmo e braços caindo para fora da visão (mantém o quadro final).
	_add(library, "death", 1.8, false, [
		_key(0.0, ready),
		_key(0.12, flinch),
		_key(0.55, _hand(Vector3(0.200, -0.480, -0.22), Vector3(-60.0, 20.0, -10.0), 0.35)),
		_key(1.8, _hand(Vector3(0.220, -0.620, -0.10), Vector3(-75.0, 15.0, 0.0), 0.30), null,
				Vector3(0.0, -0.05, 0.05)),
	])
	return library


func _add(library: AnimationLibrary, anim_name: String, length: float, loop: bool, keys: Array,
		events: Dictionary = {}, hold_time: float = -1.0, mask: String = "Both") -> void:
	_current_animation = anim_name
	library.add_animation(anim_name, _bake(length, loop, keys, events, hold_time, mask))


# =============================================================================
# Cinemática: IK de dois ossos e poses globais
# =============================================================================

func _bone_name(side: String, bone: String) -> String:
	return side + bone


func _basis_looking(direction: Vector3, up_reference: Vector3) -> Basis:
	var z := -direction.normalized()
	var up := up_reference
	if absf(up.normalized().dot(z)) > 0.98:
		up = Vector3.FORWARD if absf(z.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


func _hand_basis(hand: Dictionary) -> Basis:
	var e: Vector3 = hand["e"]
	return Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))


## Transformações globais (espaço do esqueleto) de todos os ossos.
func _pose_globals(right: Dictionary, left: Dictionary, root_offset: Vector3) -> Dictionary:
	var globals := {"Root": Transform3D(Basis.IDENTITY, root_offset)}
	for side in SIDES:
		var s: float = SIDES[side]
		var hand: Dictionary = right if side == "Right" else left
		var shoulder := root_offset + Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z)
		var target: Vector3 = root_offset + hand["p"]
		var to_target := target - shoulder
		var max_reach := UPPER_LEN + FORE_LEN - 0.001
		var distance := clampf(to_target.length(), 0.05, max_reach)
		if to_target.length() > max_reach + 0.01:
			_unreachable_warnings.append("%s/%s: alvo a %.3f m do ombro (alcance %.3f m)" % [
				_current_animation, side, to_target.length(), max_reach])
		var direction := to_target.normalized()
		var along := (UPPER_LEN * UPPER_LEN - FORE_LEN * FORE_LEN + distance * distance) / (2.0 * distance)
		var height := sqrt(maxf(UPPER_LEN * UPPER_LEN - along * along, 0.0))
		var pole := Vector3(ELBOW_POLE.x * s, ELBOW_POLE.y, ELBOW_POLE.z).normalized()
		var bend := (pole - direction * pole.dot(direction)).normalized()
		var elbow := shoulder + direction * along + bend * height
		var wrist := shoulder + direction * distance
		var upper := Transform3D(_basis_looking(elbow - shoulder, -bend), shoulder)
		var lower := Transform3D(_basis_looking(wrist - elbow, -bend), elbow)
		var hand_xform := Transform3D(_hand_basis(hand), wrist)
		globals[side + "UpperArm"] = upper
		globals[side + "LowerArm"] = lower
		globals[side + "Hand"] = hand_xform

		var grip: float = hand["g"]
		var fingers := {
			"Index": Vector3(-0.026 * s, 0.000, -HAND_LEN),
			"Middle": Vector3(-0.007 * s, 0.002, -HAND_LEN - 0.004),
		}
		for finger in fingers:
			var curl_1 := deg_to_rad(lerpf(-8.0, -88.0, grip))
			var curl_2 := deg_to_rad(lerpf(-12.0, -100.0, grip))
			var proximal := hand_xform * Transform3D(Basis(Vector3.RIGHT, curl_1), fingers[finger])
			globals[side + finger + "Proximal"] = proximal
			globals[side + finger + "Intermediate"] = proximal * Transform3D(Basis(Vector3.RIGHT, curl_2), Vector3(0.0, 0.0, -FINGER_PROX))
		var thumb_base := Vector3(-0.030 * s, -0.010, -0.022)
		# Mão aberta: polegar ao lado. Punho: polegar cruza por baixo dos dedos.
		var thumb_open := Vector3(-0.55 * s, -0.30, -0.78)
		var thumb_closed := Vector3(0.45 * s, -0.55, -0.70)
		var thumb_rest := _basis_looking(thumb_open.lerp(thumb_closed, grip * grip).normalized(), Vector3.UP)
		var thumb_curl := deg_to_rad(lerpf(-5.0, -30.0, grip))
		var thumb := hand_xform * Transform3D(thumb_rest * Basis(Vector3.RIGHT, thumb_curl), thumb_base)
		globals[side + "ThumbProximal"] = thumb
		globals[side + "ThumbDistal"] = thumb * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(lerpf(-8.0, -60.0, grip))), Vector3(0.0, 0.0, -THUMB_PROX))
	return globals


func _parent_of(bone_name: String) -> String:
	if bone_name == "Root":
		return ""
	for side in SIDES:
		if bone_name.begins_with(side):
			var parent: String = BONE_PARENTS[bone_name.trim_prefix(side)]
			return "Root" if parent.is_empty() else side + parent
	return ""


func _all_bone_names() -> Array[String]:
	var names: Array[String] = ["Root"]
	for side in SIDES:
		for bone in SIDE_BONES:
			names.append(side + bone)
	return names


# =============================================================================
# Bake das animações
# =============================================================================

func _bake(length: float, loop: bool, keys: Array, events: Dictionary, hold_time: float, mask: String) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var bones: Array[String] = []
	if mask == "Both":
		bones = _all_bone_names()
	else:
		for bone in SIDE_BONES:
			bones.append(mask + bone)
	var tracks := {}
	for bone in bones:
		var track_type := Animation.TYPE_POSITION_3D if bone == "Root" else Animation.TYPE_ROTATION_3D
		var track := animation.add_track(track_type)
		animation.track_set_path(track, NodePath("Skeleton3D:" + bone))
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		tracks[bone] = track
	var samples := int(round(length * BAKE_FPS))
	for i in samples + 1:
		var t := minf(i / BAKE_FPS, length)
		var state := _interpolate(keys, t, length, loop)
		var globals := _pose_globals(state["Right"], state["Left"], state["root"])
		for bone in bones:
			var track: int = tracks[bone]
			if bone == "Root":
				animation.position_track_insert_key(track, t, state["root"])
				continue
			var parent_global: Transform3D = globals[_parent_of(bone)]
			var local := (parent_global.basis.inverse() * (globals[bone] as Transform3D).basis).orthonormalized()
			animation.rotation_track_insert_key(track, t, local.get_rotation_quaternion())
	animation.set_meta(&"events", events)
	animation.set_meta(&"hold_time", hold_time)
	return animation


## Interpola os quadros-chave de autoria: cúbica para posição e fechamento,
## esférica cúbica para orientação; cíclica em animações em loop.
func _interpolate(keys: Array, t: float, length: float, loop: bool) -> Dictionary:
	var count := keys.size()
	if count == 1:
		return keys[0]
	var index := count - 1
	for i in count:
		if keys[i]["t"] > t:
			index = i - 1
			break
	var i0 := index
	var i1 := index + 1
	var t0: float
	var t1: float
	if index < 0:
		if not loop:
			return keys[0]
		i0 = count - 1
		i1 = 0
		t0 = keys[count - 1]["t"] - length
		t1 = keys[0]["t"]
	elif i1 >= count:
		if not loop:
			return keys[count - 1]
		i1 = 0
		t0 = keys[i0]["t"]
		t1 = keys[0]["t"] + length
	else:
		t0 = keys[i0]["t"]
		t1 = keys[i1]["t"]
	var weight := 0.0 if is_equal_approx(t0, t1) else clampf((t - t0) / (t1 - t0), 0.0, 1.0)
	var i_pre := (i0 - 1 + count) % count if loop else maxi(i0 - 1, 0)
	var i_post := (i1 + 1) % count if loop else mini(i1 + 1, count - 1)
	var result := {"t": t, "root": (keys[i0]["root"] as Vector3).cubic_interpolate(
			keys[i1]["root"], keys[i_pre]["root"], keys[i_post]["root"], weight)}
	for side in SIDES:
		var a: Dictionary = keys[i0][side]
		var b: Dictionary = keys[i1][side]
		var pre: Dictionary = keys[i_pre][side]
		var post: Dictionary = keys[i_post][side]
		var position := (a["p"] as Vector3).cubic_interpolate(b["p"], pre["p"], post["p"], weight)
		var rotation := _quat(a).spherical_cubic_interpolate(_quat(b), _quat(pre), _quat(post), weight)
		var grip := clampf(cubic_interpolate(a["g"], b["g"], pre["g"], post["g"], weight), 0.0, 1.0)
		var euler := rotation.get_euler()
		result[side] = {"p": position, "e": Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)), "g": grip}
	return result


func _quat(hand: Dictionary) -> Quaternion:
	return _hand_basis(hand).get_rotation_quaternion()


# =============================================================================
# Esqueleto e malha
# =============================================================================

func _rest_globals() -> Dictionary:
	var ready := _hand(Vector3(0.165, -0.262, -0.32), Vector3(-18.0, 10.0, -28.0), 0.35)
	_current_animation = "rest"
	return _pose_globals(ready, _mirror(ready), Vector3.ZERO)


func _build_skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	var globals := _rest_globals()
	for bone_name in _all_bone_names():
		var index := skeleton.add_bone(bone_name)
		var parent_name := _parent_of(bone_name)
		var local: Transform3D = globals[bone_name]
		if not parent_name.is_empty():
			skeleton.set_bone_parent(index, skeleton.find_bone(parent_name))
			local = (globals[parent_name] as Transform3D).affine_inverse() * local
		skeleton.set_bone_rest(index, local)
	skeleton.reset_bone_poses()
	return skeleton


class MeshBuilder:
	var tool := SurfaceTool.new()
	var count := 0

	func _init() -> void:
		tool.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	func vertex(position: Vector3, uv: Vector2, bones: Array, weights: Array) -> int:
		var b := PackedInt32Array([0, 0, 0, 0])
		var w := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		var total := 0.0
		for i in bones.size():
			b[i] = bones[i]
			w[i] = weights[i]
			total += weights[i]
		for i in 4:
			w[i] /= total
		tool.set_uv(uv)
		tool.set_bones(b)
		tool.set_weights(w)
		tool.add_vertex(position)
		count += 1
		return count - 1

	## Recebe os vértices em sentido anti-horário (vistos de fora) e grava em
	## sentido horário, que é a face da frente no Godot.
	func triangle(a: int, b: int, c: int) -> void:
		tool.add_index(a)
		tool.add_index(c)
		tool.add_index(b)


## Tubo ao longo do eixo -Z de um osso. Os pesos se misturam com o osso pai no
## início e com o filho no fim (articulações suaves).
func _tube(builder: MeshBuilder, frame: Transform3D, z_from: float, z_to: float, r_from: float,
		r_to: float, rings: int, sides: int, bone: int, start_bone: int, start_blend: float,
		end_bone: int, end_blend: float, offset: Vector3 = Vector3.ZERO, flatten: float = 1.0,
		cap: bool = false) -> void:
	var first := builder.count
	for ring in rings + 1:
		var u := float(ring) / rings
		var z := lerpf(z_from, z_to, u)
		var radius := lerpf(r_from, r_to, u)
		var bones := [bone]
		var weights := [1.0]
		if start_bone >= 0 and u < start_blend:
			var w := 0.5 * (1.0 - u / start_blend)
			bones.append(start_bone)
			weights.append(w)
			weights[0] -= w
		if end_bone >= 0 and u > 1.0 - end_blend:
			var w := 0.5 * (u - (1.0 - end_blend)) / end_blend
			bones.append(end_bone)
			weights.append(w)
			weights[0] -= w
		for side in sides:
			var angle := TAU * side / sides
			var local := offset + Vector3(cos(angle) * radius, sin(angle) * radius * flatten, z)
			builder.vertex(frame * local, Vector2(float(side) / sides, u), bones, weights)
	for ring in rings:
		for side in sides:
			var a := first + ring * sides + side
			var b := first + ring * sides + (side + 1) % sides
			var c := a + sides
			var d := b + sides
			builder.triangle(a, c, b)
			builder.triangle(b, c, d)
	if cap:
		var tip := builder.vertex(frame * (offset + Vector3(0.0, 0.0, z_to - r_to * 0.8)), Vector2(0.5, 1.0), [bone], [1.0])
		var last := first + rings * sides
		for side in sides:
			builder.triangle(last + side, tip, last + (side + 1) % sides)


func _box(builder: MeshBuilder, frame: Transform3D, min_corner: Vector3, max_corner: Vector3, bone: int) -> void:
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	var center := (min_corner + max_corner) * 0.5
	var half := (max_corner - min_corner) * 0.5
	for face in faces:
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var corners := []
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var local: Vector3 = center + (n + u * c.x + v * c.y) * half
			corners.append(builder.vertex(frame * local, (c + Vector2.ONE) * 0.5, [bone], [1.0]))
		builder.triangle(corners[0], corners[1], corners[2])
		builder.triangle(corners[0], corners[2], corners[3])


func _build_mesh(skeleton: Skeleton3D) -> ArrayMesh:
	var sleeve := MeshBuilder.new()
	var skin := MeshBuilder.new()
	var rest := _rest_globals()
	for side in SIDES:
		var s: float = SIDES[side]
		var upper := skeleton.find_bone(side + "UpperArm")
		var lower := skeleton.find_bone(side + "LowerArm")
		var hand := skeleton.find_bone(side + "Hand")
		var g_upper: Transform3D = rest[side + "UpperArm"]
		var g_lower: Transform3D = rest[side + "LowerArm"]
		var g_hand: Transform3D = rest[side + "Hand"]
		# Mangas da jaqueta, com punho mais largo.
		_tube(sleeve, g_upper, 0.04, -UPPER_LEN, 0.058, 0.047, 5, 12, upper, -1, 0.0, lower, 0.18)
		_tube(sleeve, g_lower, 0.0, -(FORE_LEN - 0.045), 0.047, 0.038, 5, 12, lower, upper, 0.2, -1, 0.0)
		_tube(sleeve, g_lower, -(FORE_LEN - 0.050), -(FORE_LEN - 0.006), 0.043, 0.043, 1, 12, lower, -1, 0.0, -1, 0.0)
		_tube(sleeve, g_lower, -(FORE_LEN - 0.006), -(FORE_LEN - 0.004), 0.043, 0.030, 1, 12, lower, -1, 0.0, -1, 0.0)
		# Pulso e mão (pele).
		_tube(skin, g_lower, -(FORE_LEN - 0.030), -(FORE_LEN + 0.004), 0.028, 0.026, 3, 10, lower, -1, 0.0, hand, 0.9, Vector3.ZERO, 0.8)
		_box(skin, g_hand, Vector3(-0.039, -0.013, -HAND_LEN - 0.002), Vector3(0.039, 0.013, 0.004), hand)
		# Dedos: indicador e médio têm ossos próprios; anelar e mínimo seguem o médio.
		var fingers := [
			["Index", Vector3.ZERO, 0.0095, 1.0],
			["Middle", Vector3.ZERO, 0.0100, 1.08],
			["Middle", Vector3(0.017 * s, -0.002, 0.004), 0.0095, 0.98],
			["Middle", Vector3(0.032 * s, -0.004, 0.010), 0.0085, 0.80],
		]
		for finger in fingers:
			var proximal := skeleton.find_bone(side + finger[0] + "Proximal")
			var intermediate := skeleton.find_bone(side + finger[0] + "Intermediate")
			var g_proximal: Transform3D = rest[side + finger[0] + "Proximal"]
			var g_intermediate: Transform3D = rest[side + finger[0] + "Intermediate"]
			var radius: float = finger[2]
			var scale: float = finger[3]
			_tube(skin, g_proximal, 0.006, -FINGER_PROX * scale, radius * 1.05, radius, 2, 8, proximal, hand, 0.35, intermediate, 0.25, finger[1], 0.85)
			_tube(skin, g_intermediate, FINGER_PROX * (1.0 - scale), -FINGER_INTER * scale + FINGER_PROX * (1.0 - scale), radius, radius * 0.88, 2, 8, intermediate, proximal, 0.3, -1, 0.0, finger[1], 0.85, true)
		var thumb_1 := skeleton.find_bone(side + "ThumbProximal")
		var thumb_2 := skeleton.find_bone(side + "ThumbDistal")
		_tube(skin, rest[side + "ThumbProximal"], 0.010, -THUMB_PROX, 0.014, 0.0115, 2, 8, thumb_1, hand, 0.45, thumb_2, 0.25, Vector3.ZERO, 0.85)
		_tube(skin, rest[side + "ThumbDistal"], 0.0, -THUMB_DIST, 0.0115, 0.0100, 2, 8, thumb_2, thumb_1, 0.3, -1, 0.0, Vector3.ZERO, 0.85, true)

	var mesh := ArrayMesh.new()
	for part in [[sleeve, _material(Color(0.27, 0.27, 0.19), 0.88, 0.07, 0.14)],
			[skin, _material(Color(0.66, 0.49, 0.39), 0.62, 0.0, 0.08)]]:
		var builder: MeshBuilder = part[0]
		builder.tool.generate_normals()
		builder.tool.set_material(part[1])
		builder.tool.commit(mesh)
	return mesh


func _material(color: Color, roughness: float, weave: float, grime: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("roughness_value", roughness)
	material.set_shader_parameter("weave_strength", weave)
	material.set_shader_parameter("grime_strength", grime)
	return material


# =============================================================================
# Cena
# =============================================================================

func _build_scene(skeleton: Skeleton3D, mesh: ArrayMesh, library: AnimationLibrary) -> int:
	var root := Node3D.new()
	root.name = "FPArms"
	if ResourceLoader.exists(ANIMATOR_SCRIPT):
		root.set_script(load(ANIMATOR_SCRIPT))
	root.add_child(skeleton)
	skeleton.owner = root

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "ArmsMesh"
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Os braços se movem muito em relação à pose de repouso: AABB generosa
	# evita que sejam descartados pelo frustum culling.
	mesh_instance.custom_aabb = AABB(Vector3(-0.8, -1.0, -1.0), Vector3(1.6, 1.6, 1.6))
	skeleton.add_child(mesh_instance)
	mesh_instance.owner = root
	mesh_instance.skeleton = NodePath("..")
	mesh_instance.skin = skeleton.create_skin_from_rest_transforms()

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", library)
	root.add_child(player)
	player.owner = root
	if root.get_script() != null:
		root.set("skeleton", skeleton)
		root.set("animation_player", player)

	var packed := PackedScene.new()
	var error := packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, SCENE_PATH)
	root.free()
	return error
