@tool
extends RefCounted
## One-time conversion of the supported 2T/3T Automapping dialect.
## This importer is not loaded or used by the painting plugin.

const EMPTY := -1
const IGNORE := -2

var error := ""


func load_profile(height: int, root: String, tileset_file: String, rule_prefix: String) -> Dictionary:
	if height not in [2, 3]:
		return _fail("Only 2T and 3T wall profiles are supported.")
	error = ""
	if tileset_file.is_empty() or rule_prefix.is_empty():
		return _fail("Choose the source TSX and rule filename prefix for this conversion.")
	var tsx_path := root.path_join(tileset_file).simplify_path()
	var tsx := _read_xml(tsx_path)
	if tsx.is_empty():
		return {}
	var attrs: Dictionary = tsx.attrs
	var images := _children(tsx, "image")
	if images.size() != 1:
		return _fail("The profile requires one image atlas.")
	var image_path := tsx_path.get_base_dir().path_join(images[0].attrs.source).simplify_path()
	if not image_path.begins_with("res://"):
		return _fail("The profile image must be inside the Godot project.")
	var profile := {
		"height": height, "columns": int(attrs.get("columns", 0)),
		"tile_count": int(attrs.get("tilecount", 0)),
		"tile_size": Vector2i(int(attrs.get("tilewidth", 0)), int(attrs.get("tileheight", 0))),
		"texture_path": image_path, "wang": {}, "phases": [], "source_root": root, "tile_probabilities": {},
	}
	if profile.columns < 1 or profile.tile_count < 1 or profile.tile_size != Vector2i(32, 32):
		return _fail("Invalid atlas: expected a 32×32 tileset.")
	for tile in _children(tsx, "tile"):
		if tile.attrs.has("probability"):
			profile.tile_probabilities[int(tile.attrs.id)] = float(tile.attrs.probability)
	for sets in _children(tsx, "wangsets"):
		for wang_set in _children(sets, "wangset"):
			if wang_set.attrs.get("type", "") != "corner":
				return _fail("The profile requires a corner Wang set.")
			for tile in _children(wang_set, "wangtile"):
				var values := str(tile.attrs.wangid).split(",")
				profile.wang[int(tile.attrs.tileid)] = [int(values[1]) - 1, int(values[3]) - 1,
					int(values[5]) - 1, int(values[7]) - 1]
	if profile.wang.is_empty():
		return _fail("No corner terrains were found in the TSX.")
	var rules_file := root.path_join("rules.txt")
	if not FileAccess.file_exists(rules_file):
		return _fail("Missing file: " + rules_file)
	for line in FileAccess.get_file_as_string(rules_file).split("\n"):
		var relative := line.strip_edges().replace("\\", "/")
		if not relative.get_file().begins_with(rule_prefix):
			continue
		var phase := _read_phase(root.path_join(relative), tsx_path, profile.tile_count)
		if phase.is_empty():
			return {}
		profile.phases.append(phase)
	if profile.phases.size() != 3:
		return _fail("Expected three ordered phases: reset, assembly and variations.")
	# Only canonical terrain tiles participate in the native terrain brush. Generated
	# wall segments must never become seeds for a new terrain stroke.
	var normalized: Dictionary = {}
	for rule in profile.phases[0].rules:
		if rule.inputs.size() == 1 and rule.outputs.size() == 1:
			normalized[rule.inputs[0].z] = rule.outputs[0].z
	profile["base_wang"] = {}
	for tile_id in profile.wang:
		if not normalized.has(tile_id) or normalized[tile_id] == tile_id:
			profile.base_wang[tile_id] = profile.wang[tile_id]
	return profile


