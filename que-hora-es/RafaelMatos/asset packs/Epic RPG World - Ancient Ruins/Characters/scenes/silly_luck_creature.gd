extends CharacterBody2D

@export var speed: float = 45.0
@export var detection_range: float = 300.0
@export var attack_range: float = 30.0
@export var attack_damage: int = 1
@export var attack_cooldown: float = 1.0
@export var art_faces_right: bool = true

@onready var sprite: AnimatedSprite2D = $SillyLuckCreature

var player: Node2D
var cooldown_left := 0.0


func _ready() -> void:
	player = %Player


func _physics_process(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node2D
		return

	cooldown_left = max(cooldown_left - delta, 0.0)

	var to_player := player.global_position - global_position
	var distance := to_player.length()

	if distance <= attack_range:
		velocity = Vector2.ZERO
		_play("idle")
		if cooldown_left <= 0.0 and player.has_method("take_damage"):
			cooldown_left = attack_cooldown
			player.take_damage(attack_damage, global_position)
	elif distance <= detection_range:
		var direction := to_player.normalized()
		velocity = direction * speed
		_play("run")
		if direction.x != 0.0:
			var facing_left := direction.x < 0.0
			sprite.flip_h = (facing_left == art_faces_right)
	else:
		velocity = Vector2.ZERO
		_play("idle")

	move_and_slide()


func _play(anim: StringName) -> void:
	if sprite.animation != anim:
		sprite.play(anim)
