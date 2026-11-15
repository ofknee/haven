extends CharacterBody2D

const STATE_IDLE := &"Idle"
const STATE_WALK := &"Walk"

const PARAM_IDLE := "parameters/Idle/blend_position"
const PARAM_WALK := "parameters/Walk/blend_position"

@onready var cat: Sprite2D = $cat
@onready var animation_tree: AnimationTree = $AnimationTree

var playback: AnimationNodeStateMachinePlayback
var current_state: StringName = STATE_IDLE
var last_direction: Vector2 = Vector2.DOWN

@export var move_speed: float = 100.0
@export var speed_boost: float = 1.0

@export var afterimage_spacing: float = 5.0
@export var afterimage_lifetime: float = 0.25

@export var dust_color := Color(0.82, 0.72, 0.6)
@export var dust_feet_offset := Vector2(0, 10)
@export var dust_forward_nudge: float = -8.0
@export var dust_spacing: float = 7.0
@export var dust_per_puff: int = 3
@export var dust_lifetime: float = 0.4

var speeding := false
var last_image_position: Vector2
var prev_physics_pos: Vector2
var dust_distance := 0.0
var dust_texture: ImageTexture


func _ready() -> void:
	SignalBus.revert.connect(revert_position)
	SignalBus.dialate_time.connect(start_speed_effect)

	prev_physics_pos = global_position
	_prepare_dust()

	animation_tree.active = true
	playback = animation_tree.get(
		"parameters/playback"
	) as AnimationNodeStateMachinePlayback

	# Initialize both blend spaces with a cardinal direction
	animation_tree.set(PARAM_IDLE, last_direction)
	animation_tree.set(PARAM_WALK, last_direction)

	current_state = STATE_IDLE
	playback.start(STATE_IDLE)


# Snaps any direction to one of the 4 cardinal directions so the
# BlendSpace2D never sits between animations (which causes frame glitching).
func _snap_cardinal(v: Vector2) -> Vector2:
	var ax: float = absf(v.x)
	var ay: float = absf(v.y)

	if ax > ay:
		return Vector2(signf(v.x), 0.0)
	elif ay > ax:
		return Vector2(0.0, signf(v.y))

	# Exact diagonal: keep the current facing to avoid flip-flopping
	return last_direction


func _update_animation(input_direction: Vector2) -> void:
	if playback == null:
		return

	var target: StringName = STATE_IDLE

	if input_direction.length_squared() > 0.001:
		# Character is moving
		last_direction = _snap_cardinal(input_direction)
		target = STATE_WALK

		animation_tree.set(PARAM_WALK, last_direction)
	else:
		# Character stopped
		target = STATE_IDLE

		animation_tree.set(PARAM_IDLE, last_direction)

	# Only switch when the desired state changes
	if current_state != target:
		current_state = target
		playback.travel(current_state)


func _get_visual_transform() -> Transform2D:
	var xform: Transform2D = cat.global_transform

	var visual_pos: Vector2 = prev_physics_pos.lerp(
		global_position,
		Engine.get_physics_interpolation_fraction()
	)

	xform.origin += visual_pos - global_position
	return xform


func start_speed_effect() -> void:
	speeding = true
	last_image_position = _get_visual_transform().origin


func _physics_process(_delta: float) -> void:
	prev_physics_pos = global_position

	# Input direction
	var input_direction := Vector2(
		Input.get_action_strength("right")
			- Input.get_action_strength("left"),
		Input.get_action_strength("down")
			- Input.get_action_strength("up")
	).normalized()

	# Update animation
	_update_animation(input_direction)

	# Movement
	var speed: float = move_speed

	if speeding:
		speed *= speed_boost

	velocity = input_direction * speed
	move_and_slide()

	# Dust particles based on actual distance moved
	var distance_moved: float = global_position.distance_to(
		prev_physics_pos
	)

	if distance_moved > 0.01:
		dust_distance += distance_moved

		if dust_distance >= dust_spacing:
			dust_distance = 0.0
			_spawn_dust_puff(input_direction)
	else:
		dust_distance = dust_spacing * 0.5


func _process(_delta: float) -> void:
	if not speeding:
		return

	var current: Transform2D = _get_visual_transform()

	if current.origin.distance_to(
		last_image_position
	) >= afterimage_spacing:
		create_afterimage(current)
		last_image_position = current.origin


func create_afterimage(xform: Transform2D) -> void:
	var image := Sprite2D.new()

	image.top_level = true
	image.physics_interpolation_mode = (
		Node.PHYSICS_INTERPOLATION_MODE_OFF
	)

	image.texture = cat.texture
	image.hframes = cat.hframes
	image.vframes = cat.vframes
	image.frame = cat.frame

	image.flip_h = cat.flip_h
	image.flip_v = cat.flip_v

	image.offset = cat.offset
	image.centered = cat.centered

	image.modulate = Color(0.75, 0.85, 1.0, 0.4)

	add_child(image)
	move_child(image, 0)

	image.global_transform = xform

	var tween := image.create_tween()
	tween.tween_property(
		image,
		"modulate:a",
		0.0,
		afterimage_lifetime
	)
	tween.tween_callback(image.queue_free)


func _prepare_dust() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)

	img.fill(Color.WHITE)

	for corner in [
		Vector2i(0, 0),
		Vector2i(3, 0),
		Vector2i(0, 3),
		Vector2i(3, 3)
	]:
		img.set_pixelv(corner, Color(1, 1, 1, 0))

	dust_texture = ImageTexture.create_from_image(img)


func _spawn_dust_puff(dir: Vector2) -> void:
	var base_pos: Vector2 = (
		global_position
		+ dust_feet_offset
		+ dir * dust_forward_nudge
	)

	for i in range(dust_per_puff):
		var dot := Sprite2D.new()

		dot.texture = dust_texture
		dot.top_level = true

		dot.physics_interpolation_mode = (
			Node.PHYSICS_INTERPOLATION_MODE_OFF
		)

		dot.z_as_relative = false
		dot.z_index = 0

		dot.modulate = Color(dust_color, 0.75)

		add_child(dot)
		move_child(dot, 0)

		dot.global_position = base_pos + Vector2(
			randf_range(-3.0, 3.0),
			randf_range(-1.5, 1.5)
		)

		var drift: Vector2 = (
			-dir * randf_range(2.0, 7.0)
			+ Vector2(0, randf_range(-6.0, -2.0))
		)

		var life: float = dust_lifetime * randf_range(0.7, 1.1)

		var tween := dot.create_tween()

		tween.set_parallel(true)

		tween.tween_property(
			dot,
			"global_position",
			dot.global_position + drift,
			life
		)

		tween.tween_property(
			dot,
			"modulate:a",
			0.0,
			life
		)

		tween.chain().tween_callback(dot.queue_free)


func revert_position(last_position: Vector2) -> void:
	if not speeding:
		return

	speeding = false

	global_position = last_position
	prev_physics_pos = last_position
	velocity = Vector2.ZERO

	dust_distance = 0.0
	last_image_position = _get_visual_transform().origin

	# Return to idle after reverting
	current_state = STATE_IDLE

	if playback != null:
		animation_tree.set(PARAM_IDLE, last_direction)
		playback.travel(STATE_IDLE)
