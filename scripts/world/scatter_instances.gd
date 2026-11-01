class_name ScatterInstances
extends MultiMeshInstance3D
## Instâncias de uma malha (árvores, troncos, vegetação) montadas em tempo de
## execução a partir de transformações salvas na cena.
##
## Por que não salvar o MultiMesh pronto: o buffer de instâncias vive no
## servidor de renderização; cenas geradas por ferramentas sem janela
## (--headless) salvariam o MultiMesh vazio. Guardar as transformações aqui e
## montar no _ready funciona em qualquer renderizador e no Android.

@export var mesh: Mesh
@export var transforms: Array[Transform3D] = []
## Esconde a partir desta distância da câmera (0 = sempre visível).
@export_range(0.0, 1000.0, 1.0) var max_distance: float = 0.0


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	multimesh = multi
	if max_distance > 0.0:
		visibility_range_end = max_distance
		visibility_range_end_margin = max_distance * 0.1
		visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	# O AABB do servidor sem renderização é vazio: calcula-o daqui.
	if mesh != null and not transforms.is_empty():
		var local := mesh.get_aabb()
		var box := transforms[0] * local
		for t in transforms:
			box = box.merge(t * local)
		custom_aabb = box
