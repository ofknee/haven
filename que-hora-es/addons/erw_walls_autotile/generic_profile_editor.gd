@tool
extends Node

const Store = preload("generic_profile_store.gd")
const Tiles = preload("generic_tiles.gd")
const AtlasView = preload("generic_atlas_view.gd")
const SLOT_SIZE := 32
const TEMPLATE_COLUMNS := 7
# Each row shows the two input pairs and the optional join pair they produce.
const JOIN_GUIDE_ROWS := [
	[[41, 42], [48, 52], [46, 47]],
	[[41, 42], [17, 19], [62, 63]],
]
const JOIN_INPUT_COLOR := Color("#ffee32")
const JOIN_OUTPUT_COLOR := Color(0.27, 0.83, 0.64)

signal profile_saved(profile_id: String)

var store: RefCounted
var _builder: ConfirmationDialog
var _name: LineEdit
var _height_choice: OptionButton
var _template: Control
var _optional_guide: VBoxContainer
var _join_input_markers: Dictionary[int, Panel] = {}
var _variants_panel: VBoxContainer
var _variant_cards: HBoxContainer
var _builder_status: Label
var _clear_slots_button: Button
var _undo_button: Button
var _redo_button: Button
var _picker: EditorResourcePicker
var _source_choice: OptionButton
var _atlas_view: AtlasView
var _atlas_tools: HBoxContainer
var _alternative: OptionButton
var _selection_count: Label
var _scenes: ScenePicker
var _tileset: TileSet
var _height := 2
var _editing_profile: Dictionary
var _drafts := {2: {}, 3: {}}
var _draft_variations := {2: [], 3: []}
var _draft_history: UndoRedo
var _expanded_role := -1
var _preview_roles: Array = []
var _slots := {}
var _positions := {}
var _empty_slot_style: StyleBoxFlat
var _filled_slot_style: StyleBoxFlat


class ScenePicker extends ItemList:
	func _get_drag_data(position: Vector2) -> Variant:
		var index := get_item_at_position(position, true)
		if index < 0:
			return null
		var preview := TextureRect.new()
		preview.texture = get_item_icon(index)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		preview.custom_minimum_size = Vector2.ONE * SLOT_SIZE
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_drag_preview(preview)
		var assignment: Dictionary = get_item_metadata(index).duplicate()
		assignment["source_view"] = self
		return assignment


class VariantMarker extends BaseButton:
	func _ready() -> void:
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var background := Color(0.24, 0.34, 0.44) if is_hovered() else Color(0.08, 0.11, 0.15)
		draw_rect(Rect2(Vector2.ZERO, size), background)
		var center := size * 0.5
		draw_line(center - Vector2(4, 0), center + Vector2(4, 0), Color.WHITE, 2.0)
		draw_line(center - Vector2(0, 4), center + Vector2(0, 4), Color.WHITE, 2.0)


class VariantDivider extends Control:
	var dotted := false

	func _draw() -> void:
		var start := get_theme_default_font_size() + 4
		var x := floorf(size.x * 0.5)
		var ink := Color(0.08, 0.10, 0.13, 0.8)
		if dotted:
			for y in range(start, floori(size.y), 4):
				draw_rect(Rect2(x, y, 1, 2), ink)
		elif size.y > start:
			draw_rect(Rect2(x, start, 1, size.y - start), ink)


class Slot extends Panel:
	signal tile_dropped(assignment: Dictionary)
	signal clear_requested
	signal preview_requested
	var accepts_tiles: Callable
	var preview: TextureRect
	var more: VariantMarker

	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and accepts_tiles.call(data)

	func _drop_data(_position: Vector2, data: Variant) -> void:
		tile_dropped.emit(data)

	func _gui_input(event: InputEvent) -> void:
		if not event is InputEventMouseButton or not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			clear_requested.emit()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and (not more.visible or not more.get_rect().has_point(event.position)):
			preview_requested.emit()
			accept_event()


func _ready() -> void:
	_draft_history = UndoRedo.new()
	_build_configurator()


func _exit_tree() -> void:
	if _draft_history != null:
		_draft_history.free()
		_draft_history = null


