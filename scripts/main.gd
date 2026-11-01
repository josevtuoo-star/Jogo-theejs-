extends Node3D
## Cena principal: prepara controles, áudio e configurações; põe o jogador no ponto de partida
## do mapa real (já com o terreno em volta montado); HUD com versão, FPS, câmera, estado do
## personagem, peso carregado, a dica do botão USAR e mensagens curtas.

@onready var player: CharacterBody3D = $Player
@onready var info: Label = $HUD/Info
@onready var help: Label = $HUD/Help
@onready var hint: Label = $HUD/Dica


func _enter_tree() -> void:
	Inputs.setup()
	Audio.setup()
	Config.load_cfg()
	Sfx.warmup() # sons gerados aos poucos nos primeiros segundos


func _ready() -> void:
	help.visible = not Inputs.touch_mode
	var mundo := get_node_or_null("Mundo")
	if mundo and mundo.has_method("spawn_point"):
		var sp: Vector3 = mundo.spawn_point()
		mundo.preload_around(sp)
		player.place_at(sp, -PI * 0.5)
	Config.apply(get_tree())


func _process(delta: float) -> void:
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	var fps := ("%d FPS  ·  " % Engine.get_frames_per_second()) if Config.v.mostrar_fps else ""
	info.text = "v%s  ·  %s%s  ·  %s  ·  %.1f m/s  ·  carga: %.1f kg" % [
		ProjectSettings.get_setting("application/config/version", "0.04"), fps,
		"1ª pessoa" if player.first_person else "3ª pessoa", player.state_text(), v, player.equip.weight]
	if Inputs.touch_mode and help.visible:
		help.visible = false
	Inputs.toast_t = maxf(Inputs.toast_t - delta, 0.0)
	if Inputs.toast_t > 0.0:
		hint.text = Inputs.toast
	elif Inputs.use_label != "" and not Inputs.menu_open:
		hint.text = ("[E] " if not Inputs.touch_mode else "") + Inputs.use_label
	else:
		hint.text = ""
