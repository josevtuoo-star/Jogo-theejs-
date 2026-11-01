class_name Itens
extends Object
## Tabela dos itens que dá para pegar: nome, peso (kg), volume (litros), modelo e onde vão no
## corpo, em ordem de preferência:
## - "costas1"/"costas2": armas longas penduradas nas costas (em X, por cima da mochila);
## - "cinto_e"/"cinto_d": no cinto (esquerda/direita);
## - "lado_e"/"lado_d": amarrados nas laterais da mochila (ferramentas compridas);
## - "baixo"/"topo": pendurados embaixo/em cima da mochila (panelas, caneca);
## - "dentro": dentro da mochila (ocupa volume).
## "rot" corrige a orientação do modelo (comprido em Y para ferramentas; cano para -Z nas armas).

const M := "res://assets/modelos/"
## capacidade da mochila (litros)
const BACKPACK_L := 32.0

const DATA := {
	"ak47": {"nome": "AK-47", "peso": 3.6, "vol": 0.0, "modelo": M + "ak47.tscn", "slots": ["costas1", "costas2"], "som": "metal", "arma": true},
	"m4a1": {"nome": "M4A1", "peso": 3.1, "vol": 0.0, "modelo": M + "m4a1.tscn", "slots": ["costas1", "costas2"], "som": "metal", "arma": true},
	"escopeta": {"nome": "Escopeta", "peso": 3.4, "vol": 0.0, "modelo": M + "escopeta.tscn", "slots": ["costas1", "costas2"], "som": "metal", "arma": true},
	"rifle_weatherby": {"nome": "Rifle de caça", "peso": 3.5, "vol": 0.0, "modelo": M + "rifle_weatherby.tscn", "slots": ["costas1", "costas2"],
		"som": "wood", "arma": true, "rot": Vector3(0, -PI / 2, 0)},
	"machado": {"nome": "Machado", "peso": 1.4, "vol": 0.0, "modelo": M + "machado.tscn", "slots": ["lado_d", "lado_e", "cinto_e"], "som": "metal"},
	"pa": {"nome": "Pá", "peso": 2.1, "vol": 0.0, "modelo": M + "pa.tscn", "slots": ["lado_e", "lado_d"], "som": "metal"},
	"lanterna": {"nome": "Lanterna", "peso": 0.4, "vol": 0.4, "modelo": M + "lanterna.tscn", "slots": ["cinto_e", "dentro"], "som": "metal_light",
		"rot": Vector3(0, 0, -PI / 2)},
	"garrafa": {"nome": "Garrafa d'água", "peso": 0.8, "vol": 0.9, "modelo": M + "garrafa.tscn", "slots": ["cinto_d", "dentro"], "som": "rubber"},
	"comida": {"nome": "Comida enlatada", "peso": 0.5, "vol": 0.6, "modelo": M + "comida.tscn", "slots": ["dentro"], "som": "metal_light"},
	"municao": {"nome": "Caixa de munição", "peso": 0.9, "vol": 0.5, "modelo": M + "municao.tscn", "slots": ["dentro"], "som": "metal_light"},
	"fosforos": {"nome": "Fósforos", "peso": 0.05, "vol": 0.1, "modelo": M + "fosforos.tscn", "slots": ["dentro"], "som": "wood_light"},
	"panela": {"nome": "Panela", "peso": 0.9, "vol": 4.0, "modelo": M + "panela.tscn", "slots": ["baixo", "dentro"], "som": "metal_light"},
	"frigideira": {"nome": "Frigideira", "peso": 1.1, "vol": 3.0, "modelo": M + "frigideira.tscn", "slots": ["lado_e", "lado_d", "dentro"],
		"som": "metal_light", "rot_lado": Vector3(0, 0, PI / 2)},
	"chaleira": {"nome": "Chaleira", "peso": 0.7, "vol": 3.0, "modelo": M + "chaleira.tscn", "slots": ["baixo", "dentro"], "som": "metal_light"},
	"caneca": {"nome": "Caneca", "peso": 0.25, "vol": 0.4, "modelo": M + "caneca.tscn", "slots": ["topo", "dentro"], "som": "metal_light"},
	"caixa_ferramentas": {"nome": "Caixa de ferramentas", "peso": 4.5, "vol": 9.0, "modelo": M + "caixa_ferramentas.tscn", "slots": ["dentro"], "som": "metal"},
	"galao": {"nome": "Galão de gasolina", "peso": 5.5, "vol": 0.0, "modelo": M + "galao.tscn", "slots": ["baixo"], "som": "metal"},
	"kit_medico": {"nome": "Kit médico", "peso": 1.6, "vol": 0.0, "modelo": M + "kit_medico.tscn", "slots": ["lado_e", "lado_d"], "som": "metal_light",
		"escala": 0.55},
}


