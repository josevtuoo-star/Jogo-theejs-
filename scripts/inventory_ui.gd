extends Control
## Painel do equipamento (Tab / botão MOCHILA): o que o personagem carrega, onde está cada
## coisa no corpo, peso de cada item e o total, espaço livre na mochila. Toque/clique num botão
## para LARGAR (o personagem pega do lugar e põe no chão), EMPUNHAR ou GUARDAR a arma.

const W := 470.0
const ROW := 44.0
const SLOT_NAMES := {"costas1": "Costas", "costas2": "Costas", "cinto_e": "Cinto (esq.)", "cinto_d": "Cinto (dir.)",
	"lado_e": "Mochila (lado esq.)", "lado_d": "Mochila (lado dir.)", "baixo": "Embaixo da mochila",
	"topo": "Em cima da mochila", "dentro": "Dentro da mochila", "mao": "Nas mãos"}

var open := false
var _buttons := [] # [Rect2, ação, índice]
var _player: Node


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if _player == null:
		var scene: Node = owner if owner else get_tree().current_scene
		if scene == null:
			return
		_player = scene.get_node_or_null("Player")
	if Input.is_action_just_pressed("inventory"):
		_toggle()
	if open:
		queue_redraw()


func _toggle() -> void:
	open = not open
	Inputs.menu_open = open
	if not Inputs.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
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
		if (b[0] as Rect2).grow(6.0).has_point(p):
			_press(b[1], b[2])
			return


func _press(action: String, idx: int) -> void:
	var eq: Node = _player.equip
	match action:
		"fechar":
			_toggle()
		"largar":
			if eq.busy or _player.mode != _player.Mode.NORMAL:
				return
			eq.drop(idx)
		"empunhar":
			if eq.busy or _player.mode != _player.Mode.NORMAL:
				return
			eq.draw(idx)
		"guardar":
			eq.holster()


func _draw() -> void:
	_buttons.clear()
	if not open or _player == null:
		return
	var eq: Node = _player.equip
	var font := ThemeDB.fallback_font
	var x0 := size.x - W - 16.0
	var rows: int = eq.items.size() + (1 if not eq.held.is_empty() else 0)
	var h := 120.0 + maxf(rows, 1) * ROW
	var panel := Rect2(x0, 60.0, W, minf(h, size.y - 80.0))
	draw_rect(panel, Color(0.06, 0.06, 0.05, 0.86))
	draw_rect(panel, Color(0.8, 0.7, 0.45, 0.6), false, 2.0)
	var y := panel.position.y + 30.0
	draw_string(font, Vector2(x0 + 16, y), "EQUIPAMENTO", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.86, 0.5))
	_button(Rect2(panel.end.x - 46, panel.position.y + 8, 36, 30), "X", "fechar", -1)
	y += 26.0
	var lf: float = eq.load_factor()
	var vol: float = eq._volume_used()
	var c := Color(1, 1, 1) if lf > 0.9 else (Color(1, 0.8, 0.4) if lf > 0.75 else Color(1, 0.45, 0.35))
	draw_string(font, Vector2(x0 + 16, y), "Peso: %.1f kg   ·   Velocidade: %d%%   ·   Mochila: %.0f/%.0f L" % [eq.weight, lf * 100.0, vol, Itens.BACKPACK_L],
		HORIZONTAL_ALIGNMENT_LEFT, W - 32, 15, c)
	y += 10.0
	draw_rect(Rect2(x0 + 16, y, W - 32, 6), Color(1, 1, 1, 0.15))
	draw_rect(Rect2(x0 + 16, y, (W - 32) * clampf(eq.weight / eq.MAX_KG, 0.0, 1.0), 6), c)
	y += 22.0
	if rows == 0:
		draw_string(font, Vector2(x0 + 16, y + 20), "Nada além da mochila vazia (1,6 kg).", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.7))
		return
	if not eq.held.is_empty():
		_row(font, x0, y, eq.held, -1, true)
		y += ROW
	for i in eq.items.size():
		if y > panel.end.y - ROW * 0.5:
			break
		_row(font, x0, y, eq.items[i], i, false)
		y += ROW


func _row(font: Font, x0: float, y: float, it: Dictionary, idx: int, in_hand: bool) -> void:
	draw_line(Vector2(x0 + 12, y), Vector2(x0 + W - 12, y), Color(1, 1, 1, 0.1))
	draw_string(font, Vector2(x0 + 16, y + 20), Itens.nome(it.id), HORIZONTAL_ALIGNMENT_LEFT, 170, 16, Color(1, 1, 1))
	draw_string(font, Vector2(x0 + 16, y + 37), "%s · %.1f kg" % [SLOT_NAMES.get(it.slot, it.slot), Itens.peso(it.id)],
		HORIZONTAL_ALIGNMENT_LEFT, 220, 12, Color(1, 1, 1, 0.6))
	var bx := x0 + W - 112
	_button(Rect2(bx, y + 7, 96, 30), "LARGAR", "largar", idx)
	if in_hand:
		_button(Rect2(bx - 108, y + 7, 100, 30), "GUARDAR", "guardar", -1)
	elif Itens.is_gun(it.id):
		_button(Rect2(bx - 108, y + 7, 100, 30), "EMPUNHAR", "empunhar", idx)


func _button(r: Rect2, label: String, action: String, idx: int) -> void:
	draw_rect(r, Color(0.25, 0.22, 0.15, 0.9))
	draw_rect(r, Color(1, 0.85, 0.5, 0.7), false, 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 5), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, Color(1, 0.92, 0.7))
	_buttons.append([r, action, idx])
