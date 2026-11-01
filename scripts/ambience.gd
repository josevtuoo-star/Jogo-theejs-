extends Node3D
## Sons de ambiente: vento contínuo (sobe e desce), pássaros e insetos gravados vindos das
## árvores mais perto do personagem (som posicionado, trocando de árvore devagar) e a água do
## lago batendo nas bordas (mais alto perto do lago). Dentro das cabanas o vento abafa.

@export var bird_spots: Array[Vector3] = []
@export var lake_center := Vector3.ZERO

var _wind: AudioStreamPlayer
var _birds: AudioStreamPlayer3D
var _insects: AudioStreamPlayer
var _lake: AudioStreamPlayer3D
var _started := false
var _spot_t := 0.0


func _ready() -> void:
	_wind = AudioStreamPlayer.new()
	_wind.stream = Sfx.get_stream("wind")
	_wind.volume_db = -20.0
	_wind.bus = "Mundo"
	add_child(_wind)
	_lake = AudioStreamPlayer3D.new()
	_lake.stream = Sfx.get_stream("water_lap")
	_lake.volume_db = -4.0
	_lake.unit_size = 8.0
	_lake.max_distance = 70.0
	_lake.bus = "Mundo"
	_lake.position = lake_center
	add_child(_lake)
	_birds = AudioStreamPlayer3D.new()
	_birds.stream = Sfx.get_stream("birds")
	_birds.unit_size = 25.0
	_birds.max_distance = 120.0
	_birds.volume_db = -14.0
	_birds.bus = "Mundo"
	add_child(_birds)
	_insects = AudioStreamPlayer.new()
	_insects.stream = Sfx.get_stream("insects")
	_insects.volume_db = -30.0
	_insects.bus = "Mundo"
	add_child(_insects)


func _process(delta: float) -> void:
	Sfx.poll()
	Audio.update(delta)
	if not _started:
		_started = true
		_birds.play()
		_insects.play()
	if Sfx.ready and not _wind.playing:
		_wind.play()
		_lake.play()
	# o vento sobe e desce devagar (rajadas); dentro de casa fica bem mais baixo
	var t := Time.get_ticks_msec() * 0.001
	var gust := sin(t * 0.4) * 3.0 + sin(t * 0.13 + 1.0) * 2.0
	_wind.volume_db = lerpf(_wind.volume_db, -19.0 + gust - (9.0 if Audio.indoor else 0.0), 1.0 - exp(-2.0 * delta))
	_insects.volume_db = -28.0 + sin(t * 0.21) * 2.0
	# pássaros: na árvore mais perto do jogador (troca a cada poucos segundos)
	_spot_t -= delta
	var cam := get_viewport().get_camera_3d()
	if _spot_t <= 0.0 and cam and not bird_spots.is_empty():
		_spot_t = 6.0
		var best := bird_spots[0]
		for s in bird_spots:
			if s.distance_squared_to(cam.global_position) < best.distance_squared_to(cam.global_position):
				best = s
		_birds.position = best + Vector3.UP * 8.0
