class_name Interactable
extends Node
## Marca um objeto do cenário como interagível.
##
## Coloque como filho de um CollisionObject3D (StaticBody3D, RigidBody3D,
## Area3D) na camada "interagiveis" (5) ou "mundo" (1). O InteractionComponent
## do jogador o encontra pelo raio de visão e chama interact() no quadro de
## contato da animação de interação.

signal interacted(by: Node)

## Texto mostrado na tela enquanto o objeto está em foco.
@export var prompt: String = "Usar"
@export var enabled: bool = true


func interact(by: Node) -> void:
	if enabled:
		interacted.emit(by)


## Procura o Interactable associado a um corpo atingido pelo raio: o próprio
## nó, um filho direto ou o pai.
static func find_on(node: Node) -> Interactable:
	if node == null:
		return null
	if node is Interactable:
		return node
	for child in node.get_children():
		if child is Interactable:
			return child
	var parent := node.get_parent()
	if parent is Interactable:
		return parent
	return null
