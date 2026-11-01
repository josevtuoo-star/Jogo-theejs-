extends Node3D
## Equipamento do personagem (filho do player):
## - roupa (jaqueta de lona, camisa xadrez, calça jeans, cinto, botas, luvas sem dedos e gorro),
##   pintada no próprio manequim por região do corpo e com tecido/sujeira no shader;
## - mochila nas costas e lugares no corpo onde cada item fica pendurado (costas, cinto,
##   laterais, embaixo e em cima da mochila) ou guardado dentro dela. Nada some: o item vai da
##   mão até o lugar dele e continua visível;
## - peso: cada item pesa; o total deixa o personagem mais lento, cansa mais e pula menos;
## - movimentos com IK nos braços: abaixar e pegar do chão/mesa, olhar o item, levar até o
##   lugar (por cima do ombro para as costas/mochila, para o quadril no cinto), largar, sacar
##   a arma das costas e segurar com as duas mãos, guardar de volta;
## - física secundária: mochila e itens pendurados balançam com o corpo (molas/pêndulos).

signal changed

const BACKPACK_KG := 1.6
const MAX_KG := 40.0
## posições no modelo (olha para +Z; +X é a esquerda do personagem; altura em metros)
const BP_PIVOT := Vector3(0.0, 1.45, -0.17)
const BP_MODEL := Vector3(0.0, 0.8, -0.3)
const BP_SCALE := 0.8

var player: CharacterBody3D
var body: Node # procedural_body.gd
var skel: Skeleton3D
var model: Node3D

## inventário: {id, node (Node3D com o centro do item na origem), slot}
var items: Array = []
## arma nas mãos (mesmo formato) ou {}
var held := {}
var weight := 0.0
var busy := false

var _slots := {} # nome -> Node3D (pivô)
var _slot_info := {} # nome -> {"modo": "centro"|"pendurado"|"apoiado", "mola": float}
var _pivots := [] # [{node, rest: Basis, ang: Vector2, vel: Vector2, prev: Vector3, pv: Vector3, k, frac, lim}]
var _bp: Node3D # modelo da mochila
var _bp_pivot: Node3D
var _attach := {}
var _rel := Transform3D() # esqueleto -> modelo

# sequência em andamento
var _seq := ""
var _t := 0.0
var _it := {}
var _start_xf := Transform3D()
var _mid_xf := Transform3D()
var _item_in_hand := Transform3D()
var _hand_att: BoneAttachment3D
var _bend_target := 0.0
var _src: RigidBody3D
var _queued: Node3D
var _grabbed := false
var _done_store := false
var _drop_vel := Vector3.ZERO

# arma nas mãos
var _aim_lag := Vector2.ZERO
var _aim_vel := Vector2.ZERO
var _last_aim := Vector2.ZERO
var _ready_amt := 0.0
var _hold_amt := 0.0
var _snd: AudioStreamPlayer3D


func setup(p: CharacterBody3D, sk: Skeleton3D, b: Node, m: Node3D) -> void:
	player = p
	skel = sk
	body = b
	model = m
	_rel = model.global_transform.affine_inverse() * skel.global_transform
	_dress()
	_build_slots()
	_hand_att = _attach_to("hand_r")
	_snd = AudioStreamPlayer3D.new()
	_snd.bus = "Mundo"
	_snd.unit_size = 4.0
	_snd.max_polyphony = 3
	_snd.position = Vector3.UP * 1.2
	p.add_child(_snd)
	_update_weight()


# ================================================================== roupa

func _dress() -> void:
	var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	var src := mi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/roupa.gdshader")
	var names := []
	for i in skel.get_bone_count():
		names.append(skel.get_bone_name(i))
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(verts.size(), 1)
		var cols := PackedColorArray()
		cols.resize(verts.size())
		var rest := PackedFloat32Array()
		rest.resize(verts.size() * 4)
		for v in verts.size():
			var best := 0
			var bw := -1.0
			for k in per:
				if wts[v * per + k] > bw:
					bw = wts[v * per + k]
					best = bones[v * per + k]
			var bn: String = names[best] if best < names.size() else ""
			var p := verts[v]
			cols[v] = _cloth(bn, p)
			rest[v * 4] = p.x
			rest[v * 4 + 1] = p.y
			rest[v * 4 + 2] = p.z
			rest[v * 4 + 3] = 0.0
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_CUSTOM0] = rest
		var flags := src.surface_get_format(s) & ~Mesh.ARRAY_FORMAT_CUSTOM0
		flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		out.surface_set_material(s, mat)
	mi.mesh = out
	# gorro de lã
	var hat := MeshInstance3D.new()
	hat.name = "Gorro"
	var sm := SphereMesh.new()
	sm.radius = 0.112
	sm.height = 0.125
	sm.is_hemisphere = true
	sm.radial_segments = 20
	sm.rings = 6
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.17, 0.18, 0.15)
	hm.roughness = 1.0
	sm.material = hm
	hat.mesh = sm
	var head := _attach_to("Head")
	head.add_child(hat)
	hat.transform = _local_for("Head", Transform3D(Basis().scaled(Vector3(1.0, 1.05, 1.1)), Vector3(0.0, 1.715, -0.01)))
	var cuff := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.112
	tm.bottom_radius = 0.114
	tm.height = 0.035
	tm.radial_segments = 20
	tm.material = hm
	cuff.mesh = tm
	head.add_child(cuff)
	cuff.transform = _local_for("Head", Transform3D(Basis().scaled(Vector3(1.0, 1.0, 1.1)), Vector3(0.0, 1.725, -0.01)))


