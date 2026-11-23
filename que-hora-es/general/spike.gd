extends Area2D

var spikes_up : bool = false
@onready var anim = $AnimatedSprite2D
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
	anim.frame = 0
func activate() -> void:
	if spikes_up:
		return
	spikes_up = true
	anim.play()
	#wave effect
	await get_tree().create_timer(0.2).timeout
	for spike in get_tree().get_nodes_in_group("spikes"):
		if spike != self and not spike.spikes_up:
			if global_position.distance_to(spike.global_position) <= 36.0:
				spike.activate()

func _on_body_entered(body: Node2D) -> void:
	if body.name == "Player":
		activate()
