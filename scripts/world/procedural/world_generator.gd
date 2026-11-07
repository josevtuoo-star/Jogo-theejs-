class_name WorldGenerator
extends RefCounted
## Gerador determinístico do mundo infinito, pedaço por pedaço (como o
## Minecraft): a mesma semente gera sempre o mesmo relevo, as mesmas cavernas,
## estradas e objetos, em qualquer ordem e em qualquer linha de execução.
##
## O terreno é um campo de densidade 3D (positivo = rocha/terra, negativo =
## ar): a superfície vem de ruídos de relevo e as cavernas são galerias
## escavadas num nível subterrâneo (ver "Cavernas" abaixo), ligadas à
## superfície por rampas naturais. A malha sai do campo por surface nets
## (células de 2 m), sem emendas entre pedaços.
##
## Só usa funções puras e ruídos próprios: cada tarefa em segundo plano cria
## a sua instância (FastNoiseLite não é compartilhado entre threads).

const CHUNK_SIZE := 32.0
const CELL := 2.0
const CELLS := 16
## Fundo do campo de densidade (abaixo é rocha maciça; as galerias mais
## fundas ficam acima de CAVE_BAND_LOW).
const FLOOR_Y := -32.0
## Rodovias norte-sul a cada ROAD_SPACING m e estradas leste-oeste entre elas.
const ROAD_SPACING := 640.0
const HIGHWAY_HALF_WIDTH := 4.6
const BYROAD_HALF_WIDTH := 3.2
## Largura da transição do aterro da estrada para o relevo natural.
const ROAD_BLEND := 11.0
const ROAD_BLEND_MAX := 34.0

## Tipos de objeto espalhados (índices usados pelo ProceduralWorld).
## Altura do quadro de cada variante: abetos (3), folhosa, seca, aljava.
const TREE_HEIGHTS := [9.0, 7.95, 6.02, 4.65, 4.65, 2.77]

var world_seed: int

var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _mountains := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _grass := FastNoiseLite.new()
var _gallery_a := FastNoiseLite.new()
var _gallery_b := FastNoiseLite.new()
var _cave_floor := FastNoiseLite.new()
var _chambers := FastNoiseLite.new()
var _rough := FastNoiseLite.new()
## Entradas de caverna já calculadas (região -> dados).
var _entrance_cache: Dictionary = {}
var _spawn_region := Vector2i(1 << 30, 0)
var _road_warp := FastNoiseLite.new()
var _jams := FastNoiseLite.new()
var _temperature := FastNoiseLite.new()
var _humidity := FastNoiseLite.new()
var _town_cache: Dictionary = {}


func _init(seed_value: int = 1) -> void:
	world_seed = seed_value
	_setup(_continent, 1, 0.0022, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_hills, 2, 0.009, 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_ridges, 3, 0.0045, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_mountains, 4, 0.0016, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_detail, 5, 0.06, 2, FastNoiseLite.TYPE_SIMPLEX)
	_setup(_forest, 6, 0.0065, 2, FastNoiseLite.TYPE_SIMPLEX)
	_setup(_grass, 7, 0.03, 2, FastNoiseLite.TYPE_SIMPLEX)
	_setup(_gallery_a, 14, 0.007, 1, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_gallery_b, 15, 0.0085, 1, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_cave_floor, 16, 0.006, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_chambers, 17, 0.011, 1, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_rough, 18, 0.16, 2, FastNoiseLite.TYPE_SIMPLEX)
	_setup(_road_warp, 12, 0.0011, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_jams, 13, 0.006, 1, FastNoiseLite.TYPE_SIMPLEX)
	_setup(_temperature, 21, 0.0012, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_humidity, 22, 0.0014, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_spawn_region = region_of(spawn_point())


func _setup(noise: FastNoiseLite, salt: int, frequency: float, octaves: int, type: FastNoiseLite.NoiseType) -> void:
	noise.seed = world_seed * 7919 + salt * 104729
	noise.noise_type = type
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE


# --- Relevo e estradas -------------------------------------------------------

## Relevo natural (sem estradas): planícies onduladas, morros e serras.
func natural_height(x: float, z: float) -> float:
	var mountain := smoothstep(-0.2, 0.45, _mountains.get_noise_2d(x, z))
	var h := 5.0 + _continent.get_noise_2d(x, z) * 12.0
	h += _hills.get_noise_2d(x, z) * (2.5 + 6.5 * mountain)
	var ridge := 1.0 - absf(_ridges.get_noise_2d(x, z))
	h += ridge * ridge * ridge * 30.0 * mountain
	return h


## Altura do leito da estrada: o relevo sem as serras (a estrada corta os
## morros em vez de subir neles), amostrado no eixo da estrada.
func _road_bed(x: float, z: float) -> float:
	return 5.0 + _continent.get_noise_2d(x, z) * 12.0 + _hills.get_noise_2d(x, z) * 2.0


## Eixo da rodovia norte-sul mais próxima: x do eixo na altura z.
func highway_center_x(x: float, z: float) -> float:
	var warp := _road_warp.get_noise_1d(z) * 110.0
	var k := roundf((x - warp) / ROAD_SPACING)
	return k * ROAD_SPACING + warp


## Eixo da estrada leste-oeste mais próxima: z do eixo na posição x.
func byroad_center_z(x: float, z: float) -> float:
	var warp := _road_warp.get_noise_1d(x + 5000.0) * 90.0 + ROAD_SPACING * 0.5
	var k := roundf((z - warp) / ROAD_SPACING)
	return k * ROAD_SPACING + warp


## [distância à rodovia, distância à estrada vicinal] (m, no plano).
func road_distances(x: float, z: float) -> Vector2:
	return Vector2(absf(x - highway_center_x(x, z)), absf(z - byroad_center_z(x, z)))


## Altura do chão (sem as cavernas): relevo + aterro das estradas.
func surface_height(x: float, z: float) -> float:
	var h := natural_height(x, z) + _detail.get_noise_2d(x, z) * 0.35
	var hx := highway_center_x(x, z)
	var d1 := absf(x - hx)
	if d1 < HIGHWAY_HALF_WIDTH + ROAD_BLEND_MAX:
		h = _embank(h, _road_bed(hx, z), d1, HIGHWAY_HALF_WIDTH)
	var bz := byroad_center_z(x, z)
	var d2 := absf(z - bz)
	if d2 < BYROAD_HALF_WIDTH + ROAD_BLEND_MAX:
		h = _embank(h, _road_bed(x, bz), d2, BYROAD_HALF_WIDTH)
	# Vilas e cidades ficam num platô (corte e aterro em volta).
	var town := town_at(x, z)
	if not town.is_empty():
		var d := Vector2(x, z).distance_to(town["center"])
		h = lerpf(h, town["base"], 1.0 - smoothstep(town["radius"], town["radius"] + TOWN_BLEND, d))
	return h


# --- Biomas (etapa 9) --------------------------------------------------------------
#
# Temperatura e umidade variam devagar pelo mundo (ruídos de baixa frequência)
# e a altitude esfria: cada lugar mistura a floresta de coníferas (a mata da
# partida) com outros quatro biomas, com transição suave entre eles:
# - FOLHOSAS: bosque de árvores de folhas largas, chão de folhas secas;
# - CAMPO: campo aberto de capim, arbustos e poucas árvores;
# - SECO: terra seca e pedregosa, árvores mortas e árvores-aljava;
# - NEVE: topos de serra e regiões frias, neve no chão e nas encostas.

enum Biome { CONIFERAS, FOLHOSAS, CAMPO, SECO, NEVE }


## Pesos dos biomas além das coníferas: x folhosas, y campo, z seco, w neve
## (coníferas = 1 - soma). `surface` = altura do chão (NAN = calcula).
func biome_weights(x: float, z: float, surface: float = NAN) -> Vector4:
	var t := _temperature.get_noise_2d(x, z)
	var h := _humidity.get_noise_2d(x, z)
	var s := surface if not is_nan(surface) else surface_height(x, z)
	var snow := clampf(smoothstep(-0.38, -0.55, t) + smoothstep(27.0, 35.0, s), 0.0, 1.0)
	var dry := smoothstep(0.1, 0.32, t) * smoothstep(0.04, -0.24, h) * (1.0 - snow)
	var plains := smoothstep(-0.04, -0.3, h) * (1.0 - dry) * (1.0 - snow)
	var broad := smoothstep(0.0, 0.22, t) * smoothstep(-0.08, 0.14, h) * (1.0 - snow) * (1.0 - dry) * (1.0 - plains)
	return Vector4(broad, plains, dry, snow)


func biome_at(x: float, z: float) -> Biome:
	var w := biome_weights(x, z)
	var best := Biome.CONIFERAS
	var value := 1.0 - (w.x + w.y + w.z + w.w)
	for k in 4:
		if w[k] > value:
			value = w[k]
			best = (k + 1) as Biome
	return best


# --- Vilas e cidades (etapa 9) ------------------------------------------------------
#
# Uma região de 448 m pode ter uma vila (casas de um ou dois andares em volta
# da estrada) ou uma cidade (quarteirões de prédios de 3 a 7 andares numa
# grade de ruas). Ficam junto da rodovia quando ela passa pela região, num
# platô aplainado (o relevo em volta é cortado ou aterrado), nunca perto da
# partida e nunca em relevo acidentado demais. Tudo determinístico pela semente.

const TOWN_REGION := 448.0
const TOWN_BLEND := 36.0
const BLOCK := 46.0
const STREET_HALF := 4.4
const FLOOR_HEIGHT := 3.2


func town_region_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / TOWN_REGION), floori(z / TOWN_REGION))


func town(region: Vector2i) -> Dictionary:
	if _town_cache.has(region):
		return _town_cache[region]
	var data := _make_town(region)
	_town_cache[region] = data
	return data


