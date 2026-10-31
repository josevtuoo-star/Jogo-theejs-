class_name Audio
extends Object
## Barramentos de áudio criados ao abrir o jogo:
## - "Mundo": todos os sons do jogo passam por aqui; tem eco (reverb) que aumenta dentro de
##   lugares fechados e um filtro que abafa tudo quando a câmera está debaixo d'água.

static var _ready := false
static var _bus := -1
static var _reverb: AudioEffectReverb
static var _lowpass: AudioEffectLowPassFilter
static var indoor := false
static var underwater := false


static func setup() -> void:
	if _ready:
		return
	_ready = true
	_bus = AudioServer.bus_count
	AudioServer.add_bus(_bus)
	AudioServer.set_bus_name(_bus, "Mundo")
	AudioServer.set_bus_send(_bus, "Master")
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.35
	_reverb.damping = 0.6
	_reverb.wet = 0.05
	_reverb.dry = 1.0
	AudioServer.add_bus_effect(_bus, _reverb)
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(_bus, _lowpass)


## Chamado todo quadro pelo jogo: aproxima os efeitos do estado atual.
static func update(delta: float) -> void:
	if not _ready:
		return
	_reverb.wet = lerpf(_reverb.wet, 0.32 if indoor else 0.05, 1.0 - exp(-4.0 * delta))
	_reverb.room_size = lerpf(_reverb.room_size, 0.55 if indoor else 0.35, 1.0 - exp(-4.0 * delta))
	var cut := 650.0 if underwater else 20000.0
	_lowpass.cutoff_hz = lerpf(_lowpass.cutoff_hz, cut, 1.0 - exp(-8.0 * delta))
