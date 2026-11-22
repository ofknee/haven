@tool
extends EditorPlugin

const ProfileStore = preload("profile_store.gd")
const Solver = preload("rule_engine.gd")
const Factory = preload("tileset_factory.gd")
const GenericStore = preload("generic_profile_store.gd")
const GenericEditor = preload("generic_profile_editor.gd")
const GenericBrush = preload("generic_brush.gd")
const GenericTiles = preload("generic_tiles.gd")
const NEW_GENERIC_PROFILE := "@new_generic_profile"
const SETTINGS_META := &"erw_walls_settings"
const BRUSH_LAYER_META := &"_erw_walls_brush_layer"
const COMPATIBLE_LAYER_HINT := "Select a TileMapLayer with a compatible TileSet (.tres) from Epic RPG World Series assets."

var _profiles: Dictionary = {}
var _profile_store := ProfileStore.new()
var _generic_store := GenericStore.new()
var _generic_brush := GenericBrush.new()
var _generic_editor: GenericEditor
var _generic_profiles: Dictionary = {}
var _last_profile_id := ""
var _catalog_refresh_pending := false
var _stamp_previews: Dictionary = {}
var _solver := Solver.new()
var _factory := Factory.new()
var _layer: TileMapLayer
var _dock: VBoxContainer
var _dock_scroll: ScrollContainer
var _editor_dock: EditorDock
var _profile_choice: OptionButton
var _edit_profile_button: Button
var _delete_profile_button: Button
var _delete_profile_dialog: ConfirmationDialog
var _profile_to_delete: Dictionary
var _paint_toggle: CheckButton
var _variations: CheckBox
var _seed: SpinBox
var _status: Label
var _layer_label: Control
var _rebuild_button: Button
var _reroll_button: Button
var _drawing := false
var _erasing := false
var _before: Dictionary = {}
var _scratch: TileMapLayer
var _last_cell := Vector2i.ZERO
var _hover_cell := Vector2i.ZERO
var _has_hover := false
var _painted_sample := false
var _canvas_overlay: Control
var _active_profile: Dictionary = {}
var _preview_cells: Dictionary = {}
var _preview_texture: Texture2D
var _base_cells: Dictionary = {}
var _updating := false
var _observed_tileset: TileSet
var _native_paint_buttons: Array[Button] = []
var _native_paint_shortcut: Shortcut


func _enter_tree() -> void:
	_build_dock()
	_editor_dock = EditorDock.new()
	_editor_dock.title = "ERW Walls"
	_editor_dock.layout_key = "ERWWalls"
	_editor_dock.icon_name = &"TileMapLayer"
	_editor_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	# Hidden wrapped labels can report a huge minimum height before their first layout.
	# Keep that content inside a scroll viewport so it cannot stretch other editor docks.
	_dock_scroll = ScrollContainer.new()
	_dock_scroll.name = "WallsScroll"
	_dock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dock_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock_scroll.add_child(_dock)
	_editor_dock.add_child(_dock_scroll)
	add_dock(_editor_dock)
	add_tool_menu_item("ERW Walls Autotile 2T / 3T", _editor_dock.make_visible)
	_profiles = _profile_store.load_available()
	_generic_profiles = _generic_store.load_profiles()
	_generic_editor = GenericEditor.new()
	_generic_editor.store = _generic_store
	_generic_editor.profile_saved.connect(_on_generic_profile_saved)
	get_editor_interface().get_base_control().add_child(_generic_editor)
	_refresh_selection()
	get_editor_interface().get_resource_filesystem().filesystem_changed.connect(_queue_catalog_refresh)
	get_editor_interface().get_selection().selection_changed.connect(_refresh_selection)
	get_window().focus_exited.connect(_on_canvas_mouse_exited)
	_bind_native_paint()


func _exit_tree() -> void:
	_finish_stroke(false)
	_release_brush()
	var filesystem := get_editor_interface().get_resource_filesystem()
	if filesystem.filesystem_changed.is_connected(_queue_catalog_refresh):
		filesystem.filesystem_changed.disconnect(_queue_catalog_refresh)
	for button in _native_paint_buttons:
		if is_instance_valid(button) and button.pressed.is_connected(_select_native_paint):
			button.pressed.disconnect(_select_native_paint)
	if is_instance_valid(_layer) and _layer.changed.is_connected(_on_layer_changed):
		_layer.changed.disconnect(_on_layer_changed)
	if get_window().focus_exited.is_connected(_on_canvas_mouse_exited):
		get_window().focus_exited.disconnect(_on_canvas_mouse_exited)
	if is_instance_valid(_canvas_overlay) and _canvas_overlay.mouse_exited.is_connected(_on_canvas_mouse_exited):
		_canvas_overlay.mouse_exited.disconnect(_on_canvas_mouse_exited)
	var selection := get_editor_interface().get_selection()
	if selection.selection_changed.is_connected(_refresh_selection):
		selection.selection_changed.disconnect(_refresh_selection)
	remove_tool_menu_item("ERW Walls Autotile 2T / 3T")
	remove_dock(_editor_dock)
	_editor_dock.queue_free()
	_generic_editor.queue_free()


