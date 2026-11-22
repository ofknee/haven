@tool
extends RefCounted
## Converted wall rules are native Variant data, with soft references to asset files.

const PROFILE_DIRECTORY := "res://addons/erw_walls_autotile/profiles"
const FORMAT_VERSION := 1


func save_imported(profile: Dictionary, tileset: TileSet, asset_name: String,
		profile_id: String, destination: String, legacy_settings_key: String = "") -> Error:
	if profile.is_empty() or tileset == null or tileset.resource_path.is_empty() or profile_id.is_empty():
		return ERR_INVALID_PARAMETER
	var converted := profile.duplicate(true)
	converted.erase("source_root")
	converted.erase("wang")
	converted.erase("tile_probabilities")
	converted["profile_id"] = profile_id
	converted["asset_name"] = asset_name
	converted["display_name"] = "%s · Walls %dT" % [asset_name, int(profile.height)]
	converted["tileset_path"] = tileset.resource_path
	converted["tileset_uid"] = _uid_for(tileset.resource_path)
	converted["texture_uid"] = _uid_for(str(profile.texture_path))
	if not legacy_settings_key.is_empty():
		converted["legacy_settings_key"] = legacy_settings_key
	var file := ConfigFile.new()
	file.set_value("wall_profile", "version", FORMAT_VERSION)
	file.set_value("wall_profile", "data", converted)
	return file.save(destination)


func load_available(directory: String = PROFILE_DIRECTORY) -> Dictionary:
	var result: Dictionary = {}
	for filename in DirAccess.get_files_at(directory):
		if filename.get_extension() != "cfg":
			continue
		var file := ConfigFile.new()
		if file.load(directory.path_join(filename)) != OK:
			continue
		if file.get_value("wall_profile", "version", 0) != FORMAT_VERSION:
			continue
		var value: Variant = file.get_value("wall_profile", "data", {})
		if not value is Dictionary or not _valid_data(value):
			continue
		var profile: Dictionary = value.duplicate(true)
		if not resolve_assets(profile):
			continue
		if not result.has(profile.profile_id):
			result[profile.profile_id] = profile
	return result


func resolve_assets(profile: Dictionary) -> bool:
	# Check both soft references before loading a TileSet. Missing assets are normal.
	var tileset_path := _existing_path(str(profile.get("tileset_path", "")), str(profile.get("tileset_uid", "")))
	var texture_path := _existing_path(str(profile.get("texture_path", "")), str(profile.get("texture_uid", "")))
	if tileset_path.is_empty() or texture_path.is_empty():
		return false
	profile["tileset_path"] = tileset_path
	profile["texture_path"] = texture_path
	return true


func load_tileset(profile: Dictionary) -> TileSet:
	if not resolve_assets(profile):
		return null
	return load(str(profile.tileset_path)) as TileSet


func _existing_path(path: String, uid_text: String) -> String:
	if not uid_text.is_empty():
		var uid := ResourceUID.text_to_id(uid_text)
		if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
			var current := ResourceUID.get_id_path(uid)
			if current.begins_with("res://") and FileAccess.file_exists(current):
				return current
	return path if path.begins_with("res://") and FileAccess.file_exists(path) else ""


func _uid_for(path: String) -> String:
	var uid := ResourceLoader.get_resource_uid(path)
	return ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else ""


func _valid_data(profile: Dictionary) -> bool:
	if str(profile.get("profile_id", "")).is_empty() or str(profile.get("display_name", "")).is_empty():
		return false
	if profile.get("height", 0) not in [2, 3]:
		return false
	if not profile.get("tile_size") is Vector2i or int(profile.get("columns", 0)) < 1:
		return false
	if not profile.get("base_wang") is Dictionary or profile.base_wang.is_empty():
		return false
	var phases: Variant = profile.get("phases")
	if not phases is Array or phases.size() != 3:
		return false
	for phase in phases:
		if not phase is Dictionary or not phase.get("rules") is Array or not phase.get("match_in_order") is bool:
			return false
		for rule in phase.rules:
			if not rule is Dictionary or not rule.get("inputs") is Array or not rule.get("outputs") is Array:
				return false
			if not rule.has_all(["id", "probability", "disabled"]):
				return false
			for cell in rule.inputs + rule.outputs:
				if not cell is Vector3i:
					return false
	return true
