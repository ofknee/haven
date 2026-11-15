extends CharacterBody2D

@export var speed: float = 45.0
@export var detection_range: float = 200.0
@export var stop_distance: float = 24.0
@export var attack_range: float = 40.0
@export var attack_damage: int = 1
@export var attack_cooldown: float = 1.0
@export var art_faces_right: bool = true
@export var slow_factor: float = 0.3

@onready var sprite: AnimatedSprite2D = $SillyLuckCreature

var player: Node2D
var cooldown_left := 0.0
var time_scale := 1.0


func _ready() -> void:
	print("CREATURE SCRIPT RUNNING")
	_find_player()
	SignalBus.dialate_time.connect(_on_time_slowed)
	SignalBus.time_finished.connect(_on_time_restored)


func _find_player() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		player = get_tree().current_scene.find_child("Player", true, false) as Node2D
	print("player lookup result: ", player)


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
	var distance := to_player.length()

	if distance <= detection_range and distance > stop_distance:
		var direction := to_player.normalized()
		velocity = direction * speed * time_scale
		if direction.x != 0.0:
			var facing_left := direction.x < 0.0
			sprite.flip_h = (facing_left == art_faces_right)
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	if distance <= attack_range and cooldown_left <= 0.0 and player.has_method("take_damage"):
		cooldown_left = attack_cooldown
		player.take_damage(attack_damage, global_position)

	if get_real_velocity().length() > 5.0:
		_play("run")
	else:
		_play("idle")


func _play(anim: StringName) -> void:
	if sprite.animation != anim:
		sprite.play(anim)
