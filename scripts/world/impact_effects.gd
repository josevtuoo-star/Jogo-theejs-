class_name ImpactEffects
extends RefCounted
## Efeitos de um golpe num ponto do mundo: estilhaços (partículas curtas,
## com gravidade, na cor do material) e um som 3D. Leves para o celular:
## partículas de CPU, poucas, e o nó se apaga sozinho ao terminar.

const MATERIALS := {
	&"madeira": [Color(0.55, 0.42, 0.27), Color(0.33, 0.24, 0.15)],
	&"casca": [Color(0.3, 0.22, 0.15), Color(0.2, 0.15, 0.1)],
	&"pedra": [Color(0.55, 0.53, 0.5), Color(0.38, 0.36, 0.34)],
	&"carvao": [Color(0.08, 0.08, 0.09), Color(0.35, 0.34, 0.33)],
	&"ferro": [Color(0.45, 0.22, 0.12), Color(0.5, 0.48, 0.45)],
	&"sangue": [Color(0.35, 0.03, 0.03), Color(0.22, 0.02, 0.02)],
}


static var _sets: Dictionary = {}


## Estilhaços saindo da superfície (`normal`) no ponto do golpe.
static func burst(parent: Node, at: Vector3, normal: Vector3, material: StringName, count: int = 14,
		size: float = 0.04, speed: float = 3.0) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var colors: Array = MATERIALS.get(material, MATERIALS[&"pedra"])
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = count
	particles.lifetime = 0.9
	particles.explosiveness = 0.95
	particles.direction = normal if normal.length_squared() > 0.01 else Vector3.UP
	particles.spread = 55.0
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.gravity = Vector3(0.0, -9.8, 0.0)
	particles.angular_velocity_min = -360.0
	particles.angular_velocity_max = 360.0
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.4
	var gradient := Gradient.new()
	gradient.set_color(0, colors[0])
	gradient.set_color(1, colors[1])
	particles.color_initial_ramp = gradient
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.roughness = 0.9
	mesh.material = paint
	particles.mesh = mesh
	parent.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	return particles


## Som 3D de um conjunto (assets/audio/<chave>_N.ogg) no ponto.
static func sound(parent: Node, at: Vector3, key: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if not _sets.has(key):
		_sets[key] = SoundSet.load_set(key)
	var sounds: SoundSet = _sets[key]
	if sounds == null:
		return
	var stream := sounds.pick()
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = &"Efeitos"
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.94, 1.06)
	player.unit_size = 6.0
	player.max_distance = 60.0
	parent.add_child(player)
	player.global_position = at
	player.play()
	player.finished.connect(player.queue_free)