func _build_configurator() -> void:
	_builder = ConfirmationDialog.new()
	_builder.title = "Configure Custom Walls"
	_builder.ok_button_text = "Save Profile"
	_builder.dialog_hide_on_ok = false
	_builder.confirmed.connect(_save)
	_builder.visibility_changed.connect(_on_configurator_visibility_changed)
	add_child(_builder)
	var content := VBoxContainer.new()
	_builder.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_name = LineEdit.new()
	_name.placeholder_text = "Profile name"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(func(_text: String) -> void: _update_save_state())
	header.add_child(_name)
	_height_choice = OptionButton.new()
	_height_choice.add_item("Walls 2T")
	_height_choice.add_item("Walls 3T")
	_height_choice.item_selected.connect(_select_height)
	header.add_child(_height_choice)
	_undo_button = _add_history_button(header, "Undo", [_history_key(KEY_Z)], _undo_draft)
	_redo_button = _add_history_button(header, "Redo", [_history_key(KEY_Y), _history_key(KEY_Z, true)], _redo_draft)
	_clear_slots_button = Button.new()
	_clear_slots_button.text = "Clear Slots"
	_clear_slots_button.pressed.connect(_clear_slots)
	header.add_child(_clear_slots_button)
	var profile_note := Label.new()
	profile_note.text = "Custom profiles use simplified autotile rules and require far fewer tiles."
	profile_note.clip_text = true
	profile_note.tooltip_text = profile_note.text
	content.add_child(profile_note)
	var hint := Label.new()
	hint.text = "Scroll to zoom. Middle-drag or right-drag to pan. Ctrl-click to select multiple tiles.\nDrag tiles from the source TileSet. Right-click to clear a tile, wall column, or variation."
	hint.clip_text = true
	content.add_child(hint)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(split)
	var template_panel := VBoxContainer.new()
	template_panel.custom_minimum_size.x = TEMPLATE_COLUMNS * SLOT_SIZE + 16
	split.add_child(template_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 7 * SLOT_SIZE + 16
	template_panel.add_child(scroll)
	_template = Control.new()
	_template.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scroll.add_child(_template)
	_empty_slot_style = _slot_style(Color(0.07, 0.10, 0.13, 0.08))
	_filled_slot_style = _slot_style(Color(0.09, 0.12, 0.16))
	_optional_guide = VBoxContainer.new()
	_optional_guide.hide()
	template_panel.add_child(_optional_guide)
	_variants_panel = VBoxContainer.new()
	_variants_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_variants_panel.add_theme_constant_override("separation", 3)
	template_panel.add_child(_variants_panel)
	_variants_panel.add_child(HSeparator.new())
	var variants_label := Label.new()
	variants_label.text = "Tile Variations"
	_variants_panel.add_child(variants_label)
	var variants_hint := Label.new()
	variants_hint.text = "Right-click to remove a variation"
	variants_hint.add_theme_font_size_override("font_size", 11)
	variants_hint.modulate = Color(1, 1, 1, 0.55)
	_variants_panel.add_child(variants_hint)
	var variants_scroll := ScrollContainer.new()
	variants_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_variants_panel.add_child(variants_scroll)
	_variant_cards = HBoxContainer.new()
	_variant_cards.add_theme_constant_override("separation", 6)
	variants_scroll.add_child(_variant_cards)
	_variants_panel.hide()

	var palette_panel := VBoxContainer.new()
	palette_panel.custom_minimum_size.x = 230
	palette_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(palette_panel)
	var tile_set_label := Label.new()
	tile_set_label.text = "Source TileSet"
	palette_panel.add_child(tile_set_label)
	_picker = EditorResourcePicker.new()
	_picker.base_type = "TileSet"
	_picker.resource_changed.connect(_set_tileset)
	palette_panel.add_child(_picker)
	_source_choice = OptionButton.new()
	_source_choice.fit_to_longest_item = false
	_source_choice.item_selected.connect(func(_index: int) -> void: _show_source())
	palette_panel.add_child(_source_choice)
	_build_source_view(palette_panel)
	_builder_status = Label.new()
	_builder_status.clip_text = true
	content.add_child(_builder_status)


func _slot_style(background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = Color(0.69, 0.81, 0.91, 0.55)
	style.set_border_width_all(1)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 1)
	return style


func _build_source_view(panel: VBoxContainer) -> void:
	_atlas_tools = HBoxContainer.new()
	panel.add_child(_atlas_tools)
	for control in ["−", "+", "Fit"]:
		var button := Button.new()
		button.text = control
		button.pressed.connect(_zoom_atlas.bind(control))
		_atlas_tools.add_child(button)
	_alternative = OptionButton.new()
	_alternative.fit_to_longest_item = false
	_alternative.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_alternative.item_selected.connect(func(index: int) -> void: _atlas_view.set_alternative(_alternative.get_item_id(index)))
	_atlas_tools.add_child(_alternative)
	_selection_count = Label.new()
	_atlas_tools.add_child(_selection_count)

	_atlas_view = AtlasView.new()
	_atlas_view.custom_minimum_size.y = 130
	_atlas_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_atlas_view.selection_changed.connect(_update_atlas_selection)
	panel.add_child(_atlas_view)
	_scenes = ScenePicker.new()
	_scenes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_scenes)


