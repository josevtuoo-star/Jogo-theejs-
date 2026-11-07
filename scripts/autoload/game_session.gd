extends Node
## Sessão de jogo (singleton GameSession): qual mundo está aberto, a semente,
## a aparência do personagem e o salvamento.
##
## Os mundos ficam na memória interna do aparelho, na pasta do próprio jogo
## (user://mundos/<id>/mundo.json; no Android, o armazenamento privado do
## aplicativo). Antes de gravar qualquer coisa o jogo pede permissão ao
## jogador (uma vez); sem permissão, joga-se sem salvar.
##
## Cada mundo tem a sua semente: a mesma semente gera sempre o mesmo mundo
## (relevo, cavernas, estradas, cidades). Sem semente digitada, é sorteada.

signal saved(world_id: String)

const WORLDS_DIR := "user://mundos/"
const SETTINGS_FILE := "user://config.cfg"
## Mundo da cena aberta direto (editor, testes): não salva.
const DEFAULT_SEED := 20261102

## Jogador já respondeu à pergunta de salvar?
var storage_asked: bool = false
## Permissão para gravar os mundos na memória do aparelho.
var storage_allowed: bool = false
var look: Dictionary = CharacterLook.default_look()
## Configurações (menu CONFIGURAÇÕES): distância de visão em pedaços de 32 m,
## sombras (0 desligadas, 1 baixas, 2 altas), sensibilidade da câmera,
## duração do dia (minutos reais por dia de jogo).
var settings: Dictionary = {"distancia": 3, "sombras": 1, "sensibilidade": 1.0, "dia_minutos": 24.0}

signal settings_changed

## Mundo aberto pelo menu (false: cena aberta direto, sem salvar).
var active: bool = false
var world_id: String = ""
var world_name: String = ""
var world_seed: int = DEFAULT_SEED
## Estado salvo do mundo aberto (posição, mochila, o que foi colhido...).
var world_state: Dictionary = {}


func _ready() -> void:
	_load_settings()
	apply_input_settings()


# --- Configuração --------------------------------------------------------------

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) != OK:
		return
	storage_asked = config.get_value("armazenamento", "perguntado", false)
	storage_allowed = config.get_value("armazenamento", "permitido", false)
	var saved_settings: Dictionary = config.get_value("jogo", "configuracoes", {})
	for key: String in settings:
		if saved_settings.has(key):
			settings[key] = saved_settings[key]
	var saved_look: Dictionary = config.get_value("personagem", "aparencia", {})
	for part: String in CharacterLook.ORDER:
		look[part] = int(saved_look.get(part, 0))


## Grava as preferências (só com permissão; a resposta "não" também fica só na
## memória até o jogo fechar).
func save_settings() -> void:
	if not storage_allowed:
		return
	var config := ConfigFile.new()
	config.set_value("armazenamento", "perguntado", storage_asked)
	config.set_value("armazenamento", "permitido", storage_allowed)
	config.set_value("personagem", "aparencia", look)
	config.set_value("jogo", "configuracoes", settings)
	config.save(SETTINGS_FILE)


## Muda uma configuração, aplica (quem estiver ouvindo) e grava.
func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_input_settings()
	settings_changed.emit()
	save_settings()


func apply_input_settings() -> void:
	var factor := float(settings.get("sensibilidade", 1.0))
	GameInput.mouse_sensitivity = 0.0022 * factor
	GameInput.touch_sensitivity = 0.0032 * factor


func set_storage_permission(allowed: bool) -> void:
	storage_asked = true
	storage_allowed = allowed
	if allowed:
		DirAccess.make_dir_recursive_absolute(WORLDS_DIR)
		save_settings()


# --- Sementes ------------------------------------------------------------------

## Semente a partir do texto digitado: número vale como está; palavras viram
## número (a mesma palavra gera sempre o mesmo mundo). Vazio = sorteio.
static func seed_from_text(text: String) -> int:
	var clean := text.strip_edges()
	if clean.is_empty():
		return random_seed()
	if clean.is_valid_int():
		return int(clean) & 0x7fffffff
	return hash(clean) & 0x7fffffff


static func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi() & 0x7fffffff


# --- Mundos --------------------------------------------------------------------

## Abre um mundo novo (ainda sem estado salvo).
func new_world(display_name: String, seed_value: int) -> void:
	active = true
	world_seed = seed_value
	world_name = display_name.strip_edges() if not display_name.strip_edges().is_empty() else "Mundo %d" % (list_worlds().size() + 1)
	world_id = "%d_%d" % [int(Time.get_unix_time_from_system()), seed_value % 100000]
	world_state = {}
	if storage_allowed:
		save_world({})


## Mundos salvos, do jogado mais recentemente ao mais antigo.
func list_worlds() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var dir := DirAccess.open(WORLDS_DIR)
	if dir == null:
		return list
	for folder in dir.get_directories():
		var data := _read(folder)
		if not data.is_empty():
			data["id"] = folder
			list.append(data)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("jogado", 0.0)) > float(b.get("jogado", 0.0)))
	return list


func load_world(id: String) -> bool:
	var data := _read(id)
	if data.is_empty():
		return false
	active = true
	world_id = id
	world_name = data.get("nome", id)
	world_seed = int(data.get("semente", DEFAULT_SEED))
	world_state = data.get("estado", {})
	return true


func delete_world(id: String) -> void:
	var path := WORLDS_DIR + id
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)


## Grava o estado do mundo aberto. Retorna se gravou.
func save_world(state: Dictionary) -> bool:
	if not active or not storage_allowed or world_id.is_empty():
		return false
	world_state = state
	DirAccess.make_dir_recursive_absolute(WORLDS_DIR + world_id)
	var data := {"nome": world_name, "semente": world_seed, "jogado": Time.get_unix_time_from_system(),
			"versao": 1, "estado": state}
	var file := FileAccess.open(WORLDS_DIR + world_id + "/mundo.json", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	saved.emit(world_id)
	return true


func _read(id: String) -> Dictionary:
	var file := FileAccess.open(WORLDS_DIR + id + "/mundo.json", FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