## Povoado cujo platô alcança este ponto ({} = nenhum).
func town_at(x: float, z: float) -> Dictionary:
	var region := town_region_of(x, z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t := town(region + Vector2i(dx, dz))
			if not t.is_empty() and Vector2(x, z).distance_to(t["center"]) < float(t["radius"]) + TOWN_BLEND:
				return t
	return {}


## Povoados até `radius` metros de um ponto.
func towns_near(point: Vector3, radius: float) -> Array:
	var list := []
	var region := town_region_of(point.x, point.z)
	var span := int(ceil(radius / TOWN_REGION)) + 1
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var t := town(region + Vector2i(dx, dz))
			if not t.is_empty() and Vector2(point.x, point.z).distance_to(t["center"]) <= radius:
				list.append(t)
	return list


func _make_town(region: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(region.x, region.y, world_seed * 17 + 3))
	var roll := rng.randf()
	var kind := "cidade" if roll < 0.15 else ("vila" if roll < 0.5 else "")
	if kind == "":
		return {}
	var radius := 112.0 if kind == "cidade" else 50.0
	var cx := (region.x + 0.5) * TOWN_REGION + rng.randf_range(-100.0, 100.0)
	var cz := (region.y + 0.5) * TOWN_REGION + rng.randf_range(-100.0, 100.0)
	var hx := highway_center_x(cx, cz)
	var on_highway := absf(hx - cx) < TOWN_REGION * 0.45
	if on_highway:
		cx = hx if kind == "cidade" else hx + (1.0 if rng.randf() < 0.5 else -1.0) * (HIGHWAY_HALF_WIDTH + 30.0)
	var center := Vector2(cx, cz)
	# Longe da partida (a mata e a caverna do começo ficam como estão).
	if center.distance_to(Vector2(highway_center_x(0.0, 0.0), 0.0)) < radius + 230.0:
		return {}
	var base := _road_bed(hx, cz) if on_highway else natural_height(cx, cz)
	var worst := 0.0
	for k in 8:
		var p := center + Vector2.from_angle(TAU * k / 8.0) * radius * 0.85
		worst = maxf(worst, absf(natural_height(p.x, p.y) - base))
	if worst > 22.0:
		return {}
	var data := {"kind": kind, "center": center, "radius": radius, "base": base, "seed": rng.randi(),
			"highway": hx if on_highway else INF, "name": _town_name(rng, kind)}
	data["buildings"] = _town_buildings(data, rng)
	return data


const TOWN_NAMES := ["São Bento", "Santa Luzia", "Ouro Fino", "Três Pinheiros", "Ponte Alta", "Bom Retiro",
		"Rio Claro", "Serra Azul", "Campo Belo", "Água Fria", "Boa Vista", "Pedra Branca", "Vale Verde",
		"São Jorge", "Nova Esperança", "Monte Alegre", "Barro Preto", "Cachoeira Seca"]


func _town_name(rng: RandomNumberGenerator, kind: String) -> String:
	return ("Vila " if kind == "vila" else "") + TOWN_NAMES[rng.randi() % TOWN_NAMES.size()]


## Distância à rua mais próxima da grade da cidade (INF fora dela).
func town_street_distance(x: float, z: float, t: Dictionary) -> float:
	if t.is_empty() or t["kind"] != "cidade":
		return INF
	var c: Vector2 = t["center"]
	var lx := x - c.x
	var lz := z - c.y
	if Vector2(lx, lz).length() > float(t["radius"]) - 2.0:
		return INF
	return minf(absf(lx - roundf(lx / BLOCK) * BLOCK), absf(lz - roundf(lz / BLOCK) * BLOCK))


## Prédios e casas do povoado: [{pos, size, style, roof, seed}]. Estilos:
## 0 tijolo, 1 reboco, 2 concreto, 3 tábuas. Telhado: 0 laje, 1 duas águas.
func _town_buildings(t: Dictionary, rng: RandomNumberGenerator) -> Array:
	var list := []
	var c: Vector2 = t["center"]
	var base: float = t["base"]
	var radius: float = t["radius"]
	var hx: float = t["highway"]
	if t["kind"] == "cidade":
		var lot := BLOCK - 2.0 * STREET_HALF - 3.0
		for i in range(-3, 3):
			for j in range(-3, 3):
				var block := c + Vector2((i + 0.5) * BLOCK, (j + 0.5) * BLOCK)
				if block.distance_to(c) > radius - lot * 0.6:
					continue
				var central := 1.0 - block.distance_to(c) / radius
				var split := rng.randf() < 0.6
				for k in (4 if split else 1):
					if rng.randf() < 0.12:
						continue # terreno baldio
					var cell := lot * (0.5 if split else 1.0)
					var offset := Vector2(((k % 2) - 0.5) * cell, ((k / 2) - 0.5) * cell) if split else Vector2.ZERO
					var w := cell - rng.randf_range(1.0, 3.5)
					var d := cell - rng.randf_range(1.0, 3.5)
					var at := block + offset
					if absf(at.x - hx) < HIGHWAY_HALF_WIDTH + 3.0 + w * 0.5:
						continue
					var floors := clampi(int(round(rng.randf_range(2.0, 4.5) + central * 4.0)), 2, 8)
					# Frente (porta) para a rua: o lado que se afasta do centro do quarteirão.
					var out := offset if split else Vector2.from_angle(rng.randi_range(0, 3) * PI * 0.5)
					var front := Vector2(signf(out.x), 0.0) if absf(out.x) >= absf(out.y) else Vector2(0.0, signf(out.y))
					list.append({"pos": Vector3(at.x, base, at.y), "size": Vector3(w, floors * FLOOR_HEIGHT + 0.5, d),
							"style": [0, 0, 1, 2][rng.randi() % 4], "roof": 0, "seed": rng.randi(), "front": front, "floors": floors})
	else:
		var count := rng.randi_range(5, 9)
		var tries := 0
		while list.size() < count and tries < 60:
			tries += 1
			var at := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, radius - 9.0)
			var w := rng.randf_range(7.0, 10.0)
			var d := rng.randf_range(8.0, 11.5)
			if rng.randf() < 0.5:
				var swap := w
				w = d
				d = swap
			if absf(at.x - hx) < HIGHWAY_HALF_WIDTH + 5.0 + maxf(w, d) * 0.5:
				continue
			var free := true
			for other: Dictionary in list:
				var op: Vector3 = other["pos"]
				var os: Vector3 = other["size"]
				if absf(op.x - at.x) < (os.x + w) * 0.5 + 4.0 and absf(op.z - at.y) < (os.z + d) * 0.5 + 4.0:
					free = false
					break
			if not free:
				continue
			var floors := 1 if rng.randf() < 0.65 else 2
			# Porta virada para o centro da vila.
			var to_center := c - at
			var front := Vector2(signf(to_center.x), 0.0) if absf(to_center.x) >= absf(to_center.y) else Vector2(0.0, signf(to_center.y))
			list.append({"pos": Vector3(at.x, base, at.y), "size": Vector3(w, floors * FLOOR_HEIGHT + 0.3, d),
					"style": [0, 1, 1, 3][rng.randi() % 4], "roof": 1, "seed": rng.randi(), "front": front, "floors": floors})
	return list


## Aterro/corte da estrada: a largura da rampa cresce com o desnível (como
## um talude de verdade, ~40°), em vez de paredes a prumo nos morros.
func _embank(natural: float, bed: float, distance: float, half_width: float) -> float:
	var blend := clampf(absf(natural - bed) * 1.2, ROAD_BLEND, ROAD_BLEND_MAX)
	var t := 1.0 - smoothstep(half_width + 0.8, half_width + blend, distance)
	return lerpf(natural, bed, t)


## Inclinação do chão (0 = plano, 1 = 45°) por diferenças finitas.
func slope_at(x: float, z: float) -> float:
	var dx := surface_height(x + 1.0, z) - surface_height(x - 1.0, z)
	var dz := surface_height(x, z + 1.0) - surface_height(x, z - 1.0)
	return Vector2(dx, dz).length() * 0.5


# --- Cavernas e densidade ----------------------------------------------------

## Densidade num ponto (m; > 0 sólido). `surface` e `roads` podem vir de cache
## da coluna (a mesma conta de surface_height / road_distances).
func density_at(x: float, y: float, z: float, surface: float, roads: Vector2) -> float:
	var depth := surface - y
	if depth < -2.5:
		return depth
	return minf(depth, cave_density(x, y, z, depth, roads))


func density(x: float, y: float, z: float) -> float:
	return density_at(x, y, z, surface_height(x, z), road_distances(x, z))


# --- Cavernas ------------------------------------------------------------------
#
# Galerias exploráveis (etapa 8). As cavernas antigas eram tubos de ruído 3D:
# 26% do chão com mais de 40° (o personagem não sobe), 9% com menos de 2 m de
# altura e um quarto das bocas eram poços verticais (quem caía não saía).
# Agora:
# - as galerias ficam num nível subterrâneo (~14 m abaixo do nível de
#   referência, variando ±4 m devagar: o chão quase não inclina) e seguem as
#   linhas de zero de dois ruídos 2D. Linhas de zero não terminam: não há
#   beco sem saída por erro de construção; onde as duas famílias se cruzam
#   há bifurcações;
# - corte transversal natural: chão quase plano que sobe nas paredes e teto
#   em arco; largura e altura variam (corredores de ~4,5 m, câmaras de até
#   15 m de largura e 6,5 m de altura); rugosidade 3D nas paredes e no teto;
# - o chão das galerias fica ao menos 12 m abaixo da superfície (sem buracos
#   no chão: a única ligação com o exterior são as rampas);
# - entradas: rampas inclinadas (10–24°) da superfície até uma galeria, uma
#   a cada região de 160 m com chance, desviando das estradas; a do ponto de
#   partida é garantida.

const CAVE_LEVEL := -14.0
const CAVE_BAND_LOW := -28.0
const CAVE_BAND_HIGH := 2.0
const REGION := 160.0


## Distância horizontal (m) até a linha de zero de um ruído 2D (eixo de
## uma galeria): |n| / |gradiente|.
func _line_distance(noise: FastNoiseLite, x: float, z: float) -> float:
	var n := noise.get_noise_2d(x, z)
	var gx := noise.get_noise_2d(x + 1.0, z) - n
	var gz := noise.get_noise_2d(x, z + 1.0) - n
	return absf(n) / (sqrt(gx * gx + gz * gz) + 0.00001)


## Altura do chão das galerias na coluna (fica sempre ao menos 12 m abaixo
## da superfície, mesmo nos vales).
func gallery_floor(x: float, z: float, surface: float) -> float:
	return minf(CAVE_LEVEL + _cave_floor.get_noise_2d(x, z) * 4.0, surface - 12.0)


## Dados da galeria na coluna: [distância ao eixo, meia largura, altura, chão].
func gallery_at(x: float, z: float, surface: float) -> Vector4:
	var chamber := smoothstep(0.2, 0.65, _chambers.get_noise_2d(x, z))
	var half := 3.0 + chamber * 5.0 + _cave_floor.get_noise_2d(z * 1.9, x * 1.9) * 0.4
	var height := 3.3 + chamber * 3.4 + _chambers.get_noise_2d(z * 1.3, x * 1.3) * 0.4
	var lateral := minf(_line_distance(_gallery_a, x, z), _line_distance(_gallery_b, x, z))
	return Vector4(lateral, half, height, gallery_floor(x, z, surface))


## Perfil de galeria (m, negativo dentro): chão quase plano que sobe junto
## às paredes e teto em arco.
static func _profile(lateral: float, half: float, height: float, floor_y: float, y: float, flat: float = 0.8) -> float:
	var across := clampf(lateral / half, 0.0, 1.0)
	# Chão plano até `flat` da meia largura (largo o bastante para a malha de
	# células de 2 m não virar um "V" de faces íngremes), depois sobe.
	var floor_here := floor_y + maxf(0.0, across - flat) * half * 1.4
	var roof := floor_y + height * pow(1.0 - across * across, 0.35)
	return maxf(lateral - half, maxf(floor_here - y, y - roof))


## Densidade das cavernas (negativo = vazio escavado).
func cave_density(x: float, y: float, z: float, depth: float, roads: Vector2) -> float:
	var surface := y + depth
	var cave := 4.0
	var floor_y := gallery_floor(x, z, surface)
	# Galerias só na faixa de profundidade delas; as rampas sobem até a
	# superfície (em qualquer altura do relevo).
	if y > CAVE_BAND_LOW and y < CAVE_BAND_HIGH and y > floor_y - 3.0 and y < floor_y + 10.0:
		var g := gallery_at(x, z, surface)
		if g.x < g.y + 3.0:
			cave = _profile(g.x, g.y, g.z, g.w, y)
	var ramp := _ramps(x, y, z)
	if ramp.x < cave:
		cave = ramp.x
		# Quem escava aqui é a rampa: a rugosidade conta a partir do chão dela.
		floor_y = ramp.y
	if cave < 3.0:
		# Rocha irregular: só escava (alarga paredes e sobe o teto), nunca
		# estreita a passagem abaixo do perfil, que garante altura e largura
		# para andar. Quase nada no chão (calombos virariam rampas íngremes).
		var amplitude := lerpf(0.06, 1.1, smoothstep(floor_y + 0.4, floor_y + 2.0, y))
		cave -= absf(_rough.get_noise_3d(x, y * 1.3, z)) * amplitude
	return cave


# --- Entradas (rampas) ---------------------------------------------------------

static func region_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / REGION), floori(point.z / REGION))


## Entrada de caverna da região (vazio se não houver): topo e fundo da rampa
## e meia largura. Determinística; calculada uma vez por gerador.
func entrance(region: Vector2i) -> Dictionary:
	if _entrance_cache.has(region):
		return _entrance_cache[region]
	var data := _find_entrance(region)
	_entrance_cache[region] = data
	return data