## Cor da roupa (rgb) e tipo de tecido (alfa) de cada parte do corpo.
## alfa: 0 pele, 0,2 jeans, 0,4 lona, 0,55 xadrez, 0,7 couro, 0,9 metal
func _cloth(bn: String, p: Vector3) -> Color:
	var skin := Color(0.6, 0.44, 0.35, 0.0)
	var jeans := Color(0.22, 0.26, 0.32, 0.2)
	var jacket := Color(0.33, 0.29, 0.2, 0.4)
	var shirt := Color(0.42, 0.13, 0.1, 0.55)
	var leather := Color(0.17, 0.12, 0.08, 0.7)
	var boots := Color(0.2, 0.14, 0.09, 0.7)
	if bn == "Head" or (bn == "neck_01" and p.y > 1.5):
		return skin
	if bn.begins_with("hand_"):
		return leather
	for f in ["thumb", "index", "middle", "ring", "pinky"]:
		if bn.begins_with(f):
			return leather if bn.contains("_01") else skin
	if bn.begins_with("lowerarm"):
		return jacket if absf(p.x) < 0.66 else Color(0.27, 0.23, 0.16, 0.4)
	if bn.begins_with("foot") or bn.begins_with("ball"):
		return boots
	if bn.begins_with("calf"):
		return boots if p.y < 0.24 else jeans
	if bn.begins_with("thigh"):
		return jeans
	if bn == "pelvis" or bn == "root":
		if p.y < 0.915:
			return jeans
		if p.y < 0.965:
			if p.z > 0.05 and absf(p.x) < 0.035:
				return Color(0.55, 0.53, 0.48, 0.9) # fivela
			return leather
		return jacket
	# tronco, ombros, braços, pescoço
	if p.z > 0.04 and absf(p.x) < 0.065 and p.y > 0.98 and p.y < 1.47:
		return shirt
	return jacket


# ================================================================== lugares no corpo

func _attach_to(bone: String) -> BoneAttachment3D:
	if _attach.has(bone):
		return _attach[bone]
	var a := BoneAttachment3D.new()
	a.name = "Preso_" + bone
	a.bone_name = bone
	skel.add_child(a)
	_attach[bone] = a
	return a


## Transformação local (filho do osso) para ficar em `xf` (espaço do modelo, pose de descanso).
func _local_for(bone: String, xf: Transform3D) -> Transform3D:
	var rest := _rel * skel.get_bone_global_rest(skel.find_bone(bone))
	return rest.affine_inverse() * xf


func _build_slots() -> void:
	# mochila: presa no alto das costas, balança com mola em volta das alças
	var sp := _attach_to("spine_03")
	_bp_pivot = Node3D.new()
	_bp_pivot.name = "Mochila"
	sp.add_child(_bp_pivot)
	_bp_pivot.transform = _local_for("spine_03", Transform3D(Basis(), BP_PIVOT))
	var piv_model := _rel.affine_inverse() # (não usado) mantém o espaço do esqueleto explícito
	piv_model = Transform3D(Basis(), BP_PIVOT)
	_bp = Node3D.new()
	_bp.name = "Modelo"
	var bpm: Node3D = load("res://assets/modelos/mochila.tscn").instantiate()
	var col := bpm.get_node_or_null("Corpo")
	if col:
		bpm.remove_child(col)
		col.free()
	_bp.add_child(bpm)
	bpm.rotation.y = -PI / 2.0
	_bp.scale = Vector3.ONE * BP_SCALE
	_bp.position = BP_MODEL - BP_PIVOT
	_bp_pivot.add_child(_bp)
	_pivots.append(_pivot_state(_bp_pivot, 90.0, 0.25, 0.12))
	# armas nas costas, em X por cima da mochila (cano para baixo, coronha atrás do ombro)
	_slot(_bp_pivot, piv_model, "costas1", Transform3D(_gun_back(Vector3(0.42, -1.0, 0.0)), Vector3(0.0, 1.12, -0.5)), "centro")
	_slot(_bp_pivot, piv_model, "costas2", Transform3D(_gun_back(Vector3(-0.42, -1.0, 0.0)), Vector3(0.0, 1.12, -0.55)), "centro")
	_slot(_bp_pivot, piv_model, "lado_e", Transform3D(Basis(), Vector3(0.235, 1.12, -0.3)), "centro")
	_slot(_bp_pivot, piv_model, "lado_d", Transform3D(Basis(), Vector3(-0.235, 1.12, -0.3)), "centro")
	_slot(_bp_pivot, piv_model, "baixo", Transform3D(Basis(), Vector3(0.0, 0.86, -0.4)), "pendurado")
	_slot(_bp_pivot, piv_model, "topo", Transform3D(Basis(), Vector3(0.1, 1.5, -0.3)), "apoiado")
	_slot(_bp_pivot, piv_model, "dentro", Transform3D(Basis(), Vector3(0.0, 1.25, -0.3)), "centro")
	# cinto: pêndulos no quadril
	var pel := _attach_to("pelvis")
	for side in [["cinto_e", 1.0], ["cinto_d", -1.0]]:
		var piv := Node3D.new()
		piv.name = side[0]
		pel.add_child(piv)
		piv.transform = _local_for("pelvis", Transform3D(Basis(Vector3.UP, side[1] * 0.35), Vector3(side[1] * 0.2, 0.95, -0.02)))
		_slots[side[0]] = piv
		_slot_info[side[0]] = {"modo": "pendurado"}
		_pivots.append(_pivot_state(piv, 40.0, 0.85, 0.7))


