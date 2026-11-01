extends AnimatableBody3D
## Porta com dobradiça: USAR abre/fecha (gira 100°), com rangido e batida.

@export var open_angle := 100.0
var is_open := false
var _closed_yaw := 0.0
var _tween: Tween
var _snd: AudioStreamPlayer3D


func _ready() -> void:
	_closed_yaw = rotation.y
	add_to_group("usavel")
	_snd = AudioStreamPlayer3D.new()
	_snd.bus = "Mundo"
	_snd.unit_size = 5.0
	add_child(_snd)


func use_label() -> String:
	return "FECHAR PORTA" if is_open else "ABRIR PORTA"


## Onde fica a maçaneta (a mão do personagem vai até ela).
func handle_point() -> Vector3:
	return global_transform * Vector3(0.0, 1.0, 0.86)


func interact(player: Node) -> void:
	player.press(self)


## Chamado pelo personagem quando a mão alcança a maçaneta.
func activate() -> void:
	is_open = not is_open
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "rotation:y", _closed_yaw + deg_to_rad(open_angle if is_open else 0.0), 0.9)
	_snd.stream = Sfx.get_stream("door_open" if is_open else "door_close")
	_snd.play()