func _find_entrance(region: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(region.x, region.y, world_seed * 31 + 77))
	var forced := region == _spawn_region
	if not forced and rng.randf() > 0.55:
		return {}
	var center := Vector2((region.x + 0.5) * REGION + rng.randf_range(-35.0, 35.0),
			(region.y + 0.5) * REGION + rng.randf_range(-35.0, 35.0))
	var spawn := Vector2.ZERO
	if forced:
		var sp := spawn_point()
		spawn = Vector2(sp.x, sp.z)
		center = spawn + Vector2(55.0, 20.0)
	# Fundo: o ponto mais perto do eixo de uma galeria em volta do centro.
	var best := Vector2.INF
	var best_lateral := INF
	var reach := 5 if not forced else 9
	for i in reach:
		for j in reach:
			var p := center + Vector2(i - reach / 2, j - reach / 2) * 9.0
			var s := surface_height(p.x, p.y)
			var g := gallery_at(p.x, p.y, s)
			if g.x < best_lateral:
				best_lateral = g.x
				best = p
	if best_lateral > 3.0:
		return {}
	var bottom_floor := gallery_floor(best.x, best.y, surface_height(best.x, best.y))
	# Topo: direção e comprimento com inclinação caminhável, longe das estradas.
	var candidates := []
	var offset := rng.randf() * TAU
	for k in 12:
		var angle := offset + TAU * k / 12.0
		var direction := Vector2(cos(angle), sin(angle))
		for length: float in [34.0, 44.0, 54.0, 66.0]:
			var top := best + direction * length
			var roads := road_distances(top.x, top.y)
			if roads.x < HIGHWAY_HALF_WIDTH + 14.0 or roads.y < BYROAD_HALF_WIDTH + 14.0:
				continue
			var drop := surface_height(top.x, top.y) - 0.3 - bottom_floor
			var slope := drop / length
			# A rampa desce em 80% do comprimento (o resto é plano até dentro
			# da galeria): inclinação real = slope / 0,8, entre ~11° e ~21°.
			if slope < 0.16 or slope > 0.31 or drop < 8.0:
				continue
			var score := absf(slope - 0.24) + (top.distance_to(spawn) * 0.004 if forced else 0.0)
			candidates.append([score, top, length])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for candidate in candidates.slice(0, 8):
		var top: Vector2 = candidate[1]
		var top_y := surface_height(top.x, top.y) - 0.3
		if _ramp_clear(top, top_y, best, bottom_floor):
			return {"top": Vector3(top.x, top_y, top.y), "bottom": Vector3(best.x, bottom_floor, best.y),
					"half": rng.randf_range(3.2, 3.8)}
	return {}


## A rampa não passa sob estradas com pouca rocha por cima (abriria buraco)
## nem atravessa outra galeria no caminho (o chão afundaria nela).
func _ramp_clear(top: Vector2, top_y: float, bottom: Vector2, bottom_y: float) -> bool:
	if not town_at(top.x, top.y).is_empty():
		return false
	for i in range(1, 21):
		var t := i / 20.0
		var p := top.lerp(bottom, t)
		var ramp_floor := lerpf(top_y, bottom_y, minf(t / 0.8, 1.0))
		var surface := surface_height(p.x, p.y)
		var roads := road_distances(p.x, p.y)
		var near_road := roads.x < HIGHWAY_HALF_WIDTH + 8.0 or roads.y < BYROAD_HALF_WIDTH + 8.0
		if near_road and surface - (ramp_floor + 4.0) < 4.0:
			return false
		if t < 0.8:
			var g := gallery_at(p.x, p.y, surface)
			if g.x < g.y + 3.5 and g.w + g.z + 2.5 > ramp_floor - 1.0:
				return false
	return true


## Rampas que tocam o pedaço sendo gerado (null = procurar nas regiões).
var _local_ramps: Variant = null


## Densidade das rampas de entrada das regiões em volta do ponto.
## [densidade, altura do chão] da rampa mais escavada no ponto.
func _ramps(x: float, y: float, z: float) -> Vector2:
	var result := Vector2(4.0, -INF)
	if _local_ramps != null:
		for e in _local_ramps:
			var r := _ramp_density(e, x, y, z)
			if r.x < result.x:
				result = r
		return result
	var region := Vector2i(floori(x / REGION), floori(z / REGION))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var e := entrance(region + Vector2i(dx, dz))
			if e.is_empty():
				continue
			var r := _ramp_density(e, x, y, z)
			if r.x < result.x:
				result = r
	return result


func _ramp_density(e: Dictionary, x: float, y: float, z: float) -> Vector2:
	var top: Vector3 = e["top"]
	var bottom: Vector3 = e["bottom"]
	var half: float = e["half"]
	var a := Vector2(top.x, top.z)
	var b := Vector2(bottom.x, bottom.z)
	var ab := b - a
	# Passa um pouco do fundo para se abrir dentro da galeria.
	var length := ab.length()
	var extended := b + ab / length * 4.0
	var p := Vector2(x, z)
	var t := clampf((p - a).dot(extended - a) / (extended - a).length_squared(), 0.0, 1.0)
	var lateral := p.distance_to(a.lerp(extended, t))
	if lateral > half + 4.0:
		return Vector2(lateral - half, -INF)
	var along := t * (length + 4.0) / length
	# Chega ao nível da galeria aos 80% e segue plana: entra na galeria sem
	# degrau (dá para voltar subindo).
	var floor_y := lerpf(top.y, bottom.y, minf(along / 0.8, 1.0))
	# A boca é mais larga e mais alta (rocha desmoronada em volta).
	var mouth := 1.0 - smoothstep(0.0, 0.25, along)
	return Vector2(_profile(lateral, half * (1.0 + mouth * 0.35), 3.8 + mouth * 1.2, floor_y, y, 0.85), floor_y)


## Entradas (topo das rampas) a até `radius` m de um ponto: para testes e
## para o jogador achar as cavernas.
func entrances_near(point: Vector3, radius: float) -> Array:
	var list := []
	var region := region_of(point)
	var span := int(ceil(radius / REGION)) + 1
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var e := entrance(region + Vector2i(dx, dz))
			if not e.is_empty() and Vector2((e["top"] as Vector3).x - point.x, (e["top"] as Vector3).z - point.z).length() <= radius:
				list.append(e)
	return list


# --- Luz que entra nas cavernas -------------------------------------------------

## Direções dos raios de "céu visível": para cima, 6 inclinadas (55°) e 6
## rasantes (25°). As rasantes deixam a luz da boca entrar alguns metros pelo
## túnel, como acontece de verdade (a claridade vem da abertura, de lado).
const SKY_RAYS: Array[Vector3] = [
	Vector3(0.0, 1.0, 0.0),
	Vector3(0.574, 0.819, 0.0), Vector3(-0.574, 0.819, 0.0),
	Vector3(0.287, 0.819, 0.497), Vector3(-0.287, 0.819, 0.497),
	Vector3(0.287, 0.819, -0.497), Vector3(-0.287, 0.819, -0.497),
	Vector3(0.906, 0.423, 0.0), Vector3(-0.906, 0.423, 0.0),
	Vector3(0.453, 0.423, 0.785), Vector3(-0.453, 0.423, 0.785),
	Vector3(0.453, 0.423, -0.785), Vector3(-0.453, 0.423, -0.785),
]
const SKY_STEP := 2.0
const SKY_STEPS := 9


## Quanto céu se enxerga de um ponto (0 a 1): fração dos raios que saem da
## terra sem bater em rocha. Na boca da caverna entra luz; para dentro ela
## some aos poucos, e o fundo das galerias fica no escuro.
func sky_visibility(point: Vector3) -> float:
	var surface := surface_height(point.x, point.z)
	if point.y > surface - 0.5:
		return 1.0
	var open := 0
	for direction in SKY_RAYS:
		var q := point
		for step in SKY_STEPS:
			q += direction * SKY_STEP
			var s := surface_height(q.x, q.z)
			if q.y > s + 0.3:
				open += 1
				break
			if density_at(q.x, q.y, q.z, s, road_distances(q.x, q.z)) > 0.0:
				break
	return float(open) / SKY_RAYS.size()


# --- Pedaço: campo de densidade e malha --------------------------------------

## Gera tudo de um pedaço (malha do terreno, colisão e listas de objetos).
## Seguro para rodar em segundo plano.
## Escavações do jogador neste pedaço (Vector4: centro xyz e raio). Só
## mudam o terreno (malha e colisão); árvores e objetos continuam onde estão.
var digs: Array[Vector4] = []


func build_chunk(coord: Vector2i) -> Dictionary:
	var started := Time.get_ticks_usec()
	var origin := Vector2(coord.x * CHUNK_SIZE, coord.y * CHUNK_SIZE)
	var points := CELLS + 2 # amostras de -1 a CELLS (bordas para costurar)
	# Colunas: altura do chão e distância às estradas.
	var surfaces := PackedFloat32Array()
	var roads := PackedVector2Array()
	surfaces.resize(points * points)
	roads.resize(points * points)
	var top := -INF
	for pz in points:
		for px in points:
			var x := origin.x + (px - 1) * CELL
			var z := origin.y + (pz - 1) * CELL
			var s := surface_height(x, z)
			surfaces[pz * points + px] = s
			roads[pz * points + px] = road_distances(x, z)
			top = maxf(top, s)
	var y0 := FLOOR_Y
	var layers := int(ceil((top + 4.0 - y0) / CELL)) + 1
	# Só as rampas cujo traçado passa perto deste pedaço entram nas contas.
	var nearby := []
	var box := Rect2(origin - Vector2.ONE * 12.0, Vector2.ONE * (CHUNK_SIZE + 24.0))
	for e in entrances_near(Vector3(origin.x + CHUNK_SIZE * 0.5, 0.0, origin.y + CHUNK_SIZE * 0.5), REGION * 1.6):
		var a := Vector2((e["top"] as Vector3).x, (e["top"] as Vector3).z)
		var b := Vector2((e["bottom"] as Vector3).x, (e["bottom"] as Vector3).z)
		var ramp_box := Rect2(a, Vector2.ZERO).expand(b).grow(8.0)
		if ramp_box.intersects(box):
			nearby.append(e)
	_local_ramps = nearby
	var field := PackedFloat32Array()
	field.resize(points * points * layers)
	for pz in points:
		for px in points:
			var column := pz * points + px
			var x := origin.x + (px - 1) * CELL
			var z := origin.y + (pz - 1) * CELL
			var s := surfaces[column]
			var r := roads[column]
			var base := column * layers
			var near: Array[Vector4] = []
			for dig in digs:
				if Vector2(dig.x - x, dig.z - z).length() < dig.w + CELL:
					near.append(dig)
			for py in layers:
				var y := y0 + py * CELL
				var d := density_at(x, y, z, s, r)
				for dig in near:
					d = minf(d, Vector3(x, y, z).distance_to(Vector3(dig.x, dig.y, dig.z)) - dig.w)
				field[base + py] = d
	var mesh := _surface_nets(origin, field, points, layers, y0, surfaces, roads)
	_local_ramps = null
	_light_caves(mesh, origin, field, points, layers, y0, surfaces)
	var result := {
		"coord": coord,
		"mesh": mesh,
		"top": top,
	}
	_scatter(coord, origin, result)
	result["usec"] = Time.get_ticks_usec() - started
	return result