func _zoom_atlas(action: String) -> void:
	if action == "Fit":
		_atlas_view.fit()
	else:
		_atlas_view.set_zoom(_atlas_view.zoom * (1.25 if action == "+" else 0.8))


func _update_atlas_selection() -> void:
	_alternative.clear()
	_alternative.add_item("Base Tile", 0)
	for id in _atlas_view.selected_alternatives():
		if id != 0:
			_alternative.add_item("Alternative %d" % id, id)
	var index := _alternative.get_item_index(_atlas_view.current_alternative())
	_alternative.select(maxi(index, 0))
	_alternative.disabled = _alternative.item_count < 2
	_selection_count.text = "%d selected" % _atlas_view.selection_size()


func edit_profile(profile: Dictionary) -> bool:
	var tileset: TileSet = store.load_profile_tileset(profile)
	if tileset == null:
		return false
	show_configurator(tileset, profile)
	return true


func show_configurator(tileset: TileSet, profile: Dictionary = {}) -> void:
	_editing_profile = profile.duplicate(true)
	_draft_history.clear_history()
	_update_history_buttons()
	_drafts = {2: {}, 3: {}}
	_draft_variations = {2: [], 3: []}
	var height := int(profile.get("height", 2))
	var source_id := -1
	if not profile.is_empty():
		var tiles: Dictionary = profile.tiles
		for role in tiles:
			_drafts[height][role] = {"tileset": tileset, "tile": tiles[role]}
		_draft_variations[height] = profile.get("variations", []).duplicate(true)
		var first_tile: Vector4i = tiles.values()[0]
		source_id = first_tile.x
	_builder.title = "Configure Custom Walls" if profile.is_empty() else "Edit Custom Walls"
	_name.text = str(profile.get("display_name", ""))
	_height_choice.select(height - 2)
	_select_height(height - 2)
	_picker.edited_resource = tileset
	_set_tileset(tileset, source_id)
	_builder.popup_centered_clamped.call_deferred(Vector2i(1100, 800), 0.95)
	_zoom_atlas.call_deferred("Fit")


func _select_height(index: int) -> void:
	_height = index + 2
	for child in _template.get_children():
		_template.remove_child(child)
		child.queue_free()
	_slots.clear()
	_positions.clear()
	_expanded_role = -1
	var slots: Dictionary = store.template(_height).get("slots", {})
	_template.custom_minimum_size = Vector2(TEMPLATE_COLUMNS, _height + 4) * SLOT_SIZE
	var guide := TextureRect.new()
	var guide_path := "res://addons/erw_walls_autotile/graphics/walls_%dt.png" % _height
	if ResourceLoader.exists(guide_path, "Texture2D"):
		guide.texture = load(guide_path) as Texture2D
	guide.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide.modulate.a = 0.6
	guide.size = _template.custom_minimum_size
	_template.add_child(guide)
	for role: int in slots:
		var slot := Slot.new()
		slot.position = Vector2(_guide_position(slots[role])) * SLOT_SIZE
		slot.size = Vector2.ONE * SLOT_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.preview = _tile_preview()
		slot.add_child(slot.preview)
		var more := VariantMarker.new()
		more.tooltip_text = "Show tile variations"
		more.focus_mode = Control.FOCUS_NONE
		more.mouse_filter = Control.MOUSE_FILTER_PASS
		more.size = Vector2(16, 16)
		more.position = (slot.size - more.size) * 0.5
		more.pressed.connect(_toggle_variants.bind(role))
		slot.more = more
		slot.add_child(more)
		slot.accepts_tiles = _can_assign.bind(role)
		slot.tile_dropped.connect(_assign.bind(role))
		slot.clear_requested.connect(_clear_slot.bind(role))
		slot.preview_requested.connect(_show_slot_variations.bind(role))
		_slots[role] = slot
		_positions[slots[role]] = role
		_template.add_child(slot)
		_update_slot(role)
	_update_optional_guide(guide, slots)
	_update_variations()
	_sync_draft_source()
	_update_save_state()


