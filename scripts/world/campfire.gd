class_name Campfire
extends Interactable
## Fogueira que o jogador acende e apaga (interação no quadro de contato da
## mão). Acesa: luz quente que tremula de forma irregular, chamas e fumaça.

@export var light: OmniLight3D
@export var flames: GPUParticles3D
@export var smoke: GPUParticles3D
@export var is_lit: bool = false
## Energia média da luz acesa.
@export_range(0.0, 10.0, 0.1) var light_energy: float = 2.4

var _time: float = 0.0
var _sound: AudioStreamPlayer3D


func _ready() -> void:
	# Crepitar em laço, posicionado na fogueira (some com a distância).
	_sound = AudioStreamPlayer3D.new()
	var stream := SoundSet.load_set("world/fogueira").pick()
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		(stream as AudioStreamOggVorbis).loop = true
	_sound.stream = stream
	_sound.bus = &"Efeitos"
	_sound.unit_size = 2.5
	_sound.max_distance = 30.0
	_sound.volume_db = -2.0
	add_child(_sound)
	interacted.connect(func(_by: Node) -> void: set_lit(not is_lit))
	set_lit(is_lit)


func set_lit(lit: bool) -> void:
	is_lit = lit
	if light != null:
		light.visible = lit
	if flames != null:
		flames.emitting = lit
	if smoke != null:
		smoke.emitting = lit
	prompt = "Apagar a fogueira" if lit else "Acender a fogueira"
	if _sound != null:
		if lit and not _sound.playing:
			_sound.play()
		elif not lit:
			_sound.stop()


func _process(delta: float) -> void:
	if not is_lit or light == null:
		return
	_time += delta
	# Tremulação: soma de senos de frequências não múltiplas (sem padrão visível).
	var flicker := 0.82 + 0.10 * sin(_time * 7.3) + 0.06 * sin(_time * 13.1 + 1.7) + 0.04 * sin(_time * 23.7 + 0.4)
	light.light_energy = light_energy * flicker
	if _sound != null:
		_sound.pitch_scale = 0.95 + 0.1 * flicker
