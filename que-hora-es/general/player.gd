extends CharacterBody2D

@onready var cat: AnimatedSprite2D = $cat
@export var max_health: int = 5
@export var invincible_time: float = 1.0
@export var knockback_strength: float = 150.0

var health: int
var invincible := false
var dead := false
var knockback := Vector2.ZERO
@export var move_speed: float = 100.0
@export var speed_boost: float = 1.0

@export var art_faces_right: bool = false

@export var sideways_y_offset: float = 10.0
@export var move_x_offset: float = 23.0

@export var afterimage_spacing: float = 5.0
@export var afterimage_lifetime: float = 0.25

@export var dust_color := Color(0.82, 0.72, 0.6)
@export var dust_feet_offset := Vector2(0, 10)
@export var dust_forward_nudge: float = -8.0
@export var dust_spacing: float = 7.0
@export var dust_per_puff: int = 3
@export var dust_lifetime: float = 0.4

var facing: Vector2 = Vector2.DOWN
var base_cat_position: Vector2
var speeding := false
var last_image_position: Vector2
var prev_physics_pos: Vector2
var dust_distance := 0.0
var dust_texture: ImageTexture


func _ready() -> void:
	SignalBus.revert.connect(revert_position)
	SignalBus.dialate_time.connect(start_speed_effect)

	base_cat_position = cat.position
	prev_physics_pos = global_position
	_prepare_dust()
	_play_animation(false)
	health = max_health
	SignalBus.player_health_changed.emit(health, max_health)
	

func take_damage(amount: int, from_position: Vector2 = Vector2.ZERO) -> void:
	if invincible or dead:
		return

	health -= amount
	SignalBus.player_health_changed.emit(health, max_health)

	if health <= 0:
		_die()
		return

	# knockback away from the attacker
	knockback = (global_position - from_position).normalized() * knockback_strength

	# invincibility + flicker
	invincible = true
	var tween := create_tween()
	tween.set_loops(int(invincible_time / 0.2))
	tween.tween_property(cat, "modulate:a", 0.3, 0.1)
	tween.tween_property(cat, "modulate:a", 1.0, 0.1)
	await get_tree().create_timer(invincible_time).timeout
	cat.modulate.a = 1.0
	invincible = false


func _die() -> void:
	dead = true
	velocity = Vector2.ZERO
	# swap for a game over screen later
	get_tree().call_deferred("reload_current_scene")
	
func _snap_cardinal(v: Vector2) -> Vector2:
	var ax: float = absf(v.x)
	var ay: float = absf(v.y)

	if ax > ay:
		return Vector2(signf(v.x), 0.0)
	elif ay > ax:
		return Vector2(0.0, signf(v.y))

	return facing


func _play_animation(moving: bool) -> void:
	var anim: StringName

	if facing.x != 0.0:
		anim = &"right" if moving else &"idle-right"
		var facing_left: bool = facing.x < 0.0
		cat.flip_h = (facing_left == art_faces_right)
		var x_shift: float = move_x_offset if facing_left else 0.0
		cat.position = base_cat_position + Vector2(x_shift, sideways_y_offset)
	elif facing.y < 0.0:
		anim = &"up" if moving else &"idle-up"
		cat.flip_h = false
		var x_shift: float = move_x_offset
		cat.position = base_cat_position + Vector2(x_shift, 0.0)
	else:
		anim = &"down" if moving else &"idle-down"
		cat.flip_h = false
		var x_shift: float = move_x_offset
		cat.position = base_cat_position + Vector2(x_shift, 0.0)

	if cat.animation != anim:
		cat.play(anim)
	elif not cat.is_playing():
		cat.play(anim)


func _update_animation(input_direction: Vector2) -> void:
	var moving: bool = input_direction.length_squared() > 0.001

	if moving:
		facing = _snap_cardinal(input_direction)

	_play_animation(moving)


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


func _physics_process(delta: float) -> void:
	if dead:
		return

	prev_physics_pos = global_position

	var input_direction := Vector2(
		Input.get_action_strength("right")
			- Input.get_action_strength("left"),
		Input.get_action_strength("down")
			- Input.get_action_strength("up")
	).normalized()

	_update_animation(input_direction)

	var speed: float = move_speed

	if speeding:
		speed *= speed_boost

	velocity = input_direction * speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 600.0 * delta)
	move_and_slide()

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
	var image := AnimatedSprite2D.new()

	image.top_level = true
	image.physics_interpolation_mode = (
		Node.PHYSICS_INTERPOLATION_MODE_OFF
	)

	image.sprite_frames = cat.sprite_frames
	image.animation = cat.animation
	image.frame = cat.frame
	image.pause()

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

	_play_animation(false)
