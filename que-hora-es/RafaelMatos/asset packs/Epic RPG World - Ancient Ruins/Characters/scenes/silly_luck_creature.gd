extends CharacterBody2D

@export var speed: float = 45.0
@export var detection_range: float = 200.0
@export var hit_radius: float = 14.0
@export var attack_damage: int = 1
@export var attack_cooldown: float = 1.0
@export var art_faces_right: bool = true
@export var slow_factor: float = 0.2
@export var sprite_offset := Vector2(-9, -10)

@onready var sprite: AnimatedSprite2D = $SillyLuckCreature

var player: Node2D
var touch_area: Area2D
var cooldown_left := 0.0
var time_scale := 1.0


func _ready() -> void:
	sprite.centered = true
	sprite.offset = sprite_offset
	_build_touch_area()
	_find_player()
	SignalBus.dialate_time.connect(_on_time_slowed)
	SignalBus.time_finished.connect(_on_time_restored)


func _build_touch_area() -> void:
	touch_area = Area2D.new()
	touch_area.collision_layer = 0
	touch_area.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = hit_radius
	shape.shape = circle
	shape.position = Vector2(0, -3)
	touch_area.add_child(shape)
	add_child(touch_area)


func _find_player() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		player = get_tree().current_scene.find_child("Player", true, false) as Node2D
	if player is CollisionObject2D:
		touch_area.collision_mask = player.collision_layer
		collision_mask &= ~player.collision_layer


func _on_time_slowed() -> void:
	time_scale = slow_factor
	sprite.speed_scale = slow_factor


func _on_time_restored() -> void:
	time_scale = 1.0
	sprite.speed_scale = 1.0


func _physics_process(delta: float) -> void:
	if player == null:
		_find_player()
		return

	cooldown_left = max(cooldown_left - delta * time_scale, 0.0)

	var to_player := player.global_position - global_position

	if to_player.length() <= detection_range:
		var direction := to_player.normalized()
		velocity = direction * speed * time_scale
		if direction.x != 0.0:
			var facing_left := direction.x < 0.0
			var mirror := (facing_left == art_faces_right)
			sprite.scale.x = -1.0 if mirror else 1.0
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	if cooldown_left <= 0.0 and touch_area.overlaps_body(player) and player.has_method("take_damage"):
		cooldown_left = attack_cooldown
		player.take_damage(attack_damage, global_position)

	if get_real_velocity().length() > 5.0:
		_play("run")
	else:
		_play("idle")


func _play(anim: StringName) -> void:
	if sprite.animation != anim:
		sprite.play(anim)