func _read_phase(path: String, tsx_path: String, tile_count: int) -> Dictionary:
	var doc := _read_xml(path)
	if doc.is_empty():
		return {}
	var width := int(doc.attrs.get("width", 0))
	var height := int(doc.attrs.get("height", 0))
	if width < 1 or height < 1 or doc.attrs.get("infinite", "0") != "0":
		return _fail("Invalid rule map: " + path)
	var sets := _children(doc, "tileset")
	var input: Dictionary = {}
	var output: Dictionary = {}
	var occupied: Dictionary = {}
	for layer in _children(doc, "layer"):
		var layer_name := str(layer.attrs.get("name", ""))
		if layer_name not in ["input_walls", "output_walls"]:
			return _fail("Unsupported layer: " + layer_name)
		if not _properties(layer).is_empty():
			return _fail("Unsupported layer properties: " + path)
		var data := _children(layer, "data")
		if data.size() != 1 or data[0].attrs.get("encoding", "") != "csv":
			return _fail("Rules must use CSV tile data: " + path)
		var values := str(data[0].text).strip_edges().split(",", false)
		if values.size() != width * height:
			return _fail("Invalid cell count: " + path)
		for i in values.size():
			var gid := int(values[i].strip_edges())
			if gid == 0:
				continue
			var value := _decode_gid(gid, sets, path, tsx_path, tile_count)
			if not error.is_empty():
				return {}
			var pos := Vector2i(i % width, i / width)
			occupied[pos] = true
			if layer_name == "input_walls":
				input[pos] = value
			else:
				output[pos] = value
	var map_props := _properties(doc)
	for key in map_props:
		if key != "MatchInOrder":
			return _fail("Unsupported map property: " + str(key))
	var regions: Array = []
	while not occupied.is_empty():
		var todo: Array = [occupied.keys()[0]]
		occupied.erase(todo[0])
		var cells: Array[Vector2i] = []
		while not todo.is_empty():
			var current: Vector2i = todo.pop_back()
			cells.append(current)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var neighbor := current + Vector2i(dx, dy)
					if occupied.erase(neighbor):
						todo.append(neighbor)
		var min_pos := cells[0]
		var max_pos := cells[0]
		for pos in cells:
			min_pos = min_pos.min(pos)
			max_pos = max_pos.max(pos)
		var bounds := Rect2i(min_pos, max_pos - min_pos + Vector2i.ONE)
		var rule := {"origin": bounds.position, "inputs": [], "outputs": [],
			"probability": 1.0, "disabled": false, "id": path.get_file() + ":" + str(bounds.position)}
		for pos in cells:
			var offset: Vector2i = pos - bounds.position
			if input.has(pos) and input[pos] != IGNORE:
				rule.inputs.append(Vector3i(offset.x, offset.y, input[pos]))
			if output.has(pos) and output[pos] != IGNORE:
				rule.outputs.append(Vector3i(offset.x, offset.y, output[pos]))
		for group in _children(doc, "objectgroup"):
			if group.attrs.get("name", "") != "rule_options":
				return _fail("Unsupported object group: " + path)
			for object in _children(group, "object"):
				var a: Dictionary = object.attrs
				# Tiled aligns rectangle option areas outwards to tile boundaries.
				var start := Vector2i(floori(float(a.get("x", 0)) / 32.0), floori(float(a.get("y", 0)) / 32.0))
				var end := Vector2i(ceili((float(a.get("x", 0)) + float(a.get("width", 0))) / 32.0),
					ceili((float(a.get("y", 0)) + float(a.get("height", 0))) / 32.0))
				if Rect2i(start, end - start).encloses(bounds):
					var options := _properties(object)
					for key in options:
						if key not in ["Probability", "Disabled"]:
							return _fail("Unsupported rule option: " + str(key))
					rule.probability = float(options.get("Probability", rule.probability))
					rule.disabled = bool(options.get("Disabled", rule.disabled))
		if rule.inputs.is_empty():
			return _fail("Rule without conditions: " + path)
		regions.append(rule)
	regions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.origin.y < b.origin.y or (a.origin.y == b.origin.y and a.origin.x < b.origin.x))
	return {"name": path.get_file(), "rules": regions, "match_in_order": bool(map_props.get("MatchInOrder", false))}


func _decode_gid(gid: int, sets: Array, map_path: String, tsx_path: String, tile_count: int) -> int:
	if gid & 0xf0000000:
		_fail("Tile transforms are not supported in these rules: " + map_path)
		return EMPTY
	var selected: Dictionary = {}
	for entry in sets:
		if int(entry.attrs.firstgid) <= gid and (selected.is_empty() or int(entry.attrs.firstgid) > int(selected.attrs.firstgid)):
			selected = entry
	if selected.is_empty():
		_fail("GID without a tileset: " + str(gid))
		return EMPTY
	var local_id := gid - int(selected.attrs.firstgid)
	var source := str(selected.attrs.source)
	if source == ":/automap-tiles.tsx":
		# IDs in Tiled's built-in Automapping Rules Tileset (verified against Tiled).
		if local_id == 3:
			return EMPTY
		_fail("Unsupported special marker: " + str(local_id))
		return EMPTY
	if map_path.get_base_dir().path_join(source).simplify_path() != tsx_path.simplify_path() or local_id >= tile_count:
		_fail("The rule references a different atlas: " + source)
		return EMPTY
	return local_id


func _read_xml(path: String) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open(path) != OK:
		return _fail("Could not read: " + path)
	var stack: Array = []
	var root: Dictionary = {}
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node := {"name": parser.get_node_name(), "attrs": {}, "children": [], "text": ""}
				for i in parser.get_attribute_count():
					node.attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
				if stack.is_empty():
					root = node
				else:
					stack[-1].children.append(node)
				if not parser.is_empty():
					stack.append(node)
			XMLParser.NODE_ELEMENT_END:
				if not stack.is_empty():
					stack.pop_back()
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				if not stack.is_empty():
					stack[-1].text += parser.get_node_data()
	return root


func _children(node: Dictionary, tag: String) -> Array:
	return node.get("children", []).filter(func(child: Dictionary) -> bool: return child.name == tag)


func _properties(node: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for group in _children(node, "properties"):
		for property in _children(group, "property"):
			var value: Variant = property.attrs.get("value", property.text)
			match property.attrs.get("type", "string"):
				"bool": value = str(value) == "true"
				"float": value = float(value)
				"int": value = int(value)
			result[property.attrs.name] = value
	return result


func _fail(message: String) -> Dictionary:
	error = message
	return {}

