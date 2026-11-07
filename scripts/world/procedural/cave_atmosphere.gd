class_name CaveAtmosphere
extends Node
## Luz dentro das cavernas e lanterna de cabeça.
##
## Sem iluminação global, a luz difusa do céu iluminaria por igual o fundo de
## uma caverna. O terreno guarda em cada vértice quanto céu se enxerga dali
## (raios no campo de densidade): a luz entra pela boca e some aos poucos para
## dentro. Aqui, pela câmera: a lanterna acende, a luz difusa geral e o sol
## baixam (personagem e objetos dentro da caverna) e os olhos se acostumam. O
## céu não escurece: de dentro, a boca da caverna continua clara.
##
## Lanterna (diagnóstico da etapa 8): antes ela ficava 25 cm à frente dos
## olhos na direção da câmera. Olhando para baixo descia para dentro do peito;
## para cima, entrava no gorro. E o corpo do próprio sobrevivente (que em 1ª
## pessoa fica invisível mas projeta sombra para o sol) tapava a luz: uma
## silhueta enorme no chão à frente e o teto preto. Agora:
## - ela fica na testa, num ponto fixo da cabeça (pela direção do corpo, não
##   pela inclinação da câmera), apontada para onde o jogador olha;
## - o corpo do sobrevivente fica numa camada de desenho própria, excluída das
##   sombras da lanterna (shadow_caster_mask). Como numa lanterna de testa de
##   verdade, quase no eixo dos olhos, o corpo não sombreia a própria luz; o
##   sol continua desenhando a sombra do corpo, e a arma na mão continua
##   projetando sombra da lanterna (está à frente da testa);
## - o halo é um segundo foco largo, sem sombra, saindo do mesmo ponto, em
##   vez de uma luz pontual à frente que entrava nas paredes.

## Camada de desenho do corpo do jogador (bit 2). A câmera desenha todas.
const PLAYER_RENDER_LAYER := 1 << 1
const ALL_RENDER_LAYERS := 0xFFFFF

@export var world: ProceduralWorld
@export var camera: Camera3D
## Ponto dos olhos do sobrevivente (âncora da câmera em 1ª pessoa).
@export var eyes: Node3D
## Corpo do sobrevivente (as malhas vão para a camada do jogador).
@export var body: Node3D
@export var environment: WorldEnvironment
@export var sun: DirectionalLight3D
## Ciclo de dia e noite (opcional): dá a base da luz e acende a lanterna à noite.
@export var sky_cycle: SkyCycle:
	set(value):
		sky_cycle = value
		if value != null:
			value.apply_light = false
@export_range(0.0, 16.0, 0.1) var headlamp_energy: float = 6.0
## Segundos para os olhos "se acostumarem" (entrar/sair).
@export_range(0.1, 10.0, 0.1) var adapt_time: float = 1.6
## Luz que resta no fundo da caverna (fração da luz do céu): sem isto as
## superfícies fora do foco ficariam pretas.
@export_range(0.0, 1.0, 0.01) var cave_ambient: float = 0.35

## 0 = céu aberto, 1 = fundo da caverna.
var underground: float = 0.0
var headlamp: SpotLight3D
## Halo da lanterna (luz espalhada em volta do foco).
var spill: SpotLight3D
## Luz suave só no corpo e na ferramenta do jogador: o foco não os ilumina
## (a 30 cm da testa, a luz pelo inverso do quadrado estouraria o cabo da
## ferramenta em branco).
var body_fill: OmniLight3D

var _ambient: float
var _frame: int = 0
var _target: float = -1.0
var _sun_energy: float
var _exposure: float


