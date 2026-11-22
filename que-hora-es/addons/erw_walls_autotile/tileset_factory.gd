@tool
extends RefCounted
## Binds converted rules to the current native TileSet without changing its data.
var error := ""
const CORNER_BITS := [TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER]


func configure_profile(profile: Dictionary, tileset: TileSet) -> bool:
	error = ""
	if tileset != null and (tileset.tile_shape != TileSet.TILE_SHAPE_SQUARE or tileset.tile_size != profile.tile_size):
		error = "The TileSet's tile shape or size does not match this wall profile."
		return false
	if tileset != null:
		for index in tileset.get_source_count():
			var source_id := tileset.get_source_id(index)
			var atlas := tileset.get_source(source_id) as TileSetAtlasSource
			if atlas == null or atlas.texture == null or atlas.texture.resource_path != str(profile.texture_path):
				continue
			if profile.get("plugin_terrain", false):
				var masks := {}
				var probabilities := {}
				for tile_id: int in profile.base_wang:
					var coords := Vector2i(tile_id % int(profile.columns), tile_id / int(profile.columns))
					if atlas.has_tile(coords):
						masks[tile_id] = profile.base_wang[tile_id]
						probabilities[tile_id] = atlas.get_tile_data(coords, 0).probability
				if masks.is_empty():
					continue
				profile.merge({"source_id": source_id, "terrain_set": 0, "terrain": 0,
					"native_wang": masks, "tile_probabilities": probabilities}, true)
				return true
			for tile_id: int in profile.base_wang:
				var coords := Vector2i(tile_id % int(profile.columns), tile_id / int(profile.columns))
				if not atlas.has_tile(coords):
					continue
				var data := atlas.get_tile_data(coords, 0)
				if data.terrain_set >= 0 and data.terrain >= 0:
					profile["source_id"] = source_id
					profile["terrain_set"] = data.terrain_set
					profile["terrain"] = data.terrain
					# Godot remains authoritative after the initial rule conversion.
					var probabilities: Dictionary = {}
					var native_wang: Dictionary = {}
					for base_id: int in profile.base_wang:
						var base_coords := Vector2i(base_id % int(profile.columns), base_id / int(profile.columns))
						if atlas.has_tile(base_coords):
							var native_data := atlas.get_tile_data(base_coords, 0)
							probabilities[base_id] = native_data.probability
							if native_data.terrain_set != data.terrain_set or native_data.terrain != data.terrain:
								continue
							var mask: Array[int] = []
							for bit in CORNER_BITS:
								mask.append(0 if native_data.get_terrain_peering_bit(bit) == data.terrain else -1)
							native_wang[base_id] = mask
					profile["tile_probabilities"] = probabilities
					profile["native_wang"] = native_wang
					return true
	error = "The selected TileSet is missing the requested wall terrain."
	return false


func scratch_tileset(profile: Dictionary, tileset: TileSet) -> TileSet:
	if not profile.get("plugin_terrain", false):
		return tileset
	# Keep the topology on the profile. The detached terrain solver needs only
	# the base tiles and their current Godot probabilities.
	var original := tileset.get_source(int(profile.source_id)) as TileSetAtlasSource
	var solver_tileset := TileSet.new()
	solver_tileset.tile_size = profile.tile_size
	solver_tileset.add_terrain_set()
	solver_tileset.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	solver_tileset.add_terrain(0)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = original.texture
	atlas.texture_region_size = original.texture_region_size
	atlas.margins = original.margins
	atlas.separation = original.separation
	atlas.use_texture_padding = false
	solver_tileset.add_source(atlas, int(profile.source_id))
	for tile_id: int in profile.native_wang:
		var coords := Vector2i(tile_id % int(profile.columns), tile_id / int(profile.columns))
		atlas.create_tile(coords)
		var data := atlas.get_tile_data(coords, 0)
		data.terrain_set = 0
		data.terrain = 0
		data.probability = profile.tile_probabilities[tile_id]
		for index in CORNER_BITS.size():
			data.set_terrain_peering_bit(CORNER_BITS[index], profile.native_wang[tile_id][index])
	return solver_tileset


func read_cells(layer: TileMapLayer, columns: int, source_id: int, protected: Dictionary = {}) -> Dictionary:
	var cells: Dictionary = {}
	for pos in layer.get_used_cells():
		if layer.get_cell_source_id(pos) == source_id and not protected.has(pos):
			var coords := layer.get_cell_atlas_coords(pos)
			cells[pos] = coords.y * columns + coords.x
	return cells


func write_cells(layer: TileMapLayer, cells: Dictionary, columns: int, source_id: int, protected: Dictionary = {}) -> void:
	# A wall rebuild must preserve cells belonging to other sources in the asset.
	for pos in layer.get_used_cells():
		if layer.get_cell_source_id(pos) == source_id and not protected.has(pos):
			layer.erase_cell(pos)
	for pos: Vector2i in cells:
		if protected.has(pos):
			continue
		var tile_id := int(cells[pos])
		layer.set_cell(pos, source_id, Vector2i(tile_id % columns, tile_id / columns))
