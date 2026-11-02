class_name ImpactSound
extends Node
## Som de batida de um corpo rígido (caixote, barril, galão, lata, pneu):
## toca quando ele bate em algo com velocidade, com o volume e o tom pela
## força do choque e o tipo de material. Filho direto do RigidBody3D.

## Material: "madeira", "metal", "borracha" ou "generico".
@export var material: StringName = &"generico"
## Velocidade relativa mínima para soar (m/s).
@export_range(0.1, 10.0, 0.05) var min_speed: float = 1.1
@export_range(0.0, 2.0, 0.01) var cooldown: float = 0.12

static var _sets: Dictionary = {}

var _body: RigidBody3D
var _emitter: SoundEmitter
var _last: float = -10.0
var _clock: float = 0.0
var _previous_velocity: Vector3 = Vector3.ZERO


## Material sonoro de um nó atingido (meta "impact_material" ou ImpactSound
## filho); alvos com receive_hit são "corpo".
static func material_of(node: Node) -> StringName:
	if node == null:
		return &"generico"
	if node.has_method(&"receive_hit"):
		return &"corpo"
	if node.has_meta(&"impact_material"):
		return StringName(node.get_meta(&"impact_material"))
	for child in node.get_children():
		if child is ImpactSound:
			return (child as ImpactSound).material
	return &"generico"


static func set_for(material_name: StringName) -> SoundSet:
	var key := String(material_name)
	if not _sets.has(key):
		match material_name:
			&"madeira":
				_sets[key] = SoundSet.load_set("props/madeira_cai")
			&"metal":
				_sets[key] = SoundSet.load_set("props/metal_cai")
			_:
				_sets[key] = SoundSet.load_set("combat/impacto_generico")
	return _sets[key]


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		return
	_body.contact_monitor = true
	_body.max_contacts_reported = maxi(_body.max_contacts_reported, 2)
	_body.body_entered.connect(_on_body_entered)
	_emitter = SoundEmitter.new()
	_emitter.voices = 2
	_emitter.max_distance = 35.0
	add_child(_emitter)


func _physics_process(delta: float) -> void:
	_clock += delta
	if _body != null:
		_previous_velocity = _body.linear_velocity


func _on_body_entered(other: Node) -> void:
	var other_velocity := (other as RigidBody3D).linear_velocity if other is RigidBody3D else Vector3.ZERO
	var speed := (_previous_velocity - other_velocity).length()
	if speed < min_speed or _clock - _last < cooldown:
		return
	_last = _clock
	var strength := clampf((speed - min_speed) / 6.0, 0.0, 1.0)
	var volume := lerpf(-14.0, 0.0, strength)
	# Objetos leves soam mais agudos.
	var pitch := clampf(1.25 - _body.mass / 80.0, 0.75, 1.25)
	_emitter.play(&"impacto", set_for(material), volume, pitch, 0.08, _body.global_position)
