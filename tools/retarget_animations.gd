extends SceneTree
## Ferramenta de produção: retarget das bibliotecas de animação Quaternius
## (UAL 1 e UAL 2, CC0) para o esqueleto do sobrevivente (Universal Base
## Characters, CC0).
##
## Uso:
##   1. Baixe as fontes (veja ASSET_LICENSES.md) e coloque em assets/_source/:
##      - AL_Standard.fbx    (UAL 1, pasta "Unreal Engine" do pacote Standard)
##      - UAL2_Standard.glb  (UAL 2, pasta "Unreal-Godot" do pacote Standard)
##   2. godot --headless --path . --import
##   3. godot --headless --path . --script res://tools/retarget_animations.gd
##
## Método: para cada quadro, a rotação global de cada osso da fonte é
## convertida em "rotação em relação ao repouso" no espaço do mundo
## (D = G_fonte · G_fonte_repouso⁻¹), mudada de base para o espaço do alvo e
## aplicada sobre o repouso do alvo (G_alvo = C·D·C⁻¹ · G_alvo_repouso).
## Isso independe da orientação de eixos de cada osso (a UAL 1 em FBX usa
## eixos diferentes do personagem) e preserva a pose física. O deslocamento
## da pélvis é escalado pela razão entre as alturas de pélvis.
##
## Poses de referência diferentes (o personagem está em T, as fontes não):
## antes do retarget, cada osso do alvo é girado no espaço do mundo até ficar
## com a mesma direção que o osso da fonte tem na pose de repouso dela
## (alinhamento de poses). O delta da fonte é aplicado sobre essa pose
## alinhada, e não sobre o T, senão os braços sairiam 45° mais altos.

## Esqueleto do personagem: o modelo do sobrevivente enviado pelo dono do
## projeto (convenção Mixamo, em T). Os ossos são renomeados para os nomes do
## jogo (tools/rig_names.gd). Ver tools/build_survivor.gd.
const TARGET_SCENE := "res://assets/characters/survivor/Sobrevivente.fbx"
const RigNames := preload("res://tools/rig_names.gd")
## Filho que define a direção de cada osso no alinhamento de poses.
const PREFERRED_CHILD := {"pelvis": "spine_01", "spine_03": "neck_01", "hand_l": "middle_01_l", "hand_r": "middle_01_r"}
const OUTPUT := "res://resources/animations/survivor_body.res"
const FPS := 30.0
## Caminho das trilhas no personagem (relativo ao nó raiz do modelo).
const TARGET_SKELETON_PATH := "Armature/Skeleton3D"

## Ciclos de marcha: medidos para sincronizar com a passada física.
const GAIT_CLIPS := ["walk", "jog", "sprint", "crouch_walk", "walk_carry"]
## Golpes e gestos: o quadro de maior extensão do braço vira evento.
const REACH_EVENTS := {"punch_jab": "hit", "punch_cross": "hit", "punch_hook": "hit",
		"weapon_swing_a": "hit", "weapon_swing_b": "hit",
		"interact": "contact", "pickup": "contact", "open_container": "contact"}

