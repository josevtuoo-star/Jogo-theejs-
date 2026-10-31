extends RigidBody3D
## Saco de pancada pendurado por uma junta (PinJoint3D): balança com os socos e conta os
## golpes. A corda é redesenhada a cada quadro entre o gancho e o topo do saco.

@export var anchor: Node3D
@export var rope: MeshInstance3D
@export var label: Label3D

var hits := 0
var strongest := 0.0


func on_punch(force: float, _point: Vector3) -> void:
	hits += 1
	strongest = maxf(strongest, force)
	if label:
		label.text = "SACO DE PANCADA\nGolpes: %d  ·  mais forte: %.0f" % [hits, strongest]


func _process(_delta: float) -> void:
	if rope == null or anchor == null:
		return
	var a := anchor.global_position
	var b := global_transform * Vector3(0, 0.62, 0)
	var mid := (a + b) * 0.5
	var len := a.distance_to(b)
	if len < 0.01:
		return
	var up := (a - b) / len
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up)
	rope.global_transform = Transform3D(Basis(side, up * len, fwd), mid)