static func nome(id: String) -> String:
	return DATA[id].nome if DATA.has(id) else id


static func peso(id: String) -> float:
	return DATA[id].peso if DATA.has(id) else 1.0


static func is_gun(id: String) -> bool:
	return DATA.has(id) and DATA[id].get("arma", false)


## Modelo do item com o centro na origem (meta "tamanho_real" = tamanho já girado/escalado).
## Armas sem marcadores ganham "Empunhadura", "Guarda" e "Cano".
static func make_model(id: String) -> Node3D:
	var d: Dictionary = DATA[id]
	var holder := Node3D.new()
	holder.name = "Modelo"
	# copia só as malhas e marcadores do modelo (sem a colisão fixa dele; e sem ser uma
	# "instância" de cena, que ao salvar o mapa traria a colisão de volta)
	var src: Node3D = load(d.modelo).instantiate()
	var m := Node3D.new()
	m.name = "Malha"
	for c in src.get_children():
		if c is MeshInstance3D:
			var mi := MeshInstance3D.new()
			mi.name = c.name
			mi.mesh = (c as MeshInstance3D).mesh
			mi.transform = (c as MeshInstance3D).transform
			mi.material_override = (c as MeshInstance3D).material_override
			m.add_child(mi)
		elif c is Marker3D:
			var mk := Marker3D.new()
			mk.name = c.name
			mk.transform = (c as Marker3D).transform
			m.add_child(mk)
	var size: Vector3 = src.get_meta("tamanho", Vector3(0.3, 0.3, 0.3))
	src.free()
	var sc: float = d.get("escala", 1.0)
	var rb := Basis.from_euler(d.get("rot", Vector3.ZERO))
	var centered := m.has_node("Empunhadura") # armas extraídas já têm o centro na origem
	var center := Vector3.ZERO if centered else Vector3(0.0, size.y * 0.5, 0.0)
	m.transform = Transform3D(rb.scaled(Vector3.ONE * sc), -(rb * center) * sc)
	holder.add_child(m)
	var real := (rb * size).abs() * sc
	holder.set_meta("tamanho_real", real)
	if d.get("arma", false) and not centered:
		var L := real.z
		for mk in [["Empunhadura", Vector3(0, -real.y * 0.25, L * 0.16)], ["Guarda", Vector3(0, -real.y * 0.1, -L * 0.18)], ["Cano", Vector3(0, 0.02, -L * 0.5)]]:
			var n := Marker3D.new()
			n.name = mk[0]
			n.position = mk[1]
			holder.add_child(n)
	return holder


## Corpo com física do item no mundo (centro na origem). `model`: reaproveita um modelo.
static func make_body(id: String, model: Node3D = null) -> RigidBody3D:
	var d: Dictionary = DATA[id]
	var rb := RigidBody3D.new()
	rb.name = "Item_" + id
	rb.set_script(load("res://scripts/item.gd"))
	rb.set("item_id", id)
	rb.set("sound", d.get("som", "wood"))
	rb.mass = d.peso
	rb.collision_layer = 2
	rb.collision_mask = 1 | 2 | 4
	rb.continuous_cd = false
	var m := model if model else make_model(id)
	if m.get_parent():
		m.get_parent().remove_child(m)
	m.top_level = false
	m.visible = true
	m.transform = Transform3D()
	rb.add_child(m)
	var real: Vector3 = m.get_meta("tamanho_real", Vector3(0.3, 0.3, 0.3))
	var cs := CollisionShape3D.new()
	cs.name = "Colisao"
	var bs := BoxShape3D.new()
	# espessura mínima: caixas muito finas atravessam o chão (malha de triângulos)
	bs.size = real.max(Vector3(0.08, 0.08, 0.08))
	cs.shape = bs
	rb.add_child(cs)
	return rb