## Surface nets: um vértice por célula cortada pela superfície (média dos
## cruzamentos nas arestas) e um quadrilátero por aresta cortada. O pedaço
## gera as arestas das células 0..CELLS-1; as amostras de borda (-1 e CELLS)
## garantem que os vértices compartilhados saiam idênticos nos dois vizinhos.
func _surface_nets(origin: Vector2, field: PackedFloat32Array, points: int, layers: int, y0: float,
		surfaces: PackedFloat32Array, roads: PackedVector2Array) -> Dictionary:
	var cells := points - 1
	var cell_layers := layers - 1
	var vertex_of := PackedInt32Array()
	vertex_of.resize(cells * cells * cell_layers)
	vertex_of.fill(-1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	# Pesos dos biomas por vértice (x folhosas, y campo, z seco, w neve).
	var customs := PackedFloat32Array()
	var corner := PackedFloat32Array()
	corner.resize(8)
	var stride_z := points * layers
	for cz in cells:
		for cx in cells:
			for cy in cell_layers:
				var base := (cz * points + cx) * layers + cy
				# Cantos: bit 0 = x, bit 1 = y, bit 2 = z.
				corner[0] = field[base]
				corner[1] = field[base + layers]
				corner[2] = field[base + 1]
				corner[3] = field[base + layers + 1]
				corner[4] = field[base + stride_z]
				corner[5] = field[base + stride_z + layers]
				corner[6] = field[base + stride_z + 1]
				corner[7] = field[base + stride_z + layers + 1]
				var mask := 0
				for i in 8:
					if corner[i] > 0.0:
						mask |= 1 << i
				if mask == 0 or mask == 255:
					continue
				# Média dos pontos onde a superfície cruza as 12 arestas.
				var sum := Vector3.ZERO
				var crossings := 0
				for edge in EDGES:
					var i0: int = edge[0]
					var i1: int = edge[1]
					var d0 := corner[i0]
					var d1 := corner[i1]
					if (d0 > 0.0) == (d1 > 0.0):
						continue
					var t := d0 / (d0 - d1)
					sum += CORNERS[i0].lerp(CORNERS[i1], t)
					crossings += 1
				var local := sum / crossings
				# Normal: gradiente trilinear do campo dentro da célula
				# (aponta para o ar = para fora do sólido).
				var gx := lerpf(lerpf(corner[1] - corner[0], corner[3] - corner[2], local.y),
						lerpf(corner[5] - corner[4], corner[7] - corner[6], local.y), local.z)
				var gy := lerpf(lerpf(corner[2] - corner[0], corner[3] - corner[1], local.x),
						lerpf(corner[6] - corner[4], corner[7] - corner[5], local.x), local.z)
				var gz := lerpf(lerpf(corner[4] - corner[0], corner[5] - corner[1], local.x),
						lerpf(corner[6] - corner[2], corner[7] - corner[3], local.x), local.y)
				var normal := -Vector3(gx, gy, gz).normalized()
				var position := Vector3(origin.x + (cx - 1 + local.x) * CELL, y0 + (cy + local.y) * CELL,
						origin.y + (cz - 1 + local.z) * CELL)
				vertex_of[(cz * cells + cx) * cell_layers + cy] = vertices.size()
				vertices.append(position)
				normals.append(normal)
				var weights := _vertex_weights(position, normal, cx, cz, local, points, surfaces, roads)
				colors.append(weights)
				var marking := _road_frame(position, weights.g)
				uvs.append(Vector2(marking.x, marking.y))
				uv2s.append(Vector2(marking.z, marking.w))
				var biome := biome_weights(position.x, position.z, position.y) if weights.a > 0.5 else Vector4.ZERO
				customs.append_array([biome.x, biome.y, biome.z, biome.w])
	# Quadriláteros: arestas com ponto inicial dentro do pedaço (1..CELLS nas
	# amostras), ligando os vértices das 4 células em volta da aresta.
	var indices := PackedInt32Array()
	for pz in range(1, points - 1):
		for px in range(1, points - 1):
			for py in range(1, layers - 1):
				var here := field[(pz * points + px) * layers + py]
				var solid := here > 0.0
				# Aresta em x (para px+1), células em volta: y-1..y, z-1..z.
				if px < points - 1:
					var other := field[(pz * points + px + 1) * layers + py]
					if (other > 0.0) != solid:
						_quad(indices, vertex_of, cells, cell_layers,
								Vector3i(px, py - 1, pz - 1), Vector3i(px, py, pz - 1),
								Vector3i(px, py, pz), Vector3i(px, py - 1, pz), solid)
				# Aresta em y (para py+1), células em volta: x-1..x, z-1..z.
				var above := field[(pz * points + px) * layers + py + 1]
				if (above > 0.0) != solid:
					_quad(indices, vertex_of, cells, cell_layers,
							Vector3i(px - 1, py, pz - 1), Vector3i(px - 1, py, pz),
							Vector3i(px, py, pz), Vector3i(px, py, pz - 1), solid)
				# Aresta em z (para pz+1), células em volta: x-1..x, y-1..y.
				if pz < points - 1:
					var ahead := field[((pz + 1) * points + px) * layers + py]
					if (ahead > 0.0) != solid:
						_quad(indices, vertex_of, cells, cell_layers,
								Vector3i(px - 1, py - 1, pz), Vector3i(px, py - 1, pz),
								Vector3i(px, py, pz), Vector3i(px - 1, py, pz), solid)
	return {"vertices": vertices, "normals": normals, "colors": colors, "uvs": uvs, "uv2s": uv2s, "customs": customs,
			"indices": indices}


## Luz das cavernas por vértice: para cada vértice abaixo da superfície,
## a fração de raios que chega ao céu (mesma regra de sky_visibility), lendo
## o campo de densidade do próprio pedaço (rápido) e o gerador fora dele.
func _light_caves(mesh: Dictionary, origin: Vector2, field: PackedFloat32Array, points: int, layers: int,
		y0: float, surfaces: PackedFloat32Array) -> void:
	var vertices: PackedVector3Array = mesh["vertices"]
	var colors: PackedColorArray = mesh["colors"]
	for i in vertices.size():
		var c := colors[i]
		if c.a > 0.5:
			continue
		var p := vertices[i] + (mesh["normals"] as PackedVector3Array)[i] * 0.6
		var open := 0
		for direction in SKY_RAYS:
			var q := p
			for step in SKY_STEPS:
				q += direction * SKY_STEP
				var s := _field_surface(q, origin, points, surfaces)
				if is_nan(s):
					s = surface_height(q.x, q.z)
				if q.y > s + 0.3:
					open += 1
					break
				var d := _field_density(q, origin, field, points, layers, y0)
				if is_nan(d):
					d = density_at(q.x, q.y, q.z, s, road_distances(q.x, q.z))
				if d > 0.0:
					break
		c.a = float(open) / SKY_RAYS.size()
		colors[i] = c
	mesh["colors"] = colors


## Altura do chão lida das colunas do pedaço (NAN fora dele).
func _field_surface(q: Vector3, origin: Vector2, points: int, surfaces: PackedFloat32Array) -> float:
	var fx := (q.x - origin.x) / CELL + 1.0
	var fz := (q.z - origin.y) / CELL + 1.0
	if fx < 0.0 or fz < 0.0 or fx >= points - 1 or fz >= points - 1:
		return NAN
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i00 := iz * points + ix
	return lerpf(lerpf(surfaces[i00], surfaces[i00 + 1], tx), lerpf(surfaces[i00 + points], surfaces[i00 + points + 1], tx), tz)


## Densidade lida do campo do pedaço por interpolação trilinear (NAN fora).
func _field_density(q: Vector3, origin: Vector2, field: PackedFloat32Array, points: int, layers: int, y0: float) -> float:
	var fx := (q.x - origin.x) / CELL + 1.0
	var fz := (q.z - origin.y) / CELL + 1.0
	var fy := (q.y - y0) / CELL
	if fx < 0.0 or fz < 0.0 or fy < 0.0 or fx >= points - 1 or fz >= points - 1 or fy >= layers - 1:
		return NAN
	var ix := int(fx)
	var iy := int(fy)
	var iz := int(fz)
	var tx := fx - ix
	var ty := fy - iy
	var tz := fz - iz
	var b := (iz * points + ix) * layers + iy
	var sx := layers
	var sz := points * layers
	var c00 := lerpf(field[b], field[b + sx], tx)
	var c01 := lerpf(field[b + 1], field[b + sx + 1], tx)
	var c10 := lerpf(field[b + sz], field[b + sz + sx], tx)
	var c11 := lerpf(field[b + sz + 1], field[b + sz + sx + 1], tx)
	return lerpf(lerpf(c00, c01, ty), lerpf(c10, c11, ty), tz)


## Coordenadas da pintura da pista para o shader: (deslocamento lateral com
## sinal a partir do eixo da estrada mais próxima, distância ao longo dela,
## 1 se pode ter faixa pintada (não em cruzamentos), meia largura da pista).
## O deslocamento lateral varia linearmente na pista, então interpola exato
## entre os vértices de 2 m e a faixa de 12 cm sai nítida.
func _road_frame(position: Vector3, asphalt: float) -> Vector4:
	if asphalt <= 0.0:
		return Vector4(99.0, 0.0, 0.0, 0.0)
	var sx := position.x - highway_center_x(position.x, position.z)
	var sz := position.z - byroad_center_z(position.x, position.z)
	var paint := 0.0 if absf(sx) < 16.0 and absf(sz) < 16.0 else 1.0
	if absf(sx) <= absf(sz):
		return Vector4(sx, position.z, paint, HIGHWAY_HALF_WIDTH)
	return Vector4(sz, position.x, paint, BYROAD_HALF_WIDTH)


## Cantos da célula e as 12 arestas (pares de cantos).
const CORNERS: Array[Vector3] = [
	Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0),
	Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1),
]
const EDGES := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]


func _quad(indices: PackedInt32Array, vertex_of: PackedInt32Array, cells: int, cell_layers: int,
		a: Vector3i, b: Vector3i, c: Vector3i, d: Vector3i, flip: bool) -> void:
	var ids := PackedInt32Array()
	for cell in [a, b, c, d]:
		if cell.x < 0 or cell.z < 0 or cell.x >= cells or cell.z >= cells or cell.y < 0 or cell.y >= cell_layers:
			return
		var id := vertex_of[(cell.z * cells + cell.x) * cell_layers + cell.y]
		if id < 0:
			return
		ids.append(id)
	# a→b→c→d gira no sentido positivo em volta do eixo da aresta; a face
	# da frente (sentido horário no Godot) fica do lado do ar.
	if flip:
		indices.append_array([ids[0], ids[2], ids[1], ids[0], ids[3], ids[2]])
	else:
		indices.append_array([ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]])


## Pesos do material por vértice: R = grama, G = asfalto, B = cascalho/lama
## (acostamento e chão de caverna), A = céu aberto (escurece cavernas).
func _vertex_weights(position: Vector3, normal: Vector3, cx: int, cz: int, local: Vector3, points: int,
		surfaces: PackedFloat32Array, roads: PackedVector2Array) -> Color:
	# Altura do chão e estradas interpoladas das colunas em volta.
	var i00 := cz * points + cx
	var s := lerpf(lerpf(surfaces[i00], surfaces[i00 + 1], local.x),
			lerpf(surfaces[i00 + points], surfaces[i00 + points + 1], local.x), local.z)
	var r := (roads[i00].lerp(roads[i00 + 1], local.x)).lerp(roads[i00 + points].lerp(roads[i00 + points + 1], local.x), local.z)
	var depth := s - position.y
	# Céu aberto provisório (as cavernas recebem a medida por raios depois,
	# em _light_caves).
	var sky := 1.0 if depth < 0.5 else 0.0
	var on_top := smoothstep(0.55, 0.8, normal.y) * smoothstep(1.2, 0.0, absf(depth))
	var asphalt := maxf(1.0 - smoothstep(HIGHWAY_HALF_WIDTH - 0.6, HIGHWAY_HALF_WIDTH + 0.3, r.x),
			1.0 - smoothstep(BYROAD_HALF_WIDTH - 0.6, BYROAD_HALF_WIDTH + 0.3, r.y)) * on_top
	var shoulder := maxf(1.0 - smoothstep(HIGHWAY_HALF_WIDTH + 0.5, HIGHWAY_HALF_WIDTH + 3.0, r.x),
			1.0 - smoothstep(BYROAD_HALF_WIDTH + 0.5, BYROAD_HALF_WIDTH + 2.5, r.y))
	# Ruas da cidade (asfalto sem faixas) e calçadas (cascalho de concreto).
	var t := town_at(position.x, position.z)
	if not t.is_empty() and sky > 0.5:
		var street := town_street_distance(position.x, position.z, t)
		asphalt = maxf(asphalt, (1.0 - smoothstep(STREET_HALF - 0.6, STREET_HALF + 0.2, street)) * on_top)
		shoulder = maxf(shoulder, 1.0 - smoothstep(STREET_HALF + 1.5, STREET_HALF + 2.6, street))
		# Terra batida em volta das casas da vila.
		if t["kind"] == "vila":
			shoulder = maxf(shoulder, 0.55 * (1.0 - smoothstep(float(t["radius"]) * 0.55, float(t["radius"]), Vector2(position.x, position.z).distance_to(t["center"]))))
	var gravel := clampf(maxf(shoulder - asphalt, (1.0 - sky) * 0.8), 0.0, 1.0)
	var grass := clampf(_grass.get_noise_2d(position.x, position.z) * 0.9 + 0.35 - _forest_density(position.x, position.z) * 0.6, 0.0, 1.0)
	grass *= on_top * (1.0 - asphalt) * (1.0 - gravel)
	return Color(grass, asphalt, gravel, sky)


