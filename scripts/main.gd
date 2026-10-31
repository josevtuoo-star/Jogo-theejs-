extends Node3D
## Cena principal: HUD com versão, FPS, câmera e estado do personagem, suprimentos e a dica
## do botão USAR.

@onready var player: CharacterBody3D = $Player
@onready var info: Label = $HUD/Info
@onready var help: Label = $HUD/Help
@onready var hint: Label = $HUD/Dica


func _enter_tree() -> void:
	Inputs.setup()


func _ready() -> void:
	help.visible = not Inputs.touch_mode


func _process(_delta: float) -> void:
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	info.text = "v%s  ·  %d FPS  ·  %s  ·  %s  ·  %.1f m/s  ·  suprimentos: %d" % [
		ProjectSettings.get_setting("application/config/version", "0.01"), Engine.get_frames_per_second(),
		"1ª pessoa" if player.first_person else "3ª pessoa", player.state_text(), v, player.supplies]
	if Inputs.touch_mode and help.visible:
		help.visible = false
	hint.text = ("[E] " if not Inputs.touch_mode else "") + Inputs.use_label if Inputs.use_label != "" else ""
