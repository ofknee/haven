@tool
extends EditorPlugin
## Expands native Paint input; Godot owns tile selection, terrain solving and undo.

const Geometry = preload("brush_geometry.gd")
const META_SECTION := "native_tile_brush_size"
const MAX_SIZE := 32
const WALLS_BRUSH_LAYER_META := &"_erw_walls_brush_layer"

var _size := 1
var _layer: TileMapLayer
var _overlay: Control
var _tools: Array[Dictionary] = []
var _replaying := false
var _stroke := false
var _button := MOUSE_BUTTON_LEFT
var _last_cell := Vector2i.ZERO
var _has_hover := false
var _hover_cell := Vector2i.ZERO
var _visited: Dictionary = {}
var _last_window_position := Vector2.ZERO
var _window_id := 0
var _available := false


func _enter_tree() -> void:
	_size = clampi(int(EditorInterface.get_editor_settings().get_project_metadata(META_SECTION,"size",1)),1,MAX_SIZE)
	_attach_controls()
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)
	get_window().focus_exited.connect(_finish_native_stroke)
	_selection_changed()


func _exit_tree() -> void:
	_finish_native_stroke()
	if is_instance_valid(_layer) and _layer.changed.is_connected(_refresh_availability):
		_layer.changed.disconnect(_refresh_availability)
	if get_window().focus_exited.is_connected(_finish_native_stroke):
		get_window().focus_exited.disconnect(_finish_native_stroke)
	var selection := EditorInterface.get_selection()
	if selection.selection_changed.is_connected(_selection_changed):
		selection.selection_changed.disconnect(_selection_changed)
	if is_instance_valid(_overlay) and _overlay.mouse_exited.is_connected(_canvas_exited):
		_overlay.mouse_exited.disconnect(_canvas_exited)
	for tool in _tools:
		if is_instance_valid(tool.paint):
			tool.paint.toggled.disconnect(_paint_toggled)
			tool.paint.visibility_changed.disconnect(_paint_visibility_changed)
		if is_instance_valid(tool.ui):
			tool.ui.get_parent().remove_child(tool.ui)
			tool.ui.queue_free()
	_tools.clear()


func _handles(object: Object) -> bool:
	return object is TileMapLayer


func _edit(object: Object) -> void:
	if object is TileMapLayer:
		_set_layer(object)


func _selection_changed() -> void:
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	_set_layer(nodes[0] as TileMapLayer if nodes.size() == 1 else null)


func _set_layer(layer: TileMapLayer) -> void:
	if layer != _layer:
		_finish_native_stroke()
		if is_instance_valid(_layer) and _layer.changed.is_connected(_refresh_availability):
			_layer.changed.disconnect(_refresh_availability)
		_layer = layer
		if is_instance_valid(_layer):
			_layer.changed.connect(_refresh_availability)
		_has_hover = false
	_refresh_availability(true)


func _refresh_availability(force: bool = false) -> void:
	var supported := _supported_layer()
	if not force and supported == _available:
		return
	_available = supported
	for tool in _tools:
		tool.spin.editable = supported
		tool.ui.tooltip_text = "Square brush size for native terrain painting. Disable the ERW Walls brush to use native Paint." if supported else "Select a square TileMapLayer."
	set_process_input(_size > 1 and supported)


func _supported_layer() -> bool:
	if not is_instance_valid(_layer) or not _layer.is_inside_tree() or _layer.tile_set == null:
		return false
	if _layer.tile_set.tile_shape != TileSet.TILE_SHAPE_SQUARE:
		return false
	return true


func _walls_brush_active() -> bool:
	var editor := EditorInterface.get_base_control()
	return editor.has_meta(WALLS_BRUSH_LAYER_META) and editor.get_meta(WALLS_BRUSH_LAYER_META) == _layer


