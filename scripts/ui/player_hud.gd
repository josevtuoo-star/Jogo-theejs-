class_name PlayerHud
extends CanvasLayer
## HUD de sobrevivência: vida, resistência, lesão nas pernas, mira, objeto
## interagível em foco, clarão de dano, aviso do modo de câmera e tela de
## morte com renascer. Minimalista: a resistência some quando está cheia e o
## aviso de câmera aparece só na troca.

@export var player: PlayerController
@export var interaction: InteractionComponent
@export var death: PlayerDeath
## Opcional: se vazio, usa o CameraRig do jogador.
@export var camera_rig: PlayerCameraRig

const DAMAGE_KIND_NAMES := {
	&"queda": "queda", &"arame": "arame farpado", &"golpe": "golpe", &"mordida": "mordida",
}

var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _injury_label: Label
var _prompt_label: Label
var _flash: ColorRect
var _death_panel: Control
var _death_cause: Label
var _respawn_button: Button
var _flash_alpha: float = 0.0
var _interact_previous: bool = false
var _stamina_row: Control
var _camera_label: Label
var _camera_label_time: float = 0.0
var _crosshair: Control


func _ready() -> void:
	layer = 15
	_build()
	var health := player.health
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	death.respawned.connect(_on_respawned)
	interaction.focus_changed.connect(_on_focus_changed)
	_on_focus_changed(null)
	var combat := player.get_node_or_null("Combat") as MeleeCombat
	if combat != null:
		combat.guard_toggled.connect(func(enabled: bool) -> void:
			get_tree().call_group(&"block_toggle_button", &"set_active", enabled))
	if camera_rig == null:
		camera_rig = player.get_node_or_null("CameraRig") as PlayerCameraRig
	if camera_rig != null:
		camera_rig.mode_changed.connect(_on_camera_mode_changed)
		_on_camera_mode_changed.call_deferred(camera_rig.third_person, false)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0.55, 0.0, 0.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)

	# Sinais vitais no canto superior esquerdo, discretos.
	var vitals := VBoxContainer.new()
	vitals.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vitals.position = Vector2(24.0, 20.0)
	vitals.add_theme_constant_override("separation", 6)
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vitals)
	_health_bar = _bar(Color(0.70, 0.16, 0.13))
	_stamina_bar = _bar(Color(0.86, 0.72, 0.30))
	vitals.add_child(_row("VIDA", _health_bar))
	_stamina_row = _row("FÔLEGO", _stamina_bar)
	vitals.add_child(_stamina_row)
	# Sem componente de resistência (desligada por enquanto): sem barra.
	_stamina_row.visible = player.stamina != null
	_injury_label = Label.new()
	_injury_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_injury_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_injury_label.add_theme_constant_override("outline_size", 4)
	_injury_label.add_theme_font_size_override("font_size", 14)
	vitals.add_child(_injury_label)

	# Aviso do modo de câmera (aparece na troca e some).
	_camera_label = Label.new()
	_camera_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_camera_label.position = Vector2(-150.0, 24.0)
	_camera_label.custom_minimum_size = Vector2(300.0, 0.0)
	_camera_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_camera_label.add_theme_font_size_override("font_size", 16)
	_camera_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_camera_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_camera_label.add_theme_constant_override("outline_size", 4)
	_camera_label.modulate.a = 0.0
	_camera_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_camera_label)

	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(func() -> void:
		_crosshair.draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.35))
		_crosshair.draw_circle(Vector2.ZERO, 2.0, Color(1, 1, 1, 0.8)))
	root.add_child(_crosshair)

	_prompt_label = Label.new()
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_label.position = Vector2(-200.0, 26.0)
	_prompt_label.custom_minimum_size = Vector2(400.0, 0.0)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt_label.add_theme_constant_override("outline_size", 5)
	root.add_child(_prompt_label)

	_death_panel = ColorRect.new()
	(_death_panel as ColorRect).color = Color(0.03, 0.0, 0.0, 0.0)
	_death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_panel.visible = false
	root.add_child(_death_panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-200.0, -80.0)
	box.custom_minimum_size = Vector2(400.0, 160.0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_death_panel.add_child(box)
	var title := Label.new()
	title.text = "VOCÊ MORREU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.85, 0.15, 0.12))
	box.add_child(title)
	_death_cause = Label.new()
	_death_cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_cause.add_theme_font_size_override("font_size", 18)
	box.add_child(_death_cause)
	_respawn_button = Button.new()
	_respawn_button.text = "RENASCER"
	_respawn_button.custom_minimum_size = Vector2(220.0, 64.0)
	_respawn_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_respawn_button.add_theme_font_size_override("font_size", 22)
	_respawn_button.pressed.connect(_respawn)
	box.add_child(_respawn_button)


func _row(caption: String, bar: ProgressBar) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(64.0, 0.0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82, 0.85))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 3)
	row.add_child(label)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	return row


