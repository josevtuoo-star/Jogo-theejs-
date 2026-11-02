extends Node
## Autoload "Wind": o vento do mundo. Uma única intensidade (0 = calmaria,
## 1 = vendaval) move a copa das árvores (parâmetro global de shader
## `wind_intensity`) e o som do ambiente, que é só o vento:
## - volume e tom sobem com a intensidade;
## - vento fraco é abafado (passa-baixa ~500 Hz no barramento Vento) e
##   vento forte abre para o chiado das agulhas (~4,5 kHz);
## - a intensidade muda devagar (tempo de minutos) com rajadas por cima
##   (alguns segundos), sem repetir um padrão.

## Faixa da intensidade de fundo (antes das rajadas).
@export_range(0.0, 1.0, 0.01) var min_intensity: float = 0.12
@export_range(0.0, 1.0, 0.01) var max_intensity: float = 0.75
## Força das rajadas sobre o fundo.
@export_range(0.0, 1.0, 0.01) var gustiness: float = 0.45

## Intensidade atual (0..1). Pode ser fixada por `override` (testes, clima).
var intensity: float = 0.3
var override: float = -1.0

var _time: float = 0.0
var _slow := FastNoiseLite.new()
var _gusts := FastNoiseLite.new()
var _player: AudioStreamPlayer
var _filter: AudioEffectLowPassFilter


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_slow.seed = 911
	_slow.frequency = 0.004
	_gusts.seed = 433
	_gusts.frequency = 0.09
	_gusts.fractal_octaves = 2
	_player = AudioStreamPlayer.new()
	var stream := SoundSet.load_set("ambience/vento").pick()
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		(stream as AudioStreamOggVorbis).loop = true
	_player.stream = stream
	_player.bus = &"Vento" if AudioServer.get_bus_index(&"Vento") >= 0 else &"Master"
	_player.volume_db = -40.0
	add_child(_player)
	var bus := AudioServer.get_bus_index(&"Vento")
	if bus >= 0:
		for i in AudioServer.get_bus_effect_count(bus):
			if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
				_filter = AudioServer.get_bus_effect(bus, i)
	if _player.stream != null:
		_player.play()


func _process(delta: float) -> void:
	_time += delta
	var base := lerpf(min_intensity, max_intensity, 0.5 + 0.5 * _slow.get_noise_1d(_time))
	var gust := maxf(_gusts.get_noise_1d(_time), 0.0) * 2.0 # rajadas só somam
	var target := clampf(base + gust * gustiness * base, 0.0, 1.0)
	if override >= 0.0:
		target = override
	intensity = lerpf(intensity, target, 1.0 - exp(-1.5 * delta))
	RenderingServer.global_shader_parameter_set(&"wind_intensity", intensity)
	# Som: o vento fraco quase não se ouve; forte, enche o ambiente.
	_player.volume_db = lerpf(-34.0, -6.0, pow(intensity, 0.7))
	_player.pitch_scale = lerpf(0.85, 1.15, intensity)
	if _filter != null:
		_filter.cutoff_hz = lerpf(500.0, 4500.0, intensity * intensity)
