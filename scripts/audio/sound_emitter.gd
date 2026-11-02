class_name SoundEmitter
extends Node3D
## Banco de vozes 3D: toca sons posicionados sem cortar o anterior (até
## `voices` ao mesmo tempo). Usado pelo jogador, objetos e mundo.

@export_range(1, 16, 1) var voices: int = 6
@export var bus: StringName = &"Efeitos"
@export_range(1.0, 200.0, 1.0) var max_distance: float = 45.0
@export_range(0.1, 20.0, 0.1) var unit_size: float = 3.0

var _players: Array[AudioStreamPlayer3D] = []
var _next: int = 0
## Diagnóstico e testes: quantos sons foram tocados por categoria.
var play_counts: Dictionary = {}
var last_played: StringName = &""


func _ready() -> void:
	for i in voices:
		var player := AudioStreamPlayer3D.new()
		player.bus = bus
		player.max_distance = max_distance
		player.unit_size = unit_size
		player.attenuation_filter_cutoff_hz = 9000.0
		player.attenuation_filter_db = -8.0
		add_child(player)
		_players.append(player)


## Toca um som do conjunto. `volume_db` relativo; `pitch` com variação
## aleatória de ±`pitch_jitter`. `at` (mundo) posiciona; senão, no emissor.
func play(category: StringName, sounds: SoundSet, volume_db: float = 0.0, pitch: float = 1.0,
		pitch_jitter: float = 0.06, at: Variant = null) -> void:
	if sounds == null:
		return
	var stream := sounds.pick()
	if stream == null or _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter), 0.1)
	player.global_position = at if at is Vector3 else global_position
	player.play()
	play_counts[category] = int(play_counts.get(category, 0)) + 1
	last_played = category


func count(category: StringName) -> int:
	return int(play_counts.get(category, 0))
