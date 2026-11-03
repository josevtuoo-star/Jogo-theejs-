class_name CharacterLook
extends RefCounted
## Aparência do sobrevivente: cor de cada parte da roupa, da pele e do
## cabelo/barba, escolhida no menu (PERSONAGEM). Cada parte é um conjunto de
## superfícies das malhas Body e Head do modelo (cores lisas, sem textura); a
## escolha troca só a cor do material daquela superfície.

## parte: {malha: [superfícies]}
const PARTS := {
	"jaqueta": {"Body": [2, 3], "Head": [10, 11]},
	"calca": {"Body": [7]},
	"botas": {"Body": [9, 10, 11]},
	"gorro": {"Head": [8, 9]},
	"pele": {"Body": [0, 1], "Head": [0, 1, 4]},
	"cabelo": {"Head": [2, 3, 6]},
}
const PART_NAMES := {"jaqueta": "Jaqueta", "calca": "Calça", "botas": "Botas", "gorro": "Gorro",
		"pele": "Pele", "cabelo": "Cabelo e barba"}
const ORDER := ["jaqueta", "calca", "botas", "gorro", "pele", "cabelo"]

## Opções de cada parte (a primeira é a original do modelo).
const COLORS := {
	"jaqueta": [Color(0, 0, 0, 0), Color(0.12, 0.12, 0.13), Color(0.14, 0.18, 0.3), Color(0.42, 0.1, 0.08),
			Color(0.36, 0.24, 0.14), Color(0.42, 0.43, 0.44), Color(0.75, 0.38, 0.1), Color(0.3, 0.34, 0.22)],
	"calca": [Color(0, 0, 0, 0), Color(0.16, 0.22, 0.36), Color(0.1, 0.1, 0.11), Color(0.3, 0.32, 0.25),
			Color(0.38, 0.38, 0.38), Color(0.3, 0.22, 0.15)],
	"botas": [Color(0, 0, 0, 0), Color(0.08, 0.08, 0.08), Color(0.42, 0.3, 0.18), Color(0.35, 0.33, 0.28)],
	"gorro": [Color(0, 0, 0, 0), Color(0.1, 0.1, 0.11), Color(0.55, 0.1, 0.08), Color(0.78, 0.4, 0.08),
			Color(0.24, 0.3, 0.18), Color(0.2, 0.25, 0.42)],
	"pele": [Color(0, 0, 0, 0), Color(0.93, 0.78, 0.66), Color(0.76, 0.56, 0.42), Color(0.55, 0.37, 0.25),
			Color(0.36, 0.23, 0.15)],
	"cabelo": [Color(0, 0, 0, 0), Color(0.08, 0.07, 0.06), Color(0.45, 0.3, 0.16), Color(0.7, 0.55, 0.3),
			Color(0.55, 0.53, 0.5), Color(0.5, 0.18, 0.08)],
}


static func default_look() -> Dictionary:
	var look := {}
	for part: String in ORDER:
		look[part] = 0
	return look


## Cor mostrada no botão da opção (a original vem do próprio modelo).
static func swatch(part: String, option: int, root: Node = null) -> Color:
	var color: Color = COLORS[part][option]
	if color.a > 0.0 or root == null:
		return color if color.a > 0.0 else Color(0.5, 0.5, 0.5)
	for mesh_name: String in PARTS[part]:
		var mesh := root.find_child(mesh_name, true, false) as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			var material := mesh.mesh.surface_get_material(PARTS[part][mesh_name][0]) as BaseMaterial3D
			if material != null:
				return material.albedo_color
	return Color(0.5, 0.5, 0.5)


## Aplica a aparência às malhas do personagem (Body e Head) em `root`.
static func apply(root: Node, look: Dictionary) -> void:
	if root == null:
		return
	for part: String in ORDER:
		var option := clampi(int(look.get(part, 0)), 0, (COLORS[part] as Array).size() - 1)
		var color: Color = COLORS[part][option]
		for mesh_name: String in PARTS[part]:
			var mesh := root.find_child(mesh_name, true, false) as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			for surface: int in PARTS[part][mesh_name]:
				if surface >= mesh.mesh.get_surface_count():
					continue
				if color.a <= 0.0:
					mesh.set_surface_override_material(surface, null)
					continue
				var base := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
				if base == null:
					continue
				var copy := base.duplicate() as BaseMaterial3D
				# Detalhes do mesmo pedaço (costuras, golas) ficam um tom abaixo.
				var shade := 1.0 if surface == PARTS[part][mesh_name][0] else 0.85
				copy.albedo_color = Color(color.r * shade, color.g * shade, color.b * shade)
				mesh.set_surface_override_material(surface, copy)
