class_name Sfx
extends Object
## Sons gerados por código (o projeto não tem arquivos de som). Cada som curto é sintetizado em
## algumas variações (o jogo sorteia uma a cada vez, com tom e volume levemente diferentes,
## para nunca soar repetido) a partir de ruído filtrado, ressonadores (madeira, metal) e
## ondas graves com envelope. Vento, água e motor são laços contínuos.

const RATE := 22050
const VARIANTS := 3
static var _cache := {}

## laços (tocam sem parar)
const LOOPS := ["wind", "water_lap", "motor"]


const KINDS := ["step_grass", "step_hard", "step_water", "land", "cloth", "swish", "punch", "knock",
	"wood", "metal", "rubber", "splash", "splash_small", "stroke", "bubbles", "click", "pickup",
	"clunk", "breath_in", "breath_out", "bird", "wind", "water_lap", "motor"]

## verdadeiro quando todos os sons já foram gerados
static var ready := false
static var _queue := []
static var _started := false


## Som para tocar. Enquanto a geração não termina, devolve um "recipiente" vazio que é
## preenchido depois (quem guardou a referência passa a tocar normalmente).
static func get_stream(kind: String) -> AudioStream:
	if not _cache.has(kind):
		if kind in LOOPS:
			_cache[kind] = AudioStreamWAV.new()
		else:
			var r := AudioStreamRandomizer.new()
			r.random_pitch = 1.06
			r.random_volume_offset_db = 1.5
			_cache[kind] = r
	return _cache[kind]


## Prepara a fila de sons a gerar. A geração acontece aos poucos em poll(), na linha principal
## (sem threads: no Android, gerar sons numa thread separada fechava o jogo).
static func warmup() -> void:
	if _started:
		return
	_started = true
	for k in KINDS:
		get_stream(k)
		for v in (1 if k in LOOPS else VARIANTS):
			_queue.append([k, v])


## Chamado todo quadro: gera alguns sons por vez (até ~4 ms por quadro) e, quando a fila
## acaba, marca tudo como pronto.
static func poll() -> void:
	if ready or not _started:
		return
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - t0 < 4000:
		var item: Array = _queue.pop_front()
		var w := _render(item[0], item[1])
		var dst: AudioStream = get_stream(item[0])
		if dst is AudioStreamRandomizer:
			(dst as AudioStreamRandomizer).add_stream(-1, w)
		else:
			var d := dst as AudioStreamWAV
			d.format = w.format
			d.mix_rate = w.mix_rate
			d.stereo = w.stereo
			d.data = w.data
			d.loop_mode = w.loop_mode
			d.loop_begin = w.loop_begin
			d.loop_end = w.loop_end
	if _queue.is_empty():
		ready = true


static func _dur(kind: String) -> float:
	return {"step_grass": 0.17, "step_hard": 0.15, "step_water": 0.3, "land": 0.35, "cloth": 0.25,
		"swish": 0.3, "punch": 0.22, "knock": 0.28, "wood": 0.32, "metal": 0.9, "rubber": 0.18,
		"splash": 1.0, "splash_small": 0.45, "stroke": 0.5, "bubbles": 0.6, "click": 0.06,
		"pickup": 0.3, "clunk": 0.35, "breath_in": 0.7, "breath_out": 0.8, "bird": 0.9,
		"wind": 3.0, "water_lap": 3.0, "motor": 1.0}.get(kind, 0.2)


