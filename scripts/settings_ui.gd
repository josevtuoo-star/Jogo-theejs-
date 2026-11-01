extends Control
## Painel de configurações (botão ⚙ ou tecla O): qualidade pronta (Baixa/Média/Alta/Ultra) e
## cada opção separada — sombras, resolução, antisserrilhado, distância de visão, densidade da
## caatinga, grama, neblina, cor final, limite de FPS, brilho, campo de visão, sensibilidade e
## mostrar FPS. Tudo salvo no aparelho.

const ROW := 46.0
var open := false
var _buttons := []
var _rows := []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Config.load_cfg()
	_rows = [
		{"nome": "Qualidade", "tipo": "opts", "k": "qualidade", "ops": ["Baixa", "Média", "Alta", "Ultra"]},
		{"nome": "Sombras", "tipo": "opts", "k": "sombras", "ops": ["Desl.", "Baixa", "Média", "Alta"]},
		{"nome": "Distância das sombras", "tipo": "num", "k": "sombra_dist", "min": 15.0, "max": 120.0, "passo": 10.0, "fmt": "%d m"},
		{"nome": "Resolução 3D", "tipo": "num", "k": "escala", "min": 0.5, "max": 1.0, "passo": 0.05, "fmt": "%d%%", "mult": 100.0},
		{"nome": "Antisserrilhado", "tipo": "opts", "k": "msaa", "ops": ["Desl.", "2x", "4x"]},
		{"nome": "Distância de visão", "tipo": "num", "k": "distancia", "min": 250.0, "max": 1500.0, "passo": 50.0, "fmt": "%d m"},
		{"nome": "Vegetação (caatinga)", "tipo": "num", "k": "vegetacao", "min": 0.2, "max": 1.6, "passo": 0.1, "fmt": "%d%%", "mult": 100.0},
		{"nome": "Grama perto", "tipo": "bool", "k": "grama"},
		{"nome": "Neblina", "tipo": "bool", "k": "neblina"},
		{"nome": "Cor final (filme)", "tipo": "bool", "k": "pos"},
		{"nome": "Limite de FPS", "tipo": "opts", "k": "fps", "ops": ["30", "60", "90", "120", "Sem"], "vals": [30, 60, 90, 120, 0]},
		{"nome": "Brilho", "tipo": "num", "k": "brilho", "min": 0.6, "max": 1.6, "passo": 0.05, "fmt": "%d%%", "mult": 100.0},
		{"nome": "Campo de visão (1ª p.)", "tipo": "num", "k": "fov", "min": 60.0, "max": 100.0, "passo": 2.0, "fmt": "%d°"},
		{"nome": "Sensibilidade", "tipo": "num", "k": "sensibilidade", "min": 0.3, "max": 2.5, "passo": 0.1, "fmt": "%d%%", "mult": 100.0},
		{"nome": "Mostrar FPS", "tipo": "bool", "k": "mostrar_fps"},
	]
	await get_tree().process_frame
	Config.apply(get_tree())


func _process(_d: float) -> void:
	if Input.is_action_just_pressed("settings"):
		toggle()
	if open:
		queue_redraw()


func toggle() -> void:
	open = not open
	Inputs.menu_open = open
	if not Inputs.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not open:
		return
	var p := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		p = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		p = event.position
	if p == Vector2.INF:
		return
	get_viewport().set_input_as_handled()
	for b in _buttons:
		if (b[0] as Rect2).grow(4.0).has_point(p):
			_press(b[1], b[2])
			return


func _press(row: Variant, val: Variant) -> void:
	if row is String:
		match row:
			"fechar":
				toggle()
			"recomecar":
				var pl := get_tree().get_first_node_in_group("jogador")
				if pl:
					pl.respawn()
				toggle()
		return
	var r: Dictionary = row
	match r.tipo:
		"opts":
			if r.k == "qualidade":
				Config.set_preset(val)
			elif r.has("vals"):
				Config.set_value(r.k, r.vals[val])
			else:
				Config.set_value(r.k, val)
		"num":
			var nv: float = clampf(float(Config.v[r.k]) + r.passo * val, r.min, r.max)
			Config.set_value(r.k, snappedf(nv, r.passo * 0.5))
		"set":
			Config.set_value(r.k, r.v)
	Config.apply(get_tree())


