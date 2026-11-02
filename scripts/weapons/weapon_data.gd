class_name WeaponData
extends Resource
## Arma branca: aparência e números de combate. Os golpes usam as animações
## de arma (weapon_swing_a rápido, weapon_swing_b carregado) e o mesmo
## sistema de impacto pela extensão real do braço, somando o comprimento da
## arma (`reach`).

@export var id: StringName = &""
@export var display_name: String = ""
## Malha com a empunhadura na origem, cabo em +Y (para a cabeça da arma) e o
## lado que golpeia em +Z.
@export var mesh: Mesh
@export_range(0.1, 10.0, 0.05) var mass: float = 2.0
## Alcance além do punho (m): comprimento útil da arma.
@export_range(0.0, 1.5, 0.01) var reach: float = 0.55
@export_range(0.02, 0.4, 0.01) var hit_radius: float = 0.14

@export_group("Golpe rápido")
@export_range(0.0, 300.0, 0.5) var light_damage: float = 22.0
@export_range(0.0, 300.0, 0.5) var light_impulse: float = 14.0
## Velocidade da animação (armas pesadas são mais lentas).
@export_range(0.3, 2.0, 0.01) var light_speed: float = 1.0
@export_range(0.0, 2.0, 0.01) var light_recovery: float = 0.18

@export_group("Golpe carregado")
@export_range(0.0, 300.0, 0.5) var heavy_min_damage: float = 32.0
@export_range(0.0, 300.0, 0.5) var heavy_max_damage: float = 55.0
@export_range(0.0, 300.0, 0.5) var heavy_min_impulse: float = 22.0
@export_range(0.0, 300.0, 0.5) var heavy_max_impulse: float = 45.0
@export_range(0.0, 2.0, 0.01) var heavy_recovery: float = 0.35

@export_group("Som")
## Material de quem golpeia ("metal" ou "madeira"): muda o som do acerto.
@export var impact_material: StringName = &"metal"