func _gun_back(dir: Vector3) -> Basis:
	var z := -dir.normalized() # +Z da arma = coronha
	var x := Vector3(0, 0, -1)
	var y := z.cross(x)
	return Basis(x, y, z).orthonormalized()


func _slot(parent: Node3D, parent_model: Transform3D, n: String, xf: Transform3D, mode: String) -> void:
	var s := Node3D.new()
	s.name = n
	parent.add_child(s)
	s.transform = parent_model.affine_inverse() * xf
	_slots[n] = s
	_slot_info[n] = {"modo": mode}
	if mode == "pendurado":
		_pivots.append(_pivot_state(s, 30.0, 0.8, 0.6))


func _pivot_state(n: Node3D, k: float, frac: float, lim: float) -> Dictionary:
	return {"node": n, "rest": n.transform.basis, "ang": Vector2.ZERO, "vel": Vector2.ZERO, "prev": Vector3.INF,
		"pv": Vector3.ZERO, "acc": Vector3.ZERO, "k": k, "frac": frac, "lim": lim}


func _slot_free(n: String) -> bool:
	for it in items:
		if it.slot == n:
			return false
	return true


func _volume_used() -> float:
	var v := 0.0
	for it in items:
		if it.slot == "dentro":
			v += Itens.DATA[it.id].vol
	return v


func _choose_slot(id: String) -> String:
	var d: Dictionary = Itens.DATA[id]
	for s in d.slots:
		if s == "dentro":
			if _volume_used() + d.vol <= Itens.BACKPACK_L:
				return s
		elif _slot_free(s):
			return s
	return ""


## Onde o item fica (espaço do pai do lugar): o centro do item no ponto certo.
func _slot_local(slot: String, it: Dictionary) -> Transform3D:
	var size: Vector3 = it.node.get_meta("tamanho_real", Vector3(0.2, 0.2, 0.2))
	var b := Basis()
	var d: Dictionary = Itens.DATA[it.id]
	if slot.begins_with("lado") and d.has("rot_lado"):
		b = Basis.from_euler(d.rot_lado)
		size = (b * size).abs()
	var mode: String = _slot_info[slot].modo
	var o := Vector3.ZERO
	if mode == "pendurado":
		o.y = -size.y * 0.5 + 0.03
	elif mode == "apoiado":
		o.y = size.y * 0.5
	if slot.begins_with("cinto"):
		o.x = 0.0
		o.z = -0.0
	return Transform3D(b, o)


func _update_weight() -> void:
	weight = BACKPACK_KG
	for it in items:
		weight += Itens.peso(it.id)
	if not held.is_empty():
		weight += Itens.peso(held.id)
	# a mochila estufa conforme enche
	if _bp:
		var fill := clampf(_volume_used() / Itens.BACKPACK_L, 0.0, 1.0)
		_bp.scale = Vector3(BP_SCALE * (0.92 + 0.12 * fill), BP_SCALE, BP_SCALE * (0.82 + 0.3 * fill))
	changed.emit()


## Quanto o peso atrapalha: 1 = nada, menor = mais lento.
func load_factor() -> float:
	return clampf(1.0 - maxf(weight - 6.0, 0.0) * 0.012, 0.62, 1.0)


# ================================================================== API

func can_act() -> bool:
	return not busy


## Pegar um item do mundo (chamado pelo item ao USAR).
func pick(src: RigidBody3D) -> void:
	if busy or not is_instance_valid(src):
		return
	var id: String = src.item_id
	if weight + Itens.peso(id) > MAX_KG:
		toast("Pesado demais (%.0f kg)" % weight)
		return
	if not held.is_empty():
		# guarda a arma primeiro (as duas mãos estavam ocupadas)
		_queued = src
		holster()
		return
	var slot := _choose_slot(id)
	if slot == "" and not Itens.is_gun(id):
		toast("Sem espaço para %s" % Itens.nome(id))
		return
	_src = src
	src.freeze = true
	src.remove_from_group("usavel")
	var m: Node3D = src.get_node("Modelo")
	_it = {"id": id, "node": m, "slot": slot}
	_start_xf = m.global_transform
	var low := src.global_position.y - player.global_position.y
	_bend_target = clampf((0.85 - low) / 0.75, 0.0, 1.0)
	_begin("pegar")
	player.begin_equip(src.global_position)