# --- Objetos do pedaço -------------------------------------------------------

## Densidade da mata (0 = clareira/campo, 1 = floresta fechada).
func _forest_density(x: float, z: float) -> float:
	return smoothstep(-0.35, 0.25, _forest.get_noise_2d(x, z))


## Altura para assentar um objeto de raio `radius`: o ponto mais baixo do
## chão sob ele (centro e quatro bordas), para nenhum lado ficar no ar.
func seat_height(x: float, z: float, radius: float) -> float:
	var low := surface_height(x, z)
	for offset: Vector2 in [Vector2(radius, 0.0), Vector2(-radius, 0.0), Vector2(0.0, radius), Vector2(0.0, -radius)]:
		low = minf(low, surface_height(x + offset.x, z + offset.y))
	return low


## Chão firme aqui (não é boca de caverna nem barranco)? Confere também em
## volta (2 m): perto da beira de um corte (boca de rampa), a malha do terreno
## arredonda a quina e o objeto ficaria no ar.
func _solid_ground(x: float, z: float, surface: float) -> bool:
	if density(x, surface - 1.2, z) <= 0.0 or density(x, surface - 3.0, z) <= 0.0:
		return false
	for offset: Vector2 in [Vector2(2.0, 0.0), Vector2(-2.0, 0.0), Vector2(0.0, 2.0), Vector2(0.0, -2.0)]:
		var s := surface_height(x + offset.x, z + offset.y)
		if density(x + offset.x, s - 1.0, z + offset.y) <= 0.0:
			return false
	return true


## Distribui árvores, vegetação, pedras, carcaças, destroços e armas.
## Determinístico por pedaço (semente própria), independente da ordem.
func _scatter(coord: Vector2i, origin: Vector2, result: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(coord.x, coord.y, world_seed))
	var trees: Array = [[], [], [], [], [], []]
	var trunks: Array[Transform3D] = []
	var trunk_colliders: Array = [] # [posição, raio]
	# Cada árvore com o que é preciso para cortá-la:
	# [variante, escala, transformação da copa, do tronco (só abetos), altura, raio].
	var tree_list: Array = []
	result["tree_list"] = tree_list
	var props := {} # nome -> Array[Transform3D] (visual)
	var colliders: Array = [] # [Transform3D, tamanho da caixa]
	var weapons: Array = [] # [id, Transform3D]
	var wrecks: Array = [] # [nome, Transform3D, Color]
	var deposits: Array = [] # [tipo, Transform3D, malha]
	result["deposits"] = deposits
	var zombies: Array = [] # posições
	result["zombies"] = zombies
	var items: Array = [] # [id, Transform3D, quantidade] (soltos no chão)
	result["items"] = items
	# Árvores: grade de 4 m com posição sorteada dentro da célula. O bioma
	# decide a densidade e a espécie.
	for gz in 8:
		for gx in 8:
			var x := origin.x + (gx + rng.randf()) * 4.0
			var z := origin.y + (gz + rng.randf()) * 4.0
			var chance := _forest_density(x, z) * 0.75 + 0.02
			var roll := rng.randf()
			var pick := rng.randf()
			var pick2 := rng.randf()
			var size_roll := rng.randf()
			var yaw := rng.randf() * TAU
			var r := road_distances(x, z)
			if r.x < HIGHWAY_HALF_WIDTH + 3.5 or r.y < BYROAD_HALF_WIDTH + 3.0:
				continue
			var s := surface_height(x, z)
			var bw := biome_weights(x, z, s)
			var conifer := maxf(1.0 - (bw.x + bw.y + bw.z + bw.w), 0.0)
			var factor := conifer + bw.x * 0.95 + bw.y * 0.12 + bw.z * 0.22 + bw.w * 0.45
			if roll > chance * factor:
				continue
			if slope_at(x, z) > 0.75 or not _solid_ground(x, z, s) or not town_at(x, z).is_empty():
				continue
			var variant := _tree_species(bw, conifer, pick, pick2)
			var scale: float = [lerpf(1.3, 2.1, size_roll), lerpf(1.3, 2.1, size_roll), lerpf(1.3, 2.1, size_roll),
					lerpf(1.7, 2.5, size_roll), lerpf(1.5, 2.3, size_roll), lerpf(1.4, 2.0, size_roll)][variant]
			var ground := s - 0.25
			trees[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), Vector3(x, ground, z)))
			var height: float = TREE_HEIGHTS[variant] * scale
			var radius: float = [0.16, 0.16, 0.16, 0.11, 0.11, 0.15][variant] * scale
			var trunk: Variant = null
			if variant <= 2:
				var trunk_scale := Vector3(scale * 0.9, height * 0.42, scale * 0.9)
				trunks.append(Transform3D(Basis.IDENTITY.scaled(trunk_scale), Vector3(x, ground + trunk_scale.y * 0.5, z)))
				trunk = trunks.back()
			trunk_colliders.append([Vector3(x, ground + 2.0, z), radius])
			tree_list.append([variant, scale, trees[variant].back(), trunk, height, radius])
	# Vegetação baixa (sem colisão), conforme o bioma.
	for i in 30:
		var x := origin.x + rng.randf() * CHUNK_SIZE
		var z := origin.y + rng.randf() * CHUNK_SIZE
		var forest := _forest_density(x, z)
		var pick := rng.randf()
		var size := rng.randf_range(0.7, 1.35)
		var yaw := rng.randf() * TAU
		var keep := rng.randf()
		var r := road_distances(x, z)
		if r.x < HIGHWAY_HALF_WIDTH + 1.0 or r.y < BYROAD_HALF_WIDTH + 1.0:
			continue
		var s := surface_height(x, z)
		var bw := biome_weights(x, z, s)
		var kind := _undergrowth(bw, pick)
		var density := 0.25 + forest * 0.7
		if bw.y > 0.5:
			density = 0.75 # campo: capim e arbustos por toda parte
		elif bw.w > 0.6:
			density = 0.08
		elif bw.z > 0.5:
			density = 0.3
		if kind == "" or keep > density:
			continue
		if slope_at(x, z) > 0.9 or not _solid_ground(x, z, s):
			continue
		var t := town_at(x, z)
		if not t.is_empty() and (t["kind"] == "cidade" or Vector2(x, z).distance_to(t["center"]) < float(t["radius"]) * 0.8):
			continue
		_add(props, kind, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), Vector3(x, s - 0.04, z)))
	# Pedras, tocos e troncos caídos (com colisão).
	for i in 3:
		var x := origin.x + rng.randf() * CHUNK_SIZE
		var z := origin.y + rng.randf() * CHUNK_SIZE
		var pick := rng.randf()
		var yaw := rng.randf() * TAU
		var size := rng.randf_range(0.6, 1.1)
		var r := road_distances(x, z)
		if r.x < HIGHWAY_HALF_WIDTH + 4.0 or r.y < BYROAD_HALF_WIDTH + 4.0:
			continue
		var s := surface_height(x, z)
		if not _solid_ground(x, z, s) or not town_at(x, z).is_empty():
			continue
		var steep := slope_at(x, z)
		var kind := "boulder_01"
		if steep > 0.5 or pick > 0.92:
			# Rochedo assentado no ponto mais baixo do chão sob ele (numa
			# encosta, o lado de cima fica enterrado e nada flutua).
			var rock := "rochedo_%d" % rng.randi_range(0, 2)
			var big := rng.randf_range(0.55, 1.05)
			var t_rock := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * big),
					Vector3(x, seat_height(x, z, 1.6 * big) - 0.3 * big, z))
			_add(props, rock, t_rock)
			colliders.append([rock, t_rock])
			continue
		elif pick < 0.35:
			kind = "tree_stump_01"
		elif pick < 0.6:
			kind = "dead_tree_trunk"
		elif pick < 0.8:
			kind = "rock_moss_set_01"
			size *= 0.6
		var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), Vector3(x, seat_height(x, z, 0.6 * size) - 0.15 * size, z))
		if kind == "boulder_01":
			# Rocha solta: depósito de pedra (minerável com a picareta).
			deposits.append(["pedra", t, "boulder_01"])
			continue
		_add(props, kind, t)
		colliders.append([kind, t])
	_town_contents(coord, origin, rng, result, props, colliders, wrecks, weapons, zombies, items)
	_entrance_rocks(origin, rng, props, colliders)
	_cave_contents(origin, rng, props, colliders, deposits)
	_road_debris(coord, origin, rng, props, colliders, wrecks, weapons)
	# Zumbis: andando entre as carcaças dos engarrafamentos e, raros, na mata.
	var spawn := spawn_point()
	var crowd := 0
	for w in wrecks:
		if rng.randf() < 0.14 and crowd < 2:
			var t: Transform3D = w[1]
			var spot := t.origin + t.basis.x.normalized() * rng.randf_range(2.5, 4.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			crowd += 1
			_add_zombie(zombies, spot, spawn)
	if rng.randf() < 0.03:
		var x := origin.x + rng.randf() * CHUNK_SIZE
		var z := origin.y + rng.randf() * CHUNK_SIZE
		_add_zombie(zombies, Vector3(x, 0.0, z), spawn)
	# Arma perdida na mata, rara.
	if rng.randf() < 0.035:
		var x := origin.x + rng.randf() * CHUNK_SIZE
		var z := origin.y + rng.randf() * CHUNK_SIZE
		var s := surface_height(x, z)
		if _solid_ground(x, z, s):
			weapons.append([_weapon_pick(rng), _lying(rng, Vector3(x, s + 0.15, z))])
	result["trees"] = trees
	result["trunks"] = trunks
	result["trunk_colliders"] = trunk_colliders
	result["props"] = props
	result["colliders"] = colliders
	result["wrecks"] = wrecks
	result["weapons"] = weapons


## Espécie da árvore pelos pesos dos biomas (sorteio ponderado).
func _tree_species(weights: Vector4, conifer_weight: float, pick: float, pick2: float) -> int:
	# Pesos ao quadrado: o bioma dominante decide (a transição fica estreita).
	var bw := weights * weights
	var conifer := conifer_weight * conifer_weight
	var total := conifer + bw.x + bw.y + bw.z + bw.w
	var at := pick * total
	var fir := int(pick2 * 2.999)
	if at < conifer:
		return fir
	at -= conifer
	if at < bw.x:
		return 3 if pick2 < 0.85 else fir
	at -= bw.x
	if at < bw.y:
		return 3 if pick2 < 0.6 else fir
	at -= bw.y
	if at < bw.z:
		return 4 if pick2 < 0.55 else 5
	return fir if pick2 < 0.72 else 4


## Planta baixa do bioma ("" = nenhuma).
func _undergrowth(bw: Vector4, pick: float) -> String:
	if bw.w > 0.6:
		return "dry_branches_medium_01" if pick < 0.5 else ""
	if bw.z > 0.5:
		return "dry_branches_medium_01" if pick < 0.45 else ("shrub_03" if pick < 0.7 else "")
	if bw.y > 0.5:
		return "weed_plant_02" if pick < 0.55 else ("shrub_04" if pick < 0.85 else "shrub_02")
	if bw.x > 0.5:
		return "shrub_02" if pick < 0.3 else ("fern_02" if pick < 0.6 else ("shrub_04" if pick < 0.85 else "weed_plant_02"))
	return "fern_02" if pick < 0.65 else ("shrub_03" if pick < 0.88 else "dry_branches_medium_01")


# --- Conteúdo das vilas e cidades ----------------------------------------------------

## Prédios cujo centro cai neste pedaço (malha e caixas de colisão), postes,
## carcaças nas ruas, lixeiras, barris, mato junto às paredes, zumbis e o que
## dá para achar (armas, ferro de sucata, tábuas).
func _town_contents(coord: Vector2i, origin: Vector2, rng: RandomNumberGenerator, result: Dictionary, props: Dictionary,
		colliders: Array, wrecks: Array, weapons: Array, zombies: Array, items: Array) -> void:
	var rect := Rect2(origin, Vector2.ONE * CHUNK_SIZE)
	var center := Vector3(origin.x + CHUNK_SIZE * 0.5, 0.0, origin.y + CHUNK_SIZE * 0.5)
	var mine: Array = []
	var touching: Array = []
	for t: Dictionary in towns_near(center, 180.0):
		if Vector2(center.x, center.z).distance_to(t["center"]) < float(t["radius"]) + CHUNK_SIZE:
			touching.append(t)
		for b: Dictionary in t["buildings"]:
			var p: Vector3 = b["pos"]
			if rect.has_point(Vector2(p.x, p.z)):
				mine.append(b)
	result["buildings"] = mine
	if not mine.is_empty():
		result["building_mesh"] = _building_mesh(mine)
	if touching.is_empty():
		return
	var spawn := spawn_point()
	var t: Dictionary = touching[0]
	var city: bool = t["kind"] == "cidade"
	# Ruas: postes de luz apagados nas calçadas e carcaças abandonadas.
	for i in (10 if city else 4):
		var x := origin.x + rng.randf() * CHUNK_SIZE
		var z := origin.y + rng.randf() * CHUNK_SIZE
		var roll := rng.randf()
		var yaw := (PI * 0.5) * rng.randi_range(0, 3) + rng.randf_range(-0.25, 0.25)
		if Vector2(x, z).distance_to(t["center"]) > float(t["radius"]) - 4.0 or _inside_building(x, z, t, 1.5):
			continue
		var street := town_street_distance(x, z, t)
		var s := surface_height(x, z)
		if city and absf(street - (STREET_HALF + 1.6)) < 0.8 and roll < 0.35:
			var lamp := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, s - 0.05, z))
			_add(props, "street_lamp_01", lamp)
			colliders.append(["street_lamp_01", lamp])
		elif city and street < STREET_HALF - 1.0 and roll < 0.55:
			var kind: String = WRECK_KINDS[rng.randi() % 10]
			var paint: Color = PAINTS[rng.randi() % PAINTS.size()]
			paint.a = rng.randf_range(0.2, 0.75)
			wrecks.append([kind, Transform3D(Basis(Vector3.UP, yaw), Vector3(x, s, z)), paint])
		elif roll < 0.8:
			var kind: String = ["metal_trash_can", "Barrel_02", "wooden_military_crate", "trashbag", "old_tyre"][rng.randi() % 5]
			var thing := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, s - 0.02, z))
			_add(props, kind, thing)
			if kind != "trashbag":
				colliders.append([kind, thing])
		else:
			# Mato tomando conta.
			_add(props, "weed_plant_02" if rng.randf() < 0.6 else "shrub_04",
					Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.4)), Vector3(x, s - 0.04, z)))
	# Dentro das casas e do térreo dos prédios: caixotes e barris (quebráveis),
	# o que sobrou (sucata, tábuas, carvão, às vezes uma arma) e, às vezes,
	# um zumbi preso lá dentro.
	for b: Dictionary in mine:
		var p: Vector3 = b["pos"]
		var size: Vector3 = b["size"]
		var floor_y := p.y + FLOOR_TOP
		var hx := size.x * 0.5 - WALL - 0.6
		var hz := size.z * 0.5 - WALL - 0.6
		for corner: Vector2 in [Vector2(hx, -hz), Vector2(hx, hz)]:
			if rng.randf() < 0.7:
				var kind := "wooden_military_crate" if rng.randf() < 0.65 else "Barrel_02"
				var thing := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(p.x + corner.x, floor_y, p.z + corner.y))
				_add(props, kind, thing)
				colliders.append([kind, thing])
		var loot_roll := rng.randf()
		var loot_at := Vector3(p.x + rng.randf_range(-hx, hx) * 0.5, floor_y + 0.3, p.z + rng.randf_range(-hz, hz) * 0.5)
		if loot_roll < 0.18:
			weapons.append([_weapon_pick(rng), _lying(rng, loot_at - Vector3.UP * 0.15)])
		elif loot_roll < 0.75:
			items.append([["ferro", "tabua", "carvao", "graveto"][rng.randi() % 4],
					Transform3D(Basis(Vector3.UP, rng.randf() * TAU), loot_at), rng.randi_range(1, 3)])
		if rng.randf() < 0.2:
			zombies.append(Vector3(p.x - hx * 0.5, floor_y + 0.05, p.z))
	# Mato junto às paredes dos prédios deste pedaço.
	for b: Dictionary in mine:
		var p: Vector3 = b["pos"]
		var size: Vector3 = b["size"]
		for k in 3:
			var side := rng.randi() % 4
			var along := rng.randf_range(-0.45, 0.45)
			var offset := Vector2(along * size.x, (0.5 * size.z + 0.4) * (1.0 if side == 0 else -1.0)) if side < 2 \
					else Vector2((0.5 * size.x + 0.4) * (1.0 if side == 2 else -1.0), along * size.z)
			var at := Vector2(p.x, p.z) + offset
			_add(props, ["weed_plant_02", "shrub_02", "shrub_04"][rng.randi() % 3],
					Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3)),
					Vector3(at.x, surface_height(at.x, at.y) - 0.04, at.y)))
	# Zumbis: mais nas cidades.
	for i in (rng.randi_range(2, 4) if city else rng.randi_range(0, 2)):
		var x := origin.x + rng.randf() * CHUNK_SIZE
		var z := origin.y + rng.randf() * CHUNK_SIZE
		if Vector2(x, z).distance_to(t["center"]) < float(t["radius"]) and not _inside_building(x, z, t, 1.0):
			_add_zombie(zombies, Vector3(x, 0.0, z), spawn)
	# O que sobrou: armas, sucata de ferro e tábuas pelas ruas e quintais.
	if rng.randf() < (0.3 if city else 0.22):
		var x := origin.x + rng.randf() * CHUNK_SIZE
		var z := origin.y + rng.randf() * CHUNK_SIZE
		if not _inside_building(x, z, t, 1.0):
			weapons.append([_weapon_pick(rng), _lying(rng, Vector3(x, surface_height(x, z) + 0.15, z))])
	for i in 2:
		if rng.randf() < 0.35:
			var x := origin.x + rng.randf() * CHUNK_SIZE
			var z := origin.y + rng.randf() * CHUNK_SIZE
			if Vector2(x, z).distance_to(t["center"]) < float(t["radius"]) and not _inside_building(x, z, t, 1.0):
				var id := "ferro" if (city and rng.randf() < 0.6) else "tabua"
				items.append([id, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, surface_height(x, z) + 0.3, z)),
						rng.randi_range(1, 3)])


