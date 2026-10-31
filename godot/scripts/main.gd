extends Node3D
## Cena de testes: HUD com FPS e estado do personagem, e o letreiro da bodycam em 1ª pessoa
## (gravando, data e hora do aparelho).

@onready var player: CharacterBody3D = $Player
@onready var info: Label = $HUD/Info
@onready var help: Label = $HUD/Help
@onready var rec: Label = $HUD/Bodycam/Rec
@onready var stamp: Label = $HUD/Bodycam/Stamp
@onready var bodycam: Control = $HUD/Bodycam


func _enter_tree() -> void:
	Inputs.setup()


func _ready() -> void:
	help.visible = not Inputs.touch_mode


func _process(_delta: float) -> void:
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	info.text = "%d FPS  ·  %s  ·  %s  ·  %.1f m/s  ·  acertos: %d" % [
		Engine.get_frames_per_second(), "1ª pessoa (bodycam)" if player.first_person else "3ª pessoa",
		player.state_text(), v, player.hits]
	if Inputs.touch_mode and help.visible:
		help.visible = false
	bodycam.visible = player.cam_blend > 0.6
	if bodycam.visible:
		var t := Time.get_datetime_dict_from_system()
		var blink := int(Time.get_ticks_msec() / 500) % 2 == 0
		rec.text = ("●" if blink else "  ") + " REC"
		stamp.text = "%04d-%02d-%02d  %02d:%02d:%02d\nCAM 01 · UNIDADE 7" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