## Larga um item do inventário (ou a arma das mãos) no chão à frente.
func drop(idx: int) -> void:
	if busy:
		return
	if idx < 0:
		if held.is_empty():
			return
		_it = held
		held = {}
		_start_xf = _it.node.global_transform
		_grabbed = true
		_begin("largar_mao")
		player.begin_equip(Vector3.INF)
		return
	if idx >= items.size():
		return
	_it = items[idx]
	_bend_target = 0.0
	_begin("largar")
	player.begin_equip(Vector3.INF)


## Saca a arma das costas (ou guarda, se já estiver na mão).
func toggle_weapon() -> void:
	if busy:
		return
	if not held.is_empty():
		holster()
		return
	for s in ["costas1", "costas2"]:
		for it in items:
			if it.slot == s and Itens.is_gun(it.id):
				draw(items.find(it))
				return
	toast("Nenhuma arma nas costas")


func draw(idx: int) -> void:
	if busy or not held.is_empty() or idx < 0 or idx >= items.size():
		return
	_it = items[idx]
	if not Itens.is_gun(_it.id):
		return
	_begin("sacar")


func holster() -> void:
	if busy or held.is_empty():
		return
	var slot := ""
	for s in ["costas1", "costas2"]:
		if _slot_free(s):
			slot = s
			break
	if slot == "":
		toast("As costas estão ocupadas: largue uma arma")
		return
	_it = held
	held = {}
	_it.slot = slot
	_start_xf = _it.node.global_transform
	_grabbed = true
	_begin("guardar")


## Guarda na hora, sem animação (ao nadar/sentar).
func stow_instant() -> void:
	if held.is_empty():
		return
	for s in ["costas1", "costas2"]:
		if _slot_free(s):
			held.slot = s
			_put_in_slot(held)
			items.append(held)
			held = {}
			_update_weight()
			return


func has_gun() -> bool:
	return not held.is_empty()


func toast(text: String) -> void:
	Inputs.toast = text
	Inputs.toast_t = 2.2


func _begin(seq: String) -> void:
	busy = true
	_seq = seq
	_t = 0.0
	_done_store = false
	if seq != "largar_mao" and seq != "guardar":
		_grabbed = false


func _play(kind: String, db := -6.0) -> void:
	if not Sfx.ready and not Sfx.SAMPLES.has(kind):
		return
	_snd.stream = Sfx.get_stream(kind)
	_snd.volume_db = db
	_snd.play()


# ================================================================== quadro a quadro

## Chamado pelo player no _process, depois de posicionar o corpo e antes do esqueleto
## atualizar: move os itens em trânsito, a arma na mão e os alvos das mãos.
func update(delta: float) -> void:
	_springs(delta)
	var want_w := [0.0, 0.0]
	if busy:
		_t += delta
		match _seq:
			"pegar":
				_seq_pick(want_w)
			"largar":
				_seq_drop(want_w)
			"largar_mao":
				_seq_drop_hand(want_w)
			"sacar":
				_seq_draw(want_w)
			"guardar":
				_seq_holster(want_w)
	if not held.is_empty() and not busy:
		_hold_gun(delta)
		want_w = [1.0, 1.0]
	elif not held.is_empty():
		_hold_gun(delta, true)
	# USAR numa porta: a mão vai até a maçaneta e empurra/puxa
	var door_w := 0.0
	if player._act == "Interact" and held.is_empty() and not busy and is_instance_valid(player._act_target_node) \
			and player._act_target_node.has_method("handle_point"):
		var at: float = player._act_t
		door_w = smoothstep(0.12, 0.45, at) * (1.0 - smoothstep(0.75, 1.05, at))
		var hp: Vector3 = player._act_target_node.handle_point()
		var f := hp - _vis().origin
		f.y = 0.0
		f = f.normalized()
		var palm := f.cross(Vector3.UP).normalized() # palma de lado (pega a maçaneta)
		var fing := (f + Vector3.DOWN * 0.2).normalized()
		palm = (palm - fing * palm.dot(fing)).normalized()
		body.hand_xf[1] = Transform3D(Basis(-palm, fing, (-palm).cross(fing)).orthonormalized(), hp - fing * 0.08)
	var swim: bool = player.mode == player.Mode.SWIM
	for i in 2:
		var target: float = want_w[i] * (0.0 if swim else 1.0)
		var rate := 7.0 if target > body.hand_w[i] else 5.0
		body.hand_w[i] = move_toward(body.hand_w[i], target, delta * rate)
	if door_w > 0.0:
		body.hand_w[1] = door_w
	body.bend = lerpf(body.bend, _bend_now(), 1.0 - exp(-10.0 * delta))
	body.squat = lerpf(body.squat, squat_now(), 1.0 - exp(-10.0 * delta))
	body.twist_share = lerpf(body.twist_share, 0.35 if not held.is_empty() else 1.0, 1.0 - exp(-6.0 * delta))
	if not busy and _queued != null:
		var q := _queued
		_queued = null
		if is_instance_valid(q):
			pick(q)