func _inside_building(x: float, z: float, t: Dictionary, margin: float) -> bool:
	for b: Dictionary in t["buildings"]:
		var p: Vector3 = b["pos"]
		var size: Vector3 = b["size"]
		if absf(x - p.x) < size.x * 0.5 + margin and absf(z - p.z) < size.z * 0.5 + margin:
			return true
	return false


## Malha dos prédios (uma superfície, material de fachada) e as caixas de
## colisão. Casas e o térreo dos prédios têm interior de verdade: paredes com
## vãos de porta e janela (dá para entrar), piso, teto, parede interna com
## passagem e, nas casas de dois andares, escada e piso de cima com o vão
## dela. Os andares de cima dos prédios da cidade são fechados (janelas
## pintadas na fachada). UV em metros (u ao longo da parede, v a partir do
## chão). Cor do vértice: r = estilo/7, g = tom, b = 1 se a face tem janelas
## pintadas, a = semente do prédio.
const WALL := 0.25
## Piso interno acima do platô.
const FLOOR_TOP := 0.12


func _building_mesh(list: Array) -> Dictionary:
	# Arrays comuns (passados por referência) durante a montagem; os
	# Packed* só no fim (dentro de um dicionário, cada acréscimo copiaria).
	var m := {"vertices": [], "normals": [], "uvs": [], "colors": [], "boxes": []}
	for b: Dictionary in list:
		_building(m, b)
	var count := (m["vertices"] as Array).size()
	var indices := PackedInt32Array()
	indices.resize(count)
	for i in count:
		indices[i] = i
	return {"vertices": PackedVector3Array(m["vertices"]), "normals": PackedVector3Array(m["normals"]),
			"uvs": PackedVector2Array(m["uvs"]), "colors": PackedColorArray(m["colors"]), "indices": indices, "boxes": m["boxes"]}


