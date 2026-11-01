class_name SurfaceProfile
extends Resource
## Propriedades físicas de uma superfície pisável.
##
## Atribua a um corpo do cenário com o metadado "surface_profile" (Inspector →
## Metadata). Corpos sem o metadado usam o atrito do PhysicsMaterial como
## aderência; sem material, usam o perfil padrão do jogador.

## Identificador usado por áudio de passos, partículas e decalques.
@export var id: StringName = &"terra"
## Coeficiente de atrito entre calçado e superfície (μ). Limita a aceleração,
## a frenagem e as curvas: aceleração máxima = μ · g · aderência das pernas.
## Referências aproximadas: asfalto seco ~1,0; grama ~0,7; lama ~0,5; gelo ~0,08.
@export_range(0.02, 1.5, 0.01) var traction: float = 1.0
## Multiplicador da velocidade máxima (terreno fofo ou irregular reduz a passada).
@export_range(0.2, 1.2, 0.01) var speed_multiplier: float = 1.0
## Multiplicador do consumo de resistência ao correr.
@export_range(0.5, 3.0, 0.01) var stamina_multiplier: float = 1.0


## Cria um perfil derivado com outra aderência (usado para PhysicsMaterial).
func with_traction(new_traction: float) -> SurfaceProfile:
	var profile := duplicate() as SurfaceProfile
	profile.traction = clampf(new_traction, 0.02, 1.5)
	return profile