## Agachar para pegar no chão (0..1).
func crouch_now() -> float:
	return clampf((_bend_now() - 0.3) / 0.4, 0.0, 1.0)


## Inclinação do tronco ao pegar/largar (0..1).
func _bend_now() -> float:
	if not busy:
		return 0.0
	if _seq == "pegar":
		return _bend_target * smoothstep(0.0, 0.35, _t) * (1.0 - smoothstep(0.55, 0.95, _t))
	if _seq == "largar":
		return 0.3 * smoothstep(0.6, 0.85, _t) * (1.0 - smoothstep(0.95, 1.2, _t))
	return 0.0


## Agachamento extra (metros que o quadril desce, com os pés presos no chão).
func squat_now() -> float:
	return 0.2 * clampf((_bend_now() - 0.5) / 0.5, 0.0, 1.0)


## Base da mão direita pegando algo por cima (palma para baixo, dedos para frente).
func _hand_over(p: Vector3, fwd: Vector3) -> Transform3D:
	var f := fwd
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	f = (f + Vector3.DOWN * 0.6).normalized()
	var palm := Vector3.DOWN
	palm = (palm - f * palm.dot(f)).normalized()
	var x := -palm
	var z := x.cross(f)
	return Transform3D(Basis(x, f, z).orthonormalized(), p + Vector3.UP * 0.045 - f * 0.07)


func _grip_point(it: Dictionary) -> Vector3:
	var g := (it.node as Node3D).find_child("Empunhadura", true, false) as Node3D
	if g:
		return g.global_position
	var size: Vector3 = it.node.get_meta("tamanho_real", Vector3(0.2, 0.2, 0.2))
	return (it.node as Node3D).global_position + Vector3.UP * size.y * 0.3


func _vis() -> Transform3D:
	return player.visual.global_transform


## Pose de "olhar o item" na frente do peito.
func _inspect_xf(it: Dictionary) -> Transform3D:
	var v := _vis()
	var b := v.basis * Basis(Vector3.UP, 0.5)
	if Itens.is_gun(it.id):
		b = v.basis * Basis(Vector3.UP, PI * 0.5 + 0.3)
	return Transform3D(b, v * Vector3(-0.12, 1.15 - 0.35 * player._crouch_amt, 0.36))


func _slot_world(it: Dictionary) -> Transform3D:
	var s: Node3D = _slots[it.slot]
	return s.global_transform * _slot_local(it.slot, it)


## Curva entre duas poses passando por um ponto de controle (Bezier quadrática).
func _path(a: Transform3D, b: Transform3D, ctrl: Vector3, u: float) -> Transform3D:
	var e := u * u * (3.0 - 2.0 * u)
	var p := a.origin.lerp(ctrl, e).lerp(ctrl.lerp(b.origin, e), e)
	var q := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), e)
	return Transform3D(Basis(q), p)


func _shoulder_ctrl(it: Dictionary) -> Vector3:
	var v := _vis()
	if it.slot.begins_with("cinto"):
		var side := 1.0 if it.slot == "cinto_e" else -1.0
		return v * Vector3(-0.12 + side * 0.12, 1.0, 0.35)
	return v * Vector3(-0.24, 1.75, 0.05)


## A mão fecha no item: ele passa a ficar preso ao osso da mão (vai junto com ela).
func _grab(it: Dictionary) -> void:
	var n: Node3D = it.node
	var xf := n.global_transform
	_item_in_hand = (body.hand_xf[1] as Transform3D).affine_inverse() * xf
	if n.get_parent():
		n.get_parent().remove_child(n)
	_hand_att.add_child(n)
	n.top_level = false
	n.visible = true
	n.transform = _item_in_hand


## Leva a mão de modo que o item (na mão) fique na pose `d`.
func _carry(d: Transform3D) -> void:
	body.hand_xf[1] = d * _item_in_hand.affine_inverse()


func _put_in_slot(it: Dictionary) -> void:
	var n: Node3D = it.node
	if n.get_parent():
		n.get_parent().remove_child(n)
	n.top_level = false
	(_slots[it.slot] as Node3D).add_child(n)
	n.transform = _slot_local(it.slot, it)
	n.visible = it.slot != "dentro"


## Item solto no mundo (top_level, posicionado pelo código: arma nas duas mãos).
func _free_in_world(it: Dictionary) -> void:
	var n: Node3D = it.node
	var xf := n.global_transform
	if n.get_parent():
		n.get_parent().remove_child(n)
	add_child(n)
	n.top_level = true
	n.global_transform = xf


