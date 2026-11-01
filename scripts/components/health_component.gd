class_name HealthComponent
extends Node
## Vida do sobrevivente, lesões nas pernas e morte.
##
## Toda fonte de dano chama apply_damage() com um tipo (queda, arame, golpe,
## mordida...) e a direção de onde veio. Quedas fortes também lesionam as
## pernas: o personagem manca, perde velocidade e não consegue correr até a
## lesão cicatrizar.

signal health_changed(current: float, maximum: float)
## direction: direção (mundo) de onde o dano veio; zero se não houver.
signal damaged(amount: float, kind: StringName, direction: Vector3)
signal died
signal revived
signal leg_injury_changed(amount: float)

@export_range(1.0, 1000.0, 1.0) var max_health: float = 100.0
## Dano de queda que corresponde a lesão total das pernas.
@export_range(1.0, 200.0, 1.0) var fall_damage_for_full_leg_injury: float = 60.0
## Cicatrização natural da lesão nas pernas (fração por segundo).
@export_range(0.0, 1.0, 0.001) var leg_heal_rate: float = 0.01

var current: float
var is_dead: bool = false
## 0 = pernas sãs, 1 = lesão grave.
var leg_injury: float = 0.0
var last_damage_kind: StringName = &""


func _ready() -> void:
	current = max_health


func _physics_process(delta: float) -> void:
	if leg_injury > 0.0 and not is_dead:
		set_leg_injury(leg_injury - leg_heal_rate * delta)


func apply_damage(amount: float, kind: StringName, direction: Vector3 = Vector3.ZERO) -> void:
	if is_dead or amount <= 0.0:
		return
	last_damage_kind = kind
	current = maxf(current - amount, 0.0)
	health_changed.emit(current, max_health)
	damaged.emit(amount, kind, direction)
	if current <= 0.0:
		is_dead = true
		died.emit()


## Dano de queda: tira vida e lesiona as pernas proporcionalmente.
func apply_fall_damage(amount: float) -> void:
	set_leg_injury(maxf(leg_injury, amount / fall_damage_for_full_leg_injury))
	apply_damage(amount, &"queda", Vector3.DOWN)


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current = minf(current + amount, max_health)
	health_changed.emit(current, max_health)


func set_leg_injury(amount: float) -> void:
	var clamped := clampf(amount, 0.0, 1.0)
	if is_equal_approx(clamped, leg_injury):
		return
	leg_injury = clamped
	leg_injury_changed.emit(leg_injury)


## Restaura vida e pernas (renascer).
func revive() -> void:
	is_dead = false
	current = max_health
	last_damage_kind = &""
	set_leg_injury(0.0)
	health_changed.emit(current, max_health)
	revived.emit()


func get_ratio() -> float:
	return current / max_health