func _sync_draft_source() -> void:
	var source := _draft_source()
	if source != null and source != _tileset:
		_picker.edited_resource = source
		_set_tileset(source)


func _update_optional_guide(guide: TextureRect, slots: Dictionary) -> void:
	_join_input_markers.clear()
	for child in _optional_guide.get_children():
		_optional_guide.remove_child(child)
		child.queue_free()
	_optional_guide.visible = _height == 3
	if _height != 3:
		return

	var heading := HBoxContainer.new()
	_optional_guide.add_child(heading)
	var caption := Label.new()
	caption.text = "Optional Tiles Guide"
	heading.add_child(caption)
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(line)

	var input_outline := _slot_style(Color.TRANSPARENT)
	input_outline.border_color = JOIN_INPUT_COLOR
	var output_outline := _slot_style(Color.TRANSPARENT)
	output_outline.border_color = JOIN_OUTPUT_COLOR
	for recipe: Array in JOIN_GUIDE_ROWS:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_theme_constant_override("separation", 0)
		_optional_guide.add_child(row)
		var inputs: Array = recipe[0] + recipe[1]
		row.mouse_entered.connect(_highlight_join_inputs.bind(inputs))
		row.mouse_exited.connect(_highlight_join_inputs.bind([]))
		for part in recipe.size():
			if part > 0:
				var operator := Label.new()
				operator.text = "+" if part == 1 else "="
				operator.custom_minimum_size.x = 18
				operator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				operator.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(operator)
			var is_output := part == 2
			var outline := output_outline if is_output else input_outline
			for role: int in recipe[part]:
				var tile := _guide_tile_panel(outline)
				row.add_child(tile)
				var region := AtlasTexture.new()
				region.atlas = guide.texture
				region.region = Rect2(Vector2(_guide_position(slots[role])) * SLOT_SIZE, Vector2.ONE * SLOT_SIZE)
				var preview := _tile_preview()
				preview.texture = region
				preview.modulate.a = guide.modulate.a
				tile.add_child(preview)
				if is_output or not _join_input_markers.has(role):
					var marker := _guide_tile_panel(outline)
					_slots[role].add_child(marker)
					marker.visible = is_output
					if not is_output:
						_join_input_markers[role] = marker
	_optional_guide.add_child(HSeparator.new())


func _guide_tile_panel(outline: StyleBoxFlat) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2.ONE * SLOT_SIZE
	panel.size = panel.custom_minimum_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", outline)
	return panel


func _highlight_join_inputs(roles: Array) -> void:
	for role in _join_input_markers:
		_join_input_markers[role].visible = role in roles


func _guide_position(position: Vector2i) -> Vector2i:
	if _height == 3 and position.x >= 14:
		return position + Vector2i(-9, 2)
	if position.x >= 9:
		return position + Vector2i(-4, 1 if _height == 3 else 0)
	return position


func _set_tileset(resource: Resource, preferred_source: int = -1) -> void:
	var source := _draft_source()
	if source != null and resource != source:
		_picker.edited_resource = source
		return
	_tileset = resource as TileSet
	_source_choice.clear()
	if _tileset != null:
		for index in _tileset.get_source_count():
			var id := _tileset.get_source_id(index)
			var native_source := _tileset.get_source(id)
			if native_source is TileSetAtlasSource and native_source.texture == null:
				continue
			var name := native_source.resource_name
			if name.is_empty() and native_source is TileSetAtlasSource:
				name = native_source.texture.resource_path.get_file()
			var kind := "Scene Collection" if native_source is TileSetScenesCollectionSource else "Atlas"
			_source_choice.add_item("%s (%d)" % [name if not name.is_empty() else kind, id])
			_source_choice.set_item_metadata(_source_choice.item_count - 1, id)
			if id == preferred_source:
				_source_choice.select(_source_choice.item_count - 1)
	_source_choice.disabled = _source_choice.item_count == 0
	if _source_choice.disabled:
		_source_choice.text = "Choose a TileSet"
	_show_source()
	_update_save_state()