func _building(m: Dictionary, b: Dictionary) -> void:
	var p: Vector3 = b["pos"]
	var size: Vector3 = b["size"]
	var seed_value := float(int(b["seed"]) % 997) / 997.0
	var tone := fposmod(seed_value * 7.31, 1.0)
	var style := float(b["style"]) / 7.0
	var outer := Color(style, tone, 0.0, seed_value)
	var painted := Color(style, tone, 1.0, seed_value)
	# Faces internas (b = 0,5): sem janelas pintadas nem trepadeiras.
	var inner := Color(1.0 / 7.0, 0.55, 0.5, seed_value)
	var boards := Color(3.0 / 7.0, 0.3, 0.5, seed_value)
	var house: bool = int(b["roof"]) == 1
	var floors: int = int(b.get("floors", 1))
	var open_floors := floors if house else 1
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var bottom := p.y - 1.5
	var top := p.y + size.y
	var open_top := top if house else p.y + FLOOR_HEIGHT
	var front: Vector2 = b.get("front", Vector2(0.0, 1.0))
	# Paredes externas: [de, até, normal para fora].
	var sides := [[Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector2(0, 1)], [Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz), Vector2(0, -1)],
			[Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector2(1, 0)], [Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz), Vector2(-1, 0)]]
	for side: Array in sides:
		var a: Vector3 = p + (side[0] as Vector3)
		var c: Vector3 = p + (side[1] as Vector3)
		var n2: Vector2 = side[2]
		var length := a.distance_to(c)
		var openings := []
		var is_front := n2.is_equal_approx(front)
		for level in open_floors:
			var y0 := level * FLOOR_HEIGHT
			if level == 0 and is_front:
				openings.append([length * 0.5 - 0.6, length * 0.5 + 0.6, FLOOR_TOP, 2.3])
				if not house and length > 6.0:
					openings.append([1.0, length * 0.5 - 1.3, 0.6, 2.6])
					openings.append([length * 0.5 + 1.3, length - 1.0, 0.6, 2.6])
				elif length > 5.0:
					openings.append([length * 0.18 - 0.55, length * 0.18 + 0.55, 0.95, 2.15])
					openings.append([length * 0.82 - 0.55, length * 0.82 + 0.55, 0.95, 2.15])
			else:
				var bays := maxi(int(length / 3.2), 1)
				for k in bays:
					var center := (k + 0.5) * length / bays
					if center - 0.55 > 0.7 and center + 0.55 < length - 0.7:
						openings.append([center - 0.55, center + 0.55, y0 + 0.95, y0 + 2.15])
		_wall(m, a, c, Vector3(n2.x, 0.0, n2.y), bottom, open_top, p.y, openings, outer, inner)
		if top > open_top + 0.01:
			# Andares de cima (cidade): parede maciça com as janelas pintadas.
			_wall(m, a, c, Vector3(n2.x, 0.0, n2.y), open_top, top, p.y, [], painted, inner)
	# Piso do térreo.
	var inside := Vector3(size.x - WALL * 2.0, 0.2, size.z - WALL * 2.0)
	_cuboid(m, p + Vector3(-inside.x * 0.5, FLOOR_TOP - 0.2, -inside.z * 0.5), p + Vector3(inside.x * 0.5, FLOOR_TOP, inside.z * 0.5),
			p.y, Vector3.UP, boards, inner, true)
	# Escada e piso de cima (casa de dois andares), teto do último andar.
	var stair_x0 := -hx + WALL + 0.35
	var stair_z0 := hz - WALL - 1.15
	for level in range(1, open_floors + 1):
		var y := p.y + level * FLOOR_HEIGHT
		if level == open_floors:
			y = open_top - 0.05 if house else y
		var lo := p + Vector3(-inside.x * 0.5, y - p.y - 0.2, -inside.z * 0.5)
		var hi := p + Vector3(inside.x * 0.5, y - p.y, inside.z * 0.5)
		if house and level < open_floors:
			var hole_lo := Vector3(p.x + stair_x0 - 0.1, 0.0, p.z + stair_z0 - 0.05)
			var hole_hi := Vector3(p.x + stair_x0 + 3.7, 0.0, hi.z)
			for piece: Array in [[lo, Vector3(hole_lo.x, hi.y, hi.z)], [Vector3(hole_hi.x, lo.y, lo.z), hi],
					[Vector3(hole_lo.x, lo.y, lo.z), Vector3(hole_hi.x, hi.y, hole_lo.z)]]:
				_cuboid(m, piece[0], piece[1], p.y, Vector3.UP, boards, inner, true)
		else:
			_cuboid(m, lo, hi, p.y, Vector3.UP, boards if level < open_floors else inner, inner, true)
	if house and open_floors >= 2:
		_stairs(m, p + Vector3(stair_x0, 0.0, stair_z0), 3.6, 1.0, FLOOR_HEIGHT, boards, inner)
	# Parede interna do térreo (casa), com passagem no meio.
	if house and size.x > 6.0:
		var x := p.x + hx * 0.3
		_wall(m, Vector3(x, 0, p.z - hz + WALL), Vector3(x, 0, p.z + hz - WALL), Vector3.RIGHT, p.y, p.y + FLOOR_HEIGHT - 0.05, p.y,
				[[(size.z - WALL * 2.0) * 0.5 - 0.5, (size.z - WALL * 2.0) * 0.5 + 0.5, FLOOR_TOP, 2.2]], inner, inner)
	# Telhado.
	if house:
		_gable(m["vertices"], m["normals"], m["uvs"], m["colors"], p, size, top, tone, seed_value, style)
	else:
		_cuboid(m, p + Vector3(-hx, size.y - 0.2, -hz), p + Vector3(hx, size.y, hz), p.y, Vector3.UP,
				Color(2.0 / 7.0, tone, 0.0, seed_value), inner, true)


## Parede de `a` a `c` (eixo x ou z), espessura para dentro, de `y_from` a
## `y_to`, com vãos [u0, u1, v0, v1] (u ao longo da parede, v desde `ground`).
## Cada pedaço maciço vira uma caixa (malha e colisão).
func _wall(m: Dictionary, a: Vector3, c: Vector3, normal: Vector3, y_from: float, y_to: float, ground: float,
		openings: Array, outer: Color, inner: Color) -> void:
	var length := a.distance_to(c)
	var along := (c - a) / length
	var v_min := y_from - ground
	var v_max := y_to - ground
	var cuts := [0.0, length]
	for o: Array in openings:
		cuts.append(clampf(o[0], 0.0, length))
		cuts.append(clampf(o[1], 0.0, length))
	cuts.sort()
	for i in cuts.size() - 1:
		var u0: float = cuts[i]
		var u1: float = cuts[i + 1]
		if u1 - u0 < 0.01:
			continue
		var holes := []
		for o: Array in openings:
			if float(o[0]) <= u0 + 0.001 and float(o[1]) >= u1 - 0.001:
				holes.append([maxf(float(o[2]), v_min), minf(float(o[3]), v_max)])
		holes.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		var v := v_min
		for h: Array in holes:
			if float(h[0]) > v + 0.01:
				_wall_piece(m, a, along, normal, u0, u1, v, h[0], ground, outer, inner)
			v = maxf(v, h[1])
		if v_max > v + 0.01:
			_wall_piece(m, a, along, normal, u0, u1, v, v_max, ground, outer, inner)


func _wall_piece(m: Dictionary, a: Vector3, along: Vector3, normal: Vector3, u0: float, u1: float, v0: float, v1: float,
		ground: float, outer: Color, inner: Color) -> void:
	var p0 := a + along * u0
	var p1 := a + along * u1 - normal * WALL
	var lo := Vector3(minf(p0.x, p1.x), ground + v0, minf(p0.z, p1.z))
	var hi := Vector3(maxf(p0.x, p1.x), ground + v1, maxf(p0.z, p1.z))
	_cuboid(m, lo, hi, ground, normal, outer, inner, true)


## Caixa alinhada aos eixos: a face virada para `special` usa a cor
## `special_color`, as outras `other`. Com `solid`, também é colisão.
func _cuboid(m: Dictionary, lo: Vector3, hi: Vector3, ground: float, special: Vector3, special_color: Color, other: Color,
		solid: bool) -> void:
	var faces := [
		[Vector3.UP, [Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
		[Vector3.DOWN, [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)]],
		[Vector3.RIGHT, [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)]],
		[Vector3.LEFT, [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)]],
		[Vector3.BACK, [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
		[Vector3.FORWARD, [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)]],
	]
	for face: Array in faces:
		var normal: Vector3 = face[0]
		var corners: Array = face[1]
		var uv := []
		for q: Vector3 in corners:
			if absf(normal.y) > 0.5:
				uv.append(Vector2(q.x, q.z))
			elif absf(normal.x) > 0.5:
				uv.append(Vector2(q.z, q.y - ground))
			else:
				uv.append(Vector2(q.x, q.y - ground))
		var color := special_color if normal.is_equal_approx(special) else other
		_face(m["vertices"], m["normals"], m["uvs"], m["colors"], corners, normal, uv, color)
	if solid:
		(m["boxes"] as Array).append([Transform3D(Basis.IDENTITY, (lo + hi) * 0.5), hi - lo])


## Escada reta ao longo de +x: degraus (malha) e uma rampa de colisão.
func _stairs(m: Dictionary, start: Vector3, run: float, width: float, rise: float, boards: Color, inner: Color) -> void:
	var steps := 12
	for i in steps:
		var lo := start + Vector3(run * i / steps, FLOOR_TOP - 0.05, 0.0)
		var hi := start + Vector3(run * (i + 1) / steps, FLOOR_TOP + rise * (i + 1) / steps, width)
		_cuboid(m, lo, hi, start.y, Vector3.UP, boards, inner, false)
	var angle := atan2(rise, run)
	var length := Vector2(run, rise).length()
	var basis := Basis(Vector3.BACK, angle)
	var center := start + Vector3(run * 0.5, FLOOR_TOP + rise * 0.5 - 0.08, width * 0.5)
	(m["boxes"] as Array).append([Transform3D(basis, center), Vector3(length + 0.3, 0.1, width)])


func _face(vertices: Array, normals: Array, uvs: Array, colors: Array,
		corners: Array, normal: Vector3, uv: Array, color: Color) -> void:
	# Dois triângulos com a face da frente para `normal` (sentido horário no Godot).
	var order := [0, 1, 2, 0, 2, 3]
	var face := ((corners[1] as Vector3) - (corners[0] as Vector3)).cross((corners[2] as Vector3) - (corners[0] as Vector3))
	if face.dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i: int in order:
		vertices.append(corners[i])
		normals.append(normal)
		uvs.append(uv[i])
		colors.append(color)


## Telhado de duas águas ao longo do lado maior, com oitões (triângulos) de parede.
func _gable(vertices: Array, normals: Array, uvs: Array, colors: Array,
		p: Vector3, size: Vector3, top: float, tone: float, seed_value: float, style: float) -> void:
	var along_x := size.x >= size.z
	var half_long := (size.x if along_x else size.z) * 0.5 + 0.35
	var half_short := (size.z if along_x else size.x) * 0.5 + 0.45
	var rise := half_short * 0.7
	var roof_color := Color((5.0 if seed_value > 0.7 else 4.0) / 7.0, tone, 0.0, seed_value)
	var wall_color := Color(style, tone, 0.0, seed_value)
	for side: float in [-1.0, 1.0]:
		var e0: Vector3
		var e1: Vector3
		var r0: Vector3
		var r1: Vector3
		if along_x:
			e0 = p + Vector3(-half_long, top - p.y, side * half_short)
			e1 = p + Vector3(half_long, top - p.y, side * half_short)
			r0 = p + Vector3(-half_long, top - p.y + rise, 0.0)
			r1 = p + Vector3(half_long, top - p.y + rise, 0.0)
		else:
			e0 = p + Vector3(side * half_short, top - p.y, -half_long)
			e1 = p + Vector3(side * half_short, top - p.y, half_long)
			r0 = p + Vector3(0.0, top - p.y + rise, -half_long)
			r1 = p + Vector3(0.0, top - p.y + rise, half_long)
		var slope_length := Vector2(half_short, rise).length()
		var normal := ((e1 - e0).cross(r0 - e0)).normalized()
		if normal.y < 0.0:
			normal = -normal
		_face(vertices, normals, uvs, colors, [e0, e1, r1, r0], normal,
				[Vector2(0, 0), Vector2(half_long * 2.0, 0), Vector2(half_long * 2.0, slope_length), Vector2(0, slope_length)], roof_color)
		# Por baixo do beiral (a casa vista de baixo não fica oca).
		_face(vertices, normals, uvs, colors, [e0, e1, r1, r0], -normal,
				[Vector2(0, 0), Vector2(half_long * 2.0, 0), Vector2(half_long * 2.0, slope_length), Vector2(0, slope_length)], roof_color)
	# Oitões.
	for end: float in [-1.0, 1.0]:
		var a: Vector3
		var b: Vector3
		var apex: Vector3
		var normal: Vector3
		if along_x:
			var x := end * size.x * 0.5
			a = p + Vector3(x, top - p.y, -size.z * 0.5)
			b = p + Vector3(x, top - p.y, size.z * 0.5)
			apex = p + Vector3(x, top - p.y + rise * (size.z * 0.5) / half_short, 0.0)
			normal = Vector3(end, 0, 0)
		else:
			var z := end * size.z * 0.5
			a = p + Vector3(-size.x * 0.5, top - p.y, z)
			b = p + Vector3(size.x * 0.5, top - p.y, z)
			apex = p + Vector3(0.0, top - p.y + rise * (size.x * 0.5) / half_short, z)
			normal = Vector3(0, 0, end)
		var span := a.distance_to(b)
		var tri := [a, b, apex]
		var tri_uv := [Vector2(0, top - p.y), Vector2(span, top - p.y), Vector2(span * 0.5, apex.y - p.y)]
		var order := [0, 1, 2]
		if (b - a).cross(apex - a).dot(normal) > 0.0:
			order = [0, 2, 1]
		for i: int in order:
			vertices.append(tri[i])
			normals.append(normal)
			uvs.append(tri_uv[i])
			colors.append(wall_color)


const WRECK_KINDS := ["car_01", "car_02", "car_03", "car_04", "jeep_01", "jeep_02", "pickup",
		"car_01", "car_02", "car_03", "truck_01", "truck_02", "truck_03", "truck_04", "truck_05", "bus"]
const WRECK_LENGTHS := {"car_01": 4.0, "car_02": 4.6, "car_03": 4.9, "car_04": 4.0, "jeep_01": 4.2,
		"jeep_02": 4.2, "pickup": 5.3, "truck_01": 7.6, "truck_02": 7.8, "truck_03": 7.8,
		"truck_04": 5.8, "truck_05": 6.2, "bus": 10.5}