func _attach_controls() -> void:
	var shortcut := EditorInterface.get_editor_settings().get_shortcut("tiles_editor/paint_tool")
	var picker_shortcut := EditorInterface.get_editor_settings().get_shortcut("tiles_editor/picker")
	var selection_shortcut := EditorInterface.get_editor_settings().get_shortcut("tiles_editor/selection_tool")
	for button in EditorInterface.get_base_control().find_children("*","Button",true,false):
		if shortcut == null or selection_shortcut == null or button.shortcut != shortcut:
			continue
		var parent: Node = button.get_parent()
		var native_tilemap := false
		while parent != null:
			native_tilemap = native_tilemap or parent.get_class() == "TileMapLayerEditor"
			parent = parent.get_parent()
		if not native_tilemap:
			continue
		# Godot's Tiles toolbar has the Selection tool. The Terrains toolbar omits it.
		var toolbar: Node = button.get_parent()
		var has_selection_tool := toolbar.get_children().any(
			func(child: Node) -> bool: return child is Button and child.shortcut == selection_shortcut
		)
		if has_selection_tool:
			continue
		var ui := HBoxContainer.new()
		ui.name = "NativeBrushSize"
		ui.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var label := Label.new()
		label.text = "Brush Size"
		ui.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 1
		spin.max_value = MAX_SIZE
		spin.step = 1
		spin.value = _size
		spin.suffix = "× %d" % _size
		spin.custom_minimum_size.x = 85
		spin.value_changed.connect(_size_changed)
		ui.add_child(spin)
		toolbar.add_child(ui)
		toolbar.move_child(ui,button.get_index()+1)
		var pickers: Array[Button] = []
		for sibling in toolbar.get_parent().find_children("*","Button",true,false):
			if sibling.shortcut == picker_shortcut and picker_shortcut != null:
				pickers.append(sibling)
		_tools.append({"paint":button,"pickers":pickers,"ui":ui,"spin":spin})
		button.toggled.connect(_paint_toggled)
		button.visibility_changed.connect(_paint_visibility_changed)
	if _tools.is_empty():
		push_warning("Native Tile Brush Size: compatible native terrain Paint controls were not found.")


func _size_changed(value: float) -> void:
	_finish_native_stroke()
	_size = clampi(int(value),1,MAX_SIZE)
	for tool in _tools:
		tool.spin.set_value_no_signal(_size)
		tool.spin.suffix = "× %d" % _size
	EditorInterface.get_editor_settings().set_project_metadata(META_SECTION,"size",_size)
	set_process_input(_size > 1 and _supported_layer())
	update_overlays()


func _paint_toggled(pressed: bool) -> void:
	if not pressed:
		_finish_native_stroke()
	update_overlays()


func _paint_visibility_changed() -> void:
	_finish_native_stroke()
	_has_hover = false
	update_overlays()


func _paint_tool_active() -> bool:
	for tool in _tools:
		if is_instance_valid(tool.paint) and tool.paint.is_visible_in_tree() and tool.paint.button_pressed:
			# The native picker remains a normal one-cell operation.
			for picker in tool.pickers:
				if is_instance_valid(picker) and picker.is_visible_in_tree() and picker.button_pressed:
					return false
			return true
	return false


func _over_canvas(position: Vector2) -> bool:
	return is_instance_valid(_overlay) and _overlay.is_visible_in_tree() and _overlay.get_global_rect().has_point(position)


func _layer_to_overlay() -> Transform2D:
	return EditorInterface.get_editor_viewport_2d().global_canvas_transform * _layer.get_global_transform_with_canvas()


func _window_to_cell(position: Vector2) -> Vector2i:
	var canvas_position := _overlay.get_global_transform_with_canvas().affine_inverse()*position
	return _layer.local_to_map(_layer_to_overlay().affine_inverse()*canvas_position)


func _cell_to_window(cell: Vector2i) -> Vector2:
	return _overlay.get_global_transform_with_canvas()*_layer_to_overlay()*_layer.map_to_local(cell)


