extends CharacterBody2D

## Movement speed in pixels per second.
@export_range(0.0, 1000.0, 1.0) var move_speed: float = 180.0


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * move_speed
	move_and_slide()
