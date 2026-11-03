class_name ZombieLook
extends RefCounted
## Variedade de zumbis: roupas de quem eles eram (policial, operário, civil,
## esfarrapado, sem camisa), pele em tons de decomposição, sangue e encardido
## por vértice (pose de repouso), altura e magreza diferentes, postura
## (cabeça caída, tronco curvado, braço pendente) e passo próprio.

const SKINS := [Color(0.55, 0.58, 0.48), Color(0.62, 0.58, 0.43), Color(0.5, 0.5, 0.5),
		Color(0.4, 0.38, 0.32), Color(0.6, 0.52, 0.5)]

## Roupas: cor por parte (CharacterLook.PARTS). "pele" na roupa = parte à mostra.
const OUTFITS := [
	{"nome": "policial", "jaqueta": Color(0.1, 0.12, 0.2), "calca": Color(0.08, 0.09, 0.15),
			"botas": Color(0.04, 0.04, 0.04), "gorro": Color(0.08, 0.09, 0.14), "sangue": 0.65},
	{"nome": "operario", "jaqueta": Color(0.85, 0.42, 0.06), "calca": Color(0.22, 0.22, 0.2),
			"botas": Color(0.3, 0.2, 0.1), "gorro": Color(0.8, 0.68, 0.1), "sangue": 0.5},
	{"nome": "civil", "jaqueta": Color(0.48, 0.12, 0.1), "calca": Color(0.15, 0.2, 0.32),
			"botas": Color(0.32, 0.24, 0.16), "gorro": "cabelo", "sangue": 0.7},
	{"nome": "esfarrapado", "jaqueta": Color(0.3, 0.27, 0.19), "calca": Color(0.25, 0.22, 0.16),
			"botas": Color(0.18, 0.14, 0.1), "gorro": Color(0.2, 0.18, 0.15), "sangue": 0.45},
	{"nome": "sem_camisa", "jaqueta": "pele", "calca": Color(0.17, 0.17, 0.19),
			"botas": "pele", "gorro": "cabelo", "sangue": 0.6, "magro": true},
]

static var _meshes: Dictionary = {}


## Veste o corpo `body` (cena survivor) com a variante `variant` e devolve a
## descrição usada (para postura e passo).
static func dress(body: Node, variant: int, rng: RandomNumberGenerator) -> Dictionary:
	var outfit: Dictionary = OUTFITS[posmod(variant, OUTFITS.size())]
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	var hair := Color(0.08, 0.07, 0.06).lerp(Color(0.4, 0.38, 0.35), rng.randf())
	var pattern := rng.randi() % 4
	for mesh_name: String in ["Body", "Head"]:
		var instance := body.find_child(mesh_name, true, false) as MeshInstance3D
		if instance == null:
			continue
		instance.mesh = _decayed(instance.mesh as ArrayMesh, mesh_name, pattern)
		for s in instance.mesh.get_surface_count():
			var part := _part_of(mesh_name, s)
			var color := skin
			var is_skin := 1.0
			var value: Variant = outfit.get(part, null) if part != "" else null
			if part == "cabelo":
				color = hair
				is_skin = 0.0
			elif value is Color:
				color = (value as Color) * rng.randf_range(0.85, 1.1)
				is_skin = 0.0
			elif value is String and value == "cabelo":
				color = hair
				is_skin = 0.0
			elif part == "" :
				# Detalhes sem parte definida (cintos, fivelas): tom da roupa.
				var base := instance.mesh.surface_get_material(s) as BaseMaterial3D
				color = (base.albedo_color if base != null else Color(0.3, 0.3, 0.3)) * 0.4
				is_skin = 0.0
			var material := ShaderMaterial.new()
			material.shader = preload("res://resources/materials/zombie.gdshader")
			material.set_shader_parameter("base_color", color)
			material.set_shader_parameter("is_skin", is_skin)
			material.set_shader_parameter("grime", rng.randf_range(0.45, 0.85))
			material.set_shader_parameter("blood", float(outfit.get("sangue", 0.5)) * rng.randf_range(0.7, 1.2))
			instance.set_surface_override_material(s, material)
	return outfit


static func _part_of(mesh_name: String, surface: int) -> String:
	for part: String in CharacterLook.PARTS:
		var map: Dictionary = CharacterLook.PARTS[part]
		if map.has(mesh_name) and surface in map[mesh_name]:
			return part
	return ""


## Cópia da malha com as manchas (encardido, sangue, veias) nas cores de
## vértice, pela posição de repouso. Quatro padrões, feitos uma vez.
static func _decayed(source: ArrayMesh, key: String, pattern: int) -> ArrayMesh:
	var cache_key := "%s_%d" % [key, pattern]
	if _meshes.has(cache_key):
		return _meshes[cache_key]
	var dirt := FastNoiseLite.new()
	dirt.seed = 910 + pattern
	dirt.frequency = 2.2
	dirt.fractal_octaves = 3
	var splat := FastNoiseLite.new()
	splat.seed = 950 + pattern
	splat.frequency = 4.0
	var veins := FastNoiseLite.new()
	veins.seed = 990 + pattern
	veins.noise_type = FastNoiseLite.TYPE_CELLULAR
	veins.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	veins.frequency = 9.0
	var mesh := ArrayMesh.new()
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors := PackedColorArray()
		colors.resize(vertices.size())
		for i in vertices.size():
			var v := vertices[i]
			var grime := clampf(0.5 + dirt.get_noise_3dv(v) * 0.9 + (0.9 - v.y) * 0.25, 0.0, 1.0)
			# Sangue: mais no peito, boca e mãos (y alto e extremidades).
			var bias := 0.15 * smoothstep(1.1, 1.6, v.y) + 0.12 * smoothstep(0.45, 0.7, absf(v.x))
			var blood := clampf(0.45 + splat.get_noise_3dv(v) * 0.8 + bias, 0.0, 1.0)
			var vein := clampf(1.0 - absf(veins.get_noise_3dv(v)) * 3.0, 0.0, 1.0)
			colors[i] = Color(grime, blood, vein)
		arrays[Mesh.ARRAY_COLOR] = colors
		var flags := source.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		mesh.add_surface_from_arrays(source.surface_get_primitive_type(s), arrays, [], {}, flags)
		mesh.surface_set_material(s, source.surface_get_material(s))
	_meshes[cache_key] = mesh
	return mesh
