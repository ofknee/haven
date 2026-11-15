extends CanvasLayer

@export var hits_to_trigger: int = 3
@export var pause_game: bool = true
@export var wood_goal: int = 25

@onready var wood_label: Label = $Label

var hurt_count := 0


func _ready() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS
	SignalBus.player_hurt.connect(_on_player_hurt)


func _on_player_hurt() -> void:
	hurt_count += 1
	if hurt_count >= hits_to_trigger:
		wood_label.text = "%d / %d\nwood found" % [Global.wood, wood_goal]
		show()
		if pause_game:
			get_tree().paused = true
