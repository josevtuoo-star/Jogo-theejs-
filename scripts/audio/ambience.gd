class_name Ambience
extends Node
## Ambiente da floresta em três camadas que não andam juntas (nenhum laço
## óbvio): o som de fundo da mata, vento na copa com rajadas e passarinhos
## que somem e voltam em ondas lentas. Presente, como numa floresta de
## verdade, mas sem cobrir os passos.

@export var bed_volume_db: float = -2.0
@export var wind_volume_db: float = -6.0
@export var birds_volume_db: float = -7.0
## Período (s) da onda de volume dos passarinhos.
@export_range(5.0, 300.0, 1.0) var birds_cycle: float = 47.0

var _bed: AudioStreamPlayer
var _birds: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _time: float = 0.0


func _ready() -> void:
	_bed = _looping("ambience/floresta", bed_volume_db)
	_birds = _looping("ambience/passaros", birds_volume_db)
	_wind = _looping("ambience/vento", wind_volume_db)


func _looping(prefix: String, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var stream := SoundSet.load_set(prefix).pick()
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		(stream as AudioStreamOggVorbis).loop = true
	player.stream = stream
	player.bus = &"Ambiente"
	player.volume_db = volume_db
	player.autoplay = true
	add_child(player)
	return player


func _process(delta: float) -> void:
	_time += delta
	var wave := 0.5 + 0.5 * sin(TAU * _time / birds_cycle)
	_birds.volume_db = birds_volume_db + lerpf(-14.0, 0.0, wave)
	# O vento sobe quando os passarinhos calam (ciclos diferentes, defasados).
	var gust := 0.5 + 0.5 * sin(TAU * _time / 31.0 + 1.3)
	_wind.volume_db = wind_volume_db + lerpf(-6.0, 0.0, gust)
