extends Node2D

@export var levels : Array[PackedScene]

func _ready() -> void:
	Global.level = 1
	Global.level_change.connect(update_level)

#shortcut to switch levels
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_level"):
		Global.level += 1
	elif event.is_action_pressed("back_level"):
		Global.level -= 1

#redraw level map
func update_level (new_level : int):
	pass