## [arquivo fonte, nome na fonte, nome no jogo, em loop]
const CLIPS := [
	["res://assets/_source/AL_Standard.fbx", "Rig|Idle", "idle", true],
	["res://assets/_source/AL_Standard.fbx", "Rig|Walk", "walk", true],
	["res://assets/_source/AL_Standard.fbx", "Rig|Jog_Fwd", "jog", true],
	["res://assets/_source/AL_Standard.fbx", "Rig|Sprint", "sprint", true],
	["res://assets/_source/AL_Standard.fbx", "Rig|Crouch_Idle", "crouch_idle", true],
	["res://assets/_source/AL_Standard.fbx", "Rig|Crouch_Fwd", "crouch_walk", true],
	["res://assets/_source/AL_Standard.fbx", "Rig|Jump_Start", "jump_start", false],
	["res://assets/_source/AL_Standard.fbx", "Rig|Jump", "fall", true],
	["res://assets/_source/AL_Standard.fbx", "Rig|Jump_Land", "land", false],
	["res://assets/_source/AL_Standard.fbx", "Rig|Punch_Jab", "punch_jab", false],
	["res://assets/_source/AL_Standard.fbx", "Rig|Punch_Cross", "punch_cross", false],
	["res://assets/_source/AL_Standard.fbx", "Rig|Hit_Chest", "hit_chest", false],
	["res://assets/_source/AL_Standard.fbx", "Rig|Hit_Head", "hit_head", false],
	["res://assets/_source/AL_Standard.fbx", "Rig|Interact", "interact", false],
	["res://assets/_source/AL_Standard.fbx", "Rig|PickUp_Table", "pickup", false],
	["res://assets/_source/AL_Standard.fbx", "Rig|Push", "push", true],
	["res://assets/_source/AL_Standard.fbx", "Rig|Death01", "death", false],
	["res://assets/_source/UAL2_Standard.glb", "Melee_Hook", "punch_hook", false],
	["res://assets/_source/UAL2_Standard.glb", "Hit_Knockback", "hit_knockback", false],
	["res://assets/_source/UAL2_Standard.glb", "LayToIdle", "get_up", false],
	["res://assets/_source/UAL2_Standard.glb", "Consume", "consume", false],
	["res://assets/_source/UAL2_Standard.glb", "Chest_Open", "open_container", false],
	["res://assets/_source/UAL2_Standard.glb", "Walk_Carry", "walk_carry", true],
	# Recuperação do gancho: termina com os dois punhos diante do rosto, a
	# guarda de defesa (o quadro final é a pose de bloqueio).
	["res://assets/_source/UAL2_Standard.glb", "Melee_Hook_Rec", "punch_hook_recover", false],
	# Impacto recebido na defesa (tronco recua; usado só da cintura para cima).
	["res://assets/_source/UAL2_Standard.glb", "Sword_Block", "block_impact", false],
	# Armas brancas (etapa 7): golpe rápido (A) e golpe amplo carregado (B,
	# segura na preparação), e a postura de arma empunhada. TreeChopping foi
	# avaliado e descartado: é um laço de cortar lenha, o impacto fica na
	# emenda do ciclo e não serve como golpe único. O 5º campo congela a pose
	# a partir desse tempo: os golpes de espada terminam erguendo a lâmina de
	# novo (pronto para o próximo); com machado ou taco o corpo fica no fim do
	# golpe e volta à postura pela transição.
	["res://assets/_source/UAL2_Standard.glb", "Sword_Regular_A", "weapon_swing_a", false, 0.255],
	["res://assets/_source/UAL2_Standard.glb", "Sword_Regular_B", "weapon_swing_b", false, 0.28],
	["res://assets/_source/AL_Standard.fbx", "Rig|Sword_Idle", "weapon_idle", true],
]


## Mantém a pose de `time` até o fim da animação (sem mudar a duração).
static func _freeze_after(animation: Animation, time: float) -> void:
	for track in animation.get_track_count():
		var type := animation.track_get_type(track)
		var value: Variant = null
		match type:
			Animation.TYPE_POSITION_3D:
				value = animation.position_track_interpolate(track, time)
			Animation.TYPE_ROTATION_3D:
				value = animation.rotation_track_interpolate(track, time)
			Animation.TYPE_SCALE_3D:
				value = animation.scale_track_interpolate(track, time)
			_:
				continue
		for key in range(animation.track_get_key_count(track) - 1, -1, -1):
			if animation.track_get_key_time(track, key) >= time:
				animation.track_remove_key(track, key)
		animation.track_insert_key(track, time, value)


class Rig:
	var skeleton: Skeleton3D
	var player: AnimationPlayer
	var prefix: String
	var global_rest: Array[Transform3D] = []
	var change_of_basis: Basis = Basis.IDENTITY
	## Pose de referência do ALVO alinhada a esta fonte (bases globais).
	var target_reference: Array[Basis] = []

	func _init(root: Node) -> void:
		skeleton = Rig.find(root, "Skeleton3D")
		player = Rig.find(root, "AnimationPlayer")
		if player != null:
			prefix = String(player.get_node(player.root_node).get_path_to(skeleton))
		for bone in skeleton.get_bone_count():
			global_rest.append(skeleton.get_bone_global_rest(bone))

	static func find(node: Node, type: String) -> Node:
		if node.is_class(type):
			return node
		for child in node.get_children():
			var found := Rig.find(child, type)
			if found != null:
				return found
		return null

	func bone_position(bone_name: String) -> Vector3:
		return global_rest[skeleton.find_bone(bone_name)].origin

	## Base anatômica: x = ombro esquerdo→direito, y = pélvis→cabeça.
	func anatomical_basis() -> Basis:
		var up := (bone_position("Head") - bone_position("pelvis")).normalized()
		var right := (bone_position("upperarm_r") - bone_position("upperarm_l"))
		right = (right - up * right.dot(up)).normalized()
		return Basis(right, up, right.cross(up).normalized())


