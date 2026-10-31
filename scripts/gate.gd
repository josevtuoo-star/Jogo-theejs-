extends AnimatableBody3D
## Portão de correr da garagem (corpo animado: empurra o que estiver no caminho).

## quanto o portão anda para abrir
@export var open_offset := Vector3(-6.0, 0.0, 0.0)
var is_open := false
var _closed := Vector3.ZERO
var _tween: Tween


func _ready() -> void:
	_closed = position


func toggle() -> void:
	is_open = not is_open
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "position", _closed + (open_offset if is_open else Vector3.ZERO), 2.4)
	var pl := AudioStreamPlayer3D.new()
	pl.stream = Sfx.get_stream("wood")
	pl.pitch_scale = 0.5
	add_child(pl)
	pl.play()
	pl.finished.connect(pl.queue_free)