func _handles(object: Object) -> bool:
	return object is TileMapLayer


func _edit(object: Object) -> void:
	_set_layer(object as TileMapLayer if object != null and _handles(object) else null)


func _make_visible(visible: bool) -> void:
	# Selection must not force the Walls dock over Inspector or the native TileMap UI.
	if visible:
		_request_preview_redraw()


func _refresh_selection() -> void:
	var nodes := get_editor_interface().get_selection().get_selected_nodes()
	var selected: TileMapLayer = null
	if nodes.size() == 1 and _handles(nodes[0]):
		selected = nodes[0]
	_set_layer(selected)


func _set_layer(selected: TileMapLayer) -> void:
	if selected != _layer:
		_finish_stroke(false)
		if is_instance_valid(_layer) and _layer.changed.is_connected(_on_layer_changed):
			_layer.changed.disconnect(_on_layer_changed)
		_layer = selected
		if is_instance_valid(_layer):
			_layer.changed.connect(_on_layer_changed)
		_observed_tileset = _layer.tile_set if is_instance_valid(_layer) else null
		_has_hover = false
		_active_profile = {}
		_preview_cells = {}
		_preview_texture = null
	var tileset := _refresh_profile_choices()
	var valid := _valid_layer()
	var profile_id := _selected_profile_id()
	var generic := _generic_profiles.has(profile_id)
	_edit_profile_button.visible = generic
	_delete_profile_button.visible = generic
	var available := valid and not profile_id.is_empty()
	if generic:
		var bound := _get_profile(profile_id)
		available = available and not bound.is_empty()
		tileset = bound.get("tileset")
	if not _layer_label is RichTextLabel:
		# Upgrade an already-open dock without restarting the user's project.
		var previous := _layer_label
		_layer_label = _create_layer_label()
		_dock.add_child(_layer_label)
		_dock.move_child(_layer_label, previous.get_index())
		_dock.remove_child(previous)
		previous.queue_free()
	_layer_label.clear()
	if valid:
		_layer_label.add_text("Layer: " + str(_layer.name))
		if available and tileset != null:
			var name := tileset.resource_path.get_file()
			if name.is_empty() or name.contains("::"):
				name = tileset.resource_name if not tileset.resource_name.is_empty() else "TileSet"
			_layer_label.add_text(". Using " + name)
	if not available:
		if valid:
			_layer_label.add_text("\n")
		if generic:
			_layer_label.add_text(_status.text)
		else:
			_layer_label.append_text(COMPATIBLE_LAYER_HINT.replace("Epic RPG World Series", "[color=#ffd75a]Epic RPG World Series[/color]"))
	_paint_toggle.disabled = not available
	_rebuild_button.disabled = not available
	_reroll_button.disabled = not available
	_seed.editable = available
	_variations.disabled = not available
	if available:
		_sync_controls(_layer)
		_status.text = "Enable the Walls brush to paint this custom profile." if generic else "Choose 2T or 3T, then enable the Walls brush."
	else:
		_paint_toggle.set_pressed_no_signal(false)
		if generic:
			_status.text = ""
		else:
			_status.text = "No compatible wall profile found. The TileSet must match a converted profile's spritesheet, tile size, atlas layout and terrain." if valid else COMPATIBLE_LAYER_HINT
		_active_profile = {}
		_preview_cells = {}
		_preview_texture = null
	if available and _paint_toggle.button_pressed:
		_prepare_preview()
	_update_brush_ownership()
	_request_preview_redraw()


func _valid_layer() -> bool:
	return is_instance_valid(_layer) and _layer.is_inside_tree()


func _on_layer_changed() -> void:
	if _drawing or _updating or not _valid_layer():
		return
	_sync_controls(_layer)
	if _observed_tileset != _layer.tile_set:
		_observed_tileset = _layer.tile_set
		_active_profile = {}
		_set_layer(_layer)


