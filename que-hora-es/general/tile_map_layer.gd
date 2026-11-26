extends Node2D

@export var levels : Array[PackedScene]
var instances : Array[Node] = []
var current : Node

func _ready() -> void:
	# set levels up as nodes
	for scene in levels:
			instances.append(scene.instantiate())
	#load starting level
	Global.level_change.connect(update_level)
	update_level(Global.level)   


#shortcut to switch levels
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_level"):
		Global.level = clampi(Global.level + 1, 0, levels.size() - 1)
	elif event.is_action_pressed("back_level"):
		Global.level = clampi(Global.level - 1, 0, levels.size() - 1)
 # clamps from going out of bounds!!

#redraw level map
func update_level (new_level  : int):
	var next = instances[new_level]
	if next == current:
		return   # out of bounds levels
	if current:
		remove_child(current)
	current = next
	add_child(current)
