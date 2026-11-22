@tool
extends Control

const Tiles = preload("generic_tiles.gd")
const NO_TILE := Vector2i(-1, -1)
const MAX_PREVIEW_TILES := 37
const PREVIEW_SIZE := 32.0

signal selection_changed

var zoom := 1.0
var _tileset: TileSet
var _source_id := -1
var _atlas: TileSetAtlasSource
var _selected: Dictionary[Vector2i, int] = {}
var _offset := Vector2.ZERO
var _fitted := true
var _pan_button := MOUSE_BUTTON_NONE


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	tooltip_text = "Ctrl-click to select several tiles. Scroll to zoom. Middle-drag or right-drag to pan."
	resized.connect(_resize_atlas)


func set_atlas(tileset: TileSet, source_id: int) -> void:
	_tileset = tileset
	_source_id = source_id
	_atlas = tileset.get_source(source_id) as TileSetAtlasSource if tileset != null and tileset.has_source(source_id) else null
	_selected.clear()
	_pan_button = MOUSE_BUTTON_NONE
	fit()
	selection_changed.emit()


func texture_size() -> Vector2:
	return _atlas.texture.get_size() if _atlas != null and _atlas.texture != null else Vector2.ZERO


func fit() -> void:
	_fitted = true
	var extent := texture_size()
	zoom = _fit_scale(extent)
	_offset = ((size - extent * zoom) * 0.5).round() if extent != Vector2.ZERO else Vector2.ZERO
	queue_redraw()


func _fit_scale(extent: Vector2) -> float:
	if extent == Vector2.ZERO or size.x <= 0 or size.y <= 0:
		return 1.0
	return minf(size.x / extent.x, size.y / extent.y)


func _resize_atlas() -> void:
	if _fitted:
		fit()


func set_zoom(value: float, pivot: Vector2 = Vector2.INF) -> void:
	if pivot == Vector2.INF:
		pivot = size * 0.5
	var old_zoom := zoom
	var fitted_zoom := _fit_scale(texture_size())
	zoom = clampf(value, minf(0.05, fitted_zoom * 0.25), maxf(6.0, fitted_zoom * 4.0))
	_offset = pivot + (_offset - pivot) * (zoom / old_zoom)
	_fitted = false
	queue_redraw()


func selection_size() -> int:
	return _selected.size()


func selected_alternatives() -> PackedInt32Array:
	var alternatives := PackedInt32Array()
	if _selected.size() == 1:
		var tile: Vector2i = _selected.keys()[0]
		for index in _atlas.get_alternative_tiles_count(tile):
			alternatives.append(_atlas.get_alternative_tile_id(tile, index))
	return alternatives


func current_alternative() -> int:
	return _selected.values()[0] if _selected.size() == 1 else 0


func set_alternative(id: int) -> void:
	if _selected.size() == 1 and id in selected_alternatives():
		_selected[_selected.keys()[0]] = id


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.12, 0.15))
	var extent := texture_size()
	if extent == Vector2.ZERO:
		return
	var display_size := extent * zoom
	draw_texture_rect(_atlas.texture, Rect2(_offset, display_size), false)
	var stride := _atlas.texture_region_size + _atlas.separation
	var margin := Vector2(_atlas.margins) * zoom
	var grid_size := _atlas.get_atlas_grid_size()
	if minf(stride.x * zoom, stride.y * zoom) >= 6:
		var grid_color := Color(0.82, 0.87, 0.92, 0.26)
		for column in grid_size.x + 1:
			var x := margin.x + column * stride.x * zoom
			if x <= display_size.x:
				draw_line(_offset + Vector2(x, margin.y), _offset + Vector2(x, display_size.y), grid_color)
		for row in grid_size.y + 1:
			var y := margin.y + row * stride.y * zoom
			if y <= display_size.y:
				draw_line(_offset + Vector2(margin.x, y), _offset + Vector2(display_size.x, y), grid_color)
	for coords: Vector2i in _selected:
		var rect := _tile_region(coords)
		draw_rect(rect, Color(0.22, 0.65, 1.0, 0.27))
		draw_rect(rect.grow(-0.5), Color(0.48, 0.82, 1.0), false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _pan_button != MOUSE_BUTTON_NONE:
		var mask := 1 << (int(_pan_button) - 1)
		if event.button_mask & mask:
			_offset += event.relative
			_fitted = false
			queue_redraw()
			accept_event()
		else:
			_pan_button = MOUSE_BUTTON_NONE
		return
	if not event is InputEventMouseButton:
		return
	if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		if event.pressed or _pan_button == event.button_index:
			_pan_button = event.button_index if event.pressed else MOUSE_BUTTON_NONE
		accept_event()
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if event.pressed and texture_size() != Vector2.ZERO:
			var factor := 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2
			set_zoom(zoom * factor, event.position)
		accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT or event.pressed:
		return
	var tile := _tile_at(event.position)
	if event.ctrl_pressed or event.meta_pressed:
		if tile == NO_TILE:
			return
		if _selected.has(tile):
			_selected.erase(tile)
		else:
			_selected[tile] = 0
	else:
		var alternative: int = _selected.get(tile, 0)
		_selected.clear()
		if tile != NO_TILE:
			_selected[tile] = alternative
	queue_redraw()
	selection_changed.emit()
	accept_event()


func _get_drag_data(position: Vector2) -> Variant:
	if _pan_button != MOUSE_BUTTON_NONE:
		return null
	var anchor := _tile_at(position)
	if anchor == NO_TILE:
		return null
	if not _selected.has(anchor):
		_selected.clear()
		_selected[anchor] = 0
		queue_redraw()
		selection_changed.emit()
	var tiles := {}
	for coords: Vector2i in _selected:
		tiles[coords - anchor] = Vector4i(_source_id, coords.x, coords.y, _selected[coords])
	var preview := Control.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count := 0
	for offset: Vector2i in tiles:
		if count >= MAX_PREVIEW_TILES:
			break
		var image := TextureRect.new()
		image.texture = Tiles.thumbnail(_tileset, tiles[offset])
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.position = Vector2(offset) * PREVIEW_SIZE
		image.size = Vector2.ONE * PREVIEW_SIZE
		preview.add_child(image)
		count += 1
	set_drag_preview(preview)
	return {"source_view": self, "tileset": _tileset, "tiles": tiles}


func _tile_at(position: Vector2) -> Vector2i:
	if texture_size() == Vector2.ZERO or not Rect2(_offset, texture_size() * zoom).has_point(position):
		return NO_TILE
	var stride := Vector2(_atlas.texture_region_size + _atlas.separation)
	var grid := Vector2i((((position - _offset) / zoom - Vector2(_atlas.margins)) / stride).floor())
	if grid.x < 0 or grid.y < 0 or grid.x >= _atlas.get_atlas_grid_size().x or grid.y >= _atlas.get_atlas_grid_size().y:
		return NO_TILE
	var tile := _atlas.get_tile_at_coords(grid)
	return tile if tile != NO_TILE and _tile_region(tile).has_point(position) else NO_TILE


func _tile_region(coords: Vector2i) -> Rect2:
	var region := _atlas.get_tile_texture_region(coords)
	return Rect2(_offset + Vector2(region.position) * zoom, Vector2(region.size) * zoom)
