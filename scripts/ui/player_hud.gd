class_name PlayerHud
extends CanvasLayer
## HUD de sobrevivência: vida, resistência, lesão nas pernas, mira, objeto
## interagível em foco, clarão de dano e tela de morte com renascer.

@export var player: PlayerController
@export var interaction: InteractionComponent
@export var death: PlayerDeath

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


func _ready() -> void:
	layer = 15
	_build()
	var health := player.health
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	death.respawned.connect(_on_respawned)
	interaction.focus_changed.connect(_on_focus_changed)
	_on_focus_changed(null)


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

	var vitals := VBoxContainer.new()
	vitals.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vitals.position = Vector2(-120.0, 12.0)
	vitals.custom_minimum_size = Vector2(240.0, 0.0)
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vitals)
	_health_bar = _bar(Color(0.72, 0.12, 0.10))
	_stamina_bar = _bar(Color(0.85, 0.70, 0.20))
	vitals.add_child(_health_bar)
	vitals.add_child(_stamina_bar)
	_injury_label = Label.new()
	_injury_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_injury_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_injury_label.add_theme_font_size_override("font_size", 14)
	vitals.add_child(_injury_label)

	var crosshair := Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(func() -> void: crosshair.draw_circle(Vector2.ZERO, 2.5, Color(1, 1, 1, 0.75)))
	root.add_child(crosshair)

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


func _bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(240.0, 10.0)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", background)
	return bar


func _process(delta: float) -> void:
	var health := player.health
	_health_bar.value = health.get_ratio()
	if player.stamina != null:
		_stamina_bar.value = player.stamina.get_ratio()
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