func _selected_profile_id() -> String:
	if _profile_choice.selected < 0 or _profile_choice.item_count == 0:
		return ""
	var id := str(_profile_choice.get_selected_metadata())
	return "" if id == NEW_GENERIC_PROFILE else id


func _refresh_profile_choices() -> TileSet:
	_profile_choice.clear()
	var tilesets := {}
	for profile_id: String in _profiles:
		var profile: Dictionary = _profiles[profile_id].duplicate(true)
		if not _profile_store.resolve_assets(profile):
			continue
		var tileset: TileSet = _layer.tile_set if _valid_layer() else null
		if tileset == null:
			tileset = _profile_store.load_tileset(profile)
		if not _factory.configure_profile(profile, tileset):
			continue
		var index := _profile_choice.item_count
		_profile_choice.add_item(str(profile.display_name))
		_profile_choice.set_item_metadata(index, profile_id)
		tilesets[profile_id] = tileset
	if _profile_choice.item_count == 0:
		_profile_choice.add_item("No compatible wall profiles" if _generic_profiles.is_empty() else "Choose a wall profile")
		_profile_choice.set_item_metadata(0, "")
		_profile_choice.set_item_disabled(0, true)
	_profile_choice.add_separator("Custom Profiles")
	var new_profile_index := _profile_choice.item_count
	_profile_choice.add_item("New Custom Profile...")
	_profile_choice.set_item_metadata(new_profile_index, NEW_GENERIC_PROFILE)
	_profile_choice.get_popup().set_item_as_radio_checkable(new_profile_index, false)
	for profile_id: String in _generic_profiles:
		var profile: Dictionary = _generic_profiles[profile_id]
		_profile_choice.add_item(str(profile.display_name))
		_profile_choice.set_item_metadata(_profile_choice.item_count - 1, profile_id)
	_select_profile_choice(_last_profile_id)
	return tilesets.get(_last_profile_id)


func _select_profile_choice(profile_id: String) -> void:
	_profile_choice.select(0)
	for index in _profile_choice.item_count:
		if _profile_choice.get_item_metadata(index) == profile_id:
			_profile_choice.select(index)
			break
	_last_profile_id = _selected_profile_id()


func _on_generic_profile_saved(profile_id: String) -> void:
	_last_profile_id = profile_id
	_refresh_profile_catalog()


func _queue_catalog_refresh() -> void:
	if _catalog_refresh_pending:
		return
	_catalog_refresh_pending = true
	_refresh_profile_catalog.call_deferred()


func _refresh_profile_catalog() -> void:
	_catalog_refresh_pending = false
	if not is_inside_tree():
		return
	_finish_stroke(true)
	_profiles = _profile_store.load_available()
	_generic_profiles = _generic_store.load_profiles()
	_stamp_previews.clear()
	_active_profile = {}
	_set_layer(_layer)