func _draw() -> void:
	_buttons.clear()
	if not open:
		return
	var font := ThemeDB.fallback_font
	var cols := 2 if size.x > 900.0 else 1
	var per := int(ceil(float(_rows.size()) / cols))
	var cw := minf(560.0, (size.x - 60.0) / cols)
	var w := cw * cols + 30.0
	var h := 96.0 + per * ROW + 60.0
	var scale_y := minf(1.0, (size.y - 40.0) / h)
	var rh := ROW * scale_y
	h = 96.0 + per * rh + 60.0
	var panel := Rect2((size.x - w) * 0.5, maxf((size.y - h) * 0.5, 10.0), w, h)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	draw_rect(panel, Color(0.07, 0.065, 0.055, 0.95))
	draw_rect(panel, Color(0.85, 0.72, 0.45, 0.7), false, 2.0)
	draw_string(font, panel.position + Vector2(18, 34), "CONFIGURAÇÕES", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.86, 0.5))
	draw_string(font, panel.position + Vector2(18, 58), "Qualidade atual: %s · %d FPS" % [Config.v.qualidade, Engine.get_frames_per_second()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	_btn(Rect2(panel.end.x - 52, panel.position.y + 10, 40, 34), "X", "fechar", null)
	for i in _rows.size():
		var c := i / per
		var rr := i % per
		var x := panel.position.x + 15.0 + c * cw
		var y := panel.position.y + 80.0 + rr * rh
		_row(font, _rows[i], Vector2(x, y), cw - 10.0, rh)
	_btn(Rect2(panel.position.x + 18, panel.end.y - 48, 180, 36), "RECOMEÇAR", "recomecar", null)
	draw_string(font, Vector2(panel.position.x + 214, panel.end.y - 24), "Mais FPS: abaixe Resolução 3D, Sombras e Vegetação.", HORIZONTAL_ALIGNMENT_LEFT, w - 230, 13, Color(1, 1, 1, 0.55))


func _row(font: Font, r: Dictionary, p: Vector2, w: float, h: float) -> void:
	draw_string(font, p + Vector2(4, h * 0.6), r.nome, HORIZONTAL_ALIGNMENT_LEFT, w * 0.42, 15, Color(1, 1, 1, 0.9))
	var x0 := p.x + w * 0.44
	var bw := w - w * 0.44
	var bh := h - 10.0
	match r.tipo:
		"opts":
			var ops: Array = r.ops
			var each := bw / ops.size()
			for k in ops.size():
				var on := false
				if r.k == "qualidade":
					on = Config.v.qualidade == ops[k]
				elif r.has("vals"):
					on = int(Config.v[r.k]) == int(r.vals[k])
				else:
					on = int(Config.v[r.k]) == k
				_btn(Rect2(x0 + k * each, p.y + 4, each - 4, bh), ops[k], r, ops[k] if r.k == "qualidade" else k, on)
		"num":
			var val: float = float(Config.v[r.k]) * r.get("mult", 1.0)
			_btn(Rect2(x0, p.y + 4, 44, bh), "−", r, -1)
			draw_string(font, Vector2(x0 + 48, p.y + h * 0.6), r.fmt % int(round(val)), HORIZONTAL_ALIGNMENT_CENTER, bw - 96, 16, Color(1, 0.92, 0.7))
			_btn(Rect2(x0 + bw - 44, p.y + 4, 44, bh), "+", r, 1)
		"bool":
			var on: bool = Config.v[r.k]
			_btn(Rect2(x0, p.y + 4, bw * 0.5 - 2, bh), "Ligado", r, true, on)
			_btn(Rect2(x0 + bw * 0.5 + 2, p.y + 4, bw * 0.5 - 2, bh), "Desligado", r, false, not on)


func _btn(r: Rect2, label: String, row: Variant, val: Variant, on := false) -> void:
	draw_rect(r, Color(0.75, 0.55, 0.25, 0.9) if on else Color(0.22, 0.2, 0.15, 0.9))
	draw_rect(r, Color(1, 0.85, 0.5, 0.6), false, 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 5), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, Color(1, 0.95, 0.85))
	# bool: o mesmo botão liga/desliga (val true = ligar)
	if row is Dictionary and (row as Dictionary).tipo == "bool":
		_buttons.append([r, {"tipo": "set", "k": row.k, "v": val}, null])
	else:
		_buttons.append([r, row, val])