func _ready() -> void:
	var env := environment.environment
	_ambient = env.ambient_light_energy
	_exposure = env.tonemap_exposure
	_sun_energy = sun.light_energy if sun != null else 0.0
	if body != null:
		for mesh: GeometryInstance3D in body.find_children("*", "GeometryInstance3D", true, false):
			mesh.layers = PLAYER_RENDER_LAYER
	headlamp = SpotLight3D.new()
	headlamp.name = "Lanterna"
	headlamp.light_color = Color(1.0, 0.93, 0.82)
	headlamp.spot_range = 30.0
	headlamp.spot_angle = 38.0
	# Borda suave (LED de lanterna de testa: foco central e transição larga).
	headlamp.spot_angle_attenuation = 0.55
	headlamp.spot_attenuation = 0.9
	headlamp.shadow_enabled = true
	# Rocha de células de 2 m vista de raspão: viés maior evita "acne" (listras
	# de sombra na própria superfície) sem descolar a sombra dos objetos.
	headlamp.shadow_bias = 0.06
	headlamp.shadow_normal_bias = 1.6
	headlamp.shadow_blur = 1.5
	headlamp.shadow_caster_mask = ALL_RENDER_LAYERS & ~PLAYER_RENDER_LAYER
	headlamp.light_cull_mask = ALL_RENDER_LAYERS & ~PLAYER_RENDER_LAYER
	headlamp.light_energy = 0.0
	headlamp.visible = false
	add_child(headlamp)
	spill = SpotLight3D.new()
	spill.name = "LanternaHalo"
	spill.light_color = Color(1.0, 0.93, 0.82)
	spill.spot_range = 12.0
	spill.spot_angle = 80.0
	spill.spot_angle_attenuation = 0.8
	spill.spot_attenuation = 1.2
	spill.shadow_enabled = false
	spill.light_cull_mask = ALL_RENDER_LAYERS & ~PLAYER_RENDER_LAYER
	spill.light_energy = 0.0
	spill.visible = false
	add_child(spill)
	body_fill = OmniLight3D.new()
	body_fill.name = "LanternaCorpo"
	body_fill.light_color = Color(1.0, 0.93, 0.82)
	body_fill.omni_range = 3.0
	body_fill.omni_attenuation = 0.6
	body_fill.shadow_enabled = false
	body_fill.light_cull_mask = PLAYER_RENDER_LAYER
	body_fill.light_energy = 0.0
	body_fill.visible = false
	add_child(body_fill)


## Quanto céu se enxerga de um ponto (1 = aberto, 0 = fundo da caverna).
func sky_visibility(point: Vector3) -> float:
	return world.generator.sky_visibility(point)


## Ponto da testa: acima e à frente dos olhos, no referencial horizontal do
## corpo (não acompanha a inclinação da câmera).
func forehead() -> Vector3:
	var origin := eyes.global_position if eyes != null else camera.global_position
	var forward := -camera.global_basis.z
	var flat := Vector3(forward.x, 0.0, forward.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	return origin + Vector3.UP * 0.07 + flat * 0.11


func _process(delta: float) -> void:
	if world == null or camera == null or world.generator == null:
		return
	# Céu visível pela câmera: medido a cada 3 quadros (13 raios no campo).
	_frame += 1
	if _frame % 3 == 0 or _target < 0.0:
		_target = 1.0 - sky_visibility(camera.global_position)
	var target := _target
	underground = move_toward(underground, target, delta / adapt_time)
	var u := underground
	var env := environment.environment
	# Com o ciclo de dia e noite, a base (luz difusa, exposição, sol) é a da hora.
	if sky_cycle != null:
		_ambient = sky_cycle.ambient_energy
		_exposure = sky_cycle.exposure
		_sun_energy = sky_cycle.sun_energy
	# O céu e a neblina não escurecem: a boca da caverna, vista de dentro,
	# continua clara. Quem escurece o fundo é o fator de céu de cada vértice
	# do terreno (luz difusa só onde o céu se vê). Aqui só baixam a luz
	# difusa geral (personagem e objetos dentro da caverna) e o sol, e os
	# olhos se acostumam (exposição).
	env.ambient_light_energy = lerpf(_ambient, _ambient * cave_ambient, u)
	env.tonemap_exposure = lerpf(_exposure, _exposure * 1.3, u)
	if sun != null:
		# As sombras do sol continuam ligadas: são elas que impedem a luz de
		# atravessar a rocha.
		sun.light_energy = lerpf(_sun_energy, _sun_energy * 0.25, u)
	# Acende na caverna e também à noite, ao ar livre.
	var night := smoothstep(0.55, 0.85, sky_cycle.darkness) if sky_cycle != null else 0.0
	var lamp := headlamp_energy * maxf(smoothstep(0.1, 0.45, u), night)
	headlamp.light_energy = lamp
	headlamp.visible = lamp > 0.01
	spill.light_energy = lamp * 0.22
	spill.visible = headlamp.visible
	body_fill.light_energy = lamp * 0.07
	body_fill.visible = headlamp.visible
	if headlamp.visible:
		var at := Transform3D(camera.global_basis, forehead())
		headlamp.global_transform = at
		spill.global_transform = at
		body_fill.global_position = at.origin - camera.global_basis.z * 0.9 + Vector3.UP * 0.25