var _target: Rig
var _sources: Dictionary = {}


func _initialize() -> void:
	var target_root: Node = (load(TARGET_SCENE) as PackedScene).instantiate()
	RigNames.rename_skeleton(Rig.find(target_root, "Skeleton3D"))
	_target = Rig.new(target_root)
	var library := AnimationLibrary.new()
	for clip in CLIPS:
		var source := _source(clip[0])
		if not source.player.has_animation(clip[1]):
			push_error("Animação %s não encontrada em %s" % [clip[1], clip[0]])
			quit(1)
			return
		var animation := _retarget(source, source.player.get_animation(clip[1]), clip[3])
		if clip.size() > 4:
			_freeze_after(animation, clip[4])
		var report := _analyze(clip[2], animation)
		library.add_animation(clip[2], animation)
		print("  %-16s <- %-20s %.2f s %s" % [clip[2], clip[1], animation.length, report])
	var error := ResourceSaver.save(library, OUTPUT)
	print("Biblioteca salva em %s: %s (%d animações)" % [OUTPUT, error_string(error), library.get_animation_list().size()])
	quit(0 if error == OK else 1)


func _source(path: String) -> Rig:
	if not _sources.has(path):
		var root: Node = (load(path) as PackedScene).instantiate()
		var rig := Rig.new(root)
		# Mudança de base: alinha os eixos anatômicos da fonte aos do alvo.
		rig.change_of_basis = _target.anatomical_basis() * rig.anatomical_basis().inverse()
		rig.target_reference = _align_target(rig)
		_sources[path] = rig
	return _sources[path]


## Pose do alvo com cada osso na direção que o osso correspondente tem na
## pose de repouso da fonte (rotação mínima, preservando a torção do alvo).
func _align_target(source: Rig) -> Array[Basis]:
	var skeleton := _target.skeleton
	var src := source.skeleton
	var count := skeleton.get_bone_count()
	var alignment: Array[Basis] = []
	alignment.resize(count)
	var result: Array[Basis] = []
	result.resize(count)
	for bone in count:
		var parent := skeleton.get_bone_parent(bone)
		var inherited := alignment[parent] if parent >= 0 else Basis.IDENTITY
		alignment[bone] = inherited
		var bone_name := skeleton.get_bone_name(bone)
		var src_bone := src.find_bone(bone_name)
		var child := _direction_child(skeleton, bone, src)
		if src_bone >= 0 and child >= 0:
			var src_child := src.find_bone(skeleton.get_bone_name(child))
			var target_direction := (_target.global_rest[child].origin - _target.global_rest[bone].origin).normalized()
			var source_direction := (source.change_of_basis * (source.global_rest[src_child].origin - source.global_rest[src_bone].origin)).normalized()
			alignment[bone] = Basis(_arc(target_direction, source_direction))
		result[bone] = (alignment[bone] * _target.global_rest[bone].basis.orthonormalized()).orthonormalized()
	return result


func _direction_child(skeleton: Skeleton3D, bone: int, src: Skeleton3D) -> int:
	var preferred: String = PREFERRED_CHILD.get(skeleton.get_bone_name(bone), "")
	var fallback := -1
	for child in skeleton.get_bone_children(bone):
		var child_name := skeleton.get_bone_name(child)
		if src.find_bone(child_name) < 0:
			continue
		if child_name == preferred:
			return child
		if fallback < 0:
			fallback = child
	return fallback


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var axis := from.cross(to)
	if axis.length_squared() < 0.0000001:
		return Quaternion.IDENTITY
	return Quaternion(axis.normalized(), acos(clampf(from.dot(to), -1.0, 1.0)))