static func _render(kind: String, variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 7919
	var dur := _dur(kind) if kind in LOOPS else _dur(kind) * rng.randf_range(0.9, 1.1)
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# estados dos filtros
	var lp := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	var r1 := [0.0, 0.0]
	var r2 := [0.0, 0.0]
	var r3 := [0.0, 0.0]
	var r4 := [0.0, 0.0]
	var ph := 0.0
	var ph2 := 0.0
	var f0 := rng.randf_range(0.9, 1.1)
	# eventos aleatórios por variação (estalos da grama, bolhas, notas do pássaro)
	var grains := []
	for i in 14:
		grains.append([rng.randf_range(0.0, 0.12), rng.randf_range(0.2, 1.0)])
	var bubbles := []
	for i in 6:
		bubbles.append([rng.randf_range(0.05, dur * 0.8), rng.randf_range(350.0, 900.0)])
	var notes := []
	var nt := 0.0
	for i in rng.randi_range(3, 6):
		notes.append([nt, rng.randf_range(2200.0, 4200.0), rng.randf_range(-1.0, 1.0), rng.randf_range(0.05, 0.12)])
		nt += rng.randf_range(0.08, 0.18)
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var w := rng.randf_range(-1.0, 1.0)
		var v := 0.0
		match kind:
			"step_grass":
				# calcanhar abafado + ponta do pé, com estalos de folhas secas
				lp += (w - lp) * 0.18
				v = lp * (exp(-t * 38.0) + 0.55 * _env(t - 0.07, 45.0)) * 1.7
				v += sin(TAU * 75.0 * f0 * t) * exp(-t * 55.0) * 0.45
				lp2 += (w - lp2) * 0.6
				var crack := 0.0
				for g in (grains if t < 0.13 else []):
					var dt: float = t - g[0]
					if dt >= 0.0 and dt < 0.004:
						crack += g[1] * (1.0 - dt / 0.004)
				v += (w - lp2) * crack * 0.9
			"step_hard":
				# estalo seco do calcanhar no concreto + ponta do pé
				lp += (w - lp) * 0.55
				var click := (w - lp) * (exp(-t * 160.0) + 0.6 * _env(t - 0.065, 170.0))
				v = click * 1.1 + _res(r1, w * 0.06, 1100.0 * f0, 0.985) * (exp(-t * 60.0) + 0.5 * _env(t - 0.065, 70.0))
				v += sin(TAU * 105.0 * t) * exp(-t * 70.0) * 0.5
			"step_water":
				lp += (w - lp) * 0.25
				v = lp * (1.0 - exp(-t * 200.0)) * exp(-t * 11.0) * 1.6
				v += _bubbles(t, bubbles, 0.35)
			"land":
				var f := lerpf(70.0, 40.0, u)
				ph += TAU * f / RATE
				lp += (w - lp) * 0.07
				lp2 += (w - lp2) * 0.3
				v = sin(ph) * exp(-t * 14.0) * 1.0 + lp * exp(-t * 18.0) * 2.0 + lp2 * exp(-t * 40.0) * 0.4
			"cloth":
				lp += (w - lp) * 0.35
				lp2 += (lp - lp2) * 0.12
				var am := 0.5 + 0.5 * sin(TAU * (6.0 + variant * 2.0) * t + variant)
				v = (lp - lp2) * 2.2 * sin(PI * u) * am
			"swish":
				# "fuuu" do braço cortando o ar: filtro que abre e fecha
				var c := lerpf(0.04, 0.4, sin(PI * pow(u, 0.7)))
				lp += (w - lp) * c
				lp2 += (lp - lp2) * c * 0.5
				v = (lp - lp2) * 3.2 * pow(sin(PI * u), 1.5)
			"punch":
				# pancada no saco: estalo de couro + grave do impacto
				lp += (w - lp) * 0.5
				v = (w - lp) * exp(-t * 90.0) * 0.9
				v += _res(r1, w * 0.08, 240.0 * f0, 0.99) * exp(-t * 25.0)
				ph += TAU * lerpf(110.0, 55.0, u) / RATE
				v += sin(ph) * exp(-t * 20.0) * 0.9
			"knock":
				# batida em parede/estrutura: modos de ressonância
				var x := w * exp(-t * 400.0) * 0.4
				v = _res(r1, x, 180.0 * f0, 0.996) * 0.6 + _res(r2, x, 430.0 * f0, 0.993) * 0.4 + _res(r3, x, 770.0 * f0, 0.99) * 0.25
				v *= exp(-t * 12.0)
			"wood":
				var x := w * exp(-t * 600.0) * 0.5
				v = _res(r1, x, 230.0 * f0, 0.995) * 0.7 + _res(r2, x, 560.0 * f0, 0.992) * 0.45 + _res(r3, x, 1010.0 * f0, 0.988) * 0.3
				v *= exp(-t * 10.0)
			"metal":
				# barril de metal: parciais inarmônicos que soam por mais tempo
				var x := w * exp(-t * 800.0) * 0.4
				v = _res(r1, x, 310.0 * f0, 0.9993) * 0.5 + _res(r2, x, 815.0 * f0, 0.9991) * 0.4 \
					+ _res(r3, x, 1470.0 * f0, 0.9988) * 0.3 + _res(r4, x, 2330.0 * f0, 0.998) * 0.2
				v *= exp(-t * 4.0)
			"rubber":
				ph += TAU * lerpf(140.0, 70.0, u) / RATE
				lp += (w - lp) * 0.3
				v = sin(ph) * exp(-t * 28.0) * 1.0 + lp * exp(-t * 60.0) * 0.6
			"splash", "splash_small":
				var big := kind == "splash"
				lp += (w - lp) * (0.35 if big else 0.45)
				lp2 += (w - lp2) * 0.08
				var env := (1.0 - exp(-t * 120.0)) * (exp(-t * (4.0 if big else 9.0)) + exp(-t * 25.0) * 0.8)
				v = (lp * 1.2 + lp2 * 1.5) * env
				v += _bubbles(t, bubbles, 0.4 if big else 0.25)
			"stroke":
				# braçada: água empurrada
				lp += (w - lp) * 0.12
				lp2 += (w - lp2) * 0.4
				v = (lp * 1.6 + (lp2 - lp) * 0.3) * pow(sin(PI * u), 2.0)
				v += _bubbles(t, bubbles, 0.15)
			"bubbles":
				v = _bubbles(t, bubbles, 0.6)
			"click":
				v = sin(TAU * 2000.0 * t) * exp(-t * 260.0) + w * exp(-t * 500.0) * 0.6
			"pickup":
				# caixa de papelão/plástico sendo pega: chacoalho e baque leve
				lp += (w - lp) * 0.4
				v = lp * (exp(-t * 30.0) + 0.6 * _env(t - 0.09, 40.0)) * 1.2
				v += _res(r1, w * 0.05 * exp(-t * 200.0), 330.0 * f0, 0.99) * 0.6
			"clunk":
				var x := w * exp(-t * 300.0) * 0.5
				v = (_res(r1, x, 95.0, 0.997) + _res(r2, x, 260.0, 0.994) * 0.5 + _res(r3, x, 640.0, 0.99) * 0.3) * exp(-t * 9.0)
			"breath_in":
				# inspiração: ar passando, mais agudo, subindo
				lp += (w - lp) * 0.5
				lp2 += (lp - lp2) * 0.15
				v = (lp - lp2) * 1.4 * pow(sin(PI * u), 1.2) * (0.6 + 0.4 * u)
			"breath_out":
				# expiração: mais grave e "soprada", caindo
				lp += (w - lp) * 0.22
				lp2 += (lp - lp2) * 0.05
				v = (lp - lp2 * 0.5) * 1.5 * pow(sin(PI * pow(u, 0.6)), 1.3) * (1.0 - 0.5 * u)
			"bird":
				for nn in notes:
					var dt: float = t - nn[0]
					if dt >= 0.0 and dt < nn[3]:
						var k: float = dt / nn[3]
						var f: float = nn[1] * (1.0 + nn[2] * 0.25 * k) + sin(TAU * 38.0 * dt) * 150.0
						ph += TAU * f / RATE
						v += sin(ph) * sin(PI * k) * 0.6
			"wind":
				# vento: ruído grave com rajadas lentas e um assobio leve
				lp += (w - lp) * 0.025
				lp2 += (w - lp2) * 0.12
				lp3 += (lp2 - lp3) * 0.05
				var gust := 0.55 + 0.25 * sin(TAU * t / 3.0) + 0.2 * sin(TAU * t / 3.0 * 2.0 + 1.3)
				v = (lp * 3.2 + (lp2 - lp3) * 0.6 * gust) * gust
			"water_lap":
				lp += (w - lp) * 0.06
				lp2 += (w - lp2) * 0.3
				var wave := 0.5 + 0.5 * sin(TAU * t / 3.0 * 2.0) * sin(TAU * t / 3.0 + 0.7)
				v = (lp * 2.0 + (lp2 - lp) * 0.4 * wave) * (0.4 + 0.6 * wave)
				v += _bubbles(fmod(t, 1.3), bubbles, 0.08)
			"motor":
				# motor do portão: zumbido grave com harmônicos e chocalho
				ph += TAU * 50.0 / RATE
				ph2 += TAU * 150.0 / RATE
				lp += (w - lp) * 0.3
				v = sin(ph) * 0.4 + sin(ph2) * 0.2 + sin(ph * 5.0) * 0.08 + lp * 0.3 * (0.5 + 0.5 * sin(TAU * 12.0 * t))
		out[i] = v
	# corta os agudos de cada som (filtro de 24 dB/oitava): sem chiado artificial
	var cut: float = {"step_grass": 4500.0, "step_hard": 6000.0, "step_water": 3500.0, "land": 1600.0,
		"cloth": 4000.0, "swish": 3500.0, "punch": 4000.0, "rubber": 2500.0, "splash": 5000.0,
		"splash_small": 4500.0, "stroke": 1800.0, "breath_in": 3200.0, "breath_out": 2000.0,
		"wind": 900.0, "water_lap": 1400.0, "motor": 2500.0, "pickup": 4000.0}.get(kind, 0.0)
	if cut > 0.0:
		_lowpass(out, cut)
		_lowpass(out, cut)
	# laços: emenda o fim no começo (sem "clique" na repetição)
	if kind in LOOPS:
		var fade := int(0.4 * RATE)
		for i in fade:
			var k := float(i) / fade
			out[i] = out[i] * k + out[n - fade + i] * (1.0 - k)
		n -= fade
	# normaliza o pico e converte para 16 bits
	var peak := 0.0001
	for i in n:
		peak = maxf(peak, absf(out[i]))
	var gain := 0.85 / peak
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(out[i] * gain, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if kind in LOOPS:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


## Passa-baixa Butterworth de 2ª ordem (biquad), aplicado no lugar.
static func _lowpass(buf: PackedFloat32Array, fc: float) -> void:
	var w0 := TAU * fc / RATE
	var alpha := sin(w0) / (2.0 * 0.7071)
	var cw := cos(w0)
	var a0 := 1.0 + alpha
	var b0 := (1.0 - cw) * 0.5 / a0
	var b1 := (1.0 - cw) / a0
	var a1 := -2.0 * cw / a0
	var a2 := (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in buf.size():
		var x := buf[i]
		var y := b0 * x + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		buf[i] = y


static func _env(t: float, k: float) -> float:
	return exp(-t * k) if t >= 0.0 else 0.0


## Ressonador de 2 polos (modo de vibração de madeira, metal...).
static func _res(st: Array, x: float, freq: float, r: float) -> float:
	var w := TAU * freq / RATE
	var y: float = x + 2.0 * r * cos(w) * st[0] - r * r * st[1]
	st[1] = st[0]
	st[0] = y
	return y * (1.0 - r) * 8.0


## Bolhas: senoides curtas que sobem de tom.
static func _bubbles(t: float, list: Array, amp: float) -> float:
	var v := 0.0
	for b in list:
		var dt: float = t - b[0]
		if dt >= 0.0 and dt < 0.05:
			v += sin(TAU * b[1] * dt * (1.0 + dt * 12.0)) * exp(-dt * 70.0) * amp
	return v
