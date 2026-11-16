extends Area2D

@export var bob_height: float = 5.0
@export var bob_speed: float = 2.0
@export var magnet_range: float = 60.0
@export var magnet_speed: float = 140.0
@export var pop_scale: float = 1.5
@export var show_plus_one: bool = true
@export var particle_color := Color(0.82, 0.6, 0.35)
@export var plus_one_font: Font

@onready var collect_sound: AudioStreamPlayer2D = $AudioStreamPlayer2D

var start_y: float
var time: float = 0.0
var collected: bool = false
var base_scale: Vector2
var player: Node2D


func _ready() -> void:
	start_y = position.y
	base_scale = scale
	time = randf() * TAU
	player = get_tree().get_first_node_in_group("player") as Node2D


func _process(delta: float) -> void:
	if collected:
		return

	if player != null and magnet_range > 0.0:
		var dist := global_position.distance_to(player.global_position)
		if dist < magnet_range:
			var pull := magnet_speed * (1.0 + (1.0 - dist / magnet_range) * 2.0)
			global_position = global_position.move_toward(player.global_position, pull * delta)
			return

	time += delta
	position.y = start_y + sin(time * bob_speed) * bob_height


func _on_body_entered(body: Node2D) -> void:
	if body.name != "Player" or collected:
		return

	collected = true
	Global.wood += 1
	set_deferred("monitoring", false)

	collect_sound.pitch_scale = randf_range(0.9, 1.2)
	collect_sound.play()

	_spawn_particles()
	if show_plus_one:
		_spawn_plus_one()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", base_scale * pop_scale, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position:y", position.y - 14.0, 0.2)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)

	await tween.finished
	if collect_sound.playing:
		await collect_sound.finished
	queue_free()


func _spawn_particles() -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 90.0
	p.gravity = Vector2(0, 200)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = particle_color
	p.z_index = 10
	get_parent().add_child(p)
	p.global_position = global_position
	p.emitting = true
	p.finished.connect(p.queue_free)


func _spawn_plus_one() -> void:
	var label := Label.new()
	label.text = "+1"
	label.z_index = 20
	label.modulate = Color(1.0, 0.95, 0.7)
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.add_theme_font_override("font", plus_one_font)
	label.add_theme_color_override("font_outline_color", Color(0.35, 0.2, 0.1))
	label.add_theme_constant_override("outline_size", 4)
	get_parent().add_child(label)
	label.global_position = global_position + Vector2(-6, -18)

	var t := label.create_tween()
	t.set_parallel(true)
	t.tween_property(label, "global_position:y", label.global_position.y - 20.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.2)
	t.chain().tween_callback(label.queue_free)
