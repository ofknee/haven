extends CharacterBody2D


@onready var animation_tree: AnimationTree = $AnimationTree
@export var move_speed : float = 100

func _ready() -> void:
	animation_tree.active = true

func _physics_process(_delta: float) -> void:
	var input_direction = Vector2(
		Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("down") - Input.get_action_strength("up")
	)
	
	if input_direction != Vector2.ZERO:
		animation_tree.set("parameters/blend_position", input_direction)
	velocity = input_direction * move_speed
	
	move_and_slide()