func _show_source() -> void:
	_scenes.clear()
	_scenes.hide()
	_atlas_view.hide()
	_atlas_tools.hide()
	if _source_choice.item_count == 0:
		_atlas_view.set_atlas(null, -1)
		return
	var id := int(_source_choice.get_selected_metadata())
	var source := _tileset.get_source(id)
	if source is TileSetScenesCollectionSource:
		_scenes.show()
		for index in source.get_scene_tiles_count():
			var scene_id: int = source.get_scene_tile_id(index)
			var scene: PackedScene = source.get_scene_tile_scene(scene_id)
			if scene != null:
				var icon := EditorInterface.get_editor_theme().get_icon(&"PackedScene", &"EditorIcons")
				var item := _scenes.add_item(scene.resource_path.get_file().get_basename(), icon)
				_scenes.set_item_metadata(item, {"tileset": _tileset, "tile": Vector4i(id, 0, 0, scene_id)})
		return
	_atlas_view.show()
	_atlas_tools.show()
	_atlas_view.set_atlas(_tileset, id)


func _can_assign(assignment: Dictionary, role: int) -> bool:
	return not _placements(assignment, role).is_empty()


func _placements(assignment: Dictionary, role: int) -> Dictionary:
	var source_view: Control = _atlas_view if _atlas_view.visible else _scenes
	if assignment.get("source_view") != source_view:
		return {}
	var tileset: TileSet = assignment.get("tileset")
	var source := _draft_source()
	if tileset == null or tileset != _tileset or (source != null and tileset != source):
		return {}
	var tiles: Dictionary = assignment.get("tiles", {})
	if tiles.is_empty() and assignment.get("tile") is Vector4i:
		tiles = {Vector2i.ZERO: assignment.tile}
	var slots: Dictionary = store.template(_height).get("slots", {})
	if not slots.has(role) or tiles.size() > slots.size():
		return {}
	var anchor: Vector2i = slots[role]
	var placements := {}
	for offset: Vector2i in tiles:
		var target := anchor + offset
		if not _positions.has(target) or not Tiles.has_tile(tileset, tiles[offset]):
			return {}
		placements[_positions[target]] = {"tileset": tileset, "tile": tiles[offset]}
	return placements


func _assign(assignment: Dictionary, role: int) -> void:
	var placements := _placements(assignment, role)
	if placements.is_empty():
		_builder_status.text = "The selected tiles do not fit here."
		return
	var before := _capture_draft()
	var draft: Dictionary = _drafts[_height]
	var variation := {}
	var changed := false
	for target: int in placements:
		if draft.has(target):
			changed = changed or draft[target].tile != placements[target].tile
		else:
			draft[target] = placements[target]
			_update_slot(target)
		variation[target] = placements[target].tile
	if changed and variation not in _draft_variations[_height]:
		_draft_variations[_height].append(variation)
	_update_variations()
	_update_save_state()
	_commit_draft_change("Assign tiles", before)


func _clear_slot(role: int) -> void:
	var before := _capture_draft()
	var draft: Dictionary = _drafts[_height]
	var cleared := _slots_to_clear(role)
	for member: int in cleared:
		draft.erase(member)
		_update_slot(member)
	var remaining := []
	for variation: Dictionary in _draft_variations[_height]:
		for member: int in cleared:
			variation.erase(member)
		for member: int in variation:
			if variation[member] != draft[member].tile and variation not in remaining:
				remaining.append(variation)
				break
	_draft_variations[_height] = remaining
	_update_variations()
	_update_save_state()
	_commit_draft_change("Clear template tiles", before)


func _slots_to_clear(role: int) -> Array:
	for column: Array in store.template(_height).get("wall_columns", []):
		if role in column:
			return column
	return [role]


func _variation_top(role: int) -> int:
	var joins: Dictionary = store.template(_height).get("join_variation_tops", {})
	if joins.has(role):
		return joins[role]
	return _slots_to_clear(role)[0]


