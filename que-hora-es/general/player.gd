extends CharacterBody2D

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var cat: Sprite2D = $cat

@export var move_speed: float = 100.0
@export var speed_boost: float = 1.0          # try 1.8 while speeding
@export var afterimage_spacing: float = 5.0
@export var afterimage_lifetime: float = 0.25
@export var dust_color := Color(0.82, 0.72, 0.6)   # warm cream-tan
@export var dust_feet_offset := Vector2(0, 10)

var speeding := false
var last_image_position: Vector2
var prev_physics_pos: Vector2
var dust: CPUParticles2D


func _ready() -> void:
	animation_tree.active = true
	SignalBus.revert.connect(revert_position)
	SignalBus.dialate_time.connect(start_speed_effect)
	prev_physics_pos = global_position
	_setup_dust()


# where the cat is drawn on screen rn
func _get_visual_transform() -> Transform2D:
	var xform: Transform2D = cat.global_transform
	var visual_pos: Vector2 = prev_physics_pos.lerp(
		global_position, Engine.get_physics_interpolation_fraction()
	)
	xform.origin += visual_pos - global_position
	return xform


func start_speed_effect() -> void:
	speeding = true
	last_image_position = _get_visual_transform().origin


func _physics_process(_delta: float) -> void:
	prev_physics_pos = global_position

	var input_direction := Vector2(
		Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("down") - Input.get_action_strength("up")
	)

	if input_direction != Vector2.ZERO:
		animation_tree.set("parameters/blend_position", input_direction)

	var speed := move_speed * (speed_boost if speeding else 1.0)
	velocity = input_direction * speed
	move_and_slide()
	_update_dust()


func _process(_delta: float) -> void:
	if not speeding:
		return
	var current: Transform2D = _get_visual_transform()
	if current.origin.distance_to(last_image_position) >= afterimage_spacing:
		create_afterimage(current)
		last_image_position = current.origin


func create_afterimage(xform: Transform2D) -> void:
	var image := Sprite2D.new()
	image.top_level = true
	image.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

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
	move_child(image, 0)
	image.global_transform = xform

	var tween := image.create_tween()
	tween.tween_property(image, "modulate:a", 0.0, afterimage_lifetime)
	tween.tween_callback(image.queue_free)


func _setup_dust() -> void:
	# 4x4 pixel circle (clipped corners)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for corner in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]:
		img.set_pixelv(corner, Color(1, 1, 1, 0))

	dust = CPUParticles2D.new()
	dust.texture = ImageTexture.create_from_image(img)
	dust.position = dust_feet_offset
	dust.z_index = -1                      # beats y-sort so it draws under the cat
	dust.local_coords = false
	dust.emitting = false

	# denser, shorter-lived = tight little puffs
	dust.amount = 14
	dust.lifetime = 0.35
	dust.explosiveness = 0.0
	dust.randomness = 0.7

	# wide, flat area at the paws
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(4, 1.5)
	dust.spread = 40.0
	dust.gravity = Vector2(0, -10)         # tiny upward float
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 10.0
	dust.damping_min = 10.0
	dust.damping_max = 18.0
	dust.scale_amount_min = 1.0            # whole numbers keep it crisp
	dust.scale_amount_max = 1.0

	# quick soft fade in, then fade out
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([
		Color(dust_color, 0.0),
		Color(dust_color, 0.75),
		Color(dust_color, 0.0)
	])
	dust.color_ramp = fade

	add_child(dust)


func _update_dust() -> void:
	var moving := velocity.length() > 1.0
	dust.emitting = moving
	if moving:
		dust.direction = -velocity.normalized()


func revert_position(last_position: Vector2) -> void:
	if not speeding:
		return
	speeding = false
	global_position = last_position
	prev_physics_pos = last_position       # avoids a one-frame streak after the snap
	velocity = Vector2.ZERO
