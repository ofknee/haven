@tool
extends RefCounted

const Tiles = preload("generic_tiles.gd")
const Variations = preload("generic_variations.gd")
const DIRECTORY := "res://addons/erw_walls_autotile/generic_profiles"
const TEMPLATE_PATH := "res://addons/erw_walls_autotile/generic_templates.cfg"
const FORMAT_VERSION := 1

var error := ""
var _templates := ConfigFile.new()
var _expanded_3t: Dictionary


func _init() -> void:
	_templates.load(TEMPLATE_PATH)
	var base := template(3, false)
	_expanded_3t = base.duplicate(true)
	if not base.is_empty():
		_expanded_3t.slots.merge(base.get("join_slots", {}))


func template(height: int, include_joins: bool = true) -> Dictionary:
	if height == 3 and include_joins:
		return _expanded_3t
	return _templates.get_value("walls_%dt" % height, "data", {})


func _template_for_saved_profile(profile: Dictionary) -> Dictionary:
	var data := template(profile.height)
	if not data.has("join_rules"):
		return data
	var rules: Array = data.assembly.rules.duplicate()
	for rule: Dictionary in data.join_rules:
		var mapped := true
		for output: Vector3i in rule.outputs:
			if not profile.tiles.has(output.z):
				mapped = false
				break
		if mapped:
			rules.append(rule)
	var bound := data.duplicate()
	bound.assembly = data.assembly.duplicate()
	bound.assembly.rules = rules
	return bound


func load_profiles() -> Dictionary:
	var profiles := {}
	if not DirAccess.dir_exists_absolute(DIRECTORY):
		return profiles
	for filename in DirAccess.get_files_at(DIRECTORY):
		if filename.get_extension() != "cfg":
			continue
		var profile := _read_profile(filename)
		if not profile.is_empty():
			profiles[profile.profile_id] = profile
	return profiles


func _read_profile(filename: String) -> Dictionary:
	var file := ConfigFile.new()
	if file.load(DIRECTORY.path_join(filename)) != OK or file.get_value("profile", "version", 0) != FORMAT_VERSION:
		return {}
	var value: Variant = file.get_value("profile", "data", {})
	if value is Dictionary and _valid_profile(value) and filename.get_basename() == value.profile_id.get_file():
		return value
	return {}


func save_new(display_name: String, height: int, assignments: Dictionary, variations: Array = []) -> Dictionary:
	return _save_profile({}, display_name, height, assignments, variations)


func save_changes(original: Dictionary, display_name: String, height: int, assignments: Dictionary, variations: Array) -> Dictionary:
	var filename := str(original.profile_id).get_file() + ".cfg"
	if _read_profile(filename) != original:
		error = "This profile changed on disk. Reopen it before saving."
		return {}
	return _save_profile(original, display_name, height, assignments, variations)


func delete_profile(original: Dictionary) -> bool:
	error = ""
	var filename := str(original.profile_id).get_file() + ".cfg"
	if _read_profile(filename) != original:
		error = "This profile changed on disk. Select it again before deleting."
		return false
	var result := DirAccess.remove_absolute(DIRECTORY.path_join(filename))
	if result != OK:
		error = "Could not delete the profile. " + error_string(result)
		return false
	return true


func _save_profile(original: Dictionary, display_name: String, height: int, assignments: Dictionary, variations: Array) -> Dictionary:
	error = ""
	var slots: Dictionary = template(height).get("slots", {})
	var required: Dictionary = template(height, false).get("slots", {})
	if display_name.strip_edges().is_empty() or required.is_empty() or not assignments.has_all(required.keys()):
		error = "Enter a name and fill every required template slot."
		return {}
	var source: TileSet
	var references := {}
	for role in assignments:
		if not slots.has(role):
			error = "An assignment does not match the template."
			return {}
		var assignment: Dictionary = assignments.get(role, {})
		var tileset: TileSet = assignment.get("tileset")
		var tile: Vector4i = assignment.get("tile", Vector4i(-1, -1, -1, -1))
		if not Tiles.has_tile(tileset, tile):
			error = "A slot refers to a tile that is no longer available."
			return {}
		if source != null and source != tileset:
			error = "All slots in a profile must use the same source TileSet."
			return {}
		source = tileset
		references[role] = tile
	if not _valid_variations(variations, references):
		error = "A tile variation does not match the template."
		return {}
	for variant: Dictionary in variations:
		for tile: Vector4i in variant.values():
			if not Tiles.has_tile(source, tile):
				error = "A variation contains a tile that is no longer available."
				return {}
	if source.tile_shape != TileSet.TILE_SHAPE_SQUARE:
		error = "Choose a source TileSet with a square grid."
		return {}
	var path := source.resource_path
	if not _is_saved_tileset(path):
		error = "Save the source TileSet as a .tres or .res resource first."
		return {}
	var result := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if result != OK:
		error = "Could not create the profile folder. " + error_string(result)
		return {}
	var uid := ResourceLoader.get_resource_uid(path)
	var profile := original.duplicate(true)
	if profile.is_empty():
		profile["profile_id"] = "generic/" + Crypto.new().generate_random_bytes(12).hex_encode()
	profile.merge({"display_name": display_name.strip_edges(), "height": height,
		"tileset_path": path, "tileset_uid": ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else "",
		"tiles": references, "variations": variations.duplicate(true)}, true)
	if not _write_profile(profile):
		return {}
	return profile