func _create_layer_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "ERW Walls"
	_dock.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_dock.custom_minimum_size.x = 245
	_dock.mouse_entered.connect(_on_canvas_mouse_exited)
	var title := Label.new()
	title.text = "ERW Walls · 2T / 3T"
	title.add_theme_font_size_override("font_size", 17)
	_dock.add_child(title)
	_layer_label = _create_layer_label()
	_dock.add_child(_layer_label)
	_profile_choice = OptionButton.new()
	_profile_choice.item_selected.connect(_on_profile_selected)
	_dock.add_child(_profile_choice)
	_edit_profile_button = Button.new()
	_edit_profile_button.text = "Edit Selected Profile..."
	_edit_profile_button.pressed.connect(_edit_selected_profile)
	_edit_profile_button.hide()
	_dock.add_child(_edit_profile_button)
	_delete_profile_button = Button.new()
	_delete_profile_button.text = "Delete Selected Profile..."
	_delete_profile_button.pressed.connect(_confirm_profile_deletion)
	_delete_profile_button.hide()
	_dock.add_child(_delete_profile_button)
	_dock.add_child(HSeparator.new())
	_delete_profile_dialog = ConfirmationDialog.new()
	_delete_profile_dialog.title = "Delete Custom Profile"
	_delete_profile_dialog.ok_button_text = "Delete"
	_delete_profile_dialog.confirmed.connect(_delete_confirmed_profile)
	_delete_profile_dialog.canceled.connect(func() -> void: _profile_to_delete = {})
	_dock.add_child(_delete_profile_dialog)
	_paint_toggle = CheckButton.new()
	_paint_toggle.text = "Enable Walls Brush"
	_paint_toggle.tooltip_text = "Selecting native Paint Tool (D) disables the Walls brush."
	_paint_toggle.toggled.connect(_on_paint_toggled)
	_dock.add_child(_paint_toggle)
	var hint := Label.new()
	hint.text = "One click: minimum wall (2×2 top).\nDrag to extend or join walls.\nLeft: paint · Right: erase\nMiddle: pan · Esc: cancel stroke\nCtrl+Z: undo"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(hint)
	_variations = CheckBox.new()
	_variations.text = "Wall Variations"
	_variations.button_pressed = true
	_variations.toggled.connect(func(_enabled: bool) -> void: _rebuild())
	_dock.add_child(_variations)
	var seed_row := HBoxContainer.new()
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_row.add_child(seed_label)
	_seed = SpinBox.new()
	_seed.min_value = 0
	_seed.max_value = 2147483646
	_seed.value = 1
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.value_changed.connect(func(_value: float) -> void: _rebuild())
	seed_row.add_child(_seed)
	_dock.add_child(seed_row)
	_rebuild_button = Button.new()
	_rebuild_button.text = "Rebuild Walls"
	_rebuild_button.tooltip_text = "Reapply the selected wall profile's assembly rules after manual edits. The same Seed keeps the same variation; use New Variation for another result."
	_rebuild_button.pressed.connect(_rebuild)
	_dock.add_child(_rebuild_button)
	_reroll_button = Button.new()
	_reroll_button.text = "New Variation"
	_reroll_button.pressed.connect(func() -> void: _seed.value = fmod(_seed.value + 1, 2147483647.0))
	_dock.add_child(_reroll_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Floors and 1T walls use native terrains."
	_dock.add_child(_status)


func _on_paint_toggled(enabled: bool) -> void:
	_finish_stroke(true)
	if enabled:
		_prepare_preview()
	else:
		_has_hover = false
	_update_brush_ownership()
	_request_preview_redraw()


func _on_profile_selected(index: int) -> void:
	_finish_stroke(true)
	var entry := str(_profile_choice.get_item_metadata(index))
	if entry == NEW_GENERIC_PROFILE:
		_select_profile_choice(_last_profile_id)
		var tileset: TileSet = _layer.tile_set if _valid_layer() else null
		_generic_editor.show_configurator(tileset)
		return
	_last_profile_id = entry
	_active_profile = {}
	_set_layer(_layer)


func _edit_selected_profile() -> void:
	var profile: Dictionary = _generic_profiles.get(_selected_profile_id(), {})
	if profile.is_empty():
		return
	_finish_stroke(true)
	if not _generic_editor.edit_profile(profile):
		_status.text = _generic_store.error


func _confirm_profile_deletion() -> void:
	var profile: Dictionary = _generic_profiles.get(_selected_profile_id(), {})
	if profile.is_empty():
		return
	_finish_stroke(true)
	_profile_to_delete = profile.duplicate(true)
	_delete_profile_dialog.dialog_text = 'Delete the custom profile "%s"?' % profile.display_name
	_delete_profile_dialog.popup_centered_clamped(Vector2i(390, 125), 0.85)


func _delete_confirmed_profile() -> void:
	var profile := _profile_to_delete
	_profile_to_delete = {}
	if profile.is_empty():
		return
	if not _generic_store.delete_profile(profile):
		_status.text = _generic_store.error
		return
	_paint_toggle.set_pressed_no_signal(false)
	_refresh_profile_catalog()


func _bind_native_paint() -> void:
	_native_paint_shortcut = get_editor_interface().get_editor_settings().get_shortcut("tiles_editor/paint_tool")
	if _native_paint_shortcut == null:
		return
	for button in get_editor_interface().get_base_control().find_children("*", "Button", true, false):
		if button.shortcut != _native_paint_shortcut:
			continue
		var ancestor: Node = button.get_parent()
		while ancestor != null and ancestor.get_class() != "TileMapLayerEditor":
			ancestor = ancestor.get_parent()
		if ancestor != null:
			button.pressed.connect(_select_native_paint)
			_native_paint_buttons.append(button)


func _select_native_paint() -> void:
	if _paint_toggle.button_pressed:
		_paint_toggle.button_pressed = false


func _release_brush() -> void:
	var editor := get_editor_interface().get_base_control()
	if editor.has_meta(BRUSH_LAYER_META) and editor.get_meta(BRUSH_LAYER_META) == _layer:
		editor.remove_meta(BRUSH_LAYER_META)
	set_process_input(false)


func _update_brush_ownership() -> void:
	var editor := get_editor_interface().get_base_control()
	var enabled := _valid_layer() and _paint_toggle.button_pressed and not _active_profile.is_empty()
	if enabled:
		editor.set_meta(BRUSH_LAYER_META, _layer)
	elif editor.has_meta(BRUSH_LAYER_META):
		editor.remove_meta(BRUSH_LAYER_META)
	set_process_input(enabled)


func _prepare_preview() -> void:
	# Bind converted rules and solve the tiny ghost on activation, never on redraw.
	if not _valid_layer():
		return
	_active_profile = _get_profile(_selected_profile_id())
	_preview_cells = {}
	_preview_texture = null
	if _active_profile.is_empty():
		return
	if _active_profile.get("generic", false):
		var top := {Vector2i.ZERO: true, Vector2i.RIGHT: true, Vector2i.DOWN: true, Vector2i.ONE: true}
		_preview_cells = _generic_brush.generate(top, _active_profile, 1, false)
		return
	_preview_cells = _minimum_stamp(_active_profile)
	var tileset: TileSet = _active_profile.get("tileset")
	if not _active_profile.is_empty() and tileset != null and tileset.has_source(_active_profile.source_id):
		var atlas := tileset.get_source(_active_profile.source_id) as TileSetAtlasSource
		if atlas != null:
			_preview_texture = atlas.texture


func _bind_canvas_overlay(overlay: Control) -> void:
	if _canvas_overlay == overlay:
		return
	if is_instance_valid(_canvas_overlay) and _canvas_overlay.mouse_exited.is_connected(_on_canvas_mouse_exited):
		_canvas_overlay.mouse_exited.disconnect(_on_canvas_mouse_exited)
	_canvas_overlay = overlay
	_canvas_overlay.mouse_exited.connect(_on_canvas_mouse_exited)


func _on_canvas_mouse_exited() -> void:
	var had_hover := _has_hover
	_has_hover = false
	if _drawing:
		# A release over a dock must not leave a stroke running in the background.
		_finish_stroke(true)
	elif had_hover:
		_request_preview_redraw()


func _request_preview_redraw() -> void:
	update_overlays()


func _get_profile(profile_id: String) -> Dictionary:
	if _generic_profiles.has(profile_id):
		var current: TileSet = _layer.tile_set if _valid_layer() else null
		var empty := _valid_layer() and _layer.get_used_cells().is_empty()
		var generic := _generic_store.bind_profile(_generic_profiles[profile_id], current, empty)
		if generic.is_empty():
			_status.text = _generic_store.error
		return generic
	if not _profiles.has(profile_id):
		_status.text = "No compatible wall profile is selected."
		return {}
	var bound: Dictionary = _profiles[profile_id].duplicate(true)
	if not _profile_store.resolve_assets(bound):
		_status.text = "This wall profile's asset is no longer available."
		_queue_catalog_refresh()
		return {}
	var tileset: TileSet = _layer.tile_set if _valid_layer() else null
	if tileset == null:
		tileset = _profile_store.load_tileset(bound)
	if not _factory.configure_profile(bound, tileset):
		_status.text = "The selected TileSet needs this wall profile's spritesheet." if bound.get("plugin_terrain", false) else "The selected TileSet needs this wall profile's spritesheet and terrain."
		return {}
	bound["tileset"] = tileset
	return bound


func _input(event: InputEvent) -> void:
	if not _valid_layer() or not _paint_toggle.button_pressed or not is_instance_valid(_canvas_overlay):
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and _native_paint_shortcut != null and _native_paint_shortcut.matches_event(event):
		_select_native_paint()
		return
	var local_event := event
	if event is InputEventMouse:
		if event.window_id != _canvas_overlay.get_window().get_window_id():
			return
		local_event = event.duplicate()
		local_event.position = _canvas_overlay.get_global_transform_with_canvas().affine_inverse() * event.position
	if _handle_canvas_input(local_event):
		get_viewport().set_input_as_handled()


func _handle_canvas_input(event: InputEvent) -> bool:
	if not _valid_layer() or not _paint_toggle.button_pressed:
		return false
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE and _drawing:
			_finish_stroke(false)
			return true
		if _drawing and (event.ctrl_pressed or event.meta_pressed):
			_finish_stroke(true)
		return false
	if event is InputEventMouse:
		if event.alt_pressed or event.ctrl_pressed or event.meta_pressed or event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_on_canvas_mouse_exited()
			return false
		if is_instance_valid(_canvas_overlay) and not Rect2(Vector2.ZERO, _canvas_overlay.size).has_point(event.position):
			_on_canvas_mouse_exited()
			return false
		var local: Vector2 = _layer_to_editor_transform().affine_inverse() * event.position
		var cell := _layer.local_to_map(local) if _layer.tile_set != null else Vector2i(floori(local.x / 32.0), floori(local.y / 32.0))
		var changed := not _has_hover or cell != _hover_cell
		_hover_cell = cell
		_has_hover = true
		if changed or event is InputEventMouseButton:
			_request_preview_redraw()
	if event is InputEventMouseButton:
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			return false
		if event.pressed:
			if _drawing:
				_finish_stroke(true)
			_begin_stroke(event.button_index == MOUSE_BUTTON_RIGHT)
		elif _drawing:
			_finish_stroke(true)
		return true
	if event is InputEventMouseMotion and _drawing:
		if event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT) == 0:
			_finish_stroke(true)
		else:
			_paint_to(_hover_cell)
		return true
	return false


