extends CharacterBody2D

@export var speed: float = 40.0              # lower = slower chase
@export var detection_range: float = 300.0   # how far away it notices the player
@export var stop_distance: float = 20.0      # stops moving when this close
@export var attack_range: float = 28.0
@export var attack_cooldown: float = 1.2
@export var max_health: int = 3

@onready var sprite: AnimatedSprite2D = $Moose

var player: Node2D
var health: int
var is_attacking := false
var is_hurt := false
var is_dead := false
var cooldown_left := 0.0


func _ready() -> void:
	health = max_health
	player = %Player
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	cooldown_left = max(cooldown_left - delta, 0.0)

	# Don't move while attacking or being hurt
	if is_attacking or is_hurt or player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_player := player.global_position - global_position
	var distance := to_player.length()

	if distance <= attack_range and cooldown_left <= 0.0:
		_start_attack()
	elif distance <= detection_range and distance > stop_distance:
		var direction := to_player.normalized()
		velocity = direction * speed
		_face(direction.x)
		_play("run")
	else:
		velocity = Vector2.ZERO
		_play("idle")

	move_and_slide()


func _face(dir_x: float) -> void:
	# Assumes your sprite art faces RIGHT by default.
	# If it faces left, swap to: sprite.flip_h = dir_x > 0
	if dir_x != 0:
		sprite.flip_h = dir_x < 0


func _play(anim: String) -> void:
	if sprite.animation != anim:
		sprite.play(anim)


func _start_attack() -> void:
	is_attacking = true
	cooldown_left = attack_cooldown
	velocity = Vector2.ZERO
	_face(player.global_position.x - global_position.x)
	sprite.play("attack")


func take_damage(amount: int = 1) -> void:
	if is_dead:
		return
	health -= amount
	if health <= 0:
		_die()
	else:
		is_attacking = false
		is_hurt = true
		sprite.play("hurt")


func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	sprite.play("death")


func _on_animation_finished() -> void:
	match sprite.animation:
		"attack":
			is_attacking = false
		"hurt":
			is_hurt = false
		"death":
			queue_free()
