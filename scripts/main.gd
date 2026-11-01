extends Node3D
## Cena principal: prepara controles e áudio; HUD com versão, FPS, câmera, estado do
## personagem, peso carregado, a dica do botão USAR e mensagens curtas.

@onready var player: CharacterBody3D = $Player
@onready var info: Label = $HUD/Info
@onready var help: Label = $HUD/Help
@onready var hint: Label = $HUD/Dica


func _enter_tree() -> void:
	Inputs.setup()
	Audio.setup()
	Sfx.warmup() # sons gerados aos poucos nos primeiros segundos


func _ready() -> void:
	help.visible = not Inputs.touch_mode


func _process(delta: float) -> void:
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	info.text = "v%s  ·  %d FPS  ·  %s  ·  %s  ·  %.1f m/s  ·  carga: %.1f kg" % [
		ProjectSettings.get_setting("application/config/version", "0.03"), Engine.get_frames_per_second(),
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
