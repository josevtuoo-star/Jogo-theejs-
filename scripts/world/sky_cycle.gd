class_name SkyCycle
extends Node
## Ciclo de dia e noite e clima.
##
## - O sol nasce a leste por volta das 6 h, passa alto ao meio-dia e se põe a
##   oeste às 18 h; à noite a lua dá uma luz fraca e azulada e o céu mostra
##   estrelas. A cor do céu, da luz, da névoa e a exposição seguem a hora
##   (madrugada, amanhecer alaranjado, dia, entardecer, noite escura).
## - O clima muda sozinho de tempos em tempos: LIMPO, NUBLADO, NEBLINA (mais
##   comum de manhã) e CHUVA (gotas caindo em volta da câmera, vento forte).
##   A névoa deixa de ser permanente: no tempo limpo só esconde a borda do
##   mundo carregado; na neblina fecha a poucas dezenas de metros.
## - A névoa é por profundidade, ajustada à distância de visão escolhida nas
##   configurações (quanto mais longe se vê, mais longe começa).
##
## A luz difusa, a exposição e a força do sol saem em `ambient_energy`,
## `exposure` e `sun_energy`; quem aplica é a CaveAtmosphere (que ainda baixa
## tudo dentro das cavernas). Sem ela, aplica aqui mesmo.

const WEATHERS := {
	"limpo": {"name": "Céu limpo", "begin": 0.6, "end": 1.0, "sun": 1.0, "cloud": 0.0, "rain": 0.0, "wind": 0.12},
	"nublado": {"name": "Nublado", "begin": 0.45, "end": 0.95, "sun": 0.5, "cloud": 0.7, "rain": 0.0, "wind": 0.25},
	"neblina": {"name": "Neblina", "begin": 0.0, "end": 0.38, "sun": 0.45, "cloud": 0.55, "rain": 0.0, "wind": 0.08},
	"chuva": {"name": "Chuva", "begin": 0.15, "end": 0.7, "sun": 0.3, "cloud": 0.9, "rain": 1.0, "wind": 0.5},
}

@export var environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var world: ProceduralWorld
@export var camera: Camera3D
## Hora do dia (0–24).
@export_range(0.0, 24.0, 0.01) var hour: float = 8.0
## Minutos reais por dia de jogo (nas configurações).
@export_range(2.0, 240.0, 1.0) var day_minutes: float = 24.0
@export var weather: String = "limpo"
## Falso: a CaveAtmosphere aplica luz difusa, exposição e sol.
var apply_light: bool = true

var sun_energy: float = 1.0
var ambient_energy: float = 1.1
var exposure: float = 0.95
## 0 = dia claro, 1 = noite escura (a lanterna de cabeça acende).
var darkness: float = 0.0

var _sky: ProceduralSkyMaterial
var _moon: DirectionalLight3D
var _rain: CPUParticles3D
var _from: Dictionary = WEATHERS["limpo"]
var _blend: float = 1.0
var _next_change: float = 6.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Antes da CaveAtmosphere, que usa os valores calculados aqui.
	process_priority = -10
	_rng.randomize()
	day_minutes = float(GameSession.settings.get("dia_minutos", day_minutes))
	GameSession.settings_changed.connect(func() -> void:
		day_minutes = float(GameSession.settings.get("dia_minutos", day_minutes))
		_apply_shadows())
	var env := environment.environment
	_sky = env.sky.sky_material as ProceduralSkyMaterial
	if _sky != null:
		_sky.sky_cover = _stars()
	# Luz difusa por cor (calculada aqui a cada quadro): o mapa de reflexo do
	# céu não acompanha a mudança de cor ao longo do dia (e custa no celular).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_depth_curve = 1.6
	_moon = DirectionalLight3D.new()
	_moon.name = "Lua"
	_moon.light_color = Color(0.6, 0.7, 1.0)
	_moon.shadow_enabled = false
	add_child(_moon)
	_rain = _make_rain()
	add_child(_rain)
	_from = WEATHERS.get(weather, WEATHERS["limpo"])
	_next_change = _rng.randf_range(3.0, 8.0)
	_apply_shadows()
	_update(0.0)


func _apply_shadows() -> void:
	if sun == null:
		return
	var quality := int(GameSession.settings.get("sombras", 1))
	sun.shadow_enabled = quality > 0
	sun.directional_shadow_max_distance = 50.0 if quality < 2 else 90.0


func set_weather(id: String, immediate: bool = false) -> void:
	if not WEATHERS.has(id):
		return
	_from = _current_weather()
	weather = id
	_blend = 1.0 if immediate else 0.0


func weather_name() -> String:
	return WEATHERS[weather]["name"]


