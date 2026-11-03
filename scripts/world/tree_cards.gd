class_name TreeCards
extends RefCounted
## Malhas das árvores por impostor: três planos cruzados com os quadros do
## atlas renderizado de um abeto real (tools/bake_tree_impostors.gd), e o
## tronco de casca de pinheiro. Usadas pelo mapa de demonstração e pelo
## mundo procedural.

const ATLAS := "res://resources/textures/trees/fir_cards.png"
const BARK := "res://assets/polyhaven/textures/pine_bark/pine_bark_"
const HEIGHTS := [9.0, 7.95, 6.02]


## Árvores dos outros biomas (etapa 9, tools/bake_broadleaf_impostors.gd):
## folhosa, a mesma seca e árvore-aljava. Quadros quadrados (lado em metros).
const BROADLEAF_ATLAS := "res://resources/textures/trees/broadleaf_cards.png"
const BROADLEAF_SIDES := [4.65, 4.65, 2.77]
const BROADLEAF_TINTS := [Color(0.82, 0.88, 0.76), Color(0.85, 0.83, 0.8), Color(0.9, 0.92, 0.82)]


## Copa das variantes 3, 4 e 5 (folhosa, seca, aljava).
static func broadleaf_mesh(row: int) -> ArrayMesh:
	var mesh := card_mesh(row, load(BROADLEAF_ATLAS), BROADLEAF_SIDES[row], 1.0)
	var material := mesh.surface_get_material(0) as ShaderMaterial
	var tint: Color = BROADLEAF_TINTS[row]
	material.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	if row == 1:
		# Galhos secos: sem a luz atravessando folhas.
		material.set_shader_parameter("translucency", Vector3(0.04, 0.035, 0.03))
	return mesh


## Três planos cruzados (0°, 60°, 120°) com os quadros da variante no atlas.
## `frame_height` (m) e `aspect` (largura/altura do quadro) servem ao atlas
## dos outros biomas; sem eles, o dos abetos.
static func card_mesh(variant: int, atlas: Texture2D = null, frame_height: float = 0.0, aspect: float = 0.5) -> ArrayMesh:
	if atlas == null:
		atlas = load(ATLAS)
	var height: float = HEIGHTS[variant] if frame_height <= 0.0 else frame_height
	var width := height * aspect
	var bottom := -height * 0.01
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for column in 3:
		var basis := Basis(Vector3.UP, deg_to_rad(column * 60.0))
		var u0 := column / 3.0
		var u1 := (column + 1) / 3.0
		var v0 := variant / 3.0
		var v1 := (variant + 1) / 3.0
		var base := vertices.size()
		vertices.append(basis * Vector3(-width * 0.5, bottom, 0.0))
		vertices.append(basis * Vector3(width * 0.5, bottom, 0.0))
		vertices.append(basis * Vector3(width * 0.5, bottom + height, 0.0))
		vertices.append(basis * Vector3(-width * 0.5, bottom + height, 0.0))
		uvs.append_array([Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)])
		indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = load("res://resources/materials/tree_card.gdshader")
	material.set_shader_parameter("atlas", atlas)
	material.set_shader_parameter("card_height", height)
	mesh.surface_set_material(0, material)
	mesh.custom_aabb = AABB(Vector3(-width, bottom, -width), Vector3(width * 2.0, height, width * 2.0))
	return mesh


## Tronco (cilindro de 1 m afinando para cima), escalado por árvore.
static func trunk_mesh() -> CylinderMesh:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.05
	trunk.bottom_radius = 0.17
	trunk.height = 1.0
	trunk.radial_segments = 8
	trunk.rings = 1
	var bark := ORMMaterial3D.new()
	bark.albedo_texture = load(BARK + "albedo_1k.jpg")
	bark.normal_enabled = true
	bark.normal_texture = load(BARK + "normal_1k.jpg")
	bark.orm_texture = load(BARK + "arm_1k.jpg")
	bark.uv1_scale = Vector3(2.0, 4.0, 1.0)
	trunk.material = bark
	return trunk
