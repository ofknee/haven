extends TextureProgressBar

@export var duration: float = 2.0
@onready var timer: Timer = $Timer

var counting := false

func _ready() -> void:
	min_value = 0
	max_value = 100
	timer.one_shot = true
	timer.timeout.connect(finish)
	hide()
	SignalBus.revert.emit()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("timeo"):
		counting = true
		value = 100
		show()
		timer.start(duration)

	if counting:
		value = (timer.time_left / duration) * 100.0

		if Input.is_action_just_released("timeo"):
			finish()


func finish() -> void:
	if not counting:
		return

	counting = false
	timer.stop()
	hide()
	SignalBus.revert.emit()
