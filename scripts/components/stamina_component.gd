class_name StaminaComponent
extends Node
## Resistência física do sobrevivente.
##
## Correr e saltar consomem resistência. A regeneração só começa após um
## intervalo sem esforço. Ao zerar, o personagem entra em exaustão e só
## volta a correr depois de recuperar uma fração do total.

signal stamina_changed(current: float, maximum: float)
signal exhausted
signal recovered

@export_range(1.0, 1000.0, 1.0) var max_stamina: float = 100.0
## Pontos regenerados por segundo em repouso.
@export_range(0.0, 200.0, 0.5) var regen_rate: float = 14.0
## Fração da regeneração mantida enquanto o personagem anda (sem correr).
@export_range(0.0, 1.0, 0.01) var moving_regen_factor: float = 0.6
## Segundos sem esforço antes de começar a regenerar.
@export_range(0.0, 10.0, 0.05) var regen_delay: float = 1.1
## Fração do máximo necessária para sair da exaustão.
@export_range(0.0, 1.0, 0.01) var exhaustion_recover_ratio: float = 0.3

## Multiplicador externo de regeneração (fome, sede, ferimentos).
var regen_multiplier: float = 1.0
## Informado pelo controlador: o personagem está se deslocando.
var is_moving: bool = false

var current: float
var is_exhausted: bool = false
var _regen_cooldown: float = 0.0


func _ready() -> void:
	current = max_stamina


func _physics_process(delta: float) -> void:
	if _regen_cooldown > 0.0:
		_regen_cooldown = maxf(_regen_cooldown - delta, 0.0)
		return
	if current >= max_stamina:
		return
	var rate := regen_rate * regen_multiplier
	if is_moving:
		rate *= moving_regen_factor
	_set_current(current + rate * delta)


## Consome resistência de forma contínua. Retorna false se não havia o suficiente.
func drain(amount_per_second: float, delta: float) -> bool:
	if is_exhausted:
		return false
	var cost := amount_per_second * delta
	_regen_cooldown = regen_delay
	if current <= cost:
		_set_current(0.0)
		return false
	_set_current(current - cost)
	return true


## Consome uma quantidade fixa se houver o suficiente.
func try_consume(amount: float) -> bool:
	if is_exhausted or current < amount:
		return false
	_regen_cooldown = regen_delay
	_set_current(current - amount)
	return true


## Consome o que restar, até o valor pedido. Retorna a fração obtida (0 a 1).
func consume_partial(amount: float) -> float:
	if amount <= 0.0:
		return 1.0
	var taken := minf(current, amount)
	_regen_cooldown = regen_delay
	_set_current(current - taken)
	return taken / amount


func can_sprint() -> bool:
	return not is_exhausted and current > 0.0


func get_ratio() -> float:
	return current / max_stamina


func restore(amount: float) -> void:
	_set_current(current + amount)


func _set_current(value: float) -> void:
	var previous := current
	current = clampf(value, 0.0, max_stamina)
	if is_equal_approx(previous, current):
		return
	if current <= 0.0 and not is_exhausted:
		is_exhausted = true
		exhausted.emit()
	elif is_exhausted and current >= max_stamina * exhaustion_recover_ratio:
		is_exhausted = false
		recovered.emit()
	stamina_changed.emit(current, max_stamina)
