extends MarginContainer

@export var text_list : Array[String]

@onready var TextNode := $NinePatchRect/MarginContainer/RichTextLabel
@onready var text = TextNode.text

var iteration : int = 0

func _ready() -> void:
	text = text_list[iteration]
	show()

func _on_exit_button_pressed() -> void:
	next()
	
func next() -> void:
	iteration += 1
	text = text_list[iteration]
	if iteration >= text_list.size():
		print("hiding!")
		hide()
	