func _begin_stroke(erase: bool) -> void:
	var profile := _get_profile(_selected_profile_id())
	if profile.is_empty():
		return
	_before = _capture_state(_layer)
	_drawing = true
	if _layer.tile_set == null or (profile.get("generic", false) and _layer.tile_set != profile.tileset):
		_layer.tile_set = profile.tileset
	_observed_tileset = _layer.tile_set
	_active_profile = profile
	_base_cells = _read_base(_layer, profile)
	_store_settings()
	_erasing = erase
	if not profile.get("generic", false):
		_scratch = TileMapLayer.new()
		_scratch.tile_set = _factory.scratch_tileset(profile, _layer.tile_set)
		_factory.write_cells(_scratch, _base_cells, int(profile.columns), int(profile.source_id))
	_painted_sample = false
	_last_cell = _hover_cell
	_paint_to(_hover_cell)


func _paint_to(cell: Vector2i) -> void:
	if _painted_sample and cell == _last_cell:
		return
	if absi(cell.x) > 32760 or absi(cell.y) > 32760:
		return
	var profile := _active_profile
	var footprint := _stroke_footprint(_last_cell, cell)
	if profile.get("generic", false):
		for position in footprint:
			if _erasing:
				_base_cells.erase(position)
			else:
				_base_cells[position] = true
	else:
		_scratch.set_cells_terrain_connect(footprint, int(profile.terrain_set), -1 if _erasing else int(profile.terrain), false)
		_base_cells = _factory.read_cells(_scratch, int(profile.columns), int(profile.source_id))
	_render(_layer, profile, _base_cells)
	_last_cell = cell
	_painted_sample = true
	_status.text = "Walls erased." if _erasing else "Walls painted."


