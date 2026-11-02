class_name SoundSet
extends RefCounted
## Conjunto de variações de um som ("footsteps/terra" → terra_0.ogg, terra_1.ogg…).
## Sorteia sem repetir a última, com variação de tom, para nada soar
## mecânico. Funciona no APK (usa ResourceLoader.exists, não lista pastas).

const ROOT := "res://assets/audio/"

var streams: Array[AudioStream] = []
var _last: int = -1


static func load_set(prefix: String) -> SoundSet:
	var result := SoundSet.new()
	var single := ROOT + prefix + ".ogg"
	if ResourceLoader.exists(single):
		result.streams.append(load(single))
	var index := 0
	while ResourceLoader.exists(ROOT + "%s_%d.ogg" % [prefix, index]):
		result.streams.append(load(ROOT + "%s_%d.ogg" % [prefix, index]))
		index += 1
	if result.streams.is_empty():
		push_warning("Conjunto de sons vazio: " + prefix)
	return result


func pick() -> AudioStream:
	if streams.is_empty():
		return null
	if streams.size() == 1:
		return streams[0]
	var index := randi() % streams.size()
	if index == _last:
		index = (index + 1) % streams.size()
	_last = index
	return streams[index]
