class_name Sfx
extends Object
## Sons gerados por código (não há arquivos de som no projeto): passos, pancadas, socos,
## água, roupa e cliques são sintetizados uma vez ao abrir o jogo a partir de ruído filtrado
## e ondas graves com envelope.

const RATE := 22050
static var _cache := {}


static func get_stream(kind: String) -> AudioStreamWAV:
	if not _cache.has(kind):
		_cache[kind] = _make(kind)
	return _cache[kind]


static func _make(kind: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var dur := 0.12
	match kind:
		"step_grass": dur = 0.11
		"step_hard": dur = 0.09
		"thud": dur = 0.22
		"punch": dur = 0.16
		"swish": dur = 0.25
		"splash": dur = 0.7
		"stroke": dur = 0.35
		"click": dur = 0.05
		"cloth": dur = 0.18
		"pickup": dur = 0.2
		"wood": dur = 0.18
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var noise := rng.randf_range(-1.0, 1.0)
		var v := 0.0
		match kind:
			"step_grass":
				# farfalhar abafado
				lp += (noise - lp) * 0.25
				v = lp * exp(-t * 45.0) * 1.6 + sin(TAU * 90.0 * t) * exp(-t * 60.0) * 0.5
			"step_hard":
				lp += (noise - lp) * 0.6
				v = lp * exp(-t * 70.0) * 1.2 + sin(TAU * 140.0 * t) * exp(-t * 80.0) * 0.6
			"thud":
				var f := lerpf(80.0, 38.0, u)
				lp += (noise - lp) * 0.08
				v = sin(TAU * f * t) * exp(-t * 18.0) * 0.9 + lp * exp(-t * 25.0) * 1.5
			"punch":
				lp += (noise - lp) * 0.35
				v = lp * exp(-t * 40.0) * 1.4 + sin(TAU * lerpf(120.0, 55.0, u) * t) * exp(-t * 22.0) * 0.8
			"swish":
				# "fuuu" do golpe no ar: ruído que sobe e desce
				lp += (noise - lp) * lerpf(0.05, 0.35, sin(PI * u))
				lp2 += (lp - lp2) * 0.5
				v = (lp - lp2) * 3.0 * sin(PI * u)
			"splash":
				lp += (noise - lp) * 0.3
				v = lp * (exp(-t * 6.0) * 0.9 + exp(-t * 30.0) * 0.6) * (0.7 + 0.3 * sin(TAU * 13.0 * t))
			"stroke":
				lp += (noise - lp) * 0.15
				v = lp * sin(PI * u) * 1.2
			"click":
				v = sin(TAU * 1800.0 * t) * exp(-t * 300.0) + noise * exp(-t * 400.0) * 0.5
			"cloth":
				lp += (noise - lp) * 0.2
				lp2 += (lp - lp2) * 0.3
				v = (lp - lp2) * 2.5 * sin(PI * u)
			"pickup":
				lp += (noise - lp) * 0.3
				v = lp * exp(-t * 30.0) + sin(TAU * 220.0 * t) * exp(-t * 35.0) * 0.4
			"wood":
				v = (sin(TAU * 180.0 * t) * 0.6 + sin(TAU * 410.0 * t) * 0.3) * exp(-t * 28.0) + noise * exp(-t * 60.0) * 0.4
		var s := int(clampf(v, -1.0, 1.0) * 26000.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
