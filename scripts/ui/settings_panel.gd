class_name SettingsPanel
extends VBoxContainer
## CONFIGURAÇÕES (menu inicial e menu de pausa): distância de visão, sombras,
## sensibilidade da câmera e duração do dia. Botões grandes para o dedo; vale
## na hora e fica gravado (GameSession.settings).

const DISTANCES := [[2, "Curta"], [3, "Média"], [4, "Longa"], [5, "Muito longa"], [6, "Máxima"]]
const SHADOWS := [[0, "Desligadas"], [1, "Baixas"], [2, "Altas"]]
const DAYS := [[12.0, "12 min"], [24.0, "24 min"], [48.0, "48 min"], [96.0, "96 min"]]

var _sensitivity: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_row("Distância de visão (mais longe pesa mais no celular)", "distancia", DISTANCES)
	_row("Sombras", "sombras", SHADOWS)
	_row("Duração de um dia no jogo", "dia_minutos", DAYS)
	add_child(MenuStyle.label("Sensibilidade da câmera", 15))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.add_child(MenuStyle.button("–", func() -> void: _nudge(-0.1), 70.0))
	_sensitivity = MenuStyle.label("", 18)
	_sensitivity.custom_minimum_size = Vector2(90.0, 0.0)
	_sensitivity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(_sensitivity)
	line.add_child(MenuStyle.button("+", func() -> void: _nudge(0.1), 70.0))
	add_child(line)
	_refresh_sensitivity()


func _row(title: String, key: String, options: Array) -> void:
	add_child(MenuStyle.label(title, 15))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	add_child(line)
	for option: Array in options:
		var button := MenuStyle.button(option[1], Callable(), 0.0)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0.0, 50.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		button.button_pressed = is_equal_approx(float(GameSession.settings.get(key, -1)), float(option[0]))
		var value: Variant = option[0]
		button.pressed.connect(func() -> void:
			for other: Button in line.get_children():
				other.set_pressed_no_signal(other == button)
			GameSession.set_setting(key, value))
		line.add_child(button)


func _nudge(step: float) -> void:
	var value := clampf(snappedf(float(GameSession.settings.get("sensibilidade", 1.0)) + step, 0.1), 0.4, 2.5)
	GameSession.set_setting("sensibilidade", value)
	_refresh_sensitivity()


func _refresh_sensitivity() -> void:
	_sensitivity.text = "%.1f×" % float(GameSession.settings.get("sensibilidade", 1.0))
