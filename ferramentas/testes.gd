extends SceneTree
## Uso: godot --headless -s res://ferramentas/testes.gd
## Testes automáticos da v0.03 (rodar sem janela).
var main: Node3D
var p
var ok := 0
var fail := 0
func check(name: String, cond: bool, info := "") -> void:
	if cond:
		ok += 1
		print("OK   ", name, "  ", info)
	else:
		fail += 1
		print("FALHA ", name, "  ", info)
func frames(n: int) -> void:
	for i in n: await physics_frame
func item(id: String) -> RigidBody3D:
	var best: RigidBody3D
	for it in main.get_node("Objetos").get_children():
		if it.get("item_id") == id and (best == null or it.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position)):
			best = it
	return best
func put(pos: Vector3, yaw := 0.0) -> void:
	p.respawn(); p.global_position = pos; p._prev_pos = pos; p._cur_pos = pos; p._pivot_y = pos.y
	p.cam_yaw = yaw; p.model_yaw = yaw + PI; p.velocity = Vector3.ZERO
func _initialize():
	var t0 := Time.get_ticks_msec()
	main = load("res://scenes/main.scn").instantiate()
	root.add_child(main)
	print("carregou em ", Time.get_ticks_msec() - t0, " ms")
	p = main.get_node("Player")
	await frames(90)
	check("personagem no chão ao começar", p.is_on_floor(), str(p.global_position))
	check("sons gravados carregam", Sfx.get_stream("step_grass") is AudioStreamRandomizer and (Sfx.get_stream("step_grass") as AudioStreamRandomizer).streams_count >= 5)
	check("ambiente gravado em laço", Sfx.get_stream("birds") is AudioStreamMP3 and (Sfx.get_stream("birds") as AudioStreamMP3).loop)
	var nan := 0
	for it in main.get_node("Objetos").get_children():
		if not it.global_position.is_finite(): nan += 1
	check("nenhum objeto com física quebrada", nan == 0)
	# andar
	var a: Vector3 = p.global_position
	Input.action_press("move_forward")
	await frames(90)
	Input.action_release("move_forward")
	check("anda para frente", p.global_position.distance_to(a) > 2.0, "%.2f m, passos %d" % [p.global_position.distance_to(a), p.steps])
	# pegar o machado: vai para a lateral da mochila, peso sobe
	var ax := item("machado")
	put(ax.global_position + Vector3(0.8, 0.2, 0.3))
	await frames(20)
	var w0: float = p.equip.weight
	p.equip.pick(ax)
	await frames(10)
	check("pegando trava o corpo", p.mode == p.Mode.ACTION)
	await frames(120)
	check("machado guardado no corpo", p.equip.items.size() == 1 and p.equip.items[0].slot in ["lado_d", "lado_e", "cinto_e"], str(p.equip.items))
	check("peso aumentou 1,4 kg", absf(p.equip.weight - w0 - 1.4) < 0.01, "%.2f kg" % p.equip.weight)
	check("machado continua visível no corpo", p.equip.items[0].node.is_visible_in_tree())
	check("corpo livre de novo", p.mode == p.Mode.NORMAL)
	# itens pequenos vão para dentro da mochila
	var food := item("comida")
	put(food.global_position + Vector3(0.7, 0.2, 0.0))
	await frames(20)
	p.equip.pick(food)
	await frames(130)
	var inside := false
	for it in p.equip.items:
		if it.id == "comida" and it.slot == "dentro": inside = true
	check("comida dentro da mochila", inside)
	check("volume da mochila usado", p.equip._volume_used() > 0.5, "%.1f L" % p.equip._volume_used())
	# arma: pegar, sacar, segurar com as duas mãos, guardar
	var sg := item("escopeta")
	put(sg.global_position + Vector3(0.8, 0.3, 0.0))
	await frames(20)
	p.equip.pick(sg)
	await frames(130)
	var on_back := false
	for it in p.equip.items:
		if it.id == "escopeta" and it.slot.begins_with("costas"): on_back = true
	check("escopeta pendurada nas costas", on_back)
	p.equip.toggle_weapon()
	await frames(80)
	check("escopeta nas mãos", p.equip.has_gun())
	await frames(20)
	check("duas mãos na arma (IK)", p._body.hand_w[0] > 0.9 and p._body.hand_w[1] > 0.9, str(p._body.hand_w))
	var grip := (p.equip.held.node as Node3D).find_child("Empunhadura", true, false) as Node3D
	var hand: Vector3 = p._body.debug_hand[1]
	check("mão direita na empunhadura", hand.distance_to(p._body.hand_xf[1].origin) < 0.08, "%.3f m" % hand.distance_to(p._body.hand_xf[1].origin))
	var spd_gun := 0.0
	Input.action_press("move_forward")
	await frames(60)
	spd_gun = Vector2(p.velocity.x, p.velocity.z).length()
	Input.action_release("move_forward")
	check("com arma anda mais devagar (sem correr)", spd_gun <= p.jog_speed * 0.8 + 0.05, "%.2f m/s" % spd_gun)
	p.equip.toggle_weapon()
	await frames(70)
	check("arma guardada nas costas", not p.equip.has_gun())
	# largar: o item volta para o mundo com física
	var n_before: int = main.get_node("Objetos").get_child_count()
	var idx := -1
	for i in p.equip.items.size():
		if p.equip.items[i].id == "machado": idx = i
	p.equip.drop(idx)
	await frames(150)
	check("largou o machado no chão", main.get_node("Objetos").get_child_count() == n_before + 1 and p.equip.items.size() == 2)
	var dropped := item("machado")
	check("machado caiu perto e parou", dropped != null and dropped.global_position.distance_to(p.global_position) < 2.0 and dropped.linear_velocity.length() < 0.5)
	# peso deixa mais lento
	var lf: float = p.equip.load_factor()
	p.equip.weight = 30.0
	check("carga pesada reduz a velocidade", p.equip.load_factor() < 0.8 and lf > 0.95, "%.2f -> %.2f" % [lf, p.equip.load_factor()])
	p.equip._update_weight()
	# porta da cabana
	var door: Node3D = main.find_child("Cabana0", true, false).get_node("Porta")
	var hp: Vector3 = door.handle_point()
	var outward: Vector3 = (hp - door.get_parent().global_position)
	outward.y = 0
	put(hp + outward.normalized() * 0.7 + Vector3.DOWN * 0.9)
	await frames(20)
	var r0: float = door.rotation.y
	door.interact(p)
	await frames(120)
	check("porta abre (mão na maçaneta)", door.is_open and absf(door.rotation.y - r0) > 1.0, "%.2f rad" % (door.rotation.y - r0))
	# lago: nadar
	put(Vector3(-185, 1.0, -150))
	await frames(120)
	check("nada no lago", p.mode == p.Mode.SWIM, p.state_text())
	print("\n%d OK, %d falhas" % [ok, fail])
	quit()