func _resolve_tileset_path(saved: Dictionary) -> String:
	var path: String = saved.tileset_path
	var uid := ResourceUID.text_to_id(str(saved.get("tileset_uid", "")))
	if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
		var moved := ResourceUID.get_id_path(uid)
		if _is_saved_tileset(moved):
			return moved
	return path if _is_saved_tileset(path) else ""


func load_profile_tileset(saved: Dictionary) -> TileSet:
	error = ""
	var path := _resolve_tileset_path(saved)
	var tileset := load(path) as TileSet if not path.is_empty() else null
	if tileset == null:
		error = "The TileSet for this profile is unavailable."
	return tileset


func bind_profile(saved: Dictionary, current: TileSet = null, allow_replacement: bool = false) -> Dictionary:
	error = ""
	var path := _resolve_tileset_path(saved)
	if path.is_empty():
		error = "The TileSet for this profile is unavailable."
		return {}
	var tileset := current
	if tileset == null or tileset.resource_path != path:
		if not allow_replacement:
			error = "Select a TileMapLayer with %s." % path.get_file()
			return {}
		tileset = load(path) as TileSet
	if tileset == null or tileset.tile_shape != TileSet.TILE_SHAPE_SQUARE:
		error = "This profile needs a square-grid TileSet."
		return {}
	var probabilities := {}
	for role in saved.tiles:
		var tile: Vector4i = saved.tiles[role]
		if not Tiles.has_tile(tileset, tile):
			error = "This profile contains a tile that is no longer in the TileSet."
			return {}
		var data := Tiles.tile_data(tileset, tile)
		probabilities[role] = data.probability if data != null else 1.0
	for variant: Dictionary in saved.get("variations", []):
		for tile: Vector4i in variant.values():
			if not Tiles.has_tile(tileset, tile):
				error = "A variation contains a tile that is no longer in the TileSet."
				return {}
	var profile := saved.duplicate(true)
	profile["generic"] = true
	profile["tileset"] = tileset
	profile["tile_size"] = tileset.tile_size
	profile["template"] = _template_for_saved_profile(saved)
	profile["tile_probabilities"] = probabilities
	profile["variation_groups"] = Variations.compile(saved, profile.template, tileset)
	return profile


func _write_profile(profile: Dictionary) -> bool:
	if not _valid_profile(profile):
		error = "The profile is incomplete."
		return false
	var path := DIRECTORY.path_join(str(profile.profile_id).get_file() + ".cfg")
	var temporary := path + ".tmp"
	var file := ConfigFile.new()
	file.set_value("profile", "version", FORMAT_VERSION)
	file.set_value("profile", "data", profile)
	var result := file.save(temporary)
	if result == OK:
		result = DirAccess.rename_absolute(temporary, path)
	if result != OK:
		DirAccess.remove_absolute(temporary)
		error = "Could not save the profile. " + error_string(result)
		return false
	return true


func _valid_profile(profile: Dictionary) -> bool:
	if not profile.get("profile_id") is String or not profile.profile_id.begins_with("generic/") or profile.profile_id.get_file().length() != 24:
		return false
	if not profile.get("display_name") is String or profile.display_name.is_empty() or not profile.get("tileset_path") is String:
		return false
	if profile.get("height", 0) not in [2, 3] or not profile.get("tiles") is Dictionary:
		return false
	var slots: Dictionary = template(profile.height).get("slots", {})
	var required: Dictionary = template(profile.height, false).get("slots", {})
	if required.is_empty() or not profile.tiles.has_all(required.keys()):
		return false
	for role in profile.tiles:
		if not slots.has(role) or not profile.tiles[role] is Vector4i:
			return false
	return _valid_variations(profile.get("variations", []), profile.tiles)


func _valid_variations(variants: Variant, references: Dictionary) -> bool:
	if not variants is Array:
		return false
	for variant in variants:
		if not variant is Dictionary or variant.is_empty():
			return false
		for role in variant:
			if not references.has(role) or not variant[role] is Vector4i:
				return false
	return true


func _is_saved_tileset(path: String) -> bool:
	return path.begins_with("res://") and not path.contains("::") and path.get_extension() in ["tres", "res"] and FileAccess.file_exists(path)
