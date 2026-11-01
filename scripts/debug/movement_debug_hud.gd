class_name MovementDebugHud
extends Label
## Painel de diagnóstico do movimento (F3 alterna). Mostra os valores físicos
## reais do controlador para calibração em dispositivo.

@export var player: PlayerController

const STATE_NAMES := {
	PlayerController.MovementState.IDLE: "parado",
	PlayerController.MovementState.WALKING: "andando",
	PlayerController.MovementState.SPRINTING: "correndo",
	PlayerController.MovementState.CROUCH_IDLE: "agachado",
	PlayerController.MovementState.CROUCH_WALKING: "agachado andando",
	PlayerController.MovementState.AIRBORNE: "no ar",
}

var _last_damage: float = 0.0
var _last_impact: float = 0.0
var _footsteps: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if player == null:
		return
	player.fall_damage_taken.connect(func(amount: float, _impact: float) -> void: _last_damage = amount)
	player.landed.connect(func(impact: float) -> void: _last_impact = impact)
	player.footstep.connect(func(_intensity: float, _left: bool) -> void: _footsteps += 1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		visible = not visible


func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	var stamina_text := "-"
	if player.stamina != null:
		stamina_text = "%.0f/%.0f%s" % [player.stamina.current, player.stamina.max_stamina,
				" (exausto)" if player.stamina.is_exhausted else ""]
	text = "FPS %d\nEstado: %s\nVelocidade: %.2f m/s (vertical %.2f)\nNo chão: %s\nAltura do corpo: %.2f m\nResistência: %s\nÚltimo impacto: %.1f m/s | dano %.1f\nPassos: %d" % [
		Engine.get_frames_per_second(),
		STATE_NAMES.get(player.movement_state, "?"),
		player.get_horizontal_speed(),
		player.velocity.y,
		"sim" if player.is_grounded() else "não",
		player.get_current_height(),
		stamina_text,
		_last_impact,
		_last_damage,
		_footsteps,
	]