## Hora como texto ("07:30").
func clock() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	hour = fmod(hour + delta * 24.0 / (day_minutes * 60.0), 24.0)
	_blend = minf(_blend + delta / 40.0, 1.0)
	# O clima muda de tempos em tempos (em horas de jogo).
	_next_change -= delta * 24.0 / (day_minutes * 60.0)
	if _next_change <= 0.0:
		_next_change = _rng.randf_range(3.0, 9.0)
		var roll := _rng.randf()
		var morning := hour > 4.0 and hour < 9.0
		var pick := "limpo"
		if roll < (0.35 if morning else 0.12):
			pick = "neblina"
		elif roll < 0.5:
			pick = "nublado"
		elif roll < 0.62:
			pick = "chuva"
		set_weather(pick)
	var w := _current_weather()
	# Sol: nasce a leste (6 h), ao norte do zênite ao meio-dia, põe-se a oeste.
	var day_angle := (hour - 6.0) / 12.0 * PI
	var elevation := sin(day_angle)
	var sun_dir := Vector3(-cos(day_angle), maxf(elevation, -0.3), 0.35).normalized()
	_aim(sun, sun_dir)
	_aim(_moon, -sun_dir + Vector3.UP * 0.4)
	# Crepúsculo longo: a claridade começa antes do sol aparecer e dura
	# depois que ele se põe.
	var daylight := smoothstep(-0.22, 0.2, elevation)
	var golden := smoothstep(0.4, 0.0, absf(elevation)) * smoothstep(-0.25, 0.05, elevation)
	darkness = 1.0 - smoothstep(-0.3, 0.02, elevation)
	var cloud: float = w["cloud"]
	sun_energy = daylight * float(w["sun"])
	ambient_energy = lerpf(0.22, 1.1, daylight) * lerpf(1.0, 0.85, cloud)
	exposure = lerpf(1.45, 0.95, daylight)
	if sun != null:
		sun.light_color = Color(1.0, 0.96, 0.9).lerp(Color(1.0, 0.62, 0.35), golden)
		sun.visible = daylight > 0.01
	_moon.light_energy = darkness * 0.22 * (1.0 - cloud * 0.6)
	_moon.visible = _moon.light_energy > 0.005
	var env := environment.environment
	# Céu: noite azul-escura, amanhecer/entardecer alaranjado, dia azul;
	# nublado puxa tudo para o cinza.
	var top := Color(0.025, 0.035, 0.07).lerp(Color(0.36, 0.48, 0.64), daylight)
	var horizon := Color(0.05, 0.07, 0.11).lerp(Color(0.66, 0.7, 0.73), daylight).lerp(Color(0.9, 0.58, 0.4), golden * 0.75)
	var grey := Color(0.5, 0.52, 0.54) * lerpf(0.15, 1.0, daylight)
	top = top.lerp(grey, cloud)
	horizon = horizon.lerp(grey * 1.05, cloud)
	if _sky != null:
		_sky.sky_top_color = top
		_sky.sky_horizon_color = horizon
		_sky.ground_horizon_color = horizon * 0.85
		_sky.ground_bottom_color = Color(0.08, 0.09, 0.08) * lerpf(0.2, 1.0, daylight)
		_sky.sun_curve = lerpf(0.06, 0.2, cloud)
		_sky.sky_cover_modulate = Color(1, 1, 1, darkness * (1.0 - cloud))
	env.ambient_light_color = horizon.lerp(top, 0.35).lerp(Color(0.62, 0.64, 0.66), 0.35 * daylight)
	# Névoa por profundidade, da cor do horizonte.
	var radius := (float(world.view_distance) + 0.5) * WorldGenerator.CHUNK_SIZE if world != null else 120.0
	env.fog_light_color = horizon.lerp(Color(0.6, 0.62, 0.62) * lerpf(0.15, 1.0, daylight), 0.4)
	env.fog_depth_begin = radius * float(w["begin"])
	env.fog_depth_end = maxf(radius * float(w["end"]), env.fog_depth_begin + 8.0)
	if apply_light:
		env.ambient_light_energy = ambient_energy
		env.tonemap_exposure = exposure
		if sun != null:
			sun.light_energy = sun_energy
	# Chuva em volta da câmera; vento mais forte.
	var rain: float = w["rain"]
	_rain.emitting = rain > 0.3
	if camera != null:
		_rain.global_position = camera.global_position + Vector3.UP * 12.0
	Wind.min_intensity = maxf(0.12, float(w["wind"]))


func _current_weather() -> Dictionary:
	var target: Dictionary = WEATHERS[weather]
	if _blend >= 1.0:
		return target
	var t := smoothstep(0.0, 1.0, _blend)
	var mixed := {}
	for key: String in target:
		if target[key] is float:
			mixed[key] = lerpf(float(_from.get(key, target[key])), float(target[key]), t)
		else:
			mixed[key] = target[key]
	return mixed


static func _aim(light: DirectionalLight3D, toward_light: Vector3) -> void:
	if light == null:
		return
	# A luz direcional aponta para -Z: olha do céu para o chão.
	var forward := -toward_light.normalized()
	var up := Vector3.UP if absf(forward.y) < 0.98 else Vector3.FORWARD
	light.global_basis = Basis.looking_at(forward, up)


## Estrelas: pontos claros espalhados (cobertura do céu, visível à noite).
static func _stars() -> Texture2D:
	var image := Image.create(1024, 512, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in 1400:
		var x := rng.randi_range(0, 1023)
		var y := rng.randi_range(0, 250)
		var b := rng.randf_range(0.35, 1.0)
		image.set_pixel(x, y, Color(b, b, b * 1.05, 1.0))
		if b > 0.9:
			image.set_pixel(mini(x + 1, 1023), y, Color(b, b, b, 0.6))
	return ImageTexture.create_from_image(image)


func _make_rain() -> CPUParticles3D:
	var rain := CPUParticles3D.new()
	rain.name = "Chuva"
	rain.amount = 700
	rain.lifetime = 1.1
	rain.local_coords = false
	rain.emitting = false
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(16.0, 1.0, 16.0)
	rain.direction = Vector3(0.08, -1.0, 0.04)
	rain.spread = 3.0
	rain.gravity = Vector3(0.0, -9.8, 0.0)
	rain.initial_velocity_min = 11.0
	rain.initial_velocity_max = 14.0
	var drop := QuadMesh.new()
	drop.size = Vector2(0.015, 0.45)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.75, 0.8, 0.88, 0.35)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = material
	rain.mesh = drop
	return rain


# --- Salvar ------------------------------------------------------------------------

func to_data() -> Dictionary:
	return {"hora": hour, "clima": weather}


func from_data(data: Dictionary) -> void:
	hour = float(data.get("hora", hour))
	set_weather(String(data.get("clima", weather)), true)