func _input(event: InputEvent) -> void:
	if _replaying:
		return
	if _walls_brush_active():
		_finish_native_stroke()
		_has_hover = false
		return
	if event is InputEventKey:
		if _stroke and event.pressed and event.keycode == KEY_ESCAPE:
			_finish_native_stroke()
		return
	if not event is InputEventMouse:
		return
	if not is_instance_valid(_overlay) or event.window_id != _overlay.get_window().get_window_id():
		return
	if _size == 1 or not _supported_layer() or not _paint_tool_active():
		return
	if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		_finish_native_stroke()
		return
	if event.alt_pressed or event.ctrl_pressed or event.meta_pressed or event.shift_pressed:
		_finish_native_stroke()
		return
	if not _over_canvas(event.position):
		if _stroke:
			_finish_native_stroke()
		if _has_hover:
			_has_hover = false
			update_overlays()
		return
	var cell := _window_to_cell(event.position)
	var changed := not _has_hover or cell != _hover_cell
	_hover_cell = cell
	_has_hover = true
	if changed:
		update_overlays()
	if event is InputEventMouseButton:
		if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			return
		if event.pressed:
			_finish_native_stroke()
			_stroke = true
			_button = event.button_index
			_window_id = event.window_id
			_last_cell = cell
			_visited.clear()
			_replay_sample(event,true)
		elif _stroke and event.button_index == _button:
			_replay_sample(event,false)
			_stroke = false
			_visited.clear()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _stroke:
		if event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT) == 0:
			_finish_native_stroke()
			return
		if cell != _last_cell:
			_replay_sample(event,false)
		get_viewport().set_input_as_handled()


func _replay_sample(event: InputEventMouse, begin: bool) -> void:
	# Direct viewport delivery keeps OS input and event-buffer settings untouched.
	_replaying = true
	if begin:
		var down := event.duplicate() as InputEventMouseButton
		down.position = _cell_to_window(_hover_cell)
		down.global_position = down.position
		_last_window_position = down.position
		get_viewport().push_input(down,true)
	var releasing: bool = event is InputEventMouseButton and not event.pressed
	if not releasing:
		for center in Geometry.line(_last_cell,_hover_cell):
			_send_motion(_cell_to_window(center),event)
			for cell in Geometry.footprint(center,_size):
				if not _visited.has(cell):
					_visited[cell] = true
					_send_motion(_cell_to_window(cell),event)
			_send_motion(_cell_to_window(center),event)
		_last_cell = _hover_cell
	if releasing:
		get_viewport().push_input(event.duplicate(),true)
	else:
		# Restore native hover to the real pointer without moving the OS cursor.
		_send_motion(event.position,event)
	_replaying = false


func _send_motion(position: Vector2, original: InputEventMouse) -> void:
	var motion := InputEventMouseMotion.new()
	motion.window_id = original.window_id
	motion.position = position
	motion.global_position = position
	motion.relative = position-_last_window_position
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	_last_window_position = position
	get_viewport().push_input(motion,true)


func _finish_native_stroke() -> void:
	if not _stroke:
		return
	_replaying = true
	var up := InputEventMouseButton.new()
	up.window_id = _window_id
	up.position = _last_window_position
	up.global_position = up.position
	up.button_index = _button
	up.pressed = false
	get_viewport().push_input(up,true)
	_replaying = false
	_stroke = false
	_visited.clear()


func _canvas_exited() -> void:
	if _replaying:
		return
	_finish_native_stroke()
	if _has_hover:
		_has_hover = false
		update_overlays()


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if _overlay != overlay:
		if is_instance_valid(_overlay) and _overlay.mouse_exited.is_connected(_canvas_exited):
			_overlay.mouse_exited.disconnect(_canvas_exited)
		_overlay = overlay
		_overlay.mouse_exited.connect(_canvas_exited)
	if _walls_brush_active():
		_has_hover = false
		return
	if _size <= 1 or not _supported_layer() or not _paint_tool_active() or not _has_hover:
		return
	var start := _hover_cell-Vector2i.ONE*int((_size-1)/2)
	var tile_size := Vector2(_layer.tile_set.tile_size)
	var top_left := _layer.map_to_local(start)-tile_size*.5
	overlay.draw_set_transform_matrix(_layer_to_overlay())
	overlay.draw_rect(Rect2(top_left,tile_size*_size),Color(1,.8,.25,.9),false,1.5)
	overlay.draw_set_transform_matrix(Transform2D.IDENTITY)


