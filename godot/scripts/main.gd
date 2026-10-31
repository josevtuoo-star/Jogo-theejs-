extends Node3D
## Cena de testes: mostra no canto da tela FPS, estado do personagem e a câmera atual.

@onready var player: CharacterBody3D = $Player
@onready var info: Label = $HUD/Info
@onready var help: Label = $HUD/Help


func _enter_tree() -> void:
	Inputs.setup()


func _ready() -> void:
	help.visible = not Inputs.touch_mode


func _process(_delta: float) -> void:
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	info.text = "%d FPS  ·  %s  ·  %s  ·  %.1f m/s  ·  acertos: %d" % [
		Engine.get_frames_per_second(), "1ª pessoa" if player.first_person else "3ª pessoa",
		player.state_text(), v, player.hits]
	if Inputs.touch_mode and help.visible:
		help.visible = false