func _seq_pick(w: Array) -> void:
	var n: Node3D = _it.node
	const GRAB := 0.5
	if not _grabbed:
		# abaixa e a mão vai até o item (chega por cima)
		var grip := _grip_point(_it)
		var s := smoothstep(0.1, GRAB, _t)
		var start := _vis() * Vector3(-0.22, 0.95, 0.15)
		var hx := _hand_over(grip, grip - player.global_position)
		hx.origin = start.lerp(hx.origin + Vector3.UP * 0.12 * (1.0 - smoothstep(0.3, GRAB, _t)), s)
		body.hand_xf[1] = hx
		w[1] = smoothstep(0.05, 0.3, _t)
		if _t >= GRAB:
			_grabbed = true
			if is_instance_valid(_src):
				_src.remove_child(n)
				_src.queue_free()
			add_child(n)
			n.global_transform = _start_xf
			body.hand_xf[1] = _hand_over(grip, grip - player.global_position)
			_grab(_it)
			_start_xf = n.global_transform
			_play(Itens.DATA[_it.id].get("som", "wood"), -20.0)
			_play("cloth", -12.0)
		return
	w[1] = 1.0
	var t2 := _t - GRAB
	if _it.slot == "":
		# arma sem lugar nas costas: fica nas mãos
		var u := clampf(t2 / 0.55, 0.0, 1.0)
		_carry(_path(_start_xf, _hold_xf(), _vis() * Vector3(-0.1, 1.2, 0.45), u))
		w[0] = smoothstep(0.6, 1.0, u)
		_left_on_gun(_hold_xf())
		if u >= 1.0:
			_free_in_world(_it)
			held = _it
			_it.slot = "mao"
			_update_weight()
			_play("gun_handle", -8.0)
			_finish()
		return
	const LIFT := 0.4
	const STORE := 0.55
	if t2 < LIFT:
		# levanta e olha o item
		var ins := _inspect_xf(_it)
		_carry(_path(_start_xf, ins, _start_xf.origin.lerp(ins.origin, 0.5) + Vector3.UP * 0.12, t2 / LIFT))
	elif t2 < LIFT + STORE:
		_carry(_path(_inspect_xf(_it), _slot_world(_it), _shoulder_ctrl(_it), (t2 - LIFT) / STORE))
	else:
		if not _done_store:
			_done_store = true
			_put_in_slot(_it)
			items.append(_it)
			_update_weight()
			_store_sound(_it.slot)
			_kick(_it.slot)
		w[1] = 0.0
		if t2 > LIFT + STORE + 0.1:
			_finish()


func _seq_drop(w: Array) -> void:
	w[1] = 1.0
	const GRAB := 0.42
	if not _grabbed:
		# a mão vai até o lugar do item (costas, cinto, mochila)
		var grip := _grip_point(_it)
		var reach := smoothstep(0.0, GRAB, _t)
		var start := _vis() * Vector3(-0.2, 1.1, 0.25)
		var hx := _hand_over(grip, _vis().basis.z)
		var ctrl := _shoulder_ctrl(_it)
		var a := start.lerp(ctrl, reach)
		hx.origin = a.lerp(hx.origin, reach)
		body.hand_xf[1] = hx
		w[1] = smoothstep(0.0, 0.25, _t)
		if _t >= GRAB:
			_grabbed = true
			body.hand_xf[1] = _hand_over(grip, _vis().basis.z)
			_grab(_it)
			_start_xf = (_it.node as Node3D).global_transform
			items.erase(_it)
			_update_weight()
			_store_sound(_it.slot)
			_kick(_it.slot)
		return
	var t2 := _t - GRAB
	var drop_xf := Transform3D(_vis().basis, _vis() * Vector3(-0.12, 0.8, 0.5))
	if t2 < 0.55:
		_carry(_path(_start_xf, drop_xf, _shoulder_ctrl(_it), t2 / 0.55))
	else:
		if not _done_store:
			_done_store = true
			_release_to_world(_it, (_vis().basis.z * 0.5 + Vector3.DOWN * 0.3))
		w[1] = 0.0
		if t2 > 0.75:
			_finish()


func _seq_drop_hand(w: Array) -> void:
	w[1] = 1.0
	if not _done_store and (_it.node as Node3D).get_parent() != _hand_att:
		_grab(_it)
		_start_xf = (_it.node as Node3D).global_transform
	var drop_xf := Transform3D(_vis().basis * Basis(Vector3.UP, PI * 0.5), _vis() * Vector3(-0.1, 0.95, 0.55))
	if _t < 0.35:
		_carry(_start_xf.interpolate_with(drop_xf, smoothstep(0.0, 0.35, _t)))
	else:
		if not _done_store:
			_done_store = true
			_release_to_world(_it, _vis().basis.z * 0.8)
			_update_weight()
		w[1] = 0.0
		if _t > 0.6:
			_finish()


