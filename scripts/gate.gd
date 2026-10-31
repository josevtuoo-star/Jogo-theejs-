extends AnimatableBody3D
## Portão de correr da garagem (corpo animado: empurra o que estiver no caminho), com som de
## motor enquanto anda e uma pancada metálica ao chegar no fim.

## quanto o portão anda para abrir
@export var open_offset := Vector3(-6.0, 0.0, 0.0)
var is_open := false
var _closed := Vector3.ZERO
var _tween: Tween
var _motor: AudioStreamPlayer3D
var _clunk: AudioStreamPlayer3D


func _ready() -> void:
	_closed = position
	_motor = _sound("motor", -6.0)
	_clunk = _sound("clunk", 0.0)


func _sound(kind: String, db: float) -> AudioStreamPlayer3D:
	var pl := AudioStreamPlayer3D.new()
	pl.stream = Sfx.get_stream(kind)
	pl.volume_db = db
	pl.unit_size = 6.0
	pl.bus = "Mundo"
	add_child(pl)
	return pl


func toggle() -> void:
	is_open = not is_open
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "position", _closed + (open_offset if is_open else Vector3.ZERO), 2.4)
	_tween.finished.connect(_on_stop)
	if Sfx.ready:
		_motor.play()


func _on_stop() -> void:
	_motor.stop()
	if Sfx.ready:
		_clunk.play()
