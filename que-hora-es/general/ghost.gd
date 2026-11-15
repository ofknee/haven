extends Node2D

@export var player_sprite: Sprite2D
@export var playback_speed: float = 0.5
@onready var ghost_sprite: Sprite2D = $Sprite2D

var history: Array[Dictionary] = []
var record_time: float = 0.0
var playback_time: float = 0.0


func _ready() -> void:
	ghost_sprite.modulate = Color(1, 1, 1, 0.3)
	record_frame()

func _process(delta: float) -> void:
	record_time += delta
	record_frame()
	playback_time += delta * playback_speed

	#remove expired frames
	while history.size() > 1 and history[1]["time"] <= playback_time:
		history.pop_front()

	var frame: Dictionary = history[0]
	var ghost_transform: Transform2D = frame["transform"]

	#move between positions
	if history.size() > 1:
		var next_frame: Dictionary = history[1]
		var frame_duration: float = next_frame["time"] - frame["time"]

		if frame_duration > 0.0:
			var weight := clampf(
				(playback_time - frame["time"]) / frame_duration,
				0.0,
				1.0
			)
			ghost_transform = ghost_transform.interpolate_with(
				next_frame["transform"],
				weight
			)

	ghost_sprite.texture = frame["texture"]
	ghost_sprite.hframes = frame["hframes"]
	ghost_sprite.vframes = frame["vframes"]
	ghost_sprite.frame = frame["frame"]
	ghost_sprite.flip_h = frame["flip_h"]
	ghost_sprite.flip_v = frame["flip_v"]
	ghost_sprite.offset = frame["offset"]
	ghost_sprite.centered = frame["centered"]
	ghost_sprite.global_transform = ghost_transform


func record_frame() -> void:
	history.append({
		"time": record_time,
		"transform": player_sprite.global_transform,
		"texture": player_sprite.texture,
		"hframes": player_sprite.hframes,
		"vframes": player_sprite.vframes,
		"frame": player_sprite.frame,
		"flip_h": player_sprite.flip_h,
		"flip_v": player_sprite.flip_v,
		"offset": player_sprite.offset,
		"centered": player_sprite.centered
	})