func _update_slot(role: int) -> void:
	var slot: Slot = _slots[role]
	var assignment: Dictionary = _drafts[_height].get(role, {})
	var coordinate := "%d,%d" % [role % 16, role / 16]
	var join_slots: Dictionary = store.template(_height).get("join_slots", {})
	var label := "Optional join slot" if join_slots.has(role) else "Reference slot"
	var clear_hint := "Right-click to clear wall column" if _slots_to_clear(role).size() > 1 else "Right-click to clear"
	slot.tooltip_text = "%s (%s)\n%s" % [label, coordinate, clear_hint]
	if not assignment.is_empty() and _variation_top(role) == role:
		slot.tooltip_text += "\nClick to preview variations"
	slot.add_theme_stylebox_override("panel", _empty_slot_style if assignment.is_empty() else _filled_slot_style)
	slot.preview.texture = null if assignment.is_empty() else _tile_thumbnail(assignment.tileset, assignment.tile)


func _tile_thumbnail(tileset: TileSet, tile: Vector4i) -> Texture2D:
	var thumbnail := Tiles.thumbnail(tileset, tile)
	if thumbnail == null:
		var icon := &"PackedScene" if Tiles.has_tile(tileset, tile) else &"StatusWarning"
		return EditorInterface.get_editor_theme().get_icon(icon, &"EditorIcons")
	return thumbnail


func _tile_preview() -> TextureRect:
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.size = Vector2.ONE * SLOT_SIZE
	return preview


func _toggle_variants(role: int) -> void:
	_show_slot_variations(-1 if _expanded_role == role else role)


func _show_slot_variations(role: int) -> void:
	if role >= 0 and _variation_top(role) != role:
		return
	if not _drafts[_height].has(role):
		role = -1
	if role == _expanded_role:
		return
	_preview_roles = [role]
	_expanded_role = role
	_update_variations()


func _update_variations() -> void:
	var draft: Dictionary = _drafts[_height]
	var by_anchor := {}
	for variant: Dictionary in _draft_variations[_height]:
		var anchor := -1
		var first := Vector2.INF
		for role: int in variant:
			var position: Vector2 = _slots[role].position
			if position.y < first.y or (position.y == first.y and position.x < first.x):
				anchor = role
				first = position
		anchor = _variation_top(anchor)
		if not by_anchor.has(anchor):
			by_anchor[anchor] = []
		by_anchor[anchor].append(variant)
	for role: int in _slots:
		_slots[role].more.visible = draft.has(role) and by_anchor.has(role)
	for card in _variant_cards.get_children():
		_variant_cards.remove_child(card)
		card.queue_free()
	_variants_panel.visible = draft.has(_expanded_role)
	if not _variants_panel.visible:
		_expanded_role = -1
		_preview_roles.clear()
		return
	var variants: Array = by_anchor.get(_expanded_role, [])
	if not variants.is_empty():
		var roles := {}
		for variant: Dictionary in variants:
			for role: int in variant:
				roles[role] = true
		_preview_roles = roles.keys()
	# Retain the preview footprint when the last variation is removed.
	var base := {_expanded_role: draft[_expanded_role].tile}
	for role: int in _preview_roles:
		if draft.has(role):
			base[role] = draft[role].tile
	var base_height := _add_variant_card("Base", base)
	_add_variant_divider(false)
	if variants.is_empty():
		_add_empty_variant_card(base_height)
		return
	for index in variants.size():
		if index > 0:
			_add_variant_divider(true)
		_add_variant_card("V%d" % (index + 1), variants[index], true)


func _add_variant_card(title: String, tiles: Dictionary, removable: bool = false) -> float:
	var card := VBoxContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	if removable:
		card.tooltip_text = "Right-click to remove this variation."
		card.gui_input.connect(_remove_variation_on_click.bind(card, tiles))
	_variant_cards.add_child(card)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(canvas)
	var start := Vector2.INF
	var end := Vector2.ZERO
	for role: int in tiles:
		var position: Vector2 = _slots[role].position
		start = start.min(position)
		end = end.max(position)
	canvas.custom_minimum_size = end - start + Vector2.ONE * SLOT_SIZE
	for role: int in tiles:
		var preview := _tile_preview()
		preview.texture = _tile_thumbnail(_draft_source(), tiles[role])
		preview.position = _slots[role].position - start
		canvas.add_child(preview)
	return canvas.custom_minimum_size.y


func _add_variant_divider(dotted: bool) -> void:
	var divider := VariantDivider.new()
	divider.dotted = dotted
	divider.custom_minimum_size.x = 1.0 if dotted else 8.0
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_variant_cards.add_child(divider)


