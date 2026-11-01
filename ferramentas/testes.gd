extends SceneTree
## Uso: godot --headless -s res://ferramentas/testes.gd
## Testes automáticos da v0.04 (mapa real; rodar sem janela).
var main: Node3D
var p
var mundo
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
func spawn_item(id: String, off: Vector3) -> RigidBody3D:
	var rb := Itens.make_body(id)
	main.get_node("Objetos").add_child(rb)
	rb.global_position = p.global_position + off + Vector3.UP * 0.5
	return rb
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
	mundo = main.get_node("Mundo")
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
	check("mundo real montou os blocos em volta", mundo._blocks.size() > 20, "%d blocos" % mundo._blocks.size())
	var under := main.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP, p.global_position + Vector3.DOWN * 3.0, 1, [p.get_rid()]))
	check("chão com colisão debaixo do jogador", not under.is_empty())
	check("altura do chão bate com o relevo", not under.is_empty() and absf(under.position.y - mundo.height_at(p.global_position.x, p.global_position.z)) < 0.3)
	var nveg := 0
	for b in mundo._blocks.values():
		if b.has("veg"):
			nveg += 1
	check("caatinga gerada perto", nveg > 4, "%d blocos com plantas" % nveg)
	check("casas reais carregadas", mundo.dados.casas.size() > 200, "%d casas" % mundo.dados.casas.size())
	var hs: Dictionary = mundo.dados.casas[40]
	var hp := Vector3(hs.x, hs.y + 1.2, hs.z)
	mundo.preload_around(hp)
	await frames(5)
	var hits := 0
	for k in 8:
		var a := k * TAU / 8.0
		var r := main.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(hp, hp + Vector3(cos(a), 0, sin(a)) * 15.0, 1))
		if not r.is_empty(): hits += 1
	check("paredes da casa com colisão (porta/janelas abertas)", hits >= 4 and hits < 8, "%d de 8 direções batem" % hits)
	put(mundo.spawn_point())
	await frames(30)
	# andar
	var a: Vector3 = p.global_position
	Input.action_press("move_forward")
	await frames(90)
	Input.action_release("move_forward")
	check("anda para frente", p.global_position.distance_to(a) > 2.0, "%.2f m, passos %d" % [p.global_position.distance_to(a), p.steps])
	# pegar o machado: vai para a lateral da mochila, peso sobe
	var ax := spawn_item("machado", Vector3(1.0, 0, 0.4))
	await frames(40)
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
	var food := spawn_item("comida", Vector3(-1.0, 0, 0.5))
	await frames(40)
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
	var sg := spawn_item("escopeta", Vector3(0.6, 0, -1.0))
	await frames(40)
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
	# comer: a mão pega a lata na mochila e a animação (UAL2) leva à boca
	var fi := -1
	for i in p.equip.items.size():
		if p.equip.items[i].id == "comida": fi = i
	var n_items: int = p.equip.items.size()
	p.equip.consume(fi)
	await frames(30)
	check("comendo: animação de comer tocando", p._act == "Consume" or p._tree.get("parameters/act_sel/current_state") == "Consume", str(p._act))
	await frames(120)
	check("comeu a comida (saiu do inventário)", p.equip.items.size() == n_items - 1 and not p.equip.busy, Inputs.toast)
	# peso deixa mais lento
	var lf: float = p.equip.load_factor()
	p.equip.weight = 30.0
	check("carga pesada reduz a velocidade", p.equip.load_factor() < 0.8 and lf > 0.95, "%.2f -> %.2f" % [lf, p.equip.load_factor()])
	p.equip._update_weight()
	# açude: nadar
	var pc: Vector3 = mundo.pond_centers()[3]
	put(Vector3(pc.x, pc.y + 0.5, pc.z))
	mundo.preload_around(p.global_position)
	await frames(150)
	check("nada no açude", p.mode == p.Mode.SWIM, p.state_text())
	# configurações
	Config.set_preset("Baixa", false)
	Config.apply(self)
	await frames(10)
	check("qualidade Baixa aplica (sem sombra, resolução 70%)", not (get_first_node_in_group("sol") as DirectionalLight3D).shadow_enabled and absf(root.scaling_3d_scale - 0.7) < 0.01)
	print("\n%d OK, %d falhas" % [ok, fail])
	quit()
