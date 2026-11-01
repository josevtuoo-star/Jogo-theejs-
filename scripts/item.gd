extends "res://scripts/prop.gd"
## Item no chão (ou numa mesa) que dá para pegar. Tem o peso de verdade (massa do corpo
## físico), faz barulho ao cair e boia/afunda na água. Ao pegar, o modelo sai daqui e vai para a
## mão do personagem e depois para o lugar do corpo onde ele guarda (equipamento.gd); ao largar,
## volta a ser um objeto com física.

@export var item_id := ""


func _ready() -> void:
	super._ready()
	_home = global_transform
	add_to_group("usavel")
	buoyancy = 0.6 if mass > 2.0 else 1.3


func use_label() -> String:
	return "PEGAR %s (%.1f kg)" % [Itens.nome(item_id).to_upper(), mass]


func interact(player: Node) -> void:
	player.equip.pick(self)


var _safe := Transform3D()
var _home := Transform3D()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# rede de segurança: se a física "explodir" (NaN), volta para a última posição boa
	if global_transform.origin.is_finite() and linear_velocity.is_finite():
		_safe = global_transform
	elif _safe != Transform3D():
		global_transform = _safe
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	# atravessou o chão (acontece com objetos pequenos em pisos finos): volta para onde estava
	if global_position.y < _home.origin.y - 25.0:
		global_transform = _home.translated(Vector3.UP * 0.3)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