func _retarget(source: Rig, animation: Animation, loop: bool) -> Animation:
	var src_skeleton := source.skeleton
	var dst_skeleton := _target.skeleton
	var bone_count := dst_skeleton.get_bone_count()
	var c := source.change_of_basis
	var c_inv := c.inverse()
	var src_pelvis := src_skeleton.find_bone("pelvis")
	var dst_pelvis := dst_skeleton.find_bone("pelvis")
	var height_ratio := _target.global_rest[dst_pelvis].origin.y / (c * source.global_rest[src_pelvis].origin).y

	# Trilhas da fonte por osso.
	var rotation_tracks := {}
	var position_tracks := {}
	for track in animation.get_track_count():
		var bone := src_skeleton.find_bone(animation.track_get_path(track).get_concatenated_subnames())
		if bone < 0:
			continue
		match animation.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				rotation_tracks[bone] = track
			Animation.TYPE_POSITION_3D:
				position_tracks[bone] = track

	var result := Animation.new()
	result.length = animation.length
	result.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var dst_tracks := {}
	for bone in bone_count:
		var bone_name := dst_skeleton.get_bone_name(bone)
		if bone_name == "root" or src_skeleton.find_bone(bone_name) < 0:
			continue
		var track := result.add_track(Animation.TYPE_ROTATION_3D)
		result.track_set_path(track, NodePath(TARGET_SKELETON_PATH + ":" + bone_name))
		dst_tracks[bone] = track
	var pelvis_track := result.add_track(Animation.TYPE_POSITION_3D)
	result.track_set_path(pelvis_track, NodePath(TARGET_SKELETON_PATH + ":pelvis"))

	var samples := int(ceil(animation.length * FPS))
	_samples.clear()
	var src_global: Array[Transform3D] = []
	src_global.resize(src_skeleton.get_bone_count())
	var dst_global: Array[Basis] = []
	dst_global.resize(bone_count)
	for i in samples + 1:
		var t := minf(i / FPS, animation.length)
		# Pose global da fonte (hierarquia aplicada em ordem de pais).
		for bone in src_skeleton.get_bone_count():
			var rest := src_skeleton.get_bone_rest(bone)
			var local := Transform3D(rest)
			if rotation_tracks.has(bone):
				local.basis = Basis(animation.rotation_track_interpolate(rotation_tracks[bone], t))
			if position_tracks.has(bone):
				local.origin = animation.position_track_interpolate(position_tracks[bone], t)
			var parent := src_skeleton.get_bone_parent(bone)
			src_global[bone] = local if parent < 0 else src_global[parent] * local
		# Rotação global de cada osso do alvo.
		for bone in bone_count:
			var bone_name := dst_skeleton.get_bone_name(bone)
			var src_bone := src_skeleton.find_bone(bone_name)
			var dst_rest := source.target_reference[bone]
			if src_bone < 0 or bone_name == "root":
				var parent := dst_skeleton.get_bone_parent(bone)
				var local_rest := dst_skeleton.get_bone_rest(bone).basis.orthonormalized()
				dst_global[bone] = local_rest if parent < 0 else dst_global[parent] * local_rest
				continue
			var delta := src_global[src_bone].basis.orthonormalized() * source.global_rest[src_bone].basis.orthonormalized().inverse()
			dst_global[bone] = (c * delta * c_inv) * dst_rest
		for bone in dst_tracks:
			var parent := dst_skeleton.get_bone_parent(bone)
			var local := dst_global[bone] if parent < 0 else dst_global[parent].inverse() * dst_global[bone]
			result.rotation_track_insert_key(dst_tracks[bone], t, local.orthonormalized().get_rotation_quaternion())
		# Pélvis: deslocamento em relação ao repouso, na base do alvo e na escala do alvo.
		var offset := c * (src_global[src_pelvis].origin - source.global_rest[src_pelvis].origin) * height_ratio
		var pelvis_global := _target.global_rest[dst_pelvis].origin + offset
		var pelvis_parent := dst_skeleton.get_bone_parent(dst_pelvis)
		var local_position := pelvis_global if pelvis_parent < 0 else _target.global_rest[pelvis_parent].affine_inverse() * pelvis_global
		result.position_track_insert_key(pelvis_track, t, local_position)
		_record_sample(t, dst_global, local_position)
	return result


# --- Análise (velocidade nativa, contato do pé, quadro de golpe) -------------

var _samples: Array = []


## Posições globais de pés, mãos e tronco no espaço do esqueleto alvo.
func _record_sample(t: float, rotations: Array[Basis], pelvis_local: Vector3) -> void:
	var skeleton := _target.skeleton
	var origins: Array[Vector3] = []
	origins.resize(skeleton.get_bone_count())
	var pelvis := skeleton.find_bone("pelvis")
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		var local_origin := pelvis_local if bone == pelvis else skeleton.get_bone_rest(bone).origin
		origins[bone] = local_origin if parent < 0 else origins[parent] + rotations[parent] * local_origin
	var sample := {"t": t}
	for name in ["ball_l", "ball_r", "foot_l", "hand_l", "hand_r", "spine_03"]:
		sample[name] = origins[skeleton.find_bone(name)]
	_samples.append(sample)


