extends CharacterBody2D

@onready var animation_tree: AnimationTree = $AnimationTree
@export var move_speed: float = 100.0

var saved_position: Vector2
var position_saved := false


func _ready() -> void:
	animation_tree.active = true
	SignalBus.revert.connect(revert_position)


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("timeo"):
		saved_position = global_position
		position_saved = true

	var input_direction := Vector2(
		Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("down") - Input.get_action_strength("up")
	)

	if input_direction != Vector2.ZERO:
		animation_tree.set("parameters/blend_position", input_direction)

	velocity = input_direction * move_speed
	move_and_slide()


func revert_position() -> void:
	if position_saved:
		global_position = saved_position
		velocity = Vector2.ZERO
		position_saved = false
