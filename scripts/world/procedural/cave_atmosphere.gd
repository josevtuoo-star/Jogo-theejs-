class_name CaveAtmosphere
extends Node
## Luz dentro das cavernas.
##
## Sem iluminação global, a luz difusa do céu iluminaria por igual o fundo de
## uma caverna. Quando a câmera está sob a terra (rocha acima da cabeça), a
## luz do céu, os reflexos, o sol e a cor da neblina descem até quase o
## escuro, e a lanterna de cabeça do sobrevivente acende. Na boca da caverna a
## transição é gradual. O terreno também escurece pelas cores de vértice
## (fator de céu aberto); isto cuida do resto (personagem, objetos, céu).

@export var world: ProceduralWorld
@export var camera: Camera3D
## Ponto dos olhos do sobrevivente (a lanterna fica na testa, não na câmera:
## em 3ª pessoa a câmera está atrás do corpo).
@export var eyes: Node3D
@export var environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export_range(0.0, 16.0, 0.1) var headlamp_energy: float = 6.0
## Segundos para os olhos "se acostumarem" (entrar/sair).
@export_range(0.1, 10.0, 0.1) var adapt_time: float = 1.6

## 0 = céu aberto, 1 = fundo da caverna.
var underground: float = 0.0
var headlamp: SpotLight3D
## Luz espalhada da lanterna (o halo em volta do foco): sem sombra, fraca e
## curta, deixa ver o entorno e o próprio corpo em 3ª pessoa.
var spill: OmniLight3D

var _ambient: float
var _background: float
var _fog_color: Color
var _fog_density: float
var _sun_energy: float
var _exposure: float


func _ready() -> void:
	var env := environment.environment
	_ambient = env.ambient_light_energy
	_background = env.background_energy_multiplier
	_fog_color = env.fog_light_color
	_fog_density = env.fog_density
	_exposure = env.tonemap_exposure
	_sun_energy = sun.light_energy if sun != null else 0.0
	headlamp = SpotLight3D.new()
	headlamp.name = "Lanterna"
	headlamp.light_color = Color(1.0, 0.92, 0.8)
	headlamp.spot_range = 30.0
	headlamp.spot_angle = 42.0
	headlamp.spot_angle_attenuation = 1.6
	headlamp.spot_attenuation = 0.9
	headlamp.shadow_enabled = true
	headlamp.light_energy = 0.0
	headlamp.visible = false
	add_child(headlamp)
	spill = OmniLight3D.new()
	spill.name = "LanternaHalo"
	spill.light_color = Color(1.0, 0.92, 0.8)
	spill.omni_range = 9.0
	spill.omni_attenuation = 1.6
	spill.shadow_enabled = false
	spill.light_energy = 0.0
	spill.visible = false
	add_child(spill)


## Profundidade sob a rocha no ponto (0 se há céu aberto acima).
func cover_depth(point: Vector3) -> float:
	var generator := world.generator
	var depth := generator.surface_height(point.x, point.z) - point.y
	if depth < 1.0:
		return 0.0
	# Há rocha entre a cabeça e o céu? (amostras subindo até a superfície)
	var y := point.y + 2.0
	while y < point.y + depth:
		if generator.density(point.x, y, point.z) > 0.0:
			return depth
		y += 2.5
	return 0.0


func _process(delta: float) -> void:
	if world == null or camera == null or world.generator == null:
		return
	var target := smoothstep(1.5, 9.0, cover_depth(camera.global_position))
	underground = move_toward(underground, target, delta / adapt_time)
	var u := underground
	var env := environment.environment
	env.ambient_light_energy = lerpf(_ambient, 0.015, u)
	env.background_energy_multiplier = lerpf(_background, 0.04, u)
	env.fog_light_color = _fog_color.lerp(Color(0.015, 0.016, 0.018), u)
	env.fog_density = lerpf(_fog_density, 0.03, u)
	env.tonemap_exposure = lerpf(_exposure, _exposure * 1.25, u)
	if sun != null:
		sun.light_energy = lerpf(_sun_energy, 0.0, u)
	var lamp := headlamp_energy * smoothstep(0.1, 0.45, u)
	headlamp.light_energy = lamp
	headlamp.visible = lamp > 0.01
	spill.light_energy = lamp * 0.16
	spill.visible = headlamp.visible
	if headlamp.visible:
		# Na testa, 25 cm à frente (fora da cabeça, que em 1ª pessoa só
		# projeta sombra), apontada para onde o jogador olha.
		var origin := eyes.global_position if eyes != null else camera.global_position
		var forward := -camera.global_basis.z
		headlamp.global_transform = Transform3D(camera.global_basis, origin + forward * 0.25 + Vector3.UP * 0.05)
		spill.global_position = origin + forward * 0.9 + Vector3.UP * 0.2