func _analyze(anim_name: String, animation: Animation) -> String:
	if anim_name in GAIT_CLIPS:
		# Contato do calcanhar esquerdo: pé esquerdo mais à frente (+Z no modelo).
		var contact := 0.0
		var forward := -INF
		var lowest := INF
		for sample in _samples:
			if (sample["foot_l"] as Vector3).z > forward:
				forward = (sample["foot_l"] as Vector3).z
				contact = sample["t"]
			lowest = minf(lowest, (sample["ball_l"] as Vector3).y)
		# Velocidade nativa: em cada pé, a janela contínua mais longa em que ele
		# está baixo (apoio); a velocidade é o deslocamento para trás dividido
		# pela duração da janela. Média dos dois pés.
		var foot_speeds: Array[float] = []
		for foot in ["ball_l", "ball_r"]:
			var floor_y := INF
			for sample in _samples:
				floor_y = minf(floor_y, (sample[foot] as Vector3).y)
			var best_len := 0
			var best_speed := 0.0
			var run_start := -1
			for i in _samples.size() + 1:
				var low := i < _samples.size() and (_samples[i][foot] as Vector3).y < floor_y + 0.035
				if low and run_start < 0:
					run_start = i
				elif not low and run_start >= 0:
					var run_end := i - 1
					if run_end - run_start > best_len:
						best_len = run_end - run_start
						var dz: float = (_samples[run_start][foot] as Vector3).z - (_samples[run_end][foot] as Vector3).z
						best_speed = dz / (float(_samples[run_end]["t"]) - float(_samples[run_start]["t"]))
					run_start = -1
			if best_len >= 1:
				foot_speeds.append(best_speed)
		var speed := 0.0
		for v in foot_speeds:
			speed += v / foot_speeds.size()
		var stride: float = speed * animation.length * 0.5
		# Verificação cruzada: distância entre os pés no contato do calcanhar.
		var spread := 0.0
		for sample in _samples:
			if is_equal_approx(float(sample["t"]), contact):
				spread = (sample["foot_l"] as Vector3).z - ((sample["ball_r"] as Vector3).z - 0.12)
		animation.set_meta(&"foot_spread", spread)
		# Se os dois métodos divergem (fase de voo da corrida), vale a medida
		# direta do afastamento dos pés.
		if spread > 0.1 and absf(stride - spread) > 0.4 * spread:
			stride = spread
		elif spread > 0.1:
			stride = (stride + spread) * 0.5
		speed = stride * 2.0 / animation.length
		animation.set_meta(&"left_contact", contact / animation.length)
		animation.set_meta(&"ground_speed", speed)
		animation.set_meta(&"stride", stride)
		return "contato esq. %.2f, velocidade %.2f m/s, passo %.2f m (pés afastados %.2f m no contato)" % [contact / animation.length, speed, stride, spread]
	if REACH_EVENTS.has(anim_name):
		var best := 0.0
		var best_t := 0.0
		var hand := "hand_r"
		# Socos: o quadro de maior extensão do braço. Armas: o braço passa
		# pela maior extensão também na preparação (atrás do corpo), então o
		# golpe é o quadro em que a mão está mais à frente do peito (+Z).
		var weapon := anim_name.begins_with("weapon_")
		for side in (["hand_r"] if weapon else ["hand_l", "hand_r"]):
			for sample in _samples:
				var offset := (sample[side] as Vector3) - (sample["spine_03"] as Vector3)
				var reach := offset.z if weapon else offset.length()
				if reach > best:
					best = reach
					best_t = sample["t"]
					hand = side
		animation.set_meta(&"events", {REACH_EVENTS[anim_name]: best_t})
		animation.set_meta(&"hand", hand)
		# Golpes carregados: seguram no meio da preparação.
		animation.set_meta(&"hold_time", best_t * 0.55 if anim_name in ["punch_hook", "weapon_swing_b"] else -1.0)
		return "evento %s em %.2f s (%s, alcance %.2f m)" % [REACH_EVENTS[anim_name], best_t, hand, best]
	return ""