func _seq_draw(w: Array) -> void:
	var n: Node3D = _it.node
	const GRAB := 0.4
	if not _grabbed:
		# mão direita sobe por cima do ombro até a coronha
		var grip := _grip_point(_it)
		var s := smoothstep(0.0, GRAB, _t)
		var shoulder := _vis() * Vector3(-0.22, 1.62, 0.12)
		var hx := _gun_hand_r(n.global_transform, grip)
		hx.origin = shoulder.lerp(hx.origin, s)
		body.hand_xf[1] = hx
		w[1] = smoothstep(0.0, 0.2, _t)
		if _t >= GRAB:
			_grabbed = true
			body.hand_xf[1] = _gun_hand_r(n.global_transform, grip)
			_grab(_it)
			_start_xf = n.global_transform
			items.erase(_it)
			_play("gun_handle", -6.0)
			_kick(_it.slot)
		return
	w[1] = 1.0
	var t2 := _t - GRAB
	var u := clampf(t2 / 0.5, 0.0, 1.0)
	var d := _path(_start_xf, _hold_xf(), _vis() * Vector3(-0.32, 1.85, 0.15), u)
	_carry(d)
	# a mão esquerda encontra a arma no fim
	_left_on_gun(n.global_transform)
	w[0] = smoothstep(0.55, 1.0, u)
	if u >= 1.0:
		_free_in_world(_it)
		held = _it
		_it.slot = "mao"
		_update_weight()
		_play("gun_click", -10.0)
		_finish()


func _seq_holster(w: Array) -> void:
	var n: Node3D = _it.node
	w[1] = 1.0
	w[0] = 1.0 - smoothstep(0.0, 0.15, _t)
	if n.get_parent() != _hand_att and not _done_store:
		_grab(_it)
		_start_xf = n.global_transform
	if _t < 0.55:
		_carry(_path(_start_xf, _slot_world(_it), _vis() * Vector3(-0.32, 1.9, 0.1), _t / 0.55))
		_left_on_gun(n.global_transform)
	else:
		if not _done_store:
			_done_store = true
			_put_in_slot(_it)
			items.append(_it)
			_update_weight()
			_play("gun_handle", -8.0)
			_play("leather", -12.0)
			_kick(_it.slot)
		w[1] = 0.0
		if _t > 0.75:
			_finish()


func _finish() -> void:
	busy = false
	_seq = ""
	_bend_target = 0.0
	if player.mode == player.Mode.ACTION and player._act == "Equip":
		player._end_action(0.2)


func _store_sound(slot: String) -> void:
	if slot.begins_with("costas"):
		_play("gun_handle", -8.0)
	elif slot.begins_with("cinto"):
		_play("belt", -8.0)
	elif slot == "dentro":
		_play("cloth", -6.0)
		_play("leather", -14.0)
	else:
		_play("leather", -9.0)


## Um tranco no pivô (a mochila balança ao receber/perder peso).
func _kick(slot: String) -> void:
	for p in _pivots:
		if p.node == _bp_pivot or p.node == _slots.get(slot):
			p.vel += Vector2(randf_range(1.5, 2.5), randf_range(-1.5, 1.5))


func _release_to_world(it: Dictionary, vel: Vector3) -> void:
	var n: Node3D = it.node
	var xf := n.global_transform
	var rb := Itens.make_body(it.id, n)
	var scene := player.get_parent()
	var parent: Node = scene.get_node("Objetos") if scene.has_node("Objetos") else scene
	parent.add_child(rb)
	rb.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	rb.linear_velocity = Vector3(player.velocity.x, 0.0, player.velocity.z) + vel
	rb.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
	_play("cloth", -12.0)


# ================================================================== arma nas mãos

## Pose da arma: coronha no ombro direito, apontando para onde a câmera olha (abaixada
## correndo). Com atraso de mola (a arma tem peso) e o balanço do passo.
func _hold_xf() -> Transform3D:
	var v := _vis()
	var crouch: float = player._crouch_amt
	var shoulder := v * Vector3(-0.17, 1.43 - 0.42 * crouch, 0.02)
	var yaw: float = player.cam_yaw + _aim_lag.x
	var pitch := clampf(player.cam_pitch + _aim_lag.y, -1.0, 1.0)
	# correndo: arma baixa e de lado (pronta, sem mirar)
	yaw += 0.55 * _ready_amt
	pitch = lerpf(pitch, -0.75, _ready_amt)
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	b = b * Basis(Vector3.FORWARD, 0.25 * _ready_amt)
	var fwd := -b.z
	var gun_len := 0.88
	if not _it.is_empty():
		gun_len = (_it.node.get_meta("tamanho_real", Vector3(0, 0, 0.88)) as Vector3).z
	if not held.is_empty():
		gun_len = (held.node.get_meta("tamanho_real", Vector3(0, 0, 0.88)) as Vector3).z
	var stock := shoulder + fwd * 0.05 + b.y * 0.02
	# 1ª pessoa: a coronha fica num ponto fixo em relação à câmera (embaixo e à direita do
	# olho), como uma pessoa olhando por cima da arma
	var e := smoothstep(0.0, 1.0, player.cam_blend)
	if e > 0.001:
		var cam: Transform3D = player.cam.global_transform
		var fp_stock := cam * Vector3(0.13, -0.19, 0.06)
		stock = stock.lerp(fp_stock, e)
	return Transform3D(b, stock + fwd * gun_len * 0.5)


