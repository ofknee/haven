@tool
extends RefCounted
## Native references are (source ID, atlas X, atlas Y, alternative ID).

static func atlas_for(tileset: TileSet, tile: Vector4i) -> TileSetAtlasSource:
	if tileset == null or not tileset.has_source(tile.x):
		return null
	return tileset.get_source(tile.x) as TileSetAtlasSource


static func tile_data(tileset: TileSet, tile: Vector4i) -> TileData:
	var atlas := atlas_for(tileset, tile)
	var coords := Vector2i(tile.y, tile.z)
	if atlas == null or atlas.texture == null or not atlas.has_tile(coords) or not atlas.has_alternative_tile(coords, tile.w):
		return null
	return atlas.get_tile_data(coords, tile.w)


static func has_tile(tileset: TileSet, tile: Vector4i) -> bool:
	if tileset == null or not tileset.has_source(tile.x):
		return false
	var scenes := tileset.get_source(tile.x) as TileSetScenesCollectionSource
	if scenes != null:
		return Vector2i(tile.y, tile.z) == Vector2i.ZERO and scenes.has_scene_tile_id(tile.w) and scenes.get_scene_tile_scene(tile.w) != null
	return tile_data(tileset, tile) != null


static func thumbnail(tileset: TileSet, tile: Vector4i) -> Texture2D:
	var data := tile_data(tileset, tile)
	if data == null:
		return null
	var atlas := atlas_for(tileset, tile)
	var region := atlas.get_tile_texture_region(Vector2i(tile.y, tile.z))
	if data.transpose or data.flip_h or data.flip_v:
		var texture_image := atlas.texture.get_image()
		if texture_image != null:
			var transformed := texture_image.get_region(region)
			if data.transpose:
				transformed.rotate_90(CLOCKWISE)
				transformed.flip_x()
			if data.flip_h:
				transformed.flip_x()
			if data.flip_v:
				transformed.flip_y()
			return ImageTexture.create_from_image(transformed)
	var image := AtlasTexture.new()
	image.atlas = atlas.texture
	image.region = region
	image.filter_clip = true
	return image
