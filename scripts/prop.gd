extends RigidBody3D
## Objeto com física que faz barulho ao bater (madeira, metal ou borracha), mais alto quanto
## mais forte a batida. Flutua na água conforme `buoyancy` (> 1 boia, < 1 afunda devagar).

@export var sound := "wood"
## empuxo na água em relação ao peso (1,6 = boia bem)
@export var buoyancy := 1.6

var _player: AudioStreamPlayer3D
var _cooldown := 0.0
var _prev_v := Vector3.ZERO


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_hit)
	_player = AudioStreamPlayer3D.new()
	_player.stream = Sfx.get_stream(sound)
	_player.unit_size = 4.0
	_player.max_polyphony = 2
	_player.bus = "Mundo"
	add_child(_player)


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	_prev_v = linear_velocity


func _on_hit(_body: Node) -> void:
	var hit := (_prev_v - linear_velocity).length()
	if hit < 0.7 or _cooldown > 0.0 or not Sfx.ready:
		return
	_cooldown = 0.09
	_player.volume_db = clampf(lerpf(-22.0, 2.0, hit / 7.0), -24.0, 3.0)
	_player.pitch_scale = randf_range(0.92, 1.08) * clampf(1.4 - mass / 60.0, 0.75, 1.3)
	_player.play()
