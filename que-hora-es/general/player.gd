extends CharacterBody2D

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var cat: Sprite2D = $cat

@export var move_speed: float = 100.0
@export var speed_boost: float = 1.0          
@export var afterimage_spacing: float = 5
@export var afterimage_lifetime: float = 0.3

var speeding := false
var last_image_position: Vector2


func _ready() -> void:
	animation_tree.active = true
	SignalBus.revert.connect(revert_position)
	SignalBus.dialate_time.connect(start_speed_effect)


func start_speed_effect() -> void:
	speeding = true
	last_image_position = cat.global_position


func _physics_process(_delta: float) -> void:
	var input_direction := Vector2(
		Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("down") - Input.get_action_strength("up")
	)

	if input_direction != Vector2.ZERO:
		animation_tree.set("parameters/blend_position", input_direction)

	var speed := move_speed * (speed_boost if speeding else 1.0)
	velocity = input_direction * speed
	move_and_slide()

	# spawn afterimages here, in the physics tick
	if speeding and cat.global_position.distance_to(last_image_position) >= afterimage_spacing:
		create_afterimage()
		last_image_position = cat.global_position


func create_afterimage() -> void:
	var image := Sprite2D.new()
	image.top_level = true
	image.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # key fix

	image.texture = cat.texture
	image.hframes = cat.hframes
	image.vframes = cat.vframes
	image.frame = cat.frame
	image.flip_h = cat.flip_h
	image.flip_v = cat.flip_v
	image.offset = cat.offset
	image.centered = cat.centered
	image.modulate = Color(0.75, 0.85, 1.0, 0.5)

	add_child(image)
	move_child(image, 0)                      # draw behind the cat
	image.global_transform = cat.global_transform

	var tween := image.create_tween()
	tween.tween_property(image, "modulate:a", 0.0, afterimage_lifetime)
	tween.tween_callback(image.queue_free)


func revert_position(last_position: Vector2) -> void:
	if not speeding:
		return
	speeding = false
	global_position = last_position
	velocity = Vector2.ZERO
