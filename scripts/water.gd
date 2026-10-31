extends Area3D
## Volume de água:
## - avisa o personagem quando entra/sai e qual a altura da superfície;
## - empuxo: objetos com física boiam (ou afundam devagar), com arrasto da água;
## - espirro de água e som quando algo cai nela.

@export var surface_y := 0.0

var _splash: CPUParticles3D
var _snd: AudioStreamPlayer3D


func _ready() -> void:
	body_entered.connect(_on_enter)
	body_exited.connect(func(b: Node3D): if b.has_method("set_water"): b.set_water(null))
	_splash = CPUParticles3D.new()
	_splash.one_shot = true
	_splash.emitting = false
	_splash.amount = 24
	_splash.lifetime = 0.8
	_splash.explosiveness = 1.0
	_splash.direction = Vector3.UP
	_splash.spread = 35.0
	_splash.initial_velocity_min = 1.0
	_splash.initial_velocity_max = 3.0
	_splash.gravity = Vector3(0, -9.8, 0)
	var m := SphereMesh.new()
	m.radius = 0.04
	m.height = 0.08
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.93, 1.0, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	_splash.mesh = m
	_splash.top_level = true
	add_child(_splash)
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = Sfx.get_stream("splash")
	_snd.unit_size = 6.0
	_snd.bus = "Mundo"
	_snd.top_level = true
	add_child(_snd)


func _on_enter(b: Node3D) -> void:
	if b.has_method("set_water"):
		b.set_water(self)
	elif b is RigidBody3D and absf((b as RigidBody3D).linear_velocity.y) > 1.5:
		splash(b.global_position, clampf(absf((b as RigidBody3D).linear_velocity.y) / 6.0, 0.3, 1.0))


## Espirro de água na superfície (intensidade 0..1).
func splash(at: Vector3, strength: float) -> void:
	var p := Vector3(at.x, surface_y, at.z)
	_splash.global_position = p
	_splash.amount = int(lerpf(10, 34, strength))
	_splash.initial_velocity_max = lerpf(1.5, 4.0, strength)
	_splash.restart()
	if not Sfx.ready:
		return
	_snd.global_position = p
	_snd.volume_db = lerpf(-14.0, 2.0, strength)
	_snd.play()


func _physics_process(delta: float) -> void:
	for b in get_overlapping_bodies():
		var rb := b as RigidBody3D
		if rb == null:
			continue
		# quanto do objeto está submerso (aproximado pela altura da caixa envolvente)
		var half: float = rb.get_meta("meia_altura", -1.0)
		if half < 0.0:
			half = 0.3
			for c in rb.get_children():
				if c is CollisionShape3D and c.shape:
					half = c.shape.get_debug_mesh().get_aabb().size.y * 0.5
					break
			rb.set_meta("meia_altura", half)
		var sub := clampf((surface_y - (rb.global_position.y - half)) / (half * 2.0), 0.0, 1.0)
		if sub <= 0.0:
			continue
		var k: float = rb.get("buoyancy") if rb.get("buoyancy") != null else 1.2
		rb.sleeping = false
		rb.apply_central_force(Vector3.UP * rb.mass * 9.8 * k * sub)
		# arrasto da água (e um leve balanço das ondas)
		rb.linear_velocity *= 1.0 - minf(1.8 * delta * sub, 0.5)
		rb.angular_velocity *= 1.0 - minf(1.2 * delta * sub, 0.5)
		rb.apply_central_force(Vector3(sin(Time.get_ticks_msec() * 0.0011 + rb.global_position.x), 0.0,
			cos(Time.get_ticks_msec() * 0.0009 + rb.global_position.z)) * rb.mass * 0.15 * sub)