func _stroke_footprint(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	# Each sample adds all four corners of a 2x2 top, never an isolated tile.
	var unique: Dictionary = {}
	for anchor in _line_cells(start, end):
		for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
			unique[anchor + offset] = true
	var result: Array[Vector2i] = []
	result.assign(unique.keys())
	return result


func _layer_to_editor_transform() -> Transform2D:
	# CanvasItem's transform omits the editor SubViewport's global canvas transform.
	# Both picking and the ghost must include the editor's zoom and pan.
	return get_editor_interface().get_editor_viewport_2d().global_canvas_transform \
		* _layer.get_global_transform_with_canvas()


func _minimum_stamp(profile: Dictionary) -> Dictionary:
	var key := str(profile.profile_id) + ":" + str(hash([profile.native_wang, profile.tile_probabilities]))
	if not _stamp_previews.has(key) or _stamp_previews[key].is_empty():
		# Resolve the four authored corner masks directly. Avoid constructing and
		# mutating a temporary TileSet while the editor is drawing its overlay.
		var masks := [[-1, 0, -1, -1], [-1, -1, 0, -1], [0, -1, -1, -1], [-1, -1, -1, 0]]
		var base: Dictionary = {}
		for i in 4:
			for tile_id: int in profile.native_wang:
				if profile.native_wang[tile_id] == masks[i] and float(profile.tile_probabilities.get(tile_id, 0.0)) > 0.0:
					base[Vector2i(i % 2, i / 2)] = tile_id
					break
		_stamp_previews[key] = _solver.generate(base, profile, 1, false)
	return _stamp_previews[key]


func _finish_stroke(commit: bool) -> void:
	if not _drawing:
		return
	_drawing = false
	_painted_sample = false
	if is_instance_valid(_layer):
		if commit:
			_commit_state("Erase ERW Walls" if _erasing else "Paint ERW Walls", _before)
		else:
			_restore_state(_layer, _before)
	if is_instance_valid(_scratch):
		_scratch.free()
	_scratch = null
	_before = {}
	_base_cells = {}
	_request_preview_redraw()


func _read_base(layer: TileMapLayer, profile: Dictionary) -> Dictionary:
	if profile.get("generic", false):
		return _generic_brush.read_top(layer, profile.profile_id)
	# The authored reset rules recover the top from baked tiles; no layer script is needed.
	var visible := _factory.read_cells(layer, int(profile.columns), int(profile.source_id), _generic_brush.protected_cells(layer))
	var normalized := _solver.apply_phase(visible, profile.phases[0], 1, true)
	var base: Dictionary = {}
	for pos: Vector2i in normalized:
		if profile.base_wang.has(normalized[pos]):
			base[pos] = normalized[pos]
	return base


func _render(layer: TileMapLayer, profile: Dictionary, base: Dictionary) -> void:
	_updating = true
	if profile.get("generic", false):
		_generic_brush.render(layer, profile, base, int(_seed.value), _variations.button_pressed)
	else:
		var cells := _solver.generate(base, profile, int(_seed.value), _variations.button_pressed)
		_factory.write_cells(layer, cells, int(profile.columns), int(profile.source_id), _generic_brush.protected_cells(layer))
	_updating = false


func _rebuild() -> void:
	if not _valid_layer():
		return
	_finish_stroke(true)
	var profile := _get_profile(_selected_profile_id())
	if profile.is_empty():
		return
	var before := _capture_state(_layer)
	_updating = true
	if _layer.tile_set == null or (profile.get("generic", false) and _layer.tile_set != profile.tileset):
		_layer.tile_set = profile.tileset
	_updating = false
	_store_settings()
	_render(_layer, profile, _read_base(_layer, profile))
	_commit_state("Rebuild Walls ERW", before)
	_status.text = "Walls rebuilt. Ctrl+Z restores the previous result."


func _commit_state(action: String, before: Dictionary) -> void:
	var after := _capture_state(_layer)
	if before == after:
		return
	var history := get_undo_redo()
	history.create_action(action, UndoRedo.MERGE_DISABLE, _layer)
	# Native node properties keep undo usable even while this editor plugin is disabled.
	if before.tileset != after.tileset:
		history.add_do_property(_layer, "tile_set", after.tileset)
		history.add_undo_property(_layer, "tile_set", before.tileset)
	_add_settings_history(history, after, true)
	_add_settings_history(history, before, false)
	history.add_do_property(_layer, "tile_map_data", after.data)
	history.add_undo_property(_layer, "tile_map_data", before.data)
	history.commit_action(false) # The preview already applied this exact state.
	get_editor_interface().mark_scene_as_unsaved()


func _capture_state(layer: TileMapLayer) -> Dictionary:
	return {"data": layer.tile_map_data, "tileset": layer.tile_set,
		"has_settings": layer.has_meta(SETTINGS_META),
		"settings": layer.get_meta(SETTINGS_META, {}).duplicate(true),
		"has_generic": layer.has_meta(GenericBrush.META),
		"generic": layer.get_meta(GenericBrush.META, {}).duplicate(true)}


func _restore_state(layer: TileMapLayer, state: Dictionary) -> void:
	_updating = true
	if layer.tile_set != state.tileset:
		layer.tile_set = state.tileset
	if state.has_settings:
		layer.set_meta(SETTINGS_META, state.settings.duplicate(true))
	elif layer.has_meta(SETTINGS_META):
		layer.remove_meta(SETTINGS_META)
	if state.has_generic:
		layer.set_meta(GenericBrush.META, state.generic.duplicate(true))
	elif layer.has_meta(GenericBrush.META):
		layer.remove_meta(GenericBrush.META)
	layer.tile_map_data = state.data
	_updating = false
	_observed_tileset = layer.tile_set
	_sync_controls(layer)


func _add_settings_history(history: EditorUndoRedoManager, state: Dictionary, forward: bool) -> void:
	var method := "add_do_method" if forward else "add_undo_method"
	if state.has_settings:
		history.call(method, _layer, "set_meta", SETTINGS_META, state.settings)
	else:
		history.call(method, _layer, "remove_meta", SETTINGS_META)
	if state.has_generic:
		history.call(method, _layer, "set_meta", GenericBrush.META, state.generic)
	else:
		history.call(method, _layer, "remove_meta", GenericBrush.META)


func _store_settings() -> void:
	var settings: Dictionary = _layer.get_meta(SETTINGS_META, {}).duplicate(true)
	settings[_selected_profile_id()] = {"seed": int(_seed.value), "variations": _variations.button_pressed}
	_layer.set_meta(SETTINGS_META, settings)


func _sync_controls(layer: TileMapLayer) -> void:
	if _layer == layer and _valid_layer():
		var saved: Dictionary = layer.get_meta(SETTINGS_META, {})
		var profile_id := _selected_profile_id()
		var legacy_key: String = _profiles.get(profile_id, {}).get("legacy_settings_key", "")
		var settings: Dictionary = saved.get(profile_id, saved.get(legacy_key, {}))
		_seed.set_value_no_signal(settings.get("seed", 1))
		_variations.set_pressed_no_signal(settings.get("variations", true))


func _line_cells(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var pos := start
	var delta := (end - start).abs()
	var direction := Vector2i(signi(end.x - start.x), signi(end.y - start.y))
	var balance := delta.x - delta.y
	while true:
		result.append(pos)
		if pos == end:
			break
		var twice := balance * 2
		if twice > -delta.y:
			balance -= delta.y
			pos.x += direction.x
		if twice < delta.x:
			balance += delta.x
			pos.y += direction.y
	return result


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	_bind_canvas_overlay(overlay)
	if not _valid_layer() or not _paint_toggle.button_pressed or not _has_hover:
		return
	if not Rect2(Vector2.ZERO, overlay.size).has_point(overlay.get_local_mouse_position()):
		return
	if _active_profile.is_empty() or (_preview_texture == null and not _active_profile.get("generic", false)):
		return
	var size := Vector2(_active_profile.tile_size)
	var top_left := _layer.map_to_local(_hover_cell) - size * 0.5 if _layer.tile_set != null else Vector2(_hover_cell) * size
	var profile := _active_profile
	overlay.draw_set_transform_matrix(_layer_to_editor_transform())
	var erasing := _erasing if _drawing else Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var color := Color(1.0, 0.35, 0.3, 0.9) if erasing else Color(1.0, 0.75, 0.25, 0.95)
	# Show the actual four-corner silhouette and generated face, not a one-cell box.
	if not erasing:
		for pos: Vector2i in _preview_cells:
			var id: int = _preview_cells[pos]
			if profile.get("generic", false):
				_draw_generic_preview_tile(overlay, profile, id, top_left + (Vector2(pos) + Vector2(0.5, 0.5)) * size)
				continue
			var atlas_cell := Vector2i(id % int(profile.columns), id / int(profile.columns))
			var source := Rect2(Vector2(atlas_cell) * size, size)
			overlay.draw_texture_rect_region(_preview_texture, Rect2(top_left + Vector2(pos) * size, size),
				source, Color(1.0, 1.0, 1.0, 0.5))
	overlay.draw_rect(Rect2(top_left, size * Vector2(2, int(profile.height) + 1)), color * Color(1, 1, 1, 0.5), false, 1.0)
	overlay.draw_rect(Rect2(top_left, size * 2.0), color, false, 1.5)
	overlay.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_generic_preview_tile(overlay: Control, profile: Dictionary, role: int, center: Vector2) -> void:
	var tile: Vector4i = profile.tiles[role]
	var tileset: TileSet = profile.tileset
	var data := GenericTiles.tile_data(tileset, tile)
	if data == null:
		var icon := EditorInterface.get_editor_theme().get_icon(&"PackedScene", &"EditorIcons")
		var icon_size := Vector2(profile.tile_size)
		overlay.draw_texture_rect(icon, Rect2(center - icon_size * 0.5, icon_size), false, Color(1, 1, 1, 0.5))
		return
	var atlas := GenericTiles.atlas_for(tileset, tile)
	var source := atlas.get_tile_texture_region(Vector2i(tile.y, tile.z))
	var size := Vector2(source.size)
	if data.transpose:
		size = Vector2(size.y, size.x)
	var position := center - size * 0.5 + Vector2(data.texture_origin)
	var flip := Vector2(-1 if data.flip_h else 1, -1 if data.flip_v else 1)
	overlay.draw_texture_rect_region(atlas.texture, Rect2(position, size * flip), source,
		data.modulate * Color(1, 1, 1, 0.5), data.transpose)

