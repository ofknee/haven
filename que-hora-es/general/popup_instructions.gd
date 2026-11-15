extends MarginContainer

@export var text_list : Array[String]
@onready var text_node : RichTextLabel = $NinePatchRect/MarginContainer/RichTextLabel

var iteration : int = 0

func _ready() -> void:
	if text_list.is_empty():
		hide()
		return
	text_node.text = text_list[iteration]
	show()

func _on_exit_button_pressed() -> void:
	next()

func next() -> void:
	iteration += 1
	if iteration >= text_list.size():
		hide()
		return
	text_node.text = text_list[iteration]