func _bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(180.0, 7.0)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.0, 0.0, 0.42)
	background.set_corner_radius_all(3)
	background.border_color = Color(1, 1, 1, 0.12)
	background.set_border_width_all(1)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", background)
	return bar


func _process(delta: float) -> void:
	var health := player.health
	_health_bar.value = health.get_ratio()
	if player.stamina != null:
		_stamina_bar.value = player.stamina.get_ratio()
		var full := player.stamina.get_ratio() >= 0.999
		_stamina_row.modulate.a = move_toward(_stamina_row.modulate.a, 0.0 if full else 1.0, delta * (0.7 if full else 4.0))
	if _camera_label_time > 0.0:
		_camera_label_time -= delta
		_camera_label.modulate.a = clampf(_camera_label_time / 0.4, 0.0, 1.0)
	_crosshair.visible = not health.is_dead
	_injury_label.text = "Perna ferida (%d%%)" % roundi(health.leg_injury * 100.0) if health.leg_injury > 0.05 else ""
	# Vida baixa: o vermelho pulsa no ritmo do coração.
	var low := clampf(1.0 - health.get_ratio() / 0.3, 0.0, 1.0) if not health.is_dead else 0.0
	var pulse := low * (0.12 + 0.06 * sin(Time.get_ticks_msec() * 0.008))
	_flash_alpha = maxf(_flash_alpha - delta * 1.6, 0.0)
	_flash.color.a = maxf(_flash_alpha, pulse)
	if interaction.focused != null and not player.health.is_dead:
		var key := "USAR" if GameInput.uses_touch_controls() else "[E]"
		_prompt_label.text = "%s  %s" % [key, interaction.focused.prompt]
	if _death_panel.visible:
		var panel := _death_panel as ColorRect
		panel.color.a = minf(panel.color.a + delta * 0.5, 0.75)
		_respawn_button.disabled = not death.can_respawn()
		var pressed := Input.is_action_pressed("interact")
		if pressed and not _interact_previous and death.can_respawn():
			_respawn()
		_interact_previous = pressed


func _on_damaged(amount: float, _kind: StringName, _direction: Vector3) -> void:
	_flash_alpha = clampf(_flash_alpha + 0.12 + amount / 60.0, 0.0, 0.6)


func _on_camera_mode_changed(third_person: bool, announce: bool = true) -> void:
	get_tree().call_group(&"camera_toggle_button", &"set_active", third_person)
	if announce:
		_camera_label.text = "Terceira pessoa" if third_person else "Primeira pessoa"
		_camera_label_time = 1.6


func _on_focus_changed(target: Interactable) -> void:
	if target == null:
		_prompt_label.text = ""
		return
	var key := "USAR" if GameInput.uses_touch_controls() else "[E]"
	_prompt_label.text = "%s  %s" % [key, target.prompt]


func _on_died() -> void:
	_death_panel.visible = true
	(_death_panel as ColorRect).color.a = 0.0
	var kind := player.health.last_damage_kind
	_death_cause.text = "Causa: %s" % DAMAGE_KIND_NAMES.get(kind, String(kind))
	_prompt_label.text = ""
	_interact_previous = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _respawn() -> void:
	if death.can_respawn():
		death.respawn()


func _on_respawned() -> void:
	_death_panel.visible = false
	_flash_alpha = 0.0
	if not GameInput.uses_touch_controls() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