func _hold_gun(delta: float, passive := false) -> void:
	var n: Node3D = held.node
	var aim := Vector2(player.cam_yaw, player.cam_pitch)
	var d := Vector2(wrapf(aim.x - _last_aim.x, -PI, PI), aim.y - _last_aim.y)
	_last_aim = aim
	# a arma fica um pouco para trás quando a câmera vira (inércia) e volta com mola
	var kg := Itens.peso(held.id)
	_aim_lag -= d * clampf(kg / 4.0, 0.3, 1.2) * 0.35
	var k := 120.0
	_aim_vel += (-k * _aim_lag - 2.0 * sqrt(k) * 0.8 * _aim_vel) * minf(delta, 0.05)
	_aim_lag += _aim_vel * minf(delta, 0.05)
	_aim_lag = _aim_lag.clamp(Vector2(-0.3, -0.3), Vector2(0.3, 0.3))
	var run: bool = player.sprinting or player.mode != player.Mode.NORMAL
	_ready_amt = lerpf(_ready_amt, 1.0 if run else 0.0, 1.0 - exp(-7.0 * delta))
	if passive:
		return
	var xf := _hold_xf()
	n.global_transform = xf
	var grip := n.find_child("Empunhadura", true, false) as Node3D
	body.hand_xf[1] = _gun_hand_r(xf, grip.global_position if grip else xf.origin + xf.basis.z * 0.12)
	_left_on_gun(xf)


func _gun_hand_r(xf: Transform3D, grip: Vector3) -> Transform3D:
	var g := xf.basis.orthonormalized()
	var f := (g * Vector3(-0.15, -0.6, -1.0)).normalized()
	var palm := -g.x
	palm = (palm - f * palm.dot(f)).normalized()
	var x := -palm
	var z := x.cross(f)
	return Transform3D(Basis(x, f, z).orthonormalized(), grip - f * 0.06 + g.x * 0.03 + g.y * 0.02)


## Mão esquerda por baixo do guarda-mão; se não alcança, escorrega para trás na arma.
func _left_on_gun(xf: Transform3D) -> void:
	var g := xf.basis.orthonormalized()
	var gun: Dictionary = held if (not held.is_empty() and not busy) else _it
	var guard: Node3D = null
	if gun.has("node"):
		guard = (gun.node as Node3D).find_child("Guarda", true, false) as Node3D
	var p := guard.global_position if guard else xf.origin - g.z * 0.12
	var shoulder := _vis() * Vector3(0.17, 1.43 - 0.42 * player._crouch_amt, 0.0)
	var back := g.z
	for i in 12:
		if shoulder.distance_to(p) < 0.5:
			break
		p += back * 0.03
	var f := (g * Vector3(0.6, 0.0, -1.0)).normalized()
	var palm := g.y
	palm = (palm - f * palm.dot(f)).normalized()
	var z := palm.cross(f)
	body.hand_xf[0] = Transform3D(Basis(palm, f, z).orthonormalized(), p - f * 0.06 - g.y * 0.045)


# ================================================================== molas

func _springs(delta: float) -> void:
	var dt := clampf(delta, 0.001, 0.05)
	for p in _pivots:
		var n: Node3D = p.node
		var parent := n.get_parent() as Node3D
		var pos := n.global_position
		if p.prev == Vector3.INF:
			p.prev = pos
		var v: Vector3 = (pos - p.prev) / dt
		p.prev = pos
		var a: Vector3 = (v - p.pv) / dt
		p.pv = v
		p.acc = p.acc.lerp(a.limit_length(40.0), 1.0 - exp(-20.0 * dt))
		# gravidade "sentida" pelo objeto pendurado, no espaço do pai
		var g: Vector3 = Vector3.DOWN * 9.8 - p.acc
		var lg: Vector3 = (parent.global_transform.basis.orthonormalized() * p.rest).inverse() * g
		lg = lg.normalized()
		var frac: float = p.frac
		var lim: float = p.lim
		var tx: float = atan2(-lg.z, -lg.y) * frac
		var tz: float = atan2(lg.x, -lg.y) * frac
		if frac < 0.5:
			# mochila: presa ao corpo, só reage à aceleração (não ao giro do tronco)
			var l0: Vector3 = ((parent.global_transform.basis.orthonormalized() * p.rest).inverse() * Vector3.DOWN).normalized()
			tx -= atan2(-l0.z, -l0.y) * frac
			tz -= atan2(l0.x, -l0.y) * frac
		var target := Vector2(clampf(tx, -lim, lim), clampf(tz, -lim, lim))
		var k: float = p.k
		p.vel += (k * (target - p.ang) - 2.0 * sqrt(k) * 0.35 * p.vel) * dt
		p.ang += p.vel * dt
		p.ang = (p.ang as Vector2).clamp(Vector2(-lim, -lim), Vector2(lim, lim))
		n.transform.basis = p.rest * Basis.from_euler(Vector3(p.ang.x, 0.0, p.ang.y))
