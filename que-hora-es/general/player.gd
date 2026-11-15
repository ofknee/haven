extends CharacterBody2D

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var cat: Sprite2D = $cat

@export var move_speed: float = 100.0
@export var speed_boost: float = 1.0          # try 1.8 while speeding
@export var afterimage_spacing: float = 5.0
@export var afterimage_lifetime: float = 0.25
@export var dust_color := Color(0.82, 0.72, 0.6)   # warm cream-tan
@export var dust_feet_offset := Vector2(0, 10)
@export var dust_forward_nudge: float = -8.0   # pushes the dust toward the cat's front
@export var dust_spacing: float = 7.0         # pixels walked between puffs
@export var dust_per_puff: int = 3            # little dots per step
@export var dust_lifetime: float = 0.4

var speeding := false
var last_image_position: Vector2
var prev_physics_pos: Vector2
var dust_distance := 0.0
var dust_texture: ImageTexture


func _ready() -> void:
	animation_tree.active = true
	SignalBus.revert.connect(revert_position)
	SignalBus.dialate_time.connect(start_speed_effect)
	prev_physics_pos = global_position
	_prepare_dust()


# where the cat is actually drawn on screen right now
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


func _physics_process(delta: float) -> void:
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

	# a puff of dust every few pixels walked
	if velocity.length() > 1.0:
		dust_distance += velocity.length() * delta
		if dust_distance >= dust_spacing:
			dust_distance = 0.0
			_spawn_dust_puff(velocity.normalized())
	else:
		dust_distance = dust_spacing * 0.5   # first step after stopping puffs quickly


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


func _prepare_dust() -> void:
	# 4x4 pixel circle (clipped corners), built once and shared by every dot
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for corner in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]:
		img.set_pixelv(corner, Color(1, 1, 1, 0))
	dust_texture = ImageTexture.create_from_image(img)


func _spawn_dust_puff(dir: Vector2) -> void:
	var base_pos: Vector2 = global_position + dust_feet_offset + dir * dust_forward_nudge

	for i in dust_per_puff:
		var dot := Sprite2D.new()
		dot.texture = dust_texture
		dot.top_level = true
		dot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		dot.z_as_relative = false
		dot.z_index = 0                       # above the ground, below the cat (z 1)
		dot.modulate = Color(dust_color, 0.75)

		add_child(dot)
		move_child(dot, 0)
		dot.global_position = base_pos + Vector2(randf_range(-3.0, 3.0), randf_range(-1.5, 1.5))

		# drift backward and up a little, fading as it goes
		var drift: Vector2 = -dir * randf_range(2.0, 7.0) + Vector2(0, randf_range(-6.0, -2.0))
		var life: float = dust_lifetime * randf_range(0.7, 1.1)

		var tween := dot.create_tween()
		tween.set_parallel(true)
		tween.tween_property(dot, "global_position", dot.global_position + drift, life)
		tween.tween_property(dot, "modulate:a", 0.0, life)
		tween.chain().tween_callback(dot.queue_free)


func revert_position(last_position: Vector2) -> void:
	if not speeding:
		return
	speeding = false
	global_position = last_position
	prev_physics_pos = last_position       # avoids a one-frame streak after the snap
	velocity = Vector2.ZERO