## Pinturas de fábrica desbotadas (o alfa é a ferrugem mínima).
const PAINTS := [Color(0.42, 0.12, 0.09), Color(0.16, 0.22, 0.3), Color(0.62, 0.62, 0.58),
		Color(0.27, 0.3, 0.2), Color(0.45, 0.44, 0.42), Color(0.5, 0.38, 0.14),
		Color(0.2, 0.2, 0.21), Color(0.55, 0.45, 0.12), Color(0.3, 0.12, 0.12)]
const DEBRIS := ["vintage_suitcase", "trashbag", "trashbag", "plastic_jerrycan", "metal_jerrycan_green",
		"old_tyre", "rusted_wheel_rim_01", "can_rusted", "can_rusted", "Barrel_02", "wooden_military_crate"]
const SPAWN_CLEARANCE := 14.0


## Congestionamento abandonado: trechos da rodovia (onde o ruído de
## engarrafamento é alto) cheios de carcaças nas duas faixas, umas atravessadas
## ou jogadas no acostamento, com malas, sacos, galões e pneus pelo chão.
func _road_debris(coord: Vector2i, origin: Vector2, rng: RandomNumberGenerator, props: Dictionary,
		colliders: Array, wrecks: Array, weapons: Array) -> void:
	# Rodovia (norte-sul): percorre o trecho do pedaço em z.
	var z := origin.y + rng.randf_range(0.0, 6.0)
	while z < origin.y + CHUNK_SIZE:
		var cx := highway_center_x(origin.x + CHUNK_SIZE * 0.5, z)
		var jam := _jams.get_noise_1d(z)
		var kind: String = WRECK_KINDS[rng.randi() % WRECK_KINDS.size()]
		var length: float = WRECK_LENGTHS[kind]
		var lane := -1.0 if rng.randf() < 0.5 else 1.0
		var ditch := rng.randf() < 0.12
		var angle := rng.randf_range(-0.35, 0.35) + (PI if rng.randf() < 0.5 else 0.0)
		var paint: Color = PAINTS[rng.randi() % PAINTS.size()]
		paint.a = rng.randf_range(0.45, 0.85)
		var debris := rng.randi_range(0, 3)
		var step := length + rng.randf_range(1.5, 9.0)
		if cx >= origin.x and cx < origin.x + CHUNK_SIZE and jam > -0.05 and absf(z) + absf(cx) > SPAWN_CLEARANCE:
			var offset := lane * (2.0 + rng.randf_range(-0.4, 0.4))
			if ditch:
				offset = lane * (HIGHWAY_HALF_WIDTH + 3.0)
				angle += rng.randf_range(-0.9, 0.9)
			# Direção da estrada (o eixo serpenteia).
			var ahead := highway_center_x(cx, z + 2.0) - highway_center_x(cx, z - 2.0)
			var heading := atan2(ahead, 4.0)
			var x := cx + offset
			var y := surface_height(x, z)
			var basis := Basis(Vector3.UP, heading + angle)
			if ditch:
				# Carcaça caída no barranco: inclinada pelo terreno e de lado às vezes.
				basis = basis * Basis(Vector3.FORWARD, rng.randf_range(-0.25, 0.25) + (PI * 0.5 if rng.randf() < 0.2 else 0.0))
			var t := Transform3D(basis, Vector3(x, y - 0.05, z))
			wrecks.append([kind, t, paint])
			for i in debris:
				var item: String = DEBRIS[rng.randi() % DEBRIS.size()]
				var spot := Vector3(x + rng.randf_range(-3.0, 3.0), 0.0, z + rng.randf_range(-length * 0.6, length * 0.6))
				spot.y = surface_height(spot.x, spot.z)
				var lie := Basis(Vector3.UP, rng.randf() * TAU)
				if item in ["vintage_suitcase", "old_tyre", "rusted_wheel_rim_01", "metal_jerrycan_green"] and rng.randf() < 0.7:
					lie = lie * Basis(Vector3.RIGHT, PI * 0.5) if item != "vintage_suitcase" else lie
				_add(props, item, Transform3D(lie, spot))
				if item in ["Barrel_02", "wooden_military_crate"]:
					colliders.append([item, Transform3D(lie, spot)])
			if rng.randf() < 0.06:
				var spot := Vector3(x + lane * 2.6, 0.0, z + rng.randf_range(-2.0, 2.0))
				spot.y = surface_height(spot.x, spot.z) + 0.15
				weapons.append([_weapon_pick(rng), _lying(rng, spot)])
		z += step
	# Estrada vicinal (leste-oeste): carros esparsos e lonas.
	var x := origin.x + rng.randf_range(0.0, 10.0)
	while x < origin.x + CHUNK_SIZE:
		var cz := byroad_center_z(x, origin.y + CHUNK_SIZE * 0.5)
		var roll := rng.randf()
		var kind := "covered_car" if roll < 0.3 else (WRECK_KINDS[rng.randi() % 7] as String)
		var angle := rng.randf_range(-0.5, 0.5)
		var paint: Color = PAINTS[rng.randi() % PAINTS.size()]
		paint.a = rng.randf_range(0.5, 0.9)
		var side := rng.randf_range(-1.2, 1.2)
		if cz >= origin.y and cz < origin.y + CHUNK_SIZE and roll < 0.45 and absf(x) + absf(cz) > SPAWN_CLEARANCE:
			var y := surface_height(x, cz + side)
			var t := Transform3D(Basis(Vector3.UP, PI * 0.5 + angle), Vector3(x, y - 0.05, cz + side))
			if kind == "covered_car":
				_add(props, kind, t)
				colliders.append([kind, t])
			else:
				wrecks.append([kind, t, paint])
		x += rng.randf_range(14.0, 30.0)


## Rochas em volta da boca das rampas de entrada que começam neste pedaço.
func _entrance_rocks(origin: Vector2, _rng: RandomNumberGenerator, props: Dictionary, colliders: Array) -> void:
	var center := Vector3(origin.x + CHUNK_SIZE * 0.5, 0.0, origin.y + CHUNK_SIZE * 0.5)
	for e in entrances_near(center, REGION * 1.5):
		var top: Vector3 = e["top"]
		if top.x < origin.x or top.x >= origin.x + CHUNK_SIZE or top.z < origin.y or top.z >= origin.y + CHUNK_SIZE:
			continue
		var bottom: Vector3 = e["bottom"]
		var half: float = e["half"]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(int(top.x), int(top.z), world_seed + 5))
		var down := Vector2(bottom.x - top.x, bottom.z - top.z).normalized()
		var side := Vector2(-down.y, down.x)
		var heading := atan2(down.x, down.y)
		for k: float in [-1.0, 1.0]:
			for j in 2:
				var at := Vector2(top.x, top.z) + side * k * (half * 1.35 + 2.2 + j * 1.5) + down * (2.0 + j * 5.0)
				var size := rng.randf_range(0.6, 0.95)
				var rock := "rochedo_%d" % rng.randi_range(0, 2)
				var t := Transform3D(Basis(Vector3.UP, heading + k * PI * 0.5 + rng.randf_range(-0.4, 0.4)).scaled(Vector3.ONE * size),
						Vector3(at.x, seat_height(at.x, at.y, 1.6 * size) - 0.35 * size, at.y))
				_add(props, rock, t)
				colliders.append([rock, t])
		for j in 3:
			var at := Vector2(top.x, top.z) + side * rng.randf_range(-half * 2.0, half * 2.0) - down * rng.randf_range(1.0, 5.0)
			var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.4, 0.8)),
					Vector3(at.x, surface_height(at.x, at.y) - 0.2, at.y))
			_add(props, "rock_moss_set_01" if j == 0 else "boulder_01", t)


## Dentro das galerias deste pedaço: estalagmites, estalactites, entulho e
## depósitos de minério junto às paredes. Só em pontos de chão real da
## galeria (procura o chão e o teto no campo de densidade).
func _cave_contents(origin: Vector2, rng: RandomNumberGenerator, props: Dictionary, colliders: Array, deposits: Array) -> void:
	for i in 22:
		var x := origin.x + rng.randf() * CHUNK_SIZE
		var z := origin.y + rng.randf() * CHUNK_SIZE
		var roll := rng.randf()
		var size := rng.randf_range(0.7, 1.4)
		var yaw := rng.randf() * TAU
		var pick := rng.randf()
		var s := surface_height(x, z)
		var g := gallery_at(x, z, s)
		if g.x > g.y * 0.92:
			continue
		var across := g.x / g.y
		var roads := road_distances(x, z)
		# Chão: desce a partir de um pouco acima do chão previsto.
		var y := g.w + 1.6
		var floor_found := false
		for step in 16:
			if density_at(x, y - 0.25, z, s, roads) > 0.0:
				floor_found = true
				break
			y -= 0.25
		if not floor_found or density_at(x, y + 0.5, z, s, roads) > 0.0:
			continue
		var floor_point := Vector3(x, y, z)
		# O meio da galeria fica livre para passar (formações e entulho só
		# para os lados) e nada perto do pé das rampas.
		if across < 0.45 or _near_ramp_bottom(x, z, 9.0):
			continue
		if roll < 0.3:
			var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, size * rng.randf_range(0.8, 1.6), size)), floor_point - Vector3.UP * 0.15)
			_add(props, "estalagmite", t)
			# Colisão: cilindro fino no tronco da formação (a ponta é fina).
			colliders.append(["estalagmite", t])
		elif roll < 0.55:
			# Teto: sobe até a rocha.
			var top := y + 0.5
			while top < y + 9.0 and density_at(x, top, z, s, roads) < 0.0:
				top += 0.25
			if top - y > 3.2 and top < y + 9.0:
				var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, size * rng.randf_range(0.7, 1.3), size)), Vector3(x, top + 0.2, z))
				_add(props, "estalactite", t)
		elif roll < 0.72:
			# Entulho miúdo: sem colisão (pedras de meio metro não barram
			# ninguém; caixas de colisão nelas viravam paredes invisíveis).
			var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size * 0.35), floor_point - Vector3.UP * 0.1)
			_add(props, "boulder_01", t)
		else:
			# Minério na base da parede, virado para dentro da galeria.
			var kind := "carvao" if pick < 0.5 else ("ferro" if pick < 0.85 else "pedra")
			var mesh := "boulder_01" if kind == "pedra" else "minerio_" + kind
			var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)), floor_point - Vector3.UP * 0.2)
			deposits.append([kind, t, mesh])


func _near_ramp_bottom(x: float, z: float, radius: float) -> bool:
	for e in entrances_near(Vector3(x, 0.0, z), REGION):
		var b: Vector3 = e["bottom"]
		if Vector2(b.x - x, b.z - z).length() < radius + 4.0:
			return true
	return false


const ZOMBIE_CLEARANCE := 45.0


func _add_zombie(zombies: Array, spot: Vector3, spawn: Vector3) -> void:
	if Vector2(spot.x - spawn.x, spot.z - spawn.z).length() < ZOMBIE_CLEARANCE:
		return
	var s := surface_height(spot.x, spot.z)
	if not _solid_ground(spot.x, spot.z, s):
		return
	zombies.append(Vector3(spot.x, s + 0.05, spot.z))


func _add(props: Dictionary, kind: String, t: Transform3D) -> void:
	if not props.has(kind):
		props[kind] = []
	(props[kind] as Array).append(t)


func _weapon_pick(rng: RandomNumberGenerator) -> String:
	return ["taco", "machado", "picareta"][rng.randi() % 3]


## Arma deitada (cabo na horizontal), em direção sorteada.
func _lying(rng: RandomNumberGenerator, spot: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, PI * 0.5), spot)


# --- Ponto de partida ----------------------------------------------------------

## Onde o jogador começa: na rodovia mais próxima da origem, em chão firme.
func spawn_point() -> Vector3:
	var x := highway_center_x(0.0, 0.0)
	return Vector3(x, surface_height(x, 0.0) + 0.1, 0.0)
