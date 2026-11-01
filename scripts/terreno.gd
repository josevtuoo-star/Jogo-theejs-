extends StaticBody3D
## Colisão de um bloco do terreno (100 m x 100 m), criada ao carregar a partir da própria malha
## do bloco (mesmos triângulos que aparecem na tela: os pés e os objetos apoiam certinho).

func _ready() -> void:
	var mi := get_parent() as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	add_child(cs)