func _add_empty_variant_card(height: float) -> void:
	var card := VBoxContainer.new()
	_variant_cards.add_child(card)
	var label := Label.new()
	label.text = "Variations"
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	card.add_child(label)
	label.custom_minimum_size.y = label.get_combined_minimum_size().y
	label.add_theme_font_size_override("font_size", 11)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var placeholder := ColorRect.new()
	placeholder.color = Color("#404959")
	placeholder.custom_minimum_size = Vector2(SLOT_SIZE, height)
	placeholder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(placeholder)


func _remove_variation_on_click(event: InputEvent, card: Control, tiles: Dictionary) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		card.accept_event()
		var before := _capture_draft()
		_draft_variations[_height].erase(tiles)
		_update_variations()
		_commit_draft_change("Remove variation", before)


func _draft_source() -> TileSet:
	var draft: Dictionary = _drafts[_height]
	return null if draft.is_empty() else draft.values()[0].tileset


func _clear_slots() -> void:
	var before := _capture_draft()
	_drafts[_height].clear()
	_draft_variations[_height].clear()
	_refresh_draft()
	_commit_draft_change("Clear all template tiles", before)


func _refresh_draft() -> void:
	for role: int in _slots:
		_update_slot(role)
	_update_variations()
	_update_save_state()


func _history_key(key: Key, shifted: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.command_or_control_autoremap = true
	event.shift_pressed = shifted
	return event


func _add_history_button(parent: HBoxContainer, title: String, keys: Array[InputEvent], action: Callable) -> Button:
	var shortcut := Shortcut.new()
	shortcut.events = keys
	var button := Button.new()
	button.text = title
	button.shortcut = shortcut
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _capture_draft() -> Dictionary:
	return {"height": _height, "tiles": _drafts[_height].duplicate(true),
		"variations": _draft_variations[_height].duplicate(true)}


func _commit_draft_change(action: String, before: Dictionary) -> void:
	var after := _capture_draft()
	if before == after:
		return
	_draft_history.create_action(action)
	_draft_history.add_do_method(_restore_draft.bind(after))
	_draft_history.add_undo_method(_restore_draft.bind(before))
	_draft_history.commit_action(false)
	_update_history_buttons()


func _restore_draft(state: Dictionary) -> void:
	var height: int = state.height
	_drafts[height] = state.tiles.duplicate(true)
	_draft_variations[height] = state.variations.duplicate(true)
	if height != _height:
		_height_choice.select(height - 2)
		_select_height(height - 2)
	else:
		_sync_draft_source()
		_refresh_draft()


func _undo_draft() -> void:
	_draft_history.undo()
	_update_history_buttons()


func _redo_draft() -> void:
	_draft_history.redo()
	_update_history_buttons()


func _update_history_buttons() -> void:
	_undo_button.disabled = not _draft_history.has_undo()
	_redo_button.disabled = not _draft_history.has_redo()


func _on_configurator_visibility_changed() -> void:
	if _draft_history != null and not _builder.visible:
		_draft_history.clear_history(false)


func _update_save_state() -> void:
	var draft: Dictionary = _drafts[_height]
	var required: Dictionary = store.template(_height, false).get("slots", {})
	var count := draft.size()
	var required_count := 0
	for role in required:
		if draft.has(role):
			required_count += 1
	var optional_total := _slots.size() - required.size()
	_picker.editable = count == 0
	_clear_slots_button.disabled = count == 0
	_builder_status.text = "%d / %d slots filled" % [required_count, required.size()]
	if optional_total > 0:
		_builder_status.text = "%d / %d required · %d / %d optional" % [
			required_count, required.size(), count - required_count, optional_total]
	_builder_status.tooltip_text = ""
	_builder.get_ok_button().disabled = required.is_empty() or required_count != required.size() or _name.text.strip_edges().is_empty()


func _save() -> void:
	var profile: Dictionary
	if _editing_profile.is_empty():
		profile = store.save_new(_name.text, _height, _drafts[_height], _draft_variations[_height])
	else:
		profile = store.save_changes(_editing_profile, _name.text, _height, _drafts[_height], _draft_variations[_height])
	if profile.is_empty():
		_builder_status.text = store.error
		_builder_status.tooltip_text = store.error
		return
	_builder.hide()
	profile_saved.emit(profile.profile_id)
