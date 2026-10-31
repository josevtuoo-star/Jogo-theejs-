extends Node3D
## Sons de ambiente: vento contínuo, pássaros cantando de vez em quando nas árvores e a água
## do lago batendo nas bordas (som posicionado: mais alto perto do lago).

@export var bird_spots: Array[Vector3] = []
@export var lake_center := Vector3.ZERO

var _wind: AudioStreamPlayer
var _bird: AudioStreamPlayer3D
var _next_bird := 3.0
var _lake: AudioStreamPlayer3D
var _started := false


func _ready() -> void:
	_wind = AudioStreamPlayer.new()
	_wind.stream = Sfx.get_stream("wind")
	_wind.volume_db = -20.0
	_wind.bus = "Mundo"
	add_child(_wind)
	var lake := AudioStreamPlayer3D.new()
	lake.stream = Sfx.get_stream("water_lap")
	lake.volume_db = -6.0
	lake.unit_size = 5.0
	lake.max_distance = 30.0
	lake.bus = "Mundo"
	lake.position = lake_center
	add_child(lake)
	_lake = lake
	_bird = AudioStreamPlayer3D.new()
	_bird.stream = Sfx.get_stream("bird")
	_bird.unit_size = 12.0
	_bird.bus = "Mundo"
	add_child(_bird)


func _process(delta: float) -> void:
	Sfx.poll()
	Audio.update(delta)
	if not Sfx.ready:
		return
	if not _started:
		_started = true
		_wind.play()
		_lake.play()
	# o vento sobe e desce devagar
	_wind.volume_db = -20.0 + sin(Time.get_ticks_msec() * 0.0004) * 3.0
	_next_bird -= delta
	if _next_bird <= 0.0 and not bird_spots.is_empty():
		_next_bird = randf_range(2.5, 8.0)
		_bird.position = bird_spots[randi() % bird_spots.size()] + Vector3.UP * 4.0
		_bird.volume_db = randf_range(-14.0, -6.0)
		_bird.pitch_scale = randf_range(0.9, 1.15)
		_bird.play()
