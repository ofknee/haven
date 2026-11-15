extends Area2D

@export var bob_height: float = 5.0
@export var bob_speed: float = 2.0

@onready var collect_sound: AudioStreamPlayer2D = $AudioStreamPlayer2D

var start_y: float
var time: float = 0.0
var collected: bool = false


func _ready() -> void:
	start_y = position.y


func _process(delta: float) -> void:
	time += delta
	position.y = start_y + sin(time * bob_speed) * bob_height


func _on_body_entered(body: Node2D) -> void:
	if body.name == "Player" and not collected:
		collect_sound.play()

		collected = true
		Global.wood += 1

		hide()
		set_deferred("monitoring", false)


		await collect_sound.finished
		queue_free()
