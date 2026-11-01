class_name MovementDebugHud
extends Label
## Painel de diagnóstico do movimento (F3 alterna). Mostra os valores físicos
## reais do controlador para calibração em dispositivo.

@export var player: PlayerController

const STATE_NAMES := {
	PlayerController.MovementState.IDLE: "parado",
	PlayerController.MovementState.WALKING: "andando",
	PlayerController.MovementState.JOGGING: "trotando",
	PlayerController.MovementState.SPRINTING: "correndo",
	PlayerController.MovementState.CROUCH_IDLE: "agachado",
	PlayerController.MovementState.CROUCH_WALKING: "agachado andando",
	PlayerController.MovementState.AIRBORNE: "no ar",
	PlayerController.MovementState.SLIDING: "escorregando",
}

var _last_damage: float = 0.0
var _last_impact: float = 0.0
var _footsteps: int = 0
var _last_wall_impact: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if player == null:
		return
	player.fall_damage_taken.connect(func(amount: float, _impact: float) -> void: _last_damage = amount)
	player.landed.connect(func(impact: float) -> void: _last_impact = impact)
	player.footstep.connect(func(_intensity: float, _left: bool, _surface: SurfaceProfile) -> void: _footsteps += 1)
	player.wall_impact.connect(func(speed: float, _normal: Vector3) -> void: _last_wall_impact = speed)


## Cargas de teste alternadas com F4 (o inventário definirá a carga real).
const DEBUG_LOADS: Array[float] = [0.0, 20.0, 40.0, 60.0]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		visible = not visible
	elif event.is_action_pressed("debug_cycle_load") and player != null:
		var index := DEBUG_LOADS.find(player.carried_mass)
		player.carried_mass = DEBUG_LOADS[(index + 1) % DEBUG_LOADS.size()]


func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	var stamina_text := "-"
	if player.stamina != null:
		stamina_text = "%.0f/%.0f%s" % [player.stamina.current, player.stamina.max_stamina,
				" (exausto)" if player.stamina.is_exhausted else ""]
	text = ("FPS %d\nEstado: %s%s\nVelocidade: %.2f m/s (alvo %.2f, vertical %.2f)\nNo chão: %s | Superfície: %s (μ %.2f)\n"
			+ "Altura do corpo: %.2f m | Carga: %.0f kg\nResistência: %s\nÚltimo impacto: %.1f m/s | dano %.1f | parede %.1f m/s\nPassos: %d") % [
		Engine.get_frames_per_second(),
		STATE_NAMES.get(player.movement_state, "?"),
		" (modo andar)" if player.is_walk_mode else "",
		player.get_horizontal_speed(),
		player.get_target_speed(),
		player.velocity.y,
		"sim" if player.is_grounded() else "não",
		player.current_surface.id,
		player.current_surface.traction,
		player.get_current_height(),
		player.carried_mass,
		stamina_text,
		_last_impact,
		_last_damage,
		_last_wall_impact,
		_footsteps,
	]
